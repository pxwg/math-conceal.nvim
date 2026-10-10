# Unified native conceal ownership (experimental)

The Unicode attachment owns conceal for the root language and every injected
language. Neovim still owns highlighting, spelling and other highlight metadata.
Unattached buffers retain native behavior.

## Query source and ownership

- `native-conceal.lua` installs one global highlighter `get_query` bridge.
  An attachment registry determines which buffers receive filtered query views.
- The bridge never changes global `query.set()` state, the original Query,
  capture IDs, or shared metadata. It copies metadata only when conceal needs
  filtering, removing both pattern-level and capture-level `conceal` and
  `conceal_lines`.
- The render pipeline consumes the original query held by the active highlighter,
  including instance-specific queries and all recursively injected languages.
  It does not reconstruct native queries from runtime files.
- Plugin math queries are separate. A native conceal capture overlapping a
  plugin math conceal mark is omitted, so math overrides win even when a native
  query gives its capture a higher priority.
- Query/highlighter identity changes invalidate render caches. Parsed injection
  languages are rediscovered without a fixed language allowlist.
- Detach restores native consumption and retires cached highlighter iterators
  and persistent native conceal-line marks. Attachment never starts/stops the
  highlighter.

## Reveal semantics

All collected marks use the existing edit/preview/presentation policies.
Markdown links and code spans retain their semantic parent expansion range.
Other languages use the captured node as their reveal range. Existing
`conceal_lines` handling is reused.

## Internal API boundary

This is an experimental adapter over Neovim's undocumented
`highlighter.active`, `get_query`, and query/iterator state fields. Keep these
accesses isolated in the bridge; do not hot-unload/reload this module in a
running editor (restart Neovim instead). Highlighter stop/start is supported.

An external global `query.set()` does not necessarily replace an already-cached
highlighter query. We follow what the actual highlighter consumes, not a newer
global query that the highlighter has not adopted.

## Verification

Headless tests:

```sh
nvim --headless -u NONE -i NONE -l scripts/test-native-conceal-ownership.lua
nvim --headless -u NONE -i NONE -l scripts/test-markdown-native-conceal.lua
nvim --headless -u NONE -i NONE -l scripts/test-render-cache.lua
nvim --headless -u NONE -i NONE -l scripts/test-render-cursor.lua
```

The ownership test covers programmatic and per-highlighter queries, shared
metadata isolation, unowned buffers, attach before/after highlighter startup,
highlighter recreation, native-only conceal, and math/native precedence.

Remote MBA UI QA used Neovim 0.12.5 and Kitty 0.49.1, both running on MBA:
two links on one line, inline code, one-symbol math reveal, a custom Lua-injection
conceal rule, preview mode, highlighter restart, `:edit`, injection
removal/reintroduction, and detach. The remote screen-text assertions passed.
Evidence and isolated runtime: `mba-backup:/tmp/math-conceal-native-qa/`.

## Known limitations

Remote MBA microbenchmarks (three runs, 10,000-line Markdown) measured median
cursor redraw at 3.64 ms, scroll redraw at 3.74 ms, and edit plus visible-mark
collection at 42.86 ms. The pre-PR171 pipeline measured 3.58/3.52/42.42 ms in
the same harness. These are reference values, not a statistically isolated or
fully behavior-equivalent comparison. Broad reparsing remains the main edit
cost. A full Neovim-version compatibility matrix has not been completed.

Cross-window conceal-line QA found a correctness issue: windows can paint
independent reveal states while layout and mouse hit-testing use shared
buffer-local conceal-line marks. With the left opening fence revealed and the
right fence hidden, clicking the left code body can land on a later source
line. Single-window controls map correctly. The existing renderer's persistent
`math-conceal-render-lines` namespace needs genuinely window-scoped ownership;
this prototype does not fix that issue.

The temporary performance and cross-window harnesses are not included in the
repository. Their report and evidence remain at
`mba-backup:/tmp/math-conceal-native-qa/bench/REPORT.md`.
