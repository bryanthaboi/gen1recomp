local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_move_tutor"

-- pokefirered/data/scripts/move_tutors.inc:53
local TUNNEL = "FR_ROCK_TUNNEL_B1F"
local TUTOR_X, TUTOR_Y = 2, 29
local FLAG_TUTOR_ROCK_SLIDE = 0x2C2 -- pokefirered/include/constants/flags.h:733

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/move_tutor.log", "a")
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
    say("PASS move_tutor")
    love.event.quit(0)
  else
    say("FAIL move_tutor failures=" .. failures)
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
  local PartyMenu = require("src.ui.game3.party_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return end

  session.party = {}
  Party.giveMon(session, 74, 30)
  result(#session.party == 1, "party has a GEODUDE for the tutor to look at")

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end
  local function tutorFlag()
    return Flags.getFlag(Space.store, ctx(), FLAG_TUTOR_ROCK_SLIDE) == true
  end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(90)
  end

  local function talk(label, shots)
    local pages = {}
    local pickerSeen = false
    U.tap(game, "a")
    U.wait(30)
    for _ = 1, 400 do
      if PartyMenu.isOpen and PartyMenu.isOpen() then pickerSeen = true end
      if not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() then break end
      local page = Message.isOpen() and Message.currentPage() or nil
      if page and pages[#pages] ~= page then
        pages[#pages + 1] = page
        say("[driver] " .. label .. " page: " .. page:gsub("\n", " / "))
        for match, name in pairs(shots or {}) do
          if page:find(match, 1, true) then
            for _ = 1, 40 do
              if Message.isWaiting and Message.isWaiting() then break end
              U.wait(6)
            end
            U.shot(game, DIR .. "/" .. name)
          end
        end
      end
      if Choice.active or (Message.isWaiting and Message.isWaiting()) then
        U.tap(game, "a")
      end
      U.wait(6)
    end
    return table.concat(pages, " "):gsub("%s+", " "), pickerSeen
  end

  goTo(TUNNEL, TUTOR_X, TUTOR_Y + 2, "up")
  U.hold(game, "up", 24)
  U.wait(120)
  result(Player.cellY == TUTOR_Y + 1,
    "walked up to the tutor, y=" .. tostring(Player.cellY))
  result(not tutorFlag(), "FLAG_TUTOR_ROCK_SLIDE starts clear")

  local text, pickerSeen = talk("tutor", {
    ["Which POKéMON"] = "move_tutor_01_which_mon.png",
    ["scared after all"] = "move_tutor_02_declined.png",
  })
  result(text:find("ROCK SLIDE", 1, true) ~= nil,
    "the tutor offered ROCK SLIDE")
  result(text:find("learned only", 1, true) ~= nil,
    "the once-only question ran")
  -- pokefirered/data/scripts/move_tutors.inc:64
  result(text:find("scared after all", 1, true) ~= nil,
    "the tutor took the declined branch with nothing taught")
  result(getVar(0x800D) == 0,
    "VAR_RESULT = FALSE after ChooseMonForMoveTutor, got " .. tostring(getVar(0x800D)))
  result(not pickerSeen, "no party picker with no tutor move to teach")
  result(not tutorFlag(), "FLAG_TUTOR_ROCK_SLIDE is not burned")

  U.wait(60)
  local text2 = talk("second visit", {
    ["Want to try using"] = "move_tutor_03_still_offered.png",
  })
  result(text2:find("ROCK SLIDE", 1, true) ~= nil,
    "the tutor still offers the move on a second visit")
  result(text2:find("might be scary", 1, true) == nil,
    "the tutor does not claim it already taught the move")
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL move_tutor driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
