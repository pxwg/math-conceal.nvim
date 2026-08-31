local bufnr = vim.api.nvim_get_current_buf()
vim.schedule(function()
  require("math-conceal.nvim").set(nil, bufnr)
end)
