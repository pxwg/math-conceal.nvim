local codes = require("math-conceal.image.kitty-codes")
local state = require("math-conceal.image.state")

local M = {}

local function capacity()
  return math.max(1, #codes.diacritics - 1)
end

function M.clamp(cols, rows)
  local cap = capacity()
  cols = math.max(1, math.min(cap, math.floor(tonumber(cols) or 1)))
  rows = math.max(1, math.min(cap, math.floor(tonumber(rows) or 1)))
  return cols, rows
end

function M.placeholder_row(row, cols)
  row = math.max(1, math.min(#codes.diacritics, row))
  local line = {}
  for col = 0, cols - 1 do
    line[#line + 1] = codes.placeholder .. codes.diacritics[row] .. codes.diacritics[col + 1]
  end
  return table.concat(line)
end

function M.natural_dimensions(display_kind, source_rows, width_px, height_px)
  width_px = math.max(1, tonumber(width_px) or 1)
  height_px = math.max(1, tonumber(height_px) or 1)
  source_rows = math.max(1, math.floor(tonumber(source_rows) or 1))

  local cell_w, cell_h = state.cell_size()
  local cols, rows
  if cell_w ~= nil and cell_h ~= nil then
    if display_kind ~= "block" and source_rows == 1 then
      local aspect = width_px / height_px
      cols = math.max(1, math.floor(cell_h * aspect / cell_w + 0.5))
      rows = 1
    else
      cols = math.max(1, math.floor(width_px / cell_w + 0.5))
      rows = math.max(1, math.floor(height_px / cell_h + 0.5))
    end
  elseif display_kind ~= "block" and source_rows == 1 then
    cols = math.max(1, math.floor((width_px / height_px) * 2))
    rows = 1
  else
    cols = math.ceil((width_px / height_px) * 2) * source_rows
    rows = source_rows
  end

  return M.clamp(cols, rows)
end

function M.preview_dimensions(width_px, height_px)
  width_px = math.max(1, tonumber(width_px) or 1)
  height_px = math.max(1, tonumber(height_px) or 1)
  local cell_w, cell_h = state.cell_size()
  local cols, rows

  if cell_w ~= nil and cell_h ~= nil then
    cols = math.max(1, math.floor(width_px / cell_w + 0.5))
    rows = math.max(1, math.floor(height_px / cell_h + 0.5))
  else
    cols = math.max(1, math.floor((width_px / height_px) * 2 + 0.5))
    rows = 1
  end

  return M.clamp(cols, rows)
end

return M
