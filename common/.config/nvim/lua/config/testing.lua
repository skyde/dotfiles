local M = {}

function M.cpp_test_file(path)
  local filename = vim.fs.basename(path):lower()
  local extension = filename:match("%.([^%.]+)$")
  if not vim.tbl_contains({ "cc", "cpp", "cxx" }, extension) then
    return false
  end

  -- Covers Google/Chromium-style *_unittest.cc and *_browsertest.cc as
  -- well as the adapter's default *_test.cpp convention.
  local stem = filename:gsub("%.[^%.]+$", "")
  return stem:match("^test[_%-]") ~= nil
    or stem:match("[_%-]test$") ~= nil
    or stem:match("[_%-]unittest$") ~= nil
    or stem:match("[_%-]browsertest$") ~= nil
end

return M
