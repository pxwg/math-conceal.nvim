local M = {}

local function source_cols_for_row(view, row)
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

local function ranges_overlap(a_start, a_end, b_start, b_end)
  return a_start < b_end and b_start < a_end
end

local function cursor_collides(cursor, view)
  if cursor == nil then
    return false
  end
  local start_col, end_col = source_cols_for_row(view, cursor.row)
  return start_col ~= nil and cursor.col >= start_col and cursor.col < end_col
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

local function selection_collides(selection, view)
  if selection == nil or view == nil then
    return false
  end
  local start_row = math.max(selection.start_row, view.row)
  local end_row = math.min(selection.end_row, view.end_row)
  if start_row > end_row then
    return false
  end
  for row = start_row, end_row do
    local selection_start, selection_end = selection_cols_for_row(selection, row)
    local source_start, source_end = source_cols_for_row(view, row)
    if
      selection_start ~= nil
      and source_start ~= nil
      and ranges_overlap(selection_start, selection_end, source_start, source_end)
    then
      return true
    end
  end
  return false
end

local function views_overlap(left, right)
  if left == nil or right == nil then
    return false
  end
  local start_row = math.max(left.row, right.row)
  local end_row = math.min(left.end_row, right.end_row)
  if start_row > end_row then
    return false
  end
  for row = start_row, end_row do
    local left_start, left_end = source_cols_for_row(left, row)
    local right_start, right_end = source_cols_for_row(right, row)
    if left_start ~= nil and right_start ~= nil and ranges_overlap(left_start, left_end, right_start, right_end) then
      return true
    end
  end
  return false
end

local function direct_parent_child(left_key, left, right_key, right)
  return (left.cursor_nested == true and left.parent_key == right_key)
    or (right.cursor_nested == true and right.parent_key == left_key)
end

local function intrinsically_source(records, views, opts, key)
  local record = records and records[key] or nil
  local request = record and record.request or nil
  local view = views and views[key] or nil
  if
    request == nil
    or request.state ~= "ready"
    or view == nil
    or (request.display_kind == "block" and request.source_boundary_role == "sandwich")
  then
    return true
  end
  if selection_collides(opts.selection, view) then
    return true
  end
  if opts.conceal_in_normal ~= true or opts.mode ~= "n" then
    if cursor_collides(opts.cursor, view) then
      return true
    end
  end
  for other_key, other in pairs(views or {}) do
    if other_key ~= key and views_overlap(view, other) and not direct_parent_child(key, view, other_key, other) then
      return true
    end
  end
  return false
end

function M.resolve(records, views, opts)
  opts = opts or {}
  local source = {}
  local keys = vim.tbl_keys(records or {})
  table.sort(keys)

  for _, key in ipairs(keys) do
    local record = records[key]
    local request = record and record.request or nil
    local view = views and views[key] or nil
    if
      request == nil
      or request.state ~= "ready"
      or view == nil
      or (request.display_kind == "block" and request.source_boundary_role == "sandwich")
    then
      source[key] = true
    elseif selection_collides(opts.selection, view) then
      source[key] = true
    elseif opts.conceal_in_normal ~= true or opts.mode ~= "n" then
      if cursor_collides(opts.cursor, view) then
        source[key] = true
      end
    end
  end

  for left_index = 1, #keys do
    local left_key = keys[left_index]
    local left = views and views[left_key] or nil
    for right_index = left_index + 1, #keys do
      local right_key = keys[right_index]
      local right = views and views[right_key] or nil
      if views_overlap(left, right) and not direct_parent_child(left_key, left, right_key, right) then
        source[left_key] = true
        source[right_key] = true
      end
    end
  end

  local changed = true
  while changed do
    changed = false
    for _, key in ipairs(keys) do
      local view = views and views[key] or nil
      if view ~= nil and view.cursor_nested == true and source[view.parent_key] ~= true and source[key] ~= true then
        source[key] = true
        changed = true
      end
    end
  end

  return source
end

-- Realization completion changes readiness, but not TrackView geometry or
-- cursor/selection facts. Recompute that record and propagate only through its
-- cursor-nested descendants; unrelated records retain the last full result.
function M.resolve_incremental(records, views, opts, changed_keys)
  opts = opts or {}
  local source = {}
  local children = {}
  for key, view in pairs(views or {}) do
    if view ~= nil and view.cursor_nested == true and view.parent_key ~= nil then
      children[view.parent_key] = children[view.parent_key] or {}
      children[view.parent_key][#children[view.parent_key] + 1] = key
    end
  end

  local queue, queued = {}, {}
  local function enqueue(key)
    if key ~= nil and records[key] ~= nil and queued[key] ~= true then
      queued[key] = true
      queue[#queue + 1] = key
    end
  end
  for key in pairs(changed_keys or {}) do
    enqueue(key)
  end

  local index = 1
  while index <= #queue do
    local key = queue[index]
    index = index + 1
    queued[key] = nil
    local record = records[key]
    local view = views and views[key] or nil
    local desired = intrinsically_source(records, views, opts, key)
    if desired ~= true and view ~= nil and view.cursor_nested == true then
      local parent_source = source[view.parent_key]
      if parent_source == nil then
        local parent = records[view.parent_key]
        parent_source = parent == nil or parent.source_visible == true
      end
      if parent_source ~= true then
        desired = true
      end
    end
    source[key] = desired
    if record.source_visible ~= desired then
      for _, child_key in ipairs(children[key] or {}) do
        enqueue(child_key)
      end
    end
  end
  return source
end

return M
