--- Per-formula presentation owner.
---
--- A placement is the side-effect boundary for one formula node.  It owns the
--- node's extmark/image binding, terminal upload state, hide/show state, and
--- render response routing.  The reducer remains the logical source of truth;
--- this object mirrors enough state to keep UI effects local to one node.

local FormulaImage = require("math-conceal.image.formula.image")
local cursor_visibility = require("math-conceal.image.cursor-visibility")
local resources = require("math-conceal.image.machine.resources")
local state = require("math-conceal.image.state")

local M = {}
M.__index = M

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

local function range_key(range)
  if range == nil then
    return "-"
  end
  return table.concat({ range[1], range[2], range[3], range[4] }, ",")
end

local function display_width_for_bufnr(bufnr)
  if bufnr == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    return vim.o.columns
  end
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 and vim.api.nvim_win_is_valid(winid) then
    return vim.api.nvim_win_get_width(winid)
  end
  return vim.o.columns
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

--- @param manager table
--- @param machine_state MachineState
--- @param node NodeState
function M.new(manager, machine_state, node)
  local placement = setmetatable({
    manager = manager,
    machine_state = machine_state,
    bufnr = node.bufnr,
    node_id = node.node_id,
    placement_id = node.node_id,
    hidden = false,
    pending_render = nil,
    image = nil,
    preview_item = nil,
    preview_render_key = nil,
  }, M)
  placement:update_from_machine(machine_state, node)
  return placement
end

function M:resolve(overlay_id)
  local machine_state = state.machine_state or self.machine_state
  local buf = machine_state and machine_state.buffers and machine_state.buffers[self.bufnr] or nil
  local node = buf and buf.nodes and buf.nodes[self.node_id] or nil
  local target_overlay_id = overlay_id or self.visible_overlay_id or self.overlay_id
  local overlay = target_overlay_id and machine_state.overlays and machine_state.overlays[target_overlay_id] or nil
  return machine_state, node, overlay, buf
end

function M:update_from_machine(machine_state, node)
  machine_state = machine_state or state.machine_state
  local buf = machine_state.buffers and machine_state.buffers[node.bufnr] or nil
  local visible = node.visible_overlay_id and machine_state.overlays[node.visible_overlay_id] or nil
  local candidate = node.candidate_overlay_id and machine_state.overlays[node.candidate_overlay_id] or nil
  local overlay = visible or candidate

  self.machine_state = machine_state
  self.bufnr = node.bufnr
  self.node_id = node.node_id
  self.placement_id = node.node_id
  self.stable_key = node.stable_key
  self.node_rev = node.node_rev
  self.source_hash = node.source_text_hash
  self.context_id = (visible and visible.context_id) or (candidate and candidate.context_id) or (buf and buf.context_id)
  self.context_rev = (visible and visible.context_rev)
    or (candidate and candidate.context_rev)
    or (buf and buf.context_rev)
  self.display_range = copy_range(node.display_range)
  self.source_range = copy_range(node.source_range)
  self.semantics = node.semantics
  self.visible_overlay_id = visible and visible.overlay_id or nil
  self.candidate_overlay_id = candidate and candidate.overlay_id or nil
  self.overlay_id = overlay and overlay.overlay_id or self.visible_overlay_id or self.candidate_overlay_id
  self.extmark_id = visible and visible.extmark_id or nil
  self.image_id = visible and visible.image_id or nil
  self.artifact = visible
      and {
        artifact_key = visible.page_stamp or visible.page_path,
        page_path = visible.page_path,
        page_stamp = visible.page_stamp,
      }
    or self.artifact
  self.natural_cols = visible and visible.natural_cols or nil
  self.natural_rows = visible and visible.natural_rows or nil
  self.terminal_upload_epoch = visible and visible.terminal_upload_epoch or self.terminal_upload_epoch

  if candidate ~= nil then
    self.pending_render = {
      job_id = candidate.request_id,
      request_id = candidate.request_id,
      overlay_id = candidate.overlay_id,
      node_rev = candidate.node_rev,
      context_id = candidate.context_id,
      context_rev = candidate.context_rev,
    }
  else
    self.pending_render = nil
  end

  if visible ~= nil and visible.image_id ~= nil then
    if self.image == nil then
      self.image = FormulaImage.new({
        overlay_id = visible.overlay_id,
        page_path = visible.page_path,
        page_stamp = visible.page_stamp,
        image_id = visible.image_id,
        natural_cols = visible.natural_cols,
        natural_rows = visible.natural_rows,
        source_rows = visible.source_rows,
        sent_epoch = visible.terminal_upload_epoch,
      })
      self.image:attach(self)
    else
      self.image:update({
        overlay_id = visible.overlay_id,
        page_path = visible.page_path,
        page_stamp = visible.page_stamp,
        image_id = visible.image_id,
        natural_cols = visible.natural_cols,
        natural_rows = visible.natural_rows,
        source_rows = visible.source_rows,
        sent_epoch = visible.terminal_upload_epoch,
      })
    end
  end
