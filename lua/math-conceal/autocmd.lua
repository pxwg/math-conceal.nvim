local M = {}
local autocmd = vim.api.nvim_create_autocmd
local ts_query = require("treesitter_query")

-- Track if queries have been loaded to avoid repeated loading
local queries_loaded = false

--- @param opts LaTeXConcealOptions
local function subscribe_autocmd(opts)
  if not opts.enabled then
    return
  end
  
  -- Load queries once during setup, not on every buffer event
  if not queries_loaded then
    ts_query.load_queries(opts)
    queries_loaded = true
  end
  
  local ft = opts.ft
  autocmd({ "BufEnter", "BufReadPre" }, {
    pattern = ft,
    callback = function()
      vim.opt_local.conceallevel = 2
      -- No need to reload queries on every buffer event
    end,
  })
end

M.subscribe_autocmd = subscribe_autocmd

return M
