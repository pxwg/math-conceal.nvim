local M = {}

local function is_insert_like_mode(mode)
  mode = mode or vim.api.nvim_get_mode().mode or ""
  return mode:find("i", 1, true) ~= nil or mode:find("R", 1, true) ~= nil
end

local function cursor_in_range(track, row, col, opts)
  opts = opts or {}
  if track == nil then
    return false
  end

  local sr, sc, er, ec = track.row, track.col, track.end_row, track.end_col
  if row < sr or row > er then
    return false
  end

  local include_right_edge = opts.include_right_edge == true
  if sr == er then
    if include_right_edge then
      return col >= sc and col <= ec
    end
    return col >= sc and col < ec
  end
  if row == sr then
    return col >= sc
  end
  if row == er then
    if include_right_edge then
      return col <= ec
    end
    return col < ec
  end
  return true
end

local function track_contains_range(track, start_row, start_col, end_row, end_col)
  if track == nil then
    return false
  end
  local start_ok = start_row > track.row or (start_row == track.row and start_col >= track.col)
  local end_ok = end_row < track.end_row or (end_row == track.end_row and end_col <= track.end_col)
  return start_ok and end_ok and (start_row < end_row or start_col <= end_col)
end

local function track_relative_col(track, row, col)
  if row == track.row then
    return col - track.col
  end
  return col
end

local function track_source_slice(track, start_row, start_col, end_row, end_col)
  local source = track and track.source or ""
  if source == "" or not track_contains_range(track, start_row, start_col, end_row, end_col) then
    return nil
  end

  local lines = vim.split(source, "\n", { plain = true })
  local start_idx = start_row - track.row + 1
  local end_idx = end_row - track.row + 1
  if start_idx < 1 or end_idx > #lines or start_idx > end_idx then
    return nil
  end

  local rel_start_col = math.max(0, track_relative_col(track, start_row, start_col))
  local rel_end_col = math.max(0, track_relative_col(track, end_row, end_col))
  if start_idx == end_idx then
    local line = lines[start_idx] or ""
    rel_start_col = math.min(rel_start_col, #line)
    rel_end_col = math.max(rel_start_col, math.min(rel_end_col, #line))
    return line:sub(rel_start_col + 1, rel_end_col)
  end

  local out = {}
  local first = lines[start_idx] or ""
  local last = lines[end_idx] or ""
  out[#out + 1] = first:sub(math.min(rel_start_col, #first) + 1)
  for idx = start_idx + 1, end_idx - 1 do
    out[#out + 1] = lines[idx] or ""
  end
  out[#out + 1] = last:sub(1, math.min(rel_end_col, #last))
  return table.concat(out, "\n")
end

local function get_math_symbol_span_at_pos(track, row, col)
  if not cursor_in_range(track, row, col, { include_right_edge = false }) then
    return nil
  end

  local ok_parser, parser = pcall(vim.treesitter.get_parser, track.bufnr, "typst")
  if not ok_parser or parser == nil then
    return nil
  end

  local trees = parser:parse()
  local tree = trees and trees[1] or nil
  if tree == nil then
    return nil
  end

  local root = tree:root()
  local node = root:named_descendant_for_range(row, col, row, col + 1)
  if node == nil then
    return nil
  end

  local formula_node = nil
  local target = node
  while target ~= nil do
    if target:type() == "formula" then
      formula_node = target
      break
    end
    target = target:parent()
  end
  if formula_node == nil then
    return nil
  end

  target = node
  while target ~= nil do
    local parent = target:parent()
    if parent == nil then
      return nil
    end
    if parent:id() == formula_node:id() then
      break
    end
    target = parent
  end

  local sr, sc, er, ec = target:range()
  if not cursor_in_range(track, sr, sc, { include_right_edge = false }) then
    return nil
  end
  if er < sr or (er == sr and ec < sc) then
    return nil
  end

  local text = track_source_slice(track, sr, sc, er, ec)
  if text == nil or text == "" or text:match("^%s+$") then
    return nil
  end

  return {
    start_row = sr,
    start_col = sc,
    end_row = er,
    end_col = ec,
  }
end

local function get_math_symbol_span_at_cursor(track, row, col, mode)
  if track == nil or track.node_type ~= "math" then
    return nil
  end

  local candidates = {}
  if cursor_in_range(track, row, col, { include_right_edge = false }) then
    candidates[#candidates + 1] = col
  end
  if is_insert_like_mode(mode) and col > 0 then
    local left_col = col - 1
    if cursor_in_range(track, row, left_col, { include_right_edge = false }) then
      candidates[#candidates + 1] = left_col
    end
  end

  for _, candidate_col in ipairs(candidates) do
    local span = get_math_symbol_span_at_pos(track, row, candidate_col)
    if span ~= nil then
      return span
    end
  end
  return nil
end

function M.transform_source(track, cursor_row, cursor_col, mode)
  if track == nil or track.node_type ~= "math" then
    return nil, nil, nil
  end

  local source_text = track.source or ""
  if source_text == "" then
    return nil, nil, nil
  end

  local span = get_math_symbol_span_at_cursor(track, cursor_row, cursor_col, mode)
  if span == nil then
    return source_text, source_text, nil
  end

  if not cursor_in_range(track, span.start_row, span.start_col, { include_right_edge = false }) then
    return source_text, source_text, nil
  end

  local prefix = track_source_slice(track, track.row, track.col, span.start_row, span.start_col)
  local highlighted = track_source_slice(track, span.start_row, span.start_col, span.end_row, span.end_col)
  local suffix = track_source_slice(track, span.end_row, span.end_col, track.end_row, track.end_col)
  if prefix == nil or highlighted == nil or suffix == nil then
    return source_text, source_text, nil
  end

  local replacement = "#text(red)[$" .. highlighted .. "$];"
  return prefix .. replacement .. suffix, source_text, span
end

return M
