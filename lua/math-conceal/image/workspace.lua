local M = {}

local session_base_dir = nil
local owned_session_dirs = {}

local function stable_hash(text)
  return vim.fn.sha256(text or ""):sub(1, 12)
end

local function base_dir()
  if session_base_dir == nil then
    session_base_dir = table.concat({
      vim.fn.stdpath("cache"),
      "math-conceal.nvim",
      "image",
      tostring(vim.fn.getpid()),
    }, "/")
  end
  return session_base_dir
end

local function buffer_slug(bufnr)
  local path = vim.api.nvim_buf_get_name(bufnr)
  local base = path ~= "" and vim.fn.fnamemodify(path, ":t:r") or "unnamed"
  base = base:gsub("[^%w%-_]", "_")
  if base == "" then
    base = "buffer"
  elseif #base > 40 then
    base = base:sub(1, 40)
  end
  return base .. "-" .. stable_hash(path ~= "" and path or tostring(bufnr))
end

local function safe_unlink(path)
  if vim.uv.fs_stat(path) ~= nil then
    pcall(vim.uv.fs_unlink, path)
  end
end

local function remove_tree(dir)
  local scan = vim.uv.fs_scandir(dir)
  if scan ~= nil then
    while true do
      local name, typ = vim.uv.fs_scandir_next(scan)
      if name == nil then
        break
      end
      local path = dir .. "/" .. name
      if typ == "directory" then
        remove_tree(path)
        pcall(vim.uv.fs_rmdir, path)
      else
        safe_unlink(path)
      end
    end
  end
  pcall(vim.uv.fs_rmdir, dir)
end

function M.base_dir()
  return base_dir()
end

function M.cleanup_all()
  remove_tree(base_dir())
  for dir in pairs(owned_session_dirs) do
    remove_tree(dir)
  end
  owned_session_dirs = {}
end

-- Optional project-local workspace keeps Typst's root stable for /asset paths.
-- Only the generated per-process child is owned/removed by this module.
function M.for_buffer(bufnr, directory)
  if type(directory) == "function" then
    directory = directory(bufnr)
  end
  local base = base_dir()
  if directory ~= nil then
    assert(type(directory) == "string" and directory ~= "", "workspace_dir must be a directory")
    base = vim.fs.normalize(vim.fn.fnamemodify(directory, ":p")) .. "/" .. tostring(vim.fn.getpid())
    owned_session_dirs[base] = true
  end
  local root = base .. "/" .. buffer_slug(bufnr)
  local full = root .. "/full"
  local outputs = full .. "/outputs"
  vim.fn.mkdir(outputs, "p")
  return {
    root = root,
    full_dir = full,
    main_path = full .. "/main.typ",
    context_path = full .. "/context.typ",
    outputs_dir = outputs,
  }
end

return M
