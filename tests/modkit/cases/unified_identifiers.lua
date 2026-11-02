package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Fixture = require("tests.modkit.dataset_view_fixture")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local Merge = require("src.mods.Merge")
local Ids = require("src.mods.UnifiedIds")
local Records = require("src.mods.UnifiedRecords")
local Runtime = require("src.mods.Runtime")
local UnifiedWorld = require("src.mods.UnifiedWorld")

local VERSIONS = { "red", "blue", "yellow", "gold", "silver", "crystal",
  "firered", "leafgreen", "ruby", "sapphire", "emerald" }
local SPECIES = { "FARFETCHD", "MR_MIME" }
local ALIASES = { FARFETCHD = "FARFETCH_D", MR_MIME = "MR__MIME" }
local INDEXES = { FARFETCHD = 83, MR_MIME = 122 }
local originalVersion, originalPrefix = GameVersion.get(), CacheFs.prefix

local function rawId(id, generation)
  return generation == 2 and ALIASES[id] or id
end

local function dataFor(generation)
  if generation == 3 then
    local data = T.sdk.gen3Data()
    local p = data.gen3Pokemon
    for _, id in ipairs(SPECIES) do
      local index = INDEXES[id]
      for _, key in ipairs({ "_stats", "_types", "_speciesMeta", "_abilities",
          "_learnsets", "_eggMoves", "_evolutions", "_dex" }) do
        p[key][index] = Merge.deepCopy(p[key][151] or {})
      end
      p._names[index] = id == "FARFETCHD" and "FARFETCH'D" or "MR. MIME"
    end
    p._evolutions[83] = { { method = 4, param = 20, target = 122 } }
    data.gen3Trainers.trainers[326].party[1].species = 83
    for _, area in pairs(data.gen3Encounters) do
      area.land.slots[1].species, area.land.slots[2].species = 83, 122
    end
    return data
  end
  local pokemon = {}
  for _, id in ipairs(SPECIES) do
    local raw = rawId(id, generation)
    local row = { id = raw, name = id, dex = INDEXES[id], types = { "NORMAL" },
      baseStats = { hp = 100, attack = 65, defense = 60, speed = 60 },
      catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST",
      spriteFront = "front.png", spriteBack = "back.png", evolutions = {},
      aliasNote = { species = raw, id = raw } }
    if generation == 1 then
      row.baseStats.special = 60
      row.level1Moves, row.learnset, row.frontSize = { "POUND" }, {}, 5
    else
      row.baseStats.specialAttack, row.baseStats.specialDefense = 60, 60
      row.levelMoves, row.picSize = { { level = 1, move = "POUND" } }, 5
    end
    pokemon[raw] = row
  end
  local evolution = { method = generation == 2 and "EVOLVE_LEVEL" or "LEVEL", level = 20 }
  evolution[generation == 2 and "into" or "species"] = rawId("MR_MIME", generation)
  pokemon[rawId("FARFETCHD", generation)].evolutions = { evolution }
  if generation == 2 then
    pokemon.growthRates = { MEDIUM_FAST = {
      numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 } }
  end
  local data = { pokemon = pokemon, maps = {}, text = {}, trainers = {}, encounters = {},
    type_chart = { types = { NORMAL = {} }, matchups = {} },
    moves = { POUND = { id = "POUND", name = "POUND", type = "NORMAL", power = 40,
      accuracy = 100, pp = 35,
      effect = generation == 1 and "NO_ADDITIONAL_EFFECT" or "EFFECT_NORMAL_HIT" } },
    items = { POTION = { id = "POTION", name = "POTION", price = 300 } } }
  local party = { { level = 5, species = rawId("FARFETCHD", generation) } }
  local slots = { { species = rawId("FARFETCHD", generation), level = 5 },
    { species = rawId("MR_MIME", generation), level = 6 } }
  if generation == 1 then
    data.items.POTION.tossable = true
    data.trainers["326"] = { name = "TERRY", parties = { party }, partyNames = { "TERRY" } }
    data.encounters.FR_ROUTE_1 = { grass = { rate = 21, buckets = { 50, 100 }, slots = slots } }
  else
    data.gen2Trainers = { classes = { ["326"] = {
      name = "TERRY", trainers = { { name = "TERRY", party = party } } } } }
    data.gen2Encounters = { grass = { FR_ROUTE_1 = {
      rates = { MORN = 21, DAY = 21, NITE = 21 }, slots = {
        MORN = Merge.deepCopy(slots), DAY = Merge.deepCopy(slots), NITE = Merge.deepCopy(slots) } } } }
    data.gen2Encounters.roamMons = { { species = "FARFETCH_D", level = 40,
      mapGroup = 1, mapNumber = 1 } }
    data.encounters = data.gen2Encounters
  end
  return data
