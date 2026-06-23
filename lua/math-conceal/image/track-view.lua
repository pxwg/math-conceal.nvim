---Late-binding helpers for reading current tracker snapshots from TrackRef-backed projections.
---Projection state stores identity; this module asks tracker for the live TrackView when position matters.
local tracker = require("math-conceal.image.tracker")

local M = {}

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

return M
