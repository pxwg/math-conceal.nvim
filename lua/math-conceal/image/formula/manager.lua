--- Buffer-level formula manager.
---
--- The render viewport is chosen by the source adapter, but the side-effect
--- boundary is a single FormulaPlacement. This manager keeps persistent
--- placement indexes and answers cursor/source lookup questions; placement
--- objects perform the extmark/image mutations.

local Placement = require("math-conceal.image.formula.placement")
local cursor_visibility = require("math-conceal.image.cursor-visibility")
local state = require("math-conceal.image.state")

local M = {}
local Manager = {}
Manager.__index = Manager

local function copy_range(range)
  if range == nil then
    return nil
  end
  return { range[1], range[2], range[3], range[4] }
end

local function machine_buffer(bufnr)
  local machine_state = state.machine_state
  local buf = machine_state and machine_state.buffers and machine_state.buffers[bufnr] or nil
  return machine_state, buf
end

local function get_effective_range(item)
  return cursor_visibility.get_item_effective_range(item)
end

local function remove_from_array(items, target)
  if items == nil or target == nil then
    return
  end
  for i = #items, 1, -1 do
    if items[i] == target then
      table.remove(items, i)
    end
  end
end

local function remove_from_row_index(row_items, target)
  if row_items == nil or target == nil then
    return
  end
  for i = #row_items, 1, -1 do
    if row_items[i] == target then
      table.remove(row_items, i)
    end
  end
end

function Manager.new(bufnr)
  return setmetatable({
    bufnr = bufnr,
    placements = {},
    by_node_id = {},
    by_overlay_id = {},
    by_image_id = {},
    extmark_index = {},
    row_index = {},
    read_items = {},
    context_id = nil,
    context_rev = nil,
    last_cursor_row = nil,
    last_cursor_col = nil,
    last_mode = nil,
    last_lo = nil,
    last_hi = nil,
    preview_placement_id = nil,
  }, Manager)
end

function M.get(bufnr)
  state.formula_managers = state.formula_managers or {}
  if state.formula_managers[bufnr] == nil then
    state.formula_managers[bufnr] = Manager.new(bufnr)
  end
  return state.formula_managers[bufnr]
end

function M.has(bufnr)
  return state.formula_managers ~= nil and state.formula_managers[bufnr] ~= nil
end

function M.drop(bufnr)
  local manager = state.formula_managers and state.formula_managers[bufnr] or nil
  if manager ~= nil then
    for _, placement in pairs(manager.placements) do
      placement:close({ release = false })
    end
    state.formula_managers[bufnr] = nil
  end
end

function Manager:invalidate_hover()
  require("math-conceal.image.machine.runtime").invalidate_hover(self.bufnr)
end

function Manager:reset_indexes()
  self.by_overlay_id = {}
  self.by_image_id = {}
  self.extmark_index = {}
  self.row_index = {}
end

function Manager:reindex_placement(placement)
  if placement == nil then
    return
  end
  if placement.visible_overlay_id ~= nil then
    self.by_overlay_id[placement.visible_overlay_id] = placement
  end
  if placement.candidate_overlay_id ~= nil then
    self.by_overlay_id[placement.candidate_overlay_id] = placement
  end
  if placement.extmark_id ~= nil then
    self.extmark_index[placement.extmark_id] = placement
  end
  if placement.image_id ~= nil then
    self.by_image_id[placement.image_id] = placement
  end
  if placement.source_range ~= nil then
    for row = placement.source_range[1], placement.source_range[3] do
      self.row_index[row] = self.row_index[row] or {}
      self.row_index[row][placement.placement_id] = placement
    end
  end
end

