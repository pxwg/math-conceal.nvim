local surface_api = require("math-conceal.image.placement.surface")

local M = {}

function M.measure(surface, record, view)
  if surface == nil or record == nil or record.grid == nil or view == nil then
    return nil
  end
  local fragments = surface_api.source_fragments(surface, view, "inline")
  if fragments[1] == nil then
    return nil
  end
  return {
    fragments = fragments,
    anchor = fragments[1],
    source_start_row = view.row,
    source_end_row = view.end_row,
  }
end

function M.signature(record, layout)
  if record == nil or layout == nil then
    return "invalid"
  end
  local parts = {
    "inline",
    tostring(record.image_id),
    tostring(record.realization_key or ""),
    tostring(record.grid.cols),
    tostring(record.grid.rows),
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
  for index, fragment in ipairs(layout.fragments) do
    surface_api.conceal_fragment(surface, fragment, index == 1, ids)
  end

  local extra_rows = {}
  for image_row = 2, record.grid.rows do
    extra_rows[#extra_rows + 1] = surface_api.placeholder_line(record, image_row, 0)
  end
  local opts = {
    virt_text = surface_api.placeholder_line(record, 1, 0),
    virt_text_pos = "inline",
    invalidate = true,
    priority = surface_api.SLOT_PRIORITY,
  }
  if #extra_rows > 0 then
    opts.virt_lines = extra_rows
    opts.virt_lines_overflow = "trunc"
  end
  ids[#ids + 1] = surface_api.add_extmark(surface, layout.anchor.row, layout.anchor.col, opts)

  record.extmark_ids = ids
  record.source_start_row = layout.source_start_row
  record.source_end_row = layout.source_end_row
  record.placed = true
  record.signature = M.signature(record, layout)
  surface_api.redraw(surface, layout.source_start_row, layout.source_end_row)
  return true
end

return M
