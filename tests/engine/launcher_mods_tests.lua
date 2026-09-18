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
  check(m.aaa.enabledByVersion.red and m.aaa.enabledByVersion.gold,
    "every row exposes its enabled answer for each game")
  eq(m.aaa.status, "ok", "a healthy enabled mod is ok")
  eq(m.aaa.statusDetail, "Ready", "ok detail reads Ready")
end

do
  local manifests = {
    mf({ id = "one", name = "One", version = "1.0.0", entry = "m.lua" }),
  }
  local row = byId(LauncherMods.deriveList(manifests, {
    mods = { one = true }, modsByVersion = { gold = { one = false } },
  }, "gold")).one
  check(row.enabledByVersion.red, "the Red checkbox keeps the shared answer")
  check(not row.enabledByVersion.gold, "the Gold checkbox reads Gold's answer")
  check(not row.enabled, "the selected game's row state matches its checkbox")
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
  -- Stamped like a shipped build, because the 0.0.0-dev placeholder is not a
  -- compatibility statement and both LauncherMods and Loader.devEngine skip
  -- the range check on it.  Unstamped, this row is "ok" on purpose.
  local was = Version.engine
  Version.engine = "1.4.0"
  local manifests = {
    mf({ id = "future", name = "Future", version = "1.0.0", entry = "m.lua",
         game_version = ">=9.9.9" }),
  }
  local m = byId(LauncherMods.deriveList(manifests, { mods = {} }))
  eq(m.future.status, "warn", "engine outside the game_version range warns")
  check(m.future.statusDetail:find(">=9.9.9", 1, true) ~= nil,
    "version warn detail quotes the required range")
  check(m.future.statusDetail:find("1.4.0", 1, true) ~= nil,
    "version warn detail quotes the engine version")
  Version.engine = was

  -- and the dev placeholder agrees with the loader instead of warning
  local dev = byId(LauncherMods.deriveList(manifests, { mods = {} }))
  eq(dev.future.status, "ok", "a dev checkout does not warn where the loader loads")
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

-- ------- which game a row is answered for (src/mods/ModTargets.lua)

do
  local manifests = {
    mf({ id = "one", name = "One", version = "1.0.0", entry = "m.lua" }),
    mf({ id = "two", name = "Two", version = "1.0.0", entry = "m.lua",
         games = { "gen2" } }),
    mf({ id = "both", name = "Both", version = "1.0.0", entry = "m.lua",
         games = { "gen1", "gen2" } }),
    mf({ id = "allg", name = "All", version = "1.0.0", entry = "m.lua",
         games = { "all" } }),
  }
  -- no game named: the pre-per-game view, where every row is just ready
  local all = byId(LauncherMods.deriveList(manifests, { mods = {} }))
  eq(all.one.targets, "GEN 1", "the chip says which games the mod is for")
  eq(all.two.targets, "GEN 2", "for each of them")
  eq(all.both.targets, "GEN 1+2", "including both")
  eq(all.allg.targets, "GEN 1+2+3", "including all supported generations")
  eq(all.one.targetsHere, nil, "with no game to answer for, nothing is claimed")
  eq(all.two.status, "ok", "and no row is judged against a game")

  local onGold = byId(LauncherMods.deriveList(manifests, { mods = {} }, "gold"))
  eq(onGold.one.status, "other_game", "a Gen 1 mod is not for Gold")
  eq(onGold.one.statusDetail, "For Gen 1, not Gold", "and says so in one line")
  eq(onGold.one.targetsHere, false, "the row carries the verdict too")
  eq(onGold.two.status, "ok", "a Gen 2 mod is ready there")
  eq(onGold.both.targetsHere, true, "and so is one that claims both")

  local onRed = byId(LauncherMods.deriveList(manifests, { mods = {} }, "red"))
  eq(onRed.two.status, "other_game", "the same rule points the other way")
  eq(onRed.one.status, "ok", "without touching the Gen 1 mod")
end

