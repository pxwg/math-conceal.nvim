# note-tree.nvim 🌳

Buiding a tree of notes in Neovim.

## Introduction

The structure of the knowledge is a connected diagrams, which could abstractly be represented as a tree with multiple links (even many loops). This plugin is designed to help you build a tree of notes in Neovim.

## Installation

```lua
return {
  "pxwg/note-tree.nvim",
  event = "VeryLazy",
  build = "make lua51",
  opts = {
    max_depth = 10, -- The deepest search depth
    root = "~/personal-wiki", -- The root directory of the notes
  },
}
```
