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

  local langs_to_setup = { lang }

  -- Check if buffer has treesitter parser and detect all injected languages
  local buf = vim.api.nvim_get_current_buf()
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if ok and parser then
    -- Get all language trees (including injections)
    parser:for_each_tree(function(tree, language_tree)
      local tree_lang = language_tree:lang()
      -- Add all detected languages (not just latex/typst)
      if not vim.tbl_contains(langs_to_setup, tree_lang) then
        table.insert(langs_to_setup, tree_lang)
      end
    end)
  end

  -- Setup all required languages
  for _, l in ipairs(langs_to_setup) do
    if M.queries[l] == nil then
      -- For latex and typst, load custom queries
      if l == "latex" or l == "typst" then
        M.files[l] = queries.get_conceal_queries(l, M.opts.conceal)
        M.queries[l] = queries.read_query_files(M.files[l])
      else
        -- For other languages, use empty string as placeholder.
        -- The actual builtin runtime queries will be loaded by get_conceal_query()
        -- in render.lua, which loads vim.treesitter.query.get_files(language, "highlights")
        -- This ensures standard Tree-sitter highlighting for non-latex/typst languages.
        M.queries[l] = ""
      end
      render.setup(M.opts, l)
      should_set_hl = true
    end
  end

  if should_set_hl then
    for _, l in ipairs(langs_to_setup) do
      M.set_highlights(l, M.queries[l], filetype)
    end
  end

  -- Attach all required languages to the buffer
  render.attach(buf, langs_to_setup)
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
