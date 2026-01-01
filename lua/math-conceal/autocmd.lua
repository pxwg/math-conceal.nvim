local M = {}
local queries = require("math-conceal.query")

--- @param opts LaTeXConcealOptions
--- @param augroup_id integer?
function M.subscribe_autocmd(opts, init_data, augroup_id)
  augroup_id = augroup_id or vim.api.nvim_create_augroup("math-conceal", {})
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup_id,
    pattern = opts.ft,
    callback = function()
      queries.load_queries(opts, init_data)
      local conceal_map = queries.get_preamble_conceal_map()
      if vim.bo.filetype == "tex" then
        queries.update_latex_queries(conceal_map, opts)
      end
    end,
  })
end

return M
