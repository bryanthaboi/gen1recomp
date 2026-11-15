-- engine/battle/move_effects/safeguard.asm:1, engine/battle/effect_commands.asm:6325

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  ELECTRIC = { id = "ELECTRIC", index = 1, category = "special" },
  FIRE = { id = "FIRE", index = 2, category = "special" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, accuracyRaw = 255, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  SAFEGUARD = { id = "SAFEGUARD", name = "SAFEGUARD", power = 0,
    type = "NORMAL", accuracy = 100, accuracyRaw = 255, pp = 25, effect = "EFFECT_SAFEGUARD" },
  THUNDER_WAVE = { id = "THUNDER_WAVE", name = "THUNDER WAVE", power = 0,
    type = "ELECTRIC", accuracy = 100, accuracyRaw = 255, pp = 20, effect = "EFFECT_PARALYZE" },
  SACRED_FIRE = { id = "SACRED_FIRE", name = "SACRED FIRE", power = 100,
    type = "FIRE", accuracy = 95, accuracyRaw = 242, pp = 5, effect = "EFFECT_SACRED_FIRE",
    effectChance = 50, effectChanceRaw = 127 },
}

local POKEMON = {
  growthRates = {
    GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
      linear = 0, constant = 0 },
  },
  MACHOP = { id = "MACHOP", index = 66, name = "MACHOP",
    baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 63,
    levelMoves = {}, evolutions = {} },
}

local DATA = { pokemon = POKEMON, moves = MOVES,
  text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = TYPES, matchups = {} }, items = {} }

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local rolls
local function rng(n)
  if rolls and #rolls > 0 then return table.remove(rolls, 1) % math.max(1, n) end
  return (n or 1) - 1
end

local function newBattle(pmoves, emoves)
  local player = Mon.new(DATA, "MACHOP", 50, { dvs = perfect })
  player.moves = pmoves
  local wild = Mon.new(DATA, "MACHOP", 50, { dvs = perfect })
  wild.moves = emoves
  return Battle.new({ data = DATA, party = { player }, wild = wild,
    random = rng }), player, wild
end

local function findText(events, sub)
  for _, e in ipairs(events or {}) do
    if e.kind == "message" and e.text and e.text:find(sub, 1, true) then
      return true
    end
  end
  return false
end
local function moveEvent(events)
  for _, e in ipairs(events or {}) do
    if e.kind == "move" then return e end
  end
end

-- ------------------------------------------------------------- 1388a
-- Safeguard sets the USER's own side, not the target's.
do
  local battle, player, wild = newBattle(
    { { id = "SAFEGUARD", pp = 25, maxPp = 25 } },
    { { id = "THUNDER_WAVE", pp = 20, maxPp = 20 } })
  battle.events = {}
  battle:useMove(player, wild, "SAFEGUARD")
  T.eq(battle.screens.player.safeguard, 5, "Safeguard sets the CASTER's side for 5 turns")
  T.check((battle.screens.enemy.safeguard or 0) == 0,
    "and never touches the opposing side")
  T.check(findText(battle.events, "covered by a veil"), "the veil line is emitted")
end

do
  local battle, player, wild = newBattle(
    { { id = "SAFEGUARD", pp = 25, maxPp = 25 } },
    { { id = "THUNDER_WAVE", pp = 20, maxPp = 20 } })
  battle.events = {}
  battle:useMove(player, wild, "SAFEGUARD")
  battle.events = {}
  rolls = { 200 } -- force the enemy's AI roll not to fail on its own
  battle:useMove(wild, player, "THUNDER_WAVE")
  T.check(findText(battle.events, battle:romText("SafeguardProtectText", wild, player)),
    "an incoming status move from the OTHER side is blocked, loudly")
  T.eq(player.status, nil, "and the paralysis never lands")
  local ev = moveEvent(battle.events)
  T.eq(ev and ev.missed, true, "the blocked move is marked missed")
end

do
  local battle, player, wild = newBattle(
    { { id = "SAFEGUARD", pp = 25, maxPp = 25 } },
    { { id = "TACKLE", pp = 35, maxPp = 35 } })
  battle.events = {}
  battle:useMove(player, wild, "SAFEGUARD")
  battle.events = {}
  battle:useMove(player, wild, "SAFEGUARD")
  T.check(findText(battle.events, "But it failed!"),
    "using it again while it is already up simply fails")
end

do
  -- the player's OWN status move against a safeguarded enemy is blocked too:
  -- the effect reads whichever side is being TARGETED, not just "the enemy".
  local battle, player, wild = newBattle(
    { { id = "THUNDER_WAVE", pp = 20, maxPp = 20 } },
    { { id = "TACKLE", pp = 35, maxPp = 35 } })
  battle.screens.enemy.safeguard = 5
  battle.events = {}
  battle:useMove(player, wild, "THUNDER_WAVE")
  T.check(findText(battle.events, battle:romText("SafeguardProtectText", player, wild)),
    "the player's status move is blocked by the enemy's own safeguard")
  T.eq(wild.status, nil, "the enemy stays unstatused under its own screen")
end

do
  local battle = newBattle(
    { { id = "TACKLE", pp = 35, maxPp = 35 } },
    { { id = "TACKLE", pp = 35, maxPp = 35 } })
  battle.screens.player.safeguard = 1
  battle.events = {}
  battle:tickScreens()
  T.check(findText(battle.events, "SAFEGUARD faded"), "it fades after its five turns")
  T.eq(battle.screens.player.safeguard, nil, "and clears off the side entirely")
end

-- ------------------------------------------------------------- 1388b
-- Sacred Fire's burn was never implemented at all.
do
  local battle, player, wild = newBattle(
    { { id = "TACKLE", pp = 35, maxPp = 35 } },
    { { id = "SACRED_FIRE", pp = 5, maxPp = 5 } })
  battle.events = {}
  rolls = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } -- everything rolls low: hit, no
  -- crit, and the 50% secondary effect chance all pass
  battle:useMove(wild, player, "SACRED_FIRE")
  T.eq(player.status, "burn", "Sacred Fire can now burn its target")
end

do
  local battle, player, wild = newBattle(
    { { id = "TACKLE", pp = 35, maxPp = 35 } },
    { { id = "SACRED_FIRE", pp = 5, maxPp = 5 } })
  battle.screens.player.safeguard = 5
  battle.events = {}
  rolls = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
  battle:useMove(wild, player, "SACRED_FIRE")
  T.eq(player.status, nil, "Safeguard blocks the burn a damaging move carries")
  T.check(not findText(battle.events, "protected by SAFEGUARD"),
    "the secondary block is silent (SafeCheckSafeguard, not CheckSafeguard)")
  local ev = moveEvent(battle.events)
  T.check(ev and not ev.missed,
    "the hit itself still lands and is not marked missed")
end

T.finish("gen2 safeguard bug 1388")
