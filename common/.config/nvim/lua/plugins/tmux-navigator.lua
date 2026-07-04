local passthrough_commands = {
  aider = true,
  autossh = true,
  claude = true,
  codex = true,
  delta = true,
  fzf = true,
  ["fzf-tmux"] = true,
  gemini = true,
  btop = true,
  bpython = true,
  gitui = true,
  helix = true,
  htop = true,
  hx = true,
  ipdb = true,
  ipython = true,
  irb = true,
  k9s = true,
  lazygit = true,
  lazydocker = true,
  less = true,
  lf = true,
  man = true,
  more = true,
  most = true,
  nnn = true,
  ranger = true,
  screen = true,
  tig = true,
  tmux = true,
  nvim = true,
  nvimdiff = true,
  opencode = true,
  pdb = true,
  phpdbg = true,
  pry = true,
  ptpython = true,
  pudb = true,
  rdbg = true,
  gdb = true,
  ghci = true,
  iex = true,
  erl = true,
  utop = true,
  jshell = true,
  lldb = true,
  radian = true,
  rr = true,
  sk = true,
  mosh = true,
  ["mosh-client"] = true,
  ssh = true,
  vi = true,
  view = true,
  vim = true,
  ["vim.basic"] = true,
  vimdiff = true,
  ["vim.tiny"] = true,
  yazi = true,
  zellij = true,
}

local wrapper_commands = {
  arch = true,
  command = true,
  doas = true,
  env = true,
  exec = true,
  gtime = true,
  nice = true,
  noglob = true,
  rlwrap = true,
  setsid = true,
  sshpass = true,
  stdbuf = true,
  sudo = true,
  time = true,
  unbuffer = true,
  winpty = true,
}

local shell_commands = {
  bash = true,
  dash = true,
  fish = true,
  ksh = true,
  nu = true,
  nushell = true,
  powershell = true,
  pwsh = true,
  sh = true,
  xonsh = true,
  zsh = true,
}

local shell_short_option_cluster_commands = {
  bash = true,
  dash = true,
  ksh = true,
  sh = true,
  zsh = true,
}

local shell_control_operators = {
  ["&"] = true,
  ["&&"] = true,
  [";"] = true,
  ["|"] = true,
  ["||"] = true,
}

local shell_setup_commands = {
  ["."] = true,
  alias = true,
  cd = true,
  clear = true,
  echo = true,
  export = true,
  popd = true,
  printf = true,
  pushd = true,
  set = true,
  source = true,
  trap = true,
  ["true"] = true,
  ulimit = true,
  umask = true,
  unset = true,
}

local shell_failure_handler_commands = {
  exit = true,
  ["return"] = true,
}

local env_options_with_value = {
  ["-C"] = true,
  ["-u"] = true,
  ["--chdir"] = true,
  ["--unset"] = true,
}

local env_split_string_options = {
  ["-S"] = true,
  ["--split-string"] = true,
}

local devcontainer_options_with_value = {
  ["--additional-features"] = true,
  ["--additional-features-file"] = true,
  ["--cache-from"] = true,
  ["--cache-to"] = true,
  ["--config"] = true,
  ["--container-session-data-folder"] = true,
  ["--default-user-env-probe"] = true,
  ["--dotfiles-install-command"] = true,
  ["--dotfiles-repository"] = true,
  ["--dotfiles-target-path"] = true,
  ["--gpu-availability"] = true,
  ["--id-label"] = true,
  ["--log-format"] = true,
  ["--log-level"] = true,
  ["--mount"] = true,
  ["--remote-env"] = true,
  ["--remote-env-file"] = true,
  ["--secrets"] = true,
  ["--secrets-file"] = true,
  ["--tmp-dir"] = true,
  ["--user"] = true,
  ["--workspace-folder"] = true,
}

local poetry_global_options_with_value = {
  ["--directory"] = true,
  ["--project"] = true,
  ["-C"] = true,
  ["-P"] = true,
}

local pipenv_global_options_with_value = {
  ["--pypi-mirror"] = true,
  ["--python"] = true,
}

local pipx_run_options_with_value = {
  ["--backend"] = true,
  ["--fetch-python"] = true,
  ["--index-url"] = true,
  ["--pip-args"] = true,
  ["--python"] = true,
  ["--spec"] = true,
  ["--with"] = true,
  ["-i"] = true,
}

local pixi_global_options_with_value = {
  ["--manifest-path"] = true,
}

local pixi_global_stop_options = {
  ["--help"] = true,
  ["--version"] = true,
  ["-V"] = true,
  ["-h"] = true,
}

local pixi_run_options_with_value = {
  ["--environment"] = true,
  ["-e"] = true,
}

local pixi_run_stop_options = {
  ["--dry-run"] = true,
  ["--help"] = true,
  ["--version"] = true,
  ["-V"] = true,
  ["-h"] = true,
  ["-n"] = true,
}

local hatch_global_options_with_value = {
  ["--env"] = true,
  ["-e"] = true,
}

local hatch_env_run_options_with_value = {
  ["--env"] = true,
  ["--exclude"] = true,
  ["--filter"] = true,
  ["--include"] = true,
  ["-e"] = true,
  ["-f"] = true,
  ["-i"] = true,
  ["-x"] = true,
}

local uv_global_options_with_value = {
  ["--cache-dir"] = true,
  ["--color"] = true,
  ["--config-file"] = true,
  ["--directory"] = true,
  ["--keyring-provider"] = true,
  ["--password"] = true,
  ["--project"] = true,
  ["--token"] = true,
  ["--username"] = true,
  ["-C"] = true,
  ["-t"] = true,
  ["-u"] = true,
}

local uv_run_options_with_value = {
  ["--allow-insecure-host"] = true,
  ["--config-file"] = true,
  ["--default-index"] = true,
  ["--directory"] = true,
  ["--env-file"] = true,
  ["--exclude-newer"] = true,
  ["--extra"] = true,
  ["--extra-index-url"] = true,
  ["--find-links"] = true,
  ["--fork-strategy"] = true,
  ["--from"] = true,
  ["--group"] = true,
  ["--index"] = true,
  ["--index-strategy"] = true,
  ["--index-url"] = true,
  ["--keyring-provider"] = true,
  ["--link-mode"] = true,
  ["--managed-python"] = true,
  ["--no-binary"] = true,
  ["--no-binary-package"] = true,
  ["--no-build"] = true,
  ["--no-build-isolation-package"] = true,
  ["--no-build-package"] = true,
  ["--no-editable-package"] = true,
  ["--no-extra"] = true,
  ["--no-group"] = true,
  ["--no-sources-package"] = true,
  ["--only-group"] = true,
  ["--override"] = true,
  ["--overrides"] = true,
  ["--package"] = true,
  ["--prerelease"] = true,
  ["--project"] = true,
  ["--python"] = true,
  ["--refresh-package"] = true,
  ["--requirement"] = true,
  ["--resolution"] = true,
  ["--upgrade-package"] = true,
  ["--with"] = true,
  ["--with-editable"] = true,
  ["--with-requirements"] = true,
  ["--with-requirement"] = true,
  ["--with-sources"] = true,
  ["--with-workspace"] = true,
  ["--workspace"] = true,
  ["-C"] = true,
  ["-i"] = true,
  ["-p"] = true,
}

local uv_tool_run_options_with_value = {
  ["--allow-insecure-host"] = true,
  ["--build-constraint"] = true,
  ["--build-constraints"] = true,
  ["--cache-dir"] = true,
  ["--color"] = true,
  ["--config-file"] = true,
  ["--config-setting"] = true,
  ["--config-settings"] = true,
  ["--config-settings-package"] = true,
  ["--constraint"] = true,
  ["--constraints"] = true,
  ["--default-index"] = true,
  ["--directory"] = true,
  ["--env-file"] = true,
  ["--exclude-newer"] = true,
  ["--exclude-newer-package"] = true,
  ["--extra-index-url"] = true,
  ["--find-links"] = true,
  ["--fork-strategy"] = true,
  ["--from"] = true,
  ["--index"] = true,
  ["--index-strategy"] = true,
  ["--index-url"] = true,
  ["--keyring-provider"] = true,
  ["--link-mode"] = true,
  ["--no-binary-package"] = true,
  ["--no-build-isolation-package"] = true,
  ["--no-build-package"] = true,
  ["--no-sources-package"] = true,
  ["--override"] = true,
  ["--overrides"] = true,
  ["--password"] = true,
  ["--prerelease"] = true,
  ["--project"] = true,
  ["--python"] = true,
  ["--python-platform"] = true,
  ["--refresh-package"] = true,
  ["--reinstall-package"] = true,
  ["--resolution"] = true,
  ["--token"] = true,
  ["--torch-backend"] = true,
  ["--trusted-host"] = true,
  ["--upgrade-group"] = true,
  ["--upgrade-package"] = true,
  ["--username"] = true,
  ["--with"] = true,
  ["--with-editable"] = true,
  ["--with-requirements"] = true,
  ["-b"] = true,
  ["-C"] = true,
  ["-c"] = true,
  ["-f"] = true,
  ["-i"] = true,
  ["-p"] = true,
  ["-P"] = true,
  ["-t"] = true,
  ["-u"] = true,
  ["-w"] = true,
}

