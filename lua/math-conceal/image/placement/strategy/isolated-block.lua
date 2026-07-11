local surface_api = require("math-conceal.image.placement.surface")
local track_view = require("math-conceal.image.track-view")

local M = {}

local function choose_carrier_count(raw_heights, image_rows)
  image_rows = math.max(1, math.floor(tonumber(image_rows) or 1))
  local carrier_count = 0
  local carrier_height = 0
  for _, raw in ipairs(raw_heights or {}) do
    raw = math.max(1, math.floor(tonumber(raw) or 1))
    if carrier_count == 0 then
      carrier_count = 1
      carrier_height = raw
      if carrier_height >= image_rows then
        break
      end
    elseif carrier_height + raw <= image_rows then
      carrier_count = carrier_count + 1
      carrier_height = carrier_height + raw
    else
      break
    end
  end
  return carrier_count, carrier_height, math.max(0, image_rows - carrier_height)
end

local function placement_prefix(surface, record, view)
  local source_prefix = surface_api.source_prefix_width(surface, view.row, view.col)
  local style = record.request and record.request.placement_style or {}
  if style.horizontal_align == "center" and record.grid.cols < surface_api.text_width(surface) then
    return math.floor((surface_api.text_width(surface) - record.grid.cols) / 2), source_prefix
  end
  return source_prefix, source_prefix
end

function M.prepare_measure(surface, record, view)
  surface_api.clear_artifacts(surface, record)
  surface_api.clear_range(surface, view)
end

function M.measure(surface, record, view)
  if surface == nil or record == nil or record.grid == nil or view == nil then
    return nil
  end
  local measured = track_view.measure_source_layout(view, surface.win, { require_valid = true })
  if measured == nil then
    return nil
  end
  local raw_heights = {}
  for _, row_layout in ipairs(measured.rows or {}) do
    raw_heights[#raw_heights + 1] = row_layout.screen_height
  end
  local carrier_count, carrier_height, tail_count = choose_carrier_count(raw_heights, record.grid.rows)
  if carrier_count == 0 then
    return nil
  end

  local carrier_rows = {}
  for index = 1, carrier_count do
    local row_layout = measured.rows[index]
    carrier_rows[#carrier_rows + 1] = {
      row = row_layout.row,
      raw_height = raw_heights[index],
      segments = row_layout.segments or {},
    }
  end
  local prefix_cols, source_prefix_cols = placement_prefix(surface, record, view)
  return {
    source_start_row = view.row,
    source_end_row = view.end_row,
    prefix_cols = prefix_cols,
    source_prefix_cols = source_prefix_cols,
    carrier_rows = carrier_rows,
    carrier_height = carrier_height,
    tail_count = tail_count,
    collapsed_start_row = view.row + carrier_count,
  }
end

function M.signature(record, layout)
  if record == nil or layout == nil then
    return "invalid"
  end
  local parts = {
    "isolated-block",
    tostring(record.image_id),
    tostring(record.realization_key or ""),
    tostring(record.grid.cols),
    tostring(record.grid.rows),
    tostring(layout.source_start_row),
    tostring(layout.source_end_row),
    tostring(layout.prefix_cols),
    tostring(layout.carrier_height),
    tostring(layout.tail_count),
  }
  for _, carrier in ipairs(layout.carrier_rows) do
    parts[#parts + 1] = tostring(carrier.row) .. "@" .. tostring(carrier.raw_height)
    for _, segment in ipairs(carrier.segments) do
      parts[#parts + 1] = table.concat({
        tostring(segment.start_vcol or 0),
        tostring(segment.end_vcol or 0),
        tostring(segment.byte_col or 0),
      }, ",")
    end
  end
  return table.concat(parts, "|")
end

local function conceal_carrier(surface, view, row, ids)
  local start_col, end_col = surface_api.source_cols(view, row)
  if start_col == nil then
    return
  end
  if end_col == math.huge then
    end_col = surface_api.line_len(surface, row)
  end
  ids[#ids + 1] = surface_api.add_extmark(surface, row, start_col, {
    end_row = row,
    end_col = math.max(start_col, end_col),
    conceal = "",
    invalidate = true,
    priority = surface_api.CONCEAL_PRIORITY,
    strict = false,
  })
end

function M.apply(surface, record, view, layout)
  if not surface_api.ensure_terminal(record) then
    return false
  end
  surface_api.clear_artifacts(surface, record)
  surface_api.clear_range(surface, view)
  local ids = {}
  for _, carrier in ipairs(layout.carrier_rows) do
    conceal_carrier(surface, view, carrier.row, ids)
  end
  if layout.collapsed_start_row <= layout.source_end_row then
    ids[#ids + 1] = surface_api.add_extmark(surface, layout.collapsed_start_row, 0, {
      end_row = layout.source_end_row,
      conceal_lines = "",
      invalidate = true,
      priority = surface_api.CONCEAL_PRIORITY,
    })
  end

  local image_row = 1
  for _, carrier in ipairs(layout.carrier_rows) do
    for index = 1, carrier.raw_height do
      if image_row <= record.grid.rows then
        local segment = carrier.segments[index] or {}
        ids[#ids + 1] = surface_api.add_extmark(surface, carrier.row, segment.byte_col or 0, {
          virt_text = surface_api.placeholder_line(record, image_row, 0),
          virt_text_pos = "overlay",
          virt_text_win_col = layout.prefix_cols,
          virt_text_hide = false,
          invalidate = true,
          priority = surface_api.SLOT_PRIORITY,
          strict = false,
        })
      end
      image_row = image_row + 1
    end
  end

  if layout.tail_count > 0 then
    local last = layout.carrier_rows[#layout.carrier_rows]
    local lines = {}
    for row = layout.carrier_height + 1, record.grid.rows do
      lines[#lines + 1] = surface_api.placeholder_line(record, row, layout.prefix_cols)
    end
    if last ~= nil and #lines > 0 then
      ids[#ids + 1] = surface_api.add_extmark(surface, last.row, 0, {
        virt_lines = lines,
        virt_lines_overflow = "trunc",
        invalidate = true,
        priority = surface_api.SLOT_PRIORITY,
      })
    end
  end

  record.extmark_ids = ids
  record.source_start_row = layout.source_start_row
  record.source_end_row = layout.source_end_row
  record.carrier_rows = layout.carrier_rows
  record.carrier_height = layout.carrier_height
  record.tail_count = layout.tail_count
  record.prefix_cols = layout.prefix_cols
  record.source_prefix_cols = layout.source_prefix_cols
  record.placed = true
  record.signature = M.signature(record, layout)
  surface_api.redraw(surface, layout.source_start_row, layout.source_end_row)
  return true
end

function M._choose_carrier_count(raw_heights, image_rows)
  return choose_carrier_count(raw_heights, image_rows)
end

return M
