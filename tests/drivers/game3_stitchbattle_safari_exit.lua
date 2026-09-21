local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchbattle_safari_exit"

local SAFARI_MAP = "FR_SAFARI_ZONE_CENTER"
local GATE_MAP = "FR_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE"
-- pokefirered/include/constants/vars.h:162
local VAR_ENTRANCE_SCENE = 0x406E

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    if fails == 0 then
      print("PASS stitchbattle_safari_exit")
      love.event.quit(0)
    else
      print("FAIL stitchbattle_safari_exit failures=" .. fails)
      love.event.quit(1)
    end
  end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Encounters = require("src.core.game3.encounters")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Message = require("src.ui.game3.message")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Safari = require("src.core.game3.safari")
  local Rng = require("src.core.game3.rng")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.party = {}
  Party.giveMon(session, 6, 40)

  local function ctx() return Space.vm and Space.vm.ctx end
  local function sceneVar() return Flags.getVar(Space.store, ctx(), VAR_ENTRANCE_SCENE) end

  local function placeAt(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(60)
  end

  -- pokefirered/src/wild_encounter.c:678 TILE_ENCOUNTER_LAND
  local function grassy(cx, cy)
    if Encounters.encounterTypeAt(cx, cy) ~= 1 then return false end
    return Collision.isWalkable(cx, cy) and Collision.canEnter(game, cx, cy, {}) ~= false
  end

  local function openCell()
    local layout = Map._def and Map._def.midLayout
    if not layout then return nil end
    local best, bestScore = nil, -1
    for cy = 3, layout.height - 4 do
      for cx = 3, layout.width - 4 do
        if grassy(cx, cy) then
          local score = 0
          for dy = -2, 2 do
            for dx = -2, 2 do
              if grassy(cx + dx, cy + dy) then score = score + 1 end
            end
          end
          if score > bestScore then best, bestScore = { cx, cy }, score end
        end
      end
    end
    if best and bestScore >= 9 then return best[1], best[2] end
    return nil
  end

  local OPPOSITE = { right = "left", left = "right", up = "down", down = "up" }

  local function patrol(maxSteps, dir)
    local steps, stuck = 0, 0
    local d = dir
    while steps < maxSteps and stuck < 8 do
      if Battle.isActive() then return true end
      local bx, by = Player.cellX, Player.cellY
      U.hold(game, d, 20)
      U.wait(4)
      if Battle.isActive() then return true end
      if Map.current ~= SAFARI_MAP then return false end
      if Player.cellX ~= bx or Player.cellY ~= by then
        steps = steps + 1
        stuck = 0
      else
        stuck = stuck + 1
      end
      d = OPPOSITE[d]
    end
    return Battle.isActive()
  end

  local function atMenu()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local function waitForMenu(n)
    for _ = 1, n or 600 do
      if atMenu() then return true end
      if not Battle.isActive() then return false end
      U.tap(game, "a")
      U.wait(6)
    end
    return atMenu()
  end

  local function shown(text)
    local page = Message.isOpen() and Message.currentPage() or ""
    return tostring(page):find(text, 1, true) ~= nil
  end

  local function mashUntil(pred, frames)
    local i = 0
    while i < (frames or 900) do
      if pred() then return true end
      if i % 8 == 0 then U.tap(game, "a") end
      U.wait(1)
      i = i + 1
    end
    return pred() and true or false
  end

  local function waitShown(text, frames)
    if not mashUntil(function() return shown(text) end, frames) then return false end
    for _ = 1, 240 do
      if not shown(text) then break end
      if Message.isWaiting() then break end
      U.wait(1)
    end
    U.wait(2)
    return shown(text)
  end

  local function startEncounter(seed)
    local gx, gy = openCell()
    if not gx then return false end
    local walkDir = grassy(gx + 1, gy) and "right" or "down"
    placeAt(SAFARI_MAP, gx, gy, walkDir)
    Rng.SeedRng(seed)
    Rng.SeedWildEncounterRng(seed)
    Encounters.resetRateModifiers()
    return patrol(300, walkDir)
  end

  -- pokefirered/src/safari_zone.c:27 EnterSafariMode
  local function enterSafariWithOneBall()
    placeAt(SAFARI_MAP, 10, 10, "down")
    Safari.enter(session)
    -- pokefirered/src/safari_zone.c:9 gNumSafariBalls
    session.safari.balls = 1
  end

  print("== pass 1: the last SAFARI BALL misses ==")
  enterSafariWithOneBall()
  if not result(startEncounter(0x2468), "walking the grass started a Safari battle") then
    return finish()
  end
  U.wait(120)
  local st = Battle.getState()
  result(st and st.safari == true, "it is a Safari battle")
  result(st and st.safariState and st.safariState.balls == 1, "one SAFARI BALL left")
  -- pokefirered/src/battle_script_commands.c:9463 Cmd_handleballthrow
  st.rng = function(_, hi) return hi end
  if not result(waitForMenu(900), "reached the BALL / BAIT / ROCK / RUN menu") then
    return finish()
  end
  Ui._log = {}
  U.tap(game, "a")
  U.wait(30)
  -- pokefirered/data/battle_scripts_2.s:110 STRINGID_OUTOFSAFARIBALLS
  result(waitShown("Game over", 900), "the ANNOUNCER line is on screen")
  result(U.shot(game, DIR .. "/stitchbattle_safari_exit_01_announcer.png"),
    "shot the in-battle ANNOUNCER line")

  local arrivalScene = nil
  mashUntil(function()
    if Battle.isActive() then return false end
    if arrivalScene == nil and Map.current == GATE_MAP then arrivalScene = sceneVar() end
    return arrivalScene ~= nil
  end, 1200)
  result(not Battle.isActive(), "the battle ended")
  -- pokefirered/src/safari_zone.c:68
  result(Map.current == GATE_MAP, "the player is back at the Safari Zone gate (got "
    .. tostring(Map.current) .. ")")
  -- pokefirered/data/scripts/safari_zone.inc:2
  result(arrivalScene == 3, "the entrance scene var arrived as 3, ExitWalkIn (got "
    .. tostring(arrivalScene) .. ")")
  -- pokefirered/data/scripts/safari_zone.inc:3
  result(Safari.isActive(session) == false, "safari mode is off")
  result(Safari.balls(session) == 0, "and the ball counter is zeroed")
  -- pokefirered/data/maps/FuchsiaCity_SafariZone_Entrance/scripts.inc:12
  result(waitShown("fair share", 1200), "the gate attendant is talking")
  result(U.shot(game, DIR .. "/stitchbattle_safari_exit_02_gate_walkin.png"),
    "shot the ExitWalkIn scene at the gate")
  for _ = 1, 400 do
    if sceneVar() == 0 and not Message.isOpen() then break end
    U.tap(game, "a")
    U.wait(4)
  end
  -- pokefirered/data/maps/FuchsiaCity_SafariZone_Entrance/scripts.inc:22
  result(sceneVar() == 0, "ExitWalkIn cleared the scene var (got " .. tostring(sceneVar()) .. ")")

  print("== pass 2: the last SAFARI BALL catches ==")
  U.wait(60)
  enterSafariWithOneBall()
  if not result(startEncounter(0x1357), "walking the grass started a second Safari battle") then
    return finish()
  end
  U.wait(120)
  st = Battle.getState()
  result(st and st.safariState and st.safariState.balls == 1, "one SAFARI BALL left again")
  -- pokefirered/src/battle_script_commands.c:9463 Cmd_handleballthrow
  st.rng = function(lo) return lo end
  if not result(waitForMenu(900), "reached the safari menu again") then return finish() end
  local partyBefore = #session.party
  Ui._log = {}
  U.tap(game, "a")
  U.wait(30)
  -- pokefirered/data/battle_scripts_2.s:77 STRINGID_GOTCHAPKMNCAUGHT
  result(waitShown("was caught", 900), "Gotcha, the POKeMON was caught")
  for _ = 1, 1200 do
    if not Battle.isActive() then break end
    if Ui.choiceActive() then
      U.tap(game, "b")
    else
      U.tap(game, "a")
    end
    U.wait(4)
  end
  result(not Battle.isActive(), "the catch flow finished and the battle ended")
  -- pokefirered/src/safari_zone.c:73
  result(#session.party == partyBefore + 1, "the caught mon is in the party ("
    .. tostring(#session.party) .. ")")
  -- pokefirered/data/text/safari_zone.inc:12 SafariZone_Text_OutOfBalls
  result(waitShown("out of SAFARI BALLS", 900), "the PA out-of-balls line plays after the catch")
  result(U.shot(game, DIR .. "/stitchbattle_safari_exit_03_pa_out_of_balls.png"),
    "shot the PA announcement")
  for _ = 1, 900 do
    if Map.current == GATE_MAP then break end
    U.tap(game, "a")
    U.wait(4)
  end
  -- pokefirered/data/scripts/safari_zone.inc:8
  result(Map.current == GATE_MAP, "the caught branch warps to the gate too (got "
    .. tostring(Map.current) .. ")")
  result(Safari.isActive(session) == false, "safari mode is off after the catch branch")
  -- pokefirered/data/maps/FuchsiaCity_SafariZone_Entrance/scripts.inc:27
  result(waitShown("fair share", 1200), "the gate attendant is talking on the ExitWarpIn scene")
  result(U.shot(game, DIR .. "/stitchbattle_safari_exit_04_gate_warpin.png"),
    "shot the ExitWarpIn scene at the gate")
  result(#session.party == partyBefore + 1, "the caught mon survived the exit")

  return finish()
end
