-- Gutter change indicators.
--
-- options.lua turns the sign column off, so the usual gitsigns marks have
-- nowhere to draw. Colouring the line *number* instead gives the same
-- at-a-glance "this line changed" cue VS Code shows in its gutter, without
-- giving up the column.

return {
  "lewis6991/gitsigns.nvim",
  opts = {
    signcolumn = false,
    numhl = true,
    -- Only worth the redraw cost on demand; `<leader>gb` in LazyVim already
    -- covers the "who wrote this line" question.
    current_line_blame = false,
  },
}
