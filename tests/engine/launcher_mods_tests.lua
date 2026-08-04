-- Love-free coverage for the pure halves of src/mods/LauncherMods.lua: the
-- status derivation (deriveList) over a synthetic manifest list + options
-- table, and the archive-root location logic (locateRoot).  The discovery and
-- installZip paths need love.filesystem and are exercised by the launcher; the
-- decision logic under them lives here so a bad range/conflict/root call fails
-- one line instead of the app.
--   luajit tests/engine/launcher_mods_tests.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Manifest = require("src.mods.Manifest")
local Version = require("src.core.Version")
local LauncherMods = require("src.mods.LauncherMods")

-- validated manifests are the exact shape deriveList/resolveToggle read
local function mf(raw)
  return Manifest.validate(raw)
end

-- index a deriveList result by mod id for assertions
local function byId(list)
  local m = {}
  for _, row in ipairs(list) do m[row.id] = row end
  return m
end

-- ------- badge derivation: category, then profile, then MOD (uppercased)

do
  local list = LauncherMods.deriveList({
    mf({ id = "cat", name = "Cat Mod", version = "1.0.0", entry = "m.lua",
         category = "gameplay" }),
    mf({ id = "prof", name = "Prof Mod", version = "1.0.0", entry = "m.lua",
         profile = "overhaul" }),
    mf({ id = "plain", name = "Plain", version = "1.0.0", entry = "m.lua" }),
  }, { mods = {} })
  local m = byId(list)
  eq(m.cat.badge, "GAMEPLAY", "badge uses the manifest category, uppercased")
  eq(m.prof.badge, "OVERHAUL", "badge falls back to the profile when no category")
  -- no category field, so the fallback reaches the profile default ("content")
  eq(m.plain.badge, "CONTENT", "bare manifest badge falls back to the profile")
  eq(#list, 3, "every discovered manifest yields one row")
  check(m.cat.id < m.plain.id and m.plain.id < m.prof.id,
    "rows come back sorted by id (cat < plain < prof)")
end

-- ------- enabled defaults to true; a false entry disables

do
  local manifests = {
    mf({ id = "aaa", name = "A", version = "1.0.0", entry = "m.lua" }),
    mf({ id = "bbb", name = "B", version = "1.0.0", entry = "m.lua" }),
  }
  local m = byId(LauncherMods.deriveList(manifests, { mods = { bbb = false } }))
  check(m.aaa.enabled, "a mod with no options entry defaults to enabled")
  check(not m.bbb.enabled, "an explicit false disables the mod")
  eq(m.aaa.status, "ok", "a healthy enabled mod is ok")
  eq(m.aaa.statusDetail, "Ready", "ok detail reads Ready")
end

-- ------- experimental defaults to disabled; github surfaces on the row

do
  local manifests = {
    mf({ id = "lab", name = "Lab", version = "1.2.0", entry = "m.lua",
         experimental = true, github = "acme/lab" }),
    mf({ id = "lab_on", name = "Lab On", version = "1.0.0", entry = "m.lua",
         experimental = true }),
  }
  local m = byId(LauncherMods.deriveList(manifests, {
    mods = { lab_on = true },
  }))
  check(not m.lab.enabled, "experimental with no options entry stays off")
  check(m.lab_on.enabled, "experimental can still be explicitly enabled")
  eq(m.lab.badge, "EXPERIMENTAL", "experimental badge overrides category")
  eq(m.lab.github, "acme/lab", "github is exposed on the panel row")
  check(m.lab.experimental, "experimental flag is exposed on the panel row")
end

-- ------- conflict: only when this mod is enabled and the other is too

do
  local manifests = {
    mf({ id = "alpha", name = "Alpha", version = "1.0.0", entry = "m.lua",
         conflicts = { "beta" } }),
    mf({ id = "beta", name = "Beta", version = "1.0.0", entry = "m.lua" }),
  }
  -- both enabled: the declaring side (and, symmetrically, the other) conflict
  local both = byId(LauncherMods.deriveList(manifests, { mods = {} }))
  eq(both.alpha.status, "conflict", "enabled mod conflicting with an enabled mod")
  check(both.alpha.statusDetail:find("Beta", 1, true) ~= nil,
    "conflict detail names the other mod")
  eq(both.beta.status, "conflict",
    "resolveToggle conflict is bidirectional: the target is flagged too")

  -- disable beta: alpha no longer conflicts (nothing enabled to conflict with)
  local off = byId(LauncherMods.deriveList(manifests, { mods = { beta = false } }))
  eq(off.alpha.status, "ok", "no conflict once the other side is disabled")
  eq(off.beta.status, "ok", "a disabled mod is never a conflict")
end

-- ------- warn: unsatisfied game_version range against Version.engine

do
  -- a range the -dev engine cannot satisfy (needs a released >=1.0.0)
  local manifests = {
    mf({ id = "future", name = "Future", version = "1.0.0", entry = "m.lua",
         game_version = ">=1.0.0" }),
  }
  local m = byId(LauncherMods.deriveList(manifests, { mods = {} }))
  eq(m.future.status, "warn", "engine outside the game_version range warns")
  check(m.future.statusDetail:find(">=1.0.0", 1, true) ~= nil,
    "version warn detail quotes the required range")
  check(m.future.statusDetail:find(Version.engine, 1, true) ~= nil,
    "version warn detail quotes the engine version")
end

-- ------- warn: hard dependency missing, disabled, or wrong version

do
  local base = { id = "base", name = "Base", version = "1.0.0", entry = "m.lua" }
  local needsMissing = { id = "needy", name = "Needy", version = "1.0.0",
    entry = "m.lua", dependencies = { "ghost" } }
  local m = byId(LauncherMods.deriveList({ mf(needsMissing) }, { mods = {} }))
  eq(m.needy.status, "warn", "a missing hard dependency warns")
  check(m.needy.statusDetail:find("not installed", 1, true) ~= nil,
    "missing-dep detail says not installed")

  -- present but disabled
  local m2 = byId(LauncherMods.deriveList(
    { mf(base), mf({ id = "needy", name = "Needy", version = "1.0.0",
      entry = "m.lua", dependencies = { "base" } }) },
    { mods = { base = false } }))
  eq(m2.needy.status, "warn", "a disabled hard dependency warns")
  check(m2.needy.statusDetail:find("disabled", 1, true) ~= nil,
    "disabled-dep detail says disabled")

  -- present, enabled, but the version is out of range
  local m3 = byId(LauncherMods.deriveList(
    { mf(base), mf({ id = "needy", name = "Needy", version = "1.0.0",
      entry = "m.lua", dependencies = { "base@>=2.0.0" } }) },
    { mods = {} }))
  eq(m3.needy.status, "warn", "a dependency below the required range warns")
  eq(m3.base.status, "ok", "the satisfied dependency itself stays ok")

  -- the same dep satisfied: needy is ok
  local m4 = byId(LauncherMods.deriveList(
    { mf(base), mf({ id = "needy", name = "Needy", version = "1.0.0",
      entry = "m.lua", dependencies = { "base@>=1.0.0" } }) },
    { mods = {} }))
  eq(m4.needy.status, "ok", "a satisfied dependency clears the warn")
end

-- ------- conflict outranks warn when a mod trips both

do
  local manifests = {
    mf({ id = "alpha", name = "Alpha", version = "1.0.0", entry = "m.lua",
         conflicts = { "beta" }, game_version = ">=1.0.0" }),
    mf({ id = "beta", name = "Beta", version = "1.0.0", entry = "m.lua" }),
  }
  local m = byId(LauncherMods.deriveList(manifests, { mods = {} }))
  eq(m.alpha.status, "conflict",
    "conflict is reported ahead of a version warn on the same mod")
end

-- ------- locateRoot: manifest at the archive root

do
  local root, err = LauncherMods.locateRoot({ "manifest.json", "main.lua" })
  eq(root, "", "a root-level manifest.json resolves to the empty prefix")
  eq(err, nil, "no error for a root-level manifest")
end

-- ------- locateRoot: manifest inside a single top-level folder

do
  local root = LauncherMods.locateRoot({
    "mymod/manifest.json", "mymod/main.lua", "mymod/assets/x.png" })
  eq(root, "mymod", "a single wrapping folder resolves to that folder name")
end

-- ------- locateRoot: no manifest anywhere

do
  local root, err = LauncherMods.locateRoot({ "readme.txt", "stuff/x.lua" })
  eq(root, nil, "an archive with no manifest.json resolves to nil")
  check(err:find("no manifest.json", 1, true) ~= nil,
    "the no-manifest reason is user-presentable")
end

-- ------- locateRoot: multiple top-level folders is ambiguous

do
  local root, err = LauncherMods.locateRoot({
    "one/manifest.json", "two/manifest.json" })
  eq(root, nil, "two candidate mod folders resolves to nil")
  check(err:find("single mod folder", 1, true) ~= nil,
    "the ambiguous reason asks for a single mod folder")
end

-- ------- locateRoot: a lone folder without a manifest is not a root

do
  local root, err = LauncherMods.locateRoot({ "assets/x.png" })
  eq(root, nil, "a single folder with no manifest is not a mod root")
  check(err ~= nil, "the no-root case carries a reason")
end

-- ------- uninstall: rejects bad ids without needing a real mods tree

do
  local ok, err = LauncherMods.uninstall("")
  eq(ok, nil, "empty id is rejected")
  check(tostring(err):find("missing", 1, true) ~= nil, "empty-id reason")

  ok, err = LauncherMods.uninstall("../escape")
  eq(ok, nil, "path-like ids are rejected")
  check(tostring(err):find("invalid", 1, true) ~= nil, "path-id reason")

  ok, err = LauncherMods.uninstall("ghost")
  -- Without a mods/ghost tree (and with the love stub's getInfo), uninstall
  -- either needs LOVE or reports not installed -- never silently succeeds.
  eq(ok, nil, "a missing mod does not uninstall")
  check(err ~= nil, "missing-mod uninstall carries a reason")
end

-- ------- issue #325: the Windows pickers must not hand back mangled paths

do
  -- PowerShell writes the pick in the console's OEM codepage by default
  -- (Pokémon -> Pok\x82mon), which broke the open AND crashed the mods
  -- panel's UTF-8-validating text draw.  Every Windows picker script must
  -- force UTF-8 output, and the mod picker must return an ASCII temp copy
  -- since io.open on Windows needs ANSI bytes to open the file at all.
  local f = assert(io.open("src/import/RomImporter.lua", "rb"))
  local src = f:read("*a")
  f:close()
  local utf8, copies = 0, 0
  for _ in src:gmatch("OutputEncoding=%[Text%.Encoding%]::UTF8") do
    utf8 = utf8 + 1
  end
  check(utf8 >= 3, "all three Windows pickers force UTF-8 output")
  check(src:find("pokeport_mod_pick.zip", 1, true) ~= nil,
    "the mod picker copies the pick to an ASCII temp name")
  check(src:find("Copy%-Item %-LiteralPath") ~= nil,
    "the copy uses the literal picked path")
end

-- ------- pickStrays: which mods dropped beside the game are worth adopting

do
  -- the case this exists for: a player unzipped a mod next to the executable
  -- of a non-portable install, where the game has no way to read it
  local rows = LauncherMods.pickStrays({
    { id = "b_mod", name = "B", folder = "/game", path = "m/b_mod" },
    { id = "a_mod", name = "A", folder = "/game", path = "m/a_mod" },
  }, {})
  eq(#rows, 2, "an uninstalled stray is worth adopting")
  eq(rows[1].id, "a_mod", "rows come back sorted by id")
  eq(rows[2].id, "b_mod", "both of them")
  eq(rows[1].path, "m/a_mod", "carrying the path the copy reads from")
  eq(rows[1].folder, "/game", "and the folder it was found in, for the notice")
end

do
  -- already installed: the player has a working copy and the loose folder is
  -- just where they first put it.  Silence is right -- adopting would make a
  -- second copy, and warning would nag on every open.
  local rows = LauncherMods.pickStrays({
    { id = "have", name = "Have" },
    { id = "want", name = "Want" },
  }, { have = true })
  eq(#rows, 1, "a stray the game can already see is not a stray")
  eq(rows[1].id, "want", "only the one it cannot see is adopted")
end

do
  -- two game folders can both hold the same id (a launcher install plus an
  -- older manual one).  First wins, matching discover()'s duplicate rule.
  local rows = LauncherMods.pickStrays({
    { id = "dup", name = "First", folder = "/a" },
    { id = "dup", name = "Second", folder = "/b" },
  }, {})
  eq(#rows, 1, "a duplicate id across two game folders is adopted once")
  eq(rows[1].name, "First", "and the first one found wins")
end

do
  eq(#LauncherMods.pickStrays({}, {}), 0, "no candidates, nothing to adopt")
  eq(#LauncherMods.pickStrays(nil, nil), 0, "and nil is not an error")
  eq(#LauncherMods.pickStrays({ { name = "no id" } }, {}), 0,
    "a row with no id is dropped rather than crashing the panel")
  local rows = LauncherMods.pickStrays({ { id = "bare" } }, {})
  eq(rows[1].name, "bare", "a nameless row falls back to its id")
end

-- ------- manifest strings are scrubbed to valid UTF-8 (MODS panel crash:
-- LÖVE's printf raises "Invalid UTF-8" on a mangled name/description, so
-- validate must drop bad bytes before any panel draws them)

do
  local m = mf({ id = "utf", entry = "m.lua",
    -- BOM-prefixed name (a real manifest shipped this way), a Latin-1 e-acute
    -- (\233, invalid as UTF-8) in the description, and a lone continuation
    -- byte in the version
    name = "\239\187\191Run Mode",
    version = "1.0\128.0",
    description = "caf\233 latt\233",
    category = "UI\255" })
  eq(m.name, "Run Mode", "a leading BOM is stripped from the name")
  eq(m.version, "1.0.0", "invalid bytes are dropped from the version")
  eq(m.description, "caf latt", "Latin-1 bytes are dropped, not replaced")
  eq(m.raw.category, "UI", "raw.category is scrubbed in place for the badge")

  local ok2 = mf({ id = "utf2", name = "Vers\195\163oVermelha", version = "1.0.0",
    entry = "m.lua", description = "Pok\195\169mon \240\159\148\165" })
  eq(ok2.name, "Vers\195\163oVermelha", "valid two-byte sequences survive")
  eq(ok2.description, "Pok\195\169mon \240\159\148\165",
    "valid three- and four-byte sequences survive")

  -- surrogate half (ED A0 80) and overlong slash (C0 AF) are invalid even
  -- though their lead bytes look plausible
  local bad = mf({ id = "utf3", name = "a\237\160\128b\192\175c",
    version = "1.0.0", entry = "m.lua" })
  eq(bad.name, "abc", "surrogates and overlongs are dropped")
end

-- ------- pre-boot translation strings (deriveStrings)
--
-- The launcher draws before Game:load, so a translation mod's catalog has to
-- reach Strings without the loader running.  These are the rules that decide
-- what it may contribute, with the filesystem read injected.
do
  local manifests = {
    { id = "aaa", name = "A", version = "1.0.0", path = "mods/aaa" },
    { id = "zzz", name = "Z", version = "1.0.0", path = "mods/zzz" },
  }
  local catalogs = {
    ["mods/aaa"] = { ["Import ROM"] = "A-rom", ["Delete"] = "A-del",
                     ["Cancel"] = "" },
    ["mods/zzz"] = { ["Import ROM"] = "Z-rom" },
  }
  local function read(path) return catalogs[path] end
  local function byIdMap(ms)
    local m = {}
    for _, x in ipairs(ms) do m[x.id] = x end
    return m
  end

  local rows = LauncherMods.deriveList(manifests, { mods = {} })
  local merged = LauncherMods.deriveStrings(rows, byIdMap(manifests), read)
  eq(merged["Delete"], "A-del", "an enabled mod contributes its catalog")
  eq(merged["Import ROM"], "Z-rom",
    "later id wins a shared key, as it would at boot")
  eq(merged["Cancel"], nil,
    "an empty value is untranslated, never a blank translation")

  local offRows = LauncherMods.deriveList(manifests, { mods = { zzz = false } })
  local off = LauncherMods.deriveStrings(offRows, byIdMap(manifests), read)
  eq(off["Import ROM"], "A-rom", "a disabled mod contributes nothing")

  local none = LauncherMods.deriveStrings(
    LauncherMods.deriveList(manifests, { mods = { aaa = false, zzz = false } }),
    byIdMap(manifests), read)
  eq(none, nil, "no enabled catalog leaves the launcher on its English source")

  eq(LauncherMods.deriveStrings(rows, byIdMap(manifests), function() return nil end),
    nil, "a mod that ships no catalog is skipped, not an error")
end

T.finish("launcher_mods")
