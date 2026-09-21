local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_moveteach_multiselect"

local COLOSSEUM = "FR_BATTLE_COLOSSEUM_2P"
local BULBASAUR, CHARMANDER, SQUIRTLE = 1, 4, 7
local PIDGEY, RATTATA, CATERPIE = 16, 19, 10

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/moveteach_multiselect.log", "a")
  if fh then
    fh:write(line, "\n")
    fh:close()
  end
end

local function result(ok, label)
  say((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    say("PASS moveteach_multiselect")
    love.event.quit(0)
  else
    say("FAIL moveteach_multiselect failures=" .. failures)
    love.event.quit(1)
  end
end

local function show(list)
  local parts = {}
  for i = 1, #(list or {}) do parts[i] = tostring(list[i]) end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function run(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Ctx = require("src.core.game3.scripting.ctx")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local Natives = require("src.core.game3.scripting.natives")
  local Std = require("src.core.game3.scripting.stdscripts")
  local Tower = require("src.core.game3.trainer_tower")
  local PartyMenu = require("src.ui.game3.party_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  session.party = {}
  for _, sp in ipairs({ BULBASAUR, CHARMANDER, SQUIRTLE, PIDGEY, RATTATA, CATERPIE }) do
    Party.giveMon(session, sp, 20)
  end
  result(#session.party == 6, "a full party of six is in the save, got " .. tostring(#session.party))
  session.party[4].hp = 0

  Map.load(nil, game, COLOSSEUM, { x = 6, y = 8, facing = "up" })
  Player.cellX, Player.cellY = 6, 8
  Player.px, Player.py = 6 * 16, 8 * 16
  Player.targetX, Player.targetY = 6, 8
  Player.facing = "up"
  if game.session then
    game.session.x, game.session.y, game.session.facing = 6, 8, "up"
  end
  U.wait(90)

  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  local adapters = Space.vm and Space.vm.adapters

  -- pokefirered/src/script_pokemon_util.c:152 ChooseHalfPartyForBattle
  local yielded = Natives.special(ctx, Std.SPECIAL.ChooseHalfPartyForBattle, adapters)
  U.wait(30)
  result(yielded == true, "the caller waits while the picker is up")
  local opened = false
  for _ = 1, 60 do
    if PartyMenu.isOpen() and PartyMenu.mode == "choose_multi" then opened = true break end
    U.wait(6)
  end
  result(opened, "the party menu opened in choose_multi, mode=" .. tostring(PartyMenu.mode))
  if not opened then
    U.shot(game, DIR .. "/moveteach_multiselect_01_no_picker.png")
    return
  end
  U.shot(game, DIR .. "/moveteach_multiselect_01_able_list.png")

  local function enter()
    U.tap(game, "a")
    U.wait(12)
    U.tap(game, "a")
    U.wait(12)
  end

  enter()
  result(#PartyMenu.chosenOrder() == 1,
    "the lead mon is entered FIRST, got " .. show(PartyMenu.chosenOrder()))
  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "down")
  U.wait(10)
  enter()
  U.shot(game, DIR .. "/moveteach_multiselect_02_first_second.png")

  U.tap(game, "down")
  U.wait(10)
  U.tap(game, "a")
  U.wait(12)
  result(PartyMenu.ACTIONS[1] == "SUMMARY" and #PartyMenu.ACTIONS == 2,
    "the fainted slot 4 is NOT ABLE and offers only SUMMARY / CANCEL, got "
      .. show(PartyMenu.ACTIONS))
  U.tap(game, "b")
  U.wait(12)

  U.tap(game, "down")
  U.wait(10)
  enter()
  local order = PartyMenu.chosenOrder()
  result(#order == 3 and order[1] == 1 and order[2] == 3 and order[3] == 5,
    "three mons are entered in order, got " .. show(order))
  result(PartyMenu.cursor == 7, "the cursor jumped to CONFIRM, got " .. tostring(PartyMenu.cursor))
  U.wait(20)
  U.shot(game, DIR .. "/moveteach_multiselect_03_third_confirm.png")

  U.tap(game, "a")
  U.wait(30)
  result(not PartyMenu.isOpen(), "CONFIRM closed the picker")
  result(ctx.nativePoll and ctx.nativePoll() == true, "and the caller resumed")
  result(Flags.getVar(nil, ctx, 0x800D) == 1,
    "VAR_RESULT is TRUE after a real pick, got " .. tostring(Flags.getVar(nil, ctx, 0x800D)))
  -- pokefirered/src/party_menu.c:413 gSelectedOrderFromParty
  local picked = Tower.selectedOrder(session)
  result(picked[1] == 1 and picked[2] == 3 and picked[3] == 5,
    "the chosen order reached the session, got " .. show(picked))

  local ctx2 = Ctx.new({})
  ctx2.mode = "bytecode"
  ctx2.status = "running"
  Natives.special(ctx2, Std.SPECIAL.ChooseHalfPartyForBattle, adapters)
  U.wait(30)
  local reopened = PartyMenu.isOpen() and PartyMenu.mode == "choose_multi"
  result(reopened, "the picker reopens for the cancel path")
  if reopened then
    U.tap(game, "b")
    U.wait(18)
    U.shot(game, DIR .. "/moveteach_multiselect_04_cancel_battle.png")
    U.tap(game, "a")
    U.wait(30)
    result(not PartyMenu.isOpen(), "answering YES closed the picker")
    result(Flags.getVar(nil, ctx2, 0x800D) == 0,
      "VAR_RESULT is FALSE after a cancel, got " .. tostring(Flags.getVar(nil, ctx2, 0x800D)))
    local cleared = Tower.selectedOrder(session)
    result(cleared[1] == 0 and cleared[2] == 0 and cleared[3] == 0,
      "and no order is left on the session, got " .. show(cleared))
  end
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL moveteach_multiselect driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
