-- Sandboxed public-API coverage for imported semantic dataset views.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Fixture = require("tests.modkit.dataset_view_fixture")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local Schemas = require("src.mods.Schemas")

local originalVersion = GameVersion.get()
local originalPrefix = CacheFs.prefix
GameVersion.set("red")

local files = {}
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal" }) do
  Fixture.cache(files, version)
end
local probe = Fixture.addMod(files, "dataset_probe", [[
local mod = ...
local out = {}
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal" }) do
  local view, reason = mod.datasets:open(version)
  local mon = view and view.content.pokemon:get("FIXMON")
  if mon then mon.name = "MUTATED" end
  local ids = {}
  if view then
    for id, value in view.content.pokemon:each() do
      ids[#ids + 1] = id
      if value then value.name = "EACH_MUTATED" end
    end
  end
  out[version] = {
    reason = reason, generation = view and view.generation,
    name = view and view.content.pokemon:get("FIXMON").name,
    has = view and view.content.pokemon:has("FIXMON"), ids = ids,
    aliasScripts = view and view.content.scripts == view.content.map_scripts,
    aliasUi = view and view.content.ui == view.content.screens,
    readOnly = view and view.content.pokemon.register == nil
      and view.content.pokemon.patch == nil and view.content.pokemon.remove == nil,
  }
end
local yellow = assert(mod.datasets:open("yellow"))
out.yellowOldMan = yellow.content.field:get("oldManBattle")
out.yellowBoot = yellow.content.field:get("boot")
local red = assert(mod.datasets:open("red"))
out.redBoot = red.content.field:get("boot")
out.redConstants = red.content.constants:get("dexSize")
local gold = assert(mod.datasets:open("gold"))
out.registryCount = 0
for _, registry in pairs(gold.content) do
  if type(registry) == "table" then out.registryCount = out.registryCount + 1 end
end
out.foresight = gold.content.type_chart:get("NORMAL>GHOST")
out.held = gold.content.held_items:get("LEFTOVERS")
out.continuations, out.moves, out.assets = {}, {}, {}
for _, id in ipairs({ "CROBAT", "BELLOSSOM", "POLITOED", "SLOWKING",
    "STEELIX", "SCIZOR", "KINGDRA", "PORYGON2", "BLISSEY" }) do
  local row = gold.content.pokemon:get(id)
  out.continuations[id] = row and row.dex
  out.assets[id] = row and {
    gold.assets:info(row.spriteFront), gold.assets:info(row.spriteBack) }
end
for _, id in ipairs({ "IRON_TAIL", "METAL_CLAW", "STEEL_WING", "RAIN_DANCE",
    "SUNNY_DAY", "SANDSTORM", "SLUDGE_BOMB", "SHADOW_BALL" }) do
  out.moves[id] = gold.content.moves:has(id)
end
out.steel = gold.content.type_chart:has("STEEL")
out.metadataHidden = not gold.content.pokemon:has("growthRates")
  and not gold.content.pokemon:has("tmhmMoves")
  and not gold.content.moves:has("generation")
  and not gold.content.moves:has("source")
  and not gold.content.items:has("generation")
  and not gold.content.items:has("source")
  and not gold.content.items:has("pockets")
out.executableBuiltinHidden = gold.content.statuses:get("sleep") == nil
out.assetDirectory = gold.assets:info("assets/generated/battle/front")
out.assetRejects = {}
for _, path in ipairs({ "/assets/generated/x", "assets\\generated\\x",
    "assets/generated/../x", "assets/generated/./x", "other/x",
    "assets/generated/x\1" }) do
  out.assetRejects[#out.assetRejects + 1] = pcall(gold.assets.path, gold.assets, path)
end
local unknown, unknownReason = mod.datasets:open("missing-version")
out.unknown = { unknown ~= nil, unknownReason }
mod.exports.result = out
]])

local active = { pokemon = { ACTIVE = { id = "ACTIVE", nested = { n = 1 } } } }
local run = T.sdk.loadMods({ probe }, {
  fs = T.sdk.memfs(files), data = active, generation = 1,
})
T.eq(#run.errors, 0, "dataset public probe loads clean")
local out = run.loader.exports.dataset_probe.result
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal" }) do
  T.eq(out[version].reason, nil, version .. " opens")
  T.eq(out[version].generation,
    GameVersion.generation(version),
    version .. " reports selected generation")
  T.eq(out[version].name, "FIXMON", version .. " get/each values are detached")
  T.eq(out[version].has, true, version .. " has reads without exposing a copy")
  T.eq(out[version].aliasScripts, true, version .. " scripts alias is canonical")
  T.eq(out[version].aliasUi, true, version .. " ui alias is canonical")
  T.eq(out[version].readOnly, true, version .. " registry has no write verbs")
end
T.eq(out.redConstants, 1, "Red derives dexSize through canonical defaults")
T.eq(out.redBoot and out.redBoot.screens and out.redBoot.screens.splash,
  "IntroMovie", "Red uses canonical boot defaults")
T.eq(out.yellowOldMan and out.yellowOldMan.species, "RATTATA",
  "Yellow applies canonical correction")
T.eq(out.yellowBoot and out.yellowBoot.screens and out.yellowBoot.screens.splash,
  "YellowIntro",
  "Yellow uses its canonical splash")
T.eq(out.foresight and out.foresight.multiplier, 0,
  "Gold appends Foresight matchup rows")
T.eq(out.held and out.held.heldEffect, "HELD_LEFTOVERS", "Gold derives held_items")
for _, id in ipairs(Fixture.CONTINUATIONS) do
  T.check(out.continuations[id] ~= nil, "Gold exposes " .. id)
  T.same(out.assets[id], { { type = "file" }, { type = "file" } },
    "Gold exposes namespaced front/back assets for " .. id)
end
for _, id in ipairs(Fixture.MOVES) do T.eq(out.moves[id], true, "Gold exposes " .. id) end
T.eq(out.steel, true, "Gold exposes Steel")
T.eq(out.metadataHidden, true,
  "Gold extractor metadata stays outside record registry id spaces")
local registryCount = 0
for _ in pairs(Schemas.REGISTRIES) do registryCount = registryCount + 1 end
for _ in pairs(Schemas.ALIASES) do registryCount = registryCount + 1 end
T.eq(out.registryCount, registryCount,
  "view exposes every canonical registry and alias")
T.eq(out.executableBuiltinHidden, true,
  "engine records containing closures do not cross the data-only facade")
T.eq(out.assetDirectory, nil, "asset info does not expose directories")
for index, accepted in ipairs(out.assetRejects) do
  T.eq(accepted, false, "asset rejection " .. index)
end
T.same(out.unknown, { false, "unknown_version" }, "unknown version fails stably")
T.eq(active.pokemon.ACTIVE.nested.n, 1, "active Data stays unchanged")
T.eq(active.pokemon.FIXMON, nil, "inactive records do not merge into active Data")
T.eq(GameVersion.get(), "red", "active GameVersion stays unchanged")
T.eq(CacheFs.prefix, originalPrefix, "CacheFs prefix stays unchanged")
run.release()

-- Facade replacement and nested record mutation do not cross mod boundaries.
local isolation = {}
Fixture.cache(isolation, "red")
local mutator = Fixture.addMod(isolation, "dataset_mutator", [[
local mod = ...
local view = assert(mod.datasets:open("red"))
view.content.pokemon.get = function() return { name = "POISONED" } end
local row = view.content.pokemon:get("FIXMON")
if row then row.name = "CHANGED" end
]])
local observer = Fixture.addMod(isolation, "dataset_observer", [[
local mod = ...
local view = assert(mod.datasets:open("red"))
mod.exports.name = view.content.pokemon:get("FIXMON").name
]])
isolation["mods/dataset_observer/manifest.json"] = [[{
  "id": "dataset_observer", "name": "dataset_observer", "version": "1.0.0",
  "entry": "main.lua", "api": 2, "games": ["all"],
  "dependencies": ["dataset_mutator"]
}]]
local isolationRun = T.sdk.loadMods({ mutator, observer }, {
  fs = T.sdk.memfs(isolation), data = { pokemon = {} }, generation = 1,
})
T.eq(isolationRun.loader.exports.dataset_observer.name, "FIXMON",
  "facade and record mutation cannot cross mods")
isolationRun.release()

-- Marker-only, empty, partial, and stale-after-first-open caches fail closed.
local readiness = {}
local emptyPrefix = GameVersion.cachePrefix("red")
readiness[emptyPrefix .. "rom-cache.complete"] =
  "rom-cache-v10:" .. GameVersion.info("red").sha1
Fixture.cache(readiness, "blue")
readiness[GameVersion.cachePrefix("blue") .. "data/generated/moves.lua"] = nil
Fixture.cache(readiness, "gold")
local staleReads = 0
local readinessFs = T.sdk.memfs(readiness)
local rawRead = readinessFs.read
readinessFs.read = function(path)
  if path == GameVersion.cachePrefix("gold") .. "rom-cache.complete" then
    staleReads = staleReads + 1
    if staleReads > 1 then return "rom-cache-v9:stale" end
  end
  return rawRead(path)
end
local readinessMod = Fixture.addMod(readiness, "readiness_probe", [[
local mod = ...
local out = {}
for _, version in ipairs({ "red", "blue" }) do
  local view, reason = mod.datasets:open(version)
  out[version] = { view ~= nil, reason }
end
local first, firstReason = mod.datasets:open("gold")
local second, secondReason = mod.datasets:open("gold")
out.gold = { first ~= nil, firstReason, second ~= nil, secondReason }
mod.exports.result = out
]])
local readinessRun = T.sdk.loadMods({ readinessMod }, {
  fs = readinessFs, data = { pokemon = {} }, generation = 1,
})
local readyOut = readinessRun.loader.exports.readiness_probe.result
T.same(readyOut.red, { false, "not_imported" }, "marker-only empty cache fails")
T.same(readyOut.blue, { false, "not_imported" }, "partial cache fails")
T.same(readyOut.gold, { true, nil, false, "not_imported" },
  "cached view is invalidated when marker becomes stale")
readinessRun.release()

-- Removal followed by a fresh import cannot resurrect the pre-removal view.
local transition = {}
Fixture.cache(transition, "red")
local transitionFs = T.sdk.memfs(transition)
local transitionRead = transitionFs.read
local transitionMarkers = 0
local reimportedPokemon = require("src.import.LuaWriter").encode({
  FIXMON = { id = "FIXMON", name = "REIMPORTED", dex = 1,
    types = {}, catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST",
    baseStats = { hp = 45, attack = 49, defense = 49, speed = 45,
      special = 65 },
    level1Moves = {}, tmhm = {}, learnset = {}, evolutions = {},
    spriteFront = "assets/generated/battle/front/fixmon.png",
    spriteBack = "assets/generated/battle/back/fixmon.png", frontSize = 5 },
})
transitionFs.read = function(path)
  if path == GameVersion.cachePrefix("red") .. "rom-cache.complete" then
    transitionMarkers = transitionMarkers + 1
    -- open and the first facade read each recheck readiness; remove the cache
    -- for the next open, then make the following open the reimport.
    if transitionMarkers == 3 then return nil end
  end
  local body = transitionRead(path)
  if transitionMarkers >= 4
      and path == GameVersion.cachePrefix("red") .. "data/generated/pokemon.lua" then
    return reimportedPokemon
  end
  return body
end
local transitionMod = Fixture.addMod(transition, "transition_probe", [[
local mod = ...
local out = {}
for index = 1, 3 do
  local view, reason = mod.datasets:open("red")
  out[index] = { view and view.content.pokemon:get("FIXMON").name, reason }
end
mod.exports.result = out
]])
local transitionRun = T.sdk.loadMods({ transitionMod }, {
  fs = transitionFs, data = { pokemon = {} }, generation = 1,
})
T.same(transitionRun.loader.exports.transition_probe.result, {
  { "FIXMON" }, { nil, "not_imported" }, { "REIMPORTED" },
}, "remove and reimport transition rebuilds the semantic view")
transitionRun.release()

-- Every hostile source is rejected as data, with one stable public reason.
local hostile = {
  { "red", "return { BAD = function() return 1 end }" },
  { "blue", "owned = true; return {}" },
  { "yellow", "return 7" },
  { "gold", string.char(27) .. "Lua" },
  { "silver", "return {}; while true do end" },
}
local hostileFiles, hostilePaths = {}, {}
for _, row in ipairs(hostile) do
  Fixture.cache(hostileFiles, row[1], { pokemon = row[2] })
end
local hostileMod = Fixture.addMod(hostileFiles, "hostile_probe", [[
local mod = ...
local out = {}
for _, version in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal" }) do
  local view, reason = mod.datasets:open(version)
  local value = view and view.content.pokemon:get("BAD")
  local reopened, reopenedReason = mod.datasets:open(version)
  out[version] = {
    first = view ~= nil, firstReason = reason, value = value,
    reopened = reopened ~= nil, reason = reopenedReason,
  }
end
mod.exports.result = out
]])
hostilePaths[1] = hostileMod
local previousHook, previousMask, previousCount
local beforeHook
if debug.gethook and debug.sethook then
  previousHook, previousMask, previousCount = debug.gethook()
  beforeHook = function() end
  debug.sethook(beforeHook, "", 1000)
end
local hostileRun = T.sdk.loadMods(hostilePaths, {
  fs = T.sdk.memfs(hostileFiles), data = { pokemon = {} }, generation = 1,
})
local hostileOut = hostileRun.loader.exports.hostile_probe.result
for _, row in ipairs(hostile) do
  T.same(hostileOut[row[1]], {
    first = true, reopened = false, reason = "invalid_cache",
  }, row[1] .. " hostile generated source fails closed on first root access")
end
T.eq(debug.gethook and debug.gethook(), beforeHook,
  "dataset decoding preserves the caller debug hook")
if debug.sethook then
  if previousHook then debug.sethook(previousHook, previousMask, previousCount)
  else debug.sethook() end
end
hostileRun.release()

-- A syntactically valid semantic root with a primitive record must fail closed
-- whichever public read verb encounters it first.
local malformedFiles = {}
for _, version in ipairs({ "red", "blue", "yellow" }) do
  Fixture.cache(malformedFiles, version, {
    pokemon = "return { FIXMON = 7 }",
  })
end
local malformedMod = Fixture.addMod(malformedFiles, "malformed_probe", [[
local mod = ...
local out = {}
local getView = assert(mod.datasets:open("red"))
out.get = getView.content.pokemon:get("FIXMON")
local getAgain, getReason = mod.datasets:open("red")
out.getAgain = { getAgain ~= nil, getReason }

local hasView = assert(mod.datasets:open("blue"))
out.has = hasView.content.pokemon:has("FIXMON")
local hasAgain, hasReason = mod.datasets:open("blue")
out.hasAgain = { hasAgain ~= nil, hasReason }

local eachView = assert(mod.datasets:open("yellow"))
for id, value in eachView.content.pokemon:each() do
  out.each = { id, value }
  break
end
local eachAgain, eachReason = mod.datasets:open("yellow")
out.eachAgain = { eachAgain ~= nil, eachReason }
mod.exports.result = out
]])
local malformedRun = T.sdk.loadMods({ malformedMod }, {
  fs = T.sdk.memfs(malformedFiles), data = { pokemon = {} }, generation = 1,
})
T.eq(#malformedRun.errors, 0, "malformed-record probe stays sandboxed")
local malformedOut = malformedRun.loader.exports.malformed_probe.result
T.eq(malformedOut.get, nil, "get never exposes a malformed semantic record")
T.eq(malformedOut.has, false, "has never affirms a malformed semantic record")
T.eq(malformedOut.each, nil, "each never exposes a malformed semantic record")
T.same(malformedOut.getAgain, { false, "invalid_cache" },
  "get invalidates the malformed dataset")
T.same(malformedOut.hasAgain, { false, "invalid_cache" },
  "has invalidates the malformed dataset")
T.same(malformedOut.eachAgain, { false, "invalid_cache" },
  "each invalidates the malformed dataset")
malformedRun.release()

-- The same Gold view stays independent while each Gen 1 version is the
-- actual active runtime version and cache namespace, not just a fixture label.
for _, activeVersion in ipairs({ "red", "blue", "yellow" }) do
  local matrixFiles = {}
  Fixture.cache(matrixFiles, "gold")
  local matrixMod = Fixture.addMod(matrixFiles,
    "active_" .. activeVersion .. "_gold_probe", [[
local mod = ...
local gold = assert(mod.datasets:open("gold"))
mod.exports.result = {
  species = gold.content.pokemon:get("FIXMON").name,
  foresight = gold.content.type_chart:get("NORMAL>GHOST").multiplier,
  held = gold.content.held_items:get("LEFTOVERS").heldEffect,
}
]])
  GameVersion.set(activeVersion)
  CacheFs.prefix = GameVersion.cachePrefix(activeVersion)
  local activeData = {
    pokemon = { ACTIVE = { id = "ACTIVE_" .. activeVersion,
      nested = { version = activeVersion } } },
  }
  local matrixRun = T.sdk.loadMods({ matrixMod }, {
    fs = T.sdk.memfs(matrixFiles), data = activeData, generation = 1,
  })
  T.eq(#matrixRun.errors, 0, activeVersion .. "-active Gold probe loads")
  T.same(matrixRun.loader.exports["active_" .. activeVersion .. "_gold_probe"].result,
    { species = "FIXMON", foresight = 0, held = "HELD_LEFTOVERS" },
    activeVersion .. "-active runtime sees canonical Gold semantics")
  T.eq(GameVersion.get(), activeVersion,
    activeVersion .. " remains the active GameVersion")
  T.eq(CacheFs.prefix, GameVersion.cachePrefix(activeVersion),
    activeVersion .. " remains the active cache namespace")
  T.eq(activeData.pokemon.ACTIVE.nested.version, activeVersion,
    activeVersion .. " active Data remains unchanged")
  T.eq(activeData.pokemon.FIXMON, nil,
    activeVersion .. " active Data receives no Gold record")
  matrixRun.release()
end

GameVersion.set(originalVersion)
CacheFs.prefix = originalPrefix
T.finish("dataset_views")
