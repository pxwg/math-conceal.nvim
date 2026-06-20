# Formula Display Projection Owns Multi-Formula Display

Accepted.

Typst graphical rendering uses a buffer-level formula display projection to decide how multiple tracked formulas share the editor reading surface, instead of pushing that policy into each per-formula image projection. Image projections continue to own render requests and rendered assets; the formula display projection consumes tracker views and those assets so cursor source access, mixed inline/block formulas, and grouped display plans can be coordinated in one place.

**Considered Options**

- Keep display ownership inside each image projection.
- Introduce a formula display projection for multi-formula display policy.

**Consequences**

- Formula display policy can reason across adjacent or overlapping source rows without making tracker tracks or image projections own group layout.
- Missing or failed assets use per-track source reveal; ready assets in the same display plan may still render as images.
- No-blank swap remains owned by Image Projection: Formula Display Projection continues to use the current displayable asset until Image Projection exposes a replacement or chooses source reveal.
- Image Projection exposes a narrow displayable-asset interface to Formula Display Projection; display planning must not depend on internal pending keys, candidate assets, or status fields.
- Cursor collision follows the minimal test strategy: the cursor row is suppressed from display line runs; row-attachable formulas on that real source row may remain image-rendered unless they are the active formula; isolated block formulas reveal their own source rows; mixed or multiline unsafe shapes reveal source when their rows are touched.
- `conceal_in_normal = true` is the explicit override for Normal mode to keep Typst formula display concealed at the cursor; without that setting, Normal mode follows the same active formula source-reveal strategy.
- Active formula selection follows the minimal test order over node-revealable formula views; overlapping formula tracks are treated as scanner/tracker bugs, not display-planner priority cases.
- Visual selection suppresses display for the full selected row range and uses source reveal throughout that range, including row-attachable formulas, so selection and copy operate on real source.
- Non-interactive Typst display is composed on display line runs: block math remains centered, while Typst code block images are left-aligned by default at the text area's first column (right of line numbers/sign columns) with no display-side left padding, a one-editor-cell right reserve, no default code-block wrapper margin, and a block wrapper that resets ambient alignment to left. The projection computes suppressed rows, builds runs over the remaining consecutive formula rows, and patches carrier/conceal extmarks instead of placing each formula independently.
- Display line runs reconstruct an ordered stream of source atoms and formula atoms, replacing the test placeholder atom with image or source-reveal atoms in the plugin implementation.
- The first implementation reconstructs source atoms as plain buffer text; the old preview branch's highlight/conceal compositor is explicitly deferred.
- Image atoms use the existing kitty placeholder glyph, 24-bit image id highlight, and cell-dimension rules; the test labels are not part of the plugin display contract.
- Display line-run carrier anchoring follows the minimal test: prefer the row before the run, otherwise the row after with `virt_lines_above`, and keep one visible landing row only for the degenerate whole-buffer run.
- Formula Display Projection does not call the Typst renderer or own render keys; it only consumes assets produced by Image Projection.
- Formula Display Projection does not read buffer source directly; source text and current geometry are consumed through tracker view/source APIs.
- Formula Display Projection may use repair-event snapshots only to recover track references and repair seeds. Current rows, columns, source facts, and revisions used for display composition, cursor suppression, resize refresh, and source reveal must be late-bound via `TrackRef -> TrackView`.
- Live Preview Projection remains separate and owns the preview window/highlighted render path; Formula Display Projection owns only the main-buffer reading surface.
- Migration keeps the current tracker, image projection asset lifecycle, service session, and live preview foundation; it replaces the main-buffer per-projection display responsibility with the Typst formula display projection.
- Typst main-buffer display must not call the per-formula `display.show()` path; that function may remain for other surfaces or helpers, but the formula display projection is the sole owner of Typst main-buffer display extmarks.
- When Image Projection changes a track's displayable asset or source-reveal state, it notifies Formula Display Projection to repair that track's display scope instead of mutating Typst main-buffer display extmarks directly.
- Tracker repair events feed both consumers: Image Projection updates render assets for affected tracks, while Formula Display Projection immediately repairs affected display scopes using current displayable assets or source reveal; asset readiness triggers a later display repair.
- Retired tracks repair display by their previous source rows/ranges: intersecting display line runs are cleared and rebuilt from current live views rather than deleting a per-track display extmark.
- The first migration target is the Typst renderer branch only; Markdown/MiTeX and LaTeX display policies remain out of scope until Typst is correct.
- Typst inline/block/isolated display shape follows the minimal test behavior for the first migration, but the display projection should consume it as source facts rather than spread parsing rules through display planning.
- For Typst code tracks, semantic flow role is not enough to choose editor placement. The Typst Display Projection should consume projection-owned layout facts, including row attachability, width-context requirements, and line-break behavior under the editor width context.
- Window or terminal geometry changes invalidate code layout classification/render keys but not tracker geometry. The projection should request fresh layout classification from live TrackViews and source-reveal stale or pending code tracks instead of keeping old image placeholders over newly wrapped source rows.
- Display line-run planning may use complete local layout units around code tracks to mirror Typst line breaking, rather than placing each code image solely from the track's semantic inline/block role.
- The plugin implementation must preserve the test semantics without full-buffer display planning: tracker and asset changes seed a display repair scope from affected formula rows, cursor changes repair old/new suppressed rows, and each scope expands only to neighboring display line-run boundaries.
- A display line run is repaired as a unit: if a display repair scope intersects an existing run, the whole run is cleared and rebuilt from the expanded scope instead of patching individual atoms in place.
- Typst display repair is not viewport-gated; viewport state may influence geometry measurements, but correctness and refresh scheduling are based on affected display repair scopes.
- The test `typst_math_placeholder_consumer.lua` should migrate as the starting model for this projection, but not as a literal placeholder-only renderer.
