--- query.lua - Tree-sitter query utilities and directive registration
--- Handles predicate/directive registration and query file processing
local M = {}

local conceal = require("math-conceal.conceal")

--- Cached lookup wrapper
--- @param text string
--- @param pattern string
--- @param mode string?
--- @return string
local function cached_lookup(text, pattern, mode)
  return conceal.lookup_math_symbol(text, pattern, mode)
end

--- Read multiple query files and concatenate
--- @param filenames string[] List of file paths
--- @return string Concatenated contents
function M.read_query_files(filenames)
  local contents = {}
  for _, filename in ipairs(filenames) do
    local file = io.open(filename, "r")
    if file then
      local content = file:read("*a")
      file:close()
      table.insert(contents, content)
    end
  end
  return table.concat(contents, "\n")
end

--- Set pairs directive for tree-sitter
--- Inspired from latex.nvim
--- @param match table<integer, TSNode[]>
--- @param _ integer
--- @param source string|integer
--- @param predicate any[]
--- @param metadata vim.treesitter.query.TSMetadata
local function setpairs(match, _, source, predicate, metadata)
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

-- Cache for ancestor type sets
local ancestor_cache = {}

--- Has grandparent predicate
--- Inspired from latex.nvim
--- @param match table<integer, TSNode[]>
--- @param predicate any[]
--- @return boolean
local function hasgrandparent(match, _, _, predicate)
  local nodes = match[predicate[2]]
  if not nodes or #nodes == 0 then
    return false
  end

  local cache_key = table.concat(predicate, "|", 3)
  local ancestor_set = ancestor_cache[cache_key]
  if not ancestor_set then
    ancestor_set = {}
    for i = 3, #predicate do
      ancestor_set[predicate[i]] = true
    end
    ancestor_cache[cache_key] = ancestor_set
  end

  for _, node in ipairs(nodes) do
    local parent = node:parent()
    if parent then
      local grandparent = parent:parent()
      if grandparent and ancestor_set[grandparent:type()] then
        return true
      end
    end
  end
  return false
end

-- Handler dispatch table for conceal types
local handler_dispatch = {
  font = function(match, _, source, predicate, metadata)
    local capture_id, function_name_id = predicate[2], predicate[3]
    if not capture_id or not match[capture_id] then
      return
    end
    local node = match[capture_id]
    local function_name_node = match[function_name_id]
    local function_name_text = function_name_node and vim.treesitter.get_node_text(function_name_node, source) or "cal"
    local node_text = vim.treesitter.get_node_text(node, source)

    local result = cached_lookup(node_text, "font", function_name_text)
    if result ~= node_text then
      metadata[capture_id] = metadata[capture_id] or {}
      metadata[capture_id]["conceal"] = result
    end
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

    local result = cached_lookup(node_text, "conceal", value)
    if result ~= node_text then
      metadata[capture_id] = metadata[capture_id] or {}
      metadata[capture_id][key] = result
    end
  end,

  sub = function(match, _, source, predicate, metadata)
    local capture_id, value = predicate[2], predicate[4]
    if not capture_id or not match[capture_id] then
      return
    end
    local node = match[capture_id]
    local node_text = vim.treesitter.get_node_text(node, source)

    local result = cached_lookup(node_text, "sub", value)
    if result ~= node_text then
      metadata[capture_id] = metadata[capture_id] or {}
      metadata[capture_id]["conceal"] = result
    end
  end,

  sup = function(match, _, source, predicate, metadata)
    local capture_id, value = predicate[2], predicate[4]
    if not capture_id or not match[capture_id] then
      return
    end
    local node = match[capture_id]
    local node_text = vim.treesitter.get_node_text(node, source)

    local result = cached_lookup(node_text, "sup", value)
    if result ~= node_text then
      metadata[capture_id] = metadata[capture_id] or {}
      metadata[capture_id]["conceal"] = result
    end
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

    local result = cached_lookup(node_text, "escape", value)
    if result ~= node_text then
      metadata[capture_id] = metadata[capture_id] or {}
      metadata[capture_id][key] = result
    end
  end,
}

-- Conceal type configuration
local conceal_config = {
  font = { pattern = "font", directive_name = "set-font!", handler_key = "font" },
  conceal = { pattern = "conceal", directive_name = "set-conceal!", handler_key = "conceal" },
  sub = { pattern = "sub", directive_name = "set-sub!", handler_key = "sub" },
  sup = { pattern = "sup", directive_name = "set-sup!", handler_key = "sup" },
  escape = { pattern = "escape", directive_name = "set-escape!", handler_key = "escape" },
}

--- Create unified handler for a conceal type
--- @param handler_type string
--- @return function
local function handle_unified(handler_type)
  return function(match, pattern_index, source, predicate, metadata)
    local handler = handler_dispatch[handler_type]
    if handler then
      handler(match, pattern_index, source, predicate, metadata)
    end
  end
