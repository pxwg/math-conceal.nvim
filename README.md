# math-conceal.nvim ☀️

中文版文档：[zh-cn](./doc/zh_cn.md)

Faster and More Precise [LaTeX](https://www.latex-project.org/) and [typst](https://github.com/typst/typst) conceal for [Neovim](https://github.com/neovim/neovim).

### Typst Equation Conceal

https://github.com/user-attachments/assets/d78175a5-7462-40b6-be63-087fd100b97a

### Markdown Equation Conceal (Compatible with Stream Output)

https://github.com/user-attachments/assets/359fb62f-2031-4b5c-8d0b-0fe835fccd80

## Preview Channel

The stable `main` branch focuses on fast ASCII/Unicode math conceal. A preview
branch is available for graphical equation conceal in Typst and Markdown, with
experimental LaTeX rendering.

### Typst Equation Conceal Preview

https://github.com/user-attachments/assets/d78175a5-7462-40b6-be63-087fd100b97a

Try the preview branch with lazy.nvim:

```lua
return {
  "pxwg/math-conceal.nvim",
  branch = "preview",
  build = "cargo build --release --manifest-path service/Cargo.toml",
  main = "math-conceal",
  opts = {
    conceal = { "greek", "script", "math", "font", "delim", "phy" },
    ft = { "plaintex", "tex", "context", "bibtex", "markdown", "typst" },
    image = {
      enabled = true,
      filetypes = { "typst", "markdown" },
    },
  },
}
```

Feedback from Typst, Markdown streaming-output, and experimental LaTeX users is
welcome. Please include your terminal, OS, Neovim version, filetype, a minimal
snippet, and any `:messages` output.

### LaTeX Conceal

<table style="width: 80%; margin: auto; text-align: center;">
  <tr>
    <td style="width: 50%;">
      <figure>
        <img src="https://github.com/user-attachments/assets/3e73c907-66f0-46cd-8b25-d842473a2e1a" alt="Experimental LaTeX Image Conceal" style="width: 95%;">
        <figcaption>Experimental LaTeX Image Conceal</figcaption>
      </figure>
    </td>
    <td style="width: 50%;">
      <figure>
        <img src="https://github.com/user-attachments/assets/affbcc24-df83-4a45-9f02-aeba891f7727" alt="Stable LaTeX ASCII Conceal" style="width: 99%;">
        <figcaption>Stable LaTeX ASCII/Unicode Conceal</figcaption>
      </figure>
    </td>
  </tr>
</table>

## Introduction

In neovim `0.11.0`, the treesitter query has been changed to allow the asynchronous query, which allows us to use the treesitter query to conceal latex file. However, it's still slow while fully use `#set! conceal` directive since the expansive cost of query over the whole AST while conceal a single node.

The basic solution of the problem above comes from [latex.nvim](https://github.com/robbielyman/latex.nvim), who uses customized `set-pairs` directive to conceal the latex file.
Using a proper-designed lua module to handle the conceal patterns and only use treesitter to locate the position of the patterns can significantly improve the performance of conceal.

## Features

- High performance conceal for LaTeX and typst files.
- Fine grained conceal patterns:
    - Original neovim conceal patterns: expand *all* concealed nodes on the line where the cursor is located.
  - Fine grained conceal patterns: only expand the concealed node under the cursor.
- Buffer-local preview mode for ASCII/Unicode conceal:
  `require("math-conceal").setup_buffer({ mode = "preview" })` keeps concealed
  nodes collapsed while the cursor moves over them.
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
    image = {
      enabled = false, -- set true to enable graphical equation conceal
      filetypes = { "typst", "markdown" },
    },
  },
}
```

## Equation Conceal

`math-conceal.nvim` can also render equations as terminal graphics using the renderer
migrated from [pxwg/typst-concealer](https://github.com/pxwg/typst-concealer),
which is a fork of [PartyWumpus/typst-concealer](https://github.com/PartyWumpus/typst-concealer).
This path uses kitty graphics protocol and works in terminals that support it,
such as kitty and Ghostty.

Graphical equation conceal supports Typst, Markdown math through
[MiTeX](https://github.com/mitex-rs/mitex), and experimental LaTeX rendering.
Markdown math supports `$...$`, `$$...$$`, `\(...\)`, and `\[...\]` delimiters.

Enable it from the same setup table:

```lua
require("math-conceal").setup({
  image = {
    enabled = true,
    filetypes = { "typst", "markdown" },
    -- Optional. When omitted, math-conceal first tries the bundled release binary:
    -- service/target/release/typst-concealer-service
    service_binary = "typst-concealer-service",
    backends = {
      latex = {
        enabled = false, -- experimental
      },
    },
  },
})
```

Build the bundled Rust service after installing or updating:

```sh
cargo build --release --manifest-path service/Cargo.toml
```

Most advanced renderer options are passed through to the migrated renderer, including
`styling_type`, `live_preview_enabled`, `render_paths`, `get_root`, `get_inputs`,
and `get_preamble_file`.

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
- [PartyWumpus](https://github.com/PartyWumpus): for the original [typst-concealer](https://github.com/PartyWumpus/typst-concealer) plugin, which inspired Typst preview support.
- [latex.nvim](https://github.com/robbielyman/latex.nvim) for the idea of using customized conceal patterns.
- [latex_concealer.nvim](http://github.com/dirichy/latex_concealer.nvim) for the idea of fine grained conceal patterns.
- [pxwg/typst-concealer](https://github.com/pxwg/typst-concealer) as the fork whose renderer source was migrated into this plugin.
