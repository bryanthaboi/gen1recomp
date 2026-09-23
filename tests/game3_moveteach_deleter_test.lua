#!/usr/bin/env luajit
-- pokefirered/src/party_menu_specials.c:44, :50, :61, :92

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function finish()
  if failed > 0 then
    print(string.format("[FAIL] %d check(s) failed", failed))
    os.exit(1)
  end
  print("[PASS] game3_moveteach_deleter")
  os.exit(0)
end

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("pokemon/learnsets.lua")
if not cacheRoot then
  print("[skip] game3_moveteach_deleter: " .. tostring(Cache.reason))
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)

local MoveLearn = require("src.core.game3.move_learn")
local Natives = require("src.core.game3.scripting.natives")
local SummaryMenu = require("src.ui.game3.summary_menu")
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")

local TACKLE, GROWL, LEECH_SEED, VINE_WHIP = 33, 45, 73, 22
local CUT = 15
local BULBASAUR = 1

local function monAt(species, level)
  local moves, pp, maxPp = Pokemon.movesAtLevel(species, level)
  return { species = species, level = level, moves = moves, pp = pp, maxPp = maxPp }
end

local function fourMoveMon()
  local mon = monAt(BULBASAUR, 50)
  mon.moves = { TACKLE, GROWL, LEECH_SEED, VINE_WHIP }
  mon.pp = { 35, 40, 10, 25 }
  mon.maxPp = { 35, 40, 10, 25 }
  return mon
end

print("[test] 1. MoveDeleterForgetMove clears the slot and shifts the rest up")
do
  local mon = fourMoveMon()
  check(MoveLearn.forgetMove(mon, 1) == true, "forgetting move slot 1 (0-based) reports success")
  check(Pokemon.moveIdAt(mon, 1) == TACKLE, "slot 1 still holds TACKLE, got "
    .. tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 1))))
  check(Pokemon.moveIdAt(mon, 2) == LEECH_SEED, "LEECH SEED shifted down into slot 2, got "
    .. tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 2))))
  check(Pokemon.moveIdAt(mon, 3) == VINE_WHIP, "VINE WHIP shifted down into slot 3, got "
    .. tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 3))))
  check(Pokemon.moveIdAt(mon, 4) == nil, "slot 4 is now empty")
  check(mon.pp[2] == 10 and mon.pp[3] == 25, "PP travelled with the shifted moves, got "
    .. tostring(mon.pp[2]) .. "/" .. tostring(mon.pp[3]))
  check(mon.maxPp[4] == nil and mon.pp[4] == nil, "the freed slot carries no PP")
  check(Pokemon.moveSlotCount(mon) == 3, "the mon knows three moves, got "
    .. tostring(Pokemon.moveSlotCount(mon)))
end

print("[test] 2. deleting the last slot leaves the others alone")
do
  local mon = fourMoveMon()
  MoveLearn.forgetMove(mon, 3)
  check(Pokemon.moveIdAt(mon, 4) == nil and Pokemon.moveIdAt(mon, 3) == LEECH_SEED,
    "VINE WHIP is gone and slot 3 still holds "
      .. tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 3))))
  check(MoveLearn.forgetMove(mon, 3) == false, "deleting an empty slot does nothing")
  check(MoveLearn.forgetMove(mon, 4) == false, "an out of range slot does nothing")
end

print("[test] 3. PP Ups ride along with the shift")
do
  local mon = fourMoveMon()
  mon.ppBonuses = { 0, 3, 1, 0 }
  MoveLearn.forgetMove(mon, 1)
  check(mon.ppBonuses[2] == 1, "the third slot's PP Up bonus moved to slot 2, got "
    .. tostring(mon.ppBonuses[2]))
  check(mon.ppBonuses[4] == nil, "and the freed slot has none")

  local packed = fourMoveMon()
  -- pokefirered/src/pokemon.c:3904 RemoveMonPPBonus
  packed.ppBonusesPacked = 0 + (3 * 4) + (1 * 16)
  MoveLearn.forgetMove(packed, 1)
  check(bit.band(bit.rshift(packed.ppBonusesPacked, 2), 3) == 1,
    "the packed bonus shifted down too, got "
      .. tostring(bit.band(bit.rshift(packed.ppBonusesPacked, 2), 3)))
end

