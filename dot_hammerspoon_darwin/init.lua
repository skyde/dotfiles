-- init.lua

-- Bind Shift+F9 → Cmd+Space
hs.hotkey.bind({ "shift" }, "f9", function()
	-- send Cmd+Space to open Spotlight
	hs.eventtap.keyStroke({ "cmd" }, "space", 0)
end)
