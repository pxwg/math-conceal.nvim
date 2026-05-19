--- Resource lifecycle layer for typst-concealer.
--- Owns image_id / extmark_id allocation, reuse, release, and index maintenance.
--- Receives PlannedItem[] from render.lua (the planner) and produces AppliedItem[].

local state = require("typst-concealer.state")
local resources = require("typst-concealer.machine.resources")
local cursor_visibility = require("typst-concealer.cursor-visibility")
local M = {}

--- @class PlannedItem
--- @field bufnr integer
--- @field item_idx integer
--- @field range table
--- @field display_range table
--- @field display_prefix string|nil
--- @field display_suffix string|nil
--- @field str string
--- @field prelude_count integer
--- @field node_type string
--- @field semantics table

--- @class AppliedItem : PlannedItem
--- @field image_id integer
--- @field extmark_id integer
--- @field needs_swap boolean
--- @field linger_misses integer|nil
--- @field page_path string|nil
--- @field page_stamp string|nil
--- @field natural_cols integer|nil
--- @field natural_rows integer|nil
--- @field source_rows integer|nil

--- @class PageUpdate
--- @field bufnr integer
--- @field image_id integer
--- @field extmark_id integer
--- @field original_range table
--- @field page_path string
--- @field page_stamp string
--- @field kind string

--- Allocate a new image_id for bufnr, scanning for a free slot.
--- @param bufnr integer
--- @return integer
local function new_image_id(bufnr)
  return resources.allocate_image_id(bufnr)
end

M._new_image_id = new_image_id

--- Release all resources for a single render item.
--- @param bufnr   integer
--- @param item    table|nil
local function cleanup_item(bufnr, item)
  if item == nil then
    return
  end
  resources.release_overlay_resources(bufnr, item.image_id, item.extmark_id)
end

M.cleanup_item = cleanup_item

local function row_overlap_len(a, b)
  local top = math.max(a[1], b[1])
  local bottom = math.min(a[3], b[3])
  if bottom < top then
    return 0
  end
  return bottom - top + 1
end

local function row_gap_len(a, b)
  if a[3] < b[1] then
    return b[1] - a[3]
  end
  if b[3] < a[1] then
    return a[1] - b[3]
  end
  return 0
end

local function col_delta_len(a, b)
  return math.abs(a[2] - b[2]) + math.abs(a[4] - b[4])
end

local function prev_item_matches_entry(prev_item, entry)
  if prev_item == nil or entry == nil then
    return false
  end

  -- Resource reuse must preserve source identity, not just visual proximity.
  -- If we reuse an image/extmark for a different math node, stale rendered
  -- pages stay bound to the wrong source until typst rewrites that page.
  if prev_item.node_type ~= entry.node_type then
    return false
  end
  if prev_item.str ~= entry.str then
    return false
  end
  if prev_item.prelude_count ~= entry.prelude_count then
    return false
  end

  return true
end

--- Match a fresh render entry to the most plausible previous item.
--- @param prev_items table[]
--- @param entry table
--- @param used_prev table<integer, boolean>
--- @return table|nil
local function find_matching_prev_item(prev_items, entry, used_prev)
  local best_idx = nil
  local best_item = nil
  local best_overlap = -1
  local best_gap = math.huge
  local best_col_delta = math.huge

  for idx, prev_item in ipairs(prev_items) do
    if not used_prev[idx] and prev_item_matches_entry(prev_item, entry) then
      local overlap = row_overlap_len(prev_item.range, entry.range)
      local gap = row_gap_len(prev_item.range, entry.range)
      local col_delta = col_delta_len(prev_item.range, entry.range)
      if
        overlap > best_overlap
        or (overlap == best_overlap and gap < best_gap)
        or (overlap == best_overlap and gap == best_gap and col_delta < best_col_delta)
      then
        best_idx = idx
        best_item = prev_item
        best_overlap = overlap
        best_gap = gap
        best_col_delta = col_delta
      end
    end
  end

  if best_idx ~= nil then
    used_prev[best_idx] = true
  end
  return best_item
end

M.find_matching_prev_item = find_matching_prev_item

