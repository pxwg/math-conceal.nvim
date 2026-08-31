-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-placement-inline-boundary-strategies.lua'

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
    "before $x$ after",
    "before $",
    "x",
    "$",
    "$",
    "x",
    "$ after",
  })

  local surface_api = require("math-conceal.image.placement.surface")
  local inline = require("math-conceal.image.placement.strategy.inline")
  local boundary = require("math-conceal.image.placement.strategy.boundary-block")
  local surface = assert(surface_api.ensure(vim.api.nvim_get_current_win(), bufnr))

  local inline_request = {
    state = "ready",
    ref = { bufnr = bufnr, tracker_generation = 1, track_id = 1 },
    realization_key = "inline",
    image_id = 201,
    natural_grid = { cols = 3, rows = 1 },
    display_kind = "inline",
    placement_style = { horizontal_align = "source", fit = {} },
  }
  local inline_record = surface_api.update_record(surface, "inline", inline_request)
  local inline_view = { row = 0, col = 7, end_row = 0, end_col = 10 }
  local inline_layout = assert(inline.measure(surface, inline_record, inline_view))
  assert_true("inline apply", inline.apply(surface, inline_record, inline_view, inline_layout))
  assert_true("inline placed", inline_record.placed)

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, surface.ns, 0, -1, { details = true })
  local saw_inline = false
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    if mark[2] == 0 and mark[3] == 7 and details.virt_text_pos == "inline" then
      saw_inline = true
    end
  end
  assert_true("inline strategy creates inline virtual text", saw_inline)

  local prefix_request = {
    state = "ready",
    ref = { bufnr = bufnr, tracker_generation = 1, track_id = 2 },
    realization_key = "prefix",
    image_id = 202,
    natural_grid = { cols = 5, rows = 2 },
    display_kind = "block",
    source_boundary_role = "prefix",
    placement_style = { horizontal_align = "center", fit = {} },
  }
  local prefix_record = surface_api.update_record(surface, "prefix", prefix_request)
  local prefix_view = { row = 1, col = 7, end_row = 3, end_col = 1 }
  local prefix_layout = assert(boundary.measure(surface, prefix_record, prefix_view))
  assert_eq("prefix anchors start boundary", prefix_layout.anchor.row, 1)
  assert_true("prefix apply", boundary.apply(surface, prefix_record, prefix_view, prefix_layout))

  local suffix_request = vim.deepcopy(prefix_request)
  suffix_request.ref.track_id = 3
  suffix_request.realization_key = "suffix"
  suffix_request.image_id = 203
  suffix_request.source_boundary_role = "suffix"
  local suffix_record = surface_api.update_record(surface, "suffix", suffix_request)
  local suffix_view = { row = 4, col = 0, end_row = 6, end_col = 1 }
  local suffix_layout = assert(boundary.measure(surface, suffix_record, suffix_view))
  assert_eq("suffix anchors end boundary", suffix_layout.anchor.row, 6)
  assert_true("suffix apply", boundary.apply(surface, suffix_record, suffix_view, suffix_layout))

  marks = vim.api.nvim_buf_get_extmarks(bufnr, surface.ns, 0, -1, { details = true })
  local saw_prefix, saw_suffix = false, false
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    if mark[2] == 1 and details.virt_lines ~= nil and details.virt_lines_above ~= true then
      saw_prefix = true
    elseif mark[2] == 6 and details.virt_lines ~= nil and details.virt_lines_above == true then
      saw_suffix = true
    end
  end
  assert_true("prefix block inserts below start boundary", saw_prefix)
  assert_true("suffix block inserts above end boundary", saw_suffix)

  surface_api.close_buffer(bufnr)
  print("placement-inline-boundary-strategies-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
