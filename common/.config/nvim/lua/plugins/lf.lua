return {
  {
    "is0n/fm-nvim",
    cmd = "Lf",
    keys = {
      -- Reserve <leader>e for the preferred file manager; keep LF on <leader>E.
      {
        "<leader>E",
        function()
          local project = require("config.project")
          local dir = project.root_for_buffer(0)
          local ok, fm = pcall(require, "fm-nvim")
          if ok and fm and type(fm.Lf) == "function" then
            fm.Lf(vim.fn.shellescape(dir))
            return
          end

          if vim.fn.exists(":Lf") ~= 2 then
            vim.notify("LF is unavailable", vim.log.levels.WARN)
            return
          end

          local cmd_ok, err = pcall(vim.cmd, "Lf " .. vim.fn.fnameescape(dir))
          if not cmd_ok then
            vim.notify("Unable to open LF: " .. tostring(err), vim.log.levels.WARN)
          end
        end,
        desc = "LF at project root",
      },
    },
    config = function()
      require("fm-nvim").setup({
        cmd = "lf",
      })
    end,
  },
}
