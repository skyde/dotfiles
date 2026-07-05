-- lua/plugins/telescope-ignore.lua
local rg_speedup_globs = {
  "--hidden",
  "--glob=!.git/**",
  "--glob=!.hg/**",
  "--glob=!.svn/**",
  "--glob=!.idea/**",
  "--glob=!.cache/**",
  "--glob=!.next/**",
  "--glob=!.nuxt/**",
  "--glob=!.svelte-kit/**",
  "--glob=!.turbo/**",
  "--glob=!.parcel-cache/**",
  "--glob=!.expo/**",
  "--glob=!.serverless/**",
  "--glob=!.terraform/**",
  "--glob=!.gradle/**",
  "--glob=!android/.gradle/**",
  "--glob=!__pycache__/**",
  "--glob=!build/**",
  "--glob=!android/app/build/**",
  "--glob=!ios/build/**",
  "--glob=!out/**",
  "--glob=!bin/**",
  "--glob=!dist/**",
  "--glob=!Debug/**",
  "--glob=!Release/**",
  "--glob=!DerivedData/**",
  "--glob=!cmake-build-*/**",
  "--glob=!CMakeFiles/**",
  "--glob=!CMakeCache.txt",
  "--glob=!compile_commands.json",
  "--glob=!node_modules/**",
  "--glob=!.pnpm/**",
  "--glob=!.yarn/**",
  "--glob=!vendor/**",
  "--glob=!Pods/**",
  "--glob=!.mypy_cache/**",
  "--glob=!.pytest_cache/**",
  "--glob=!.ruff_cache/**",
  "--glob=!.tox/**",
  "--glob=!.venv/**",
  "--glob=!venv/**",
  "--glob=!target/**",
  "--glob=!.zig-cache/**",
  "--glob=!zig-cache/**",
  "--glob=!coverage/**",
  "--glob=!docs/_build/**",
  "--glob=!*.o",
  "--glob=!*.obj",
  "--glob=!*.so",
  "--glob=!*.dll",
}

local fd_find_args = {
  "--hidden",
  "--exclude=.git",
  "--exclude=.hg",
  "--exclude=.svn",
  "--exclude=.idea",
  "--exclude=.cache",
  "--exclude=.next",
  "--exclude=.nuxt",
  "--exclude=.svelte-kit",
  "--exclude=.turbo",
  "--exclude=.parcel-cache",
  "--exclude=.expo",
  "--exclude=.serverless",
  "--exclude=.terraform",
  "--exclude=.gradle",
  "--exclude=android/.gradle",
  "--exclude=__pycache__",
  "--exclude=.mypy_cache",
  "--exclude=.pytest_cache",
  "--exclude=.ruff_cache",
  "--exclude=.tox",
  "--exclude=.venv",
  "--exclude=venv",
  "--exclude=node_modules",
  "--exclude=.pnpm",
  "--exclude=.yarn",
  "--exclude=vendor",
  "--exclude=Pods",
  "--exclude=build",
  "--exclude=android/app/build",
  "--exclude=ios/build",
  "--exclude=out",
  "--exclude=bin",
  "--exclude=dist",
  "--exclude=Debug",
  "--exclude=Release",
  "--exclude=DerivedData",
  "--exclude=cmake-build-*",
  "--exclude=CMakeFiles",
  "--exclude=CMakeCache.txt",
  "--exclude=compile_commands.json",
  "--exclude=target",
  "--exclude=.zig-cache",
  "--exclude=zig-cache",
  "--exclude=coverage",
  "--exclude=docs/_build",
  "--exclude=*.o",
  "--exclude=*.obj",
  "--exclude=*.so",
  "--exclude=*.dll",
}

local focused_grep_globs = vim.list_extend(vim.deepcopy(rg_speedup_globs), {
  "--glob=!*.blob.*",
  "--glob=!blob/**",
})

local function list_copy(items)
  return vim.list_extend({}, items)
end

