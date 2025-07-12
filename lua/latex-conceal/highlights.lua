local M = {}
local function set_highlights()
  local highlights = {
    ["@_cmd"] = { fg = "#b4befe", bold = true }, -- Lavender
    ["@cmd"] = { fg = "#f5c2e7", bold = true }, -- Pink
    ["@func"] = { fg = "#89b4fa", italic = true }, -- Blue
    ["@font_letter"] = { fg = "#89b4fa", bold = true }, -- Text
    ["@sub"] = { fg = "#94e2d5" }, -- Teal
    ["@sub_ident"] = { fg = "#a6e3a1" }, -- Green
    ["@sub_letter"] = { fg = "#bac2de" }, -- Subtext 1
    ["@sub_number"] = { fg = "#f9e2af" }, -- Yellow
    ["@sup"] = { fg = "#fab387" }, -- Peach
    ["@sup_ident"] = { fg = "#eba0ac" }, -- Maroon
    ["@sup_letter"] = { fg = "#f38ba8" }, -- Red
    ["@sup_number"] = { fg = "#f2cdcd" }, -- Flamingo
    ["@symbol"] = { fg = "#74c7ec" }, -- Sapphire
    ["@typ_font_name"] = { fg = "#cba6f7", italic = true }, -- Mauve
    ["@typ_greek_symbol"] = { fg = "#cba6f7", bold = true }, -- Red (鲜艳)
    ["@typ_inline_dollar"] = { fg = "#7f849c", bold = true }, -- Peach (鲜艳)
    ["@typ_math_delim"] = { fg = "#9399b2" }, -- Overlay 2
    ["@typ_math_font"] = { fg = "#f9e2af" }, -- Yellow
    ["@typ_math_symbol"] = { fg = "#a6adc8" }, -- Subtext 0
    ["@typ_phy_symbol"] = { fg = "#a6e3a1" }, -- Green
    ["@conceal"] = { fg = "#74c7ec" }, -- Rosewater
    ["@open1"] = { fg = "#6c7086" }, -- Overlay 0
    ["@open2"] = { fg = "#45475a" }, -- Surface 1
    ["@close1"] = { fg = "#313244" }, -- Surface 0
    ["@close2"] = { fg = "#585b70" }, -- Surface 2
    ["@punctuation"] = { fg = "#9399b2" }, -- Overlay 2
    ["@left_paren"] = { fg = "#7f849c" }, -- Overlay 1
    ["@right_paren"] = { fg = "#7f849c" }, -- Overlay 1
  }
  for group, opts in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, opts)
  end
end

M.set_highlights = set_highlights

return M