end

function M:compat_item(machine_state, node, overlay)
  machine_state = machine_state or state.machine_state or self.machine_state
  node = node or select(2, self:resolve())
  overlay = overlay or select(3, self:resolve())
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

function M:concealing_for_cursor(node)
  if
    require("math-conceal.image.cursor-visibility").should_preserve_source_at_cursor(
      node.bufnr,
      cursor_item_from_node(node)
    )
  then
    return false
  end
  return nil
end

function M:should_unconceal_for_row(row, cursor_row, cursor_col, mode)
  local item = {
    bufnr = self.bufnr,
    range = copy_range(self.source_range),
    display_range = copy_range(self.display_range),
    node_type = "math",
    semantics = self.semantics,
  }
  return require("math-conceal.image.cursor-visibility").should_unconceal_item_for_row(
    item,
    row,
    cursor_row,
    cursor_col,
    mode
  )
end

function M:preview_source_item()
  local machine_state, node, overlay = self:resolve(self.visible_overlay_id)
  if
    node == nil
    or overlay == nil
    or node.node_type ~= "math"
    or overlay.status ~= "visible"
    or overlay.image_id == nil
    or overlay.extmark_id == nil
  then
    return nil
  end
  return self:compat_item(machine_state, node, overlay)
end

function M:engages_preview(row, col, mode)
  local item = self:preview_source_item()
  local effective_range = cursor_visibility.get_item_effective_range(item)
  return effective_range ~= nil and cursor_visibility.cursor_engages_inline_item(effective_range, row, col, mode)
end

function M:expand_preview(cursor_row, cursor_col, mode)
  local item = self:preview_source_item()
  if item == nil then
    self:clear_preview()
    return false
  end

  local ok, preview_item, render_key = require("math-conceal.image.plan").render_live_typst_preview_for_item(
    self.bufnr,
    item,
    cursor_row,
    cursor_col,
    mode
  )
  if ok then
    self.preview_item = preview_item
    self.preview_render_key = render_key
  end
  return ok
end

function M:clear_preview(opts)
  local bs = state.get_buf_state(self.bufnr)
  local preview_item = bs.preview_item or bs.preview_last_rendered_item
  if self.preview_item ~= nil or (preview_item ~= nil and preview_item.node_id == self.node_id) then
    require("math-conceal.image.plan").clear_live_typst_preview(self.bufnr, opts)
  end
  self.preview_item = nil
  self.preview_render_key = nil
end

