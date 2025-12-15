local git_ref = '$git_ref'
local modrev = '$modrev'
local specrev = '$specrev'

local repo_url = '$repo_url'

rockspec_format = '3.0'
package = '$package'
version = modrev ..'-'.. specrev

description = {
  summary = '$summary',
  detailed = $detailed_description,
  labels = $labels,
  homepage = '$homepage',
  $license
}

build_dependencies = {  }

dependencies = { "lua >= 5.1" }

test_dependencies = $test_dependencies

source = {
  url = repo_url .. '/archive/' .. git_ref .. '.zip',
  dir = '$repo_name-' .. '$archive_dir_suffix',
}

if modrev == 'scm' or modrev == 'dev' then
  source = {
    url = repo_url:gsub('https', 'git')
  }
end

build = {
  type = 'rust-mlua',
  copy_directories = {'plugin', 'queries'},
  modules = {
    "lookup_conceal"
  },
  install = {
    lua = {
      treesitter_query = "lua/treesitter_query.lua",
      ["utils.latex_conceal"] = "lua/utils/latex_conceal.lua",
      ["math-conceal.autocmd"] = "lua/math-conceal/autocmd.lua",
      ["math-conceal.highlights"] = "lua/math-conceal/highlights.lua",
      ["math-conceal.init"] = "lua/math-conceal/init.lua",
    }
  },
}
