--- Cross-extmark line-run scheduler.
---
--- This module owns grouping, splitting and anchoring of collapsed display
--- runs.  Atomic extmark resources live in extmark.lua; cursor transitions
--- update those resources first and then reconcile line runs here.

local display = require("math-conceal.image.display")
local state = require("math-conceal.image.state")

local M = {}
local adapter = {}

function M.configure(opts)
  adapter = vim.tbl_extend("force", adapter, opts or {})
end

local function get_win_cols(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  return vim.api.nvim_win_get_width(winid ~= -1 and winid or 0)
end

local function buf_win(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  if winid ~= -1 and vim.api.nvim_win_is_valid(winid) then
    return winid
  end
end

local function get_win_text_cols(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  local width = get_win_cols(bufnr)
  if winid == -1 then
    return width
  end

  local info = vim.fn.getwininfo(winid)[1]
  local textoff = info and tonumber(info.textoff) or 0
  return math.max(1, width - textoff)
end

local function item_display_bufnr(item)
  if adapter.item_display_bufnr ~= nil then
    return adapter.item_display_bufnr(item)
  end
  if item == nil then
    return nil
  end
  if item.render_target == "float" then
    return item.target_bufnr or item.bufnr
  end
  return item.bufnr
end

local function display_size_for_image(item, natural_cols, natural_rows)
  if adapter.display_size_for_image ~= nil then
    return adapter.display_size_for_image(item, natural_cols, natural_rows)
  end
  return math.max(1, tonumber(natural_cols) or 1), math.max(1, tonumber(natural_rows) or 1)
end

local function cursor_row_for_buf(bufnr)
  local winid = vim.fn.bufwinid(bufnr)
  if winid == -1 then
    return nil
  end
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, winid)
  if not ok or cursor == nil then
    return nil
  end
  return cursor[1] - 1
end

local function extmark_row(bufnr, ns_id, extmark_id)
  if type(extmark_id) ~= "number" then
    return nil
  end
  local ok, mark = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns_id, extmark_id, {})
  if not ok or mark == nil or #mark == 0 then
    return nil
  end
  return mark[1]
end

local function extmark_range(bufnr, ns_id, extmark_id)
  if type(extmark_id) ~= "number" then
    return nil
  end
  local ok, mark = pcall(vim.api.nvim_buf_get_extmark_by_id, bufnr, ns_id, extmark_id, { details = true })
  if not ok or mark == nil or #mark == 0 then
    return nil
  end
  local details = mark[3] or {}
  if details.invalid then
    return nil
  end
  return {
    start_row = mark[1],
    end_row = details.end_row or mark[1],
    start_col = mark[2],
    end_col = details.end_col or mark[2],
  }
end

local function add_range(geo, range)
  if range == nil then
    return
  end
  geo.start_row = geo.start_row == nil and range.start_row or math.min(geo.start_row, range.start_row)
  geo.end_row = geo.end_row == nil and range.end_row or math.max(geo.end_row, range.end_row)
  for row = range.start_row, range.end_row do
    geo.rows[row] = true
  end
end

local function line_run_geometry(bufnr, run)
  if run == nil then
    return nil
  end

  local geo = {
    start_row = nil,
    end_row = nil,
    rows = {},
  }

  for extmark_id in pairs(run.extmark_ids or run.block_extmark_ids or {}) do
    add_range(geo, extmark_range(bufnr, state.ns_id, extmark_id))
  end

  for _, conceal_id in pairs(run.conceal_ids or {}) do
    local row = extmark_row(bufnr, state.ns_id2, conceal_id)
    if row ~= nil then
      add_range(geo, { start_row = row, end_row = row })
    end
  end

  for _, sub_id in pairs(run.sub_ids or {}) do
    local row = extmark_row(bufnr, state.ns_id2, sub_id)
    if row ~= nil then
      add_range(geo, { start_row = row, end_row = row })
    end
  end

  if geo.start_row == nil or geo.end_row == nil then
    return nil
  end
  return geo
end

local function row_in_range(row, start_row, end_row)
  if type(row) ~= "number" then
    return false
  end
  if type(start_row) == "number" and row < start_row then
    return false
  end
  if type(end_row) == "number" and row > end_row then
    return false
  end
  return true
end

function M.row_set(start_row, end_row)
  local rows = {}
  if type(start_row) ~= "number" or type(end_row) ~= "number" then
    return rows
  end
  for row = start_row, end_row do
    rows[row] = true
  end
  return rows
end

local function inline_line_mark_in_range(bufnr, row, mark, start_row, end_row)
  if row_in_range(row, start_row, end_row) then
    return true
  end
  if row_in_range(extmark_row(bufnr, state.ns_id2, mark.carrier_id), start_row, end_row) then
    return true
  end
  return row_in_range(extmark_row(bufnr, state.ns_id2, mark.conceal_id), start_row, end_row)
end

function M.clear(bufnr, run_id)
  local bs = state.get_buf_state(bufnr)
  bs.inline_line_reconcile_key = nil
  local runs = bs.line_run_marks or {}
  local run = runs[run_id]
  if run == nil then
    return nil
  end

  if run.carrier_id ~= nil then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id2, run.carrier_id)
  end
  local geo = line_run_geometry(bufnr, run)
  for _, conceal_id in pairs(run.conceal_ids or {}) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id2, conceal_id)
  end

  for row in pairs(geo and geo.rows or {}) do
    if bs.inline_line_marks and bs.inline_line_marks[row] and bs.inline_line_marks[row].line_run_id == run_id then
      bs.inline_line_marks[row] = nil
    end
    if bs.line_run_by_row then
      bs.line_run_by_row[row] = nil
    end
  end

  for _, sub_id in pairs(run.sub_ids or {}) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id2, sub_id)
  end

  for extmark_id in pairs(run.extmark_ids or run.block_extmark_ids or {}) do
    local mm = bs.multiline_marks[extmark_id]
    if mm and mm.line_run_id == run_id then
      mm.carrier_id = nil
      mm.tail_ids = {}
      mm.sub_ids = {}
      mm.line_run_id = nil
    end
    if bs.line_run_by_extmark then
      bs.line_run_by_extmark[extmark_id] = nil
    end
  end

  runs[run_id] = nil
  state.invalidate_hover(bufnr)
  return run
