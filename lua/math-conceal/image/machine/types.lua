--- Shared type annotations and constructors for the full-overlay state machine.

local M = {}

--- @alias NodeStatus
--- | "stable"
--- | "stale"
--- | "pending"
--- | "ready"
--- | "orphaned"
--- | "deleted_confirmed"

--- @alias OverlayStatus
--- | "placeholder"
--- | "rendering"
--- | "ready"
--- | "visible"
--- | "retiring"
--- | "retired"

--- @alias SlotStatus
--- | "dirty"
--- | "clean"
--- | "tombstone"

--- @alias RenderRequestStatus
--- | "active"
--- | "abandoned"
--- | "completed"
--- | "failed"
--- | "superseded"

--- @alias NodeType "math" | "code"
--- @alias ConstraintKind "intrinsic" | "flow"
--- @alias DisplayKind "inline" | "block"

--- @class Range4
--- @field [1] integer
--- @field [2] integer
--- @field [3] integer
--- @field [4] integer

--- @class ProjectScope
--- @field project_scope_id string
--- @field source_root string
--- @field effective_root string
--- @field inputs_signature string
--- @field preamble_signature string
--- @field context_signature string
--- @field buf_dir string|nil
--- @field buf_path string|nil
--- @field cwd string|nil
--- @field inputs string[]|nil
--- @field preamble_path string|nil

--- @class NodeSemantics
--- @field constraint_kind ConstraintKind
--- @field display_kind DisplayKind
--- @field render_whole_line boolean?

--- @class NodeState
--- @field node_id string
--- @field slot_id string|nil
--- @field stable_key string|nil
--- @field bufnr integer
--- @field project_scope_id string
--- @field item_idx integer
--- @field node_type NodeType
--- @field backend_node_type string|nil
--- @field source_range Range4
--- @field display_range Range4
--- @field display_prefix string|nil
--- @field display_suffix string|nil
--- @field source_text string
--- @field source_str string|nil
--- @field source_text_hash string
--- @field node_rev integer
--- @field requires_mitex boolean|nil
--- @field render_in_coverage boolean|nil
--- @field render_priority number|nil
--- @field context_hash string
--- @field prelude_count integer
--- @field semantics NodeSemantics
--- @field status NodeStatus
--- @field visible_overlay_id string|nil
--- @field candidate_overlay_id string|nil
--- @field last_rendered_epoch integer|nil
--- @field last_buffer_version integer
--- @field last_layout_version integer
--- @field missing_since_buffer_version integer|nil

--- @class SlotState
--- @field slot_id string
--- @field page_index integer
--- @field node_id string|nil
--- @field source_text string
--- @field source_str string|nil
--- @field source_text_hash string|nil
--- @field requires_mitex boolean|nil
--- @field source_range Range4|nil
--- @field source_rows integer
--- @field context_hash string|nil
--- @field prelude_count integer
--- @field node_type NodeType|nil
--- @field semantics NodeSemantics|nil
--- @field display_range Range4|nil
--- @field visible_overlay_id string|nil
--- @field candidate_overlay_id string|nil
--- @field status SlotStatus
--- @field dirty boolean|nil
--- @field pending_request_id string|nil

--- @class OverlayState
--- @field overlay_id string
--- @field slot_id string|nil
--- @field owner_node_id string
--- @field owner_bufnr integer
--- @field owner_project_scope_id string
--- @field request_id string|nil
--- @field page_index integer|nil
--- @field session_id string|nil
--- @field render_epoch integer
--- @field node_rev integer|nil
--- @field context_id string|nil
--- @field context_rev integer|nil
--- @field source_text_hash string|nil
--- @field buffer_version integer
--- @field layout_version integer
--- @field extmark_id integer|nil
--- @field image_id integer|nil
--- @field page_path string|nil
--- @field page_stamp string|nil
--- @field natural_cols integer|nil
--- @field natural_rows integer|nil
--- @field source_rows integer|nil
--- @field terminal_upload_epoch integer|nil
--- @field binding_buffer_version integer|nil
--- @field binding_layout_version integer|nil
--- @field binding_display_range Range4|nil
--- @field status OverlayStatus

--- @class EventNodeDeletedConfirmed
--- @field type "node_deleted_confirmed"
--- @field bufnr integer
--- @field node_id string

--- @class EventOverlayResourcesAllocated
--- @field type "overlay_resources_allocated"
--- @field overlay_id string
--- @field image_id integer|nil
--- @field extmark_id integer|nil
--- @field binding_buffer_version integer|nil
--- @field binding_layout_version integer|nil
--- @field binding_display_range Range4|nil

