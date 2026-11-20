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
