---Global bridge between Tree-sitter highlighting and plugin-owned conceal.
---The query objects remain untouched. Only highlighter consumption is filtered,
---and only for buffers explicitly attached to our Unicode surface.
---Neovim's highlighter.get_query/active API is internal: keep access here.
local M = {}
local highlighter = vim.treesitter.highlighter
local original_get_query = highlighter.get_query
local owners = {}
local views = setmetatable({}, { __mode = "k" })
local native_ns = vim.api.nvim_create_namespace("nvim.treesitter.highlighter")

local function without_conceal(metadata)
  if not metadata then
    return metadata
  end
  local needs_filter = metadata.conceal ~= nil or metadata.conceal_lines ~= nil
  if not needs_filter then
    for key, value in pairs(metadata) do
      if type(key) == "number" and type(value) == "table" and (value.conceal ~= nil or value.conceal_lines ~= nil) then
        needs_filter = true
        break
      end
    end
  end
  if not needs_filter then
    return metadata
  end
  local copy = {}
  for key, value in pairs(metadata) do
    if key ~= "conceal" and key ~= "conceal_lines" then
      if type(key) == "number" and type(value) == "table" and (value.conceal ~= nil or value.conceal_lines ~= nil) then
        local capture = {}
        for k, v in pairs(value) do
          if k ~= "conceal" and k ~= "conceal_lines" then
            capture[k] = v
          end
        end
        copy[key] = capture
      else
        copy[key] = value
      end
    end
  end
  return copy
end

local function filtered_query(raw)
  return setmetatable({
    has_conceal_line = false,
    iter_captures = function(_, ...)
      local iter = raw:iter_captures(...)
      return function(...)
        local id, node, metadata, match, tree = iter(...)
        return id, node, without_conceal(metadata), match, tree
      end
    end,
  }, { __index = raw })
end

-- One global interception, not one patch per buffer or injected language.
highlighter.get_query = function(self, lang)
  local original = original_get_query(self, lang)
  if not owners[self.bufnr] then
    return original
  end
  local raw = original:query()
  if not raw then
    return original
  end
  local by_lang = views[self]
  if not by_lang then
    by_lang = {}
    views[self] = by_lang
  end
  local cached = by_lang[lang]
  if not cached or cached.original ~= original or cached.raw ~= raw then
    local filtered = filtered_query(raw)
    cached = {
      original = original,
      raw = raw,
      view = setmetatable({
        query = function()
          return filtered
        end,
        get_hl_from_capture = function(_, id)
          return original:get_hl_from_capture(id)
        end,
      }, { __index = original }),
    }
    by_lang[lang] = cached
  end
  return cached.view
end

local function reset(buf)
  local hl = highlighter.active[buf]
  if not hl then
    return
  end
  hl._highlight_states = {}
  hl._conceal_checked = {}
  hl._conceal_line = false
  -- Native conceal_lines marks are persistent; retire them on ownership changes.
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, native_ns, 0, -1)
  end
  if not owners[buf] then
    for _, wrapper in pairs(hl._queries) do
      local q = wrapper:query()
      hl._conceal_line = hl._conceal_line or (q and q.has_conceal_line) or false
    end
  end
end

function M.attach(buf)
  owners[buf] = true
  reset(buf)
end

function M.detach(buf)
  if not owners[buf] then
    return
  end
  owners[buf] = nil
  reset(buf)
  if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
    vim.api.nvim__redraw({ buf = buf, valid = true, flush = false })
  end
end

---Get the actual highlighter's unfiltered query, never reconstruct from files.
function M.specs(buf)
  local hl = highlighter.active[buf]
  if not hl then
    return {}, nil
  end
  if not hl.tree:is_valid() then
    hl.tree:parse(true)
  end
  local specs, seen = {}, {}
  local function visit(parser)
    local lang = parser:lang()
    if not seen[lang] then
      seen[lang] = true
      local query = original_get_query(hl, lang):query()
      if query then
        specs[#specs + 1] = { target_lang = lang, query = query, native = true }
      end
    end
    for _, child in pairs(parser:children()) do
      visit(child)
    end
  end
  visit(hl.tree)
  table.sort(specs, function(a, b)
    return a.target_lang < b.target_lang
  end)
  return specs, hl
end

return M
