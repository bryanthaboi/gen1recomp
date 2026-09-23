local SafePath = require("src.mods.SafePath")
local Semver = require("src.mods.Semver")

local Importers = {}

Importers.ROOT = "asset_packs"
Importers.PACK_FILE = "pack.lua"
Importers.PACK_FORMAT = 1
Importers.MAX_ENTRY_BYTES = 8 * 1024 * 1024

Importers.KINDS = {
  sprite  = { ext = { png = true } },
  tileset = { ext = { png = true } },
  palette = { ext = { png = true, lua = true } },
  font    = { ext = { png = true } },
  sfx     = { ext = { wav = true, ogg = true } },
  music   = { ext = { ogg = true, wav = true } },
  sample  = { ext = { wav = true, ogg = true } },
}

Importers.STATUS = { planned = true, beta = true, ready = true }

local ID_PATTERN = "^[%l%d_%-]+$"
local ENTRY_PATTERN = "^[%l%d_%-]+[%l%d_%-/]*$"

local LIST = {
  {
    id = "pmd_red",
    name = "Pokémon Mystery Dungeon",
    status = "beta",
    summary = "All Pokémon sprite sheets and animations from Red Rescue Team.",
    source = {
      name = "Mystery Dungeon Red Rescue Team (USA/Australia) GBA cartridge dump",
      formats = { "gba" }, sizes = { 33554432 },
    },
    packs = {
      { id = "sprites", kind = "sprite", name = "Pokémon sprites",
        description = "423 Pokémon and form sheets with poses, directions and animation timing." },
    },
  },
  {
    id = "lttp",
    name = "A Link to the Past",
    status = "beta",
    summary = "Sprites, tiles and sound out of your own Link to the Past cartridge dump.",
    source = {
      name = "A Link to the Past (SNES) cartridge dump",
      formats = { "sfc", "smc" },
      sizes = { 1048576, 2097152 },
    },
    packs = {
      { id = "sprites", kind = "sprite", name = "Sprites",
        description = "Overworld, menu and enemy sprite sheets." },
      { id = "tiles", kind = "tileset", name = "Tiles",
        description = "Overworld and dungeon tilesets with their palettes." },
      { id = "palettes", kind = "palette", name = "Palettes",
        description = "Sprite and armor palette rows the sheets are drawn with." },
      { id = "sfx", kind = "sfx", name = "Sound effects", planned = true,
        description = "The SPC sound effect bank, one file per effect." },
      { id = "music", kind = "music", name = "Music", planned = true,
        description = "The SPC music bank, rendered per track." },
    },
  },
}

local BY_ID = {}
for _, desc in ipairs(LIST) do BY_ID[desc.id] = desc end

function Importers.all() return LIST end

function Importers.get(id) return BY_ID[id] end

function Importers.pack(importerId, packId)
  local desc = BY_ID[importerId]
  for _, p in ipairs(desc and desc.packs or {}) do
    if p.id == packId then return p end
  end
  return nil
end

local function badId(value)
  return type(value) ~= "string" or not value:match(ID_PATTERN)
end

function Importers.validateDescriptor(desc)
  if type(desc) ~= "table" then return false, "importer must be a table" end
  if badId(desc.id) then
    return false, "importer id must be lowercase letters, numbers, _ or -"
  end
  if type(desc.name) ~= "string" or desc.name == "" then
    return false, "importer name is required"
  end
  if not Importers.STATUS[desc.status] then
    return false, "importer status must be planned, beta or ready"
  end
  if type(desc.source) ~= "table" or type(desc.source.name) ~= "string" then
    return false, "importer source must name the dump it reads"
  end
  if type(desc.packs) ~= "table" or #desc.packs == 0 then
    return false, "importer must declare at least one pack"
  end
  local seen = {}
  for _, p in ipairs(desc.packs) do
    if badId(p.id) then
      return false, "pack id must be lowercase letters, numbers, _ or -"
    end
    if seen[p.id] then return false, "duplicate pack id: " .. p.id end
    seen[p.id] = true
    if not Importers.KINDS[p.kind] then
      return false, ("pack %s has unknown kind %s"):format(p.id, tostring(p.kind))
    end
    if type(p.name) ~= "string" or p.name == "" then
      return false, "pack " .. p.id .. " needs a name"
    end
  end
  return true
end

function Importers.packRoot(importerId, packId)
  return Importers.ROOT .. "/" .. importerId .. "/" .. packId
end

