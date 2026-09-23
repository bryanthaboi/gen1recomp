local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_hof_credits"

local HOF = "FR_POKEMON_LEAGUE_HALL_OF_FAME"
-- pokefirered/src/hall_of_fame.c:704
local PLATEAU = "FR_INDIGO_PLATEAU_EXTERIOR"
-- pokefirered/include/constants/vars.h:185
local VAR_MAP_SCENE_INDIGO_PLATEAU_EXTERIOR = 0x4085

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_hof_credits")
    love.event.quit(0)
  else
    print("FAIL game3_hof_credits failures=" .. failures)
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
  local Party = require("src.core.game3.party")
  local Message = require("src.ui.game3.message")
  local HallOfFame = require("src.ui.game3.hall_of_fame")
  local Credits = require("src.ui.game3.credits")
  local Player = require("src.core.game3.player")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return end
  session.party = {}
  Party.giveMon(session, 6, 62)
  Party.giveMon(session, 25, 58)
  Party.giveMon(session, 131, 57)
  Party.giveMon(session, 143, 59)

  local function pumpUntil(frames, pred)
    for _ = 1, frames do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end

  local function mashMessages(frames, pred)
    for _ = 1, frames do
      if pred() then return true end
      if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
      if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
      U.wait(2)
    end
    return pred()
  end

  -- pokefirered/data/maps/PokemonLeague_HallOfFame/scripts.inc:18
  Map.load(nil, game, HOF, { x = 5, y = 12, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 5, 12, "up"
  local opened = mashMessages(3000, function() return HallOfFame.isOpen() end)
  if not result(opened, "Hall of Fame room script called EnterHallOfFame") then return end

  local first = pumpUntil(900, function() return HallOfFame.phase() == "hold" end)
  result(first, "first mon slid in and its info printed")
  local Audio = require("src.core.game3.audio")
  result(Audio.currentSong() and Audio.currentSong().id == 286, "MUS_HALL_OF_FAME is playing")
  U.still(game, DIR .. "/cred_hof_first_mon.png")
  result(Flags.getFlag(Space.store, nil, 0x82C) or session.flags[0x82C] == true, "the induction saved the clear flag")

  local card = pumpUntil(6000, function() return HallOfFame.phase() == "exitwait" end)
  result(card, "induction reached the player card")
  U.still(game, DIR .. "/cred_hof_player_card.png")
  U.tap(game, "a")
  local closed = pumpUntil(300, function() return not HallOfFame.isOpen() end)
  result(closed, "A faded the Hall of Fame out")
  U.wait(5)
  result(Map.current == PLATEAU, "SetWarpsToRollCredits warped to " .. tostring(Map.current))
  result(Player.cellX == 11 and Player.cellY == 6,
    string.format("player at 11,6 (got %s,%s)", tostring(Player.cellX), tostring(Player.cellY)))
  result(Flags.getVar(Space.store, nil, VAR_MAP_SCENE_INDIGO_PLATEAU_EXTERIOR) == 1,
    "VAR_MAP_SCENE_INDIGO_PLATEAU_EXTERIOR = 1")

  local rolled = pumpUntil(6000, function() return Credits.isOpen() end)
  if not result(rolled, "the plateau walk ended in special DoCredits") then return end
  result(Audio.currentSong() and Audio.currentSong().id == 290, "MUS_CREDITS kept playing into the credits")

  local S = Credits.SCENE
  local function st() return Credits.state() or {} end

  local staff = pumpUntil(1200, function() local s = st() return s.text and s.text.staff end)
  result(staff, "title staff card printed over Indigo Plateau")
  U.wait(20)
  U.still(game, DIR .. "/cred_title_staff.png")

  local page = pumpUntil(3000, function()
    local s = st()
    return s.mainseq == S.EXEC_CMD and s.text and s.text.names and s.textLevel == 0
  end)
  result(page, "first staff page faded in")
  U.still(game, DIR .. "/cred_text_page.png")

  local runner = pumpUntil(6000, function()
    local s = st()
    return s.task and s.task.sheet and s.textLevel == 0 and s.text and s.text.names and s.scrcmdidx > 6
  end)
  result(runner, "map scroll scene with the running player")
  U.still(game, DIR .. "/cred_map_scene_runner.png")

  local mon = pumpUntil(6000, function()
    local s = st()
    return s.mainseq == S.MON_SHOW and s.mon and s.mon.showBall
  end)
  result(mon, "Charizard pokeball scene")
  U.wait(30)
  U.still(game, DIR .. "/cred_mon_scene.png")

  local theEnd = pumpUntil(20000, function()
    local s = st()
    return s.closing and s.whichMon == 1 and s.mainseq == S.EXEC_CMD
  end)
  result(theEnd, "THE END screen")
  U.wait(20)
  U.still(game, DIR .. "/cred_the_end.png")

  local back = pumpUntil(1200, function() return game.phase == "boot" and game.boot ~= nil end)
  result(back, "WAITBUTTON timed out and the game soft reset to the title")
  result(not Credits.isOpen(), "credits closed")
  U.wait(600)
  U.still(game, DIR .. "/cred_back_at_title.png")
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    print("FAIL game3_hof_credits driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
