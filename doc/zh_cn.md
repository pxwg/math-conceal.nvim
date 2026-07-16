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

顶层 `opt` 表控制插件只注入到已 attach buffer 所在 window 的 Neovim
window-local conceal 选项。默认 `concealcursor = "n"`，Normal 模式保持
公式 conceal，Insert 模式光标行显示源码；如果想保留旧的光标行始终
conceal 行为，可以设为 `"nci"`。当 window 不再显示已 attach buffer 时，
插件会恢复原 window 选项，避免污染其他 window。

## Buffer Attach API

`attach()` 是 ASCII/Unicode 符号 conceal 与图形化 image conceal 的统一
buffer 入口。普通 filetype buffer 会自动 attach；虚拟 buffer 或 preview
buffer 的适配器可以显式传入逻辑 source，不需要修改 buffer 自身的
`filetype` 或名字：

```lua
local conceal = require("math-conceal")
local attachment = conceal.attach(bufnr, {
  source = {
    kind = "markdown", -- "latex"、"markdown" 或 "typst"
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

匿名 preview buffer 应传入真实 `path`，以便 image renderer 正确解析
project root、import、preamble 和 path filter。`image = true` 仍受顶层
`image.enabled` 控制；Typst 与 Markdown 支持 image conceal，原生 LaTeX
本次只支持 ASCII/Unicode conceal。

每次 attach 都会返回带 owner 的 handle。同一个逻辑 source 可以有多个
owner；释放一个 handle 不会移除其他 owner。使用相同显式 `owner` 再次
attach 会替换该 owner 的请求，并使旧 handle 失效。自定义适配器还可以
使用 `resolve_source()`、`get_attachment()`、`refresh()` 和 `detach()`。

source descriptor 会显式选择 Tree-sitter root parser。math-conceal 获取并
使用 parser，但不调用 `vim.treesitter.start()` 或
`vim.treesitter.stop()`；Tree-sitter highlighting 生命周期仍由编辑器或
preview host 管理。

### Snacks picker preview

当 Snacks 可用时，math-conceal 默认适配
`Snacks.picker.preview.file`。Typst、Markdown 和 LaTeX 文件 preview
都会启用 Unicode conceal；当全局 `image.enabled = true` 时，Typst 和
Markdown 还会启用 image conceal。

Snacks scratch preview 使用 `presentation` mode。若 Snacks 直接复用一个
已经加载的真实 buffer，适配器会保留该 buffer 的 mode，并新增独立的
attachment owner；关闭 picker 不会移除普通 filetype owner。

```lua
require("math-conceal").setup({
  integrations = {
    snacks = {
      enabled = true, -- 默认值
      unicode = true,
      image = true,
      mode = "presentation",
    },
  },
})
```

使用 `integrations.snacks = false` 可以关闭默认适配。自定义同步
previewer 可以复用公开的 wrapper：

```lua
local snacks_conceal = require("math-conceal.integrations.snacks")

opts.preview = snacks_conceal.wrap(my_previewer, {
  source = function(ctx, bufnr, detected)
    return detected -- 可修改 kind、filetype 或 path
  end,
})
```

异步 previewer 应在内容写入完成后调用
`snacks_conceal.sync(ctx, opts)`，并在自定义 cleanup 中调用
`snacks_conceal.detach(ctx)`。

## 数学公式 Conceal

本插件可以将数学公式渲染为终端图形。渲染器源自 [pxwg/typst-concealer](https://github.com/pxwg/typst-concealer)，该 fork 基于 [PartyWumpus/typst-concealer](https://github.com/PartyWumpus/typst-concealer)。该功能依赖 kitty graphics protocol，适用于 kitty、Ghostty 等兼容终端。

图形化公式 conceal 支持 Typst，以及通过 [MiTeX](https://github.com/mitex-rs/mitex) 渲染数学公式的 Markdown。Markdown 数学公式支持 `$...$`、`$$...$$`、`\(...\)` 和 `\[...\]` 分隔符。

统一配置入口如下：

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

使用 rocks.nvim 安装时，安装可选的服务 rock：

```vim
:Rocks install math-conceal-service
```

使用源码或 lazy.nvim 安装时，安装或更新后需要构建 Rust 服务：

```sh
cargo build --release --manifest-path service/Cargo.toml
```

渲染器选项位于 `image.renderers.<name>`，包括 `filetypes`、`service_binary`、`live_debounce`、`root`、`inputs`、`preamble_file`、`header`、`render_paths`、Typst 的 `code_render.allow`，以及 Markdown 的 `mitex_package`。

Typst code 渲染默认只允许一组内置的可预测 primitive；可以用 `code_render.allow` 增加项目级用户白名单：

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
- [PartyWumpus](https://github.com/PartyWumpus)：感谢原始 [typst-concealer](https://github.com/PartyWumpus/typst-concealer) 插件，它启发了 Typst 图形化 conceal 支持。
- [latex.nvim](https://github.com/robbielyman/latex.nvim)：为使用自定义隐藏模式（conceal patterns）的想法提供了灵感。
- [latex_concealer.nvim](http://github.com/dirichy/latex_concealer.nvim)：为细粒度隐藏模式的想法提供了灵感。
- [pxwg/typst-concealer](https://github.com/pxwg/typst-concealer)：本插件图形化公式渲染源码所参考的 fork。
