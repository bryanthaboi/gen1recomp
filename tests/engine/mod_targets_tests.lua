-- Which games a mod is for: the manifest `games` key, the legacy gen2compat
-- reading of it, the per-game enable overlay both mod surfaces resolve
-- through, and the profile that carries a per-game set between installs.
--   luajit tests/engine/mod_targets_tests.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local Manifest = require("src.mods.Manifest")
local ModProfile = require("src.mods.ModProfile")
local ModTargets = require("src.mods.ModTargets")
local SaveData = require("src.core.SaveData")

local function mf(raw)
  raw.id = raw.id or "m"
  raw.name = raw.name or "M"
  raw.version = raw.version or "1.0.0"
  raw.entry = raw.entry or "main.lua"
  return Manifest.validate(raw)
end

local function list(m)
  return table.concat(ModTargets.versions(m), ",")
end

-- ------- tokens expand off GameVersion, never a literal list

do
  eq(table.concat(ModTargets.expand("red"), ","), "red",
    "a version id names exactly that game")
  eq(table.concat(ModTargets.expand("GEN1"), ","), "red,blue,yellow",
    "gen1 is every Gen 1 game, case-insensitive")
  eq(table.concat(ModTargets.expand("gen2"), ","), "gold,silver",
    "gen2 is every Gen 2 game")
  eq(table.concat(ModTargets.expand("silver"), ","), "silver",
    "and each of them names itself")
  eq(table.concat(ModTargets.expand("all"), ","),
    table.concat(GameVersion.ORDER, ","), "all is the launcher order itself")
  eq(ModTargets.expand("crystal"), nil, "a game this engine has no cache for")
  eq(ModTargets.expand("gen9"), nil, "a generation with no games is unknown")
  eq(ModTargets.expand(7), nil, "a non-string token is not a game")
end

