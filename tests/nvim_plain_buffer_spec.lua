-- Run with an ordinary file argument and the installed full config:
-- nvim --headless -i NONE /etc/hosts -c 'luafile tests/nvim_plain_buffer_spec.lua' +qa

local lazy_config = require("lazy.core.config")
for _, name in ipairs({ "neotest", "rustaceanvim" }) do
	local plugin = assert(lazy_config.plugins[name], "missing plugin spec: " .. name)
	assert(plugin._.loaded == nil, name .. " loaded for an unrelated plain-text buffer")
end
assert(package.loaded.neotest == nil, "Neotest module loaded for a plain-text buffer")
assert(package.loaded.rustaceanvim == nil, "Rustaceanvim loaded for a plain-text buffer")

print("nvim plain-buffer lazy-loading tests passed")
