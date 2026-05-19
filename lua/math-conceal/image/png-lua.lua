-- A modified version of https://github.com/Didericis/png-lua
-- Which contained the below license:

-- The MIT License (MIT)

-- Copyright (c) 2013 DelusionalLogic

-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
-- the Software, and to permit persons to whom the Software is furnished to do so,
-- subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
-- FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
-- COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
-- IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
-- CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

local function bsLeft(num, pow)
  return math.floor(num * 2 ^ pow)
end

local function bytesToNum(bytes)
  local n = 0
  for k, v in ipairs(bytes) do
    n = bsLeft(n, 8) + v
  end
  if n > 2147483647 then
    return (n - 4294967296)
  else
    return n
  end
  n = (n > 2147483647) and (n - 4294967296) or n
  return n
end

---@param stream file*
---@return integer
local function readInt(stream, bps)
  local bytes = {}
  bps = bps or 4
  for i = 1, bps do
    bytes[i] = stream:read(1):byte()
  end
  return bytesToNum(bytes)
end

---@param stream file*
local function readChar(stream, num)
  num = num or 1
  return stream:read(num)
end

---@param stream file*
---@return integer
local function readByte(stream)
  return stream:read(1):byte()
end

---@param stream file*
---@param length integer
---@return IHDRdata
local function getDataIHDR(stream, length)
  local data = {}
  data["width"] = readInt(stream)
  data["height"] = readInt(stream)
  data["bitDepth"] = readByte(stream)
  data["colorType"] = readByte(stream)
  data["compression"] = readByte(stream)
  data["filter"] = readByte(stream)
  data["interlace"] = readByte(stream)
  return data
end

--- @class IHDRdata
--- @field width integer
--- @field height integer
--- @field bitDepth integer
--- @field colorType integer
--- @field compression integer
--- @field filter integer
--- @field interlace integer

--- @class pngData
--- @field IHDR IHDRdata

--- @param stream file*
--- @return IHDRdata
local function extractChunkData(stream)
  local chunkData = {}
  local length
  local type
  local crc

  while type ~= "IEND" do
    length = readInt(stream)
    type = readChar(stream, 4)
    if type == "IHDR" then
      -- We have the data we want, free to return
      return getDataIHDR(stream, length)
    else
      readChar(stream, length)
    end
    crc = readChar(stream, 4)
  end

  return chunkData
end

--- Return png metadata
--- @param path string
--- @return IHDRdata
local function pngData(path)
  local stream, err = io.open(path, "rb")

  if err ~= nil then
    error("File '" .. path .. "' failed to open: " .. err)
  end

  if stream == nil then
    error("File '" .. path .. "' failed to open with no error")
  end

  if readChar(stream, 8) ~= "\137\080\078\071\013\010\026\010" then
    error("File '" .. path .. "' is not a png (missing magic bytes)")
  end

  local data = extractChunkData(stream)
  stream:close()
  return data
end

return pngData
