# math-conceal.nvim

This context defines the project language for turning math source in editor buffers into concealed or rendered reading forms.

## Language

**Tracker**:
The image-path source of truth for tracked object identity and current source ranges. Renderers and displays consume tracker output rather than discovering object identity themselves. Tracker identity is isolated per buffer instance.
_Avoid_: Renderer core, renderer

**Buffer Version**:
A conceptual version of a buffer's source text after a sequence of edits. Tracker repair must not combine source geometry that belongs to different buffer versions.
_Avoid_: Repair epoch, async generation

**Damaged Region**:
A tracker-owned source interval where tracked object identity cannot be trusted after an edit and must contribute to repair scanning.
_Avoid_: Damage range, dirty track

**Dirty Track**:
An existing tracked object whose source range was touched by an edit and must be revalidated by tracker repair. Its identity remains a repair candidate until repair either inherits new source or retires it.
_Avoid_: Damaged region, stale projection

**Tracked Object**:
A tracker-owned renderable source object in the image path. Typst tracked objects currently include formula tracks and code tracks.
_Avoid_: Formula-only track, render node, display atom

**Object Kind**:
The category of a tracked object, currently math or code for Typst display. It is distinct from the source kind of the buffer or renderer binding, and tracker repair must not inherit identity across object kinds.
_Avoid_: Source kind, renderer kind, node type

**Formula Track**:
A tracker-owned formula instance whose identity follows one complete source-kind math span. For Typst, a formula track represents the whole math span; internal formula, symbol, or sub-expression spans are interaction facts, not separate tracks.
_Avoid_: Symbol track, sub-formula track, render atom

**Code Track**:
A tracker-owned Typst code object whose identity follows one top-level allowlisted renderable code expression, such as a predictable built-in primitive or a user-allowed project function/reference. Structural code such as imports, lets, sets, and shows is a context unit instead; non-allowlisted custom code remains visible source, and nested code or math objects are not code tracks.
_Avoid_: Formula track, context unit, scanned code node

**Flow Classification Projection**:
A track projection that assigns a semantic Typst flow role to code tracks. It answers whether Typst realization produces inline-level content, block-level content, or unknown content; it does not decide editor row placement, line breaking, or render width. It is consumer-owned state keyed by track identity and current source or context signature, not tracker identity.
_Avoid_: Tracker flow state, code tracker classifier, display guess, layout classifier

**Code Flow Role**:
The semantic Typst flow role of a code track: inline, block, or unknown. Unknown code flow should reveal source instead of presenting a rendered image as if its layout role were known. Inline flow does not imply row-attachability: inline content can still require a line break under a finite paragraph width.
_Avoid_: Source display kind, geometry role, code type, row placement

**Layout Classification Projection**:
A Typst display projection concern that derives editor placement facts for code tracks from a complete local layout unit, render context, and editor width context. It is separate from flow classification and remains projection-owned rather than tracker-owned.
_Avoid_: Flow classification, tracker layout state, source multiline heuristic

**Code Layout Fact**:
A projection-owned fact about how a code track should participate in the editor reading surface, such as row attachability, width-context requirement, break-before or break-after behavior, and constrained render width. Code layout facts may depend on neighboring source text and editor geometry, not just the tracked node.
_Avoid_: Code flow role, source fact, tracker geometry

**Editor Width Context**:
The finite layout width supplied to Typst layout probes or constrained render wrappers, derived from the target Neovim display surface and current cell geometry. It resolves relative or fractional widths without changing the rendered font-size baseline.
_Avoid_: Scale factor, source range width, unconstrained measure width

**Font-Size Alignment Invariant**:
The graphical Typst renderer keeps Typst text size tied to the configured Neovim-aligned baseline. Width-context fixes must provide a finite layout width instead of scaling rendered text away from the editor cell-height relationship.
_Avoid_: Fit-to-width scaling, image zoom as layout

**Repair Window**:
A tracker-owned source interval selected for scanner repair, derived from damaged regions and dirty tracks and bounded by stable neighboring tracks. It is the range where tracker may reconcile existing track identity with newly scanned formula nodes.
_Avoid_: Raw edit range, damage range, full-buffer repair

**Repair Geometry**:
The set of tracker-owned source positions and intervals that repair consumes for a single current buffer version. Core track positions and damaged regions must belong to the same repair geometry before scanner repair can reconcile tracked object identity.
_Avoid_: Mixed edit ranges, stale damage data

