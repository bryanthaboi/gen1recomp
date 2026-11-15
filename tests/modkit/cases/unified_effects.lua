package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Merge = require("src.mods.Merge")
local Schemas = require("src.mods.Schemas")
local GameVersion = require("src.core.GameVersion")
local CacheFs = require("src.import.CacheFs")
local E = require("src.core.game3.battle.effect_ids")

local VERSIONS = { "red", "blue", "yellow", "gold", "silver", "crystal",
  "firered", "leafgreen", "ruby", "sapphire", "emerald" }
local CASES = {
  { "POISON", "POISON_EFFECT", "EFFECT_POISON", E.POISON, 0 },
  { "PARALYZE", "PARALYZE_EFFECT", "EFFECT_PARALYZE", E.PARALYZE, 0 },
  { "RAISE", "ATTACK_UP1_EFFECT", "EFFECT_ATTACK_UP", E.ATTACK_UP, 0 },
  { "DRAIN", "DRAIN_HP_EFFECT", "EFFECT_LEECH_HIT", E.ABSORB, 40 },
  { "RECOIL", "RECOIL_EFFECT", "EFFECT_RECOIL_HIT", E.RECOIL, 40 },
  { "SEED", "LEECH_SEED_EFFECT", "EFFECT_LEECH_SEED", E.LEECH_SEED, 0 },
  { "RECHARGE", "HYPER_BEAM_EFFECT", "EFFECT_HYPER_BEAM", E.RECHARGE, 40 },
  { "POISON_20", "POISON_SIDE_EFFECT1", "EFFECT_POISON_HIT", E.POISON_HIT, 40, 20 },
  { "POISON_40", "POISON_SIDE_EFFECT2", "EFFECT_POISON_HIT", E.POISON_HIT, 40, 40 },
  { "PARALYZE_10", "PARALYZE_SIDE_EFFECT1", "EFFECT_PARALYZE_HIT", E.PARALYZE_HIT, 40, 10 },
  { "PARALYZE_30", "PARALYZE_SIDE_EFFECT2", "EFFECT_PARALYZE_HIT", E.PARALYZE_HIT, 40, 30 },
  { "BURN_10", "BURN_SIDE_EFFECT1", "EFFECT_BURN_HIT", E.BURN_HIT, 40, 10 },
  { "BURN_30", "BURN_SIDE_EFFECT2", "EFFECT_BURN_HIT", E.BURN_HIT, 40, 30 },
  { "DROP_33", "ATTACK_DOWN_SIDE_EFFECT", "EFFECT_ATTACK_DOWN_HIT", E.ATTACK_DOWN_HIT, 40, 33 },
}