end

local function addMod(files, id, api, body)
  files["mods/" .. id .. "/manifest.json"] = ('{"id":"%s","name":"%s",'
    .. '"version":"1.0.0","api":%d,"games":["all"],"entry":"main.lua"}')
    :format(id, id, api)
  files["mods/" .. id .. "/main.lua"] = body
end

local COMMON = [[
local mod = ...
local content, out = mod.content, mod.exports
local ids = { "FARFETCHD", "MR_MIME" }
local aliases = { FARFETCHD = "FARFETCH_D", MR_MIME = "MR__MIME" }
local function must(value, reason) assert(value ~= nil, reason); return value end
local function slots(row) return row.grass.slots or row.grass.times.DAY.slots end
for _, id in ipairs(ids) do
  assert(content.pokemon:has(id))
  local row = must(content.pokemon:get(id))
  assert(row.id == id and row.baseStats.hp == 100)
  if mod.generation ~= 3 then
    assert(row.native.aliasNote.species == (mod.generation == 2 and aliases[id] or id))
  end
  row.baseStats.hp = 1
  assert(content.pokemon:get(id).baseStats.hp == 100)
end
local counts = {}
for key, row in content.pokemon:each() do
  assert(key ~= "FARFETCH_D" and key ~= "MR__MIME")
  if key == "FARFETCHD" or key == "MR_MIME" then
    counts[key] = (counts[key] or 0) + 1
    assert(row.id == key)
    row.baseStats.hp = 2
  end
end
assert(counts.FARFETCHD == 1 and counts.MR_MIME == 1)
assert(content.pokemon:get("FARFETCHD").baseStats.hp == 100)
local evolution = content.pokemon:get("FARFETCHD").evolutions[1]
assert(evolution.species == "MR_MIME" and evolution.into == nil)
evolution.species = "POISONED"
assert(content.pokemon:get("FARFETCHD").evolutions[1].species == "MR_MIME")
assert(content.trainers:get("326").parties[1][1].species == "FARFETCHD")
local area = content.encounters:get("FR_ROUTE_1")
assert(slots(area)[1].species == "FARFETCHD" and slots(area)[2].species == "MR_MIME")

for index, id in ipairs(ids) do
  local row = content.pokemon:get(id)
  row.native = nil
  local _, reason
  if index == 1 then _, reason = content.pokemon:patch(id, mod.DELETE)
  else _, reason = content.pokemon:remove(id) end
  assert(reason == nil and not content.pokemon:has(id) and content.pokemon:get(id) == nil)
  for key in content.pokemon:each() do assert(key ~= id and key ~= aliases[id]) end
  assert(must(content.pokemon:register(id, row)).id == id)
  assert(content.pokemon:has(id))
end
must(content.pokemon:patch("FARFETCHD", { name = "Friendly Bird", baseStats = { hp = 83 },
  evolutions = { { method = "LEVEL", level = 25, species = "MR_MIME" } } }))
must(content.pokemon:patch("MR_MIME", { name = "Friendly Mime", baseStats = { hp = 122 } }))
local custom = must(content.pokemon:register("MY_SPECIES", {
  name = "MY SPECIES", dex = 200, types = { "NORMAL" },
  baseStats = { hp = 50, attack = 60, defense = 60, speed = 60, special = 60 },
  catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST",
  spriteFront = "front.png", spriteBack = "back.png",
  level1Moves = { "POUND" }, learnset = {}, evolutions = {} }))
out.customIndex = custom.index
must(content.pokemon:patch("MY_SPECIES", { name = "FARFETCH'D" }))
local replacement = content.pokemon:get("MR_MIME")
replacement.native = nil
must(content.pokemon:override("MR_MIME", replacement))
must(content.trainers:patch("326", { parties = { {
  { species = "MR_MIME", level = 7 }, { species = "MY_SPECIES", level = 8 } } } }))
must(content.encounters:patch("FR_ROUTE_1", { grass = { rate = 31, slots = {
  { species = "FARFETCHD", level = 7 }, { species = "MR_MIME", level = 8 } } } }))
assert(content.pokemon:get("MY_SPECIES").id == "MY_SPECIES")
assert(content.pokemon:get("MY_SPECIES").name == "FARFETCH'D")
assert(content.trainers:get("326").parties[1][1].species == "MR_MIME")
assert(content.trainers:get("326").parties[1][2].species == "MY_SPECIES")
assert(slots(content.encounters:get("FR_ROUTE_1"))[2].species == "MR_MIME")
if mod.generation == 2 then
  local roamers = must(content.encounters:get("roamMons"))
  assert(roamers.entries[1].species == "FARFETCHD")
  must(content.encounters:patch("roamMons", { kind = "roamMons", entries = {
    { species = "MR_MIME", level = 41, mapGroup = 1, mapNumber = 1 } } }))
  assert(content.encounters:get("roamMons").entries[1].species == "MR_MIME")
end

for _, version in ipairs({ "red", "gold" }) do
  local view = must(mod.datasets:open(version))
  local registry = view.content.pokemon
  for _, id in ipairs(ids) do
    local row = must(registry:get(id))
    assert(registry:has(id) and row.id == id)
    assert(row.baseStats.hp == (version == "red" and 41 or 42))
    row.baseStats.hp = 1
  end
  local seen = {}
  for key, row in registry:each() do
    assert(key ~= "FARFETCH_D" and key ~= "MR__MIME")
    if key == "FARFETCHD" or key == "MR_MIME" then
      seen[key] = (seen[key] or 0) + 1
      assert(row.id == key)
      row.baseStats.hp = 2
    end
  end
  assert(seen.FARFETCHD == 1 and seen.MR_MIME == 1)
  assert(registry:get("FARFETCHD").evolutions[1].species == "MR_MIME")
  assert(registry:get("FARFETCHD").baseStats.hp == (version == "red" and 41 or 42))
end
assert(content.pokemon:get("FARFETCHD").baseStats.hp == 83)
out.live = function(id) return content.pokemon:get(id) end
out.frozen = {
  function() content.pokemon:patch("FARFETCHD", { name = "FROZEN" }) end,
  function() content.pokemon:remove("MR_MIME") end,
  function() content.pokemon:override("MR_MIME", replacement) end,
  function()
    local row = content.pokemon:get("MY_SPECIES")
    row.id, row.index, row.native = "AFTER_LOAD", nil, nil
    content.pokemon:register("AFTER_LOAD", row)
  end,
}
mod.events:on("pokemon.evolved", function(ev)
  out.eventFrom, out.eventTo = ev.fromSpecies, ev.toSpecies
  out.eventMon = ev.mon.species
  ev.fromSpecies, ev.mon.species = "POISONED", "POISONED"
end)
mod.hooks:wrap("encounter.species", function(next, encounter, context)
  out.before = encounter.species
  if out.target then encounter.species = out.target end
  local result, middle, tail = next(encounter, context)
  out.after = result.species
  return result, middle, tail
end)
out.done = true
]]

