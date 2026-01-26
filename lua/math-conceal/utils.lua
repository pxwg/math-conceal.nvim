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

---Read conceal symbols from data files
---@param type "symbols" | "fonts"
---@param lang "latex" | "typst"
---@return table<string, string>[]
function M.read_conceal_symbols(type, lang)
  local info = debug.getinfo(1, "S")
  local script_path = info.source:sub(2)
  local dir = vim.fn.fnamemodify(script_path, ":h")
  local data_path = dir .. "/conceal/math_" .. type .. "_" .. lang .. ".json"
  local file = io.open(data_path, "r")
  if not file then
    vim.notify("Cannot open file: " .. data_path, vim.log.levels.ERROR)
    return {}
  end
  local content = file:read("*a")
  file:close()
  local data = vim.fn.json_decode(content)
  return data
end

---Clean raw_data into pattern_type sub-tables
---@param raw_data table<string, table<string, string>>
---@return table<string, table<string, string>>
function M.clean_conceal_data(raw_data)
  local result = {
    conceal = {},
    font = {},
    subsup = {},
    escape = {},
  }
  for k, data in pairs(raw_data.symbols or {}) do
    result.conceal[k] = data
  end
  for key, value in pairs(raw_data.fonts or {}) do
    if key == "sub" or key == "sup" then
      result.subsup[key] = value
    elseif key == "escape" then
      result.escape[key] = value
    else
      result.font[key] = value
    end
  end
  return result
end

return M