local function dataFor(generation)
  if generation == 3 then
    local data = T.sdk.gen3Data()
    data.gen3Pokemon._moveNames[49] = "OBSERVED"
    data.gen3Pokemon._moveNames[120] = "OPAQUE"
    data.gen3Moves._rom[49] = { effect = E.SONICBOOM, power = 1, type = 0,
      accuracy = 90, pp = 20, secondaryChance = 37, target = 8, priority = -1, flags = 19 }
    data.gen3Moves._rom[120] = { effect = 250, power = 40, type = 0,
      accuracy = 100, pp = 20, secondaryChance = 17, target = 0, priority = 0, flags = 3 }
    data.gen3Pokemon._battleMoves = Merge.deepCopy(data.gen3Moves._rom)
    Schemas.bindGen3(data, GameVersion.get())
    return data
  end
  local data = T.fixtures.fresh()
  data.pokemon.MEW = Merge.deepCopy(data.pokemon.FIXMON_A)
  data.pokemon.MEW.id, data.pokemon.MEW.name, data.pokemon.MEW.index = "MEW", "MEW", 4
  data.pokemon.MEW.types, data.pokemon.MEW.evolutions = { "NORMAL" }, {}
  data.moves.POUND = Merge.deepCopy(data.moves.FIX_TACKLE)
  data.moves.POUND.id, data.moves.POUND.name, data.moves.POUND.index = "POUND", "POUND", 5
  data.pokemon.MEW.level1Moves = { "POUND" }
  data.pokemon.MEW.learnset = { { level = 1, move = "POUND" } }
  data.moves.OBSERVED = { id = "OBSERVED", index = 49, name = "OBSERVED", type = "NORMAL",
    power = 1, accuracy = 90, pp = 20, effect = "SPECIAL_DAMAGE_EFFECT", fixedDamage = 20 }
  data.palettes = data.palettes or { palettes = {} }
  data.palettes.pokemon = data.palettes.pokemon or {}
  data.moves.OBSERVED.category = generation == 1 and "physical" or nil
  data.moves.OPAQUE = { id = "OPAQUE", index = 120, name = "OPAQUE", type = "NORMAL",
    power = 40, accuracy = 100, pp = 20, effect = "NO_ADDITIONAL_EFFECT",
    category = generation == 1 and "physical" or nil }
  if generation == 2 then
    for _, mon in pairs(data.pokemon) do
      mon.baseStats.specialAttack, mon.baseStats.specialDefense = mon.baseStats.special, mon.baseStats.special
      mon.baseStats.special = nil
      mon.levelMoves, mon.learnset, mon.level1Moves = mon.learnset, nil, nil
      mon.picSize, mon.frontSize, mon.evolutions = mon.frontSize, nil, {}
    end
    data.pokemon.growthRates = { MEDIUM_SLOW = {
      numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 } }
    for _, move in pairs(data.moves) do
      move.effect = move.effect == "BURN_SIDE_EFFECT1" and "EFFECT_BURN_HIT" or "EFFECT_NORMAL_HIT"
    end
    data.moves.OBSERVED.effect = "EFFECT_STATIC_DAMAGE"
    data.moves.OBSERVED.fixedDamage = nil
    data.moves.OBSERVED.effectChance, data.moves.OBSERVED.effectChanceRaw = 37, 95
    data.moves.OPAQUE.effect = "EFFECT_UNUSED_25"
    data.moves.OPAQUE.effectChance, data.moves.OPAQUE.effectChanceRaw = 17, 44
    data.moves.OBSERVED.accuracyRaw, data.moves.OPAQUE.accuracyRaw = 229, 255
    for i, row in ipairs(CASES) do
      data.moves["NATIVE_SEED_" .. i] = { id = "NATIVE_SEED_" .. i, name = "NATIVE SEED " .. i,
        type = "NORMAL", power = row[5], accuracy = 100, pp = 20, effect = row[3] }
    end
    data.gen2Trainers, data.gen2Encounters = { classes = {} }, {}
  end
  return data
end

local function addMod(files, id, body, dependency)
  files["mods/" .. id .. "/manifest.json"] = ('{"id":"%s","name":"%s",'
    .. '"version":"1.0.0","api":3,"games":["all"],"entry":"main.lua"%s}')
    :format(id, id, dependency and ',"dependencies":["' .. dependency .. '"]' or "")
  files["mods/" .. id .. "/main.lua"] = body
end

local function load(files, data, version)
  T.sdk.captureRuntime()
  Loader._resetShimWarned()
  local loader = Loader.new({ fs = T.sdk.memfs(files), dev = true,
    generation = GameVersion.generation(version), version = version })
  local ok, result = pcall(loader.load, loader, data)
  T.sdk.restoreRuntime()
  T.check(ok, version .. " Loader completed: " .. tostring(result))
  return loader, ok and result
end