local FAILURE = [[
local mod = ...
for _, id in ipairs({ "FARFETCHD", "MR_MIME" }) do
  local row = assert(mod.content.pokemon:get(id))
  row.native, row.name = nil, "ROLLBACK"
  local _, reason = mod.content.pokemon:remove(id)
  assert(reason == nil and not mod.content.pokemon:has(id))
  assert(mod.content.pokemon:register(id, row))
  assert(mod.content.pokemon:patch(id, { baseStats = { hp = 1 } }))
end
assert(mod.content.pokemon:patch("FARFETCHD", {
  evolutions = { { method = "LEVEL", level = 99, species = "MY_SPECIES" } } }))
assert(mod.content.trainers:patch("326", { parties = { { { species = "FARFETCHD", level = 99 } } } }))
assert(mod.content.encounters:patch("FR_ROUTE_1", { grass = {
  slots = { { species = "MY_SPECIES", level = 99 } } } }))
if mod.generation == 2 then
  assert(mod.content.encounters:patch("roamMons", { kind = "roamMons", entries = {
    { species = "FARFETCHD", level = 99, mapGroup = 1, mapNumber = 1 } } }))
end
error("intentional identifier rollback")
]]

local LEGACY = [[
local mod = ...
local raw = mod.generation == 2 and "FARFETCH_D" or "FARFETCHD"
local row = assert(mod.content.pokemon:get(raw))
assert(row.id == raw and row.baseStats.hp == 83)
if mod.generation == 2 then
  assert(mod.content.pokemon:get("FARFETCHD") == nil)
  assert(row.evolutions[1].into == "MR__MIME")
end
mod.exports.done = true
]]

