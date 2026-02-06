--- loader.lua - Query loading and buffer attachment
--- Responsible for: attach buffer → parse TS highlighters → load SCM queries → register to render
local M = {}

local query_utils = require("math-conceal.query")
local render = require("math-conceal.render")

--- @class LoaderConfig
--- @field conceal string[] Conceal types to enable (e.g., "greek", "script", "math", "font", "delim", "phy")
--- @field ft string[] Filetypes to enable conceal
--- @field ns_id integer Namespace ID
--- @field highlights table<string, table<string, string>> Highlight group definitions

--- @type LoaderConfig
local config = {
  conceal = { "greek", "script", "math", "font", "delim", "phy" },
  ft = { "plaintex", "tex", "context", "bibtex", "markdown", "typst" },
  ns_id = 0,
  highlights = {},
}

-- Track loaded queries per language to avoid redundant loading
local loaded_langs = {}

-- Track query file content per language
local query_files_cache = {}
local query_content_cache = {}

-- Augroup for buffer-specific autocmds
local augroup = vim.api.nvim_create_augroup("math-conceal-loader", { clear = true })

-- Get plugin root directory
local plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
local symbols_dir = plugin_root .. "/symbols"

--- Map filetype to tree-sitter language
--- @param filetype string
--- @return "latex"|"typst"
local function filetype_to_lang(filetype)
  if filetype == "typst" then
    return "typst"
  end
  return "latex"
end

--- Strip "; extends" directive from query content
--- @param content string Query content
--- @return string Cleaned content
local function strip_extends_directive(content)
  -- Remove lines that start with "; extends" (with optional whitespace)
  local result = content:gsub("^;%s*extends[^\n]*\n?", ""):gsub("\n;%s*extends[^\n]*", "")
  return result
end

--- Read and concatenate query files
--- @param files string[] List of file paths
--- @return string Concatenated query content
local function read_query_files(files)
  local contents = {}
  for _, file in ipairs(files) do
    local f = io.open(file, "r")
    if f then
      local content = f:read("*a")
      f:close()
      -- Strip extends directive
      content = strip_extends_directive(content)
      table.insert(contents, content)
    end
  end
  return table.concat(contents, "\n")
end

--- Get all conceal query files for a language from plugin's symbols directory
--- @param lang "latex"|"typst"
--- @param conceal_types string[] List of conceal types
--- @return string[] List of query file paths
local function get_conceal_query_files(lang, conceal_types)
  local files = {}
  local lang_dir = symbols_dir .. "/" .. lang

  for _, name in ipairs(conceal_types) do
    local query_file = lang_dir .. "/conceal_" .. name .. ".scm"
    -- Check if file exists
    local f = io.open(query_file, "r")
    if f then
      f:close()
      table.insert(files, query_file)
    end
  end

  return files
end

--- Get highlight query files for a language (from standard treesitter paths)
--- @param lang "latex"|"typst"
--- @return string[] List of query file paths
local function get_highlight_query_files(lang)
  return vim.treesitter.query.get_files(lang, "highlights")
end

--- Load and cache query content for a language
--- @param lang "latex"|"typst"
--- @return string Query content
local function load_lang_queries(lang)
  if query_content_cache[lang] then
    return query_content_cache[lang]
  end

  -- Get all query files: highlights + conceal types
  local files = get_highlight_query_files(lang)
  local conceal_files = get_conceal_query_files(lang, config.conceal)
  vim.list_extend(files, conceal_files)

  query_files_cache[lang] = files
  local content = read_query_files(files)
  query_content_cache[lang] = content

  return content
end

--- Build final query string for a language, optionally with preamble additions
--- @param lang "latex"|"typst"
--- @param buf integer Buffer number (for preamble detection)
--- @return string Final query content
local function build_query_string(lang, buf)
  local base_content = load_lang_queries(lang)

  -- For tex files with latex language, add preamble-defined commands
  local filetype = vim.bo[buf].filetype
  if filetype == "tex" and lang == "latex" then
    local conceal_map = query_utils.get_preamble_conceal_map(buf)
    local preamble_queries = query_utils.update_latex_queries(conceal_map)
    if preamble_queries and #preamble_queries > 0 then
      base_content = base_content .. "\n" .. preamble_queries
    end
  end

  return base_content
end

