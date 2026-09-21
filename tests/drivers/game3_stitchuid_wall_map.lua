local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchuid_wall_map"

local PALLET = "FR_PALLET_TOWN"
local MT_MOON = "FR_MT_MOON_1F"
local MT_MOON_X, MT_MOON_Y = 9, 3
local MT_MOON_FLAG = "FLAG_WORLD_MAP_MT_MOON_1F"
local SWITCH_X, SWITCH_Y = 21, 11
local MB_TOWN_MAP = 0x85

local HOUSES = {
  "FR_PEWTER_CITY_HOUSE1",
  "FR_PEWTER_CITY_HOUSE2",
}

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/stitchuid_wall_map.log", "a")
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
    say("PASS stitchuid_wall_map")
    love.event.quit(0)
  else
    say("FAIL stitchuid_wall_map failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Field = require("src.core.game3.field")
  local RegionMap = require("src.ui.game3.region_map")
  local PokedexChrome = require("src.ui.game3.pokedex_chrome")
  local Strings = require("src.core.Strings")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function placeAt(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(60)
  end

  local function closeMap()
    for _ = 1, 40 do
      if not RegionMap.isOpen() then break end
      U.tap(game, "b")
      U.wait(8)
    end
    U.wait(20)
  end

  -- ../pokefirered/data/maps/MtMoon_1F/scripts.inc:6
  placeAt(MT_MOON, 18, 37)
  result(RegionMap.isFlagSet(MT_MOON_FLAG) == true, "MT. MOON is marked visited")

  -- ../pokefirered/src/field_control_avatar.c:538, data/event_scripts.s:1095
  local found = nil
  for _, mapId in ipairs(HOUSES) do
    if found then break end
    placeAt(mapId, 1, 1)
    for y = 0, 39 do
      for x = 0, 39 do
        if Collision.behavior(x, y) == MB_TOWN_MAP then
          found = { map = mapId, x = x, y = y }
          break
        end
      end
      if found then break end
    end
  end

  if found then
    say("[driver] MB_TOWN_MAP at " .. found.map .. " (" .. found.x .. "," .. found.y .. ")")
    placeAt(found.map, found.x, found.y + 1, "up")
    Field.interact(game)
    for _ = 1, 60 do
      if RegionMap.isOpen() then break end
      U.tap(game, "a")
      U.wait(8)
    end
    result(RegionMap.isOpen() == true, "the wall TOWN MAP object opens the region map")
    say("[driver] EventScript_WallTownMap opened mode=" .. tostring(RegionMap.mode))
    closeMap()
  else
    say("[driver] no MB_TOWN_MAP cell on the Pallet Town interiors, skipping the object step")
  end

  -- ../pokefirered/src/field_specials.c:185, src/region_map.c:603-608
  placeAt(PALLET, 10, 6)
  RegionMap.show({ session = session, mode = "wall" })
  U.wait(30)
  if not result(RegionMap.isOpen() == true, "the wall map opens") then return finish() end
  result(RegionMap.mode == "wall", "REGIONMAP_TYPE_WALL is the open mode")

  local function moveCursorTo(x, y)
    for _ = 1, 60 do
      if RegionMap.cursorX == x and RegionMap.cursorY == y then return true end
      if RegionMap.cursorX < x then U.tap(game, "right")
      elseif RegionMap.cursorX > x then U.tap(game, "left")
      elseif RegionMap.cursorY < y then U.tap(game, "down")
      else U.tap(game, "up") end
      U.wait(6)
    end
    return RegionMap.cursorX == x and RegionMap.cursorY == y
  end

  if not result(moveCursorTo(MT_MOON_X, MT_MOON_Y), "cursor reaches the visited MT. MOON") then
    return finish()
  end
  result(RegionMap.currentDungeonSec() == "MAPSEC_MT_MOON", "the dungeon under the cursor is MT. MOON")
  result(RegionMap.canGuideCursor() == false, "the wall map refuses the GUIDE for a visited dungeon")

  local prompts = {}
  local realPrompt = PokedexChrome.drawControlInfoLeft
  PokedexChrome.drawControlInfoLeft = function(text, x, y)
    prompts[#prompts + 1] = tostring(text)
    return realPrompt(text, x, y)
  end
  U.wait(10)
  local guideDrawn = false
  for _, p in ipairs(prompts) do
    if p == Strings("{A_BUTTON}GUIDE") then guideDrawn = true end
  end
  PokedexChrome.drawControlInfoLeft = realPrompt
  result(guideDrawn == false, "no GUIDE prompt on the wall map top bar")
  U.shot(game, DIR .. "/stitchuid_wall_map_01_no_guide.png")

  U.tap(game, "a")
  U.wait(30)
  result(RegionMap.previewDungeon == nil, "A opens no preview on the wall map")
  result(RegionMap.isOpen() == true, "the wall map stays open")

  if not result(moveCursorTo(SWITCH_X, SWITCH_Y), "cursor reaches the switch button cell") then
    return finish()
  end
  result(RegionMap.hasSwitchButton() == false, "the wall map has no switch button")
  U.shot(game, DIR .. "/stitchuid_wall_map_02_no_switch.png")

  closeMap()
  finish()
end