-- ------- the row is a verdict, not a decoration: the loader enforces it
--
-- "For Blue, not Red" has to be what the boot does, per VERSION and not only
-- per generation, or the panel is reporting a claim while the mod runs anyway.
-- Real loader, real gate (Loader:_gateGeneration), no love.

do
  local Sdk = require("tests.modkit.sdk")
  local GameVersion = require("src.core.GameVersion")
  local function manifestFile(id, games)
    return ("{\"id\":\"%s\",\"name\":\"%s\",\"version\":\"1.0.0\"," ..
      "\"entry\":\"main.lua\",\"api\":2,\"games\":[\"%s\"]}"):format(id, id, games)
  end
  local FILES = {
    ["mods/blueonly/manifest.json"] = manifestFile("blueonly", "blue"),
    ["mods/blueonly/main.lua"] = "local mod = ...\n",
    ["mods/goldonly/manifest.json"] = manifestFile("goldonly", "gold"),
    ["mods/goldonly/main.lua"] = "local mod = ...\n",
    ["mods/anygame/manifest.json"] = manifestFile("anygame", "all"),
    ["mods/anygame/main.lua"] = "local mod = ...\n",
  }
  local paths = { "mods/blueonly", "mods/goldonly", "mods/anygame" }
  local was = GameVersion.get()
  GameVersion.set("red")
  local run = Sdk.loadMods(paths, { fs = Sdk.memfs(FILES), generation = 1 })
  local rows = byId(LauncherMods.deriveList({
    mf({ id = "blueonly", name = "blueonly", version = "1.0.0",
         entry = "main.lua", games = { "blue" } }),
    mf({ id = "goldonly", name = "goldonly", version = "1.0.0",
         entry = "main.lua", games = { "gold" } }),
    mf({ id = "anygame", name = "anygame", version = "1.0.0",
         entry = "main.lua", games = { "all" } }),
  }, { mods = {} }, "red"))
  for _, id in ipairs({ "blueonly", "goldonly", "anygame" }) do
    local ran = run.loader.mods[id].state ~= "wrong_generation"
    eq(ran, rows[id].targetsHere,
      "the loader and the panel agree about " .. id .. " on Red")
  end
  eq(run.loader.mods.blueonly.state, "wrong_generation",
    "a Blue-only mod does not run on Red")
  eq(run.loader.mods.blueonly.skipReason, "For Blue, not Red",
    "and the skip line is the launcher's own line")
  eq(run.loader.mods.anygame.state, "loaded", "a mod for every game still runs")
  run.release()

  -- the override answers for ONE game.  A version-blind flag forced a mod
  -- past the gate on a game whose owner was never asked (SaveData.modForced).
  local Serializer = require("src.core.SaveSerializer")
  local function bootWith(modsGen2, generation)
    local fs = Sdk.memfs(FILES)
    fs.write("options.lua", Serializer.encode({ mods = {}, modsGen2 = modsGen2 }))
    local r = Sdk.loadMods(paths, { fs = fs, generation = generation })
    local state = r.loader.mods.blueonly.state
    r.release()
    return state
  end
  eq(bootWith({ blueonly = { red = true } }, 1), "loaded",
    "an override for Red runs the Blue-only mod on Red")
  eq(bootWith({ blueonly = { blue = true } }, 1), "wrong_generation",
    "an override for another game does not answer for Red")
  eq(bootWith({ blueonly = true }, 1), "wrong_generation",
    "a pre-per-game flag keeps its old meaning: Gen 2 only, never Red")

  GameVersion.set("gold")
  eq(bootWith({ blueonly = true }, 2), "loaded",
    "and on the Gen 2 game it always meant, it still forces")
  eq(bootWith({}, 2), "wrong_generation", "with no override the gate holds")
  if was then GameVersion.set(was) end
end

