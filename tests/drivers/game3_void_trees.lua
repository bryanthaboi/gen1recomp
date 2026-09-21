local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_void_trees"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_void_trees")
    love.event.quit(0)
  else
    print("FAIL game3_void_trees failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local FieldView = require("src.core.game3.field_view")
  local NativeTileset = require("src.core.game3.tileset_native")
  local VoidFill = require("src.core.game3.void_fill")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end

  local mapId = "FR_PALLET_TOWN"
  Map.load(nil, game, mapId, { x = 8, y = 10, facing = "down" })
  game.session.x, game.session.y, game.session.facing = 8, 10, "down"
  U.wait(60)

  local layout = Map.ensureMidLayout(game, mapId)
  if not result(layout ~= nil, "Pallet Town mid layout bound") then return finish() end
  local pair = layout.pair
  print("pair=" .. tostring(pair) .. " size=" .. tostring(layout.width) .. "x" .. tostring(layout.height))

  local vx, vy = (layout.width or 24) + 6, 10
  Player.reset(vx, vy, "down")
  game.session.x, game.session.y = vx, vy
  FieldView._nativeDirty = true
  U.wait(30)
  U.shot(game, DIR .. "/2309_02_void_mode_map.png")

  local primary = VoidFill.primaryFor(pair)
  result(primary == "general", "pallet pair primary is general")
  local has = function(m) return NativeTileset.hasMid(pair, m) end
  local treeBorder = VoidFill.borderFor("trees")
  if not result(treeBorder ~= nil, "tree border resolved from the cached Pallet layout") then
    return finish()
  end
  local same = #treeBorder.mids == #layout.borderMids
  for i, mid in ipairs(treeBorder.mids) do
    if layout.borderMids[i] ~= mid then same = false end
  end
  result(same, "tree border equals Pallet's cached borderMids")
  local treesOk = true
  for _, mid in ipairs(treeBorder.mids) do
    if not has(mid) then treesOk = false end
  end
  result(treesOk, "pallet pair packs all four tree mids")

  VoidFill.setMode("trees")
  U.wait(30)
  U.shot(game, DIR .. "/2309_03_void_trees.png")
  result(VoidFill.mode == "trees", "void mode is trees")

  local seen, distinct = {}, 0
  for cy = vy - 1, vy do
    for cx = vx - 1, vx do
      local mid = VoidFill.fillAt("trees", cx, cy, has, primary)
      if mid and not seen[mid] then
        seen[mid] = true
        distinct = distinct + 1
      end
    end
  end
  result(distinct == 4, "on-screen 2x2 void window draws 4 distinct tree mids")

  VoidFill.setMode("water")
  U.wait(30)
  U.shot(game, DIR .. "/2309_04_void_water.png")
  local cinnabar = Map.ensureMidLayout(game, "FR_CINNABAR_ISLAND")
  local waterMid = cinnabar and cinnabar.borderMids and cinnabar.borderMids[1]
  result(waterMid ~= nil
    and VoidFill.fillAt("water", vx, vy, has, primary) == waterMid,
    "water void uses Cinnabar's cached border metatile")

  VoidFill.setMode("black")
  U.wait(30)
  U.shot(game, DIR .. "/2309_05_void_black.png")
  result(VoidFill.fillAt("black", vx, vy) == false, "black void skips the cell")

  VoidFill.setMode("map")
  U.wait(20)

  local function bytes(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
  end

  local houseId = "FR_PLAYERS_HOUSE_2F"
  Map.load(nil, game, houseId, { x = 6, y = 5, facing = "down" })
  Player.reset(6, 5, "down")
  game.session.x, game.session.y, game.session.facing = 6, 5, "down"
  U.wait(60)
  local house = Map.ensureMidLayout(game, houseId)
  local housePair = house and house.pair
  local housePrimary = VoidFill.primaryFor(housePair)
  print("house pair=" .. tostring(housePair) .. " primary=" .. tostring(housePrimary))
  result(housePrimary == "building", "player's house primary is building")
  local houseHas = function(m) return NativeTileset.hasMid(housePair, m) end
  local packed = true
  for _, mid in ipairs(treeBorder.mids) do
    if not houseHas(mid) then packed = false end
  end
  print("house pair packs the four tree ids = " .. tostring(packed))

  FieldView._nativeDirty = true
  U.wait(30)
  U.shot(game, DIR .. "/2309_06_house_map.png")
  VoidFill.setMode("trees")
  U.wait(30)
  U.shot(game, DIR .. "/2309_07_house_trees.png")
  result(VoidFill.fillAt("trees", -1, -1, houseHas, housePrimary) == nil,
    "trees fall through on a building primary")
  local a, b = bytes(DIR .. "/2309_06_house_map.png"), bytes(DIR .. "/2309_07_house_trees.png")
  result(a ~= nil and a == b, "house frame is identical in map and trees mode")
  VoidFill.setMode("water")
  U.wait(30)
  U.shot(game, DIR .. "/2309_08_house_water.png")
  local c = bytes(DIR .. "/2309_08_house_water.png")
  result(a ~= nil and a == c, "house frame is identical in map and water mode")

  VoidFill.setMode("map")
  U.wait(20)

  finish()
end
