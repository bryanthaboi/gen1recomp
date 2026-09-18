-- Bound ROM reads via mod.imports (8 MiB max per call) into numeric byte tables.

local Rom = {}
Rom.__index = Rom

local CHUNK = 4 * 1024 * 1024 -- under ImportAccess.MAX_READ_BYTES (8 MiB)

function Rom.open(imports, importId)
  local info, err = imports:info(importId)
  if not info then return nil, err end
  local self = setmetatable({
    imports = imports,
    id = importId,
    size = info.size,
    md5 = info.md5,
    _cache = {}, -- optional page cache: pageIndex → 1-based bytes
  }, Rom)
  return self
end

local function page_index(offset)
  return math.floor(offset / CHUNK)
end

function Rom:ensurePage(page)
  if self._cache[page] then return self._cache[page] end
  local offset = page * CHUNK
  local length = math.min(CHUNK, self.size - offset)
  if length <= 0 then return nil end
  local data, err = self.imports:read(self.id, offset, length)
  if not data then error(err or "rom read failed") end
  local bytes = {}
  for i = 1, #data do
    bytes[i] = data:byte(i)
  end
  -- Drop oldest pages if cache grows large (keep ≤3 pages ≈ 12 MiB)
  local n = 0
  for _ in pairs(self._cache) do n = n + 1 end
  if n >= 3 then
    self._cache = {}
  end
  self._cache[page] = bytes
  return bytes
end

--- Byte at 0-based ROM offset.
function Rom:get(offset)
  if offset < 0 or offset >= self.size then
    error(("ROM OOB 0x%X"):format(offset))
  end
  local page = page_index(offset)
  local bytes = self:ensurePage(page)
  local localIndex = (offset % CHUNK) + 1
  return bytes[localIndex]
end

--- Read `length` bytes at 0-based offset into a new 1-based array.
function Rom:readBytes(offset, length)
  local out = {}
  for i = 0, length - 1 do
    out[i + 1] = self:get(offset + i)
  end
  return out
end

--- Read little-endian u16 / u32.
function Rom:u16(offset)
  return self:get(offset) + self:get(offset + 1) * 256
end

function Rom:u32(offset)
  return self:get(offset)
    + self:get(offset + 1) * 256
    + self:get(offset + 2) * 65536
    + self:get(offset + 3) * 16777216
end

--- GBA pointer (0x08XXXXXX) → file offset, or nil.
function Rom:ptrOffset(gbaPtr)
  if gbaPtr < 0x08000000 or gbaPtr >= 0x0A000000 then return nil end
  return gbaPtr - 0x08000000
end

function Rom:clearCache()
  self._cache = {}
end

return Rom
