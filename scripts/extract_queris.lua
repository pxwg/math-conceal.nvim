#!/usr/bin/env lua

local lfs = require("lfs")

local function find_queries_dir()
  for _, candidate in ipairs({ "queries", "queries_config", "../queries", "../queries_config" }) do
    local attr = lfs.attributes(candidate)
    if attr and attr.mode == "directory" then
      return candidate
    end
  end
  error("No queries directory found!")
end

local function ensure_dir(path)
  local attr = lfs.attributes(path)
  if not attr then
    assert(os.execute("mkdir -p " .. path))
  end
end

local function basename(path)
  return path:match("([^/]+)$")
end

local function name_from_filename(filename)
  return filename:gsub("%.scm$", "")
end

local function process_dir(subdir, out_dir)
  local name = basename(subdir)
  local out = {}
  table.insert(out, "local M = {}")
  table.insert(out, "")

  for entry in lfs.dir(subdir) do
    if entry:match("%.scm$") then
      local src_path = subdir .. "/" .. entry
      local file = io.open(src_path, "r")
      local content = file:read("*a")
      file:close()
      local key = name_from_filename(entry)
      table.insert(out, string.format("M.%s = [[", key))
      table.insert(out, content)
      table.insert(out, "]]")
      table.insert(out, "")
    end
  end

  table.insert(out, "return M")
  ensure_dir(out_dir)
  local out_file = io.open(out_dir .. "/" .. name .. ".lua", "w")
  out_file:write(table.concat(out, "\n"))
  out_file:close()
end

-- Main
local src_root = find_queries_dir()
local dst_root = "dir"
ensure_dir(dst_root)
for entry in lfs.dir(src_root) do
  if entry ~= "." and entry ~= ".." then
    local subdir = src_root .. "/" .. entry
    local attr = lfs.attributes(subdir)
    if attr and attr.mode == "directory" then
      process_dir(subdir, dst_root)
    end
  end
end
print("Done.")
