-- Run with:
--   nvim --headless -u NONE -l scripts/test-realization-adapters.lua

local function run()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

  local function assert_eq(label, actual, expected)
    if actual ~= expected then
      error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)), 2)
    end
  end

  local registry = require("math-conceal.image.realization")
  local typst = registry.require("typst")
  local markdown = registry.require("markdown")
  local common = require("math-conceal.image.realization.common")
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "$x$", "#rect(width: 100%)" })
  local win = vim.api.nvim_get_current_win()
  local window = common.window_context(win, { math_baseline_pt = 11 })
  local ctx = {
    context_id = "ctx",
    context_rev = 1,
    context_units = {},
    context_source = "",
    flow_context_source = "",
    effective_root = cwd,
    inputs = {},
    wrapper = "typst",
    code_block = { padding_cols = 2, right_padding_cols = 3 },
  }
  local math_track = {
    bufnr = bufnr,
    tracker_generation = 1,
    generation = 1,
    track_id = 1,
    rev = 1,
    row = 0,
    col = 0,
    end_row = 0,
    end_col = 3,
    source = "$x$",
    source_hash = "math",
    source_display_kind = "block",
    source_rows = 1,
    object_kind = "math",
  }
  local code_track = vim.tbl_extend("force", vim.deepcopy(math_track), {
    track_id = 2,
    row = 1,
    end_row = 1,
    end_col = 18,
    source = "#rect(width: 100%)",
    source_hash = "code",
    source_display_kind = "inline",
    object_kind = "code",
  })

  assert_eq("Typst math is width independent", typst.layout(math_track, window, ctx, {}).key, "shared")
  assert_eq("Markdown math is width independent", markdown.layout(math_track, window, ctx, {}).key, "shared")
  local code_layout = typst.layout(code_track, window, ctx, {})
  assert_eq("Typst code is window keyed", code_layout.key:sub(1, 7), "window:")

  local math_desc = typst.describe(math_track, ctx, typst.layout(math_track, window, ctx, {}), {}, "track:1")
  assert_eq("math pending keeps previous", math_desc.pending_visibility, "previous")
  assert_eq("block math centers", math_desc.placement_style.horizontal_align, "center")
  local code_desc = typst.describe(code_track, ctx, code_layout, {}, "track:2")
  assert_eq("code uses flow batch", code_desc.batch_kind, "code_flow")
  assert_eq("code pending reveals source", code_desc.pending_visibility, "source")
  assert_eq("code block left padding", code_desc.meta.variants.block.placement_style.fit.left_padding_cols, 2)
  assert_eq("code block right padding", code_desc.meta.variants.block.placement_style.fit.right_padding_cols, 3)

  local accepted = typst.accept_response({
    type = "code_flow_rendered",
    flow_status = "ok",
    flow_role = "inline",
    layout_role = "block",
    selected_variant = "block",
    selected_variant_hash = code_desc.meta.variants.block.source_hash,
    render_status = "ok",
    path = "/tmp/code.png",
    width_px = 100,
    height_px = 50,
  }, code_desc)
  assert_eq("code response ready", accepted.status, "ready")
  assert_eq("code response display kind", accepted.display_kind, "block")

  print("realization-adapters-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
