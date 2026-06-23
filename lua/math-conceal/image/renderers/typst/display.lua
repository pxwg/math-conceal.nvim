local flow_classification = require("math-conceal.image.renderers.typst.flow")
local repair_event = require("math-conceal.image.repair-event")
local state = require("math-conceal.image.state")
local surface = require("math-conceal.image.surface")
local tracker = require("math-conceal.image.tracker")

local M = {}

local state_by_buf = {}

local CONCEAL_PRIORITY = 210
local SLOT_PRIORITY = 220

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function lt(a_row, a_col, b_row, b_col)
  return a_row < b_row or (a_row == b_row and a_col < b_col)
end

local function is_blank(text)
  return (text or ""):match("^%s*$") ~= nil
end

local function new_extmark_groups()
  return {
    node_slots = {},
    conceal_spans = {},
    conceal_rows = {},
  }
end

local function ensure_state(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local fd = state_by_buf[bufnr]
  if fd == nil then
    fd = {
      extmarks = new_extmark_groups(),
      suppressed_track_keys = {},
      reconcile_key = nil,
      layout_mode = nil,
    }
    state_by_buf[bufnr] = fd
  end
  fd.extmarks = fd.extmarks or new_extmark_groups()
  fd.suppressed_track_keys = fd.suppressed_track_keys or {}
  return fd
end

local function delete_extmark(bufnr, ns, id)
  if id ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, ns, id)
  end
end

local function delete_group_extmark(bufnr, group, ns, key)
  delete_extmark(bufnr, ns, group[key])
  group[key] = nil
end

local function source_line(bufnr, row)
  return tracker.source_line(bufnr, row)
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
    kind = "math",
    inline = inline == true,
    break_line = break_line == true,
    isolated = facts.isolated == true,
    renderable = true,
  }
end

local function classify_code(view)
  local ctx = state.get_buf_state(view.bufnr).context
  local entry = flow_classification.classification(view.bufnr, view, ctx)
  local role = entry and (entry.layout_role or entry.flow_role) or nil
  local display_view = flow_classification.apply_role(view, role, {
    flow_role = entry and entry.flow_role or nil,
    render_policy = entry and entry.render_policy or nil,
    reason = entry and entry.layout_reason or nil,
  })
  local break_line = view.row ~= view.end_row
  if display_view ~= nil and display_view.source_display_kind == "inline" then
    return {
      kind = "code",
      inline = true,
      break_line = break_line,
      isolated = false,
      flow_role = entry and entry.flow_role or role,
      display_role = "inline",
      render_policy = display_view.source_facts and display_view.source_facts.render_policy or nil,
      renderable = true,
    }
  end
  if display_view ~= nil and display_view.source_display_kind == "block" then
    local start_line = source_line(view.bufnr, view.row)
    local end_line = source_line(view.bufnr, view.end_row)
    local prefix = start_line:sub(1, view.col)
    local suffix = end_line:sub(view.end_col + 1)
    return {
      kind = "code",
      inline = false,
      break_line = break_line,
      isolated = break_line == true or (is_blank(prefix) and is_blank(suffix)),
      flow_role = entry and entry.flow_role or role,
      display_role = "block",
      render_policy = display_view.source_facts and display_view.source_facts.render_policy or nil,
      renderable = true,
    }
  end
  return {
    kind = "code",
    inline = false,
    break_line = true,
    isolated = false,
    flow_role = entry and entry.flow_role or "unknown",
    display_role = "unknown",
    renderable = false,
  }
end

local function classify_object(view)
  if (view.object_kind or view.node_type) == "code" then
    return classify_code(view)
  end
  return classify_equation(view)
end

local function view_from_snapshot(bufnr, snapshot)
  if
    snapshot == nil
    or snapshot.invalid == true
    or snapshot.state ~= "valid"
    or snapshot.kind ~= "typst"
    or (snapshot.track_id or snapshot.id) == nil
  then
    return nil
  end

  local ref = ref_from_snapshot(snapshot)
  local key = tracker.track_ref_key(ref)
  local view = {}
  for field, value in pairs(snapshot) do
    view[field] = value
  end
  view.ref = ref
  view.key = key
  view.object = classify_object(view)
  if view.object and view.object.renderable == false then
    view.asset = nil
  else
    view.asset = display_asset_for_key(bufnr, key)
  end
  return view
end

