# math-conceal.nvim ☀️

为 [Neovim](https://github.com/neovim/neovim) 提供更快、更精确的 [LaTeX](https://www.latex-project.org/) 和 [typst](https://github.com/typst/typst) 隐藏功能。

### Typst 数学公式 Conceal

https://github.com/user-attachments/assets/d78175a5-7462-40b6-be63-087fd100b97a

### Markdown 数学公式 Conceal（兼容流式输出）

https://github.com/user-attachments/assets/359fb62f-2031-4b5c-8d0b-0fe835fccd80

### LaTeX Conceal

<p align="center">
  <img src="https://github.com/user-attachments/assets/affbcc24-df83-4a45-9f02-aeba891f7727" alt="LaTeX ASCII/Unicode 字符 Conceal" width="80%">
</p>

## 简介

在 neovim `0.11.0` 中，treesitter 查询已更改为允许异步查询，这使我们能够使用 treesitter 查询隐藏 LaTeX 文件。然而，完全使用 `#set! conceal` 指令时仍然很慢，因为在隐藏单个节点时对整个 AST 进行查询的开销很大。

上述问题的基本解决方案来自 [latex.nvim](https://github.com/robbielyman/latex.nvim)，它使用自定义的 `set-pairs` 指令来隐藏 LaTeX 文件。然而，它仍然存在一些性能问题。解决性能问题的方法是考虑使用哈希表来加速模式匹配，而不是在 AST 查询文件中匹配隐藏模式。

## 特性

- 高性能的 LaTeX 和 typst 文件隐藏功能。
- 支持细粒度隐藏模式：
    - 原生 neovim 隐藏模式：展开光标所在行的所有隐藏节点。
    - 细粒度隐藏模式：只展开光标下的隐藏节点。
- 其他 filetype 中的 Typst：通过配置为嵌入 Org、Markdown 代码围栏等 Tree-sitter 宿主中的 Typst 提供渲染与隐藏。
- 支持多种隐藏模式，包括希腊字母、脚本字母、数学符号、字体样式、分隔符和物理单位。
- 多种高亮组用于不同的隐藏模式，允许您自定义每种模式的外观（所有高亮组可以在 [highlights](../highlights/highlights.md) 中找到）。

## 安装

### rocks.nvim

#### 命令方式

```vim
:Rocks install math-conceal.nvim
```

#### 声明方式

`~/.config/nvim/rocks.toml`:

```toml
[plugins]
"math-conceal.nvim" = "scm"
```

然后

```vim
:Rocks sync
```

或：

```sh
$ luarocks --lua-version 5.1 --local --tree ~/.local/share/nvim/rocks install math-conceal.nvim
# ~/.local/share/nvim/rocks 是默认 rocks tree 路径
# 可根据你的 vim.g.rocks_nvim.rocks_path 进行更改
```

图形化公式 conceal 还需要安装可选的 Rust 服务二进制：

```vim
:Rocks install math-conceal-service
```

或：

```sh
$ luarocks --lua-version 5.1 --local --tree ~/.local/share/nvim/rocks install math-conceal-service
```

LuaRocks 会优先使用适配当前平台的预构建 service rock；如果没有可用的预构建版本，则会从源码构建，此时需要 Rust/Cargo。

### lazy.nvim

```lua
return {
  "pxwg/math-conceal.nvim",
  event = "VeryLazy",
  main = "math-conceal",
  build = "cargo build --release --manifest-path service/Cargo.toml", -- 图形化公式渲染需要
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
      enabled = true, -- 启用图形化公式 conceal
    },
  },
}
```

## 参考

- [ts_query_lsp](https://github.com/ribru17/ts_query_ls) 我使用这个 LSP 作为预提交钩子来格式化查询文件。
- [latex_concealer.nvim](http://github.com/dirichy/latex_concealer.nvim) 提供了一些关于隐藏模式的想法。

## 致谢

- [Freed-Wu](https://github.com/Freed-Wu)：在将本插件发布到 [LuaRocks](https://luarocks.org/modules/pxwg/math-conceal.nvim) 以及重构代码结构以符合 Neovim 插件最佳实践方面起到了关键作用。
- [Dirichy](https://github.com/dirichy)：就 LaTeX 隐藏模式和优化进行了有益的讨论。
- [PartyWumpus](https://github.com/PartyWumpus)：感谢原始 [typst-concealer](https://github.com/PartyWumpus/typst-concealer) 插件，它启发了 Typst 图形化 conceal 支持。
- [latex.nvim](https://github.com/robbielyman/latex.nvim)：为使用自定义隐藏模式（conceal patterns）的想法提供了灵感。
- [latex_concealer.nvim](http://github.com/dirichy/latex_concealer.nvim)：为细粒度隐藏模式的想法提供了灵感。
- [pxwg/typst-concealer](https://github.com/pxwg/typst-concealer)：本插件图形化公式渲染源码所参考的 fork。