local uv_tool_run_stop_options = {
  ["--help"] = true,
  ["--version"] = true,
  ["-V"] = true,
  ["-h"] = true,
}

local npm_exec_options_with_value = {
  ["--call"] = true,
  ["--package"] = true,
  ["--workspace"] = true,
  ["-c"] = true,
  ["-p"] = true,
  ["-w"] = true,
}

local package_executable_options_with_value = {
  ["--package"] = true,
  ["-p"] = true,
}

local pnpm_global_options_with_value = {
  ["--dir"] = true,
  ["--filter"] = true,
  ["--filter-prod"] = true,
  ["--workspace-concurrency"] = true,
  ["-C"] = true,
  ["-F"] = true,
}

local pnpm_exec_options_with_value = {
  ["--changed-files-ignore-pattern"] = true,
  ["--dir"] = true,
  ["--filter"] = true,
  ["--filter-prod"] = true,
  ["--loglevel"] = true,
  ["--resume-from"] = true,
  ["--test-pattern"] = true,
  ["-C"] = true,
  ["-F"] = true,
}

local pnpm_dlx_options_with_value = {
  ["--allow-build"] = true,
  ["--package"] = true,
  ["--reporter"] = true,
}

local container_global_options_with_value = {
  docker = {
    ["--config"] = true,
    ["--context"] = true,
    ["--host"] = true,
    ["--log-level"] = true,
    ["--tlscacert"] = true,
    ["--tlscert"] = true,
    ["--tlskey"] = true,
    ["-c"] = true,
    ["-H"] = true,
    ["-l"] = true,
  },
  podman = {
    ["--cgroup-manager"] = true,
    ["--config"] = true,
    ["--connection"] = true,
    ["--events-backend"] = true,
    ["--identity"] = true,
    ["--imagestore"] = true,
    ["--log-level"] = true,
    ["--module"] = true,
    ["--namespace"] = true,
    ["--network-cmd-path"] = true,
    ["--out"] = true,
    ["--root"] = true,
    ["--runroot"] = true,
    ["--runtime"] = true,
    ["--storage-driver"] = true,
    ["--storage-opt"] = true,
    ["--tmpdir"] = true,
    ["--url"] = true,
    ["--volumepath"] = true,
  },
}

local container_global_stop_options = {
  ["--help"] = true,
  ["--version"] = true,
  ["-h"] = true,
  ["-v"] = true,
}

local kubernetes_exec_options_with_value = {
  ["--as"] = true,
  ["--as-group"] = true,
  ["--as-uid"] = true,
  ["--cache-dir"] = true,
  ["--certificate-authority"] = true,
  ["--client-certificate"] = true,
  ["--client-key"] = true,
  ["--cluster"] = true,
  ["--container"] = true,
  ["--context"] = true,
  ["--filename"] = true,
  ["--kubeconfig"] = true,
  ["--log-flush-frequency"] = true,
  ["--namespace"] = true,
  ["--password"] = true,
  ["--pod-running-timeout"] = true,
  ["--profile"] = true,
  ["--profile-output"] = true,
  ["--request-timeout"] = true,
  ["--selector"] = true,
  ["--server"] = true,
  ["--tls-server-name"] = true,
  ["--token"] = true,
  ["--user"] = true,
  ["--username"] = true,
  ["--v"] = true,
  ["--vmodule"] = true,
  ["-c"] = true,
  ["-f"] = true,
  ["-l"] = true,
  ["-n"] = true,
  ["-s"] = true,
  ["-v"] = true,
}

local kubernetes_global_stop_options = {
  ["--help"] = true,
  ["--version"] = true,
  ["-h"] = true,
}

local function kubernetes_short_option_has_flag(option, flag)
  if not option:match("^%-[^%-]") then
    return false
  end

  local flags = option:sub(2)
  for index = 1, #flags do
    local character = flags:sub(index, index)
    if character == flag then
      return true
    end
    if kubernetes_exec_options_with_value["-" .. character] then
      return false
    end
  end

  return false
end

local wrapper_options_with_value = {
  doas = {
    ["-a"] = true,
    ["-C"] = true,
    ["-u"] = true,
  },
  nice = {
    ["-n"] = true,
    ["--adjustment"] = true,
  },
  rlwrap = {
    ["-C"] = true,
    ["--command-name"] = true,
    ["-D"] = true,
    ["--history-no-dupes"] = true,
    ["-f"] = true,
    ["--file"] = true,
    ["-H"] = true,
    ["--history-filename"] = true,
    ["-p"] = true,
    ["--prompt-colour"] = true,
    ["-P"] = true,
    ["--pre-given"] = true,
    ["-s"] = true,
    ["--histsize"] = true,
  },
  gtime = {
    ["-f"] = true,
    ["--format"] = true,
    ["-o"] = true,
    ["--output"] = true,
  },
  stdbuf = {
    ["-e"] = true,
    ["--error"] = true,
    ["-i"] = true,
    ["--input"] = true,
    ["-o"] = true,
    ["--output"] = true,
  },
  sudo = {
    ["-C"] = true,
    ["-D"] = true,
    ["-g"] = true,
    ["-h"] = true,
    ["-p"] = true,
    ["-r"] = true,
    ["-t"] = true,
    ["-T"] = true,
    ["-u"] = true,
    ["--chdir"] = true,
    ["--close-from"] = true,
    ["--group"] = true,
    ["--host"] = true,
    ["--prompt"] = true,
    ["--role"] = true,
    ["--type"] = true,
    ["--user"] = true,
  },
  sshpass = {
    ["-d"] = true,
    ["-f"] = true,
    ["-p"] = true,
    ["-P"] = true,
  },
  time = {
    ["-f"] = true,
    ["--format"] = true,
    ["-o"] = true,
    ["--output"] = true,
  },
}

