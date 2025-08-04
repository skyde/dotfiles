------------------------------------------------------------
--  Cmd‑tap → Spotlight           (external keyboards only)
--  Robust against   • sleep/wake • long uptimes • USB swap
------------------------------------------------------------

--------- tweakables ----------------------------------------------------------
local TAPPING_TERM = 0.18 -- max seconds Cmd can be held and still count as “tap”
local RELEASE_DELAY = 0.06 -- let macOS finish key‑up animation before Spotlight
local STALE_FOR = 10 -- restart tap if no event for this many seconds
-------------------------------------------------------------------------------

-- internal “don’t touch while running” state
local cmdDownAt, sawOtherKey, lastEventAt = nil, false, hs.timer.secondsSinceEpoch()
local tap -- will hold the current hs.eventtap
local usbWatcher, caffeineWatcher, dog -- helper watchers

--------------------------------------------------------------------- utilities
local function now()
	return hs.timer.secondsSinceEpoch()
end

local function isExternalKeyboard(dev)
	local name = (dev.productName or ""):lower()
	return name:find("keyboard") and name ~= "apple internal keyboard / trackpad"
end

local function externalKeyboardPresent()
	for _, d in ipairs(hs.usb.attachedDevices() or {}) do
		if isExternalKeyboard(d) then
			return true
		end
	end
	return false
end

------------------------------------------------------------------ spotlight FX
local function triggerSpotlight()
	hs.eventtap.keyStroke({ "cmd" }, "space", 0) -- works even if user remapped glob‑ally
end

-------------------------------------------------------------- tap event logic
local function handle(evt)
	local t = evt:getType()
	local flags = evt:getFlags()
	lastEventAt = now() -- heartbeat for watchdog

	-- start of Cmd press --------------------------------------------------------
	if t == hs.eventtap.event.types.flagsChanged and flags.cmd and not cmdDownAt then
		cmdDownAt = now()
		sawOtherKey = false
		return false
	end

	-- any other key/mod while Cmd is down? -------------------------------------
	if cmdDownAt and t == hs.eventtap.event.types.keyDown then
		sawOtherKey = true
		return false
	end
	if cmdDownAt and (flags.alt or flags.shift or flags.ctrl or flags.fn) then
		sawOtherKey = true
	end

	-- Cmd released -------------------------------------------------------------
	if t == hs.eventtap.event.types.flagsChanged and not flags.cmd and cmdDownAt then
		local pressDuration = now() - cmdDownAt
		cmdDownAt = nil

		if not sawOtherKey and pressDuration < TAPPING_TERM then
			hs.timer.doAfter(RELEASE_DELAY, function()
				if not cmdDownAt then
					triggerSpotlight()
				end
			end)
		end
	end
	return false -- never swallow the event, just observe
end

-------------------------------------------------------- tap (re)construction
local function buildTap()
	if tap then
		tap:stop()
	end -- kill previous instance (if any)
	tap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown }, handle)
	tap:start()
end

------------------------------------------------------------- public bootstrap
local function ensureRunning()
	if externalKeyboardPresent() then
		buildTap()
	else
		if tap then
			tap:stop()
		end
	end
end

-- USB hot‑plug watcher --------------------------------------------------------
usbWatcher = hs.usb.watcher
	.new(function(info)
		if isExternalKeyboard(info) then
			hs.timer.doAfter(0.3, ensureRunning)
		end
	end)
	:start()

-- sleep / wake / unlock watcher ---------------------------------------------
caffeineWatcher = hs.caffeinate.watcher
	.new(function(e)
		if e == hs.caffeinate.watcher.systemWillSleep then
			if tap then
				tap:stop()
			end
		elseif e == hs.caffeinate.watcher.systemDidWake or e == hs.caffeinate.watcher.screensDidUnlock then
			hs.timer.doAfter(1, ensureRunning)
		end
	end)
	:start()

-- watchdog – heal macOS dropping the event‑tap -------------------------------
dog = hs.timer.doEvery(5, function()
	if tap and (now() - lastEventAt) > STALE_FOR then
		buildTap()
	end
end)

-- initial activation ---------------------------------------------------------
ensureRunning()
