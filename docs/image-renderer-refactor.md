# Image Renderer Refactor Notes

This note records working boundaries for the image renderer refactor. It is not an ADR; use ADRs only when a harder-to-reverse trade-off is accepted.

## Resolved Boundaries

- Renderer is the source/render-input capability boundary selected by a Renderer Binding. It can provide scanner, render-input, display, flow, or preview hooks, but it must not own tracker identity, live geometry, image assets, service response validation, diagnostics, or no-blank swaps.
- Do not introduce a separate provider registry in this refactor. What earlier discussion called a provider is the renderer itself.
- `image.renderers.<name>` is the renderer's canonical identity. By default the refactor should resolve renderer capability from the same name, with compatibility overrides for existing `scanner`, `backend`, and `wrapper` fields where useful for tests or migration.
- Existing `source_kind`, `scanner`, `backend`, and `wrapper` fields remain supported for compatibility and test override, but they must not be used as capability predicates. Capability checks should read the resolved renderer table.
- Unknown `image.renderers.<name>` keys are unsupported unless a matching renderer module exists. Compatibility fields may override known renderer parameters, but they must not synthesize implicit renderer capabilities.
- Renderer resolution should fail closed. If a renderer module is missing, malformed, or lacks required capabilities, image attach for that buffer is skipped with a one-time warning rather than falling back to old scanner or generic inferred behavior.
- Renderer hooks should cover source-specific scanning, render-context construction, render-input construction, flow/layout probing, display projection integration, and live-preview source transformation. Shared session lifecycle, request merging, response validation, image upload, diagnostics mapping, no-blank swaps, and asset cleanup remain shared Image Projection responsibilities.
- Required renderer capabilities are `scanner`, `backend`, `build_context_document`, `build_slot_document`, and `render_size_key`. Optional capabilities include `build_flow_context_document`, `build_flow_source`, `render_layout_key`, `flow`, `display_projection`, and `preview`; `build_flow_source` is required when `flow` exists.
- Renderer capabilities participate in detach cleanup. Shared cleanup owns image assets, preview assets, and generic display extmarks; renderer display and flow capabilities must clean their own buffer-local state, extmarks, and quickfix buckets before tracker detach completes.
- Flow capabilities must provide explicit buffer cleanup such as `flow.detach(bufnr)`. Retired-track cleanup through `flow.clear_refs(bufnr, refs)` is not enough for buffer disable, renderer switch, or wipeout.
- Scanner resolution belongs to renderer resolution and attachment. Tracker core should receive a scanner table through `tracker.attach`; it should not require Typst or Markdown scanner modules by name.
- Render context and render input construction belong to renderer hooks rather than a shared wrapper module branching on renderer names. Typst owns Typst source rewriting, editor-size prelude, code layout wrappers, and flow probe source; Markdown owns MiTeX delimiter handling, imports, and render input calls.
- Render keys and cache keys remain shared Image Projection concerns. Renderers may contribute stable key fragments such as size, layout, and render-context signatures, but pending-key comparison, service response validation, visible asset replacement, and no-blank swap stay shared.
- Typst main-buffer display should be exposed through an optional renderer `display_projection` capability matching the current Typst Display Projection public surface: `on_tracker_repair`, `repair_tracks`, `sync_cursor`, `refresh`, and `detach`. Shared projection code should check the resolved renderer capability instead of using Typst-name predicates.
- Typst code flow/layout classification should be exposed through an optional renderer `flow` capability. It remains a projection-owned consumer keyed by track references and current signatures; tracker core must not own flow roles, layout roles, render policies, or classification request state.
- Live Preview Projection remains shared. Renderer-specific preview hooks may transform `track.source` for preview rendering, such as Typst cursor-symbol highlighting, but preview window ownership, handoff assets, preview service backpressure, response validation, and placement stay shared.
- Image Surface is the shared low-level surface for rendered image assets and terminal placeholder semantics. It is not a replacement owner for Typst main-buffer display.
- Typst main-buffer display remains owned by Typst Display Projection. Markdown/MiTeX and other non-Typst paths may continue using the generic simple image display path while the refactor extracts shared surface primitives.
- Split the current `image/display.lua` responsibilities into Image Surface primitives and a generic display owner. Typst Display Projection may consume only Image Surface primitives; non-Typst paths may continue to use the generic display owner for `show`, `reveal`, and `clear`.
- Renderer-specific modules should live under `lua/math-conceal/image/renderers/<name>/`. Shared modules should stay in their current image-path locations during the first migration unless a move directly reduces coupling; a later `core/` move can happen after renderer boundaries settle.
- Do not create an ADR for the renderer-boundary decision at this point; keep migration guidance in this design note.
- Do not preserve legacy fallback paths during implementation. When a path or branch is migrated, update callers to the new boundary instead of keeping defensive alternate routes.
- Do not keep old module-path compatibility shims after moving renderer-specific modules. Update in-repo require sites and tests to the new renderer paths directly.
- Use a hard migration order: create renderer/surface/generic-display modules, update all shared callers to the new boundaries, delete old renderer-specific module paths, then verify zero stale require sites and run focused tests.
- Tests and fixtures must hard-switch to new renderer module paths; do not keep compatibility imports for old paths. Public Neovim/user docs must be updated to the current renderer terminology and configuration behavior.
- Public user docs should describe renderer configuration behavior, not internal Lua module structure or hook names. Internal renderer layout belongs in this design note and code organization, not README/help-facing API docs.

## TODO

- Revisit a unified Display Projection after renderer isolation and Image Surface extraction have landed. The future design must preserve tracker-owned identity, `TrackRef -> TrackView` geometry, and Image Projection asset ownership, and it must state whether the unified projection owns all main-buffer display policy or only coordinates renderer-specific display hooks.
