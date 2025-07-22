-- init.lua


-- Open Spotlight when Cmd is tapped without other keys
local cmdPressed = false
local otherKeyPressed = false
local cmdDownTime = 0

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
        if not otherKeyPressed and hs.timer.secondsSinceEpoch() - cmdDownTime < 0.2 then
            hs.eventtap.keyStroke({ "cmd" }, "space", 0)
        end
    elseif cmdPressed and (flags.alt or flags.shift or flags.ctrl or flags.fn) then
        otherKeyPressed = true
    end
end)

keyDownListener:start()
flagsListener:start()
