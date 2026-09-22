-- ../pokecrystal/engine/events/overworld.asm:1444
-- ../pokecrystal/data/maps/attributes.asm:139
local U = require("tests.drivers.util")
local Map = require("src.world.gen2.Map")
local Permissions = require("src.world.gen2.Permissions")
local WorldAPI = require("src.world.gen2.WorldAPI")

local SHOTS = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots/2352"
local TOWN = "GOLDENROD_CITY"
local POND = "ROUTE_34"
local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

return function(game)
  local fails = 0
  local function say(line) print("[edge2352] " .. line) end
  local function ok(cond, label, detail)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. label
      .. (detail ~= nil and (" (" .. tostring(detail) .. ")") or ""))
    return cond
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map and game.save) then
    say("FAIL the crystal world did not boot")
    love.event.quit(1)
    return
  end
  world.noWildEncounters = true
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.OLD_ROD = 1
  local api = WorldAPI.new(game, "driver2352")

  local function offersFish()
    for _, row in ipairs((api:availableFieldActions())) do
      if row.id == "fish" then return true end
    end
    return false
  end

  local function settle()
    for _ = 1, 240 do
      if not world.mapSetup and not world:busy() then break end
      U.wait(1)
    end
    U.wait(10)
  end

  local function mouth(x, y, facing, label, shot)
    world:warpToMapId(TOWN, x, y, facing)
    settle()
    world.player.facing = facing
    U.wait(2)
    ok(world.map and world.map.id == TOWN and world.player.cellX == x
      and world.player.cellY == y, label .. ": standing at " .. x .. "," .. y)
    local ctx = world:fieldContext()
    ok(not Permissions.isWater(ctx.facingColl),
      label .. ": the faced cell is the neighbour's road, not water",
      ("coll $%02x"):format(ctx.facingColl or 0xff))
    ok(not offersFish(), label .. ": no FISH shortcut offered")
    ok(world:useFieldItem("OLD_ROD") == "nowhere",
      label .. ": OLD ROD answers nowhere (PACK stays open, not the time)")
    ok(not world.fishing and not world:busy(),
      label .. ": and no cast started")
    if shot then U.shot(game, SHOTS .. "/" .. shot) end
  end

  for x = 18, 21 do
    mouth(x, 35, "down", "south mouth x=" .. x,
      x == 19 and "2352_01_south_mouth_no_fish.png" or nil)
  end
  for x = 24, 27 do
    mouth(x, 0, "up", "north mouth x=" .. x,
      x == 25 and "2352_02_north_mouth_no_fish.png" or nil)
  end

  local def = world.maps[POND]
  local tileset = def and world.tilesets[def.tileset]
  local shore
  if def and tileset then
    local probe = Map.new(def, tileset)
    local taken = {}
    for _, obj in ipairs(def.objects or {}) do taken[obj.x .. "," .. obj.y] = true end
    for cy = 0, probe.heightCells - 1 do
      for cx = 0, probe.widthCells - 1 do
        for _, facing in ipairs({ "up", "down", "left", "right" }) do
          local d = DELTA[facing]
          if not shore and not taken[cx .. "," .. cy]
              and Permissions.isWalkable(probe:cellCollision(cx, cy))
              and not Permissions.isWater(probe:cellCollision(cx, cy))
              and probe:inBounds(cx + d[1], cy + d[2])
              and Permissions.isWater(probe:cellCollision(cx + d[1], cy + d[2])) then
            shore = { x = cx, y = cy, facing = facing }
          end
        end
      end
    end
  end
  if ok(shore ~= nil, "found a real Route 34 shore cell") then
    world:warpToMapId(POND, shore.x, shore.y, shore.facing)
    settle()
    world.player.facing = shore.facing
    U.wait(2)
    ok(offersFish(), "control: the FISH shortcut is offered at a real pond")
    local outcome = world:useFieldItem("OLD_ROD")
    ok(outcome ~= "nowhere", "control: OLD ROD casts into real water", outcome)
    U.wait(40)
    U.shot(game, SHOTS .. "/2352_03_control_real_pond_cast.png")
  end

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
