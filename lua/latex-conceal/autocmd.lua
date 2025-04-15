local M = {}
local autocmd = vim.api.nvim_create_autocmd
local ts_query = require("treesitter_query")

--- @param opts LaTeXConcealOptions
local function subscribe_autocmd(opts)
  if not opts.enabled then
    return
  end
  local ft = opts.ft
  autocmd("FileType", {
    pattern = ft,
    callback = function()
      vim.opt_local.conceallevel = 2
      ts_query.load_queries(opts)
    end,
  })
end

M.subscribe_autocmd = subscribe_autocmd

return M