local function split_words(commandline)
  local words = {}
  local current = {}
  local quote = nil
  local escaped = false
  local in_word = false

  local function push_word()
    if in_word then
      table.insert(words, table.concat(current))
      current = {}
      in_word = false
    end
  end

  local index = 1
  while index <= #commandline do
    local character = commandline:sub(index, index)
    local next_character = commandline:sub(index + 1, index + 1)
    local previous_word_character = current[#current]

    if escaped then
      table.insert(current, character)
      in_word = true
      escaped = false
    elseif character == "\\" and quote ~= "'" then
      local current_text = table.concat(current)
      if current_text:match("^%a:") or current_text:match("^\\\\") then
        table.insert(current, character)
      elseif current_text == "" and next_character == "\\" then
        table.insert(current, "\\")
        table.insert(current, "\\")
        index = index + 1
      else
        escaped = true
      end
      in_word = true
    elseif quote then
      if character == quote then
        quote = nil
      else
        table.insert(current, character)
      end
      in_word = true
    elseif character == "'" or character == '"' then
      quote = character
      in_word = true
    elseif character:match("%s") then
      push_word()
    elseif character == ";" then
      push_word()
      table.insert(words, character)
    elseif character == "&" then
      if next_character == character then
        push_word()
        table.insert(words, character .. next_character)
        index = index + 1
      elseif next_character == ">" or previous_word_character == ">" or previous_word_character == "<" then
        table.insert(current, character)
        in_word = true
      else
        push_word()
        table.insert(words, character)
      end
    elseif character == "|" then
      push_word()
      if next_character == character then
        table.insert(words, character .. next_character)
        index = index + 1
      else
        table.insert(words, character)
      end
    else
      table.insert(current, character)
      in_word = true
    end

    index = index + 1
  end

  if escaped then
    table.insert(current, "\\")
  end

  push_word()

  return words
end

local function basename(command)
  local name = command:match("([^/\\]+)$") or command
  local stripped = name:gsub("%.[Ee][Xx][Ee]$", ""):gsub("%.[Cc][Mm][Dd]$", ""):gsub("%.[Bb][Aa][Tt]$", "")
  if stripped ~= name then
    if stripped == "R" or stripped == "r" then
      return "R"
    end
    return stripped:lower()
  end
  return stripped
end

local function option_without_value(option)
  return option:match("^([^=]+)=") or option
end

local function option_value(option)
  return option:match("^[^=]+=(.*)$")
end

local function option_value_is_false(option)
  local value = option_value(option)
  if not value then
    return false
  end

  value = value:lower()
  return value == "0" or value == "false" or value == "no"
end

local function option_has_short_flag(option, flag)
  return option:match("^%-[^%-]") and option:sub(2):find(flag, 1, true) ~= nil
end

local function insert_words(words, index, new_words)
  for offset = #new_words, 1, -1 do
    table.insert(words, index, new_words[offset])
  end
end

local function insert_command_string(words, index, command_string)
  if not (command_string and command_string ~= "") then
    return nil
  end

  local split = split_words(command_string)
  if #split == 0 then
    return nil
  end

  insert_words(words, index, split)
  return index
end

local function devcontainer_exec_command_index(words, index)
  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      break
    elseif devcontainer_options_with_value[key] and option == key then
      index = index + 1
    end
  end

  if words[index] then
    return index
  end

  return nil
end

local function skip_command_options(words, index, options_with_value)
  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      return index, true
    elseif options_with_value[key] and option == key then
      index = index + 1
    end
  end

  return index, false
end

local function poetry_run_command_index(words, index)
  index = index + 1
  if words[index] == "--" then
    index = index + 1
  end

  if words[index] then
    return index
  end

  return nil
end

local function pixi_run_command_index(words, index)
  index = index + 1

  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      break
    elseif pixi_run_stop_options[key] then
      return nil
    elseif pixi_run_options_with_value[key] and option == key then
      index = index + 1
    end
  end

  if words[index] then
    return index
  end

  return nil
end

local function pixi_command_index(words, index)
  index = index + 1

  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      break
    elseif pixi_global_stop_options[key] then
      return nil
    elseif pixi_global_options_with_value[key] and option == key then
      index = index + 1
    end
  end

  if words[index] == "run" then
    return pixi_run_command_index(words, index)
  end

  return nil
end

local function uv_run_command_index(words, index)
  index = index + 1

  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      break
    elseif option == "-m" or option == "--module" then
      return nil
    elseif uv_run_options_with_value[key] and option == key then
      index = index + 1
    end
  end

  if words[index] then
    return index
  end

  return nil
end

local function uv_tool_run_command_index(words, index)
  index = index + 1

  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      break
    elseif uv_tool_run_stop_options[key] then
      return nil
    elseif uv_tool_run_options_with_value[key] and option == key then
      index = index + 1
    end
  end

  if words[index] then
    return index
  end

  return nil
end

local package_executable_command_index

local function hatch_run_command_index(words, index)
  while words[index] do
    local word = words[index]
    if word == "--" then
      index = index + 1
      break
    end
    if not (word:match("^%+") or word:match("^%-")) then
      break
    end
    index = index + 1
  end

  local command_word = words[index]
  if not command_word then
    return nil
  end

  local command_name = command_word:match("^[^:]+:(.+)$")
  if command_name and command_name ~= "" then
    return insert_command_string(words, index + 1, command_name)
  end

  return index
end

local function hatch_command_index(words, index)
  index = index + 1
  index = skip_command_options(words, index, hatch_global_options_with_value)

  local subcommand = words[index]
  if subcommand == "run" then
    return hatch_run_command_index(words, index + 1)
  elseif subcommand == "env" and words[index + 1] == "run" then
    index = skip_command_options(words, index + 2, hatch_env_run_options_with_value)
    return hatch_run_command_index(words, index)
  end

  return nil
end

local function bundle_exec_command_index(words, index)
  index = index + 1
  if words[index] and words[index]:match("^_.*_$") then
    index = index + 1
  end

  if words[index] ~= "exec" then
    return nil
  end

  index = index + 1
  while words[index] and words[index]:match("^%-") do
    local word = words[index]
    index = index + 1
    if word == "--" then
      break
    end
  end

  if words[index] then
    return index
  end

  return nil
end

local function dev_wrapper_command_index(words, index, command)
  if command == "asdf" then
    if words[index + 1] == "exec" and words[index + 2] then
      return index + 2
    end
  elseif command == "bundle" or command == "bundler" then
    return bundle_exec_command_index(words, index)
  elseif command == "direnv" then
    if words[index + 1] == "exec" and words[index + 3] then
      index = index + 3
      if words[index] == "--" then
        index = index + 1
      end
      if words[index] then
        return index
      end
    end
  elseif command == "devcontainer" then
    if words[index + 1] == "exec" then
      return devcontainer_exec_command_index(words, index + 2)
    end
  elseif command == "hatch" then
    return hatch_command_index(words, index)
  elseif command == "mise" or command == "rtx" then
    local subcommand = words[index + 1]
    if subcommand == "exec" or subcommand == "x" then
      index = index + 2
      while words[index] do
        if words[index] == "--" and words[index + 1] then
          return index + 1
        end
        index = index + 1
      end
    end
  elseif command == "nix" then
    local subcommand = words[index + 1]
    if subcommand == "develop" or subcommand == "shell" then
      index = index + 2
      while words[index] do
        local word = words[index]
        local option = option_without_value(word)
        if option == "-c" or option == "--command" then
          local command_string = option_value(word)
          if command_string and command_string ~= "" then
            return insert_command_string(words, index + 1, command_string)
          end
          if not words[index + 1] then
            return nil
          end
          return index + 1
        end
        index = index + 1
      end
    elseif subcommand == "run" then
      index = index + 2
      while words[index] do
        if words[index] == "--" and words[index + 1] then
          return index + 1
        end
        index = index + 1
      end
    end
  elseif command == "poetry" then
    index = index + 1
    index = skip_command_options(words, index, poetry_global_options_with_value)
    if words[index] == "run" then
      return poetry_run_command_index(words, index)
    end
  elseif command == "pixi" then
    return pixi_command_index(words, index)
  elseif command == "pipenv" then
    index = index + 1
    index = skip_command_options(words, index, pipenv_global_options_with_value)
    if words[index] == "run" then
      return poetry_run_command_index(words, index)
    end
  elseif command == "pipx" then
    if words[index + 1] == "run" then
      return package_executable_command_index(words, index + 2, pipx_run_options_with_value)
    end
  elseif command == "uv" then
    index = index + 1
    index = skip_command_options(words, index, uv_global_options_with_value)
    if words[index] == "run" then
      return uv_run_command_index(words, index)
    elseif words[index] == "tool" then
      index = skip_command_options(words, index + 1, uv_global_options_with_value)
      if words[index] == "run" then
        return uv_tool_run_command_index(words, index)
      end
    end
  elseif command == "uvx" then
    return uv_tool_run_command_index(words, index)
  end

  return nil
end

local function npm_exec_command_index(words, index, command)
  if command == "npm" then
    local subcommand = words[index + 1]
    if subcommand ~= "exec" and subcommand ~= "x" then
      return nil
    end
    index = index + 2
  else
    index = index + 1
  end

  while words[index] do
    local word = words[index]
    local option = option_without_value(word)

    if word == "--" then
      if words[index + 1] then
        return index + 1
      end
      return nil
    elseif option == "-c" or option == "--call" then
      local command_string = option_value(word)
      index = index + 1
      if word == option then
        command_string = words[index]
        index = index + 1
      end
      return insert_command_string(words, index, command_string)
    elseif word:match("^%-") then
      index = index + 1
      if npm_exec_options_with_value[option] and word == option then
        index = index + 1
      end
    else
      return index
    end
  end

  return nil
end

package_executable_command_index = function(words, index, options_with_value)
  while words[index] and words[index]:match("^%-") do
    local word = words[index]
    local option = option_without_value(word)
    index = index + 1

    if word == "--" then
      break
    elseif options_with_value[option] and word == option then
      index = index + 1
    end
  end

  if words[index] then
    return index
  end

  return nil
end

local function bun_command_index(words, index)
  if words[index + 1] == "x" then
    return package_executable_command_index(words, index + 2, package_executable_options_with_value)
  end

  return nil
end

local function yarn_command_index(words, index)
  local subcommand = words[index + 1]

  if subcommand == "dlx" then
    return package_executable_command_index(words, index + 2, package_executable_options_with_value)
  elseif subcommand == "exec" then
    index = index + 2
    if words[index] then
      return insert_command_string(words, index + 1, words[index])
    end
  end

  return nil
end

local function pnpm_subcommand_command_index(words, index, options_with_value, shell_mode)
  while words[index] and words[index]:match("^%-") do
    local word = words[index]
    local option = option_without_value(word)
    index = index + 1

    if word == "--" then
      break
    elseif option == "-c" or option == "--shell-mode" then
      shell_mode = true
    elseif options_with_value[option] and word == option then
      index = index + 1
    end
  end

  if not words[index] then
    return nil
  end

  if shell_mode then
    return insert_command_string(words, index, words[index])
  end

  return index
end

local function pnpm_command_index(words, index)
  local subcommand = nil
  local shell_mode = false

  index = index + 1
  while words[index] do
    local word = words[index]
    local option = option_without_value(word)

    if word == "exec" or word == "dlx" then
      subcommand = word
      index = index + 1
      break
    end

    if not word:match("^%-") then
      return nil
    end

    index = index + 1
    if word == "--" then
      return nil
    elseif option == "-c" or option == "--shell-mode" then
      shell_mode = true
    elseif pnpm_global_options_with_value[option] and word == option then
      index = index + 1
    end
  end

  if not words[index] then
    return nil
  end

  if subcommand == "exec" then
    return pnpm_subcommand_command_index(words, index, pnpm_exec_options_with_value, shell_mode)
  elseif subcommand == "dlx" then
    return pnpm_subcommand_command_index(words, index, pnpm_dlx_options_with_value, shell_mode)
  end

  return nil
end

local function corepack_command_index(words, index)
  local manager = words[index + 1]
  if not manager or manager:match("^%-") then
    return nil
  end

  local manager_name = manager:match("^([^@]+)@") or manager
  if manager_name == "npm" or manager_name == "npx" then
    return npm_exec_command_index(words, index + 1, manager_name)
  elseif manager_name == "pnpm" then
    return pnpm_command_index(words, index + 1)
  elseif manager_name == "pnpx" or manager_name == "pnx" then
    return package_executable_command_index(words, index + 2, pnpm_dlx_options_with_value)
  elseif manager_name == "yarn" or manager_name == "yarnpkg" then
    return yarn_command_index(words, index + 1)
  end

  return nil
end

local function js_wrapper_command_index(words, index, command)
  if command == "bun" then
    return bun_command_index(words, index)
  elseif command == "bunx" then
    return package_executable_command_index(words, index + 1, package_executable_options_with_value)
  elseif command == "corepack" then
    return corepack_command_index(words, index)
  elseif command == "npm" or command == "npx" then
    return npm_exec_command_index(words, index, command)
  elseif command == "pnpm" then
    return pnpm_command_index(words, index)
  elseif command == "pnpx" or command == "pnx" then
    return package_executable_command_index(words, index + 1, pnpm_dlx_options_with_value)
  elseif command == "yarn" or command == "yarnpkg" then
    return yarn_command_index(words, index)
  end

  return nil
end

local compose_command_index

local function skip_kubernetes_global_options(words, index)
  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" or kubernetes_global_stop_options[key] then
      return nil
    elseif kubernetes_exec_options_with_value[key] and option == key then
      index = index + 1
    end
  end

  if words[index] then
    return index
  end

  return nil
end

local function kubernetes_attach_matches(words, index)
  local stdin = false
  local target = false

  while words[index] do
    local option = words[index]
    local key = option_without_value(option)

    if option == "--" then
      index = index + 1
    elseif option:match("^%-") then
      if
        key == "-i"
        or (key == "--stdin" and not option_value_is_false(option))
        or kubernetes_short_option_has_flag(option, "i")
      then
        stdin = true
      end

      index = index + 1
      if kubernetes_exec_options_with_value[key] and option == key then
        index = index + 1
      end
    else
      target = true
      index = index + 1
    end
  end

  return stdin and target
end

local function kubernetes_exec_command_index(words, index)
  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      if words[index] then
        return index
      end
      return nil
    elseif kubernetes_exec_options_with_value[key] and option == key then
      index = index + 1
    end
  end

  if not words[index] then
    return nil
  end
  index = index + 1

  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      break
    elseif kubernetes_exec_options_with_value[key] and option == key then
      index = index + 1
    end
  end

  if words[index] then
    return index
  end

  return nil
end

local function container_attach_matches(words, index)
  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)

    index = index + 1
    if option == "--" then
      break
    elseif key == "--no-stdin" then
      if not option_value_is_false(option) then
        return false
      end
    elseif key == "--detach-keys" and option == key then
      index = index + 1
    end
  end

  return words[index] ~= nil
