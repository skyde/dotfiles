-- lua/plugins/telescope-ignore.lua
return {
  "nvim-telescope/telescope.nvim",
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
      --Documents & datasets("%.pdf$"),
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
    --    Passing --glob to ripgrep means it never *opens* the file, which is
    --    faster than post-filtering. You can add or remove globs as needed.
    ---------------------------------------------------------------------------
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
      -- Add or remove globs here to customize what is excluded for speed
    }
    opts.pickers = opts.pickers or {}
    opts.pickers.live_grep = opts.pickers.live_grep or {}
    opts.pickers.live_grep.additional_args = function()
      return speedup_globs
    end
    opts.pickers.find_files = opts.pickers.find_files or {}
    -- Include hidden files when searching with Telescope
    opts.pickers.find_files.hidden = true
    opts.pickers.find_files.additional_args = function()
      return speedup_globs
    end
  end,
  config = function()
    -- Add <leader>se to run live_grep_args with --type=cpp and --type=py, but exclude any *.blob.* files
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
      "--glob=!*.blob.*", -- Exclude any file with .blob. in the name
      "--glob=!blob/**",   -- Exclude any folder named blob
    }
    vim.keymap.set("n", "<leader>se", function()
      require("telescope").extensions.live_grep_args.live_grep_args({
        additional_args = function()
          return vim.list_extend({ "--type=cpp", "--type=py" }, speedup_globs)
        end,
      })
    end, { desc = "Grep C++/Python files only" })
  end,
}
