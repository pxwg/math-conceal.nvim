local M = {}

---Translate language name to filetype
---@param lang "latex" | "typst"
---@return string
function M.lang_to_ft(lang)
  if lang == "latex" then
    return "tex"
  elseif lang == "typst" then
    return "typst"
  else
    return ""
  end
end

return M
