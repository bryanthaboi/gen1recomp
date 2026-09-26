-- Zero-copy high-performance ROM accessor with LuaJIT FFI pointer anchoring
-- and ARM-safe byte arithmetic (no unaligned multi-byte typed pointer casts).

local RevisionView = require("src.import.gba.revision_view")

local ffi
do
  local ok, mod = pcall(require, "ffi")
  if ok and mod and mod.cast and mod.string then
    ffi = mod
  end
end

local bit = rawget(_G, "bit") or rawget(_G, "bit32")
if not bit then
  local ok, mod = pcall(require, "bit")
  if ok and mod then bit = mod end
end

local Rom = {}
Rom.__index = Rom

local CHUNK_READ_MAX = 8 * 1024 * 1024 -- ImportAccess.MAX_READ_BYTES limit

function Rom.open(imports, importId)
  local info, err = imports:info(importId)
  if not info then return nil, err end
  require("src.import.gba.versions").select(info.md5)

  local self = setmetatable({
    imports = imports,
    id = importId,
    size = info.size,
    md5 = info.md5,
    _info = info,
    _raw = nil,
    _cdata = nil,
  }, Rom)

  self:ensureBuffer()
  return self
end

function Rom:ensureBuffer()
  if self._raw and (#self._raw == self.size) then
    return self._raw
  end

  local info = self._info or (self.imports and self.imports:info(self.id))
  local view = RevisionView.forImports(self.imports, self.id, info)
  if type(view) == "string" and #view == self.size then
    self._raw = view
  else
    local chunks = {}
    local pos = 0
    while pos < self.size do
      local len = math.min(CHUNK_READ_MAX, self.size - pos)
      local part, rerr
      if view then
        part = view:sub(pos + 1, pos + len)
      else
        part, rerr = self.imports:read(self.id, pos, len)
      end
      if not part then error(rerr or "rom read failed") end
      chunks[#chunks + 1] = part
      pos = pos + len
    end
    self._raw = table.concat(chunks)
  end

  -- Anchor FFI pointer directly to self._raw on instance
  if ffi and self._raw then
    self._cdata = ffi.cast("const uint8_t*", self._raw)
  end

  return self._raw
end

--- Byte at 0-based ROM offset.
function Rom:get(offset)
  if offset < 0 or offset >= self.size then
    error(("ROM OOB 0x%X (size 0x%X)"):format(offset, self.size))
  end
  if not self._raw then self:ensureBuffer() end
  if self._cdata then
    return self._cdata[offset]
  end
  return string.byte(self._raw, offset + 1) or 0
end

--- Read little-endian u16 with ARM-safe byte arithmetic.
function Rom:u16(offset)
  if offset < 0 or offset + 1 >= self.size then
    error(("ROM OOB u16 0x%X"):format(offset))
  end
  if not self._raw then self:ensureBuffer() end
  if self._cdata then
    local cd = self._cdata
    if bit and bit.lshift then
      return cd[offset] + bit.lshift(cd[offset + 1], 8)
    end
    return cd[offset] + cd[offset + 1] * 256
  end
  local b0, b1 = string.byte(self._raw, offset + 1, offset + 2)
  return (b0 or 0) + (b1 or 0) * 256
end

--- Read little-endian u32 with ARM-safe byte arithmetic.
function Rom:u32(offset)
  if offset < 0 or offset + 3 >= self.size then
    error(("ROM OOB u32 0x%X"):format(offset))
  end
  if not self._raw then self:ensureBuffer() end
  if self._cdata then
    local cd = self._cdata
    if bit and bit.lshift then
      return cd[offset]
        + bit.lshift(cd[offset + 1], 8)
        + bit.lshift(cd[offset + 2], 16)
        + cd[offset + 3] * 16777216
    end
    return cd[offset]
      + cd[offset + 1] * 256
      + cd[offset + 2] * 65536
      + cd[offset + 3] * 16777216
  end
  local b0, b1, b2, b3 = string.byte(self._raw, offset + 1, offset + 4)
  return (b0 or 0)
    + (b1 or 0) * 256
    + (b2 or 0) * 65536
    + (b3 or 0) * 16777216
end

--- Fast binary slice read (returns binary Lua string).
function Rom:readString(offset, length)
  if offset < 0 or length < 0 or offset + length > self.size then
    error(("ROM OOB readString 0x%X + %d"):format(offset, length))
  end
  if length == 0 then return "" end
  if not self._raw then self:ensureBuffer() end
  if self._cdata and ffi then
    return ffi.string(self._cdata + offset, length)
  end
  return self._raw:sub(offset + 1, offset + length)
end

--- Read `length` bytes at 0-based offset into a new 1-based array.
function Rom:readBytes(offset, length)
  if offset < 0 or length < 0 or offset + length > self.size then
    error(("ROM OOB readBytes 0x%X + %d"):format(offset, length))
  end
  if not self._raw then self:ensureBuffer() end
  local out = {}
  if self._cdata then
    local cd = self._cdata
    for i = 0, length - 1 do
      out[i + 1] = cd[offset + i]
    end
  else
    local raw = self._raw
    for i = 0, length - 1 do
      out[i + 1] = string.byte(raw, offset + i + 1)
    end
  end
  return out
end

--- GBA pointer (0x08XXXXXX) → file offset, or nil.
function Rom:ptrOffset(gbaPtr)
  if not gbaPtr or gbaPtr < 0x08000000 or gbaPtr >= 0x0A000000 then return nil end
  return gbaPtr - 0x08000000
end

function Rom:clearCache()
  -- Rom holds contiguous buffer for the lifetime of open ROM handle
end

return Rom