local OBSERVER = [[
local mod = ...
local bird, mime = mod.content.pokemon:get("FARFETCHD"), mod.content.pokemon:get("MR_MIME")
assert(bird.id == "FARFETCHD" and bird.name == "Friendly Bird" and bird.baseStats.hp == 83)
assert(mime.id == "MR_MIME" and mime.name == "Friendly Mime" and mime.baseStats.hp == 122)
assert(bird.evolutions[1].species == "MR_MIME" and bird.evolutions[1].level == 25)
assert(mod.content.trainers:get("326").parties[1][1].species == "MR_MIME")
local grass = mod.content.encounters:get("FR_ROUTE_1").grass
assert((grass.slots or grass.times.DAY.slots)[2].species == "MR_MIME")
if mod.generation == 2 then
  local roamer = mod.content.encounters:get("roamMons").entries[1]
  assert(roamer.species == "MR_MIME" and roamer.level == 41)
end
mod.exports.done = true
]]

do
  local source = { id = "FARFETCH_D", species = "MR__MIME", item = "FARFETCH_D",
    label = "MR__MIME", nested = { id = "MR__MIME", into = "FARFETCH_D",
      fromSpecies = "FARFETCH_D", toSpecies = "MR__MIME", deleted = Merge.DELETE },
    native = { species = "FARFETCH_D", id = "MR__MIME" } }
  source.self = source
  local view = Ids.record(source, 2, false, nil, true)
  T.eq(view.id, "FARFETCHD", "helper canonical root species ID")
  T.eq(view.species, "MR_MIME", "helper canonical species reference")
  T.eq(view.nested.into, "FARFETCHD", "helper canonical into reference")
  T.eq(view.nested.fromSpecies, "FARFETCHD", "helper canonical evolution source")
  T.eq(view.nested.toSpecies, "MR_MIME", "helper canonical evolution target")
  T.eq(view.nested.id, "MR__MIME", "helper leaves unrelated nested IDs intact")
  T.eq(view.item, "FARFETCH_D", "helper leaves item IDs intact")
  T.eq(view.label, "MR__MIME", "helper leaves arbitrary strings intact")
  T.eq(view.nested.deleted, Merge.DELETE, "helper preserves DELETE identity")
  T.check(view.self == view and view ~= source, "helper preserves detached cycles")
  T.same(view.native, source.native, "helper skips native metadata conversion")
  view.native.species = "POISONED"
  T.eq(source.native.species, "FARFETCH_D", "helper detaches native metadata")
  local native = Ids.record(view, 2, true, function(id)
    return id == "FARFETCH_D" or id == "MR__MIME"
  end, true)
  T.eq(native.id, "FARFETCH_D", "helper restores native root ID")
  T.eq(native.species, "MR__MIME", "helper restores native species reference")
  T.eq(native.nested.into, "FARFETCH_D", "helper restores native into reference")
  T.eq(Ids.native("FARFETCHD", "species", 2, function() return false end), "FARFETCHD",
    "helper retains custom canonical key when native alias never existed")
  T.eq(Ids.native("MR_MIME", "species", 2), "MR__MIME", "helper runtime alias lookup")
  T.eq(Ids.canonical("MY_SPECIES", "species", 2), "MY_SPECIES", "helper preserves custom species")
  for _, kind in ipairs({ "move", "item" }) do
    T.eq(Ids.canonical("FARFETCH_D", kind, 2), "FARFETCH_D", "helper preserves " .. kind .. " IDs")
  end
  for _, generation in ipairs({ 1, 3 }) do
    T.eq(Ids.canonical("MR__MIME", "species", generation), "MR__MIME",
      "helper does not infer aliases outside Gen 2")
  end
