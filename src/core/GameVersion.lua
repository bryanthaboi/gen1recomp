-- Which game this process is running: Red, Blue, Yellow, or Gold.
-- Red's Spanish ROM is a regional variant of the same visible Red game.
-- One source of truth for version-specific ROM hashes, manifests, caches and saves.

local GameVersion = {}

GameVersion.VERSIONS = {
  red = {
    id = "red", label = "Red", displayName = "Pokemon Red", launcherName = "Red",
    sha1 = "ea9bcae617fdf159b045185467ae58b2e4a48b9a", manifest = "tools/rom_manifest.json",
    cachePrefix = "red/", saveSuffix = "",
  },
  blue = {
    id = "blue", label = "Blue", displayName = "Pokemon Blue", launcherName = "Blue",
    sha1 = "d7037c83e1ae5b39bde3c30787637ba1d4c48ce2", manifest = "tools/rom_manifest_blue.json",
    cachePrefix = "blue/", saveSuffix = "_blue",
  },
  yellow = {
    id = "yellow", label = "Yellow", displayName = "Pokemon Yellow", launcherName = "Yellow",
    sha1 = "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1", manifest = "tools/rom_manifest_yellow.json",
    cachePrefix = "yellow/", saveSuffix = "_yellow",
  },
  -- Internal ROM definition only. Spanish Red belongs to the visible Red
  -- launcher tab, uses Red's cache/save namespace, and is selected by SHA-1.
  rojo = {
    id = "rojo", label = "Rojo ES", displayName = "Pokemon Rojo (España)", launcherName = "Red",
    sha1 = "fc17c5b904d551b1b908054ccd1c493f755f832a", manifest = "tools/rom_manifest_red_es.json",
    cachePrefix = "red/", saveSuffix = "",
    launcherGroup = "red", hidden = true,
  },
  -- Internal ROM definition only. Spanish Blue belongs to the visible Blue
  -- launcher tab and shares Blue's cache/save namespace.
  azul = {
    id = "azul", label = "Azul ES", displayName = "Pokemon Azul (España)", launcherName = "Blue",
    sha1 = "7715e7b133e8634df48918b9138374110212a108", manifest = "tools/rom_manifest_blue_es.json",
    cachePrefix = "blue/", saveSuffix = "_blue",
    launcherGroup = "blue", hidden = true,
  },
  gold = {
    id = "gold", label = "Gold", displayName = "Pokemon Gold", launcherName = "Gold (Beta)",
    sha1 = "d8b8a3600a465308c9953dfa04f0081c05bdcb94", manifest = "tools/rom_manifest_gold.json",
    cachePrefix = "gold/", saveSuffix = "_gold", generation = 2,
  },
}

-- Only visible launcher games belong here. Spanish Red is deliberately absent:
-- it is a ROM variant selected inside the Red game slot.
GameVersion.ORDER = { "red", "blue", "yellow", "gold" }
GameVersion.current = "red"
GameVersion._redSha1 = nil
GameVersion._blueSha1 = nil

local SPANISH_RED_SHA1 = GameVersion.VERSIONS.rojo.sha1
local ENGLISH_RED_SHA1 = GameVersion.VERSIONS.red.sha1
local SPANISH_BLUE_SHA1 = GameVersion.VERSIONS.azul.sha1
local ENGLISH_BLUE_SHA1 = GameVersion.VERSIONS.blue.sha1

local function installSpanishDexPatch()
  if GameVersion._dexPatchInstalled then return end
  local ok, extractor = pcall(require, "src.import.RomExtractor")
  if not ok or type(extractor) ~= "table" or type(extractor.dexEntry) ~= "function" then return end
  local originalDexEntry = extractor.dexEntry
  extractor.dexEntry = function(self, index, species)
    local okEntry, result = pcall(originalDexEntry, self, index, species)
    if okEntry then return result end
    local message = tostring(result)
    local expected = "dex entry " .. index .. " has no TX_FAR command"
    if not message:find(expected, 1, true) then error(result) end
    local labels = self.manifest.dexEntryLabels or {}
    local textLabel = labels[species]
    if not textLabel then error(result) end
    local pointerTable = self:symbol("PokedexEntryPointers")
    local address = self.rom:word(pointerTable.bank, pointerTable.address + (index - 1) * 2)
    local kind, consumed = self.rom:readString(pointerTable.bank, address, self.manifest.charmap, 0x50, 32)
    address = address + consumed
    local heightFt = self.rom:byte(pointerTable.bank, address)
    local heightIn = self.rom:byte(pointerTable.bank, address + 1)
    local weight = self.rom:word(pointerTable.bank, address + 2)
    return { kind = kind, heightFt = heightFt, heightIn = heightIn, weight = weight, text = textLabel }
  end

  -- Spanish Red/Blue keep the original Gen-1 title-screen layout, but their
  -- Version_GFX bytes contain the localized ribbon. Keep it ROM-backed rather
  -- than shipping a hand-authored replacement. Version_GFX is at bank $1A:$402F
  -- and occupies 10 tiles (80 bytes), exactly like the English ribbon.
  local originalExtractField = extractor.extractField
  if type(originalExtractField) == "function" then
    extractor.extractField = function(self, ...)
      local result = originalExtractField(self, ...)
      local ImageWriter = require("src.import.ImageWriter")
      local raw = self.rom:bytes(0x1A, 0x402F, 80)
      local image = ImageWriter.decode1bpp(raw, 80, 8)
      self:save(image, "title/red_version.png")
      return result
    end
  end

  GameVersion._dexPatchInstalled = true