local function reattach_item_image(image_id, opts)
  if image_id == nil then
    return
  end

  local ok_manager, manager = pcall(require, "typst-concealer.formula.manager")
  if ok_manager and manager.reattach_image(image_id, opts) then
    return
  end

  local item = state.get_item_by_image_id(image_id)
  if
    item == nil
    or item.page_path == nil
    or item.natural_cols == nil
    or item.natural_rows == nil
    or state.image_id_to_extmark[image_id] == nil
  then
    return
  end

  local target_bufnr = item.render_target == "float" and (item.target_bufnr or item.bufnr) or item.bufnr
  if target_bufnr == nil or not vim.api.nvim_buf_is_valid(target_bufnr) then
    return
  end

  local extmark_mod = require("typst-concealer.extmark")
  extmark_mod.create_image(item.page_path, image_id, item.natural_cols, item.natural_rows)
  item.terminal_upload_epoch = state.terminal_upload_epoch
  extmark_mod.conceal_for_image_id(
    target_bufnr,
    image_id,
    item.natural_cols,
    item.natural_rows,
    item.source_rows or 1,
    opts
  )
  extmark_mod.flush_terminal_data()
end

local function cleanup_preview_image(bufnr, opts)
  opts = opts or {}
  local bs = state.get_buf_state(bufnr)
  local preview = bs.preview_image
  local last_rendered = bs.preview_last_rendered_item
  local had_preview_resources = preview ~= nil or bs.preview_item ~= nil or last_rendered ~= nil
  local source_image_id = bs.preview_source_image_id
    or (bs.preview_item and bs.preview_item.source_image_id)
    or (last_rendered and last_rendered.source_image_id)
  if preview == nil then
    if bs.preview_item ~= nil then
      if bs.preview_item.extmark_id ~= nil then
        state.prepare_extmark_reuse(bufnr, bs.preview_item.extmark_id)
        pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id, bs.preview_item.extmark_id)
      end
    end
    if bs.preview_item ~= nil and bs.preview_item.image_id ~= nil then
      resources.release_image_id(bs.preview_item.image_id)
    end
    bs.preview_item = nil
    if last_rendered ~= nil and last_rendered.image_id ~= nil then
      resources.release_image_id(last_rendered.image_id)
    end
    bs.preview_last_rendered_item = nil
    bs.preview_last_render_key = nil
    bs.preview_render_key = nil
    require("typst-concealer.machine.runtime").reset_preview_state(bufnr)
    bs.preview_source_image_id = nil
    bs.preview_source_page_stamp = nil
    bs.preview_source_range = nil
    if had_preview_resources then
      reattach_item_image(source_image_id, opts)
    end
    return
  end

  local target_bufnr = preview.target_bufnr or bufnr
  state.prepare_extmark_reuse(target_bufnr, preview.extmark_id)
  pcall(vim.api.nvim_buf_del_extmark, target_bufnr, state.ns_id, preview.extmark_id)
  if preview.image_id ~= nil then
    resources.release_image_id(preview.image_id)
  end
  if bs.preview_item ~= nil and bs.preview_item.image_id ~= nil and bs.preview_item.image_id ~= preview.image_id then
    resources.release_image_id(bs.preview_item.image_id)
  end
  if
    last_rendered ~= nil
    and last_rendered.image_id ~= nil
    and last_rendered.image_id ~= preview.image_id
    and (bs.preview_item == nil or last_rendered.image_id ~= bs.preview_item.image_id)
  then
    resources.release_image_id(last_rendered.image_id)
  end
  bs.preview_image = nil
  bs.preview_item = nil
  bs.preview_last_rendered_item = nil
  bs.preview_last_render_key = nil
  bs.preview_render_key = nil
  require("typst-concealer.machine.runtime").reset_preview_state(bufnr)
  bs.preview_source_image_id = nil
  bs.preview_source_page_stamp = nil
  bs.preview_source_range = nil
  if had_preview_resources then
    reattach_item_image(source_image_id, opts)
  end
end

M.cleanup_preview_image = cleanup_preview_image

local function cleanup_preview_item_request(bufnr, item, opts)
  if item == nil then
    return
  end

  opts = opts or {}
  if item.image_id ~= nil then
    resources.release_image_id(item.image_id)
  end

  if opts.keep_extmark ~= true and item.extmark_id ~= nil then
    state.prepare_extmark_reuse(bufnr, item.extmark_id)
    pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id, item.extmark_id)
  end
end

M.cleanup_preview_item_request = cleanup_preview_item_request

