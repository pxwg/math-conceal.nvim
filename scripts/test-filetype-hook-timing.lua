-- Run with:
--   nvim --headless -u NONE -i NONE -l scripts/test-filetype-hook-timing.lua
-- Each case runs in a fresh Neovim; MC_CASE selects one.

local cwd = vim.fn.getcwd()
local script = debug.getinfo(1, "S").source:sub(2)
local cases = { "early", "late", "changed", "nohost", "builtin" }

if vim.env.MC_CASE == nil then
  for _, name in ipairs(cases) do
    local res = vim
      .system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", script }, {
        env = { MC_CASE = name },
        text = true,
      })
      :wait()
    if res.code ~= 0 then
      error(("case %s failed:\n%s%s"):format(name, res.stdout or "", res.stderr or ""))
    end
  end
  print("filetype-hook-timing-ok")
  return
end

vim.opt.runtimepath:append(cwd)
package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")
local treesitter = vim.fn.stdpath("data") .. "/lazy/nvim-treesitter"
if vim.fn.isdirectory(treesitter) == 1 then
  vim.opt.runtimepath:append(treesitter)
end
for _, lang in ipairs({ "markdown", "markdown_inline", "typst" }) do
  assert(pcall(vim.treesitter.language.add, lang), "missing Tree-sitter parser: " .. lang)
end
vim.treesitter.language.register("markdown", "mdtypst")

local function assert_eq(label, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(
      ("[%s] %s mismatch\nexpected: %s\nactual:   %s"):format(
        vim.env.MC_CASE,
        label,
        vim.inspect(expected),
        vim.inspect(actual)
      ),
      2
    )
  end
end

local errors = {}
vim.notify = function(msg, level)
  if (level or vim.log.levels.INFO) >= vim.log.levels.WARN then
    errors[#errors + 1] = tostring(msg)
  end
end
vim.notify_once = vim.notify

package.loaded["math-conceal.image.projection"] = {
  detach = function() end,
  on_tracker_repair = function() end,
  on_layout_change = function() end,
  force_render = function() end,
  sync_cursor = function() end,
}
package.loaded["math-conceal.image.state"] = {
  refresh_cell_px_size = function()
    return false
  end,
}
package.loaded["math-conceal.image.capability"] = { assert_supported = function() end }

local function setup(host_filetype)
  require("math-conceal").setup({
    ft = { "typst", host_filetype },
    image = {
      enabled = true,
      renderers = {
        host_typst = {
          filetypes = { host_filetype },
          -- The builtin Typst scanner renders the host's Typst injections.
          source_kind = "typst",
          service_binary = "typst-concealer-service",
        },
      },
    },
  })
end

local lines = { "Intro alpha text", "", "```typst", "$ alpha + beta $", "```", "", "outro alpha" }

local function open(filetype, path)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, path or ("/tmp/mc-hook-" .. vim.env.MC_CASE .. ".md"))
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = filetype
  return bufnr
end

local function settle()
  vim.wait(200, function()
    return false
  end)
end

local function attachment(bufnr)
  local nvim = package.loaded["math-conceal.nvim"]
  return nvim and nvim.get_attachment(bufnr) or nil
end

-- Rows with symbol conceal text. Host-native marks such as Markdown fence
-- conceal carry no conceal text.
local function symbol_conceal_rows(bufnr)
  local rows = {}
  for _, mark in ipairs(require("math-conceal.render").collect_display_marks(bufnr, { toprow = 0, botrow = #lines })) do
    if mark.conceal ~= nil then
      rows[mark.row] = true
    end
  end
  return vim.tbl_keys(rows)
end

local function track_count(bufnr)
  return #require("math-conceal.image.tracker").get_tracks(bufnr)
end

local case = vim.env.MC_CASE
if case == "early" then
  setup("mdtypst")
  -- A host plugin that configures itself later in the same FileType event,
  -- like lazy-loaded orgmode registering its injection directives.
  local injections = {}
  for _, file in ipairs(vim.treesitter.query.get_files("markdown", "injections")) do
    injections[#injections + 1] = table.concat(vim.fn.readfile(file), "\n")
  end
  injections[#injections + 1] = "((fenced_code_block) @_late (#mc-test-late! @_late))"
  vim.treesitter.query.set("markdown", "injections", table.concat(injections, "\n"))
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "mdtypst",
    callback = function()
      vim.treesitter.query.add_directive("mc-test-late!", function() end, { force = true, all = true })
    end,
  })
  local bufnr = open("mdtypst")
  assert_eq("no synchronous attach", attachment(bufnr), nil)
  settle()
  local att = attachment(bufnr)
  assert_eq("root_lang derived from host filetype", att and att.source.root_lang, "markdown")
  assert_eq("conceal_lang from profile", att and att.source.conceal_lang, "typst")
  assert_eq("unicode attached", att and att.unicode, true)
  assert_eq("image attached", att and att.image, true)
  assert_eq("typst conceal only inside the fence", symbol_conceal_rows(bufnr), { 3 })
  assert_eq("image tracks", track_count(bufnr), 1)
elseif case == "late" then
  local bufnr = open("mdtypst")
  settle()
  assert_eq("nothing before setup", attachment(bufnr), nil)
  setup("mdtypst")
  settle()
  local att = attachment(bufnr)
  assert_eq("late setup attaches loaded buffer", att and att.unicode, true)
  assert_eq("late setup root_lang", att and att.source.root_lang, "markdown")
  assert_eq("late setup image tracks", track_count(bufnr), 1)
elseif case == "changed" then
  setup("mdtypst")
  local bufnr = open("mdtypst")
  vim.bo[bufnr].filetype = "text"
  settle()
  assert_eq("stale filetype is not attached", attachment(bufnr), nil)
elseif case == "nohost" then
  setup("nohost")
  local bufnr = open("nohost")
  settle()
  local att = attachment(bufnr)
  assert_eq("missing host parser keeps the host root", att and att.source.root_lang, "nohost")
  assert_eq("missing host parser attaches no unicode", att and att.unicode, false)
  assert_eq("missing host parser renders no tracks", track_count(bufnr), 0)
elseif case == "builtin" then
  setup("mdtypst")
  local bufnr = open("typst", "/tmp/mc-hook-builtin.typ")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "$ alpha $" })
  settle()
  local att = attachment(bufnr)
  assert_eq("builtin filetype root_lang", att and att.source.root_lang, "typst")
  assert_eq("builtin filetype unicode", att and att.unicode, true)
end
assert_eq("no warnings or errors", errors, {})
