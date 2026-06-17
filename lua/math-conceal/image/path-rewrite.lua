local M = {}

local cache = {}

local function normalize(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
end

local function path_exists(path)
  return path ~= nil and vim.uv.fs_stat(path) ~= nil
end

local function starts_with(path, base)
  return path == base or path:sub(1, #base + 1) == base .. "/"
end

local function remote_url(path)
  if type(path) ~= "string" then
    return false
  end
  local scheme = path:match("^([%a][%w+%.%-]*)://")
  return scheme ~= nil and scheme:lower() ~= "file"
end

function M.common_ancestor(a, b)
  a = normalize(a)
  b = normalize(b)
  if a == nil or b == nil then
    return a or b
  end

  local aa, bb, out = {}, {}, {}
  for part in a:gmatch("[^/]+") do
    aa[#aa + 1] = part
  end
  for part in b:gmatch("[^/]+") do
    bb[#bb + 1] = part
  end
  for idx = 1, math.min(#aa, #bb) do
    if aa[idx] ~= bb[idx] then
      break
    end
    out[#out + 1] = aa[idx]
  end
  return #out > 0 and "/" .. table.concat(out, "/") or "/"
end

function M.get_project_root(buf_dir)
  buf_dir = normalize(buf_dir)
  if buf_dir == nil then
    return nil
  end
  if cache[buf_dir] ~= nil then
    return cache[buf_dir]
  end

  local dir = buf_dir
  while dir ~= nil and dir ~= "" do
    for _, marker in ipairs({ "typst.toml", ".git", ".jj", ".hg" }) do
      if vim.uv.fs_stat(dir .. "/" .. marker) ~= nil then
        cache[buf_dir] = dir
        return dir
      end
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end

  cache[buf_dir] = buf_dir
  return buf_dir
end

function M.resolve_to_absolute(raw_path, buf_dir, source_root)
  if raw_path == nil or raw_path == "" then
    return nil, nil
  end
  if raw_path:sub(1, 1) == "@" then
    return raw_path, "package"
  end
  if remote_url(raw_path) then
    return raw_path, "url"
  end
  if raw_path:sub(1, 1) ~= "/" then
    return normalize((buf_dir or "") .. "/" .. raw_path), "fs"
  end

  local source_candidate = source_root and normalize(source_root .. raw_path) or nil
  if path_exists(source_candidate) then
    return source_candidate, "fs"
  end
  local fs_candidate = normalize(raw_path)
  if path_exists(fs_candidate) then
    return fs_candidate, "fs"
  end
  return source_candidate or fs_candidate, "fs"
end

function M.encode_root_relative(abs_path, effective_root)
  local path = normalize(abs_path)
  local root = normalize(effective_root)
  if path == nil or root == nil then
    return abs_path
  end
  if not starts_with(path, root) then
    return path
  end
  if path == root then
    return "/"
  end
  return "/" .. path:sub(#root + 2)
end

function M.rewrite_path(raw_path, opts)
  local abs, kind = M.resolve_to_absolute(raw_path, opts.buf_dir, opts.source_root)
  if kind == "package" or kind == "url" then
    return raw_path
  end
  if kind == "fs" and abs ~= nil then
    return M.encode_root_relative(abs, opts.effective_root)
  end
  return raw_path
end

function M.rewrite_paths(text, opts)
  if type(text) ~= "string" then
    return text
  end

  local function rw(path)
    return M.rewrite_path(path, opts)
  end
  local function sub(prefix, path, suffix)
    return prefix .. rw(path) .. suffix
  end

  for _, kw in ipairs({ "import", "include" }) do
    text = text:gsub("(#" .. kw .. '%s+")([^"]*)(")', sub)
    text = text:gsub("(#" .. kw .. "%s*')" .. "([^']*)" .. "(')", sub)
  end

  for _, fn in ipairs({ "image", "json", "toml", "yaml", "read", "csv", "bibliography" }) do
    text = text:gsub("(" .. fn .. '%s*%(%s*")([^"]*)(")', sub)
    text = text:gsub("(" .. fn .. "%s*%(%s*')" .. "([^']*)" .. "(')", sub)
  end

  text = text:gsub('(style%s*:%s*")([^"]*)(")', sub)
  text = text:gsub("(style%s*:%s*')" .. "([^']*)" .. "(')", sub)
  text = text:gsub('(path%s*:%s*")([^"]*)(")', sub)
  text = text:gsub("(path%s*:%s*')" .. "([^']*)" .. "(')", sub)

  return text
end

return M
