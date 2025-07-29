-- init.lua


-- Open Spotlight when Cmd is tapped without other keys
local cmdPressed = false
local otherKeyPressed = false
local cmdDownTime = 0
local cmdThreshold = 0.15
local cmdReleaseDelay = 0.05

local keyDownListener = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(_)
    if cmdPressed then
        otherKeyPressed = true
    end
    return false
end)

local flagsListener = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(evt)
    local flags = evt:getFlags()

    if flags.cmd and not cmdPressed then
        cmdPressed = true
        otherKeyPressed = false
        cmdDownTime = hs.timer.secondsSinceEpoch()
    elseif not flags.cmd and cmdPressed then
        cmdPressed = false
        local elapsed = hs.timer.secondsSinceEpoch() - cmdDownTime
        if not otherKeyPressed and elapsed < cmdThreshold then
            hs.timer.doAfter(cmdReleaseDelay, function()
                if not cmdPressed and not otherKeyPressed then
                    hs.eventtap.keyStroke({ "cmd" }, "space", 0)
                end
            end)
        end
    elseif cmdPressed and (flags.alt or flags.shift or flags.ctrl or flags.fn) then
        otherKeyPressed = true
    end
end)

-- Helper to determine if a device is an external keyboard
local function isExternalKeyboard(dev)
    local name = string.lower(dev.productName or "")
    return name:find("keyboard") and
        name ~= string.lower("Apple Internal Keyboard / Trackpad")
end

-- Check if any external keyboard is currently connected
local function externalKeyboardPresent()
    local devices = hs.usb.attachedDevices() or {}
    for _, dev in ipairs(devices) do
        if isExternalKeyboard(dev) then
            return true
        end
    end
    return false
end

-- Start or stop listeners based on external keyboard presence
local function updateListeners()
    if externalKeyboardPresent() then
        if not keyDownListener:isEnabled() then
            keyDownListener:start()
            flagsListener:start()
        end
    else
        if keyDownListener:isEnabled() then
            keyDownListener:stop()
            flagsListener:stop()
        end
    end
end

-- Watch for USB device changes to refresh listener status
hs.usb.watcher.new(function(info)
    if isExternalKeyboard(info) then
        hs.timer.doAfter(0.5, updateListeners)
    end
end):start()

-- Activate listeners if an external keyboard is already connected
updateListeners()