--- @class EventOverlayBindingsBatchSucceeded
--- @field type "overlay_bindings_batch_succeeded"
--- @field entries table[]

--- @class BufferState
--- @field bufnr integer
--- @field project_scope_id string
--- @field buffer_version integer
--- @field layout_version integer
--- @field render_epoch integer
--- @field active_request_id string|nil
--- @field nodes table<string, NodeState>
--- @field node_order string[]
--- @field slots table<string, SlotState>
--- @field slot_order string[]
--- @field next_slot_id integer
--- @field shape_epoch integer
--- @field render_context_hash string|nil
--- @field context_id string|nil
--- @field context_rev integer

--- @class MachineCounters
--- @field next_node_id integer
--- @field next_overlay_id integer
--- @field next_request_id integer

--- @class MachineState
--- @field buffers table<integer, BufferState>
--- @field projects table<string, ProjectScope>
--- @field overlays table<string, OverlayState>
--- @field ui MachineUIState
--- @field counters MachineCounters

--- @class MachineUIHoverState
--- @field last_cursor_row integer|nil
--- @field last_cursor_col integer|nil
--- @field last_mode string|nil
--- @field last_lo integer|nil
--- @field last_hi integer|nil
--- @field invalidated boolean

--- @class MachineUIPreviewState
--- @field sync_tick integer|nil
--- @field sync_needs_full boolean
--- @field render_key string|nil
--- @field last_render_key string|nil
--- @field active_request_id string|nil
--- @field next_request_id integer
--- @field status "idle"|"rendering"|"ready"

--- @class MachineUIBufferState
--- @field hover MachineUIHoverState
--- @field preview MachineUIPreviewState

--- @class MachineUIState
--- @field buffers table<integer, MachineUIBufferState>

--- @class ScannedNode
--- @field stable_key string|nil
--- @field item_idx integer
--- @field node_type NodeType
--- @field source_range Range4
--- @field display_range Range4
--- @field display_prefix string|nil
--- @field display_suffix string|nil
--- @field source_text string
--- @field source_text_hash string
--- @field context_hash string
--- @field prelude_count integer
--- @field semantics NodeSemantics
--- @field render_in_coverage boolean|nil
--- @field render_priority number|nil

--- @class RenderJob
--- @field request_id string
--- @field request_page_index integer
--- @field overlay_id string
--- @field slot_id string|nil
--- @field node_id string
--- @field bufnr integer
--- @field project_scope_id string
--- @field render_epoch integer
--- @field node_rev integer|nil
--- @field context_id string|nil
--- @field context_rev integer|nil
--- @field buffer_version integer
--- @field layout_version integer
--- @field item_idx integer
--- @field range Range4
--- @field display_range Range4
--- @field source_text string
--- @field source_text_hash string|nil
--- @field backend_node_type string|nil
--- @field str string
--- @field prelude_count integer
--- @field semantics NodeSemantics
--- @field display_prefix string|nil
--- @field display_suffix string|nil
--- @field image_id integer
--- @field extmark_id integer|nil
--- @field is_stub boolean|nil
--- @field is_tombstone boolean|nil
--- @field slot_status SlotStatus|nil
--- @field slot_dirty boolean|nil

--- @class RenderRequest
--- @field request_id string
--- @field bufnr integer
--- @field project_scope_id string
--- @field render_epoch integer
--- @field buffer_version integer
--- @field layout_version integer
--- @field shape_epoch integer|nil
--- @field jobs RenderJob[]

--- @class RenderRequestMeta
--- @field request_id string
--- @field bufnr integer|nil
--- @field render_epoch integer
--- @field buffer_version integer
--- @field layout_version integer
--- @field project_scope_id string
--- @field jobs RenderJob[]
--- @field page_to_slot table<integer, string>|nil
--- @field slot_to_node table<string, string>|nil
--- @field slot_to_overlay table<string, string>|nil
--- @field node_to_job table<string, RenderJob>|nil
--- @field page_count integer
--- @field status RenderRequestStatus
--- @field line_map table[]|nil
--- @field slot_line_maps table<string, table>|nil
--- @field formula_line_maps table<string, table>|nil
--- @field formula_line_offsets table<string, integer>|nil
--- @field pending_formula_count integer|nil
--- @field formula_response_count integer|nil
--- @field generated_slot_paths table<string, string>|nil
--- @field generated_node_paths table<string, string>|nil
--- @field generated_context_path string|nil
--- @field generated_input_path string|nil

--- @return MachineState
function M.initial_state()
  return {
    buffers = {},
    projects = {},
    overlays = {},
    ui = {
      buffers = {},
    },
    counters = {
      next_node_id = 1,
      next_overlay_id = 1,
      next_request_id = 1,
    },
  }
end

return M