local function resolve_views(bufnr, snapshots)
  snapshots = snapshots or tracker.get_tracks(bufnr)

  local views = {}
  for _, snapshot in ipairs(snapshots) do
    local view = view_from_snapshot(bufnr, snapshot)
    if view ~= nil then
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

local function ref_key_set(refs)
  local keys = {}
  for _, ref in ipairs(refs or {}) do
    add_key(keys, tracker.track_ref_key(ref))
  end
  return keys
end

local function all_plan_keys(node_plans)
  local keys = {}
  for _, plan in ipairs(node_plans or {}) do
    add_key(keys, plan.view.key)
  end
  return keys
end

local function sorted_keys(keys)
  local sorted = {}
  for key in pairs(keys or {}) do
    sorted[#sorted + 1] = key
  end
  table.sort(sorted)
  return sorted
end

local function key_set_key(keys)
  return table.concat(sorted_keys(keys), ",")
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

local function visual_selection()
  local mode = vim.api.nvim_get_mode().mode
  if mode ~= "v" and mode ~= "V" and mode ~= "\22" then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local mark = vim.fn.getpos("v")
  local cursor_row, cursor_col = cursor[1] - 1, cursor[2]
  local mark_row, mark_col = mark[2] - 1, math.max(0, mark[3] - 1)
  local start_row, start_col = mark_row, mark_col
  local end_row, end_col = cursor_row, cursor_col
  if lt(end_row, end_col, start_row, start_col) then
    start_row, start_col, end_row, end_col = end_row, end_col, start_row, start_col
  end

  if mode == "V" then
    return {
      mode = "line",
      start_row = math.min(mark_row, cursor_row),
      end_row = math.max(mark_row, cursor_row),
    }
  end

  if mode == "\22" then
    return {
      mode = "block",
      start_row = math.min(mark_row, cursor_row),
      end_row = math.max(mark_row, cursor_row),
      start_col = math.min(mark_col, cursor_col),
      end_col = math.max(mark_col, cursor_col) + 1,
    }
  end

  return {
    mode = "char",
    start_row = start_row,
    start_col = start_col,
    end_row = end_row,
    end_col = end_col + 1,
  }
end

local function add_fragment(fragments, row, col, end_col, line)
  local len = #line
  local prefix = line:sub(1, col)
  local suffix = line:sub(end_col + 1)
  fragments[#fragments + 1] = {
    row = row,
    col = col,
    end_col = math.max(col, end_col),
    empty_row = len == 0 and col == 0 and end_col == 0,
    fragment_only = is_blank(prefix) and is_blank(suffix),
  }
end

local function node_boundary_context(bufnr, view)
  local start_line = source_line(bufnr, view.row)
  local end_line = view.row == view.end_row and start_line or source_line(bufnr, view.end_row)
  local prefix = start_line:sub(1, view.col)
  local suffix = end_line:sub(view.end_col + 1)
  local absorbed_end_col = view.end_col

  if view.object.inline == true and view.row ~= view.end_row then
    local blanks = suffix:match("^[ \t]*") or ""
    absorbed_end_col = view.end_col + #blanks
  end

  return {
    start_line = start_line,
    end_line = end_line,
    prefix_blank = is_blank(prefix),
    suffix_blank = is_blank(suffix),
    absorbed_end_col = absorbed_end_col,
  }
end

local function collect_fragments(bufnr, view, context)
  local fragments = {}
  if view.row == view.end_row then
    add_fragment(fragments, view.row, view.col, view.end_col, context.start_line)
    return fragments
  end

  add_fragment(fragments, view.row, view.col, #context.start_line, context.start_line)
  for row = view.row + 1, view.end_row - 1 do
    local line = source_line(bufnr, row)
    add_fragment(fragments, row, 0, #line, line)
  end
  add_fragment(fragments, view.end_row, 0, context.absorbed_end_col, context.end_line)
  return fragments
end

local function build_node_plan(bufnr, view)
  local context = node_boundary_context(bufnr, view)
  local fragments = collect_fragments(bufnr, view, context)
  local single_line = view.row == view.end_row
  local block_shape = nil
  if view.object.inline ~= true then
    if context.prefix_blank and context.suffix_blank then
      block_shape = "isolated"
    elseif context.prefix_blank then
      block_shape = "suffix"
    elseif context.suffix_blank then
      block_shape = "prefix"
    elseif single_line then
      block_shape = "sandwich"
    else
      block_shape = "prefix"
    end
  end
  return {
    view = view,
    fragments = fragments,
    start_fragment = fragments[1],
    end_fragment = fragments[#fragments],
    single_line = single_line,
    prefix_blank = context.prefix_blank,
    suffix_blank = context.suffix_blank,
    source_reveal = block_shape == "sandwich" or view.asset == nil or (view.object and view.object.renderable == false),
    block_shape = block_shape,
  }
end

local function fragments_overlap(a, b)
  if a.row ~= b.row then
    return false
  end
  if a.empty_row or b.empty_row then
    return a.empty_row and b.empty_row
  end
  return a.col < b.end_col and b.col < a.end_col
end

local function mark_conflicts(node_plans)
  for i = 1, #node_plans do
    for j = i + 1, #node_plans do
      local a = node_plans[i]
      local b = node_plans[j]
      for _, left in ipairs(a.fragments) do
        for _, right in ipairs(b.fragments) do
          if fragments_overlap(left, right) then
            a.source_reveal = true
            b.source_reveal = true
          end
        end
      end
    end
  end
end

local function build_node_plans(bufnr, views)
  local node_plans = {}
  local by_key = {}
  for _, view in ipairs(views) do
    local plan = build_node_plan(bufnr, view)
    node_plans[#node_plans + 1] = plan
    by_key[view.key] = plan
  end
  mark_conflicts(node_plans)
  return node_plans, by_key
end

local function node_source_cols_for_row(plan, row)
  local view = plan and plan.view or nil
  if view == nil or row < view.row or row > view.end_row then
    return nil, nil
  end

  if view.row == view.end_row then
    return view.col, view.end_col
  end
  if row == view.row then
    return view.col, math.huge
  end
  if row == view.end_row then
    return 0, view.end_col
  end
  return 0, math.huge
end

local function cursor_collides_with_plan(row, col, plan)
  if row == nil then
    return false
  end
  local start_col, end_col = node_source_cols_for_row(plan, row)
  return start_col ~= nil and col >= start_col and col < end_col
end

local function selection_cols_for_row(selection, row)
  if selection == nil or row < selection.start_row or row > selection.end_row then
    return nil, nil
  end
  if selection.mode == "line" then
    return 0, math.huge
  end
  if selection.mode == "block" then
    return selection.start_col, selection.end_col
  end
  if selection.start_row == selection.end_row then
    return selection.start_col, selection.end_col
  end
  if row == selection.start_row then
    return selection.start_col, math.huge
  end
  if row == selection.end_row then
    return 0, selection.end_col
  end
  return 0, math.huge
end

local function ranges_overlap(a_start, a_end, b_start, b_end)
  return a_start < b_end and b_start < a_end
end

local function selection_collides_with_plan(selection, plan)
  if selection == nil or plan == nil or plan.view == nil then
    return false
  end

  local start_row = math.max(selection.start_row, plan.view.row)
  local end_row = math.min(selection.end_row, plan.view.end_row)
  if start_row > end_row then
    return false
  end

  for row = start_row, end_row do
    local selection_start_col, selection_end_col = selection_cols_for_row(selection, row)
    local node_start_col, node_end_col = node_source_cols_for_row(plan, row)
    if
      selection_start_col ~= nil
      and node_start_col ~= nil
      and ranges_overlap(selection_start_col, selection_end_col, node_start_col, node_end_col)
    then
      return true
    end
  end

  return false
end

local function source_reveal_keys(node_plans)
  local keys = {}
  for _, plan in ipairs(node_plans) do
    if plan.source_reveal then
      add_key(keys, plan.view.key)
    end
  end
  return keys
end

local function collision_keys(bufnr, node_plans, config)
  local selection = visual_selection()
  local keys = {}
  if selection ~= nil then
    for _, plan in ipairs(node_plans) do
      if selection_collides_with_plan(selection, plan) then
        add_key(keys, plan.view.key)
      end
    end
    return keys,
      "visual:" .. selection.mode .. ":" .. tostring(selection.start_row) .. ":" .. tostring(selection.end_row)
  end

  local mode = vim.api.nvim_get_mode().mode or ""
  if config and config.conceal_in_normal == true and mode == "n" then
    return keys, "normal-conceal"
  end

  local row, col = cursor_for_buf(bufnr)
  for _, plan in ipairs(node_plans) do
    if cursor_collides_with_plan(row, col, plan) then
      add_key(keys, plan.view.key)
    end
  end
  return keys, table.concat({ mode, tostring(row), tostring(col) }, ":")
end

local function compact_in_wrap_enabled(config)
  return config == nil or config.compact_in_wrap ~= false
end

local function visible_windows_for_buf(bufnr)
  local wins = {}
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      wins[#wins + 1] = win
    end
  end
  return wins
end

local function has_wrapped_window(bufnr)
  for _, win in ipairs(visible_windows_for_buf(bufnr)) do
    if vim.wo[win].wrap then
      return true
    end
  end
  return false
end

local function display_layout_mode(bufnr, config)
  if compact_in_wrap_enabled(config) or not has_wrapped_window(bufnr) then
    return "compact"
  end
  return "noncompact"
end

local function build_projection_plan(bufnr, snapshots, config)
  config = config or {}
  local layout_mode = display_layout_mode(bufnr, config)
  local views = resolve_views(bufnr, snapshots)
  local node_plans, plans_by_key = build_node_plans(bufnr, views)
  local suppressed_keys = source_reveal_keys(node_plans)
  local cursor_keys, collision_key = collision_keys(bufnr, node_plans, config)
  merge_keys(suppressed_keys, cursor_keys)
  return {
    views = views,
    node_plans = node_plans,
    plans_by_key = plans_by_key,
    suppressed_keys = suppressed_keys,
    layout_mode = layout_mode,
    key = collision_key .. "|layout:" .. layout_mode .. "|" .. key_set_key(suppressed_keys),
  }
end

local function node_slot_key(track_key, index)
  if index ~= nil then
    return "slot:" .. track_key .. ":row:" .. tostring(index)
  end
  return "slot:" .. track_key
end

local function node_slot_prefix(track_key)
  return "slot:" .. track_key .. ":"
end

local function conceal_span_key(track_key, index)
  return "conceal:" .. track_key .. ":" .. tostring(index)
end

local function conceal_row_key(track_key, index)
  return "conceal-line:" .. track_key .. ":" .. tostring(index)
end

local function clear_group_prefix(bufnr, group, ns, prefix)
  for key in pairs(vim.deepcopy(group)) do
    if key:sub(1, #prefix) == prefix then
      delete_group_extmark(bufnr, group, ns, key)
    end
  end
end

local function clear_artifacts_for_track_key(bufnr, fd, track_key)
  delete_group_extmark(bufnr, fd.extmarks.node_slots, state.display_ns, node_slot_key(track_key))
  clear_group_prefix(bufnr, fd.extmarks.node_slots, state.display_ns, node_slot_prefix(track_key))
  clear_group_prefix(bufnr, fd.extmarks.conceal_spans, state.aux_ns, "conceal:" .. track_key .. ":")
  clear_group_prefix(bufnr, fd.extmarks.conceal_rows, state.aux_ns, "conceal-line:" .. track_key .. ":")
end

local function clear_all_artifacts(bufnr, fd)
  for key in pairs(vim.deepcopy(fd.extmarks.node_slots or {})) do
    delete_group_extmark(bufnr, fd.extmarks.node_slots, state.display_ns, key)
  end
  for key in pairs(vim.deepcopy(fd.extmarks.conceal_spans or {})) do
    delete_group_extmark(bufnr, fd.extmarks.conceal_spans, state.aux_ns, key)
  end
  for key in pairs(vim.deepcopy(fd.extmarks.conceal_rows or {})) do
    delete_group_extmark(bufnr, fd.extmarks.conceal_rows, state.aux_ns, key)
  end
end

local function image_cell_rows(bufnr, view)
  local asset = view.asset
  if asset == nil then
    return nil
  end
  local cols = math.max(1, math.floor(tonumber(asset.cols) or 1))
  local rows = math.max(1, math.floor(tonumber(asset.rows) or 1))
  local hl = state.image_hl_group(asset.image_id)
  local pad = view.object.inline and 0 or surface.block_left_pad_cols(bufnr, view, cols)
  local pad_text = pad > 0 and string.rep(" ", pad) or ""
  local out = {}
  for row = 1, rows do
    out[#out + 1] = { { pad_text .. surface.placeholder_row(row, cols), hl } }
  end
  return out
end

local function block_slot_position(plan)
  local start_fragment = plan.start_fragment
  local end_fragment = plan.end_fragment

  if plan.block_shape == "suffix" then
    return end_fragment and end_fragment.row or plan.view.end_row, true
  end

  if plan.block_shape == "prefix" then
    return start_fragment and start_fragment.row or plan.view.row, false
  end

  return nil, false
end

local function fragment_carries_node_slot(plan, fragment)
  if fragment == nil then
    return false
  end

  if plan.view.object.inline then
    return fragment == plan.start_fragment
  end

  if plan.block_shape == "isolated" then
    return false
  end

  local anchor_row = block_slot_position(plan)
  return anchor_row ~= nil and fragment.row == anchor_row
end

local function render_conceal_line(bufnr, plan, fragment, index, extmarks)
  local key = conceal_row_key(plan.view.key, index)
  extmarks.conceal_rows[key] = vim.api.nvim_buf_set_extmark(bufnr, state.aux_ns, fragment.row, 0, {
    id = extmarks.conceal_rows[key],
    conceal_lines = "",
    end_row = fragment.row,
    right_gravity = true,
    end_right_gravity = true,
    undo_restore = true,
    invalidate = true,
    priority = CONCEAL_PRIORITY,
  })
end

local function render_conceal_span(bufnr, plan, fragment, index, extmarks)
  if fragment.end_col <= fragment.col then
    return
  end
  local key = conceal_span_key(plan.view.key, index)
  extmarks.conceal_spans[key] = vim.api.nvim_buf_set_extmark(bufnr, state.aux_ns, fragment.row, fragment.col, {
    id = extmarks.conceal_spans[key],
    end_row = fragment.row,
    end_col = fragment.end_col,
    conceal = "",
    invalidate = true,
    priority = CONCEAL_PRIORITY,
  })
end

local function render_conceal_fragment(bufnr, plan, fragment, index, extmarks, layout_mode)
  if layout_mode == "compact" and fragment.fragment_only and not fragment_carries_node_slot(plan, fragment) then
    render_conceal_line(bufnr, plan, fragment, index, extmarks)
    return
  end

  render_conceal_span(bufnr, plan, fragment, index, extmarks)
end

local function render_conceal_fragments(bufnr, plan, extmarks, layout_mode)
  for index, fragment in ipairs(plan.fragments) do
    render_conceal_fragment(bufnr, plan, fragment, index, extmarks, layout_mode)
  end
end

local function source_prefix_display_width(bufnr, fragment)
  if fragment == nil or fragment.col <= 0 then
    return 0
  end
  local line = source_line(bufnr, fragment.row)
  return math.max(0, vim.fn.strdisplaywidth(line:sub(1, fragment.col)))
end

local function add_virt_lines_prefix(virt_lines, prefix_cols)
  prefix_cols = math.max(0, math.floor(tonumber(prefix_cols) or 0))
  if prefix_cols == 0 then
    return virt_lines
  end

  local prefix = string.rep(" ", prefix_cols)
  local out = {}
  for _, line in ipairs(virt_lines or {}) do
    local prefixed = { { prefix, "" } }
    for _, chunk in ipairs(line) do
      prefixed[#prefixed + 1] = chunk
    end
    out[#out + 1] = prefixed
  end
  return out
end

local function blank_virt_lines(count)
  local out = {}
  for _ = 1, math.max(0, math.floor(tonumber(count) or 0)) do
    out[#out + 1] = { { "", "" } }
  end
  return out
end

local function render_source_row_slot(bufnr, plan, extmarks, slot_opts)
  slot_opts = slot_opts or {}
  local fragment = plan.start_fragment
  local rows = image_cell_rows(bufnr, plan.view)
  if fragment == nil or rows == nil or rows[1] == nil then
    return
  end

  local extra_rows = {}
  for index = 2, #rows do
    extra_rows[#extra_rows + 1] = rows[index]
  end

  local key = node_slot_key(plan.view.key)
  local opts = {
    id = extmarks.node_slots[key],
    virt_text = rows[1],
    virt_text_pos = slot_opts.virt_text_pos or "inline",
    invalidate = true,
    priority = SLOT_PRIORITY,
  }
  if #extra_rows > 0 then
    opts.virt_lines = add_virt_lines_prefix(extra_rows, slot_opts.virt_lines_prefix_cols)
    opts.virt_lines_overflow = "trunc"
  end
  extmarks.node_slots[key] = vim.api.nvim_buf_set_extmark(bufnr, state.display_ns, fragment.row, fragment.col, opts)
end

local function render_inline_slot(bufnr, plan, extmarks)
  render_source_row_slot(bufnr, plan, extmarks, { virt_text_pos = "inline" })
end

-- Isolated block images live on a visible neighboring row, not on the
-- concealed source rows themselves.  The normal case uses the first row after
-- the block with virt_lines_above, which lets Neovim scroll within the virtual
-- image footprint through the window-local topfill field.
local function isolated_block_slot_position(bufnr, plan)
  local after_row = plan.view.end_row + 1
  if after_row < vim.api.nvim_buf_line_count(bufnr) then
    return after_row, true
  end

  local before_row = plan.view.row - 1
  if before_row >= 0 then
    return before_row, false
  end

  return nil, nil
end

local function render_isolated_block_slot(bufnr, plan, extmarks)
  local rows = image_cell_rows(bufnr, plan.view)
  if rows == nil or #rows == 0 then
    return
  end

  local anchor_row, virt_lines_above = isolated_block_slot_position(bufnr, plan)
  if anchor_row == nil then
    return
  end

  local key = node_slot_key(plan.view.key)
  extmarks.node_slots[key] = vim.api.nvim_buf_set_extmark(bufnr, state.display_ns, anchor_row, 0, {
    id = extmarks.node_slots[key],
    virt_lines = add_virt_lines_prefix(rows, source_prefix_display_width(bufnr, plan.start_fragment)),
    virt_lines_above = virt_lines_above,
    virt_lines_overflow = "trunc",
    invalidate = true,
    priority = SLOT_PRIORITY,
  })
end

local function render_block_slot(bufnr, plan, extmarks)
  if plan.block_shape == "isolated" then
    render_isolated_block_slot(bufnr, plan, extmarks)
    return
  end

  local rows = image_cell_rows(bufnr, plan.view)
  if rows == nil or #rows == 0 then
    return
  end

  local anchor_row, virt_lines_above = block_slot_position(plan)
  if anchor_row == nil then
    return
  end

  local key = node_slot_key(plan.view.key)
  extmarks.node_slots[key] = vim.api.nvim_buf_set_extmark(bufnr, state.display_ns, anchor_row, 0, {
    id = extmarks.node_slots[key],
    virt_lines = rows,
    virt_lines_above = virt_lines_above,
    virt_lines_overflow = "trunc",
    invalidate = true,
    priority = SLOT_PRIORITY,
  })
end

local function render_node_slot(bufnr, plan, extmarks)
  if plan.view.object.inline then
    render_inline_slot(bufnr, plan, extmarks)
  else
    render_block_slot(bufnr, plan, extmarks)
  end
end

local function render_node_projection(bufnr, plan, extmarks, layout_mode)
  render_conceal_fragments(bufnr, plan, extmarks, layout_mode)
  render_node_slot(bufnr, plan, extmarks)
end

local function capture_window_views(bufnr)
  local views = {}
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      local ok, view = pcall(vim.api.nvim_win_call, win, vim.fn.winsaveview)
      if ok and type(view) == "table" then
        views[win] = view
      end
    end
  end
  return views
end

local function restore_window_view(win, view)
  if not vim.api.nvim_win_is_valid(win) or type(view) ~= "table" then
    return
  end
  pcall(vim.api.nvim_win_call, win, function()
    vim.fn.winrestview(view)
  end)
end

local function image_row_count(plan)
  local asset = plan and plan.view and plan.view.asset or nil
  if asset == nil then
    return 0
  end
  return math.max(1, math.floor(tonumber(asset.rows) or 1))
end

local function fallback_source_row_count(plan)
  if plan == nil or plan.view == nil then
    return 0
  end
  return math.max(0, plan.view.end_row - plan.view.row + 1)
end

local function source_text_height_for_win(win, plan, max_height)
  if type(vim.api.nvim_win_text_height) ~= "function" then
    return nil
  end
  local ok, result = pcall(vim.api.nvim_win_text_height, win, {
    start_row = plan.view.row,
    start_vcol = 0,
    end_row = plan.view.end_row,
    max_height = math.max(1, max_height),
  })
  if not ok or type(result) ~= "table" then
    return nil
  end
  return tonumber(result.all)
end

local function source_text_height(bufnr, plan, max_height)
  local measured = nil
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      local height = source_text_height_for_win(win, plan, max_height)
      if height ~= nil then
        -- The reveal spacer is buffer-local for now, so use the smallest
        -- visible source height.  This yields the conservative
        -- R = max_w(0, I - S_w) spacer across all windows.
        measured = measured == nil and height or math.min(measured, height)
      end
    end
  end
  return measured or fallback_source_row_count(plan)
end

local function render_source_reveal_spacer(bufnr, plan, extmarks, layout_mode)
  -- TODO(image-display): Re-evaluate whether source-reveal footprint
  -- preservation is worth the extra blank area.  The current pure-extmark
  -- experiments show that removing the image footprint during source reveal
  -- only causes the expected local conceal/reveal reflow, while the serious
  -- viewport jump is addressed by the compact-in-wrap layout policy.  Keep the
  -- previous implementation commented here until we decide whether a
  -- configurable reveal-footprint policy is needed.
  return

  --[[
  if plan == nil or plan.block_shape ~= "isolated" or plan.view == nil then
    return
  end

  local image_rows = image_row_count(plan)
  if image_rows <= 0 then
    return
  end

  local spacer_rows
  if layout_mode == "noncompact" then
    -- Non-compact image state keeps source rows line-addressable and adds the
    -- image footprint above the post-block anchor.  Source reveal should hide
    -- image content, not delete that additional footprint.
    spacer_rows = image_rows
  else
    spacer_rows = image_rows - source_text_height(bufnr, plan, image_rows)
  end
  if spacer_rows <= 0 then
    return
  end

  local anchor_row, virt_lines_above = isolated_block_slot_position(bufnr, plan)
  if anchor_row == nil then
    return
  end

  local key = node_slot_key(plan.view.key)
  extmarks.node_slots[key] = vim.api.nvim_buf_set_extmark(bufnr, state.display_ns, anchor_row, 0, {
    id = extmarks.node_slots[key],
    virt_lines = blank_virt_lines(spacer_rows),
    virt_lines_above = virt_lines_above,
    virt_lines_overflow = "trunc",
    invalidate = true,
    priority = SLOT_PRIORITY,
  })
  --]]
end

-- When source reveal transitions back to image conceal while a window topline
-- was inside the soon-to-be-concealed source range, remap that logical source
-- offset to Neovim's native virt_lines_above/topfill scroll state.  This keeps
-- the image footprint scroll-continuous without drawing wrapped source rows.
local function remap_isolated_block_topfill(bufnr, plan, before_views)
  if plan == nil or plan.block_shape ~= "isolated" or plan.view == nil then
    return
  end

  local anchor_row, virt_lines_above = isolated_block_slot_position(bufnr, plan)
  if anchor_row == nil or virt_lines_above ~= true then
    return
  end

  local rows = image_row_count(plan)
  if rows <= 0 then
    return
  end

  local source_start = plan.view.row + 1
  local source_end = plan.view.end_row + 1
  local anchor_lnum = anchor_row + 1

  for win, view in pairs(before_views or {}) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      local old_topline = tonumber(view.topline) or 0
      if old_topline >= source_start and old_topline <= source_end then
        local offset = old_topline - source_start
        local topfill = math.max(0, rows - offset)
        local remapped = vim.deepcopy(view)
        remapped.topline = anchor_lnum
        remapped.topfill = topfill
        restore_window_view(win, remapped)
      end
    end
  end
end

local function remap_rendered_topfills(bufnr, rendered_plans, before_views)
  for _, node_plan in ipairs(rendered_plans or {}) do
    remap_isolated_block_topfill(bufnr, node_plan, before_views)
  end
end

local function render_track_keys(bufnr, fd, plan, keys)
  local before_views = capture_window_views(bufnr)
  local rendered_plans = {}
  local ordered_keys = sorted_keys(keys)

  for _, key in ipairs(ordered_keys) do
    clear_artifacts_for_track_key(bufnr, fd, key)
  end

  for _, key in ipairs(ordered_keys) do
    local node_plan = plan.plans_by_key[key]
    if node_plan ~= nil then
      if plan.suppressed_keys[key] then
        render_source_reveal_spacer(bufnr, node_plan, fd.extmarks, plan.layout_mode)
      else
        render_node_projection(bufnr, node_plan, fd.extmarks, plan.layout_mode)
        rendered_plans[#rendered_plans + 1] = node_plan
      end
    end
  end
  if plan.layout_mode == "compact" then
    remap_rendered_topfills(bufnr, rendered_plans, before_views)
  end
end

local function ensure_conceal_options(bufnr, config)
  for _, win in ipairs(visible_windows_for_buf(bufnr)) do
    vim.wo[win].conceallevel = math.max(tonumber(vim.wo[win].conceallevel) or 0, 2)
    vim.wo[win].concealcursor = "nci"
    if compact_in_wrap_enabled(config) and vim.wo[win].wrap then
      pcall(function()
        vim.wo[win].smoothscroll = true
      end)
    end
  end
end

local function repair_keys_for_event(event, plan)
  if event.force == true then
    return all_plan_keys(plan.node_plans)
  end

  local keys = repair_event.ref_set(event.checked_refs)
  merge_keys(keys, repair_event.ref_set(event.born_refs))
  merge_keys(keys, repair_event.ref_set(event.retired_refs))
  merge_keys(keys, repair_event.context_dependent_key_set(event))
  return keys
end

function M.on_tracker_repair(event, config)
  if event == nil or event.bufnr == nil or not vim.api.nvim_buf_is_valid(event.bufnr) then
    return
  end
  local bufnr = normalize_bufnr(event.bufnr)
  local fd = ensure_state(bufnr)
  ensure_conceal_options(bufnr, config or {})
  local plan = build_projection_plan(bufnr, event.tracks, config or {})

  if event.initial == true then
    clear_all_artifacts(bufnr, fd)
    render_track_keys(bufnr, fd, plan, all_plan_keys(plan.node_plans))
  else
    local keys = repair_keys_for_event(event, plan)
    if fd.layout_mode ~= nil and fd.layout_mode ~= plan.layout_mode then
      merge_keys(keys, all_plan_keys(plan.node_plans))
    end
    merge_keys(keys, fd.suppressed_track_keys)
    merge_keys(keys, plan.suppressed_keys)
    render_track_keys(bufnr, fd, plan, keys)
  end

  fd.suppressed_track_keys = plan.suppressed_keys
  fd.reconcile_key = plan.key
  fd.layout_mode = plan.layout_mode
end

function M.repair_tracks(bufnr, refs, config)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local fd = ensure_state(bufnr)
  ensure_conceal_options(bufnr, config or {})
  local plan = build_projection_plan(bufnr, nil, config or {})
  local keys = ref_key_set(refs)
  if fd.layout_mode ~= nil and fd.layout_mode ~= plan.layout_mode then
    merge_keys(keys, all_plan_keys(plan.node_plans))
  end
  merge_keys(keys, fd.suppressed_track_keys)
  merge_keys(keys, plan.suppressed_keys)
  render_track_keys(bufnr, fd, plan, keys)
  fd.suppressed_track_keys = plan.suppressed_keys
  fd.reconcile_key = plan.key
  fd.layout_mode = plan.layout_mode
end

function M.sync_cursor(bufnr, config)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local fd = ensure_state(bufnr)
  ensure_conceal_options(bufnr, config or {})
  local plan = build_projection_plan(bufnr, nil, config or {})
  if fd.reconcile_key == plan.key then
    return
  end

  local layout_changed = fd.layout_mode ~= nil and fd.layout_mode ~= plan.layout_mode
  local keys = {}
  if layout_changed then
    merge_keys(keys, all_plan_keys(plan.node_plans))
  end
  merge_keys(keys, fd.suppressed_track_keys)
  merge_keys(keys, plan.suppressed_keys)
  render_track_keys(bufnr, fd, plan, keys)
  fd.suppressed_track_keys = plan.suppressed_keys
  fd.reconcile_key = plan.key
  fd.layout_mode = plan.layout_mode
end

function M.refresh(bufnr, config)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local fd = ensure_state(bufnr)
  ensure_conceal_options(bufnr, config or {})
  local plan = build_projection_plan(bufnr, nil, config or {})
  clear_all_artifacts(bufnr, fd)
  render_track_keys(bufnr, fd, plan, all_plan_keys(plan.node_plans))
  fd.suppressed_track_keys = plan.suppressed_keys
  fd.reconcile_key = plan.key
  fd.layout_mode = plan.layout_mode
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
