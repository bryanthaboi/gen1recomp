local Importers = require("src.import.Importers")
local SaveData = require("src.core.SaveData")

local AssetPacks = {}

AssetPacks.MAX_READ_BYTES = Importers.MAX_ENTRY_BYTES

local function specs(manifest)
  local out = {}
  for _, list in ipairs({ (manifest and manifest.required_assets) or {},
      (manifest and manifest.optional_assets) or {} }) do
    for _, spec in ipairs(list) do
      out[spec.importer .. "/" .. spec.pack] = spec
    end
  end
  return out
end

AssetPacks.specs = function(manifest)
  local out = {}
  for _, spec in ipairs((manifest and manifest.required_assets) or {}) do
    out[#out + 1] = spec
  end
  for _, spec in ipairs((manifest and manifest.optional_assets) or {}) do
    out[#out + 1] = spec
  end
  return out
end

local function copyMetadata(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copyMetadata(v) end
  return out
end

local function copyEntry(id, entry)
  return { id = id, file = entry.file, size = entry.size,
    width = entry.width, height = entry.height, frames = entry.frames,
    seconds = entry.seconds, note = entry.note, sprite = copyMetadata(entry.sprite),
    metadata = copyMetadata(entry.metadata) }
end

function AssetPacks.new(manifest, fs)
  local declared = specs(manifest)
  local packFs = SaveData.persistenceFs(fs) or fs
  local api = {}

  local function specFor(importerId, packId)
    local spec = declared[tostring(importerId) .. "/" .. tostring(packId)]
    if not spec then
      return nil, ("undeclared asset pack: %s/%s")
        :format(tostring(importerId), tostring(packId))
    end
    return spec
  end

  local function resolved(importerId, packId)
    local spec, err = specFor(importerId, packId)
    if not spec then return nil, err end
    return Importers.resolve(spec, packFs)
  end

  function api:list()
    local out = {}
    for _, spec in ipairs(AssetPacks.specs(manifest)) do
      local pack = Importers.resolve(spec, packFs)
      out[#out + 1] = {
        importer = spec.importer,
        pack = spec.pack,
        version = pack and pack.version or nil,
        kind = pack and pack.kind or nil,
        required = spec.required ~= false,
        installed = pack ~= nil,
      }
    end
    return out
  end

  function api:info(importerId, packId)
    local pack, err = resolved(importerId, packId)
    if not pack then return nil, err end
    local count = 0
    for _ in pairs(pack.entries) do count = count + 1 end
    return { importer = pack.importer, pack = pack.pack, kind = pack.kind,
      version = pack.version, entries = count, source = pack.source.name }
  end

  function api:entries(importerId, packId)
    local pack, err = resolved(importerId, packId)
    if not pack then return nil, err end
    local out = {}
    for id, entry in pairs(pack.entries) do
      out[#out + 1] = copyEntry(id, entry)
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
  end

  function api:entry(importerId, packId, entryId)
    local pack, err = resolved(importerId, packId)
    if not pack then return nil, err end
    local entry = pack.entries[entryId]
    if not entry then
      return nil, "no such pack entry: " .. tostring(entryId)
    end
    return copyEntry(entryId, entry)
  end

  function api:read(importerId, packId, entryId)
    local pack, err = resolved(importerId, packId)
    if not pack then return nil, err end
    local entry = pack.entries[entryId]
    if not entry then
      return nil, "no such pack entry: " .. tostring(entryId)
    end
    if entry.size > AssetPacks.MAX_READ_BYTES then
      return nil, "pack entry exceeds the 8 MiB read limit"
    end
    local path, pathErr = Importers.assetPath(pack.importer, pack.pack, entry.file)
    if not path then return nil, pathErr end
    if not (packFs and packFs.read) then
      return nil, "pack reads are unavailable"
    end
    local bytes = packFs.read(path)
    if type(bytes) ~= "string" then return nil, "pack entry is missing" end
    if #bytes ~= entry.size then return nil, "pack entry size does not match" end
    return bytes
  end

  function api:metadata(importerId, packId, entryId)
    local pack, err = resolved(importerId, packId)
    if not pack then return nil, err end
    local entry = pack.entries[entryId]
    if not entry then return nil, "no such pack entry: " .. tostring(entryId) end
    return Importers.readMetadata(importerId, packId, entry, packFs)
  end

  return api
end

return AssetPacks
