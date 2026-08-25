-- Which game this process is running: Red (the historical default), Blue,
-- Yellow, Gold, Silver, or Crystal.  One source of truth for everything that
-- differs by version -- the accepted ROM hash, the import manifest, where the
-- extracted cache lives, and the save-file suffix -- so the importer,
-- cache mount, SaveData, title screen and palette all agree.
--
-- Red keeps the un-suffixed save paths it always used (save.lua) so existing
-- saves are untouched, but its extracted cache lives under red/ like Blue,
-- Yellow, and Gold (issue #899); a legacy root cache is moved into red/ once
-- by CacheFs.migrateLegacyRedCache.  All supported versions can be imported
-- and selected side by side.  Gold, Silver and Crystal are Gen 2 (see
-- docs/gold-phase1.md); `generation` splits Gen 1 from Gen 2 and `engine`
-- splits Gold/Silver from Crystal within Gen 2.
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
    -- Absent reads as "gen1" (GameVersion.engine)
    engine = "gen1",
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
    engine = "gen1",
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
    engine = "gen1",
  },
  -- Gen 2, Phase 1 (docs/gold-phase1.md): a 2 MiB cart, twice the size of
  -- the Gen 1 ROMs above, imported through RomExtractorGen2 instead of
  -- RomExtractor.
  gold = {
    id = "gold",
    label = "Gold",
    displayName = "Pokemon Gold",
    launcherName = "Gold",
    sha1 = "d8b8a3600a465308c9953dfa04f0081c05bdcb94",
    manifest = "tools/rom_manifest_gold.json",
    cachePrefix = "gold/",    -- gold/data/generated, gold/assets/generated
    saveSuffix = "_gold",     -- save_gold.lua / .bak / .tmp
    -- Absent reads as 1 (GameVersion.generation)
    generation = 2,
    engine = "gs",
  },
  -- Gold's engine with edition-selected data; the manifest is derived from
  -- Gold's by tools/make_silver_manifest.py.
  silver = {
    id = "silver",
    label = "Silver",
    displayName = "Pokemon Silver",
    launcherName = "Silver",
    sha1 = "49b163f7e57702bc939d642a18f591de55d92dae",
    manifest = "tools/rom_manifest_silver.json",
    cachePrefix = "silver/",  -- silver/data/generated, silver/assets/generated
    saveSuffix = "_silver",   -- save_silver.lua / .bak / .tmp
    generation = 2,
    engine = "gs",
  },
  crystal = {
    id = "crystal",
    label = "Crystal",
    displayName = "Pokemon Crystal",
    -- Still Gen 2 Phase work; the launcher panel / Play button say Beta so
    -- players do not treat it like the shipped Gold and Silver columns.
    launcherName = "Crystal (Beta)",
    sha1 = "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133",
    manifest = "tools/rom_manifest_crystal.json",
    cachePrefix = "crystal/",  -- crystal/data/generated, crystal/assets/generated
    saveSuffix = "_crystal",   -- save_crystal.lua / .bak / .tmp
    generation = 2,
    engine = "crystal",
    revisions = {
      { sha1 = "f4cd194bdee0d04ca4eac29e09b8e4e9d818c133", label = "1.0" },
      { sha1 = "f2f52230b536214ef7c9924f483392993e226cfb", label = "1.1" },
    },
    fixes = {
      -- pokegold/docs/bugs_and_glitches.md:61
      luckyNumberBoxes = true,
      -- pokegold/docs/bugs_and_glitches.md:88
      surfOntoNpc = true,
      -- pokecrystal/engine/battle/effect_commands.asm:2614
      reflectOverflow = true,
    },
  },
}

local NO_FIXES = {}

-- Launcher column order.  Append only (src/mods/ModProfile.lua encodes by index).
GameVersion.ORDER = { "red", "blue", "yellow", "gold", "silver", "crystal" }

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

-- "gen1" | "gs" | "crystal": lineage within a generation.
function GameVersion.engine(id)
  return GameVersion.info(id).engine or "gen1"
end

-- Cart bugs a version FIXED, by fix name; an absent row reads {} and stays bugged.
function GameVersion.fixes(id)
  local info = GameVersion.info(id)
  return (info and info.fixes) or NO_FIXES
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

function GameVersion.revisions(id)
  local info = GameVersion.info(id)
  return info.revisions or { { sha1 = info.sha1 } }
end

function GameVersion.acceptsSha1(id, sha1)
  for _, revision in ipairs(GameVersion.revisions(id)) do
    if revision.sha1 == sha1 then return true end
  end
  return false
end

function GameVersion.revisionLabel(id, sha1)
  for _, revision in ipairs(GameVersion.revisions(id)) do
    if revision.sha1 == sha1 then return revision.label end
  end
  return nil
end

-- The version a ROM belongs to, by its SHA-1, or nil for an unknown ROM.
function GameVersion.forSha1(sha1)
  for id in pairs(GameVersion.VERSIONS) do
    if GameVersion.acceptsSha1(id, sha1) then return id end
  end
  return nil
end

return GameVersion
