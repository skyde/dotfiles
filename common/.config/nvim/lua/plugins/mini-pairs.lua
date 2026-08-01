-- mini.pairs only ever acts on keys typed in insert mode, but LazyVim loads it
-- on VeryLazy — the batch that runs the moment the UI comes up, whether or not
-- this session ever enters insert mode. InsertEnter is the earliest point its
-- mappings can matter, and lazy.nvim finishes loading inside that autocmd, so
-- the first character typed after `i` is already paired.
--
-- `event` has to be a function to *replace* LazyVim's trigger rather than add
-- to it: list-valued plugin properties are merged with the parent spec, so
-- returning the table from a function is what drops "VeryLazy".
return {
  "nvim-mini/mini.pairs",
  event = function()
    return { "InsertEnter" }
  end,
  opts = {
    mappings = {
      ["`"] = false,
    },
  },
}
