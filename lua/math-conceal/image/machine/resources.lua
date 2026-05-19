--- Resource allocation/release helpers for machine-owned overlays.
--- This is the **single entry point** for writing to the three index tables:
---   state.image_ids_in_use, state.image_id_to_extmark, state.item_by_image_id

local state = require("typst-concealer.state")

local M = {}

--- Allocate a new terminal image id for a buffer.
--- @param bufnr integer
--- @return integer
function M.allocate_image_id(bufnr)
  local pid = state.pid
  for i = pid, 2 ^ 16 + pid - 1 do
    if state.image_ids_in_use[i] == nil then
      state.image_ids_in_use[i] = bufnr
      return i
    end
  end
  print(
    "[typst-concealer] >65536 image ids in use, overflowing. "
      .. "This is probably a bug, you're looking at a very long document or a lot of documents.\n"
      .. "Open an issue if you see this, the cap can be increased if someone actually needs it.\n"
  )
  state.image_ids_in_use = {}
  return M.allocate_image_id(bufnr)
end

--- @param bufnr integer
--- @param image_id integer
--- @param range Range4
--- @param extmark_id integer|nil
--- @param concealing boolean|nil
--- @param semantics NodeSemantics
--- @return integer
function M.place_overlay_extmark(bufnr, image_id, range, extmark_id, concealing, semantics)
  return require("typst-concealer.extmark").place_render_extmark(
    bufnr,
    image_id,
    range,
    extmark_id,
    concealing,
    semantics
  )
end

--- Release a single image_id from all three index tables and clear the terminal image.
--- @param image_id integer|nil
function M.release_image_id(image_id)
  if image_id == nil then
    return
  end
  require("typst-concealer.extmark").clear_image_only(image_id)
  state.image_id_to_extmark[image_id] = nil
  state.item_by_image_id[image_id] = nil
  state.image_ids_in_use[image_id] = nil
end

--- Release a machine-owned image/extmark pair.
--- @param bufnr integer
--- @param image_id integer|nil
--- @param extmark_id integer|nil
function M.release_overlay_resources(bufnr, image_id, extmark_id)
  if extmark_id ~= nil then
    state.prepare_extmark_reuse(bufnr, extmark_id)
    pcall(vim.api.nvim_buf_del_extmark, bufnr, state.ns_id, extmark_id)
  end
  M.release_image_id(image_id)
end

--- Register an item in the index tables (item_by_image_id + image_id_to_extmark).
--- @param image_id integer
--- @param item table|nil  when non-nil, updates the item mapping
--- @param extmark_id integer|nil  when non-nil, updates the extmark mapping
function M.bind_image_id(image_id, item, extmark_id)
  if item ~= nil then
    state.item_by_image_id[image_id] = item
  end
  if extmark_id ~= nil then
    state.image_id_to_extmark[image_id] = extmark_id
  end
end

--- Unbind an image_id from the item/extmark index tables without releasing the
--- underlying terminal image or image_ids_in_use slot.
--- @param image_id integer|nil
--- @param extmark_id integer|nil  only clears extmark mapping if it matches
function M.unbind_image_id(image_id, extmark_id)
  if image_id == nil then
    return
  end
  state.item_by_image_id[image_id] = nil
  if extmark_id == nil or state.image_id_to_extmark[image_id] == extmark_id then
    state.image_id_to_extmark[image_id] = nil
  end
end

--- Atomically rebuild item_by_image_id and image_id_to_extmark from machine
--- state for a single buffer.  Called after commit/bind/retire batches.
--- @param machine_state MachineState
--- @param bufnr integer
--- @param build_compat_item function  runtime.build_compat_item
function M.rebuild_indices(machine_state, bufnr, build_compat_item)
  local buf = machine_state.buffers[bufnr]

  -- Clear stale entries from previous full_items for this buffer.
  local bstate = state.buffer_render_state[bufnr] or {}
  for _, item in ipairs(bstate.full_items or {}) do
    if item.image_id ~= nil then
      state.item_by_image_id[item.image_id] = nil
      if state.image_id_to_extmark[item.image_id] == item.extmark_id then
        state.image_id_to_extmark[item.image_id] = nil
      end
    end
  end
  for _, item in ipairs(bstate.lingering_items or {}) do
    if item.image_id ~= nil then
      state.item_by_image_id[item.image_id] = nil
      if state.image_id_to_extmark[item.image_id] == item.extmark_id then
        state.image_id_to_extmark[item.image_id] = nil
      end
    end
  end

  -- Rebuild from machine state.
  state.buffer_render_state[bufnr] = bstate
  local full_items = {}
  local line_to_items = {}
  local extmark_to_item = {}

  if buf ~= nil then
    for _, node_id in ipairs(buf.node_order or {}) do
      local node = buf.nodes[node_id]
      local overlay = node and node.visible_overlay_id and machine_state.overlays[node.visible_overlay_id] or nil
      if overlay ~= nil and overlay.status == "visible" then
        local item = build_compat_item(machine_state, node, overlay)
        if item ~= nil then
          full_items[#full_items + 1] = item
          state.item_by_image_id[item.image_id] = item
          state.image_id_to_extmark[item.image_id] = item.extmark_id
          -- index per-line
          if item.extmark_id ~= nil and item.range ~= nil then
            extmark_to_item[item.extmark_id] = item
            for row = item.range[1], item.range[3] do
              line_to_items[row] = line_to_items[row] or {}
              line_to_items[row][#line_to_items[row] + 1] = item
            end
          end
        end
      end
    end
  end

  bstate.full_items = full_items
  bstate.lingering_items = {}
  bstate.line_to_items = line_to_items
  bstate.extmark_to_item = extmark_to_item
end

return M
