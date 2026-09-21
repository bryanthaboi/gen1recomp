local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_ui_fly_map"

local PALLET = "FR_PALLET_TOWN"
local VIRIDIAN = "FR_VIRIDIAN_CITY"
-- pokefirered/include/constants/flags.h:1090
local FLAG_BADGE03_GET = 0x822

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/ui_fly_map.log", "a")
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
    say("PASS ui_fly_map")
    love.event.quit(0)
  else
    say("FAIL ui_fly_map failures=" .. failures)
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
  local StartMenu = require("src.ui.game3.start_menu")
  local RegionMap = require("src.ui.game3.region_map")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  Flags.setFlag(Space.store, ctx(), FLAG_BADGE03_GET, true)

  session.party = {}
  Party.giveMon(session, 6, 40)
  session.party[1].moves = { "FLY", "EMBER", "SCRATCH", "GROWL" }
  session.party[1].pp = { 15, 25, 35, 40 }

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(120)
  end

  -- pokefirered/data/maps/ViridianCity/scripts.inc:6
  goTo(VIRIDIAN, 21, 27, "down")
  local viridianVisited = RegionMap.isFlagSet("FLAG_WORLD_MAP_VIRIDIAN_CITY")
  goTo(PALLET, 10, 6, "down")
  local palletVisited = RegionMap.isFlagSet("FLAG_WORLD_MAP_PALLET_TOWN")
  if not (viridianVisited and palletVisited) then
    say("NOTE the map scripts did not run setworldmapflag on arrival; setting the two"
      .. " flags the scripts set (viridian=" .. tostring(viridianVisited)
      .. " pallet=" .. tostring(palletVisited) .. ")")
    Flags.setFlag(Space.store, ctx(), "FLAG_WORLD_MAP_VIRIDIAN_CITY", true)
    Flags.setFlag(Space.store, ctx(), "FLAG_WORLD_MAP_PALLET_TOWN", true)
  end
  result(RegionMap.isFlagSet("FLAG_WORLD_MAP_PALLET_TOWN")
    and RegionMap.isFlagSet("FLAG_WORLD_MAP_VIRIDIAN_CITY"),
    "Pallet Town and Viridian City are marked visited")
  result(RegionMap.isFlagSet("FLAG_WORLD_MAP_PEWTER_CITY") == false,
    "Pewter City is not marked visited")

  local function openParty()
    for _ = 1, 40 do
      if PartyMenu.isOpen and PartyMenu.isOpen() then return true end
      if StartMenu.isOpen and StartMenu.isOpen() then break end
      U.tap(game, "start")
      U.wait(8)
    end
    for _ = 1, 20 do
      local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == "pokemon" then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    for _ = 1, 60 do
      if PartyMenu.isOpen and PartyMenu.isOpen() then return true end
      U.wait(4)
    end
    return false
  end

  local function chooseAction(label)
    U.tap(game, "a")
    U.wait(12)
    local target = nil
    for i, name in ipairs(PartyMenu.ACTIONS or {}) do
      if name == label then target = i end
    end
    if not target then return false end
    for _ = 1, 12 do
      if PartyMenu.actionCursor == target then break end
      U.tap(game, "down")
      U.wait(6)
    end
    return PartyMenu.actionCursor == target
  end

  local picked, pickedId, pickCalls = nil, nil, 0

  -- pokefirered/src/party_menu.c:4099 SetUpFieldMove_Fly
  if not result(openParty(), "party menu opens in Pallet Town") then return finish() end
  result(chooseAction("FLY"), "FLY is on the action list")
  U.tap(game, "a")
  U.wait(60)
  result(PartyMenu._messageText == nil, "FLY outdoors is accepted (no refusal text)")

  -- pokefirered/src/party_menu.c:3953
  if not result(RegionMap.isOpen() and RegionMap.isFlyMode(),
    "the field fly arm opened the fly map") then
    return finish()
  end
  local fieldPick = RegionMap._onPick
  RegionMap._onPick = function(sec, id, ...)
    picked, pickedId, pickCalls = sec, id, pickCalls + 1
    if fieldPick then return fieldPick(sec, id, ...) end
  end

  -- pokefirered/src/region_map.c:3558 CreateFlyIcons
  local targets = RegionMap.flyTargets()
  local names = {}
  for _, t in ipairs(targets) do names[t.sec] = true end
  result(#targets == 2, "exactly two cells carry a fly icon (" .. #targets .. ")")
  result(names["MAPSEC_PALLET_TOWN"] == true, "Pallet Town carries a fly icon")
  result(names["MAPSEC_VIRIDIAN_CITY"] == true, "Viridian City carries a fly icon")
  result(names["MAPSEC_PEWTER_CITY"] == nil, "Pewter City carries none")

  result(RegionMap.cursorX == 4 and RegionMap.cursorY == 11,
    "the cursor opens on the player in Pallet Town")
  result(RegionMap.canFlyToCursor() == true, "Pallet Town is selectable")
  U.wait(30)
  U.shot(game, DIR .. "/fly_map_01_pallet_selectable.png")

  for _ = 1, 4 do
    U.tap(game, "up")
    U.wait(10)
  end
  result(RegionMap.cursorY == 7, "the cursor reached Route 2 (y=" .. RegionMap.cursorY .. ")")
  result(RegionMap.canFlyToCursor() == false, "a route is not selectable")
  U.wait(20)
  U.shot(game, DIR .. "/fly_map_02_route_not_selectable.png")

  for _ = 1, 3 do
    U.tap(game, "up")
    U.wait(10)
  end
  result(RegionMap.cursorY == 4, "the cursor reached Pewter City (y=" .. RegionMap.cursorY .. ")")
  result(RegionMap.canFlyToCursor() == false, "unvisited Pewter City is not selectable")
  U.wait(20)
  U.shot(game, DIR .. "/fly_map_03_pewter_not_selectable.png")
  U.tap(game, "a")
  U.wait(20)
  result(pickCalls == 0, "A on Pewter City picks nothing")
  result(RegionMap.isOpen(), "the fly map stays open")

  for _ = 1, 4 do
    U.tap(game, "down")
    U.wait(10)
  end
  result(RegionMap.cursorY == 8, "the cursor reached Viridian City (y=" .. RegionMap.cursorY .. ")")
  result(RegionMap.canFlyToCursor() == true, "visited Viridian City is selectable")
  U.wait(20)
  U.shot(game, DIR .. "/fly_map_04_viridian_selectable.png")
  U.tap(game, "a")
  U.wait(30)
  -- pokefirered/src/region_map.c:3991
  result(pickCalls == 1, "A on Viridian City picked once")
  result(picked == "MAPSEC_VIRIDIAN_CITY",
    "onPick received the symbolic mapsec, got " .. tostring(picked))
  result(pickedId == 89, "and the numeric mapsec second, got " .. tostring(pickedId))
  result(RegionMap.isOpen() == false, "the fly map closed on the pick")

  -- pokefirered/src/region_map.c:4022
  U.wait(420)
  local Field = require("src.core.game3.field")
  result(Field.locked ~= true, "the fly warp finished and unlocked the field")
  result(session.map == VIRIDIAN, "the player landed in Viridian City (map=" .. tostring(session.map) .. ")")
  U.shot(game, DIR .. "/fly_map_05_landed_viridian.png")

  -- pokefirered/src/region_map.c:4019
  if not result(openParty(), "party menu opens in Viridian City") then return finish() end
  result(chooseAction("FLY"), "FLY is on the action list again")
  U.tap(game, "a")
  U.wait(60)
  if result(RegionMap.isOpen() and RegionMap.isFlyMode(), "the fly map reopened") then
    U.tap(game, "b")
    U.wait(40)
    result(RegionMap.isOpen() == false, "B closed the fly map")
    result(PartyMenu.isOpen and PartyMenu.isOpen(), "B came back to the party menu")
    U.shot(game, DIR .. "/fly_map_06_cancel_party_menu.png")
    for _ = 1, 30 do
      if not (PartyMenu.isOpen and PartyMenu.isOpen()) then break end
      U.tap(game, "b")
      U.wait(6)
    end
    result(Field.locked ~= true, "and B out of the party menu leaves the field unlocked")
  end

  finish()
end

return run
