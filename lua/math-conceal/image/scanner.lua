---Renderer scanner resolution for the image attachment layer.
---
---A renderer `scanner` is either a builtin scanner name or a factory
---`fun(ctx): scanner`. Factory scanners are validated on every scan so that a
---node schema change fails loudly instead of rendering stale assumptions.
local M = {}

local builtins = {
  typst = function()
    return require("math-conceal.image.tracker.typst")
  end,
  markdown = function(ctx)
    return require("math-conceal.image.tracker.markdown").new({ backslash_math = ctx.backslash_math == true })
  end,
}

local schemas = {
  typst = "math-conceal.image.tracker.typst",
}

local function supported_source_kinds()
  local kinds = vim.tbl_keys(schemas)
  table.sort(kinds)
  return table.concat(kinds, ", ")
end

---@param name string Renderer name.
---@param spec table Renderer config.
---@return string
function M.source_kind(name, spec)
  spec = spec or {}
  if spec.source_kind ~= nil then
    return spec.source_kind
  end
  if type(spec.scanner) == "string" then
    return spec.scanner
  end
  return name
end

---Logical scanner name used for tracker kind and binding identity.
---@param name string Renderer name.
---@param spec table Renderer config.
---@return string
function M.name(name, spec)
  if type(spec.scanner) == "string" then
    return spec.scanner
  end
  if type(spec.scanner) == "function" then
    return name
  end
  return M.source_kind(name, spec)
end

---@param name string Renderer name.
---@param spec table Renderer config.
function M.validate_spec(name, spec)
  local scanner = spec.scanner
  local prefix = ("math-conceal image renderer %s: "):format(name)
  if type(scanner) == "string" then
    if builtins[scanner] == nil then
      error(prefix .. ("unknown builtin scanner %q"):format(scanner), 0)
    end
    return
  end
  if scanner == nil then
    return
  end
  if type(scanner) ~= "function" then
    error(
      prefix
        .. "scanner must be a builtin scanner name or a factory function; "
        .. "wrap a module as function() return require(...) end",
      0
    )
  end
  if type(spec.source_kind) ~= "string" then
    error(prefix .. "a scanner factory requires an explicit source_kind", 0)
  end
  if schemas[spec.source_kind] == nil then
    error(
      prefix .. ("scanner factories support source_kind %s, got %q"):format(supported_source_kinds(), spec.source_kind),
      0
    )
  end
end

local function check_list(label, list, validate)
  if list == nil then
    return
  end
  if type(list) ~= "table" then
    error(label .. " must be a list", 0)
  end
  for idx, item in ipairs(list) do
    local ok, err = validate(item)
    if not ok then
      error(("%s[%d] %s"):format(label, idx, err), 0)
    end
  end
end

local function checked(label, scanner, schema)
  local function check_nodes(method, nodes, window)
    if nodes == nil then
      error(("%s.%s returned no nodes"):format(label, method), 0)
    end
    check_list(("%s.%s nodes"):format(label, method), nodes, function(node)
      local ok, err = schema._validate_node(node)
      if ok and window ~= nil and not schema._range_intersects(node, window) then
        return false, "does not intersect the scan window"
      end
      return ok, err
    end)
  end
  local function check_scan(method, result, window)
    if type(result) ~= "table" then
      error(("%s.%s must return a table"):format(label, method), 0)
    end
    if result.nodes == nil and vim.islist(result) then
      check_nodes(method, result, window)
      return result
    end
    check_nodes(method, result.nodes, window)
    check_list(("%s.%s context_units"):format(label, method), result.context_units, schema._validate_context_unit)
    return result
  end

  local wrapped = {
    scan = function(bufnr, window, context_units)
      return check_scan("scan", scanner.scan(bufnr, window, context_units), window)
    end,
    scan_context = function(bufnr)
      local result = scanner.scan_context(bufnr)
      if type(result) ~= "table" then
        error(label .. ".scan_context must return a table", 0)
      end
      check_list(label .. ".scan_context units", result.units or result.context_units, schema._validate_context_unit)
      local signature = result.signature or result.context_signature
      if signature ~= nil and type(signature) ~= "string" then
        error(label .. ".scan_context signature must be a string", 0)
      end
      return result
    end,
  }
  if scanner.scan_all ~= nil then
    wrapped.scan_all = function(bufnr)
      return check_scan("scan_all", scanner.scan_all(bufnr))
    end
  end
  if scanner.scan_nested ~= nil then
    wrapped.scan_nested = function(bufnr, container, context_units)
      return check_scan("scan_nested", scanner.scan_nested(bufnr, container, context_units))
    end
  end
  return wrapped
end

---Resolve the scanner implementation for an image binding.
---@param binding table
---@param spec table Renderer config.
---@return table? scanner
---@return string? err
function M.resolve(binding, spec)
  local factory = spec.scanner
  if type(factory) ~= "function" then
    local name = binding.scanner
    local builtin = builtins[name]
    if builtin == nil then
      return nil, ("unsupported scanner: %s"):format(tostring(name))
    end
    return builtin(binding)
  end

  local label = ("renderer %s scanner"):format(binding.kind)
  local ok, scanner = pcall(factory, vim.deepcopy(binding))
  if not ok then
    return nil, ("%s factory failed: %s"):format(label, tostring(scanner))
  end
  if type(scanner) ~= "table" then
    return nil, ("%s factory must return a table, got %s"):format(label, type(scanner))
  end
  for _, method in ipairs({ "scan", "scan_context" }) do
    if type(scanner[method]) ~= "function" then
      return nil, ("%s is missing %s()"):format(label, method)
    end
  end
  for _, method in ipairs({ "scan_all", "scan_nested" }) do
    if scanner[method] ~= nil and type(scanner[method]) ~= "function" then
      return nil, ("%s.%s must be a function"):format(label, method)
    end
  end
  local schema_module = schemas[binding.source_kind]
  if schema_module == nil then
    return nil, ("%s has unsupported source_kind %s"):format(label, tostring(binding.source_kind))
  end
  return checked(label, scanner, require(schema_module))
end

return M
