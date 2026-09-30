-- Run from the repo in a real kitty terminal (parsers and render service required):
--   MATH_CONCEAL_FT=typst MATH_CONCEAL_ALIGN=source \
--     nvim -u NONE -i NONE --listen /tmp/block-align.sock \
--     '+luafile scripts/test-image-block-align.lua'
-- Repeat with FT=markdown and ALIGN=center (or unset to test the default).
-- RPC result: luaeval('_G.block_align_result'); leave UI open for visual inspection.
vim.opt.runtimepath:append(vim.fn.getcwd())
if vim.env.MATH_CONCEAL_RUNTIME then
  vim.opt.runtimepath:append(vim.env.MATH_CONCEAL_RUNTIME)
end
vim.o.swapfile = false
vim.o.termguicolors = true
local ft = vim.env.MATH_CONCEAL_FT or "typst"
local align = vim.env.MATH_CONCEAL_ALIGN
if align == "" then
  align = nil
end
local binary = vim.env.MATH_CONCEAL_SERVICE or "service/target/release/typst-concealer-service"
local conceal = require("math-conceal")
conceal.setup({
  image = {
    enabled = true,
    enabled_by_default = false,
    live_preview_enabled = false,
    block_align = align,
    renderers = { typst = { service_binary = binary }, markdown = { service_binary = binary } },
  },
})
vim.bo.filetype = ft
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
  "Block alignment: " .. ft .. " / " .. (align or "default"),
  "",
  ft == "typst" and "  $ x^2 + y^2 = z^2 $" or "  $$x^2 + y^2 = z^2$$",
  "",
  "Inline $x+y$ stays inline.",
})
local bufnr, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
assert(require("math-conceal.nvim").attach(bufnr, { surfaces = { unicode = false, image = true } }).image)
require("math-conceal.image.projection").force_render(bufnr)

_G.block_align_result = "pending"
vim.defer_fn(function()
  local ok, result = xpcall(function()
    local api = require("math-conceal.image.placement.surface")
    local surface
    assert(
      vim.wait(20000, function()
        surface = api._state().surfaces_by_win[win]
        local count = 0
        for _, record in pairs(surface and surface.records or {}) do
          if record.placed and record.placement_id then
            count = count + 1
          end
        end
        return count == 2
      end, 20),
      "two real rendered placements must appear"
    )
    local block
    for _, record in pairs(surface.records) do
      if record.request.display_kind == "block" then
        block = record
      else
        assert(record.request.placement_style.horizontal_align == nil, "inline alignment unchanged")
      end
    end
    assert(block, "block placement exists")
    local expected = (align or "center") == "center" and math.floor((api.text_width(surface) - block.grid.cols) / 2)
      or 2
    assert(block.prefix_cols == expected, "block must land at expected column")
    local overlay = false
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, surface.ns, 0, -1, { details = true })) do
      if mark[2] == 2 and mark[4].virt_text_win_col == expected then
        overlay = true
      end
    end
    assert(overlay, "actual block overlay must use expected column")
    return { status = "pass", filetype = ft, align = align or "default", column = expected }
  end, debug.traceback)
  _G.block_align_result = ok and result or { status = "fail", error = result }
  print(vim.json.encode(_G.block_align_result))
end, 100)
