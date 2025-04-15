local M = {}

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
local function lua_func(match, _, source, predicate, metadata)
  -- (#lua_func! @capture key value)
  local capture_id = predicate[2]
  local node = match[capture_id]
  -- Exit early if node is nil
  if not node then
    return
  end
  -- Get the node text (for possible future use)
  local node_text = vim.treesitter.get_node_text(node, source)
  local key = predicate[3] or "conceal"
  local value = predicate[4] or "font"
  if type(metadata[capture_id]) ~= "table" then
    metadata[capture_id] = {}
  end
  metadata[capture_id][key] = M.get_mathfont_conceal(node_text)
end

--- @param args LaTeXConcealOptions
local function load_queries(args)
  vim.treesitter.query.add_predicate("has-grandparent?", hasgrandparent, { force = true })
  vim.treesitter.query.add_directive("set-pairs!", setpairs, { force = true })
  vim.treesitter.query.add_directive("lua_func!", lua_func, { force = true })
  local out = vim.treesitter.query.get_files("latex", "highlights")
  -- local out = {}
  for _, name in ipairs(args.conceal) do
    local files = vim.api.nvim_get_runtime_file("queries_config/latex/conceal_" .. name .. ".scm", true)
    for _, file in ipairs(files) do
      table.insert(out, file)
    end
  end
  local strings = read_query_files(out)
  vim.treesitter.query.set("latex", "highlights", strings)
end

--- @param text string
function M.get_mathfont_conceal(text)
  local out = require("utils.latex_conceal").lookup_math_symbol(text)
  return out or text
end

--- initializes the conceal queries
M.load_queries = load_queries

return M
