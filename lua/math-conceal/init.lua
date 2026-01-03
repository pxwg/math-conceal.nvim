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
--- @field augroup_id integer?
--- @field ns_id integer
--- @field highlights table<string, table<string, string>>

---set up
---@param opts LaTeXConcealOptions?
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

---set highlights only when `filetype` is in `M.opts.ft`
---@param filetype string?
function M.set(filetype)
  filetype = filetype or vim.bo.filetype
  for _, ft in ipairs(M.opts.ft) do
    if ft == filetype then
      M.set_hl(filetype)
    end
  end
end

---set highlights only once
---@param filetype string?
function M.set_hl(filetype)
  --- first run
  if #M.queries == 0 then
    for name, val in pairs(M.opts.highlights) do
      vim.api.nvim_set_hl(M.opts.ns_id, name, val)
    end
    queries.load_queries()
  end

  --- after editing preamble and save, reset highlights
  if filetype == "tex" then
    M.opts.augroup_id = M.opts.augroup_id or vim.api.nvim_create_augroup("math-conceal", {})
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = M.opts.augroup_id,
      buffer = 0,
      callback = function()
        M.set_highlights(filetype, M.queries.latex)
        vim.treesitter.start()
      end
    })
  end

  -- set typst math conceal for typst
  -- and set latex math conceal for all other filetypes.
  local ft = filetype == "typst" and filetype or "latex"
  ---always reset highlights for tex due to preamble
  local should_set_hl = filetype == "tex"
  -- if haven't set highlights, must set highlights
  if M.queries[ft] == nil then
    M.files[ft] = queries.get_conceal_queries(ft, M.opts.conceal)
    M.queries[ft] = queries.read_query_files(M.files[ft])
    should_set_hl = true
  end
  if should_set_hl then
    M.set_highlights(filetype, M.queries[ft])
  end
end

---set highlights
---@param filetype string?
---@param code string?
function M.set_highlights(filetype, code)
  filetype = filetype or vim.bo.filetype
  code = code or ""

  if filetype == "tex" then
    local conceal_map = queries.get_preamble_conceal_map()
    code = code .. "\n" .. queries.update_latex_queries(conceal_map)
  end
  vim.treesitter.query.set(filetype, "highlights", code)
end

return M
