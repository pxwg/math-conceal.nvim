--- Formula artifact / terminal image state.
---
--- A FormulaImage owns the upload epoch for one rendered formula artifact.
--- Placements keep extmarks and source ranges; this object tracks whether the
--- backing PNG has been sent to the terminal for the current terminal epoch.

local state = require("typst-concealer.state")

local M = {}
M.__index = M

local function artifact_key(spec)
  return spec.artifact_key
    or spec.page_stamp
    or spec.page_path
    or (spec.overlay_id and ("overlay:" .. tostring(spec.overlay_id)))
    or (spec.image_id and ("image:" .. tostring(spec.image_id)))
end

function M.new(spec)
  spec = spec or {}
  return setmetatable({
    artifact_key = artifact_key(spec),
    page_path = spec.page_path,
    page_stamp = spec.page_stamp,
    image_id = spec.image_id,
    natural_cols = spec.natural_cols,
    natural_rows = spec.natural_rows,
    source_rows = spec.source_rows,
    sent_epoch = spec.sent_epoch,
    placements = {},
  }, M)
end

function M:update(spec)
  spec = spec or {}
  self.artifact_key = artifact_key(spec) or self.artifact_key
  self.page_path = spec.page_path or self.page_path
  self.page_stamp = spec.page_stamp or self.page_stamp
  self.image_id = spec.image_id or self.image_id
  self.natural_cols = spec.natural_cols or self.natural_cols
  self.natural_rows = spec.natural_rows or self.natural_rows
  self.source_rows = spec.source_rows or self.source_rows
  if spec.sent_epoch ~= nil then
    self.sent_epoch = spec.sent_epoch
  end
end

function M:attach(placement)
  if placement ~= nil then
    self.placements[placement.placement_id] = placement
  end
end

function M:detach(placement)
  if placement ~= nil then
    self.placements[placement.placement_id] = nil
  end
end

function M:is_ready()
  return self.image_id ~= nil and self.page_path ~= nil and self.natural_cols ~= nil and self.natural_rows ~= nil
end

function M:needs_upload(opts)
  opts = opts or {}
  return opts.force_reupload == true or self.sent_epoch ~= state.terminal_upload_epoch
end

function M:upload(opts)
  opts = opts or {}
  if not self:is_ready() then
    return false
  end
  if opts.force ~= true and not self:needs_upload(opts) then
    return false
  end

  require("typst-concealer.extmark").create_image(self.page_path, self.image_id, self.natural_cols, self.natural_rows)
  self.sent_epoch = state.terminal_upload_epoch
  return true
end

function M:conceal(bufnr, source_rows, opts)
  if not self:is_ready() then
    return false
  end
  require("typst-concealer.extmark").conceal_for_image_id(
    bufnr,
    self.image_id,
    self.natural_cols,
    self.natural_rows,
    source_rows or self.source_rows or 1,
    opts
  )
  return true
end

return M