**Tracker Repair Event**:
A tracker-owned report of neutral repair facts after validation, including object identity changes, geometry changes, lifecycle changes, context facts, and repair geometry. It is not a renderer, display, diagnostics, or preview trigger list.
_Avoid_: Render event, display event, affected refs

**Track Reference**:
A compound reference to one tracked object, made from buffer number, tracker generation, and buffer-local track id. It is the identity shape used across module or asynchronous boundaries.
_Avoid_: Global track id, bare track id across buffers

**Object Identity Change**:
A tracker repair result where an existing tracked object inherits different scanner-owned object facts, such as object kind, source identity, source display form, or source facts. It is distinct from geometry-only movement, context dependency changes, and projection-specific decisions about rendering or display.
_Avoid_: Render change, display change, dirty track

**TrackView**:
The live tracker-owned view resolved from a track reference at the moment a projection needs current source geometry, source facts, or revision. Repair-event snapshots may seed track references and stable render requests, but projections must not cache or reuse snapshot rows as display geometry.
_Avoid_: Cached snapshot, projection-owned range, display extmark position as truth

**Track Projection**:
Consumer-owned state derived from tracker output and keyed by a track reference. Image, display, diagnostics, or debug consumers keep their own projections instead of storing consumer-specific data inside tracker tracks.
_Avoid_: Tracker attachment, image data on tracks

**Image Projection**:
A track projection representing the graphical reading form of a tracked object. It stores a track reference and late-binds a live TrackView from tracker when it needs current source position; it owns only image-rendering and display state.
_Avoid_: Image data on tracks, cached track snapshots on projections, provider node, overlay node

**Typst Display Projection**:
A buffer-level projection that decides how Typst formula and code tracks share the editor reading surface. It may sample source text, editor display facts, layout facts, and editor width context inside tracker-derived display scopes, but it does not own track identity, discover objects by scanning source, own per-object render state, or obtain current object geometry from anything except `TrackRef -> TrackView`.
_Avoid_: Formula Display Projection, placeholder consumer, extmark renderer, line-run manager, image projection display

**Row-Attachable Formula**:
A single-line inline formula whose rendered reading form may stay attached to a real source row even when the cursor is on that row. Formula shapes that are not row-attachable use source reveal when the cursor touches their source row.
_Avoid_: Safe local fold, cursor-row placeholder

**Node-Revealable Formula**:
A formula whose cursor collision can reveal the formula's own source rows without forcing a broader mixed-row reveal. Typst single-line inline formulas and isolated block formulas are node-revealable; only single-line inline formulas are row-attachable.
_Avoid_: Cursor-safe block, local preview node

**Active Formula**:
The node-revealable formula whose source range currently contains the cursor. On a cursor row, row-attachable formulas other than the active formula may remain image-rendered while the active formula reveals source.
_Avoid_: Cursor line formula, hovered formula, selected render node

**Node Slot**:
A Typst Display Projection display artifact for one tracked object. It presents a rendered asset from tracker-owned geometry while ordinary text remains drawn by Neovim.
_Avoid_: Display line run, redraw carrier, render node, fold grid

**Source Row Slot**:
A node slot whose first rendered image row is attached to a real source fragment row. Inline slots use inline virtual text at the first fragment column, and non-isolated block behavior follows the existing Typst Display Projection policy.
_Avoid_: Cursor-row placeholder, row carrier, line-run landing row, isolated block surface

**Block Node Slot**:
A block-shaped node slot for block placements. Existing Typst Display Projection policy decides whether non-isolated block shapes use a node slot or source reveal.
_Avoid_: Display line run, block carrier, whole-row redraw, isolated block placement

**Window Extmark Node Slot**:
A node slot materialized independently per editor window so each window can use its own source wrapping geometry while presenting the same tracker-owned object. It is the target isolated-block display model, replacing Fold Grid Placement Surface after migration.
_Avoid_: Window extmark placement surface, fold-grid successor, buffer-global isolated block slot

**Window-Local Slot Reveal**:
The per-window source reveal state for Window Extmark Node Slots. It follows the existing source-reveal behavior: entering any part of the tracked source range reveals the whole tracked source range in that window, and leaving the source range restores conceal without forcing other windows showing the same buffer to close their node slots. This is a visibility state, not a terminal-placement disposal state: `placed=false` means window-local slot extmarks are absent, while `placement_id` may remain live so the Kitty Unicode-placeholder virtual placement can be reused on restore. Hard lifecycle events, not cursor source reveal, own `delete_placement`.
_Avoid_: Buffer-global reveal state, cross-window slot teardown, shared cursor collision, treating `placed=false` as terminal placement release

