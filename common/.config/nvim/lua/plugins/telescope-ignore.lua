-- lua/plugins/telescope-ignore.lua

-- Passing --glob to ripgrep means it never *opens* the file, which is faster
-- than post-filtering. Shared by the pickers configured in `opts` and the
-- live_grep_args keys below.
local speedup_globs = {
  "--hidden",
  "--glob=!build/**",
  "--glob=!out/**",
  "--glob=!bin/**",
  "--glob=!dist/**",
  "--glob=!node_modules/**",
  "--glob=!*.o",
  "--glob=!*.obj",
  "--glob=!*.so",
  "--glob=!*.dll",
}

-- The typed searches additionally skip generated blob payloads, which are
-- large enough to dominate results without ever being what you wanted.
local typed_globs = vim.list_extend(vim.list_extend({}, speedup_globs), {
  "--glob=!*.blob.*",
  "--glob=!blob/**",
})

return {
  "nvim-telescope/telescope.nvim",
  -- <leader>se and <leader>st below call into live_grep_args, so it has to be
  -- installed and registered or those keys raise.
  dependencies = { "nvim-telescope/telescope-live-grep-args.nvim" },
  cmd = "Telescope",
  opts = function(_, opts)
    ---------------------------------------------------------------------------
    -- 1. Global ignore patterns (Lua regexes) ---------------------------------
    --    • Paths are always relative to the cwd / project root
    --    • “^” anchors to the start of that relative path
    --    • “%.ext$” matches a literal dot + extension
    --    Feel free to slim this down if you *do* want to search any of them.
    ---------------------------------------------------------------------------
    local ignore = {
      --  Version-control & editor cruft
      "^.git/",
      "^.hg/",
      "^.svn/",
      "^.idea/",
      "^.vscode/",
      "^.cache/",
      "^__pycache__/",
      "^.tox/",
      "^.DS_Store$",
      "%.swp$",
      "%.swo$",
      --  Dependency / package managers
      "^node_modules/",
      "^.pnpm/",
      "^.yarn/",
      "^vendor/",
      "^Pods/",
      "^android/app/build/",
      "^ios/Pods/",
      "^_deps/",
      --  Build & artefact directories
      "^build/",
      "^out/",
      "^bin/",
      "^dist/",
      "^Debug/",
      "^Release/",
      "^target/",
      --  Coverage & docs
      "^coverage/",
      "^docs/_build/",
      --  Binary/object/library files
      "%.o$",
      "%.obj$",
      "%.a$",
      "%.lib$",
      "%.dll$",
      "%.so$",
      "%.dylib$",
      "%.exe$",
      "%.pdb$",
      "%.idb$",
      "%.ilk$",
      "%.class$",
      "%.jar$",
      --  Archives
      "%.zip$",
      "%.tar$",
      "%.gz$",
      "%.bz2$",
      "%.xz$",
      "%.7z$",
      "%.rar$",
      --  Media (comment out if you often grep assets)
      "%.png$",
      "%.jpe?g$",
      "%.gif$",
      "%.bmp$",
      "%.svg$",
      "%.webp$",
      "%.mp3$",
      "%.wav$",
      "%.ogg$",
      "%.flac$",
      "%.mp4$",
      "%.mkv$",
      "%.mov$",
      --  Documents & datasets
      "%.pdf$",
      "%.docx?$",
      "%.xlsx?$",
      "%.pptx?$",
      "%.csv$",
      "%.tsv$",
      "%.parquet$",
      "%.arrow$",
      "%.dat$",
      "%.bin$",
      "%.db$",
    }

    ---------------------------------------------------------------------------
    -- 2. Merge with whatever LazyVim already set ------------------------------
    ---------------------------------------------------------------------------
    -- Ensure opts and defaults exist
    opts = opts or {}
    opts.defaults = opts.defaults or {}
    opts.defaults.file_ignore_patterns = vim.list_extend(opts.defaults.file_ignore_patterns or {}, ignore)
    opts.defaults.hidden = true

    ---------------------------------------------------------------------------
    -- 3. (Optional) Speed up live_grep even more ------------------------------
    --    See `speedup_globs` at the top of this file.
    ---------------------------------------------------------------------------
    opts.pickers = opts.pickers or {}
    opts.pickers.live_grep = opts.pickers.live_grep or {}
    opts.pickers.live_grep.additional_args = function()
      return speedup_globs
    end
    -- Ensure `grep_string` also searches hidden files.  LazyVim maps
    -- <leader>sg to `grep_string`, so we configure it with the same flags
    -- as `live_grep`.
    opts.pickers.grep_string = opts.pickers.grep_string or {}
    opts.pickers.grep_string.additional_args = function()
      return speedup_globs
    end
    opts.pickers.find_files = opts.pickers.find_files or {}
    -- Include hidden files when searching with Telescope
    opts.pickers.find_files.hidden = true
    opts.pickers.find_files.additional_args = function()
      return speedup_globs
    end
  end,
  config = function(_, opts)
    -- Defining `config` suppresses lazy.nvim's automatic setup call, so the
    -- opts built above have to be handed over explicitly or every ignore
    -- pattern in this file is silently dropped.
    require("telescope").setup(opts)
    require("telescope").load_extension("live_grep_args")
  end,
  keys = {
    {
      "<leader>se",
      function()
        require("telescope").extensions.live_grep_args.live_grep_args({
          additional_args = function()
            return vim.list_extend({ "--type=cpp", "--type=py" }, typed_globs)
          end,
        })
      end,
      desc = "Grep C++/Python files only",
    },
    {
      -- Search files by type using the word under cursor
      "<leader>st",
      function()
        -- Nil when ripgrep has no type for this filetype, in which case the
        -- search runs unfiltered rather than erroring out. See util.ripgrep.
        local type_arg = require("util.ripgrep").type_arg(vim.bo.filetype)
        require("telescope").extensions.live_grep_args.live_grep_args({
          default_text = vim.fn.expand("<cword>"),
          additional_args = function()
            if type_arg then
              return vim.list_extend({ type_arg }, typed_globs)
            end
            return typed_globs
          end,
        })
      end,
      desc = "Search word in current filetype",
    },
  },
}
