-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-fold-grid-centered-prefix.lua'

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
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "  $",
    "  x",
    "  $",
    "",
  })
  vim.o.columns = 80
  vim.api.nvim_win_set_width(0, 80)

  local tracker = require("math-conceal.image.tracker")
  local display = require("math-conceal.image.display")
  local placement = require("math-conceal.image.placement")

  local ref = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 1,
    id = 1,
  }
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
    end_row = 2,
    end_col = 3,
    source_display_kind = "block",
    source_facts = {
      inline = false,
      isolated = true,
    },
  }

  tracker.resolve_ref = function(requested_ref)
    return requested_ref and requested_ref.track_id == ref.track_id and track or nil
  end

  local asset = {
    image_id = 0x123456,
    cols = 10,
    rows = 2,
    render_key = "asset:centered",
  }

  assert_true(
    "fold-grid sync succeeds",
    placement.sync(bufnr, {
      key = "math:centered",
      ref = ref,
      asset = asset,
      display_role = "block",
      block_role = "isolated",
    })
  )

  local surface = placement._state().surfaces_by_win[vim.api.nvim_get_current_win()]
  assert_true("surface exists", surface ~= nil)
  local active = surface.placements["math:centered"]
  assert_true("placement exists", active ~= nil)

  local expected = display.block_left_pad_cols(bufnr, track, asset.cols)
  assert_eq("fold-grid prefix uses block centering pad", active.prefix_cols, expected)
  assert_eq("fold-grid prefix ignores source indent", active.prefix_cols, math.floor((80 - asset.cols) / 2))
  assert_true("fold-grid placed image", #terminal_calls > 0)

  placement.close_all(bufnr)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("fold-grid-centered-prefix-ok")
vim.cmd("qa!")
