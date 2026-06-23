local flow_classification = require("math-conceal.image.flow-classification")
local placement = require("math-conceal.image.placement.snacks")
local repair_event = require("math-conceal.image.repair-event")
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

local function is_blank(text)
  return (text or ""):match("^%s*$") ~= nil
end

local function ensure_state(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local fd = state_by_buf[bufnr]
  if fd == nil then
    fd = {
      suppressed_track_keys = {},
      reconcile_key = nil,
    }
    state_by_buf[bufnr] = fd
  end
  fd.suppressed_track_keys = fd.suppressed_track_keys or {}
  return fd
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

local function display_asset_entry(bufnr, key)
  local bs = state.get_buf_state(bufnr)
  return bs.display_assets and bs.display_assets[key] or nil
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

  local entry = display_asset_entry(bufnr, key)
  view.display_source_reveal = entry ~= nil and entry.source_reveal == true
  if view.object and view.object.renderable == false then
    view.asset = nil
  elseif entry ~= nil and entry.source_reveal ~= true then
    view.asset = entry.asset
  else
    view.asset = nil
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
    return (a.track_id or 0) < (b.track_id or 0)
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
  fragments[#fragments + 1] = {
    row = row,
    col = col,
    end_col = math.max(col, end_col),
    empty_row = len == 0 and col == 0 and end_col == 0,
  }
end

local function node_boundary_context(bufnr, view)
  local start_line = source_line(bufnr, view.row)
  local end_line = view.row == view.end_row and start_line or source_line(bufnr, view.end_row)
  local suffix = end_line:sub(view.end_col + 1)
  local absorbed_end_col = view.end_col

  if view.object.inline == true and view.row ~= view.end_row then
    local blanks = suffix:match("^[ \t]*") or ""
    absorbed_end_col = view.end_col + #blanks
  end

  return {
    start_line = start_line,
    end_line = end_line,
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
  return {
    view = view,
    fragments = fragments,
    start_fragment = fragments[1],
    end_fragment = fragments[#fragments],
    source_reveal = view.asset == nil
      or view.display_source_reveal == true
      or (view.object and view.object.renderable == false),
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

local function block_math_delimiter_only_row(plan, row)
  local view = plan and plan.view or nil
  local object = view and view.object or nil
  if
    view == nil
    or object == nil
    or object.kind ~= "math"
    or object.inline == true
    or view.row == view.end_row
    or (row ~= view.row and row ~= view.end_row)
  then
    return false
  end

  local line = source_line(view.bufnr, row)
  local start_col = row == view.row and view.col or 0
  local end_col = row == view.end_row and view.end_col or #line
  local fragment = line:sub(start_col + 1, end_col)
  return fragment:match("^%s*%$%s*$") ~= nil
end

local function cursor_collides_with_plan(row, col, plan, mode)
  if row == nil then
    return false
  end
  if mode == "n" and block_math_delimiter_only_row(plan, row) then
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
    if cursor_collides_with_plan(row, col, plan, mode) then
      add_key(keys, plan.view.key)
    end
  end
  return keys, table.concat({ mode, tostring(row), tostring(col) }, ":")
end

local function build_projection_plan(bufnr, snapshots, config)
  local views = resolve_views(bufnr, snapshots)
  local node_plans, plans_by_key = build_node_plans(bufnr, views)
  local permanent_reveal_keys = source_reveal_keys(node_plans)
  local transient_reveal_keys, collision_key = collision_keys(bufnr, node_plans, config or {})
  local suppressed_keys = {}
  merge_keys(suppressed_keys, permanent_reveal_keys)
  merge_keys(suppressed_keys, transient_reveal_keys)
  return {
    views = views,
    node_plans = node_plans,
    plans_by_key = plans_by_key,
    permanent_reveal_keys = permanent_reveal_keys,
    transient_reveal_keys = transient_reveal_keys,
    suppressed_keys = suppressed_keys,
    key = collision_key .. "|" .. key_set_key(suppressed_keys),
  }
end

local function ensure_conceal_options(bufnr)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].conceallevel = math.max(tonumber(vim.wo[win].conceallevel) or 0, 2)
      vim.wo[win].concealcursor = ""
    end
  end
end

local function placement_constraints(bufnr, plan, config)
  local max_width = state.visible_text_width(bufnr)
  local max_height = math.max(1, vim.o.lines - vim.o.cmdheight)
  local object = plan.view.object or {}
  if object.kind == "code" and object.inline ~= true then
    local code_block = (((config or {}).renderers or {}).typst or {}).code_block or {}
    local right_pad = math.max(0, tonumber(code_block.right_padding_cols) or 1)
    local pad = math.max(0, tonumber(code_block.padding_cols) or 0)
    max_width = math.max(1, max_width - right_pad - 2 * pad)
  end
  return max_width, max_height
end

local function fit_cells(cols, rows, max_width, max_height)
  cols = math.max(1, math.floor(tonumber(cols) or 1))
  rows = math.max(1, math.floor(tonumber(rows) or 1))
  max_width = math.max(1, math.floor(tonumber(max_width) or cols))
  max_height = math.max(1, math.floor(tonumber(max_height) or rows))
  if cols <= max_width and rows <= max_height then
    return cols, rows
  end
  local scale = math.min(max_width / cols, max_height / rows)
  return math.max(1, math.floor(cols * scale + 0.5)), math.max(1, math.floor(rows * scale + 0.5))
end

local function intent_dimensions(view, max_width, max_height)
  local asset = view.asset or {}
  local width_px = math.max(1, tonumber(asset.width_px) or 1)
  local height_px = math.max(1, tonumber(asset.height_px) or 1)
  local cell_w, cell_h = state.cell_size()
  local object = view.object or {}

  if object.inline == true then
    local cols
    if cell_w ~= nil and cell_h ~= nil then
      cols = math.floor((width_px / height_px) * (cell_h / cell_w) + 0.5)
    else
      cols = math.floor((width_px / height_px) * 2 + 0.5)
    end
    cols = math.max(1, math.min(max_width, cols))
    -- Snacks reserves two extra cells for single-row inline image placements.
    -- Request the image payload width minus that reserve so the final inline
    -- footprint is closer to the renderer-derived terminal-cell width.
    return math.max(1, cols - 2), 1
  end

  local cols, rows
  if cell_w ~= nil and cell_h ~= nil then
    cols = math.floor(width_px / cell_w + 0.5)
    rows = math.floor(height_px / cell_h + 0.5)
  else
    cols = math.floor((width_px / height_px) * 2 + 0.5)
    rows = math.max(1, view.end_row - view.row + 1)
  end
  return fit_cells(cols, rows, max_width, max_height)
end

local function show_intent(bufnr, plan, config)
  local view = plan.view
  local max_width, max_height = placement_constraints(bufnr, plan, config)
  local width, height = intent_dimensions(view, max_width, max_height)
  local object = view.object or {}
  local source_range = { view.row + 1, view.col, view.end_row + 1, view.end_col }
  local placement_col = view.col
  local placement_range = nil
  local collapse_source_lines = false
  local preserve_size = false
  if object.kind == "math" and object.inline ~= true then
    placement_col = math.max(0, math.floor((state.visible_text_width(bufnr) - width) / 2))
    -- Keep the Snacks placement range on a short anchor line. Snacks refuses
    -- overlay placement when a ranged source line is wider than the wrapped
    -- window, and then falls back to unpadded virtual lines. The backend keeps
    -- the real source range concealed separately while Snacks owns the image.
    placement_range = { view.row + 1, placement_col, view.row + 1, placement_col }
    collapse_source_lines = true
    preserve_size = true
  end
  return {
    key = view.key,
    action = "show",
    asset = view.asset,
    ref = view.ref,
    pos = { view.row + 1, placement_col },
    range = source_range,
    placement_range = placement_range,
    collapse_source_lines = collapse_source_lines,
    preserve_size = preserve_size,
    width = width,
    height = height,
    max_width = max_width,
    max_height = max_height,
    type = object.kind == "math" and "math" or "image",
    auto_resize = true,
  }
end

local function intent_for_key(bufnr, plan, key, config)
  local node_plan = plan.plans_by_key[key]
  if node_plan == nil then
    return { key = key, action = "close" }
  end
  if plan.permanent_reveal_keys[key] then
    return { key = key, action = "close" }
  end
  if plan.transient_reveal_keys[key] then
    return { key = key, action = "hide" }
  end
  if node_plan.view.asset ~= nil then
    return show_intent(bufnr, node_plan, config)
  end
  return { key = key, action = "close" }
end

local function sync_track_keys(bufnr, fd, plan, keys, config, opts)
  local intents = {}
  for _, key in ipairs(sorted_keys(keys)) do
    intents[#intents + 1] = intent_for_key(bufnr, plan, key, config)
  end
  placement.sync(bufnr, intents, opts)
  fd.suppressed_track_keys = plan.suppressed_keys
  fd.reconcile_key = plan.key
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
  ensure_conceal_options(bufnr)
  local plan = build_projection_plan(bufnr, event.tracks, config or {})

  if event.initial == true then
    sync_track_keys(bufnr, fd, plan, all_plan_keys(plan.node_plans), config or {}, { replace_all = true })
  else
    local keys = repair_keys_for_event(event, plan)
    merge_keys(keys, fd.suppressed_track_keys)
    merge_keys(keys, plan.suppressed_keys)
    sync_track_keys(bufnr, fd, plan, keys, config or {})
  end
end

function M.repair_tracks(bufnr, refs, config)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local fd = ensure_state(bufnr)
  ensure_conceal_options(bufnr)
  local plan = build_projection_plan(bufnr, nil, config or {})
  local keys = ref_key_set(refs)
  merge_keys(keys, fd.suppressed_track_keys)
  merge_keys(keys, plan.suppressed_keys)
  sync_track_keys(bufnr, fd, plan, keys, config or {})
end

function M.sync_cursor(bufnr, config)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local fd = ensure_state(bufnr)
  ensure_conceal_options(bufnr)
  local plan = build_projection_plan(bufnr, nil, config or {})
  if fd.reconcile_key == plan.key then
    return
  end

  local keys = {}
  merge_keys(keys, fd.suppressed_track_keys)
  merge_keys(keys, plan.suppressed_keys)
  sync_track_keys(bufnr, fd, plan, keys, config or {})
end

function M.refresh(bufnr, config)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local fd = ensure_state(bufnr)
  ensure_conceal_options(bufnr)
  local plan = build_projection_plan(bufnr, nil, config or {})
  sync_track_keys(bufnr, fd, plan, all_plan_keys(plan.node_plans), config or {}, { replace_all = true })
end

function M.detach(bufnr)
  bufnr = normalize_bufnr(bufnr)
  placement.detach(bufnr)
  state_by_buf[bufnr] = nil
end

function M._build_projection_plan(bufnr, snapshots, config)
  return build_projection_plan(normalize_bufnr(bufnr), snapshots, config or {})
end

return M
