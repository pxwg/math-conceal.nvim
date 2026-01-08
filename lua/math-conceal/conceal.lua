local M = {}

local raw_data_latex = require("math-conceal.conceal.latex")
local raw_data_typst = require("math-conceal.conceal.typst")
local raw_data = {
  font = vim.tbl_extend("force", raw_data_latex.font or {}, raw_data_typst.font or {}),
  subsup = vim.tbl_extend("force", raw_data_latex.subsup or {}, raw_data_typst.subsup or {}),
  escape = vim.tbl_extend("force", raw_data_latex.escape or {}, raw_data_typst.escape or {}),
  conceal = vim.tbl_extend("force", raw_data_latex.conceal or {}, raw_data_typst.conceal or {}),
}

-- cache_by_type: M.lookup_math_symbol
-- cache_full_string: M.lookup_all
local cache_by_type = {
  font = {},
  sub = {},
  sup = {},
  escape = {},
  conceal = raw_data.conceal,
}
local cache_full_string = {}

local function init()
  -- Font: "cal:A" -> cache_by_type.font["cal"]["A"]
  for key, symbol in pairs(raw_data.font or {}) do
    local type_name, char = key:match("^(.*):(.*)$")
    if type_name and char then
      if not cache_by_type.font[type_name] then
        cache_by_type.font[type_name] = {}
      end
      cache_by_type.font[type_name][char] = symbol
      local full_tex = "\\" .. type_name .. "{" .. char .. "}"
      cache_full_string[full_tex] = symbol
    end
  end

  -- Sub/Sup
  for key, symbol in pairs(raw_data.subsup or {}) do
    local type_name, char = key:match("^(.*):(.*)$")
    if type_name == "sub" or type_name == "sup" then
      cache_by_type[type_name][char] = symbol
    end
  end

  -- Escape
  for key, symbol in pairs(raw_data.escape or {}) do
    local type_name, char = key:match("^(.*):(.*)$")
    if type_name == "escape" then
      cache_by_type.escape[char] = symbol
    end
  end

  -- Conceal
  for k, v in pairs(raw_data.conceal or {}) do
    cache_full_string["\\" .. k] = v
    cache_full_string[k] = v
  end
end

init()

--- @param text string: The LaTeX math symbol to convert
--- @param pattern '"escape"'|'"conceal"'|'"font"'|'"sub"'|'"sup"' Valid values from PatternType enum
--- @param type_name? string: Type of concealment (e.g., "cal", "frak", "bold", etc.)
--- @return string: The converted Unicode symbol or the original text if not found
function M.lookup_math_symbol(text, pattern, type_name)
  -- Fast path for common case
  if not pattern or pattern == "conceal" then
    return cache_by_type.conceal[text] or text
  end

  local category = cache_by_type[pattern]
  if not category then
    return text
  end

  if pattern == "font" then
    local font_group = category[type_name or ""]
    return (font_group and font_group[text]) or text
  else
    -- sub, sup, escape
    return category[text] or text
  end
end

--- @param text string: The LaTeX math symbol to convert
--- @return string: The converted Unicode symbol or the original text if not found
function M.lookup_all(text)
  return cache_full_string[text] or text
end

--- Batch lookup function for better performance
--- @param batch table: Array of {text, pattern, mode} tables
--- @return table: Array of results
function M.lookup_batch(batch)
  local results = {}
  local lookup = M.lookup_math_symbol
  for i = 1, #batch do
    local item = batch[i]
    results[i] = lookup(item.text, item.pattern, item.mode)
  end
  return results
end

return M