**Carrier-Maximized Slot Height**:
The Window Extmark Node Slot height principle that preserves the largest real source carrier footprint that fits within the rendered image height, then uses collapsed source rows and virtual image rows only to reconcile the visible slot height with the rendered asset. If the smallest useful carrier already wraps taller than the rendered asset, carrier continuity wins and the visible slot may be taller than the asset.
_Avoid_: Minimum carrier height, source-height preservation, fold-grid height

**Local Slot Remeasure**:
The Window Extmark Node Slot update rule that clears only the current window and track slot artifacts before measuring raw source wrapping geometry. It prevents shaped extmarks from contaminating measurement without tearing down unrelated tracks or other windows.
_Avoid_: Full-buffer remeasure, cross-window cleanup, global slot rebuild

**Incremental Slot Materialization**:
The Window Extmark Node Slot update boundary that changes only affected window and track artifacts after source, cursor, selection, scroll, or layout events. It avoids full-buffer display rebuilds and does not turn viewport events into tracker repair.
_Avoid_: Full-buffer display rebuild, scroll-driven repair, window-global rematerialization

**Fold Grid Placement Surface**:
A legacy Image Placement Backend owned display surface formerly used for isolated block-shaped Typst placements. It is superseded by Window Extmark Node Slots and must not remain as a production fallback.
_Avoid_: Node slot replacement, source row slot replacement, block node slot replacement, display line run, fold-owned track, mixed-row block surface, migration fallback

The following Fold Grid terms are retained as legacy implementation history rather than current production guidance.

**Managed Fold Window Surface**:
The window-local fold option ownership used to materialize Fold Grid Placement Surfaces. A buffer-level placement may have window-specific folded surfaces because Neovim fold expression, fold text, fold level, and fold enablement are window-local editor state. It saves and restores prior window fold options rather than composing with user folds.
_Avoid_: Buffer-global fold state, user fold composition, tracker-owned fold option

**Fold Grid Height Invariant**:
The concealed visible height of a Fold Grid Placement Surface equals the rendered image height, not the source height. If the source range is taller than the rendered image, the final visible fold consumes the remaining source rows; if the rendered image is taller than the source range, trailing virtual image rows extend the surface from the last folded source row.
_Avoid_: Source-height preservation, blank tail rows, scale-to-source-height

**Rendered Grid Dimensions**:
The Image Projection owned cell dimensions of a rendered asset, such as placeholder columns and image rows. They are render asset facts, not source geometry, and combine with live TrackRef-derived source geometry when a Fold Grid Placement Surface is materialized.
_Avoid_: Tracker source geometry, intent source range, backend image measurement

**Fold Grid Tail Rows**:
The trailing virtual image rows of a Fold Grid Placement Surface when the rendered image is taller than its source range. They are anchored to the last folded source row so the rendered grid remains one continuous surface and source reveal can remove the whole placement at once.
_Avoid_: Post-block anchor, detached image tail, independent virtual-line placement

**Fold Grid Placement Identity**:
The terminal identity shape for a Fold Grid Placement Surface. One rendered asset uses one image id and one placement id across all folded placeholder rows and trailing virtual image rows, so the terminal binds the whole placeholder grid as one image placement.
_Avoid_: Per-row placement id, split image placement, row-local terminal identity

**Fold Grid No-Blank Swap**:
The no-blank update behavior for Fold Grid Placement Surfaces. The active placement remains visible while a pending placement for a newly ready asset is materialized; after the pending surface is ready, it is promoted and the old placement is closed. If the new rendered image height differs, the visible height changes at promotion according to the Fold Grid Height Invariant. Source reveal closes placement surfaces instead of using no-blank swap.
_Avoid_: Clear-then-fold, blank image refresh, source reveal as hidden placement, topfill compensation

**Neovim-Owned Fold Grid Scrolling**:
The scrolling model for Fold Grid Placement Surfaces. Neovim's fold layout owns viewport position, visible rows, topline, and topfill; backend scroll handlers only perform placement hygiene such as fold refresh, terminal placement re-emission, and stale placement cleanup.
_Avoid_: Screen-coordinate image scrolling, scroll-driven intent recompute, tracker repair on scroll

