return {
  -- Replaced ojroques/nvim-osc52 with local script to avoid /dev/fd/2 write errors
  name = 'osc52-clipboard',
  dir = vim.fn.stdpath('config'), -- Dummy path to satisfy lazy.nvim
  config = function()
    local function copy()
      if vim.v.event.operator == 'y' and vim.v.event.regname == '' then
        local text = vim.fn.getreg('"')
        -- Use the external osc-copy script which handles /dev/tty writing
        -- and tmux wrapping correctly.
        -- Ensure 'osc-copy' is in PATH.
        vim.fn.system({'osc-copy'}, text)
      end
    end

    vim.api.nvim_create_autocmd('TextYankPost', {
      group = vim.api.nvim_create_augroup('OSC52Yank', { clear = true }),
      callback = copy,
    })
  end
}