print("[test] 4. GetNumMovesSelectedMonHas feeds the one-move branch")
do
  local prevRuntime = package.loaded["src.core.game3.runtime"]
  local party = { fourMoveMon(), monAt(BULBASAUR, 5) }
  party[2].moves = { TACKLE }
  party[2].pp = { 35 }
  party[2].maxPp = { 35 }
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return { party = party } end,
    isActive = function() return true end,
  }

  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  local handled = select(3, Natives.special(ctx, 0xDF, { log = function() end }))
  check(handled == true, "special 0xDF is bound (pokefirered/data/specials.inc:234)")
  check(Flags.getVar(nil, ctx, 0x800D) == 4,
    "VAR_RESULT is the four known moves, got " .. tostring(Flags.getVar(nil, ctx, 0x800D)))

  Flags.setVar(nil, ctx, 0x8004, 1)
  Natives.special(ctx, 0xDF, { log = function() end })
  check(Flags.getVar(nil, ctx, 0x800D) == 1,
    "the one-move mon reports 1, which is the script's CantForgetOnlyMove branch, got "
      .. tostring(Flags.getVar(nil, ctx, 0x800D)))

  package.loaded["src.core.game3.runtime"] = prevRuntime
end

print("[test] 5. BufferMoveDeleterNicknameAndMove fills STR_VAR_1 and STR_VAR_2")
do
  local prevRuntime = package.loaded["src.core.game3.runtime"]
  local mon = fourMoveMon()
  mon.nickname = "SPROUT"
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return { party = { mon } } end,
    isActive = function() return true end,
  }

  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  Flags.setVar(nil, ctx, 0x8005, 2)
  local buffered = {}
  local handled = select(3, Natives.special(ctx, 0xDE, {
    log = function() end,
    setStringVar = function(idx, text) buffered[idx] = text end,
  }))
  check(handled == true, "special 0xDE is bound (pokefirered/data/specials.inc:233)")
  check(buffered[1] == "SPROUT", "STR_VAR_1 is the nickname, got " .. tostring(buffered[1]))
  check(buffered[2] == Pokemon.moveName(LEECH_SEED),
    "STR_VAR_2 is the move in VAR_0x8005, got " .. tostring(buffered[2]))
  check(ctx.stringVars[1] == "SPROUT" and ctx.stringVars[2] == buffered[2],
    "and the script ctx carries the same pair")

  package.loaded["src.core.game3.runtime"] = prevRuntime
end

print("[test] 6. SelectMoveDeleterMove drives the summary screen and MoveDeleterForgetMove")
do
  local prevRuntime = package.loaded["src.core.game3.runtime"]
  local mon = fourMoveMon()
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return { party = { mon } } end,
    isActive = function() return true end,
  }

  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  local yielded = Natives.special(ctx, 0xDC, { log = function() end })
  check(yielded == true, "the script waits while the summary screen is up")
  check(SummaryMenu.isOpen(), "special 0xDC opened the summary screen")

  local pressed = nil
  local input = { wasPressed = function(_, key) return key == pressed end }
  local function press(key)
    pressed = key
    SummaryMenu.handleInput(input)
    pressed = nil
  end

  press("down")
  press("a")
  check(not SummaryMenu.isOpen(), "picking a move closed the screen")
  check(ctx.nativePoll and ctx.nativePoll() == true, "and the script resumed")
  check(Flags.getVar(nil, ctx, 0x8005) == 1,
    "VAR_0x8005 is the chosen move slot, got " .. tostring(Flags.getVar(nil, ctx, 0x8005)))

  Natives.special(ctx, 0xDD, { log = function() end })
  check(Pokemon.moveIdAt(mon, 2) == LEECH_SEED,
    "special 0xDD deleted GROWL and shifted LEECH SEED up, got "
      .. tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 2))))
  check(Pokemon.moveSlotCount(mon) == 3, "three moves are left, got "
    .. tostring(Pokemon.moveSlotCount(mon)))

  package.loaded["src.core.game3.runtime"] = prevRuntime
end

print("[test] 7. backing out of the summary screen returns MAX_MON_MOVES")
do
  local prevRuntime = package.loaded["src.core.game3.runtime"]
  local mon = fourMoveMon()
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return { party = { mon } } end,
    isActive = function() return true end,
  }

  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  Natives.special(ctx, 0xDC, { log = function() end })
  local pressed = nil
  local input = { wasPressed = function(_, key) return key == pressed end }
  pressed = "b"
  SummaryMenu.handleInput(input)
  pressed = nil
  check(Flags.getVar(nil, ctx, 0x8005) == 4,
    "VAR_0x8005 is MAX_MON_MOVES so the script loops back to the mon chooser, got "
      .. tostring(Flags.getVar(nil, ctx, 0x8005)))
  check(Pokemon.moveSlotCount(mon) == 4, "nothing was deleted")

  package.loaded["src.core.game3.runtime"] = prevRuntime
