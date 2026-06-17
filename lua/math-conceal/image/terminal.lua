local state = require("math-conceal.image.state")

local M = {}

local is_tmux = vim.env.TMUX ~= nil
local stdout = nil
local pending = {}

local function tmux_escape(message)
  return "\x1bPtmux;" .. message:gsub("\x1b", "\x1b\x1b") .. "\x1b\\"
end

local function encode_kitty(message)
  local payload = "\x1b_G" .. message .. "\x1b\\"
  if is_tmux then
    return tmux_escape(payload)
  end
  return payload
end

local function queue(message)
  pending[#pending + 1] = encode_kitty(message)
end

local function write(data)
  if vim.api.nvim_ui_send ~= nil and pcall(vim.api.nvim_ui_send, data) then
    return
  end

  stdout = stdout or assert(vim.uv.new_tty(1, false))
  stdout:write(data)
end

function M.flush()
  if #pending == 0 then
    return
  end
  local data = table.concat(pending)
  pending = {}
  write(data)
end

function M.upload(path, image_id, cols, rows)
  if type(path) ~= "string" or path == "" then
    return false
  end

  cols = math.max(1, math.floor(tonumber(cols) or 1))
  rows = math.max(1, math.floor(tonumber(rows) or 1))
  queue("q=2,f=100,t=t,i=" .. image_id .. ";" .. vim.base64.encode(path))
  queue("q=2,a=p,U=1,i=" .. image_id .. ",c=" .. cols .. ",r=" .. rows)
  M.flush()
  return true
end

function M.delete(image_id)
  if image_id == nil then
    return
  end
  queue("q=2,a=d,d=i,i=" .. image_id)
  state.release_image_id(image_id)
  M.flush()
end

return M