end

local function container_start_matches(words, index)
  local attach = false
  local interactive = false

  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)

    index = index + 1
    if option == "--" then
      break
    end

    if
      key == "-a"
      or (key == "--attach" and not option_value_is_false(option))
      or option_has_short_flag(option, "a")
    then
      attach = true
    end
    if
      key == "-i"
      or (key == "--interactive" and not option_value_is_false(option))
      or option_has_short_flag(option, "i")
    then
      interactive = true
    end

    if (key == "--checkpoint" or key == "--checkpoint-dir" or key == "--detach-keys") and option == key then
      index = index + 1
    end
  end

  return attach and interactive and words[index] ~= nil
end

local function container_run_command_index(words, index)
  local entrypoint = nil

  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      break
    elseif key == "--entrypoint" then
      if option == key then
        entrypoint = words[index]
        index = index + 1
      else
        entrypoint = option_value(option)
      end
    elseif
      (
        key == "--add-host"
        or key == "--annotation"
        or key == "-a"
        or key == "--attach"
        or key == "--blkio-weight-device"
        or key == "--cap-add"
        or key == "--cap-drop"
        or key == "--cgroup-parent"
        or key == "--cidfile"
        or key == "--cpu-period"
        or key == "--cpu-quota"
        or key == "--cpu-rt-period"
        or key == "--cpu-rt-runtime"
        or key == "-c"
        or key == "--cpu-shares"
        or key == "--cpuset-cpus"
        or key == "--cpuset-mems"
        or key == "--device"
        or key == "--device-cgroup-rule"
        or key == "--device-read-bps"
        or key == "--device-read-iops"
        or key == "--device-write-bps"
        or key == "--device-write-iops"
        or key == "--dns"
        or key == "--dns-option"
        or key == "--dns-search"
        or key == "--domainname"
        or key == "-e"
        or key == "--env"
        or key == "--env-file"
        or key == "--expose"
        or key == "--gpus"
        or key == "--group-add"
        or key == "--health-cmd"
        or key == "--health-interval"
        or key == "--health-retries"
        or key == "--health-start-period"
        or key == "--health-timeout"
        or key == "-h"
        or key == "--hostname"
        or key == "--ip"
        or key == "--ip6"
        or key == "--ipc"
        or key == "--isolation"
        or key == "--kernel-memory"
        or key == "-l"
        or key == "--label"
        or key == "--label-file"
        or key == "--link"
        or key == "--log-driver"
        or key == "--log-opt"
        or key == "-m"
        or key == "--memory"
        or key == "--memory-reservation"
        or key == "--memory-swap"
        or key == "--memory-swappiness"
        or key == "--mount"
        or key == "--name"
        or key == "--network"
        or key == "--network-alias"
        or key == "--oom-score-adj"
        or key == "--pid"
        or key == "--platform"
        or key == "-p"
        or key == "--publish"
        or key == "--pull"
        or key == "--restart"
        or key == "--runtime"
        or key == "--security-opt"
        or key == "--shm-size"
        or key == "--stop-signal"
        or key == "--stop-timeout"
        or key == "--storage-opt"
        or key == "--sysctl"
        or key == "--tmpfs"
        or key == "--ulimit"
        or key == "-u"
        or key == "--user"
        or key == "--userns"
        or key == "-v"
        or key == "--volume"
        or key == "--volumes-from"
        or key == "-w"
        or key == "--workdir"
      ) and option == key
    then
      index = index + 1
    end
  end

  if words[index] then
    index = index + 1
    if words[index] == "--" then
      index = index + 1
    end
    if entrypoint and entrypoint ~= "" then
      insert_words(words, index, { entrypoint })
    end
    if words[index] then
      return index
    end
  end

  return nil
end

local function skip_container_global_options(words, index, command)
  local options_with_value = container_global_options_with_value[command] or {}

  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" or container_global_stop_options[key] then
      return nil
    elseif options_with_value[key] and option == key then
      index = index + 1
    end
  end

  if words[index] then
    return index
  end

  return nil
end

local function container_exec_command_index(words, index, command)
  if command == "docker" or command == "podman" then
    index = skip_container_global_options(words, index + 1, command)
    if not index then
      return nil
    end

    local subcommand = words[index]
    if words[index] == "container" and words[index + 1] == "attach" then
      if container_attach_matches(words, index + 2) then
        return "passthrough"
      end
      return nil
    elseif words[index] == "container" and words[index + 1] == "exec" then
      index = index + 2
    elseif words[index] == "container" and words[index + 1] == "start" then
      if container_start_matches(words, index + 2) then
        return "passthrough"
      end
      return nil
    elseif subcommand == "attach" then
      if container_attach_matches(words, index + 1) then
        return "passthrough"
      end
      return nil
    elseif subcommand == "exec" then
      index = index + 1
    elseif subcommand == "run" then
      return container_run_command_index(words, index + 1)
    elseif subcommand == "start" then
      if container_start_matches(words, index + 1) then
        return "passthrough"
      end
      return nil
    elseif subcommand == "compose" then
      return compose_command_index(words, index + 1)
    else
      return nil
    end

    while words[index] and words[index]:match("^%-") do
      local option = words[index]
      local key = option_without_value(option)
      index = index + 1

      if option == "--" then
        break
      elseif
        (
          key == "-e"
          or key == "--env"
          or key == "--env-file"
          or key == "-u"
          or key == "--user"
          or key == "-w"
          or key == "--workdir"
          or key == "--detach-keys"
        ) and option == key
      then
        index = index + 1
      end
    end

    if words[index] then
      index = index + 1
      if words[index] == "--" then
        index = index + 1
      end
      if words[index] then
        return index
      end
    end
  elseif command == "docker-compose" or command == "podman-compose" then
    return compose_command_index(words, index + 1)
  elseif command == "kubectl" or command == "oc" then
    index = skip_kubernetes_global_options(words, index + 1)
    if not index or words[index] ~= "exec" then
      if index and words[index] == "attach" and kubernetes_attach_matches(words, index + 1) then
        return "passthrough"
      end
      return nil
    end

    return kubernetes_exec_command_index(words, index + 1)
  end

  return nil
