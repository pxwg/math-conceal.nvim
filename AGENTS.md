# Project Agent Instructions

## Project Memory

- Before project work, load `memory-dream show` and treat the generated `Memory.md` entry point as the curated project truth.
- For graphical image-renderer work, start from Memory Dream `2606190506`: the current architecture is tracker/projection based, not the historical scaffold reset.

## Commit Messages

- Use Conventional Commits for project commits, for example `fix(tracker): separate repair facts from render triggers`.

## Window Placement Ownership

- Treat a Window Placement Surface as owned by `(winid, bufnr)`, not by `winid` alone.
- Delayed or scheduled cleanup derived from a buffer lifecycle must pass the expected buffer owner and must not close a replacement surface installed by another buffer in the reused window. Only true window destruction may use an unqualified window close.
- Preserve a focused regression where buffer B replaces buffer A in one window before A's delayed cleanup runs; B's surface and terminal placements must survive.

## Tracker Core Semantics

- Use the term `tracker core` for the formula identity and geometry layer; do not call it renderer core.
- Tracker core owns formula identity, current source geometry, damage/repair, context units, source facts, and `TrackRef`/`TrackView` semantics. Image, display, diagnostics, and live preview layers are projections over tracker output.
- Before changing tracker-core semantics, discuss the abstraction and intended invariant with the user first unless the user explicitly asks for immediate implementation.
- Prove editor invariants with the smallest focused MVP or headless repro before moving the behavior into the plugin. Prefer a minimal external script or narrow test that demonstrates the extmark, damage, repair, or cursor interaction invariant.
- Do not add defensive fallback paths that bypass tracker ownership. If a normal edit path needs broad repair, make the reason explicit and keep it tied to the tracker model.