**Repair-Driven Fold Grid Sync**:
The synchronization relationship between tracker repair and Fold Grid Placement Surfaces. Tracker repair events prompt Typst Display Projection to rebuild placement intents and Image Placement Backend to synchronize fold-grid surfaces, while tracker core remains responsible only for identity, current source geometry, damage, and repair facts.
_Avoid_: Tracker-owned fold state, foldexpr in tracker core, scroll-triggered tracker repair

**Late-Bound Fold Grid Rows**:
The source-row entries used by a Managed Fold Window Surface. They are materialized from a Placement Intent by resolving its TrackRef to a live TrackView; fold expression lookup may use a backend-local row cache, but stale intent rows or invalid TrackViews must not keep rows folded.
_Avoid_: Snapshot fold rows, cached repair geometry, fold-owned source position, anchor-only geometry

**Invalid Fold Grid Recovery**:
The recovery behavior when a Fold Grid Placement Surface can no longer be materialized from live tracker geometry or its isolated-block display role. The backend closes the placement surface and leaves source visible until repair-driven sync provides a new valid placement intent.
_Avoid_: Row-cache repair, backend source reclassification, stale fold preservation

**Fold Grid Source Reveal**:
The source reveal behavior for a Fold Grid Placement Surface. Cursor collision with any folded source row, including a multi-row tail fold, or visual selection overlap with any part of the tracked source range reveals the entire tracked source range and closes the whole placement surface; it never reveals only one folded grid row.
_Avoid_: Per-row reveal, half-image state, partial folded source

**Fold Grid Normal Conceal Policy**:
The Fold Grid Placement Surface behavior when normal-mode graphical conceal is enabled for a buffer. Normal-mode cursor collision may keep the fold-grid surface visible, while insert-like editing and visual selection still use source reveal according to the active buffer conceal policy.
_Avoid_: Mode-blind reveal, CopilotChat policy regression, always-open normal cursor row

**Window-Local Fold Grid Reveal**:
The per-window reveal state for Fold Grid Placement Surfaces. A cursor or selection collision in one window reveals the tracked source range in that window without forcing other windows showing the same buffer to close their placement surfaces.
_Avoid_: Buffer-global reveal state, cross-window fold teardown, shared cursor collision

**Non-Isolated Block Policy Preservation**:
The Typst display behavior for block-shaped objects that are not isolated blocks. Window Extmark Node Slot migration does not change their existing Typst Display Projection policy, including whether they use node slots or source reveal.
_Avoid_: Prefix fold grid, suffix fold grid, sandwich fold grid, policy rewrite during isolated-block migration

**Kitty Placeholder Row Alignment**:
The invariant that every placeholder row for one Kitty image id starts at the same visual text column. If an isolated block's first row is overlaid at an indented source fragment column while the remaining rows are `virt_lines`, those `virt_lines` must be prefixed by the source prefix display width so indentation is preserved without horizontally tearing the image.
_Avoid_: Image reupload fix, renderer scaling fix, moving indented blocks to column zero

**Legacy Display Line Run**:
The historical Typst display model that folded consecutive source rows behind a carrier extmark and reconstructed ordinary source plus image atoms. It is retained only as historical language; active Typst main-buffer display should use node slots or backend-owned placement surfaces instead.
_Avoid_: Active display shape, node slot, current landing model

**Editor Display Fact**:
An editor-side presentation fact attached to source text, including editor-owned highlight, conceal, semantic token, inline decoration layers, and math-conceal ASCII/Unicode display marks. Active Typst display generally leaves ordinary source text to Neovim instead of reconstructing it from these facts.
_Avoid_: Source fact, render asset, tracker decoration

**Display Repair Scope**:
The bounded part of Typst Display Projection that must be recomputed after tracker, asset, cursor, visual-selection, or layout changes. In the node-local model it is track/object-local and keyed by track references and stable extmark keys, not by neighboring display line-run boundaries.
_Avoid_: Full-buffer display plan, global rerender, line-run repair

**Renderer Binding**:
The buffer-level image-path choice that associates a supported buffer with a source kind, scanner, and render-context family. It does not own object identity and must not discover tracked objects itself.
_Avoid_: Renderer core, source adapter, backend, formula owner

**Markdown Math Source**:
A Markdown-family source kind whose formulas are written with LaTeX-style inline or display delimiters and consumed through the image path. It is distinct from a LaTeX source kind even when its formula text uses LaTeX syntax.
_Avoid_: LaTeX backend, raw LaTeX buffer, source adapter

