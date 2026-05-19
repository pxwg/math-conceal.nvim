--- Effect annotations emitted by the full-overlay reducer.

local M = {}

--- @class EffectEnsureOverlayPlaceholder
--- @field kind "ensure_overlay_placeholder"
--- @field overlay_id string
--- @field bufnr integer
--- @field node_id string
--- @field display_range Range4
--- @field semantics NodeSemantics

--- @class EffectRequestFullRender
--- @field kind "request_full_render"
--- @field request RenderRequest

--- @class EffectCommitOverlay
--- @field kind "commit_overlay"
--- @field overlay_id string
--- @field node_id string
--- @field bufnr integer
--- @field page_path string
--- @field natural_cols integer
--- @field natural_rows integer
--- @field source_rows integer

--- @class EffectBindOverlay
--- @field kind "bind_overlay"
--- @field overlay_id string
--- @field request_id string|nil
--- @field node_id string
--- @field bufnr integer
--- @field buffer_version integer
--- @field layout_version integer
--- @field display_range Range4
--- @field semantics NodeSemantics

--- @class EffectRetireOverlay
--- @field kind "retire_overlay"
--- @field overlay_id string

--- @class EffectRerenderBuffer
--- @field kind "rerender_buffer"
--- @field bufnr integer

--- @class EffectAbandonRequest
--- @field kind "abandon_request"
--- @field bufnr integer
--- @field old_request_id string
--- @field new_request_id string|nil

--- @alias MachineEffect
--- | EffectEnsureOverlayPlaceholder
--- | EffectRequestFullRender
--- | EffectCommitOverlay
--- | EffectBindOverlay
--- | EffectRetireOverlay
--- | EffectRerenderBuffer
--- | EffectAbandonRequest

return M
