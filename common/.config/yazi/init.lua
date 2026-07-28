-- require("git"):setup()
-- Preload the bounded text previewer so Yazi knows its peek function is
-- synchronous before the first cursor move.
require("sync-text-preview")
require("relative-line-numbers"):setup()

require("zoxide"):setup({
	update_db = true,
})
