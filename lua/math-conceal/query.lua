local M = {}

local conceal = require("math-conceal.conceal")

-- Wrapper function to call look up function
local function cached_lookup(text, pattern, mode)
  local result = conceal.lookup_math_symbol(text, pattern, mode)
  return result
end

---Normalize a query capture into a single TSNode.
---Neovim 0.12 may pass captures as TSNode[] for repeated matches.
---@param capture TSNode|TSNode[]|nil
---@return TSNode|nil
local function get_capture_node(capture)
  if not capture then
    return nil
  end

  if type(capture) == "table" and capture.range == nil then
    return capture[1]
  end

  return capture
end

---@param node TSNode|nil
---@param source string|integer
---@return string|nil
local function safe_get_node_text(node, source)
  if not node then
    return nil
  end

  local ok, text = pcall(vim.treesitter.get_node_text, node, source)
  if not ok then
    return nil
  end

  return text
end

---@param capture TSNode|TSNode[]|nil
---@param source string|integer
---@return string|nil
local function get_capture_text(capture, source)
  local node = get_capture_node(capture)
  if not node then
    return nil
  end

  return safe_get_node_text(node, source)
end

---add predicate (optimized for performance)
---@param filenames string[] List of filenames to read
---@return string contents Concatenated contents of the files
local function read_query_files(filenames)
  local contents_table = {}

  for _, filename in ipairs(filenames) do
    local file, err = io.open(filename, "r")
    if file then
      local payload = file:read("*a")
      file:close()
      table.insert(contents_table, payload)
    else
      error(err)
    end
  end
  return table.concat(contents_table, "\n")
end

local conceal_directives = {
  ["set-conceal!"] = true,
  ["set-font!"] = true,
  ["set-sub!"] = true,
  ["set-sup!"] = true,
  ["set-escape!"] = true,
  ["set-greek!"] = true,
  ["set-greek_font!"] = true,
}

local function find_directive_end(code, start)
  local depth = 0
  local in_string = false
  local escaped = false

  for i = start, #code do
    local char = code:sub(i, i)

    if in_string then
      if escaped then
        escaped = false
      elseif char == "\\" then
        escaped = true
      elseif char == '"' then
        in_string = false
      end
    elseif char == '"' then
      in_string = true
    elseif char == "(" then
      depth = depth + 1
    elseif char == ")" then
      depth = depth - 1
      if depth == 0 then
        return i
      end
    end
  end
end

local function is_conceal_directive(expr)
  local directive = expr:match("^%(%#([%w%-%?!]+)")
  if not directive then
    return false
  end

  if conceal_directives[directive] then
    return true
  end

  if directive == "set!" or directive == "set-pairs!" or directive == "lua_func!" then
    return expr:find("conceal", 1, true) ~= nil
  end

  return false
end

local function strip_conceal_directives(code)
  local output = {}
  local i = 1

  while i <= #code do
    local directive_start = code:find("%(%#", i)
    if not directive_start then
      table.insert(output, code:sub(i))
      break
    end

    table.insert(output, code:sub(i, directive_start - 1))

    local directive_end = find_directive_end(code, directive_start)
    if not directive_end then
      table.insert(output, code:sub(directive_start))
      break
    end

    local expr = code:sub(directive_start, directive_end)
    if not is_conceal_directive(expr) then
      table.insert(output, expr)
    end

    i = directive_end + 1
  end

  return table.concat(output)
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
  local node = get_capture_node(match[capture_id])
  local key = predicate[3]
  if not node then
    return
  end
  local node_text = safe_get_node_text(node, source)
  if not node_text then
    return
  end
  for i = 4, #predicate, 2 do
    if node_text == predicate[i] then
      metadata[key] = predicate[i + 1]
      break
    end
  end
end

-- Cache for ancestor type sets to avoid repeated table creation and conversion
local ancestor_cache = {}