end

local function compose_exec_command_index(words, index)
  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      break
    elseif
      (
        key == "-e"
        or key == "--env"
        or key == "-u"
        or key == "--user"
        or key == "-w"
        or key == "--workdir"
        or key == "--index"
      ) and option == key
    then
      index = index + 1
    end
  end

  if words[index] then
    index = index + 1
    if words[index] == "--" then
      index = index + 1
    end
    if words[index] then
      return index
    end
  end

  return nil
end

local function compose_run_command_index(words, index)
  local entrypoint = nil

  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      break
    elseif key == "--entrypoint" then
      if option == key then
        entrypoint = words[index]
        index = index + 1
      else
        entrypoint = option_value(option)
      end
    elseif
      (
        key == "--add-host"
        or key == "--cap-add"
        or key == "--cap-drop"
        or key == "--dns"
        or key == "--dns-option"
        or key == "--dns-search"
        or key == "-e"
        or key == "--env"
        or key == "--env-from-file"
        or key == "--expose"
        or key == "-l"
        or key == "--label"
        or key == "--name"
        or key == "--network"
        or key == "-p"
        or key == "--publish"
        or key == "--pull"
        or key == "-u"
        or key == "--user"
        or key == "-v"
        or key == "--volume"
        or key == "-w"
        or key == "--workdir"
      ) and option == key
    then
      index = index + 1
    end
  end

  if words[index] then
    index = index + 1
    if words[index] == "--" then
      index = index + 1
    end
    if entrypoint and entrypoint ~= "" then
      insert_words(words, index, { entrypoint })
    end
    if words[index] then
      return index
    end
  end

  return nil
end

compose_command_index = function(words, index)
  local subcommand = nil

  while words[index] do
    local option = words[index]
    local key = option_without_value(option)

    if option == "exec" or option == "run" then
      subcommand = option
      index = index + 1
      break
    end

    if not option:match("^%-") then
      return nil
    end

    index = index + 1
    if option == "--" then
      return nil
    elseif
      (
        key == "-f"
        or key == "--file"
        or key == "-p"
        or key == "--project-name"
        or key == "--profile"
        or key == "--env-file"
        or key == "--project-directory"
        or key == "--ansi"
        or key == "--progress"
        or key == "--parallel"
      ) and option == key
    then
      index = index + 1
    end
  end

  if not words[index] then
    return nil
  end

  if subcommand == "exec" then
    return compose_exec_command_index(words, index)
  elseif subcommand == "run" then
    return compose_run_command_index(words, index)
  end

  return nil
end

local function is_assignment(word)
  return word:match("^[%a_][%w_]*=") ~= nil
end

local function sudo_short_option_takes_value(flag)
  return flag == "C"
    or flag == "D"
    or flag == "g"
    or flag == "h"
    or flag == "p"
    or flag == "r"
    or flag == "t"
    or flag == "T"
    or flag == "u"
end

local function sudo_short_option_consumes_next(option)
  if not option:match("^%-[^%-]") then
    return false
  end

  local flags = option:sub(2)
  for index = 1, #flags do
    local flag = flags:sub(index, index)
    if sudo_short_option_takes_value(flag) then
      return index == #flags
    end
  end

  return false
end

local function skip_wrapper_options(words, index, command)
  local options_with_value = wrapper_options_with_value[command] or {}

  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    local consumed_value = false

    index = index + 1
    if option == "--" then
      break
    elseif options_with_value[key] and option == key then
      index = index + 1
      consumed_value = true
    elseif command == "nice" and option:match("^%-%d+$") then
      -- nice accepts a compact priority like -10.
    end

    if command == "sudo" and not consumed_value and sudo_short_option_consumes_next(option) then
      index = index + 1
    end
  end

  return index
end

local script_options_with_value = {
  ["-B"] = true,
  ["--log-io"] = true,
  ["-I"] = true,
  ["--log-in"] = true,
  ["--log-incoming"] = true,
  ["-O"] = true,
  ["--log-out"] = true,
  ["--log-output"] = true,
  ["-T"] = true,
  ["--log-timing"] = true,
  ["-t"] = true,
  ["--timing"] = true,
  ["--logging-format"] = true,
}

local function script_command_index(words, index)
  index = index + 1

  while words[index] and words[index]:match("^%-") do
    local option = words[index]
    local key = option_without_value(option)
    index = index + 1

    if option == "--" then
      break
    elseif key == "-c" or key == "--command" then
      local command_string = option_value(option)
      if option == key then
        command_string = words[index]
        index = index + 1
      end
      if command_string and command_string ~= "" then
        insert_words(words, index, split_words(command_string))
        return index
      end
      return nil
    elseif script_options_with_value[key] and option == key then
      index = index + 1
    end
  end

  if words[index] and words[index + 1] then
    return index + 1
  end

  return nil
end

local function kitten_ssh_command(words, index)
  while words[index] and words[index]:match("^%-") do
    if words[index] == "--" then
      index = index + 1
      break
    end

    index = index + 1
  end

  local command = basename(words[index] or "")
  if command == "ssh" then
    return command
  end

  return nil
end

local function is_ssh_command(command)
  return command == "autossh" or command == "ssh"
end

local function ssh_option_takes_value(command, key)
  if
    key == "-b"
    or key == "-c"
    or key == "-D"
    or key == "-E"
    or key == "-e"
    or key == "-F"
    or key == "-I"
    or key == "-i"
    or key == "-J"
    or key == "-L"
    or key == "-l"
    or key == "-m"
    or key == "-O"
    or key == "-o"
    or key == "-p"
    or key == "-Q"
    or key == "-R"
    or key == "-S"
    or key == "-W"
    or key == "-w"
  then
    return true
  end

  return command == "autossh" and key == "-M"
end

local function ssh_short_word_has_flag(word, flag)
  if not word:match("^%-[^%-]") then
    return false
  end

  local flags = word:sub(2)
  for index = 1, #flags do
    local character = flags:sub(index, index)
    if character == flag then
      return true
    end
    if ssh_option_takes_value("ssh", "-" .. character) then
      break
    end
  end

  return false
end

local function ssh_noninteractive_option_matches(word, key)
  if
    key == "-f"
    or key == "-G"
    or key == "-N"
    or key == "-n"
    or key == "-O"
    or key == "-Q"
    or key == "-T"
    or key == "-V"
    or key == "-W"
    or key == "-h"
  then
    return true
  end

  for _, flag in ipairs({ "f", "G", "N", "n", "O", "Q", "T", "V", "W" }) do
    if ssh_short_word_has_flag(word, flag) then
      return true
    end
  end

  return false
end

local function ssh_passthrough_command(words, index, command)
  local has_args = false

  index = index + 1
  while words[index] do
    has_args = true
    local word = words[index]
    local key = option_without_value(word)

    if word == "--" then
      index = index + 1
      break
    elseif not word:match("^%-") then
      break
    elseif ssh_noninteractive_option_matches(word, key) then
      return nil
    end

    index = index + 1
    if ssh_option_takes_value(command, key) and word == key then
      index = index + 1
    end
  end

  if not has_args or words[index] then
    return command
  end

  return nil
end

local python_interactive_modules = {
  bpython = true,
  ipdb = true,
  ipython = true,
  pdb = true,
  ptpython = true,
  pudb = true,
}

local python_options_with_value = {
  ["-W"] = true,
  ["-X"] = true,
  ["--check-hash-based-pycs"] = true,
  ["--cpu-count"] = true,
  ["--presite"] = true,
}

local python_stop_options = {
  ["-h"] = true,
  ["--help"] = true,
  ["-V"] = true,
  ["--version"] = true,
}

local function is_python_command(command)
  return command == "python"
    or command == "pypy"
    or command:match("^python%d[%d%.]*$")
    or command:match("^pypy%d[%d%.]*$")
end