end

for _, version in ipairs(VERSIONS) do
  GameVersion.set(version)
  CacheFs.prefix = GameVersion.cachePrefix(version)
  local generation = GameVersion.generation(version)
  local data, files = dataFor(generation), {}
  for _, dataset in ipairs({ "red", "gold" }) do
    local gen = GameVersion.generation(dataset)
    local fixture = dataFor(gen)
    for _, id in ipairs(SPECIES) do fixture.pokemon[rawId(id, gen)].baseStats.hp = 40 + gen end
    Fixture.cache(files, dataset, fixture)
  end
  addMod(files, "a_common", 3, COMMON)
  addMod(files, "b_failure", 3, FAILURE)
  addMod(files, "c_legacy", 2, LEGACY)
  addMod(files, "d_observer", 3, OBSERVER)
  T.sdk.captureRuntime()
  local loader = Loader.new({ fs = T.sdk.memfs(files), dev = true,
    generation = generation, version = version })
  loader.game = { data = data, generation = generation, phase = "field" }
  local called, result = pcall(loader.load, loader, data)
  T.check(called, version .. " Loader completes: " .. tostring(result))
  T.eq(result, false, version .. " intentional failed owner makes load incomplete")
  T.eq(#loader.errors, 1, version .. " only the intentional rollback fails")
  T.check(tostring(loader.errors[1]):find("intentional identifier rollback", 1, true) ~= nil,
    version .. " failure reaches the intended rollback point")
  T.same(loader.order, { "a_common", "c_legacy", "d_observer" },
    version .. " independent owners load in order")
  T.check(loader.exports.c_legacy and loader.exports.c_legacy.done, version .. " API 2 reads native IDs")
  T.check(loader.exports.d_observer and loader.exports.d_observer.done, version .. " observer sees rollback")
  T.eq(loader.exports.b_failure, nil, version .. " failed owner exports disappear")
  local out = loader.exports.a_common
  T.check(out and out.done, version .. " identical body completed")
  for _, registry in pairs(loader.content) do
    T.eq(registry.frozen, true, version .. " registry freezes after failed owner")
    for _, operations in pairs(registry.ops) do
      for _, operation in ipairs(operations) do
        T.neq(operation.owner, "b_failure", version .. " rollback removes failed owner's operations")
      end
    end
  end
  if out and out.done then
    for index, mutate in ipairs(out.frozen) do
      T.raises(mutate, "frozen after load", version .. " frozen species mutation " .. index)
    end
    T.eq(out.live("FARFETCHD").name, "Friendly Bird", version .. " frozen patch leaves species intact")
    T.eq(out.live("MR_MIME").baseStats.hp, 122, version .. " frozen remove and override leave species intact")
    local customNative = generation == 3 and out.customIndex or "MY_SPECIES"
    for _, id in ipairs(SPECIES) do
      local raw = generation == 3 and INDEXES[id] or rawId(id, generation)
      if generation == 2 then
        T.eq(loader.content.pokemon.ops[id], nil, version .. " no parallel canonical operation key " .. id)
        T.eq(data.pokemon[id], nil, version .. " no parallel canonical native row " .. id)
        T.check(loader.content.pokemon.ops[raw] ~= nil, version .. " resurrection logs use native key " .. raw)
      end
      local mon = { species = raw, moves = {}, stats = { hp = 20 }, hp = 20, level = 5 }
      local original = Merge.deepCopy(mon)
      local view = Records.mon(mon, generation, data, version)
      T.eq(view.species, id, version .. " runtime canonical read " .. id)
      T.eq(view.native.species, raw, version .. " runtime native metadata remains raw " .. id)
      T.eq(Records.applyMon(mon, view, generation, data, version), true,
        version .. " unchanged record applies " .. id)
      T.same(mon, original, version .. " unchanged record preserves native representation " .. id)
      view.stats.hp, view.native.species = 1, "POISONED"
      T.same(mon, original, version .. " runtime nested records are detached " .. id)
      T.eq(Records.applyMon(mon, { species = "MY_SPECIES" }, generation, data, version), true,
        version .. " custom species write after display rename")
      T.eq(mon.species, customNative, version .. " custom native identity survives rename")
      T.eq(Records.mon(mon, generation, data, version).species, "MY_SPECIES",
        version .. " custom canonical identity survives rename")
      T.eq(Records.applyMon(mon, { species = id }, generation, data, version), true,
        version .. " canonical species write " .. id)
      T.eq(mon.species, raw, version .. " canonical write returns to same native key " .. id)
      local saved = generation == 3 and loader.game.session or loader.game.save
      if not saved then
        saved = { party = {} }
        loader.game[generation == 3 and "session" or "save"] = saved
      end
      saved.party = { mon }
      local world = UnifiedWorld.new(function() return loader.game end, generation, version, "a_common")
      local party = world:party()
      T.eq(party[1].species, id, version .. " world party canonical species " .. id)
      party[1].species, party[1].native.species = "POISONED", "POISONED"
      T.eq(mon.species, raw, version .. " world party record is detached " .. id)
    end
    local far = generation == 3 and 83 or rawId("FARFETCHD", generation)
    local mime = generation == 3 and 122 or rawId("MR_MIME", generation)
    local event = { fromSpecies = far, toSpecies = mime,
      mon = { species = far, moves = {}, stats = { hp = 20 }, hp = 20, level = 5 } }
    local originalEvent = Merge.deepCopy(event)
    Runtime.emit("pokemon.evolved", event)
    T.eq(out.eventFrom, "FARFETCHD", version .. " callback source species is canonical")
    T.eq(out.eventTo, "MR_MIME", version .. " callback target species is canonical")
    T.eq(out.eventMon, "FARFETCHD", version .. " callback mon species is canonical")
    T.same(event, originalEvent, version .. " notification records are detached")
    local encounter = { species = far, level = 5 }
    for _, target in ipairs({ false, "MR_MIME", "FARFETCHD" }) do
      out.target = target
      local before, calls, dispatched = encounter.species, 0
      local value, middle, tail = Runtime.call("encounter.species", function(row)
        calls, dispatched = calls + 1, row.species
        return row, nil, "tail"
      end, encounter, {})
      local expected = target == "MR_MIME" and mime or far
      T.eq(calls, 1, version .. " callback calls native continuation once")
      T.eq(out.before, before == far and "FARFETCHD" or "MR_MIME",
        version .. " callback input is canonical")
      T.eq(dispatched, expected, version .. " callback dispatch uses native species")
      T.eq(value.species, expected, version .. " callback writes and restores native species")
      T.eq(out.after, target or "FARFETCHD", version .. " callback return is canonical")
      T.eq(middle, nil, version .. " callback preserves nil middle result")
      T.eq(tail, "tail", version .. " callback preserves trailing result")
      encounter = value
    end
    local nativeTrainer, nativeSlots, evolution
    if generation == 3 then
      T.eq(data.gen3Pokemon._stats[83].hp, 83, version .. " native numeric bird stats")
      T.eq(data.gen3Pokemon._stats[122].hp, 122, version .. " native numeric mime stats")
      evolution = data.gen3Pokemon._evolutions[83][1].target
      nativeTrainer = data.gen3Trainers.trainers[326].party
      nativeSlots = data.gen3Encounters.FR_ROUTE_1.land.slots
      T.eq(data.gen3Pokemon.modRecords.MY_SPECIES.index, out.customIndex,
        version .. " registered custom numeric identity remains stable")
    else
      T.eq(data.pokemon[far].id, far, version .. " native bird root ID")
      T.eq(data.pokemon[mime].id, mime, version .. " native mime root ID")
      T.eq(data.pokemon[far].baseStats.hp, 83, version .. " native bird stats after rollback")
      T.eq(data.pokemon[mime].baseStats.hp, 122, version .. " native mime stats after rollback")
      local row = data.pokemon[far].evolutions[1]
      evolution = generation == 2 and row.into or row.species
      if generation == 1 then
        nativeTrainer = data.trainers["326"].parties[1]
        nativeSlots = data.encounters.FR_ROUTE_1.grass.slots
      else
        nativeTrainer = data.gen2Trainers.classes["326"].trainers[1].party
        nativeSlots = data.gen2Encounters.grass.FR_ROUTE_1.slots.DAY
        T.eq(data.gen2Encounters.roamMons[1].species, mime, version .. " native roamer species after rollback")
        T.eq(data.gen2Encounters.roamMons[1].level, 41, version .. " native roamer level after rollback")
      end
    end
    T.eq(evolution, mime, version .. " native evolution reference after rollback")
    T.eq(nativeTrainer[1].species, mime, version .. " native trainer species reference")
    T.eq(nativeTrainer[2].species, customNative, version .. " native trainer custom reference")
    T.eq(nativeSlots[1].species, far, version .. " native encounter bird reference")
    T.eq(nativeSlots[2].species, mime, version .. " native encounter mime reference")

    if generation ~= 3 then
      local game = loader.game
      local native = require(generation == 1 and "src.world.WorldAPI" or "src.world.gen2.WorldAPI")
        .new(game, "a_common")
      local world = UnifiedWorld.new(function() return game end, generation, version, "a_common")
      local opts = generation == 2 and { daytime = "DAY" } or nil
      local raw = native:effectiveEncounters("FR_ROUTE_1", "grass", opts)
      local preview = world:effectiveEncounters("FR_ROUTE_1", "grass", opts)
      T.eq(preview.chance, 31 / 256, version .. " encounter chance remains native")
      T.check((raw.dist[far] or 0) > 0 and (raw.dist[mime] or 0) > 0,
        version .. " native preview includes both species with positive weight")
      T.eq(preview.dist.FARFETCHD, raw.dist[far], version .. " canonical bird encounter weight")
      T.eq(preview.dist.MR_MIME, raw.dist[mime], version .. " canonical mime encounter weight")
      if generation == 2 then
        T.eq(preview.dist.FARFETCH_D, nil, version .. " preview omits raw bird key")
        T.eq(preview.dist.MR__MIME, nil, version .. " preview omits raw mime key")
        local captured
        game.stack = { top = function() return nil end }
        game.world = { map = { id = "FR_ROUTE_1" }, acceptsMenuInput = function() return true end,
          startBattle = function(_, args) captured = args.wild; return true end }
        for _, id in ipairs({ "FARFETCHD", "MR_MIME", "MY_SPECIES" }) do
          local ok, reason = world:startWildBattle(id, 7)
          T.eq(ok, true, version .. " canonical wild dispatch: " .. tostring(reason))
          if ok then
            T.eq(captured.species, rawId(id, generation), version .. " real wild mon uses native key " .. id)
            T.eq(captured.level, 7, version .. " real wild mon keeps requested level")
            T.check(captured.stats.hp > 0 and #captured.moves > 0, version .. " real wild mon has stats and moves")
            T.eq(game.save.pokedex.seen[rawId(id, generation)], true, version .. " Pokedex writes native key " .. id)
          end
        end
        T.eq(game.save.pokedex.seen.FARFETCHD, nil, version .. " no canonical bird key leaks into save")
        T.eq(game.save.pokedex.seen.MR_MIME, nil, version .. " no canonical mime key leaks into save")
      end
    end
  end
  T.eq(GameVersion.get(), version, version .. " dataset reads retain active version")
  T.eq(CacheFs.prefix, GameVersion.cachePrefix(version), version .. " dataset reads retain cache prefix")
  T.sdk.restoreRuntime()
end

GameVersion.set(originalVersion)
CacheFs.prefix = originalPrefix
T.finish("unified_identifiers")
