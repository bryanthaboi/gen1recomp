local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_static_encounters"

local POWER_PLANT = "FR_POWER_PLANT"
local ROUTE_10 = "FR_ROUTE_10"

local LOCAL_ZAPDOS, LOCAL_ELECTRODE_2, LOCAL_ELECTRODE_1 = 6, 7, 8
local ZAPDOS_XY = { 5, 12 }
local ELECTRODE_1_XY = { 30, 39 }
local ELECTRODE_2_XY = { 36, 6 }

-- pokefirered/include/constants/flags.h:109
local FLAG_HIDE_ZAPDOS = 0x05D
-- pokefirered/include/constants/flags.h:730
local FLAG_FOUGHT_ZAPDOS = 0x2BF

local MASTER_BALL = "FRLG_1"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS static_encounters")
    love.event.quit(0)
  else
    print("FAIL static_encounters failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
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
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, 150, 100)
  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, MASTER_BALL, 5)

  local function ctx() return Space.vm and Space.vm.ctx end
  local function flag(id) return Flags.getFlag(Space.store, ctx(), id) and true or false end
  local function visible(localId)
    local eo = Objects.find(localId)
    return eo ~= nil and eo.visible == true
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
    U.wait(30)
    local Preview = package.loaded["src.ui.game3.map_preview_screen"]
    for _ = 1, 240 do
      if not (Preview and Preview.isActive and Preview.isActive()) then break end
      U.wait(5)
    end
    U.wait(60)
  end

  local function fieldBusy()
    local Message = package.loaded["src.ui.game3.message"]
    local open = Message and Message.isOpen and Message.isOpen()
    return open, (Space.vm and Space.vm:isRunning()) and true or false
  end

  local function pumpField(frames)
    for _ = 1, (frames or 300) do
      local open, running = fieldBusy()
      if not open and not running then return true end
      if open then U.tap(game, "a") end
      U.wait(10)
    end
    return false
  end

  local function atCommand()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local function mash(frames, stop)
    for i = 1, (frames or 2500) do
      if stop() then return true end
      if i % 300 == 0 then
        U.log("mash", i, "active=" .. tostring(Battle.isActive()),
          "phase=" .. tostring(Battle._phase), "mode=" .. tostring(Ui._mode),
          "dialog=" .. tostring(Ui.dialogPending and Ui.dialogPending()))
      end
      if Ui.dialogPending and Ui.dialogPending() then
        U.tap(game, "a")
        U.wait(8)
      elseif Battle._phase == "catch_nickname_prompt" then
        U.tap(game, "b")
        U.wait(12)
      elseif i % 16 == 0 then
        U.tap(game, "a")
        U.wait(4)
      else
        U.wait(1)
      end
    end
    return stop()
  end

  local function waitForCommand(frames)
    return mash(frames or 2500, atCommand)
  end

  local function talkTo(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(15)
    U.tap(game, "a")
    U.wait(30)
    for _ = 1, 400 do
      if Battle.isActive() then return true end
      local open = fieldBusy()
      if open then U.tap(game, "a") end
      U.wait(6)
    end
    return Battle.isActive()
  end

  local function endBattle(command, label)
    for _ = 1, 20 do
      if not Battle.isActive() then break end
      if not waitForCommand(1800) then break end
      Ui._pendingCommand = command()
      Ui._mode = "none"
      mash(2500, function() return (not Battle.isActive()) or atCommand() end)
    end
    mash(600, function() return not Battle.isActive() end)
    U.wait(60)
    pumpField(300)
    return result(not Battle.isActive(), label)
  end

  goTo(POWER_PLANT, ELECTRODE_1_XY[1], ELECTRODE_1_XY[2], "up")
  result(visible(LOCAL_ELECTRODE_1), "the Power Plant spawns Electrode 1")
  U.shot(game, DIR .. "/static_encounters_01_electrode_present.png")

  if not result(talkTo(ELECTRODE_1_XY[1], ELECTRODE_1_XY[2], "up"),
    "talking to the item ball started the Electrode battle") then
    return finish()
  end
  result(waitForCommand(2500), "the Electrode battle reached the command menu")
  U.shot(game, DIR .. "/static_encounters_02_electrode_battle.png")
  endBattle(function()
    return { kind = "bag", user = "player", itemId = MASTER_BALL }
  end, "the Master Ball ended the Electrode battle")

  result(session.battleOutcome == 7,
    "the battle return hook recorded B_OUTCOME_CAUGHT, got "
    .. tostring(session.battleOutcome))
  result(visible(LOCAL_ELECTRODE_1) == false,
    "ON_RESUME removed the caught Electrode from the map")
  U.shot(game, DIR .. "/static_encounters_03_electrode_gone.png")

  goTo(ROUTE_10, 10, 10, "down")
  goTo(POWER_PLANT, ELECTRODE_1_XY[1], ELECTRODE_1_XY[2], "up")
  result(visible(LOCAL_ELECTRODE_1) == false,
    "the caught Electrode is still gone after leaving and coming back")
  U.shot(game, DIR .. "/static_encounters_04_electrode_still_gone.png")

  if result(talkTo(ELECTRODE_2_XY[1], ELECTRODE_2_XY[2], "up"),
    "talking to the second item ball started its battle") then
    local st = Battle.getState()
    local slot = 1
    if st and st.player and st.player.mon and st.player.mon.moves then
      for i, mv in ipairs(st.player.mon.moves) do
        if (tonumber(mv) or 0) > 0 then slot = i break end
      end
    end
    endBattle(function()
      local s = Battle.getState()
      local mon = s and s.player and s.player.mon
      return { kind = "move", user = "player", slot = slot,
        move = mon and mon.moves and mon.moves[slot] }
    end, "the second Electrode was beaten in battle")
    result(visible(LOCAL_ELECTRODE_2) == false,
      "the defeated Electrode is off the map")
    U.shot(game, DIR .. "/static_encounters_05_electrode2_defeated.png")
  end

  goTo(POWER_PLANT, ZAPDOS_XY[1], ZAPDOS_XY[2], "up")
  result(visible(LOCAL_ZAPDOS), "Zapdos is on the map")
  if result(talkTo(ZAPDOS_XY[1], ZAPDOS_XY[2], "up"),
    "talking to Zapdos started the legendary battle") then
    result(waitForCommand(2500), "the Zapdos battle reached the command menu")
    U.shot(game, DIR .. "/static_encounters_06_zapdos_battle.png")
    endBattle(function()
      return { kind = "run", user = "player" }
    end, "the player ran from Zapdos")
    result(session.battleOutcome == 4,
      "the battle return hook recorded B_OUTCOME_RAN, got "
      .. tostring(session.battleOutcome))
    result(flag(FLAG_FOUGHT_ZAPDOS) == false,
      "fleeing never sets FLAG_FOUGHT_ZAPDOS")
    result(visible(LOCAL_ZAPDOS) == false,
      "EventScript_MonFlewAway took Zapdos off the map")
    result(flag(FLAG_HIDE_ZAPDOS) == true, "and set his hide flag")
    U.shot(game, DIR .. "/static_encounters_07_zapdos_flew_away.png")

    goTo(ROUTE_10, 10, 10, "down")
    goTo(POWER_PLANT, ZAPDOS_XY[1], ZAPDOS_XY[2], "up")
    result(visible(LOCAL_ZAPDOS),
      "ON_TRANSITION clears the hide flag again, so Zapdos is back")
    U.shot(game, DIR .. "/static_encounters_08_zapdos_back.png")
  end

  finish()
end