function Importers.manifestPath(importerId, packId)
  return Importers.packRoot(importerId, packId) .. "/" .. Importers.PACK_FILE
end

function Importers.assetPath(importerId, packId, file)
  local rel = SafePath.safe(file)
  if not rel then return nil, "pack file must stay inside its pack" end
  return Importers.packRoot(importerId, packId) .. "/" .. rel
end

local function extensionOf(file)
  return (file:match("%.([%a%d]+)$") or ""):lower()
end

function Importers.validatePack(manifest, importerId, packId)
  if type(manifest) ~= "table" then return false, "pack manifest must be a table" end
  if manifest.format ~= Importers.PACK_FORMAT then
    return false, ("pack format %s is not %d")
      :format(tostring(manifest.format), Importers.PACK_FORMAT)
  end
  if importerId and manifest.importer ~= importerId then
    return false, "pack manifest names a different importer"
  end
  if packId and manifest.pack ~= packId then
    return false, "pack manifest names a different pack"
  end
  if badId(manifest.importer) or badId(manifest.pack) then
    return false, "pack manifest importer and pack ids are malformed"
  end
  local kind = Importers.KINDS[manifest.kind]
  if not kind then
    return false, "pack kind is unknown: " .. tostring(manifest.kind)
  end
  if not Semver.parse(manifest.version or "") then
    return false, "pack version must be semver"
  end
  if type(manifest.source) ~= "table" or type(manifest.source.md5) ~= "string" then
    return false, "pack must record the md5 of the dump it came from"
  end
  if type(manifest.entries) ~= "table" then
    return false, "pack entries must be a table"
  end
  local count = 0
  for id, entry in pairs(manifest.entries) do
    if type(id) ~= "string" or not id:match(ENTRY_PATTERN) then
      return false, "pack entry id is malformed: " .. tostring(id)
    end
    if type(entry) ~= "table" then
      return false, "pack entry " .. id .. " must be a table"
    end
    local rel = type(entry.file) == "string" and SafePath.safe(entry.file)
    if not rel then
      return false, "pack entry " .. id .. " must name a file inside the pack"
    end
    if not kind.ext[extensionOf(rel)] then
      return false, ("pack entry %s is not a %s file"):format(id, manifest.kind)
    end
    if type(entry.size) ~= "number" or entry.size < 0
        or entry.size % 1 ~= 0 then
      return false, "pack entry " .. id .. " must record its byte size"
    end
    if entry.size > Importers.MAX_ENTRY_BYTES then
      return false, "pack entry " .. id .. " exceeds the 8 MiB entry limit"
    end
    if entry.metadata ~= nil then
      local meta = entry.metadata
      if type(meta) ~= "table" or type(meta.file) ~= "string"
          or not SafePath.safe(meta.file) or extensionOf(meta.file) ~= "lua"
          or type(meta.size) ~= "number" or meta.size < 0 or meta.size % 1 ~= 0
          or meta.size > Importers.MAX_ENTRY_BYTES then
        return false, "pack entry " .. id .. " has invalid metadata"
      end
    end
    count = count + 1
  end
  return true, nil, count
end

local function persistFs(fs)
  if fs then return fs end
  local SaveData = require("src.core.SaveData")
  local base = love and love.filesystem or nil
  return SaveData.persistenceFs(base) or base
end

Importers.fs = persistFs

local function decode(bytes, chunkName)
  local loader = loadstring or load
  local chunk, err = loader(bytes, "@" .. chunkName)
  if not chunk then return nil, err end
  if setfenv then setfenv(chunk, {}) end
  local ok, value = pcall(chunk)
  if not ok then return nil, value end
  return value
end

function Importers.readPack(importerId, packId, fs)
  fs = persistFs(fs)
  local path = Importers.manifestPath(importerId, packId)
  local bytes = fs and fs.read and fs.read(path)
  if type(bytes) ~= "string" then return nil, "pack is not installed" end
  local manifest, err = decode(bytes, path)
  if type(manifest) ~= "table" then
    return nil, "pack manifest could not be read: " .. tostring(err)
  end
  local ok, reason = Importers.validatePack(manifest, importerId, packId)
  if not ok then return nil, reason end
  return manifest
end

