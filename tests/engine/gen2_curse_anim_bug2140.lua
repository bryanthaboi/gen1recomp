-- engine/battle_anims/bg_effects.asm:2480-2519
-- engine/battle/effect_commands.asm:1947

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local BgEffects = require("src.battle.gen2.BgEffects")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

-- constants/battle_anim_constants.asm:836
local BG_EFFECT_TARGET, BG_EFFECT_USER = 0, 1

-- data/moves/animations.asm:3255 FADE_MON_TO_LIGHT
local function fadeToLight(battleTurn, turn)
  local bg = BgEffects.new({}, { battleTurn = battleTurn })
  local st = bg:queue("BATTLE_BG_EFFECT_FADE_MON_TO_LIGHT", 0, turn, 0x40)
  return bg, st
end

do
  local bg = fadeToLight(1, BG_EFFECT_USER)
  for _ = 1, 40 do bg:playFrame() end
  eq(bg.monShade.enemy, 0x40, "the user (enemy turn) is light after 40 frames")
  eq(bg.monShade.player, 0xe4, "and the player's mon is untouched")
  eq(bg:activeCount(), 1, "the effect is still live on the $ff terminator")
  for _ = 1, 60 do bg:playFrame() end
  eq(bg.monShade.enemy, 0x40, "still held 60 frames later")
  eq(bg:activeCount(), 1, "and still live")
  bg:incEffect("BATTLE_BG_EFFECT_FADE_MON_TO_LIGHT")
  bg:playFrame()
  eq(bg.monShade.enemy, 0xe4, "anim_incbgeffect restores $e4")
  eq(bg:activeCount(), 0, "and ends the effect")
end

do
  local bg = fadeToLight(0, BG_EFFECT_USER)
  for _ = 1, 40 do bg:playFrame() end
  eq(bg.monShade.player, 0x40, "the user (player turn) is light after 40 frames")
  eq(bg.monShade.enemy, 0xe4, "and the enemy's mon is untouched")
end

do
  local bg = fadeToLight(0, BG_EFFECT_TARGET)
  for _ = 1, 40 do bg:playFrame() end
  eq(bg.monShade.enemy, 0x40, "BG_EFFECT_TARGET on the player's turn is the enemy")
  eq(bg.monShade.player, 0xe4, "the player's mon is untouched")
end

do
  local bg = fadeToLight(0, BG_EFFECT_USER)
  local seen = {}
  for _ = 1, 40 do
    bg:playFrame()
    local shade = bg.monShade.player
    if seen[#seen] ~= shade then seen[#seen + 1] = shade end
  end
  eq(table.concat(seen, ","), "228,144,64", "the list walks e4 / 90 / 40 once")
end

do
  local bg = BgEffects.new({}, { battleTurn = 0 })
  bg:queue("BATTLE_BG_EFFECT_FADE_MON_TO_BLACK_REPEATING", 0, BG_EFFECT_USER, 0x40)
  for _ = 1, 64 do bg:playFrame() end
  eq(bg:activeCount(), 1, "the repeating fade keeps running")
  check(bg.monShade.player ~= nil, "and shades the player's mon")
  bg:incEffect("BATTLE_BG_EFFECT_FADE_MON_TO_BLACK_REPEATING")
  bg:playFrame()
  eq(bg.monShade.player, 0xe4, "incbgeffect restores it")
end

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
}
local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  GROWL = { id = "GROWL", name = "GROWL", power = 0, type = "NORMAL",
    accuracy = 100, pp = 40, effect = "EFFECT_ATTACK_DOWN" },
  CURSE = { id = "CURSE", name = "CURSE", power = 0, type = "NORMAL",
    accuracy = 0, pp = 10, effect = "EFFECT_CURSE" },
  SPLASH = { id = "SPLASH", name = "SPLASH", power = 0, type = "NORMAL",
    accuracy = 100, pp = 40, effect = "EFFECT_SPLASH" },
  SWORDS_DANCE = { id = "SWORDS_DANCE", name = "SWORDS DANCE", power = 0,
    type = "NORMAL", accuracy = 0, pp = 30, effect = "EFFECT_ATTACK_UP_2" },
}
local POKEMON = {
  growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1,
    squared = 0, linear = 0, constant = 0 } },
  SNORLAX = {
    id = "SNORLAX", index = 143, name = "SNORLAX",
    baseStats = { hp = 160, attack = 110, defense = 65, speed = 30,
      specialAttack = 65, specialDefense = 110 },
    types = { "NORMAL", "NORMAL" }, catchRate = 25, baseExp = 154,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}
local DATA = { pokemon = POKEMON, moves = MOVES,
  type_chart = { types = TYPES, matchups = {} }, items = {} }
local dvs = { attack = 15, defense = 15, speed = 15, special = 15 }
dvs.hp = Mon.hpDV(dvs)

local function moveEvent(moveId, roll, setup)
  local player = Mon.new(DATA, "SNORLAX", 30, { dvs = dvs })
  player.moves = { { id = moveId, pp = 10, maxPp = 10 } }
  local wild = Mon.new(DATA, "SNORLAX", 30, { dvs = dvs })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = function() return roll or 0 end })
  if setup then setup(battle) end
  battle:useMove(player, wild, moveId)
  for _, event in ipairs(battle:takeEvents()) do
    if event.kind == "move" then return event, battle end
  end
  return nil, battle
end

do
  local ev = moveEvent("CURSE")
  check(ev ~= nil, "CURSE emits a move event")
  check(ev and ev.afterAnim == nil, "Curse: no after-anim (curse.asm:36 AnimateCurrentMove)")
  ev = moveEvent("SPLASH")
  check(ev and ev.afterAnim == nil, "Splash: no after-anim")
  ev = moveEvent("SWORDS_DANCE")
  check(ev and ev.afterAnim == nil, "statupanim: no after-anim")
  ev = moveEvent("TACKLE")
  eq(ev and ev.afterAnim, "damage", "moveanim: the damage shake")
  ev = moveEvent("GROWL")
  eq(ev and ev.afterAnim, "statdown", "statdownanim: the stat-down wobble")
end

-- engine/battle/effect_commands.asm:1958
love = require("tests.love_stub")
local BattleState = require("src.ui.gen2.BattleState")
local Input = require("src.core.Input")

local function screenFor(battle)
  Input:init()
  local pushed = {}
  local game = {
    data = DATA, save = { party = battle.party, inventory = {} },
    input = Input, options = {},
    stack = {
      push = function(_, screen) pushed[#pushed + 1] = screen end,
      pop = function() table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
    },
  }
  local screen = BattleState.new(game, { battle = battle, save = game.save })
  screen.startAnim = function() return true end
  return screen
end

local function evasive(battle) battle.stages.enemy.evasion = 6 end

do
  local ev, battle = moveEvent("GROWL", 0, evasive)
  check(ev and not ev.missed, "Growl through +6 evasion lands on a 0 roll")
  local screen = screenFor(battle)
  screen.queue = { ev }
  screen:advanceQueue()
  eq(screen.pendingAfterAnim and screen.pendingAfterAnim.name,
    "ANIM_ENEMY_STAT_DOWN", "a landed Growl queues the target's wobble")

  ev, battle = moveEvent("GROWL", 99, evasive)
  check(ev and ev.missed, "and misses on a 99 roll")
  eq(ev and ev.afterAnim, "statdown", "the event still names statdownanim")
  screen = screenFor(battle)
  screen.queue = { ev }
  screen:advanceQueue()
  eq(screen.pendingAfterAnim, nil, "but a missed Growl queues no wobble")
end

T.finish("gen2 curse anim bug 2140")
