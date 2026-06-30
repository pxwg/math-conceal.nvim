-- Run with:
--   nvim --headless -u NONE '+luafile scripts/test-typst-code-transparent-scan.lua'

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

local function has_source(tracks, needle)
  for _, track in ipairs(tracks) do
    if (track.source or ""):find(needle, 1, true) ~= nil then
      return true
    end
  end
  return false
end

local function count_kind(tracks, kind)
  local count = 0
  for _, track in ipairs(tracks) do
    if track.object_kind == kind then
      count = count + 1
    end
  end
  return count
end

local function create_typst_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = "typst"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function run()
  add_repo_to_path()

  local image = require("math-conceal.image")
  image.config.renderers.typst.code_render.allow = { "remark" }

  local tracker = require("math-conceal.image.tracker")

  local allow_buf = create_typst_buf({
    "#remark[",
    "  $a + b$",
    "]",
  })
  assert_true("allowlisted container attaches", tracker.attach(allow_buf, { kind = "typst" }))
  local tracks = tracker.get_tracks(allow_buf)
  assert_eq("allowlisted container emits only itself when inactive", #tracks, 1)
  assert_eq("allowlisted container is code", tracks[1].object_kind, "code")
  assert_true("allowlisted container source is retained", has_source(tracks, "#remark"))

  vim.api.nvim_win_set_cursor(0, { 2, 4 })
  assert_true("allowlisted container expands under cursor", tracker.sync_cursor_nested(allow_buf))
  tracks = tracker.get_tracks(allow_buf)
  assert_eq("active allowlisted container keeps parent plus child", #tracks, 2)
  assert_eq("active allowlisted container has one child math", count_kind(tracks, "math"), 1)
  assert_true("active allowlisted container exposes child math", has_source(tracks, "$a + b$"))
  tracker.detach(allow_buf)

  local transparent_buf = create_typst_buf({
    "#plain[",
    "  $x + y$",
    "  #remark[$z$]",
    "]",
  })
  assert_true("transparent container attaches", tracker.attach(transparent_buf, { kind = "typst" }))
  tracks = tracker.get_tracks(transparent_buf)
  assert_eq("transparent non-allow container emits children", #tracks, 2)
  assert_eq("transparent non-allow container emits one math", count_kind(tracks, "math"), 1)
  assert_eq("transparent non-allow container emits one allow code", count_kind(tracks, "code"), 1)
  assert_true("transparent container skips itself", not has_source(tracks, "#plain"))
  assert_true("transparent container emits child math", has_source(tracks, "$x + y$"))
  assert_true("transparent container emits allowlisted child code", has_source(tracks, "#remark"))
  tracker.detach(transparent_buf)
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end

print("typst-code-transparent-scan-ok")
vim.cmd("qa!")
