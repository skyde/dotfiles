-- mini-files-arrows.lua
-- Add left/right arrow key support to mini.files navigation.
--
-- Registered from `init`, not `config`: a child spec's `config` replaces the
-- parent's, and LazyVim's mini-files extra is what calls MiniFiles.setup()
-- (plus the dotfile toggle and rename-on-move integration). The autocmd does
-- not need the plugin loaded, so `init` adds the keys without discarding any
-- of that.

return {
  "nvim-mini/mini.files",
  init = function()
    vim.api.nvim_create_autocmd("User", {
      pattern = "MiniFilesBufferCreate",
      callback = function(args)
        local MiniFiles = require("mini.files")
        local buf_id = args.data.buf_id
        -- Left arrow: go to parent directory (same as 'h')
        vim.keymap.set("n", "<Left>", function()
          MiniFiles.go_out()
        end, { buffer = buf_id, desc = "MiniFiles: Go left (parent dir)" })
        -- Right arrow: open directory or file (same as 'l' or 'j')
        vim.keymap.set("n", "<Right>", function()
          MiniFiles.go_in()
        end, { buffer = buf_id, desc = "MiniFiles: Go right (open)" })
      end,
    })
  end,
}
