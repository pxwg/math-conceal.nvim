local M = {}

local notified = {}

local function notify_once(message, level)
  if notified[message] then
    return
  end
  notified[message] = true
  vim.notify("math-conceal image renderer: " .. message, level or vim.log.levels.WARN)
end

local function shallow_copy(value)
  local out = {}
  for key, item in pairs(value or {}) do
    out[key] = item
  end
  return out
end

local function resolve_scanner_override(scanner)
  if scanner == nil then
    return nil
  end
  if type(scanner) == "table" then
    return scanner
  end
  if type(scanner) ~= "string" or scanner == "" then
    return nil, "scanner override must be a renderer scanner name or scanner table"
  end

  local ok, mod = pcall(require, "math-conceal.image.renderers." .. scanner .. ".scanner")
  if not ok or type(mod) ~= "table" then
    return nil, "unsupported scanner override: " .. scanner
  end
  return mod
end

local function validate(renderer)
  if type(renderer.scanner) ~= "table" or type(renderer.scanner.scan) ~= "function" then
    return nil, "missing required scanner capability"
  end
  if type(renderer.backend) ~= "string" and type(renderer.backend) ~= "function" then
    return nil, "missing required backend capability"
  end
  for _, name in ipairs({ "build_context_document", "build_slot_document", "render_size_key" }) do
    if type(renderer[name]) ~= "function" then
      return nil, "missing required " .. name .. " capability"
    end
  end
  if renderer.flow ~= nil and type(renderer.build_flow_source) ~= "function" then
    return nil, "flow capability requires build_flow_source"
  end
  return renderer
end

function M.resolve(kind, spec)
  if type(kind) ~= "string" or kind == "" then
    return nil, "renderer name is required"
  end

  local ok, mod = pcall(require, "math-conceal.image.renderers." .. kind)
  if not ok or type(mod) ~= "table" then
    return nil, "unsupported renderer: " .. tostring(kind)
  end

  local renderer = shallow_copy(mod)
  renderer.name = renderer.name or kind
  renderer.source_kind = (spec and spec.source_kind) or renderer.source_kind or kind
  renderer.backend = (spec and spec.backend) or renderer.backend
  renderer.wrapper = (spec and spec.wrapper) or renderer.wrapper or kind

  local scanner, scanner_err = resolve_scanner_override(spec and spec.scanner or nil)
  if scanner_err ~= nil then
    return nil, scanner_err
  end
  if scanner ~= nil then
    renderer.scanner = scanner
  end

  return validate(renderer)
end

function M.resolve_or_notify(kind, spec)
  local renderer, err = M.resolve(kind, spec)
  if renderer == nil then
    notify_once(err or ("unsupported renderer: " .. tostring(kind)), vim.log.levels.WARN)
  end
  return renderer
end

return M
