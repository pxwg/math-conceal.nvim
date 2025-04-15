# note-tree.nvim 🌳

Buiding a tree of notes in Neovim.

## Introduction

The structure of the knowledge is a connected diagrams, which could abstractly be represented as a tree with multiple links (even many loops). This plugin is designed to help you build a tree of notes in Neovim.

## Installation

```lua
return {
  "pxwg/latex-conceal.nvim",
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
    },
    ft = { "tex", "latex", "markdown" },
  },
}
```
