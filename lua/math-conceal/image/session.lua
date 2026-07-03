local M = {}

---@type table<integer, table>
local services = {}
local send_next_payload

local function notify(message, level)
  vim.schedule(function()
    vim.notify("[math-conceal.image] " .. message, level or vim.log.levels.WARN)
  end)
end

local function service_for(bufnr, kind)
  kind = kind or "full"
  services[bufnr] = services[bufnr] or {}
  services[bufnr][kind] = services[bufnr][kind]
    or {
      bufnr = bufnr,
      kind = kind,
      line_buffer = "",
      stderr_buffer = "",
      active = {},
    }
  return services[bufnr][kind]
end

local function service_kind_for_meta(meta)
  return meta ~= nil and meta.kind == "live_preview" and "preview" or "full"
end

local function same_full_context(left, right)
  if left == nil or right == nil then
    return false
  end
  for _, key in ipairs({
    "type",
    "backend",
    "cache_key",
    "context_id",
    "context_rev",
    "context_source",
    "flow_context_source",
    "root",
    "inputs",
    "output_dir",
    "ppi",
    "worker_count",
  }) do
    if type(left[key]) == "table" or type(right[key]) == "table" then
      if not vim.deep_equal(left[key], right[key]) then
        return false
      end
    elseif left[key] ~= right[key] then
      return false
    end
  end
  return true
end

local function copy_request(payload, meta)
  return {
    payload = vim.deepcopy(payload),
    meta = vim.deepcopy(meta or {}),
  }
end

