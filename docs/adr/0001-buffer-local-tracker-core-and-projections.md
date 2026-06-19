# Buffer-local tracker core and projections

The rebuilt image path uses a tracker core inside the image subsystem as the source of truth for formula identity, movement, and current source ranges. Repair events may carry snapshots to seed projection reconciliation, but renderers and displays store track references and resolve a live TrackView whenever current source geometry is needed. Track ids are buffer-local within a tracker generation; cross-module or asynchronous references use buffer number, tracker generation, and track id together. Consumer-specific state such as image assets, render cache keys, diagnostics, or debug virtual text lives in track projections keyed by track references, not inside tracker tracks, so the tracker remains independent from renderer and display lifecycles.

## Considered Options

- Use global track ids across all buffers. Rejected because the image path is intentionally buffer-isolated and global ids would imply a cross-buffer object model.
- Store asset keys or image data directly on tracks. Rejected because renderer context, cache identity, and display state belong to consumers derived from tracker output.
- Put MVP debug virtual text in tracker core. Rejected because debug display is a disposable consumer and should validate the projection model rather than pollute core identity logic.

## Consequences

Repeated attach for the same buffer and source kind keeps the current tracker generation and tracks. Explicit detach followed by attach starts a new tracker generation and reseeds buffer-local track ids. The first MVP consumer is the debug projection that displays track id and revision; future image rendering should be another projection keyed by track references. Projection-owned display extmarks, cached repair snapshots, and renderer-local scans must never become alternate sources of current object geometry; cursor, resize, reveal, and placement paths go through `TrackRef -> TrackView`.
