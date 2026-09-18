-- GBA BIOS LZ77 decompress.
-- Prefer LuaJIT FFI uint8 buffers; fall back to preallocated numeric arrays.
-- Never build output via string concatenation.

local Lz77 = {}

local ffi
do
  local ok, mod = pcall(require, "ffi")
  if ok then ffi = mod end
end

local function ensure_capacity(arr, n)
  for i = #arr + 1, n do
    arr[i] = 0
  end
end

function Lz77.len(buf)
  if type(buf) == "string" then return #buf end
  if type(buf) == "table" then return buf._len or #buf end
  return 0
end

--- Decompress GBA LZ77 starting at `offset` in a byte source.
-- @param get fun(i: integer): integer  -- 0-based absolute ROM index → byte
-- @param offset integer  -- 0-based start of LZ header
-- @return table out  -- 1-based byte array of uncompressed data
-- @return integer bytes_consumed
function Lz77.decompress(get, offset)
  local typ = get(offset)
  if typ ~= 0x10 then
    error(("LZ77: expected type 0x10 at 0x%X, got 0x%02X"):format(offset, typ))
  end
  local size = get(offset + 1) + get(offset + 2) * 256 + get(offset + 3) * 65536
  if size <= 0 or size > 8 * 1024 * 1024 then
    error(("LZ77: unreasonable size %d"):format(size))
  end

  local src = offset + 4
  local out = {}
  local o = 0

  local produced = 0
  while produced < size do
    local flags = get(src)
    src = src + 1
    for bi = 0, 7 do
      if produced >= size then break end
      local mask = 2 ^ (7 - bi)
      local is_ref = math.floor(flags / mask) % 2 == 1
      if is_ref then
        local b1 = get(src)
        local b2 = get(src + 1)
        src = src + 2
        local length = math.floor(b1 / 16) + 3
        local disp = (b1 % 16) * 256 + b2
        for _ = 1, length do
          if produced >= size then break end
          local v = out[produced - disp] or 0
          o = o + 1
          out[o] = v
          produced = produced + 1
        end
      else
        o = o + 1
        out[o] = get(src) or 0
        src = src + 1
        produced = produced + 1
      end
    end
  end

  return out, src - offset
end

--- Decompress from a 1-based byte array / string-like source.
function Lz77.decompressFromBytes(bytes, offset0)
  local function get(i)
    local v = bytes[i + 1]
    if not v and type(bytes) == "string" then
      v = bytes:byte(i + 1)
    end
    if not v then error(("LZ77: OOB read at 0x%X"):format(i)) end
    return v
  end
  return Lz77.decompress(get, offset0 or 0)
end

--- Pack 1-based byte array to binary string (for cache writes).
function Lz77.toString(arr)
  if type(arr) == "string" then return arr end
  local n = (arr and arr._len) or (arr and #arr) or 0
  local parts = {}
  local CHUNK = 4096
  for i = 1, n, CHUNK do
    local last = math.min(i + CHUNK - 1, n)
    local t = {}
    for j = i, last do
      t[#t + 1] = string.char(arr[j] or 0)
    end
    parts[#parts + 1] = table.concat(t)
  end
  return table.concat(parts)
end

--- Encode uncompressed payload as GBA LZ77 (store-only blocks) for tests.
function Lz77.compressStore(payload)
  -- payload: 1-based bytes or string
  local function at(i)
    if type(payload) == "string" then return payload:byte(i) end
    return payload[i]
  end
  local size = type(payload) == "string" and #payload or #payload
  local out = { 0x10, size % 256, math.floor(size / 256) % 256, math.floor(size / 65536) % 256 }
  local i = 1
  while i <= size do
    local flags_index = #out + 1
    out[flags_index] = 0
    local flag = 0
    local literals = {}
    for bit = 0, 7 do
      if i <= size then
        literals[#literals + 1] = at(i)
        i = i + 1
      end
    end
    out[flags_index] = flag -- all literal
    for _, b in ipairs(literals) do out[#out + 1] = b end
  end
  return out
end

return Lz77
