-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-typst-display-isolated-slot-lines.lua'

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

local function mark_rows(marks)
  local rows = {}
  for _, mark in ipairs(marks) do
    rows[#rows + 1] = tostring(mark[2])
  end
  return table.concat(rows, ",")
end

local function count_aux_kinds(marks)
  local spans = 0
  local conceal_lines = 0
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    if details.conceal ~= nil then
      spans = spans + 1
    end
    if details.conceal_lines ~= nil then
      conceal_lines = conceal_lines + 1
    end
  end
  return spans, conceal_lines
end

local function count_display_conceals(marks)
  local conceals = 0
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    if details.conceal ~= nil then
      conceals = conceals + 1
    end
  end
  return conceals
end

local function run()
  add_repo_to_path()

  local terminal_calls = {}
  package.loaded["math-conceal.image.terminal"] = {
    place_image = function(image_id, placement_id, cols, rows, opts)
      terminal_calls[#terminal_calls + 1] = {
        image_id = image_id,
        placement_id = placement_id,
        cols = cols,
        rows = rows,
        opts = opts,
      }
      return true
    end,
    delete_placement = function() end,
    delete = function() end,
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "  $",
    "  a",
    "  b",
    "  $",
    "after",
  })
  vim.cmd("set columns=80 lines=16 nowrap")

  local state = require("math-conceal.image.state")
  local tracker = require("math-conceal.image.tracker")
  local formula_display = require("math-conceal.image.formula-display")

  local track = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 1,
    id = 1,
    kind = "typst",
    state = "valid",
    row = 0,
    col = 2,
    end_row = 3,
    end_col = 3,
    source_display_kind = "block",
    source_facts = {
      inline = false,
      break_line = true,
      isolated = true,
    },
  }

  tracker.get_tracks = function(requested_bufnr)
    return requested_bufnr == bufnr and { track } or {}
  end
  tracker.source_line = function(requested_bufnr, row)
    return (vim.api.nvim_buf_get_lines(requested_bufnr, row, row + 1, false) or { "" })[1] or ""
  end

  local key = tracker.track_ref_key(track)
  local function set_asset(rows)
    state.get_buf_state(bufnr).display_assets[key] = {
      asset = {
        image_id = 0x123456,
        cols = 3,
        rows = rows,
        render_key = "asset:" .. tostring(rows),
      },
    }
  end

  vim.api.nvim_win_set_cursor(0, { 5, 0 })

  set_asset(2)
  formula_display.refresh(bufnr, { conceal_in_normal = false })
  local display_marks = vim.api.nvim_buf_get_extmarks(bufnr, state.display_ns, 0, -1, { details = true })
  local aux_marks = vim.api.nvim_buf_get_extmarks(bufnr, state.aux_ns, 0, -1, { details = true })
  assert_eq("S>I display row count", #display_marks, 2)
  assert_eq("S>I source rows carry first image rows", mark_rows(display_marks), "0,1")
  local span_count, line_count = count_aux_kinds(aux_marks)
  assert_eq("S>I uses one primary display conceal", count_display_conceals(display_marks), 1)
  assert_eq("S>I primary conceal spans whole source range", display_marks[1][4].end_row, 3)
  assert_eq("S>I primary conceal reaches source end col", display_marks[1][4].end_col, 3)
  assert_eq("S>I uses no per-carrier aux range conceal", span_count, 0)
  assert_eq("S>I surplus source rows use one conceal_lines range", line_count, 1)
  assert_eq("S>I no tail virt_lines", display_marks[#display_marks][4].virt_lines, nil)

  set_asset(5)
  formula_display.refresh(bufnr, { conceal_in_normal = false })
  display_marks = vim.api.nvim_buf_get_extmarks(bufnr, state.display_ns, 0, -1, { details = true })
  aux_marks = vim.api.nvim_buf_get_extmarks(bufnr, state.aux_ns, 0, -1, { details = true })
  assert_eq("S<I display row count", #display_marks, 4)
  assert_eq("S<I all source rows carry image rows", mark_rows(display_marks), "0,1,2,3")
  span_count, line_count = count_aux_kinds(aux_marks)
  assert_eq("S<I uses one primary display conceal", count_display_conceals(display_marks), 1)
  assert_eq("S<I primary conceal spans whole source range", display_marks[1][4].end_row, 3)
  assert_eq("S<I primary conceal reaches source end col", display_marks[1][4].end_col, 3)
  assert_eq("S<I uses no per-carrier aux range conceal", span_count, 0)
  assert_eq("S<I no source row uses conceal_lines", line_count, 0)
  local tail = display_marks[#display_marks][4].virt_lines or {}
  assert_eq("S<I tail image rows are virt_lines", #tail, 1)

  assert_true("slot path uploads image placement", #terminal_calls >= 2)
  formula_display.detach(bufnr)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("typst-display-isolated-slot-lines-ok")
vim.cmd("qa!")
