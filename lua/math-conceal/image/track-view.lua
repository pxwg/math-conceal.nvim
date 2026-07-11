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

local function source_line(bufnr, row)
  return tracker.source_line(bufnr, row)
end

local function window_text_width(winid)
  local info = vim.fn.getwininfo(winid)[1] or {}
  local textoff = tonumber(info.textoff) or 0
  return math.max(1, vim.api.nvim_win_get_width(winid) - textoff)
end

local function source_row_display_width(bufnr, winid, row)
  local line = source_line(bufnr, row)
  local ok, width = pcall(vim.api.nvim_win_call, winid, function()
    return vim.fn.strdisplaywidth(line)
  end)
  if not ok or type(width) ~= "number" then
    return math.max(0, vim.fn.strdisplaywidth(line))
  end
  return math.max(0, width)
end

local function byte_col_for_vcol(winid, row, start_vcol)
  if start_vcol <= 0 then
    return 0
  end
  local ok, col = pcall(vim.fn.virtcol2col, winid, row + 1, start_vcol + 1)
  if not ok or type(col) ~= "number" or col < 1 then
    return 0
  end
  return math.max(0, col - 1)
end

local function fallback_row_layout(bufnr, winid, row)
  local text_width = window_text_width(winid)
  local width = source_row_display_width(bufnr, winid, row)
  local screen_height = 1
  if vim.wo[winid].wrap and width > 0 then
    screen_height = math.max(1, math.ceil(width / text_width))
  end

  local segments = {}
  local start_vcol = 0
  for _ = 1, screen_height do
    local end_vcol = math.min(width, start_vcol + text_width)
    if end_vcol <= start_vcol and width > start_vcol then
      end_vcol = start_vcol + text_width
    end
    segments[#segments + 1] = {
      start_vcol = start_vcol,
      end_vcol = end_vcol,
      byte_col = byte_col_for_vcol(winid, row, start_vcol),
    }
    start_vcol = end_vcol
  end

  return {
    row = row,
    screen_height = screen_height,
    end_vcol = width,
    fill = 0,
    segments = segments,
  }
end

local function text_height(winid, opts)
  if type(vim.api.nvim_win_text_height) ~= "function" then
    return nil
  end
  local ok, result = pcall(vim.api.nvim_win_text_height, winid, opts)
  if not ok or type(result) ~= "table" then
    return nil
  end
  return result
end

local function next_wrap_boundary(winid, row, start_vcol, final_vcol, fallback_width)
  local result = text_height(winid, {
    start_row = row,
    end_row = row,
    start_vcol = start_vcol,
    max_height = 1,
  })
  local boundary = result and tonumber(result.end_vcol) or nil
  if boundary == nil or boundary <= start_vcol then
    boundary = math.min(final_vcol, start_vcol + fallback_width)
  end
  if boundary <= start_vcol and final_vcol > start_vcol then
    boundary = start_vcol + fallback_width
  end
  return math.max(start_vcol, boundary)
end

local function oracle_row_layout(bufnr, winid, row)
  local result = text_height(winid, {
    start_row = row,
    end_row = row,
    start_vcol = 0,
  })
  if result == nil then
    return fallback_row_layout(bufnr, winid, row)
  end

  local screen_height = math.max(1, math.floor(tonumber(result.all) or 1))
  local final_vcol = math.max(0, math.floor(tonumber(result.end_vcol) or 0))
  local fallback_width = window_text_width(winid)
  local segments = {}

  if not vim.wo[winid].wrap then
    segments[#segments + 1] = {
      start_vcol = 0,
      end_vcol = final_vcol,
      byte_col = 0,
    }
  else
    local start_vcol = 0
    for _ = 1, screen_height do
      local end_vcol = next_wrap_boundary(winid, row, start_vcol, final_vcol, fallback_width)
      segments[#segments + 1] = {
        start_vcol = start_vcol,
        end_vcol = end_vcol,
        byte_col = byte_col_for_vcol(winid, row, start_vcol),
      }
      if end_vcol <= start_vcol or end_vcol >= final_vcol then
        break
      end
      start_vcol = end_vcol
    end
  end

  while #segments < screen_height do
    local previous = segments[#segments]
    local start_vcol = previous and previous.end_vcol or 0
    local end_vcol = math.max(start_vcol, final_vcol)
    segments[#segments + 1] = {
      start_vcol = start_vcol,
      end_vcol = end_vcol,
      byte_col = byte_col_for_vcol(winid, row, start_vcol),
    }
  end

  return {
    row = row,
    screen_height = screen_height,
    end_vcol = final_vcol,
    fill = math.max(0, math.floor(tonumber(result.fill) or 0)),
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
    local measured = oracle_row_layout(bufnr, winid, row)
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