return {
  {
    "folke/todo-comments.nvim",
    keys = {
      { "<leader>st", false },
    },
  },
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-telescope/telescope-live-grep-args.nvim",
    },
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
        "^%.git/",
        "^%.hg/",
        "^%.svn/",
        "^%.idea/",
        "^%.cache/",
        "^%.next/",
        "^%.nuxt/",
        "^%.svelte%-kit/",
        "^%.turbo/",
        "^%.parcel%-cache/",
        "^%.expo/",
        "^%.serverless/",
        "^%.terraform/",
        "^%.gradle/",
        "^__pycache__/",
        "^%.mypy_cache/",
        "^%.pytest_cache/",
        "^%.ruff_cache/",
        "^%.tox/",
        "^%.venv/",
        "^venv/",
        "^%.DS_Store$",
        "%.swp$",
        "%.swo$",
        --  Dependency / package managers
        "^node_modules/",
        "^%.pnpm/",
        "^%.yarn/",
        "^vendor/",
        "^Pods/",
        "^android/app/build/",
        "^android/%.gradle/",
        "^ios/Pods/",
        "^ios/build/",
        "^_deps/",
        --  Build & artefact directories
        "^build/",
        "^out/",
        "^bin/",
        "^dist/",
        "^Debug/",
        "^Release/",
        "^DerivedData/",
        "^cmake%-build%-[^/]+/",
        "^CMakeFiles/",
        "^CMakeCache%.txt$",
        "^compile_commands%.json$",
        "^target/",
        "^%.zig%-cache/",
        "^zig%-cache/",
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
        -- Documents & datasets
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
      --    Passing --glob to ripgrep means it never *opens* the file, which is
      --    faster than post-filtering. You can add or remove globs as needed.
      ---------------------------------------------------------------------------
      opts.pickers = opts.pickers or {}
      opts.pickers.live_grep = opts.pickers.live_grep or {}
      opts.pickers.live_grep.additional_args = function()
        return list_copy(rg_speedup_globs)
      end
      -- Ensure `grep_string` also searches hidden files.  LazyVim maps
      -- <leader>sg to `grep_string`, so we configure it with the same flags
      -- as `live_grep`.
      opts.pickers.grep_string = opts.pickers.grep_string or {}
      opts.pickers.grep_string.additional_args = function()
        return list_copy(rg_speedup_globs)
      end
      opts.pickers.find_files = opts.pickers.find_files or {}
      -- Include hidden files when searching with Telescope
      opts.pickers.find_files.hidden = true
      opts.pickers.find_files.additional_args = function()
        return list_copy(fd_find_args)
      end
    end,
    keys = function()
      local function live_grep_args()
        local telescope = require("telescope")
        pcall(telescope.load_extension, "live_grep_args")
        local extension = telescope.extensions.live_grep_args

        if not extension then
          vim.notify("telescope-live-grep-args is unavailable", vim.log.levels.WARN)
          return nil
        end

        return extension
      end

      local rg_types_by_filetype = {
        bash = "sh",
        c = "c",
        cmake = "cmake",
        cpp = "cpp",
        css = "css",
        dockerfile = "docker",
        fish = "fish",
        go = "go",
        html = "html",
        java = "java",
        javascript = "js",
        javascriptreact = "js",
        json = "json",
        kotlin = "kotlin",
        lua = "lua",
        make = "make",
        markdown = "md",
        objc = "objc",
        objcpp = "objcpp",
        php = "php",
        python = "py",
        ruby = "ruby",
        rust = "rust",
        scss = "css",
        sh = "sh",
        svelte = "svelte",
        swift = "swift",
        toml = "toml",
        typescript = "ts",
        typescriptreact = "ts",
        vim = "vim",
        vue = "vue",
        yaml = "yaml",
        zsh = "sh",
      }

      local function current_filetype_args()
        local ft = vim.bo.filetype
        local rg_type = rg_types_by_filetype[ft]
        if rg_type then
          return vim.list_extend({ "--type=" .. rg_type }, list_copy(focused_grep_globs))
        end

        local extension = vim.fn.expand("%:e")
        if extension ~= "" then
          return vim.list_extend({ "--glob=*." .. extension }, list_copy(focused_grep_globs))
        end

        return list_copy(focused_grep_globs)
      end

      local function grep_cpp_python()
        local extension = live_grep_args()
        if not extension then
          return
        end

        extension.live_grep_args({
          additional_args = function()
            return vim.list_extend({ "--type=cpp", "--type=py" }, list_copy(focused_grep_globs))
          end,
        })
      end

      local function grep_with_args()
        local extension = live_grep_args()
        if not extension then
          return
        end

        extension.live_grep_args({
          additional_args = function()
            return list_copy(rg_speedup_globs)
          end,
        })
      end

      -- Search files by type using the word under cursor
      local function grep_current_filetype()
        local extension = live_grep_args()
        if not extension then
          return
        end

        extension.live_grep_args({
          default_text = vim.fn.expand("<cword>"),
          additional_args = current_filetype_args,
        })
      end

      return {
        { "<leader>sA", grep_with_args, desc = "Grep with args" },
        { "<leader>se", grep_cpp_python, desc = "Grep C++/Python files only" },
        { "<leader>st", grep_current_filetype, desc = "Search word in current filetype" },
      }
    end,
  },
}
