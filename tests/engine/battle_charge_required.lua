-- Public, shared battle.charge_required hook.
--
-- A mod that adds weather to Gen 1 needs to let SolarBeam resolve on the
-- turn it is selected without replacing the move, mutating private battle
-- state, or reimplementing the damage pipeline.  This case loads a real
-- sandboxed mod through the public SDK and drives the real Gen 1 and Gold
-- battle engines.  It also pins each generation's empty-chain decision.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local BattleState = require("src.battle.BattleState")
local Font = require("src.render.Font")
local Gen2Battle = require("src.battle.gen2.Battle")
local Gen2Mon = require("src.battle.gen2.Mon")
local Pokemon = require("src.pokemon.Pokemon")
local Runtime = require("src.mods.Runtime")
local SaveData = require("src.core.SaveData")
local TypeChart = require("src.battle.TypeChart")

local function lowRoll(a)
  return a or 0
end

local function queueHasText(battle, fragment)
  for _, row in ipairs(battle.queue or {}) do
    if row.text and row.text:find(fragment, 1, true) then return true end
  end
  return false
end

local function eventHasText(battle, fragment)
  for _, row in ipairs(battle.events or {}) do
    if row.kind == "message" and row.text
        and row.text:find(fragment, 1, true) then return true end
  end
  return false
end

local function gen1Data()
  local data = T.fixtures.fresh()
  data.moves.SOLARBEAM = {
    id = "SOLARBEAM", index = 80, name = "SOLARBEAM", type = "GRASS",
    power = 120, accuracy = 100, pp = 10, effect = "CHARGE_EFFECT",
  }
  data.moves.FLY = {
    id = "FLY", index = 81, name = "FLY", type = "FLYING",
    power = 70, accuracy = 95, pp = 15, effect = "FLY_EFFECT",
  }
  data.moves.DIG = {
    id = "DIG", index = 82, name = "DIG", type = "GROUND",
    power = 100, accuracy = 100, pp = 10, effect = "FLY_EFFECT",
  }
  Font.load(data)
  TypeChart.load(data)
  return data
end

local function gen1Battle(data, moveId)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(data, "FIXMON_A", 30) }
  local move = { id = moveId, pp = 10, maxPp = 10 }
  save.party[1].moves = { move }
  local stack = { states = {} }
  function stack:push(state) self.states[#self.states + 1] = state end
  function stack:pop() return table.remove(self.states) end
  function stack:top() return self.states[#self.states] end
  local game = { data = data, save = save, stack = stack,
    input = { wasPressed = function() return false end,
              isDown = function() return false end } }
  local battle = BattleState.newWild(game, "FIXMON_B", 20)
  battle.rng = lowRoll
  return battle, battle.player, battle.enemy, move
end

local G2_TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  GRASS = { id = "GRASS", index = 22, category = "special" },
  FLYING = { id = "FLYING", index = 2, category = "physical" },
  GROUND = { id = "GROUND", index = 4, category = "physical" },
}

local G2_MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35,
    type = "NORMAL", accuracy = 100, pp = 35,
    effect = "EFFECT_NORMAL_HIT" },
  SOLARBEAM = { id = "SOLARBEAM", name = "SOLARBEAM", power = 120,
    type = "GRASS", accuracy = 100, pp = 10,
    effect = "EFFECT_SOLARBEAM" },
  FLY = { id = "FLY", name = "FLY", power = 70, type = "FLYING",
    accuracy = 95, pp = 15, effect = "EFFECT_FLY" },
  DIG = { id = "DIG", name = "DIG", power = 60, type = "GROUND",
    accuracy = 100, pp = 10, effect = "EFFECT_FLY" },
}

local G2_DATA = {
  pokemon = {
    growthRates = {
      GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
        linear = 0, constant = 0 },
    },
    MACHOP = {
      id = "MACHOP", index = 66, name = "MACHOP",
      baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
        specialAttack = 35, specialDefense = 35 },
      types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
      growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 63,
      levelMoves = {}, evolutions = {},
    },
  },
  moves = G2_MOVES,
  type_chart = { types = G2_TYPES, matchups = {} },
  items = {},
}

local G2_DVS = { attack = 15, defense = 15, speed = 15, special = 15 }
G2_DVS.hp = Gen2Mon.hpDV(G2_DVS)

local function gen2Battle(moveId, weather)
  local player = Gen2Mon.new(G2_DATA, "MACHOP", 30, { dvs = G2_DVS })
  local move = { id = moveId, pp = 10, maxPp = 10 }
  player.moves = { move }
  local wild = Gen2Mon.new(G2_DATA, "MACHOP", 20, { dvs = G2_DVS })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Gen2Battle.new({ data = G2_DATA, party = { player },
    wild = wild, random = function(n) return math.max(0, (n or 1) - 1) end })
  battle.weather = weather
  return battle, player, wild, move
end

