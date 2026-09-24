-- SaveConvert -- the runtime-facing entry point the launcher UI calls to
-- turn a vanilla Gen1 (Red/Blue, international) battery save into this
-- project's in-memory save table, and back out to a raw .sav image.
--
-- This is the ONE place the engine, the tests and the CLI
-- (tools/save_convert/convert.lua) share: the GenSave codec, the crosswalk
-- data loading, the merge over new-game defaults, and the version tag all
-- live here so every consumer behaves identically.
--
-- Pure Lua, no love.* dependency at require time: GenSave and the crosswalk
-- tables load through `require`, exactly how src/core/Data.lua pulls the
-- generated modules -- which resolves under both plain luajit (package.path
-- "./?.lua") for the headless CLI/tests and love.filesystem for a fused
-- build, with an OS-path fallback for odd working directories. `love` is only
-- ever referenced inside guarded fallbacks, so running under stock Lua never
-- touches it.
--
-- When a caller names the game a save belongs to, the generated tables come
-- out of that version's ROM cache through CacheFs instead: the launcher does
-- its importing before the cache is mounted onto the un-prefixed paths, so
-- require alone cannot see them there (#420).

local GenSave = require("src.save_convert.GenSave")
local Gen2Save = require("src.save_convert.Gen2Save")
local Gen3Save = require("src.save_convert.Gen3Save")

local SaveConvert = {}

SaveConvert.SAVE_SIZE = GenSave.SAVE_SIZE

local function isGen3(gameVersion)
  if gameVersion == nil then return false end
  local GameVersion = require("src.core.GameVersion")
  return GameVersion.VERSIONS[gameVersion] ~= nil
    and GameVersion.generation(gameVersion) == 3
end
SaveConvert.isGen3 = isGen3

SaveConvert.GEN3_FLASH_MISMATCH = "That is a FireRed/LeafGreen (Game Boy Advance) save, "
  .. "not a save for this game."

-- include/save.h:15
local GEN3_SECTOR_SIGNATURE = 0x08012025
local GEN3_SECTOR_SIZE = 0x1000
local GEN3_SLOT_SECTORS = 14

function SaveConvert.looksLikeGen3Flash(bytes)
  if type(bytes) ~= "string" or #bytes < GEN3_SECTOR_SIZE * GEN3_SLOT_SECTORS then
    return false
  end
  for sector = 0, 2 * GEN3_SLOT_SECTORS - 1 do
    -- include/save.h:69
    local off = sector * GEN3_SECTOR_SIZE + 0xFF8
    if off + 4 > #bytes then break end
    local b1, b2, b3, b4 = bytes:byte(off + 1, off + 4)
    if b1 + b2 * 0x100 + b3 * 0x10000 + b4 * 0x1000000 == GEN3_SECTOR_SIGNATURE then
      return true
    end
  end
  return false
end

-- Is this a real save for THIS GAME? Dispatches on the generation, because
-- the two do not share a rule: Gen 1 stores a complement checksum of its main
-- data block, Gen 2 stores two check values plus a 16-bit sum. Run one over
-- the other's bytes and the answer is always no.
--
-- gameVersion is optional and defaults to Gen 1's rule, which is what every
-- caller meant before Gen 2 had a codec.
function SaveConvert.mainChecksumValid(bytes, gameVersion)
  if isGen3(gameVersion) then return nil end
  if SaveConvert.looksLikeGen3Flash(bytes) then return nil, SaveConvert.GEN3_FLASH_MISMATCH end
  local L = gameVersion and Gen2Save.layoutFor(gameVersion)
  if L then return Gen2Save.checksumValid(bytes, L) end
  return GenSave.mainChecksumValid(bytes)
end

-- ------------------------------------------------------------------
-- Crosswalk data loading (cached).  Mirrors src/core/Data.lua: prefer
-- `require` (works headless via package.path and fused via love's package
-- searcher); fall back to love.filesystem.load, then a plain dofile, for
-- the rare case a host has an unusual cwd or module path.
-- ------------------------------------------------------------------

-- { require-module-path, os-relative-file-path } for each table the codec
-- needs.  pokemon/moves/items/maps come from the shared generated data;
-- charmap/event_flags are the save-convert-specific crosswalks.
local DATA_MODULES = {
  pokemon    = { "data.generated.pokemon",          "data/generated/pokemon.lua" },
  moves      = { "data.generated.moves",            "data/generated/moves.lua" },
  items      = { "data.generated.items",            "data/generated/items.lua" },
  maps       = { "data.generated.maps",             "data/generated/maps.lua" },
  -- tilesets/audio are only read by src/save_convert/MapContext.lua, to
  -- rebuild the current map's engine state on export (#889)
  tilesets   = { "data.generated.tilesets",         "data/generated/tilesets.lua" },
  audio      = { "data.generated.audio",            "data/generated/audio.lua" },
  charmap    = { "src.save_convert.data.charmap",   "src/save_convert/data/charmap.lua" },
  eventFlags = { "src.save_convert.data.event_flags", "src/save_convert/data/event_flags.lua" },
  toggleObjects = { "src.save_convert.data.toggle_objects", "src/save_convert/data/toggle_objects.lua" },
  hiddenItems = { "src.save_convert.data.hidden_items", "src/save_convert/data/hidden_items.lua" },
}

local OPTIONAL_MODULES = { tilesets = true, audio = true }

-- Yellow renumbers wEventFlags bits: pokeyellow's constants/event_constants.asm
-- inserts events pokered does not have (the Jessie & James fights, catch
-- training, the Officer Jenny Squirtle) and shifts the Mt Moon 3 / Silph Co
-- 11F block, so writing a Yellow save through the Red table lands bits on the
-- wrong events and drops every Yellow-only flag.  Kept outside DATA_MODULES so
-- the ensureData loop never loads it as a crosswalk of its own -- it
-- substitutes for `eventFlags` when the caller names Yellow (#838).
local YELLOW_EVENT_FLAGS = {
  "src.save_convert.data.event_flags_yellow",
  "src/save_convert/data/event_flags_yellow.lua",
}
local YELLOW_HIDDEN_ITEMS = {
  "src.save_convert.data.hidden_items_yellow",
  "src/save_convert/data/hidden_items_yellow.lua",
}

local function loadTable(requirePath, filePath)
  local ok, mod = pcall(require, requirePath)
  if ok and type(mod) == "table" then return mod end
  -- fused build with an unexpected module path: read straight off the
  -- mounted filesystem (love is a global here, only ever touched when it
  -- actually exists -- stock Lua never reaches this branch)
  if love and love.filesystem and love.filesystem.getInfo
     and love.filesystem.getInfo(filePath) then
    local chunk = love.filesystem.load(filePath)
    if chunk then
      local m = chunk()
      if type(m) == "table" then return m end
    end
  end
  local chunk = loadfile(filePath)
  if chunk then
    local m = chunk()
    if type(m) == "table" then return m end
  end
  return nil, ("cannot load save-convert data module %q (tried require %q and file %q)")
    :format(requirePath, requirePath, filePath)
end

-- The four generated tables live in one game's ROM cache, and the launcher
-- reaches this code before that cache is on the un-prefixed read path:
-- CacheFs.mountVersion only runs from main.lua's bootGame (after Play), and
-- Blue/Yellow keep their cache under GameVersion.cachePrefix.  So a bare
-- require sees Red's copy at best, and nothing at all in a fused portable
-- build (the game folder is only readable through CacheFs's PhysFS mount) --
-- read the tables out of the cache whenever the caller names the game the
-- save belongs to, and let the require path above cover everything else
-- (#420).
local function loadCacheTable(gameVersion, filePath)
  if not (gameVersion and love and love.filesystem) then return nil end
  if not filePath:match("^data/generated/") then return nil end
  local okc, CacheFs = pcall(require, "src.import.CacheFs")
  local okg, GameVersion = pcall(require, "src.core.GameVersion")
  if not (okc and okg and type(CacheFs) == "table") then return nil end
  local info = GameVersion.VERSIONS[gameVersion]
  if not info then return nil end
  -- CacheFs.prefix is launcher-owned global state (it points at whatever
  -- import last ran), so borrow it for this read and put it back.
  local saved = CacheFs.prefix
  CacheFs.prefix = info.cachePrefix
  local okr, bytes = pcall(CacheFs.read, filePath)
  CacheFs.prefix = saved
  if not (okr and type(bytes) == "string") then return nil end
  local chunk = loadstring(bytes, "@" .. info.cachePrefix .. filePath)
  if not chunk then return nil end
  local okx, mod = pcall(chunk)
  if okx and type(mod) == "table" then return mod end
  return nil
end

-- The generated tables Gen2Save needs to turn cart numbers into the ids the
-- engine is keyed by. Deliberately not ensureData: that one also demands Gen
-- 1's charmap, event flags and hidden items, none of which a Gen 2 cache has
-- or a Gen 2 save uses.
local gen2Data = {}
local function ensureGen2Data(gameVersion)
  local key = gameVersion or "*"
  if gen2Data[key] == nil then
    local out = {}
    for _, name in ipairs({ "pokemon", "moves", "items", "maps" }) do
      out[name] = loadCacheTable(gameVersion, "data/generated/" .. name .. ".lua")
        or (loadTable("data.generated." .. name, "data/generated/" .. name .. ".lua"))
    end
    gen2Data[key] = out
  end
  return gen2Data[key]
end

-- Crosswalk sets keyed by the game whose cache they came from ("*" for the
-- require-resolved set): Yellow's tables are not Red's, so one import must
-- never be handed the previous import's data (#420).
local crosswalks = {}   -- [key] = { pokemon=, moves=, items=, maps=, eventFlags= }
local charmapReady

local function ensureData(gameVersion)
  local key = gameVersion or "*"
  if not crosswalks[key] then
    local data = {}
    for name, spec in pairs(DATA_MODULES) do
      if name ~= "charmap" then
        if name == "eventFlags" and gameVersion == "yellow" then
          spec = YELLOW_EVENT_FLAGS -- Yellow's bit numbering differs (#838)
        elseif name == "hiddenItems" and gameVersion == "yellow" then
          spec = YELLOW_HIDDEN_ITEMS
        end
        local mod = loadCacheTable(gameVersion, spec[2])
        if not mod then
          local e
          mod, e = loadTable(spec[1], spec[2])
          -- tilesets/audio only sharpen the export (MapContext); a cache
          -- without them still imports and exports, just without the
          -- rebuilt map window, so they must not fail the whole load
          if not mod and not OPTIONAL_MODULES[name] then return nil, e end
        end
        data[name] = mod
      end
    end
    -- record which game's tables these are: the codec gates Yellow-only
    -- bytes (wPikachuFriendship) on it, since those offsets are map
    -- scratch in Red/Blue (#763, #838)
    data.gameVersion = gameVersion
    crosswalks[key] = data
  end
  if not charmapReady then
    local cm, err = loadTable(DATA_MODULES.charmap[1], DATA_MODULES.charmap[2])
    if not cm then return nil, err end
    GenSave.setCharmap(cm)
    charmapReady = true
  end
  return crosswalks[key]
end

-- Exposed for the CLI/tests so they can share the exact data set the codec
-- uses (and so a caller can pre-warm the cache).  gameVersion picks whose ROM
-- cache the generated tables come from.  Returns data, err.
function SaveConvert.loadData(gameVersion)
  return ensureData(gameVersion)
end

-- ------------------------------------------------------------------
-- new-game default skeleton the decoded fields merge on top of.  Carried
-- verbatim from tools/save_convert/convert.lua so the CLI and the runtime
-- produce a byte-identical save table for the same input.
-- ------------------------------------------------------------------

local function defaultsSave()
  return {
    meta = { format = "gen1_import", mods = {} },
    defeatedTrainers = {},
    repelSteps = 0,
    modData = {},
    options = {
      textSpeed = 3, animations = true, battleStyle = "shift",
      battleLayout = "og",
      ruleset = "gen1_faithful", musicVol = 7, sfxVol = 7, pikaVol = 7,
      musicFilter = 0,
      speed = 1, colors = "gbc", tilt = 0,
      videoMode = "windowed", mods = {},
    },
  }
end

-- Merge a GenSave.decode() result over the new-game defaults, exactly the
-- way convert.lua did, then stamp the requested version.  Keep the imported
-- SRAM image with the slot: Pokémon Red restores its saved current-map cache
-- before Continue, and an export needs that unmodeled data to remain bootable.
-- Decode warnings are only import diagnostics and do not belong in the slot.
local function mergeDefaults(decoded, version)
  decoded.warnings = nil
  local save = defaultsSave()
  for k, v in pairs(decoded) do save[k] = v end
  save.lastHeal = { map = save.player.map, x = save.player.x, y = save.player.y }
  save.lastOutdoor = save.lastOutdoor or { id = save.player.map }
  if version ~= nil then
    save.meta = save.meta or {}
    save.meta.version = version
  end
  return save
end
SaveConvert.mergeDefaults = mergeDefaults

-- ------------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------------

-- GenSave models Gen 1 SRAM and nothing else: a Gen 2 cart save is a
-- different bank map, party struct and checksum scheme (pokegold
-- ram/sram.asm sOptions/sCheckValue1/sPlayerData/sBox1-sBox14 vs
-- pokered's single sPlayerName..sMainDataCheckSum window), and no Gen 2
-- codec exists yet.  Both directions answer with a plain message the
-- launcher's save card renders as-is, instead of pushing a Gen 2 save
-- Can a cart save for this game cross in or out at all?  Public because the
-- launcher has to ask about the GAME before it measures the BYTES.
--
-- SaveFileIO.importToSlot judges anything that is not exactly SAVE_SIZE with
-- mainChecksumValid, which is pokered's main-data checksum.  A Gen 2 cart is
-- MBC3+TIMER, so a real Gold/Silver/Crystal .sav carries an RTC footer and is
-- 32786 bytes: it misses the size test and is then measured against a rule
-- that was never going to match it.  The player is told "save data checksum
-- invalid" about a save that is perfectly good (#1832).
--
-- Returns true, or false plus the same sentence importSav/exportSav would have
-- answered with, so a caller that asks early and a caller that does not cannot
-- describe the same game two different ways.
-- Does this game use a Gen 2 cart save?  The RTC footer that follows one is
-- expected rather than surprising, which the import path needs to know.
function SaveConvert.isGen2Cart(gameVersion)
  return Gen2Save.layoutFor(gameVersion) ~= nil
end

function SaveConvert.importSupported(gameVersion)
  -- Gen 2 imports through Gen2Save now. Kept as a predicate rather than
  -- deleted: SaveFileIO asks it before it measures the bytes, and export
  -- still answers no.
  return true
end

-- Only the implemented SRAM codecs may be offered as cartridge exports.
-- A Gen 3 save must never fall through to the Gen 1 encoder.
function SaveConvert.exportSupported(gameVersion)
  if gameVersion == nil or gameVersion == "red" or gameVersion == "blue"
      or gameVersion == "yellow" or Gen2Save.layoutFor(gameVersion) or isGen3(gameVersion) then
    return true
  end
  return false, "Cartridge save export is not implemented for this game yet."
end

-- importSav(bytes, version, gameVersion) -> saveTable, err
-- bytes: the raw 32768-byte SRAM string. Validates size and the main-data
-- checksum, decodes through GenSave, and returns a save table fully merged
-- over the new-game defaults and tagged with `version`, ready to hand to
-- SaveSerializer.encode for a slot file. gameVersion ("red"/"blue"/"yellow")
-- names the game the save is being imported for, which is what selects the
-- crosswalk tables; omit it to take whatever `require` resolves. On any
-- failure returns nil + a message (never raises).
function SaveConvert.importSav(bytes, version, gameVersion)
  if type(bytes) ~= "string" then
    return nil, "expected raw save bytes as a string"
  end
  local supported, unsupportedWhy = SaveConvert.importSupported(gameVersion)
  if not supported then return nil, unsupportedWhy end
  if isGen3(gameVersion) then return Gen3Save.importPort(bytes, gameVersion) end
  -- Gen 2 is a different SRAM entirely: different bank map, different party
  -- struct, its own check values. Gen2Save owns it, and it needs no crosswalk
  -- tables because it decodes ids the engine already speaks.
  if Gen2Save.layoutFor(gameVersion) then
    local decoded, gen2Err = Gen2Save.decode(bytes, gameVersion,
                                             ensureGen2Data(gameVersion))
    if not decoded then return nil, gen2Err end
    return Gen2Save.mergeDefaults(decoded, gameVersion)
  end
  if #bytes ~= GenSave.SAVE_SIZE then
    return nil, ("save must be %d bytes, got %d"):format(GenSave.SAVE_SIZE, #bytes)
  end
  local data, derr = ensureData(gameVersion)
  if not data then return nil, derr end

  local ok, decoded = pcall(GenSave.decode, bytes, data)
  if not ok then return nil, "decode failed: " .. tostring(decoded) end

  -- checksum validation: GenSave.decode records a warning rather than
  -- throwing (so it can still read a foreign/corrupt save), but for the
  -- runtime import path a bad main-data checksum means the file is not a
  -- trustworthy save, so reject it.
  for _, w in ipairs(decoded.warnings or {}) do
    if tostring(w):find("checksum") then
      return nil, "save data checksum invalid (" .. tostring(w) .. ")"
    end
  end

  return mergeDefaults(decoded, version)
end

local GBA_ROOT = "data/generated/gba/"

local function gen3CacheBytes(gameVersion, rel)
  local path = GBA_ROOT .. rel
  if gameVersion and love and love.filesystem then
    local okc, CacheFs = pcall(require, "src.import.CacheFs")
    local info = require("src.core.GameVersion").VERSIONS[gameVersion]
    if okc and type(CacheFs) == "table" and info then
      local saved = CacheFs.prefix
      CacheFs.prefix = info.cachePrefix
      local okr, bytes = pcall(CacheFs.read, path)
      CacheFs.prefix = saved
      if okr and type(bytes) == "string" then return bytes end
    end
  end
  local okd, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = okd and Dataset.cache and Dataset.cache()
  local bytes = cache and cache:read(path)
  return type(bytes) == "string" and bytes or nil
end

local function gen3CacheTable(gameVersion, rel)
  local bytes = gen3CacheBytes(gameVersion, rel)
  local chunk = bytes and loadstring(bytes, "@" .. rel)
  if not chunk then return nil end
  local ok, t = pcall(setfenv(chunk, {}))
  return ok and type(t) == "table" and t or nil
end

local function gen3ExportOpts(gameVersion, cartImage)
  local L3 = require("src.save_convert.Gen3Layout")
  local national = gen3CacheTable(gameVersion, "pokemon/national.lua")
  local names = gen3CacheTable(gameVersion, "pokemon/names.lua")
  local fly = gen3CacheTable(gameVersion, "region_map/fly_destinations.lua")
  local heal = gen3CacheTable(gameVersion, "region_map/heal_locations.lua")
  local okI, ItemsData = pcall(require, "src.core.game3.items_data")
  local opts = {
    template = cartImage,
    version = gameVersion,
    metGame = gameVersion == "leafgreen" and L3.VERSION_LEAF_GREEN or L3.VERSION_FIRE_RED,
    itemId = function(id)
      return tonumber(id) or (okI and ItemsData.toNumericId(id)) or nil
    end,
    mapLayoutId = function(group, num)
      local raw = gen3CacheBytes(gameVersion, ("map_tree/maps/%d_%d/header.json"):format(group, num))
      return raw and tonumber(raw:match('"layoutId"%s*:%s*(%d+)')) or nil
    end,
  }
  if national and type(national.toNational) == "table" then
    opts.toNational = function(species) return national.toNational[species] end
    opts.speciesFromNational = function(nat) return national.toSpecies and national.toSpecies[nat] end
  end
  if names then
    opts.speciesName = function(species) return names[species] end
  end
  opts.registeredTextDefaults = function()
    local okC, Chat = pcall(require, "src.core.game3.link.chat")
    local text = okC and gen3CacheTable(gameVersion, "scripts/text.lua")
    if not text then return nil end
    local out = {}
    for i, key in ipairs(Chat.REGISTERED_DEFAULTS) do
      if type(text[key]) ~= "table" then return nil end
      local parts = {}
      for _, seg in ipairs(text[key]) do
        if seg.t == "text" then parts[#parts + 1] = seg.s elseif seg.t == "tag" then parts[#parts + 1] = seg.tag end
      end
      out[i] = table.concat(parts)
    end
    return out
  end
  local whiteout = heal and (heal.whiteout or heal.heal_locations)
  local dests = fly and fly.fly_destinations
  if type(whiteout) == "table" and type(dests) == "table" then
    opts.healWarp = function(respawnMap)
      local id = L3.HEAL_LOCATION_PALLET_TOWN
      for i, loc in pairs(whiteout) do
        if type(loc) == "table" and loc.map == respawnMap then id = i end
      end
      for _, dest in pairs(dests) do
        if type(dest) == "table" and dest.healLocation == id then
          return Gen3Save.cartWarp({ map = dest.map, warpId = -1, x = dest.x, y = dest.y })
        end
      end
      return nil
    end
  end
  return opts
end

-- exportSav(saveTable, gameVersion, cartImage) -> bytes, err
-- Encodes a save table back to a raw 32768-byte SRAM image. Template-aware:
-- if the table still carries the stashed import template (saveTable.rawImport)
-- GenSave reproduces every unmodeled region from it; otherwise those regions
-- are zero-filled. gameVersion selects the crosswalk tables exactly as in
-- importSav. On failure returns nil + a message (never raises).
function SaveConvert.exportSav(saveTable, gameVersion, cartImage)
  if type(saveTable) ~= "table" then
    return nil, "expected a save table"
  end
  local supported, unsupportedWhy = SaveConvert.exportSupported(gameVersion)
  if not supported then return nil, unsupportedWhy end
  if isGen3(gameVersion) then
    local ok, bytes, err = pcall(Gen3Save.exportPort, saveTable, gen3ExportOpts(gameVersion, cartImage))
    if not ok then return nil, "encode failed: " .. tostring(bytes) end
    return bytes, err
  end
  -- Gen 2 has its own SRAM and its own codec, and needs no Gen 1 crosswalks.
  if Gen2Save.layoutFor(gameVersion) then
    return Gen2Save.encode(saveTable, gameVersion, cartImage,
                           ensureGen2Data(gameVersion))
  end
  local data, derr = ensureData(gameVersion)
  if not data then return nil, derr end
  local ok, bytes = pcall(GenSave.encode, saveTable, data, nil)
  if not ok then return nil, "encode failed: " .. tostring(bytes) end
  return bytes
end

return SaveConvert