-- Private copies to avoid circular require with render.lua
local function clamp_range_to_buffer(bufnr, range)
  if range == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 0 then
    return nil
  end

  local start_row = math.max(0, math.min(range[1], line_count - 1))
  local end_row = math.max(start_row, math.min(range[3], line_count - 1))
  local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  if #lines == 0 then
    return nil
  end

  local start_col = math.max(0, math.min(range[2], #(lines[1] or "")))
  local end_col
  if start_row == end_row then
    end_col = math.max(start_col, math.min(range[4], #(lines[#lines] or "")))
  else
    end_col = math.max(0, math.min(range[4], #(lines[#lines] or "")))
  end

  return { start_row, start_col, end_row, end_col }
end

local function get_item_effective_range(item)
  if item == nil then
    return nil
  end
  return clamp_range_to_buffer(item.bufnr, item.range)
end

local function normalize_buf_path(path)
  if path == nil or path == "" then
    return ""
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function item_has_stable_render(item)
  return item ~= nil and item.page_path ~= nil and item.natural_cols ~= nil and item.natural_rows ~= nil
end

local function carry_stable_render_metadata(dst, src)
  if dst == nil or not item_has_stable_render(src) then
    return
  end

  dst.page_path = src.page_path
  dst.page_stamp = src.page_stamp
  dst.natural_cols = src.natural_cols
  dst.natural_rows = src.natural_rows
  dst.source_rows = src.source_rows
end

local function item_blocked_by_error_diagnostics(bufnr, item)
  if item == nil then
    return false
  end
  local bucket = state.render_diagnostics[bufnr]
  local diagnostics_items = bucket and bucket.full or nil
  if diagnostics_items == nil or #diagnostics_items == 0 then
    return false
  end

  local item_file = normalize_buf_path(vim.api.nvim_buf_get_name(item.bufnr))
  local effective_range = get_item_effective_range(item)
  if effective_range == nil then
    return false
  end
  local start_row = effective_range[1] + 1
  local end_row = effective_range[3] + 1
  local item_idx = item.item_idx
  for _, diag in ipairs(diagnostics_items) do
    if diag.type == "E" and diag.item_idx ~= nil and item_idx ~= nil and diag.item_idx == item_idx then
      return true
    end
    if diag.type == "E" and normalize_buf_path(diag.filename) == item_file then
      local lnum = tonumber(diag.lnum)
      if lnum ~= nil and lnum >= start_row and lnum <= end_row then
        return true
      end
    end
  end
  return false
end

local function concealing_for_cursor(item)
  if cursor_visibility.should_preserve_source_at_cursor(item.bufnr, item) then
    return false
  end
  return nil
end

--- Allocate image_ids and extmarks for a batch of PlannedItems,
--- reusing resources from previous render pass where possible.
--- @param bufnr integer
--- @param planned_items PlannedItem[]
--- @return table[]
function M.commit_plan(bufnr, planned_items)
  local extmark_mod = require("typst-concealer.extmark")

  local prev_state = state.buffer_render_state[bufnr] or {}
  local prev_items = {}
  for _, item in ipairs(prev_state.full_items or {}) do
    prev_items[#prev_items + 1] = item
  end

  local batch_items = {}
  local visible_batch_items = {}
  local used_prev = {}

  for _, planned in ipairs(planned_items) do
    local prev_item = find_matching_prev_item(prev_items, planned, used_prev)
    local image_id, ext_id

    if prev_item ~= nil then
      image_id = prev_item.image_id
      ext_id = prev_item.extmark_id
    else
      image_id = new_image_id(bufnr)
      ext_id = extmark_mod.place_render_extmark(
        bufnr,
        image_id,
        planned.display_range,
        nil,
        concealing_for_cursor(planned),
        planned.semantics
      )
    end

    local item = {
      bufnr = planned.bufnr,
      image_id = image_id,
      extmark_id = ext_id,
      item_idx = planned.item_idx,
      range = planned.range,
      display_range = planned.display_range,
      display_prefix = planned.display_prefix,
      display_suffix = planned.display_suffix,
      str = planned.str,
      prelude_count = planned.prelude_count,
      node_type = planned.node_type,
      semantics = planned.semantics,
      needs_swap = prev_item ~= nil,
    }

    carry_stable_render_metadata(item, prev_item)

    batch_items[#batch_items + 1] = item
    resources.bind_image_id(image_id, item, ext_id)
  end

  for _, item in ipairs(batch_items) do
    if item_blocked_by_error_diagnostics(bufnr, item) then
      cleanup_item(bufnr, item)
    else
      visible_batch_items[#visible_batch_items + 1] = item
    end
  end

  -- Release extmarks/images for items that no longer exist. Do not keep
  -- unmatched items alive across passes: when a math node is deleted or moved
  -- far enough to stop matching, the old overlay must disappear immediately.
  for idx, prev_item in ipairs(prev_items) do
    if not used_prev[idx] then
      cleanup_item(bufnr, prev_item)
    end
  end

  state.buffer_render_state[bufnr] = state.buffer_render_state[bufnr] or {}
  state.buffer_render_state[bufnr].full_items = visible_batch_items
  state.buffer_render_state[bufnr].lingering_items = {}

  -- Rebuild per-line item index for O(1) hover lookup
  local line_to_items = {}
  local extmark_to_item = {}
  local visible_items = {}
  for _, item in ipairs(visible_batch_items) do
    visible_items[#visible_items + 1] = item
  end
  for _, item in ipairs(visible_items) do
    local effective_range = get_item_effective_range(item)
    if effective_range ~= nil then
      extmark_to_item[item.extmark_id] = item
      for row = effective_range[1], effective_range[3] do
        if not line_to_items[row] then
          line_to_items[row] = {}
        end
        line_to_items[row][#line_to_items[row] + 1] = item
      end
    end
  end
  state.buffer_render_state[bufnr].line_to_items = line_to_items
  state.buffer_render_state[bufnr].extmark_to_item = extmark_to_item

  return visible_batch_items
end

--- Display a preview item's image in virtual lines (no stable-render required).
--- @param bufnr  integer
--- @param item   table    AppliedItem with natural_cols/rows
--- @param layout table    { vertical: string, anchor_row: integer, left_pad_cols: integer, effective_range: table }
function M.show_preview_item(bufnr, item, layout)
  local extmark_mod = require("typst-concealer.extmark")
  local bs = state.get_buf_state(bufnr)

  local prev_visible_image_id = bs.preview_image and bs.preview_image.image_id or nil
  local extmark_id = bs.preview_image and bs.preview_image.extmark_id or nil
  extmark_id = extmark_mod.show_virtual_image(
    bufnr,
    extmark_id,
    layout.anchor_row,
    item.image_id,
    item.natural_cols,
    item.natural_rows,
    { above = layout.vertical == "above", left_pad_cols = layout.left_pad_cols }
  )

  if prev_visible_image_id ~= nil and prev_visible_image_id ~= item.image_id then
    resources.release_image_id(prev_visible_image_id)
  end

  bs.preview_image = {
    extmark_id = extmark_id,
    target_bufnr = bufnr,
    natural_cols = item.natural_cols,
    natural_rows = item.natural_rows,
  }
  bs.preview_source_image_id = item.image_id
  bs.preview_source_page_stamp = item.page_stamp
  bs.preview_source_range = vim.deepcopy(layout.effective_range)
end

--- Display a rendered preview item and update all tracking state.
--- @param bufnr  integer
--- @param item   table
--- @param layout table   { vertical: string, anchor_row: integer, left_pad_cols: integer, effective_range: table }
function M.show_rendered_preview_item(bufnr, item, layout)
  local extmark_mod = require("typst-concealer.extmark")
  local bs = state.get_buf_state(bufnr)

  local prev_visible_image_id = bs.preview_image and bs.preview_image.image_id or nil
  local extmark_id = bs.preview_image and bs.preview_image.extmark_id or item.extmark_id
  extmark_id = extmark_mod.show_virtual_image(
    bufnr,
    extmark_id,
    layout.anchor_row,
    item.image_id,
    item.natural_cols,
    item.natural_rows,
    { above = layout.vertical == "above", left_pad_cols = layout.left_pad_cols }
  )

  item.extmark_id = extmark_id
  resources.bind_image_id(item.image_id, nil, extmark_id)
  if prev_visible_image_id ~= nil and prev_visible_image_id ~= item.image_id then
    resources.release_image_id(prev_visible_image_id)
  end
  bs.preview_image = {
    extmark_id = extmark_id,
    target_bufnr = bufnr,
    natural_cols = item.natural_cols,
    natural_rows = item.natural_rows,
    image_id = item.image_id,
  }
  bs.preview_item = item
  bs.preview_last_rendered_item = item
  bs.preview_last_render_key = bs.preview_render_key
  require("typst-concealer.machine.runtime").mark_preview_rendered(bufnr)
  bs.preview_source_image_id = item.source_image_id or item.image_id
  bs.preview_source_page_stamp = item.page_stamp
  bs.preview_source_range = vim.deepcopy(layout.effective_range)
end

--- Allocate a preview item (new image_id + extmark) and register it in state indices.
--- @param bufnr             integer
--- @param source_item       table   full AppliedItem under cursor
--- @param preview_str       string
--- @param source_str        string
--- @param render_key        string
--- @param shared_extmark_id integer|nil  reuse extmark from previous preview if available
--- @return table  preview_item
function M.allocate_preview_item(bufnr, source_item, preview_str, source_str, render_key, shared_extmark_id)
  local extmark_id = shared_extmark_id
  if extmark_id == nil then
    extmark_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id, source_item.range[3], 0, { invalidate = true })
  end
  local preview_item = {
    bufnr = bufnr,
    image_id = new_image_id(bufnr),
    extmark_id = extmark_id,
    node_id = source_item.node_id,
    overlay_id = source_item.overlay_id,
    range = vim.deepcopy(source_item.range),
    str = preview_str,
    source_str = source_str,
    source_text = source_str,
    prelude_count = source_item.prelude_count,
    node_type = "math",
    semantics = source_item.semantics,
    requires_mitex = source_item.requires_mitex,
    render_target = "preview_float",
    source_image_id = source_item.image_id,
  }
  resources.bind_image_id(preview_item.image_id, preview_item, extmark_id)
  local bs = state.get_buf_state(bufnr)
  bs.preview_item = preview_item
  bs.preview_render_key = render_key
  require("typst-concealer.machine.runtime").set_preview_render_key(bufnr, render_key)
  return preview_item
end

--- Apply a rendered page update to the display layer.
--- @param update PageUpdate
function M.accept_page_update(update)
  local extmark_mod = require("typst-concealer.extmark")
  local bufnr = update.bufnr
  local image_id = update.image_id
  local extmark_id = update.extmark_id
  local page_path = update.page_path
  local page_stamp = update.page_stamp
  local natural_cols = update.natural_cols
  local natural_rows = update.natural_rows
  local source_rows = update.source_rows

  local item = state.get_item_by_image_id(image_id)
  if item == nil or type(extmark_id) ~= "number" then
    return
  end

  local target_bufnr = bufnr
  if item and item.render_target == "float" then
    target_bufnr = item.target_bufnr or bufnr
  end
  if not vim.api.nvim_buf_is_valid(target_bufnr) then
    return
  end
  if state.image_id_to_extmark[image_id] ~= extmark_id then
    return
  end
  local ok_mark, mark =
    pcall(vim.api.nvim_buf_get_extmark_by_id, target_bufnr, state.ns_id, extmark_id, { details = true })
  if not ok_mark or mark == nil or #mark == 0 then
    return
  end

  if item ~= nil then
    item.natural_cols = natural_cols
    item.natural_rows = natural_rows
    item.source_rows = source_rows
    item.page_path = page_path
    item.page_stamp = page_stamp
  end

  -- Swap extmark to new range when the new image is ready.
  local bstate = state.buffer_render_state[bufnr]
  if bstate and bstate.full_items then
    for _, fi in ipairs(bstate.full_items) do
      if fi.image_id == image_id then
        if fi.needs_swap then
          extmark_mod.swap_extmark_to_range(
            bufnr,
            image_id,
            extmark_id,
            fi.display_range or fi.range,
            fi.semantics,
            concealing_for_cursor(fi)
          )
          fi.needs_swap = false
        end
        break
      end
    end
  end

  extmark_mod.create_image(page_path, image_id, natural_cols, natural_rows)
  if item ~= nil then
    item.terminal_upload_epoch = state.terminal_upload_epoch
  end
  extmark_mod.flush_terminal_data()
  if item ~= nil and item.render_target == "preview_float" then
    if state.hooks.present_rendered_preview_item then
      state.hooks.present_rendered_preview_item(target_bufnr, item)
    end
    return
  end
  extmark_mod.conceal_for_image_id(target_bufnr, image_id, natural_cols, natural_rows, source_rows)
  require("typst-concealer.machine.runtime").invalidate_hover(bufnr)
  if state.hooks.on_page_committed then
    state.hooks.on_page_committed(bufnr)
  end
end

--- Release all resources for a buffer and reset render state.
--- @param bufnr integer
function M.hard_reset(bufnr)
  local bstate = state.buffer_render_state[bufnr]
  if bstate and bstate.full_items then
    for _, item in ipairs(bstate.full_items) do
      cleanup_item(bufnr, item)
    end
  end
  if bstate and bstate.lingering_items then
    for _, item in ipairs(bstate.lingering_items) do
      cleanup_item(bufnr, item)
    end
  end
  state.buffer_render_state[bufnr] = nil

  -- Remove only entries belonging to this buffer from the shared O(1) index
  local to_remove = {}
  for image_id, item in pairs(state.item_by_image_id) do
    if item.bufnr == bufnr then
      to_remove[#to_remove + 1] = image_id
    end
  end
  for _, image_id in ipairs(to_remove) do
    resources.unbind_image_id(image_id, nil)
  end
  state.runtime_preludes = {}

  for id, image_bufnr in pairs(state.image_ids_in_use) do
    if bufnr == image_bufnr then
      resources.release_image_id(id)
    end
  end
end

return M