---has grandparent predicate (optimized for performance)
------inspired from [latex.nvim](https://github.com/robbielyman/latex.nvim)
---@param match table<integer, TSNode[]>
---@param predicate any[]
local function hasgrandparent(match, _, _, predicate)
  local capture = match[predicate[2]]
  if not capture then
    return false
  end

  local nodes = capture
  if nodes.range ~= nil then
    nodes = { nodes }
  end

  if #nodes == 0 then
    return false
  end

  -- Create cache key for ancestor types to avoid repeated table operations
  local cache_key = table.concat(predicate, "|", 3)
  local ancestor_set = ancestor_cache[cache_key]

  if not ancestor_set then
    -- Convert ancestor types list to hash set for O(1) lookup
    ancestor_set = {}
    for i = 3, #predicate do
      ancestor_set[predicate[i]] = true
    end
    ancestor_cache[cache_key] = ancestor_set
  end

  for _, node in ipairs(nodes) do
    -- Optimized traversal: get grandparent directly instead of loop
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
  greek = { pattern = "greek", directive_name = "set-greek!", handler_key = "greek" },
  greek_font = { pattern = "greek_font", directive_name = "set-greek_font!", handler_key = "greek_font" },
}

-- Function to easily register new conceal types
local function register_conceal_type(name, pattern, directive_name)
  -- Add to config
  conceal_config[name] = {
    pattern = pattern,
    directive_name = directive_name or ("set-" .. name .. "!"),
    handler_key = name,
  }

  -- Add handler to dispatch table
  handler_dispatch[name] = function(match, _, source, predicate, metadata)
    local capture_id, key, value = predicate[2], predicate[3], predicate[4]
    if not capture_id or not match[capture_id] then
      return
    end

    local node = get_capture_node(match[capture_id])
    local node_text = get_capture_text(node, source)
    if not node_text then
      return
    end

    local result = cached_lookup(node_text, pattern, value)

    if result ~= node_text then
      metadata[capture_id] = metadata[capture_id] or {}
      metadata[capture_id][key or "conceal"] = result
    end
  end
end

-- Export the registration function for extensibility
M.register_conceal_type = register_conceal_type

