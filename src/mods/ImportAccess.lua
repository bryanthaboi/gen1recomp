-- Scoped access to a mod's launcher-validated required/optional imports and
-- to installation-wide generated cache data.
--
-- This intentionally does not expose host paths or raw filesystem handles.
-- Import reads are bounded and can only address ids declared by the calling
-- mod's manifest. Cache paths are confined to mod_cache/<mod-id>/ and are not
-- tied to a Pokémon playthrough.

local RequiredImports = require("src.mods.RequiredImports")
local SafePath = require("src.mods.SafePath")
local SaveData = require("src.core.SaveData")

local ImportAccess = {}

ImportAccess.MAX_READ_BYTES = 8 * 1024 * 1024
ImportAccess.MAX_CACHE_WRITE_BYTES = 64 * 1024 * 1024

local function specMap(manifest)
  local out = {}
  for _, spec in ipairs(RequiredImports.specs(manifest)) do out[spec.id] = spec end
  return out
end

local function parentOf(path)
  return path:match("^(.*)/[^/]+$")
end

local function copyInfo(info)
  if not info then return nil end
  return { type = info.type, size = info.size, modtime = info.modtime }
end

local function fsReadRange(fs, path, offset, length)
  if fs and type(fs.readRange) == "function" then
    return fs.readRange(path, offset, length)
  end
  local newFile = fs and fs.newFile
  if newFile then
    local file, makeErr = newFile(path)
    if not file then return nil, makeErr or "could not open import" end
    local ok, openErr = file:open("r")
    if not ok then return nil, openErr or "could not open import" end
    local seekOk, seekErr = file:seek(offset)
    if seekOk == nil or seekOk == false then
      file:close()
      return nil, seekErr or "could not seek import"
    end
    local data, readErr = file:read(length)
    file:close()
    return data, readErr
  end
  -- Injectable headless filesystems may expose only read(). Production
  -- love.filesystem has newFile(), so large imports are never materialized
  -- into one Lua string by this fallback.
  if fs and fs.read then
    local data = fs.read(path)
    if type(data) ~= "string" then return nil, "could not read import" end
    return data:sub(offset + 1, offset + length)
  end
  return nil, "random-access import reads are unavailable"
end

local function validatedInfo(manifest, spec, fs)
  local ok, detail = RequiredImports.validateStored(manifest, spec, fs)
  if not ok then return nil, detail or "import is not validated" end
  local path = RequiredImports.path(manifest, spec)
  local info = fs.getInfo and fs.getInfo(path, "file") or nil
  if not info then return nil, "import is missing" end
  return info, detail
end

local function makeCache(modId, fs)
  local root = "mod_cache/" .. modId
  local function pathFor(rel, what)
    rel = SafePath.require(rel, what or "mod.cache path")
    return root .. "/" .. rel
  end
  local cache = {}

  function cache:write(rel, bytes)
    if type(bytes) ~= "string" then
      return nil, "mod.cache:write expects a byte string"
    end
    if #bytes > ImportAccess.MAX_CACHE_WRITE_BYTES then
      return nil, "mod.cache:write payload exceeds 64 MiB; split generated data into smaller files"
    end
    local path = pathFor(rel, "mod.cache:write")
    local parent = parentOf(path)
    if parent and fs.createDirectory then
      local ok = fs.createDirectory(parent)
      if ok == false then return nil, "could not create cache directory" end
    end
    if not fs.write then return nil, "cache writes are unavailable" end
    return fs.write(path, bytes)
  end

  function cache:read(rel)
    local path = pathFor(rel, "mod.cache:read")
    if not fs.read then return nil, "cache reads are unavailable" end
    return fs.read(path)
  end

  function cache:info(rel)
    local path = pathFor(rel, "mod.cache:info")
    if not fs.getInfo then return nil end
    return copyInfo(fs.getInfo(path))
  end

  function cache:exists(rel)
    local info = self:info(rel)
    return info ~= nil and info.type == "file"
  end


  function cache:delete(rel)
    local path = pathFor(rel, "mod.cache:delete")
    if not fs.remove then return nil, "cache deletion is unavailable" end
    return fs.remove(path)
  end

  return cache
end

function ImportAccess.new(manifest, fs)
  local specs = specMap(manifest)
  local cacheFs = SaveData.persistenceFs(fs) or fs
  local imports = {}

  function imports:info(id)
    local spec = specs[id]
    if not spec then return nil, "undeclared import: " .. tostring(id) end
    local info, digestOrErr = validatedInfo(manifest, spec, fs)
    if not info then return nil, digestOrErr end
    return {
      id = spec.id,
      name = spec.name,
      file = spec.file,
      size = info.size,
      md5 = digestOrErr,
      required = spec.required ~= false,
    }
  end

  function imports:read(id, offset, length)
    local spec = specs[id]
    if not spec then return nil, "undeclared import: " .. tostring(id) end
    offset, length = tonumber(offset), tonumber(length)
    if not offset or offset < 0 or offset % 1 ~= 0 then
      return nil, "offset must be a non-negative integer"
    end
    if not length or length < 0 or length % 1 ~= 0 then
      return nil, "length must be a non-negative integer"
    end
    if length > ImportAccess.MAX_READ_BYTES then
      return nil, "single import read exceeds 8 MiB"
    end

    local info, err = validatedInfo(manifest, spec, fs)
    if not info then return nil, err end
    local size = tonumber(info.size) or tonumber(spec.size)
    if size and offset + length > size then return nil, "import read is out of bounds" end
    if length == 0 then return "" end

    local path = RequiredImports.path(manifest, spec)
    local data, readErr = fsReadRange(fs, path, offset, length)
    if not data then return nil, readErr end
    if #data ~= length then return nil, "short import read" end
    return data
  end

  return imports, makeCache(manifest.id, cacheFs)
end

return ImportAccess