local function merged_full_request(existing, payload, meta)
  if existing == nil or not same_full_context(existing.payload, payload) then
    return copy_request(payload, meta)
  end

  local merged = copy_request(payload, meta)
  local by_node = {}
  local order = {}

  local function add_node(node, node_meta)
    if node == nil or node.node_id == nil then
      return
    end
    if by_node[node.node_id] == nil then
      order[#order + 1] = node.node_id
    end
    by_node[node.node_id] = vim.deepcopy(node)
    if node_meta ~= nil then
      merged.meta.node_meta = merged.meta.node_meta or {}
      merged.meta.node_meta[node.node_id] = vim.deepcopy(node_meta)
    end
  end

  for _, node in ipairs(existing.payload.nodes or {}) do
    add_node(node, existing.meta.node_meta and existing.meta.node_meta[node.node_id] or nil)
  end
  for _, node in ipairs(payload.nodes or {}) do
    add_node(node, meta and meta.node_meta and meta.node_meta[node.node_id] or nil)
  end

  merged.payload.nodes = {}
  for _, node_id in ipairs(order) do
    merged.payload.nodes[#merged.payload.nodes + 1] = by_node[node_id]
  end
  merged.payload.request_id = payload.request_id
  merged.meta.request_id = payload.request_id
  return merged
end

local function queue_payload(service, payload, meta)
  if meta ~= nil and meta.kind == "live_preview" then
    service.pending_preview = copy_request(payload, meta)
    return true
  end

  local bucket = payload and payload.type or "render_formulas"
  service.pending_full = service.pending_full or {}
  service.pending_full[bucket] = merged_full_request(service.pending_full[bucket], payload, meta)
  return true
end

local function send_payload(service, payload, meta)
  local ok, json = pcall(vim.json.encode, payload)
  if not ok then
    notify("failed to encode render request: " .. tostring(json), vim.log.levels.ERROR)
    return false
  end

  meta = meta or {}
  meta.expected = #(payload.nodes or {})
  meta.received = 0
  meta.request_id = payload.request_id
  service.active[payload.request_id] = meta
  service.active_request_id = payload.request_id

  local sent = vim.fn.chansend(service.job_id, json .. "\n")
  if sent == 0 then
    service.active[payload.request_id] = nil
    if service.active_request_id == payload.request_id then
      service.active_request_id = nil
    end
    notify("failed to write render request", vim.log.levels.ERROR)
    return false
  end

  return true
end

local function pop_pending_full(service)
  local pending = service.pending_full
  if pending == nil then
    return nil
  end

  for _, key in ipairs({ "render_formulas", "render_code_flow" }) do
    local next_payload = pending[key]
    if next_payload ~= nil then
      pending[key] = nil
      if next(pending) == nil then
        service.pending_full = nil
      end
      return next_payload
    end
  end

  local key, next_payload = next(pending)
  if key ~= nil then
    pending[key] = nil
    if next(pending) == nil then
      service.pending_full = nil
    end
  end
  return next_payload
end

send_next_payload = function(service)
  if service == nil or service.active_request_id ~= nil or service.job_id == nil then
    return
  end

  local next_payload = pop_pending_full(service)
  if next_payload == nil then
    next_payload = service.pending_preview
    service.pending_preview = nil
  end

  if next_payload ~= nil and not send_payload(service, next_payload.payload, next_payload.meta) then
    send_next_payload(service)
  end
end

local function handle_line(service, line)
  if line == "" then
    return
  end

  local ok, decoded = pcall(vim.json.decode, line)
  if not ok or type(decoded) ~= "table" then
    notify("failed to decode service response: " .. tostring(decoded), vim.log.levels.WARN)
    return
  end

  local bufnr = service.bufnr
  local meta = service and service.active and service.active[decoded.request_id] or nil
  require("math-conceal.image.projection").handle_service_response(bufnr, decoded, meta)

  if meta ~= nil then
    meta.received = (meta.received or 0) + 1
    if meta.received >= (meta.expected or 1) then
      service.active[decoded.request_id] = nil
      if service.active_request_id == decoded.request_id then
        service.active_request_id = nil
      end
      send_next_payload(service)
    end
  end
end

local function on_stdout(service, _, data)
  if service == nil or type(data) ~= "table" then
    return
  end

  if #data == 0 then
    return
  end

  service.line_buffer = service.line_buffer .. (data[1] or "")
  for idx = 2, #data do
    handle_line(service, service.line_buffer)
    service.line_buffer = data[idx] or ""
  end
end

local function on_stderr(bufnr, _, data)
  if type(data) ~= "table" then
    return
  end
  local text = table.concat(
    vim.tbl_filter(function(line)
      return line ~= ""
    end, data),
    "\n"
  )
  if text ~= "" then
    notify("service stderr: " .. text, vim.log.levels.DEBUG)
  end
end

function M.ensure(bufnr, binding, kind)
  local service = service_for(bufnr, kind)
  if service.job_id ~= nil and vim.fn.jobwait({ service.job_id }, 0)[1] == -1 then
    return service
  end

  local binary = binding and binding.service_binary or "typst-concealer-service"
  if vim.fn.executable(binary) ~= 1 and vim.uv.fs_stat(binary) == nil then
    local message = "service binary not found: " .. tostring(binary)
    if binary == "typst-concealer-service" or binary == "typst-concealer-service.exe" then
      message = message
        .. ". Install math-conceal-service with :Rocks install math-conceal-service, or set image.renderers.<name>.service_binary."
    end
    notify(message, vim.log.levels.ERROR)
    return nil
  end

  service.job_id = vim.fn.jobstart({ binary }, {
    stdin = "pipe",
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = function(job_id, data)
      on_stdout(service, job_id, data)
    end,
    on_stderr = function(job_id, data)
      on_stderr(bufnr, job_id, data)
    end,
    on_exit = function(_, code)
      local bucket = services[bufnr]
      local current = bucket and bucket[service.kind] or nil
      if current == service then
        bucket[service.kind] = nil
        if next(bucket) == nil then
          services[bufnr] = nil
        end
      end
      if code ~= 0 and service.stopping ~= true then
        notify(service.kind .. " service exited with code " .. tostring(code), vim.log.levels.WARN)
      end
    end,
  })

  if service.job_id <= 0 then
    notify("failed to start service: " .. tostring(binary), vim.log.levels.ERROR)
    service.job_id = nil
    return nil
  end

  return service
end

function M.render_formulas(bufnr, binding, payload, meta)
  meta = meta or {}
  local service = M.ensure(bufnr, binding, service_kind_for_meta(meta))
  if service == nil or service.job_id == nil then
    return false
  end

  if service.active_request_id ~= nil then
    return queue_payload(service, payload, meta)
  end

  return send_payload(service, payload, meta)
end

function M.render_code_flow(bufnr, binding, payload, meta)
  meta = meta or {}
  meta.kind = "code_flow_render"
  local service = M.ensure(bufnr, binding, "full")
  if service == nil or service.job_id == nil then
    return false
  end

  if service.active_request_id ~= nil then
    return queue_payload(service, payload, meta)
  end

  return send_payload(service, payload, meta)
end

function M.cancel_live_preview(bufnr)
  local bucket = services[bufnr]
  local service = bucket and bucket.preview or nil
  if service ~= nil then
    service.pending_preview = nil
  end
end

function M.stop(bufnr)
  local bucket = services[bufnr]
  if bucket == nil then
    return
  end

  for _, service in pairs(bucket) do
    if service.job_id ~= nil then
      service.stopping = true
      pcall(vim.fn.chansend, service.job_id, vim.json.encode({ type = "shutdown" }) .. "\n")
      pcall(vim.fn.jobstop, service.job_id)
    end
  end
  services[bufnr] = nil
end

return M
