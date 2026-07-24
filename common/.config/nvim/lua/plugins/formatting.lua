local function format_change_list()
  vim.cmd("silent update")

  if vim.fn.executable("git-cl") ~= 1 then
    return LazyVim.format({ force = true })
  end

  local cwd = LazyVim.root.get({ normalize = true })
  vim.system({ "git", "cl", "format" }, { cwd = cwd, text = true }, function(result)
    vim.schedule(function()
      if result.code == 0 then
        vim.cmd("checktime")
        vim.notify("Formatted the current change list", vim.log.levels.INFO)
      else
        LazyVim.format({ force = true })
        local message = vim.trim(result.stderr or "")
        if message ~= "" then
          vim.notify("git cl format unavailable here; formatted the current buffer\n" .. message, vim.log.levels.WARN)
        end
      end
    end)
  end)
end

return {
  {
    "stevearc/conform.nvim",
    keys = {
      { "<leader>cf", format_change_list, desc = "Format Change List / Buffer", mode = { "n", "x" } },
    },
    opts = {
      formatters_by_ft = {
        bash = { "shfmt" },
        c = { "clang_format" },
        cmake = { "cmake_format" },
        cpp = { "clang_format" },
        cuda = { "clang_format" },
        objc = { "clang_format" },
        objcpp = { "clang_format" },
        proto = { "buf" },
        python = { "ruff_format", "black", stop_after_first = true },
        sh = { "shfmt" },
        zsh = { "shfmt" },
      },
    },
  },
}
