-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-fold-grid-reupload-after-close.lua'

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

local function assert_not_eq(label, actual, unexpected)
  if actual == unexpected then
    error(string.format("%s unexpectedly matched %q", label, tostring(actual)), 2)
  end
end

local function run()
  add_repo_to_path()

  local terminal_calls = {}
  package.loaded["math-conceal.image.terminal"] = {
    send_image = function(path, image_id)
      terminal_calls[#terminal_calls + 1] = {
        kind = "send_image",
        path = path,
        image_id = image_id,
      }
      return true
    end,
    place_image = function(image_id, placement_id, cols, rows, opts)
      terminal_calls[#terminal_calls + 1] = {
        kind = "place_image",
        image_id = image_id,
        placement_id = placement_id,
        cols = cols,
        rows = rows,
        opts = opts,
      }
      return true
    end,
    delete_placement = function(image_id, placement_id)
      terminal_calls[#terminal_calls + 1] = {
        kind = "delete_placement",
        image_id = image_id,
        placement_id = placement_id,
      }
    end,
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "$",
    "x + y = z",
    "$",
    "after",
  })
  vim.o.columns = 80
  vim.api.nvim_win_set_width(0, 80)

  local tracker = require("math-conceal.image.tracker")
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
    col = 0,
    end_row = 2,
    end_col = 1,
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
    image_id = 0x234567,
    path = "/tmp/fold-grid-reupload.png",
    cols = 12,
    rows = 3,
    render_key = "asset:reupload",
  }

  local intent = {
    key = "math:reupload",
    ref = ref,
    asset = asset,
    display_role = "block",
    block_role = "isolated",
  }

  assert_true("initial fold-grid sync succeeds", placement.sync(bufnr, intent))
  local surface = placement._state().surfaces_by_win[vim.api.nvim_get_current_win()]
  local first = surface.placements["math:reupload"]
  assert_true("first placement exists", first ~= nil)
  local first_placement_id = first.placement_id

  assert_eq("initial sync uploads image", terminal_calls[1].kind, "send_image")
  assert_eq("initial upload uses asset path", terminal_calls[1].path, asset.path)
  assert_eq("initial upload uses asset image", terminal_calls[1].image_id, asset.image_id)
  assert_eq("initial sync places image", terminal_calls[2].kind, "place_image")
  assert_eq("initial place uses uploaded image", terminal_calls[2].image_id, asset.image_id)
  assert_eq("initial place uses first placement", terminal_calls[2].placement_id, first_placement_id)

  -- Drain repaint scheduled by surface sync before measuring close/restore.
  vim.wait(100, function()
    return false
  end, 10)
  terminal_calls = {}

  placement.close_key(bufnr, "math:reupload")
  assert_eq("source reveal deletes terminal placement", terminal_calls[1].kind, "delete_placement")
  assert_eq("source reveal targets first placement", terminal_calls[1].placement_id, first_placement_id)

  terminal_calls = {}
  assert_true("restored fold-grid sync succeeds", placement.sync(bufnr, intent))
  local restored = placement._state().surfaces_by_win[vim.api.nvim_get_current_win()].placements["math:reupload"]
  assert_true("restored placement exists", restored ~= nil)
  assert_not_eq("restore creates a fresh placement id", restored.placement_id, first_placement_id)

  assert_eq("restore reuploads image", terminal_calls[1].kind, "send_image")
  assert_eq("restore upload uses same asset path", terminal_calls[1].path, asset.path)
  assert_eq("restore upload uses same image id", terminal_calls[1].image_id, asset.image_id)
  assert_eq("restore places image after reupload", terminal_calls[2].kind, "place_image")
  assert_eq("restore place uses same image id", terminal_calls[2].image_id, asset.image_id)
  assert_eq("restore place uses fresh placement", terminal_calls[2].placement_id, restored.placement_id)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("fold-grid-reupload-after-close-ok")
vim.cmd("qa!")
