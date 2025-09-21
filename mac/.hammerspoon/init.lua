--------------------------------------------------------------------------------
-- Spotlight‑on‑Cmd‑tap  •  zero cached device state
--  – One always‑running event‑tap
--  – No USB or caffeinate watchers
--  – Device presence checked exactly when a decision is needed
--------------------------------------------------------------------------------

---------------------------  Constants  ----------------------------------------
local INTERNAL_KB_NAME = "Apple Internal Keyboard / Trackpad"
local CMD_TAP_THRESHOLD = 0.15 -- seconds a press counts as a tap
local CMD_RELEASE_DELAY = 0.05 -- let other modifiers settle first
--------------------------------------------------------------------------------

------------------------  Device‑query helper  ---------------------------------
local function externalKeyboardPresent()
	for _, dev in ipairs(hs.usb.attachedDevices() or {}) do
		local name = string.lower(dev.productName or "")
		if name:find("keyboard") and name ~= string.lower(INTERNAL_KB_NAME) then
			return true
		end
	end
	return false
end
--------------------------------------------------------------------------------

---------------------------  Gesture state  ------------------------------------
local cmdDown = false -- Cmd currently held?
local otherKeyDuringCmd = false -- any non‑modifier key pressed while Cmd down?
local cmdDownStart = 0 -- epoch seconds when Cmd went down
--------------------------------------------------------------------------------

---------------------------  Single event‑tap  ---------------------------------
local types = { hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown }

local tap = hs.eventtap
	.new(types, function(evt)
		local t = evt:getType()

		---------------------------------------------------------
		-- Record any ordinary key‑down while Cmd is held
		---------------------------------------------------------
		if t == hs.eventtap.event.types.keyDown then
			if cmdDown then
				otherKeyDuringCmd = true
			end
			return false
		end

		---------------------------------------------------------
		-- Track Cmd going up/down
		---------------------------------------------------------
		local flags = evt:getFlags()

		if flags.cmd and not cmdDown then
			--------------------------------- Cmd just went down
			cmdDown = true
			otherKeyDuringCmd = false
			cmdDownStart = hs.timer.secondsSinceEpoch()
		elseif not flags.cmd and cmdDown then
			--------------------------------- Cmd just released
			cmdDown = false
			local elapsed = hs.timer.secondsSinceEpoch() - cmdDownStart

			if not otherKeyDuringCmd and elapsed < CMD_TAP_THRESHOLD and externalKeyboardPresent() then -- <-- live query #1
				hs.timer.doAfter(CMD_RELEASE_DELAY, function()
					if not cmdDown and not otherKeyDuringCmd and externalKeyboardPresent() then -- <-- live query #2
						hs.eventtap.keyStroke({ "cmd" }, "space", 0)
					end
				end)
			end
		elseif cmdDown and (flags.alt or flags.shift or flags.ctrl or flags.fn) then
			-----------------------------------------------------
			-- A modifier combination (e.g. Cmd‑Shift) was used
			-----------------------------------------------------
			otherKeyDuringCmd = true
		end

		return false -- observe only; never consume the event
	end)
	:start()
--------------------------------------------------------------------------------

-- Keep a strong reference so Lua’s GC never collects the tap
_G.__spotlightTap_noCache = tap

--------------------------------------------------------------------------------
-- Custom binding to map shift f9 (bound to a macro) to backslash - this is for ease of use as the macro is currently no used for anything else

hs.hotkey.bind({ "shift" }, "f9", function()
	hs.eventtap.event.newKeyEvent("\\", true):post() -- key down \
end, function()
	hs.eventtap.event.newKeyEvent("\\", false):post() -- key up \
end)
