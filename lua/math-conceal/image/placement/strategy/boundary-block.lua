local surface_api = require("math-conceal.image.placement.surface")

local M = {}

local function prefix_cols(surface, record)
  local style = record.request and record.request.placement_style or {}
  if style.horizontal_align == "center" and record.grid.cols < surface_api.text_width(surface) then
    return math.floor((surface_api.text_width(surface) - record.grid.cols) / 2)
  end
  return 0
end

function M.measure(surface, record, view)
  if surface == nil or record == nil or record.grid == nil or view == nil then
    return nil
  end
  local role = record.request and record.request.source_boundary_role or nil
  if role ~= "prefix" and role ~= "suffix" then
    return nil
  end
  local fragments = surface_api.source_fragments(surface, view, "block")
  if fragments[1] == nil then
    return nil
  end
  local anchor = role == "suffix" and fragments[#fragments] or fragments[1]
  return {
    role = role,
    fragments = fragments,
    anchor = anchor,
    prefix_cols = prefix_cols(surface, record),
    source_start_row = view.row,
    source_end_row = view.end_row,
  }
end

function M.signature(record, layout)
  if record == nil or layout == nil then
    return "invalid"
  end
  local parts = {
    "boundary-block",
    layout.role,
    tostring(record.image_id),
    tostring(record.realization_key or ""),
    tostring(record.grid.cols),
    tostring(record.grid.rows),
    tostring(layout.prefix_cols),
  }
  for _, fragment in ipairs(layout.fragments) do
    parts[#parts + 1] = table.concat({ fragment.row, fragment.col, fragment.end_col }, ":")
  end
  return table.concat(parts, "|")
end

function M.apply(surface, record, _view, layout)
  if not surface_api.ensure_terminal(record) then
    return false
  end
  surface_api.clear_artifacts(surface, record)
  local ids = {}
  for _, fragment in ipairs(layout.fragments) do
    surface_api.conceal_fragment(surface, fragment, fragment.row == layout.anchor.row, ids)
  end

  local lines = {}
  for image_row = 1, record.grid.rows do
    lines[#lines + 1] = surface_api.placeholder_line(record, image_row, layout.prefix_cols)
  end
  ids[#ids + 1] = surface_api.add_extmark(surface, layout.anchor.row, 0, {
    virt_lines = lines,
    virt_lines_above = layout.role == "suffix",
    virt_lines_overflow = "trunc",
    invalidate = true,
    priority = surface_api.SLOT_PRIORITY,
  })

  record.extmark_ids = ids
  record.source_start_row = layout.source_start_row
  record.source_end_row = layout.source_end_row
  record.placed = true
  record.signature = M.signature(record, layout)
  surface_api.redraw(surface, layout.source_start_row, layout.source_end_row)
  return true
end

return M