local COMMON = [[
local mod = ...
local moves = mod.content.moves
local function must(value, reason) assert(value ~= nil, reason); return value end
local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
local rejectedCount = 0
local function rejected(fn)
  rejectedCount = rejectedCount + 1
  local ok, value, reason = pcall(fn)
  assert(not ok or (value == nil and type(reason) == "string"), "invalid write accepted " .. rejectedCount)
end
local cases = {
  { "POISON", "POISON_EFFECT", 0 }, { "PARALYZE", "PARALYZE_EFFECT", 0 },
  { "RAISE", "ATTACK_UP1_EFFECT", 0 }, { "DRAIN", "DRAIN_HP_EFFECT", 40 },
  { "RECOIL", "RECOIL_EFFECT", 40 }, { "SEED", "LEECH_SEED_EFFECT", 0 },
  { "RECHARGE", "HYPER_BEAM_EFFECT", 40 },
  { "POISON_20", "POISON_SIDE_EFFECT1", 40, 20 },
  { "POISON_40", "POISON_SIDE_EFFECT2", 40, 40 },
  { "PARALYZE_10", "PARALYZE_SIDE_EFFECT1", 40, 10 },
  { "PARALYZE_30", "PARALYZE_SIDE_EFFECT2", 40, 30 },
  { "BURN_10", "BURN_SIDE_EFFECT1", 40, 10 },
  { "BURN_30", "BURN_SIDE_EFFECT2", 40, 30 },
  { "DROP_33", "ATTACK_DOWN_SIDE_EFFECT", 40, 33 },
}
mod.exports.rows = {}
for _, row in ipairs(cases) do
  local id = "FX_" .. row[1]
  must(moves:register(id, { name = "SAME DISPLAY NAME", type = "NORMAL", power = row[3],
    accuracy = 100, pp = 20, effect = row[2] }))
  local value = must(moves:get(id))
  assert(value.effect == row[2], id .. " canonical identity")
  if row[4] and mod.generation ~= 1 then assert(value.secondaryChance == row[4], id .. " default chance") end
  must(moves:override(id, value))
  assert(same(moves:get(id), value), id .. " unchanged round trip")
  mod.exports.rows[id] = moves:get(id)
end

for _, id in ipairs({ "OBSERVED", "OPAQUE" }) do
  local before = must(moves:get(id))
  if id == "OPAQUE" and mod.generation ~= 1 then
    assert(before.effect:find("native:" .. mod.generation .. ":", 1, true) == 1)
  end
  must(moves:override(id, before))
  must(moves:patch(id, { name = "RENAMED OBSERVATION" }))
  local after = must(moves:get(id))
  assert(after.effect == before.effect and after.secondaryChance == before.secondaryChance)
end

if mod.generation ~= 1 then
  for _, row in ipairs({ { "EXPLICIT", 73 }, { "ZERO", 0 }, { "CERTAIN", 100 } }) do
    local id = "FX_" .. row[1]
    must(moves:register(id, { name = id, type = "NORMAL", power = 40, accuracy = 100,
      pp = 20, effect = "PARALYZE_SIDE_EFFECT1", secondaryChance = row[2] }))
    assert(moves:get(id).secondaryChance == row[2])
    must(moves:patch(id, { effect = "POISON_SIDE_EFFECT2", secondaryChance = row[2] }))
    assert(moves:get(id).effect == "POISON_SIDE_EFFECT2" and moves:get(id).secondaryChance == row[2])
    must(moves:override(id, moves:get(id)))
    assert(moves:get(id).secondaryChance == row[2])
  end
  must(moves:patch("FX_EXPLICIT", { effect = "BURN_SIDE_EFFECT2" }))
  assert(moves:get("FX_EXPLICIT").effect == "BURN_SIDE_EFFECT2"
    and moves:get("FX_EXPLICIT").secondaryChance == 30)
  must(moves:register("FX_ADDITION", { name = "NEW MECHANIC", type = "NORMAL", power = 0,
    accuracy = 100, pp = 20, effect = "EFFECT_PROTECT" }))
  assert(moves:get("FX_ADDITION").effect == "EFFECT_PROTECT")
  must(moves:override("FX_ADDITION", moves:get("FX_ADDITION")))
  assert(moves:get("FX_ADDITION").effect == "EFFECT_PROTECT")
end
if mod.generation == 3 then
  must(moves:register("FX_WISH", { name = "WISH", type = "NORMAL", power = 0,
    accuracy = 100, pp = 10, effect = "WISH" }))
  assert(moves:get("FX_WISH").effect == "WISH")
  must(moves:override("FX_WISH", moves:get("FX_WISH")))
  assert(moves:get("FX_WISH").effect == "WISH")
end

local before = must(moves:get("FX_POISON"))
if mod.generation == 2 then
  rejected(function() return moves:patch("FX_POISON", {
    effect = "PARALYZE_EFFECT", index = must(moves:get("POUND")).index }) end)
  assert(same(moves:get("FX_POISON"), before), "colliding index mutated move effect or index")
end
local invalidEffects = { 17, {}, "native:9:POISON" }
if mod.generation ~= 1 then invalidEffects[#invalidEffects + 1] = "NOT_AN_EFFECT" end
for _, effect in ipairs(invalidEffects) do
  rejected(function() return moves:patch("FX_POISON", { effect = effect, power = 99 }) end)
  assert(same(moves:get("FX_POISON"), before), "rejected patch mutated move")
end
if mod.generation ~= 1 then
  rejected(function() return moves:patch("FX_POISON", { effect = "SPEED_UP1_EFFECT" }) end)
  assert(same(moves:get("FX_POISON"), before), "missing handler mutated move")
  for _, chance in ipairs({ -1, 101, 1.5, "20" }) do
    rejected(function() return moves:patch("FX_POISON", { effect = "POISON_SIDE_EFFECT1", secondaryChance = chance }) end)
    assert(same(moves:get("FX_POISON"), before), "invalid chance mutated move")
  end
end
rejected(function() return moves:register("FX_BAD", { name = "BAD", type = "NORMAL",
  power = 40, accuracy = 100, pp = 20, effect = 17 }) end)
assert(moves:get("FX_BAD") == nil)

local pokemon = mod.content.pokemon
must(pokemon:patch("MEW", { level1Moves = { "POUND" },
  learnset = { { level = 1, move = "FX_POISON" }, { level = 7, move = "FX_DRAIN" } } }))
local mew = must(pokemon:get("MEW"))
if mod.generation == 1 then
  assert(#mew.learnset == 2 and mew.learnset[1].level == 1 and mew.learnset[1].move == "FX_POISON")
else
  assert(#mew.level1Moves == 2 and mew.level1Moves[2] == "FX_POISON")
  assert(#mew.learnset == 1 and mew.learnset[1].level == 7)
end
must(pokemon:patch("MEW", { learnset = { { level = 1, move = "FX_RECOIL" } } }))
mew = must(pokemon:get("MEW"))
if mod.generation == 1 then
  assert(#mew.learnset == 1 and mew.learnset[1].move == "FX_RECOIL")
else
  assert(#mew.learnset == 0 and mew.level1Moves[#mew.level1Moves] == "FX_RECOIL")
end
must(pokemon:patch("MEW", { learnset = {} }))
assert(#pokemon:get("MEW").learnset == 0)
must(pokemon:patch("MEW", { level1Moves = { "POUND" },
  learnset = { { level = 1, move = "FX_POISON" }, { level = 7, move = "FX_DRAIN" } } }))
mod.exports.mew = pokemon:get("MEW")

if mod.generation == 1 then
  must(mod.content.move_effects:register("FX_CUSTOM_EFFECT", { kind = "primary", run = function(_, user)
    user.stages.attack = (user.stages.attack or 0) + 3
    return {}
  end }))
  must(moves:register("FX_CUSTOM", { name = "CUSTOM", type = "NORMAL", power = 0,
    accuracy = 100, pp = 10, effect = "FX_CUSTOM_EFFECT" }))
  assert(moves:get("FX_CUSTOM").effect == "FX_CUSTOM_EFFECT")
  must(moves:override("FX_CUSTOM", moves:get("FX_CUSTOM")))
  must(mod.content.music:register("FX_THEME", { file = "theme.ogg" }))
  must(mod.content.palettes:register("FX_PALETTE", { {255,255,255}, {170,170,170}, {85,85,85}, {0,0,0} }))
  must(mod.content.cries:register("FX_CRY", { header = {}, pitch = 128, length = 128 }))
  must(mod.content.ai_classes:register("FX_BRAIN", { kind = "brain", brain = function() return "FX_POISON" end }))
  must(pokemon:patch("MEW", { icon = "BALL", cry = "FX_CRY", palette = "FX_PALETTE",
    battleTheme = "FX_THEME", battleScaleFront = 1.5, battleScaleBack = 2.5 }))
  must(moves:patch("POUND", { anim = { seq = {} }, highCrit = true, fixedDamage = 23,
    chargeText = "CHARGING", semiInvulnerable = true, multiHit = { 2, 3 }, counterable = false }))
  must(mod.content.trainers:patch("OPP_FIX_YOUNGSTER", { palette = "FX_PALETTE",
    paletteSource = "red:1", basePic = "OPP_FIX_YOUNGSTER", aiMods = { 1, 2 },
    aiClass = "FX_BRAIN", brain = function() return "FX_DRAIN" end }))
  local mon, move = pokemon:get("MEW"), moves:get("POUND")
  local trainer = mod.content.trainers:get("OPP_FIX_YOUNGSTER")
  assert(mon.icon == "BALL" and mon.cry == "FX_CRY" and mon.palette == "FX_PALETTE")
  assert(mon.battleTheme == "FX_THEME" and mon.battleScaleFront == 1.5 and mon.battleScaleBack == 2.5)
  assert(move.highCrit and move.fixedDamage == 23 and move.chargeText == "CHARGING")
  assert(move.semiInvulnerable and move.counterable == false and same(move.multiHit, { 2, 3 })
    and same(move.anim, { seq = {} }))
  assert(trainer.palette == "FX_PALETTE" and trainer.paletteSource == "red:1")
  assert(trainer.basePic == "OPP_FIX_YOUNGSTER" and trainer.aiClass == "FX_BRAIN")
  assert(same(trainer.aiMods, { 1, 2 }) and trainer.brain() == "FX_DRAIN")
  must(pokemon:override("MEW", mon))
  must(moves:override("POUND", move))
  must(mod.content.trainers:override("OPP_FIX_YOUNGSTER", trainer))
  assert(same(pokemon:get("MEW"), mon) and same(moves:get("POUND"), move))
  assert(same(mod.content.trainers:get("OPP_FIX_YOUNGSTER"), trainer))
end
mod.exports.done = true
]]

local FAILURE = [[
local mod = ...
assert(mod.content.moves:patch("FX_POISON", { effect = "PARALYZE_EFFECT", power = 99 }))
assert(mod.content.pokemon:patch("MEW", { level1Moves = { "FX_RECOIL" },
  learnset = { { level = 1, move = "FX_RECOIL" } } }))
assert(mod.content.moves:register("FX_FAILED", { name = "FAILED", type = "NORMAL", power = 0,
  accuracy = 100, pp = 5, effect = "POISON_EFFECT" }))
error("intentional effect owner rollback")
]]

local function nativeMove(data, generation, id)
  if generation ~= 3 then return data.moves[id] end
  local index = Schemas.gen3View.moveNum(data.gen3Moves, id)
  return index and data.gen3Moves._rom[index]
end

local function gen1Dispatch(data, version)
  local Battle = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")
  local SaveData = require("src.core.SaveData")
  local Effects = require("src.battle.MoveEffects")
  require("src.battle.TypeChart").load(data)
  local function fresh(roll)
    local save = SaveData.newGame()
    save.party = { Pokemon.new(data, "MEW", 30) }
    local battle = Battle.newWild({ data = data, save = save,
      stack = { top = function() return nil end, push = function() end } }, "FIXMON_C", 30)
    battle.phase, battle.queue = "menu", {}
    battle.rng = function(lo, hi) return math.max(lo, math.min(hi, roll or 0)) end
    return battle, battle.player, battle.enemy
  end
  for _, row in ipairs(CASES) do
    local battle, user, target = fresh()
    local move = data.moves["FX_" .. row[1]]
    if Effects.primary[move.effect] then
      Effects.primary[move.effect](battle, user, target, move)
      if row[1] == "POISON" then T.eq(target.mon.status, "PSN", version .. " native poison") end
      if row[1] == "PARALYZE" then T.eq(target.mon.status, "PAR", version .. " native paralysis") end
      if row[1] == "RAISE" then T.eq(user.stages.attack, 1, version .. " native stat raise") end
      if row[1] == "SEED" then T.eq(target.leechSeeded, true, version .. " native seed") end
    elseif Effects.secondary[move.effect] then
      Effects.secondary[move.effect](battle, user, target, move)
      if row[1] == "DROP_33" then T.eq(target.stages.attack, -1, version .. " native stat drop")
      else
        local status = row[1]:find("POISON", 1, true) and "PSN"
          or row[1]:find("PARALYZE", 1, true) and "PAR" or "BRN"
        T.eq(target.mon.status, status, version .. " native secondary " .. row[1])
        local miss, a, b = fresh(255)
        Effects.secondary[move.effect](miss, a, b, move)
        T.eq(b.mon.status, nil, version .. " native chance miss " .. row[1])
      end
    else
      user.mon.hp = math.floor(user.mon.stats.hp / 2)
      local before = user.mon.hp
      Effects.full[move.effect].afterDamage({ battle = battle, user = user, target = target,
        move = move, moveInst = {}, totalDealt = 20, say = function(message) battle:sayNext(message) end })
      if row[1] == "DRAIN" then T.eq(user.mon.hp, before + 10, version .. " native drain HP") end
      if row[1] == "RECOIL" then T.eq(user.mon.hp, before - 5, version .. " native recoil HP") end
      if row[1] == "RECHARGE" then T.eq(user.mustRecharge, true, version .. " native recharge") end
    end
  end
  local battle, user, target = fresh()
  local move = data.moves.FX_CUSTOM
  data.move_effects[move.effect].run(battle, user, target, move)
  T.eq(user.stages.attack, 3, version .. " custom Gen 1 handler executes")
  local low, a, b = fresh(75)
  Effects.secondary[data.moves.FX_POISON_20.effect](low, a, b, data.moves.FX_POISON_20)
  T.eq(b.mon.status, nil, version .. " lower poison chance misses middle roll")
  local high, c, d = fresh(75)
  Effects.secondary[data.moves.FX_POISON_40.effect](high, c, d, data.moves.FX_POISON_40)
  T.eq(d.mon.status, "PSN", version .. " higher poison chance lands middle roll")
end

local function gen2Dispatch(data, version)
  local Battle = require("src.battle.gen2.Battle")
  local Mon = require("src.battle.gen2.Mon")
  data.type_chart = data.type_chart or {}
  data.type_chart.battleRules = data.type_chart.battleRules or require("tests.gen2_battle_rules_fixture")()
  data.text = data.text or {}
  for label, text in pairs(require("tests.gen2_battle_text_fixture")()) do
    if data.text[label] == nil then data.text[label] = text end
  end
  for _, row in ipairs(CASES) do
    local id = "FX_" .. row[1]
    local user, target = Mon.new(data, "MEW", 30), Mon.new(data, "FIXMON_C", 30)
    user.moves = { { id = id, pp = 20, maxPp = 20 } }
    local battle = Battle.new({ data = data, party = { user }, wild = target,
      random = function(n) return n and n > 1 and 1 or 0 end })
    user.hp = math.floor(user.stats.hp / 2)
    local hp, targetHp = user.hp, target.hp
    battle:useMove(user, target, id)
    if row[1] == "POISON" or row[1]:find("POISON_", 1, true) then
      T.eq(target.status, "poison", version .. " native poison " .. id)
    elseif row[1] == "PARALYZE" or row[1]:find("PARALYZE_", 1, true) then
      T.eq(target.status, "paralyze", version .. " native paralysis " .. id)
    elseif row[1]:find("BURN_", 1, true) then
      T.eq(target.status, "burn", version .. " native burn " .. id)
    elseif row[1] == "RAISE" then T.eq(battle.stages.player.attack, 1, version .. " native stat raise")
    elseif row[1] == "DROP_33" then T.eq(battle.stages.enemy.attack, -1, version .. " native stat drop")
    elseif row[1] == "SEED" then T.eq(battle:volatile(target).leechSeed, true, version .. " native seed")
    elseif row[1] == "RECHARGE" then T.eq(battle:volatile(user).recharge, true, version .. " native recharge")
    elseif row[1] == "DRAIN" then
      T.check(target.hp < targetHp and user.hp > hp, version .. " native drain damages and heals")
    elseif row[1] == "RECOIL" then
      T.check(target.hp < targetHp and user.hp < hp, version .. " native recoil damages both mons")
    end
  end
  local battle = Battle.new({ data = data })
  battle.random = function() return 75 end
  T.eq(battle:effectChanceFailed(data.moves.FX_POISON_20, {}), true, version .. " lower raw chance misses")
  T.eq(battle:effectChanceFailed(data.moves.FX_POISON_40, {}), false, version .. " higher raw chance lands")
end

local function gen3Dispatch(data, version)
  local Pokemon = require("src.core.game3.pokemon")
  local State = require("src.core.game3.battle.state")
  local Adapter = require("src.core.game3.battle.adapter")
  local Effects = require("src.core.game3.battle.effects")
  local Damaging = require("src.core.game3.battle.effects.damaging")
  local Moves = require("src.core.game3.battle.moves")
  local Engine = require("src.core.game3.battle.engine")
  local oldMoveNames = Pokemon._moveNames
  Pokemon._moveNames = data.gen3Pokemon._moveNames
  local oldByNum, oldByName = Moves.BY_NUM, Moves._numByName
  Moves.BY_NUM, Moves._numByName = {}, {}
  for index in pairs(data.gen3Moves._rom) do
    local id = Schemas.gen3View.moveId(data.gen3Moves, index)
    Moves.BY_NUM[index], Moves._numByName[id] = id, index
  end
  local oldRom, oldRomLoaded = Moves._rom, Moves._romLoaded
  Moves._rom, Moves._romLoaded = data.gen3Moves._rom, true
  local oldTypes, oldStats, oldSink = Pokemon._types, Pokemon._stats, Adapter.textSink
  Pokemon._types, Pokemon._stats = data.gen3Pokemon._types, data.gen3Pokemon._stats
  Adapter.textSink = function(id) return id end
  local function fresh(roll)
    local function mon()
      return { species = 151, level = 30, hp = 100, maxHp = 200, attack = 50, defense = 50,
        spAtk = 50, spDef = 50, speed = 50, ability = 0, moves = {}, pp = {}, nickname = "MEW" }
    end
    local st = State.new({ wild = true, playerParty = { mon() }, foeParty = { mon() },
      rng = function(lo, hi) return math.max(lo, math.min(hi, roll or 0)) end })
    return st, Adapter.new(st)
  end
  local ok, reason = pcall(function()
    for _, row in ipairs(CASES) do
      local st, ad = fresh()
      local move = nativeMove(data, 3, "FX_" .. row[1])
      if row[1] == "POISON" or row[1] == "PARALYZE" or row[1] == "RAISE" or row[1] == "SEED" then
        T.eq(Effects.runForMove(ad, st.player, st.enemy, "FX_" .. row[1], { move = move }), true,
          version .. " native setup dispatch " .. row[1])
        if row[1] == "POISON" then T.eq(ad:status(st.enemy), "PSN", version .. " native poison") end
        if row[1] == "PARALYZE" then T.eq(ad:status(st.enemy), "PAR", version .. " native paralysis") end
        if row[1] == "RAISE" then T.eq(st.player.stages.attack, 1, version .. " native stat raise") end
        if row[1] == "SEED" then T.check(st.enemy.expSeeded == true and st.enemy.expSeedSource == st.player,
          version .. " native seed state") end
      elseif row[1] == "DRAIN" then
        local moveIndex = Schemas.gen3View.moveNum(data.gen3Moves, "FX_DRAIN")
        st.player.mon.moves, st.player.mon.pp = { moveIndex }, { 20 }
        local beforeUser, beforeTarget = ad:hp(st.player), ad:hp(st.enemy)
        Engine.resolveMove(st.player, st.enemy, moveIndex, 1, ad, st, {})
        local lost = beforeTarget - ad:hp(st.enemy)
        T.check(lost > 0, version .. " native full drain pipeline damages target")
        T.eq(ad:hp(st.player), beforeUser + math.max(1, math.floor(lost / 2)),
          version .. " native full drain pipeline heals user")
      else
        Damaging.afterHit(ad, st.player, st.enemy, move, 20)
        if row[1] == "RECOIL" then T.eq(ad:hp(st.player), 95, version .. " native recoil HP")
        elseif row[1] == "RECHARGE" then T.eq(st.player.expMustRecharge, true, version .. " native recharge")
        elseif row[1] == "DROP_33" then T.eq(st.enemy.stages.attack, -1, version .. " native stat drop")
        else
          local status = row[1]:find("POISON", 1, true) and "PSN"
            or row[1]:find("PARALYZE", 1, true) and "PAR" or "BRN"
          T.eq(ad:status(st.enemy), status, version .. " native secondary " .. row[1])
          local missed, missAd = fresh(99)
          Damaging.afterHit(missAd, missed.player, missed.enemy, move, 20)
          T.eq(missAd:status(missed.enemy), nil, version .. " native secondary miss " .. row[1])
        end
      end
    end
    for _, pair in ipairs({ { "FX_POISON_20", nil }, { "FX_POISON_40", "PSN" },
        { "FX_ZERO", nil }, { "FX_CERTAIN", "PSN" } }) do
      local st, ad = fresh(30)
      Damaging.afterHit(ad, st.player, st.enemy, nativeMove(data, 3, pair[1]), 20)
      T.eq(ad:status(st.enemy), pair[2], version .. " native explicit/default chance " .. pair[1])
    end
  end)
  Moves.BY_NUM, Moves._numByName = oldByNum, oldByName
  Pokemon._moveNames = oldMoveNames
  Moves._rom, Moves._romLoaded = oldRom, oldRomLoaded
  Pokemon._types, Pokemon._stats, Adapter.textSink = oldTypes, oldStats, oldSink
  T.check(ok, version .. " native dispatch completed: " .. tostring(reason))
end

local originalVersion, originalPrefix = GameVersion.get(), CacheFs.prefix
for _, version in ipairs(VERSIONS) do
  GameVersion.set(version)
  CacheFs.prefix = GameVersion.cachePrefix(version)
  local generation = GameVersion.generation(version)
  local data, files = dataFor(generation), {}
  local observed = Merge.deepCopy(nativeMove(data, generation, "OBSERVED"))
  local opaque = Merge.deepCopy(nativeMove(data, generation, "OPAQUE"))
  addMod(files, "a_effects", COMMON)
  local loader, result = load(files, data, version)
  T.eq(result, true, version .. " Loader result")
  T.eq(#loader.errors, 0, version .. " Loader errors: " .. table.concat(loader.errors, " | "))
  local out = loader.exports.a_effects
  T.check(out and out.done, version .. " all sandbox assertions completed")
  if out and out.done then
    for _, row in ipairs(CASES) do
      local move = nativeMove(data, generation, "FX_" .. row[1])
      T.eq(move.effect, row[generation + 1], version .. " native effect " .. row[1])
      if row[6] and generation == 2 then
        T.eq(move.effectChance, row[6], version .. " native percentage " .. row[1])
        T.eq(move.effectChanceRaw, math.floor(row[6] * 255 / 100), version .. " native chance byte " .. row[1])
      elseif row[6] and generation == 3 then
        T.eq(move.secondaryChance, row[6], version .. " native chance " .. row[1])
      end
    end
    if generation ~= 3 then
      observed.name, opaque.name = "RENAMED OBSERVATION", "RENAMED OBSERVATION"
    else
      T.eq(data.gen3Pokemon._moveNames[49], "RENAMED OBSERVATION", version .. " native observed name")
      T.eq(data.gen3Pokemon._moveNames[120], "RENAMED OBSERVATION", version .. " native opaque name")
    end
    T.same(nativeMove(data, generation, "OBSERVED"), observed, version .. " native override round trip")
    T.same(nativeMove(data, generation, "OPAQUE"), opaque, version .. " opaque native round trip")
    if generation == 1 then gen1Dispatch(data, version)
    elseif generation == 2 then gen2Dispatch(data, version)
    else gen3Dispatch(data, version) end

    local rollbackData, rollbackFiles = dataFor(generation), {}
    addMod(rollbackFiles, "a_effects", COMMON)
    addMod(rollbackFiles, "b_failure", FAILURE, "a_effects")
    local failed = load(rollbackFiles, rollbackData, version)
    T.eq(#failed.errors, 1, version .. " failed owner reports one error")
    T.check(tostring(failed.errors[1]):find("intentional effect owner rollback", 1, true) ~= nil,
      version .. " failure reaches intended rollback point")
    for _, row in ipairs(CASES) do
      local id = "FX_" .. row[1]
      T.same(nativeMove(rollbackData, generation, id), nativeMove(data, generation, id),
        version .. " owner rollback preserves survivor " .. id)
    end
    T.eq(nativeMove(rollbackData, generation, "FX_FAILED"), nil, version .. " failed registration removed")
    if generation == 3 then
      T.same(rollbackData.gen3Pokemon._learnsets[151], data.gen3Pokemon._learnsets[151],
        version .. " native level-1 learnset rollback")
      T.same(rollbackData.gen3Pokemon._battleMoves, data.gen3Pokemon._battleMoves,
        version .. " native battle-move mirror rollback")
    else
      T.same(rollbackData.pokemon.MEW, data.pokemon.MEW, version .. " native species/list rollback")
    end
  end
end
GameVersion.set(originalVersion)
CacheFs.prefix = originalPrefix
T.finish("unified_effects")