function M:ensure_resources(overlay_id, opts)
  opts = opts or {}
  local machine_state, node, overlay = self:resolve(overlay_id)
  if machine_state == nil or node == nil or overlay == nil then
    return nil
  end

  local image_id = overlay.image_id or resources.allocate_image_id(overlay.owner_bufnr)
  local extmark_id = overlay.extmark_id
  if opts.place_extmark == true and extmark_id == nil then
    extmark_id = resources.place_overlay_extmark(
      overlay.owner_bufnr,
      image_id,
      node.display_range,
      nil,
      opts.concealing == nil and self:concealing_for_cursor(node) or opts.concealing,
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
    require("math-conceal.image.machine.runtime").dispatch({
      type = "overlay_resources_allocated",
      overlay_id = overlay.overlay_id,
      image_id = image_id,
      extmark_id = extmark_id,
      binding_buffer_version = binding_buffer_version,
      binding_layout_version = binding_layout_version,
      binding_display_range = binding_display_range,
    }, { run_effects = false })
  end

  if opts.sync_manager ~= false then
    self.manager:sync_from_machine({ read_model = false })
  end
  return select(3, self:resolve(overlay_id))
end

function M:build_render_job(overlay_id)
  local _, node, overlay = self:resolve(overlay_id)
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

local function node_wants_render(node)
  return node ~= nil and node.status ~= "stable" and node.status ~= "orphaned" and node.status ~= "deleted_confirmed"
end

function M:rendering_status()
  local _, node, candidate, buf = self:resolve(self.candidate_overlay_id)
  if node == nil or buf == nil then
    return "missing"
  end
  if not node_wants_render(node) and node.candidate_overlay_id == nil then
    return "stable"
  end
  if node.candidate_overlay_id == nil then
    return "unscheduled"
  end
  if candidate == nil or candidate.status == "retiring" or candidate.status == "retired" then
    return "unscheduled"
  end

  local rendering = require("math-conceal.image.session").formula_candidate_is_rendering(self.bufnr, {
    request_id = candidate.request_id,
    overlay_id = candidate.overlay_id,
    node_id = node.node_id,
    node_rev = candidate.node_rev,
    context_id = candidate.context_id,
    context_rev = candidate.context_rev,
    source_text_hash = candidate.source_text_hash,
    layout_version = candidate.layout_version,
  })
  return rendering and "rendering" or "orphan_candidate"
end

--- Check that this placement has a live render transport if it needs one.
--- @return boolean ok
--- @return string status
function M:ensure_rendering()
  local status = self:rendering_status()
  if status == "orphan_candidate" then
    local _, _, candidate = self:resolve(self.candidate_overlay_id)
    if candidate ~= nil then
      require("math-conceal.image.machine.runtime").dispatch({
        type = "overlay_render_failed",
        request_id = candidate.request_id,
        overlay_id = candidate.overlay_id,
        node_rev = candidate.node_rev,
        context_id = candidate.context_id,
        context_rev = candidate.context_rev,
        reason = "formula candidate lost render transport",
      })
    end
    return false, status
  end
  if status == "unscheduled" then
    return false, status
  end
  return true, status
end

function M:update_presentation(opts)
  opts = opts or {}
  local machine_state, node, overlay = self:resolve(self.visible_overlay_id)
  if
    machine_state == nil
    or node == nil
    or overlay == nil
    or overlay.status ~= "visible"
    or overlay.image_id == nil
    or overlay.page_path == nil
    or overlay.natural_cols == nil
    or overlay.natural_rows == nil
  then
    self.manager:remove_read_model_entry(self)
    return false, false
  end

  local extmark = require("math-conceal.image.extmark")
  local extmark_id = overlay.extmark_id
  local concealing = self:concealing_for_cursor(node)
  local force_upload = opts.force_reupload == true
    or (opts.force_reupload_blocks == true and node.semantics ~= nil and node.semantics.display_kind == "block")
  local presentation_key = table.concat({
    tostring(overlay.overlay_id),
    tostring(overlay.image_id),
    tostring(extmark_id),
    tostring(overlay.page_stamp or overlay.page_path),
    tostring(overlay.natural_cols),
    tostring(overlay.natural_rows),
    tostring(overlay.source_rows),
    range_key(node.display_range),
    range_key(node.source_range),
    tostring(node.display_prefix),
    tostring(node.display_suffix),
    tostring(concealing),
    tostring(display_width_for_bufnr(node.bufnr)),
  }, "|")

  if opts.skip_upload ~= true and self.presentation_key == presentation_key then
    local uploaded = false
    if force_upload and self.image ~= nil then
      uploaded = self.image:upload({ force_reupload = true })
      if uploaded then
        overlay.terminal_upload_epoch = self.image.sent_epoch
      end
    end
    return false, uploaded
  end

  if extmark_id ~= nil then
    extmark.swap_extmark_to_range(
      node.bufnr,
      overlay.image_id,
      extmark_id,
      node.display_range,
      node.semantics,
      concealing
    )
  else
    extmark_id =
      resources.place_overlay_extmark(node.bufnr, overlay.image_id, node.display_range, nil, concealing, node.semantics)
  end

  if extmark_id ~= overlay.extmark_id then
    require("math-conceal.image.machine.runtime").dispatch({
      type = "overlay_resources_allocated",
      overlay_id = overlay.overlay_id,
      image_id = overlay.image_id,
      extmark_id = extmark_id,
      binding_buffer_version = overlay.buffer_version,
      binding_layout_version = overlay.layout_version,
      binding_display_range = copy_range(node.display_range),
    }, { run_effects = false })
    machine_state, node, overlay = self:resolve(self.visible_overlay_id)
    if machine_state == nil or node == nil or overlay == nil then
      return false, false
    end
  end

  local item = self:compat_item(machine_state, node, overlay)
  if item ~= nil then
    item.extmark_id = extmark_id
    resources.bind_image_id(overlay.image_id, item, extmark_id)
  end

  if self.image == nil then
    self.image = FormulaImage.new({ overlay_id = overlay.overlay_id })
    self.image:attach(self)
  end
  self.image:update({
    overlay_id = overlay.overlay_id,
    page_path = overlay.page_path,
    page_stamp = overlay.page_stamp,
    image_id = overlay.image_id,
    natural_cols = overlay.natural_cols,
    natural_rows = overlay.natural_rows,
    source_rows = overlay.source_rows,
    sent_epoch = overlay.terminal_upload_epoch,
  })

  local uploaded = false
  local is_block = node.semantics ~= nil and node.semantics.display_kind == "block"
  if opts.skip_upload ~= true then
    uploaded = self.image:upload({
      force_reupload = opts.force_reupload == true or (opts.force_reupload_blocks == true and is_block),
    })
    if uploaded then
      overlay.terminal_upload_epoch = self.image.sent_epoch
    end
  end

  self.image:conceal(node.bufnr, overlay.source_rows or 1, {
    defer_line_run_reconcile = opts.defer_line_run_reconcile == true,
    line_run_refresh_rows = opts.line_run_refresh_rows,
  })
  self.manager:replace_read_model_entry(self, self:compat_item(machine_state, node, overlay))
  self.manager:reindex_placement(self)
  self.presentation_key = presentation_key
  return true, uploaded
end

function M:commit_render(effect, batch_mode)
  self:ensure_resources(effect.overlay_id, { place_extmark = true })
  local machine_state, node, overlay = self:resolve(effect.overlay_id)
  if overlay == nil or node == nil or overlay.image_id == nil or overlay.extmark_id == nil then
    return nil
  end

  local item = self:compat_item(machine_state, node, overlay)
  if item == nil then
    return nil
  end
  resources.bind_image_id(item.image_id, item, item.extmark_id)

  if self.image == nil then
    self.image = FormulaImage.new({ overlay_id = overlay.overlay_id })
    self.image:attach(self)
  end
  self.image:update({
    overlay_id = overlay.overlay_id,
    page_path = effect.page_path,
    page_stamp = overlay.page_stamp,
    image_id = item.image_id,
    natural_cols = effect.natural_cols,
    natural_rows = effect.natural_rows,
    source_rows = effect.source_rows,
    sent_epoch = overlay.terminal_upload_epoch,
  })
  self.image:upload({ force = true })
  overlay.terminal_upload_epoch = self.image.sent_epoch
  self.image:conceal(effect.bufnr, effect.source_rows)

  if batch_mode then
    return { overlay_id = effect.overlay_id, node_id = effect.node_id, bufnr = effect.bufnr }
  end

  require("math-conceal.image.machine.runtime").dispatch({
    type = "overlay_commit_succeeded",
    overlay_id = effect.overlay_id,
    node_id = effect.node_id,
  })
  self.manager:sync_from_machine()
  self.manager:invalidate_hover()
  if state.hooks.on_page_committed then
    state.hooks.on_page_committed(effect.bufnr)
  end
  return nil
end

function M:bind(effect)
  local machine_state, node, overlay, buf = self:resolve(effect.overlay_id)
  if overlay == nil or node == nil or buf == nil then
    return nil
  end
  if
    overlay.status ~= "visible"
    or node.visible_overlay_id ~= overlay.overlay_id
    or overlay.request_id ~= effect.request_id
    or overlay.owner_node_id ~= effect.node_id
    or buf.buffer_version ~= effect.buffer_version
    or buf.layout_version ~= effect.layout_version
    or not ranges_equal(node.display_range, effect.display_range)
    or overlay.image_id == nil
    or overlay.page_path == nil
    or overlay.natural_cols == nil
    or overlay.natural_rows == nil
  then
    return nil
  end

  self:update_presentation({ skip_upload = true })
  local _, _, current_overlay = self:resolve(effect.overlay_id)
  if current_overlay == nil then
    return nil
  end

  return {
    overlay_id = current_overlay.overlay_id,
    request_id = current_overlay.request_id,
    node_id = node.node_id,
    bufnr = buf.bufnr,
    extmark_id = current_overlay.extmark_id,
    buffer_version = effect.buffer_version,
    layout_version = effect.layout_version,
    display_range = copy_range(node.display_range),
  }
end

function M:on_rendered(entry)
  require("math-conceal.image.machine.runtime").dispatch({
    type = "overlay_pages_batch_ready",
    entries = { entry },
  })
end

function M:on_render_failed(ev)
  require("math-conceal.image.machine.runtime").dispatch(vim.tbl_extend("force", {
    type = "overlay_render_failed",
  }, ev))
end

function M:hide(opts)
  opts = opts or {}
  local _, _, overlay = self:resolve(self.visible_overlay_id)
  if overlay == nil or overlay.extmark_id == nil then
    return false
  end
  local ok = require("math-conceal.image.extmark").unconceal_extmark(self.bufnr, overlay.extmark_id, {
    defer_line_run_reconcile = opts.defer_line_run_reconcile == true,
  }) ~= nil
  if ok then
    self.hidden = true
    state.get_buf_state(self.bufnr).currently_hidden_extmark_ids[overlay.extmark_id] = true
  end
  return ok
end

function M:show(opts)
  opts = opts or {}
  local _, node, overlay = self:resolve(self.visible_overlay_id)
  if
    node == nil
    or overlay == nil
    or overlay.image_id == nil
    or overlay.natural_cols == nil
    or overlay.natural_rows == nil
  then
    return false
  end
  if self.image == nil then
    self.image = FormulaImage.new({ overlay_id = overlay.overlay_id })
    self.image:attach(self)
  end
  self.image:update({
    overlay_id = overlay.overlay_id,
    page_path = overlay.page_path,
    page_stamp = overlay.page_stamp,
    image_id = overlay.image_id,
    natural_cols = overlay.natural_cols,
    natural_rows = overlay.natural_rows,
    source_rows = overlay.source_rows,
    sent_epoch = overlay.terminal_upload_epoch,
  })
  self.hidden = false
  if overlay.extmark_id ~= nil then
    state.get_buf_state(self.bufnr).currently_hidden_extmark_ids[overlay.extmark_id] = nil
  end
  self.image:conceal(node.bufnr, overlay.source_rows or 1, {
    defer_line_run_reconcile = opts.defer_line_run_reconcile == true,
  })
  return true
end

function M:reattach_image(opts)
  opts = vim.tbl_extend("force", opts or {}, { force_reupload = true })
  return self:update_presentation(opts)
end

function M:close(opts)
  opts = opts or {}
  local _, _, overlay = self:resolve(opts.overlay_id or self.visible_overlay_id or self.candidate_overlay_id)
  self:clear_preview()
  if self.image ~= nil then
    self.image:detach(self)
  end
  self.manager:remove_read_model_entry(self)
  if overlay ~= nil and opts.release ~= false then
    resources.release_overlay_resources(overlay.owner_bufnr, overlay.image_id, overlay.extmark_id)
  end
  if overlay ~= nil and overlay.extmark_id ~= nil then
    state.get_buf_state(overlay.owner_bufnr).currently_hidden_extmark_ids[overlay.extmark_id] = nil
  end
  self.hidden = false
end

return M
