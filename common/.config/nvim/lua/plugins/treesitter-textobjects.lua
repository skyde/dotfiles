-- `]c` / `[c` mean "next/previous change" everywhere in this config — diff
-- hunk, conflict, or gitsigns hunk (see config/vcs.lua), matching both vim
-- tradition and the VS Code bindings. The textobjects plugin binds the same
-- keys buffer-locally to class motions, which silently shadows the global
-- mapping in every treesitter buffer. Move the class motions to k ("klass").
return {
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    opts = function(_, opts)
      local keys = vim.tbl_get(opts, "move", "keys")
      if not keys then
        return
      end
      local moved = {
        goto_next_start = { from = "]c", to = "]k" },
        goto_next_end = { from = "]C", to = "]K" },
        goto_previous_start = { from = "[c", to = "[k" },
        goto_previous_end = { from = "[C", to = "[K" },
      }
      for method, m in pairs(moved) do
        local t = keys[method]
        if t and t[m.from] then
          t[m.to], t[m.from] = t[m.from], nil
        end
      end
    end,
  },
}
