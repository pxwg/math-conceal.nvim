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
A track projection representing the graphical reading form of a tracked object. It stores a track reference and late-binds a live TrackView from tracker when it needs current source position; it owns image-rendering and displayable asset state, not terminal placement state.
_Avoid_: Image data on tracks, cached track snapshots on projections, provider node, overlay node, placement backend

**Image Placement Backend**:
A projection-facing UI adapter that binds a displayable image asset to an editor presentation surface. It owns terminal image placement, placeholder binding, placement lifecycle, UI coordination, and any backend-local source conceal needed to reconcile a placement range with the tracked source range; it must not discover tracked objects, own track identity, or replace tracker-derived geometry.
_Avoid_: Renderer Binding, image binding API, tracker, render asset projection

**Snacks Placement Backend**:
The required graphical Image Placement Backend that uses Snacks image library placement primitives for already tracked math-conceal render assets. It must not use Snacks document scanning or let Snacks create tracked-object identity from a buffer.
_Avoid_: Snacks document renderer, Snacks scanner, fallback renderer

**Typst Display Projection**:
A buffer-level projection that decides which Typst formula and code tracks should have a graphical reading form on the editor surface and communicates those display intents to an Image Placement Backend. It may sample source text, editor display facts, layout facts, and editor width context inside tracker-derived display scopes, but it does not own track identity, discover objects by scanning source, own per-object render state, own terminal image placement, or obtain current object geometry from anything except `TrackRef -> TrackView`.
_Avoid_: Formula Display Projection, placeholder consumer, extmark renderer, line-run manager, image projection display

**Display Intent**:
A projection-owned request for an Image Placement Backend to present, update, hide, or source-reveal the graphical reading form of a tracked object, optionally carrying source range, preferred position, maximum dimensions, or preferred cell dimensions derived from render asset pixels and terminal cell metrics. It is derived from tracker output, displayability, cursor or selection state, and projection policy; it is not object identity, render asset state, terminal placement lifecycle, or image metadata ownership.
_Avoid_: Track, render asset, placement, backend state, image metadata

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
The historical custom-placement display artifact for one tracked object in the pre-Snacks Typst display model. Its source-access motivation survives as display-intent policy, but concrete source-anchored placeholder extmarks and conceal-row ownership belong to the legacy custom placement design rather than the Snacks Placement Backend target.
_Avoid_: Display line run, redraw carrier, render node, placeholder run, display intent

**Source Row Slot**:
A historical custom node-slot shape whose first rendered image row was attached to a real source fragment row. It is retained as legacy language for ADR-0007-era placement details; the Snacks Placement Backend target should express source access through display intents rather than requiring this exact extmark shape.
_Avoid_: Cursor-row placeholder, row carrier, line-run landing row, placement intent

**Block Node Slot**:
A historical custom node-slot shape for block objects whose anchor followed source boundary shape. Its exact suffix, prefix, isolated, and sandwich placement rules are legacy placement details after the Snacks Placement Backend decision; only the higher-level source-access and source-reveal policy remains part of the active display-intent language.
_Avoid_: Display line run, block carrier, whole-row redraw, Snacks placement

**Kitty Placeholder Row Alignment**:
A legacy custom-placement invariant from the hand-written Kitty placeholder renderer: every placeholder row for one Kitty image id had to start at the same visual text column. Under the Snacks Placement Backend target, terminal placeholder alignment is backend-owned rather than a Typst Display Projection invariant.
_Avoid_: Image reupload fix, renderer scaling fix, moving indented blocks to column zero, display intent

**Legacy Display Line Run**:
The pre-node-local Typst display model that folded consecutive source rows behind a carrier extmark and reconstructed ordinary source plus image atoms. It is retained only as historical language; active Typst main-buffer display uses node slots instead.
_Avoid_: Active display shape, node slot, current landing model

**Editor Display Fact**:
An editor-side presentation fact attached to source text, including editor-owned highlight, conceal, semantic token, inline decoration layers, and math-conceal ASCII/Unicode display marks. Active node-local Typst display generally leaves ordinary source text to Neovim instead of reconstructing it from these facts.
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

**Render Asset**:
A projection-owned result from the math-conceal render service for a tracked object, including the rendered file path, render key, diagnostics mapping, and service metadata needed by Image Projection. A render asset is consumed by an Image Placement Backend but is not produced by Snacks and does not own placement state or final cell geometry.
_Avoid_: Placement, terminal image, Snacks image, track

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
An image projection update that keeps the previous display intent pointed at the last displayable asset until the replacement asset is ready for the Image Placement Backend. It prevents graphical conceal from disappearing during asynchronous renders without requiring the projection to own terminal placeholder extmarks.
_Avoid_: Clear-then-render, blank refresh

**Source Reveal**:
A display intent where graphical display leaves a tracked object's source text directly visible by asking the Image Placement Backend to hide, pause, or close that object's placement and clear backend-local source conceal. Missing render assets, render failures, unknown code flow, and cursor- or selection-protected editing use source reveal instead of keeping an invalid or obstructive image over the source.
_Avoid_: Failed image overlay, hidden error source, projection-owned conceal extmarks