local function python_short_option_suffix(word, flag)
  if not word:match("^%-[^%-]") then
    return nil
  end

  local flags = word:sub(2)
  for index = 1, #flags do
    local character = flags:sub(index, index)
    if character == flag then
      return flags:sub(index + 1)
    end
    if character == "c" or character == "m" or character == "W" or character == "X" then
      break
    end
  end

  return nil
end

local function python_passthrough_command(words, index)
  local interactive = false

  index = index + 1
  while words[index] and words[index]:match("^%-") do
    local word = words[index]
    local option = option_without_value(word)

    if python_short_option_suffix(word, "i") ~= nil then
      interactive = true
    end

    if word == "--" then
      index = index + 1
      break
    elseif python_stop_options[option] then
      return nil
    elseif option == "-m" then
      local module
      if word == option then
        module = words[index + 1]
      else
        module = word:sub(3)
      end

      module = module and module:lower()
      if interactive then
        return "python"
      end
      if module and python_interactive_modules[module] then
        return module
      end
      return nil
    elseif option == "-c" then
      if interactive then
        return "python"
      end
      return nil
    end

    local module = python_short_option_suffix(word, "m")
    if module ~= nil then
      if module == "" then
        module = words[index + 1]
      end
      module = module and module:lower()
      if interactive then
        return "python"
      end
      if python_interactive_modules[module] then
        return module
      end
      return nil
    elseif python_short_option_suffix(word, "c") ~= nil then
      if interactive then
        return "python"
      end
      return nil
    end

    index = index + 1
    if python_options_with_value[option] and word == option then
      index = index + 1
    end
  end

  if interactive or not words[index] then
    return "python"
  end

  return nil
end

local node_options_with_value = {
  ["-C"] = true,
  ["--conditions"] = true,
  ["--diagnostic-dir"] = true,
  ["--experimental-loader"] = true,
  ["--heap-prof-dir"] = true,
  ["--import"] = true,
  ["--input-type"] = true,
  ["--loader"] = true,
  ["--require"] = true,
  ["-r"] = true,
  ["--title"] = true,
  ["--watch-path"] = true,
}

local node_stop_options = {
  ["-h"] = true,
  ["--help"] = true,
  ["-v"] = true,
  ["--version"] = true,
  ["-c"] = true,
  ["--check"] = true,
  ["--test"] = true,
}

local node_eval_options = {
  ["-e"] = true,
  ["--eval"] = true,
  ["-p"] = true,
  ["--print"] = true,
}

local function is_node_command(command)
  return command == "node" or command == "nodejs"
end

local function is_deno_command(command)
  return command == "deno"
end

local function is_bun_command(command)
  return command == "bun"
end

local function is_php_command(command)
  return command == "php"
end

local function node_short_option_suffix(word, flag)
  if not word:match("^%-[^%-]") then
    return nil
  end

  local flags = word:sub(2)
  for index = 1, #flags do
    local character = flags:sub(index, index)
    if character == flag then
      return flags:sub(index + 1)
    end
    if character == "C" or character == "e" or character == "p" or character == "r" then
      break
    end
  end

  return nil
end

local function node_passthrough_command(words, index)
  local interactive = false
  local after_separator = false

  index = index + 1
  while words[index] and words[index]:match("^%-") do
    local word = words[index]
    local option = option_without_value(word)

    if node_short_option_suffix(word, "i") ~= nil or option == "--interactive" then
      interactive = true
    end

    if word == "--" then
      after_separator = true
      index = index + 1
      break
    elseif node_stop_options[option] or node_eval_options[option] then
      if interactive then
        return "node"
      end
      return nil
    elseif node_short_option_suffix(word, "e") ~= nil or node_short_option_suffix(word, "p") ~= nil then
      if interactive then
        return "node"
      end
      return nil
    end

    index = index + 1
    if node_options_with_value[option] and word == option then
      index = index + 1
    end
  end

  if not after_separator and words[index] == "inspect" then
    return "node"
  end

  if interactive or not words[index] then
    return "node"
  end

  return nil
end

local deno_options_with_value = {
  ["-c"] = true,
  ["--config"] = true,
  ["--import-map"] = true,
  ["--cert"] = true,
  ["--location"] = true,
  ["--v8-flags"] = true,
  ["--env-file"] = true,
  ["--node-modules-dir"] = true,
}

local deno_one_shot_options = {
  ["-h"] = true,
  ["--help"] = true,
  ["-V"] = true,
  ["--version"] = true,
}

local function deno_passthrough_command(words, index)
  index = index + 1
  while words[index] and words[index]:match("^%-") do
    local word = words[index]
    local option = option_without_value(word)

    if option == "--" or deno_one_shot_options[option] then
      return nil
    end

    index = index + 1
    if deno_options_with_value[option] and word == option then
      index = index + 1
    end
  end

  local subcommand = words[index]
  if subcommand == nil or subcommand == "repl" then
    return "deno"
  end

  return nil
end

local function bun_passthrough_command(words, index)
  if words[index + 1] == "repl" then
    return "bun-repl"
  end

  return nil
end

local php_options_with_value = {
  ["-c"] = true,
  ["--php-ini"] = true,
  ["-d"] = true,
  ["--define"] = true,
}

local function php_passthrough_command(words, index)
  index = index + 1
  while words[index] and words[index]:match("^%-") do
    local word = words[index]
    local option = option_without_value(word)

    if option == "--" then
      return nil
    elseif option == "-a" or option == "--interactive" then
      return "php-repl"
    elseif
      option == "-r"
      or option == "-B"
      or option == "-R"
      or option == "-E"
      or option == "-F"
      or option == "--run"
      or option == "--process-begin"
      or option == "--process-code"
      or option == "--process-end"
      or option == "--file"
    then
      return nil
    end

    index = index + 1
    if php_options_with_value[option] and word == option then
      index = index + 1
    end
  end

  return nil
end

local ruby_options_with_value = {
  ["-C"] = true,
  ["-E"] = true,
  ["-I"] = true,
  ["-r"] = true,
  ["-T"] = true,
  ["-W"] = true,
  ["--disable"] = true,
  ["--enable"] = true,
  ["--encoding"] = true,
  ["--external-encoding"] = true,
  ["--internal-encoding"] = true,
  ["--jit-warnings"] = true,
  ["--mjit-max-cache"] = true,
  ["--mjit-min-calls"] = true,
  ["--mjit-verbose"] = true,
  ["--mjit-warnings"] = true,
  ["--require"] = true,
  ["--yjit-call-threshold"] = true,
  ["--yjit-exec-mem-size"] = true,
}

local ruby_one_shot_options = {
  ["-c"] = true,
  ["-e"] = true,
  ["-h"] = true,
  ["--help"] = true,
  ["-v"] = true,
  ["--version"] = true,
}

local rails_options_with_value = {
  ["-e"] = true,
  ["--environment"] = true,
}

local rails_one_shot_options = {
  ["-h"] = true,
  ["--help"] = true,
  ["-v"] = true,
  ["--version"] = true,
}

local function is_ruby_command(command)
  return command == "ruby" or command:match("^ruby%d[%d%.]*$") ~= nil
end

local function is_rails_command(command)
  return command == "rails"
end

local function rails_passthrough_from(words, index)
  while words[index] and words[index]:match("^%-") do
    local word = words[index]
    local option = option_without_value(word)

    if rails_one_shot_options[option] then
      return nil
    end

    index = index + 1
    if rails_options_with_value[option] and word == option then
      index = index + 1
    end
  end

  local subcommand = words[index]
  if subcommand ~= "c" and subcommand ~= "console" and subcommand ~= "db" and subcommand ~= "dbconsole" then
    return nil
  end

  index = index + 1
  while words[index] do
    local option = option_without_value(words[index])
    if rails_one_shot_options[option] then
      return nil
    end
    index = index + 1
  end

  return "rails-console"
end

local function rails_passthrough_command(words, index)
  return rails_passthrough_from(words, index + 1)
end

local function ruby_script_passthrough(script, words, index)
  local script_name = basename(script)
  if script_name == "irb" or script_name == "pry" or script_name == "rdbg" then
    return "ruby-repl"
  elseif script_name == "rails" then
    return rails_passthrough_from(words, index)
  end

  return nil
end

local function ruby_passthrough_command(words, index)
  index = index + 1
  while words[index] and words[index]:match("^%-") do
    local word = words[index]
    local option = option_without_value(word)

    if word == "--" then
      index = index + 1
      break
    elseif option == "-S" then
      local script
      if word == option then
        script = words[index + 1]
        index = index + 2
      else
        script = word:sub(3)
        index = index + 1
      end

      if not (script and script ~= "") then
        return nil
      end
      return ruby_script_passthrough(script, words, index)
    elseif ruby_one_shot_options[option] or word:match("^%-e.") then
      return nil
    end

    index = index + 1
    if ruby_options_with_value[option] and word == option then
      index = index + 1
    end
  end

  local script = words[index]
  if not script then
    return nil
  end

  return ruby_script_passthrough(script, words, index + 1)
