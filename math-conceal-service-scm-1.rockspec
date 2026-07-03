local git_ref = '$git_ref'
local modrev = '$modrev'
local specrev = '$specrev'

local repo_url = '$repo_url'
local homepage = '$homepage'

rockspec_format = '3.0'
package = 'math-conceal-service'
if modrev:sub(1, 1) == '$' then
  modrev = "scm"
  specrev = "1"
  repo_url = "https://github.com/pxwg/math-conceal.nvim"
  homepage = repo_url
end
version = modrev ..'-'.. specrev

local build_command = 'cargo build --release --locked --manifest-path service/Cargo.toml --target-dir build/luarocks-target'
local service_binary = 'build/luarocks-target/release/typst-concealer-service'
local windows_build_command = 'cargo build --release --locked --manifest-path service/Cargo.toml --target-dir build\\luarocks-target'
local windows_service_binary = 'build\\luarocks-target\\release\\typst-concealer-service.exe'

description = {
  summary = 'Rust rendering service for math-conceal.nvim graphical equation conceal',
  detailed = [[
Optional typst-concealer-service binary used by math-conceal.nvim's graphical
Typst and Markdown equation renderer. The Lua plugin is packaged separately as
math-conceal.nvim; install this rock only when image conceal is enabled.
]],
  labels = { 'math', 'tex', 'typst', 'neovim', 'rust', },
  homepage = homepage,
  license = 'MIT',
}

build_dependencies = {  }

dependencies = { "lua >= 5.1" }

test_dependencies = {}

source = {
  url = repo_url .. '/archive/' .. git_ref .. '.zip',
  dir = '$repo_name-' .. '$archive_dir_suffix',
}

if (modrev == 'scm' or modrev == 'dev') and git_ref:sub(1, 1) == '$' then
  source = {
    url = repo_url:gsub('https', 'git')
  }
end

build = {
  type = 'command',
  build_command = build_command,
  install = {
    bin = {
      ['typst-concealer-service'] = service_binary,
    },
  },
  copy_directories = {},
  platforms = {
    windows = {
      build_command = windows_build_command,
      install = {
        bin = {
          ['typst-concealer-service.exe'] = windows_service_binary,
        },
      },
    },
  },
}