end

print("[test] 8. the Move Deleter forgets an HM move")
do
  local prevRuntime = package.loaded["src.core.game3.runtime"]
  local mon = fourMoveMon()
  mon.moves[1] = CUT
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return { party = { mon } } end,
    isActive = function() return true end,
  }

  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  Natives.special(ctx, 0xDC, { log = function() end })
  local pressed = nil
  local input = { wasPressed = function(_, key) return key == pressed end }
  pressed = "a"
  SummaryMenu.handleInput(input)
  pressed = nil
  check(not SummaryMenu.isOpen(),
    "PSS_MODE_FORGET_MOVE accepts an HM (pokefirered/src/pokemon_summary_screen.c:3772)")
  check(SummaryMenu._hmNotice ~= true, "no HM refusal is printed")
  check(Flags.getVar(nil, ctx, 0x8005) == 0,
    "VAR_0x8005 is CUT's slot, got " .. tostring(Flags.getVar(nil, ctx, 0x8005)))
  Natives.special(ctx, 0xDD, { log = function() end })
  check(Pokemon.moveIdAt(mon, 1) == GROWL,
    "special 0xDD deleted CUT and shifted GROWL up, got "
      .. tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 1))))
  check(Pokemon.moveSlotCount(mon) == 3, "three moves are left, got "
    .. tostring(Pokemon.moveSlotCount(mon)))

  package.loaded["src.core.game3.runtime"] = prevRuntime
end

print("[test] 9. a move-learn summary screen still refuses an HM")
do
  local mon = fourMoveMon()
  mon.moves[1] = CUT
  local picked = "unset"
  SummaryMenu.openMenu({ mon }, 1, {
    mode = "select_move",
    moveToLearn = TACKLE,
    onSelectMove = function(slot) picked = slot end,
  })
  local pressed = nil
  local input = { wasPressed = function(_, key) return key == pressed end }
  pressed = "a"
  SummaryMenu.handleInput(input)
  pressed = nil
  check(SummaryMenu.isOpen(), "PSS_MODE_SELECT_MOVE keeps the screen up on an HM")
  check(SummaryMenu._hmNotice == true,
    "the HM refusal is printed (pokefirered/src/pokemon_summary_screen.c:3772)")
  check(picked == "unset", "no slot was reported")
  SummaryMenu.close()
end

print("[test] 10. the deleter cursor skips empty move slots onto CANCEL")
do
  local prevRuntime = package.loaded["src.core.game3.runtime"]
  local mon = monAt(BULBASAUR, 5)
  mon.moves = { TACKLE, GROWL }
  mon.pp = { 35, 40 }
  mon.maxPp = { 35, 40 }
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return { party = { mon } } end,
    isActive = function() return true end,
  }

  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  Natives.special(ctx, 0xDC, { log = function() end })
  local pressed = nil
  local input = { wasPressed = function(_, key) return key == pressed end }
  local function press(key)
    pressed = key
    SummaryMenu.handleInput(input)
    pressed = nil
  end

  press("down")
  check(SummaryMenu._moveCursor == 2, "down lands on GROWL, got " .. tostring(SummaryMenu._moveCursor))
  press("down")
  check(SummaryMenu._moveCursor == 5,
    "down skips the two empty slots onto CANCEL (pokefirered/src/pokemon_summary_screen.c:3829), got "
      .. tostring(SummaryMenu._moveCursor))
  press("up")
  check(SummaryMenu._moveCursor == 2,
    "up from CANCEL skips back to GROWL (pokefirered/src/pokemon_summary_screen.c:3802), got "
      .. tostring(SummaryMenu._moveCursor))
  press("down")
  press("down")
  check(SummaryMenu._moveCursor == 1, "down from CANCEL wraps to slot 1, got "
    .. tostring(SummaryMenu._moveCursor))
  press("up")
  check(SummaryMenu._moveCursor == 5, "up from slot 1 wraps to CANCEL, got "
    .. tostring(SummaryMenu._moveCursor))
  press("a")
  check(not SummaryMenu.isOpen(), "A on CANCEL closes the screen")
  check(Flags.getVar(nil, ctx, 0x8005) == 4,
    "VAR_0x8005 is 4 on CANCEL, got " .. tostring(Flags.getVar(nil, ctx, 0x8005)))
  check(Pokemon.moveSlotCount(mon) == 2, "nothing was deleted")

  package.loaded["src.core.game3.runtime"] = prevRuntime
end

finish()
