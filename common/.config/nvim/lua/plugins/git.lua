local vcs = require("config.vcs")

local function perforce_command()
  local configured = vim.env.NVIM_PERFORCE_CMD
  if configured and configured ~= "" then
    return configured
  end

  local shim = vim.fn.exepath("vcs-p4")
  if shim ~= "" then
    return shim
  end
  return vim.fn.executable("g4") == 1 and "g4" or "p4"
end

local function configured_adapter()
  local adapter = vim.env.NVIM_VCS
  if adapter == "g4" then
    return "p4"
  end
  if vim.tbl_contains({ "git", "hg", "jj", "p4" }, adapter) then
    return adapter
  end
  return "jj"
end

local vcs_keys = {
  { "<leader>gc", vcs.changes, desc = "VCS changes" },
  { "<leader>gd", vcs.current_file, desc = "VCS diff current file" },
  { "<leader>gD", vcs.branch_diff, desc = "VCS diff branch/base" },
  { "<leader>gC", vcs.choose_base, desc = "VCS choose compare base" },
  { "<leader>ga", vcs.current_change, desc = "VCS current-file change" },
  { "<leader>gl", vcs.file_history, desc = "VCS current-file history" },
  { "<leader>gL", vcs.repo_history, desc = "VCS repository history" },
  { "<leader>gR", vcs.refresh, desc = "VCS refresh view" },
  { "<leader>gr", vcs.choose_adapter, desc = "VCS choose repository/adapter" },
  { "<leader>gv", vcs.choose_adapter, desc = "VCS choose adapter" },
  { "<leader>gp", vcs.upstream_patch, desc = "VCS upstream patch" },
  { "<leader>gA", vcs.branch_diff, desc = "VCS all branch changes" },
  { "<leader>gy", vcs.copy_diff, desc = "VCS copy branch diff" },
  { "<leader>gw", vcs.worktree_file, desc = "VCS open worktree file" },
  { "<leader>gq", vcs.close, desc = "VCS close diff view" },
  { "<leader>g?", vcs.info, desc = "VCS workspace info" },
}

