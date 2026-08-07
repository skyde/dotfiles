-- Text primitives that have to survive a Neovim version bump.
--
-- Small on purpose: this is where an API that upstream renamed gets bound
-- once, so the rest of the config keeps calling one name. Everything here is
-- pure — no buffers, no windows — which is why the specs can exercise it
-- without a UI.

local M = {}

---Diff two strings.
---
---`vim.diff()` was renamed to `vim.text.diff()` in Neovim 0.12 and is listed
---for removal at 1.0 (`:h deprecated`). The signature is unchanged — 0.12's
---`vim.text.diff` is a straight forward to the same C function — so binding
---whichever name this build has, once at load, keeps the diff engine working
---on 0.11 (where only `vim.diff` exists) and on whatever release finally drops
---it. Doing it here rather than at each call site means a new call site cannot
---quietly reintroduce the deprecated name; tests/nvim_text_spec.lua checks that
---none has.
---
---@type fun(a: string, b: string, opts?: table): string|integer[][]|nil
M.diff = vim.text and vim.text.diff or vim.diff

---Hunk indices for two strings, as `{ start_a, count_a, start_b, count_b }`
---rows. The common shape by far: every caller in this config asks for indices
---and treats "no differences" and "diff refused" alike, so the `or {}` that
---every one of them used to carry lives here instead.
---@param a string
---@param b string
---@param opts? table extra options passed through to the diff, e.g. `algorithm`
---@return integer[][]
function M.hunks(a, b, opts)
  opts = vim.tbl_extend("force", opts or {}, { result_type = "indices" })
  local out = M.diff(a, b, opts)
  ---@cast out integer[][]|nil
  return out or {}
end

return M