do
  -- the player's override is the one thing that outranks the author's claim,
  -- and it must read as the untested thing it is (Loader:_gateGeneration)
  local manifests = {
    mf({ id = "one", name = "One", version = "1.0.0", entry = "m.lua" }),
  }
  local m = byId(LauncherMods.deriveList(manifests,
    { mods = {}, modsGen2 = { one = true } }, "gold"))
  eq(m.one.status, "warn", "a forced mod is a warning, not a wrong game")
  check(m.one.statusDetail:find("Gold", 1, true) ~= nil,
    "and the line names the game it was forced onto")
  eq(m.one.targetsHere, true, "it will run there")
end

-- ------- enable flags: the panel reads exactly what the switch writes
--
-- One scope for both halves (SaveData.modScope).  Per-game flags are live, so
-- a modsByVersion answer -- including one restored from a .g1rmodlist -- is
-- both what the launcher shows and what the next boot reads.

local SaveData = require("src.core.SaveData")

local function flip(options, id, enabled, version)
  SaveData.setModEnabled(options, id, enabled, SaveData.modScope(version))
end

do
  local manifests = {
    mf({ id = "one", name = "One", version = "1.0.0", entry = "m.lua",
         games = { "all" } }),
  }
  local planted = { mods = { one = true },
                    modsByVersion = { gold = { one = false } } }
  eq(byId(LauncherMods.deriveList(manifests, planted, "gold")).one.enabled,
    false, "the overlay is read exactly when a write can reach it")

  -- the round trip, the thing the dead switch failed: flip it, re-derive
  local options = { mods = {} }
  for _, version in ipairs({ "red", "gold" }) do
    flip(options, "one", false, version)
    eq(byId(LauncherMods.deriveList(manifests, options, version)).one.enabled,
      false, "switching off reads back off on " .. version)
    flip(options, "one", true, version)
    eq(byId(LauncherMods.deriveList(manifests, options, version)).one.enabled,
      true, "and switching on reads back on on " .. version)
  end

  -- the same round trip through the planted overlay: no write is ignored
  flip(planted, "one", false, "gold")
  eq(byId(LauncherMods.deriveList(manifests, planted, "gold")).one.enabled,
    false, "a planted overlay cannot outrank the player's own write")
  flip(planted, "one", true, "gold")
  eq(byId(LauncherMods.deriveList(manifests, planted, "gold")).one.enabled,
    true, "in either direction")

  -- and what the loader will do agrees with the row, per game
  eq(SaveData.modEnabled(planted, "one", SaveData.modScope("gold")), true,
    "the loader resolves the flag under the same scope the panel read")
end

-- ------- a dependency that does not run here is a dependency problem
--
-- The loader's target skip is contagious (Loader:_enforceDependencies), so a
-- mod that runs on every game still does not run on Gold when the mod it
-- needs is Gen 1 only.

do
  local manifests = {
    mf({ id = "base", name = "Base", version = "1.0.0", entry = "m.lua",
         games = { "gen1" } }),
    mf({ id = "user", name = "User", version = "1.0.0", entry = "m.lua",
         games = { "all" }, dependencies = { "base" } }),
  }
  local onGold = byId(LauncherMods.deriveList(manifests, { mods = {} }, "gold"))
  eq(onGold.user.status, "warn",
    "a dependency that cannot run here is a warning, not Ready")
  check(onGold.user.statusDetail:find("base", 1, true) ~= nil
    and onGold.user.statusDetail:find("Gold", 1, true) ~= nil,
    "and the line names the dependency and the game")
  eq(byId(LauncherMods.deriveList(manifests, { mods = {} }, "red")).user.status,
    "ok", "while the same pair is Ready where both run")

  -- the player's override on the DEPENDENCY clears it: same scope the loader
  -- resolves the override under (SaveData.modForced)
  local forced = { mods = {}, modsGen2 = { base = { gold = true } } }
  eq(byId(LauncherMods.deriveList(manifests, forced, "gold")).user.status, "ok",
    "forcing the dependency onto Gold clears the dependent's warning")
  eq(byId(LauncherMods.deriveList(manifests,
    { mods = {}, modsGen2 = { base = { red = true } } }, "gold")).user.status,
    "warn", "an override for another game does not answer for this one")
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
