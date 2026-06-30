-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-typst-cursor-nested-repair-preserves-tracks.lua'

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

local function child_by_kind(tracks, kind)
  for _, track in ipairs(tracks) do
    if track.object_kind == kind and track.cursor_nested_depth == 1 then
      return track
    end
  end
  return nil
end

local function ref_id_set(refs)
  local set = {}
  for _, ref in ipairs(refs or {}) do
    set[ref.track_id or ref.id] = true
  end
  return set
end

local function wait_for_events(events, count)
  assert_true(
    "scheduled repair event arrives",
    vim.wait(300, function()
      return #events >= count
    end, 5)
  )
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
        events[#events + 1] = vim.deepcopy(event)
      end,
    })
  )

  vim.api.nvim_win_set_cursor(0, { 2, 4 })
  assert_true("initial cursor-nested expansion", tracker.sync_cursor_nested(bufnr))
  local initial_nested = nested_tracks(tracker, bufnr)
  assert_eq("initial nested count", #initial_nested, 2)
  local math_child = child_by_kind(initial_nested, "math")
  local code_child = child_by_kind(initial_nested, "code")
  assert_true("initial math child", math_child ~= nil)
  assert_true("initial code child", code_child ~= nil)
  local math_id = math_child.track_id
  local code_id = code_child.track_id

  local events_before_move = #events
  vim.api.nvim_buf_set_text(bufnr, 1, 2, 1, 2, { "X" })
  wait_for_events(events, events_before_move + 1)

  local moved_nested = nested_tracks(tracker, bufnr)
  assert_eq("nested count after parent edit", #moved_nested, 2)
  local moved_math = child_by_kind(moved_nested, "math")
  local moved_code = child_by_kind(moved_nested, "code")
  assert_eq("math child id survives parent edit", moved_math and moved_math.track_id, math_id)
  assert_eq("code child id survives parent edit", moved_code and moved_code.track_id, code_id)
  assert_eq("math child source unchanged after prefix edit", moved_math.source, "$a + b$")
  assert_eq("math child start col moves with source", moved_math.col, 3)

  local parent_edit_event = events[#events]
  local parent_retired = ref_id_set(parent_edit_event.retired_refs)
  local parent_born = ref_id_set(parent_edit_event.born_refs)
  assert_true("parent edit does not retire math child", parent_retired[math_id] ~= true)
  assert_true("parent edit does not retire code child", parent_retired[code_id] ~= true)
  assert_true("parent edit does not rebirth math child", parent_born[math_id] ~= true)
  assert_true("parent edit does not rebirth code child", parent_born[code_id] ~= true)

  local events_before_child = #events
  vim.api.nvim_win_set_cursor(0, { 2, 6 })
  vim.api.nvim_buf_set_text(bufnr, 1, 5, 1, 5, { "Y" })
  wait_for_events(events, events_before_child + 1)

  local edited_nested = nested_tracks(tracker, bufnr)
  assert_eq("nested count after child edit", #edited_nested, 2)
  local edited_math = child_by_kind(edited_nested, "math")
  assert_eq("math child id survives child edit", edited_math and edited_math.track_id, math_id)
  assert_eq("math child source updates after child edit", edited_math.source, "$aY + b$")
  assert_eq("math child rev advances after source edit", edited_math.rev, 1)

  local child_edit_event = events[#events]
  local child_retired = ref_id_set(child_edit_event.retired_refs)
  local child_born = ref_id_set(child_edit_event.born_refs)
  local child_identity_changed = ref_id_set(child_edit_event.identity_changed_refs)
  assert_true("child edit does not retire math child", child_retired[math_id] ~= true)
  assert_true("child edit does not rebirth math child", child_born[math_id] ~= true)
  assert_true("child edit reports math identity change", child_identity_changed[math_id] == true)

  tracker.detach(bufnr)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("typst-cursor-nested-repair-preserves-tracks-ok")
vim.cmd("qa!")
