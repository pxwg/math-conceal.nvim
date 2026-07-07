-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-typst-cursor-nested-tracks.lua'

local function add_repo_to_path()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({
    cwd .. "/lua/?.lua",
    cwd .. "/lua/?/init.lua",
    package.path,
  }, ";")
end

local function assert_eq(label, actual, expected)
  if actual ~= expected then
    error(string.format("%s mismatch\nexpected: %q\nactual:   %q", label, tostring(expected), tostring(actual)), 2)
  end
end

local function assert_true(label, value)
  if not value then
    error(label, 2)
  end
end

local function nested_tracks(tracker, bufnr)
  local tracks = {}
  for _, track in ipairs(tracker.get_tracks(bufnr)) do
    if track.cursor_nested == true then
      tracks[#tracks + 1] = track
    end
  end
  table.sort(tracks, function(a, b)
    if (a.cursor_nested_depth or 0) ~= (b.cursor_nested_depth or 0) then
      return (a.cursor_nested_depth or 0) < (b.cursor_nested_depth or 0)
    end
    if a.row ~= b.row or a.col ~= b.col then
      return a.row < b.row or (a.row == b.row and a.col < b.col)
    end
    return a.track_id < b.track_id
  end)
  return tracks
end

local function count_kind_depth(tracks, kind, depth)
  local count = 0
  for _, track in ipairs(tracks) do
    if track.object_kind == kind and track.cursor_nested_depth == depth then
      count = count + 1
    end
  end
  return count
end

local function has_source(tracks, needle, depth)
  for _, track in ipairs(tracks) do
    if track.cursor_nested_depth == depth and (track.source or ""):find(needle, 1, true) ~= nil then
      return true
    end
  end
  return false
end

local function run()
  add_repo_to_path()

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = "typst"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "#block[",
    "  $a + b$",
    "  #box[$c + d$]",
    "]",
    "after",
  })

  local tracker = require("math-conceal.image.tracker")
  local events = {}
  assert_true(
    "tracker attaches",
    tracker.attach(bufnr, {
      kind = "typst",
      on_repair = function(event)
        events[#events + 1] = event
      end,
    })
  )

  local initial = tracker.get_tracks(bufnr)
  assert_eq("initial top-level track count", #initial, 1)
  assert_eq("initial top-level track kind", initial[1].object_kind, "code")

  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  assert_true("first-level cursor expansion", tracker.sync_cursor_nested(bufnr))
  local tracks = nested_tracks(tracker, bufnr)
  assert_eq("first-level nested track count", #tracks, 2)
  assert_eq("first-level math count", count_kind_depth(tracks, "math", 1), 1)
  assert_eq("first-level code count", count_kind_depth(tracks, "code", 1), 1)
  assert_true("first-level math source present", has_source(tracks, "$a + b$", 1))
  assert_true("first-level code source present", has_source(tracks, "#box", 1))

  vim.api.nvim_win_set_cursor(0, { 3, 9 })
  assert_true("second-level cursor expansion", tracker.sync_cursor_nested(bufnr))
  tracks = nested_tracks(tracker, bufnr)
  assert_eq("second-level nested track count", #tracks, 3)
  assert_eq("first-level math remains", count_kind_depth(tracks, "math", 1), 1)
  assert_eq("first-level code remains", count_kind_depth(tracks, "code", 1), 1)
  assert_eq("second-level math count", count_kind_depth(tracks, "math", 2), 1)
  assert_true("second-level math source present", has_source(tracks, "$c + d$", 2))

  vim.api.nvim_win_set_cursor(0, { 5, 0 })
  assert_true("cursor exit retires nested tracks", tracker.sync_cursor_nested(bufnr))
  tracks = nested_tracks(tracker, bufnr)
  assert_eq("nested tracks retired after cursor exit", #tracks, 0)
  assert_true("repair events emitted", #events >= 4)

  tracker.detach(bufnr)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("typst-cursor-nested-tracks-ok")
vim.cmd("qa!")
