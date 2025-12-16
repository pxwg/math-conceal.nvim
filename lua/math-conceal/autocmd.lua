local M = {}
local autocmd = vim.api.nvim_create_autocmd
local queries = require("treesitter_query")

--- @param opts LaTeXConcealOptions
--- @param augroup_id integer?
local function subscribe_autocmd(opts, init_data, augroup_id)
  if not opts.enabled then
    return
  end

  augroup_id = augroup_id or vim.api.nvim_create_augroup("math-conceal", {})
  local ft = opts.ft
  autocmd({ "BufEnter", "BufReadPre" }, {
    group = augroup_id,
    pattern = ft,
    callback = function()
      vim.opt_local.conceallevel = 2
      -- No need to reload queries on every buffer event
    end,
  })
  autocmd("BufReadPost", {
    group = augroup_id,
    pattern = ft,
    callback = function()
      queries.load_queries(opts, init_data)
      local conceal_map = queries.get_preamble_conceal_map()
      if vim.bo.filetype == "tex" then
        queries.update_latex_queries(conceal_map, opts)
      end
      vim.cmd("e")
    end,
  })
end

M.subscribe_autocmd = subscribe_autocmd

return M
