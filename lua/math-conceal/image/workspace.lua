--- Per-buffer filesystem workspace helpers for compiler-service sidecars.

local M = {}

local function stable_hash(text)
  local ok, digest = pcall(vim.fn.sha256, text or "")
  if ok and type(digest) == "string" and digest ~= "" then
    return digest:sub(1, 12)
  end

  local h = 0
  text = text or ""
  for i = 1, #text do
    h = (h * 31 + text:byte(i)) % 0xFFFFFFFF
  end
  return string.format("%08x", h)
end

local function buffer_slug(bufnr)
  local buf_file = vim.api.nvim_buf_get_name(bufnr)
  local base
  if buf_file == nil or buf_file == "" then
    base = "unnamed"
    buf_file = tostring(bufnr)
  else
    base = vim.fn.fnamemodify(buf_file, ":t:r")
  end
  base = base:gsub("[^%w%-_]", "_")
  if #base == 0 then
    base = "buffer"
  elseif #base > 40 then
    base = base:sub(1, 40)
  end
  return base .. "-" .. stable_hash(buf_file)
end

--- @param bufnr integer
--- @param source_root string|nil
--- @return table
function M.for_buffer(bufnr, source_root)
  local base_dir
  if source_root ~= nil and source_root ~= "" then
    base_dir = source_root .. "/.typst-concealer"
  else
    base_dir = vim.fn.stdpath("cache") .. "/typst-concealer"
  end

  local root = base_dir .. "/" .. buffer_slug(bufnr)
  local full = root .. "/full"
  local slots = full .. "/slots"
  local outputs = full .. "/outputs"
  local preview = root .. "/preview"
  vim.fn.mkdir(slots, "p")
  vim.fn.mkdir(outputs, "p")
  vim.fn.mkdir(preview, "p")

  return {
    root = root,
    full_dir = full,
    main_path = full .. "/main.typ",
    context_path = full .. "/context.typ",
    slots_dir = slots,
    outputs_dir = outputs,
    preview_dir = preview,
  }
end

--- @param slot_id string|number
--- @return integer
function M.slot_number(slot_id)
  if type(slot_id) == "number" then
    return slot_id
  end
  return tonumber(tostring(slot_id):match("(%d+)$")) or 0
end

--- @param workspace table
--- @param slot_id string|number
--- @return string
function M.slot_path(workspace, slot_id)
  return ("%s/slot-%06d.typ"):format(workspace.slots_dir, M.slot_number(slot_id))
end

return M
