-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-placement-conflict.lua'

local cwd = vim.fn.getcwd()
vim.opt.runtimepath:append(cwd)
package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

local conflict = require("math-conceal.image.placement.conflict")

local function assert_true(label, value)
  if value ~= true then
    error(label, 2)
  end
end

local function assert_false(label, value)
  if value == true then
    error(label, 2)
  end
end

local function ready(role)
  return {
    request = {
      state = "ready",
      display_kind = role and "block" or "inline",
      source_boundary_role = role,
    },
  }
end

local parent = { row = 0, col = 0, end_row = 0, end_col = 10 }
local child = {
  row = 0,
  col = 3,
  end_row = 0,
  end_col = 7,
  cursor_nested = true,
  parent_key = "parent",
}

local records = { parent = ready(), child = ready() }
local views = { parent = parent, child = child }

local source = conflict.resolve(records, views, {
  cursor = { row = 0, col = 1 },
  mode = "n",
})
assert_true("cursor reveals parent", source.parent)
assert_false("nested child renders inside revealed parent", source.child)

source = conflict.resolve(records, views, {
  cursor = { row = 1, col = 0 },
  mode = "n",
})
assert_false("parent remains ready away from cursor", source.parent)
assert_true("nested child is hidden while parent is rendered", source.child)

source = conflict.resolve(records, views, {
  cursor = { row = 0, col = 1 },
  mode = "n",
  conceal_in_normal = true,
})
assert_false("normal conceal keeps parent ready", source.parent)
assert_true("normal conceal still suppresses nested child", source.child)

source = conflict.resolve(records, views, {
  selection = { mode = "char", start_row = 0, start_col = 0, end_row = 0, end_col = 2 },
})
assert_true("selection reveals parent", source.parent)
assert_false("child remains eligible inside selected parent source", source.child)

local overlap_records = { left = ready(), right = ready() }
local overlap_views = {
  left = { row = 2, col = 0, end_row = 2, end_col = 5 },
  right = { row = 2, col = 4, end_row = 2, end_col = 9 },
}
source = conflict.resolve(overlap_records, overlap_views, {})
assert_true("unrelated left overlap reveals", source.left)
assert_true("unrelated right overlap reveals", source.right)

source = conflict.resolve({ block = ready("sandwich") }, {
  block = { row = 3, col = 2, end_row = 3, end_col = 6 },
}, {})
assert_true("sandwich block reveals", source.block)

print("placement-conflict-ok")
vim.cmd("qa!")
