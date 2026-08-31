local M = {}

---@type table<integer, table>
local services = {}
local send_next_payload

-- One process per buffer, with independent request ownership per lane.
local FULL_LANE = "full"
local PREVIEW_LANE = "preview"

local function notify(message, level)
  vim.schedule(function()
    vim.notify("[math-conceal.image] " .. message, level or vim.log.levels.WARN)
  end)
end

local function service_for(bufnr)
  services[bufnr] = services[bufnr]
    or {
      bufnr = bufnr,
      line_buffer = "",
      stderr_buffer = "",
      active = {},
      active_request_ids = {},
    }
  return services[bufnr]
end

local function lane_for_meta(meta)
  return meta ~= nil and meta.kind == "live_preview" and PREVIEW_LANE or FULL_LANE
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

local function queue_payload(service, lane, payload, meta)
  if lane == PREVIEW_LANE then
    service.pending_preview = copy_request(payload, meta)
    return true
  end

  local bucket =
    table.concat({ payload and payload.type or "render_formulas", payload and payload.cache_key or "" }, "\0")
  service.pending_full = service.pending_full or { order = {}, by_key = {} }
  if service.pending_full.by_key[bucket] == nil then
    service.pending_full.order[#service.pending_full.order + 1] = bucket
  end
  service.pending_full.by_key[bucket] = merged_full_request(service.pending_full.by_key[bucket], payload, meta)
  return true
end

local function send_payload(service, lane, payload, meta)
  local ok, json = pcall(vim.json.encode, payload)
  if not ok then
    notify("failed to encode render request: " .. tostring(json), vim.log.levels.ERROR)
    return false
  end

  meta = meta or {}
  meta.expected = #(payload.nodes or {})
  meta.received = 0
  meta.request_id = payload.request_id
  meta.lane = lane
  service.active[payload.request_id] = meta
  service.active_request_ids[lane] = payload.request_id

  local sent = vim.fn.chansend(service.job_id, json .. "\n")
  if sent == 0 then
    service.active[payload.request_id] = nil
    if service.active_request_ids[lane] == payload.request_id then
      service.active_request_ids[lane] = nil
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
  local key = table.remove(pending.order, 1)
  local next_payload = key and pending.by_key[key] or nil
  if key ~= nil then
    pending.by_key[key] = nil
  end
  if #pending.order == 0 then
    service.pending_full = nil
  end
  return next_payload
end

send_next_payload = function(service, lane)
  if service == nil or service.active_request_ids[lane] ~= nil or service.job_id == nil then
    return
  end

  local next_payload
  if lane == PREVIEW_LANE then
    next_payload = service.pending_preview
    service.pending_preview = nil
  else
    next_payload = pop_pending_full(service)
  end

  if next_payload ~= nil and not send_payload(service, lane, next_payload.payload, next_payload.meta) then
    send_next_payload(service, lane)
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
      local lane = meta.lane or FULL_LANE
      if service.active_request_ids[lane] == decoded.request_id then
        service.active_request_ids[lane] = nil
      end
      send_next_payload(service, lane)
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

function M.ensure(bufnr, binding, _kind)
  local service = service_for(bufnr)
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
      if services[bufnr] == service then
        services[bufnr] = nil
      end
      if code ~= 0 and service.stopping ~= true then
        notify("service exited with code " .. tostring(code), vim.log.levels.WARN)
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
  local lane = lane_for_meta(meta)
  local service = M.ensure(bufnr, binding)
  if service == nil or service.job_id == nil then
    return false
  end

  if service.active_request_ids[lane] ~= nil then
    return queue_payload(service, lane, payload, meta)
  end

  return send_payload(service, lane, payload, meta)
end

function M.render_code_flow(bufnr, binding, payload, meta)
  meta = meta or {}
  local service = M.ensure(bufnr, binding)
  if service == nil or service.job_id == nil then
    return false
  end

  if service.active_request_ids[FULL_LANE] ~= nil then
    return queue_payload(service, FULL_LANE, payload, meta)
  end

  return send_payload(service, FULL_LANE, payload, meta)
end

function M.cancel_live_preview(bufnr)
  local service = services[bufnr]
  if service ~= nil then
    service.pending_preview = nil
  end
end

function M.prune_full(bufnr, wanted_realizations)
  local service = services[bufnr]
  local pending = service and service.pending_full or nil
  if pending == nil then
    return
  end
  wanted_realizations = wanted_realizations or {}
  local retained_order = {}
  for _, bucket in ipairs(pending.order) do
    local request = pending.by_key[bucket]
    local nodes = {}
    local node_meta = {}
    for _, node in ipairs((request and request.payload and request.payload.nodes) or {}) do
      local descriptor = request.meta.node_meta and request.meta.node_meta[node.node_id] or nil
      local key = descriptor and (descriptor.key or (descriptor.meta and descriptor.meta.realization_key)) or nil
      if key ~= nil and wanted_realizations[key] == true then
        nodes[#nodes + 1] = node
        node_meta[node.node_id] = descriptor
      end
    end
    if #nodes > 0 then
      request.payload.nodes = nodes
      request.meta.node_meta = node_meta
      request.meta.expected = #nodes
      retained_order[#retained_order + 1] = bucket
    else
      pending.by_key[bucket] = nil
    end
  end
  pending.order = retained_order
  if #retained_order == 0 then
    service.pending_full = nil
  end
end

local function lane_idle(service, lane)
  if service == nil then
    return true
  end
  if service.active_request_ids[lane] ~= nil then
    return false
  end
  if lane == PREVIEW_LANE then
    return service.pending_preview == nil
  end
  return service.pending_full == nil or #service.pending_full.order == 0
end

local function service_idle(service)
  return lane_idle(service, FULL_LANE) and lane_idle(service, PREVIEW_LANE) and next(service.active or {}) == nil
end

local function reset_preview_lane(service)
  if service ~= nil and service.job_id ~= nil then
    pcall(vim.fn.chansend, service.job_id, vim.json.encode({ type = "reset_lane", lane = PREVIEW_LANE }) .. "\n")
  end
end

local function stop_service(service)
  if service ~= nil and service.job_id ~= nil then
    service.stopping = true
    pcall(vim.fn.chansend, service.job_id, vim.json.encode({ type = "shutdown" }) .. "\n")
    pcall(vim.fn.jobstop, service.job_id)
  end
end

function M.stop_if_idle(bufnr, kind)
  local service = services[bufnr]
  if service == nil then
    return true
  end

  if kind == PREVIEW_LANE then
    if not lane_idle(service, PREVIEW_LANE) then
      return false
    end
    service.pending_preview = nil
    reset_preview_lane(service)
    return true
  end

  if not service_idle(service) then
    return false
  end
  M.stop(bufnr)
  return true
end

function M.stop(bufnr, kind)
  local service = services[bufnr]
  if service == nil then
    return
  end

  if kind == PREVIEW_LANE then
    service.pending_preview = nil
    reset_preview_lane(service)
    return
  end

  stop_service(service)
  services[bufnr] = nil
end

function M._state()
  return services
end

return M
