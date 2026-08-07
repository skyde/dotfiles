-- :checkhealth chromium — renders util.chromium's diagnosis. Everything
-- that decides whether goto-definition and find-usages work in a Chromium
-- checkout, checked as one report: the binary, the build dir, the compdb
-- and its freshness, the running client's actual command, the background
-- index, the tools regeneration needs, and whether the buffer you came
-- from is in the database at all.

local M = {}

local CPP = { c = true, cpp = true, objc = true, objcpp = true }

---The buffer the report should be about. :checkhealth runs inside its own
---health:// scratch buffer, so "the current buffer" is never the one the
---user cares about — prefer the alternate buffer when it is C++, then the
---most recently used loaded C++ buffer. nil = detect the checkout from
---the cwd instead.
---@return integer|nil
function M.target_buf()
  local alt = vim.fn.bufnr("#")
  if alt > 0 and vim.api.nvim_buf_is_loaded(alt) and CPP[vim.bo[alt].filetype] then
    return alt
  end
  local best, best_used
  for _, info in ipairs(vim.fn.getbufinfo({ bufloaded = 1 })) do
    if CPP[vim.bo[info.bufnr].filetype] and (not best_used or info.lastused > best_used) then
      best, best_used = info.bufnr, info.lastused
    end
  end
  return best
end

function M.check()
  vim.health.start("chromium clangd")
  for _, finding in ipairs(require("util.chromium").diagnose(M.target_buf())) do
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
