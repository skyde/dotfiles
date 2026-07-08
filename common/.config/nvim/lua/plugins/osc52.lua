return {
  'ojroques/nvim-osc52',
  config = function()
    require('osc52').setup {
      max_length = 0,           -- No limit
      silent = false,           -- Show message on copy
      tmux_passthrough = true,  -- vital for your tmux setup
    }

    -- Automatically copy to system clipboard on yank
    local function copy()
      if vim.v.event.operator == 'y' and vim.v.event.regname == '' then
        require('osc52').copy_register('')
      end
    end

    vim.api.nvim_create_autocmd('TextYankPost', { callback = copy })
  end
}
