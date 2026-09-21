local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchuid_region_guide"

local PALLET = "FR_PALLET_TOWN"
local MT_MOON = "FR_MT_MOON_1F"
local TOWN_MAP = 361
local MT_MOON_X, MT_MOON_Y = 9, 3
local MT_MOON_FLAG = "FLAG_WORLD_MAP_MT_MOON_1F"

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/stitchuid_region_guide.log", "a")
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
    say("PASS stitchuid_region_guide")
    love.event.quit(0)
  else
    say("FAIL stitchuid_region_guide failures=" .. failures)
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
  local Player = require("src.core.game3.player")
  local Bag = require("src.core.game3.bag")
  local ItemUse = require("src.core.game3.item_use")
  local RegionMap = require("src.ui.game3.region_map")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function placeAt(mapId, x, y)
    Map.load(nil, game, mapId, { x = x, y = y, facing = "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.targetX, Player.targetY = x, y
    U.wait(90)
  end

  placeAt(PALLET, 10, 6)

  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, TOWN_MAP, 1)

  local function openMap()
    local ok = ItemUse.useField(session, session.bag, TOWN_MAP, nil)
    U.wait(30)
    return ok and RegionMap.isOpen()
  end

  local function moveCursorTo(x, y)
    for _ = 1, 40 do
      if RegionMap.cursorX == x and RegionMap.cursorY == y then return true end
      if RegionMap.cursorX < x then U.tap(game, "right")
      elseif RegionMap.cursorX > x then U.tap(game, "left")
      elseif RegionMap.cursorY < y then U.tap(game, "down")
      else U.tap(game, "up") end
      U.wait(6)
    end
    return RegionMap.cursorX == x and RegionMap.cursorY == y
  end

  local function closeMap()
    for _ = 1, 40 do
      if not RegionMap.isOpen() then break end
      U.tap(game, "b")
      U.wait(8)
    end
    U.wait(20)
  end

  if not result(openMap(), "the TOWN MAP opens the region map") then return finish() end
  if not result(moveCursorTo(MT_MOON_X, MT_MOON_Y), "cursor reaches the MT. MOON cell") then return finish() end
  result(RegionMap.currentDungeonSec() == "MAPSEC_MT_MOON", "the dungeon under the cursor is MT. MOON")
  result(RegionMap.isFlagSet(MT_MOON_FLAG) == false, "MT. MOON has not been visited yet")
  result(RegionMap.canGuideCursor() == false, "the GUIDE is refused before the first visit")
  U.wait(20)

  U.tap(game, "a")
  U.wait(30)
  result(RegionMap.previewDungeon == nil, "A opens no preview before the first visit")
  result(RegionMap.isOpen() == true, "the region map stays open")
  U.shot(game, DIR .. "/stitchuid_region_guide_01_guide_refused.png")

  closeMap()

  -- ../pokefirered/data/maps/MtMoon_1F/scripts.inc:6
  placeAt(MT_MOON, 18, 37)
  result(RegionMap.isFlagSet(MT_MOON_FLAG) == true,
    "walking into MT. MOON ran setworldmapflag FLAG_WORLD_MAP_MT_MOON_1F")

  placeAt(PALLET, 10, 6)
  if not result(openMap(), "the TOWN MAP reopens the region map") then return finish() end
  if not result(moveCursorTo(MT_MOON_X, MT_MOON_Y), "cursor reaches the MT. MOON cell again") then return finish() end
  result(RegionMap.canGuideCursor() == true, "the GUIDE is offered after the visit")
  U.wait(20)
  U.shot(game, DIR .. "/stitchuid_region_guide_02_guide_prompt.png")

  U.tap(game, "a")
  U.wait(120)
  result(RegionMap.previewDungeon == "MAPSEC_MT_MOON", "A opens the MT. MOON preview after the visit")
  U.shot(game, DIR .. "/stitchuid_region_guide_03_preview.png")

  closeMap()
  finish()
end

return run
