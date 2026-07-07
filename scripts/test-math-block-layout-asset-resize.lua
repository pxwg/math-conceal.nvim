-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-math-block-layout-asset-resize.lua'

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

  local refresh_calls = 0
  local preview_refresh_calls = 0
  local render_calls = 0

  package.loaded["math-conceal.image.context"] = {
    resolve = function(bufnr)
      return {
        bufnr = bufnr,
        backend = "typst",
        wrapper = "typst",
        context_id = "ctx",
        context_rev = 1,
        context_source = "",
        effective_root = vim.uv.cwd(),
        inputs = vim.empty_dict(),
        workspace = { outputs_dir = vim.fn.tempname() },
        context_units = {},
      }
    end,
  }
  package.loaded["math-conceal.image.formula-display"] = {
    refresh = function()
      refresh_calls = refresh_calls + 1
    end,
    repair_tracks = function() end,
    on_tracker_repair = function() end,
    sync_cursor = function() end,
    detach = function() end,
  }
  package.loaded["math-conceal.image.preview"] = {
    refresh = function()
      preview_refresh_calls = preview_refresh_calls + 1
    end,
    schedule = function() end,
    detach = function() end,
  }
  package.loaded["math-conceal.image.quickfix"] = { rebuild = function() end }
  package.loaded["math-conceal.image.session"] = {
    render_formulas = function()
      render_calls = render_calls + 1
      return true
    end,
    stop = function() end,
  }

  local binding = {
    kind = "typst",
    source_kind = "typst",
    scanner = "typst",
    backend = "typst",
    wrapper = "typst",
    root = vim.uv.cwd(),
  }
  package.loaded["math-conceal.image"] = {
    config = { block_padding_cols = 0 },
    get_binding = function()
      return binding
    end,
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "$",
    "x + y = z",
    "$",
    "",
  })
  vim.o.columns = 80
  vim.api.nvim_win_set_width(0, 80)

  local state = require("math-conceal.image.state")
  state._cell_px_w = 10
  state._cell_px_h = 20

  local tracker = require("math-conceal.image.tracker")
  local ref = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 1,
    id = 1,
  }
  local key = tracker.track_ref_key(ref)
  local track = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 1,
    id = 1,
    kind = "typst",
    object_kind = "math",
    node_type = "math",
    state = "valid",
    row = 0,
    col = 0,
    end_row = 2,
    end_col = 1,
    source_display_kind = "block",
    source_rows = 3,
    render_whole_line = true,
    source_facts = {
      inline = false,
      isolated = true,
    },
  }
  tracker.resolve_ref = function(requested_ref)
    return requested_ref and requested_ref.track_id == ref.track_id and track or nil
  end
  tracker.get_context = function()
    return { units = {}, signature = "" }
  end

  local asset = {
    image_id = 0x345678,
    path = "/tmp/math-block.png",
    width_px = 1200,
    height_px = 40,
    cols = 120,
    rows = 2,
    render_key = "render:natural-width",
  }
  local bs = state.get_buf_state(bufnr)
  bs.projections[key] = {
    bufnr = bufnr,
    key = key,
    ref = ref,
    visible_asset = asset,
    status = "visible",
  }
  bs.display_assets[key] = { asset = asset, source_reveal = false }

  require("math-conceal.image.projection").on_layout_change(bufnr)

  assert_eq("math block asset cols are clamped to current window", asset.cols, 80)
  assert_eq("math block asset rows are recomputed", asset.rows, 2)
  assert_true("display asset remains the visible asset", bs.display_assets[key].asset == asset)
  assert_eq("formula display refreshed", refresh_calls, 1)
  assert_eq("preview refreshed", preview_refresh_calls, 1)
  assert_eq("math layout resize does not request a rerender", render_calls, 0)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("math-block-layout-asset-resize-ok")
vim.cmd("qa!")
