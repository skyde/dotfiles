-- nvim-ts-autotag only ever does anything in markup-ish buffers, but the
-- LazyVim spec loads it on LazyFile — every file, including .txt and C++,
-- where its ~8ms of setup buys nothing. Loading by filetype instead keeps
-- the behaviour identical in the buffers it supports and off the file-open
-- path everywhere else. The event function returning {} is how a child spec
-- *removes* the parent's trigger: list-valued props are otherwise merged.
return {
  "windwp/nvim-ts-autotag",
  event = function()
    return {}
  end,
  -- The plugin's own supported-filetype list.
  ft = {
    "astro",
    "glimmer",
    "handlebars",
    "html",
    "htmldjango",
    "javascript",
    "javascriptreact",
    "jsx",
    "markdown",
    "php",
    "rescript",
    "svelte",
    "tsx",
    "twig",
    "typescript",
    "typescriptreact",
    "vue",
    "xml",
  },
}
