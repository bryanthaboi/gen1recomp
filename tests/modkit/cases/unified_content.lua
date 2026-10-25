package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Fixture = require("tests.modkit.dataset_view_fixture")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local Merge = require("src.mods.Merge")
local Records = require("src.mods.UnifiedRecords")
local Schemas = require("src.mods.Schemas")
local TextIR = require("src.core.game3.scripting.text_ir")
local Logger = require("src.core.Logger")

local VERSIONS = { "red", "blue", "yellow", "gold", "silver", "crystal",
  "firered", "leafgreen", "ruby", "sapphire", "emerald" }
local SOURCE = "{PLAYER}\\n{RIVAL}\\p{STR_VAR_1}\\lEND 100%"
local RAW_SOURCE = "{PLAYER}\n{RIVAL}\f{STR_VAR_1}\vEND 100%"
local REPLACEMENT = "{RIVAL}\\n{PLAYER}\\p{STR_VAR_2}\\lDONE 50%"
local RAW_REPLACEMENT = "{RIVAL}\n{PLAYER}\f{STR_VAR_2}\vDONE 50%"

local function dataFor(generation)
  local data
  if generation == 3 then
    data = T.sdk.gen3Data()
    data.gen3Text.CommonText = TextIR.fromAscii(SOURCE)
    data.gen3Text.BadControl = { { t = "ext", cmd = 1, args = { 2 } }, { t = "eos" } }
    data.gen3RomText = { CommonText = TextIR.fromAscii(SOURCE) }
    data.gen3Items._byId[13].description = "OPTIONAL"
    data.gen3Pokemon._battleMoves = Merge.deepCopy(data.gen3Moves._rom)
    for offset, id in ipairs({ "REMOVED", "DELETED" }) do
      local species, move, item = 148 + offset, 118 + offset, 118 + offset
      local p = data.gen3Pokemon
      for _, key in ipairs({ "_stats", "_types", "_speciesMeta", "_abilities",
          "_learnsets", "_eggMoves", "_evolutions", "_dex" }) do
        p[key][species] = Merge.deepCopy(p[key][151] or {})
      end
      p._names[species] = id .. " MON"
      p._moveNames[move] = id .. " HIT"
      data.gen3Moves._rom[move] = Merge.deepCopy(data.gen3Moves._rom[1])
      p._battleMoves[move] = Merge.deepCopy(data.gen3Moves._rom[1])
      data.gen3Items._byId[item] = { name = id .. " ITEM", price = 1, pocket = "ITEMS" }
    end
    return data
  end
  local mon = { id = "MEW", name = "MEW", dex = 151, types = { "PSYCHIC" },
    baseStats = { hp = 100, attack = 100, defense = 100, speed = 100 },
    catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST",
    spriteFront = "front.png", spriteBack = "back.png", evolutions = {} }
  if generation == 1 then
    mon.baseStats.special = 100
    mon.level1Moves, mon.learnset, mon.frontSize = { "POUND" }, {}, 5
  else
    mon.baseStats.specialAttack, mon.baseStats.specialDefense = 100, 100
    mon.levelMoves, mon.picSize = { { level = 1, move = "POUND" } }, 5
  end
  local effect = generation == 1 and "NO_ADDITIONAL_EFFECT" or "EFFECT_NORMAL_HIT"
  local pokemon = { MEW = mon }
  if generation == 2 then
    pokemon.growthRates = { MEDIUM_FAST = {
      numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 } }
  end
  data = { pokemon = pokemon,
    moves = { POUND = { id = "POUND", name = "POUND", type = "NORMAL",
      power = 40, accuracy = 100, pp = 35, effect = effect } },
    items = { POTION = { id = "POTION", name = "POTION", price = 300 } },
    maps = {}, type_chart = { types = { NORMAL = {}, PSYCHIC = {} }, matchups = {} },
    text = { CommonText = RAW_SOURCE, BadControl = "\252\1\2" },
    trainers = {}, encounters = {} }
  if generation == 1 then data.items.POTION.tossable = true
  else
    data.items.POTION.description = "OPTIONAL"
    data.gen2Text = Merge.deepCopy(data.text)
  end
  for _, prefix in ipairs({ "REMOVED", "DELETED" }) do
    local row = Merge.deepCopy(mon)
    row.id, row.name = prefix .. "_MON", prefix .. " MON"
    pokemon[row.id] = row
    row = Merge.deepCopy(data.moves.POUND)
    row.id, row.name = prefix .. "_HIT", prefix .. " HIT"
    data.moves[row.id] = row
    data.items[prefix .. "_ITEM"] = { id = prefix .. "_ITEM", name = prefix .. " ITEM", price = 1 }
  end
  local party = { { level = 5, species = "MEW" } }
  if generation == 1 then
    data.trainers["326"] = { name = "TERRY", parties = { party }, partyNames = { "TERRY" } }
    data.encounters.FR_ROUTE_1 = {
      grass = { rate = 21, slots = { { species = "MEW", level = 5 } } } }
  else
    data.gen2Trainers = { classes = { ["326"] = {
      name = "TERRY", trainers = { { name = "TERRY", party = party } } } } }
    data.gen2Encounters = { grass = { FR_ROUTE_1 = {
      rates = { MORN = 21, DAY = 21, NITE = 21 }, slots = {
        MORN = { { species = "MEW", level = 5 } },
        DAY = { { species = "MEW", level = 5 } },
        NITE = { { species = "MEW", level = 5 } } } } } }
  end
  return data
end

local function addMod(files, id, api, body, dependency)
  files["mods/" .. id .. "/manifest.json"] = ('{"id":"%s","name":"%s",'
    .. '"version":"1.0.0","api":%d,"games":["all"],"entry":"main.lua"%s}')
    :format(id, id, api, dependency and ',"dependencies":["' .. dependency .. '"]' or "")
  files["mods/" .. id .. "/main.lua"] = body
end

