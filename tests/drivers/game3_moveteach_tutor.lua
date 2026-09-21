local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_moveteach_tutor"

local HOUSE = "FR_TWO_ISLAND_CAPE_BRINK_HOUSE"
local TUTOR_X, TUTOR_Y = 4, 4
-- pokefirered/include/constants/species.h:13
local BLASTOISE = 9
-- pokefirered/include/constants/moves.h:312
local HYDRO_CANNON = 308
-- pokefirered/include/constants/flags.h:763
local FLAG_TUTOR_HYDRO_CANNON = 0x2E0
local FLAG_LEARNED_ALL_MOVES_AT_CAPE_BRINK = 0x2E1

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/moveteach_tutor.log", "a")
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
    say("PASS moveteach_tutor")
    love.event.quit(0)
  else
    say("FAIL moveteach_tutor failures=" .. failures)
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
  local Pokemon = require("src.core.game3.pokemon")
  local MoveLearn = require("src.core.game3.move_learn")
  local PartyMenu = require("src.ui.game3.party_menu")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  session.party = {}
  Party.giveMon(session, BLASTOISE, 40)
  local mon = session.party[1]
  if not result(mon ~= nil, "a level 40 BLASTOISE joined the party") then return end
  -- pokefirered/src/field_specials.c:2239
  Pokemon.setFriendship(mon, 255)
  result((tonumber(Pokemon.friendshipOf(mon)) or 0) == 255,
    "the lead mon is at max friendship, got " .. tostring(Pokemon.friendshipOf(mon)))

  local startMoves = {}
  for i = 1, 4 do startMoves[i] = Pokemon.moveIdAt(mon, i) end
  say("[driver] starting moveset: " .. table.concat({
    tostring(Pokemon.moveName(startMoves[1])), tostring(Pokemon.moveName(startMoves[2])),
    tostring(Pokemon.moveName(startMoves[3])), tostring(Pokemon.moveName(startMoves[4])),
  }, ", "))
  result(not Pokemon.knowsMove(mon, HYDRO_CANNON),
    "it does not know HYDRO CANNON yet")
  result(MoveLearn.canLearnTutorMove(BLASTOISE, MoveLearn.TUTOR_MOVE_HYDRO_CANNON),
    "CanLearnTutorMove accepts BLASTOISE for the ultimate move")

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end
  local function getFlag(id) return Flags.getFlag(Space.store, ctx(), id) == true end

  Map.load(nil, game, HOUSE, { x = TUTOR_X, y = TUTOR_Y + 2, facing = "up" })
  Player.cellX, Player.cellY = TUTOR_X, TUTOR_Y + 2
  Player.px, Player.py = TUTOR_X * 16, (TUTOR_Y + 2) * 16
  Player.targetX, Player.targetY = TUTOR_X, TUTOR_Y + 2
  Player.facing = "up"
  if game.session then
    game.session.x, game.session.y, game.session.facing = TUTOR_X, TUTOR_Y + 2, "up"
  end
  U.wait(90)
  U.hold(game, "up", 24)
  U.wait(90)
  result(Player.cellY == TUTOR_Y + 1,
    "walked up to the Cape Brink tutor, y=" .. tostring(Player.cellY))
  result(not getFlag(FLAG_TUTOR_HYDRO_CANNON), "FLAG_TUTOR_HYDRO_CANNON starts clear")
  U.shot(game, DIR .. "/moveteach_tutor_01_cape_brink.png")

  local pages = {}
  local function pumpUntil(cond, frames)
    for _ = 1, (frames or 300) do
      if cond() then return true end
      local page = Message.isOpen() and Message.currentPage() or nil
      if page and pages[#pages] ~= page then
        pages[#pages + 1] = page
        say("[driver] page: " .. page:gsub("\n", " / "))
      end
      if Choice.active or (Message.isWaiting and Message.isWaiting()) then
        U.tap(game, "a")
      end
      U.wait(6)
    end
    return cond() and true or false
  end

  say("[driver] talking to the tutor")
  U.tap(game, "a")
  U.wait(24)

  local picker = pumpUntil(function()
    return PartyMenu.isOpen and PartyMenu.isOpen()
  end, 500)
  result(picker, "ChooseMonForMoveTutor opened the party menu")
  if not picker then
    U.shot(game, DIR .. "/moveteach_tutor_02_no_picker.png")
    return
  end
  result(PartyMenu.mode == "move_tutor" or PartyMenu.mode == "message",
    "the menu is in the MOVE TUTOR action, mode=" .. tostring(PartyMenu.mode))
  result(getVar(0x8005) == MoveLearn.TUTOR_MOVE_HYDRO_CANNON,
    "VAR_0x8005 carries MOVETUTOR_HYDRO_CANNON, got " .. tostring(getVar(0x8005)))
  U.wait(24)
  U.shot(game, DIR .. "/moveteach_tutor_02_party_menu.png")

  local steps = 0
  while PartyMenu.isOpen() and steps < 40 do
    U.tap(game, "a")
    U.wait(18)
    steps = steps + 1
  end
  result(not PartyMenu.isOpen(), "the party menu closed after the teach")
  result(Pokemon.knowsMove(mon, HYDRO_CANNON), "the BLASTOISE now knows HYDRO CANNON")

  pumpUntil(function()
    return not (Space.vm and Space.vm:isRunning()) and not Message.isOpen()
  end, 600)
  U.wait(30)

  local joined = table.concat(pages, " "):gsub("%s+", " ")
  result(joined:find("HYDRO CANNON", 1, true) ~= nil,
    "the tutor named HYDRO CANNON in its pages")
  result(getFlag(FLAG_TUTOR_HYDRO_CANNON),
    "HasLearnedAllMovesFromCapeBrinkTutor burned FLAG_TUTOR_HYDRO_CANNON")
  result(not getFlag(FLAG_LEARNED_ALL_MOVES_AT_CAPE_BRINK),
    "one of three ultimate moves is not all of them")

  SummaryMenu.openMenu(session.party, 1, { session = session, page = 2 })
  U.wait(60)
  U.shot(game, DIR .. "/moveteach_tutor_03_new_moveset.png")
  say("[driver] final moveset: " .. table.concat({
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 1))),
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 2))),
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 3))),
    tostring(Pokemon.moveName(Pokemon.moveIdAt(mon, 4))),
  }, ", "))
  SummaryMenu.close()
  U.wait(20)

  say("[driver] second visit")
  U.tap(game, "a")
  U.wait(24)
  local second = {}
  for _ = 1, 300 do
    local page = Message.isOpen() and Message.currentPage() or nil
    if page and second[#second] ~= page then
      second[#second + 1] = page
      say("[driver] second page: " .. page:gsub("\n", " / "))
    end
    if not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() then break end
    if Choice.active or (Message.isWaiting and Message.isWaiting()) then
      U.tap(game, "a")
    end
    U.wait(6)
  end
  result(#second > 0, "the tutor still talks on a second visit")
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL moveteach_tutor driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
