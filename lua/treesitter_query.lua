local M = {}

local conceal = require("utils.latex_conceal")

---add predicate
---@param filenames string[] List of filenames to read
---@return string contents Concatenated contents of the files
local function read_query_files(filenames)
  local contents = ""

  for _, filename in ipairs(filenames) do
    local file, err = io.open(filename, "r")
    local payload = ""
    if file then
      payload = file:read("*a")
      io.close(file)
    else
      error(err)
    end
    contents = contents .. "\n" .. payload
  end
  return contents
end

---set pairs in treesitter
---inspired from [latex.nvim](https://github.com/robbielyman/latex.nvim)
---@param match table<integer, TSNode[]>
---@param _ integer
---@param source string|integer
---@param predicate any[]
---@param metadata vim.treesitter.query.TSMetadata
local function setpairs(match, _, source, predicate, metadata)
  -- (#set-pairs! @aa key list)
  local capture_id = predicate[2]
  local node = match[capture_id]
  local key = predicate[3]
  if not node then
    return
  end
  local node_text = vim.treesitter.get_node_text(node, source)
  for i = 4, #predicate, 2 do
    if node_text == predicate[i] then
      metadata[key] = predicate[i + 1]
      break
    end
  end
end

---has grandparent predicate
------inspired from [latex.nvim](https://github.com/robbielyman/latex.nvim)
---@param match table<integer, TSNode[]>
---@param predicate any[]
local function hasgrandparent(match, _, _, predicate)
  local nodes = match[predicate[2]]
  if not nodes or #nodes == 0 then
    return false
  end
  for _, node in ipairs(nodes) do
    local current = node
    local valid = true
    for _ = 1, 2 do
      current = current and current:parent()
      if not current then
        valid = false
        break
      end
    end
    if valid then
      local ancestor_types = { unpack(predicate, 3) }
      if vim.tbl_contains(ancestor_types, current:type()) then
        return true
      end
    end
  end

  return false
end

---@param match table<integer, TSNode[]>
---@param _ integer
---@param source string|integer
---@param predicate any[]
---@param metadata vim.treesitter.query.TSMetadata
local function handle_font(match, _, source, predicate, metadata)
  local capture_id = predicate[2]
  local function_name_id = predicate[3]
  if not capture_id or not match[capture_id] then
    return
  end
  local node = match[capture_id]
  local function_name_node = match[function_name_id]
  local function_name_text = function_name_node and vim.treesitter.get_node_text(function_name_node, source) or "cal"
  if type(metadata[capture_id]) ~= "table" then
    metadata[capture_id] = {}
  end
  local node_text = vim.treesitter.get_node_text(node, source)
  metadata[capture_id]["conceal"] = conceal.lookup_math_symbol(node_text, "font", function_name_text)
end

---@param match table<integer, TSNode[]>
---@param _ integer
---@param source string|integer
---@param predicate any[]
---@param metadata vim.treesitter.query.TSMetadata
local function handle_conceal(match, _, source, predicate, metadata)
  local capture_id, key, value = predicate[2], predicate[3], predicate[4]
  if not capture_id or not key then
    return
  end
  local node = match[capture_id]
  if not node then
    return
  end
  local meta = metadata[capture_id]
  if type(meta) ~= "table" then
    meta = {}
    metadata[capture_id] = meta
  end
  local node_text = vim.treesitter.get_node_text(node, source)
  if node_text then
    meta[key] = conceal.lookup_math_symbol(node_text, "conceal", value)
  end
end

---@param match table<integer, TSNode[]>
---@param _ integer
---@param source string|integer
---@param predicate any[]
---@param metadata vim.treesitter.query.TSMetadata
local function handle_sub(match, _, source, predicate, metadata)
  local capture_id = predicate[2]
  local value = predicate[4]
  if not capture_id or not match[capture_id] then
    return
  end
  local node = match[capture_id]
  if type(metadata[capture_id]) ~= "table" then
    metadata[capture_id] = {}
  end
  local node_text = vim.treesitter.get_node_text(node, source)
  metadata[capture_id]["conceal"] = conceal.lookup_math_symbol(node_text, "sub", value)
end

---@param match table<integer, TSNode[]>
---@param _ integer
---@param source string|integer
---@param predicate any[]
---@param metadata vim.treesitter.query.TSMetadata
local function handle_sup(match, _, source, predicate, metadata)
  local capture_id = predicate[2]
  local value = predicate[4]
  if not capture_id or not match[capture_id] then
    return
  end
  local node = match[capture_id]
  if type(metadata[capture_id]) ~= "table" then
    metadata[capture_id] = {}
  end
  local node_text = vim.treesitter.get_node_text(node, source)
  metadata[capture_id]["conceal"] = conceal.lookup_math_symbol(node_text, "sup", value)
end

---@deprecated
local function lua_func(match, _, source, predicate, metadata)
  local capture_id = predicate[2]
  local key = predicate[3]
  local value = predicate[4]
  if not capture_id or not match[capture_id] or not key then
    return
  end
  local node = match[capture_id]
  if type(metadata[capture_id]) ~= "table" then
    metadata[capture_id] = {}
  end
  local node_text = vim.treesitter.get_node_text(node, source)

  if key == "font" then
    handle_font(match, _, source, predicate, metadata)
  elseif key == "conceal" then
    handle_conceal(match, _, source, predicate, metadata)
  elseif key == "sub" then
    handle_sub(match, _, source, predicate, metadata)
  elseif key == "sup" then
    handle_sup(match, _, source, predicate, metadata)
  else
    metadata[capture_id][key] = node_text
  end
end

--- @param args LaTeXConcealOptions
local function load_queries(args)
  vim.treesitter.query.add_predicate("has-grandparent?", hasgrandparent, { force = true })
  vim.treesitter.query.add_directive("set-pairs!", setpairs, { force = true })
  vim.treesitter.query.add_directive("set-font!", handle_font, { force = true })
  vim.treesitter.query.add_directive("set-conceal!", handle_conceal, { force = true })
  vim.treesitter.query.add_directive("set-sub!", handle_sub, { force = true })
  vim.treesitter.query.add_directive("set-sup!", handle_sup, { force = true })
  vim.treesitter.query.add_directive("lua_func!", lua_func, { force = true })

  -- Load LaTeX queries
  local latex_out = vim.treesitter.query.get_files("latex", "highlights")
  for _, name in ipairs(args.conceal) do
    local files = vim.api.nvim_get_runtime_file("queries_config/latex/conceal_" .. name .. ".scm", true)
    for _, file in ipairs(files) do
      table.insert(latex_out, file)
    end
  end
  local latex_strings = read_query_files(latex_out)
  vim.treesitter.query.set("latex", "highlights", latex_strings)

  -- Load Typst queries
  local typst_out = vim.treesitter.query.get_files("typst", "highlights")
  for _, name in ipairs(args.conceal) do
    local files = vim.api.nvim_get_runtime_file("queries_config/typst/conceal_" .. name .. ".scm", true)
    for _, file in ipairs(files) do
      table.insert(typst_out, file)
    end
  end
  local typst_strings = read_query_files(typst_out)
  vim.treesitter.query.set("typst", "highlights", typst_strings)
end

-- --- @param text string
-- --- @param pattern string?
-- --- @param type string?
-- function M.get_mathfont_conceal(text, pattern, type)
--   local out = lookup_math_symbol.lookup_math_symbol(text, pattern, type)
--   return out
-- end

--- initializes the conceal queries
M.load_queries = load_queries

return M
