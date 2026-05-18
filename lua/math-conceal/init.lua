local queries = require("math-conceal.query")
local render = require("math-conceal.render")
local M = {
  files = {},
  queries = {},
  -- Default options
  --- @type MathConcealOptions
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
      ["@_env"] = { link = "@conceal", default = true },
      ["@_frac_name"] = { link = "@conceal", default = true },
      ["@_func_name"] = { link = "@conceal", default = true },
      ["@_line"] = { link = "@conceal", default = true },
      ["@abs_name"] = { link = "@conceal", default = true },
      ["@close_paren"] = { link = "@conceal", default = true },
      ["@cmd"] = { link = "@conceal", default = true },
      ["@comma"] = { link = "@conceal", default = true },
      ["@conceal"] = { link = "Conceal", default = true },
      ["@conceal_dollar"] = { link = "@conceal", default = true },
      ["@content"] = { link = "@conceal", default = true },
      ["@first_letter"] = { link = "@conceal", default = true },
      ["@font_letter"] = { link = "@conceal", default = true },
      ["@frac"] = { link = "@conceal", default = true },
      ["@func"] = { link = "@conceal", default = true },
      ["@func_name"] = { link = "@conceal", default = true },
      ["@left_1"] = { link = "@conceal", default = true },
      ["@left_2"] = { link = "@conceal", default = true },
      ["@left_brace"] = { link = "@conceal", default = true },
      ["@left_content"] = { link = "@conceal", default = true },
      ["@left_paren"] = { link = "@conceal", default = true },
      ["@left_paren_cmd"] = { link = "@conceal", default = true },
      ["@open_paren"] = { link = "@conceal", default = true },
      ["@punctuation"] = { link = "@conceal", default = true },
      ["@right_1"] = { link = "@conceal", default = true },
      ["@right_2"] = { link = "@conceal", default = true },
      ["@right_brace"] = { link = "@conceal", default = true },
      ["@right_content"] = { link = "@conceal", default = true },
      ["@right_paren"] = { link = "@conceal", default = true },
      ["@right_paren_cmd"] = { link = "@conceal", default = true },
      ["@second_letter"] = { link = "@conceal", default = true },
      ["@sub_letter"] = { link = "@conceal", default = true },
      ["@sub_object"] = { link = "@conceal", default = true },
      ["@sub_symbol"] = { link = "@conceal", default = true },
      ["@sup_letter"] = { link = "@conceal", default = true },
      ["@sup_object"] = { link = "@conceal", default = true },
      ["@sup_symbol"] = { link = "@conceal", default = true },
      ["@symbol"] = { link = "@conceal", default = true },
      ["@tex_font_name"] = { link = "@conceal", default = true },
      ["@tex_greek"] = { link = "@conceal", default = true },
      ["@tex_math_command"] = { link = "@conceal", default = true },
      ["@typ_font_name"] = { link = "@conceal", default = true },
      ["@typ_greek_symbol"] = { link = "@conceal", default = true },
      ["@typ_inline_ampersand"] = { link = "@conceal", default = true },
      ["@typ_inline_asterisk"] = { link = "@conceal", default = true },
      ["@typ_inline_dollar"] = { link = "@conceal", default = true },
      ["@typ_inline_quote"] = { link = "@conceal", default = true },
      ["@typ_math_delim"] = { link = "@conceal", default = true },
      ["@typ_math_font"] = { link = "@conceal", default = true },
      ["@typ_math_symbol"] = { link = "@conceal", default = true },
      ["@typ_phy_symbol"] = { link = "@conceal", default = true },
    },
  },
}

--- TODO: add custum_function setup

--- @class custum_function
--- @field custum_functions table<string, function>: A table of custom functions to be used for concealment.

--- @class MathConcealOptions
--- @field conceal string[]?: Enable or disable math symbol concealment. You can add your own custom conceal types here. Default is {"greek", "script", "math", "font", "delim"}.
--- @field ft string[]: A list of filetypes to enable conceal
--- @field depth integer
--- @field augroup_id integer?
--- @field ns_id integer
--- @field highlights table<string, table<string, string>>

---set up
---@param opts MathConcealOptions?
function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
end

---check if `filetype` is in `M.opts.ft`.
---if true, call `set_hl`
---@param filetype string?
function M.set(filetype)
  filetype = filetype or vim.bo.filetype
  for _, ft in ipairs(M.opts.ft) do
    if ft == filetype then
      M.set_hl(filetype)
    end
  end
end

---do some prepare work, then call `set_highlights`
---@param filetype string
function M.set_hl(filetype)
  -- force set conceallevel and concealcursor for current buffer
  vim.opt_local.conceallevel = 2
  vim.opt_local.concealcursor = "nci"

  -- set typst math conceal for typst
  -- and set latex math conceal for all other filetypes.
  ---@type "typst" | "latex"
  local lang = filetype == "typst" and filetype or "latex"
  --- first run
  if #M.queries == 0 then
    for name, val in pairs(M.opts.highlights) do
      vim.api.nvim_set_hl(M.opts.ns_id, name, val)
    end
    queries.load_queries()
    render.setup(M.opts, lang)
  end

  --- after editing preamble and save, reset highlights
  if filetype == "tex" then
    M.opts.augroup_id = M.opts.augroup_id or vim.api.nvim_create_augroup("math-conceal", {})
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = M.opts.augroup_id,
      buffer = 0,
      callback = function()
        M.set_highlights("latex", M.queries.latex, "tex")
        vim.treesitter.start()
      end,
    })
  end

  ---always reset highlights for tex due to preamble
  local should_set_hl = filetype == "tex"
  -- if haven't set highlights, must set highlights
  if M.queries[lang] == nil then
    M.files[lang] = queries.get_conceal_queries(lang, M.opts.conceal)
    M.queries[lang] = queries.read_query_files(M.files[lang])
    should_set_hl = true
  end
  if should_set_hl then
    M.set_highlights(lang, M.queries[lang], filetype)
  end

  -- Always try to attach render to current buffer
  render.attach(vim.api.nvim_get_current_buf(), lang)
end

---set highlights for lang.
---if filetype == 'tex', update queries for preamble
---@param lang string
---@param code string?
---@param filetype string?
function M.set_highlights(lang, code, filetype)
  filetype = filetype or vim.bo.filetype
  code = code or ""

  if filetype == "tex" then
    local conceal_map = queries.get_preamble_conceal_map()
    code = code .. "\n" .. queries.update_latex_queries(conceal_map)
  end
  vim.treesitter.query.set(lang, "highlights", code)
end

return M
