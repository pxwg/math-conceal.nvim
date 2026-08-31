local M = {}

local function version_string(version)
  return table.concat({ version.major or 0, version.minor or 0, version.patch or 0 }, ".")
end

local function service_path(binary)
  if type(binary) ~= "string" or binary == "" then
    return nil
  end
  if vim.fn.executable(binary) == 1 or vim.uv.fs_stat(binary) ~= nil then
    return binary
  end
  local default_name = vim.fn.has("win32") == 1 and "typst-concealer-service.exe" or "typst-concealer-service"
  if binary ~= default_name then
    return nil
  end
  local source = debug.getinfo(1, "S").source:gsub("^@", "")
  local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(source)))
  local bundled = root .. "/service/target/release/" .. default_name
  return vim.uv.fs_stat(bundled) ~= nil and bundled or nil
end

local function terminal_supports_graphics()
  local term = (vim.env.TERM or ""):lower()
  local program = (vim.env.TERM_PROGRAM or ""):lower()
  return vim.env.KITTY_WINDOW_ID ~= nil
    or term:find("kitty", 1, true) ~= nil
    or program:find("kitty", 1, true) ~= nil
    or program:find("ghostty", 1, true) ~= nil
    or program:find("wezterm", 1, true) ~= nil
end

function M.check()
  vim.health.start("math-conceal")
  local capability = require("math-conceal.image.capability").inspect()
  if capability.nvim_011 then
    vim.health.ok("Neovim " .. version_string(capability.nvim_version) .. " supports the image path")
  else
    vim.health.error("Graphical conceal requires Neovim 0.11 or newer")
  end
  for name, available in pairs(capability.apis) do
    if available then
      vim.health.ok(name .. " is available")
    else
      vim.health.error(name .. " is unavailable")
    end
  end

  local ok_placement, placement_available = pcall(function()
    return require("math-conceal.image.placement").available()
  end)
  if ok_placement and placement_available then
    vim.health.ok("window-scoped placement namespaces are available")
  else
    vim.health.error("window-scoped placement namespaces are unavailable")
  end

  if terminal_supports_graphics() then
    vim.health.ok("the terminal environment advertises kitty graphics support")
  else
    vim.health.warn("the terminal environment does not advertise kitty graphics support")
  end

  local image = require("math-conceal.image")
  local registry = require("math-conceal.image.realization")
  local seen_services = {}
  for name, renderer in pairs(image.config.renderers or {}) do
    local source_kind = renderer.source_kind or renderer.scanner or name
    if registry.get(source_kind) ~= nil then
      vim.health.ok(("%s realization adapter is registered"):format(source_kind))
    else
      vim.health.error(("%s realization adapter is not registered"):format(source_kind))
    end
    local binary = renderer.service_binary or "typst-concealer-service"
    if not seen_services[binary] then
      seen_services[binary] = true
      local resolved = service_path(binary)
      if resolved ~= nil then
        vim.health.ok("render service is executable: " .. resolved)
      else
        vim.health.error("render service is unavailable: " .. binary)
      end
    end
  end
end

return M