function Manager:sync_from_machine(opts)
  opts = opts or {}
  local machine_state, buf = machine_buffer(self.bufnr)
  self:reset_indexes()
  if machine_state == nil or buf == nil then
    for _, placement in pairs(self.placements) do
      placement:close({ release = false })
    end
    self.placements = {}
    self.by_node_id = {}
    self.read_items = {}
    return self
  end

  self.context_id = buf.context_id
  self.context_rev = buf.context_rev
  local seen = {}
  for _, node_id in ipairs(buf.node_order or {}) do
    local node = buf.nodes[node_id]
    if node ~= nil and node.status ~= "deleted_confirmed" then
      local placement = self.by_node_id[node.node_id]
      if placement == nil then
        placement = Placement.new(self, machine_state, node)
        self.by_node_id[node.node_id] = placement
        self.placements[placement.placement_id] = placement
      else
        placement:update_from_machine(machine_state, node)
      end
      self:reindex_placement(placement)
      seen[node.node_id] = true
    end
  end

  local to_remove = {}
  for node_id, placement in pairs(self.by_node_id) do
    if not seen[node_id] then
      to_remove[#to_remove + 1] = { node_id = node_id, placement = placement }
    end
  end
  for _, entry in ipairs(to_remove) do
    entry.placement:close({ release = false })
    self.by_node_id[entry.node_id] = nil
    self.placements[entry.placement.placement_id] = nil
  end

  if opts.read_model ~= false then
    self:sync_read_model()
  end
  return self
end

function Manager:visible_placements()
  local placements = {}
  local _, buf = machine_buffer(self.bufnr)
  if buf == nil then
    return placements
  end
  for _, node_id in ipairs(buf.node_order or {}) do
    local placement = self.by_node_id[node_id]
    if placement ~= nil then
      local _, _, overlay = placement:resolve(placement.visible_overlay_id)
      if overlay ~= nil and overlay.status == "visible" then
        placements[#placements + 1] = placement
      end
    end
  end
  return placements
end

function Manager:placement_for_overlay(overlay_id)
  self:sync_from_machine({ read_model = false })
  return overlay_id and self.by_overlay_id[overlay_id] or nil
end

function Manager:placement_for_extmark(extmark_id)
  self:sync_from_machine({ read_model = false })
  return extmark_id and self.extmark_index[extmark_id] or nil
end

function Manager:placement_for_image(image_id)
  self:sync_from_machine({ read_model = false })
  return image_id and self.by_image_id[image_id] or nil
end

function Manager:placements_for_row(row)
  self:sync_from_machine({ read_model = false })
  return self.row_index[row] or {}
end

function Manager:placements_for_row_cached(row)
  return self.row_index[row] or {}
end

function Manager:placement_for_cursor(row, col, mode, opts)
  opts = opts or {}
  if opts.sync ~= false then
    self:sync_from_machine({ read_model = false })
  end
  local best = nil
  for _, placement in pairs(self:placements_for_row_cached(row)) do
    if placement:engages_preview(row, col, mode) then
      if best == nil then
        best = placement
      else
        local best_range = get_effective_range(best:preview_source_item())
        local placement_range = get_effective_range(placement:preview_source_item())
        if best_range == nil then
          best = placement
        elseif placement_range ~= nil then
          local best_span = (best_range[3] - best_range[1]) * 100000 + (best_range[4] - best_range[2])
          local placement_span = (placement_range[3] - placement_range[1]) * 100000
            + (placement_range[4] - placement_range[2])
          if placement_span > best_span then
            best = placement
          end
        end
      end
    end
  end
  return best
end

function Manager:remove_read_model_entry(placement)
  if placement == nil then
    return
  end
  local old = self.read_items[placement.node_id]
  if old == nil then
    return
  end

  local bstate = state.buffer_render_state[self.bufnr] or {}
  state.buffer_render_state[self.bufnr] = bstate
  remove_from_array(bstate.full_items, old)
  remove_from_array(bstate.lingering_items, old)
  if old.image_id ~= nil and state.item_by_image_id[old.image_id] == old then
    state.item_by_image_id[old.image_id] = nil
  end
  if old.image_id ~= nil and state.image_id_to_extmark[old.image_id] == old.extmark_id then
    state.image_id_to_extmark[old.image_id] = nil
  end
  if bstate.extmark_to_item ~= nil and old.extmark_id ~= nil then
    bstate.extmark_to_item[old.extmark_id] = nil
  end
  local effective_range = get_effective_range(old)
  if effective_range ~= nil and bstate.line_to_items ~= nil then
    for row = effective_range[1], effective_range[3] do
      remove_from_row_index(bstate.line_to_items[row], old)
      if bstate.line_to_items[row] ~= nil and #bstate.line_to_items[row] == 0 then
        bstate.line_to_items[row] = nil
      end
    end
  end
  self.read_items[placement.node_id] = nil
end

function Manager:replace_read_model_entry(placement, item)
  self:remove_read_model_entry(placement)
  if item == nil or item.image_id == nil or item.extmark_id == nil then
    return
  end

  local bstate = state.buffer_render_state[self.bufnr] or {}
  state.buffer_render_state[self.bufnr] = bstate
  bstate.full_items = bstate.full_items or {}
  bstate.lingering_items = bstate.lingering_items or {}
  bstate.line_to_items = bstate.line_to_items or {}
  bstate.extmark_to_item = bstate.extmark_to_item or {}

  bstate.full_items[#bstate.full_items + 1] = item
  bstate.extmark_to_item[item.extmark_id] = item
  state.item_by_image_id[item.image_id] = item
  state.image_id_to_extmark[item.image_id] = item.extmark_id
  local effective_range = get_effective_range(item)
  if effective_range ~= nil then
    for row = effective_range[1], effective_range[3] do
      bstate.line_to_items[row] = bstate.line_to_items[row] or {}
      bstate.line_to_items[row][#bstate.line_to_items[row] + 1] = item
    end
  end
  self.read_items[placement.node_id] = item
end

function Manager:sync_read_model()
  local bstate = state.buffer_render_state[self.bufnr] or {}
  state.buffer_render_state[self.bufnr] = bstate

  for _, item in pairs(self.read_items or {}) do
    if item.image_id ~= nil and state.item_by_image_id[item.image_id] == item then
      state.item_by_image_id[item.image_id] = nil
    end
    if item.image_id ~= nil and state.image_id_to_extmark[item.image_id] == item.extmark_id then
      state.image_id_to_extmark[item.image_id] = nil
    end
  end

  bstate.full_items = {}
  bstate.lingering_items = {}
  bstate.line_to_items = {}
  bstate.extmark_to_item = {}
  self.read_items = {}

  for _, placement in ipairs(self:visible_placements()) do
    local machine_state, node, overlay = placement:resolve(placement.visible_overlay_id)
    local item = placement:compat_item(machine_state, node, overlay)
    self:replace_read_model_entry(placement, item)
  end
end

function Manager:reconcile_visible_overlay_bindings()
  local machine_state, buf = machine_buffer(self.bufnr)
  if buf == nil or not vim.api.nvim_buf_is_valid(self.bufnr) then
    return 0
  end
  self:sync_from_machine({ read_model = false })

  local changedtick = vim.api.nvim_buf_get_changedtick(self.bufnr)
  local layout_version = state.visible_window_width(self.bufnr)
  local repaired = 0
  for _, placement in ipairs(self:visible_placements()) do
    local _, _, overlay = placement:resolve(placement.visible_overlay_id)
    if overlay ~= nil and overlay.extmark_id ~= nil then
      local ok, mark =
        pcall(vim.api.nvim_buf_get_extmark_by_id, self.bufnr, state.ns_id, overlay.extmark_id, { details = true })
      if ok and mark ~= nil and #mark > 0 then
        local row = mark[1]
        local col = mark[2]
        local details = mark[3] or {}
        local actual_range = {
          row,
          col,
          details.end_row or row,
          details.end_col or col,
        }
        local binding = overlay.binding_display_range
        if
          binding == nil
          or actual_range[1] ~= binding[1]
          or actual_range[2] ~= binding[2]
          or actual_range[3] ~= binding[3]
          or actual_range[4] ~= binding[4]
        then
          overlay.binding_display_range = copy_range(actual_range)
          overlay.binding_buffer_version = changedtick
          overlay.binding_layout_version = layout_version
          repaired = repaired + 1
        end
      end
    end
  end
  return repaired
end

function Manager:build_render_batch_request(source_request)
  self:sync_from_machine({ read_model = false })
  local request = {
    request_id = source_request.request_id,
    bufnr = source_request.bufnr,
    project_scope_id = source_request.project_scope_id,
    render_epoch = source_request.render_epoch,
    buffer_version = source_request.buffer_version,
    layout_version = source_request.layout_version,
    shape_epoch = source_request.shape_epoch,
    jobs = {},
  }

  for _, source_job in ipairs(source_request.jobs or {}) do
    local placement = source_job.overlay_id and self.by_overlay_id[source_job.overlay_id] or nil
    if placement ~= nil then
      placement:ensure_resources(source_job.overlay_id, { sync_manager = false })
      local job = placement:build_render_job(source_job.overlay_id)
      if job ~= nil then
        request.jobs[#request.jobs + 1] = job
      end
    end
  end
  return request
end

local function node_id_set(node_ids)
  if type(node_ids) ~= "table" then
    return nil
  end
  local set = {}
  for _, node_id in ipairs(node_ids) do
    set[node_id] = true
  end
  return set
end

--- Ensure pending/stale placements are actually backed by a render transport.
--- Returns the node ids that had to be re-scheduled.
--- @param opts table|nil
--- @return string[]
function Manager:ensure_pending_nodes_rendering(opts)
  opts = opts or {}
  self:sync_from_machine({ read_model = false })
  local _, buf = machine_buffer(self.bufnr)
  if buf == nil then
    return {}
  end

  local requested = node_id_set(opts.node_ids)
  local missing = {}
  for _, node_id in ipairs(buf.node_order or {}) do
    if requested == nil or requested[node_id] then
      local placement = self.by_node_id[node_id]
      if placement ~= nil then
        local ok_rendering = placement:ensure_rendering()
        if not ok_rendering then
          missing[#missing + 1] = node_id
        end
      end
    end
  end

  if #missing > 0 then
    require("math-conceal.image.machine.runtime").schedule_formula_renders(self.bufnr, {
      node_ids = missing,
    })
    self:sync_from_machine({ read_model = false })
  end
  return missing
end

function Manager:render_queue_node_ids()
  self:sync_from_machine({ read_model = false })
  local _, buf = machine_buffer(self.bufnr)
  if buf == nil then
    return {}
  end

  local candidates = {}
  for _, node_id in ipairs(buf.node_order or {}) do
    local node = buf.nodes[node_id]
    if
      node ~= nil
      and node.status ~= "orphaned"
      and node.status ~= "deleted_confirmed"
      and node.render_in_coverage ~= false
    then
      local slot = node.slot_id and buf.slots[node.slot_id] or nil
      local dirty = slot ~= nil
        and (slot.status == "dirty" or slot.dirty == true or node.status == "pending" or node.status == "stale")
      if dirty then
        candidates[#candidates + 1] = {
          node_id = node.node_id,
          priority = tonumber(node.render_priority) or math.huge,
          item_idx = tonumber(node.item_idx) or math.huge,
        }
      end
    end
  end

  table.sort(candidates, function(a, b)
    if a.priority ~= b.priority then
      return a.priority < b.priority
    end
    return a.item_idx < b.item_idx
  end)

  local node_ids = {}
  for _, candidate in ipairs(candidates) do
    node_ids[#node_ids + 1] = candidate.node_id
  end
  return node_ids
end

function Manager:on_rendered(entry)
  self:sync_from_machine({ read_model = false })
  local placement = self.by_node_id[entry.owner_node_id] or self.by_overlay_id[entry.overlay_id]
  if placement ~= nil then
    placement:on_rendered(entry)
  else
    require("math-conceal.image.machine.runtime").dispatch({
      type = "overlay_pages_batch_ready",
      entries = { entry },
    })
  end
end

function Manager:on_render_failed(ev)
  self:sync_from_machine({ read_model = false })
  local placement = self.by_overlay_id[ev.overlay_id]
  if placement ~= nil then
    placement:on_render_failed(ev)
  else
    require("math-conceal.image.machine.runtime").dispatch(vim.tbl_extend("force", {
      type = "overlay_render_failed",
    }, ev))
  end
end

function Manager:restore_all_hidden()
  local bs = state.get_buf_state(self.bufnr)
  local to_restore = {}
  for extmark_id in pairs(bs.currently_hidden_extmark_ids or {}) do
    to_restore[#to_restore + 1] = extmark_id
  end
  for _, extmark_id in ipairs(to_restore) do
    local placement = self.extmark_index[extmark_id]
    if placement ~= nil then
      placement:show()
    else
      bs.currently_hidden_extmark_ids[extmark_id] = nil
    end
  end
  self.last_cursor_row = nil
  self.last_cursor_col = nil
  self.last_mode = nil
  self.last_lo = nil
  self.last_hi = nil
end

function Manager:sync_cursor_conceal(opts)
  opts = opts or {}
  self:sync_from_machine({ read_model = false })
  local ok_main, main = pcall(require, "math-conceal.image")
  local bs = state.get_buf_state(self.bufnr)
  local hover = require("math-conceal.image.machine.runtime").get_ui_buffer(self.bufnr).hover

  if
    not ok_main
    or main._enabled_buffers[self.bufnr] ~= true
    or not main.is_render_allowed(self.bufnr)
    or not vim.api.nvim_buf_is_valid(self.bufnr)
  then
    self:restore_all_hidden()
    bs.currently_hidden_extmark_ids = {}
    hover.last_cursor_row = nil
    hover.last_cursor_col = nil
    hover.last_mode = nil
    hover.last_lo = nil
    hover.last_hi = nil
    hover.invalidated = false
    return true
  end

  local mode = vim.api.nvim_get_mode().mode
  if cursor_visibility.presentation_keeps_conceal(self.bufnr, mode) then
    self:restore_all_hidden()
    bs.currently_hidden_extmark_ids = {}
    hover.last_cursor_row = nil
    hover.last_cursor_col = nil
    hover.last_mode = mode
    hover.last_lo = nil
    hover.last_hi = nil
    hover.invalidated = false
    require("math-conceal.image.presentation").keep_cursor_out_of_protected_range(self.bufnr)
    return true
  end

  if main.config.conceal_in_normal and mode:find("n", 1, true) ~= nil then
    self:restore_all_hidden()
    bs.currently_hidden_extmark_ids = {}
    hover.last_cursor_row = nil
    hover.last_cursor_col = nil
    hover.last_mode = mode
    hover.last_lo = nil
    hover.last_hi = nil
    hover.invalidated = false
    return true
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_row = cursor[1] - 1
  local cursor_col = cursor[2]
  local is_visual = mode == "v" or mode == "V" or mode == "\22"
  local lo, hi = cursor_row, cursor_row
  if is_visual then
    local vrow = vim.fn.getpos("v")[2] - 1
    lo, hi = math.min(cursor_row, vrow), math.max(cursor_row, vrow)
  end

  if
    hover.last_mode == mode
    and hover.last_lo == lo
    and hover.last_hi == hi
    and hover.last_cursor_col == cursor_col
    and not hover.invalidated
  then
    return true
  end

  local should_hide = {}
  for row = lo, hi do
    for _, placement in pairs(self:placements_for_row_cached(row)) do
      if placement:should_unconceal_for_row(row, cursor_row, cursor_col, mode) then
        local _, _, overlay = placement:resolve(placement.visible_overlay_id)
        if overlay ~= nil and overlay.extmark_id ~= nil then
          should_hide[overlay.extmark_id] = placement
        end
      end
    end
  end

  local new_hidden = {}
  for extmark_id in pairs(bs.currently_hidden_extmark_ids or {}) do
    if should_hide[extmark_id] ~= nil then
      new_hidden[extmark_id] = true
    else
      local placement = self.extmark_index[extmark_id]
      if placement ~= nil then
        placement:show({ defer_line_run_reconcile = true })
      end
    end
  end

  for extmark_id, placement in pairs(should_hide) do
    if
      not (bs.currently_hidden_extmark_ids or {})[extmark_id]
      and placement:hide({ defer_line_run_reconcile = true })
    then
      new_hidden[extmark_id] = true
    end
  end

  bs.currently_hidden_extmark_ids = new_hidden
  if opts.defer_line_run_reconcile ~= true then
    require("math-conceal.image.extmark").reconcile_cursor_line_runs(self.bufnr, lo, hi)
  end
  hover.last_cursor_row = cursor_row
  hover.last_cursor_col = cursor_col
  hover.last_mode = mode
  hover.last_lo = lo
  hover.last_hi = hi
  hover.invalidated = false
  return true
end

function Manager:sync_cursor_preview(opts)
  opts = opts or {}
  if cursor_visibility.is_presentation_mode(self.bufnr) then
    if self.preview_placement_id ~= nil and self.placements[self.preview_placement_id] ~= nil then
      self.placements[self.preview_placement_id]:clear_preview(opts)
    else
      require("math-conceal.image.plan").clear_live_typst_preview(self.bufnr, opts)
    end
    self.preview_placement_id = nil
    return false
  end

  self:sync_from_machine({ read_model = false })
  local ok_main, main = pcall(require, "math-conceal.image")
  if
    not ok_main
    or main._enabled_buffers[self.bufnr] ~= true
    or not main.is_render_allowed(self.bufnr)
    or (main.config and main.config.live_preview_enabled == false)
    or not vim.api.nvim_buf_is_valid(self.bufnr)
  then
    if self.preview_placement_id ~= nil and self.placements[self.preview_placement_id] ~= nil then
      self.placements[self.preview_placement_id]:clear_preview(opts)
    else
      require("math-conceal.image.plan").clear_live_typst_preview(self.bufnr, opts)
    end
    self.preview_placement_id = nil
    return false
  end

  local winid = state.active_window_for_bufnr(self.bufnr)
  if winid == nil then
    if self.preview_placement_id ~= nil and self.placements[self.preview_placement_id] ~= nil then
      self.placements[self.preview_placement_id]:clear_preview(opts)
    else
      require("math-conceal.image.plan").clear_live_typst_preview(self.bufnr, opts)
    end
    self.preview_placement_id = nil
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local cursor_row = cursor[1] - 1
  local cursor_col = cursor[2]
  local mode = vim.api.nvim_get_mode().mode or ""
  local placement = self:placement_for_cursor(cursor_row, cursor_col, mode, { sync = false })

  if placement == nil then
    if self.preview_placement_id ~= nil and self.placements[self.preview_placement_id] ~= nil then
      self.placements[self.preview_placement_id]:clear_preview(opts)
    else
      require("math-conceal.image.plan").clear_live_typst_preview(self.bufnr, opts)
    end
    self.preview_placement_id = nil
    return false
  end

  self.preview_placement_id = placement.placement_id
  return placement:expand_preview(cursor_row, cursor_col, mode)
end

function Manager:update_presentation_all(opts)
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(self.bufnr) then
    return 0
  end

  local ok_main, main = pcall(require, "math-conceal.image")
  if not ok_main or main._enabled_buffers[self.bufnr] ~= true or not main.is_render_allowed(self.bufnr) then
    return 0
  end

  self:reconcile_visible_overlay_bindings()
  local refreshed = 0
  local uploaded = false
  local batch_opts = vim.tbl_extend("force", opts, {
    line_run_refresh_rows = opts.line_run_refresh_rows or {},
  })
  for _, placement in ipairs(self:visible_placements()) do
    local _, node = placement:resolve(placement.visible_overlay_id)
    local is_block = node ~= nil and node.semantics ~= nil and node.semantics.display_kind == "block"
    if not (opts.skip_blocks == true and is_block) then
      local did_refresh, did_upload = placement:update_presentation(batch_opts)
      if did_refresh then
        refreshed = refreshed + 1
      end
      uploaded = uploaded or did_upload
    end
  end

  if uploaded then
    require("math-conceal.image.extmark").flush_terminal_data()
  end
  return refreshed
end

--- Reconcile the whole-buffer formula scan and schedule dirty placements.
--- @param scan_event table
function M.update_from_scan(scan_event)
  local runtime = require("math-conceal.image.machine.runtime")
  local manager = M.get(scan_event.bufnr)
  runtime.dispatch(scan_event)
  manager:sync_from_machine()
  local node_ids = manager:render_queue_node_ids()
  local ret = runtime.schedule_formula_renders(scan_event.bufnr, {
    node_ids = node_ids,
  })
  manager:sync_from_machine({ read_model = false })
  manager:ensure_pending_nodes_rendering({ node_ids = node_ids })
  return ret
end

--- @param bufnr integer
--- @return table[]
function M.placements(bufnr)
  return M.get(bufnr):sync_from_machine({ read_model = false }):visible_placements()
end

--- @param bufnr integer
--- @param opts table|nil
--- @return integer refreshed
function M.update_presentation_all(bufnr, opts)
  return M.get(bufnr):update_presentation_all(opts)
end

function M.reconcile_visible_overlay_bindings(bufnr)
  return M.get(bufnr):reconcile_visible_overlay_bindings()
end

function M.sync_cursor_conceal(bufnr, opts)
  return M.get(bufnr):sync_cursor_conceal(opts)
end

function M.sync_cursor_preview(bufnr, opts)
  return M.get(bufnr):sync_cursor_preview(opts)
end

function M.ensure_pending_nodes_rendering(bufnr, opts)
  return M.get(bufnr):ensure_pending_nodes_rendering(opts)
end

function M.rendered(bufnr, entry)
  return M.get(bufnr):on_rendered(entry)
end

function M.render_failed(bufnr, ev)
  return M.get(bufnr):on_render_failed(ev)
end

function M.reattach_image(image_id, opts)
  if image_id == nil then
    return false
  end
  for _, manager in pairs(state.formula_managers or {}) do
    local placement = manager:placement_for_image(image_id)
    if placement ~= nil then
      placement:reattach_image(opts)
      require("math-conceal.image.extmark").flush_terminal_data()
      return true
    end
  end
  return false
end

return M
