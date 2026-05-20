--- Path rewriting utilities for math-conceal.image.
--- Resolve asset paths against the source/project root first, then encode them
--- for the effective Typst root used by the compiler service.
local M = {}

local state = require("math-conceal.image.state")
local project_root_cache = {}

local function normalize_path(path)
  if path == nil or path == "" then
    return nil
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
end

local function path_exists(path)
  return path ~= nil and vim.uv.fs_stat(path) ~= nil
end

local function is_remote_url(path)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local scheme = path:match("^([%a][%w+%.%-]*)://")
  return scheme ~= nil and scheme:lower() ~= "file"
end

local function starts_with_path(path, base)
  if path == nil or base == nil then
    return false
  end
  return path == base or path:sub(1, #base + 1) == (base .. "/")
end

local function get_cache_bucket(bufnr, opts)
  if bufnr == nil or bufnr <= 0 then
    return nil
  end
  local signature = table.concat({
    opts.buf_dir or "",
    opts.source_root or "",
    opts.effective_root or "",
  }, "\0")
  local by_buf = state.path_rewrite_cache[bufnr]
  if by_buf == nil then
    by_buf = {}
    state.path_rewrite_cache[bufnr] = by_buf
  end
  local bucket = by_buf[signature]
  if bucket == nil then
    bucket = {}
    by_buf[signature] = bucket
  end
  return bucket
end

--- Return the longest common ancestor directory of dir1 and dir2.
--- Both must be absolute paths. Returns "/" if they share only the root.
--- @param dir1 string
--- @param dir2 string
--- @return string
function M.common_ancestor(dir1, dir2)
  local function split(path)
    local parts = {}
    for part in path:gmatch("[^/]+") do
      parts[#parts + 1] = part
    end
    return parts
  end
  local p1 = split(dir1)
  local p2 = split(dir2)
  local shared = {}
  for i = 1, math.min(#p1, #p2) do
    if p1[i] == p2[i] then
      shared[#shared + 1] = p1[i]
    else
      break
    end
  end
  return #shared > 0 and ("/" .. table.concat(shared, "/")) or "/"
end

--- Walk upward from buf_dir to find the nearest Typst/project root marker.
--- Falls back to buf_dir if none is found.
--- @param buf_dir string
--- @return string
function M.get_project_root(buf_dir)
  if project_root_cache[buf_dir] ~= nil then
    return project_root_cache[buf_dir]
  end
  local dir = buf_dir
  while true do
    for _, marker in ipairs({ "typst.toml", ".git", ".jj", ".hg" }) do
      if vim.uv.fs_stat(dir .. "/" .. marker) ~= nil then
        project_root_cache[buf_dir] = dir
        return dir
      end
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end
  project_root_cache[buf_dir] = buf_dir
  return buf_dir
end

--- Resolve a raw Typst path string into a filesystem path when possible.
--- @param raw_path string
--- @param buf_dir string
--- @param source_root string
--- @return string|nil abs_fs_path
--- @return "package"|"fs"|nil kind
function M.resolve_to_absolute(raw_path, buf_dir, source_root)
  if raw_path == nil or raw_path == "" then
    return nil, nil
  end
  if raw_path:sub(1, 1) == "@" then
    return raw_path, "package"
  end
  if is_remote_url(raw_path) then
    return raw_path, "url"
  end

  if raw_path:sub(1, 1) ~= "/" then
    return normalize_path((buf_dir or "") .. "/" .. raw_path), "fs"
  end

  local fs_candidate = normalize_path(raw_path)
  local source_candidate = source_root and normalize_path(source_root .. raw_path) or nil
  if path_exists(source_candidate) then
    return source_candidate, "fs"
  end
  if path_exists(fs_candidate) then
    return fs_candidate, "fs"
  end
  if source_candidate ~= nil then
    return source_candidate, "fs"
  end
  return fs_candidate, "fs"
end

--- Encode a filesystem path for the effective Typst root.
--- Paths under the effective root are emitted as Typst root-relative strings.
--- @param abs_path string
--- @param effective_root string
--- @return string
function M.encode_root_relative(abs_path, effective_root)
  local normalized_abs = normalize_path(abs_path)
  local normalized_root = normalize_path(effective_root)
  if normalized_abs == nil or normalized_root == nil then
    return abs_path
  end
  if not starts_with_path(normalized_abs, normalized_root) then
    return normalized_abs
  end
  if normalized_abs == normalized_root then
    return "/"
  end
  return "/" .. normalized_abs:sub(#normalized_root + 2)
end

--- Rewrite one Typst path literal according to source/effective roots.
--- @param raw_path string
--- @param opts { bufnr?: integer, buf_dir: string, source_root: string, effective_root: string }
--- @return string
function M.rewrite_path(raw_path, opts)
  local bucket = get_cache_bucket(opts.bufnr, opts)
  if bucket ~= nil and bucket[raw_path] ~= nil then
    return bucket[raw_path]
  end

  local abs_path, kind = M.resolve_to_absolute(raw_path, opts.buf_dir, opts.source_root)
  local rewritten = raw_path
  if kind == "package" then
    rewritten = raw_path
  elseif kind == "url" then
    rewritten = raw_path
  elseif kind == "fs" and abs_path ~= nil then
    rewritten = M.encode_root_relative(abs_path, opts.effective_root)
  end

  if bucket ~= nil then
    bucket[raw_path] = rewritten
  end
  return rewritten
end

--- Rewrite all relevant path strings in a Typst text fragment.
--- Handles: #import, #include, image(), json(), toml(), yaml(), read(), csv(),
---          bibliography() first arg and style:/path: named args.
--- @param text string
--- @param opts { bufnr?: integer, buf_dir: string, source_root: string, effective_root: string }
--- @return string
function M.rewrite_paths(text, opts)
  if type(text) ~= "string" then
    return text
  end
  local bucket = get_cache_bucket(opts.bufnr, opts)
  local text_cache = bucket and (bucket.__text_rewrites or {}) or nil
  if bucket ~= nil and bucket.__text_rewrites == nil then
    bucket.__text_rewrites = text_cache
  end
  if text_cache ~= nil and text_cache[text] ~= nil then
    return text_cache[text]
  end

  local original_text = text

  local function rw(p)
    return M.rewrite_path(p, opts)
  end
  local function sub(a, p, b)
    return a .. rw(p) .. b
  end

  for _, kw in ipairs({ "import", "include" }) do
    text = text:gsub("(#" .. kw .. '%s+")([^"]*)(")', sub)
    text = text:gsub("(#" .. kw .. "%s+')" .. "([^']*)" .. "(')", sub)
  end

  local first_arg_fns = { "image", "json", "toml", "yaml", "read", "csv", "bibliography" }
  for _, fn in ipairs(first_arg_fns) do
    text = text:gsub("(" .. fn .. '%s*%(%s*")([^"]*)(")', sub)
    text = text:gsub("(" .. fn .. "%s*%(%s*')" .. "([^']*)" .. "(')", sub)
  end

  text = text:gsub('(style%s*:%s*")([^"]*)(")', sub)
  text = text:gsub("(style%s*:%s*')" .. "([^']*)" .. "(')", sub)
  text = text:gsub('(path%s*:%s*")([^"]*)(")', sub)
  text = text:gsub("(path%s*:%s*')" .. "([^']*)" .. "(')", sub)

  if text_cache ~= nil then
    text_cache[original_text] = text
  end
  return text
end

return M