--- Detect all tree-sitter languages used in a buffer (including injections)
--- @param buf integer Buffer number
--- @return string[] List of language names (all languages, not just latex/typst)
local function detect_buffer_languages(buf)
  local langs = {}
  local seen = {}

  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if not ok or not parser then
    return langs
  end

  -- Parse to ensure injections are loaded
  pcall(parser.parse, parser)

  parser:for_each_tree(function(_, language_tree)
    local lang = language_tree:lang()
    if not seen[lang] then
      seen[lang] = true
      table.insert(langs, lang)
    end
  end)

  return langs
end

--- Check if a language is supported for conceal
--- @param lang string
--- @return boolean
local function is_supported_lang(lang)
  return lang == "latex" or lang == "typst"
end

--- Register directives if not already done
local directives_registered = false
local function ensure_directives_registered()
  if directives_registered then
    return
  end
  query_utils.load_queries()
  directives_registered = true
end

--- Attach conceal rendering to a buffer
--- This takes over the treesitter highlight pipeline for supported languages
--- @param buf integer Buffer number (0 for current)
--- @param filetype string? Filetype (defaults to buffer's filetype)
function M.attach(buf, filetype)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  filetype = filetype or vim.bo[buf].filetype

  -- Skip if already attached
  if render.is_attached(buf) then
    return
  end

  -- Ensure directives are registered
  ensure_directives_registered()

  -- Set conceal options
  vim.api.nvim_set_option_value("conceallevel", 2, { win = 0 })
  vim.api.nvim_set_option_value("concealcursor", "nc", { win = 0 })

  -- Detect all languages in buffer (including injections)
  local all_langs = detect_buffer_languages(buf)

  -- Fallback: if no parser available yet, use filetype mapping
  if #all_langs == 0 then
    local primary_lang = filetype_to_lang(filetype)
    all_langs = { primary_lang }
  end

  -- For each supported language, override its highlights query
  for _, lang in ipairs(all_langs) do
    if is_supported_lang(lang) then
      local query_string = build_query_string(lang, buf)
      -- Override the highlights query for this language
      vim.treesitter.query.set(lang, "highlights", query_string)
    end
  end

  -- Register with render to track attachment state
  -- We pass a dummy query since highlights are set via vim.treesitter.query.set
  for _, lang in ipairs(all_langs) do
    if is_supported_lang(lang) then
      render.register_query(buf, lang, "")
    end
  end

  -- For tex files, setup auto-refresh on save (preamble changes)
  if filetype == "tex" then
    vim.api.nvim_create_autocmd("BufWritePost", {
      group = augroup,
      buffer = buf,
      callback = function()
        M.refresh(buf)
      end,
    })
  end
end

--- Refresh conceal for a buffer (re-parse preamble, re-register queries)
--- @param buf integer Buffer number (0 for current)
function M.refresh(buf)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end

  local filetype = vim.bo[buf].filetype

  -- Invalidate query cache to force reload
  for _, lang in ipairs({ "latex", "typst" }) do
    query_content_cache[lang] = nil
  end

  -- Re-detect languages
  local all_langs = detect_buffer_languages(buf)
  if #all_langs == 0 then
    all_langs = { filetype_to_lang(filetype) }
  end

  -- Re-set highlights queries for supported languages
  for _, lang in ipairs(all_langs) do
    if is_supported_lang(lang) then
      local query_string = build_query_string(lang, buf)
      vim.treesitter.query.set(lang, "highlights", query_string)
    end
  end

  -- Restart treesitter to apply new queries
  vim.treesitter.stop(buf)
  vim.schedule(function()
    vim.treesitter.start(buf)
  end)
end

--- Detach conceal from a buffer
--- @param buf integer Buffer number (0 for current)
function M.detach(buf)
  if buf == 0 then
    buf = vim.api.nvim_get_current_buf()
  end
  render.clear_buffer(buf)
end

--- Setup loader with configuration
--- @param opts LoaderConfig?
function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  -- Setup highlights
  for name, val in pairs(config.highlights) do
    vim.api.nvim_set_hl(config.ns_id, name, val)
  end

  -- Setup and enable render engine
  render.setup()
  render.enable()
end

--- Invalidate query cache (useful when query files change)
--- @param lang string? Language to invalidate (nil for all)
function M.invalidate_cache(lang)
  if lang then
    query_content_cache[lang] = nil
    query_files_cache[lang] = nil
  else
    query_content_cache = {}
    query_files_cache = {}
  end
end

--- Get supported languages
--- @return string[]
function M.get_supported_langs()
  return { "latex", "typst" }
end

--- Check if a filetype should have conceal enabled
--- @param filetype string
--- @return boolean
function M.is_supported_filetype(filetype)
  for _, ft in ipairs(config.ft) do
    if ft == filetype then
      return true
    end
  end
  return false
end

return M
