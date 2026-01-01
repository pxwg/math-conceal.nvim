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
    filetypes = {
      latex = { "*.tex" },
      markdown = { "*.md" },
      typst = { "*.typ" },
    },
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
--- @field filetypes table<"latex" | "typst" | "markdown", string[]>
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

  M.opts.augroup_id = M.opts.augroup_id or vim.api.nvim_create_augroup("math-conceal", {})
  -- ftplugin or FileType cannot work
  for ft, pattern in pairs(M.opts.filetypes) do
    vim.api.nvim_create_autocmd("BufReadPost", {
      group = M.opts.augroup_id,
      pattern = pattern,
      callback = function()
        M.load_queries(ft)
      end
    })
  end
end

---load all queries.
---callback for autocmd
---@param filetype "latex" | "typst" | "markdown"
function M.load_queries(filetype)
  queries.load_queries()
  local code = ""
  if filetype == "latex" then
    local conceal_map = queries.get_preamble_conceal_map()
    code = queries.update_latex_queries(conceal_map)
  elseif filetype == "markdown" then
    filetype = "latex"
  end
  if M.queries[filetype] == nil then
    M.files[filetype] = queries.get_conceal_queries(filetype, M.opts.conceal)
    M.queries[filetype] = queries.read_query_files(M.files[filetype])
  end
  code = M.queries[filetype] .. "\n" .. code
  vim.treesitter.query.set(filetype, "highlights", code)
  vim.cmd.edit()
end

return M
