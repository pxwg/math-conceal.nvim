# Track Projection Image Rendering

Accepted.

Graphical image rendering is rebuilt as projections over tracker-owned formula identity instead of reviving the old provider-owned node and overlay lifecycle. Tracker tracks and projection anchors are the source of formula identity and position; image projections own render jobs, terminal image ids, display extmarks, rendered assets, diagnostics, and no-blank swaps, while render context projections own buffer-level context units and context dependencies.

**Considered Options**

- Revive the old provider machine, node, and overlay lifecycle.
- Store image and render state directly on tracker tracks.
- Use track projections plus buffer-level render context projections.

**Consequences**

- Scanners may produce source facts and context unit indexes, but tracker core must not own renderer artifacts.
- Context unit changes stale only downstream image projections whose context dependencies changed.
- Service responses are accepted only when they match the current track reference, source revision, context revision, and projection render key.
- Projection state stores track references plus assets/status; display placement, cursor reveal, resize refresh, diagnostics mapping, and live-preview geometry late-bind a live TrackView through tracker instead of reading cached repair snapshots or projection extmarks as source geometry.
- Successful replacement uses no-blank swap; render failure uses source reveal and mapped diagnostics.
