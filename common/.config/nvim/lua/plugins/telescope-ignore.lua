local ignore_patterns = {
  "^%.DS_Store$",
  "%.swp$",
  "%.swo$",
  "%.o$",
  "%.obj$",
  "%.a$",
  "%.lib$",
  "%.dll$",
  "%.so$",
  "%.dylib$",
  "%.exe$",
  "%.pdb$",
  "%.class$",
  "%.jar$",
  "%.zip$",
  "%.tar$",
  "%.gz$",
  "%.7z$",
  "%.png$",
  "%.jpe?g$",
  "%.gif$",
  "%.webp$",
  "%.mp3$",
  "%.wav$",
  "%.mp4$",
  "%.mkv$",
  "%.mov$",
  "%.pdf$",
  "%.docx?$",
  "%.xlsx?$",
  "%.pptx?$",
  "%.parquet$",
  "%.arrow$",
  "%.db$",
}

-- Match ignored directories at any path depth, whether Telescope returns a
-- relative or absolute entry.
local ignored_directories = {
  ".git",
  ".hg",
  ".svn",
  ".idea",
  ".vscode",
  ".cache",
  "__pycache__",
  ".mypy_cache",
  ".pytest_cache",
  ".tox",
  "node_modules",
  ".pnpm",
  ".yarn",
  "vendor",
  "Pods",
  "_deps",
  "build",
  "out",
  "bin",
  "dist",
  "Debug",
  "Release",
  "target",
  "coverage",
}

for _, directory in ipairs(ignored_directories) do
  local escaped = directory:gsub("([^%w])", "%%%1")
  table.insert(ignore_patterns, "^" .. escaped .. "/")
  table.insert(ignore_patterns, "/" .. escaped .. "/")
end

local rg_args = { "--hidden" }
for _, directory in ipairs(ignored_directories) do
  table.insert(rg_args, "--glob=!" .. directory .. "/**")
  table.insert(rg_args, "--glob=!**/" .. directory .. "/**")
end
vim.list_extend(rg_args, {
  "--glob=!*.o",
  "--glob=!*.obj",
  "--glob=!*.so",
  "--glob=!*.dll",
  "--glob=!*.DS_Store",
})

local find_command = { "rg", "--files", "--color", "never" }
vim.list_extend(find_command, rg_args)

local filetype_to_rg_type = {
  c = "c",
  cpp = "cpp",
  javascript = "js",
  javascriptreact = "js",
  lua = "lua",
  python = "py",
  rust = "rust",
  typescript = "ts",
  typescriptreact = "ts",
}

local function live_grep_args(opts)
  return require("telescope").extensions.live_grep_args.live_grep_args(opts or {})
end

local function search_word_for_filetype()
  local args = vim.deepcopy(rg_args)
  local rg_type = filetype_to_rg_type[vim.bo.filetype]
  if rg_type then
    vim.list_extend(args, { "--type", rg_type })
  end
  live_grep_args({
    default_text = vim.fn.expand("<cword>"),
    additional_args = function()
      return args
    end,
  })
end

return {
  "nvim-telescope/telescope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    {
      "nvim-telescope/telescope-live-grep-args.nvim",
      config = function()
        LazyVim.on_load("telescope.nvim", function()
          require("telescope").load_extension("live_grep_args")
        end)
      end,
    },
  },
  opts = function(_, opts)
    opts.defaults = opts.defaults or {}
    opts.defaults.file_ignore_patterns = vim.list_extend(opts.defaults.file_ignore_patterns or {}, ignore_patterns)

    opts.pickers = opts.pickers or {}
    opts.pickers.find_files = vim.tbl_deep_extend("force", opts.pickers.find_files or {}, {
      find_command = find_command,
      hidden = true,
    })
    opts.pickers.live_grep = vim.tbl_deep_extend("force", opts.pickers.live_grep or {}, {
      additional_args = function()
        return rg_args
      end,
    })
    opts.pickers.grep_string = vim.tbl_deep_extend("force", opts.pickers.grep_string or {}, {
      additional_args = function()
        return rg_args
      end,
    })

    opts.extensions = opts.extensions or {}
    opts.extensions.live_grep_args = vim.tbl_deep_extend("force", opts.extensions.live_grep_args or {}, {
      auto_quoting = true,
    })
  end,
  keys = {
    {
      "<leader>se",
      function()
        local args = vim.deepcopy(rg_args)
        vim.list_extend(args, { "--type", "cpp", "--type", "py", "--glob=!*.blob.*", "--glob=!**/blob/**" })
        live_grep_args({
          additional_args = function()
            return args
          end,
        })
      end,
      desc = "Grep C++/Python files",
    },
    { "<leader>st", search_word_for_filetype, desc = "Search word in current filetype" },
    {
      "<leader>sT",
      function()
        live_grep_args({
          default_text = vim.fn.expand("<cword>"),
          additional_args = function()
            return rg_args
          end,
        })
      end,
      desc = "Search word in all files",
    },
  },
}
