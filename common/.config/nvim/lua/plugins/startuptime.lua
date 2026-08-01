-- :StartupTime profiles a fresh launch and attributes the cost per plugin and
-- sourced file. cmd-gated, so the profiler itself never shows up in the
-- numbers it reports.
return {
  "dstein64/vim-startuptime",
  cmd = "StartupTime",
  init = function()
    -- Average several runs; a single launch is too noisy to compare against.
    vim.g.startuptime_tries = 10
  end,
}
