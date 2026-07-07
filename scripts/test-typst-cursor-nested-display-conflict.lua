-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-typst-cursor-nested-display-conflict.lua'

local function add_repo_to_path()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({
    cwd .. "/lua/?.lua",
    cwd .. "/lua/?/init.lua",
    package.path,
  }, ";")
end

local function assert_true(label, value)
  if not value then
    error(label, 2)
  end
end

local function run()
  add_repo_to_path()

  package.loaded["math-conceal.image.terminal"] = {
    place_image = function()
      return true
    end,
    delete_placement = function() end,
    delete = function() end,
  }

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "$abc$" })

  local state = require("math-conceal.image.state")
  local tracker = require("math-conceal.image.tracker")
  local formula_display = require("math-conceal.image.formula-display")

  local parent = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 1,
    id = 1,
    kind = "typst",
    state = "valid",
    object_kind = "math",
    node_type = "math",
    row = 0,
    col = 0,
    end_row = 0,
    end_col = 5,
    source_display_kind = "inline",
    source_facts = {
      inline = true,
      break_line = false,
      isolated = false,
    },
  }
  parent.key = tracker.track_ref_key(parent)

  local child = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 2,
    id = 2,
    kind = "typst",
    state = "valid",
    object_kind = "math",
    node_type = "math",
    row = 0,
    col = 2,
    end_row = 0,
    end_col = 4,
    source_display_kind = "inline",
    source_facts = {
      inline = true,
      break_line = false,
      isolated = false,
    },
    cursor_nested = true,
    parent_key = parent.key,
    cursor_nested_depth = 1,
    cursor_nested_root_key = parent.key,
  }
  child.key = tracker.track_ref_key(child)

  tracker.get_tracks = function(requested_bufnr)
    return requested_bufnr == bufnr and { parent, child } or {}
  end
  tracker.source_line = function(requested_bufnr, row)
    return (vim.api.nvim_buf_get_lines(requested_bufnr, row, row + 1, false) or { "" })[1] or ""
  end

  state.get_buf_state(bufnr).display_assets[child.key] = {
    asset = {
      image_id = 0x234567,
      cols = 2,
      rows = 1,
      render_key = "child",
    },
  }

  vim.api.nvim_win_set_cursor(0, { 1, 1 })
  formula_display.refresh(bufnr, { conceal_in_normal = false })

  local marks = vim.api.nvim_buf_get_extmarks(bufnr, state.display_ns, 0, -1, { details = true })
  local child_slot = false
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    if mark[2] == child.row and mark[3] == child.col and details.virt_text ~= nil then
      child_slot = true
    end
  end

  assert_true("cursor-nested child renders inside revealed parent source", child_slot)
  formula_display.detach(bufnr)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("typst-cursor-nested-display-conflict-ok")
vim.cmd("qa!")