end

--- Lua func directive handler
local function lua_func(match, _, source, predicate, metadata)
  local capture_id = predicate[2]
  local key = predicate[3]
  if not capture_id or not match[capture_id] or not key then
    return
  end
  local node = match[capture_id]
  if type(metadata[capture_id]) ~= "table" then
    metadata[capture_id] = {}
  end

  local handler = handler_dispatch[key]
  if handler then
    handler(match, _, source, predicate, metadata)
  else
    local node_text = vim.treesitter.get_node_text(node, source)
    metadata[capture_id][key] = node_text
  end
end

--- Register all tree-sitter predicates and directives
function M.load_queries()
  vim.treesitter.query.add_predicate("has-grandparent?", hasgrandparent, { force = true })
  vim.treesitter.query.add_directive("set-pairs!", setpairs, { force = true })

  for _, config in pairs(conceal_config) do
    vim.treesitter.query.add_directive(config.directive_name, handle_unified(config.handler_key), { force = true })
  end

  vim.treesitter.query.add_directive("lua_func!", lua_func, { force = true })
end

--- Register a new conceal type dynamically
--- @param name string Type name
--- @param pattern string Pattern for lookup
--- @param directive_name string? Directive name (defaults to "set-{name}!")
function M.register_conceal_type(name, pattern, directive_name)
  directive_name = directive_name or ("set-" .. name .. "!")

  conceal_config[name] = {
    pattern = pattern,
    directive_name = directive_name,
    handler_key = name,
  }

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

    local result = cached_lookup(node_text, pattern, value)
    if result ~= node_text then
      metadata[capture_id] = metadata[capture_id] or {}
      metadata[capture_id][key or "conceal"] = result
    end
  end

  vim.treesitter.query.add_directive(directive_name, handle_unified(name), { force = true })
end

--- Get conceal query files for a language
--- @param language "latex"|"typst"
--- @param names string[] Conceal type names
--- @return string[] Query file paths
function M.get_conceal_queries(language, names)
  local files = vim.treesitter.query.get_files(language, "highlights")

  for _, name in ipairs(names) do
    local query_name = "conceal_" .. name
    local conceal_files = vim.treesitter.query.get_files(language, query_name)
    for _, file in ipairs(conceal_files) do
      table.insert(files, file)
    end
  end

  return files
end

--- Generate dynamic queries from preamble conceal map
--- @param conceal_map table<string, string> Map of commands to conceal chars
--- @return string Query string
function M.update_latex_queries(conceal_map)
  local queries = {}

  for cmd, origin in pairs(conceal_map) do
    local conceal_string = conceal.lookup_all(origin)
    if vim.fn.strdisplaywidth(conceal_string) == 1 then
      local query = string.format(
        [[
(generic_command
  command: ((command_name) @conceal
    (#match? @conceal "^\\%s$"))
  (#set! @conceal conceal "%s"))
]],
        cmd,
        conceal_string
      )
      table.insert(queries, query)
    end
  end

  return table.concat(queries, "\n")
end

--- Get preamble conceal map from buffer
--- Parses \newcommand and \renewcommand definitions
--- @param bufnr integer? Buffer number
--- @return table<string, string> Conceal map
function M.get_preamble_conceal_map(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local conceal_map = {}

  local ok_parser, parser = pcall(vim.treesitter.get_parser, bufnr, "latex")
  if not ok_parser or not parser then
    return conceal_map
  end

  local tree = parser:parse()[1]
  if not tree then
    return conceal_map
  end

  local root = tree:root()
  local query_string = [[
    (new_command_definition
      declaration: (curly_group_command_name
        command: (command_name) @cmd)
      implementation: (curly_group) @impl) @definition
  ]]

  local ok_query, query = pcall(vim.treesitter.query.parse, "latex", query_string)
  if not ok_query or not query then
    return conceal_map
  end

  local definitions = {}
  for id, node, _ in query:iter_captures(root, bufnr, 0, -1) do
    local name = query.captures[id]
    if name == "definition" then
      table.insert(definitions, {})
    elseif name == "cmd" or name == "impl" then
      if #definitions > 0 then
        definitions[#definitions][name] = node
      end
    end
  end

  for _, def in ipairs(definitions) do
    if def.cmd and def.impl then
      local cmd_text = vim.treesitter.get_node_text(def.cmd, bufnr)
      local impl_text = vim.treesitter.get_node_text(def.impl, bufnr)

      while impl_text:match("^%b{}$") do
        impl_text = impl_text:sub(2, -2)
      end

      conceal_map["\\" .. cmd_text] = impl_text
    end
  end

  return conceal_map
end

return M
