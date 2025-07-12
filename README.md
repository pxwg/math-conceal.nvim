# math-conceal.nvim ☀️

Faster and More Precise [LaTeX](https://www.latex-project.org/) and [typst](https://github.com/typst/typst) conceal for [Neovim](https://github.com/neovim/neovim) with the power of [rust](https://www.rust-lang.org/).

![showcase](./fig/showcase_1.png)

## Introduction

In neovim `0.11.0`, the treesitter query has been changed to allow the asynchronous query, which allows us to use the treesitter query to conceal latex file. However, it's still slow while fully use `#set! conceal` directive since the expansive cost of query over the whole AST while conceal a single node.

The basic solution of the problem above comes from [latex.nvim](https://github.com/robbielyman/latex.nvim), who uses customized `set-pairs` directive to conceal the latex file. However, it still has some performance problem. The way to resolve the performance issue is considering a hash map to accelerate pattern matching, instead of matching conceal pattern inside AST query file.

## Features

- High performance conceal for LaTeX and typst files.
- Support multiple conceal patterns, including greek letters, script letters, math symbols, font styles, delimiters, and physical units.
- Multiple highlight groups for different conceal patterns, allowing you to customize the appearance of each pattern (all highlight groups can be found in [highlights](./highlights/highlights.md)).

## Installation

```lua
return {
  "pxwg/math-conceal.nvim",
  event = "VeryLazy",
  build = "make lua51",
  --- @type LaTeXConcealOptions
  opts = {
    enabled = true,
    conceal = {
      "greek",
      "script",
      "math",
      "font",
      "delim",
      "phy",
    },
    ft = { "tex", "latex", "markdown", "typst" },
  },
}
```

## To-do
- [ ] Better support for typst files, and customizable conceal patterns.