-- No-mod parity: Red always charges a charge-capable move on initial use,
-- spends PP only on that initial use, and resolves on the continuation.
do
  local run = T.sdk.loadNone()
  local battle, player, enemy, move = gen1Battle(gen1Data(), "SOLARBEAM")
  local hp = enemy.mon.hp
  battle:performMove(player, enemy, move)
  T.eq(enemy.mon.hp, hp, "Gen 1 no-mod initial SolarBeam only charges")
  T.eq(player.charging, move, "Gen 1 no-mod stores the selected move")
  T.eq(move.pp, 9, "Gen 1 no-mod charge spends one PP")
  T.check(queueHasText(battle, "took in sunlight"),
    "Gen 1 no-mod keeps the charge text")
  battle:performMove(player, enemy, move)
  T.check(enemy.mon.hp < hp, "Gen 1 no-mod continuation resolves damage")
  T.eq(move.pp, 9, "Gen 1 no-mod continuation spends no second PP")
  run.release()
end

-- No-mod parity: Gold's native answer remains weather-sensitive.  Solarbeam
-- charges without sun and skips charge under sun.
do
  local run = T.sdk.loadNone({ generation = 2 })
  local battle, player, wild, move = gen2Battle("SOLARBEAM")
  local hp = wild.hp
  battle:useMove(player, wild, "SOLARBEAM")
  T.eq(wild.hp, hp, "Gold no-mod initial Solarbeam charges without sun")
  T.eq(player.volatile.chargeMove, "SOLARBEAM",
    "Gold no-mod stores Solarbeam without sun")
  T.eq(move.pp, 9, "Gold no-mod charge spends one PP")
  battle:useMove(player, wild, "SOLARBEAM")
  T.check(wild.hp < hp, "Gold no-mod continuation resolves damage")
  T.eq(player.volatile.chargeMove, nil,
    "Gold no-mod continuation clears stored charge state")
  T.eq(move.pp, 9, "Gold no-mod continuation spends no second PP")

  battle, player, wild, move = gen2Battle("SOLARBEAM", "sun")
  hp = wild.hp
  battle:useMove(player, wild, "SOLARBEAM")
  T.check(wild.hp < hp, "Gold no-mod sun skips Solarbeam charge")
  T.eq(player.volatile.chargeMove, nil,
    "Gold no-mod sun stores no charge continuation")
  T.eq(move.pp, 9, "Gold no-mod sun still spends exactly one PP")
  run.release()
end

local MOD = {
  ["mods/charge_probe/manifest.json"] = [[{
    "id": "charge_probe",
    "name": "Charge Required Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2,
    "games": ["all"]
  }]],
  ["mods/charge_probe/main.lua"] = [[
    local mod = ...
    mod.hooks:wrap("battle.charge_required", function(nextFn, ctx)
      mod.exports.calls = (mod.exports.calls or 0) + 1
      mod.exports.last = {
        battle = ctx.battle ~= nil,
        user = ctx.user ~= nil,
        target = ctx.target ~= nil,
        move = ctx.move and ctx.move.id,
        charge = ctx.charge,
        isCalled = ctx.isCalled,
      }
      if ctx.move.id == "SOLARBEAM" then return false end
      return nextFn(ctx)
    end)
  ]],
}

-- Public mod API, Gen 1: one conditional false resolves through the ordinary
-- damage pipeline on the first turn.  Fly and Dig keep their vanilla charge
-- state, invulnerability, PP, and text; the release does not call the hook.
do
  local run = T.sdk.loadMods({ "mods/charge_probe" }, {
    fs = T.sdk.memfs(MOD),
  })
  T.eq(#run.errors, 0,
    "the public charge hook mod loads clean (" .. tostring(run.errors[1]) .. ")")
  local data = gen1Data()
  local battle, player, enemy, move = gen1Battle(data, "SOLARBEAM")
  local hp = enemy.mon.hp
  battle:performMove(player, enemy, move)
  T.check(enemy.mon.hp < hp,
    "a public Gen 1 hook can resolve SolarBeam on its initial use")
  T.eq(move.pp, 9, "the one-turn Gen 1 resolution spends one PP")
  T.eq(player.charging, nil, "the bypass creates no Gen 1 continuation")
  T.check(not queueHasText(battle, "took in sunlight"),
    "the bypass emits no Gen 1 charge text")

  local out = run.loader.exports.charge_probe or {}
  T.eq(out.calls, 1, "the public Gen 1 hook fires once on initial use")
  T.same(out.last, {
    battle = true, user = true, target = true, move = "SOLARBEAM",
    charge = true, isCalled = false,
  }, "the public Gen 1 hook receives the generation-neutral context")

  for _, id in ipairs({ "FLY", "DIG" }) do
    battle, player, enemy, move = gen1Battle(data, id)
    local beforeCalls = out.calls or 0
    battle:performMove(player, enemy, move)
    T.eq(player.charging, move, id .. " still charges through next(ctx)")
    T.eq(player.invulnerable, true, id .. " still becomes invulnerable")
    T.eq(move.pp, 9, id .. " still spends one PP on its charge turn")
    T.check(queueHasText(battle, id == "FLY" and "flew up" or "dug a hole"),
      id .. " still emits its charge text")
    T.eq(out.calls, beforeCalls + 1, id .. " calls the hook on initial use")
    battle:performMove(player, enemy, move)
    T.eq(out.calls, beforeCalls + 1,
      id .. " release does not call the initial-use hook again")
    T.eq(move.pp, 9, id .. " release spends no second PP")
  end

  -- Called charge-capable moves get the same initial-use seam and say so.
  battle, player, enemy, move = gen1Battle(data, "FLY")
  battle:performMove(player, enemy, move, true)
  out = run.loader.exports.charge_probe or {}
  T.eq(out.last and out.last.isCalled, true,
    "the Gen 1 context marks a called charge move")
  T.eq(move.pp, 10, "a called Gen 1 charge move keeps called-move PP semantics")
  run.release()
