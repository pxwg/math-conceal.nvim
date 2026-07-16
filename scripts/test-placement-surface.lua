-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-placement-surface.lua'

local cwd = vim.fn.getcwd()
vim.opt.runtimepath:append(cwd)
package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

local calls = { place = {}, delete = {} }
package.loaded["math-conceal.image.terminal"] = {
  place_image = function(image_id, placement_id, cols, rows)
    calls.place[#calls.place + 1] = { image_id, placement_id, cols, rows }
    return true
  end,
  delete_placement = function(image_id, placement_id)
    calls.delete[#calls.delete + 1] = { image_id, placement_id }
    require("math-conceal.image.state").release_placement_id(placement_id)
  end,
}

local function assert_eq(label, actual, expected)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

local function assert_true(label, value)
  if value ~= true then
    error(label, 2)
  end
end

local function run()
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "  $x$  " })
  vim.cmd("vsplit")
  local narrow = vim.api.nvim_get_current_win()
  local wide = nil
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if winid ~= narrow and vim.api.nvim_win_get_buf(winid) == bufnr then
      wide = winid
      break
    end
  end
  assert_true("second split exists", wide ~= nil)
  vim.api.nvim_win_set_width(narrow, 12)

  local surface = require("math-conceal.image.placement.surface")
  local narrow_surface = assert(surface.ensure(narrow, bufnr))
  local wide_surface = assert(surface.ensure(wide, bufnr))
  assert_true("window namespaces differ", narrow_surface.ns ~= wide_surface.ns)

  local inline_request = {
    state = "ready",
    ref = { bufnr = bufnr, tracker_generation = 1, track_id = 1 },
    realization_key = "inline",
    image_id = 100,
    natural_grid = { cols = 20, rows = 1 },
    display_kind = "inline",
    placement_style = { fit = {} },
  }
  local inline_grid = surface.effective_grid(narrow_surface, inline_request)
  assert_eq("inline preserves natural columns", inline_grid.cols, 20)

  local block_request = vim.deepcopy(inline_request)
  block_request.realization_key = "block"
  block_request.display_kind = "block"
  block_request.source_boundary_role = "isolated"
  block_request.placement_style = { fit = { left_padding_cols = 2, right_padding_cols = 1 } }
  local block_grid = surface.effective_grid(narrow_surface, block_request)
  assert_eq("block fits current window", block_grid.cols, math.max(1, surface.text_width(narrow_surface) - 3))
  assert_eq("block keeps natural rows", block_grid.rows, 1)

  local record = surface.update_record(narrow_surface, "track", block_request)
  assert_true("terminal placement succeeds", surface.ensure_terminal(record))
  local placement_id = record.placement_id
  assert_true("placement id allocated", placement_id ~= nil)
  surface.deactivate(narrow_surface, record, { keep_terminal = true })
  assert_eq("source reveal keeps placement id", record.placement_id, placement_id)

  local replacement = vim.deepcopy(block_request)
  replacement.image_id = 101
  replacement.realization_key = "replacement"
  surface.update_record(narrow_surface, "track", replacement)
  assert_eq("image replacement releases old placement", #calls.delete, 1)
  assert_eq("replacement clears placement id", record.placement_id, nil)

  assert_true("replacement terminal placement succeeds", surface.ensure_terminal(record))
  surface.release_image(101)
  assert_eq("image eviction releases placement", #calls.delete, 2)
  assert_eq("evicted record becomes source", record.request.state, "source")

  local fragments = surface.source_fragments(narrow_surface, {
    row = 0,
    col = 2,
    end_row = 0,
    end_col = 5,
  }, "inline")
  assert_eq("single source fragment", #fragments, 1)
  assert_true("surrounding whitespace keeps fragment-only", fragments[1].fragment_only)

  local replacement_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(narrow, replacement_bufnr)
  local replacement_surface = assert(surface.ensure(narrow, replacement_bufnr))
  local placement = require("math-conceal.image.placement")
  assert_eq("stale owner close is rejected", placement.close_window(narrow, bufnr), false)
  assert_eq("replacement surface remains current", surface._state().surfaces_by_win[narrow], replacement_surface)
  assert_eq("current owner close succeeds", placement.close_window(narrow, replacement_bufnr), true)

  surface.close_buffer(bufnr)
  assert_eq("all surfaces close", next(surface._state().surfaces_by_win), nil)

  print("placement-surface-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
