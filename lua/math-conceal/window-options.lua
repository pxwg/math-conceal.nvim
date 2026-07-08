-- Manage Neovim window-local conceal options for math-conceal-attached buffers.
-- Options are injected per window and restored when the window stops showing a
-- managed buffer, so plugin defaults do not leak into unrelated windows.
local M = {}

local config = {
  conceallevel = 2,
  concealcursor = "n",
}

local managed_buffers = {}
local win_state = {}
local inherited_saved_by_win = {}
local augroup = vim.api.nvim_create_augroup("math-conceal-window-options", { clear = true })
local autocmds_setup = false

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function normalize_config(opts, base)
  opts = opts or {}
  base = base or config
  local out = vim.tbl_extend("force", {}, base, opts)
  local conceallevel = tonumber(out.conceallevel)
  if conceallevel == nil or conceallevel < 0 or conceallevel > 3 then
    error("math-conceal: opt.conceallevel must be an integer from 0 to 3", 3)
  end

  out.conceallevel = math.floor(conceallevel)
  out.concealcursor = tostring(out.concealcursor or "")
  if out.concealcursor:find("[^nvic]") then
    error("math-conceal: opt.concealcursor can only contain 'n', 'v', 'i', and 'c'", 3)
  end

  return out
end

local function same_options(a, b)
  return a ~= nil
    and b ~= nil
    and tonumber(a.conceallevel) == tonumber(b.conceallevel)
    and tostring(a.concealcursor or "") == tostring(b.concealcursor or "")
end

local function window_options(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return nil
  end

  local ok, opts = pcall(function()
    return {
      conceallevel = vim.wo[winid].conceallevel,
      concealcursor = vim.wo[winid].concealcursor,
    }
  end)
  return ok and opts or nil
end

local function set_window_options(winid, opts)
  if not vim.api.nvim_win_is_valid(winid) or opts == nil then
    return false
  end

  local ok = pcall(function()
    vim.wo[winid].conceallevel = opts.conceallevel
    vim.wo[winid].concealcursor = opts.concealcursor
  end)
  return ok
end

local function window_buffer(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    return nil
  end

  local ok, bufnr = pcall(vim.api.nvim_win_get_buf, winid)
  return ok and bufnr or nil
end

local function is_managed(bufnr)
  local entry = managed_buffers[bufnr]
  return entry ~= nil and entry.owners ~= nil and next(entry.owners) ~= nil
end

local function windows_showing(bufnr)
  local wins = {}
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if window_buffer(winid) == bufnr then
      wins[#wins + 1] = winid
    end
  end
  return wins
end

local function inherited_saved_for(winid, bufnr, current)
  if not same_options(current, config) then
    return nil
  end

  for other_win, state in pairs(win_state) do
    if other_win ~= winid and state.bufnr == bufnr and same_options(state.applied, config) then
      return vim.deepcopy(state.saved)
    end
  end

  local inherited = inherited_saved_by_win[winid]
  if inherited ~= nil then
    return vim.deepcopy(inherited)
  end
end

local function remember_inherited_from_previous_window(winid)
  if win_state[winid] ~= nil or not vim.api.nvim_win_is_valid(winid) then
    return
  end

  local current = window_options(winid)
  if not same_options(current, config) then
    return
  end

  local previous = vim.fn.win_getid(vim.fn.winnr("#"))
  local previous_state = previous and win_state[previous] or nil
  if previous_state ~= nil and same_options(current, previous_state.applied) then
    inherited_saved_by_win[winid] = vim.deepcopy(previous_state.saved)
  end
end

local function apply_to_window(bufnr, winid)
  if window_buffer(winid) ~= bufnr or not is_managed(bufnr) then
    return false
  end

  local current = window_options(winid)
  if current == nil then
    return false
  end

  local state = win_state[winid]
  local saved = state and state.saved or inherited_saved_for(winid, bufnr, current) or current

  win_state[winid] = {
    bufnr = bufnr,
    saved = vim.deepcopy(saved),
    applied = vim.deepcopy(config),
  }
  inherited_saved_by_win[winid] = nil
  return set_window_options(winid, config)
end

local function restore_window(winid)
  if not vim.api.nvim_win_is_valid(winid) then
    win_state[winid] = nil
    inherited_saved_by_win[winid] = nil
    return false
  end

  local current = window_options(winid)
  local state = win_state[winid]
  if state ~= nil then
    if same_options(current, state.applied) then
      set_window_options(winid, state.saved)
    end
    win_state[winid] = nil
    inherited_saved_by_win[winid] = nil
    return true
  end

  local inherited = inherited_saved_by_win[winid]
  if inherited ~= nil and same_options(current, config) then
    set_window_options(winid, inherited)
  end
  inherited_saved_by_win[winid] = nil
  return inherited ~= nil
end

local function release_window_for_buffer(winid, bufnr)
  local current_buf = window_buffer(winid)
  if current_buf ~= nil and current_buf ~= bufnr and is_managed(current_buf) then
    return apply_to_window(current_buf, winid)
  end
  return restore_window(winid)
end

function M.sync_window(winid)
  winid = winid or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then
    win_state[winid] = nil
    inherited_saved_by_win[winid] = nil
    return false
  end

  if winid == vim.api.nvim_get_current_win() then
    remember_inherited_from_previous_window(winid)
  end

  local bufnr = window_buffer(winid)
  if bufnr ~= nil and is_managed(bufnr) then
    return apply_to_window(bufnr, winid)
  end

  return restore_window(winid)
end

local function ensure_autocmds()
  if autocmds_setup then
    return
  end
  autocmds_setup = true

  vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter", "WinEnter" }, {
    group = augroup,
    callback = function()
      M.sync_window(vim.api.nvim_get_current_win())
    end,
  })

  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = augroup,
    callback = function()
      local winid = vim.api.nvim_get_current_win()
      vim.schedule(function()
        M.sync_window(winid)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup,
    callback = function(args)
      local winid = tonumber(args.match)
      if winid ~= nil then
        win_state[winid] = nil
        inherited_saved_by_win[winid] = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufUnload", "BufDelete", "BufWipeout" }, {
    group = augroup,
    callback = function(args)
      M.detach(args.buf)
    end,
  })
