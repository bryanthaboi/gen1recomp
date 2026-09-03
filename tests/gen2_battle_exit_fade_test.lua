-- data/maps/setup_scripts.asm:127
-- home/fade.asm:35-62

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle exit fade")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local GbcPalette = require("src.render.GbcPalette")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")
local Music = require("src.core.Music")

local TYPES = { NORMAL = { id = "NORMAL", index = 0, category = "physical" } }
local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
}
local POKEMON = {
  growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1,
    squared = 0, linear = 0, constant = 0 } },
  RATTATA = {
    id = "RATTATA", index = 19, name = "RATTATA",
    baseStats = { hp = 30, attack = 56, defense = 35, speed = 72,
      specialAttack = 25, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 57,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}
local DATA = { pokemon = POKEMON, moves = MOVES,
  type_chart = { types = TYPES, matchups = {} }, items = {} }
local dvs = { attack = 15, defense = 15, speed = 15, special = 15 }
dvs.hp = Mon.hpDV(dvs)

local function newScreen()
  Input:init()
  local player = Mon.new(DATA, "RATTATA", 10, { dvs = dvs })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Mon.new(DATA, "RATTATA", 5, { dvs = dvs })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local save = { party = { player }, inventory = {} }
  local pushed = {}
  local game = {
    data = DATA, save = save, input = Input, options = {},
    stack = {
      push = function(_, screen) pushed[#pushed + 1] = screen end,
      pop = function() table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
    },
  }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = function() return 0 end })
  return BattleState.new(game, { battle = battle, save = save }), battle
end

eq(BattleState.EXIT_FADE_FRAMES, 8, "eight frames a row (home/fade.asm:57)")
eq(#BattleState.EXIT_FADE_ROWS, 3, "three rows (RotateThreePalettesRight)")
eq(BattleState.EXIT_FADE_ROWS[1], 0x90, "IncGradGBPalTable_05: dc 2,1,0,0")
eq(BattleState.EXIT_FADE_ROWS[2], 0x40, "IncGradGBPalTable_06: dc 1,0,0,0")
eq(BattleState.EXIT_FADE_ROWS[3], 0x00, "IncGradGBPalTable_07: dc 0,0,0,0")
eq(BattleState.EXIT_MUSIC_FADE, 4, "wMusicFade = 4 (map_setup.asm:186)")

do
  local screen, battle = newScreen()
  battle.outcome = "win"
  local doneAt
  local ticks = 0
  screen.onDone = function(outcome) doneAt = ticks; screen.doneOutcome = outcome end
  local faded
  local realFade = Music.fadeOut
  Music.fadeOut = function(control) faded = control end
  screen:finishBattle()
  Music.fadeOut = realFade
  eq(screen.phase, "fadeout", "ExitBattle enters the fade-out, not done")
  eq(faded, 4, "the battle music starts fading at wMusicFade 4")
  eq(doneAt, nil, "onDone has not fired yet")
  eq(screen:exitFadeBgp(), 0x90, "the first row is up before the first tick")

  local rows = {}
  for _ = 1, 24 do
    ticks = ticks + 1
    Input:step()
    screen:update(1 / 60)
    rows[ticks] = screen:exitFadeBgp()
    if ticks < 24 then
      eq(screen.phase, "fadeout", "still fading at tick " .. ticks)
    end
  end
  for tick = 1, 7 do eq(rows[tick], 0x90, "row 1 through tick " .. tick) end
  for tick = 8, 15 do eq(rows[tick], 0x40, "row 2 through tick " .. tick) end
  for tick = 16, 23 do eq(rows[tick], 0x00, "row 3 through tick " .. tick) end
  eq(doneAt, 24, "onDone fires on the 24th tick")
  eq(screen.phase, "done", "and the screen is done")
  eq(screen.doneOutcome, "win", "with the battle's outcome")
  eq(rows[24], nil, "no row once the battle is done")
  Input:step()
  screen:update(1 / 60)
  eq(doneAt, 24, "a later tick does not fire onDone again")
end

do
  local screen, battle = newScreen()
  battle.outcome = "run"
  local realFade = Music.fadeOut
  Music.fadeOut = function() end
  screen:finishBattle()
  Music.fadeOut = realFade
  screen.fadeTick = 9
  local seen
  screen.drawSceneBody = function() seen = GbcPalette.bgp end
  screen:drawScene()
  eq(seen, 0x40, "drawScene sets rBGP to the fade row")
  eq(GbcPalette.bgp, nil, "and restores it afterwards")
  screen.phase = "menu"
  screen:drawScene()
  eq(seen, nil, "outside the fade the scene draws through the identity")
end

-- engine/events/whiteout.asm:12-13
eq(BattleState.WHITEOUT_FADE_FRAMES, 2, "FadeOutToWhite: two frames a row")
eq(#BattleState.WHITEOUT_FADE_ROWS, 4, "ld b, $4")
eq(BattleState.WHITEOUT_FADE_ROWS[1], 0xe4, ".cgbfade: dc 3,2,1,0")
eq(BattleState.WHITEOUT_FADE_ROWS[4], 0x00, ".cgbfade: dc 0,0,0,0")
eq(BattleState.WHITEOUT_HOLD_FRAMES, 40, "pause 40")

do
  local screen, battle = newScreen()
  battle.outcome = "lose"
  local doneAt
  local ticks = 0
  screen.onDone = function() doneAt = ticks end
  local faded = false
  local realFade = Music.fadeOut
  Music.fadeOut = function() faded = true end
  screen:finishBattle()
  Music.fadeOut = realFade
  eq(screen.phase, "fadeout", "a whiteout still fades on the battle screen")
  eq(faded, false, "Script_Whiteout fades no music")
  local rows = {}
  for _ = 1, 48 do
    ticks = ticks + 1
    Input:step()
    screen:update(1 / 60)
    rows[ticks] = screen:exitFadeBgp()
  end
  eq(rows[1], 0xe4, "row 1 on tick 1")
  eq(rows[2], 0x90, "row 2 on tick 2")
  eq(rows[4], 0x40, "row 3 on tick 4")
  eq(rows[6], 0x00, "row 4 on tick 6")
  eq(rows[47], 0x00, "held white through the pause")
  eq(doneAt, 48, "onDone fires after 8 + 40 frames")
  eq(rows[48], nil, "no row once the battle is done")
end

do
  local screen, battle = newScreen()
  battle.outcome = "lose"
  battle.battleType = Battle.BATTLETYPE_CANLOSE
  local faded = false
  local realFade = Music.fadeOut
  Music.fadeOut = function() faded = true end
  screen:finishBattle()
  Music.fadeOut = realFade
  eq(faded, true, "BATTLETYPE_CANLOSE loses through the ReloadMap fade")
  eq(screen:exitFadeLength(), 24, "over 24 frames")
end

S.finish()
