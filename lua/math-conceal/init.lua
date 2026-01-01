local queries = require("math-conceal.query")
local M = {
  files = {},
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
    ft = { "plaintex", "tex", "context", "bibtex", "markdown", "typst" },
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
--- @field ft string[]: A list of filetypes to enable LaTeX conceal
--- @field depth integer
--- @field ns_id integer
--- @field highlights table<string, table<string, string>>

---set up
---@param opts LaTeXConcealOptions?
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

---set math conceal
---@param filetype string?
function M.set(filetype)
  filetype = filetype or vim.bo.filetype
  for _, ft in ipairs(M.opts.ft) do
    if ft == filetype then
      M.set_highlights(filetype, M.opts.ns_id, M.opts.highlights, M.opts.conceal)
      return
    end
  end
end

---set highlights
---@param filetype string?
---@param ns_id integer?
---@param highlights table<string, table<string, string>>
---@param conceal string[]
function M.set_highlights(filetype, ns_id, highlights, conceal)
  filetype = filetype or vim.bo.filetype
  ns_id = ns_id or 0
  highlights = highlights or {}
  conceal = conceal or {}
  local code = ""
  if filetype == "tex" then
    local conceal_map = queries.get_preamble_conceal_map()
    code = queries.update_latex_queries(conceal_map)
  end
  if filetype ~= "typst" then
    filetype = "latex"
  end

  if #M.queries == 0 then
    for name, val in pairs(highlights) do
      vim.api.nvim_set_hl(ns_id, name, val)
    end
    queries.load_queries()
  end

  if M.queries[filetype] == nil then
    M.files[filetype] = queries.get_conceal_queries(filetype, conceal)
    M.queries[filetype] = queries.read_query_files(M.files[filetype])
  end
  code = M.queries[filetype] .. "\n" .. code
  vim.treesitter.query.set(filetype, "highlights", code)
end

return M