end

-- Public mod API, Gold: the same wrapper bypasses the ordinary no-sun charge
-- branch, preserves one PP spend, and emits no charge text.
do
  local run = T.sdk.loadMods({ "mods/charge_probe" }, {
    fs = T.sdk.memfs(MOD), generation = 2,
  })
  T.eq(#run.errors, 0,
    "the shared charge hook mod loads clean on Gold")
  local battle, player, wild, move = gen2Battle("SOLARBEAM")
  local hp = wild.hp
  battle:useMove(player, wild, "SOLARBEAM")
  T.check(wild.hp < hp,
    "the public Gold hook resolves Solarbeam on its initial use")
  T.eq(move.pp, 9, "the one-turn Gold resolution spends one PP")
  T.eq(player.volatile.chargeMove, nil,
    "the bypass creates no Gold charge continuation")
  T.check(not eventHasText(battle, "took in sunlight"),
    "the bypass emits no Gold charge text")
  local out = run.loader.exports.charge_probe or {}
  T.same(out.last, {
    battle = true, user = true, target = true, move = "SOLARBEAM",
    charge = true, isCalled = false,
  }, "Gold receives the same generation-neutral hook context")

  local calls = out.calls
  battle, player, wild, move = gen2Battle("DIG")
  hp = wild.hp
  battle:useMove(player, wild, "DIG")
  T.eq(wild.hp, hp, "Gold next(ctx) keeps the initial charge turn")
  T.eq(player.volatile.chargeMove, "DIG",
    "Gold next(ctx) stores the selected charge move")
  T.eq(player.volatile.vanished, true,
    "Gold next(ctx) preserves semi-invulnerability")
  T.eq(move.pp, 9, "Gold next(ctx) spends one PP on the charge turn")
  T.eq(out.calls, calls + 1,
    "Gold next(ctx) invokes the hook once on initial use")
  battle:useMove(player, wild, "DIG")
  T.check(wild.hp < hp, "Gold next(ctx) release resolves damage")
  T.eq(out.calls, calls + 1,
    "Gold release does not invoke the charge hook again")
  T.eq(move.pp, 9, "Gold release spends no second PP")

  calls = out.calls
  battle, player, wild, move = gen2Battle("TACKLE")
  battle.copyDepth = 1
  battle:useMove(player, wild, "FLY")
  T.eq(out.calls, calls + 1, "a called Gold charge move invokes the hook")
  T.eq(out.last and out.last.isCalled, true,
    "the Gold context marks a called charge move")
  T.eq(move.pp, 10, "a called Gold move spends no known-move PP")
  T.eq(player.volatile.chargeMove, "FLY",
    "a called Gold charge move can keep its charge through next(ctx)")

  calls = out.calls
  battle, player, wild, move = gen2Battle("SOLARBEAM", "sun")
  hp = wild.hp
  battle:useMove(player, wild, "SOLARBEAM")
  T.check(wild.hp < hp,
    "Gold native sun still resolves before the public charge decision")
  T.eq(out.calls, calls,
    "the hook does not run when the active rules already skip charge")
  run.release()
end

-- Guard parity: with no subscriber, neither generation reaches Runtime.call;
-- both take their vanilla decision without constructing/dispatching a ctx.
do
  local battle, player, enemy, move = gen1Battle(gen1Data(), "SOLARBEAM")
  local battle2, player2, enemy2 = gen2Battle("SOLARBEAM")
  local oldWants, oldCall = Runtime.wantsHook, Runtime.call
  Runtime.wantsHook = function(name)
    T.eq(name, "battle.charge_required", "the Gen 1 guard checks the hook name")
    return false
  end
  Runtime.call = function()
    error("unsubscribed charge hot path dispatched", 0)
  end
  local ok, err = pcall(battle.performMove, battle, player, enemy, move)
  T.check(ok, "the guarded Gen 1 hot path does not dispatch: " .. tostring(err))

  Runtime.wantsHook = function(name)
    T.eq(name, "battle.charge_required", "the Gold guard checks the hook name")
    return false
  end
  ok, err = pcall(battle2.useMove, battle2, player2, enemy2, "SOLARBEAM")
  T.check(ok, "the guarded Gold hot path does not dispatch: " .. tostring(err))
  Runtime.wantsHook, Runtime.call = oldWants, oldCall
end

T.finish("battle charge required")