local handler_dispatch = {
  font = function(match, _, source, predicate, metadata)
    local capture_id, function_name_id = predicate[2], predicate[3]
    if not capture_id or not match[capture_id] then
      return
    end

    local node = get_capture_node(match[capture_id])
    local function_name_node = get_capture_node(match[function_name_id])
    local function_name_text = safe_get_node_text(function_name_node, source) or "cal"
    local node_text = get_capture_text(node, source)
    if not node_text then
      return
    end

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

    local node = get_capture_node(match[capture_id])
    local node_text = get_capture_text(node, source)
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

    local node = get_capture_node(match[capture_id])
    local node_text = get_capture_text(node, source)
    if not node_text then
      return
    end

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

    local node = get_capture_node(match[capture_id])
    local node_text = get_capture_text(node, source)
    if not node_text then
      return
    end

    local result = cached_lookup(node_text, "sup", value)

    if result ~= node_text then
      metadata[capture_id] = metadata[capture_id] or {}
      metadata[capture_id]["conceal"] = result
    end
  end,

escape = function(match, _, source, predicate, metadata)
  local capture_id = predicate[2]
  local type_name = predicate[3]
  if not capture_id or not match[capture_id] then
    return
  end

  local node = get_capture_node(match[capture_id])
  local node_text = get_capture_text(node, source)
  if not node_text then
    return
  end

  local result = cached_lookup(node_text, "escape", type_name)

  if result ~= node_text then
    metadata[capture_id] = metadata[capture_id] or {}
    metadata[capture_id]["conceal"] = result
  end
end,

  greek = function(match, _, source, predicate, metadata)
    local capture_id = predicate[2]
    if not capture_id or not match[capture_id] then
      return
    end

    local node = get_capture_node(match[capture_id])
    local node_text = get_capture_text(node, source)
    if not node_text then
      return
    end

    local result = cached_lookup(node_text, "greek", nil)

    if result ~= node_text then
      metadata[capture_id] = metadata[capture_id] or {}
      metadata[capture_id]["conceal"] = result
    end
  end,

  greek_font = function(match, _, source, predicate, metadata)
    local capture_id, function_name_id = predicate[2], predicate[3]
    if not capture_id or not match[capture_id] then
      return
    end

    local node = get_capture_node(match[capture_id])
    local function_name_node = get_capture_node(match[function_name_id])
    local function_name_text = safe_get_node_text(function_name_node, source) or "cal"
    local node_text = get_capture_text(node, source)
    if not node_text then
      return
    end

    local result = cached_lookup(node_text, "greek_font", function_name_text)

    if result ~= node_text then
      metadata[capture_id] = metadata[capture_id] or {}
      metadata[capture_id]["conceal"] = result
    end
  end,
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

  local node = get_capture_node(match[capture_id])
  if type(metadata[capture_id]) ~= "table" then
    metadata[capture_id] = {}
  end

  -- Use dispatch table for faster lookups
  local handler = handler_dispatch[key]
  if handler then
    handler(match, _, source, predicate, metadata)
  else
    -- Fallback for unknown keys
    local node_text = get_capture_text(node, source)
    if node_text then
      metadata[capture_id][key] = node_text
    end
  end
end

local function load_queries()
  vim.treesitter.query.add_predicate("has-grandparent?", hasgrandparent, { force = true })
  vim.treesitter.query.add_directive("set-pairs!", setpairs, { force = true })

  -- Register all configured conceal types
  for _, config in pairs(conceal_config) do
    vim.treesitter.query.add_directive(config.directive_name, handle_unified(config.handler_key), { force = true })
  end

  vim.treesitter.query.add_directive("lua_func!", lua_func, { force = true })
end

---Get conceal queries
---@param language "latex" | "typst"
---@param names string[]
---@return string[] conceal_files Map of language to list of conceal query files
local function get_conceal_queries(language, names)
  local files = vim.treesitter.query.get_files(language, "highlights")

  -- Batch collect conceal files for both languages
  for _, name in ipairs(names) do
    name = "conceal_" .. name
    local conceal_files = vim.treesitter.query.get_files(language, name)
    for _, file in ipairs(conceal_files) do
      table.insert(files, file)
    end
  end

  return files
end

---Update user-defined and preamble conceal commands
---@param conceal_map table<string, string> Map of LaTeX commands to conceal characters
---@return string
local function update_latex_queries(conceal_map)
  -- Generate conceal queries from conceal_map
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

-- --- @param text string
-- --- @param pattern string?
-- --- @param type string?
-- function M.get_mathfont_conceal(text, pattern, type)
--   local out = lookup_math_symbol.lookup_math_symbol(text, pattern, type)
--   return out
-- end

---Get conceal mapping from file pramble, e.g., \newcommand{\R}{\mathbb{R}}, \renewcommand{\a}{\alpha}
---The key in the returned table has the form: { ["\\\\R"] = "\mathbb{R}", ["\\\\a"] = "\alpha", ...}
---@param bufnr integer?
---@return table<string, string> Map of LaTeX commands to conceal characters
local function get_preamble_conceal_map(bufnr)
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

  local function get_node_text(node)
    return safe_get_node_text(node, bufnr)
  end

  local definitions = {}
  for id, node, metadata in query:iter_captures(root, bufnr, 0, -1) do
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
      local cmd_text = get_node_text(def.cmd)
      local impl_text = get_node_text(def.impl)
      if not cmd_text or not impl_text then
        goto continue
      end

      while impl_text:match("^%b{}$") do
        impl_text = impl_text:sub(2, -2)
      end

      conceal_map["\\" .. cmd_text] = impl_text
    end
    ::continue::
  end

  return conceal_map
end

--- initializes the conceal queries
M.load_queries = load_queries
M.update_latex_queries = update_latex_queries
M.get_preamble_conceal_map = get_preamble_conceal_map
M.get_conceal_queries = get_conceal_queries
M.read_query_files = read_query_files
M.strip_conceal_directives = strip_conceal_directives

return M
