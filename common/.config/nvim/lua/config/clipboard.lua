local M = {}

local last_copy = {
  text = nil,
  regtype = nil,
}

local function copy_text(lines, regtype)
  local text = table.concat(lines, "\n")

  if regtype == "V" then
    text = text .. "\n"
  end

  last_copy.text = text
  last_copy.regtype = regtype

  return text
end

local function paste_lines(text, regtype)
  local lines = vim.split(text, "\n", { plain = true })

  if regtype == "V" and lines[#lines] == "" then
    table.remove(lines)
  end

  if #lines == 0 then
    lines = { "" }
  end

  return { lines, regtype }
end

local function system_copy(command, lines, regtype)
  local text = copy_text(lines, regtype)
  vim.fn.system(command, text)
end

local function system_paste(command)
  local text = vim.fn.system(command)
  local regtype = "v"

  if text == last_copy.text and last_copy.regtype then
    regtype = last_copy.regtype
  end

  return paste_lines(text, regtype)
end

function M.provider(name, copy_command, paste_command)
  return {
    name = name,
    copy = {
      ["+"] = function(lines, regtype)
        system_copy(copy_command, lines, regtype)
      end,
      ["*"] = function(lines, regtype)
        system_copy(copy_command, lines, regtype)
      end,
    },
    paste = {
      ["+"] = function()
        return system_paste(paste_command)
      end,
      ["*"] = function()
        return system_paste(paste_command)
      end,
    },
    cache_enabled = 0,
  }
end

return M
