# math-conceal.nvim ☀️

为 [Neovim](https://github.com/neovim/neovim) 提供更快、更精确的 [LaTeX](https://www.latex-project.org/) 和 [typst](https://github.com/typst/typst) 隐藏功能。

### Typst 数学公式 Conceal

https://github.com/user-attachments/assets/d78175a5-7462-40b6-be63-087fd100b97a

### Markdown 数学公式 Conceal（兼容流式输出）

https://github.com/user-attachments/assets/359fb62f-2031-4b5c-8d0b-0fe835fccd80

### LaTeX Conceal

<table style="width: 80%; margin: auto; text-align: center;">
  <tr>
    <td style="width: 50%;">
      <figure>
        <img src="https://github.com/user-attachments/assets/3e73c907-66f0-46cd-8b25-d842473a2e1a" alt="实验性 LaTeX 图片 Conceal" style="width: 95%;">
        <figcaption>实验性 LaTeX 图片 Conceal</figcaption>
      </figure>
    </td>
    <td style="width: 50%;">
      <figure>
        <img src="https://github.com/user-attachments/assets/affbcc24-df83-4a45-9f02-aeba891f7727" alt="稳定 LaTeX ASCII Conceal" style="width: 99%;">
        <figcaption>稳定 LaTeX ASCII/Unicode 字符 Conceal</figcaption>
      </figure>
    </td>
  </tr>
</table>

## 简介

在 neovim `0.11.0` 中，treesitter 查询已更改为允许异步查询，这使我们能够使用 treesitter 查询隐藏 LaTeX 文件。然而，完全使用 `#set! conceal` 指令时仍然很慢，因为在隐藏单个节点时对整个 AST 进行查询的开销很大。

上述问题的基本解决方案来自 [latex.nvim](https://github.com/robbielyman/latex.nvim)，它使用自定义的 `set-pairs` 指令来隐藏 LaTeX 文件。然而，它仍然存在一些性能问题。解决性能问题的方法是考虑使用哈希表来加速模式匹配，而不是在 AST 查询文件中匹配隐藏模式。

## 特性

- 高性能的 LaTeX 和 typst 文件隐藏功能。
- 支持细粒度隐藏模式：
    - 原生 neovim 隐藏模式：展开光标所在行的所有隐藏节点。
    - 细粒度隐藏模式：只展开光标下的隐藏节点。
- 支持多种隐藏模式，包括希腊字母、脚本字母、数学符号、字体样式、分隔符和物理单位。
- 多种高亮组用于不同的隐藏模式，允许您自定义每种模式的外观（所有高亮组可以在 [highlights](./highlights/highlights.md) 中找到）。

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
    image = {
      enabled = false, -- 改为 true 以启用图形化公式 conceal
      filetypes = { "typst", "markdown" },
    },
  },
}
```

## 数学公式 Conceal

本插件可以通过从 [pxwg/typst-concealer](https://github.com/pxwg/typst-concealer) 迁移进来的渲染管线，将数学公式渲染为终端图形。该 fork 基于 [PartyWumpus/typst-concealer](https://github.com/PartyWumpus/typst-concealer)。该功能依赖 kitty graphics protocol，适用于 kitty、Ghostty 等兼容终端。

图形化公式 conceal 支持 Typst、通过 [MiTeX](https://github.com/mitex-rs/mitex) 渲染数学公式的 Markdown，以及实验性的 LaTeX 渲染。Markdown 数学公式支持 `$...$`、`$$...$$`、`\(...\)` 和 `\[...\]` 分隔符。

统一配置入口如下：

```lua
require("math-conceal").setup({
  image = {
    enabled = true,
    filetypes = { "typst", "markdown" },
    -- 可选；未设置时会优先查找当前插件内的 release 二进制：
    -- service/target/release/typst-concealer-service
    service_binary = "typst-concealer-service",
    backends = {
      latex = {
        enabled = false, -- 实验性支持
      },
    },
  },
})
```

安装或更新后需要构建 Rust 服务：

```sh
cargo build --release --manifest-path service/Cargo.toml
```

`styling_type`、`live_preview_enabled`、renderer 级 `live_debounce`、`render_paths`、`root`、`inputs`、`preamble_file`、Typst 的 `code_render.allow` 等高级渲染选项会透传给迁移后的管线。Typst code 渲染默认只允许一组内置的可预测 primitive；可以用 `code_render.allow = { "theorem", "lemma" }` 增加全局用户白名单。

## 待办事项

- [ ] 更好地支持 typst 文件，并提供可自定义的隐藏模式。
    - [x] LaTeX 可自定义隐藏模式。
    - [ ] Typst 可自定义隐藏模式。
- [ ] Typst 文件的交换图隐藏功能。
- [ ] LaTeX 和 Typst 文件的表格隐藏功能（灵感来自 [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)）。
- [ ] 自动维护隐藏查询文件和 `math_symbols.json` 文件。
    - [x] Typst
  - [ ]  LaTeX

## 参考

- [ts_query_lsp](https://github.com/ribru17/ts_query_ls) 我使用这个 LSP 作为预提交钩子来格式化查询文件。
- [latex_concealer.nvim](http://github.com/dirichy/latex_concealer.nvim) 提供了一些关于隐藏模式的想法。

## 致谢

- [Freed-Wu](https://github.com/Freed-Wu)：在将本插件发布到 [LuaRocks](https://luarocks.org/modules/pxwg/math-conceal.nvim) 以及重构代码结构以符合 Neovim 插件最佳实践方面起到了关键作用。
- [Dirichy](https://github.com/dirichy)：就 LaTeX 隐藏模式和优化进行了有益的讨论。
- [PartyWumpus](https://github.com/PartyWumpus)：感谢原始 [typst-concealer](https://github.com/PartyWumpus/typst-concealer) 插件，它启发了 Typst 预览支持。
- [latex.nvim](https://github.com/robbielyman/latex.nvim)：为使用自定义隐藏模式（conceal patterns）的想法提供了灵感。
- [latex_concealer.nvim](http://github.com/dirichy/latex_concealer.nvim)：为细粒度隐藏模式的想法提供了灵感。
- [pxwg/typst-concealer](https://github.com/pxwg/typst-concealer)：本插件迁移图形化公式渲染源码所基于的 fork。
