local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_move_tutor"

-- pokefirered/data/scripts/move_tutors.inc:53
local TUNNEL = "FR_ROCK_TUNNEL_B1F"
local TUTOR_X, TUTOR_Y = 2, 29
local FLAG_TUTOR_ROCK_SLIDE = 0x2C2 -- pokefirered/include/constants/flags.h:733
local ROCK_SLIDE = 157 -- pokefirered/include/constants/moves.h:161

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

  local lastResult = nil
  local function sampleResult()
    if not (Space.vm and Space.vm:isRunning()) then return end
    local v = getVar(0x800D)
    if v then lastResult = v end
  end
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
      if PartyMenu.isOpen and PartyMenu.isOpen() then
        pickerSeen = true
        break
      end
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
    ["Want to try using"] = "move_tutor_01_offer.png",
  })
  result(text:find("ROCK SLIDE", 1, true) ~= nil,
    "the tutor offered ROCK SLIDE")
  result(text:find("learned only", 1, true) ~= nil,
    "the once-only question ran")
  -- pokefirered/src/party_menu.c:5793
  result(pickerSeen, "ChooseMonForMoveTutor opened the party menu")
  if not pickerSeen then return end
  U.wait(30)
  result(PartyMenu.mode == "move_tutor",
    "the menu is in the MOVE TUTOR action, mode=" .. tostring(PartyMenu.mode))
  U.shot(game, DIR .. "/move_tutor_02_party_menu.png")

  local MoveLearn = require("src.core.game3.move_learn")
  local Pokemon = require("src.core.game3.pokemon")
  local mon = session.party[1]
  local desc = PartyMenu.slotDescription(1)
  say("[driver] the GEODUDE slot reads " .. tostring(desc))

  -- pokefirered/src/data/pokemon/tutor_learnsets.h:22
  if MoveLearn.tutorLearnsets() then
    result(desc == "ABLE!", "the GEODUDE slot reads ABLE!, got " .. tostring(desc))
    for _ = 1, 40 do
      sampleResult()
      if not PartyMenu.isOpen() then break end
      U.tap(game, "a")
      U.wait(18)
    end
    result(Pokemon.knowsMove(mon, ROCK_SLIDE), "the GEODUDE learned ROCK SLIDE")
    for _ = 1, 200 do
      sampleResult()
      if not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() then break end
      if Choice.active or (Message.isWaiting and Message.isWaiting()) then
        U.tap(game, "a")
      end
      U.wait(6)
    end
    result(lastResult == 1,
      "VAR_RESULT = TRUE after the teach, got " .. tostring(lastResult))
    result(tutorFlag(), "FLAG_TUTOR_ROCK_SLIDE is burned")
    U.shot(game, DIR .. "/move_tutor_03_taught.png")
  else
    say("[driver] no pokemon/tutor.lua in this cache: sTutorLearnsets is not imported,"
      .. " so every regular tutor reads NOT ABLE!")
    result(desc == "NOT ABLE!",
      "the GEODUDE slot reads NOT ABLE! without the imported table, got " .. tostring(desc))
    U.tap(game, "b")
    U.wait(30)
    for _ = 1, 200 do
      sampleResult()
      if not (Space.vm and Space.vm:isRunning()) and not Message.isOpen() then break end
      if Choice.active or (Message.isWaiting and Message.isWaiting()) then
        U.tap(game, "a")
      end
      U.wait(6)
    end
    result(lastResult == 0,
      "VAR_RESULT = FALSE after cancelling, got " .. tostring(lastResult))
    result(not Pokemon.knowsMove(mon, ROCK_SLIDE), "nothing was taught")
    result(not tutorFlag(), "FLAG_TUTOR_ROCK_SLIDE is not burned")
  end
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then
    say("FAIL move_tutor driver error: " .. tostring(err))
    failures = failures + 1
  end
  finish()
end
