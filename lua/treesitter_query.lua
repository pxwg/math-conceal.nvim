local M = {}

local conceal = require("utils.latex_conceal")

-- Cache for frequently used symbols to reduce FFI overhead
local symbol_cache = {}
local cache_size = 0
local max_cache_size = 500

-- Helper function to get from cache or lookup
local function cached_lookup(text, pattern, mode)
  local cache_key = text .. ":" .. pattern .. ":" .. (mode or "")
  
  -- Check cache first
  local cached_result = symbol_cache[cache_key]
  if cached_result then
    return cached_result
  end
  
  -- Perform lookup
  local result = conceal.lookup_math_symbol(text, pattern, mode)
  
  -- Cache the result if cache isn't full
  if cache_size < max_cache_size then
    symbol_cache[cache_key] = result
    cache_size = cache_size + 1
  end
  
  return result
end

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

-- Configuration for easily adding new conceal types
local conceal_config = {
  -- Each entry defines how to register a new conceal type
  -- pattern: the pattern type to use for lookup
  -- directive_name: the tree-sitter directive name 
  -- handler_key: key in the handler_dispatch table
  font = { pattern = "font", directive_name = "set-font!", handler_key = "font" },
  conceal = { pattern = "conceal", directive_name = "set-conceal!", handler_key = "conceal" },
  sub = { pattern = "sub", directive_name = "set-sub!", handler_key = "sub" },
  sup = { pattern = "sup", directive_name = "set-sup!", handler_key = "sup" },
  escape = { pattern = "escape", directive_name = "set-escape!", handler_key = "escape" },
}

-- Function to easily register new conceal types
local function register_conceal_type(name, pattern, directive_name)
  -- Add to config
  conceal_config[name] = { 
    pattern = pattern, 
    directive_name = directive_name or ("set-" .. name .. "!"),
    handler_key = name
  }
  
  -- Add handler to dispatch table
  handler_dispatch[name] = function(match, _, source, predicate, metadata)
    local capture_id, key, value = predicate[2], predicate[3], predicate[4]
    if not capture_id or not match[capture_id] then
      return
    end

    local node = match[capture_id]
    local node_text = vim.treesitter.get_node_text(node, source)
    if not node_text then
      return
    end

    metadata[capture_id] = metadata[capture_id] or {}
    metadata[capture_id][key or "conceal"] = cached_lookup(node_text, pattern, value)
  end
end

-- Export the registration function for extensibility
M.register_conceal_type = register_conceal_type

-- Optimized unified handler function
local function handle_unified(handler_type)
  return function(match, pattern_index, source, predicate, metadata)
    local handler = handler_dispatch[handler_type]
    if handler then
      handler(match, pattern_index, source, predicate, metadata)
    end
  end
end
local handler_dispatch = {
  font = function(match, _, source, predicate, metadata)
    local capture_id, function_name_id = predicate[2], predicate[3]
    if not capture_id or not match[capture_id] then
      return
    end

    local node = match[capture_id]
    local function_name_node = match[function_name_id]
    local function_name_text = function_name_node and vim.treesitter.get_node_text(function_name_node, source) or "cal"

    metadata[capture_id] = metadata[capture_id] or {}
    metadata[capture_id]["conceal"] = cached_lookup(vim.treesitter.get_node_text(node, source), "font", function_name_text)
  end,
  
  conceal = function(match, _, source, predicate, metadata)
    local capture_id, key, value = predicate[2], predicate[3], predicate[4]
    if not capture_id or not key or not match[capture_id] then
      return
    end

    local node = match[capture_id]
    local node_text = vim.treesitter.get_node_text(node, source)
    if not node_text then
      return
    end

    metadata[capture_id] = metadata[capture_id] or {}
    metadata[capture_id][key] = cached_lookup(node_text, "conceal", value)
  end,
  
  sub = function(match, _, source, predicate, metadata)
    local capture_id, value = predicate[2], predicate[4]
    if not capture_id or not match[capture_id] then
      return
    end

    local node = match[capture_id]
    metadata[capture_id] = metadata[capture_id] or {}
    metadata[capture_id]["conceal"] = cached_lookup(vim.treesitter.get_node_text(node, source), "sub", value)
  end,
  
  sup = function(match, _, source, predicate, metadata)
    local capture_id, value = predicate[2], predicate[4]
    if not capture_id or not match[capture_id] then
      return
    end

    local node = match[capture_id]
    metadata[capture_id] = metadata[capture_id] or {}
    metadata[capture_id]["conceal"] = cached_lookup(vim.treesitter.get_node_text(node, source), "sup", value)
  end,
  
  escape = function(match, _, source, predicate, metadata)
    local capture_id, key, value = predicate[2], predicate[3], predicate[4]
    if not capture_id or not key or not match[capture_id] then
      return
    end

    local node = match[capture_id]
    local node_text = vim.treesitter.get_node_text(node, source)
    if not node_text then
      return
    end

    metadata[capture_id] = metadata[capture_id] or {}
    metadata[capture_id][key] = cached_lookup(node_text, "escape", value)
  end
}

-- Optimized unified handler function
local function handle_unified(handler_type)
  return function(match, pattern_index, source, predicate, metadata)
    local handler = handler_dispatch[handler_type]
    if handler then
      handler(match, pattern_index, source, predicate, metadata)
    end
  end
end

-- Optimized lua_func using dispatch table instead of if-elseif chains
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
  
  -- Use dispatch table for faster lookups
  local handler = handler_dispatch[key]
  if handler then
    handler(match, _, source, predicate, metadata)
  else
    -- Fallback for unknown keys
    local node_text = vim.treesitter.get_node_text(node, source)
    metadata[capture_id][key] = node_text
  end
end

--- @param args LaTeXConcealOptions
local function load_queries(args)
  vim.treesitter.query.add_predicate("has-grandparent?", hasgrandparent, { force = true })
  vim.treesitter.query.add_directive("set-pairs!", setpairs, { force = true })
  
  -- Register all configured conceal types
  for name, config in pairs(conceal_config) do
    vim.treesitter.query.add_directive(config.directive_name, handle_unified(config.handler_key), { force = true })
  end
  
  vim.treesitter.query.add_directive("lua_func!", lua_func, { force = true })

  -- load latex queries
  local latex_out = vim.treesitter.query.get_files("latex", "highlights")
  for _, name in ipairs(args.conceal) do
    local files = vim.api.nvim_get_runtime_file("queries_config/latex/conceal_" .. name .. ".scm", true)
    for _, file in ipairs(files) do
      table.insert(latex_out, file)
    end
  end
  local latex_strings = read_query_files(latex_out)
  vim.treesitter.query.set("latex", "highlights", latex_strings)

  -- load typst queries
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
