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

---Translate language name to an element in {typst, latex}
---@param lang string
function M.lang_to_lt(lang)
  if lang ~= "typst" then
    return "latex"
  else
    return "typst"
  end
end

return M