end

-- Detect which Red ROM variant owns the persisted red/ cache. The completion
-- marker contains the SHA-1 that was actually imported, so the visible Red
-- tab survives a restart without requiring the Spanish ROM to be imported again.
local function detectRedVariant()
  if GameVersion._redSha1 then return GameVersion._redSha1 end
  local marker
  if love and love.filesystem then
    marker = love.filesystem.read("red/rom-cache.complete")
    if type(marker) ~= "string" then
      marker = love.filesystem.read("rom-cache.complete")
    end
  end
  local sha = type(marker) == "string"
    and marker:match("^rom%-cache%-v%d+:(%x+)$")
  if sha == SPANISH_RED_SHA1 or sha == ENGLISH_RED_SHA1 then
    GameVersion._redSha1 = sha
  end
  return GameVersion._redSha1
end

local function detectBlueVariant()
  if GameVersion._blueSha1 then return GameVersion._blueSha1 end
  local marker
  if love and love.filesystem then
    marker = love.filesystem.read("blue/rom-cache.complete")
    if type(marker) ~= "string" then
      marker = love.filesystem.read("rom-cache.complete")
    end
  end
  local sha = type(marker) == "string"
    and marker:match("^rom%-cache%-v%d+:(%x+)$")
  if sha == SPANISH_BLUE_SHA1 or sha == ENGLISH_BLUE_SHA1 then
    GameVersion._blueSha1 = sha
  end
  return GameVersion._blueSha1
end

local function redInfo()
  if detectRedVariant() == SPANISH_RED_SHA1 then
    return GameVersion.VERSIONS.rojo
  end
  return GameVersion.VERSIONS.red
end

local function blueInfo()
  if detectBlueVariant() == SPANISH_BLUE_SHA1 then
    return GameVersion.VERSIONS.azul
  end
  return GameVersion.VERSIONS.blue
end

function GameVersion.set(id)
  -- The launcher only ever selects the visible Red game. The ROM variant is
  -- restored from red/rom-cache.complete rather than from a separate tab.
  GameVersion.current = GameVersion.VERSIONS[id] and id or "red"
  if GameVersion.current == "rojo" then
    GameVersion.current = "red"
    GameVersion._redSha1 = SPANISH_RED_SHA1
  elseif GameVersion.current == "azul" then
    GameVersion.current = "blue"
    GameVersion._blueSha1 = SPANISH_BLUE_SHA1
  end
  if GameVersion.isSpanish() then
    installSpanishDexPatch()
  end
  return GameVersion.current
end

function GameVersion.get() return GameVersion.current end
function GameVersion.isBlue() return GameVersion.current == "blue" end
function GameVersion.isYellow() return GameVersion.current == "yellow" end
function GameVersion.isRojo()
  return GameVersion.current == "red" and detectRedVariant() == SPANISH_RED_SHA1
end
function GameVersion.isSpanishRed() return GameVersion.isRojo() end
function GameVersion.isAzul()
  return GameVersion.current == "blue" and detectBlueVariant() == SPANISH_BLUE_SHA1
end
function GameVersion.isSpanishBlue() return GameVersion.isAzul() end
function GameVersion.isSpanish() return GameVersion.isRojo() or GameVersion.isAzul() end
function GameVersion.isGold() return GameVersion.current == "gold" end
function GameVersion.generation(id) return GameVersion.info(id).generation or 1 end

function GameVersion.info(id)
  id = id or GameVersion.current
  if id == "red" then return redInfo() end
  if id == "blue" then return blueInfo() end
  return GameVersion.VERSIONS[id]
end

function GameVersion.saveSuffix(id) return GameVersion.info(id).saveSuffix end
function GameVersion.cachePrefix(id) return GameVersion.info(id).cachePrefix end
function GameVersion.variant(id)
  id = id or GameVersion.current
  if id == "red" and detectRedVariant() == SPANISH_RED_SHA1 then return "es" end
  if id == "red" then return "en" end
  if id == "blue" and detectBlueVariant() == SPANISH_BLUE_SHA1 then return "es" end
  if id == "blue" then return "en" end
  return nil
end

-- Map the ROM's SHA-1 to the visible launcher game. Spanish and English Red
-- therefore share the same ready-state, tab, cache namespace and save slot,
-- while retaining their own manifest internally.
function GameVersion.forSha1(sha1)
  if sha1 == SPANISH_RED_SHA1 then
    GameVersion._redSha1 = SPANISH_RED_SHA1
    installSpanishDexPatch()
    return "red"
  end
  if sha1 == ENGLISH_RED_SHA1 then
    GameVersion._redSha1 = ENGLISH_RED_SHA1
    return "red"
  end
  if sha1 == SPANISH_BLUE_SHA1 then
    GameVersion._blueSha1 = SPANISH_BLUE_SHA1
    installSpanishDexPatch()
    return "blue"
  end
  if sha1 == ENGLISH_BLUE_SHA1 then
    GameVersion._blueSha1 = ENGLISH_BLUE_SHA1
    return "blue"
  end
  for id, info in pairs(GameVersion.VERSIONS) do
    if not info.hidden and info.sha1 == sha1 then
      return id
    end
  end
  return nil
end

return GameVersion
