-- Which Gen-1 game this process is running: Red (the historical default),
-- Blue, or Yellow.  One source of truth for everything that differs by
-- version -- the accepted ROM hash, the import manifest, where the
-- extracted cache lives, and the save-file suffix -- so the importer,
-- cache mount, SaveData, title screen and palette all agree.
--
-- Red keeps every un-suffixed path it always used (save.lua, the root cache),
-- so existing installs are untouched; Blue is namespaced under blue/ and
-- _blue, Yellow under yellow/ and _yellow, so all three can be imported and
-- played side by side.
--
-- Zero requires, so it loads during love.conf and under plain Lua for tools
-- and tests.  The active version is a process-global set once at boot from
-- the launcher's column choice (main.lua); it defaults to Red.

local GameVersion = {}

-- Each version accepts one ROM per supported release: the US dump (the
-- historical default -- sha1/manifest at the top level keep pointing at it)
-- plus any localized EUR rebuilds whose manifests tools/make_es_manifest.py
-- derives.  All dumps of a version extract into the same cache and share the
-- same saves; the last imported dump decides the game's language.
GameVersion.VERSIONS = {
  red = {
    id = "red",
    label = "Red",
    displayName = "Pokemon Red",
    launcherName = "Red",       -- game-panel header in the launcher
    sha1 = "ea9bcae617fdf159b045185467ae58b2e4a48b9a",
    manifest = "tools/rom_manifest.json",
    roms = {
      { locale = "us", sha1 = "ea9bcae617fdf159b045185467ae58b2e4a48b9a",
        manifest = "tools/rom_manifest.json" },
      { locale = "es", sha1 = "fc17c5b904d551b1b908054ccd1c493f755f832a",
        manifest = "tools/rom_manifest_red_es.json" },
    },
    cachePrefix = "",       -- Red owns the cache root (backwards compatible)
    saveSuffix = "",        -- save.lua / save.lua.bak / save.lua.tmp
  },
  blue = {
    id = "blue",
    label = "Blue",
    displayName = "Pokemon Blue",
    launcherName = "Blue",
    sha1 = "d7037c83e1ae5b39bde3c30787637ba1d4c48ce2",
    manifest = "tools/rom_manifest_blue.json",
    roms = {
      { locale = "us", sha1 = "d7037c83e1ae5b39bde3c30787637ba1d4c48ce2",
        manifest = "tools/rom_manifest_blue.json" },
      { locale = "es", sha1 = "7715e7b133e8634df48918b9138374110212a108",
        manifest = "tools/rom_manifest_blue_es.json" },
    },
    cachePrefix = "blue/",  -- blue/data/generated, blue/assets/generated
    saveSuffix = "_blue",   -- save_blue.lua / .bak / .tmp
  },
  yellow = {
    id = "yellow",
    label = "Yellow",
    displayName = "Pokemon Yellow",
    launcherName = "Yellow (alpha)",
    sha1 = "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1",
    manifest = "tools/rom_manifest_yellow.json",
    roms = {
      { locale = "us", sha1 = "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1",
        manifest = "tools/rom_manifest_yellow.json" },
    },
    cachePrefix = "yellow/",  -- yellow/data/generated, yellow/assets/generated
    saveSuffix = "_yellow",   -- save_yellow.lua / .bak / .tmp
  },
}

-- Recognized clean dumps we cannot import yet, so the launcher can say why
-- instead of implying the file is a bad dump.  Spanish EUR Red/Blue derive
-- their manifests from the shift-matching einstein95/pokered-es
-- disassembly; no such disassembly exists for the Spanish Yellow.
GameVersion.UNSUPPORTED = {
  ["1dc242039218fba50928d1afb66b70565b6b9daf"] =
    "Pokemon Amarillo (Spanish EUR Yellow)",
}

-- Launcher column order.
GameVersion.ORDER = { "red", "blue", "yellow" }

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
-- Second return is the matched rom entry ({ locale, sha1, manifest }), so
-- the importer can extract with the dump's own manifest.
function GameVersion.forSha1(sha1)
  for id, info in pairs(GameVersion.VERSIONS) do
    for _, rom in ipairs(info.roms) do
      if rom.sha1 == sha1 then return id, rom end
    end
  end
  return nil
end

return GameVersion