**Live Preview Projection**:
A cursor-engaged projection that presents a transient rendered view of the currently engaged math track in editor modes such as normal, insert-like, and visual, following the old live preview behavior. When the cursor is on math node source, it may replace the engaged rendered math symbol or span with a red rendered fragment inside the preview result. It derives identity and source position from track projections and is distinct from buffer-wide conceal modes.
_Avoid_: Buffer preview mode, standalone preview renderer

**Preview Window**:
The concrete editor UI surface used by a live preview projection. It is a presentation surface, not a source of formula identity.
_Avoid_: Preview track, renderer-owned window

**Buffer Preview Mode**:
The buffer-local ASCII or Unicode conceal mode named `preview`. It is separate from live graphical preview windows.
_Avoid_: Live preview, preview window

**Render Context**:
The document-level environment used to render tracked objects, including project scope, styling, preambles, imports, and path interpretation. It is shared by image projections and does not identify an individual object.
_Avoid_: Preview context, provider context

**Render Context Projection**:
A buffer-level projection that derives the render context from source structure and renderer binding configuration. It owns shared rendering context such as runtime preludes, context source, project scope, roots, and inputs while track projections own per-object image or semantic state.
_Avoid_: Context on tracks, provider session

**Render Input**:
The renderer-owned source text derived from a tracked object's source and projection facts for graphical rendering. It may normalize delimiters, wrap source for a rendering backend, or provide a constrained editor-width context for layout-dependent code, but it is not object identity and must not replace tracker source.
_Avoid_: Track source, scanner output, object identity

**Projection Reconciliation**:
The act of aligning consumer-owned projections with the current tracker snapshot. It may update, create, stale, or retire projections, but it does not create tracker identity.
_Avoid_: Provider sync, overlay reconciliation

**Stale Image Projection**:
An image projection whose rendered asset no longer matches the current tracked object revision but may remain visible until a newer projection can replace it or the track stops being displayable.
_Avoid_: Broken image, orphan overlay

**Debug Projection**:
A development track projection that visualizes tracked object identity and revision state. It must remain disposable and must not own object identity.
_Avoid_: Tracker display, core tracker UI

**Scanner**:
A source-kind-specific reader that reports current renderable source objects from a buffer range for the tracker. It does not own object identity, rendering, or display state.
_Avoid_: Source adapter, renderer

**Source Fact**:
A scanner-reported fact about a tracked object's source structure or geometry, such as node type, delimiter shape, or source-level display form. Source facts may guide image projections but must not contain inferred semantic projection results such as code flow role, code layout facts, render state, or display artifacts.
_Avoid_: Render state, display artifact, flow role, layout fact

**Context Unit**:
A scanner-recognized source node that contributes rendering context for later tracked objects without becoming a tracked object itself. Typst context units include structural code such as `#set`, `#let`, `#import`, and `#show` forms.
_Avoid_: Formula track, provider prelude node

**Context Unit Index**:
A buffer-level index of context units used to detect rendering-context changes and derive per-track context facts. It is scanner-owned coordination data, not per-track image state.
_Avoid_: Context list on tracks, renderer cache

**Context Dependency**:
The relationship between a tracked object and the context-unit prefix that affects its rendered form. Projections derive context impact from tracker-reported context facts and per-track prefix facts rather than receiving projection-specific affected-object lists from tracker.
_Avoid_: Full-buffer rerender, implicit prelude

**Projection Anchor**:
The tracker-owned core extmark from which projections late-bind the current source range for a tracked object. Projections may create their own display extmarks, but those extmarks remain anchored to this tracker-owned source position and must not become a second source of object position truth.
_Avoid_: Display extmark as identity, renderer-owned anchor, cached projection position

**Projection Geometry Invariant**:
Image, Typst display, diagnostics, and live-preview consumers may store track references and projection-owned assets/status, but whenever they need current object rows, columns, source facts, or revision they must resolve a live TrackView through the tracker. Window-size changes, cursor sync, display placement, and source reveal must not derive geometry from cached repair snapshots, projection extmarks, independent scans, or renderer-local source parsing.
_Avoid_: Consumer-owned geometry, stale snapshot rows, placeholder extmark as position source

**No-Blank Swap**:
An image projection update that keeps the previous visible asset in place until the replacement asset is uploaded and ready to bind. It prevents graphical conceal from disappearing during asynchronous renders.
_Avoid_: Clear-then-render, blank refresh

**Source Reveal**:
The projection state where graphical display leaves a tracked object's source text directly visible. Missing render assets, render failures, unknown code flow, and cursor-protected editing use source reveal instead of keeping an invalid image over the source.
_Avoid_: Failed image overlay, hidden error source
