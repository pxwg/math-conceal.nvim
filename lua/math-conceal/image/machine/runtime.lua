--- Runtime boundary for the full-overlay state machine.
--- Converts reducer effects into Neovim/session/extmark side effects.

local cursor_visibility = require("math-conceal.image.cursor-visibility")
local reducer = require("math-conceal.image.machine.reducer")
local resources = require("math-conceal.image.machine.resources")
local state = require("math-conceal.image.state")
local types = require("math-conceal.image.machine.types")

local M = {}

local function copy_range(range)
  if range == nil then
    return nil
  end
  return { range[1], range[2], range[3], range[4] }
end

local function ranges_equal(a, b)
  if a == nil or b == nil then
    return a == b
  end
  return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4]
end

local concealing_for_cursor
local dispatch_without_effects

local function uses_formula_manager(bufnr, main)
  if main == nil or main.config == nil then
    return false
  end
  local config = main.config
  if config.use_formula_service ~= false then
    return true
  end
  if type(main.source_kind_for_bufnr) == "function" then
    local ok, kind = pcall(main.source_kind_for_bufnr, bufnr)
    return ok and kind == "latex"
  end
  return false
end

local function formula_cursor_ui_can_batch(bufnr, main)
  if not uses_formula_manager(bufnr, main) then
    return false
  end
  if main._enabled_buffers == nil or main._enabled_buffers[bufnr] ~= true then
    return false
  end
  if type(main.is_render_allowed) == "function" and not main.is_render_allowed(bufnr) then
    return false
  end
  local mode = vim.api.nvim_get_mode().mode or ""
  if main.config.conceal_in_normal and mode:find("n", 1, true) ~= nil then
    return false
  end
  return true
end

local function cursor_line_range(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return nil, nil
  end

  local ok_cursor, cursor = pcall(vim.api.nvim_win_get_cursor, winid)
  if not ok_cursor or cursor == nil then
    return nil, nil
  end

  local row = cursor[1] - 1
  local mode = vim.api.nvim_get_mode().mode or ""
  if mode == "v" or mode == "V" or mode == "\22" then
    local visual_row = vim.fn.getpos("v")[2] - 1
    return math.min(row, visual_row), math.max(row, visual_row)
  end
  return row, row
end

local function sync_cursor_ui_now(bufnr)
  local plan = require("math-conceal.image.plan")
  local ok_main, main = pcall(require, "math-conceal.image")
  if ok_main and formula_cursor_ui_can_batch(bufnr, main) then
    local lo, hi = cursor_line_range(bufnr)
    local defer_opts = { defer_line_run_reconcile = true }
    M.sync_hover(bufnr, defer_opts)
    plan.sync_progressive_render(bufnr)
    M.render_live_preview(bufnr, defer_opts)
    if lo ~= nil then
      require("math-conceal.image.extmark").reconcile_cursor_line_runs(bufnr, lo, hi)
    end
    return
  end

  M.sync_hover(bufnr)
  plan.sync_progressive_render(bufnr)
  M.render_live_preview(bufnr)
end

local function ensure_machine_state()
  if state.machine_state == nil then
    state.machine_state = types.initial_state()
  end
  state.machine_state.ui = state.machine_state.ui or { buffers = {} }
  state.machine_state.ui.buffers = state.machine_state.ui.buffers or {}
  return state.machine_state
end

local function new_ui_buffer()
  return {
    hover = {
      last_cursor_row = nil,
      last_cursor_col = nil,
      last_mode = nil,
      last_lo = nil,
      last_hi = nil,
      invalidated = false,
    },
    preview = {
      sync_tick = nil,
      sync_needs_full = false,
      render_key = nil,
      last_render_key = nil,
      active_request_id = nil,
      next_request_id = 1,
      status = "idle",
    },
  }
end

function M.get_ui_buffer(bufnr)
  local machine_state = ensure_machine_state()
  local buffers = machine_state.ui.buffers
  if buffers[bufnr] == nil then
    buffers[bufnr] = new_ui_buffer()
  end
  return buffers[bufnr]
end

function M.invalidate_hover(bufnr)
  M.get_ui_buffer(bufnr).hover.invalidated = true
end

function M.reconcile_visible_overlay_bindings(bufnr)
  if state.formula_managers ~= nil and state.formula_managers[bufnr] ~= nil then
    return require("math-conceal.image.formula.manager").reconcile_visible_overlay_bindings(bufnr)
  end

  local machine_state = ensure_machine_state()
  local buf = machine_state.buffers[bufnr]
  if buf == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    return 0
  end

  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  local layout_version = vim.o.columns
  local repaired = 0

  for _, node_id in ipairs(buf.node_order or {}) do
    local node = buf.nodes[node_id]
    local overlay = node and node.visible_overlay_id and machine_state.overlays[node.visible_overlay_id] or nil
    if overlay ~= nil and overlay.extmark_id ~= nil then
      local ok, mark =
        pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, state.ns_id, overlay.extmark_id, { details = true })
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
        if not ranges_equal(actual_range, overlay.binding_display_range) then
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

