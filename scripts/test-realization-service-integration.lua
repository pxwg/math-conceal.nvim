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
  local image = require("math-conceal.image")
  image.setup({
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
  })

  local function render_buffer(filetype, lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.bo[bufnr].filetype = filetype
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    assert_true(filetype .. " attach", image.attach_buf(bufnr))
    require("math-conceal.image.projection").force_render(bufnr)
    assert_true(
      filetype .. " realization becomes ready",
      vim.wait(10000, function()
        local bs = require("math-conceal.image.state").get_buf_state(bufnr)
        for _, projection in pairs(bs.projections or {}) do
          if projection.status == "ready" and projection.visible_asset ~= nil then
            return true
          end
        end
        return false
      end, 10)
    )
    return bufnr
  end

  local typst_buf = render_buffer("typst", { "Inline $x + y$.", "", "$ x^2 + y^2 = z^2 $" })
  local markdown_buf = render_buffer("markdown", { "Inline $x + y$.", "", "$$", "x^2 + y^2 = z^2", "$$" })
  assert_true("images uploaded", #terminal_calls.sent >= 2)
  assert_true("placements created", #terminal_calls.placed >= 2)

  image.disable_buf(typst_buf)
  image.disable_buf(markdown_buf)
  print("realization-service-integration-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
