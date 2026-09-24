local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_seagallop"

-- pokefirered/include/constants/vars.h:165
local VAR_MAP_SCENE_CINNABAR_ISLAND = 0x4071
-- pokefirered/include/constants/vars.h:169
local VAR_MAP_SCENE_ONE_ISLAND_HARBOR = 0x4075
-- pokefirered/include/constants/vars.h:170
local VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F = 0x4076
-- pokefirered/include/constants/vars.h:178
local VAR_MAP_SCENE_VERMILION_CITY = 0x407E
-- pokefirered/include/constants/flags.h:114
local FLAG_HIDE_CINNABAR_BILL = 0x062

local VERMILION = "FR_VERMILION_CITY"
local CINNABAR = "FR_CINNABAR_ISLAND"
local ONE_HARBOR = "SEVII_ONE_ISLAND_HARBOR"
local TWO_HARBOR = "FR_TWO_ISLAND_HARBOR"
local ONE_ISLAND = "SEVII_ONE_ISLAND"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS seagallop")
    love.event.quit(0)
  else
    print("FAIL seagallop failures=" .. failures)
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

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end
  local function getVar(id) return Flags.getVar(Space.store, ctx(), id) end
  local function mapId() return Space.mapId end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing or "down")
    U.wait(90)
  end

  local function runScript(fromMap, limit)
    local ticks = 0
    while ticks < (limit or 900) do
      if Space.mapId ~= fromMap then return true end
      local running = Space.vm and Space.vm:isRunning()
      local open = Message.isOpen and Message.isOpen()
      if not running and not open and not Choice.active then break end
      U.tap(game, "a")
      U.wait(12)
      ticks = ticks + 12
    end
    return Space.mapId ~= fromMap
  end

  local function talkTo(x, y, facing)
    place(x, y, facing)
    U.wait(12)
    U.tap(game, "a")
    U.wait(24)
    return (Space.vm and Space.vm:isRunning()) or (Message.isOpen and Message.isOpen())
  end

  -- pokefirered/data/maps/VermilionCity/scripts.inc:14
  setVar(VAR_MAP_SCENE_VERMILION_CITY, 3)
  -- pokefirered/data/maps/OneIsland_PokemonCenter_1F/scripts.inc:117
  setVar(VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F, 1)
  goTo(VERMILION, 24, 34, "up")
  setVar(VAR_MAP_SCENE_VERMILION_CITY, 3)
  setVar(VAR_MAP_SCENE_ONE_ISLAND_POKEMON_CENTER_1F, 1)
  U.shot(game, DIR .. "/seagallop_01_vermilion_pier.png")

  local spoke = talkTo(24, 34, "up")
  if not spoke then spoke = talkTo(23, 33, "right") end
  if not spoke then spoke = talkTo(25, 33, "left") end
  result(spoke, "the Vermilion ferry sailor answers")
  U.wait(30)
  U.shot(game, DIR .. "/seagallop_02_tripass_prompt.png")
  runScript(VERMILION, 1800)
  U.wait(120)
  print("[driver] after the Vermilion sail: map=" .. tostring(mapId()) ..
    " at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  result(mapId() == ONE_HARBOR, "the Tri-Pass ferry landed on One Island Harbor, map=" ..
    tostring(mapId()))
  result(Player.cellX == 8 and Player.cellY == 5,
    "landed on the sSeag berth (8,5), got (" .. tostring(Player.cellX) ..
    "," .. tostring(Player.cellY) .. ")")
  result(not require("src.ui.game3.seagallop").isActive(), "the ferry overlay cleared on One Island Harbor")
  U.shot(game, DIR .. "/seagallop_03_one_island_harbor.png")

  local spoke2 = talkTo(8, 5, "down")
  result(spoke2, "the One Island Harbor sailor answers")
  U.wait(30)
  U.shot(game, DIR .. "/seagallop_04_island_menu.png")
  runScript(ONE_HARBOR, 1800)
  U.wait(120)
  print("[driver] after the island hop: map=" .. tostring(mapId()) ..
    " at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")")
  result(mapId() == TWO_HARBOR, "One Island -> Two Island Harbor, map=" .. tostring(mapId()))
  result(not require("src.ui.game3.seagallop").isActive(), "the ferry overlay cleared on Two Island Harbor")
  U.shot(game, DIR .. "/seagallop_05_two_island_harbor.png")

  local spoke3 = talkTo(8, 5, "down")
  result(spoke3, "the Two Island Harbor sailor answers")
  U.wait(30)
  runScript(TWO_HARBOR, 1800)
  U.wait(120)
  result(mapId() == ONE_HARBOR, "Two Island -> One Island Harbor, map=" .. tostring(mapId()))
  result(not require("src.ui.game3.seagallop").isActive(), "the ferry overlay cleared back on One Island")
  U.shot(game, DIR .. "/seagallop_06_back_on_one_island.png")

  goTo(CINNABAR, 20, 5, "down")
  -- pokefirered/data/maps/CinnabarIsland_Gym/scripts.inc:61
  setVar(VAR_MAP_SCENE_CINNABAR_ISLAND, 1)
  -- pokefirered/data/maps/CinnabarIsland_Gym/scripts.inc:62
  Flags.setFlag(Space.store, ctx(), FLAG_HIDE_CINNABAR_BILL, false)
  goTo(CINNABAR, 20, 5, "down")
  U.wait(60)
  local billRan = (Space.vm and Space.vm:isRunning()) or (Message.isOpen and Message.isOpen())
  result(billRan, "the ON_FRAME Bill scene started on Cinnabar Island")
  for _ = 1, 12 do
    if Message.isOpen and Message.isOpen() then break end
    U.wait(10)
  end
  U.wait(60)
  U.shot(game, DIR .. "/seagallop_07_cinnabar_bill.png")
  runScript(CINNABAR, 3600)
  U.wait(180)
  for _ = 1, 40 do
    if mapId() == ONE_ISLAND then break end
    U.tap(game, "a")
    U.wait(20)
  end
  print("[driver] after the Bill scene: map=" .. tostring(mapId()) ..
    " at (" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY) .. ")" ..
    " harbor scene var=" .. tostring(getVar(VAR_MAP_SCENE_ONE_ISLAND_HARBOR)))
  result(mapId() == ONE_ISLAND or mapId() == ONE_HARBOR,
    "the Bill ferry reached One Island, map=" .. tostring(mapId()))
  result(mapId() == ONE_ISLAND, "standing on One Island itself, map=" .. tostring(mapId()))

  local Fade = require("src.ui.game3.fade")
  result((Fade.t or 0) <= 0, "the ferry fade was undone, veil t=" .. tostring(Fade.t))
  result(not require("src.ui.game3.seagallop").isActive(), "the Bill ferry overlay cleared on One Island")
  U.shot(game, DIR .. "/seagallop_08_one_island.png")

  finish()
end