function M.invalidate_terminal_uploads(bufnr)
  state.terminal_upload_epoch = (state.terminal_upload_epoch or 1) + 1
  if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    M.schedule_visible_overlay_refresh(bufnr, { immediate = true })
  end
  return state.terminal_upload_epoch
end

local function get_window_visible_ranges(bufnr, margin)
  local ranges = {}
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(winid) then
      local ok, range = pcall(vim.api.nvim_win_call, winid, function()
        return {
          top = math.max(0, vim.fn.line("w0") - 1 - margin),
          bottom = math.max(0, vim.fn.line("w$") - 1 + margin),
        }
      end)
      if ok and range ~= nil then
        ranges[#ranges + 1] = range
      end
    end
  end
  return ranges
end

local function overlay_screen_range(node, overlay)
  if node == nil or node.display_range == nil then
    return nil
  end
  local top = node.display_range[1]
  local bottom = node.display_range[3]
  if overlay ~= nil and overlay.natural_rows ~= nil then
    bottom = math.max(bottom, top + math.max(1, overlay.natural_rows) - 1)
  end
  return { top = top, bottom = bottom }
end

local function row_ranges_intersect(a, b)
  return a ~= nil and b ~= nil and a.top <= b.bottom and b.top <= a.bottom
end

local function overlay_intersects_any_window(node, overlay, ranges)
  local overlay_range = overlay_screen_range(node, overlay)
  for _, range in ipairs(ranges) do
    if row_ranges_intersect(overlay_range, range) then
      return true
    end
  end
  return false
end

--- Re-present already-rendered overlays in visible windows without compiling.
--- This repairs placeholder/extmark drift caused by scroll redraws while avoiding
--- the expensive full render path.
--- @param bufnr integer
--- @param opts table|nil { margin?: integer, force_reupload?: boolean, force_reupload_blocks?: boolean, skip_blocks?: boolean }
--- @return integer refreshed
function M.refresh_visible_overlays(bufnr, opts)
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return 0
  end

  return require("math-conceal.image.formula.manager").update_presentation_all(bufnr, opts)
end

function M.schedule_visible_overlay_refresh(bufnr, opts)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  opts = opts or {}
  local bs = state.get_buf_state(bufnr)
  if bs.visible_refresh_timer == nil or bs.visible_refresh_timer:is_closing() then
    bs.visible_refresh_timer = vim.uv.new_timer()
  end

  bs.visible_refresh_generation = (bs.visible_refresh_generation or 0) + 1
  local generation = bs.visible_refresh_generation
  bs.visible_refresh_timer:stop()
  bs.visible_refresh_timer:start(
    opts.immediate == true and 0 or (opts.delay_ms or 16),
    0,
    vim.schedule_wrap(function()
      if bs.visible_refresh_generation ~= generation then
        return
      end
      M.refresh_visible_overlays(bufnr, opts)
    end)
  )
end

function M.set_preview_render_key(bufnr, render_key)
  M.get_ui_buffer(bufnr).preview.render_key = render_key
end

function M.mark_preview_rendered(bufnr)
  local preview = M.get_ui_buffer(bufnr).preview
  preview.last_render_key = preview.render_key
end

function M.reset_preview_state(bufnr)
  local preview = M.get_ui_buffer(bufnr).preview
  preview.sync_tick = nil
  preview.sync_needs_full = false
  preview.render_key = nil
  preview.last_render_key = nil
  preview.active_request_id = nil
  preview.status = "idle"
end

function M.prepare_preview_request(bufnr, item)
  if item == nil then
    return nil
  end
  local preview = M.get_ui_buffer(bufnr).preview
  local n = preview.next_request_id or 1
  preview.next_request_id = n + 1
  preview.active_request_id = "preview:" .. tostring(bufnr) .. ":" .. tostring(n)
  preview.status = "rendering"
  item.preview_request_id = preview.active_request_id
  return item
end

function M.clear_preview_request(bufnr)
  local preview = M.get_ui_buffer(bufnr).preview
  preview.active_request_id = nil
  preview.status = "idle"
end

function M.accept_preview_page_update(update, opts)
  opts = opts or {}
  local preview = M.get_ui_buffer(update.bufnr).preview
  if update.preview_request_id ~= nil and update.preview_request_id ~= preview.active_request_id then
    return false
  end
  if opts.apply ~= false then
    require("math-conceal.image.apply").accept_page_update(update)
  end
  preview.status = "ready"
  return true
end

local function get_overlay_and_node(machine_state, overlay_id)
  local overlay = machine_state.overlays[overlay_id]
  if overlay == nil then
    return nil, nil, nil
  end
  local buf = machine_state.buffers[overlay.owner_bufnr]
  if buf == nil then
    return overlay, nil, nil
  end
  return overlay, buf.nodes[overlay.owner_node_id], buf
end

local function cursor_item_from_node(node)
  if node == nil then
    return nil
  end
  return {
    bufnr = node.bufnr,
    range = copy_range(node.source_range),
    display_range = copy_range(node.display_range),
    node_type = node.node_type,
    semantics = node.semantics,
  }
end

concealing_for_cursor = function(node)
  if cursor_visibility.should_preserve_source_at_cursor(node.bufnr, cursor_item_from_node(node)) then
    return false
  end
  return nil
end

--- @param _machine_state MachineState
--- @param node NodeState
--- @param overlay OverlayState
--- @return table|nil
function M.build_compat_item(_machine_state, node, overlay)
  if node == nil or overlay == nil or overlay.image_id == nil or overlay.extmark_id == nil then
    return nil
  end

  return {
    bufnr = node.bufnr,
    node_id = node.node_id,
    overlay_id = overlay.overlay_id,
    image_id = overlay.image_id,
    extmark_id = overlay.extmark_id,
    item_idx = node.item_idx,
    range = copy_range(node.source_range),
    display_range = copy_range(node.display_range),
    display_prefix = node.display_prefix,
    display_suffix = node.display_suffix,
    str = node.source_text,
    source_str = node.source_str,
    source_text = node.source_text,
    prelude_count = node.prelude_count,
    node_type = node.node_type,
    semantics = node.semantics,
    requires_mitex = node.requires_mitex,
    needs_swap = false,
    page_path = overlay.page_path,
    page_stamp = overlay.page_stamp,
    natural_cols = overlay.natural_cols,
    natural_rows = overlay.natural_rows,
    source_rows = overlay.source_rows,
    terminal_upload_epoch = overlay.terminal_upload_epoch,
  }
end

--- Rebuild the compat read model consumed by hover/live-preview code.
--- @param machine_state MachineState
--- @param bufnr integer
function M.rebuild_buffer_read_model(machine_state, bufnr)
  machine_state = machine_state or ensure_machine_state()
  if state.formula_managers ~= nil and state.formula_managers[bufnr] ~= nil then
    require("math-conceal.image.formula.manager").get(bufnr):sync_read_model()
    return
  end
  resources.rebuild_indices(machine_state, bufnr, M.build_compat_item)
end

function M.reset()
  state.machine_state = types.initial_state()
  return state.machine_state
end

function M.reset_buffer(bufnr)
  local machine_state = ensure_machine_state()
  local to_remove = {}
  for overlay_id, overlay in pairs(machine_state.overlays or {}) do
    if overlay.owner_bufnr == bufnr then
      to_remove[#to_remove + 1] = {
        overlay_id = overlay_id,
        image_id = overlay.image_id,
        extmark_id = overlay.extmark_id,
        page_path = overlay.page_path,
      }
    end
  end
  for _, entry in ipairs(to_remove) do
    resources.release_overlay_resources(bufnr, entry.image_id, entry.extmark_id)
    machine_state.overlays[entry.overlay_id] = nil
    if entry.page_path ~= nil then
      require("math-conceal.image.session")._safe_unlink_service_artifact(entry.page_path)
    end
  end
  machine_state.buffers[bufnr] = nil
  if machine_state.ui and machine_state.ui.buffers then
    machine_state.ui.buffers[bufnr] = nil
  end
  if state.active_service_requests then
    state.active_service_requests[bufnr] = nil
  end
  if state.active_formula_batches then
    state.active_formula_batches[bufnr] = nil
  end
  if state.active_preview_service_requests then
    state.active_preview_service_requests[bufnr] = nil
  end
  require("math-conceal.image.formula.manager").drop(bufnr)
  local session = require("math-conceal.image.session")
  if type(session._cleanup_service_workspace_for_buf) == "function" then
    session._cleanup_service_workspace_for_buf(bufnr)
  end
  M.rebuild_buffer_read_model(machine_state, bufnr)
end

function M.get_state()
  return ensure_machine_state()
end

dispatch_without_effects = function(event)
  local new_state = reducer.reduce(ensure_machine_state(), event)
  state.machine_state = new_state
  return new_state
end

local function allocate_image_id(bufnr)
  return resources.allocate_image_id(bufnr)
end

local function ensure_overlay_resources(overlay_id, opts)
  opts = opts or {}
  local machine_state = ensure_machine_state()
  local overlay, node = get_overlay_and_node(machine_state, overlay_id)
  if overlay == nil or node == nil then
    return nil
  end

  local image_id = overlay.image_id or allocate_image_id(overlay.owner_bufnr)
  local extmark_id = overlay.extmark_id
  if opts.place_extmark == true and extmark_id == nil then
    local concealing = opts.concealing
    if concealing == nil then
      concealing = concealing_for_cursor(node)
    end
    extmark_id = resources.place_overlay_extmark(
      overlay.owner_bufnr,
      image_id,
      node.display_range,
      nil,
      concealing,
      node.semantics
    )
  end

  if image_id ~= overlay.image_id or extmark_id ~= overlay.extmark_id then
    local binding_display_range = nil
    local binding_buffer_version = nil
    local binding_layout_version = nil
    if opts.place_extmark == true and extmark_id ~= nil then
      binding_display_range = copy_range(node.display_range)
      binding_buffer_version = overlay.buffer_version
      binding_layout_version = overlay.layout_version
    end
    dispatch_without_effects({
      type = "overlay_resources_allocated",
      overlay_id = overlay.overlay_id,
      image_id = image_id,
      extmark_id = extmark_id,
      binding_buffer_version = binding_buffer_version,
      binding_layout_version = binding_layout_version,
      binding_display_range = binding_display_range,
    })
  end

  return get_overlay_and_node(ensure_machine_state(), overlay_id)
end

--- @param machine_state MachineState
--- @param overlay_id string
--- @return RenderJob|nil
function M.build_render_job(machine_state, overlay_id)
  local overlay, node = get_overlay_and_node(machine_state, overlay_id)
  if overlay == nil or node == nil or overlay.image_id == nil then
    return nil
  end

  return {
    request_id = overlay.request_id,
    request_page_index = overlay.page_index,
    overlay_id = overlay.overlay_id,
    slot_id = overlay.slot_id or node.slot_id,
    node_id = node.node_id,
    bufnr = node.bufnr,
    project_scope_id = node.project_scope_id,
    render_epoch = overlay.render_epoch,
    node_rev = overlay.node_rev,
    context_id = overlay.context_id,
    context_rev = overlay.context_rev,
    buffer_version = overlay.buffer_version,
    layout_version = overlay.layout_version,
    item_idx = node.item_idx,
    range = copy_range(node.source_range),
    display_range = copy_range(node.display_range),
    display_prefix = node.display_prefix,
    display_suffix = node.display_suffix,
    source_text = node.source_text,
    source_text_hash = node.source_text_hash,
    backend_node_type = node.backend_node_type,
    source_str = node.source_str,
    str = node.source_text,
    requires_mitex = node.requires_mitex,
    prelude_count = node.prelude_count,
    semantics = node.semantics,
    image_id = overlay.image_id,
    extmark_id = overlay.extmark_id,
    is_stub = false,
    is_tombstone = false,
    slot_status = "dirty",
    slot_dirty = true,
  }
end

local function prepare_render_request(effect)
  local source_request = effect.request or {}
  local jobs = {}
  for _, source_job in ipairs(source_request.jobs or {}) do
    if source_job.is_stub then
      jobs[#jobs + 1] = source_job
    else
      ensure_overlay_resources(source_job.overlay_id)
      local job = M.build_render_job(ensure_machine_state(), source_job.overlay_id)
      if job ~= nil then
        jobs[#jobs + 1] = job
      end
    end
  end

  return {
    request_id = source_request.request_id,
    bufnr = source_request.bufnr,
    project_scope_id = source_request.project_scope_id,
    render_epoch = source_request.render_epoch,
    buffer_version = source_request.buffer_version,
    layout_version = source_request.layout_version,
    shape_epoch = source_request.shape_epoch,
    jobs = jobs,
  }
end

local function run_ensure_overlay_placeholder(effect)
  ensure_overlay_resources(effect.overlay_id, { place_extmark = true })
end

local function run_request_full_render(effect)
  local request = prepare_render_request(effect)
  if #request.jobs == 0 then
    return
  end
  local session = require("math-conceal.image.session")
  session.render_request_via_service(request.bufnr, request)
end

local function run_request_formula_render_batch(effect)
  local source_request = effect.request or {}
  local request =
    require("math-conceal.image.formula.manager").get(source_request.bufnr):build_render_batch_request(source_request)

  if #request.jobs == 0 then
    return
  end

  local session = require("math-conceal.image.session")
  if type(session.render_formula_batch_via_service) == "function" then
    session.render_formula_batch_via_service(request.bufnr, request)
  end
end

local function run_commit_overlay(effect, batch_mode)
  local placement =
    require("math-conceal.image.formula.manager").get(effect.bufnr):placement_for_overlay(effect.overlay_id)
  if placement ~= nil then
    return placement:commit_render(effect, batch_mode)
  end
  return nil
end

local function run_bind_overlay(effect)
  local placement =
    require("math-conceal.image.formula.manager").get(effect.bufnr):placement_for_overlay(effect.overlay_id)
  if placement ~= nil then
    return placement:bind(effect)
  end
  return nil
end

local function run_retire_overlay(effect)
  local machine_state = ensure_machine_state()
  local overlay = machine_state.overlays[effect.overlay_id]
  if overlay == nil then
    return
  end

  local bufnr = overlay.owner_bufnr
  local page_path = overlay.page_path
  local manager = require("math-conceal.image.formula.manager").get(bufnr)
  local placement = manager:placement_for_overlay(effect.overlay_id)
  if placement ~= nil then
    placement:close({ overlay_id = effect.overlay_id })
  else
    resources.release_overlay_resources(bufnr, overlay.image_id, overlay.extmark_id)
  end
  machine_state.overlays[effect.overlay_id] = nil

  -- Only delete the backing PNG when no other non-retired overlay shares the
  -- same file path.  Multiple overlays may reference the same PNG (identical
  -- pixel hash), so unconditional deletion would destroy files still needed
  -- by visible or rendering overlays.
  if page_path then
    require("math-conceal.image.session")._safe_unlink_service_artifact(page_path)
  end
  manager:sync_from_machine()
end

local function run_rerender_buffer(effect)
  require("math-conceal.image.plan").render_buf(effect.bufnr)
end

local function run_abandon_request(effect)
  local meta = state.active_service_requests and state.active_service_requests[effect.bufnr]
  if meta ~= nil and meta.request_id == effect.old_request_id then
    meta.status = "abandoned"
  end
end

local function schedule_post_commit_ui(bufnr)
  if state.hooks.on_page_committed == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local bs = state.get_buf_state(bufnr)
  bs.post_commit_ui_pending = true
  if bs.post_commit_ui_timer == nil or bs.post_commit_ui_timer:is_closing() then
    bs.post_commit_ui_timer = vim.uv.new_timer()
  end

  bs.post_commit_ui_timer:stop()
  bs.post_commit_ui_timer:start(
    16,
    0,
    vim.schedule_wrap(function()
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      local current = state.get_buf_state(bufnr)
      current.post_commit_ui_pending = false
      if state.hooks.on_page_committed then
        state.hooks.on_page_committed(bufnr)
      end
    end)
  )
end

function M.run_effects(effects)
  local commit_effects = {}
  local bind_effects = {}
  local other_effects = {}
  for _, effect in ipairs(effects or {}) do
    if effect.kind == "commit_overlay" then
      commit_effects[#commit_effects + 1] = effect
    elseif effect.kind == "bind_overlay" then
      bind_effects[#bind_effects + 1] = effect
    else
      other_effects[#other_effects + 1] = effect
    end
  end

  local extmark = require("math-conceal.image.extmark")

  for _, effect in ipairs(other_effects) do
    if effect.kind == "ensure_overlay_placeholder" then
      run_ensure_overlay_placeholder(effect)
    elseif effect.kind == "request_full_render" then
      run_request_full_render(effect)
    elseif effect.kind == "request_formula_render_batch" then
      run_request_formula_render_batch(effect)
    elseif effect.kind == "retire_overlay" then
      run_retire_overlay(effect)
    elseif effect.kind == "rerender_buffer" then
      run_rerender_buffer(effect)
    elseif effect.kind == "abandon_request" then
      run_abandon_request(effect)
    end
  end
  extmark.flush_terminal_data()

  if #bind_effects > 0 then
    local batch_entries = {}
    local affected_buffers = {}
    for _, effect in ipairs(bind_effects) do
      local entry = run_bind_overlay(effect)
      if entry ~= nil then
        batch_entries[#batch_entries + 1] = entry
        affected_buffers[entry.bufnr] = true
      end
    end
    extmark.flush_terminal_data()
    if #batch_entries > 0 then
      M.dispatch({
        type = "overlay_bindings_batch_succeeded",
        entries = batch_entries,
      })
      for bufnr in pairs(affected_buffers) do
        require("math-conceal.image.formula.manager").get(bufnr):sync_from_machine()
        M.invalidate_hover(bufnr)
      end
    end
  end

  if #commit_effects > 0 then
    local batch_entries = {}
    local affected_buffers = {}
    for _, effect in ipairs(commit_effects) do
      local entry = run_commit_overlay(effect, true)
      if entry ~= nil then
        batch_entries[#batch_entries + 1] = entry
        affected_buffers[entry.bufnr] = true
      end
    end
    extmark.flush_terminal_data()
    if #batch_entries > 0 then
      M.dispatch({
        type = "overlay_commits_batch_succeeded",
        entries = batch_entries,
      })
      for bufnr in pairs(affected_buffers) do
        require("math-conceal.image.formula.manager").get(bufnr):sync_from_machine()
        M.invalidate_hover(bufnr)
        schedule_post_commit_ui(bufnr)
      end
    end
  end
end

function M.dispatch(event, opts)
  opts = opts or {}
  local new_state, effects = reducer.reduce(ensure_machine_state(), event)
  state.machine_state = new_state
  if opts.run_effects ~= false then
    M.run_effects(effects)
  end
  return state.machine_state, effects
end

function M.render_buf(bufnr)
  require("math-conceal.image.plan").render_buf(bufnr)
end

function M.schedule_full_render(bufnr, opts)
  require("math-conceal.image.plan").schedule_full_render(bufnr, opts)
end

function M.schedule_formula_renders(bufnr, opts)
  opts = opts or {}
  return M.dispatch({
    type = "formula_renders_requested",
    bufnr = bufnr,
    node_ids = opts.node_ids,
    request_id = opts.request_id,
  })
end

function M.render_live_preview(bufnr, opts)
  opts = opts or {}
  if cursor_visibility.is_presentation_mode(bufnr) then
    require("math-conceal.image.presentation").keep_cursor_out_of_protected_range(bufnr)
    M.clear_live_preview(bufnr, opts)
    return
  end
  local ok_main, main = pcall(require, "math-conceal.image")
  if ok_main and uses_formula_manager(bufnr, main) then
    require("math-conceal.image.formula.manager").sync_cursor_preview(bufnr, opts)
    return
  end
  require("math-conceal.image.plan").render_live_typst_preview(bufnr)
end

function M.clear_live_preview(bufnr, opts)
  M.clear_preview_request(bufnr)
  require("math-conceal.image.plan").clear_live_typst_preview(bufnr, opts)
end

function M.sync_hover(bufnr, opts)
  opts = opts or {}
  local ok_main, main = pcall(require, "math-conceal.image")
  if ok_main and uses_formula_manager(bufnr, main) then
    require("math-conceal.image.formula.manager").sync_cursor_conceal(bufnr, opts)
    return
  end
  require("math-conceal.image.plan").hide_extmarks_at_cursor(bufnr)
end

function M.sync_cursor_ui(bufnr)
  require("math-conceal.image.presentation").keep_cursor_out_of_protected_range(bufnr)

  local mode = vim.api.nvim_get_mode().mode or ""
  if cursor_visibility.is_presentation_mode(bufnr) and cursor_visibility.is_visual_mode(mode) then
    sync_cursor_ui_now(bufnr)
    return
  end

  local throttle = require("math-conceal.image").config.cursor_hover_throttle_ms
  if throttle <= 0 then
    sync_cursor_ui_now(bufnr)
    return
  end

  local bs = state.get_buf_state(bufnr)
  if bs.hover.throttle_timer == nil then
    bs.hover.throttle_timer = vim.uv.new_timer()
  end
  bs.hover.throttle_timer:stop()
  bs.hover.throttle_timer:start(
    throttle,
    0,
    vim.schedule_wrap(function()
      sync_cursor_ui_now(bufnr)
    end)
  )
end

function M.schedule_live_preview_sync(bufnr, opts)
  require("math-conceal.image.plan").sync_progressive_render(bufnr)
  require("math-conceal.image.plan").schedule_live_preview_sync(bufnr, opts)
end

function M.render_preview_tail(bufnr, item)
  M.prepare_preview_request(bufnr, item)
  local session = require("math-conceal.image.session")
  session.render_preview_tail_via_service(bufnr, item)
end

return M