do
  local versions, unknown = ModTargets.normalize({ "gold", "red", "red" })
  eq(table.concat(versions, ","), "red,gold",
    "normalize dedupes and sorts into GameVersion.ORDER")
  eq(#unknown, 0, "known tokens leave nothing unreported")
  local _, bad = ModTargets.normalize({ "crystal", "gen1" })
  eq(#bad, 1, "an unknown token comes back for the caller to report")
  eq(bad[1], "crystal", "by name")
end

-- ------- the legacy reading: gen2compat only ever ADDS Gen 2

do
  eq(list(mf({})), "red,blue,yellow",
    "a manifest with no games key is Gen 1, which is what it was tested as")
  eq(list(mf({ gen2compat = true })), "red,blue,yellow,gold,silver",
    "gen2compat keeps Gen 1 and adds Gen 2")
  eq(mf({}).gen2compat, false, "and the derived flag agrees")
  eq(mf({ gen2compat = true }).gen2compat, true, "both ways")
end

-- ------- games declares it directly, and the loader's gate reads the derived
-- gen2compat, so no Loader change is needed to honour the new key

do
  local gen2 = mf({ games = { "gen2" } })
  eq(list(gen2), "gold,silver", "games can name Gen 2 alone")
  eq(gen2.gen2compat, true, "which IS the gen2compat claim the gate reads")
  local both = mf({ games = { "gen1", "gen2" } })
  eq(list(both), "red,blue,yellow,gold,silver", "or both generations")
  local one = mf({ games = { "blue" } })
  eq(list(one), "blue", "or one single game")
  eq(one.gen2compat, false, "a Gen 1 game is not a Gen 2 claim")
  eq(list(mf({ games = { "red" }, gen2compat = true })), "red,gold,silver",
    "an old gen2compat beside a new games list still adds its game")
end

do
  -- vocabulary: api 1 warns and keeps loading, api 2 refuses, exactly like
  -- every other manifest vocabulary (Manifest.violation)
  local lenient = mf({ games = { "crystal", "red" } })
  eq(list(lenient), "red", "api 1 drops the unknown game and keeps the rest")
  check(not pcall(mf, { api = 2, games = { "crystal" } }),
    "api 2 refuses a game it does not have")
  check(not pcall(mf, { games = "gen1" }),
    "games must be an array, not a bare string")
  eq(list(mf({ games = {} })), "red,blue,yellow",
    "an empty games list falls back rather than orphaning the mod")
end

-- ------- supports / runsHere: the claim, then what actually happens

do
  local gen1 = mf({ id = "one" })
  local gen2 = mf({ id = "two", games = { "gen2" } })
  check(ModTargets.supports(gen1, "red"), "a Gen 1 mod supports Red")
  check(not ModTargets.supports(gen1, "gold"), "and not Gold")
  check(ModTargets.supports(gen2, "gold"), "a Gen 2 mod supports Gold")
  check(not ModTargets.supports(gen2, "red"), "and not Red")
  check(ModTargets.supports(gen1, nil, 1), "a generation can be asked directly")
  check(not ModTargets.supports(gen1, nil, 2), "and answers the same way")
  check(not ModTargets.runsHere(gen1, "gold"), "no claim, no run")
  check(ModTargets.runsHere(gen1, "gold", nil, true),
    "the player's override is what forces one anyway")
end

-- ------- one label, both surfaces

do
  eq(ModTargets.label(mf({})), "Gen 1", "whole generations read as generations")
  eq(ModTargets.label(mf({ games = { "all" } })), "Gen 1+2", "both of them")
  eq(ModTargets.label(mf({ games = { "gen2" } })), "Gen 2", "or just the one")
  eq(ModTargets.label(mf({ games = { "red", "gold" } })), "Red/Gold",
    "part of a generation reads as the games themselves")
  eq(ModTargets.chip(mf({})), "GEN 1", "the chip is the same label, uppercased")
  eq(ModTargets.detail(mf({}), "gold"), "For Gen 1, not Gold",
    "and the launcher line names both sides")
end

-- ------- per-game enable overlay: absent means the shared flag, which is
-- what every options.lua written before this key holds

do
  local opts = { mods = { a = false, b = true } }
  eq(SaveData.modEnabled(opts, "a", "gold"), false,
    "no overlay entry falls through to the shared flag")
  eq(SaveData.modEnabled(opts, "b"), true, "with or without a game")
  eq(SaveData.modEnabled(opts, "ghost", "gold"), nil,
    "an unanswered mod is nil, so the caller owns the default")

  opts.modsByVersion = { gold = { a = true } }
  eq(SaveData.modEnabled(opts, "a", "gold"), true, "the game's own answer wins")
  eq(SaveData.modEnabled(opts, "a", "red"), false, "for that game only")
  eq(SaveData.modEnabled(opts, "a"), false, "and the shared view is untouched")
end

do
  local opts = { mods = {} }
  SaveData.setModEnabled(opts, "a", false, "gold")
  eq(opts.modsByVersion.gold.a, false, "a per-game write lands in that game")
  eq(opts.mods.a, nil, "and never in the shared flag")
  SaveData.setModEnabled(opts, "a", false)
  eq(opts.mods.a, false, "a shared write lands in the shared flag")
  SaveData.setModEnabled(opts, "a", false, "gold")
  eq(opts.modsByVersion.gold.a, nil,
    "a per-game answer that agrees with the shared one is dropped, not stored")
  eq(SaveData.modEnabled(opts, "a", "gold"), false, "and still resolves the same")

  local fresh = { mods = {} }
  SaveData.setModEnabled(fresh, "b", true, "gold")
  eq(fresh.modsByVersion.gold.b, true,
    "with no shared flag the answer is stored, not dropped against an assumed default")
end

do
  -- the write scope is gated on the loader honouring it, so no surface can
  -- promise a per-game set the boot would ignore
  eq(SaveData.modScope("gold"), SaveData.PER_VERSION_MODS and "gold" or nil,
    "modScope follows the PER_VERSION_MODS switch")
end

do
  -- First launch after per-game controls shipped: preserve every old answer
  -- and make the old implicit defaults explicit for the installed set.
  local opts = {
    mods = { old_on = true, old_off = false },
    modsByVersion = { gold = { old_on = false } },
  }
  check(SaveData.migrateModEnablement(opts, {
    { id = "old_on" }, { id = "old_off" }, { id = "implicit" },
    { id = "lab", experimental = true },
  }), "legacy mod state is migrated once")
  check(opts.modsByVersionMigrated, "the migration is marked complete")
  eq(SaveData.modEnabled(opts, "old_on", "red"), true,
    "an old enabled mod is enabled for Red")
  eq(SaveData.modEnabled(opts, "old_on", "gold"), false,
    "an already-stored preview answer is preserved")
  eq(SaveData.modEnabled(opts, "old_off", "blue"), false,
    "an old disabled mod stays disabled for every game")
  eq(SaveData.modEnabled(opts, "implicit", "yellow"), true,
    "an old implicit default is enabled for every game")
  eq(SaveData.modEnabled(opts, "lab", "red"), false,
    "an experimental mod keeps its existing opt-in default")
  check(not SaveData.migrateModEnablement(opts, { { id = "newer" } }),
    "a later mod install does not rerun the legacy migration")
end

-- ------- a profile carries the per-game half of a setup

do
  local available = {
    { id = "a", enabled = true }, { id = "b", enabled = false },
  }
  local byVersion = { gold = { a = false }, red = {} }
  local p = ModProfile.capture(available, {}, byVersion)
  eq(p.enabledByVersion.gold.a, false, "capture takes the per-game answers")
  eq(p.enabledByVersion.red, nil, "an empty game is not carried")

  p.name = "PROF"
  local back = ModProfile.decode(ModProfile.encode(p))
  eq(back.enabledByVersion.gold.a, false, "and they survive an export")

  local opts = { mods = {} }
  ModProfile.restoreVersions(back, opts)
  eq(opts.modsByVersion.gold.a, false, "applying a profile restores them")
  check(ModProfile.matchesVersions(back, opts),
    "a restored setup still reads as that profile")
  opts.modsByVersion.gold.a = true
  check(not ModProfile.matchesVersions(back, opts),
    "and drifts to ad-hoc as soon as one game differs")

  local untouched = { modsByVersion = { gold = { z = true } } }
  ModProfile.restoreVersions({ enabledByVersion = {} }, untouched)
  eq(untouched.modsByVersion.gold.z, true,
    "a profile that names no game blanks none")
end

do
  -- a shared .g1rmodlist is untrusted input; the manager indexes it straight
  -- into options.modsByVersion
  local bad = ModProfile.decode(require("src.core.SaveSerializer").encode({
    format = "g1rmodlist", formatVersion = 1,
    profile = { name = "P", enabledByVersion = {
      gold = { a = true }, silver = { a = true }, crystal = { a = true },
      red = "nope" } },
  }))
  eq(bad.enabledByVersion.gold.a, true, "a shared file's known game is kept")
  eq(bad.enabledByVersion.silver.a, true, "every one of them, not just the first")
  eq(bad.enabledByVersion.crystal, nil, "an unknown game is dropped on read")
  eq(bad.enabledByVersion.red, nil, "and so is a bucket that is not a table")
end

T.finish("mod_targets")
