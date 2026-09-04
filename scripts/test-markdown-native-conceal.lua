-- Run with:
--   nvim --headless -u NONE -i NONE -l scripts/test-markdown-native-conceal.lua
--
-- Regression coverage for the markdown query-override issue: attaching
-- math-conceal to a markdown buffer must not globally replace the runtime
-- `markdown`/`markdown_inline` highlights queries. Native markdown
-- concealment (inline links) belongs to the Treesitter highlighter;
-- math-conceal owns only the math regions (latex injections).

local function add_runtime_paths()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

  local treesitter = vim.fn.stdpath("data") .. "/lazy/nvim-treesitter"
  if vim.fn.isdirectory(treesitter) == 1 then
    vim.opt.runtimepath:append(treesitter)
  end
end

local function assert_eq(label, actual, expected)
  if not vim.deep_equal(actual, expected) then
    error(
      string.format("%s mismatch\nexpected: %s\nactual:   %s", label, vim.inspect(expected), vim.inspect(actual)),
      2
    )
  end
end

local function assert_true(label, value)
  if not value then
    error(label, 2)
  end
end

local function display_marks(bufnr)
  return require("math-conceal.render").collect_display_marks(bufnr, {
    toprow = 0,
    botrow = vim.api.nvim_buf_line_count(bufnr),
  })
end

local function run()
  add_runtime_paths()

  for _, lang in ipairs({ "latex", "markdown", "markdown_inline" }) do
    assert_true("Tree-sitter parser is installed for " .. lang, pcall(vim.treesitter.language.add, lang))
  end

  -- Snapshot the effective native markdown_inline query before attach.
  local ok_native, native_query = pcall(vim.treesitter.query.get, "markdown_inline", "highlights")
  assert_true("runtime markdown_inline highlights query exists", ok_native and native_query ~= nil)

  require("math-conceal").setup({ ft = { "markdown" }, image = { enabled = false } })
  local conceal = require("math-conceal.nvim")

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "[title](./name.md)", "", "$\\alpha + \\beta$" })

  local attachment = conceal.attach(bufnr, { owner = "test" })
  assert_true("attachment is current", attachment:is_current())
  assert_true("unicode surface attached", attachment.unicode)

  -- The effective markdown_inline query must still conceal inline-link
  -- punctuation and destination: native conceal is untouched.
  local parser = vim.treesitter.get_parser(bufnr, "markdown_inline")
  local tree = parser:parse()[1]
  local effective = vim.treesitter.query.get("markdown_inline", "highlights")
  local concealed = {}
  for id, node, metadata in effective:iter_captures(tree:root(), bufnr, 0, -1) do
    if effective.captures[id] == "markup.link" and metadata.conceal == "" then
      table.insert(concealed, vim.treesitter.get_node_text(node, bufnr))
    end
  end
  assert_eq("inline-link conceal metadata intact after attach", concealed, { "[", "]", "(", "./name.md", ")" })

  -- The math region is still concealed by math-conceal itself.
  local marks = display_marks(bufnr)
  local greek = {}
  for _, mark in ipairs(marks) do
    if mark.kind == "conceal" then
      greek[mark.conceal] = (greek[mark.conceal] or 0) + 1
    end
  end
  assert_true("latex injection still concealed (\\alpha -> α)", (greek["α"] or 0) > 0)
  assert_true("latex injection still concealed (\\beta -> β)", (greek["β"] or 0) > 0)

  -- No markdown capture may be concealed by math-conceal's render layer.
  for _, mark in ipairs(marks) do
    assert_true("no math-conceal mark on the link line (row 0)", mark.row ~= 0)
  end

  attachment:detach()
  print("test-markdown-native-conceal: OK")
end

run()