end

local database_options_with_value = {
  duckdb = {
    ["-init"] = true,
    ["--init"] = true,
  },
  mariadb = {
    ["-D"] = true,
    ["--database"] = true,
    ["-h"] = true,
    ["--host"] = true,
    ["-P"] = true,
    ["--port"] = true,
    ["-S"] = true,
    ["--socket"] = true,
    ["-u"] = true,
    ["--user"] = true,
  },
  mysql = {
    ["-D"] = true,
    ["--database"] = true,
    ["-h"] = true,
    ["--host"] = true,
    ["-P"] = true,
    ["--port"] = true,
    ["-S"] = true,
    ["--socket"] = true,
    ["-u"] = true,
    ["--user"] = true,
  },
  psql = {
    ["-d"] = true,
    ["--dbname"] = true,
    ["-h"] = true,
    ["--host"] = true,
    ["-p"] = true,
    ["--port"] = true,
    ["-U"] = true,
    ["--username"] = true,
    ["-v"] = true,
    ["--set"] = true,
    ["--variable"] = true,
    ["-P"] = true,
    ["--pset"] = true,
    ["-F"] = true,
    ["--field-separator"] = true,
    ["-R"] = true,
    ["--record-separator"] = true,
    ["-T"] = true,
    ["--table-attr"] = true,
  },
  ["redis-cli"] = {
    ["-a"] = true,
    ["--pass"] = true,
    ["-h"] = true,
    ["--hostname"] = true,
    ["-i"] = true,
    ["--interval"] = true,
    ["-n"] = true,
    ["--db"] = true,
    ["-p"] = true,
    ["--port"] = true,
    ["-r"] = true,
    ["--repeat"] = true,
    ["-s"] = true,
    ["--socket"] = true,
    ["-u"] = true,
    ["--user"] = true,
    ["-U"] = true,
    ["--uri"] = true,
  },
  sqlite3 = {
    ["-cmd"] = true,
    ["-init"] = true,
    ["-newline"] = true,
    ["-separator"] = true,
  },
}

local database_one_shot_options = {
  duckdb = {
    ["-c"] = true,
    ["--command"] = true,
    ["-help"] = true,
    ["--help"] = true,
    ["-version"] = true,
    ["--version"] = true,
  },
  mariadb = {
    ["-e"] = true,
    ["--execute"] = true,
    ["-?"] = true,
    ["--help"] = true,
    ["-V"] = true,
    ["--version"] = true,
  },
  mysql = {
    ["-e"] = true,
    ["--execute"] = true,
    ["-?"] = true,
    ["--help"] = true,
    ["-V"] = true,
    ["--version"] = true,
  },
  psql = {
    ["-c"] = true,
    ["--command"] = true,
    ["-f"] = true,
    ["--file"] = true,
    ["-l"] = true,
    ["--list"] = true,
    ["-?"] = true,
    ["--help"] = true,
    ["-V"] = true,
    ["--version"] = true,
  },
  ["redis-cli"] = {
    ["--help"] = true,
    ["-v"] = true,
    ["--version"] = true,
  },
  sqlite3 = {
    ["-help"] = true,
    ["--help"] = true,
    ["-version"] = true,
    ["--version"] = true,
  },
}

local database_shell_commands = {
  duckdb = true,
  mariadb = true,
  mysql = true,
  psql = true,
  ["redis-cli"] = true,
  sqlite3 = true,
}

local function database_one_shot_option_matches(command, word, option)
  local one_shot_options = database_one_shot_options[command] or {}
  if one_shot_options[option] then
    return true
  end

  return (command == "duckdb" and word:match("^%-c.") ~= nil)
    or (command == "mysql" and word:match("^%-e.") ~= nil)
    or (command == "mariadb" and word:match("^%-e.") ~= nil)
    or (command == "psql" and (word:match("^%-c.") ~= nil or word:match("^%-f.") ~= nil))
end

local function database_shell_command(words, index, command)
  local positionals = 0
  local options_with_value = database_options_with_value[command] or {}

  index = index + 1
  while words[index] do
    local word = words[index]
    local option = option_without_value(word)

    if word == "--" then
      index = index + 1
    elseif word:match("^%-") then
      if database_one_shot_option_matches(command, word, option) then
        return nil
      end

      index = index + 1
      if options_with_value[option] and word == option then
        index = index + 1
      end
    else
      if command == "redis-cli" then
        return nil
      elseif command == "duckdb" or command == "sqlite3" then
        positionals = positionals + 1
        if positionals > 1 then
          return nil
        end
      end

      index = index + 1
    end
  end

  return "database-shell"
end

local language_repl_options_with_value = {
  julia = {
    ["-L"] = true,
    ["--load"] = true,
    ["--project"] = true,
    ["--sysimage"] = true,
    ["-J"] = true,
    ["--threads"] = true,
    ["-t"] = true,
  },
  lua = {
    ["-l"] = true,
  },
  luajit = {
    ["-l"] = true,
  },
}

local language_repl_one_shot_options = {
  R = {
    ["-e"] = true,
    ["--file"] = true,
    ["-f"] = true,
    ["--help"] = true,
    ["-h"] = true,
    ["--version"] = true,
    ["--slave"] = true,
  },
  julia = {
    ["-e"] = true,
    ["--eval"] = true,
    ["-E"] = true,
    ["--print"] = true,
    ["-h"] = true,
    ["--help"] = true,
    ["-v"] = true,
    ["--version"] = true,
  },
  lua = {
    ["-e"] = true,
  },
  luajit = {
    ["-e"] = true,
  },
}

local language_repl_commands = {
  R = true,
  julia = true,
  lua = true,
  luajit = true,
}

local function language_repl_one_shot_option_matches(command, word, option)
  local one_shot_options = language_repl_one_shot_options[command] or {}
  if one_shot_options[option] then
    return true
  end

  return (command == "lua" and word:match("^%-e.") ~= nil)
    or (command == "luajit" and word:match("^%-e.") ~= nil)
    or (command == "julia" and (word:match("^%-e.") ~= nil or word:match("^%-E.") ~= nil))
    or (command == "R" and (word:match("^%-e.") ~= nil or word:match("^%-f.") ~= nil))
end

local function language_repl_command(words, index, command)
  local interactive = false
  local options_with_value = language_repl_options_with_value[command] or {}

  index = index + 1
  while words[index] and words[index]:match("^%-") do
    local word = words[index]
    local option = option_without_value(word)

    if word == "--" then
      index = index + 1
      break
    end

    if option == "-i" or option == "--interactive" then
      interactive = true
    end

    if language_repl_one_shot_option_matches(command, word, option) then
      if interactive then
        return "language-repl"
      end
      return nil
    end

    index = index + 1
    if options_with_value[option] and word == option then
      index = index + 1
    end
  end

  if command == "R" and words[index] == "CMD" then
    return nil
  end

  if interactive or not words[index] then
    return "language-repl"
  end

  return nil
end

local function skip_shell_command(words, index)
  while index <= #words and not shell_control_operators[words[index]] do
    index = index + 1
  end

  return index
end

local function skip_control_operators(words, index)
  while index <= #words and shell_control_operators[words[index]] do
    index = index + 1
  end

  return index
end

local function next_shell_command(words, index)
  index = skip_shell_command(words, index)

  local operator = words[index]
  index = skip_control_operators(words, index)

  if operator == "||" and shell_failure_handler_commands[basename(words[index] or "")] then
    index = skip_shell_command(words, index + 1)
    index = skip_control_operators(words, index)
  end

  return index
end

local function expand_shell_command(words, index, command)
  while index <= #words and words[index]:match("^%-") do
    local word = words[index]
    local option = option_without_value(word)
    local option_lower = option:lower()
    local command_string = nil

    if word == "--" then
      return nil
    elseif option == "-c" or option_lower == "-command" or option_lower == "--command" then
      command_string = option_value(word)
      if word == option then
        command_string = words[index + 1]
        index = index + 2
      else
        index = index + 1
      end
    elseif shell_short_option_cluster_commands[command] and option_has_short_flag(word, "c") then
      command_string = words[index + 1]
      index = index + 2
    else
      index = index + 1
    end

    if command_string then
      if command_string ~= "" then
        insert_words(words, index, split_words(command_string))
        return index
      end
      return nil
    end
  end

  return nil
end

local function windows_cmd_command_index(words, index)
  while index <= #words do
    local option = words[index]:lower()

    if option == "/c" or option == "/k" then
      local command_index = index + 1
      if words[command_index] then
        local split = split_words(words[command_index])
        if #split > 1 then
          insert_words(words, command_index, split)
        end
        return command_index
      end
      return nil
    elseif
      option == "/d"
      or option == "/q"
      or option == "/s"
      or option == "/a"
      or option == "/u"
      or option:match("^/[efv]:") ~= nil
    then
      index = index + 1
    else
      return nil
    end
  end

  return nil
