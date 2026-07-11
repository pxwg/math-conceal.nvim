---Late-binding helpers for reading current tracker snapshots from TrackRef-backed projections.
---Projection state stores identity; this module asks tracker for the live TrackView when position matters.
local tracker = require("math-conceal.image.tracker")

local M = {}

local function valid_buf(bufnr)
  return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_win(winid)
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

local function line_count(bufnr)
  if not valid_buf(bufnr) then
    return 0
  end
  return vim.api.nvim_buf_line_count(bufnr)
end

local function byte_col_for_vcol(winid, row, start_vcol)
  if start_vcol <= 0 then
    return 0
  end
  local col = vim.fn.virtcol2col(winid, row + 1, start_vcol + 1)
  if type(col) ~= "number" or col < 1 then
    error("math-conceal could not map a measured virtual column to source", 3)
  end
  return col - 1
end

local function text_height(winid, opts)
  if type(vim.api.nvim_win_text_height) ~= "function" then
    error("math-conceal image placement requires nvim_win_text_height", 3)
  end
  local result = vim.api.nvim_win_text_height(winid, opts)
  if type(result) ~= "table" then
    error("nvim_win_text_height returned an invalid result", 3)
  end
  return result
end

local function integer_field(result, field, minimum)
  local value = result[field]
  if type(value) ~= "number" or value ~= math.floor(value) or value < minimum then
    error(string.format("nvim_win_text_height returned an invalid %s", field), 3)
  end
  return value
end

local function next_wrap_boundary(winid, row, start_vcol, final_vcol)
  local result = text_height(winid, {
    start_row = row,
    end_row = row,
    start_vcol = start_vcol,
    max_height = 1,
  })
  local boundary = integer_field(result, "end_vcol", 0)
  if boundary > final_vcol or (boundary <= start_vcol and final_vcol > start_vcol) then
    error("nvim_win_text_height returned a non-progressing wrap boundary", 3)
  end
  return boundary
end

local function oracle_row_layout(winid, row)
  local result = text_height(winid, {
    start_row = row,
    end_row = row,
    start_vcol = 0,
  })
  local screen_height = integer_field(result, "all", 1)
  local fill = integer_field(result, "fill", 0)
  local final_vcol = integer_field(result, "end_vcol", 0)
  if integer_field(result, "end_row", 0) ~= row then
    error("nvim_win_text_height measured outside the requested source row", 3)
  end
  if fill ~= 0 then
    error("math-conceal image placement cannot map fill rows to source columns", 3)
  end

  local segments = {}

  if not vim.wo[winid].wrap then
    if screen_height ~= 1 then
      error("nvim_win_text_height returned multiple source rows with wrap disabled", 3)
    end
    segments[#segments + 1] = {
      start_vcol = 0,
      end_vcol = final_vcol,
      byte_col = 0,
    }
  else
    local start_vcol = 0
    for index = 1, screen_height do
      local end_vcol = next_wrap_boundary(winid, row, start_vcol, final_vcol)
      segments[#segments + 1] = {
        start_vcol = start_vcol,
        end_vcol = end_vcol,
        byte_col = byte_col_for_vcol(winid, row, start_vcol),
      }
      if index < screen_height and end_vcol >= final_vcol then
        error("nvim_win_text_height ended wrapped source before its measured height", 3)
      end
      start_vcol = end_vcol
    end
    if segments[#segments].end_vcol ~= final_vcol then
      error("nvim_win_text_height wrap boundaries do not reach the measured line end", 3)
    end
  end

  return {
    row = row,
    screen_height = screen_height,
    end_vcol = final_vcol,
    fill = fill,
    segments = segments,
  }
end

local function usable_track(track, opts)
  opts = opts or {}
  if track == nil or track.invalid == true or track.state == "retired" then
    return nil
  end
  if opts.require_valid == true and track.state ~= "valid" then
    return nil
  end
  return track
end

function M.usable(track, opts)
  return usable_track(track, opts)
end

function M.for_ref(ref, opts)
  opts = opts or {}
  if ref == nil then
    return nil
  end

  local track
  if opts.by_key ~= nil then
    track = opts.by_key[tracker.track_ref_key(ref)]
  else
    track = tracker.resolve_ref(ref)
  end

  return usable_track(track, opts)
end

function M.for_projection(projection, opts)
  opts = opts or {}
  if projection == nil or projection.ref == nil then
    return nil
  end

  local track
  if opts.by_key ~= nil then
    track = opts.by_key[projection.key]
    if track == nil then
      track = opts.by_key[tracker.track_ref_key(projection.ref)]
    end
  else
    track = tracker.resolve_ref(projection.ref)
  end

  return usable_track(track, opts)
end

function M.by_key(bufnr, opts)
  local by_key = {}
  for _, track in ipairs(tracker.get_tracks(bufnr)) do
    track = usable_track(track, opts)
    if track ~= nil then
      by_key[tracker.track_ref_key(track)] = track
    end
  end
  return by_key
end

function M.measure_source_layout(view_or_ref, winid, opts)
  opts = opts or {}
  if not valid_win(winid) then
    return nil
  end

  local view = view_or_ref
  if view == nil or view.row == nil or view.end_row == nil then
    view = M.for_ref(view_or_ref, { require_valid = opts.require_valid == true })
  end
  if view == nil or view.row == nil or view.end_row == nil or view.end_row < view.row then
    return nil
  end

  local bufnr = view.bufnr
  if not valid_buf(bufnr) or vim.api.nvim_win_get_buf(winid) ~= bufnr then
    return nil
  end

  local rows = {}
  local total_screen_height = 0
  local max_row = line_count(bufnr) - 1
  if view.row < 0 or view.end_row > max_row then
    return nil
  end

  for row = view.row, view.end_row do
    local measured = oracle_row_layout(winid, row)
    rows[#rows + 1] = measured
    total_screen_height = total_screen_height + measured.screen_height
  end

  return {
    bufnr = bufnr,
    winid = winid,
    source_start_row = view.row,
    source_end_row = view.end_row,
    total_screen_height = total_screen_height,
    rows = rows,
  }
end

return M
