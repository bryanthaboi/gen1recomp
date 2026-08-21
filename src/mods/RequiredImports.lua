-- Engine-owned import handling for files declared by a mod's required or
-- optional import arrays. Mods never receive host paths or broader
-- filesystem access: accepted bytes are copied into their own
-- mods/<id>/baseroms/ tree, where the existing mod:read sandbox can see them.

local CacheFs = require("src.import.CacheFs")

local RequiredImports = {}

local function allSpecs(manifest)
  local out = {}
  for _, spec in ipairs((manifest and manifest.required_imports) or {}) do
    out[#out + 1] = spec
  end
  for _, spec in ipairs((manifest and manifest.optional_imports) or {}) do
    out[#out + 1] = spec
  end
  return out
end

local function isRequired(spec)
  return spec.required ~= false
end

RequiredImports.specs = allSpecs
RequiredImports.MAX_BYTES = 2 * 1024 * 1024 * 1024
-- Past this, the launcher interposes a free-space warning before importing.
RequiredImports.LARGE_WARN_BYTES = 128 * 1024 * 1024

local function sizeLabel(bytes)
  if bytes >= 1024 * 1024 * 1024 then
    return ("%.1f GiB"):format(bytes / (1024 * 1024 * 1024))
  end
  return ("%.1f MiB"):format(bytes / (1024 * 1024))
end
RequiredImports.sizeLabel = sizeLabel

-- Check size before a caller reads an external or stored file into one large
-- Lua string. N64 sources may carry a 512-byte copier header, while stored
-- files are always canonical and therefore must match the declared size.
function RequiredImports.sizeError(spec, size, stored)
  if type(size) ~= "number" then return nil end
  if size > RequiredImports.MAX_BYTES then
    return ("file is too large (%s; hard limit is %s)")
      :format(sizeLabel(size), sizeLabel(RequiredImports.MAX_BYTES))
  end
  local headerAllowance = not stored and spec and spec.format == "n64" and 512 or 0
  if spec and spec.size then
    if size ~= spec.size and size ~= spec.size + headerAllowance then
      return ("wrong file size (expected %d bytes%s, got %d)")
        :format(spec.size, headerAllowance > 0 and " or a 512-byte header" or "", size)
    end
  end
  if spec and spec.max_size and size > spec.max_size + headerAllowance then
    return ("file is too large for this import (maximum %d bytes, got %d)")
      :format(spec.max_size, size)
  end
  return nil
end

local N64_MAGIC = {
  ["\128\55\18\64"] = "z64", -- big endian / canonical
  ["\55\128\64\18"] = "v64", -- byte-swapped
  ["\64\18\55\128"] = "n64", -- little endian words
}

local function n64KindAt(data, offset)
  return N64_MAGIC[data:sub(offset, offset + 3)]
end

-- Return canonical big-endian N64 bytes.  A 512-byte copier header is
-- recognized only when valid N64 magic follows it, so arbitrary data is never
-- shortened just because its size happens to line up.
function RequiredImports.normalizeN64(data)
  if type(data) ~= "string" then return nil, "selected file could not be read" end
  local offset, kind = 1, n64KindAt(data, 1)
  if not kind then
    kind = n64KindAt(data, 513)
    if kind then offset = 513 end
  end
  if not kind then
    return nil, "expected an N64 ROM (.z64/.v64/.n64); file signature was not recognized"
  end
  data = data:sub(offset)
  if kind == "z64" then return data end

  if kind == "v64" then
    if #data % 2 ~= 0 then return nil, "byte-swapped N64 ROM has an odd size" end
    return (data:gsub("(.)(.)", "%2%1"))
  else
    if #data % 4 ~= 0 then return nil, "little-endian N64 ROM size is not word aligned" end
    return (data:gsub("(.)(.)(.)(.)", "%4%3%2%1"))
  end
end

function RequiredImports.normalize(spec, data)
  if spec and spec.format == "n64" then
    return RequiredImports.normalizeN64(data)
  end
  if type(data) ~= "string" then return nil, "selected file could not be read" end
  return data
end

local function hexDigest(data, hashFn)
  if hashFn then return hashFn(data):lower() end
  if not (love and love.data and love.data.hash and love.data.encode) then
    return nil, "MD5 support is unavailable in this build"
  end
  local digest = love.data.hash("md5", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest):lower()
end

local function accepts(spec, digest)
  for _, wanted in ipairs((spec and spec.md5) or {}) do
    if wanted == digest then return true end
  end
  return false
end

local function specById(manifest, importId)
  for _, candidate in ipairs(allSpecs(manifest)) do
    if candidate.id == importId then return candidate end
  end
  return nil
end

RequiredImports.spec = specById

local function streamDigest(fs, path, chunkBytes)
  if not (fs and fs.newFile) then return nil, "streaming file access is unavailable" end
  local file, makeErr = fs.newFile(path)
  if not file then return nil, makeErr or "could not open stored import" end
  local ok, openErr = file:open("r")
  if not ok then return nil, openErr or "could not open stored import" end
  local MD5 = require("src.mods.StreamMD5")
  local ctx = MD5.new()
  chunkBytes = chunkBytes or (4 * 1024 * 1024)
  while true do
    local data, readErr = file:read(chunkBytes)
    if data and #data > 0 then ctx:update(data) end
    if not data or #data < chunkBytes then
      if readErr then file:close(); return nil, readErr end
      break
    end
  end
  file:close()
  return ctx:final()
end

function RequiredImports.path(manifest, spec)
  return manifest.path .. "/baseroms/" .. spec.file
end

local function removedMarker(manifest, spec)
  return manifest.path .. "/baseroms/.required-import-" .. spec.id .. ".removed"
end

local function receiptPath(manifest, spec)
  return manifest.path .. "/baseroms/.required-import-" .. spec.id .. ".validated"
end

RequiredImports.receiptPath = receiptPath

local function parseReceipt(raw)
  if type(raw) ~= "string" then return nil end
  local digest, size, modtime = raw:match("^v1\n([%x]+)\n(%d+)\n([^\n]+)\n?$")
  if not digest then return nil end
  return digest:lower(), tonumber(size), tonumber(modtime)
end

local function cachedDigest(manifest, spec, fs, info)
  -- A size alone cannot detect a same-length replacement. Require modtime as
  -- well; filesystems that do not expose it simply take the safe hash path.
  if not (fs and fs.read and info and info.size and info.modtime) then return nil end
  local digest, size, modtime = parseReceipt(fs.read(receiptPath(manifest, spec)))
  if digest and size == info.size and modtime == info.modtime
      and accepts(spec, digest) then
    return digest
  end
  return nil
end

local function writeReceipt(manifest, spec, digest, info, fs)
  if not (digest and info and info.size and info.modtime) then return end
  local path = receiptPath(manifest, spec)
  local body = ("v1\n%s\n%d\n%s\n")
    :format(digest, info.size, tostring(info.modtime))
  if love and fs == love.filesystem then
    local savedPrefix = CacheFs.prefix
    CacheFs.prefix = ""
    CacheFs.write(path, body)
    CacheFs.prefix = savedPrefix
  elseif fs and fs.write then
    fs.write(path, body)
  end
end

local function removeReceipt(manifest, spec, fs)
  local path = receiptPath(manifest, spec)
  if love and fs == love.filesystem then
    local savedPrefix = CacheFs.prefix
    CacheFs.prefix = ""
    CacheFs.remove(path)
    CacheFs.prefix = savedPrefix
  elseif fs and fs.remove then
    fs.remove(path)
  end
end

-- Finalize a caller-streamed import after the destination bytes have already
-- been copied into the engine-owned baseroms path. This keeps large imports
-- out of a single Lua string while preserving the same size/MD5 receipt rules.
function RequiredImports.acceptStoredDigest(manifest, importId, digest, fs)
  fs = fs or (love and love.filesystem)
  local spec = specById(manifest, importId)
  if not spec then return nil, "unknown required import: " .. tostring(importId) end
  digest = tostring(digest or ""):lower()
  if not accepts(spec, digest) then
    return nil, ("MD5 mismatch (got %s)"):format(digest ~= "" and digest or "unavailable")
  end
  local path = RequiredImports.path(manifest, spec)
  local info = fs and fs.getInfo and fs.getInfo(path, "file") or nil
  if not info then return nil, "copied import is missing" end
  local sizeErr = RequiredImports.sizeError(spec, info.size, true)
  if sizeErr then return nil, sizeErr end
  if love and fs == love.filesystem then
    local savedPrefix = CacheFs.prefix
    local ok, prefixErr = xpcall(function()
      CacheFs.prefix = ""
      CacheFs.remove(removedMarker(manifest, spec))
      CacheFs.prefix = savedPrefix
      -- writeReceipt has its own temporary CacheFs prefix switch. Keep it
      -- inside this guard too so a write error cannot leak global state.
      writeReceipt(manifest, spec, digest, info, fs)
    end, function(err)
      return tostring(err)
    end)
    CacheFs.prefix = savedPrefix
    if not ok then
      return nil, "could not finalize import receipt: " .. tostring(prefixErr)
    end
    return true, digest
  elseif fs and fs.remove then
    fs.remove(removedMarker(manifest, spec))
  end
  writeReceipt(manifest, spec, digest, info, fs)
  return true, digest
end


-- Validate bytes against a declaration.  The returned data is canonicalized
-- (notably for N64 byte order/header variants) and is what must be stored.
function RequiredImports.validateData(spec, data, hashFn)
  local sourceSizeErr = type(data) == "string"
    and RequiredImports.sizeError(spec, #data, false)
  if sourceSizeErr then return nil, sourceSizeErr end
  local normalized, normalizeErr = RequiredImports.normalize(spec, data)
  if not normalized then return nil, normalizeErr end
  local storedSizeErr = RequiredImports.sizeError(spec, #normalized, true)
  if storedSizeErr then return nil, storedSizeErr end
  local digest, hashErr = hexDigest(normalized, hashFn)
  if not digest then return nil, hashErr end
  if not accepts(spec, digest) then
    return nil, ("MD5 mismatch (got %s)"):format(digest)
  end
  return normalized, digest
end

-- Validate one installed import without reading it when the engine-authored
-- receipt still matches the file's size and modification time.
function RequiredImports.validateStored(manifest, spec, fs, hashFn)
  fs = fs or (love and love.filesystem)
  if not (fs and fs.getInfo) then return nil, "filesystem is unavailable" end
  local path = RequiredImports.path(manifest, spec)
  local info = fs.getInfo(path, "file")
  if not info then
    removeReceipt(manifest, spec, fs)
    return nil, "file is missing"
  end
  local sizeErr = RequiredImports.sizeError(spec, info.size, true)
  if sizeErr then
    removeReceipt(manifest, spec, fs)
    return nil, sizeErr
  end
  local cached = cachedDigest(manifest, spec, fs, info)
  if cached then return true, cached, true end
  removeReceipt(manifest, spec, fs)
  -- Large raw imports (GameCube discs, future optical images, etc.) must never
  -- be materialized into one Lua string merely because their validation
  -- receipt was lost. Stream the MD5 directly from the installed file. N64
  -- sources stay on the canonicalization path because byte-order/header
  -- normalization is part of their validation contract.
  if info.size and info.size > RequiredImports.LARGE_WARN_BYTES
      and spec.format ~= "n64" and fs.newFile then
    local digest, hashErr = streamDigest(fs, path)
    if not digest then return nil, hashErr end
    if not accepts(spec, digest) then
      return nil, ("MD5 mismatch (got %s)"):format(digest)
    end
    info = fs.getInfo(path, "file") or info
    writeReceipt(manifest, spec, digest, info, fs)
    return true, digest, false
  end
  if not fs.read then return nil, "file could not be read" end
  local data = fs.read(path)
  local normalized, detail = RequiredImports.validateStoredData(spec, data, hashFn)
  if not normalized then return nil, detail end
  info = fs.getInfo(path, "file") or info
  info.size = info.size or #data
  writeReceipt(manifest, spec, detail, info, fs)
  return true, detail, false
end

function RequiredImports.validateStoredData(spec, data, hashFn)
  local normalized, detail = RequiredImports.validateData(spec, data, hashFn)
  if not normalized then return nil, detail end
  if normalized ~= data then
    return nil, "stored N64 ROM is not canonical; choose the source file again"
  end
  return normalized, detail
end

function RequiredImports.inspect(manifest, fs, hashFn)
  fs = fs or (love and love.filesystem)
  local rows, missing, missingOptional = {}, 0, 0
  for _, spec in ipairs(allSpecs(manifest)) do
    local path = RequiredImports.path(manifest, spec)
    local suppressed = fs and fs.getInfo
      and fs.getInfo(removedMarker(manifest, spec), "file") ~= nil
    local exists = fs and fs.getInfo and fs.getInfo(path, "file") ~= nil
    local valid, detail = RequiredImports.validateStored(manifest, spec, fs, hashFn)
    local row = { id = spec.id, name = spec.name, file = spec.file,
      description = spec.description, format = spec.format, path = path,
      present = valid == true, digest = valid and detail or nil,
      error = exists and not valid and detail or nil,
      suppressed = suppressed, required = isRequired(spec), spec = spec }
    if not row.present then
      if row.required then missing = missing + 1
      else missingOptional = missingOptional + 1 end
    end
    rows[#rows + 1] = row
  end
  return rows, missing, missingOptional
end

function RequiredImports.importData(manifest, importId, data, opts)
  opts = opts or {}
  local spec
  for _, candidate in ipairs(allSpecs(manifest)) do
    if candidate.id == importId then spec = candidate break end
  end
  if not spec then return nil, "unknown required import: " .. tostring(importId) end
  local normalized, digest = RequiredImports.validateData(spec, data, opts.hash)
  if not normalized then return nil, digest end
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = ""
  CacheFs.remove(receiptPath(manifest, spec))
  local ok, err = CacheFs.write(RequiredImports.path(manifest, spec), normalized)
  if ok then CacheFs.remove(removedMarker(manifest, spec)) end
  if ok and love and love.filesystem and love.filesystem.getInfo then
    local info = love.filesystem.getInfo(RequiredImports.path(manifest, spec), "file")
    writeReceipt(manifest, spec, digest, info, love.filesystem)
  end
  CacheFs.prefix = savedPrefix
  if not ok then return nil, "could not copy import: " .. tostring(err) end
  return true, digest
end

function RequiredImports.remove(manifest, importId)
  for _, spec in ipairs(allSpecs(manifest)) do
    if spec.id == importId then
      local savedPrefix = CacheFs.prefix
      CacheFs.prefix = ""
      CacheFs.remove(RequiredImports.path(manifest, spec))
      CacheFs.remove(receiptPath(manifest, spec))
      local marked, markErr = CacheFs.write(removedMarker(manifest, spec), "removed\n")
      CacheFs.prefix = savedPrefix
      if not marked then return nil, "could not remember removal: " .. tostring(markErr) end
      return true
    end
  end
  return nil, "unknown required import: " .. tostring(importId)
end

return RequiredImports
