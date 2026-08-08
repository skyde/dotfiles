-- :checkhealth chromium — renders util.chromium's diagnosis. Everything
-- that decides whether goto-definition and find-usages work in a Chromium
-- checkout, checked as one report: the binary, the build dir, the compdb
-- and its freshness, the running client's actual command, the background
-- index, the tools regeneration needs, and whether the current buffer is
-- in the database at all.

local M = {}

function M.check()
  vim.health.start("chromium clangd")
  for _, finding in ipairs(require("util.chromium").diagnose()) do
    if finding.status == "ok" then
      vim.health.ok(finding.msg)
    elseif finding.status == "warn" then
      vim.health.warn(finding.msg, finding.advice)
    elseif finding.status == "error" then
      vim.health.error(finding.msg, finding.advice)
    else
      vim.health.info(finding.msg)
    end
  end
end

return M
