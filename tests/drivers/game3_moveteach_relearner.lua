local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_moveteach_relearner"

local HOUSE = "FR_TWO_ISLAND_HOUSE"
local MANIAC_X, MANIAC_Y = 7, 5
-- pokefirered/include/constants/items.h:108
local ITEM_BIG_MUSHROOM = 104
local BULBASAUR = 1

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/moveteach_relearner.log", "a")
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
    say("PASS moveteach_relearner")
    love.event.quit(0)
  else
    say("FAIL moveteach_relearner failures=" .. failures)
    love.event.quit(1)
  end
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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Pokemon = require("src.core.game3.pokemon")
  local MoveLearn = require("src.core.game3.move_learn")
  local MoveRelearner = require("src.ui.game3.move_relearner")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  session.party = {}
  Party.giveMon(session, BULBASAUR, 50)
  local mon = session.party[1]
  if not result(mon ~= nil, "a level 50 BULBASAUR joined the party") then return end
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_BIG_MUSHROOM, 1)
  result(Bag.has(session.bag, ITEM_BIG_MUSHROOM, 1), "the player carries a BIG MUSHROOM")

  local startMoves = {}
  for i = 1, 4 do startMoves[i] = Pokemon.moveIdAt(mon, i) end
  local offers = MoveLearn.relearnableMoves(mon)
  say("[driver] starting moveset: " .. table.concat({
    tostring(Pokemon.moveName(startMoves[1])), tostring(Pokemon.moveName(startMoves[2])),
    tostring(Pokemon.moveName(startMoves[3])), tostring(Pokemon.moveName(startMoves[4])),
  }, ", "))
  result(#offers > 0, "the mon has relearnable moves, count=" .. tostring(#offers))
  local wanted = offers[1]
  local wantedName = Pokemon.moveName(wanted)

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end

  Map.load(nil, game, HOUSE, { x = MANIAC_X, y = MANIAC_Y + 1, facing = "up" })
  Player.cellX, Player.cellY = MANIAC_X, MANIAC_Y + 1
  Player.px, Player.py = MANIAC_X * 16, (MANIAC_Y + 1) * 16
  Player.targetX, Player.targetY = MANIAC_X, MANIAC_Y + 1
  Player.facing = "up"
  if game.session then
    game.session.x, game.session.y, game.session.facing = MANIAC_X, MANIAC_Y + 1, "up"
  end
  U.wait(90)
  U.shot(game, DIR .. "/moveteach_relearner_01_move_maniac.png")

  local function pumpUntil(cond, frames)
    for _ = 1, (frames or 300) do
      if cond() then return true end
      if Choice.active or (Message.isWaiting and Message.isWaiting()) then
        U.tap(game, "a")
      end
      U.wait(6)
    end
    return cond() and true or false
  end

  say("[driver] talking to the Move Maniac")
  U.tap(game, "a")
  U.wait(24)
  local picker = pumpUntil(function()
    return PartyMenu.isOpen and PartyMenu.isOpen()
  end, 300)
  result(picker, "ChooseMonForMoveRelearner opened the party picker")
  if not picker then
    U.shot(game, DIR .. "/moveteach_relearner_02_no_picker.png")
    return
  end
  U.shot(game, DIR .. "/moveteach_relearner_02_party_picker.png")

  U.tap(game, "a")
  U.wait(40)
  result(getVar(0x8004) == 0, "VAR_0x8004 = 0 for the lead slot, got " .. tostring(getVar(0x8004)))
  result(getVar(0x8005) == #offers,
    "VAR_0x8005 = the relearnable count " .. tostring(#offers)
      .. ", got " .. tostring(getVar(0x8005)))

  local opened = pumpUntil(function() return MoveRelearner.isOpen() end, 400)
  result(opened, "TeachMoveRelearnerMove opened the relearner screen")
  if not opened then
    U.shot(game, DIR .. "/moveteach_relearner_03_no_screen.png")
    return
  end
  U.wait(24)
  U.shot(game, DIR .. "/moveteach_relearner_03_move_list.png")
  result(#MoveRelearner.moves() == #offers,
    "the screen lists every relearnable move, got " .. tostring(#MoveRelearner.moves()))

  say("[driver] choosing " .. tostring(wantedName))
  U.tap(game, "a")
  U.wait(18)
  result(MoveRelearner.state == "yesno" and MoveRelearner.prompt
    and MoveRelearner.prompt:find("Teach ", 1, true) ~= nil,
    "the confirm prompt appeared: " .. tostring(MoveRelearner.prompt))
  U.shot(game, DIR .. "/moveteach_relearner_04_teach_confirm.png")

  U.tap(game, "a")
  U.wait(18)
  local steps = 0
  while MoveRelearner.isOpen() and MoveRelearner.state ~= "list"
      and not SummaryMenu.isOpen() and steps < 12 do
    U.tap(game, "a")
    U.wait(18)
    steps = steps + 1
  end
  result(SummaryMenu.isOpen(),
    "the four-move mon is sent to the summary screen to pick a move to forget")
  if SummaryMenu.isOpen() then
    U.shot(game, DIR .. "/moveteach_relearner_05_forget_which.png")
    U.tap(game, "a")
    U.wait(24)
  end

  steps = 0
  while MoveRelearner.isOpen() and steps < 16 do
    U.tap(game, "a")
    U.wait(18)
    steps = steps + 1
  end
  result(not MoveRelearner.isOpen(), "the relearner screen closed after the teach")
  result(getVar(0x8004) == 1,
    "VAR_0x8004 = TRUE after a real teach, got " .. tostring(getVar(0x8004)))
  result(Pokemon.knowsMove(mon, wanted),
    "the mon now knows " .. tostring(wantedName))
  result(not Pokemon.knowsMove(mon, startMoves[1]),
    "and forgot " .. tostring(Pokemon.moveName(startMoves[1])))

  pumpUntil(function()
    return not (Space.vm and Space.vm:isRunning())
  end, 400)
  U.wait(30)
  result(not Bag.has(session.bag, ITEM_BIG_MUSHROOM, 1),
    "the Move Maniac took the BIG MUSHROOM")

  SummaryMenu.openMenu(session.party, 1, { session = session, page = 2 })
  U.wait(60)
  U.shot(game, DIR .. "/moveteach_relearner_06_new_moveset.png")
  say("[driver] final moveset: " .. table.concat({
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 1))),
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 2))),
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 3))),
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 4))),
  }, ", "))
  SummaryMenu.close()
  U.wait(20)
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL moveteach_relearner driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
