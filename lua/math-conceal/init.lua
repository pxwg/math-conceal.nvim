local M = {}
local highlights = require("math-conceal.highlights")
local queries = require("math-conceal.query")

--- TODO: add custum_function setup

--- @class custum_function
--- @field custum_functions table<string, function>: A table of custom functions to be used for concealment.

--- @class LaTeXConcealOptions
--- @field enabled boolean: Enable or disable LaTeX conceal. Default is true.
--- @field conceal string[]?: Enable or disable math symbol concealment. You can add your own custom conceal types here. Default is {"greek", "script", "math", "font", "delim"}.
--- @field ft string[]: A list of filetypes to enable LaTeX conceal. Default is {"tex", "latex", "markdown", "typst"}.
--- @field depth integer

-- Default options
--- @type LaTeXConcealOptions
local default_opts = {
  enabled = true,
  conceal = {
    "greek",
    "script",
    "math",
    "font",
    "delim",
    "phy",
  },
  ft = { "*.tex", "*.md", "*.typ" },
  depth = 90,
}
local autocmd = require("math-conceal.autocmd")

function M.setup(opts)
  highlights.set_highlights()
  M.opts = vim.tbl_deep_extend("force", default_opts, opts or {})
  local latex_query_files = queries.get_conceal_queries(M.opts).latex
  local typst_query_files = queries.get_conceal_queries(M.opts).typst
  local init_data = {
    latex = latex_query_files,
    typst = typst_query_files,
  }
  local latex_queries = queries.read_query_files(init_data.latex)
  local typst_queries = queries.read_query_files(init_data.typst)
  init_data.latex_queries = latex_queries
  init_data.typst_queries = typst_queries
  if M.opts.enabled then
    autocmd.subscribe_autocmd(M.opts, init_data)
  end
end

return M
