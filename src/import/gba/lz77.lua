-- GBA BIOS LZ77 decompress.
-- High performance: uses LuaJIT FFI with reusable buffer & bitwise ops,
-- falling back safely to pure-Lua with strict bounds checking.

local Lz77 = {}

local ffi
do
  local ok, mod = pcall(require, "ffi")
  if ok and mod and mod.new and mod.string then
    ffi = mod
  end
end

local bit = rawget(_G, "bit") or rawget(_G, "bit32")
if not bit then
  local ok, mod = pcall(require, "bit")
  if ok and mod then bit = mod end
end

-- Reusable static FFI buffer to prevent GC allocation churn in tight loops
local ffi_buf = nil
local ffi_cap = 0

local function get_ffi_buffer(min_size)
  if not ffi then return nil end
  if ffi_cap < min_size then
    local new_cap = math.max(min_size + 1024, math.max(65536, ffi_cap * 2))
    ffi_buf = ffi.new("uint8_t[?]", new_cap)
    ffi_cap = new_cap
  end
  return ffi_buf
end

function Lz77.len(buf)
  if type(buf) == "string" then return #buf end
  if type(buf) == "table" then return buf._len or #buf end
  return 0
end

--- Decompress GBA LZ77 starting at `offset` in a byte source.
-- @param get fun(i: integer): integer | string | table  -- 0-based absolute ROM index → byte, or string/table
-- @param offset integer  -- 0-based start of LZ header
-- @return table out  -- 1-based byte array of uncompressed data
-- @return integer bytes_consumed
function Lz77.decompress(get, offset)
  offset = offset or 0
  local get_byte
  if type(get) == "function" then
    get_byte = get
  elseif type(get) == "string" then
    get_byte = function(i) return string.byte(get, i + 1) or 0 end
  elseif type(get) == "table" and get.get then
    get_byte = function(i) return get:get(i) or 0 end
  elseif type(get) == "table" then
    get_byte = function(i) return get[i + 1] or 0 end
  else
    error("LZ77: invalid byte source")
  end

  local typ = get_byte(offset)
  if typ ~= 0x10 then
    error(("LZ77: expected type 0x10 at 0x%X, got 0x%02X"):format(offset, typ or 0))
  end
  local size = get_byte(offset + 1) + get_byte(offset + 2) * 256 + get_byte(offset + 3) * 65536
  if size <= 0 or size > 8 * 1024 * 1024 then
    error(("LZ77: unreasonable size %d"):format(size))
  end

  local src = offset + 4
  local out = {}
  local buf = get_ffi_buffer(size)

  local band = bit and bit.band
  local rshift = bit and bit.rshift
  local lshift = bit and bit.lshift
  local bor = bit and bit.bor

  if buf and band and rshift and bor and lshift then
    -- Fast FFI + bitops path
    local produced = 0
    while produced < size do
      local flags = get_byte(src)
      src = src + 1
      for bi = 7, 0, -1 do
        if produced >= size then break end
        local is_ref = band(rshift(flags, bi), 1) == 1
        if is_ref then
          local b1 = get_byte(src)
          local b2 = get_byte(src + 1)
          src = src + 2
          local length = rshift(b1, 4) + 3
          local disp = bor(lshift(band(b1, 0x0F), 8), b2)
          for _ = 1, length do
            if produced >= size then break end
            local read_pos = produced - 1 - disp
            local v = 0
            if read_pos >= 0 then
              v = buf[read_pos]
            end
            buf[produced] = v
            produced = produced + 1
          end
        else
          buf[produced] = get_byte(src) or 0
          src = src + 1
          produced = produced + 1
        end
      end
    end

    -- Convert FFI buffer to 1-based table for caller compatibility
    for i = 1, size do
      out[i] = buf[i - 1]
    end
    out._raw_size = size
  else
    -- Fallback pure-Lua path with bitwise optimization if available
    local produced = 0
    local o = 0
    while produced < size do
      local flags = get_byte(src)
      src = src + 1
      for bi = 7, 0, -1 do
        if produced >= size then break end
        local is_ref
        if band and rshift then
          is_ref = band(rshift(flags, bi), 1) == 1
        else
          local mask = 2 ^ bi
          is_ref = math.floor(flags / mask) % 2 == 1
        end

        if is_ref then
          local b1 = get_byte(src)
          local b2 = get_byte(src + 1)
          src = src + 2
          local length, disp
          if rshift and band and bor and lshift then
            length = rshift(b1, 4) + 3
            disp = bor(lshift(band(b1, 0x0F), 8), b2)
          else
            length = math.floor(b1 / 16) + 3
            disp = (b1 % 16) * 256 + b2
          end

          for _ = 1, length do
            if produced >= size then break end
            local read_pos = produced - disp
            local v = 0
            if read_pos >= 1 then
              v = out[read_pos] or 0
            end
            o = o + 1
            out[o] = v
            produced = produced + 1
          end
        else
          o = o + 1
          out[o] = get_byte(src) or 0
          src = src + 1
          produced = produced + 1
        end
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
  if n == 0 then return "" end

  if ffi then
    local buf = get_ffi_buffer(n)
    for i = 1, n do
      buf[i - 1] = arr[i] or 0
    end
    return ffi.string(buf, n)
  end

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

