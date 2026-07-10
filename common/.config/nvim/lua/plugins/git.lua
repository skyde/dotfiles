local function current_file_arg()
  local path = vim.fn.expand("%:p")
  if path == "" then
    vim.notify("No file", vim.log.levels.WARN)
    return nil
  end
  return vim.fn.fnameescape(path)
end

return {
  {
    -- This is the actively maintained fork of sindrets/diffview.nvim.
    "dlyongemallo/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = {
      "DiffviewClose",
      "DiffviewFileHistory",
      "DiffviewFocusFiles",
      "DiffviewOpen",
      "DiffviewRefresh",
      "DiffviewToggleFiles",
    },
    opts = {
      enhanced_diff_hl = true,
      use_icons = true,
    },
    keys = {
      { "<leader>gD", "<cmd>DiffviewOpen<CR>", desc = "Git diff: all changes" },
      {
        "<leader>gd",
        function()
          local path = current_file_arg()
          if path then
            vim.cmd("DiffviewOpen -- " .. path)
          end
        end,
        desc = "Git diff: current file",
      },
      {
        "<leader>ga",
        function()
          local path = current_file_arg()
          if path then
            vim.cmd("DiffviewOpen HEAD -- " .. path)
          end
        end,
        desc = "Git changes: current file",
      },
      {
        "<leader>gC",
        function()
          vim.ui.input({ prompt = "Compare base: ", default = "origin/main" }, function(base)
            if base and base ~= "" then
              vim.cmd("DiffviewOpen " .. vim.fn.fnameescape(base) .. "...HEAD")
            end
          end)
        end,
        desc = "Git diff: choose compare base",
      },
      {
        "<leader>gF",
        function()
          local path = current_file_arg()
          if path then
            vim.cmd("DiffviewFileHistory " .. path)
          end
        end,
        desc = "Git file history",
      },
      { "<leader>gq", "<cmd>DiffviewClose<CR>", desc = "Close Git diff" },
    },
  },
}
