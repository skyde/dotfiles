local disabled_lowercase_keys = {
  "<leader>ta",
  "<leader>tt",
  "<leader>tT",
  "<leader>tr",
  "<leader>tl",
  "<leader>ts",
  "<leader>to",
  "<leader>tO",
  "<leader>tS",
  "<leader>tw",
  "<leader>td",
}

local python_cache = {}

local function executable(path)
  return path and path ~= "" and vim.fn.executable(path) == 1
end

local function pytest_python()
  local pytest = vim.fn.exepath("pytest")
  if pytest == "" then
    return nil
  end

  local ok, lines = pcall(vim.fn.readfile, pytest, "", 1)
  local shebang = ok and lines[1] and lines[1]:match("^#!%s*(.+)$")
  if not shebang then
    return nil
  end

  local words = vim.split(shebang, "%s+", { trimempty = true })
  local interpreter = words[1]
  if interpreter and vim.fs.basename(interpreter) == "env" and words[2] then
    interpreter = vim.fn.exepath(words[2])
  end
  return executable(interpreter) and interpreter or nil
end

local function python_for_tests(root)
  root = root or vim.uv.cwd()
  if python_cache[root] then
    return python_cache[root]
  end

  local executable_path = LazyVim.is_win() and { "Scripts", "python.exe" } or { "bin", "python" }
  local candidates = {}
  if vim.env.VIRTUAL_ENV then
    table.insert(candidates, vim.fs.joinpath(vim.env.VIRTUAL_ENV, unpack(executable_path)))
  end
  for _, name in ipairs({ ".venv", "venv" }) do
    table.insert(candidates, vim.fs.joinpath(root, name, unpack(executable_path)))
  end
  table.insert(candidates, pytest_python())
  table.insert(candidates, vim.fn.exepath("python3"))
  table.insert(candidates, vim.fn.exepath("python"))

  for _, candidate in ipairs(candidates) do
    if executable(candidate) then
      python_cache[root] = candidate
      return candidate
    end
  end

  python_cache[root] = "python"
  return python_cache[root]
end

local keys = {}
for _, lhs in ipairs(disabled_lowercase_keys) do
  table.insert(keys, { lhs, false })
end

vim.list_extend(keys, {
  {
    "<leader>Tr",
    function()
      require("neotest").run.run()
    end,
    desc = "Test: run nearest",
  },
  {
    "<leader>Td",
    function()
      require("neotest").run.run({ strategy = "dap" })
    end,
    desc = "Test: debug nearest",
  },
  {
    "<leader>Ta",
    function()
      require("neotest").run.run(vim.uv.cwd())
    end,
    desc = "Test: run all",
  },
  {
    "<leader>TR",
    function()
      require("neotest").run.run_last()
    end,
    desc = "Test: re-run last",
  },
  {
    "<leader>To",
    function()
      require("neotest").output.open({ enter = true, auto_close = true })
    end,
    desc = "Test: show output",
  },
  {
    "<leader>Tf",
    function()
      require("neotest").run.run(vim.fn.expand("%"))
    end,
    desc = "Test: run file",
  },
  {
    "<leader>Te",
    function()
      require("neotest").summary.toggle()
    end,
    desc = "Test: toggle explorer",
  },
})

return {
  {
    "nvim-neotest/neotest",
    event = "BufReadPre",
    keys = keys,
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      opts.adapters["neotest-python"] = opts.adapters["neotest-python"] or {}
      opts.adapters["neotest-python"].python = python_for_tests
    end,
  },
}
