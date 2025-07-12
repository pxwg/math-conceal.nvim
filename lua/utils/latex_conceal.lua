local M = {}

-- State management
local state = {
  initialized = false,
  lookup_conceal = nil,
}

-- Helper function to get the plugin root directory
local function get_plugin_root()
  local source = debug.getinfo(2, "S").source
  local file = string.sub(source, 2) -- Remove the '@' prefix
  local dir = string.match(file, "(.*/)")

  -- Navigate up two directories: from lua/utils/ to the plugin root
  return string.gsub(dir, "lua/utils/$", "")
end

-- Try to load a dynamic library
local function try_load(path)
  local success, result = pcall(function()
    return package.loadlib(path, "luaopen_lookup_conceal")
  end)

  if success and type(result) == "function" then
    return result
  end

  return nil
end

-- Initialize the library
function M.initialize()
  if state.initialized then
    return state.lookup_conceal ~= nil
  end

  local plugin_root = get_plugin_root()

  -- Try with different extensions based on the platform
  local lib_paths = {
    plugin_root .. "/build/lookup_conceallua51.dylib",
    plugin_root .. "/build/lookup_conceallua51.so",
    plugin_root .. "/build/lookup_conceallua51.dll",
    plugin_root .. "/build/lookup_concealluajit.dylib",
    plugin_root .. "/build/lookup_concealluajit.so",
    plugin_root .. "/build/lookup_concealluajit.dll",
  }

  local lib_func = nil
  for _, path in ipairs(lib_paths) do
    lib_func = try_load(path)
    if lib_func then
      break
    end
  end

  if not lib_func then
    vim.notify(
      "Failed to load lookup_conceal library. Make sure you run 'make lua51' or 'make luajit' first.",
      vim.log.levels.ERROR
    )
    state.initialized = true
    return false
  end

  state.lookup_conceal = lib_func()
  state.initialized = true
  return true
end

-- Ensure the library is loaded before usage
local function ensure_loaded()
  if not state.initialized then
    return M.initialize()
  end
  return state.lookup_conceal ~= nil
end

--- Function to convert LaTeX math symbols to Unicode
--- @param text string: The LaTeX math symbol to convert
--- @param pattern? string: Conceal or Fonts pattern to use
--- @param type? string: Type of concealment (e.g., "cal", "frak", "bold", etc.)
--- @return string: The converted Unicode symbol or the original text if not found
function M.lookup_math_symbol(text, pattern, type)
  if not ensure_loaded() then
    return text
  end

  return state.lookup_conceal.lookup_math_symbol({ text = text, pattern = pattern or "", mode = type or "" })
end

-- _G.GetMathSymbol = M.lookup_math_symbol

return M
