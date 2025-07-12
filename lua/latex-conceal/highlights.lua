local M = {}
local function set_highlights()
  local highlights = {
    ["@_cmd"] = { fg = "#b4beff", bold = true },
    ["@cmd"] = { fg = "#b4beff", bold = true },
    ["@func"] = { fg = "#89b4fb", italic = true },
    ["@letter"] = { fg = "#cdd6f5" },
    ["@sub"] = { fg = "#94e2d6" },
    ["@sub_ident"] = { fg = "#94e2d6" },
    ["@sub_letter"] = { fg = "#94e2d6" },
    ["@sub_number"] = { fg = "#94e2d6" },
    ["@sup"] = { fg = "#fab388" },
    ["@sup_ident"] = { fg = "#fab388" },
    ["@sup_letter"] = { fg = "#fab388" },
    ["@sup_number"] = { fg = "#fab388" },
    ["@symbol"] = { fg = "#74c7ed" },
    ["@typ_font_name"] = { fg = "#cba6f8", italic = true },
    ["@typ_greek_symbol"] = { fg = "#89b4fb" },
    ["@typ_inline_dollar"] = { fg = "#7f849d" },
    ["@typ_math_delim"] = { fg = "#9399b3" },
    ["@typ_math_font"] = { fg = "#f9e2b0" },
    ["@typ_math_symbol"] = { fg = "#74c7ed" },
    ["@typ_phy_symbol"] = { fg = "#a6e3a2" },
    ["@conceal"] = { fg = "#6c7087" },
    ["@open1"] = { fg = "#7f849d" },
    ["@open2"] = { fg = "#7f849d" },
    ["@close1"] = { fg = "#7f849d" },
    ["@close2"] = { fg = "#7f849d" },
    ["@punctuation"] = { fg = "#9399b3" },
    ["@left_paren"] = { fg = "#7f849d" },
    ["@right_paren"] = { fg = "#7f849d" },
  }
  for group, opts in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, opts)
  end
end

M.set_highlights = set_highlights

return M
