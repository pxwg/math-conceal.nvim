local utils = require("math-conceal.utils")
local M = {}

local latex_data = utils.init_conceal_symbols("latex")
local typst_data = utils.init_conceal_symbols("typst")
local raw_data = vim.tbl_deep_extend("force", latex_data, typst_data)

-- cache_by_type: M.lookup_math_symbol
-- cache_full_string: M.lookup_all
local cache_by_type = {
  font = {},
  sub = {},
  sup = {},
  escape = raw_data.escape,
  conceal = raw_data.conceal,
  greek = raw_data.greek,
  greek_font = {},
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

  -- Greek letters with font style (like font)
  for key, symbol in pairs(raw_data.greek_font or {}) do
    local type_name, char = key:match("^(.*):(.*)$")
    if type_name and char then
      if not cache_by_type.greek_font[type_name] then
        cache_by_type.greek_font[type_name] = {}
      end
      cache_by_type.greek_font[type_name][char] = symbol
      local full_tex = "\\" .. type_name .. "{" .. char .. "}"
      cache_full_string[full_tex] = symbol
    end
  end

  -- Greek letters (simple conceal)
  for key, symbol in pairs(raw_data.greek or {}) do
    cache_full_string["\\" .. key] = symbol
    cache_full_string[key] = symbol
  end


  -- Sub/Sup
  for key, symbol in pairs(raw_data.sub or {}) do
    local type_name, char = key:match("^(.*):(.*)$")
    if type_name == "sub" then
      cache_by_type.sub[char] = symbol
    end
  end

  for key, symbol in pairs(raw_data.sup or {}) do
    local type_name, char = key:match("^(.*):(.*)$")
    if type_name == "sup" then
      cache_by_type.sup[char] = symbol
    end
  end

  -- Escape
  -- Use fullwidth colon (U+FF1A) as separator to avoid conflict with ASCII characters
  -- that may appear in LaTeX escape commands (e.g., \:, \;, \!, \,, etc.)
  -- Fullwidth colon: \uFF1A
  -- Example: `"latex：\\:": ""` -> type_name = "latex", char = "\\:"
  for key, symbol in pairs(raw_data.escape or {}) do
    local type_name, char = key:match("^(.*)：(.*)$")
    if type_name and char then
      if not cache_by_type.escape[type_name] then
        cache_by_type.escape[type_name] = {}
      end
      cache_by_type.escape[type_name][char] = symbol
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
--- @param pattern '"escape"'|'"conceal"'|'"font"'|'"greek"'|'"greek_font"'|'"sub"'|'"sup"' Valid values from PatternType enum
--- @param type_name? string: Type of concealment (e.g., "cal", "frak", "bold", etc.)
--- @return string: The converted Unicode symbol or the original text if not found
function M.lookup_math_symbol(text, pattern, type_name)
  -- Fast path for conceal
  if not pattern or pattern == "conceal" then
    return cache_by_type.conceal[text] or text
  end

  -- Escape (requires type_name)
  if pattern == "escape" then
    if type_name then
      local escape_group = cache_by_type.escape[type_name]
      return (escape_group and escape_group[text]) or text
    end
    return text
  end

  -- Greek letters (simple conceal)
  if pattern == "greek" then
    return cache_by_type.greek[text] or text
  end

  local category = cache_by_type[pattern]
  if not category then
    return text
  end

  -- Greek letters with font style
  if pattern == "greek_font" then
    local greek_font_group = category[type_name or ""]
    return (greek_font_group and greek_font_group[text]) or text
  end

  if pattern == "font" then
    local font_group = category[type_name or ""]
    return (font_group and font_group[text]) or text
  end

  -- sub, sup
  return category[text] or text
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
