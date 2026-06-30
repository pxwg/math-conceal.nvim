local window_node_slot = require("math-conceal.image.placement.window-node-slot")

local M = {}

local backends = {
  window_node_slot = window_node_slot,
}

window_node_slot.setup()

local function backend_for_intent(intent)
  if intent == nil then
    return nil
  end
  local name = intent.backend or "window_node_slot"
  return backends[name]
end

function M.available(name)
  local backend = backends[name or "window_node_slot"]
  return backend ~= nil and (type(backend.available) ~= "function" or backend.available())
end

function M.sync(bufnr, intent)
  local backend = backend_for_intent(intent)
  if backend == nil or type(backend.sync) ~= "function" then
    return false
  end
  return backend.sync(bufnr, intent)
end

function M.close_key(bufnr, key)
  for _, backend in pairs(backends) do
    if type(backend.close_key) == "function" then
      backend.close_key(bufnr, key)
    end
  end
end

function M.close_all(bufnr)
  for _, backend in pairs(backends) do
    if type(backend.close_all) == "function" then
      backend.close_all(bufnr)
    end
  end
end

function M.reconcile(bufnr, keep_keys)
  for _, backend in pairs(backends) do
    if type(backend.reconcile) == "function" then
      backend.reconcile(bufnr, keep_keys)
    end
  end
end

function M.refresh_buf(bufnr)
  local changed = false
  for _, backend in pairs(backends) do
    if type(backend.refresh_buf) == "function" then
      changed = backend.refresh_buf(bufnr) or changed
    end
  end
  return changed
end

function M.refresh_geometry(bufnr, opts)
  local changed = false
  for _, backend in pairs(backends) do
    if type(backend.refresh_geometry) == "function" then
      changed = backend.refresh_geometry(bufnr, opts) or changed
    end
  end
  return changed
end

function M.batch(fn)
  if type(fn) ~= "function" then
    return nil
  end
  return fn()
end

function M._state()
  return {
    window_node_slot = window_node_slot._state(),
  }
end

return M
