local M = {}
local function set_highlights()
  local highlights = {
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
  for group, opts in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, opts)
  end
end

M.set_highlights = set_highlights

return M
