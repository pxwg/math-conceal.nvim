-- Persistent source highlighting, excluding the formula's own decorations.
local M = {}
local tree_cache = setmetatable({}, { __mode = "k" })

-- Renderer/source overrides image defaults; keep the existing global option compatible.
function M.enabled(options, defaults)
  local value = options and options.inherit_environment_color
  if value == nil then
    value = options and options.inherit_environment
  end
  if value == nil and defaults then
    value = defaults.inherit_environment_color
    if value == nil then
      value = defaults.inherit_environment
    end
  end
  return value ~= false
end

function M.resolve_for(bufnr, winid, span, options, defaults)
  if M.enabled(options, defaults) then
    return M.resolve(bufnr, winid, span)
  end
end

local function before(ar, ac, br, bc)
  return ar < br or (ar == br and ac < bc)
end

local function contains(r, span, strict)
  return not before(span.row, span.col, r[1], r[2])
    and not before(r[3], r[4], span.end_row, span.end_col)
    and (not strict or before(r[1], r[2], span.row, span.col) or before(span.end_row, span.end_col, r[3], r[4]))
end

local function excluded(name)
  name = (name or ""):lower()
  return name:find("math%-conceal")
    or name:find("diagnostic")
    or name:find("semantic_tokens")
    or name:find("search")
    or name:find("visual")
end

-- Resolve links in the window namespace, with the same global fallback as Nvim.
local function foreground(winid, name)
  if not name or name == "" then
    return nil
  end
  local ns = vim.api.nvim_get_hl_ns({ winid = winid })
  ns = ns >= 0 and ns or vim.api.nvim_get_hl_ns({})
  ns = math.max(0, ns)
  if ns == 0 then
    local mapped = vim.wo[winid].winhighlight:match("Normal:([^,]+)")
    if name == "Normal" and mapped then
      name = mapped
    end
  end
  local function lookup(group, seen)
    if seen[group] then
      return {}
    end
    seen[group] = true
    local opts = { name = group, link = true, create = false }
    local hl = vim.api.nvim_get_hl(ns, opts)
    if next(hl) == nil and ns ~= 0 then
      hl = vim.api.nvim_get_hl(0, opts)
    end
    if hl.link then
      return lookup(hl.link, seen)
    end
    -- Tree-sitter groups fall back from @capture.language to @capture,
    -- then through dotted capture parents, even when no explicit link exists.
    if next(hl) == nil and group:sub(1, 1) == "@" then
      local parent = group:match("^(.*)%.[^.]+$")
      if parent then
        return lookup(parent, seen)
      end
    end
    return hl
  end
  return lookup(name, {}).fg
end

---Resolve an enclosing environment's foreground; nil keeps default math styling.
---span is the complete formula range, with an exclusive end.
function M.resolve(bufnr, winid, span)
  if not winid or not vim.api.nvim_win_is_valid(winid) or vim.api.nvim_win_get_buf(winid) ~= bufnr then
    return nil
  end
  local candidates = {}
  local function add(group, priority)
    if type(group) == "table" then
      for _, item in ipairs(group) do
        add(item, priority)
      end
    elseif group and not excluded(group) then
      local fg = foreground(winid, group)
      if fg then
        candidates[#candidates + 1] = { fg = fg, priority = tonumber(priority) or 0, order = #candidates + 1 }
      end
    end
  end

  -- Syntax stacks retain outer regions even when a math region covers the text.
  vim.api.nvim_win_call(winid, function()
    for _, id in ipairs(vim.fn.synstack(span.row + 1, span.col + 1)) do
      local name = vim.fn.synIDattr(id, "name")
      if not name:lower():find("math") and not name:lower():find("equation") then
        add(name, 0)
      end
    end
  end)

  local specs, highlighter = require("math-conceal.native-conceal").specs(bufnr)
  if highlighter then
    local queries = {}
    for _, spec in ipairs(specs) do
      queries[spec.target_lang] = spec.query
    end
    local roots, signature = {}, { tostring(vim.api.nvim_buf_get_changedtick(bufnr)) }
    highlighter.tree:for_each_tree(function(tree, language)
      local lang = language:lang()
      roots[#roots + 1] = { root = tree:root(), lang = lang }
      signature[#signature + 1] = lang .. tostring(tree:root():id()) .. tostring(queries[lang])
    end)
    signature = table.concat(signature, ":")
    local cache = tree_cache[highlighter]
    if not cache or cache.signature ~= signature then
      cache = { signature = signature, spans = {} }
      tree_cache[highlighter] = cache
    end
    local key = table.concat({ span.row, span.col, span.end_row, span.end_col }, ":")
    local captures = cache.spans[key]
    if not captures then
      captures = {}
      cache.spans[key] = captures
      for _, entry in ipairs(roots) do
        local query = queries[entry.lang]
        if query then
          for id, node, metadata in query:iter_captures(entry.root, bufnr, span.row, span.row + 1) do
            local data = metadata[id] or {}
            local range = vim.treesitter.get_range(node, bufnr, data)
            if contains({ range[1], range[2], range[4], range[5] }, span, true) then
              captures[#captures + 1] =
                { "@" .. query.captures[id] .. "." .. entry.lang, data.priority or metadata.priority or 100 }
            end
          end
        end
      end
    end
    for _, capture in ipairs(captures) do
      add(capture[1], capture[2])
    end
  end

  local namespaces = {}
  for name, id in pairs(vim.api.nvim_get_namespaces()) do
    namespaces[id] = name
  end
  for _, mark in
    ipairs(
      vim.api.nvim_buf_get_extmarks(
        bufnr,
        -1,
        { span.row, span.col },
        { span.row, span.col },
        { details = true, overlap = true }
      )
    )
  do
    local d = mark[4]
    if
      not d.invalid
      and not excluded(namespaces[d.ns_id])
      and contains({ mark[2], mark[3], d.end_row or mark[2], d.end_col or mark[3] }, span, false)
    then
      add(d.hl_group, d.priority or 0)
    end
  end
  table.sort(candidates, function(a, b)
    return a.priority < b.priority or (a.priority == b.priority and a.order < b.order)
  end)
  local color = candidates[#candidates] and candidates[#candidates].fg
  return color ~= foreground(winid, "Normal") and color or nil
end

function M.group(color)
  if not color then
    return nil
  end
  local name = ("MathConcealEnvironment%06X"):format(color)
  if vim.api.nvim_get_hl(0, { name = name, create = false }).fg ~= color then
    vim.api.nvim_set_hl(0, name, { fg = color })
  end
  return name
end

return M
