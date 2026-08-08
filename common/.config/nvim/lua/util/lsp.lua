-- Small LSP helpers that are keymap-facing, so a binding never has to know
-- what a plugin happens to have named a command this month.

local M = {}

-- clangd's switch-source-header is an LSP *extension*: the server answers
-- textDocument/switchSourceHeader with the counterpart's URI. nvim-lspconfig
-- wraps it in a buffer-local command, and renamed that command
-- (ClangdSwitchSourceHeader -> LspClangdSwitchSourceHeader) in its 2.0
-- rewrite — a binding pinned to either name is one plugin update away from
-- E492, and under nvim 0.12's native :lsp support lspconfig defines no Lsp*
-- commands at all. Asking the client directly outlives all of that; the
-- commands are only a fallback for a clangd attached by something that does
-- not answer the request itself.
local SWITCH = "textDocument/switchSourceHeader"

---Jump between a C/C++/ObjC source file and its header.
---@param bufnr? integer  defaults to the current buffer
function M.switch_source_header(bufnr)
  bufnr = (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
  local client = vim.lsp.get_clients({ bufnr = bufnr, name = "clangd" })[1]
  if not client then
    -- No clangd on this buffer: try the commands anyway (another plugin may
    -- provide them), then say what is actually missing.
    for _, cmd in ipairs({ "LspClangdSwitchSourceHeader", "ClangdSwitchSourceHeader" }) do
      if vim.fn.exists(":" .. cmd) == 2 then
        return vim.cmd(cmd)
      end
    end
    vim.notify("clangd is not attached; switch header/source needs it", vim.log.levels.WARN)
    return
  end
  client:request(SWITCH, { uri = vim.uri_from_bufnr(bufnr) }, function(err, result)
    if err then
      vim.notify("switch header/source failed: " .. (err.message or vim.inspect(err)), vim.log.levels.ERROR)
      return
    end
    if type(result) ~= "string" or result == "" then
      -- clangd answers null when it cannot find the counterpart — usually
      -- because the file is not in the compilation database, which is a
      -- different problem with its own report.
      vim.notify("No matching header/source for this file", vim.log.levels.WARN)
      return
    end
    vim.cmd.edit(vim.fn.fnameescape(vim.uri_to_fname(result)))
  end, bufnr)
end

return M
