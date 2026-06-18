local display = require("math-conceal.image.display")
local state = require("math-conceal.image.state")
local tracker = require("math-conceal.image.tracker")

local M = {}

local state_by_buf = {}

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function lt(a_row, a_col, b_row, b_col)
  return a_row < b_row or (a_row == b_row and a_col < b_col)
end

local function point_in_range(row, col, range)
  if range == nil then
    return false
  end
  if range.row == range.end_row then
    return row == range.row and col >= range.col and col < range.end_col
  end
  return (row == range.row and col >= range.col)
    or (row == range.end_row and col < range.end_col)
    or (row > range.row and row < range.end_row)
end

local function row_in_range(row, range)
  return range ~= nil and row >= range.row and row <= range.end_row
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

local function mark_rows(rows, start_row, end_row)
  for row = start_row, end_row do
    rows[row] = true
  end
end

local function new_extmark_groups()
  return {
    line_runs = {},
    conceal_rows = {},
    row_attached = {},
  }
end

local function ensure_state(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local fd = state_by_buf[bufnr]
  if fd == nil then
    fd = {
      extmarks = new_extmark_groups(),
      line_runs = {},
      row_attached = {},
      suppressed_track_keys = {},
      reconcile_key = nil,
    }
    state_by_buf[bufnr] = fd
  end
  fd.extmarks = fd.extmarks or new_extmark_groups()
  return fd
end

local function delete_extmark(bufnr, ns, id)
  if id ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, id)
  end
end

local function source_line(bufnr, row)
  return tracker.source_line(bufnr, row)
end

local function line_len(bufnr, row)
  return #source_line(bufnr, row)
end

local function ref_from_snapshot(snapshot)
  return {
    bufnr = snapshot.bufnr,
    tracker_generation = snapshot.tracker_generation,
    generation = snapshot.generation,
    track_id = snapshot.track_id,
    id = snapshot.track_id,
  }
end

local function display_asset_for_key(bufnr, key)
  local bs = state.get_buf_state(bufnr)
  local item = bs.display_assets and bs.display_assets[key] or nil
  if item == nil or item.source_reveal == true or item.asset == nil then
    return nil
  end
  return item.asset
end

local function classify_equation(view)
  local facts = view.source_facts or {}
  local inline = facts.inline
  if inline == nil then
    inline = view.source_display_kind ~= "block"
  end
  local break_line = facts.break_line
  if break_line == nil then
    break_line = view.row ~= view.end_row
  end
  return {
    inline = inline == true,
    break_line = break_line == true,
    isolated = facts.isolated == true,
  }
end

local function row_attachable(equation)
  return equation.inline == true and equation.break_line ~= true
end

local function node_revealable(equation)
  return row_attachable(equation) or (equation.inline ~= true and equation.isolated == true)
end

local function row_revealed(equation)
  return not node_revealable(equation)
end

