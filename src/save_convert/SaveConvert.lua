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

local SaveConvert = {}

SaveConvert.SAVE_SIZE = GenSave.SAVE_SIZE

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
  charmap    = { "src.save_convert.data.charmap",   "src/save_convert/data/charmap.lua" },
  eventFlags = { "src.save_convert.data.event_flags", "src/save_convert/data/event_flags.lua" },
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
        local mod = loadCacheTable(gameVersion, spec[2])
        if not mod then
          local e
          mod, e = loadTable(spec[1], spec[2])
          if not mod then return nil, e end
        end
        data[name] = mod
      end
    end
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
      speed = 1, colors = "gbc", tilt = 0, gbcfx = 0,
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

-- exportSav(saveTable, gameVersion) -> bytes, err
-- Encodes a save table back to a raw 32768-byte SRAM image. Template-aware:
-- if the table still carries the stashed import template (saveTable.rawImport)
-- GenSave reproduces every unmodeled region from it; otherwise those regions
-- are zero-filled. gameVersion selects the crosswalk tables exactly as in
-- importSav. On failure returns nil + a message (never raises).
function SaveConvert.exportSav(saveTable, gameVersion)
  if type(saveTable) ~= "table" then
    return nil, "expected a save table"
  end
  local data, derr = ensureData(gameVersion)
  if not data then return nil, derr end
  local ok, bytes = pcall(GenSave.encode, saveTable, data, nil)
  if not ok then return nil, "encode failed: " .. tostring(bytes) end
  return bytes
end

return SaveConvert
