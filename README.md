# math-conceal.nvim ☀️

中文版文档：[zh-cn](./doc/zh_cn.md)

Faster and More Precise [LaTeX](https://www.latex-project.org/) and [typst](https://github.com/typst/typst) conceal for [Neovim](https://github.com/neovim/neovim).

### Typst Equation Conceal

https://github.com/user-attachments/assets/d78175a5-7462-40b6-be63-087fd100b97a

### Markdown Equation Conceal (Compatible with Stream Output)

https://github.com/user-attachments/assets/359fb62f-2031-4b5c-8d0b-0fe835fccd80

### LaTeX Conceal

<p align="center">
  <img src="https://github.com/user-attachments/assets/affbcc24-df83-4a45-9f02-aeba891f7727" alt="LaTeX ASCII/Unicode Conceal" width="80%">
</p>

## Features

- High performance conceal for LaTeX and typst files.
- Fine grained conceal patterns:
    - Original neovim conceal patterns: expand *all* concealed nodes on the line where the cursor is located.
  - Fine grained conceal patterns: only expand the concealed node under the cursor.
- Image overlay conceal: Using [kitty graphic protocol](https://sw.kovidgoyal.net/kitty/graphics-protocol/) to show the compiled equations instead of source code.
- Typst in other filetypes: render and conceal Typst embedded in Org, Markdown fences, and other Tree-sitter hosts from configuration.
- Support multiple conceal patterns, including greek letters, script letters, math symbols, font styles, delimiters, and physical units.
- Multiple highlight groups for different conceal patterns, allowing you to customize the appearance of each pattern (all highlight groups can be found in [highlights](./highlights/highlights.md)).

## Installation

### rocks.nvim

#### Command style

```vim
:Rocks install math-conceal.nvim
```

#### Declare style

`~/.config/nvim/rocks.toml`:

```toml
[plugins]
"math-conceal.nvim" = "scm"
```

Then

```vim
:Rocks sync
```

or:

```sh
$ luarocks --lua-version 5.1 --local --tree ~/.local/share/nvim/rocks install math-conceal.nvim
# ~/.local/share/nvim/rocks is the default rocks tree path
# you can change it according to your vim.g.rocks_nvim.rocks_path
```

Graphical equation conceal also needs the optional Rust service binary:

```vim
:Rocks install math-conceal-service
```

or:

```sh
$ luarocks --lua-version 5.1 --local --tree ~/.local/share/nvim/rocks install math-conceal-service
```

The service rock builds from source and requires Rust/Cargo. New prebuilt service
binaries are distributed through GitHub Releases; existing binary rocks may still
be available for older versions.

### lazy.nvim

```lua
return {
  "pxwg/math-conceal.nvim",
  event = "VeryLazy",
  main = "math-conceal",
  version = "*", -- use a release tag so the service matches the plugin
  build = function(plugin) -- optional: graphical equation conceal
    require("math-conceal.install").install({ root = plugin.dir, wait = true })
  end,
  --- @type LaTeXConcealOptions
  opts = {
    conceal = {
      "greek",
      "script",
      "math",
      "font",
      "delim",
      "phy",
    },
    ft = { "plaintex", "tex", "context", "bibtex", "markdown", "typst" },
    opt = {
      conceallevel = 2,
      concealcursor = "n",
    },
    image = {
      enabled = true, -- set true to enable graphical equation conceal
    },
  },
}
```

The top-level `opt` table controls the Neovim window-local conceal options that
math-conceal injects only into windows showing attached buffers. The default
`concealcursor = "n"` keeps conceal active in Normal mode while revealing source
on the cursor line during Insert mode; set it to `"nci"` to keep the previous
always-concealed cursor-line behavior.

Buffers of the filetypes in `ft` and in `image.renderers.<name>.filetypes` are
attached by a FileType autocommand that math-conceal registers itself.
`setup()` also attaches matching buffers that are already open, so lazy-loading
with `event = "VeryLazy"` works.

## Buffer Attachment API

`attach()` is the common entry point for ASCII/Unicode and graphical conceal.
Ordinary filetype buffers are attached automatically. Integrations for virtual
or preview buffers can provide the logical source independently of the
buffer's concrete `filetype` and name:

```lua
local conceal = require("math-conceal")
local attachment = conceal.attach(bufnr, {
  source = {
    kind = "markdown", -- "latex", "markdown", or "typst"
    filetype = "markdown",
    path = "/absolute/path/to/note.md",
  },
  surfaces = {
    unicode = true,
    image = true,
  },
  mode = "presentation",
})

attachment:detach()
```

`path` supplies the real source provenance for renderer roots, imports, and
path filters when the attached buffer is anonymous. `image = true` still
requires top-level `image.enabled = true`; graphical attachment is available
for Typst and Markdown, while LaTeX uses ASCII/Unicode conceal only.

Calls return owner-qualified handles. Multiple integrations may attach the
same logical source to one buffer, and detaching one handle leaves the other
owners active. Re-attaching with the same explicit `owner` replaces that
owner's request and makes its old handle stale. Use
`resolve_source(bufnr, source)`, `get_attachment(bufnr)`, `refresh()`, or
`detach(bufnr)` for custom integrations and lifecycle inspection.

The source descriptor determines the Tree-sitter root parser explicitly.
math-conceal obtains that parser but does not start or stop Tree-sitter
highlighting, so preview hosts remain responsible for their own highlighter
lifecycle.

### Snacks picker previews

The stock `Snacks.picker.preview.file` previewer is adapted automatically when
Snacks is available. Scratch previews use `presentation` mode, while previews
that reuse an already-loaded buffer preserve that buffer's existing mode and
attachment owner. Typst, Markdown, and LaTeX previews receive Unicode conceal;
Typst and Markdown also request image conceal when it is globally enabled.

```lua
require("math-conceal").setup({
  integrations = {
    snacks = {
      enabled = true, -- default
      unicode = true,
      image = true,
      mode = "presentation",
    },
  },
})
```

Disable the default adapter with `integrations.snacks = false`. Custom Snacks
previewers can reuse the same lifecycle:

```lua
local snacks_conceal = require("math-conceal.integrations.snacks")

opts.preview = snacks_conceal.wrap(my_synchronous_previewer, {
  source = function(ctx, bufnr, detected)
    return detected -- customize kind, filetype, or path here
  end,
})
```

For asynchronous previewers, call `snacks_conceal.sync(ctx, opts)` after the
preview content has been committed and `snacks_conceal.detach(ctx)` during
custom cleanup.

## Equation Conceal

`math-conceal.nvim` can also render equations as terminal graphics using the renderer
adapted from [pxwg/typst-concealer](https://github.com/pxwg/typst-concealer),
which is a fork of [PartyWumpus/typst-concealer](https://github.com/PartyWumpus/typst-concealer).
This path uses kitty graphics protocol and works in terminals that support it,
such as kitty and Ghostty.

Graphical equation conceal supports Typst and Markdown math through
[MiTeX](https://github.com/mitex-rs/mitex).
Markdown math supports `$...$` and `$$...$$` through Tree-sitter by default.
Set `image.renderers.markdown.backslash_math = true` to also recognize
`\(...\)` and `\[...\]`. This optional handwritten scanner scans the full
buffer and is disabled by default to avoid its additional scanning cost.
The graphical path requires Neovim 0.11 or newer; ASCII/Unicode conceal does not.

Enable it from the same setup table:

```lua
require("math-conceal").setup({
  image = {
    enabled = true,
    renderers = {
      typst = {
        filetypes = { "typst" },
      },
      markdown = {
        filetypes = { "markdown" },
        mitex_package = "@preview/mitex:0.2.7",
      },
    },
  },
})
```

Display math is centered by default. Set `image.block_align = "source"` to
align Typst and Markdown display math with its source column instead.
Inline math and Typst code placement are unchanged.

For rocks.nvim installs, install the optional service rock:

```vim
:Rocks install math-conceal-service
```

For tagged source/lazy.nvim installs, the download hook installs the matching
GitHub Release service without a Rust toolchain (Neovim 0.10+, Git, and curl required):

```lua
require("math-conceal.install").install()
```

The function downloads asynchronously and shows a progress bar in Neovim's
command area. The lazy.nvim hook uses `wait = true` to keep the build pending
until installation succeeds or fails, while processing UI events. For custom
progress displays, pass `on_progress = function(message, percent) ... end`.
The returned handle exposes `done`, `error`, and `path`. A headless entry point
is also available: `nvim --headless -u NONE -i NONE -l scripts/install-service.lua`.

Prebuilt targets are Linux x86_64 (glibc 2.35+), macOS Apple Silicon, and macOS
Intel. The hook downloads only when invoked, verifies SHA-256, and atomically
replaces `service/target/release/typst-concealer-service`, which the plugin
discovers automatically. Failed downloads preserve the installed binary. curl
uses standard proxy environment variables such as `https_proxy`. Restart Neovim
after updating an already running service.

The hook requires an exact release tag and never downloads `latest`. Releases
created before this distribution workflow may lack the required assets. For
development branches, unsupported platforms, or offline source builds, use this
command instead (also usable as the lazy.nvim `build` hook; omit `version` to
track the development branch):

```sh
cargo build --release --locked --manifest-path service/Cargo.toml
```

Check Neovim APIs, terminal support, adapters, and the render service with:

```vim
:checkhealth math-conceal
```

Renderer-specific options live under `image.renderers.<name>`, including
`filetypes`, `service_binary`, `live_debounce`, `root`, `inputs`,
`preamble_file`, `header`, `render_paths`, Typst's `code_render.allow` and
`code_render.exclude`, and Markdown's `mitex_package`, `mitex_preamble`, and
`mitex_preamble_file`.

Markdown MiTeX rendering can prepend reusable LaTeX macro definitions to every
inline and block formula. File definitions are loaded before inline definitions:

```lua
require("math-conceal").setup({
  image = {
    enabled = true,
    renderers = {
      markdown = {
        mitex_preamble = [[
          \newcommand{\RR}{\mathbb{R}}
        ]],
        mitex_preamble_file = function(ctx)
          return vim.fs.dirname(ctx.path) .. "/mitex-preamble.tex"
        end,
      },
    },
  },
})
```

These options are MiTeX macro preludes, not full LaTeX document preambles:
MiTeX-supported definitions such as `\newcommand` and `\newenvironment` work,
but they do not load LaTeX packages with `\usepackage`. For example, a
MiTeX-compatible `\slashed` approximation is:

```tex
\newcommand{\slashed}[1]{\not{#1}}
```

After changing an external preamble file, call
`require("math-conceal.image").rerender_buf()` to refresh the current Markdown
buffer.

Typst code rendering is intentionally allowlisted. math-conceal renders a
built-in set of predictable Typst primitives by default. Add project-wide custom
function names with `code_render.allow`, or remove names from the effective
allowlist with `code_render.exclude`. Exclusions take precedence over both
built-in and explicitly allowed names, and match the tracked code expression's
head rather than recursively inspecting nested calls:

```lua
require("math-conceal").setup({
  image = {
    enabled = true,
    renderers = {
      typst = {
        code_render = {
          allow = { "theorem", "lemma", "remark" },
          exclude = { "image" },
        },
      },
    },
  },
})
```

### Typst in other filetypes

The built-in Typst renderer also renders Typst injected into other filetypes.
With [nvim-orgmode](https://github.com/nvim-orgmode/orgmode), Typst is injected
into `#+begin_src typst` blocks and `src_typst{...}`; one extra injection query
also treats inline `$...$` as Typst. Declaring the host filetype is enough:

```lua
require("math-conceal").setup({
  -- `ft` is not appended to the default list: list every filetype.
  ft = { "plaintex", "tex", "context", "bibtex", "markdown", "typst", "org" },
  image = {
    enabled = true,
    renderers = {
      org_typst = {
        filetypes = { "org" },
        source_kind = "typst",
      },
    },
  },
})
```

Each source block renders as one unit: prose stays at its source column and
display math is centered, as Typst lays it out. With the cursor inside a block,
its formulas render one by one. `#let` and `#set` rules are shared across
blocks in document order. ASCII/Unicode conceal applies to the injected Typst;
set `image.enabled = false` to keep only ASCII/Unicode conceal. See
`:h math-conceal-image-scanners` for the injection query and the rendering rules.

If nvim-orgmode is lazy-loaded, load it on the `org` filetype (lazy.nvim:
`ft = { "org" }`). Loaded only on `VeryLazy`, it may not be set up yet when
math-conceal scans a file opened at startup, and that file renders no Typst.

## To-do

- [ ] Better support for typst files, and customizable conceal patterns.
    - [x] LaTeX customizable conceal patterns.
  - [ ]  Typst customizable conceal patterns.
- [ ] Commutative diagram conceal for Typst files.
- [ ] Table conceal for LaTeX and Typst files (inspired from [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)).
- [ ] Automatically maintain the conceal query file and `math_symbols.json` file.
    - [x] Typst
  - [ ]  LaTeX

## References

- [ts_query_lsp](https://github.com/ribru17/ts_query_ls) I use this LSP as a pre-commit hook to format the query file.
- [latex_concealer.nvim](http://github.com/dirichy/latex_concealer.nvim) for some ideas about conceal patterns.

## Acknowledgements

- [Freed-Wu](https://github.com/Freed-Wu): Instrumental in publishing this plugin to [LuaRocks](https://luarocks.org/modules/pxwg/math-conceal.nvim) and refactoring the code structure to fit the best practices for Neovim plugins.
- [Dirichy](https://github.com/dirichy): for helpful discussions about LaTeX conceal patterns and optimizations.
- [PartyWumpus](https://github.com/PartyWumpus): for the original [typst-concealer](https://github.com/PartyWumpus/typst-concealer) plugin, which inspired Typst graphical conceal support.
- [latex.nvim](https://github.com/robbielyman/latex.nvim) for the idea of using customized conceal patterns.
- [latex_concealer.nvim](http://github.com/dirichy/latex_concealer.nvim) for the idea of fine grained conceal patterns.
- [pxwg/typst-concealer](https://github.com/pxwg/typst-concealer) as the fork whose renderer source was adapted into this plugin.