end

function M.clear_inline_line_mark(bufnr, row)
  local bs = state.get_buf_state(bufnr)
  bs.inline_line_reconcile_key = nil
  local marks = bs.inline_line_marks or {}
  local mark = marks[row]
  if mark == nil then
    return false
  end

  if mark.line_run_id ~= nil then
    return M.clear(bufnr, mark.line_run_id) ~= nil
  end

  if mark.carrier_id ~= nil then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id2, mark.carrier_id)
  end
  if mark.conceal_id ~= nil then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id2, mark.conceal_id)
  end
  marks[row] = nil
  bs.inline_line_marks = marks
  return true
end

function M.clear_inline_line_marks(bufnr, start_row, end_row)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return 0
  end

  local bs = state.get_buf_state(bufnr)
  local marks = bs.inline_line_marks or {}
  local rows = {}
  for row, mark in pairs(marks) do
    if inline_line_mark_in_range(bufnr, row, mark, start_row, end_row) then
      rows[#rows + 1] = row
    end
  end

  local cleared = 0
  for _, row in ipairs(rows) do
    if M.clear_inline_line_mark(bufnr, row) then
      cleared = cleared + 1
    end
  end
  return cleared
end

local function image_hl_group(image_id)
  local hl_group = "math-conceal.image-image-id-" .. tostring(image_id)
  vim.api.nvim_set_hl(0, hl_group, { fg = string.format("#%06X", image_id), nocombine = true })
  return hl_group
end

local function inline_line_item_ready(item, bufnr, row)
  if item == nil or item.render_target == "float" or item.render_target == "preview_float" then
    return false
  end
  if item_display_bufnr(item) ~= bufnr then
    return false
  end
  if item.range == nil or item.range[1] ~= row or item.range[3] ~= row then
    return false
  end
  if item.semantics == nil or item.semantics.display_kind ~= "inline" then
    return false
  end
  return item.image_id ~= nil and item.natural_cols ~= nil and item.natural_rows ~= nil
end

local function collect_inline_line_items(bufnr, row)
  local items = {}
  for _, item in pairs(state.item_by_image_id) do
    if inline_line_item_ready(item, bufnr, row) then
      items[#items + 1] = item
    end
  end
  table.sort(items, function(a, b)
    if a.range[2] == b.range[2] then
      return a.range[4] < b.range[4]
    end
    return a.range[2] < b.range[2]
  end)

  local last_end = 0
  for _, item in ipairs(items) do
    if item.range[2] < last_end then
      return {}
    end
    last_end = item.range[4]
  end
  return items
end

local function row_has_render_item(bufnr, row)
  for _, item in pairs(state.item_by_image_id) do
    if item ~= nil and item.render_target ~= "float" and item.render_target ~= "preview_float" then
      local item_bufnr = item_display_bufnr(item)
      local range = item.display_range or item.range
      local semantics = item.semantics or {}
      if
        item_bufnr == bufnr
        and type(range) == "table"
        and row >= (range[1] or -1)
        and row <= (range[3] or -1)
        and (semantics.display_kind == "inline" or semantics.display_kind == "block")
      then
        return true
      end
    end
  end
  return false
end

local function row_can_anchor_inline_line(bufnr, row)
  if row_has_render_item(bufnr, row) then
    return false
  end

  local ok, marks = pcall(
    vim.api.nvim_buf_get_extmarks,
    bufnr,
    state.ns_id2,
    { row, 0 },
    { row, -1 },
    { details = true }
  )
  if not ok then
    return false
  end
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    if details.conceal_lines ~= nil or details.virt_lines ~= nil or details.virt_text ~= nil then
      return false
    end
  end
  return true
end

local function build_inline_line_replacements(bufnr, row, items)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if line == nil then
    return nil
  end

  local replacements = {}
  for _, item in ipairs(items) do
    local display_cols, display_rows = display_size_for_image(item, item.natural_cols, item.natural_rows)
    if display_rows ~= 1 then
      return nil
    end
    item.display_cols = display_cols
    item.display_rows = display_rows
    replacements[#replacements + 1] = {
      source = "math-conceal.image-image",
      start_col = item.range[2],
      end_col = item.range[4],
      priority = 10000,
      chunks = {
        {
          image = true,
          image_row = 1,
          hl_group = image_hl_group(item.image_id),
          width = display_cols,
        },
      },
    }
  end

  return replacements
end

local function extmark_suppressed(bufnr, extmark_id, opts)
  if type(extmark_id) ~= "number" then
    return false
  end
  if opts and opts.suppressed_extmark_ids and opts.suppressed_extmark_ids[extmark_id] then
    return true
  end
  return state.get_buf_state(bufnr).currently_hidden_extmark_ids[extmark_id] ~= nil
end

local function line_run_block_for_row(bufnr, row, opts)
  local bs = state.get_buf_state(bufnr)
  for _, item in pairs(state.item_by_image_id) do
    local semantics = item and item.semantics or nil
    local extmark_id = item and (item.extmark_id or state.image_id_to_extmark[item.image_id]) or nil
    local mm = extmark_id and bs.multiline_marks[extmark_id] or nil
    if
      item_display_bufnr(item) == bufnr
      and semantics
      and semantics.display_kind == "block"
      and mm
      and mm.is_block_carrier == true
      and type(mm.line_run_display_lines) == "table"
      and not extmark_suppressed(bufnr, extmark_id, opts)
    then
      local range = extmark_range(bufnr, state.ns_id, extmark_id)
      if range ~= nil and row >= range.start_row and row <= range.end_row then
        return item, extmark_id, mm, row == range.start_row
      end
    end
  end
end

local function line_run_row_ready(bufnr, row, opts)
  opts = opts or {}
  local suppressed_rows = opts.suppressed_rows or state.get_buf_state(bufnr).inline_line_suppressed_rows
  if suppressed_rows and suppressed_rows[row] then
    return false
  end
  if line_run_block_for_row(bufnr, row, opts) ~= nil then
    return true
  end
  if opts.ignore_cursor ~= true and cursor_row_for_buf(bufnr) == row then
    return false
  end

  local items = collect_inline_line_items(bufnr, row)
  return #items > 0 and build_inline_line_replacements(bufnr, row, items) ~= nil
end

local function build_line_run_row(bufnr, row, opts)
  local _, extmark_id, mm, is_block_start = line_run_block_for_row(bufnr, row, opts)
  if mm ~= nil then
    return is_block_start and mm.line_run_display_lines or {}, {
      block_extmark_id = extmark_id,
    }
  end

  local items = collect_inline_line_items(bufnr, row)
  if #items == 0 then
    return nil
  end

  local replacements = build_inline_line_replacements(bufnr, row, items)
  if replacements == nil then
    return nil
  end

  local display_opts = {
    exclude_namespaces = {
      [state.ns_id] = true,
      [state.ns_id2] = true,
    },
    math_conceal = opts.math_conceal,
    math_conceal_marks_by_row = opts.math_conceal_marks_by_row,
    winid = opts.winid,
  }
  local lines = display.line_virt_lines(bufnr, row, replacements, get_win_text_cols(bufnr), display_opts)
  if lines == nil then
    return nil
  end

  return lines, {
    inline_row = true,
  }
end

local function clear_line_runs_in_range(bufnr, start_row, end_row)
  local bs = state.get_buf_state(bufnr)
  local run_ids = {}
  for run_id, run in pairs(bs.line_run_marks or {}) do
    local geo = line_run_geometry(bufnr, run)
    if geo ~= nil and not (geo.end_row < start_row or geo.start_row > end_row) then
      run_ids[run_id] = true
    end
  end

  local cleared = {}
  for run_id in pairs(run_ids) do
    cleared[#cleared + 1] = M.clear(bufnr, run_id)
  end
  return cleared
end

local function choose_line_run_anchor(bufnr, start_row, end_row, opts)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local anchor_rows = opts and opts.anchor_rows or nil

  -- Prefer anchoring virt_lines to start_row itself with virt_lines_above so
  -- the rendered image stays at the visual position of the concealed source
  -- block.  This prevents cursor jumps to the top/bottom of the screen when
  -- conceal is applied to a multi-line display math block.
  -- Only fall back to start_row - 1 if start_row already has conflicting
  -- virt_lines from another extmark in the secondary namespace.
  if start_row > 0 then
    local ok, marks = pcall(
      vim.api.nvim_buf_get_extmarks,
      bufnr,
      state.ns_id2,
      { start_row, 0 },
      { start_row, -1 },
      { details = true }
    )
    local has_virt_lines_conflict = false
    if ok and marks then
      for _, mark in ipairs(marks) do
        local details = mark[4] or {}
        if details.virt_lines ~= nil then
          has_virt_lines_conflict = true
          break
        end
      end
    end
    if not has_virt_lines_conflict then
      return start_row, true
    end
    return start_row - 1, false
  end

  local function scan_safe(anchor_row, direction)
    while anchor_row >= 0 and anchor_row < line_count do
      if row_has_render_item(bufnr, anchor_row) then
        return nil, nil
      end
      if row_can_anchor_inline_line(bufnr, anchor_row) then
        return anchor_row, direction > 0
      end
      anchor_row = anchor_row + direction
    end
    return nil, nil
  end

  local function boundary_anchor(row, direction)
    if anchor_rows and anchor_rows[row] and row >= 0 and row < line_count then
      return row, direction > 0
    end
  end

  local previous_row, previous_above = scan_safe(start_row - 1, -1)
  if previous_row ~= nil then
    return previous_row, previous_above
  end

  local next_row, next_above = scan_safe(end_row + 1, 1)
  if next_row ~= nil then
    return next_row, next_above
  end

  previous_row, previous_above = boundary_anchor(start_row - 1, -1)
  if previous_row ~= nil then
    return previous_row, previous_above
  end

  return boundary_anchor(end_row + 1, 1)
end

function M.refresh_for_row(bufnr, row, opts)
  opts = opts or {}
  if row == nil or not vim.api.nvim_buf_is_valid(bufnr) then
    return false, row, row
  end

  state.get_buf_state(bufnr).inline_line_reconcile_key = nil

  if not line_run_row_ready(bufnr, row, opts) then
    clear_line_runs_in_range(bufnr, row, row)
    return false, row, row
  end

  local start_row = row
  while start_row > 0 and line_run_row_ready(bufnr, start_row - 1, opts) do
    start_row = start_row - 1
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local end_row = row
  while end_row + 1 < line_count and line_run_row_ready(bufnr, end_row + 1, opts) do
    end_row = end_row + 1
  end

  clear_line_runs_in_range(bufnr, start_row, end_row)

  local anchor_row, virt_lines_above = choose_line_run_anchor(bufnr, start_row, end_row, opts)
  if anchor_row == nil then
    return false, start_row, end_row
  end

  local display_lines = {}
  local inline_rows = {}
  local block_extmark_ids = {}
  local build_opts = opts
  if opts.math_conceal ~= false and type(opts.math_conceal_marks_by_row) ~= "table" then
    local winid = buf_win(bufnr)
    local marks_by_row = display.collect_math_conceal_marks_by_row(bufnr, start_row, end_row, {
      winid = winid,
    }) or {}
    build_opts = vim.tbl_extend("force", opts, {
      math_conceal_marks_by_row = marks_by_row,
      winid = winid,
    })
  end
  for run_row = start_row, end_row do
    local row_lines, meta = build_line_run_row(bufnr, run_row, build_opts)
    if row_lines == nil then
      return false, start_row, end_row
    end
    for _, line in ipairs(row_lines) do
      display_lines[#display_lines + 1] = line
    end
    if meta and meta.inline_row then
      inline_rows[run_row] = true
    end
    if meta and meta.block_extmark_id ~= nil then
      block_extmark_ids[meta.block_extmark_id] = true
    end
  end

  if #display_lines == 0 then
    return false, start_row, end_row
  end

  local bs = state.get_buf_state(bufnr)
  bs.line_run_marks = bs.line_run_marks or {}
  bs.line_run_by_row = bs.line_run_by_row or {}
  bs.line_run_by_extmark = bs.line_run_by_extmark or {}
  bs.inline_line_marks = bs.inline_line_marks or {}
  bs.next_line_run_id = (bs.next_line_run_id or 0) + 1
  local run_id = bs.next_line_run_id

  local carrier_id = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id2, anchor_row, 0, {
    virt_lines = display_lines,
    virt_lines_above = virt_lines_above,
    virt_lines_overflow = "trunc",
  })

  local conceal_ids = {}
  for run_row = start_row, end_row do
    conceal_ids[run_row] = vim.api.nvim_buf_set_extmark(bufnr, state.ns_id2, run_row, 0, {
      conceal_lines = "",
      end_row = run_row,
    })
    bs.line_run_by_row[run_row] = run_id
  end

  bs.line_run_marks[run_id] = {
    carrier_id = carrier_id,
    conceal_ids = conceal_ids,
    extmark_ids = block_extmark_ids,
    block_extmark_ids = block_extmark_ids,
  }

  for run_row in pairs(inline_rows) do
    bs.inline_line_marks[run_row] = {
      carrier_id = carrier_id,
      conceal_id = conceal_ids[run_row],
      line_run_id = run_id,
    }
  end

  for extmark_id in pairs(block_extmark_ids) do
    local mm = bs.multiline_marks[extmark_id]
    if mm then
      mm.carrier_id = carrier_id
      mm.tail_ids = {}
      local range = extmark_range(bufnr, state.ns_id, extmark_id)
      if range ~= nil then
        for run_row = range.start_row, range.end_row do
          if conceal_ids[run_row] ~= nil then
            mm.tail_ids[#mm.tail_ids + 1] = conceal_ids[run_row]
          end
        end
      end
      mm.line_run_id = run_id
      bs.line_run_by_extmark[extmark_id] = run_id
    end
  end

  return true, start_row, end_row
end

function M.refresh_around_range(bufnr, start_row, end_row, opts)
  opts = opts or {}
  if type(start_row) ~= "number" or type(end_row) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  clear_line_runs_in_range(bufnr, start_row, end_row)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local boundary_rows = opts.anchor_rows or M.row_set(start_row, end_row)
  local refresh_opts = vim.tbl_extend("force", opts, {
    anchor_rows = boundary_rows,
  })

  if start_row > 0 then
    M.refresh_for_row(bufnr, start_row - 1, refresh_opts)
  end
  if end_row + 1 < line_count then
    M.refresh_for_row(bufnr, end_row + 1, refresh_opts)
  end
end

local function restore_line_attachments(bufnr, next_rows, opts)
  if type(opts.restore_row_attached_extmark) ~= "function" then
    return
  end
  local bs = state.get_buf_state(bufnr)
  local attachments = bs.inline_line_attachment_marks or {}
  for extmark_id, meta in pairs(vim.deepcopy(attachments)) do
    if not (next_rows and next_rows[meta.row]) then
      opts.restore_row_attached_extmark(bufnr, extmark_id, { defer_line_run_reconcile = true })
    end
  end
end

local function attach_inline_images_for_rows(bufnr, rows, opts)
  if rows == nil or type(opts.attach_inline_image_after_source) ~= "function" then
    return
  end

  local bs = state.get_buf_state(bufnr)
  bs.inline_line_attachment_marks = bs.inline_line_attachment_marks or {}
  for row in pairs(rows) do
    for _, item in ipairs(collect_inline_line_items(bufnr, row)) do
      local extmark_id = item.extmark_id or state.image_id_to_extmark[item.image_id]
      if extmark_id ~= nil then
        opts.attach_inline_image_after_source(bufnr, item, extmark_id, item.natural_cols, item.natural_rows)
      end
    end
  end
end

local function row_set_key(rows)
  local keys = {}
  for row in pairs(rows or {}) do
    keys[#keys + 1] = tonumber(row) or row
  end
  table.sort(keys)
  for idx, row in ipairs(keys) do
    keys[idx] = tostring(row)
  end
  return table.concat(keys, ",")
end

local function hidden_extmarks_key(bs)
  return row_set_key(bs.currently_hidden_extmark_ids or {})
end

local function reconcile_key(bufnr, bs, rows)
  return table.concat({
    row_set_key(rows),
    hidden_extmarks_key(bs),
    tostring(vim.api.nvim_buf_get_changedtick(bufnr)),
    tostring(get_win_text_cols(bufnr)),
  }, "|")
end

function M.reconcile_cursor_line_runs(bufnr, lo, hi, opts)
  if type(lo) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  opts = opts or {}
  hi = type(hi) == "number" and hi or lo
  local bs = state.get_buf_state(bufnr)
  local previous = bs.inline_line_suppressed_rows or {}
  local next_rows = {}

  for row = lo, hi do
    next_rows[row] = true
  end

  local next_key = reconcile_key(bufnr, bs, next_rows)
  if bs.inline_line_reconcile_key == next_key then
    return false
  end

  bs.inline_line_suppressed_rows = next_rows
  restore_line_attachments(bufnr, next_rows, opts)

  for row = lo, hi do
    M.clear_inline_line_mark(bufnr, row)
  end
  attach_inline_images_for_rows(bufnr, next_rows, opts)

  local refreshed_rows = {}
  local function refresh_once(row, refresh_opts)
    if refreshed_rows[row] then
      return nil
    end
    local ok, start_row, end_row = M.refresh_for_row(bufnr, row, refresh_opts)
    if type(start_row) == "number" and type(end_row) == "number" then
      for refreshed_row = start_row, end_row do
        refreshed_rows[refreshed_row] = true
      end
    else
      refreshed_rows[row] = true
    end
    return ok
  end

  for row in pairs(previous) do
    if not next_rows[row] then
      refresh_once(row, {
        ignore_cursor = true,
        anchor_rows = next_rows,
        suppressed_rows = next_rows,
      })
    end
  end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  for row = math.max(0, lo - 1), math.min(line_count - 1, hi + 1) do
    if not next_rows[row] then
      refresh_once(row, {
        anchor_rows = next_rows,
        suppressed_rows = next_rows,
      })
    end
  end

  bs.inline_line_reconcile_key = next_key
  return true
end

return M
