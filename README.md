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

LuaRocks uses a prebuilt service rock when one is available for your platform;
otherwise it builds the service from source and requires Rust/Cargo.

### lazy.nvim

```lua
return {
  "pxwg/math-conceal.nvim",
  event = "VeryLazy",
  main = "math-conceal",
  build = "cargo build --release --manifest-path service/Cargo.toml", -- required for graphical equation conceal
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

## Equation Conceal

`math-conceal.nvim` can also render equations as terminal graphics using the renderer
adapted from [pxwg/typst-concealer](https://github.com/pxwg/typst-concealer),
which is a fork of [PartyWumpus/typst-concealer](https://github.com/PartyWumpus/typst-concealer).
This path uses kitty graphics protocol and works in terminals that support it,
such as kitty and Ghostty.

Graphical equation conceal supports Typst and Markdown math through
[MiTeX](https://github.com/mitex-rs/mitex).
Markdown math supports `$...$`, `$$...$$`, `\(...\)`, and `\[...\]` delimiters.
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

For rocks.nvim installs, install the optional service rock:

```vim
:Rocks install math-conceal-service
```

For source/lazy.nvim installs, build the bundled Rust service after installing or updating:

```sh
cargo build --release --manifest-path service/Cargo.toml
```

Check Neovim APIs, terminal support, adapters, and the render service with:

```vim
:checkhealth math-conceal
```

Renderer-specific options live under `image.renderers.<name>`, including
`filetypes`, `service_binary`, `live_debounce`, `root`, `inputs`,
`preamble_file`, `header`, `render_paths`, Typst's `code_render.allow`, and
Markdown's `mitex_package`.

Typst code rendering is intentionally allowlisted. math-conceal renders a
built-in set of predictable Typst primitives by default; add project-wide custom
function names with `code_render.allow`:

```lua
require("math-conceal").setup({
  image = {
    enabled = true,
    renderers = {
      typst = {
        code_render = {
          allow = { "theorem", "lemma", "remark" },
        },
      },
    },
  },
})
```

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
