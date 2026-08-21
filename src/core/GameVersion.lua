-- Which game this process is running: Red (the historical default), Blue,
-- Yellow, Gold, or Silver.  One source of truth for everything that differs by
-- version -- the accepted ROM hash, the import manifest, where the
-- extracted cache lives, and the save-file suffix -- so the importer,
-- cache mount, SaveData, title screen and palette all agree.
--
-- Red keeps the un-suffixed save paths it always used (save.lua) so existing
-- saves are untouched, but its extracted cache lives under red/ like Blue,
-- Yellow, and Gold (issue #899); a legacy root cache is moved into red/ once
-- by CacheFs.migrateLegacyRedCache.  All supported versions can be imported
-- and selected side by side.  Gold and Silver are Gen 2 (see
-- docs/gold-phase1.md).
--
-- Zero requires, so it loads during love.conf and under plain Lua for tools
-- and tests.  The active version is a process-global set once at boot from
-- the launcher's column choice (main.lua); it defaults to Red.

local GameVersion = {}

GameVersion.VERSIONS = {
  red = {
    id = "red",
    label = "Red",
    displayName = "Pokemon Red",
    launcherName = "Red",       -- game-panel header in the launcher
    sha1 = "ea9bcae617fdf159b045185467ae58b2e4a48b9a",
    manifest = "tools/rom_manifest.json",
    cachePrefix = "red/",   -- red/data/generated, red/assets/generated (#899)
    saveSuffix = "",        -- save.lua / save.lua.bak / save.lua.tmp
  },
  blue = {
    id = "blue",
    label = "Blue",
    displayName = "Pokemon Blue",
    launcherName = "Blue",
    sha1 = "d7037c83e1ae5b39bde3c30787637ba1d4c48ce2",
    manifest = "tools/rom_manifest_blue.json",
    cachePrefix = "blue/",  -- blue/data/generated, blue/assets/generated
    saveSuffix = "_blue",   -- save_blue.lua / .bak / .tmp
  },
  yellow = {
    id = "yellow",
    label = "Yellow",
    displayName = "Pokemon Yellow",
    launcherName = "Yellow",
    sha1 = "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1",
    manifest = "tools/rom_manifest_yellow.json",
    cachePrefix = "yellow/",  -- yellow/data/generated, yellow/assets/generated
    saveSuffix = "_yellow",   -- save_yellow.lua / .bak / .tmp
  },
  -- Gen 2, Phase 1 (docs/gold-phase1.md): a 2 MiB cart, twice the size of
  -- the Gen 1 ROMs above, imported through RomExtractorGen2 instead of
  -- RomExtractor.
  gold = {
    id = "gold",
    label = "Gold",
    displayName = "Pokemon Gold",
    -- Still Gen 2 Phase work; the launcher panel / Play button say Beta so
    -- players do not treat it like the shipped Gen 1 columns.
    launcherName = "Gold (Beta)",
    sha1 = "d8b8a3600a465308c9953dfa04f0081c05bdcb94",
    manifest = "tools/rom_manifest_gold.json",
    cachePrefix = "gold/",    -- gold/data/generated, gold/assets/generated
    saveSuffix = "_gold",     -- save_gold.lua / .bak / .tmp
    -- Absent reads as 1 (GameVersion.generation)
    generation = 2,
  },
  -- Gold's engine with edition-selected data; the manifest is derived from
  -- Gold's by tools/make_silver_manifest.py.
  silver = {
    id = "silver",
    label = "Silver",
    displayName = "Pokemon Silver",
    launcherName = "Silver (Beta)",
    sha1 = "49b163f7e57702bc939d642a18f591de55d92dae",
    manifest = "tools/rom_manifest_silver.json",
    cachePrefix = "silver/",  -- silver/data/generated, silver/assets/generated
    saveSuffix = "_silver",   -- save_silver.lua / .bak / .tmp
    generation = 2,
  },
}

-- Launcher column order.
GameVersion.ORDER = { "red", "blue", "yellow", "gold", "silver" }

GameVersion.current = "red"

function GameVersion.set(id)
  GameVersion.current = GameVersion.VERSIONS[id] and id or "red"
  return GameVersion.current
end

function GameVersion.get()
  return GameVersion.current
end

function GameVersion.isBlue()
  return GameVersion.current == "blue"
end

function GameVersion.isYellow()
  return GameVersion.current == "yellow"
end

function GameVersion.isGold()
  return GameVersion.current == "gold"
end

-- 1 or 2.  The mod API is shared across both (same hook names, same registry
-- names), so the pieces that must branch -- the manifest gen2compat gate, the
-- registry target routing, the mod.world arm -- ask this rather than each
-- spelling out its own isGold() test.  A third generation adds a `generation`
-- to its VERSIONS row and nothing else changes shape.
function GameVersion.generation(id)
  return GameVersion.info(id).generation or 1
end

-- Metadata for a version id, defaulting to the active one.
function GameVersion.info(id)
  return GameVersion.VERSIONS[id or GameVersion.current]
end

function GameVersion.saveSuffix(id)
  return GameVersion.info(id).saveSuffix
end

function GameVersion.cachePrefix(id)
  return GameVersion.info(id).cachePrefix
end

-- The version a ROM belongs to, by its SHA-1, or nil for an unknown ROM.
function GameVersion.forSha1(sha1)
  for id, info in pairs(GameVersion.VERSIONS) do
    if info.sha1 == sha1 then return id end
  end
  return nil
end

return GameVersion
