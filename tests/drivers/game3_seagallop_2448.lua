local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_seagallop_2448"

-- pokefirered/include/constants/vars.h:170
local VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F = 0x4076
-- pokefirered/include/constants/vars.h:178
local VAR_MAP_SCENE_VERMILION_CITY = 0x407E
-- pokefirered/include/constants/vars.h:165
local VAR_MAP_SCENE_CINNABAR_ISLAND = 0x4071

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS seagallop_2448")
    love.event.quit(0)
  else
    print("FAIL seagallop_2448 failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Sea = require("src.ui.game3.seagallop")
  local Fade = require("src.ui.game3.fade")

  if not result(Runtime.getSession() ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end
  local function vmRunning() return Space.vm and Space.vm:isRunning() end
  local function setScenes(scene)
    setVar(VAR_MAP_SCENE_VERMILION_CITY, 3)
    setVar(VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F, scene)
    setVar(VAR_MAP_SCENE_CINNABAR_ISLAND, 4)
  end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing })
    place(x, y, facing)
    U.wait(90)
  end

  local function sail(fromMap, x, y, facing, picks, tag)
    place(x, y, facing)
    U.wait(12)
    U.tap(game, "a")
    U.wait(24)
    local pickIdx, sawSea = 1, false
    for _ = 1, 600 do
      if Sea.isActive() then sawSea = true break end
      if Choice.active and Choice.kind == "multi" and picks[pickIdx] then
        Choice.cursor = picks[pickIdx]
        pickIdx = pickIdx + 1
        U.wait(6)
      end
      U.tap(game, "a")
      U.wait(8)
    end
    result(sawSea, tag .. ": the ferry scene started")
    U.wait(40)
    U.still(game, DIR .. "/2448_" .. tag .. "_crossing.png")
    for _ = 1, 40 do
      U.wait(30)
      if not Sea.isActive() and not vmRunning() and Space.mapId ~= fromMap and not Fade.active then break end
    end
    U.wait(30)
    print(string.format("[2448] %s map=%s xy=(%s,%s) seaActive=%s vm=%s fadeT=%s",
      tag, tostring(Space.mapId), tostring(Player.cellX), tostring(Player.cellY),
      tostring(Sea.isActive()), tostring(vmRunning()), tostring(Fade.t)))
    result(not Sea.isActive(), tag .. ": the ferry overlay is gone after arrival")
    result((Fade.t or 0) <= 0, tag .. ": the arrival fade-in finished, t=" .. tostring(Fade.t))
    result(not vmRunning(), tag .. ": the ferry script ended")
    U.shot(game, DIR .. "/2448_" .. tag .. "_arrived.png")
  end

  local function canMove(tag)
    local x0, y0 = Player.cellX, Player.cellY
    for _, dir in ipairs({ "up", "left", "right", "down" }) do
      U.hold(game, dir, 20)
      U.wait(20)
      if Player.cellX ~= x0 or Player.cellY ~= y0 then break end
    end
    local moved = Player.cellX ~= x0 or Player.cellY ~= y0
    result(moved, tag .. ": the player walks from (" .. tostring(x0) .. "," .. tostring(y0) ..
      ") to (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  end

  setScenes(1)
  goTo("FR_VERMILION_CITY", 24, 34, "up")
  setScenes(1)
  sail("FR_VERMILION_CITY", 24, 34, "up", {}, "tripass")
  result(Space.mapId == "SEVII_ONE_ISLAND_HARBOR", "tripass: landed on One Island Harbor, map=" .. tostring(Space.mapId))
  canMove("tripass")

  setScenes(5)
  goTo("FR_VERMILION_CITY", 24, 34, "up")
  setScenes(5)
  -- pokefirered/src/script_menu.c:1291
  sail("FR_VERMILION_CITY", 24, 34, "up", { 5, 3 }, "menu_seven")
  result(tostring(Space.mapId):find("SEVEN") ~= nil, "menu_seven: landed on Seven Island, map=" .. tostring(Space.mapId))
  canMove("menu_seven")

  local sevenMap = Space.mapId
  goTo(sevenMap, 8, 5, "down")
  setScenes(5)
  sail(sevenMap, 8, 5, "down", { 1 }, "return_vermilion")
  result(Space.mapId == "FR_VERMILION_CITY", "return_vermilion: back in Vermilion, map=" .. tostring(Space.mapId))
  canMove("return_vermilion")

  local okS = pcall(function() return game:saveGame() end)
  result(okS, "saved after the return trip")
  Sea._active, Sea._run = true, { tick = 0, accum = 0, bgX = 0, ferryX = 0, ferryY = 92, wakes = {}, direction = 1, state = "running" }
  game.softResetRequested = true
  U.wait(60)
  game:_handleBootAction({ action = "continue" })
  for _ = 1, 900 do
    if Runtime.getSession() and game.phase ~= "quest_log" then break end
    if game.phase == "quest_log" then U.tap(game, "b") end
    U.wait(4)
  end
  U.wait(120)
  print(string.format("[2448] continue map=%s xy=(%s,%s) seaActive=%s",
    tostring(Space.mapId), tostring(Player.cellX), tostring(Player.cellY), tostring(Sea.isActive())))
  result(not Sea.isActive(), "continue: a leaked ferry overlay is cleared by soft reset + CONTINUE")
  result(Space.mapId == "FR_VERMILION_CITY", "continue: resumed in Vermilion, map=" .. tostring(Space.mapId))
  U.shot(game, DIR .. "/2448_continue_clean.png")
  canMove("continue")

  finish()
end
