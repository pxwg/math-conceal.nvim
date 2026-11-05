-- Optional headless entry point; interactive users can call the Lua function directly.
local script = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p")
local root = vim.fs.dirname(vim.fs.dirname(script))
local installer = dofile(root .. "/lua/math-conceal/install.lua")
local ok, err = pcall(installer.install, { root = root, wait = true })
if not ok then
  io.stderr:write(tostring(err) .. "\n")
  vim.cmd("cquit")
end
