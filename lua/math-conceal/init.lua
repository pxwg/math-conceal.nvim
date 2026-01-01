local queries = require("math-conceal.query")
local M = {
  queries = {},
  -- Default options
  --- @type LaTeXConcealOptions
  opts = {
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
    ns_id = 0,
    highlights = {
      ["@_cmd"] = { link = "@conceal" },
      ["@cmd"] = { link = "@conceal" },
      ["@func"] = { link = "@conceal" },
      ["@font_letter"] = { link = "@conceal" },
      ["@sub"] = { link = "@conceal" },
      ["@sub_ident"] = { link = "@conceal" },
      ["@sub_letter"] = { link = "@conceal" },
      ["@sub_number"] = { link = "@conceal" },
      ["@sup"] = { link = "@conceal" },
      ["@sup_ident"] = { link = "@conceal" },
      ["@sup_letter"] = { link = "@conceal" },
      ["@sup_number"] = { link = "@conceal" },
      ["@symbol"] = { link = "@conceal" },
      ["@typ_font_name"] = { link = "@conceal" },
      ["@typ_greek_symbol"] = { link = "@conceal" },
      ["@typ_inline_dollar"] = { link = "@conceal" },
      ["@typ_math_delim"] = { link = "@conceal" },
      ["@typ_math_font"] = { link = "@conceal" },
      ["@typ_math_symbol"] = { link = "@conceal" },
      ["@typ_phy_symbol"] = { link = "@conceal" },
      ["@conceal"] = { link = "@conceal" },
      ["@open1"] = { link = "@conceal" },
      ["@open2"] = { link = "@conceal" },
      ["@close1"] = { link = "@conceal" },
      ["@close2"] = { link = "@conceal" },
      ["@punctuation"] = { link = "@conceal" },
      ["@left_paren"] = { link = "@conceal" },
      ["@right_paren"] = { link = "@conceal" },
    }
  }
}

--- TODO: add custum_function setup

--- @class custum_function
--- @field custum_functions table<string, function>: A table of custom functions to be used for concealment.

--- @class LaTeXConcealOptions
--- @field conceal string[]?: Enable or disable math symbol concealment. You can add your own custom conceal types here. Default is {"greek", "script", "math", "font", "delim"}.
--- @field ft string[]: A list of filetypes to enable LaTeX conceal. Default is {"tex", "latex", "markdown", "typst"}.
--- @field depth integer
--- @field ns_id integer
--- @field highlights table<string, table<string, string>>
--- @field augroup_id integer?

---set up
---@param opts LaTeXConcealOptions?
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})

  for group, opts in pairs(M.opts.highlights) do
    vim.api.nvim_set_hl(M.opts.ns_id, group, opts)
  end

  local latex_query_files = queries.get_conceal_queries("latex", M.opts.conceal)
  M.queries.latex = queries.read_query_files(latex_query_files)
  local typst_query_files = queries.get_conceal_queries("typst", M.opts.conceal)
  M.queries.typst = queries.read_query_files(typst_query_files)

  local augroup_id = M.opts.augroup_id or vim.api.nvim_create_augroup("math-conceal", {})
  -- ftplugin or FileType cannot work
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = augroup_id,
    pattern = M.opts.ft,
    callback = M.load_queries
  })
end

---load all queries.
---callback for autocmd
---@param filetype string?
function M.load_queries(filetype)
  filetype = filetype or vim.bo.filetype
  -- only support typst and latex
  if filetype ~= "typst" then
    filetype = "latex"
  end
  if M.queries[filetype] == nil then
    M.setup()
  end
  queries.load_queries()
  vim.treesitter.query.set(filetype, "highlights", M.queries[filetype])
  if filetype == "latex" then
    local conceal_map = queries.get_preamble_conceal_map()
    queries.update_latex_queries(conceal_map, M.opts)
  end
  vim.cmd.edit()
end

return M
