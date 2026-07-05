local M = {}

function M.parse_args(value, opts)
  opts = opts or {}
  value = value or ""

  local should_expand = opts.expand ~= false
  local should_notify = opts.notify ~= false
  local args = {}
  local current = {}
  local quote = nil
  local escaped = nil
  local token_started = false

  local function is_double_quote_escape_char(char)
    return char == '"' or char == "\\" or char == "$" or char == "`"
  end

  local function append(text, expandable)
    if text == "" then
      return
    end

    local last = current[#current]
    if last and last.expandable == expandable then
      last.text = last.text .. text
    else
      table.insert(current, { text = text, expandable = expandable })
    end
  end

  local function expand_text(text)
    text = text:gsub("%${([%a_][%w_]*)}", function(name)
      return vim.env[name] or ""
    end)
    text = text:gsub("%$([%a_][%w_]*)", function(name)
      return vim.env[name] or ""
    end)

    local home = vim.env.HOME
    if home and home ~= "" then
      if text == "~" then
        return home
      elseif text:sub(1, 2) == "~/" or text:sub(1, 2) == "~\\" then
        return home .. text:sub(2)
      end
    end

    return text
  end

  local function push_current()
    local token = ""
    if should_expand then
      for _, part in ipairs(current) do
        if part.expandable then
          token = token .. expand_text(part.text)
        else
          token = token .. part.text
        end
      end
    else
      for _, part in ipairs(current) do
        token = token .. part.text
      end
    end
    table.insert(args, token)
    current = {}
    token_started = false
  end

  for _, char in ipairs(vim.fn.split(value, [[\zs]])) do
    if escaped then
      if escaped == "double" and not is_double_quote_escape_char(char) then
        append("\\", false)
        append(char, true)
      else
        append(char, false)
      end
      token_started = true
      escaped = nil
    elseif quote then
      if char == quote then
        quote = nil
      elseif quote == '"' and char == "\\" then
        escaped = "double"
      else
        append(char, quote ~= "'")
      end
      token_started = true
    elseif char == "\\" then
      escaped = "outside"
      token_started = true
    elseif char == "'" or char == '"' then
      quote = char
      token_started = true
    elseif char:match("%s") then
      if token_started then
        push_current()
      end
    else
      append(char, true)
      token_started = true
    end
  end

  if escaped then
    append("\\", false)
  end

  if quote and should_notify then
    vim.notify("Unclosed quote in debug args", vim.log.levels.WARN)
  end

  if token_started or #current > 0 then
    push_current()
  end

  return args
end

return M
