-- Run with:
--   MATH_CONCEAL_SERVICE=service/target/release/typst-concealer-service \
--     nvim --headless -u NONE -i NONE -l scripts/test-realization-service-integration.lua

local function run()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

  local function assert_true(label, value)
    if not value then
      error(label, 2)
    end
  end

  local terminal_calls = { sent = {}, placed = {}, deleted = {} }
  package.loaded["math-conceal.image.terminal"] = {
    batch = function(fn)
      return fn()
    end,
    send_image = function(path, image_id)
      terminal_calls.sent[#terminal_calls.sent + 1] = { path = path, image_id = image_id }
      return true
    end,
    place_image = function(image_id, placement_id, cols, rows)
      terminal_calls.placed[#terminal_calls.placed + 1] = {
        image_id = image_id,
        placement_id = placement_id,
        cols = cols,
        rows = rows,
      }
      return true
    end,
    delete_placement = function() end,
    delete_image = function(image_id)
      terminal_calls.deleted[#terminal_calls.deleted + 1] = image_id
    end,
    delete = function(image_id)
      terminal_calls.deleted[#terminal_calls.deleted + 1] = image_id
    end,
    upload = function()
      return true
    end,
  }

  local binary = vim.env.MATH_CONCEAL_SERVICE or "service/target/release/typst-concealer-service"
  assert_true("service executable", vim.fn.executable(binary) == 1)
  local conceal = require("math-conceal")
  conceal.setup({
    image = {
      enabled = true,
      enabled_by_default = false,
      styling_type = "none",
      live_preview_enabled = false,
      renderers = {
        typst = {
          filetypes = { "typst" },
          service_binary = binary,
          source_kind = "typst",
          scanner = "typst",
          backend = "typst",
          wrapper = "typst",
          inputs = {},
          code_render = { allow = {} },
          code_block = { padding_cols = 0, right_padding_cols = 1, min_cols = 8 },
          render_paths = { exclude = {} },
        },
        markdown = {
          filetypes = { "markdown" },
          service_binary = binary,
          source_kind = "markdown",
          scanner = "markdown",
          backend = "typst",
          wrapper = "mitex",
          inputs = {},
          mitex_package = "@preview/mitex:0.2.7",
          render_paths = { exclude = {} },
        },
      },
    },
  })
  local image = require("math-conceal.image")

  local function render_buffer(filetype, lines, expected_ready, source)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = filetype
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    local attachment = conceal.attach(bufnr, {
      source = source,
      surfaces = { unicode = false, image = true },
    })
    assert_true(filetype .. " attach", attachment.image)
    require("math-conceal.image.projection").force_render(bufnr)
    assert_true(
      filetype .. " realizations become ready",
      vim.wait(10000, function()
        local bs = require("math-conceal.image.state").get_buf_state(bufnr)
        local ready = 0
        for _, projection in pairs(bs.projections or {}) do
          if projection.status == "ready" and projection.visible_asset ~= nil then
            ready = ready + 1
          end
        end
        return ready == expected_ready
      end, 10)
    )
    return bufnr, attachment
  end

  local typst_buf, typst_attachment =
    render_buffer("typst", { "Inline $x + y$.", "", "$ x^2 + y^2 = z^2 $", "", "#rect(width: 100%)[code]" }, 3)
  local markdown_path = vim.fs.normalize(vim.fn.fnamemodify("/tmp/math-conceal-preview.md", ":p"))
  local markdown_buf, markdown_attachment = render_buffer(
    "snacks_picker_preview",
    { "Inline $x + y$.", "", "$$", "x^2 + y^2 = z^2", "$$" },
    2,
    {
      kind = "markdown",
      filetype = "markdown",
      path = markdown_path,
    }
  )
  local markdown_binding = image.get_binding(markdown_buf)
  assert_true("preview binding uses Markdown renderer", markdown_binding.kind == "markdown")
  assert_true("preview binding keeps logical filetype", markdown_binding.filetype == "markdown")
  assert_true("preview binding keeps real path", markdown_binding.path == markdown_path)
  assert_true("preview source helper uses explicit source", image.source_kind_for_bufnr(markdown_buf) == "markdown")
  assert_true("images uploaded", #terminal_calls.sent >= 2)
  assert_true("placements created", #terminal_calls.placed >= 2)

  assert_true("Typst attachment detaches", typst_attachment:detach())
  assert_true("Markdown attachment detaches", markdown_attachment:detach())
  assert_true("Typst image binding released", image.get_binding(typst_buf) == nil)
  assert_true("Markdown image binding released", image.get_binding(markdown_buf) == nil)
  print("realization-service-integration-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
