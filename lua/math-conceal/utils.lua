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

---Init conceal symbols
---@param lang "latex" | "typst"
---@return table<string, string>
function M.init_conceal_symbols(lang)
  local type = { "symbols", "fonts" }
  local raw_data = {}
  for _, t in ipairs(type) do
    local data = M.read_conceal_symbols(t, lang)
    raw_data = vim.tbl_deep_extend("force", raw_data, data)
  end
  return raw_data
end

---Get queries file from symbols directory
---@param lang "latex" | "typst"
---@param query_name "greek" | "script" | "math" | "font" | "delim" | "phy"
---@return string
local function get_queries_file(lang, query_name)
  local info = debug.getinfo(1, "S")
  local script_path = info.source:sub(2)
  local dir = vim.fn.fnamemodify(script_path, ":h")
  local queries_path = dir .. "/symbols/" .. lang .. "/conceal_" .. query_name .. ".scm"
  return queries_path
end

---Init query table
---@param lang "latex" | "typst"
---@return table<string, string>
function M.init_queries_table(lang)
  local queries_name = { "greek", "script", "math", "font", "delim", "phy" }
  local queries = {}
  for _, name in ipairs(queries_name) do
    local query_file = get_queries_file(lang, name)
    local file = io.open(query_file, "r")
    if file then
      local content = file:read("*a")
      queries["conceal_" .. name] = content
      file:close()
    end
  end
  return queries
end

return M