return {
  {
    "dlyongemallo/diffview-plus.nvim",
    version = "*",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = {
      "DiffviewClose",
      "DiffviewDiffDirs",
      "DiffviewDiffFiles",
      "DiffviewFileHistory",
      "DiffviewFocusFiles",
      "DiffviewMergeFiles",
      "DiffviewOpen",
      "DiffviewRefresh",
      "DiffviewToggle",
      "DiffviewToggleFiles",
    },
    keys = vcs_keys,
    -- LazyVim installs some Git-only mappings during VeryLazy. Re-apply this
    -- backend-neutral matrix afterwards so gd/gD/gp/gl/gL cannot be shadowed.
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        callback = function()
          vim.schedule(function()
            for _, key in ipairs(vcs_keys) do
              vim.keymap.set("n", key[1], key[2], { desc = key.desc, silent = true })
            end
          end)
        end,
      })
    end,
    opts = function()
      local actions = require("diffview.actions")

      local function git_only(action, description)
        return function()
          local view = require("diffview.lib").get_current_view()
          if not view or not view.adapter or view.adapter.config_key ~= "git" then
            vim.notify(description .. " is only available in Git views", vim.log.levels.WARN)
            return
          end
          action()
        end
      end

      local next_hunk = "<cmd>normal! ]c<CR>"
      local previous_hunk = "<cmd>normal! [c<CR>"

      return {
        enhanced_diff_hl = true,
        preferred_adapter = configured_adapter(),
        p4_cmd = { perforce_command() },
        hide_merge_artifacts = true,
        clean_up_buffers = true,
        large_file_threshold = 20000,
        diffopt = {
          algorithm = "histogram",
          indent_heuristic = true,
          linematch = 60,
        },
        persist_selections = { enabled = true },
        view = {
          default = {
            layout = "diff1_inline",
            disable_diagnostics = true,
            winbar_info = true,
            focus_diff = false,
          },
          file_history = {
            layout = "diff1_inline",
            disable_diagnostics = true,
            winbar_info = true,
            focus_diff = false,
          },
          merge_tool = {
            layout = "diff4_mixed",
            disable_diagnostics = true,
            winbar_info = true,
            focus_diff = false,
          },
          cycle_layouts = {
            default = { "diff1_inline", "diff2_horizontal", "diff2_vertical" },
            merge_tool = { "diff4_mixed", "diff3_mixed", "diff3_horizontal", "diff1_plain" },
          },
          inline = {
            style = "unified",
            deletion_highlight = "full_width",
            deletion_treesitter = true,
          },
        },
        file_panel = {
          listing_style = "tree",
          show_branch_name = true,
          win_config = { position = "left", width = 42 },
        },
        file_history_panel = {
          stat_style = "both",
          date_format = "relative",
          win_config = { position = "left", width = 48 },
        },
        hooks = {
          diff_buf_read = function()
            vim.opt_local.wrap = false
            vim.opt_local.list = false
          end,
        },
        keymaps = {
          view = {
            { "n", "<leader>ci", actions.cycle_layout, { desc = "Diff: cycle inline/side-by-side" } },
            { "n", "<leader>gw", actions.goto_file_edit_close, { desc = "Open worktree file and close diff" } },
          },
          diff1 = {
            { "n", "<A-Down>", next_hunk, { desc = "Next change" } },
            { "n", "<A-Up>", previous_hunk, { desc = "Previous change" } },
          },
          diff1_inline = {
            { "n", "<A-Down>", actions.next_inline_hunk, { desc = "Next change" } },
            { "n", "<A-Up>", actions.prev_inline_hunk, { desc = "Previous change" } },
            { { "n", "x" }, "<leader>cv", actions.diffget_inline, { desc = "Revert diff hunk" } },
          },
          diff2 = {
            { "n", "<A-Down>", next_hunk, { desc = "Next change" } },
            { "n", "<A-Up>", previous_hunk, { desc = "Previous change" } },
          },
          diff3 = {
            { "n", "<A-Down>", actions.next_conflict, { desc = "Next conflict" } },
            { "n", "<A-Up>", actions.prev_conflict, { desc = "Previous conflict" } },
          },
          diff4 = {
            { "n", "<A-Down>", actions.next_conflict, { desc = "Next conflict" } },
            { "n", "<A-Up>", actions.prev_conflict, { desc = "Previous conflict" } },
          },
          file_panel = {
            { "n", "j", actions.select_next_entry, { desc = "Preview next changed file" } },
            { "n", "k", actions.select_prev_entry, { desc = "Preview previous changed file" } },
            { "n", "p", actions.select_entry, { desc = "Preview selected changed file" } },
            { "n", "<leader>ci", actions.cycle_layout, { desc = "Diff: cycle inline/side-by-side" } },
            { "n", "q", actions.close, { desc = "Close diff view" } },
            { "n", "-", git_only(actions.toggle_stage_entry, "Stage/unstage"), { desc = "Git stage/unstage file" } },
            { "n", "s", git_only(actions.toggle_stage_entry, "Stage/unstage"), { desc = "Git stage/unstage file" } },
            { "n", "S", git_only(actions.stage_all, "Stage all"), { desc = "Git stage all files" } },
            { "n", "U", git_only(actions.unstage_all, "Unstage all"), { desc = "Git unstage all files" } },
            { "n", "X", git_only(actions.restore_entry, "Restore"), { desc = "Git restore file (undoable)" } },
          },
          file_history_panel = {
            { "n", "j", actions.select_next_entry, { desc = "Preview next history entry" } },
            { "n", "k", actions.select_prev_entry, { desc = "Preview previous history entry" } },
            { "n", "p", actions.select_entry, { desc = "Preview selected history entry" } },
            { "n", "<leader>ci", actions.cycle_layout, { desc = "Diff: cycle inline/side-by-side" } },
            { "n", "q", actions.close, { desc = "Close file history" } },
          },
        },
      }
    end,
    config = function(_, opts)
      require("diffview").setup(opts)
    end,
  },
}