end

function M.setup(opts)
  config = normalize_config(opts, config)
  ensure_autocmds()
  M.sync()
  return vim.deepcopy(config)
end

function M.get()
  return vim.deepcopy(config)
end

function M.attach(bufnr, owner)
  bufnr = normalize_bufnr(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  owner = owner or "default"
  managed_buffers[bufnr] = managed_buffers[bufnr] or { owners = {} }
  managed_buffers[bufnr].owners[owner] = true
  ensure_autocmds()
  M.sync(bufnr)
  return true
end

function M.detach(bufnr, owner)
  bufnr = normalize_bufnr(bufnr)
  local entry = managed_buffers[bufnr]
  if entry ~= nil then
    if owner == nil then
      managed_buffers[bufnr] = nil
    else
      entry.owners[owner] = nil
      if next(entry.owners) == nil then
        managed_buffers[bufnr] = nil
      end
    end
  end

  if not is_managed(bufnr) then
    for winid, state in pairs(vim.deepcopy(win_state)) do
      if state.bufnr == bufnr then
        release_window_for_buffer(winid, bufnr)
      end
    end
  end
end

function M.sync(bufnr)
  ensure_autocmds()
  if bufnr ~= nil then
    bufnr = normalize_bufnr(bufnr)
    if is_managed(bufnr) then
      for _, winid in ipairs(windows_showing(bufnr)) do
        apply_to_window(bufnr, winid)
      end
    else
      for winid, state in pairs(vim.deepcopy(win_state)) do
        if state.bufnr == bufnr then
          release_window_for_buffer(winid, bufnr)
        end
      end
    end
    return
  end

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    M.sync_window(winid)
  end

  for winid in pairs(win_state) do
    if not vim.api.nvim_win_is_valid(winid) then
      win_state[winid] = nil
      inherited_saved_by_win[winid] = nil
    end
  end
end

return M
