local M = {}
local autocmd = vim.api.nvim_create_autocmd
local queries = require("treesitter_query")

--- @param opts LaTeXConcealOptions
local function subscribe_autocmd(opts)
  if not opts.enabled then
    return
  end

  local ft = opts.ft
  autocmd({ "BufEnter", "BufReadPre" }, {
    pattern = ft,
    callback = function()
      vim.opt_local.conceallevel = 2
      -- No need to reload queries on every buffer event
    end,
  })
  autocmd("BufReadPost", {
    pattern = ft,
    callback = function()
      local conceal_map = queries.get_preamble_conceal_map()
      queries.update_queries(conceal_map, opts)
      vim.cmd("e")
    end,
  })
end

M.subscribe_autocmd = subscribe_autocmd

return M