end

local function command_from_line(commandline)
  local words = split_words(commandline)
  local index = 1

  while index <= #words do
    local word = words[index]
    local command = basename(word)
    if shell_control_operators[word] or is_assignment(word) then
      index = index + 1
    elseif shell_setup_commands[command] then
      index = next_shell_command(words, index + 1)
    elseif command == "cmd" then
      local cmd_command_index = windows_cmd_command_index(words, index + 1)
      if not cmd_command_index then
        return command
      end
      index = cmd_command_index
    elseif shell_commands[command] then
      local shell_command_index = expand_shell_command(words, index + 1, command)
      if not shell_command_index then
        return command
      end
      index = shell_command_index
    elseif is_python_command(command) then
      return python_passthrough_command(words, index) or ""
    elseif is_node_command(command) then
      return node_passthrough_command(words, index) or ""
    elseif is_deno_command(command) then
      return deno_passthrough_command(words, index) or ""
    elseif is_bun_command(command) and bun_passthrough_command(words, index) then
      return "bun-repl"
    elseif is_php_command(command) then
      return php_passthrough_command(words, index) or ""
    elseif is_ruby_command(command) then
      return ruby_passthrough_command(words, index) or ""
    elseif is_rails_command(command) then
      return rails_passthrough_command(words, index) or ""
    elseif database_shell_commands[command] then
      return database_shell_command(words, index, command) or ""
    elseif language_repl_commands[command] then
      return language_repl_command(words, index, command) or ""
    elseif command == "kitten" then
      return kitten_ssh_command(words, index + 1) or command
    elseif command == "kitty" and words[index + 1] == "+kitten" then
      return kitten_ssh_command(words, index + 2) or command
    elseif is_ssh_command(command) then
      return ssh_passthrough_command(words, index, command) or ""
    elseif command == "script" then
      local script_index = script_command_index(words, index)
      if not script_index then
        return command
      end
      index = script_index
    else
      local container_command_index = container_exec_command_index(words, index, command)
      local js_command_index = js_wrapper_command_index(words, index, command)
      local wrapper_command_index = dev_wrapper_command_index(words, index, command)
      if container_command_index then
        if container_command_index == "passthrough" then
          return "passthrough"
        end
        index = container_command_index
      elseif js_command_index then
        index = js_command_index
      elseif wrapper_command_index then
        index = wrapper_command_index
      elseif not wrapper_commands[command] then
        return command
      else
        index = index + 1
        if command == "env" then
          while index <= #words do
            local word = words[index]
            local option = option_without_value(word)
            if word == "--" then
              index = index + 1
              break
            elseif env_split_string_options[option] then
              local split_string = option_value(word)
              if word == option then
                split_string = words[index + 1]
                index = index + 2
              else
                index = index + 1
              end

              if split_string and split_string ~= "" then
                insert_words(words, index, split_words(split_string))
              end
            elseif env_options_with_value[option] and word == option then
              index = index + 2
            elseif word:match("^%-") or word:match("^[%a_][%w_]*=") then
              index = index + 1
            else
              break
            end
          end
        else
          index = skip_wrapper_options(words, index, command)
        end
      end
    end
  end

  return ""
end

local function terminal_command()
  local name = vim.api.nvim_buf_get_name(0)
  local commandline = name:match("^term://.-//%d+:%s*(.+)$")
  if not commandline then
    return ""
  end

  return command_from_line(commandline)
end

local function command_should_passthrough(command)
  return command == "python"
    or command == "node"
    or command == "deno"
    or command == "bun-repl"
    or command == "php-repl"
    or command == "ruby-repl"
    or command == "rails-console"
    or command == "database-shell"
    or command == "language-repl"
    or command == "passthrough"
    or passthrough_commands[command] == true
end

local function terminal_job_pid()
  if type(vim.b.terminal_job_pid) == "number" and vim.b.terminal_job_pid > 0 then
    return vim.b.terminal_job_pid
  end

  if type(vim.b.terminal_job_id) == "number" and vim.b.terminal_job_id > 0 then
    local ok, pid = pcall(vim.fn.jobpid, vim.b.terminal_job_id)
    if ok and type(pid) == "number" and pid > 0 then
      return pid
    end
  end

  return nil
end

local function process_table_output()
  if vim.env.DOTFILES_NVIM_TEST_PS_OUTPUT and vim.env.DOTFILES_NVIM_TEST_PS_OUTPUT ~= "" then
    return vim.env.DOTFILES_NVIM_TEST_PS_OUTPUT
  end

  if vim.fn.executable("ps") ~= 1 then
    return ""
  end

  local ok, output = pcall(vim.fn.system, { "ps", "-axo", "pid=,ppid=,state=,command=" })
  if not ok or type(output) ~= "string" then
    return ""
  end

  return output
end

local function active_process_state(state)
  return state ~= nil and state ~= "" and state:match("[TXZ]") == nil
end

local function terminal_foreground_command()
  local root_pid = terminal_job_pid()
  if not root_pid then
    return ""
  end

  local children = {}
  for line in process_table_output():gmatch("[^\r\n]+") do
    local pid, ppid, state, commandline = line:match("^%s*(%d+)%s+(%d+)%s+(%S+)%s+(.+)$")
    pid = tonumber(pid)
    ppid = tonumber(ppid)
    if pid and ppid and commandline and active_process_state(state) then
      local process = {
        pid = pid,
        ppid = ppid,
        state = state,
        commandline = commandline,
      }
      children[ppid] = children[ppid] or {}
      table.insert(children[ppid], process)
    end
  end

  local descendants = {}
  local function visit(parent_pid, depth)
    for _, child in ipairs(children[parent_pid] or {}) do
      child.depth = depth
      table.insert(descendants, child)
      visit(child.pid, depth + 1)
    end
  end
  visit(root_pid, 1)

  if #descendants == 0 then
    return ""
  end

  local has_foreground = false
  for _, process in ipairs(descendants) do
    if process.state:find("+", 1, true) then
      has_foreground = true
      break
    end
  end

  table.sort(descendants, function(left, right)
    if left.depth == right.depth then
      return left.pid > right.pid
    end
    return left.depth > right.depth
  end)

  for _, process in ipairs(descendants) do
    if (not has_foreground or process.state:find("+", 1, true)) and process.pid ~= root_pid then
      local command = command_from_line(process.commandline)
      if command_should_passthrough(command) then
        return command
      end
    end
  end

  return ""
end

local function terminal_should_passthrough()
  local filetype = vim.bo.filetype
  if filetype:match("^fzf") or filetype == "lazygit" then
    return true
  end

  return command_should_passthrough(terminal_command()) or command_should_passthrough(terminal_foreground_command())
end

local function terminal_nav(command, passthrough)
  return function()
    return terminal_should_passthrough() and passthrough or "<C-\\><C-n><cmd>" .. command .. "<cr>"
  end
end

return {
  {
    "christoomey/vim-tmux-navigator",
    init = function()
      vim.g.tmux_navigator_no_mappings = 1
    end,
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
    },
    keys = {
      { "<C-h>", "<cmd><C-U>TmuxNavigateLeft<cr>", mode = "n", desc = "Navigate left" },
      { "<C-j>", "<cmd><C-U>TmuxNavigateDown<cr>", mode = "n", desc = "Navigate down" },
      { "<C-k>", "<cmd><C-U>TmuxNavigateUp<cr>", mode = "n", desc = "Navigate up" },
      { "<C-l>", "<cmd><C-U>TmuxNavigateRight<cr>", mode = "n", desc = "Navigate right" },
      { "<C-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>", mode = "n", desc = "Navigate previous" },
      {
        "<C-h>",
        terminal_nav("TmuxNavigateLeft", "<C-h>"),
        mode = "t",
        expr = true,
        replace_keycodes = true,
        desc = "Navigate left",
      },
      {
        "<C-j>",
        terminal_nav("TmuxNavigateDown", "<C-j>"),
        mode = "t",
        expr = true,
        replace_keycodes = true,
        desc = "Navigate down",
      },
      {
        "<C-k>",
        terminal_nav("TmuxNavigateUp", "<C-k>"),
        mode = "t",
        expr = true,
        replace_keycodes = true,
        desc = "Navigate up",
      },
      {
        "<C-l>",
        terminal_nav("TmuxNavigateRight", "<C-l>"),
        mode = "t",
        expr = true,
        replace_keycodes = true,
        desc = "Navigate right",
      },
      {
        "<C-\\>",
        terminal_nav("TmuxNavigatePrevious", "<C-\\>"),
        mode = "t",
        expr = true,
        replace_keycodes = true,
        desc = "Navigate previous",
      },
    },
  },
}