function Importers.installed(importerId, fs)
  fs = persistFs(fs)
  local desc = BY_ID[importerId]
  local out = {}
  for _, p in ipairs(desc and desc.packs or {}) do
    local manifest = Importers.readPack(importerId, p.id, fs)
    if manifest then
      local count = 0
      for _ in pairs(manifest.entries) do count = count + 1 end
      out[p.id] = { version = manifest.version, entries = count,
        kind = manifest.kind, source = manifest.source }
    end
  end
  return out
end

function Importers.readMetadata(importerId, packId, entry, fs)
  local meta = entry and entry.metadata
  if not meta then return nil, "entry has no metadata" end
  local path, err = Importers.assetPath(importerId, packId, meta.file)
  if not path then return nil, err end
  fs = persistFs(fs)
  local bytes = fs and fs.read and fs.read(path)
  if type(bytes) ~= "string" then return nil, "entry metadata is missing" end
  if #bytes ~= meta.size or #bytes > Importers.MAX_ENTRY_BYTES then
    return nil, "entry metadata size does not match"
  end
  local value, reason = decode(bytes, path)
  if type(value) ~= "table" then return nil, "invalid entry metadata: " .. tostring(reason) end
  return value
end

function Importers.state(importerId, fs)
  local desc = BY_ID[importerId]
  if not desc then return "unknown" end
  if desc.status == "planned" then return "planned" end
  if not (fs or (love and love.filesystem)) then return "missing" end
  local installed = Importers.installed(importerId, fs)
  local have, total = 0, 0
  for _, p in ipairs(desc.packs) do
    if not p.planned then total = total + 1 end
  end
  for id in pairs(installed) do
    if not (Importers.pack(importerId, id) or {}).planned then
      have = have + 1
    end
  end
  if have == 0 then return "missing" end
  if have < total then return "partial" end
  return "ready"
end

function Importers.resolve(spec, fs)
  if type(spec) ~= "table" then return nil, "asset spec must be a table" end
  local desc = BY_ID[spec.importer]
  if not desc then return nil, "unknown importer: " .. tostring(spec.importer) end
  if not Importers.pack(spec.importer, spec.pack) then
    return nil, ("%s has no pack %s"):format(desc.name, tostring(spec.pack))
  end
  local manifest, err = Importers.readPack(spec.importer, spec.pack, fs)
  if not manifest then
    return nil, ("%s / %s: %s"):format(desc.name, spec.pack, tostring(err))
  end
  if spec.version then
    local ok, reason = Semver.satisfies(manifest.version, spec.version)
    if not ok then
      return nil, ("%s / %s is v%s, needs %s%s"):format(desc.name, spec.pack,
        tostring(manifest.version), spec.version,
        reason and (" (" .. reason .. ")") or "")
    end
  end
  return manifest
end

function Importers.writeAsset(importerId, packId, file, bytes, fs)
  local path, err = Importers.assetPath(importerId, packId, file)
  if not path then return nil, err end
  if type(bytes) ~= "string" then return nil, "pack asset must be bytes" end
  if #bytes > Importers.MAX_ENTRY_BYTES then
    return nil, "pack asset exceeds the 8 MiB entry limit"
  end
  fs = persistFs(fs)
  if not (fs and fs.write) then return nil, "pack writes are unavailable" end
  if fs.createDirectory then
    local parts, walked = {}, Importers.ROOT
    fs.createDirectory(walked)
    walked = walked .. "/" .. importerId
    fs.createDirectory(walked)
    walked = walked .. "/" .. packId
    fs.createDirectory(walked)
    for segment in path:sub(#walked + 2):gmatch("[^/]+") do
      parts[#parts + 1] = segment
    end
    for i = 1, #parts - 1 do
      walked = walked .. "/" .. parts[i]
      fs.createDirectory(walked)
    end
  end
  local ok, writeErr = fs.write(path, bytes)
  if not ok then return nil, writeErr or "could not write pack asset" end
  return #bytes
end

function Importers.writePack(importerId, packId, manifest, fs)
  local ok, reason = Importers.validatePack(manifest, importerId, packId)
  if not ok then return nil, reason end
  fs = persistFs(fs)
  if not (fs and fs.write) then return nil, "pack writes are unavailable" end
  local LuaWriter = require("src.import.LuaWriter")
  local root = Importers.packRoot(importerId, packId)
  if fs.createDirectory then
    fs.createDirectory(Importers.ROOT)
    fs.createDirectory(Importers.ROOT .. "/" .. importerId)
    fs.createDirectory(root)
  end
  return fs.write(Importers.manifestPath(importerId, packId),
    LuaWriter.encode(manifest))
end

return Importers
