--- Render backend session management for math-conceal.image.
--- Manages Rust compiler-service processes and JSON-lines request/response
--- boundaries. Machine-owned full pages are emitted as overlay_page_ready
--- events.
---
--- TypstBackend interface
---   M.render_request_via_service(bufnr, request)    dispatch full overlay request to Rust service
---   M.render_formula_batch_via_service(bufnr, req)  dispatch formula overlay batch to Rust service
---   M.render_preview_tail_via_service(bufnr, item)  dispatch live preview request to Rust service
---   M.ensure_compiler_service(bufnr)                start/reuse the Rust compiler service
---   M.stop_compiler_service(bufnr)                  kill and clean up compiler service

local state = require("math-conceal.image.state")
local M = {}

--- Generate quickfix title for all render diagnostics belonging to a buffer.
--- @param bufnr integer
--- @return string
local function qf_title(bufnr)
  local name = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or nil
  if name == nil or name == "" then
    name = ("buf:%d"):format(bufnr)
  end
  return ("math-conceal.image: %s"):format(name)
end

--- Rebuild the global quickfix list for a buffer from active render diagnostics.
--- @param bufnr integer
local function rebuild_quickfix(bufnr)
  local bucket = state.render_diagnostics[bufnr] or {}
  local items = {}
  for _, kind in ipairs({ "full" }) do
    for _, item in ipairs(bucket[kind] or {}) do
      items[#items + 1] = item
    end
  end
  vim.schedule(function()
    vim.fn.setqflist({}, "r", {
      title = qf_title(bufnr),
      items = items,
    })
  end)
end

local function rebuild_full_diagnostics_bucket(bufnr)
  state.render_diagnostics[bufnr] = state.render_diagnostics[bufnr] or {}
  local bucket = state.render_diagnostics[bufnr]
  local items = {}
  for _, item in ipairs(bucket.full_base or {}) do
    items[#items + 1] = item
  end

  local node_ids = {}
  for node_id in pairs(bucket.formula_by_node or {}) do
    node_ids[#node_ids + 1] = node_id
  end
  table.sort(node_ids)
  for _, node_id in ipairs(node_ids) do
    for _, item in ipairs(bucket.formula_by_node[node_id] or {}) do
      items[#items + 1] = item
    end
  end

  bucket.full = items
end

--- Clear quickfix diagnostics for one session kind and rebuild the aggregated
--- buffer quickfix list.
--- @param bufnr integer
--- @param kind  'full'
local function clear_quickfix(bufnr, kind)
  state.render_diagnostics[bufnr] = state.render_diagnostics[bufnr] or {}
  if kind == "full" then
    state.render_diagnostics[bufnr].full_base = {}
    state.render_diagnostics[bufnr].formula_by_node = {}
    state.render_diagnostics[bufnr].full = {}
  else
    state.render_diagnostics[bufnr][kind] = {}
  end
  rebuild_quickfix(bufnr)
end

--- @param line_map table[]|nil
--- @param gen_lnum integer
--- @param gen_col integer
--- @return table|nil
local function map_generated_pos(line_map, gen_lnum, gen_col)
  if not line_map or #line_map == 0 then
    return nil
  end

  local function clamp(x, lo, hi)
    return math.max(lo, math.min(hi, x))
  end

  local function map_col(seg)
    local line_offset = gen_lnum - seg.gen_start
    local src_lnum = seg.src_start + line_offset

    if seg.src_start == seg.src_end and seg.gen_start == seg.gen_end then
      local delta = math.max(0, gen_col - seg.gen_start_col)
      local hi = math.max(seg.src_start_col, seg.src_end_col - 1)
      return src_lnum, clamp(seg.src_start_col + delta, seg.src_start_col, hi)
    end

    if gen_lnum == seg.gen_start then
      local delta = math.max(0, gen_col - seg.gen_start_col)
      return src_lnum, math.max(seg.src_start_col, seg.src_start_col + delta)
    end

    if gen_lnum == seg.gen_end then
      local hi = math.max(1, seg.src_end_col - 1)
      return src_lnum, clamp(gen_col, 1, hi)
    end

    return src_lnum, math.max(1, gen_col)
  end

  local nearest = nil
  for _, seg in ipairs(line_map) do
    if gen_lnum >= seg.gen_start and gen_lnum <= seg.gen_end then
      local src_lnum, src_col = map_col(seg)
      return {
        filename = vim.api.nvim_buf_get_name(seg.bufnr),
        lnum = src_lnum,
        col = src_col,
        exact = true,
        item_idx = seg.item_idx,
        src_start = seg.src_start,
        src_end = seg.src_end,
      }
    end
    if gen_lnum < seg.gen_start then
      nearest = seg
      break
    end
    nearest = seg
  end

  if nearest then
    return {
      filename = vim.api.nvim_buf_get_name(nearest.bufnr),
      lnum = nearest.src_start,
      col = nearest.src_start_col or 1,
      exact = false,
      item_idx = nearest.item_idx,
      src_start = nearest.src_start,
      src_end = nearest.src_end,
    }
  end
end

--- Normalize a path for comparison when possible.
--- @param path string
--- @return string
local function normalize_path(path)
  if path == nil or path == "" then
    return ""
  end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function normalize_root(path)
  if path == nil or path == "" then
    return nil
  end
  return normalize_path(path):gsub("/$", "")
end

--- Discover Typst package roots once from common environment variables and
--- platform defaults. The Rust service owns compilation, so Lua does not shell
--- out to a Typst CLI for discovery.
--- @return string[]
local function get_typst_package_roots()
  if state.typst_package_roots ~= nil then
    return state.typst_package_roots
  end

  local roots = {}
  local seen = {}
  local function add(path)
    if path == nil or path == "" then
      return
    end
    local norm = normalize_path(path)
    if norm == "" or seen[norm] then
      return
    end
    seen[norm] = true
    roots[#roots + 1] = norm
  end

  add(vim.env.TYPST_PACKAGE_CACHE_PATH)
  add(vim.env.TYPST_PACKAGE_PATH)
  add(vim.fn.expand("~/Library/Caches/typst/packages"))
  add(vim.fn.expand("~/Library/Application Support/typst/packages"))
  add(vim.fn.expand("~/.cache/typst/packages"))
  add(vim.fn.expand("~/.local/share/typst/packages"))

  state.typst_package_roots = roots
  return roots
end

--- Resolve a Typst-reported source path into a local filesystem path when
--- possible. Supports:
---   - absolute paths
---   - Typst package references like @preview/pkg:1.2.3/file.typ
---   - paths relative to the buffer directory / project root
--- @param session table
--- @param file string
--- @return string
local function resolve_typst_source_path(session, file)
  if file == nil or file == "" then
    return vim.api.nvim_buf_get_name(session.bufnr)
  end

  if file:sub(1, 1) == "/" then
    local path_rewrite = require("math-conceal.image.path-rewrite")
    return path_rewrite.resolve_to_absolute(file, session.buf_dir, session.source_root) or file
  end

  local namespace, pkg, ver, rest = file:match("^@([^/]+)/([^:]+):([^/]+)/(.*)$")
  if namespace and pkg and ver and rest then
    for _, base in ipairs(get_typst_package_roots()) do
      local path = table.concat({ base, namespace, pkg, ver, rest }, "/")
      if vim.uv.fs_stat(path) ~= nil then
        return path
      end
    end
  end

  local relative_candidates = {}
  if session.buf_dir then
    relative_candidates[#relative_candidates + 1] = session.buf_dir .. "/" .. file
  end
  if session.source_root then
    relative_candidates[#relative_candidates + 1] = session.source_root .. "/" .. file
  end
  if session.effective_root then
    relative_candidates[#relative_candidates + 1] = session.effective_root .. "/" .. file
  end

  for _, path in ipairs(relative_candidates) do
    if vim.uv.fs_stat(path) ~= nil then
      return path
    end
  end

  return file
end

--- @param path string
local function safe_unlink(path)
  if vim.uv.fs_stat(path) ~= nil then
    vim.uv.fs_unlink(path)
  end
end

--- Return true when a service PNG path is still referenced by a live overlay
--- or preview item. Service PNG names are content-addressed, so a stale
--- response can point at the same file as the currently visible render.
--- @param path string|nil
--- @return boolean
local function service_page_path_in_use(path)
  if type(path) ~= "string" or path == "" then
    return false
  end

  local target = normalize_path(path)
  local machine_state = state.machine_state
  for _, overlay in pairs((machine_state and machine_state.overlays) or {}) do
    if overlay.page_path ~= nil and overlay.status ~= "retired" and normalize_path(overlay.page_path) == target then
      return true
    end
  end

  for _, bstate in pairs(state.buffer_render_state or {}) do
    for _, item in ipairs(bstate.full_items or {}) do
      if item.page_path ~= nil and normalize_path(item.page_path) == target then
        return true
      end
    end
    for _, item in ipairs(bstate.lingering_items or {}) do
      if item.page_path ~= nil and normalize_path(item.page_path) == target then
        return true
      end
    end
  end

  for _, bs in pairs(state.buffers or {}) do
    for _, item in ipairs({ bs.preview_item, bs.preview_last_rendered_item }) do
      if item ~= nil and item.page_path ~= nil and normalize_path(item.page_path) == target then
        return true
      end
    end
  end

  return false
end

--- @param path string|nil
local function safe_unlink_service_artifact(path)
  if type(path) ~= "string" or path == "" then
    return
  end
  if not service_page_path_in_use(path) then
    safe_unlink(path)
  end
end

M._service_page_path_in_use = service_page_path_in_use
M._safe_unlink_service_artifact = safe_unlink_service_artifact

--- @param path string
--- @param text string
--- @return boolean, string?
local function write_file_in_place(path, text)
  local dir = vim.fn.fnamemodify(path, ":h")
  local base = vim.fn.fnamemodify(path, ":t")
  vim.fn.mkdir(dir, "p")
  local tmp_path = string.format("%s/.%s.tmp-%d", dir, base, vim.uv.hrtime())
  local fd, open_err = vim.uv.fs_open(tmp_path, "w", tonumber("644", 8))
  if not fd then
    return false, open_err
  end
  local _, write_err = vim.uv.fs_write(fd, text, 0)
  vim.uv.fs_close(fd)
  if write_err ~= nil then
    safe_unlink(tmp_path)
    return false, write_err
  end
  local ok, rename_err = vim.uv.fs_rename(tmp_path, path)
  if not ok then
    safe_unlink(tmp_path)
    return false, rename_err
  end
  return true
end

--- @param path string
--- @param text string
--- @return boolean, string?, boolean
local function write_file_if_changed(path, text)
  local stat = vim.uv.fs_stat(path)
  if stat ~= nil then
    local fd = vim.uv.fs_open(path, "r", tonumber("644", 8))
    if fd ~= nil then
      local existing = vim.uv.fs_read(fd, stat.size, 0)
      vim.uv.fs_close(fd)
      if existing == text then
        return true, nil, false
      end
    end
  end
  local ok, err = write_file_in_place(path, text)
  return ok, err, ok
end

--- @param bufnr integer
--- @param effective_root string
--- @param kind "full"
--- @return string
local function resolve_preamble_include_line(bufnr, effective_root, kind)
  local main = require("math-conceal.image")
  local config = main.config
  if type(config.get_preamble_file) ~= "function" then
    return ""
  end

  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  local cwd = vim.fn.getcwd()
  local ok, pf = pcall(config.get_preamble_file, bufnr, buf_path, cwd, kind)
  if not ok or type(pf) ~= "string" or pf == "" then
    return ""
  end

  local path_rewrite = require("math-conceal.image.path-rewrite")
  local abs = vim.fs.normalize(vim.fn.fnamemodify(pf, ":p")):gsub("/$", "")
  local typst_path = path_rewrite.encode_root_relative(abs, effective_root)
  return '#include "' .. typst_path .. '"\n'
end

local function diagnostics_have_errors(items)
  for _, item in ipairs(items or {}) do
    if item.type == "E" or item.severity == "error" or (item.severity == nil and item.type == nil) then
      return true
    end
  end
  return false
end

--- Returns (and creates) a per-buffer cache directory.
--- Prefer placing it inside source_root so generated inputs stay within
--- the same Typst project root as real source files.
--- @param bufnr integer
--- @param source_root string|nil
--- @return string
local function get_cache_dir(bufnr, source_root)
  local buf_file = vim.api.nvim_buf_get_name(bufnr)
  local safe_name
  if buf_file == nil or buf_file == "" then
    safe_name = "unnamed"
  else
    safe_name = vim.fn.fnamemodify(buf_file, ":t:r"):gsub("[^%w%-]", "_")
    if #safe_name > 40 then
      safe_name = safe_name:sub(1, 40)
    end
  end
  -- Simple polynomial hash to distinguish same-named files in different directories
  local hash_input = (buf_file ~= nil and buf_file ~= "") and buf_file or tostring(bufnr)
  local h = 0
  for i = 1, #hash_input do
    h = (h * 31 + hash_input:byte(i)) % 0xFFFF
  end
  local base_dir
  if source_root ~= nil and source_root ~= "" then
    base_dir = source_root .. "/.math-conceal.image"
  else
    base_dir = vim.fn.stdpath("cache") .. "/math-conceal.image"
  end
  local dir = base_dir .. "/" .. safe_name .. "-" .. string.format("%04x", h)
  vim.fn.mkdir(dir, "p")
  return dir
end

--- Recursively remove generated, per-render service work directories.
--- @param dir string
local function cleanup_generated_work_dir(dir)
  local scan = vim.uv.fs_scandir(dir)
  if scan ~= nil then
    while true do
      local name, typ = vim.uv.fs_scandir_next(scan)
      if name == nil then
        break
      end
      local path = dir .. "/" .. name
      if typ == "directory" then
        cleanup_generated_work_dir(path)
        pcall(vim.uv.fs_rmdir, path)
      elseif typ == "file" then
        safe_unlink(path)
      end
    end
  end
  pcall(vim.uv.fs_rmdir, dir)
end

--- Remove unreferenced service-generated PNGs and preview sidecars for a buffer
--- cache directory. PNG deletion goes through safe_unlink_service_artifact
--- because service output paths are content-addressed and may be shared.
--- @param dir string|nil
local function cleanup_service_cache_dir(dir)
  if dir == nil or dir == "" then
    return
  end
  local scan = vim.uv.fs_scandir(dir)
  if scan == nil then
    return
  end
  while true do
    local name, typ = vim.uv.fs_scandir_next(scan)
    if name == nil then
      break
    end
    if typ == "directory" and name:match("^latex%-work%-") then
      cleanup_generated_work_dir(dir .. "/" .. name)
    elseif typ == "file" and (name:match("%.png$") or name:match("^%.typst%-concealer%-preview%-.*%.typ$")) then
      local path = dir .. "/" .. name
      if name:match("%.png$") then
        safe_unlink_service_artifact(path)
      else
        safe_unlink(path)
      end
    end
  end
end

--- @param dir string|nil
local function cleanup_service_workspace_dir(dir)
  if dir == nil or dir == "" then
    return
  end
  local scan = vim.uv.fs_scandir(dir)
  if scan == nil then
    return
  end
  while true do
    local name, typ = vim.uv.fs_scandir_next(scan)
    if name == nil then
      break
    end
    local path = dir .. "/" .. name
    if typ == "directory" then
      if name:match("^latex%-work%-") then
        cleanup_generated_work_dir(path)
      else
        cleanup_service_workspace_dir(path)
        pcall(vim.uv.fs_rmdir, path)
      end
    elseif typ == "file" then
      if name:match("%.png$") then
        safe_unlink_service_artifact(path)
      elseif name:match("%.typ$") or name:match("^%.") then
        safe_unlink(path)
      end
    end
  end
end

function M._cleanup_service_workspace_for_buf(bufnr)
  cleanup_service_workspace_dir(state.service_workspace_dirs and state.service_workspace_dirs[bufnr])
  if state.service_workspace_dirs then
    state.service_workspace_dirs[bufnr] = nil
  end
end

--- @param request RenderRequest
--- @return RenderRequestMeta
local function build_render_request_meta(request)
  local jobs = request.jobs or {}
  local page_to_slot = {}
  local slot_to_node = {}
  local slot_to_overlay = {}
  local node_to_job = {}

  for i, job in ipairs(jobs) do
    local page_index = job.request_page_index or i
    job.request_id = request.request_id
    job.request_page_index = page_index
    job.slot_id = job.slot_id or ("slot:" .. tostring(page_index))
    if job.slot_id ~= nil then
      page_to_slot[page_index] = job.slot_id
      if job.node_id ~= nil then
        slot_to_node[job.slot_id] = job.node_id
        node_to_job[job.node_id] = job
      end
      if job.overlay_id ~= nil then
        slot_to_overlay[job.slot_id] = job.overlay_id
      end
    elseif job.node_id ~= nil then
      node_to_job[job.node_id] = job
    end
  end

  return {
    request_id = request.request_id,
    bufnr = request.bufnr,
    render_epoch = request.render_epoch,
    buffer_version = request.buffer_version,
    layout_version = request.layout_version,
    shape_epoch = request.shape_epoch or 0,
    project_scope_id = request.project_scope_id,
    jobs = jobs,
    page_to_slot = page_to_slot,
    slot_to_node = slot_to_node,
    slot_to_overlay = slot_to_overlay,
    node_to_job = node_to_job,
    page_count = #jobs,
    status = "active",
  }
end

local on_service_response
local finish_service_response
local get_compiler_service
local send_next_service_payload
local send_or_queue_service_payload
local service_cache_key

--- @param bufnr integer
--- @return string[]
local function snapshot_full_context_preludes(bufnr)
  local bstate = state.buffer_render_state[bufnr]
  return (bstate and bstate.runtime_preludes) or {}
end

--- @param bufnr integer
--- @param range table
--- @return string|nil
local function range_to_string(bufnr, range)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end

  local start_row, start_col, end_row, end_col = range[1], range[2], range[3], range[4]
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count <= 0 then
    return ""
  end

  start_row = math.max(0, math.min(start_row, line_count - 1))
  end_row = math.max(start_row, math.min(end_row, line_count - 1))

  local content = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  if #content == 0 then
    return ""
  end

  local first_len = #(content[1] or "")
  local last_len = #(content[#content] or "")
  start_col = math.max(0, math.min(start_col, first_len))
  end_col = math.max(0, math.min(end_col, last_len))

  if start_row == end_row then
    if end_col < start_col then
      end_col = start_col
    end
    content[1] = string.sub(content[1], start_col + 1, end_col)
  else
    content[1] = string.sub(content[1], start_col + 1)
    content[#content] = string.sub(content[#content], 1, end_col)
  end

  return table.concat(content, "\n")
end

--- Called when a rendered page file is stable enough to inspect.
--- @param bufnr          integer
--- @param page_path      string
--- @param item           table
--- @param original_range table
--- @param page_stamp     string
--- @return table|nil
local function build_page_update(bufnr, page_path, item, original_range, page_stamp)
  local pngData = require("math-conceal.image.png-lua")
  local kitty_codes = require("math-conceal.image.kitty-codes")

  if item == nil then
    return
  end

  local target_range = original_range
  if item and item.render_target == "float" then
    target_range = item.target_range or original_range
  end

  local expected_str = item.source_str or item.source_text or item.str
  if expected_str ~= nil and range_to_string(item.bufnr, item.range) ~= expected_str then
    return
  end

  local source_rows = target_range[3] - target_range[1] + 1
  local success, data = pcall(pngData, page_path)
  if not success then
    return
  end

  local natural_rows, natural_cols
  if state._cell_px_w and state._cell_px_h then
    natural_rows = math.max(1, math.floor(data.height / state._cell_px_h + 0.5))
    natural_cols = math.max(1, math.floor(data.width / state._cell_px_w + 0.5))
  else
    natural_rows = source_rows
    natural_cols = math.ceil((data.width / data.height) * 2) * source_rows
  end

  if
    source_rows == 1
    and natural_rows > 1
    and not (item and item.semantics and item.semantics.display_kind == "block")
  then
    if state._cell_px_w and state._cell_px_h then
      local aspect = data.width / data.height
      natural_cols = math.max(1, math.floor(state._cell_px_h * aspect / state._cell_px_w + 0.5))
    else
      natural_cols = math.max(1, math.floor((data.width / data.height) * 2))
    end
    natural_rows = 1
  end

  if natural_cols >= #kitty_codes.diacritics then
    natural_cols = #kitty_codes.diacritics - 1
  end

  return {
    bufnr = bufnr,
    image_id = item.image_id,
    extmark_id = item.extmark_id,
    original_range = original_range,
    page_path = page_path,
    page_stamp = page_stamp,
    natural_cols = natural_cols,
    natural_rows = natural_rows,
    source_rows = source_rows,
  }
end

--- @param width_px integer
--- @param height_px integer
--- @param job RenderJob
--- @return integer
local function compute_natural_cols(width_px, height_px, job)
  width_px = tonumber(width_px) or 1
  height_px = tonumber(height_px) or 1
  if width_px <= 0 then
    width_px = 1
  end
  if height_px <= 0 then
    height_px = 1
  end

  local source_rows = job.range[3] - job.range[1] + 1
  local natural_cols
  if state._cell_px_w and state._cell_px_h then
    natural_cols = math.max(1, math.floor(width_px / state._cell_px_w + 0.5))
    if source_rows == 1 and not (job.semantics and job.semantics.display_kind == "block") then
      local aspect = width_px / height_px
      natural_cols = math.max(1, math.floor(state._cell_px_h * aspect / state._cell_px_w + 0.5))
    end
  elseif source_rows == 1 and not (job.semantics and job.semantics.display_kind == "block") then
    natural_cols = math.max(1, math.floor((width_px / height_px) * 2))
  else
    natural_cols = math.ceil((width_px / height_px) * 2) * source_rows
  end

  local kitty_codes = require("math-conceal.image.kitty-codes")
  if natural_cols >= #kitty_codes.diacritics then
    natural_cols = #kitty_codes.diacritics - 1
  end
  return natural_cols
end

--- @param width_px integer
--- @param height_px integer
--- @param job RenderJob
--- @return integer
local function compute_natural_rows(width_px, height_px, job)
  width_px = tonumber(width_px) or 1
  height_px = tonumber(height_px) or 1
  if width_px <= 0 then
    width_px = 1
  end
  if height_px <= 0 then
    height_px = 1
  end

  local source_rows = job.range[3] - job.range[1] + 1
  if state._cell_px_w and state._cell_px_h then
    if source_rows == 1 and not (job.semantics and job.semantics.display_kind == "block") then
      return 1
    end
    return math.max(1, math.floor(height_px / state._cell_px_h + 0.5))
  end
  return source_rows
end

--- Extract --input key=value pairs from compiler_args and project_scope.inputs.
--- @param config table
--- @param project_scope table
--- @return table<string, string>
local function extract_service_inputs(config, project_scope)
  local inputs = {}
  if config.compiler_args then
    local i = 1
    while i <= #config.compiler_args do
      local arg = config.compiler_args[i]
      if arg == "--input" and i + 1 <= #config.compiler_args then
        local kv = config.compiler_args[i + 1]
        local eq = kv:find("=", 1, true)
        if eq then
          inputs[kv:sub(1, eq - 1)] = kv:sub(eq + 1)
        end
        i = i + 2
      elseif arg:sub(1, 8) == "--input=" then
        local kv = arg:sub(9)
        local eq = kv:find("=", 1, true)
        if eq then
          inputs[kv:sub(1, eq - 1)] = kv:sub(eq + 1)
        end
        i = i + 1
      else
        i = i + 1
      end
    end
  end
  for _, s in ipairs(project_scope.inputs or {}) do
    local eq = s:find("=", 1, true)
    if eq ~= nil then
      inputs[s:sub(1, eq - 1)] = s:sub(eq + 1)
    end
  end
  if next(inputs) == nil then
    return vim.empty_dict()
  end
  return inputs
end

--- @param text string
--- @return string
local function stable_hash(text)
  local ok, digest = pcall(vim.fn.sha256, text)
  if ok and type(digest) == "string" and digest ~= "" then
    return digest:sub(1, 16)
  end

  local h = 0
  for i = 1, #text do
    h = (h * 31 + text:byte(i)) % 0xFFFFFFFF
  end
  return string.format("%08x", h)
end

--- @param text string|nil
--- @return integer
local function count_lines(text)
  text = text or ""
  if text == "" then
    return 0
  end
  local _, n = text:gsub("\n", "\n")
  if text:sub(-1) ~= "\n" then
    n = n + 1
  end
  return n
end

--- @param item table
--- @return integer
local function item_source_rows(item)
  local range = item.range or { 0, 0, 0, 0 }
  return math.max(1, (range[3] or 0) - (range[1] or 0) + 1)
end

--- Build the preview sidecar exactly like a full-render slot: runtime prelude,
--- wrapper, and the current preview body all live in the included file.  The
--- preview main document stays stable and only includes this context-owned
--- sidecar, matching the full service render layout.
--- @param item table
--- @param project_scope table
--- @param prelude_chunks string[]
--- @return string
local function build_preview_service_sidecar_source(item, project_scope, prelude_chunks)
  local text = require("math-conceal.image.wrapper").build_slot_document(
    item,
    project_scope.buf_dir,
    project_scope.source_root,
    project_scope.effective_root,
    prelude_chunks
  )
  return text
end

--- @param service typst_compiler_service
--- @param sidecar_path string
--- @param sidecar_text string
--- @return fun(): boolean, string?
local function make_preview_sidecar_prepare(service, sidecar_path, sidecar_text)
  return function()
    service._preview_sidecar_texts = service._preview_sidecar_texts or {}
    if service._preview_sidecar_texts[sidecar_path] == sidecar_text and vim.uv.fs_stat(sidecar_path) ~= nil then
      return true
    end
    local ok, err = write_file_in_place(sidecar_path, sidecar_text)
    if ok then
      service._preview_sidecar_texts[sidecar_path] = sidecar_text
    end
    return ok, err
  end
end

local function root_relative(path, effective_root)
  return require("math-conceal.image.path-rewrite").encode_root_relative(path, effective_root)
end

local function virtual_path_id(value)
  local out = tostring(value or ""):gsub("[^%w%-_]", "-")
  if out == "" then
    return "node"
  end
  return out
end

local function formula_virtual_node_path(node_id)
  return "/__typst_concealer__/nodes/" .. virtual_path_id(node_id) .. ".typ"
end

local function latex_formula_virtual_node_path(node_id)
  return "/__typst_concealer__/latex-nodes/" .. virtual_path_id(node_id) .. ".tex"
end

--- @param request RenderRequest
--- @param project_scope table
--- @param workspace table
--- @param context_text string
--- @return string
local function build_full_main_document(request, project_scope, workspace, context_text)
  local parts = {}
  if context_text ~= nil and context_text ~= "" then
    parts[#parts + 1] = context_text
    if context_text:sub(-1) ~= "\n" then
      parts[#parts + 1] = "\n"
    end
    parts[#parts + 1] = "#pagebreak(weak: true)\n"
  end
  for idx, job in ipairs(request.jobs or {}) do
    if idx > 1 then
      parts[#parts + 1] = "#pagebreak()\n"
    end
    local slot_path = require("math-conceal.image.workspace").slot_path(workspace, job.slot_id or idx)
    parts[#parts + 1] = '#include "' .. root_relative(slot_path, project_scope.effective_root) .. '"\n'
  end
  return table.concat(parts)
end

--- @param service typst_compiler_service
--- @param writes table[]
--- @return fun(): boolean, string?
local function make_full_sidecar_prepare(service, writes)
  return function()
    service._full_sidecar_texts = service._full_sidecar_texts or {}
    for _, entry in ipairs(writes or {}) do
      local path = entry.path
      local text = entry.text or ""
      if service._full_sidecar_texts[path] ~= text or vim.uv.fs_stat(path) == nil then
        local ok, err = write_file_if_changed(path, text)
        if not ok then
          return false, err
        end
        service._full_sidecar_texts[path] = text
      end
    end
    return true
  end
end

local function request_allows_partial_error_diagnostics(_request)
  return false
end

--- @param request RenderRequest
--- @param project_scope table
--- @param prelude_chunks string[]
--- @param preamble_include_line string
--- @param config table
--- @return table
local function build_full_service_spec(request, project_scope, prelude_chunks, preamble_include_line, config)
  local wrapper = require("math-conceal.image.wrapper")
  local workspace_mod = require("math-conceal.image.workspace")
  local workspace = workspace_mod.for_buffer(request.bufnr, project_scope.source_root)
  local context_text = wrapper.build_context_document(
    request.bufnr,
    project_scope.buf_dir,
    project_scope.source_root,
    project_scope.effective_root,
    preamble_include_line
  )
  local main_text = build_full_main_document(request, project_scope, workspace, context_text)
  local writes = {
    { path = workspace.context_path, text = context_text, kind = "context" },
    { path = workspace.main_path, text = main_text, kind = "main" },
  }
  local slot_line_maps = {}
  local generated_slot_paths = {}

  for _, job in ipairs(request.jobs or {}) do
    local slot_path = workspace_mod.slot_path(workspace, job.slot_id)
    generated_slot_paths[job.slot_id] = slot_path
    local slot_text, slot_map = wrapper.build_slot_document(
      job,
      project_scope.buf_dir,
      project_scope.source_root,
      project_scope.effective_root,
      prelude_chunks
    )
    if slot_map ~= nil then
      slot_map.filename = vim.api.nvim_buf_get_name(job.bufnr)
      slot_line_maps[normalize_path(slot_path)] = slot_map
    end
    if job.slot_dirty == true or vim.uv.fs_stat(slot_path) == nil then
      writes[#writes + 1] = {
        path = slot_path,
        text = slot_text,
        kind = "slot",
        slot_id = job.slot_id,
      }
    end
  end

  return {
    workspace = workspace,
    source_text = main_text,
    writes = writes,
    slot_line_maps = slot_line_maps,
    generated_slot_paths = generated_slot_paths,
    generated_input_path = workspace.main_path,
    generated_context_path = workspace.context_path,
    output_dir = workspace.outputs_dir,
    -- Keep one full-render compiler per project scope. Using shape_epoch here
    -- causes the service to retain one Compiler per structural edit.
    cache_key = service_cache_key(project_scope, "full"),
  }
end

--- @param request RenderRequest
--- @param project_scope table
--- @param prelude_chunks string[]
--- @param preamble_include_line string
--- @param config table
--- @return table
local function build_formula_service_spec(request, project_scope, prelude_chunks, preamble_include_line, config)
  local wrapper = require("math-conceal.image.wrapper")
  local workspace_mod = require("math-conceal.image.workspace")
  local workspace = workspace_mod.for_buffer(request.bufnr, project_scope.source_root)
  local context_source = wrapper.build_context_document(
    request.bufnr,
    project_scope.buf_dir,
    project_scope.source_root,
    project_scope.effective_root,
    preamble_include_line
  )
  local context_line_offset = context_source ~= "" and (count_lines(context_source) + 1) or 0
  local context_id = nil
  local context_rev = nil
  local nodes = {}
  local formula_line_maps = {}
  local formula_line_offsets = {}
  local generated_slot_paths = {}
  local generated_node_paths = {}

  for _, job in ipairs(request.jobs or {}) do
    if not (job.is_stub or job.is_tombstone or job.overlay_id == nil) then
      context_id = context_id or job.context_id or project_scope.project_scope_id
      context_rev = context_rev or job.context_rev or 1

      local slot_path = workspace_mod.slot_path(workspace, job.slot_id)
      generated_slot_paths[job.slot_id] = slot_path
      generated_node_paths[job.node_id] = formula_virtual_node_path(job.node_id)
      local slot_text, slot_map = wrapper.build_slot_document(
        job,
        project_scope.buf_dir,
        project_scope.source_root,
        project_scope.effective_root,
        prelude_chunks
      )
      if slot_map ~= nil then
        slot_map.filename = vim.api.nvim_buf_get_name(job.bufnr)
        formula_line_maps[job.node_id] = slot_map
        formula_line_offsets[job.node_id] = context_line_offset
      end

      nodes[#nodes + 1] = {
        node_id = job.node_id,
        node_rev = job.node_rev or 1,
        source_hash = job.source_text_hash or stable_hash(slot_text),
        kind = job.node_type,
        source = slot_text,
      }
    end
  end

  context_id = context_id or project_scope.project_scope_id or ("ctx:" .. stable_hash(context_source))
  context_rev = context_rev or 1

  return {
    workspace = workspace,
    context_id = context_id,
    context_rev = context_rev,
    context_source = context_source,
    nodes = nodes,
    formula_line_maps = formula_line_maps,
    formula_line_offsets = formula_line_offsets,
    generated_slot_paths = generated_slot_paths,
    generated_node_paths = generated_node_paths,
    generated_input_path = workspace.main_path,
    generated_context_path = workspace.context_path,
    output_dir = workspace.outputs_dir,
    cache_key = service_cache_key(project_scope, "formula") .. ":" .. stable_hash(context_source),
  }
end

--- @param request RenderRequest
--- @param project_scope table
--- @param config table
--- @return table
local function build_latex_formula_service_spec(request, project_scope, config)
  local wrapper = require("math-conceal.image.latex-wrapper")
  local workspace_mod = require("math-conceal.image.workspace")
  local workspace = workspace_mod.for_buffer(request.bufnr, project_scope.source_root)
  local latex_config = (config.backends and config.backends.latex) or {}
  local context_source = wrapper.build_context_document(project_scope, latex_config)
  local context_id = nil
  local context_rev = nil
  local nodes = {}
  local formula_line_maps = {}
  local formula_line_offsets = {}
  local generated_slot_paths = {}
  local generated_node_paths = {}

  for _, job in ipairs(request.jobs or {}) do
    if not (job.is_stub or job.is_tombstone or job.overlay_id == nil) then
      context_id = context_id or job.context_id or project_scope.project_scope_id
      context_rev = context_rev or job.context_rev or 1

      local slot_path = workspace_mod.slot_path(workspace, job.slot_id)
      generated_slot_paths[job.slot_id] = slot_path
      generated_node_paths[job.node_id] = latex_formula_virtual_node_path(job.node_id)
      formula_line_maps[job.node_id] = wrapper.build_formula_line_map(job, context_source)
      formula_line_offsets[job.node_id] = 0

      local source = job.source_str or job.source_text or job.str or ""
      local backend_node_type = job.backend_node_type
        or (job.semantics and job.semantics.backend_node_type)
        or "inline_formula"

      nodes[#nodes + 1] = {
        node_id = job.node_id,
        node_rev = job.node_rev or 1,
        source_hash = job.source_text_hash or stable_hash(source),
        kind = backend_node_type,
        source = source,
      }
    end
  end

  context_id = context_id or project_scope.project_scope_id or ("ctx:" .. stable_hash(context_source))
  context_rev = context_rev or 1

  return {
    workspace = workspace,
    context_id = context_id,
    context_rev = context_rev,
    context_source = context_source,
    nodes = nodes,
    formula_line_maps = formula_line_maps,
    formula_line_offsets = formula_line_offsets,
    generated_slot_paths = generated_slot_paths,
    generated_node_paths = generated_node_paths,
    generated_input_path = workspace.main_path,
    generated_context_path = project_scope.preamble_path ~= "" and project_scope.preamble_path
      or workspace.context_path,
    output_dir = workspace.outputs_dir,
    cache_key = service_cache_key(project_scope, "latex-formula") .. ":" .. stable_hash(context_source),
  }
end

local function latex_mitex_fast_path_enabled(config)
  local latex_config = (config.backends and config.backends.latex) or {}
  return latex_config.mitex_fast_path ~= false
end

local function latex_job_source(job)
  return job.source_str or job.source_text or job.str or ""
end

local function latex_job_backend_node_type(job)
  return job.backend_node_type or (job.semantics and job.semantics.backend_node_type) or "inline_formula"
end

local function build_latex_mitex_item(item, mitex_prelude)
  local next_item = vim.deepcopy(item)
  local source = latex_job_source(item)
  local backend_node_type = latex_job_backend_node_type(item)
  local render_text =
    require("math-conceal.image.latex-wrapper").build_mitex_render_text(source, backend_node_type, mitex_prelude)
  next_item.source_str = source
  next_item.source_text = render_text
  next_item.str = render_text
  next_item.source_text_hash =
    stable_hash(table.concat({ "latex-mitex", mitex_prelude, source, backend_node_type }, "\0"))
  next_item.prelude_count = 0
  next_item.requires_mitex = true
  next_item.node_type = next_item.node_type or "math"
  next_item.backend_node_type = backend_node_type
  next_item.semantics = vim.deepcopy(next_item.semantics or {})
  next_item.semantics.backend_id = "latex"
  next_item.semantics.backend_node_type = backend_node_type
  next_item.semantics.source_kind = "latex"
  next_item.semantics.latex_mitex_fast_path = true
  return next_item
end

local function latex_mitex_prelude(project_scope, config)
  local latex_config = (config.backends and config.backends.latex) or {}
  return require("math-conceal.image.latex-wrapper").build_mitex_prelude(project_scope, latex_config)
end

local function build_latex_mitex_request(request, project_scope, config)
  local mitex_prelude = latex_mitex_prelude(project_scope, config)
  local mitex_request = vim.deepcopy(request)
  mitex_request.jobs = {}

  for _, job in ipairs(request.jobs or {}) do
    local next_job = vim.deepcopy(job)
    if not (next_job.is_stub or next_job.is_tombstone or next_job.overlay_id == nil) then
      next_job = build_latex_mitex_item(job, mitex_prelude)
    end
    mitex_request.jobs[#mitex_request.jobs + 1] = next_job
  end

  return mitex_request
end

local function build_latex_mitex_formula_service_spec(request, project_scope, config)
  local mitex_request = build_latex_mitex_request(request, project_scope, config)
  return build_formula_service_spec(mitex_request, project_scope, {}, nil, config), mitex_request
end

--- @param bufnr integer
--- @param item table
--- @param project_scope table
--- @param config table
--- @return table
local function build_latex_preview_service_spec(bufnr, item, project_scope, config)
  local wrapper = require("math-conceal.image.latex-wrapper")
  local workspace_mod = require("math-conceal.image.workspace")
  local workspace = workspace_mod.for_buffer(bufnr, project_scope.source_root)
  local latex_config = (config.backends and config.backends.latex) or {}
  local context_source = wrapper.build_context_document(project_scope, latex_config)
  local source = item.source_str or item.source_text or item.str or ""
  local backend_node_type = item.backend_node_type
    or (item.semantics and item.semantics.backend_node_type)
    or "inline_formula"
  local node_id = item.node_id or ("preview:" .. tostring(bufnr))
  local node_rev = item.node_rev or 1

  return {
    workspace = workspace,
    context_id = item.context_id or project_scope.project_scope_id,
    context_rev = item.context_rev or 1,
    context_source = context_source,
    output_dir = workspace.preview_dir,
    cache_key = service_cache_key(project_scope, "latex-preview") .. ":" .. stable_hash(
      table.concat({ context_source, source, backend_node_type }, "\0")
    ),
    nodes = {
      {
        node_id = node_id,
        node_rev = node_rev,
        source_hash = item.source_text_hash or stable_hash(source),
        kind = backend_node_type,
        source = source,
      },
    },
  }
end

--- @param resp table
local function cleanup_request_artifacts(resp)
  for _, page in ipairs(resp.pages or {}) do
    if type(page.path) == "string" and page.path ~= "" then
      safe_unlink_service_artifact(page.path)
    end
  end
end

local function cleanup_formula_artifact(resp)
  if type(resp.path) == "string" and resp.path ~= "" then
    safe_unlink_service_artifact(resp.path)
  end
end

local function cleanup_service_pages(pages)
  for _, page in ipairs(pages or {}) do
    if type(page.path) == "string" and page.path ~= "" then
      safe_unlink_service_artifact(page.path)
    end
  end
end

local function is_integer(value)
  return type(value) == "number" and value == math.floor(value)
end

local function select_last_service_page(resp)
  if type(resp.pages) ~= "table" or #resp.pages == 0 then
    return nil, {}
  end

  local selected = nil
  local selected_pos = nil
  local selected_page_index = nil
  for pos, page in ipairs(resp.pages) do
    local page_index = tonumber(page.page_index)
    if is_integer(page_index) and (selected_page_index == nil or page_index > selected_page_index) then
      selected = page
      selected_pos = pos
      selected_page_index = page_index
    end
  end

  if selected == nil then
    selected = resp.pages[#resp.pages]
    selected_pos = #resp.pages
  end

  local leading_pages = {}
  for pos, page in ipairs(resp.pages) do
    if pos ~= selected_pos then
      leading_pages[#leading_pages + 1] = page
    end
  end

  return selected, leading_pages
end

--- Validate the compiler-service page contract before dispatching any page.
--- @param meta RenderRequestMeta
--- @param resp table
--- @return boolean, table|string
local function validate_service_pages(meta, resp)
  if type(resp.pages) ~= "table" then
    return false, "missing pages array"
  end
  local expected_pages = meta.page_count or 0
  local total_pages = #resp.pages
  if total_pages < expected_pages then
    return false, ("page count mismatch: expected at least %d, got %d"):format(expected_pages, total_pages)
  end

  local seen = {}
  local pages_by_doc_index = {}
  local pages_by_request_index = {}
  for _, page in ipairs(resp.pages) do
    local raw_page_index = tonumber(page.page_index)
    if not is_integer(raw_page_index) then
      return false, "page_index must be an integer"
    end
    if raw_page_index < 0 then
      return false, ("page_index out of range: %s"):format(tostring(page.page_index))
    end
    if seen[raw_page_index] then
      return false, ("duplicate page_index: %d"):format(raw_page_index)
    end
    seen[raw_page_index] = true
    if type(page.path) ~= "string" or page.path == "" then
      return false, "page path must be a non-empty string"
    end
    if (tonumber(page.width_px) or 0) <= 0 or (tonumber(page.height_px) or 0) <= 0 then
      return false, "page width/height must be positive"
    end
    pages_by_doc_index[raw_page_index + 1] = page
  end

  for i = 1, total_pages do
    if pages_by_doc_index[i] == nil then
      return false, ("missing page_index: %d"):format(i - 1)
    end
  end

  local leading_page_count = total_pages - expected_pages
  pages_by_request_index.leading_pages = {}
  pages_by_request_index.leading_page_count = leading_page_count
  pages_by_request_index.total_pages = total_pages
  for i = 1, leading_page_count do
    pages_by_request_index.leading_pages[#pages_by_request_index.leading_pages + 1] = pages_by_doc_index[i]
  end
  for request_index = 1, expected_pages do
    pages_by_request_index[request_index] = pages_by_doc_index[leading_page_count + request_index]
  end

  return true, pages_by_request_index
end

--- @param bufnr integer
--- @param meta RenderRequestMeta
--- @return boolean, string?
local function validate_service_request_fresh(bufnr, meta)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "buffer is no longer valid"
  end
  local changedtick = vim.api.nvim_buf_get_changedtick(bufnr)
  if tonumber(meta.buffer_version) ~= changedtick then
    return false,
      ("buffer changedtick mismatch: expected %s, got %s"):format(tostring(meta.buffer_version), tostring(changedtick))
  end
  local ms = state.machine_state
  local buf = ms and ms.buffers and ms.buffers[bufnr] or nil
  if buf == nil then
    return false, "machine buffer is gone"
  end
  if buf.active_request_id ~= meta.request_id then
    return false,
      ("active request mismatch: expected %s, got %s"):format(
        tostring(meta.request_id),
        tostring(buf.active_request_id)
      )
  end
  if buf.project_scope_id ~= meta.project_scope_id then
    return false, "project scope changed"
  end
  if tonumber(buf.layout_version) ~= tonumber(meta.layout_version) then
    return false, "layout version changed"
  end
  return true
end

--- @param meta RenderRequestMeta
--- @return boolean, string?
local function validate_service_job_ranges(meta)
  for _, job in ipairs(meta.jobs or {}) do
    if not (job.is_stub or job.overlay_id == nil) then
      local expected_str = job.source_str or job.source_text or job.str
      if expected_str ~= nil and range_to_string(job.bufnr, job.range) ~= expected_str then
        return false, ("source range changed for %s"):format(tostring(job.overlay_id))
      end
    end
  end
  return true
end

--- @param bufnr integer
--- @param meta RenderRequestMeta
--- @param reason string
--- @param event_type string
local function dispatch_request_cleanup(bufnr, meta, reason, event_type)
  if meta ~= nil then
    meta.status = event_type == "render_request_superseded" and "superseded" or "failed"
  end
  if state.active_service_requests and state.active_service_requests[bufnr] == meta then
    state.active_service_requests[bufnr] = nil
  end
  if meta == nil or meta.request_id == nil then
    return
  end
  require("math-conceal.image.machine.runtime").dispatch({
    type = event_type,
    bufnr = bufnr,
    request_id = meta and meta.request_id or nil,
    reason = reason,
  })
end

--- @param bufnr integer
--- @param meta RenderRequestMeta|nil
--- @param reason string
local function fail_full_service_request(bufnr, meta, reason)
  dispatch_request_cleanup(bufnr, meta, reason, "render_request_failed")
end

--- @param bufnr integer
--- @param meta RenderRequestMeta|nil
--- @param reason string
local function supersede_full_service_request(bufnr, meta, reason)
  dispatch_request_cleanup(bufnr, meta, reason, "render_request_superseded")
end

local function active_formula_batches(bufnr)
  state.active_formula_batches = state.active_formula_batches or {}
  state.active_formula_batches[bufnr] = state.active_formula_batches[bufnr] or {}
  return state.active_formula_batches[bufnr]
end

local function get_formula_batch_meta(bufnr, request_id)
  local batches = state.active_formula_batches and state.active_formula_batches[bufnr] or nil
  return batches and batches[request_id] or nil
end

local function remove_formula_batch_meta(bufnr, request_id, meta)
  local batches = state.active_formula_batches and state.active_formula_batches[bufnr] or nil
  if batches == nil then
    return
  end
  if meta == nil or batches[request_id] == meta then
    batches[request_id] = nil
  end
  if next(batches) == nil then
    state.active_formula_batches[bufnr] = nil
  end
end

local function fail_formula_batch(bufnr, meta, reason)
  if meta == nil then
    return
  end
  meta.status = "failed"
  remove_formula_batch_meta(bufnr, meta.request_id, meta)
  for _, job in pairs(meta.node_to_job or {}) do
    if job.overlay_id ~= nil then
      require("math-conceal.image.formula.manager").render_failed(bufnr, {
        request_id = meta.request_id,
        overlay_id = job.overlay_id,
        node_rev = job.node_rev,
        context_id = job.context_id,
        context_rev = job.context_rev,
        reason = reason or "formula batch failed",
      })
    end
  end
end

M._validate_service_pages = validate_service_pages

--- @param bufnr integer
--- @param meta table|nil
--- @param diagnostics table[]|nil
local function handle_compile_diagnostics(bufnr, meta, diagnostics)
  local config = require("math-conceal.image").config
  if not config.do_diagnostics then
    return
  end

  local function generated_path(path)
    if type(path) ~= "string" or path == "" then
      return false
    end
    local norm = normalize_path(path)
    if meta ~= nil and normalize_path(meta.generated_input_path) == norm then
      return true
    end
    if meta ~= nil and normalize_path(meta.generated_context_path) == norm then
      return true
    end
    return false
  end

  local items = {}
  for _, diag in ipairs(diagnostics or {}) do
    local line = tonumber(diag.line) or 1
    local column = tonumber(diag.column) or 1
    local filename = diag.file
    local prefix = "[service]"

    if filename == nil or filename == "" then
      local mapped = meta and map_generated_pos(meta.line_map, line, column) or nil
      if mapped ~= nil and mapped.exact == true then
        filename = mapped.filename
        line = mapped.lnum
        column = mapped.col
      else
        filename = (meta and meta.generated_input_path) or vim.api.nvim_buf_get_name(bufnr)
        prefix = "[service/generated]"
      end
    else
      local resolved_filename = resolve_typst_source_path({
        bufnr = bufnr,
        buf_dir = meta and meta.buf_dir or nil,
        source_root = meta and meta.source_root or nil,
        effective_root = meta and meta.effective_root or nil,
      }, filename)
      local slot_map = meta and meta.slot_line_maps and meta.slot_line_maps[normalize_path(resolved_filename)] or nil
      if slot_map ~= nil then
        local mapped = map_generated_pos({ slot_map }, line, column)
        if mapped ~= nil and mapped.exact == true then
          filename = mapped.filename
          line = mapped.lnum
          column = mapped.col
          prefix = "[service]"
        else
          filename = resolved_filename
          prefix = "[service/generated]"
        end
      elseif generated_path(resolved_filename) then
        filename = resolved_filename
        prefix = "[service/generated]"
      else
        filename = resolved_filename
        prefix = "[service/external]"
      end
    end

    items[#items + 1] = {
      filename = filename,
      lnum = line,
      col = column,
      text = ("%s %s"):format(prefix, diag.message or "typst compile error"),
      type = diag.severity == "warning" and "W" or "E",
    }
  end

  state.render_diagnostics[bufnr] = state.render_diagnostics[bufnr] or {}
  state.render_diagnostics[bufnr].full_base = items
  rebuild_full_diagnostics_bucket(bufnr)
  rebuild_quickfix(bufnr)
end

local function note_formula_service_response(bufnr, service_kind, request_id)
  local service = get_compiler_service(bufnr, service_kind)
  if service == nil or service.inflight == nil or service.inflight.request_id ~= request_id then
    return false
  end
  if service.inflight.formula_remaining == nil then
    return true
  end
  service.inflight.formula_remaining = math.max(0, service.inflight.formula_remaining - 1)
  return service.inflight.formula_remaining == 0
end

--- @param bufnr integer
--- @param meta RenderRequestMeta
--- @param resp table
--- @param job RenderJob
local function handle_formula_diagnostics(bufnr, meta, resp, job)
  local config = require("math-conceal.image").config
  if not config.do_diagnostics then
    return
  end

  state.render_diagnostics[bufnr] = state.render_diagnostics[bufnr] or {}
  local bucket = state.render_diagnostics[bufnr]
  bucket.formula_by_node = bucket.formula_by_node or {}
  local node_id = resp.node_id or (job and job.node_id)
  if node_id == nil then
    return
  end

  local items = {}
  bucket.formula_by_node[node_id] = nil
  local formula_map = meta.formula_line_maps and meta.formula_line_maps[node_id] or nil
  local line_offset = (meta.formula_line_offsets and meta.formula_line_offsets[node_id]) or 0
  local generated_node_path = meta.generated_node_paths and meta.generated_node_paths[node_id] or nil
  local generated_context_path = (meta.node_generated_context_paths and meta.node_generated_context_paths[node_id])
    or meta.generated_context_path
  local generated_input_path = (meta.node_generated_input_paths and meta.node_generated_input_paths[node_id])
    or meta.generated_input_path
  local engine = (meta.node_service_engines and meta.node_service_engines[node_id]) or meta.service_engine

  if type(resp.diagnostics) ~= "table" or #resp.diagnostics == 0 then
    rebuild_full_diagnostics_bucket(bufnr)
    rebuild_quickfix(bufnr)
    return
  end

  for _, diag in ipairs(resp.diagnostics or {}) do
    local line = tonumber(diag.line) or 1
    local column = tonumber(diag.column) or 1
    local filename = diag.file
    local prefix = "[service/" .. (engine == "latex" and "latex" or "formula") .. "]"

    if filename == nil or filename == "" then
      if formula_map ~= nil and line > line_offset then
        local mapped = map_generated_pos({ formula_map }, line - line_offset, column)
        if mapped ~= nil and mapped.exact == true then
          filename = mapped.filename
          line = mapped.lnum
          column = mapped.col
        else
          filename = meta.generated_slot_paths and meta.generated_slot_paths[job.slot_id]
          prefix = "[service/generated]"
        end
      else
        filename = generated_context_path or generated_input_path or vim.api.nvim_buf_get_name(bufnr)
        prefix = "[service/generated]"
      end
    else
      if generated_node_path ~= nil and filename == generated_node_path and formula_map ~= nil then
        local mapped = map_generated_pos({ formula_map }, line, column)
        if mapped ~= nil and mapped.exact == true then
          filename = mapped.filename
          line = mapped.lnum
          column = mapped.col
        else
          filename = generated_node_path
          prefix = "[service/generated]"
        end
      elseif tostring(filename):find("/__typst_concealer__/", 1, true) ~= nil then
        prefix = "[service/generated]"
      else
        local resolved_filename = resolve_typst_source_path({
          bufnr = bufnr,
          buf_dir = meta and meta.buf_dir or nil,
          source_root = meta and meta.source_root or nil,
          effective_root = meta and meta.effective_root or nil,
        }, filename)
        filename = resolved_filename
        prefix = "[service/external]"
      end
    end

    items[#items + 1] = {
      filename = filename or vim.api.nvim_buf_get_name(bufnr),
      lnum = line,
      col = column,
      text = ("%s %s"):format(prefix, diag.message or "typst formula error"),
      type = diag.severity == "warning" and "W" or "E",
      _formula_node_id = node_id,
    }
  end

  bucket.formula_by_node[node_id] = items
  rebuild_full_diagnostics_bucket(bufnr)
  rebuild_quickfix(bufnr)
end

local function find_formula_node(nodes, node_id)
  for _, node in ipairs(nodes or {}) do
    if node.node_id == node_id then
      return node
    end
  end
  return nil
end

local function install_latex_fallback_maps(meta, node_id)
  local spec = meta and meta.latex_fallback_spec or nil
  if spec == nil or node_id == nil then
    return
  end
  meta.formula_line_maps = meta.formula_line_maps or {}
  meta.formula_line_offsets = meta.formula_line_offsets or {}
  meta.generated_node_paths = meta.generated_node_paths or {}
  meta.generated_slot_paths = meta.generated_slot_paths or {}
  if spec.formula_line_maps and spec.formula_line_maps[node_id] ~= nil then
    meta.formula_line_maps[node_id] = spec.formula_line_maps[node_id]
  end
  if spec.formula_line_offsets and spec.formula_line_offsets[node_id] ~= nil then
    meta.formula_line_offsets[node_id] = spec.formula_line_offsets[node_id]
  end
  if spec.generated_node_paths and spec.generated_node_paths[node_id] ~= nil then
    meta.generated_node_paths[node_id] = spec.generated_node_paths[node_id]
  end
  for slot_id, path in pairs(spec.generated_slot_paths or {}) do
    meta.generated_slot_paths[slot_id] = path
  end
  meta.node_generated_context_paths = meta.node_generated_context_paths or {}
  meta.node_generated_input_paths = meta.node_generated_input_paths or {}
  meta.node_generated_context_paths[node_id] = spec.generated_context_path
  meta.node_generated_input_paths[node_id] = spec.generated_input_path
  meta.node_service_engines = meta.node_service_engines or {}
  meta.node_service_engines[node_id] = "latex"
end

local function queue_latex_formula_fallback(bufnr, service_kind, meta, resp)
  if meta == nil or meta.latex_mitex_fallback ~= true or resp == nil or resp.node_id == nil then
    return false, "fallback unavailable"
  end
  meta.latex_fallback_node_state = meta.latex_fallback_node_state or {}
  if meta.latex_fallback_node_state[resp.node_id] ~= nil then
    return false, "fallback already attempted"
  end

  local spec = meta.latex_fallback_spec
  local node = spec and find_formula_node(spec.nodes, resp.node_id) or nil
  local job = meta.node_to_job and meta.node_to_job[resp.node_id] or nil
  if spec == nil or node == nil or job == nil then
    return false, "fallback node missing"
  end

  local latex_config = meta.latex_config or {}
  local ok, msg = pcall(vim.json.encode, {
    type = "render_formulas",
    backend = "latex",
    request_id = meta.request_id,
    cache_key = spec.cache_key,
    context_id = spec.context_id,
    context_rev = spec.context_rev,
    context_source = spec.context_source,
    root = meta.effective_root,
    inputs = vim.empty_dict(),
    output_dir = spec.output_dir,
    ppi = meta.render_ppi or state._render_ppi or (require("math-conceal.image").config or {}).ppi,
    worker_count = 1,
    compiler = latex_config.compiler,
    converter = latex_config.converter,
    compiler_args = meta.latex_compiler_args or latex_config.compiler_args or {},
    nodes = { node },
  })
  if not ok then
    return false, "failed to encode LaTeX fallback request: " .. tostring(msg)
  end

  install_latex_fallback_maps(meta, resp.node_id)
  meta.latex_fallback_node_state[resp.node_id] = "queued"

  local service = get_compiler_service(bufnr, service_kind)
  local sent = send_or_queue_service_payload(bufnr, service, {
    kind = "formula",
    request_id = meta.request_id,
    message = msg,
    meta = meta,
    formula_count = 1,
    formula_jobs = { job },
  })
  if not sent or meta.status ~= "active" then
    meta.latex_fallback_node_state[resp.node_id] = nil
    return false, "failed to queue LaTeX fallback request"
  end

  meta.pending_formula_count = (meta.pending_formula_count or 0) + 1
  return true, nil
end

local function reconcile_formula_diagnostics_for_request(bufnr)
  local ok_main, main = pcall(require, "math-conceal.image")
  if not ok_main or not main.config or not main.config.do_diagnostics then
    return
  end

  local bucket = state.render_diagnostics[bufnr]
  if bucket == nil or bucket.formula_by_node == nil then
    return
  end

  local machine_state = state.machine_state
  local buf = machine_state and machine_state.buffers and machine_state.buffers[bufnr] or nil
  local active_nodes = {}
  if buf ~= nil then
    for node_id, node in pairs(buf.nodes or {}) do
      if node ~= nil and node.status ~= "deleted_confirmed" then
        active_nodes[node_id] = true
      end
    end
  end

  local changed = false
  for node_id in pairs(bucket.formula_by_node or {}) do
    if not active_nodes[node_id] then
      bucket.formula_by_node[node_id] = nil
      changed = true
    end
  end

  if changed then
    rebuild_full_diagnostics_bucket(bufnr)
    rebuild_quickfix(bufnr)
  end
end

local function validate_formula_response_fresh(bufnr, meta, resp, job)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "buffer is no longer valid"
  end
  if meta == nil or meta.request_id ~= resp.request_id or meta.status ~= "active" then
    return false, "request is no longer active"
  end
  if job == nil or job.overlay_id == nil then
    return false, "formula job is no longer active"
  end
  if tostring(job.node_rev or "") ~= tostring(resp.node_rev or "") then
    return false, "node revision changed"
  end
  if tostring(job.context_id or "") ~= tostring(resp.context_id or "") then
    return false, "context id changed"
  end
  if tostring(job.context_rev or "") ~= tostring(resp.context_rev or "") then
    return false, "context revision changed"
  end

  local ms = state.machine_state
  local buf = ms and ms.buffers and ms.buffers[bufnr] or nil
  if buf == nil then
    return false, "machine buffer is gone"
  end
  if meta.formula_transport_only ~= true and buf.active_request_id ~= meta.request_id then
    return false, "active request changed"
  end
  local node = buf.nodes and buf.nodes[resp.node_id] or nil
  if node == nil or tostring(node.node_rev or "") ~= tostring(resp.node_rev or "") then
    return false, "node revision is no longer current"
  end
  if node.candidate_overlay_id ~= job.overlay_id then
    return false, "formula candidate changed"
  end
  if tostring(buf.context_id or "") ~= tostring(resp.context_id or "") then
    return false, "buffer context id is no longer current"
  end
  if tostring(buf.context_rev or "") ~= tostring(resp.context_rev or "") then
    return false, "buffer context revision is no longer current"
  end
  return true
end

local function formula_response_was_superseded_locally(reason)
  return reason == "active request changed"
    or reason == "node revision is no longer current"
    or reason == "formula candidate changed"
    or reason == "buffer context id is no longer current"
    or reason == "buffer context revision is no longer current"
end

local function note_formula_convergence(meta, stale_reason, job)
  if meta == nil or meta.formula_transport_only ~= true then
    return
  end
  if not formula_response_was_superseded_locally(stale_reason) then
    return
  end
  meta.needs_formula_convergence = true
  if job ~= nil and job.node_id ~= nil then
    meta.convergence_node_ids = meta.convergence_node_ids or {}
    meta.convergence_node_ids[job.node_id] = true
  end
end

local function formula_convergence_node_ids(meta)
  if meta == nil or meta.convergence_node_ids == nil then
    return nil
  end
  local node_ids = {}
  for node_id in pairs(meta.convergence_node_ids) do
    node_ids[#node_ids + 1] = node_id
  end
  if #node_ids == 0 then
    return nil
  end
  table.sort(node_ids, function(a, b)
    return tostring(a) < tostring(b)
  end)
  return node_ids
end

local function schedule_formula_convergence(bufnr, meta)
  if meta == nil or meta.needs_formula_convergence ~= true then
    return
  end
  require("math-conceal.image.formula.manager").ensure_pending_nodes_rendering(bufnr, {
    node_ids = formula_convergence_node_ids(meta),
  })
end

local function complete_formula_request_if_done(bufnr, service_kind, meta, request_id)
  if meta ~= nil and meta.pending_formula_count ~= nil then
    meta.pending_formula_count = math.max(0, meta.pending_formula_count - 1)
  end
  local service_done = note_formula_service_response(bufnr, service_kind, request_id)
  if meta ~= nil and (meta.pending_formula_count or 0) == 0 then
    require("math-conceal.image.machine.runtime").dispatch({
      type = "render_request_completed",
      bufnr = bufnr,
      request_id = request_id,
    })
    if state.active_service_requests[bufnr] == meta then
      meta.status = "completed"
      state.active_service_requests[bufnr] = nil
    end
    state._last_service_bench = {
      request_id = request_id,
      total_formulas = meta.formula_response_count or 0,
      dispatched = meta.formula_dispatched or 0,
      failed = meta.formula_failed or 0,
      cached = meta.formula_cached or 0,
      request_sent_at = meta.sent_at,
      response_at = vim.uv.hrtime(),
      service_engine = meta.service_engine or "formula",
    }
  end
  if service_done then
    finish_service_response(bufnr, service_kind, request_id)
  end
end

local function complete_formula_batch_if_done(bufnr, service_kind, meta, request_id)
  if meta ~= nil and meta.pending_formula_count ~= nil then
    meta.pending_formula_count = math.max(0, meta.pending_formula_count - 1)
  end
  local service_done = note_formula_service_response(bufnr, service_kind, request_id)
  local should_converge = meta ~= nil
    and meta.formula_transport_only == true
    and (meta.pending_formula_count or 0) == 0
    and meta.needs_formula_convergence == true
  if meta ~= nil and (meta.pending_formula_count or 0) == 0 then
    meta.status = "completed"
    remove_formula_batch_meta(bufnr, request_id, meta)
    state._last_service_bench = {
      request_id = request_id,
      total_formulas = meta.formula_response_count or 0,
      dispatched = meta.formula_dispatched or 0,
      failed = meta.formula_failed or 0,
      cached = meta.formula_cached or 0,
      request_sent_at = meta.sent_at,
      response_at = vim.uv.hrtime(),
      service_engine = meta.service_engine or "formula",
    }
  end
  if service_done then
    finish_service_response(bufnr, service_kind, request_id)
  end
  if should_converge then
    schedule_formula_convergence(bufnr, meta)
  end
end

local function try_handle_latex_preview_formula_response(bufnr, service_kind, resp)
  if service_kind ~= "preview" then
    return false
  end
  local pmeta = state.active_preview_service_requests and state.active_preview_service_requests[bufnr]
  if pmeta == nil or pmeta.request_id ~= resp.request_id then
    return false
  end

  state.active_preview_service_requests[bufnr] = nil
  state._last_preview_service_bench = {
    request_id = resp.request_id,
    total_pages = (type(resp.path) == "string" and resp.path ~= "") and 1 or 0,
    compile_us = resp.compile_us,
    render_us = resp.render_us,
    rendered_pages = resp.cached and 0 or ((type(resp.path) == "string" and resp.path ~= "") and 1 or 0),
    request_sent_at = pmeta.sent_at,
    response_at = vim.uv.hrtime(),
    service_engine = "latex",
  }

  if resp.status ~= "ok" or type(resp.path) ~= "string" or resp.path == "" then
    cleanup_formula_artifact(resp)
    return true
  end

  local item = pmeta.item
  local update = build_page_update(bufnr, resp.path, item, item.range, nil)
  if update == nil then
    cleanup_formula_artifact(resp)
    return true
  end

  update.preview_request_id = item.preview_request_id
  local accepted = require("math-conceal.image.machine.runtime").accept_preview_page_update(update)
  if not accepted then
    safe_unlink_service_artifact(resp.path)
  end
  return true
end

--- @param bufnr integer
--- @param service_kind '"full"'|'"preview"'
--- @param resp table
--- @return boolean true if this was a formula-render response
local function try_handle_formula_service_response(bufnr, service_kind, resp)
  if type(resp) ~= "table" or resp.type ~= "formula_rendered" then
    return false
  end
  if service_kind ~= "full" then
    if not try_handle_latex_preview_formula_response(bufnr, service_kind, resp) then
      cleanup_formula_artifact(resp)
    end
    if note_formula_service_response(bufnr, service_kind, resp.request_id) then
      finish_service_response(bufnr, service_kind, resp.request_id)
    end
    return true
  end

  local meta = get_formula_batch_meta(bufnr, resp.request_id)
  if meta == nil then
    meta = state.active_service_requests and state.active_service_requests[bufnr]
  end
  if meta == nil or meta.request_id ~= resp.request_id then
    cleanup_formula_artifact(resp)
    if note_formula_service_response(bufnr, service_kind, resp.request_id) then
      finish_service_response(bufnr, service_kind, resp.request_id)
    end
    return true
  end

  local complete = meta.formula_transport_only == true and complete_formula_batch_if_done
    or complete_formula_request_if_done
  meta.formula_response_count = (meta.formula_response_count or 0) + 1
  local job = meta.node_to_job and meta.node_to_job[resp.node_id] or nil
  local fresh, stale_reason = validate_formula_response_fresh(bufnr, meta, resp, job)
  if not fresh then
    cleanup_formula_artifact(resp)
    meta.formula_failed = (meta.formula_failed or 0) + 1
    note_formula_convergence(meta, stale_reason, job)
    if job ~= nil and job.overlay_id ~= nil then
      require("math-conceal.image.formula.manager").render_failed(bufnr, {
        request_id = resp.request_id,
        overlay_id = job.overlay_id,
        node_rev = job.node_rev,
        context_id = job.context_id,
        context_rev = job.context_rev,
        reason = stale_reason or "stale formula response",
      })
    end
    complete(bufnr, service_kind, meta, resp.request_id)
    return true
  end

  if resp.status ~= "ok" or type(resp.path) ~= "string" or resp.path == "" then
    cleanup_formula_artifact(resp)
    if meta.latex_mitex_fallback == true and not (meta.latex_fallback_node_state or {})[resp.node_id] then
      local queued, reason = queue_latex_formula_fallback(bufnr, service_kind, meta, resp)
      if queued then
        complete(bufnr, service_kind, meta, resp.request_id)
        return true
      end
      vim.schedule(function()
        vim.notify(
          "[math-conceal.image] LaTeX MiTeX fallback was not queued: " .. tostring(reason),
          vim.log.levels.WARN
        )
      end)
    end
    handle_formula_diagnostics(bufnr, meta, resp, job)
    meta.formula_failed = (meta.formula_failed or 0) + 1
    require("math-conceal.image.formula.manager").render_failed(bufnr, {
      request_id = resp.request_id,
      overlay_id = job.overlay_id,
      node_rev = tonumber(resp.node_rev),
      context_id = resp.context_id,
      context_rev = tonumber(resp.context_rev),
      reason = resp.status or stale_reason or "formula render failed",
    })
    complete(bufnr, service_kind, meta, resp.request_id)
    return true
  end

  handle_formula_diagnostics(bufnr, meta, resp, job)
  local width_px = tonumber(resp.width_px) or 1
  local height_px = tonumber(resp.height_px) or 1
  meta.formula_dispatched = (meta.formula_dispatched or 0) + 1
  if resp.cached then
    meta.formula_cached = (meta.formula_cached or 0) + 1
  end
  require("math-conceal.image.formula.manager").rendered(bufnr, {
    request_id = resp.request_id,
    request_page_index = job.request_page_index,
    overlay_id = job.overlay_id,
    owner_node_id = job.node_id,
    owner_bufnr = job.bufnr,
    owner_project_scope_id = job.project_scope_id,
    render_epoch = job.render_epoch,
    node_rev = job.node_rev,
    context_id = job.context_id,
    context_rev = job.context_rev,
    buffer_version = job.buffer_version,
    layout_version = job.layout_version,
    page_path = resp.path,
    page_stamp = nil,
    natural_cols = compute_natural_cols(width_px, height_px, job),
    natural_rows = compute_natural_rows(width_px, height_px, job),
    source_rows = job.range[3] - job.range[1] + 1,
  })
  complete(bufnr, service_kind, meta, resp.request_id)
  return true
end

local function queue_latex_preview_fallback(bufnr, service_kind, pmeta)
  local fallback = pmeta and pmeta.latex_preview_fallback or nil
  if fallback == nil then
    return false
  end
  pmeta.latex_preview_fallback = nil
  local service = get_compiler_service(bufnr, service_kind)
  if service == nil then
    return false
  end
  service.cache_dir = fallback.output_dir
  state.service_cache_dirs = state.service_cache_dirs or {}
  state.service_cache_dirs[bufnr] = fallback.output_dir
  state.active_preview_service_requests = state.active_preview_service_requests or {}
  state.active_preview_service_requests[bufnr] = pmeta
  return send_or_queue_service_payload(bufnr, service, {
    kind = "preview",
    request_id = pmeta.request_id,
    message = fallback.message,
    meta = pmeta,
    formula_count = fallback.formula_count,
    on_prepare_failed = function()
      local active = state.active_preview_service_requests and state.active_preview_service_requests[bufnr]
      if active ~= nil and active.request_id == pmeta.request_id then
        state.active_preview_service_requests[bufnr] = nil
      end
    end,
  })
end

--- Handle a preview compile response from the service.
--- @param bufnr integer
--- @param service_kind '"full"'|'"preview"'
--- @param resp table
--- @return boolean true if this was a preview response
local function try_handle_preview_service_response(bufnr, service_kind, resp)
  if service_kind ~= "preview" then
    return false
  end
  local pmeta = state.active_preview_service_requests and state.active_preview_service_requests[bufnr]
  if pmeta == nil or pmeta.request_id ~= resp.request_id then
    return false
  end

  -- Matched a preview request — consume it regardless of status.
  state._last_preview_service_bench = {
    request_id = resp.request_id,
    total_pages = #(resp.pages or {}),
    compile_us = resp.compile_us,
    render_us = resp.render_us,
    rendered_pages = resp.rendered_pages,
    request_sent_at = pmeta.sent_at,
    response_at = vim.uv.hrtime(),
    service_engine = pmeta.latex_preview_fallback ~= nil and "latex-mitex" or nil,
  }

  if resp.status ~= "ok" or not resp.pages or #resp.pages == 0 then
    cleanup_request_artifacts(resp)
    if queue_latex_preview_fallback(bufnr, service_kind, pmeta) then
      return true
    end
    state.active_preview_service_requests[bufnr] = nil
    return true
  end

  local page, leading_pages = select_last_service_page(resp)
  if type(page.path) ~= "string" then
    cleanup_request_artifacts(resp)
    if queue_latex_preview_fallback(bufnr, service_kind, pmeta) then
      return true
    end
    state.active_preview_service_requests[bufnr] = nil
    return true
  end

  local item = pmeta.item
  local update = build_page_update(bufnr, page.path, item, item.range, nil)
  if update == nil then
    cleanup_request_artifacts(resp)
    state.active_preview_service_requests[bufnr] = nil
    return true
  end

  update.preview_request_id = item.preview_request_id
  local accepted = require("math-conceal.image.machine.runtime").accept_preview_page_update(update)
  cleanup_service_pages(leading_pages)
  if not accepted then
    safe_unlink_service_artifact(page.path)
  end
  state.active_preview_service_requests[bufnr] = nil
  return true
end

--- Handle a preview backend prewarm response.  Prewarm pages are never shown;
--- they exist only to populate the service world's prelude/import/font caches.
--- @param bufnr integer
--- @param service_kind '"full"'|'"preview"'
--- @param resp table
--- @return boolean
local function try_handle_preview_prewarm_response(bufnr, service_kind, resp)
  local service = get_compiler_service(bufnr, service_kind)
  local inflight = service and service.inflight or nil
  if
    service_kind ~= "preview"
    or inflight == nil
    or inflight.request_id ~= resp.request_id
    or inflight.is_prewarm ~= true
  then
    return false
  end

  cleanup_request_artifacts(resp)
  service.preview_warmed_signatures = service.preview_warmed_signatures or {}
  if resp.status == "ok" and inflight.preview_context_hash ~= nil then
    service.preview_warmed_signatures[inflight.preview_context_hash] = true
  end
  state._last_preview_prewarm_bench = {
    request_id = resp.request_id,
    context_hash = inflight.preview_context_hash,
    total_pages = #(resp.pages or {}),
    compile_us = resp.compile_us,
    render_us = resp.render_us,
    rendered_pages = resp.rendered_pages,
    response_at = vim.uv.hrtime(),
  }
  finish_service_response(bufnr, service_kind, resp.request_id)
  return true
end

--- @param bufnr integer
--- @param service_kind '"full"'|'"preview"'
--- @param resp table  pre-decoded JSON response from the compiler service
on_service_response = function(bufnr, service_kind, resp)
  if try_handle_formula_service_response(bufnr, service_kind, resp) then
    return
  end

  if type(resp) ~= "table" or resp.type ~= "compile_result" then
    return
  end

  if try_handle_preview_prewarm_response(bufnr, service_kind, resp) then
    return
  end

  -- Check preview requests first (they have distinct request_ids).
  if try_handle_preview_service_response(bufnr, service_kind, resp) then
    finish_service_response(bufnr, service_kind, resp.request_id)
    return
  end

  if service_kind ~= "full" then
    cleanup_request_artifacts(resp)
    finish_service_response(bufnr, service_kind, resp.request_id)
    return
  end

  local meta = state.active_service_requests and state.active_service_requests[bufnr]
  if meta == nil or meta.request_id ~= resp.request_id or meta.status ~= "active" then
    cleanup_request_artifacts(resp)
    finish_service_response(bufnr, service_kind, resp.request_id)
    return
  end

  if resp.status ~= "ok" then
    handle_compile_diagnostics(bufnr, meta, resp.diagnostics)
    cleanup_request_artifacts(resp)
    fail_full_service_request(bufnr, meta, resp.status or "compile failed")
    finish_service_response(bufnr, service_kind, resp.request_id)
    return
  end

  handle_compile_diagnostics(bufnr, meta, resp.diagnostics)
  if diagnostics_have_errors(resp.diagnostics) and not request_allows_partial_error_diagnostics(meta) then
    cleanup_request_artifacts(resp)
    fail_full_service_request(bufnr, meta, "compile diagnostics")
    finish_service_response(bufnr, service_kind, resp.request_id)
    return
  end

  local ok_pages, pages_or_err = validate_service_pages(meta, resp)
  if not ok_pages then
    cleanup_request_artifacts(resp)
    fail_full_service_request(bufnr, meta, pages_or_err)
    vim.schedule(function()
      vim.notify(
        "[math-conceal.image] compiler service page contract failed: " .. tostring(pages_or_err),
        vim.log.levels.ERROR
      )
    end)
    finish_service_response(bufnr, service_kind, resp.request_id)
    return
  end

  local fresh, stale_reason = validate_service_request_fresh(bufnr, meta)
  if not fresh then
    cleanup_request_artifacts(resp)
    supersede_full_service_request(bufnr, meta, stale_reason or "stale service response")
    finish_service_response(bufnr, service_kind, resp.request_id)
    return
  end

  local ranges_ok, range_reason = validate_service_job_ranges(meta)
  if not ranges_ok then
    cleanup_request_artifacts(resp)
    supersede_full_service_request(bufnr, meta, range_reason or "source range changed")
    finish_service_response(bufnr, service_kind, resp.request_id)
    return
  end

  local t_lua_start = vim.uv.hrtime()
  local dispatched = 0
  local skipped_cached = 0

  local runtime = require("math-conceal.image.machine.runtime")
  local pages_by_request_index = pages_or_err
  local batch_entries = {}
  for page_index = 1, meta.page_count or 0 do
    local page = pages_by_request_index[page_index]
    local job = meta.jobs[page_index]
    if job ~= nil then
      local should_dispatch = true
      -- Skip stub jobs — these are stable slots with no active overlay
      if job.is_stub or job.overlay_id == nil then
        skipped_cached = skipped_cached + 1
        should_dispatch = false
      end

      -- Skip re-dispatching for cached (unchanged) pages whose overlay is
      -- already visible — avoids redundant image uploads and extmark updates.
      if should_dispatch and page.cached then
        local ms = state.machine_state
        local overlay = ms and ms.overlays and ms.overlays[job.overlay_id]
        if overlay and overlay.status == "visible" and overlay.page_path == page.path then
          skipped_cached = skipped_cached + 1
          should_dispatch = false
        end
      end

      if should_dispatch then
        local width_px = tonumber(page.width_px) or 1
        local height_px = tonumber(page.height_px) or 1
        batch_entries[#batch_entries + 1] = {
          request_id = resp.request_id,
          request_page_index = page_index,
          overlay_id = job.overlay_id,
          owner_node_id = job.node_id,
          owner_bufnr = job.bufnr,
          owner_project_scope_id = job.project_scope_id,
          render_epoch = job.render_epoch,
          buffer_version = job.buffer_version,
          layout_version = job.layout_version,
          page_path = page.path,
          page_stamp = nil,
          natural_cols = compute_natural_cols(width_px, height_px, job),
          natural_rows = compute_natural_rows(width_px, height_px, job),
          source_rows = job.range[3] - job.range[1] + 1,
        }
        dispatched = dispatched + 1
      end
    end
  end

  if #batch_entries > 0 then
    runtime.dispatch({
      type = "overlay_pages_batch_ready",
      entries = batch_entries,
    })
  end
  runtime.dispatch({
    type = "render_request_completed",
    bufnr = bufnr,
    request_id = resp.request_id,
  })
  cleanup_service_pages(pages_by_request_index.leading_pages)

  local lua_us = math.floor((vim.uv.hrtime() - t_lua_start) / 1000)

  if state.active_service_requests[bufnr] == meta then
    meta.status = "completed"
    state.active_service_requests[bufnr] = nil
  end

  -- Store benchmark data for retrieval
  state._last_service_bench = {
    request_id = resp.request_id,
    total_pages = #(resp.pages or {}),
    leading_pages = pages_by_request_index.leading_page_count or 0,
    dispatched = dispatched,
    skipped_cached = skipped_cached,
    compile_us = resp.compile_us,
    render_us = resp.render_us,
    rendered_pages = resp.rendered_pages,
    lua_dispatch_us = lua_us,
    request_sent_at = meta.sent_at,
    response_at = vim.uv.hrtime(),
  }
  finish_service_response(bufnr, service_kind, resp.request_id)
end

--- Report whether a compiler service exists and is still alive.
--- @param bufnr integer
--- @return boolean
function M.has_compiler_service(bufnr)
  local bucket = state.compiler_services and state.compiler_services[bufnr]
  local service = bucket and bucket.full or nil
  return service ~= nil and service.dead ~= true
end

--- @param bufnr integer
--- @return table
local function get_service_bucket(bufnr)
  state.compiler_services = state.compiler_services or {}
  state.compiler_services[bufnr] = state.compiler_services[bufnr] or {}
  return state.compiler_services[bufnr]
end

--- @param bufnr integer
--- @param kind '"full"'|'"preview"'
--- @return typst_compiler_service|nil
get_compiler_service = function(bufnr, kind)
  local bucket = state.compiler_services and state.compiler_services[bufnr]
  return bucket and bucket[kind] or nil
end

local function close_pipe(pipe)
  if pipe ~= nil and not pipe:is_closing() then
    pipe:close()
  end
end

local mark_service_payload_failed
local mark_inflight_service_request_failed

--- Start or reuse the Rust compiler service for bufnr.
--- @param bufnr integer
--- @param kind '"full"'|'"preview"'|nil
--- @return typst_compiler_service|nil
function M.ensure_compiler_service(bufnr, kind)
  kind = kind or "full"
  local bucket = get_service_bucket(bufnr)
  local existing = bucket[kind]
  if existing ~= nil and existing.dead ~= true then
    return existing
  end

  local main = require("math-conceal.image")
  local service_path = main.config.service_binary or "typst-concealer-service"
  local stdin = vim.uv.new_pipe()
  local stdout = vim.uv.new_pipe()
  local stderr = vim.uv.new_pipe()
  local service
  local handle

  handle = vim.uv.spawn(service_path, {
    stdio = { stdin, stdout, stderr },
    args = {},
  }, function()
    if service ~= nil then
      service.dead = true
      local inflight_request_id = service.inflight and service.inflight.request_id or nil
      local pending_full = service.pending_full_request
      local pending_preview = service.pending_preview_request
      service.inflight = nil
      service.pending_full_request = nil
      service.pending_preview_request = nil
      service.pending_prewarm_requests = nil
      vim.schedule(function()
        mark_inflight_service_request_failed(bufnr, inflight_request_id, "compiler service exited")
        mark_service_payload_failed(bufnr, pending_full, "compiler service exited")
        mark_service_payload_failed(bufnr, pending_preview, "compiler service exited")
      end)
    end
    local current_bucket = state.compiler_services and state.compiler_services[bufnr]
    if current_bucket ~= nil and current_bucket[kind] == service then
      current_bucket[kind] = nil
      if next(current_bucket) == nil then
        state.compiler_services[bufnr] = nil
      end
    end
    close_pipe(stdin)
    close_pipe(stdout)
    close_pipe(stderr)
    if handle ~= nil and not handle:is_closing() then
      handle:close()
    end
  end)

  if handle == nil then
    close_pipe(stdin)
    close_pipe(stdout)
    close_pipe(stderr)
    vim.schedule(function()
      vim.notify("[math-conceal.image] failed to spawn compiler service: " .. service_path, vim.log.levels.ERROR)
    end)
    return nil
  end

  service = {
    handle = handle,
    stdin = stdin,
    stdout = stdout,
    stderr = stderr,
    bufnr = bufnr,
    kind = kind,
    dead = false,
    line_buffer = "",
    stderr_line_buffer = "",
    cache_dir = nil,
  }

  stdout:read_start(function(err, data)
    if err ~= nil or data == nil then
      return
    end
    service.line_buffer = service.line_buffer .. data
    while true do
      local nl = service.line_buffer:find("\n", 1, true)
      if nl == nil then
        break
      end
      local line = service.line_buffer:sub(1, nl - 1)
      service.line_buffer = service.line_buffer:sub(nl + 1)
      if line ~= "" then
        -- Decode JSON in the UV callback to keep the main-thread work minimal.
        local decode_ok, resp = pcall(vim.json.decode, line)
        if decode_ok and type(resp) == "table" then
          vim.schedule(function()
            on_service_response(bufnr, kind, resp)
          end)
        end
      end
    end
  end)

  stderr:read_start(function(err, data)
    if err ~= nil or data == nil or data == "" then
      return
    end
    service.stderr_line_buffer = (service.stderr_line_buffer or "") .. data
    while true do
      local nl = service.stderr_line_buffer:find("\n", 1, true)
      if nl == nil then
        break
      end
      local line = vim.trim(service.stderr_line_buffer:sub(1, nl - 1))
      service.stderr_line_buffer = service.stderr_line_buffer:sub(nl + 1)
      if line ~= "" then
        vim.schedule(function()
          vim.notify("[typst-concealer-service] " .. line, vim.log.levels.WARN)
        end)
      end
    end
  end)

  bucket[kind] = service
  return service
end

--- @param project_scope table
--- @param kind '"full"'|'"preview"'
--- @return string
service_cache_key = function(project_scope, kind)
  return table.concat({
    kind,
    tostring(project_scope.project_scope_id or ""),
    tostring(project_scope.effective_root or ""),
  }, ":")
end

--- @param prelude_chunks string[]
--- @param prelude_count integer
--- @return string
local function preview_prelude_signature(prelude_chunks, prelude_count)
  local parts = { tostring(prelude_count) }
  for i = 1, prelude_count do
    parts[#parts + 1] = prelude_chunks[i] or ""
  end
  return table.concat(parts, "\0")
end

--- Build the stable preview main document and sidecar metadata for one
--- prelude/wrapper context.  The main document intentionally contains only the
--- global document context plus an include of the context-owned sidecar; the
--- sidecar itself contains the runtime prelude, wrapper, and current formula.
--- @param bufnr integer
--- @param service typst_compiler_service
--- @param item table
--- @param project_scope table
--- @param prelude_chunks string[]
--- @param preamble_include_line string
--- @return table|nil
local function build_preview_service_spec(bufnr, service, item, project_scope, prelude_chunks, preamble_include_line)
  local main = require("math-conceal.image")
  local config = main.config
  local wrapper = require("math-conceal.image.wrapper")

  local prelude_count = math.max(0, math.min(item.prelude_count or 0, #prelude_chunks))
  local probe_item = vim.deepcopy(item)
  probe_item.prelude_count = prelude_count
  probe_item.range = probe_item.range or { 0, 0, 0, 0 }
  probe_item.node_type = probe_item.node_type or "math"
  probe_item.semantics = probe_item.semantics or { display_kind = "inline", constraint_kind = "intrinsic" }

  local source_rows = item_source_rows(probe_item)
  local wrap_prefix, wrap_suffix = wrapper.build_wrapper(probe_item, source_rows)
  local context_text = table.concat({
    project_scope.buf_dir or "",
    project_scope.source_root or "",
    project_scope.effective_root or "",
    tostring(state._cell_px_w or ""),
    tostring(state._cell_px_h or ""),
    tostring(state._render_ppi or config.ppi or ""),
    config.header or "",
    main._styling_prelude or "",
    preamble_include_line or "",
    preview_prelude_signature(prelude_chunks, prelude_count),
    tostring(probe_item.node_type or ""),
    tostring(probe_item.semantics and probe_item.semantics.constraint_kind or ""),
    tostring(probe_item.semantics and probe_item.semantics.display_kind or ""),
    tostring(source_rows),
    wrap_prefix,
    wrap_suffix,
  }, "\0")
  local context_hash = stable_hash(context_text)

  local cache_dir = get_cache_dir(bufnr, project_scope.source_root)
  local sidecar_path = cache_dir .. "/.math-conceal.image-preview-" .. context_hash .. ".typ"
  local sidecar_root_relative_path =
    require("math-conceal.image.path-rewrite").encode_root_relative(sidecar_path, project_scope.effective_root)

  local include_item = vim.deepcopy(probe_item)
  include_item.str = '#include "' .. sidecar_root_relative_path .. '"\n'
  include_item.source_str = nil
  include_item.source_text = nil
  include_item.prelude_count = 0
  include_item.skip_wrapper = true

  service._preview_wrapper_caches = service._preview_wrapper_caches or {}
  service._preview_wrapper_caches[context_hash] = service._preview_wrapper_caches[context_hash]
    or { item_fragments = {} }
  local doc_str = wrapper.build_batch_document(
    { include_item },
    project_scope.buf_dir,
    project_scope.source_root,
    project_scope.effective_root,
    "full",
    prelude_chunks,
    preamble_include_line,
    false,
    service._preview_wrapper_caches[context_hash]
  )

  return {
    context_hash = context_hash,
    cache_key = service_cache_key(project_scope, "preview") .. ":" .. context_hash,
    cache_dir = cache_dir,
    source_text = doc_str,
    sidecar_path = sidecar_path,
    sidecar_text = build_preview_service_sidecar_source(probe_item, project_scope, prelude_chunks),
  }
end

--- @param item table|nil
--- @param bufnr integer
--- @param prelude_chunks string[]
--- @return table
local function make_preview_prewarm_item(item, bufnr, prelude_chunks)
  local out = item ~= nil and vim.deepcopy(item) or {}
  out.bufnr = out.bufnr or bufnr
  out.range = out.range and vim.deepcopy(out.range) or { 0, 0, 0, 3 }
  out.str = "$x$"
  out.source_str = "$x$"
  out.source_text = "$x$"
  out.prelude_count = out.prelude_count or #prelude_chunks
  out.node_type = out.node_type or "math"
  out.semantics = out.semantics or { display_kind = "inline", constraint_kind = "intrinsic" }
  out.request_id = nil
  out.preview_request_id = nil
  out.image_id = nil
  out.extmark_id = nil
  return out
end

--- @param bufnr integer
--- @param payload table|nil
--- @param reason string
mark_service_payload_failed = function(bufnr, payload, reason)
  if payload == nil then
    return
  end
  if payload.kind == "full" then
    local meta = payload.meta
    if meta == nil and state.active_service_requests then
      local active = state.active_service_requests[bufnr]
      if active ~= nil and active.request_id == payload.request_id then
        meta = active
      end
    end
    fail_full_service_request(bufnr, meta, reason)
  elseif payload.kind == "formula" then
    local meta = payload.meta or get_formula_batch_meta(bufnr, payload.request_id)
    if
      meta ~= nil
      and meta.formula_transport_only ~= true
      and state.active_service_requests
      and state.active_service_requests[bufnr] == meta
    then
      fail_full_service_request(bufnr, meta, reason)
    else
      fail_formula_batch(bufnr, meta, reason)
    end
  elseif payload.kind == "preview" and payload.is_prewarm ~= true then
    local active = state.active_preview_service_requests and state.active_preview_service_requests[bufnr]
    if active ~= nil and active.request_id == payload.request_id then
      state.active_preview_service_requests[bufnr] = nil
    end
  end
end

local function formula_job_is_current(bufnr, job, request_id)
  if job == nil or job.node_id == nil or job.overlay_id == nil then
    return false
  end
  local ms = state.machine_state
  local buf = ms and ms.buffers and ms.buffers[bufnr] or nil
  local node = buf and buf.nodes and buf.nodes[job.node_id] or nil
  local overlay = ms and ms.overlays and ms.overlays[job.overlay_id] or nil
  if node == nil or overlay == nil then
    return false
  end
  if node.candidate_overlay_id ~= job.overlay_id then
    return false
  end
  if overlay.status == "retiring" or overlay.status == "retired" then
    return false
  end
  if request_id ~= nil and overlay.request_id ~= request_id then
    return false
  end
  if job.node_rev ~= nil and tonumber(overlay.node_rev) ~= tonumber(job.node_rev) then
    return false
  end
  if job.context_id ~= nil and overlay.context_id ~= job.context_id then
    return false
  end
  if job.context_rev ~= nil and tonumber(overlay.context_rev) ~= tonumber(job.context_rev) then
    return false
  end
  if
    job.source_text_hash ~= nil
    and overlay.source_text_hash ~= nil
    and overlay.source_text_hash ~= job.source_text_hash
  then
    return false
  end
  if job.layout_version ~= nil and tonumber(overlay.layout_version) ~= tonumber(job.layout_version) then
    return false
  end
  return true
end

local function formula_payload_has_current_jobs(bufnr, payload)
  local meta = payload and payload.meta or nil
  if meta == nil or meta.node_to_job == nil then
    return false
  end
  local jobs = payload.formula_jobs or meta.node_to_job
  for _, job in pairs(jobs) do
    if formula_job_is_current(bufnr, job, payload.request_id or meta.request_id) then
      return true
    end
  end
  return false
end

--- Return whether a formula candidate is actually owned by the compiler
--- transport, either currently in-flight or queued to be sent.
--- @param bufnr integer
--- @param candidate table
--- @return boolean
function M.formula_candidate_is_rendering(bufnr, candidate)
  if type(candidate) ~= "table" or candidate.request_id == nil or candidate.node_id == nil then
    return false
  end

  local meta = get_formula_batch_meta(bufnr, candidate.request_id)
  if meta == nil or meta.status ~= "active" or meta.node_to_job == nil then
    return false
  end

  local job = meta.node_to_job[candidate.node_id]
  if not formula_job_is_current(bufnr, job or candidate, candidate.request_id) then
    return false
  end

  local service = get_compiler_service(bufnr, "full")
  if service == nil then
    return false
  end
  if service.inflight ~= nil and service.inflight.request_id == candidate.request_id then
    return true
  end
  for _, payload in ipairs(service.pending_formula_requests or {}) do
    if (payload.request_id or (payload.meta and payload.meta.request_id)) == candidate.request_id then
      return true
    end
  end
  return false
end

local function prune_pending_formula_requests(bufnr, service, reason)
  if service == nil or service.pending_formula_requests == nil then
    return
  end

  local kept = {}
  for _, pending in ipairs(service.pending_formula_requests) do
    if formula_payload_has_current_jobs(bufnr, pending) then
      kept[#kept + 1] = pending
    else
      mark_service_payload_failed(bufnr, pending, reason or "formula request superseded before send")
    end
  end
  service.pending_formula_requests = #kept > 0 and kept or nil
end

--- @param bufnr integer
--- @param request_id string|nil
--- @param reason string
mark_inflight_service_request_failed = function(bufnr, request_id, reason)
  if request_id == nil then
    return
  end
  local meta = state.active_service_requests and state.active_service_requests[bufnr]
  if meta ~= nil and meta.request_id == request_id then
    fail_full_service_request(bufnr, meta, reason)
  end
  local formula_meta = get_formula_batch_meta(bufnr, request_id)
  if formula_meta ~= nil then
    fail_formula_batch(bufnr, formula_meta, reason)
  end
  local preview = state.active_preview_service_requests and state.active_preview_service_requests[bufnr]
  if preview ~= nil and preview.request_id == request_id then
    state.active_preview_service_requests[bufnr] = nil
  end
end

--- @param service typst_compiler_service
--- @param payload table
--- @return boolean
local function write_service_payload(service, payload)
  if service == nil or service.dead == true or service.stdin == nil or service.stdin:is_closing() then
    return false
  end
  if payload.prepare ~= nil then
    local ok, err = payload.prepare()
    if not ok then
      if payload.on_prepare_failed ~= nil then
        payload.on_prepare_failed(err)
      end
      vim.schedule(function()
        vim.notify("[math-conceal.image] failed to prepare compiler request: " .. tostring(err), vim.log.levels.ERROR)
      end)
      return false
    end
  end

  local sent_at = vim.uv.hrtime()
  service.inflight = {
    kind = payload.kind,
    request_id = payload.request_id,
    is_prewarm = payload.is_prewarm == true,
    preview_context_hash = payload.preview_context_hash,
    formula_remaining = payload.formula_count,
  }
  if payload.meta ~= nil then
    payload.meta.sent_at = sent_at
  end

  service.stdin:write(payload.message .. "\n", function(err)
    if err ~= nil then
      if service.inflight ~= nil and service.inflight.request_id == payload.request_id then
        service.inflight = nil
      end
      vim.schedule(function()
        mark_service_payload_failed(service.bufnr, payload, "stdin write failed")
        vim.notify("[math-conceal.image] failed to write compiler request: " .. tostring(err), vim.log.levels.ERROR)
        if send_next_service_payload ~= nil then
          send_next_service_payload(service)
        end
      end)
    end
  end)
  return true
end

--- @param bufnr integer
--- @param service typst_compiler_service
--- @param payload table
send_or_queue_service_payload = function(bufnr, service, payload)
  if service.inflight ~= nil then
    if payload.is_prewarm == true then
      service.preview_warmed_signatures = service.preview_warmed_signatures or {}
      if service.preview_warmed_signatures[payload.preview_context_hash] then
        return true
      end
      if service.inflight.preview_context_hash == payload.preview_context_hash then
        return true
      end
      service.pending_prewarm_requests = service.pending_prewarm_requests or {}
      for _, pending in ipairs(service.pending_prewarm_requests) do
        if pending.preview_context_hash == payload.preview_context_hash then
          return true
        end
      end
      service.pending_prewarm_requests[#service.pending_prewarm_requests + 1] = payload
    elseif payload.kind == "preview" then
      service.pending_preview_request = payload
    elseif payload.kind == "formula" then
      prune_pending_formula_requests(bufnr, service)
      if not formula_payload_has_current_jobs(bufnr, payload) then
        mark_service_payload_failed(bufnr, payload, "formula request superseded before send")
        return true
      end
      service.pending_formula_requests = service.pending_formula_requests or {}
      service.pending_formula_requests[#service.pending_formula_requests + 1] = payload
    else
      if service.pending_full_request ~= nil then
        supersede_full_service_request(bufnr, service.pending_full_request.meta, "pending full request superseded")
      end
      service.pending_full_request = payload
    end
    return true
  end

  return write_service_payload(service, payload)
end

--- @param bufnr integer
--- @param service_kind '"full"'|'"preview"'
--- @param request_id string
send_next_service_payload = function(service)
  if service == nil then
    return
  end
  local payload = service.pending_full_request
  service.pending_full_request = nil
  if payload == nil and service.pending_formula_requests ~= nil then
    prune_pending_formula_requests(service.bufnr, service)
    while payload == nil and service.pending_formula_requests ~= nil do
      local candidate = table.remove(service.pending_formula_requests, 1)
      if #service.pending_formula_requests == 0 then
        service.pending_formula_requests = nil
      end
      if formula_payload_has_current_jobs(service.bufnr, candidate) then
        payload = candidate
      else
        mark_service_payload_failed(service.bufnr, candidate, "formula request superseded before send")
      end
    end
  end
  if payload == nil then
    payload = service.pending_preview_request
    service.pending_preview_request = nil
  end
  if payload == nil and service.pending_prewarm_requests ~= nil then
    payload = table.remove(service.pending_prewarm_requests, 1)
    if #service.pending_prewarm_requests == 0 then
      service.pending_prewarm_requests = nil
    end
  end
  if payload ~= nil then
    local sent = write_service_payload(service, payload)
    if not sent then
      mark_service_payload_failed(service.bufnr, payload, "failed to send queued compiler request")
      send_next_service_payload(service)
    end
  end
end

--- @param bufnr integer
--- @param service_kind '"full"'|'"preview"'
--- @param request_id string
finish_service_response = function(bufnr, service_kind, request_id)
  local service = get_compiler_service(bufnr, service_kind)
  if service == nil then
    return
  end
  if service.inflight ~= nil and service.inflight.request_id == request_id then
    service.inflight = nil
  end
  send_next_service_payload(service)
end

--- @param bufnr integer
--- @param service typst_compiler_service|nil
--- @param jobs table[]|nil
--- @param project_scope table
--- @param config table
--- @param prelude_chunks string[]
--- @param preamble_include_line string
local function prewarm_preview_service(
  bufnr,
  service,
  jobs,
  project_scope,
  config,
  prelude_chunks,
  preamble_include_line
)
  if service == nil or service.dead == true then
    return
  end

  local inputs = extract_service_inputs(config, project_scope)
  local candidates = {}
  if jobs ~= nil and #jobs > 0 then
    for _, job in ipairs(jobs) do
      candidates[#candidates + 1] = make_preview_prewarm_item(job, bufnr, prelude_chunks)
    end
  else
    candidates[#candidates + 1] = make_preview_prewarm_item(nil, bufnr, prelude_chunks)
  end

  service.preview_warmed_signatures = service.preview_warmed_signatures or {}
  local seen = {}
  for _, item in ipairs(candidates) do
    local spec = build_preview_service_spec(bufnr, service, item, project_scope, prelude_chunks, preamble_include_line)
    if spec ~= nil and not seen[spec.context_hash] then
      seen[spec.context_hash] = true
      if not service.preview_warmed_signatures[spec.context_hash] then
        local request_id = ("preview-prewarm:%d:%s"):format(bufnr, spec.context_hash)
        local ok, msg = pcall(vim.json.encode, {
          type = "compile",
          request_id = request_id,
          cache_key = spec.cache_key,
          source_text = spec.source_text,
          root = project_scope.effective_root,
          inputs = inputs,
          output_dir = spec.cache_dir,
          ppi = state._render_ppi or config.ppi,
        })
        if ok then
          service.cache_dir = spec.cache_dir
          state.service_cache_dirs = state.service_cache_dirs or {}
          state.service_cache_dirs[bufnr] = spec.cache_dir
          send_or_queue_service_payload(bufnr, service, {
            kind = "preview",
            request_id = request_id,
            message = msg,
            is_prewarm = true,
            preview_context_hash = spec.context_hash,
            prepare = make_preview_sidecar_prepare(service, spec.sidecar_path, spec.sidecar_text),
          })
        else
          vim.schedule(function()
            vim.notify(
              "[math-conceal.image] failed to encode preview prewarm request: " .. tostring(msg),
              vim.log.levels.ERROR
            )
          end)
        end
      end
    end
  end
end

--- Stop a Rust compiler service and remove service-generated PNGs.
--- @param bufnr integer
--- @param kind '"full"'|'"preview"'|nil
function M.stop_compiler_service(bufnr, kind)
  local bucket = state.compiler_services and state.compiler_services[bufnr]
  if bucket == nil then
    cleanup_service_cache_dir(state.service_cache_dirs and state.service_cache_dirs[bufnr])
    M._cleanup_service_workspace_for_buf(bufnr)
    if state.service_cache_dirs then
      state.service_cache_dirs[bufnr] = nil
    end
    return
  end

  local kinds = kind and { kind } or { "full", "preview" }
  for _, service_kind in ipairs(kinds) do
    local service = bucket[service_kind]
    if service ~= nil then
      service.dead = true
      bucket[service_kind] = nil

      if service_kind == "full" and state.active_service_requests and state.active_service_requests[bufnr] then
        supersede_full_service_request(bufnr, state.active_service_requests[bufnr], "compiler service stopped")
      end
      if service_kind == "full" and state.active_formula_batches and state.active_formula_batches[bufnr] then
        local batches = vim.deepcopy(state.active_formula_batches[bufnr])
        for _, meta in pairs(batches or {}) do
          fail_formula_batch(bufnr, meta, "compiler service stopped")
        end
      end
      if service_kind == "preview" and state.active_preview_service_requests then
        state.active_preview_service_requests[bufnr] = nil
      end

      mark_service_payload_failed(bufnr, service.pending_full_request, "compiler service stopped")
      for _, payload in ipairs(service.pending_formula_requests or {}) do
        mark_service_payload_failed(bufnr, payload, "compiler service stopped")
      end
      mark_service_payload_failed(bufnr, service.pending_preview_request, "compiler service stopped")
      service.inflight = nil
      service.pending_full_request = nil
      service.pending_formula_requests = nil
      service.pending_preview_request = nil
      service.pending_prewarm_requests = nil

      if service.stdin ~= nil and not service.stdin:is_closing() then
        service.stdin:write(vim.json.encode({ type = "shutdown" }) .. "\n")
      end

      close_pipe(service.stdin)
      close_pipe(service.stdout)
      close_pipe(service.stderr)
      if service.handle ~= nil and not service.handle:is_closing() then
        service.handle:kill(15)
        service.handle:close()
      end
    end
  end

  if next(bucket) == nil then
    if state.compiler_services then
      state.compiler_services[bufnr] = nil
    end
    cleanup_service_cache_dir(state.service_cache_dirs and state.service_cache_dirs[bufnr])
    M._cleanup_service_workspace_for_buf(bufnr)
    if state.service_cache_dirs then
      state.service_cache_dirs[bufnr] = nil
    end
  end
end

--- Send per-node formula jobs as a transport batch to the compiler service.
--- Unlike render_request_via_service(), this does not install a buffer-global
--- active request.  The batch is only IO bookkeeping; each job remains owned by
--- its node/candidate overlay in the machine state.
--- @param bufnr integer
--- @param request RenderRequest
function M.render_formula_batch_via_service(bufnr, request)
  local meta = build_render_request_meta(request)
  meta.formula_transport_only = true
  meta.pending_formula_count = #((request and request.jobs) or {})
  meta.formula_response_count = 0
  meta.formula_dispatched = 0
  meta.formula_failed = 0
  meta.formula_cached = 0

  local service = M.ensure_compiler_service(bufnr, "full")
  if service == nil or service.stdin == nil or service.stdin:is_closing() then
    fail_formula_batch(bufnr, meta, "compiler service unavailable")
    return
  end

  local project_scope = require("math-conceal.image.project-scope").resolve(bufnr, "full")
  local main = require("math-conceal.image")
  local config = main.config
  reconcile_formula_diagnostics_for_request(bufnr)
  local prelude_chunks = snapshot_full_context_preludes(bufnr)
  local preamble_include_line = resolve_preamble_include_line(bufnr, project_scope.effective_root, "full")
  local is_latex = project_scope.backend_id == "latex"
  local latex_fast_path = is_latex and latex_mitex_fast_path_enabled(config)
  local latex_fallback_spec = nil
  local spec
  if latex_fast_path then
    latex_fallback_spec = build_latex_formula_service_spec(request, project_scope, config)
    spec = build_latex_mitex_formula_service_spec(request, project_scope, config)
  elseif is_latex then
    spec = build_latex_formula_service_spec(request, project_scope, config)
  else
    spec = build_formula_service_spec(request, project_scope, prelude_chunks, preamble_include_line, config)
  end
  local preview_service = nil
  if not is_latex then
    preview_service = M.ensure_compiler_service(bufnr, "preview")
  end

  service.cache_dir = spec.output_dir
  state.service_cache_dirs = state.service_cache_dirs or {}
  state.service_cache_dirs[bufnr] = spec.output_dir
  state.service_workspace_dirs = state.service_workspace_dirs or {}
  state.service_workspace_dirs[bufnr] = spec.workspace.root

  meta.slot_line_maps = spec.slot_line_maps
  meta.formula_line_maps = spec.formula_line_maps
  meta.formula_line_offsets = spec.formula_line_offsets
  meta.generated_slot_paths = spec.generated_slot_paths
  meta.generated_node_paths = spec.generated_node_paths
  meta.project_scope_id = project_scope.project_scope_id or meta.project_scope_id
  meta.buf_dir = project_scope.buf_dir
  meta.source_root = project_scope.source_root
  meta.effective_root = project_scope.effective_root
  meta.generated_input_path = spec.generated_input_path
  meta.generated_context_path = spec.generated_context_path
  meta.context_id = spec.context_id
  meta.context_rev = spec.context_rev
  meta.service_engine = latex_fast_path and "latex-mitex" or (is_latex and "latex" or "formula")
  meta.render_ppi = state._render_ppi or config.ppi
  if latex_fast_path then
    local latex_config = (config.backends and config.backends.latex) or {}
    meta.latex_mitex_fallback = true
    meta.latex_fallback_spec = latex_fallback_spec
    meta.latex_config = {
      compiler = latex_config.compiler,
      converter = latex_config.converter,
      compiler_args = latex_config.compiler_args or {},
    }
    meta.latex_compiler_args = project_scope.compiler_args or latex_config.compiler_args or {}
  end
  meta.pending_formula_count = #(spec.nodes or {})

  active_formula_batches(bufnr)[request.request_id] = meta

  if #(spec.nodes or {}) == 0 then
    remove_formula_batch_meta(bufnr, request.request_id, meta)
    if not is_latex then
      prewarm_preview_service(
        bufnr,
        preview_service,
        request.jobs,
        project_scope,
        config,
        prelude_chunks,
        preamble_include_line
      )
    end
    return
  end

  local inputs = (is_latex and not latex_fast_path) and vim.empty_dict()
    or extract_service_inputs(config, project_scope)
  local latex_config = (config.backends and config.backends.latex) or {}
  local formula_worker_count = math.max(1, math.floor(tonumber(config.formula_worker_count) or 1))
  local ok, msg = pcall(vim.json.encode, {
    type = "render_formulas",
    backend = (is_latex and not latex_fast_path) and "latex" or "typst",
    request_id = request.request_id,
    cache_key = spec.cache_key,
    context_id = spec.context_id,
    context_rev = spec.context_rev,
    context_source = spec.context_source,
    root = project_scope.effective_root,
    inputs = inputs,
    output_dir = spec.output_dir,
    ppi = state._render_ppi or config.ppi,
    worker_count = formula_worker_count,
    compiler = (is_latex and not latex_fast_path) and latex_config.compiler or nil,
    converter = (is_latex and not latex_fast_path) and latex_config.converter or nil,
    compiler_args = (is_latex and not latex_fast_path)
        and (project_scope.compiler_args or latex_config.compiler_args or {})
      or nil,
    nodes = spec.nodes,
  })
  if not ok then
    fail_formula_batch(bufnr, meta, "failed to encode formula request")
    vim.schedule(function()
      vim.notify("[math-conceal.image] failed to encode formula request: " .. tostring(msg), vim.log.levels.ERROR)
    end)
    return
  end

  local sent = send_or_queue_service_payload(bufnr, service, {
    kind = "formula",
    request_id = request.request_id,
    message = msg,
    meta = meta,
    formula_count = #(spec.nodes or {}),
  })
  if not sent then
    fail_formula_batch(bufnr, meta, "failed to send formula request")
    return
  end

  if not is_latex then
    prewarm_preview_service(
      bufnr,
      preview_service,
      request.jobs,
      project_scope,
      config,
      prelude_chunks,
      preamble_include_line
    )
  end
end

--- Send a machine-owned full render request to the compiler service.
--- @param bufnr integer
--- @param request RenderRequest
function M.render_request_via_service(bufnr, request)
  local early_meta = build_render_request_meta(request)
  local service = M.ensure_compiler_service(bufnr, "full")
  if service == nil or service.stdin == nil or service.stdin:is_closing() then
    fail_full_service_request(bufnr, early_meta, "compiler service unavailable")
    return
  end
  local preview_service = nil

  local project_scope = require("math-conceal.image.project-scope").resolve(bufnr, "full")
  local main = require("math-conceal.image")
  local config = main.config
  local prelude_chunks = snapshot_full_context_preludes(bufnr)
  local preamble_include_line = resolve_preamble_include_line(bufnr, project_scope.effective_root, "full")
  local is_latex = project_scope.backend_id == "latex"
  local latex_fast_path = is_latex and latex_mitex_fast_path_enabled(config)
  local use_formula_service = is_latex or config.use_formula_service ~= false
  if use_formula_service then
    reconcile_formula_diagnostics_for_request(bufnr)
  end
  local latex_fallback_spec = nil
  local spec
  if use_formula_service and latex_fast_path then
    latex_fallback_spec = build_latex_formula_service_spec(request, project_scope, config)
    spec = build_latex_mitex_formula_service_spec(request, project_scope, config)
  elseif use_formula_service and is_latex then
    spec = build_latex_formula_service_spec(request, project_scope, config)
  elseif use_formula_service then
    spec = build_formula_service_spec(request, project_scope, prelude_chunks, preamble_include_line, config)
  else
    spec = build_full_service_spec(request, project_scope, prelude_chunks, preamble_include_line, config)
  end
  -- Start the preview backend with the same buffer/project lifetime so the
  -- first cursor preview does not pay process startup while full rendering is
  -- busy. It compiles only preview requests, so it cannot block full updates.
  if not is_latex then
    preview_service = M.ensure_compiler_service(bufnr, "preview")
  end
  service.cache_dir = spec.output_dir
  state.service_cache_dirs = state.service_cache_dirs or {}
  state.service_cache_dirs[bufnr] = spec.output_dir
  state.service_workspace_dirs = state.service_workspace_dirs or {}
  state.service_workspace_dirs[bufnr] = spec.workspace.root

  local current_request = build_render_request_meta(request)
  current_request.line_map = nil
  current_request.slot_line_maps = spec.slot_line_maps
  current_request.formula_line_maps = spec.formula_line_maps
  current_request.formula_line_offsets = spec.formula_line_offsets
  current_request.generated_slot_paths = spec.generated_slot_paths
  current_request.generated_node_paths = spec.generated_node_paths
  current_request.project_scope_id = project_scope.project_scope_id or current_request.project_scope_id
  current_request.buf_dir = project_scope.buf_dir
  current_request.source_root = project_scope.source_root
  current_request.effective_root = project_scope.effective_root
  current_request.generated_input_path = spec.generated_input_path
  current_request.generated_context_path = spec.generated_context_path
  current_request.service_engine = latex_fast_path and "latex-mitex"
    or (is_latex and "latex" or (use_formula_service and "formula" or "typst"))
  current_request.render_ppi = state._render_ppi or config.ppi
  if use_formula_service then
    current_request.pending_formula_count = #(spec.nodes or {})
    current_request.formula_response_count = 0
    current_request.formula_dispatched = 0
    current_request.formula_failed = 0
    current_request.formula_cached = 0
    if latex_fast_path then
      local latex_config = (config.backends and config.backends.latex) or {}
      current_request.latex_mitex_fallback = true
      current_request.latex_fallback_spec = latex_fallback_spec
      current_request.latex_config = {
        compiler = latex_config.compiler,
        converter = latex_config.converter,
        compiler_args = latex_config.compiler_args or {},
      }
      current_request.latex_compiler_args = project_scope.compiler_args or latex_config.compiler_args or {}
    end
  end

  local old = state.active_service_requests and state.active_service_requests[bufnr]
  if old ~= nil then
    old.status = "abandoned"
  end
  state.active_service_requests = state.active_service_requests or {}
  current_request.queued_at = vim.uv.hrtime()
  state.active_service_requests[bufnr] = current_request

  if config.do_diagnostics then
    clear_quickfix(bufnr, "full")
  end

  if use_formula_service and #(spec.nodes or {}) == 0 then
    require("math-conceal.image.machine.runtime").dispatch({
      type = "render_request_completed",
      bufnr = bufnr,
      request_id = request.request_id,
    })
    if state.active_service_requests[bufnr] == current_request then
      current_request.status = "completed"
      state.active_service_requests[bufnr] = nil
    end
    if not is_latex then
      prewarm_preview_service(
        bufnr,
        preview_service,
        request.jobs,
        project_scope,
        config,
        prelude_chunks,
        preamble_include_line
      )
    end
    return
  end

  local formula_worker_count = math.max(1, math.floor(tonumber(config.formula_worker_count) or 1))
  local latex_config = (config.backends and config.backends.latex) or {}
  local inputs = (is_latex and not latex_fast_path) and vim.empty_dict()
    or extract_service_inputs(config, project_scope)
  local message = use_formula_service
      and {
        type = "render_formulas",
        backend = (is_latex and not latex_fast_path) and "latex" or "typst",
        request_id = request.request_id,
        cache_key = spec.cache_key,
        context_id = spec.context_id,
        context_rev = spec.context_rev,
        context_source = spec.context_source,
        root = project_scope.effective_root,
        inputs = inputs,
        output_dir = spec.output_dir,
        ppi = state._render_ppi or config.ppi,
        worker_count = formula_worker_count,
        compiler = (is_latex and not latex_fast_path) and latex_config.compiler or nil,
        converter = (is_latex and not latex_fast_path) and latex_config.converter or nil,
        compiler_args = (is_latex and not latex_fast_path)
            and (project_scope.compiler_args or latex_config.compiler_args or {})
          or nil,
        nodes = spec.nodes,
      }
    or {
      type = "compile",
      request_id = request.request_id,
      cache_key = spec.cache_key,
      source_text = spec.source_text,
      root = project_scope.effective_root,
      inputs = inputs,
      output_dir = spec.output_dir,
      ppi = state._render_ppi or config.ppi,
    }

  local ok, msg = pcall(vim.json.encode, message)
  if not ok then
    fail_full_service_request(bufnr, current_request, "failed to encode compiler request")
    vim.schedule(function()
      vim.notify("[math-conceal.image] failed to encode compiler request: " .. tostring(msg), vim.log.levels.ERROR)
    end)
    return
  end

  local sent = send_or_queue_service_payload(bufnr, service, {
    kind = "full",
    request_id = request.request_id,
    message = msg,
    meta = current_request,
    formula_count = use_formula_service and #(spec.nodes or {}) or nil,
    prepare = (not use_formula_service) and make_full_sidecar_prepare(service, spec.writes) or nil,
    on_prepare_failed = function(err)
      fail_full_service_request(bufnr, current_request, "failed to prepare sidecars: " .. tostring(err))
    end,
  })
  if not sent then
    fail_full_service_request(bufnr, current_request, "failed to send compiler request")
    return
  end

  if not is_latex then
    prewarm_preview_service(
      bufnr,
      preview_service,
      request.jobs,
      project_scope,
      config,
      prelude_chunks,
      preamble_include_line
    )
  end
end

--- Send a preview item to the compiler service for rendering.
--- @param bufnr integer
--- @param item table  preview item from allocate_preview_item
function M.render_preview_tail_via_service(bufnr, item)
  local service = M.ensure_compiler_service(bufnr, "preview")
  if service == nil or service.stdin == nil or service.stdin:is_closing() then
    return
  end

  local project_scope = require("math-conceal.image.project-scope").resolve(bufnr, "full")
  if project_scope.backend_id == "latex" then
    local main = require("math-conceal.image")
    local config = main.config
    local request_id = item.preview_request_id
    if request_id == nil then
      return
    end

    local latex_config = (config.backends and config.backends.latex) or {}
    local preview_meta = {
      request_id = request_id,
      item = item,
      queued_at = vim.uv.hrtime(),
    }
    local cache_dir = nil
    local formula_count = nil
    local prepare = nil
    local ok, msg

    if latex_mitex_fast_path_enabled(config) then
      local fast_item = build_latex_mitex_item(item, latex_mitex_prelude(project_scope, config))
      local spec = build_preview_service_spec(bufnr, service, fast_item, project_scope, {}, nil)
      if spec == nil then
        return
      end

      local fallback_spec = build_latex_preview_service_spec(bufnr, item, project_scope, config)
      local fallback_ok, fallback_msg = pcall(vim.json.encode, {
        type = "render_formulas",
        backend = "latex",
        request_id = request_id,
        cache_key = fallback_spec.cache_key,
        context_id = fallback_spec.context_id,
        context_rev = fallback_spec.context_rev,
        context_source = fallback_spec.context_source,
        root = project_scope.effective_root,
        inputs = vim.empty_dict(),
        output_dir = fallback_spec.output_dir,
        ppi = state._render_ppi or config.ppi,
        worker_count = 1,
        compiler = latex_config.compiler,
        converter = latex_config.converter,
        compiler_args = project_scope.compiler_args or latex_config.compiler_args or {},
        nodes = fallback_spec.nodes,
      })
      if not fallback_ok then
        vim.schedule(function()
          vim.notify(
            "[math-conceal.image] failed to encode LaTeX preview fallback request: " .. tostring(fallback_msg),
            vim.log.levels.ERROR
          )
        end)
        return
      end
      preview_meta.latex_preview_fallback = {
        message = fallback_msg,
        output_dir = fallback_spec.output_dir,
        formula_count = #(fallback_spec.nodes or {}),
      }

      ok, msg = pcall(vim.json.encode, {
        type = "compile",
        request_id = request_id,
        cache_key = spec.cache_key,
        source_text = spec.source_text,
        root = project_scope.effective_root,
        inputs = extract_service_inputs(config, project_scope),
        output_dir = spec.cache_dir,
        ppi = state._render_ppi or config.ppi,
      })
      cache_dir = spec.cache_dir
      prepare = make_preview_sidecar_prepare(service, spec.sidecar_path, spec.sidecar_text)
    else
      local spec = build_latex_preview_service_spec(bufnr, item, project_scope, config)
      ok, msg = pcall(vim.json.encode, {
        type = "render_formulas",
        backend = "latex",
        request_id = request_id,
        cache_key = spec.cache_key,
        context_id = spec.context_id,
        context_rev = spec.context_rev,
        context_source = spec.context_source,
        root = project_scope.effective_root,
        inputs = vim.empty_dict(),
        output_dir = spec.output_dir,
        ppi = state._render_ppi or config.ppi,
        worker_count = 1,
        compiler = latex_config.compiler,
        converter = latex_config.converter,
        compiler_args = project_scope.compiler_args or latex_config.compiler_args or {},
        nodes = spec.nodes,
      })
      cache_dir = spec.output_dir
      formula_count = #(spec.nodes or {})
    end
    if not ok then
      vim.schedule(function()
        vim.notify(
          "[math-conceal.image] failed to encode LaTeX preview request: " .. tostring(msg),
          vim.log.levels.ERROR
        )
      end)
      return
    end

    state.active_preview_service_requests = state.active_preview_service_requests or {}
    state.active_preview_service_requests[bufnr] = preview_meta

    service.cache_dir = cache_dir
    state.service_cache_dirs = state.service_cache_dirs or {}
    state.service_cache_dirs[bufnr] = cache_dir

    local sent = send_or_queue_service_payload(bufnr, service, {
      kind = "preview",
      request_id = request_id,
      message = msg,
      meta = preview_meta,
      formula_count = formula_count,
      prepare = prepare,
      on_prepare_failed = function()
        local active = state.active_preview_service_requests and state.active_preview_service_requests[bufnr]
        if active ~= nil and active.request_id == request_id then
          state.active_preview_service_requests[bufnr] = nil
        end
      end,
    })
    if not sent then
      local active = state.active_preview_service_requests and state.active_preview_service_requests[bufnr]
      if active ~= nil and active.request_id == request_id then
        state.active_preview_service_requests[bufnr] = nil
      end
    end
    return
  end
  local main = require("math-conceal.image")
  local config = main.config
  local prelude_chunks = snapshot_full_context_preludes(bufnr)
  local preamble_include_line = resolve_preamble_include_line(bufnr, project_scope.effective_root, "full")
  local spec = build_preview_service_spec(bufnr, service, item, project_scope, prelude_chunks, preamble_include_line)
  if spec == nil then
    return
  end

  local request_id = item.preview_request_id
  if request_id == nil then
    return
  end

  -- Track the preview request so the response handler can route it.
  state.active_preview_service_requests = state.active_preview_service_requests or {}
  local preview_meta = {
    request_id = request_id,
    item = item,
    queued_at = vim.uv.hrtime(),
  }
  state.active_preview_service_requests[bufnr] = preview_meta

  local inputs = extract_service_inputs(config, project_scope)
  service.cache_dir = spec.cache_dir
  state.service_cache_dirs = state.service_cache_dirs or {}
  state.service_cache_dirs[bufnr] = spec.cache_dir

  local ok, msg = pcall(vim.json.encode, {
    type = "compile",
    request_id = request_id,
    cache_key = spec.cache_key,
    source_text = spec.source_text,
    root = project_scope.effective_root,
    inputs = inputs,
    output_dir = spec.cache_dir,
    ppi = state._render_ppi or config.ppi,
  })
  if not ok then
    vim.schedule(function()
      vim.notify("[math-conceal.image] failed to encode preview request: " .. tostring(msg), vim.log.levels.ERROR)
    end)
    return
  end

  local prepare = nil
  if spec.sidecar_path ~= nil then
    prepare = make_preview_sidecar_prepare(service, spec.sidecar_path, spec.sidecar_text)
  end

  local sent = send_or_queue_service_payload(bufnr, service, {
    kind = "preview",
    request_id = request_id,
    message = msg,
    meta = preview_meta,
    preview_context_hash = spec.context_hash,
    prepare = prepare,
    on_prepare_failed = function()
      local active = state.active_preview_service_requests and state.active_preview_service_requests[bufnr]
      if active ~= nil and active.request_id == request_id then
        state.active_preview_service_requests[bufnr] = nil
      end
    end,
  })
  if not sent then
    state.active_preview_service_requests[bufnr] = nil
  end
end

return M
