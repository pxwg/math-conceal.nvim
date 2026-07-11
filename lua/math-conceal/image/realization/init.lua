local M = {}

local adapters = {}
local builtins = {
  markdown = "math-conceal.image.realization.markdown",
  typst = "math-conceal.image.realization.typst",
}

local required_methods = {
  "layout",
  "describe",
  "dispatch_batch",
  "accept_response",
  "placement_request",
}

local function validate(name, adapter)
  if type(name) ~= "string" or name == "" or type(adapter) ~= "table" then
    return false, "adapter name and table are required"
  end
  for _, method in ipairs(required_methods) do
    if type(adapter[method]) ~= "function" then
      return false, ("realization adapter %s is missing %s()"):format(name, method)
    end
  end
  return true
end

function M.register(name, adapter)
  local ok, err = validate(name, adapter)
  if not ok then
    error(err, 2)
  end
  adapters[name] = adapter
  return adapter
end

function M.get(name)
  if adapters[name] == nil and builtins[name] ~= nil then
    M.register(name, require(builtins[name]))
  end
  return adapters[name]
end

function M.require(name)
  local adapter = M.get(name)
  if adapter == nil then
    error("no realization adapter registered for source kind: " .. tostring(name), 2)
  end
  return adapter
end

function M._state()
  return { adapters = adapters }
end

return M
