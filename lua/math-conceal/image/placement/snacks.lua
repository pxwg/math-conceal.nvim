local M = {}

local state_by_buf = {}
local notified = {}
local conceal_ns = vim.api.nvim_create_namespace("math-conceal.image.placement.snacks.conceal")
local augroup = vim.api.nvim_create_augroup("math-conceal.image.placement.snacks", { clear = true })

local function table_keys(tbl)
  local keys = {}
  for key in pairs(tbl or {}) do
    keys[#keys + 1] = key
  end
  return keys
end

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function notify_once(key, message, level)
  if notified[key] then
    return
  end
  notified[key] = true
  vim.schedule(function()
    vim.notify("[math-conceal.image] " .. message, level or vim.log.levels.ERROR)
  end)
end

local function schedule_repaint(bufnr)
  local s = state_by_buf[bufnr]
  if s == nil or s.repaint_scheduled then
    return
  end
  s.repaint_scheduled = true
  vim.defer_fn(function()
    local current = state_by_buf[bufnr]
    if current ~= nil then
      current.repaint_scheduled = false
      M.repaint(bufnr)
    end
  end, 20)
end

local function schedule_geometry_dirty(bufnr)
  local s = state_by_buf[bufnr]
  if s == nil then
    return
  end
  s.edit_epoch = (s.edit_epoch or 0) + 1
  s.geometry_dirty = true
end

local function ensure_scroll_repaint(bufnr, s)
  if s.scroll_repaint_autocmd == true then
    return
  end
  s.scroll_repaint_autocmd = true
  pcall(vim.api.nvim_create_autocmd, { "WinScrolled", "BufWinEnter" }, {
    group = augroup,
    buffer = bufnr,
    callback = function()
      schedule_repaint(bufnr)
    end,
  })
end

local function ensure_edit_invalidate(bufnr, s)
  if s.edit_invalidate_attached == true then
    return
  end
  s.edit_invalidate_attached = true
  pcall(vim.api.nvim_buf_attach, bufnr, false, {
    on_lines = function(_, changed_buf)
      schedule_geometry_dirty(changed_buf)
    end,
    on_detach = function()
      state_by_buf[bufnr] = nil
    end,
  })
end

local function state(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local s = state_by_buf[bufnr]
  if s == nil then
    s = { placements = {} }
    state_by_buf[bufnr] = s
  end
  s.placements = s.placements or {}
  ensure_scroll_repaint(bufnr, s)
  ensure_edit_invalidate(bufnr, s)
  return s
end

local function close_placement(placement)
  if placement ~= nil and type(placement.close) == "function" then
    pcall(placement.close, placement)
  end
end

local function hide_placement(placement)
  if placement ~= nil and type(placement.hide) == "function" then
    pcall(placement.hide, placement)
  end
end

local function show_placement(placement)
  if placement ~= nil and type(placement.show) == "function" then
    pcall(placement.show, placement)
  elseif placement ~= nil and type(placement.update) == "function" then
    pcall(placement.update, placement)
  end
end

local function delete_terminal_placement(placement)
  local ok_terminal, terminal = pcall(require, "snacks.image.terminal")
  if not ok_terminal or placement == nil or placement.img == nil or placement.img.id == nil or placement.id == nil then
    return
  end
  pcall(terminal.request, { a = "d", d = "i", i = placement.img.id, p = placement.id })
end

local function repaint_placement(placement)
  if placement == nil or placement.closed == true then
    return
  end
  -- Kitty unicode-placeholder placements can leave stale terminal images on
  -- scroll when their virtual-text placeholders move out of the viewport,
  -- especially for wrapped inline math. Delete only the terminal placement,
  -- keep Snacks' extmark lifecycle intact, and force Snacks to re-emit the
  -- placement request against the currently visible placeholder grid.
  delete_terminal_placement(placement)
  placement._state = nil
  if type(placement.update) == "function" then
    pcall(placement.update, placement)
  end
end

local function patch_preserve_size_state(placement)
  if placement == nil or placement._math_conceal_preserve_size_patched == true then
    return
  end
  if type(placement.state) ~= "function" then
    return
  end
  local base_state = placement.state
  placement._math_conceal_preserve_size_patched = true
  placement.state = function(self)
    local placement_state = base_state(self)
    local opts = self.opts or {}
    if opts.math_conceal_preserve_size == true and placement_state ~= nil and placement_state.loc ~= nil then
      if opts.width ~= nil then
        placement_state.loc.width = math.max(1, math.floor(tonumber(opts.width) or placement_state.loc.width or 1))
      end
      if opts.height ~= nil then
        placement_state.loc.height = math.max(1, math.floor(tonumber(opts.height) or placement_state.loc.height or 1))
      end
    end
    return placement_state
  end
end

local function update_placement(placement, opts)
  if placement == nil then
    return
  end
  placement.opts = placement.opts or {}
  for key, value in pairs(opts or {}) do
    placement.opts[key] = value
  end
  patch_preserve_size_state(placement)
  placement._state = nil
  if type(placement.update) == "function" then
    pcall(placement.update, placement)
  end
end

local function asset_key(asset)
  if asset == nil then
    return nil
  end
  return asset.render_key or asset.path
end

function M.available()
  local ok_snacks = pcall(require, "snacks")
  if not ok_snacks and _G.Snacks == nil then
    return false, "snacks.nvim is required for graphical image placement"
  end
  local ok_placement, placement = pcall(require, "snacks.image.placement")
  if not ok_placement or type(placement) ~= "table" or type(placement.new) ~= "function" then
    return false, "snacks.nvim image placement module is required for graphical image placement"
  end
  return true, nil, placement
end

function M.conflict(bufnr)
  bufnr = normalize_bufnr(bufnr)
  if vim.b[bufnr].snacks_image_attached == true then
    return true,
      "Snacks document image rendering is already attached to this buffer; disable Snacks image.doc for this filetype before enabling math-conceal graphical images"
  end
  return false, nil
end

function M.assert_ready(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local ok, err = M.available()
  if not ok then
    notify_once("missing-snacks", err)
    return false
  end
  local has_conflict, conflict = M.conflict(bufnr)
  if has_conflict then
    notify_once("snacks-doc-conflict:" .. tostring(bufnr), conflict)
    return false
  end
  return true
end

local function placement_opts(intent, on_update)
  return {
    pos = intent.pos,
    range = intent.placement_range or intent.range,
    inline = true,
    conceal = true,
    width = intent.width,
    min_width = intent.min_width,
    max_width = intent.max_width,
    height = intent.height,
    min_height = intent.min_height,
    max_height = intent.max_height,
    type = intent.type or "math",
    auto_resize = intent.auto_resize ~= false,
    math_conceal_preserve_size = intent.preserve_size == true,
    on_update = on_update,
  }
end

local function same_range(a, b)
  if a == nil or b == nil then
    return a == b
  end
  for i = 1, 4 do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

local function clear_source_conceal(bufnr, record)
  for _, id in ipairs(record.source_conceal_ids or {}) do
    pcall(vim.api.nvim_buf_del_extmark, bufnr, conceal_ns, id)
  end
  record.source_conceal_ids = nil
end

local function line_len(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  return #line
end

local function render_source_conceal(bufnr, record, intent)
  clear_source_conceal(bufnr, record)
  if
    intent == nil
    or intent.range == nil
    or intent.placement_range == nil
    or same_range(intent.range, intent.placement_range)
  then
    return
  end

  local range = intent.range
  local start_row = math.max(0, (tonumber(range[1]) or 1) - 1)
  local end_row = math.max(start_row, (tonumber(range[3]) or range[1] or 1) - 1)
  local ids = {}
  local can_collapse_tail = intent.collapse_source_lines == true and vim.fn.has("nvim-0.11.4") == 1
  local conceal_until = can_collapse_tail and start_row or end_row
  for row = start_row, conceal_until do
    local col = row == start_row and math.max(0, tonumber(range[2]) or 0) or 0
    local end_col = row == end_row and math.max(0, tonumber(range[4]) or 0) or line_len(bufnr, row)
    if end_col > col then
      ids[#ids + 1] = vim.api.nvim_buf_set_extmark(bufnr, conceal_ns, row, col, {
        end_row = row,
        end_col = end_col,
        conceal = "",
        priority = 4095,
        invalidate = true,
      })
    end
  end
  if can_collapse_tail and end_row > start_row then
    ids[#ids + 1] = vim.api.nvim_buf_set_extmark(bufnr, conceal_ns, start_row + 1, 0, {
      end_row = end_row,
      conceal_lines = "",
      priority = 4095,
      invalidate = true,
    })
  end
  record.source_conceal_ids = ids
end

local function promote_pending(bufnr, key, pending_token)
  local s = state_by_buf[bufnr]
  local record = s and s.placements and s.placements[key] or nil
  if record == nil or record.pending_token ~= pending_token or record.pending == nil then
    return
  end
  local old = record.active
  record.active = record.pending
  record.active_key = record.pending_key
  record.pending = nil
  record.pending_key = nil
  record.pending_token = nil
  if record.hidden then
    hide_placement(record.active)
  end
  close_placement(old)
end

local function create_pending(bufnr, key, intent, record, placement_mod)
  local token = {}
  record.pending_token = token
  local opts = placement_opts(intent, function()
    promote_pending(bufnr, key, token)
  end)
  local ok, placement = pcall(placement_mod.new, bufnr, intent.asset.path, opts)
  if not ok or placement == nil then
    record.pending = nil
    record.pending_key = nil
    record.pending_token = nil
    notify_once(
      "placement-create:" .. tostring(bufnr),
      "failed to create Snacks image placement: " .. tostring(placement)
    )
    return false
  end
  patch_preserve_size_state(placement)
  record.pending = placement
  record.pending_key = asset_key(intent.asset)
  if record.hidden then
    hide_placement(record.pending)
  end
  return true
end

local function show_intent(bufnr, key, intent, placement_mod)
  local s = state(bufnr)
  local record = s.placements[key]
  if record == nil then
    record = { hidden = false }
    s.placements[key] = record
  end
  record.intent = intent
  record.hidden = false
  render_source_conceal(bufnr, record, intent)

  local key_now = asset_key(intent.asset)
  local opts = placement_opts(intent)

  if record.active ~= nil and record.active_key == key_now then
    update_placement(record.active, opts)
    close_placement(record.pending)
    record.pending = nil
    record.pending_key = nil
    record.pending_token = nil
    show_placement(record.active)
    return
  end

  if record.pending ~= nil and record.pending_key == key_now then
    update_placement(record.pending, opts)
    show_placement(record.pending)
    show_placement(record.active)
    return
  end

  close_placement(record.pending)
  record.pending = nil
  record.pending_key = nil
  record.pending_token = nil

  if record.active == nil then
    local token = {}
    record.pending_token = token
    local first_opts = placement_opts(intent, function()
      promote_pending(bufnr, key, token)
    end)
    local ok, placement = pcall(placement_mod.new, bufnr, intent.asset.path, first_opts)
    if not ok or placement == nil then
      record.pending_token = nil
      notify_once(
        "placement-create:" .. tostring(bufnr),
        "failed to create Snacks image placement: " .. tostring(placement)
      )
      return
    end
    patch_preserve_size_state(placement)
    record.pending = placement
    record.pending_key = key_now
    show_placement(record.pending)
    return
  end

  create_pending(bufnr, key, intent, record, placement_mod)
  show_placement(record.active)
end

local function hide_key(bufnr, key)
  -- Snacks' hide() intentionally keeps placement extmarks alive. For multi-line
  -- concealed placements that can leave backend-owned conceal_lines in place,
  -- so a tracker-owned source reveal would still look collapsed. Use Snacks'
  -- close lifecycle for reveal and recreate the placement when display is safe.
  M.close_key(bufnr, key)
end

function M.close_key(bufnr, key)
  bufnr = normalize_bufnr(bufnr)
  local s = state_by_buf[bufnr]
  local record = s and s.placements and s.placements[key] or nil
  if record == nil then
    return
  end
  close_placement(record.active)
  close_placement(record.pending)
  clear_source_conceal(bufnr, record)
  s.placements[key] = nil
end

function M.repaint(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local s = state_by_buf[bufnr]
  if s == nil or s.geometry_dirty == true then
    return
  end
  for _, record in pairs(s.placements or {}) do
    repaint_placement(record.active)
    repaint_placement(record.pending)
  end
end

function M.invalidate(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local s = state_by_buf[bufnr]
  if s == nil then
    return
  end
  for _, key in ipairs(table_keys(s.placements or {})) do
    M.close_key(bufnr, key)
  end
end

function M.sync(bufnr, intents, opts)
  bufnr = normalize_bufnr(bufnr)
  opts = opts or {}
  if not vim.api.nvim_buf_is_valid(bufnr) then
    M.detach(bufnr)
    return false
  end
  local ok, _, placement_mod = M.available()
  if not ok then
    notify_once("missing-snacks", "snacks.nvim image placement module is required for graphical image placement")
    M.detach(bufnr)
    return false
  end
  local has_conflict, conflict = M.conflict(bufnr)
  if has_conflict then
    notify_once("snacks-doc-conflict:" .. tostring(bufnr), conflict)
    M.detach(bufnr)
    return false
  end

  local geometry_sync = opts.replace_all == true or opts.tracker_geometry_sync == true
  local existing_state = state_by_buf[bufnr]
  if existing_state ~= nil and existing_state.geometry_dirty == true and not geometry_sync then
    return true
  end

  local seen = {}
  for _, intent in ipairs(intents or {}) do
    local key = intent.key
    if key ~= nil then
      seen[key] = true
      if
        intent.action == "show"
        and intent.asset ~= nil
        and type(intent.asset.path) == "string"
        and intent.asset.path ~= ""
      then
        show_intent(bufnr, key, intent, placement_mod)
      elseif intent.action == "hide" then
        hide_key(bufnr, key)
      else
        M.close_key(bufnr, key)
      end
    end
  end

  local s = state_by_buf[bufnr]
  if opts.replace_all == true then
    for _, key in ipairs(table_keys(s and s.placements or {})) do
      if not seen[key] then
        M.close_key(bufnr, key)
      end
    end
  end
  if s ~= nil and geometry_sync then
    s.geometry_dirty = false
    s.pending_edit_ranges = nil
    s.last_sync_epoch = s.edit_epoch or 0
  end
  return true
end

function M.detach(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local s = state_by_buf[bufnr]
  if s == nil then
    return
  end
  for _, key in ipairs(table_keys(s.placements or {})) do
    M.close_key(bufnr, key)
  end
  state_by_buf[bufnr] = nil
end

function M._state(bufnr)
  return state_by_buf[normalize_bufnr(bufnr)]
end

return M
