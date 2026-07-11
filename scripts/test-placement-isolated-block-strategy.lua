-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-placement-isolated-block-strategy.lua'

local function run()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

  package.loaded["math-conceal.image.terminal"] = {
    place_image = function()
      return true
    end,
    delete_placement = function(_, placement_id)
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

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "  $",
    "  this source row is long enough to wrap in a narrow window",
    "  b",
    "  $",
  })
  vim.api.nvim_win_set_width(0, 24)
  vim.wo.wrap = true

  local surface_api = require("math-conceal.image.placement.surface")
  local isolated = require("math-conceal.image.placement.strategy.isolated-block")
  local surface = assert(surface_api.ensure(vim.api.nvim_get_current_win(), bufnr))
  local request = {
    state = "ready",
    ref = { bufnr = bufnr, tracker_generation = 1, track_id = 1 },
    realization_key = "isolated",
    image_id = 301,
    natural_grid = { cols = 6, rows = 3 },
    display_kind = "block",
    source_boundary_role = "isolated",
    placement_style = { horizontal_align = "center", fit = {} },
  }
  local record = surface_api.update_record(surface, "isolated", request)
  local view = {
    bufnr = bufnr,
    state = "valid",
    row = 0,
    col = 2,
    end_row = 3,
    end_col = 3,
  }

  isolated.prepare_measure(surface, record, view)
  local layout = assert(isolated.measure(surface, record, view))
  assert_true("at least one source carrier", #layout.carrier_rows >= 1)
  assert_eq("source prefix preserved", layout.source_prefix_cols, 2)
  assert_eq("block centered in text area", layout.prefix_cols, math.floor((surface_api.text_width(surface) - 6) / 2))
  assert_true("isolated apply", isolated.apply(surface, record, view, layout))
  assert_true("isolated record placed", record.placed)

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, surface.ns, 0, -1, { details = true })
  local saw_overlay = false
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    if details.virt_text_pos == "win_col" and details.virt_text_win_col == layout.prefix_cols then
      saw_overlay = true
    end
  end
  assert_true("isolated strategy uses window-column overlays", saw_overlay)

  local carriers, height, tail = isolated._choose_carrier_count({ 1, 1, 1, 1 }, 2)
  assert_eq("carrier count maximized within image", carriers, 2)
  assert_eq("carrier height", height, 2)
  assert_eq("no virtual tail", tail, 0)

  surface_api.close_buffer(bufnr)
  print("placement-isolated-block-strategy-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