local function load(files, data, version, rollbackOwner)
  T.sdk.captureRuntime()
  Loader._resetShimWarned()
  local loader = Loader.new({ fs = T.sdk.memfs(files), dev = true,
    generation = GameVersion.generation(version), version = version })
  if rollbackOwner then
    local validateScripts = loader._validateScripts
    loader._validateScripts = function(self)
      validateScripts(self)
      self:_rollback(rollbackOwner)
    end
  end
  local warnings, originalWarn = {}, Logger.warn
  Logger.warn = function(fmt, ...)
    local ok, message = pcall(string.format, fmt, ...)
    warnings[#warnings + 1] = ok and message or tostring(fmt)
    originalWarn(fmt, ...)
  end
  local called, result = pcall(loader.load, loader, data)
  Logger.warn = originalWarn
  T.sdk.restoreRuntime()
  T.check(called, version .. " Loader does not throw: " .. tostring(result))
  return loader, called and result, warnings
end

local LEGACY_BEFORE = [[
local mod = ...
mod.content.moves:patch("POUND", { power = 49 })
mod.content.items:patch("POTION", { price = 222 })
mod.exports.raw = mod.content.pokemon:get("MEW")
]]

local COMMON = [[
local mod = ...
local content = mod.content
local function must(value, reason) assert(value ~= nil, reason); return value end
local function unsupported(value, reason)
  assert(value == nil and type(reason) == "string" and reason:find("unsupported: ", 1, true) == 1,
    tostring(reason))
  return reason
end
local function rejected(fn)
  local ok, value, reason = pcall(fn)
  assert(not ok or (value == nil and type(reason) == "string"), "invalid write accepted")
end
local mew = must(content.pokemon:get("MEW"))
assert(mew.baseStats.hp == 100 and mew.baseStats.special == 100)
if mod.generation == 1 then
  assert(mew.baseStats.specialAttack == nil and mew.baseStats.specialDefense == nil)
else
  assert(mew.baseStats.specialAttack == 100 and mew.baseStats.specialDefense == 100)
end
assert(#mew.level1Moves == 1 and mew.level1Moves[1] == "POUND" and #mew.learnset == 0)
assert(content.moves:get("POUND").effect == "NO_ADDITIONAL_EFFECT")
assert(content.moves:get("POUND").category == "physical")
assert(content.moves:get("POUND").power == 49 and content.items:get("POTION").price == 222)
assert(mod:supports("content", "pokemon") == true)

must(content.moves:register("FIX_HIT", {
  name = "FIX HIT", type = "NORMAL", power = 55, accuracy = 100, pp = 20, effect = "NO_ADDITIONAL_EFFECT" }))
must(content.moves:register("FIX_NEXT", {
  name = "FIX NEXT", type = "NORMAL", power = 65, accuracy = 100, pp = 15, effect = "NO_ADDITIONAL_EFFECT" }))
must(content.items:register("FIX_ITEM", { name = "FIX ITEM", price = 75 }))
local function species(name)
  return { name = name, dex = 200, types = { "NORMAL" },
    baseStats = { hp = 60, attack = 70, defense = 65, speed = 75,
      special = 80 }, catchRate = 45, baseExp = 64,
    growthRate = "MEDIUM_FAST", spriteFront = "front.png", spriteBack = "back.png",
    level1Moves = { "FIX_HIT" }, learnset = {}, evolutions = {}, tmhm = {} }
end
must(content.pokemon:register("FIXMON_B", species("FIXMON B")))
local returned = must(content.pokemon:register("FIXMON_A", species("FIXMON A")))
returned.baseStats.hp = 1
assert(content.pokemon:get("FIXMON_A").baseStats.hp == 60)
must(content.pokemon:patch("FIXMON_B", {
  evolutions = { { method = "LEVEL", level = 20, species = "FIXMON_A" } } }))
must(content.pokemon:patch("FIXMON_A", {
  evolutions = { { method = "LEVEL", level = 21, species = "FIXMON_B" } },
  level1Moves = { "FIX_NEXT" } }))

rejected(function() content.moves:register("POUND", {
  name = "DUPLICATE", type = "NORMAL", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT" }) end)
rejected(function() content.moves:register("BAD_POWER", {
  name = "BAD POWER", type = "NORMAL", power = 999, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT" }) end)
if mod.generation == 3 then
  rejected(function() content.moves:register("COLLIDE_MOVE", {
    name = "COLLIDE MOVE", index = content.moves:get("FIX_HIT").index,
    type = "NORMAL", power = 1, accuracy = 100, pp = 1, effect = "NO_ADDITIONAL_EFFECT" }) end)
  rejected(function() content.items:register("COLLIDE_ITEM", {
    name = "COLLIDE ITEM", price = 1, index = content.items:get("POTION").index }) end)
  rejected(function()
    local row = species("COLLIDE MON"); row.index = content.pokemon:get("MEW").index
    content.pokemon:register("COLLIDE_MON", row)
  end)
  rejected(function()
    local row = species("EGG SLOT"); row.index = 412
    content.pokemon:register("EGG_SLOT", row)
  end)
end
assert(content.moves:get("BAD_POWER") == nil and content.moves:get("POUND").power == 49)
local extension = mew.native or {}
extension.portableWrite = true
local extensionReason = unsupported(content.pokemon:patch("MEW", { native = extension }))
assert(extensionReason == "unsupported: native extensions are read-only")
assert(content.pokemon:get("MEW").native == nil
  or content.pokemon:get("MEW").native.portableWrite == nil)
unsupported(content.pokemon:patch("MEW", { baseStats = { hp = mod.DELETE } }))
assert(content.pokemon:get("MEW").baseStats.hp == 100)
local artwork = unsupported(content.pokemon:patch("MEW", { native = { artwork = "custom.png" } }))
assert(artwork == extensionReason)
if mod.generation == 3 then
  unsupported(content.pokemon:patch("MEW", { trueColor = true }))
  unsupported(content.pokemon:patch("MEW", { frontSize = 5 }))
end

rejected(function()
  content.pokemon:patch("MEW", { baseStats = { special = 109, specialAttack = 110 } })
end)
assert(content.pokemon:get("MEW").baseStats.special == 100)
must(content.pokemon:patch("MEW", { baseStats = { attack = 121, special = 109 },
  learnset = { { level = 9, move = "FIX_HIT" } } }))
must(content.pokemon:patch("MEW", { learnset = {} }))
assert(#content.pokemon:get("MEW").learnset == 0
  and content.pokemon:get("MEW").level1Moves[1] == "POUND")
must(content.pokemon:patch("MEW", { learnset = { { level = 9, move = "FIX_HIT" } } }))
must(content.pokemon:patch("MEW", { learnset = {
  __prepend = { { level = 5, move = "POUND" } },
  __append = { { level = 20, move = "FIX_NEXT" } } } }))
local learned = content.pokemon:get("MEW").learnset
assert(#learned == 3 and learned[1].move == "POUND"
  and learned[2].move == "FIX_HIT" and learned[3].move == "FIX_NEXT")
must(content.pokemon:patch("MEW", { level1Moves = { "FIX_HIT" } }))
must(content.pokemon:patch("MEW", { level1Moves = {
  __prepend = { "POUND" }, __append = { "FIX_NEXT" } } }))
local starting = content.pokemon:get("MEW").level1Moves
assert(#starting == 3 and starting[1] == "POUND"
  and starting[2] == "FIX_HIT" and starting[3] == "FIX_NEXT")
must(content.pokemon:patch("MEW", { level1Moves = mod.DELETE }))
assert(#content.pokemon:get("MEW").level1Moves == 0
  and #content.pokemon:get("MEW").learnset == 3)
must(content.pokemon:patch("MEW", { level1Moves = { "POUND" } }))
must(content.pokemon:patch("MEW", { evolutions = {} }))
assert(#content.pokemon:get("MEW").evolutions == 0)
must(content.pokemon:patch("MEW", {
  evolutions = { { method = "LEVEL", level = 30, species = "FIXMON_A" } } }))
local evolution = content.pokemon:get("MEW").evolutions[1]
assert(evolution.method == "LEVEL" and evolution.species == "FIXMON_A"
  and evolution.level == 30 and evolution.into == nil)
must(content.moves:patch("POUND", { power = 61 }))
must(content.items:patch("POTION", { price = 100 }))
if mod.generation == 1 then
  must(content.items:patch("POTION", { tossable = mod.DELETE }))
  assert(content.items:get("POTION").tossable == nil)
else
  must(content.items:patch("POTION", { description = mod.DELETE }))
  assert(content.items:get("POTION").description == nil)
end

local trainer = must(content.trainers:get("326"))
assert(type(trainer.parties[1][1].species) == "string" and trainer.partyNames[1] == "TERRY")
must(content.trainers:patch("326", { partyNames = { "TERRY" }, parties = { {
  { species = "FIXMON_A", level = 7, moves = { "FIX_HIT", "POUND" } } } } }))
local encounters = must(content.encounters:get("FR_ROUTE_1"))
local initial = encounters.grass.slots
assert(type(initial[1].species) == "string" and type(initial[1].level) == "number")
if mod.generation == 3 then
  assert(type(initial[1].minLevel) == "number" and type(initial[1].maxLevel) == "number")
end
must(content.encounters:patch("FR_ROUTE_1", { grass = { rate = 31,
  slots = { { species = "FIXMON_B", level = 7 } } } }))

for name, id in pairs({ pokemon = "MEW", moves = "POUND", items = "POTION",
    trainers = "326", encounters = "FR_ROUTE_1" }) do
  local row = must(content[name]:get(id))
  row.name, row.portableWrite = "POISONED", true
  if name == "pokemon" then row.baseStats.attack = 1; row.learnset[1].move = "POISONED" end
  if name == "trainers" then row.parties[1][1].species = "POISONED" end
  if name == "encounters" then
    local slots = row.grass.slots or row.grass.times.DAY.slots
    slots[1].species = "POISONED"
  end
  local found = false
  for key, value in content[name]:each() do
    assert(key ~= "growthRates" and key ~= "tmhmMoves" and key ~= "tutorMoves" and key ~= "generation" and key ~= "source")
    if key == id then
      found = true; value.portableWrite = true
      if name == "pokemon" then value.baseStats.attack = 2 end
      if name == "moves" then value.power = 0 end
      if name == "items" then value.price = 0 end
      if name == "trainers" then value.parties[1][1].species = "POISONED" end
      if name == "encounters" then
        local slots = value.grass.slots or value.grass.times.DAY.slots
        slots[1].species = "POISONED"
      end
    end
  end
  assert(found and content[name]:get(id).portableWrite == nil
    and content[name]:get(id).name ~= "POISONED")
end
assert(content.pokemon:get("MEW").baseStats.attack == 121)
assert(content.pokemon:get("MEW").learnset[1].move == "POUND")
assert(content.moves:get("POUND").power == 61 and content.items:get("POTION").price == 100)
assert(content.trainers:get("326").parties[1][1].species == "FIXMON_A")
local area = content.encounters:get("FR_ROUTE_1").grass
assert((area.slots or area.times.DAY.slots)[1].species == "FIXMON_B")

for name, suffix in pairs({ pokemon = "MON", moves = "HIT", items = "ITEM" }) do
  local _, reason = content[name]:remove("REMOVED_" .. suffix)
  assert(reason == nil and not content[name]:has("REMOVED_" .. suffix))
  local _, deleteReason = content[name]:patch("DELETED_" .. suffix, mod.DELETE)
  assert(deleteReason == nil and not content[name]:has("DELETED_" .. suffix))
end

assert(content.text:get("CommonText") == "{PLAYER}\n{RIVAL}\f{STR_VAR_1}\vEND 100%")
must(content.text:override("CommonText", "{RIVAL}\n{PLAYER}\f{STR_VAR_2}\vDONE 50%"))
assert(content.text:get("CommonText") == "{RIVAL}\n{PLAYER}\f{STR_VAR_2}\vDONE 50%")
unsupported(content.text:register("BAD_WRITE", "\252\1\2"))
assert(not content.text:has("BAD_WRITE"))
local controlOk, controlReason = pcall(content.text.get, content.text, "BadControl")
assert(not controlOk and tostring(controlReason):find("unsupported: ", 1, true))
local romAvailable, romReason = content.rom_text:supports()
if romAvailable then
  assert(content.rom_text:get("CommonText") == "{PLAYER}\n{RIVAL}\f{STR_VAR_1}\vEND 100%")
  must(content.rom_text:override("CommonText", "{RIVAL}\\n{PLAYER}\\p{STR_VAR_2}\\lDONE 50%"))
else
  assert(unsupported(content.rom_text:get("CommonText")) == romReason)
end
local available = mod:supports("content", "evolution_methods")
assert(available == true)
must(content.evolution_methods:register("PORTABLE", { check = function() return false end }))
assert(type(content.evolution_methods:get("PORTABLE").check) == "function")

for _, version in ipairs({ "red", "gold" }) do
  local view = must(mod.datasets:open(version))
  local registry = view.content.pokemon
  assert(view.generation == (version == "red" and 1 or 2))
  local row = must(registry:get("FIXMON"))
  assert(row.baseStats.special == 65 and type(row.level1Moves) == "table"
    and type(row.learnset) == "table")
  if view.generation == 1 then
    assert(row.baseStats.specialAttack == nil and row.baseStats.specialDefense == nil)
  else
    assert(row.baseStats.specialAttack == 65 and row.baseStats.specialDefense == 65)
  end
  row.baseStats.special = 1
  for _, value in registry:each() do value.baseStats.special = 2 end
  assert(registry:get("FIXMON").baseStats.special == 65)
  assert(registry.register == nil and registry.patch == nil
    and registry.override == nil and registry.remove == nil)
  assert(not registry:has("growthRates"))
end
mod.exports.mew = content.pokemon:get("MEW")
mod.exports.a, mod.exports.b = content.pokemon:get("FIXMON_A"), content.pokemon:get("FIXMON_B")
mod.exports.hit, mod.exports.nextHit = content.moves:get("FIX_HIT"), content.moves:get("FIX_NEXT")
mod.exports.item = content.items:get("FIX_ITEM")
mod.exports.price = content.items:get("POTION").price
mod.exports.liveMove = function() return content.moves:get("POUND") end
mod.exports.liveText = function() return content.text:get("CommonText") end
mod.exports.frozen = {
  function() content.items:patch("POTION", { price = 1 }) end,
  function() content.items:override("POTION", { name = "POTION", price = 1 }) end,
  function() content.items:register("AFTER_LOAD", { name = "AFTER LOAD", price = 1 }) end,
  function() content.items:remove("POTION") end,
}
mod.exports.done = true
]]

local LEGACY_AFTER = [[
local mod = ...
mod.content.moves:patch("POUND", { power = 73 })
mod.content.items:patch("POTION", { price = 321 })
mod.exports.raw = mod.content.pokemon:get("MEW")
mod.exports.text = mod.content.text:get("CommonText")
]]

local SURVIVOR = [[
local mod = ...
assert(mod.content.moves:patch("POUND", { power = 54 }))
assert(mod.content.items:patch("POTION", { price = 210 }))
mod.exports.marker = "survived"
]]

local FAILURE = [[
local mod = ...
assert(mod.content.items:register("ROLLBACK_ITEM", { name = "ROLLBACK ITEM", price = 1 }))
assert(mod.content.moves:register("ROLLBACK_HIT", {
  name = "ROLLBACK HIT", type = "NORMAL", power = 5, accuracy = 100, pp = 5, effect = "NO_ADDITIONAL_EFFECT" }))
assert(mod.content.pokemon:register("ROLLBACK_MON", {
  name = "ROLLBACK MON", dex = 201, types = { "NORMAL" },
  baseStats = { hp = 50, attack = 50, defense = 50, speed = 50,
    special = 50 }, catchRate = 45, baseExp = 64,
  growthRate = "MEDIUM_FAST", spriteFront = "front.png", spriteBack = "back.png",
  level1Moves = { "ROLLBACK_HIT" }, learnset = {}, evolutions = {} }))
assert(mod.content.moves:patch("POUND", { power = 250 }))
assert(mod.content.items:patch("POTION", { price = 999 }))
local _, reason = mod.content.pokemon:remove("REMOVED_MON")
assert(reason == nil)
assert(mod.content.text:override("CommonText", "ROLLBACK"))
mod.exports.marker = "must disappear"
error("intentional content rollback")
]]

local OBSERVER = [[
local mod = ...
assert(mod.content.moves:get("POUND").power == 54)
assert(mod.content.items:get("POTION").price == 210)
assert(mod.content.pokemon:has("REMOVED_MON"))
assert(not mod.content.pokemon:has("ROLLBACK_MON"))
assert(not mod.content.moves:has("ROLLBACK_HIT"))
assert(not mod.content.items:has("ROLLBACK_ITEM"))
assert(mod.content.text:get("CommonText") == "{PLAYER}\n{RIVAL}\f{STR_VAR_1}\vEND 100%")
mod.exports.done = true
]]

local PARTITION_OWNER = [[
local mod = ...
assert(mod.content.pokemon:patch("MEW", { level1Moves = { __append = { "POUND" } } }))
assert(mod.content.trainers:patch("326", { parties = { {
  { species = "MEW", level = 5 }, { species = "MEW", level = 7 } } } }))
]]

local PARTITION_SURVIVOR = [[
local mod = ...
assert(#mod.content.pokemon:get("MEW").level1Moves == 2)
assert(#mod.content.trainers:get("326").parties[1] == 2)
assert(mod.content.pokemon:patch("MEW", { learnset = { { level = 9, move = "POUND" } } }))
assert(mod.content.trainers:patch("326", { partyNames = { "SURVIVOR" } }))
mod.exports.done = true
]]

local function nativeChecks(data, generation, out, version)
  local label = version .. " native "
  if generation == 3 then
    local p = data.gen3Pokemon
    local a, b = out.a.index, out.b.index
    local hit, nextHit, item = out.hit.index, out.nextHit.index, out.item.index
    T.check(a ~= b and a ~= 412 and b ~= 412, label .. "species indexes are distinct and avoid egg")
    T.check(hit ~= nextHit and hit ~= 1, label .. "move indexes avoid existing and staged rows")
    T.neq(item, 13, label .. "item index avoids the existing row")
    T.eq(p._stats[151].atk, 121, label .. "stats write uses atk")
    T.eq(p._stats[151].spa, 109, label .. "common special writes special attack")
    T.eq(p._stats[151].spd, 109, label .. "common special writes special defense")
    T.eq(p._stats[a].spa, 80, label .. "registered common special attack")
    T.eq(p._stats[a].spd, 80, label .. "registered common special defense")
    T.same(p._learnsets[151], { { 1, 1 }, { 5, 1 }, { 9, hit }, { 20, nextHit } }, label .. "learnset IDs are numeric")
    T.same(p._learnsets[a], { { 1, nextHit } }, label .. "staged move reference is numeric")
    T.eq(p._evolutions[a][1].target, b, label .. "forward evolution reference")
    T.eq(p._evolutions[b][1].target, a, label .. "reverse evolution reference")
    T.eq(p._evolutions[151][1].target, a, label .. "base species evolves into staged species")
    T.eq(Schemas.gen3View.speciesNum(p, "FIXMON_A"), a, label .. "species name cache")
    T.eq(Schemas.gen3View.moveNum(data.gen3Moves, "FIX_HIT"), hit, label .. "move name cache")
    T.eq(Schemas.gen3View.itemNum(data.gen3Items, "FIX_ITEM"), item, label .. "item name cache")
    T.eq(data.gen3Moves._rom[1].power, 73, label .. "mixed API move stacking")
    T.eq(data.gen3Moves._rom[hit].effect, 0, label .. "Gen 1 effect maps to native hit")
    T.eq(p._battleMoves[1].power, 73, label .. "battle move view follows ROM row")
    T.eq(data.gen3Items._byId[13].price, 321, label .. "mixed API item stacking")
    T.eq(data.gen3Items._byId[13].description, nil, label .. "optional DELETE reaches backing row")
    T.eq(data.gen3Items._byId[item].price, 75, label .. "new item reaches backing row")
    local trainer = data.gen3Trainers.trainers[326].party[1]
    T.eq(trainer.species, a, label .. "trainer species is numeric")
    T.same(trainer.moves, { hit, 1, 0, 0 }, label .. "trainer move IDs retain native four-slot shape")
    T.eq(data.gen3Encounters.FR_ROUTE_1.land.slots[1].species, b, label .. "encounter species is numeric")
    T.eq(data.gen3Encounters.FR_ROUTE_1.land.slots[1].minLevel, 7, label .. "level writes range minimum")
    T.eq(data.gen3Encounters.FR_ROUTE_1.land.slots[1].maxLevel, 7, label .. "level writes range maximum")
    T.eq(data.gen3Encounters["3:19"].land.slots[1].species, b, label .. "encounter alias follows patch")
    for offset, prefix in ipairs({ "REMOVED", "DELETED" }) do
      local species, index = 148 + offset, 118 + offset
      for _, key in ipairs({ "_names", "_stats", "_types", "_speciesMeta", "_abilities",
          "_learnsets", "_eggMoves", "_evolutions", "_dex" }) do
        T.eq(p[key][species], nil, label .. prefix .. " clears " .. key)
      end
      T.eq(data.gen3Moves._rom[index], nil, label .. prefix .. " clears move ROM row")
      T.eq(p._battleMoves[index], nil, label .. prefix .. " clears battle move row")
      T.eq(p._moveNames[index], nil, label .. prefix .. " clears move name")
      T.eq(data.gen3Items._byId[index], nil, label .. prefix .. " clears item row")
      T.eq(Schemas.gen3View.speciesNum(p, prefix .. "_MON"), nil, label .. prefix .. " species cache removed")
      T.eq(Schemas.gen3View.moveNum(data.gen3Moves, prefix .. "_HIT"), nil, label .. prefix .. " move cache removed")
      T.eq(Schemas.gen3View.itemNum(data.gen3Items, prefix .. "_ITEM"), nil, label .. prefix .. " item cache removed")
    end
    T.eq(TextIR.toSource(data.gen3Text.CommonText, nil,
      { named = true, nl = "\\n", para = "\\p", scroll = "\\l" }),
      REPLACEMENT:gsub("%%", "%%%%"), label .. "text keeps placeholders and controls")
    T.same(data.gen3RomText.CommonText, data.gen3Text.CommonText, label .. "rom_text shares source conversion")
    local native = { species = 151, item = 13, moves = { 1 }, pp = { 35 }, maxPp = { 35 },
      level = 10, hp = 20, maxHp = 30, attack = 10, defense = 10, speed = 10, spAtk = 10, spDef = 10 }
    local view = Records.mon(native, 3, data, version)
    T.eq(view.species, "MEW", label .. "live record species read")
    T.eq(view.item, "POTION", label .. "live record item read")
    T.eq(view.moves[1].id, "POUND", label .. "live record move read")
    view.item, view.moves[1] = "POKE_BALL", { id = "SURF", pp = 10, maxPp = 15 }
    local applied, reason = Records.applyMon(native, view, 3, data, version)
    T.check(applied, label .. "live record applies: " .. tostring(reason))
    T.eq(native.item, 4, label .. "live item write is numeric")
    T.eq(native.moves[1], 57, label .. "live move write is numeric")
  else
    local mew, a = data.pokemon.MEW, data.pokemon.FIXMON_A
    T.eq(mew.baseStats.attack, 121, label .. "attack patch")
    T.eq(data.moves.POUND.power, 73, label .. "mixed API move stacking")
    T.eq(data.moves.FIX_HIT.effect,
      generation == 1 and "NO_ADDITIONAL_EFFECT" or "EFFECT_NORMAL_HIT", label .. "native move effect")
    T.eq(data.items.POTION.price, 321, label .. "mixed API item stacking")
    T.eq(data.items.FIX_ITEM.price, 75, label .. "registered item")
    for _, prefix in ipairs({ "REMOVED", "DELETED" }) do
      T.eq(data.pokemon[prefix .. "_MON"], nil, label .. prefix .. " species tombstone")
      T.eq(data.moves[prefix .. "_HIT"], nil, label .. prefix .. " move tombstone")
      T.eq(data.items[prefix .. "_ITEM"], nil, label .. prefix .. " item tombstone")
    end
    if generation == 1 then
      T.eq(mew.baseStats.special, 109, label .. "legacy special field")
      T.eq(mew.baseStats.specialAttack, nil, label .. "no canonical stat leaks")
      T.eq(mew.baseStats.specialDefense, nil, label .. "no split defense leaks")
      T.eq(a.baseStats.special, 80, label .. "registered common special")
      T.eq(a.baseStats.specialAttack, nil, label .. "registered split attack does not leak")
      T.eq(a.baseStats.specialDefense, nil, label .. "registered split defense does not leak")
      T.same(mew.level1Moves, { "POUND" }, label .. "level-one moves stay separate")
      T.same(a.level1Moves, { "FIX_NEXT" }, label .. "registered level-one move patch")
      T.same(mew.learnset, { { level = 5, move = "POUND" },
        { level = 9, move = "FIX_HIT" }, { level = 20, move = "FIX_NEXT" } },
        label .. "native learnset")
      T.check(type(a.frontSize) == "number", label .. "frontSize default")
      T.eq(data.items.POTION.tossable, nil, label .. "optional DELETE")
      T.eq(data.trainers["326"].parties[1][1].species, "FIXMON_A", label .. "native trainer party")
      T.eq(data.encounters.FR_ROUTE_1.grass.slots[1].level, 7, label .. "native encounter level")
      T.eq(data.encounters.FR_ROUTE_1.grass.slots[1].species, "FIXMON_B", label .. "native encounter species")
      T.eq(a.evolutions[1].species, "FIXMON_B", label .. "native evolution target")
    else
      T.eq(mew.baseStats.specialAttack, 109, label .. "common special writes special attack")
      T.eq(mew.baseStats.specialDefense, 109, label .. "common special writes special defense")
      T.eq(a.baseStats.specialAttack, 80, label .. "registered common special attack")
      T.eq(a.baseStats.specialDefense, 80, label .. "registered common special defense")
      T.eq(mew.baseStats.special, nil, label .. "common special does not leak")
      local combined = {}
      for _, move in ipairs(out.mew.level1Moves) do
        combined[#combined + 1] = { level = 1, move = move }
      end
      for _, row in ipairs(out.mew.learnset) do combined[#combined + 1] = row end
      T.same(mew.levelMoves, combined, label .. "levelMoves combines starting and later moves")
      T.same(a.levelMoves, { { level = 1, move = "FIX_NEXT" } }, label .. "registered level-one move patch")
      T.eq(mew.learnset, nil, label .. "canonical learnset does not leak")
      T.check(type(a.picSize) == "number", label .. "picSize default")
      T.eq(a.frontSize, nil, label .. "canonical crop name does not leak")
      T.eq(a.evolutions[1].into, "FIXMON_B", label .. "native evolution target")
      T.eq(a.evolutions[1].method, "EVOLVE_LEVEL", label .. "native evolution method")
      T.eq(data.items.POTION.description, nil, label .. "optional DELETE")
      T.eq(data.gen2Trainers.classes["326"].trainers[1].party[1].species,
        "FIXMON_A", label .. "native trainer class")
      for _, time in ipairs({ "MORN", "DAY", "NITE" }) do
        local grass = data.gen2Encounters.grass.FR_ROUTE_1
        T.eq(grass.rates[time], 31, label .. time .. " encounter rate")
        T.same(grass.slots[time], { { species = "FIXMON_B", level = 7 } }, label .. time .. " encounter slots")
      end
      local mon = { species = "MEW", level = 5, hp = 10, maxHp = 10, moves = {} }
      local accepted, reason = Records.applyMon(mon, { species = "growthRates" }, 2, data, version)
      T.check(not accepted and type(reason) == "string", label .. "metadata is not a species")
      T.eq(mon.species, "MEW", label .. "rejected metadata leaves mon intact")
      T.eq(data.text.CommonText, RAW_REPLACEMENT, label .. "rom_text native string")
    end
    T.eq((generation == 2 and data.gen2Text or data.text).CommonText,
      RAW_REPLACEMENT, label .. "text native string")
  end
end

local originalVersion, originalPrefix = GameVersion.get(), CacheFs.prefix
local originalProvider = TextIR._provider
TextIR.setContextProvider(function(field)
  if field == "playerName" then return "LIVE_PLAYER" end
  if field == "rivalName" then return "LIVE_RIVAL" end
end)

for _, version in ipairs(VERSIONS) do
  GameVersion.set(version)
  CacheFs.prefix = GameVersion.cachePrefix(version)
  local generation = GameVersion.generation(version)
  local data, files = dataFor(generation), {}
  Fixture.cache(files, "red")
  Fixture.cache(files, "gold")
  addMod(files, "a_legacy", 2, LEGACY_BEFORE)
  addMod(files, "b_common", 3, COMMON, "a_legacy")
  addMod(files, "c_legacy", 2, LEGACY_AFTER, "b_common")
  local loader, result, warnings = load(files, data, version)
  T.eq(result, true, version .. " complete Loader result")
  T.eq(#loader.errors, 0, version .. " clean load: " .. table.concat(loader.errors, " | "))
  T.same(loader.order, { "a_legacy", "b_common", "c_legacy" }, version .. " mixed API dependency order")
  for _, id in ipairs({ "a_legacy", "b_common", "c_legacy" }) do
    T.eq(loader.mods[id] and loader.mods[id].state, "loaded", version .. " " .. id .. " state")
  end
  for _, warning in ipairs(warnings) do
    T.check(not warning:find("undeclared engine_internals require", 1, true),
      version .. " supported content does not attribute internal requires: " .. warning)
  end
  local out = loader.exports.b_common
  T.check(out and out.done, version .. " common body completed every behavior")
  if out and out.done then
    T.eq(out.price, 100, version .. " API 3 observes its own staged price")
    T.eq(out.liveMove().power, 73, version .. " API 3 observes later API 2 patch")
    T.eq(out.liveText(), RAW_REPLACEMENT, version .. " frozen Gen 1 text read")
    for index, mutate in ipairs(out.frozen) do
      T.raises(mutate, "frozen after load", version .. " frozen mutation " .. index)
    end
    T.eq(#loader.errors, 0, version .. " caught frozen writes do not corrupt Loader errors")
    local raw = loader.exports.c_legacy.raw
    T.eq(type(loader.exports.c_legacy.text), generation == 3 and "table" or "string",
      version .. " API 2 raw text shape remains native")
    T.eq(raw.baseStats.attack, 121, version .. " API 2 reads API 3 stat patch")
    T.check((generation == 1 and raw.baseStats.special == 109)
      or (generation ~= 1 and raw.baseStats.specialAttack == 109), version .. " API 2 stat schema")
    local checked, reason = pcall(nativeChecks, data, generation, out, version)
    T.check(checked, version .. " native assertions complete: " .. tostring(reason))
  end
  for registry, ids in pairs({ moves = { "BAD_POWER", "COLLIDE_MOVE" },
      items = { "COLLIDE_ITEM", "AFTER_LOAD" }, pokemon = { "COLLIDE_MON", "EGG_SLOT" },
      text = { "BAD_WRITE" } }) do
    for _, id in ipairs(ids) do
      T.eq(loader.content[registry].ops[id], nil, version .. " rejected " .. id .. " has no logged operations")
    end
  end
  T.eq(GameVersion.get(), version, version .. " dataset reads retain active version")
  T.eq(CacheFs.prefix, GameVersion.cachePrefix(version), version .. " dataset reads retain active cache prefix")
  T.eq(data.pokemon and data.pokemon.FIXMON, nil, version .. " dataset records never merge into active data")

  local rollbackData, rollbackFiles = dataFor(generation), {}
  addMod(rollbackFiles, "a_survivor", 3, SURVIVOR)
  addMod(rollbackFiles, "b_failure", 3, FAILURE, "a_survivor")
  addMod(rollbackFiles, "c_observer", 3, OBSERVER, "a_survivor")
  local failed, failedResult = load(rollbackFiles, rollbackData, version)
  T.eq(failedResult, false, version .. " failed mod makes complete load result false")
  T.eq(#failed.errors, 1, version .. " only the intentional failure is reported")
  T.check(tostring(failed.errors[1]):find("intentional content rollback", 1, true) ~= nil,
    version .. " reported error reaches the intended rollback point")
  T.eq(failed.mods.b_failure and failed.mods.b_failure.state, "failed", version .. " failed mod state")
  T.eq(failed.exports.b_failure, nil, version .. " failed exports disappear")
  T.eq(failed.exports.a_survivor and failed.exports.a_survivor.marker, "survived", version .. " prior mod survives")
  T.check(failed.exports.c_observer and failed.exports.c_observer.done, version .. " independent observer sees rollback")
  for _, registry in pairs(failed.content) do
    T.eq(registry.frozen, true, version .. " failed-mod load still freezes " .. registry.name)
    for _, ops in pairs(registry.ops) do
      for _, op in ipairs(ops) do T.neq(op.owner, "b_failure", version .. " failed owner leaves no operations") end
    end
  end
  if generation == 3 then
    T.eq(rollbackData.gen3Moves._rom[1].power, 54, version .. " native survivor move remains")
    T.eq(rollbackData.gen3Items._byId[13].price, 210, version .. " native survivor item remains")
    T.check(rollbackData.gen3Pokemon._stats[149] ~= nil, version .. " failed native tombstone is undone")
    T.eq(Schemas.gen3View.speciesNum(rollbackData.gen3Pokemon, "ROLLBACK_MON"), nil, version .. " failed species has no numeric mapping")
    T.eq(Schemas.gen3View.moveNum(rollbackData.gen3Moves, "ROLLBACK_HIT"), nil, version .. " failed move has no numeric mapping")
    T.eq(Schemas.gen3View.itemNum(rollbackData.gen3Items, "ROLLBACK_ITEM"), nil, version .. " failed item has no numeric mapping")
    T.same(rollbackData.gen3Text.CommonText, TextIR.fromAscii(SOURCE), version .. " failed native text patch is undone")
  else
    T.eq(rollbackData.moves.POUND.power, 54, version .. " native survivor move remains")
    T.eq(rollbackData.items.POTION.price, 210, version .. " native survivor item remains")
    T.check(rollbackData.pokemon.REMOVED_MON ~= nil, version .. " failed tombstone is undone")
    T.eq(rollbackData.pokemon.ROLLBACK_MON, nil, version .. " failed native species absent")
    T.eq(rollbackData.moves.ROLLBACK_HIT, nil, version .. " failed native move absent")
    T.eq(rollbackData.items.ROLLBACK_ITEM, nil, version .. " failed native item absent")
    T.eq((generation == 2 and rollbackData.gen2Text or rollbackData.text).CommonText,
      RAW_SOURCE, version .. " failed native text patch is undone")
  end

  local partitionData, partitionFiles = dataFor(generation), {}
  local function nativePartitions(value)
    if generation == 1 then
      local mon, trainer = value.pokemon.MEW, value.trainers["326"]
      return mon.level1Moves, mon.learnset, trainer.parties[1], trainer.partyNames[1]
    end
    local moves, party, name
    if generation == 2 then
      local trainer = value.gen2Trainers.classes["326"].trainers[1]
      moves, party, name = value.pokemon.MEW.levelMoves, trainer.party, trainer.name
    else
      local trainer = value.gen3Trainers.trainers[326]
      moves, party, name = value.gen3Pokemon._learnsets[151], trainer.party, trainer.name
    end
    local starting, later = {}, {}
    for _, row in ipairs(moves) do
      local level = generation == 3 and row[1] or row.level
      local partition = level == 1 and starting or later
      partition[#partition + 1] = row
    end
    return starting, later, party, name
  end
  local pristineStarting, _, pristineParty = nativePartitions(partitionData)
  local startingCount, partyCount = #pristineStarting, #pristineParty
  T.eq(startingCount, 1, version .. " pristine starting move count")
  T.eq(partyCount, 1, version .. " pristine trainer party count")
  addMod(partitionFiles, "a_owner", 3, PARTITION_OWNER)
  addMod(partitionFiles, "b_owner", 3, PARTITION_SURVIVOR)
  local partitionLoader, partitionResult = load(partitionFiles, partitionData, version, "a_owner")
  T.eq(partitionResult, true, version .. " later-owner rollback Loader result")
  T.eq(#partitionLoader.errors, 0, version .. " later-owner rollback errors")
  T.same(partitionLoader.order, { "a_owner", "b_owner" }, version .. " independent partition owner order")
  T.eq(partitionLoader.exports.a_owner, nil, version .. " rolled-back partition owner exports disappear")
  T.eq(partitionLoader.mods.b_owner and partitionLoader.mods.b_owner.state, "loaded",
    version .. " independent partition owner remains loaded")
  T.check(partitionLoader.exports.b_owner and partitionLoader.exports.b_owner.done,
    version .. " later owner observed both earlier list changes and completed")
  for _, registry in pairs(partitionLoader.content) do
    for _, ops in pairs(registry.ops) do
      for _, op in ipairs(ops) do
        T.neq(op.owner, "a_owner", version .. " rolled-back partition owner leaves no operations")
      end
    end
  end
  local starting, later, party, name = nativePartitions(partitionData)
  T.eq(#starting, startingCount, version .. " rollback restores pristine native starting move count")
  T.same(later, generation == 3 and { { 9, 1 } } or { { level = 9, move = "POUND" } },
    version .. " later owner's native level-nine move remains")
  T.eq(#party, partyCount, version .. " rollback restores pristine native trainer party count")
  T.eq(name, "SURVIVOR", version .. " later owner's native trainer name remains")

  local baselineData = dataFor(generation)
  local function coreTables(value)
    if generation == 3 then
      return { value.gen3Pokemon._stats, value.gen3Pokemon._learnsets,
        value.gen3Moves._rom, value.gen3Items._byId, value.gen3Text }
    end
    return { value.pokemon, value.moves, value.items,
      generation == 2 and value.gen2Text or value.text }
  end
  local pristine = Merge.deepCopy(coreTables(baselineData))
  local baseline, baselineResult = load({}, baselineData, version)
  T.eq(baselineResult, true, version .. " no-mod Loader result")
  T.eq(#baseline.errors, 0, version .. " no-mod errors")
  T.eq(next(baseline.mods), nil, version .. " no-mod discovery")
  T.same(coreTables(baselineData), pristine, version .. " no-mod native content remains intact")
end

do
  GameVersion.set("firered")
  local data = T.sdk.gen3Data()
  local fs = T.sdk.memfs({
    ["mods/identity_probe/manifest.json"] =
      '{"id":"identity_probe","name":"Identity Probe","version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"}',
    ["mods/identity_probe/main.lua"] = [[
      local mod = ...
      mod.content.pokemon:patch("MEW", { name = "Friendly Mew" })
      mod.content.moves:patch("POUND", { name = "Pound Reborn" })
      mod.content.items:patch("POTION", { name = "Small Healing" })
    ]],
  })
  local run = T.sdk.loadMods({ "mods/identity_probe" },
    { fs = fs, data = data, generation = 3 })
  T.eq(#run.errors, 0, "display-name probe loads cleanly")
  local native = { species = 151, item = 13, moves = { 1 },
    pp = { 35 }, maxPp = { 35 }, level = 5, hp = 10, maxHp = 10 }
  local view = Records.mon(native, 3, data, "firered")
  T.eq(view.species, "MEW", "renamed species retains canonical ID")
  T.eq(view.item, "POTION", "renamed item retains canonical ID")
  T.eq(view.moves[1].id, "POUND", "renamed move retains canonical ID")
  local other = { species = 4, item = 4, moves = { 57 },
    pp = { 15 }, maxPp = { 15 }, level = 5, hp = 10, maxHp = 10 }
  local ok, reason = Records.applyMon(other, {
    species = "MEW", item = "POTION",
    moves = { { id = "POUND", pp = 35, maxPp = 35 } },
  }, 3, data, "firered")
  T.eq(ok, true, "renamed IDs resolve for writes: " .. tostring(reason))
  T.eq(other.species, 151, "renamed species writes its numeric ID")
  T.eq(other.item, 13, "renamed item writes its numeric ID")
  T.eq(other.moves[1], 1, "renamed move writes its numeric ID")
  run.release()
end

TextIR.setContextProvider(originalProvider)
GameVersion.set(originalVersion)
CacheFs.prefix = originalPrefix
T.finish("unified_content")
