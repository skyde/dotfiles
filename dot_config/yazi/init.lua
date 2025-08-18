-- require("git"):setup()

-- NOTE: The relative-line-numbers plugin patches Yazi's redraw logic.  When it
-- runs too early (before the UI is fully initialized) Yazi can start up with a
-- blank or partially rendered screen.  Deferring the setup to the main event
-- loop ensures the UI is ready before we hook into it, avoiding the black
-- screen on launch.
ya.sync(function()
  require("relative-line-numbers"):setup()
end)
