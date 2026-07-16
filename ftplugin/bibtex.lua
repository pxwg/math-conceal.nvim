local bufnr = vim.api.nvim_get_current_buf()
vim.schedule(function()
  require("math-conceal").set(nil, bufnr)
end)
