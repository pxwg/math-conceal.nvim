local tracker = require("math-conceal.image.tracker")

local M = {}

function M.ref_set(refs)
  local set = {}
  for _, ref in ipairs(refs or {}) do
    set[tracker.track_ref_key(ref)] = true
  end
  return set
end

function M.merge_keys(target, source)
  target = target or {}
  for key, value in pairs(source or {}) do
    if value then
      target[key] = true
    end
  end
  return target
end

function M.tracks_by_key(event)
  local by_key = {}
  for _, track in ipairs((event and event.tracks) or {}) do
    by_key[tracker.track_ref_key(track)] = track
  end
  return by_key
end

function M.current_track_key_set(event, predicate)
  local set = {}
  for _, track in ipairs((event and event.tracks) or {}) do
    if predicate == nil or predicate(track) then
      set[tracker.track_ref_key(track)] = true
    end
  end
  return set
end

function M.first_changed_context_index(event)
  local first = nil
  local context = event and event.context or nil
  for _, index in ipairs((context and context.changed_unit_indexes) or {}) do
    if first == nil or index < first then
      first = index
    end
  end
  return first
end

function M.context_dependent_key_set(event, predicate)
  local first = M.first_changed_context_index(event)
  if first == nil then
    return {}
  end

  local context_units = event and event.context and event.context.units or {}
  local threshold = math.min(first, #context_units)
  local set = {}
  for _, track in ipairs((event and event.tracks) or {}) do
    if (track.prelude_count or 0) >= threshold and (predicate == nil or predicate(track)) then
      set[tracker.track_ref_key(track)] = true
    end
  end
  return set
end

return M