local function resolve_views(bufnr, snapshots)
  local views = {}
  for _, snapshot in ipairs(snapshots or tracker.get_tracks(bufnr)) do
    local ref = ref_from_snapshot(snapshot)
    local view = tracker.view(ref, { require_valid = true })
    if view ~= nil and view.kind == "typst" then
      view.ref = ref
      view.key = tracker.track_ref_key(ref)
      view.equation = classify_equation(view)
      view.asset = display_asset_for_key(bufnr, view.key)
      views[#views + 1] = view
    end
  end
  table.sort(views, function(a, b)
    if a.row ~= b.row or a.col ~= b.col then
      return lt(a.row, a.col, b.row, b.col)
    end
    return a.track_id < b.track_id
  end)
  return views
end

local function views_by_key(views)
  local by_key = {}
  for _, view in ipairs(views or {}) do
    by_key[view.key] = view
  end
  return by_key
end

local function cursor_for_buf(bufnr)
  local win = vim.fn.bufwinid(bufnr)
  if win == -1 or not vim.api.nvim_win_is_valid(win) then
    return nil, nil
  end
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
  if not ok or cursor == nil then
    return nil, nil
  end
  return cursor[1] - 1, cursor[2]
end

local function visual_rows()
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil, nil
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local vrow = vim.fn.getpos("v")[2] - 1
  return math.min(cursor[1] - 1, vrow), math.max(cursor[1] - 1, vrow)
end

local function find_active(bufnr, views)
  local row, col = cursor_for_buf(bufnr)
  if row == nil then
    return nil
  end
  for _, view in ipairs(views) do
    if node_revealable(view.equation) and point_in_range(row, col, view) then
      return { view = view, row = row, col = col }
    end
  end
  return nil
end

local function view_touches_rows(view, rows)
  for row = view.row, view.end_row do
    if rows[row] then
      return true
    end
  end
  return false
end

local function build_plan(bufnr, views, config)
  local rows = {}
  for _, view in ipairs(views) do
    if view.asset == nil then
      mark_rows(rows, view.row, view.end_row)
    end
  end

  local visual_start, visual_end = visual_rows()
  if visual_start ~= nil then
    mark_rows(rows, visual_start, visual_end)
    return {
      visual = true,
      active = nil,
      suppressed_rows = rows,
      key = "visual:" .. tostring(visual_start) .. ":" .. tostring(visual_end) .. ":" .. row_set_key(rows),
    }
  end

  local mode = vim.api.nvim_get_mode().mode or ""
  if config and config.conceal_in_normal == true and mode == "n" then
    return {
      visual = false,
      active = nil,
      suppressed_rows = rows,
      key = "normal-conceal:" .. row_set_key(rows),
    }
  end

  local cursor_row = cursor_for_buf(bufnr)
  local active = find_active(bufnr, views)
  if cursor_row ~= nil then
    rows[cursor_row] = true
    if active ~= nil and active.view ~= nil then
      mark_rows(rows, active.view.row, active.view.end_row)
    end
    for _, view in ipairs(views) do
      if row_revealed(view.equation) and cursor_row >= view.row and cursor_row <= view.end_row then
        mark_rows(rows, view.row, view.end_row)
      end
    end
  end

  return {
    visual = false,
    active = active,
    suppressed_rows = rows,
    key = table.concat({
      mode,
      tostring(cursor_row),
      active and active.view and active.view.key or "",
      row_set_key(rows),
    }, "|"),
  }
end

local function add_key(keys, key)
  if key == nil or keys[key] == true then
    return false
  end
  keys[key] = true
  return true
end

local function merge_keys(dst, src)
  local changed = false
  for key in pairs(src or {}) do
    if add_key(dst, key) then
      changed = true
    end
  end
  return changed
end

local function has_keys(keys)
  for _ in pairs(keys or {}) do
    return true
  end
  return false
end

local function sorted_keys(keys)
  local sorted = {}
  for key in pairs(keys or {}) do
    sorted[#sorted + 1] = key
  end
  table.sort(sorted)
  return sorted
end

local function ref_key_set(refs)
  local keys = {}
  for _, ref in ipairs(refs or {}) do
    add_key(keys, tracker.track_ref_key(ref))
  end
  return keys
end

local function all_view_keys(views)
  local keys = {}
  for _, view in ipairs(views or {}) do
    add_key(keys, view.key)
  end
  return keys
end

local function suppressed_track_keys(views, plan)
  local keys = {}
  for _, view in ipairs(views or {}) do
    if view_touches_rows(view, plan.suppressed_rows) then
      add_key(keys, view.key)
    end
  end
  return keys
end

local function run_track_keys(run)
  local keys = {}
  for _, view in ipairs(run.views or {}) do
    keys[#keys + 1] = view.key
  end
  return keys
end

local function artifact_depends_on(artifact, keys)
  for _, key in ipairs((artifact and artifact.track_keys) or {}) do
    if keys[key] then
      return true
    end
  end
  return false
end

local function line_empty(line)
  return line == nil or #line == 0
end

local function append_chunk(lines, text, hl)
  if text == nil or text == "" then
    return
  end
  local line = lines[#lines]
  local last = line[#line]
  if last ~= nil and last[2] == (hl or "") then
    last[1] = last[1] .. text
  else
    line[#line + 1] = { text, hl or "" }
  end
end

local function newline(lines)
  lines[#lines + 1] = {}
end

local function trim_line_trailing_space(line)
  while line ~= nil and #line > 0 do
    local chunk = line[#line]
    local text = chunk and chunk[1] or ""
    local trimmed = text:gsub("[ \t]+$", "")
    if trimmed == text then
      return
    end
    if trimmed == "" then
      table.remove(line)
    else
      chunk[1] = trimmed
      return
    end
  end
end

local function append_text(lines, text, hl)
  text = text or ""
  while true do
    local first, last = text:find("\n", 1, true)
    if first == nil then
      append_chunk(lines, text, hl)
      return
    end
    append_chunk(lines, text:sub(1, first - 1), hl)
    newline(lines)
    text = text:sub(last + 1)
  end
end

local function trim_next_source_leading_space(layout, text)
  if layout == nil or layout.trim_next_source_leading_space ~= true then
    return text
  end
  layout.trim_next_source_leading_space = false
  local trimmed = (text or ""):gsub("^[ \t]+", "")
  return trimmed
end

local function append_source_text(lines, text, layout)
  append_text(lines, trim_next_source_leading_space(layout, text), "")
end

local function append_source_segment(lines, bufnr, from_pos, to_pos, layout)
  if from_pos.row == to_pos.row then
    local line = source_line(bufnr, from_pos.row)
    append_source_text(lines, line:sub(from_pos.col + 1, to_pos.col), layout)
    return
  end

  local first = source_line(bufnr, from_pos.row)
  append_source_text(lines, first:sub(from_pos.col + 1), layout)
  newline(lines)
  for row = from_pos.row + 1, to_pos.row - 1 do
    append_source_text(lines, source_line(bufnr, row), layout)
    newline(lines)
  end
  local last = source_line(bufnr, to_pos.row)
  append_source_text(lines, last:sub(1, to_pos.col), layout)
end

local function append_image_atom(lines, bufnr, view, layout)
  local asset = view.asset
  if asset == nil then
    return
  end
  local cols = math.max(1, math.floor(tonumber(asset.cols) or 1))
  local rows = math.max(1, math.floor(tonumber(asset.rows) or 1))
  local hl = state.image_hl_group(asset.image_id)

  if view.equation.inline then
    append_chunk(lines, display.placeholder_row(1, cols), hl)
    return
  end

  trim_line_trailing_space(lines[#lines])
  if not line_empty(lines[#lines]) then
    newline(lines)
  end
  local win_width = state.visible_window_width(bufnr)
  local pad = cols < win_width and math.floor((win_width - cols) / 2) or 0
  local pad_text = pad > 0 and string.rep(" ", pad) or ""
  for row = 1, rows do
    append_chunk(lines, pad_text .. display.placeholder_row(row, cols), hl)
    newline(lines)
  end
  if layout ~= nil then
    layout.trim_next_source_leading_space = true
  end
end

local function finalize_lines(lines)
  while #lines > 1 and line_empty(lines[#lines]) do
    table.remove(lines)
  end
  if #lines == 0 then
    return { { { "", "" } } }
  end
  for _, line in ipairs(lines) do
    if #line == 0 then
      line[1] = { "", "" }
    end
  end
  return lines
end

local function compose_run(bufnr, run)
  local lines = { {} }
  local layout = {}
  local pos = { row = run.start_row, col = 0 }
  for _, view in ipairs(run.views) do
    append_source_segment(lines, bufnr, pos, { row = view.row, col = view.col }, layout)
    append_image_atom(lines, bufnr, view, layout)
    pos = { row = view.end_row, col = view.end_col }
  end
  append_source_segment(lines, bufnr, pos, { row = run.end_row, col = line_len(bufnr, run.end_row) }, layout)
  return finalize_lines(lines)
end

local function eligible_view(view, suppressed_rows)
  return view.asset ~= nil and not view_touches_rows(view, suppressed_rows)
end

local function run_around_row(row, views, suppressed_rows)
  local seed = nil
  for _, view in ipairs(views) do
    if eligible_view(view, suppressed_rows) and row_in_range(row, view) then
      seed = view
      break
    end
  end
  if seed == nil then
    return nil
  end

  local included = { [seed.key] = true }
  local run = {
    start_row = seed.row,
    end_row = seed.end_row,
    views = { seed },
  }

  local changed = true
  while changed do
    changed = false
    for _, view in ipairs(views) do
      if
        not included[view.key]
        and eligible_view(view, suppressed_rows)
        and view.row <= run.end_row + 1
        and view.end_row >= run.start_row - 1
      then
        included[view.key] = true
        run.views[#run.views + 1] = view
        run.start_row = math.min(run.start_row, view.row)
        run.end_row = math.max(run.end_row, view.end_row)
        changed = true
      end
    end
  end

  table.sort(run.views, function(a, b)
    if a.row ~= b.row or a.col ~= b.col then
      return lt(a.row, a.col, b.row, b.col)
    end
    return a.track_id < b.track_id
  end)
  return run
end

local function line_run_key(run)
  local keys = {}
  for _, view in ipairs(run.views) do
    keys[#keys + 1] = view.key
  end
  return "run:" .. table.concat(keys, "|")
end

local function row_attached_key(view)
  return "row:" .. view.key
end

local function clear_row_attached(bufnr, fd, key)
  delete_extmark(bufnr, state.display_ns, fd.extmarks.row_attached[key])
  fd.extmarks.row_attached[key] = nil
  fd.row_attached[key] = nil
end

local function clear_line_run(bufnr, fd, key)
  local run = fd.line_runs[key]
  if run == nil then
    return
  end
  delete_extmark(bufnr, state.display_ns, fd.extmarks.line_runs[key])
  fd.extmarks.line_runs[key] = nil
  for _, conceal_key in pairs(run.conceal_keys or {}) do
    delete_extmark(bufnr, state.aux_ns, fd.extmarks.conceal_rows[conceal_key])
    fd.extmarks.conceal_rows[conceal_key] = nil
  end
  fd.line_runs[key] = nil
end

local function clear_all_artifacts(bufnr, fd)
  local line_run_keys = {}
  for key in pairs(fd.line_runs or {}) do
    line_run_keys[#line_run_keys + 1] = key
  end
  for _, key in ipairs(line_run_keys) do
    clear_line_run(bufnr, fd, key)
  end

  local row_attached_keys = {}
  for key in pairs(fd.row_attached or {}) do
    row_attached_keys[#row_attached_keys + 1] = key
  end
  for _, key in ipairs(row_attached_keys) do
    clear_row_attached(bufnr, fd, key)
  end
end

local function clear_artifacts_for_track_keys(bufnr, fd, keys)
  local touched = {}
  if not has_keys(keys) then
    return touched
  end

  local line_run_keys = {}
  for key, artifact in pairs(fd.line_runs or {}) do
    if artifact_depends_on(artifact, keys) then
      for _, track_key in ipairs(artifact.track_keys or {}) do
        add_key(touched, track_key)
      end
      line_run_keys[#line_run_keys + 1] = key
    end
  end
  for _, key in ipairs(line_run_keys) do
    clear_line_run(bufnr, fd, key)
  end

  local row_attached_keys = {}
  for key, artifact in pairs(fd.row_attached or {}) do
    if artifact_depends_on(artifact, keys) then
      for _, track_key in ipairs(artifact.track_keys or {}) do
        add_key(touched, track_key)
      end
      row_attached_keys[#row_attached_keys + 1] = key
    end
  end
  for _, key in ipairs(row_attached_keys) do
    clear_row_attached(bufnr, fd, key)
  end

  return touched
end

local function slice_lines(lines, first, last)
  local out = {}
  if type(lines) ~= "table" or first == nil or last == nil or first > last then
    return out
  end
  for idx = first, math.min(last, #lines) do
    out[#out + 1] = lines[idx]
  end
  return out
end

local function source_line_landing_opts(bufnr, row, virt_text, virt_lines)
  local opts = {
    virt_text = virt_text,
    virt_text_pos = "overlay",
    conceal = "",
    end_row = row,
    end_col = line_len(bufnr, row),
    right_gravity = true,
    end_right_gravity = false,
    invalidate = true,
    priority = 220,
  }
  if #virt_lines > 0 then
    opts.virt_lines = virt_lines
    opts.virt_lines_overflow = "trunc"
  end
  return opts
end

local function render_line_run(bufnr, fd, run)
  local key = line_run_key(run)

  local display_lines = compose_run(bufnr, run)
  local lead = run.views[1]
  if lead == nil then
    return
  end
  local anchor_row = lead.row
  local first_line = display_lines[1] or { { "", "" } }
  local tail_lines = slice_lines(display_lines, 2, #display_lines)
  local opts = source_line_landing_opts(bufnr, anchor_row, first_line, tail_lines)
  opts.id = fd.extmarks.line_runs[key]
  fd.extmarks.line_runs[key] = vim.api.nvim_buf_set_extmark(bufnr, state.display_ns, anchor_row, 0, opts)

  local conceal_keys = {}
  local conceal_idx = 0
  for row = run.start_row, run.end_row do
    if row ~= anchor_row then
      conceal_idx = conceal_idx + 1
      local conceal_key = key .. ":conceal:" .. tostring(conceal_idx)
      conceal_keys[#conceal_keys + 1] = conceal_key
      fd.extmarks.conceal_rows[conceal_key] = vim.api.nvim_buf_set_extmark(bufnr, state.aux_ns, row, 0, {
        id = fd.extmarks.conceal_rows[conceal_key],
        conceal_lines = "",
        end_row = row,
        invalidate = true,
        priority = 220,
      })
    end
  end

  fd.line_runs[key] = {
    track_keys = run_track_keys(run),
    conceal_keys = conceal_keys,
  }
end

local function render_row_attached_view(bufnr, fd, view, plan)
  if plan.visual == true then
    return
  end
  local active_key = plan.active and plan.active.view and plan.active.view.key or nil
  if
    view.asset == nil
    or view.key == active_key
    or not row_attachable(view.equation)
    or not plan.suppressed_rows[view.row]
  then
    return
  end

  local key = row_attached_key(view)
  local asset = view.asset
  local cols = math.max(1, math.floor(tonumber(asset.cols) or 1))
  local hl = state.image_hl_group(asset.image_id)
  fd.extmarks.row_attached[key] = vim.api.nvim_buf_set_extmark(bufnr, state.display_ns, view.row, view.col, {
    id = fd.extmarks.row_attached[key],
    end_row = view.end_row,
    end_col = view.end_col,
    conceal = "",
    virt_text = { { display.placeholder_row(1, cols), hl } },
    virt_text_pos = "inline",
    invalidate = true,
    priority = 230,
  })
  fd.row_attached[key] = {
    track_keys = { view.key },
  }
end

local function expand_render_keys_by_current_runs(render_keys, by_key, views, plan)
  local changed = false
  for _, key in ipairs(sorted_keys(render_keys)) do
    local view = by_key[key]
    if view ~= nil and eligible_view(view, plan.suppressed_rows) then
      local run = run_around_row(view.row, views, plan.suppressed_rows)
      for _, track_key in ipairs(run and run_track_keys(run) or {}) do
        if add_key(render_keys, track_key) then
          changed = true
        end
      end
    end
  end
  return changed
end

local function render_track_keys(bufnr, fd, views, plan, keys)
  if not has_keys(keys) then
    return
  end

  local by_key = views_by_key(views)
  local render_keys = {}
  merge_keys(render_keys, keys)

  local changed = true
  while changed do
    changed = expand_render_keys_by_current_runs(render_keys, by_key, views, plan)
    local touched = clear_artifacts_for_track_keys(bufnr, fd, render_keys)
    if merge_keys(render_keys, touched) then
      changed = true
    end
  end

  local rendered_runs = {}
  for _, key in ipairs(sorted_keys(render_keys)) do
    local view = by_key[key]
    if view ~= nil then
      if eligible_view(view, plan.suppressed_rows) then
        local run = run_around_row(view.row, views, plan.suppressed_rows)
        local run_key = run and line_run_key(run) or nil
        if run ~= nil and not rendered_runs[run_key] then
          render_line_run(bufnr, fd, run)
          rendered_runs[run_key] = true
        end
      else
        render_row_attached_view(bufnr, fd, view, plan)
      end
    end
  end
end

function M.on_tracker_repair(event, config)
  if event == nil or event.bufnr == nil or not vim.api.nvim_buf_is_valid(event.bufnr) then
    return
  end
  local bufnr = normalize_bufnr(event.bufnr)
  local fd = ensure_state(bufnr)
  local views = resolve_views(bufnr, event.tracks)
  local plan = build_plan(bufnr, views, config or {})
  local suppressed_keys = suppressed_track_keys(views, plan)

  if event.initial == true then
    clear_all_artifacts(bufnr, fd)
    render_track_keys(bufnr, fd, views, plan, all_view_keys(views))
  else
    local keys = ref_key_set(event.affected_refs)
    merge_keys(keys, ref_key_set(event.retired_refs))
    merge_keys(keys, fd.suppressed_track_keys)
    merge_keys(keys, suppressed_keys)
    render_track_keys(bufnr, fd, views, plan, keys)
  end

  fd.suppressed_track_keys = suppressed_keys
  fd.reconcile_key = plan.key
end

function M.repair_tracks(bufnr, refs, config)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local fd = ensure_state(bufnr)
  local views = resolve_views(bufnr)
  local plan = build_plan(bufnr, views, config or {})
  local suppressed_keys = suppressed_track_keys(views, plan)
  local keys = ref_key_set(refs)
  merge_keys(keys, fd.suppressed_track_keys)
  merge_keys(keys, suppressed_keys)
  render_track_keys(bufnr, fd, views, plan, keys)
  fd.suppressed_track_keys = suppressed_keys
  fd.reconcile_key = plan.key
end

function M.sync_cursor(bufnr, config)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local fd = ensure_state(bufnr)
  local views = resolve_views(bufnr)
  local plan = build_plan(bufnr, views, config or {})
  if fd.reconcile_key == plan.key then
    return
  end

  local suppressed_keys = suppressed_track_keys(views, plan)
  local keys = {}
  merge_keys(keys, fd.suppressed_track_keys)
  merge_keys(keys, suppressed_keys)
  render_track_keys(bufnr, fd, views, plan, keys)
  fd.suppressed_track_keys = suppressed_keys
  fd.reconcile_key = plan.key
end

function M.refresh(bufnr, config)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  M.detach(bufnr)
  local fd = ensure_state(bufnr)
  local views = resolve_views(bufnr)
  local plan = build_plan(bufnr, views, config or {})
  render_track_keys(bufnr, fd, views, plan, all_view_keys(views))
  fd.suppressed_track_keys = suppressed_track_keys(views, plan)
  fd.reconcile_key = plan.key
end

function M.detach(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.display_ns, 0, -1)
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.aux_ns, 0, -1)
  end
  state_by_buf[bufnr] = nil
end

return M
