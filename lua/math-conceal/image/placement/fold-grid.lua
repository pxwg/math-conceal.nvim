local display = require("math-conceal.image.display")
local state = require("math-conceal.image.state")
local terminal = require("math-conceal.image.terminal")
local track_view = require("math-conceal.image.track-view")

local M = {}

local FOLD_PRIORITY = 230
local REDRAW_NS = vim.api.nvim_create_namespace("math-conceal.image.placement.redraw")

local OPTION_NAMES = {
  "foldenable",
  "foldmethod",
  "foldexpr",
  "foldtext",
  "foldminlines",
  "foldlevel",
  "foldcolumn",
  "fillchars",
  "winhighlight",
}

local placements_by_buf = {}
local surfaces_by_win = {}
local augroup_id = nil
local provider_attached = false
local refresh_batch_depth = 0
local dirty_surfaces = {}

local function normalize_bufnr(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

local function valid_buf(bufnr)
  return bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_win(winid)
  return winid ~= nil and vim.api.nvim_win_is_valid(winid)
end

local function delete_extmark(bufnr, id)
  if id ~= nil and valid_buf(bufnr) then
    pcall(vim.api.nvim_buf_del_extmark, bufnr, state.placement_ns, id)
  end
end

local function replace_option_map(current, replacements)
  local out = {}
  for part in tostring(current or ""):gmatch("[^,]+") do
    local key = part:match("^([^:]+):")
    if key and replacements[key] == nil then
      out[#out + 1] = part
    end
  end
  local keys = vim.tbl_keys(replacements)
  table.sort(keys)
  for _, key in ipairs(keys) do
    out[#out + 1] = key .. ":" .. replacements[key]
  end
  return table.concat(out, ",")
end

local function save_window_options(winid)
  local saved = {}
  for _, name in ipairs(OPTION_NAMES) do
    local ok, value = pcall(function()
      return vim.wo[winid][name]
    end)
    if ok then
      saved[name] = value
    end
  end
  return saved
end

local function restore_window_options(winid, saved)
  if not valid_win(winid) then
    return
  end
  for _, name in ipairs(OPTION_NAMES) do
    if saved[name] ~= nil then
      pcall(function()
        vim.wo[winid][name] = saved[name]
      end)
    end
  end
end

local function apply_window_options(winid)
  vim.wo[winid].foldenable = true
  vim.wo[winid].foldmethod = "expr"
  vim.wo[winid].foldexpr = "v:lua.MathConcealImagePlacementFoldExpr(v:lnum)"
  vim.wo[winid].foldtext = "v:lua.MathConcealImagePlacementFoldText()"
  vim.wo[winid].foldminlines = 0
  vim.wo[winid].foldlevel = 0
  vim.wo[winid].foldcolumn = "0"
  vim.wo[winid].fillchars = replace_option_map(vim.wo[winid].fillchars, { fold = " " })
  vim.wo[winid].winhighlight = replace_option_map(vim.wo[winid].winhighlight, {
    CursorLineFold = "Normal",
    FoldColumn = "Normal",
    Folded = "Normal",
  })
end

function M.layout_rows(source_start_row, source_end_row, image_rows)
  source_start_row = math.max(0, math.floor(tonumber(source_start_row) or 0))
  source_end_row = math.max(source_start_row, math.floor(tonumber(source_end_row) or source_start_row))
  image_rows = math.max(1, math.floor(tonumber(image_rows) or 1))

  local source_rows = source_end_row - source_start_row + 1
  local rows = {}
  if source_rows >= image_rows then
    for image_row = 1, image_rows - 1 do
      local row = source_start_row + image_row - 1
      rows[#rows + 1] = {
        image_row = image_row,
        source_start_row = row,
        source_end_row = row,
      }
    end
    rows[#rows + 1] = {
      image_row = image_rows,
      source_start_row = source_start_row + image_rows - 1,
      source_end_row = source_end_row,
    }
    return rows
  end

  for image_row = 1, source_rows do
    local row = source_start_row + image_row - 1
    rows[#rows + 1] = {
      image_row = image_row,
      source_start_row = row,
      source_end_row = row,
    }
  end

  local tail_rows = {}
  for image_row = source_rows + 1, image_rows do
    tail_rows[#tail_rows + 1] = image_row
  end
  rows[#rows].tail_image_rows = tail_rows
  return rows
end

local function with_prefix(line, prefix_cols)
  prefix_cols = math.max(0, math.floor(tonumber(prefix_cols) or 0))
  if prefix_cols == 0 then
    return line
  end
  local prefixed = { { string.rep(" ", prefix_cols), "" } }
  for _, chunk in ipairs(line) do
    prefixed[#prefixed + 1] = chunk
  end
  return prefixed
end

local function placeholder_line(placement, image_row)
  return {
    { display.placeholder_row(image_row, placement.cols), placement.hl },
  }
end

local function tail_virt_lines(placement)
  local tail = placement.tail_image_rows or {}
  if #tail == 0 then
    return nil
  end
  local out = {}
  for _, image_row in ipairs(tail) do
    out[#out + 1] = with_prefix(placeholder_line(placement, image_row), placement.prefix_cols)
  end
  return out
end

local function update_tail_extmark(placement)
  local tail = tail_virt_lines(placement)
  if tail == nil then
    delete_extmark(placement.bufnr, placement.tail_extmark_id)
    placement.tail_extmark_id = nil
    return true
  end

  local anchor = placement.tail_anchor_row
  if anchor == nil or not valid_buf(placement.bufnr) then
    return false
  end
  placement.tail_extmark_id = vim.api.nvim_buf_set_extmark(placement.bufnr, state.placement_ns, anchor, 0, {
    id = placement.tail_extmark_id,
    virt_lines = tail,
    virt_lines_above = true,
    virt_lines_overflow = "trunc",
    invalidate = true,
    priority = FOLD_PRIORITY,
  })
  return true
end

local function refresh_placement_geometry(placement)
  if placement == nil or placement.closed then
    return false
  end

  local view = track_view.for_ref(placement.ref, { require_valid = true })
  if view == nil then
    return false
  end

  local rows = M.layout_rows(view.row, view.end_row, placement.rows)
  if #rows == 0 then
    return false
  end

  placement.prefix_cols = display.block_left_pad_cols(placement.bufnr, view, placement.cols)
  placement.entries = rows
  placement.tail_image_rows = rows[#rows].tail_image_rows or {}
  if #placement.tail_image_rows > 0 then
    local tail_anchor = view.end_row + 1
    if tail_anchor >= vim.api.nvim_buf_line_count(placement.bufnr) then
      return false
    end
    placement.tail_anchor_row = tail_anchor
  else
    placement.tail_anchor_row = nil
  end
  return update_tail_extmark(placement)
end

local function row_list_signature(rows)
  local parts = {}
  for _, row in ipairs(rows or {}) do
    parts[#parts + 1] = tostring(row)
  end
  return table.concat(parts, ",")
end

local function placement_geometry_signature(placement)
  if placement == nil then
    return ""
  end

  local parts = {
    tostring(placement.prefix_cols or ""),
    tostring(placement.tail_anchor_row or ""),
    row_list_signature(placement.tail_image_rows),
  }
  for _, entry in ipairs(placement.entries or {}) do
    parts[#parts + 1] = table.concat({
      tostring(entry.image_row or ""),
      tostring(entry.source_start_row or ""),
      tostring(entry.source_end_row or ""),
      row_list_signature(entry.tail_image_rows),
    }, ":")
  end
  return table.concat(parts, "|")
end

local function close_placement(placement)
  if placement == nil or placement.closed then
    return
  end
  placement.closed = true
  delete_extmark(placement.bufnr, placement.tail_extmark_id)
  placement.tail_extmark_id = nil
  terminal.delete_placement(placement.image_id, placement.placement_id)
end

local function make_placement(bufnr, intent)
  local asset = intent and intent.asset or nil
  if asset == nil or asset.image_id == nil then
    return nil
  end

  local placement_id = state.allocate_placement_id(bufnr)
  local placement = {
    bufnr = bufnr,
    key = intent.key,
    ref = vim.deepcopy(intent.ref),
    image_id = asset.image_id,
    placement_id = placement_id,
    cols = math.max(1, math.floor(tonumber(asset.cols) or 1)),
    rows = math.max(1, math.floor(tonumber(asset.rows) or 1)),
    render_key = asset.render_key,
    hl = state.placement_hl_group(asset.image_id, placement_id),
    entries = {},
    tail_image_rows = {},
  }

  if not refresh_placement_geometry(placement) then
    close_placement(placement)
    return nil
  end
  if
    not terminal.place_image(placement.image_id, placement.placement_id, placement.cols, placement.rows, { C = 1 })
  then
    close_placement(placement)
    return nil
  end
  return placement
end

local function buf_records(bufnr)
  bufnr = normalize_bufnr(bufnr)
  placements_by_buf[bufnr] = placements_by_buf[bufnr] or {}
  return placements_by_buf[bufnr]
end

local function close_surface(surface)
  if surface == nil or surface.closed then
    return
  end
  surfaces_by_win[surface.win] = nil
  restore_window_options(surface.win, surface.saved_options or {})
  surface.closed = true
end

local function ensure_surface(winid, bufnr)
  if not valid_win(winid) or vim.api.nvim_win_get_buf(winid) ~= bufnr then
    return nil
  end

  local surface = surfaces_by_win[winid]
  if surface ~= nil and surface.bufnr ~= bufnr then
    close_surface(surface)
    surface = nil
  end
  if surface == nil then
    surface = {
      win = winid,
      bufnr = bufnr,
      saved_options = save_window_options(winid),
      placements = {},
      row_to_entry = {},
      fold_start_to_entry = {},
      viewport = nil,
    }
    surfaces_by_win[winid] = surface
  end
  return surface
end

local function surface_empty(surface)
  return next(surface.placements or {}) == nil
end

local refresh_surface
local schedule_surface

local function mark_surface_dirty(surface)
  if surface == nil or surface.closed then
    return
  end
  if refresh_batch_depth > 0 then
    dirty_surfaces[surface] = true
    return
  end
  refresh_surface(surface)
end

local function flush_dirty_surfaces()
  local surfaces = {}
  for surface in pairs(dirty_surfaces) do
    surfaces[#surfaces + 1] = surface
  end
  dirty_surfaces = {}

  for _, surface in ipairs(surfaces) do
    refresh_surface(surface)
  end
end

local function with_surface_refresh_batch(fn)
  refresh_batch_depth = refresh_batch_depth + 1
  local result = { pcall(fn) }
  refresh_batch_depth = refresh_batch_depth - 1
  if refresh_batch_depth == 0 then
    flush_dirty_surfaces()
  end
  if not result[1] then
    error(result[2])
  end
  return unpack(result, 2)
end

local function current_viewport(surface)
  if surface ~= nil and surface.viewport ~= nil then
    return surface.viewport.topline, surface.viewport.botline
  end
  if surface == nil or not valid_win(surface.win) then
    return nil, nil
  end

  local top, bot
  local ok = pcall(function()
    vim.api.nvim_win_call(surface.win, function()
      top = math.max(0, (tonumber(vim.fn.line("w0")) or 1) - 1)
      bot = math.max(top, (tonumber(vim.fn.line("w$")) or top + 1) - 1)
    end)
  end)
  if not ok then
    return nil, nil
  end
  return top, bot
end

local function placement_intersects_viewport(placement, top, bot)
  if top == nil or bot == nil then
    return true
  end

  top = math.max(0, top - 2)
  bot = bot + 2
  for _, entry in ipairs(placement.entries or {}) do
    local start_row = entry.source_start_row
    local end_row = entry.source_end_row or start_row
    if start_row ~= nil and end_row ~= nil and end_row >= top and start_row <= bot then
      return true
    end
  end

  local tail_anchor = placement.tail_anchor_row
  return tail_anchor ~= nil and tail_anchor >= top and tail_anchor <= bot
end

local function repaint_surface(surface)
  if surface == nil or surface.closed then
    return
  end
  if
    not valid_win(surface.win)
    or not valid_buf(surface.bufnr)
    or vim.api.nvim_win_get_buf(surface.win) ~= surface.bufnr
  then
    close_surface(surface)
    return
  end

  local top, bot = current_viewport(surface)
  for _, placement in pairs(surface.placements or {}) do
    if not placement.closed and placement_intersects_viewport(placement, top, bot) then
      terminal.place_image(placement.image_id, placement.placement_id, placement.cols, placement.rows, { C = 1 })
    end
  end
end

local function schedule_repaint(surface)
  if surface == nil or surface.closed or surface.repaint_scheduled then
    return
  end
  surface.repaint_scheduled = true
  vim.schedule(function()
    surface.repaint_scheduled = false
    repaint_surface(surface)
  end)
end

local function remove_key_from_surfaces(bufnr, key, opts)
  opts = opts or {}
  local surfaces = {}
  for _, surface in pairs(surfaces_by_win) do
    surfaces[#surfaces + 1] = surface
  end
  for _, surface in ipairs(surfaces) do
    if surface.bufnr == bufnr and surface.placements ~= nil then
      surface.placements[key] = nil
      surface.row_to_entry = {}
      surface.fold_start_to_entry = {}
      if surface_empty(surface) then
        close_surface(surface)
      elseif opts.refresh ~= false then
        mark_surface_dirty(surface)
      end
    end
  end
end

local function close_key_internal(bufnr, key, opts)
  opts = opts or {}
  local records = placements_by_buf[bufnr]
  local record = records and records[key] or nil
  if record ~= nil then
    close_placement(record.active)
    close_placement(record.pending)
    records[key] = nil
  end
  remove_key_from_surfaces(bufnr, key, opts)
end

local function rebuild_surface_rows(surface)
  if surface == nil or surface.closed or not valid_win(surface.win) then
    return false, {}
  end
  if not valid_buf(surface.bufnr) or vim.api.nvim_win_get_buf(surface.win) ~= surface.bufnr then
    return false, {}
  end

  local row_to_entry = {}
  local fold_start_to_entry = {}
  local invalid_keys = {}
  local tick = vim.api.nvim_buf_get_changedtick(surface.bufnr)

  for key, placement in pairs(surface.placements or {}) do
    if placement.closed or not refresh_placement_geometry(placement) then
      invalid_keys[key] = true
    else
      for _, entry in ipairs(placement.entries or {}) do
        local start_row = entry.source_start_row
        local end_row = entry.source_end_row
        if start_row == nil or end_row == nil or end_row < start_row then
          invalid_keys[key] = true
        else
          local wrapped = {
            placement = placement,
            entry = entry,
            start_row = start_row,
            end_row = end_row,
          }
          for row = start_row, end_row do
            local existing = row_to_entry[row]
            if existing ~= nil and existing.placement.key ~= key then
              invalid_keys[key] = true
              invalid_keys[existing.placement.key] = true
            end
            row_to_entry[row] = wrapped
          end
          fold_start_to_entry[start_row] = wrapped
        end
      end
    end
  end

  surface.row_to_entry = row_to_entry
  surface.fold_start_to_entry = fold_start_to_entry
  surface.row_cache_tick = tick
  return next(invalid_keys) == nil, invalid_keys
end

function refresh_surface(surface)
  if surface == nil or surface.closed then
    return
  end
  if
    not valid_win(surface.win)
    or not valid_buf(surface.bufnr)
    or vim.api.nvim_win_get_buf(surface.win) ~= surface.bufnr
  then
    close_surface(surface)
    return
  end

  apply_window_options(surface.win)
  local ok, invalid_keys = rebuild_surface_rows(surface)
  if not ok then
    for key in pairs(invalid_keys) do
      close_key_internal(surface.bufnr, key, { refresh = false })
    end
    if surface.closed or surface_empty(surface) then
      close_surface(surface)
      return
    end
    rebuild_surface_rows(surface)
  end

  pcall(function()
    vim.api.nvim_win_call(surface.win, function()
      local view = vim.fn.winsaveview()
      vim.cmd("silent! normal! zx")
      -- `zx` recomputes folds, but it also scrolls the cursor back into view.
      -- Mouse-wheel scrolling may intentionally leave the cursor off-screen.
      pcall(vim.fn.winrestview, view)
    end)
  end)

  repaint_surface(surface)
end

function schedule_surface(surface)
  if surface == nil or surface.closed or surface.update_scheduled then
    return
  end
  surface.update_scheduled = true
  vim.schedule(function()
    surface.update_scheduled = false
    refresh_surface(surface)
  end)
end

local function sync_surfaces_for_key(bufnr, key, placement)
  local wins = vim.fn.win_findbuf(bufnr)
  for _, winid in ipairs(wins) do
    local surface = ensure_surface(winid, bufnr)
    if surface ~= nil then
      surface.placements[key] = placement
      mark_surface_dirty(surface)
    end
  end
end

local function observe_viewport(winid, bufnr, topline, botline)
  local surface = surfaces_by_win[winid]
  if surface == nil or surface.closed or surface.bufnr ~= bufnr then
    return
  end

  local viewport = surface.viewport
  if viewport ~= nil and viewport.topline == topline and viewport.botline == botline then
    return
  end

  -- Viewport observations are redraw facts only. Placement rows remain
  -- materialized from TrackRef -> live TrackView in refresh_placement_geometry().
  surface.viewport = {
    topline = topline,
    botline = botline,
  }
  schedule_repaint(surface)
end

local function setup_decoration_provider()
  if provider_attached or type(vim.api.nvim_set_decoration_provider) ~= "function" then
    return
  end
  provider_attached = true
  vim.api.nvim_set_decoration_provider(REDRAW_NS, {
    on_win = function(_, winid, bufnr, topline, botline)
      observe_viewport(winid, bufnr, topline, botline)
      return false
    end,
  })
end

function M.sync(bufnr, intent)
  bufnr = normalize_bufnr(bufnr)
  if not valid_buf(bufnr) or intent == nil or intent.key == nil then
    return false
  end
  if intent.display_role ~= "block" or intent.block_role ~= "isolated" or intent.asset == nil then
    close_key_internal(bufnr, intent.key)
    return false
  end

  local records = buf_records(bufnr)
  local record = records[intent.key] or {}
  local active = record.active
  if active ~= nil and not active.closed and active.image_id == intent.asset.image_id then
    active.ref = vim.deepcopy(intent.ref)
    active.cols = math.max(1, math.floor(tonumber(intent.asset.cols) or 1))
    active.rows = math.max(1, math.floor(tonumber(intent.asset.rows) or 1))
    active.render_key = intent.asset.render_key
    if refresh_placement_geometry(active) then
      record.active = active
      records[intent.key] = record
      sync_surfaces_for_key(bufnr, intent.key, active)
      return true
    end
  end

  local pending = make_placement(bufnr, intent)
  if pending == nil then
    close_key_internal(bufnr, intent.key, { refresh = false })
    return false
  end

  record.pending = pending
  records[intent.key] = record
  sync_surfaces_for_key(bufnr, intent.key, pending)
  record.active = pending
  record.pending = nil
  close_placement(active)
  return true
end

function M.close_key(bufnr, key)
  bufnr = normalize_bufnr(bufnr)
  if key == nil then
    return
  end
  with_surface_refresh_batch(function()
    close_key_internal(bufnr, key)
  end)
end

function M.close_all(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local records = placements_by_buf[bufnr] or {}
  for key in pairs(vim.deepcopy(records)) do
    close_key_internal(bufnr, key, { refresh = false })
  end
  placements_by_buf[bufnr] = nil
  if valid_buf(bufnr) then
    pcall(vim.api.nvim_buf_clear_namespace, bufnr, state.placement_ns, 0, -1)
  end
end

function M.reconcile(bufnr, keep_keys)
  bufnr = normalize_bufnr(bufnr)
  keep_keys = keep_keys or {}
  local records = placements_by_buf[bufnr] or {}
  with_surface_refresh_batch(function()
    for key in pairs(vim.deepcopy(records)) do
      if keep_keys[key] ~= true then
        close_key_internal(bufnr, key)
      end
    end
  end)
end

function M.foldexpr(lnum)
  local winid = vim.api.nvim_get_current_win()
  local surface = surfaces_by_win[winid]
  if surface == nil or surface.closed or not valid_buf(surface.bufnr) then
    return 0
  end

  local tick = vim.api.nvim_buf_get_changedtick(surface.bufnr)
  if surface.row_cache_tick ~= tick then
    schedule_surface(surface)
    return 0
  end

  local row = lnum - 1
  local wrapped = surface.row_to_entry and surface.row_to_entry[row] or nil
  if wrapped == nil then
    return 0
  end
  if row == wrapped.start_row then
    return ">1"
  end
  return "1"
end

function M.foldtext()
  local winid = vim.api.nvim_get_current_win()
  local surface = surfaces_by_win[winid]
  if surface == nil or surface.closed then
    return vim.fn.foldtext()
  end

  local row = vim.v.foldstart - 1
  local wrapped = surface.fold_start_to_entry and surface.fold_start_to_entry[row] or nil
  if wrapped == nil then
    return vim.fn.foldtext()
  end

  local placement = wrapped.placement
  placement.hl = state.placement_hl_group(placement.image_id, placement.placement_id)
  return with_prefix(placeholder_line(placement, wrapped.entry.image_row), placement.prefix_cols)
end

function M.refresh_buf(bufnr)
  bufnr = normalize_bufnr(bufnr)
  local records = placements_by_buf[bufnr]
  if records == nil then
    return
  end
  with_surface_refresh_batch(function()
    for key, record in pairs(records) do
      if record.active ~= nil and not record.active.closed then
        sync_surfaces_for_key(bufnr, key, record.active)
      end
    end
  end)
end

function M.refresh_geometry(bufnr, opts)
  bufnr = normalize_bufnr(bufnr)
  opts = opts or {}
  local records = placements_by_buf[bufnr]
  if records == nil then
    return false
  end

  local only_keys = opts.keys
  local keys = {}
  for key in pairs(records) do
    if only_keys == nil or only_keys[key] == true then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)

  local changed = false
  with_surface_refresh_batch(function()
    for _, key in ipairs(keys) do
      local record = records[key]
      local active = record and record.active or nil
      if active ~= nil and not active.closed then
        local before = placement_geometry_signature(active)
        if not refresh_placement_geometry(active) then
          changed = true
          close_key_internal(bufnr, key, { refresh = false })
        else
          local after = placement_geometry_signature(active)
          if before ~= after then
            changed = true
            sync_surfaces_for_key(bufnr, key, active)
          end
        end
      end
    end
  end)
  return changed
end

function M.batch(fn)
  if type(fn) ~= "function" then
    return
  end
  return with_surface_refresh_batch(fn)
end

function M.refresh_all()
  local surfaces = {}
  for _, surface in pairs(surfaces_by_win) do
    surfaces[#surfaces + 1] = surface
  end
  for _, surface in ipairs(surfaces) do
    refresh_surface(surface)
  end
end

function M.setup()
  _G.MathConcealImagePlacementFoldExpr = function(lnum)
    return require("math-conceal.image.placement").foldexpr(lnum)
  end
  _G.MathConcealImagePlacementFoldText = function()
    return require("math-conceal.image.placement").foldtext()
  end

  if augroup_id ~= nil then
    return
  end
  augroup_id = vim.api.nvim_create_augroup("math-conceal.image.placement", { clear = true })
  setup_decoration_provider()
  vim.api.nvim_create_autocmd("WinResized", {
    group = augroup_id,
    desc = "refresh math-conceal fold-grid image placement geometry",
    callback = function()
      for _, surface in pairs(surfaces_by_win) do
        schedule_surface(surface)
      end
    end,
  })
  if not provider_attached then
    vim.api.nvim_create_autocmd("WinScrolled", {
      group = augroup_id,
      desc = "repaint math-conceal fold-grid image placements",
      callback = function()
        for _, surface in pairs(surfaces_by_win) do
          schedule_repaint(surface)
        end
      end,
    })
  end
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = augroup_id,
    desc = "attach math-conceal fold-grid placement surface",
    callback = function(ev)
      M.refresh_buf(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = augroup_id,
    desc = "drop math-conceal fold-grid placement window surface",
    callback = function(ev)
      local winid = tonumber(ev.match)
      if winid ~= nil then
        surfaces_by_win[winid] = nil
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = augroup_id,
    desc = "clear math-conceal fold-grid placements",
    callback = function(ev)
      M.close_all(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = augroup_id,
    desc = "refresh math-conceal fold-grid placement highlights",
    callback = function()
      M.refresh_all()
    end,
  })
end

function M._state()
  return {
    placements_by_buf = placements_by_buf,
    provider_attached = provider_attached,
    refresh_batch_depth = refresh_batch_depth,
    surfaces_by_win = surfaces_by_win,
  }
end

return M
