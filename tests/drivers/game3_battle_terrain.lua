local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_battle_terrain"

local MT_MOON = "FR_MT_MOON_1F"
local SURF_MAP = "FR_ROUTE_21_NORTH"
local GRASS_MAP = "FR_ROUTE_1"
local GYM_MAP = "FR_PEWTER_CITY_GYM"
-- pokefirered/include/constants/opponents.h:148
local TRAINER_CAMPER_LIAM = 142

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    if fails == 0 then
      print("PASS battle_terrain")
      love.event.quit(0)
    else
      print("FAIL battle_terrain failures=" .. fails)
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
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Rng = require("src.core.game3.rng")
  local BattleBg = require("src.core.game3.battle.bg")
  local BattleChrome = require("src.ui.game3.battle_chrome")

  local T = BattleBg.TERRAIN
  local NAME = {
    [T.GRASS] = "GRASS", [T.LONG_GRASS] = "LONG_GRASS", [T.SAND] = "SAND",
    [T.UNDERWATER] = "UNDERWATER", [T.WATER] = "WATER", [T.POND] = "POND",
    [T.MOUNTAIN] = "MOUNTAIN", [T.CAVE] = "CAVE", [T.BUILDING] = "BUILDING",
    [T.PLAIN] = "PLAIN",
  }

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.party = {}
  Party.giveMon(session, 6, 50)

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

  local function enterable(want, cx, cy)
    if Encounters.encounterTypeAt(cx, cy) ~= want then return false end
    if want == 2 then return Collision.isWater(cx, cy) end
    return Collision.isWalkable(cx, cy) and Collision.canEnter(game, cx, cy, {}) ~= false
  end

  local function openCell(want)
    local layout = Map._def and Map._def.midLayout
    if not layout then return nil end
    local best, bestScore = nil, -1
    for cy = 3, layout.height - 4 do
      for cx = 3, layout.width - 4 do
        if enterable(want, cx, cy) then
          local score = 0
          for dy = -2, 2 do
            for dx = -2, 2 do
              if enterable(want, cx + dx, cy + dy) then score = score + 1 end
            end
          end
          if score > bestScore then best, bestScore = { cx, cy }, score end
        end
      end
    end
    if best and bestScore >= 9 then return best[1], best[2], bestScore end
    return nil
  end

  local DIRS = { "right", "down", "left", "up" }
  local DELTA = { right = { 1, 0 }, down = { 0, 1 }, left = { -1, 0 }, up = { 0, -1 } }

  local function patrol(mapId, want, maxSteps)
    local steps, stuck, di = 0, 0, 1
    while steps < maxSteps and stuck < 24 do
      if Battle.isActive and Battle.isActive() then return true, steps end
      local d = DELTA[DIRS[di]]
      local tx, ty = Player.cellX + d[1], Player.cellY + d[2]
      if not enterable(want, tx, ty) then
        stuck = stuck + 1
        di = (di % 4) + 1
      else
        local bx, by = Player.cellX, Player.cellY
        U.hold(game, DIRS[di], 20)
        U.wait(4)
        if Battle.isActive and Battle.isActive() then return true, steps end
        if Map.current ~= mapId then return false, steps end
        if Player.cellX ~= bx or Player.cellY ~= by then
          steps = steps + 1
          stuck = 0
        else
          stuck = stuck + 1
          di = (di % 4) + 1
        end
      end
    end
    return (Battle.isActive and Battle.isActive()) or false, steps
  end

  -- pokefirered/src/wild_encounter.c:355 StandardWildEncounter
  local function forceEncounter(mapId, want)
    local enc
    for _ = 1, 400 do
      enc = (want == 2) and Encounters.rollWater(mapId) or Encounters.rollLand(mapId)
      if enc then break end
    end
    if not enc then return false end
    local BattleBridge = require("src.core.game3.battle_bridge")
    local ok = BattleBridge.startWild(Runtime._mod, game, enc, {})
    if not ok then return false end
    for _ = 1, 600 do
      if Battle.isActive and Battle.isActive() then return true end
      U.wait(1)
    end
    return Battle.isActive and Battle.isActive()
  end

  local function flee()
    for _ = 1, 400 do
      if not (Battle.isActive and Battle.isActive()) then return true end
      if Battle._phase == "command" and Ui._mode == "menu" then
        U.tap(game, "down")
        U.wait(6)
        U.tap(game, "right")
        U.wait(6)
        U.tap(game, "a")
        U.wait(20)
      else
        U.tap(game, "a")
        U.wait(8)
      end
    end
    return not (Battle.isActive and Battle.isActive())
  end

  local function mapTypeOf(mapId)
    local def = game and game.data and game.data.maps and game.data.maps[mapId]
    return def and def.mapType
  end

  local function report(label)
    local st = Battle.getState and Battle.getState()
    local id = st and st.terrain
    local key = BattleBg.sheetKey(BattleBg.terrainId())
    U.log(string.format("%s: terrain=%s(%s) sheet=%s drawnId=%s",
      label, tostring(id), tostring(NAME[id] or id), tostring(key),
      tostring(BattleBg.terrainId())))
    return id, key
  end

  local function loaded(key)
    local t = BattleChrome._terrains or {}
    return t[key] ~= nil
  end

  Rng.SeedRng(0x1357)
  Rng.SeedWildEncounterRng(0x1357)

  -- pokefirered/src/battle_setup.c:485 MAP_TYPE_UNDERGROUND
  placeAt(MT_MOON, 5, 33, "down")
  result(Map.current == MT_MOON, "loaded " .. MT_MOON)
  U.log("mapType(" .. MT_MOON .. ") = " .. tostring(mapTypeOf(MT_MOON)))
  local cx, cy, cScore = openCell(1)
  if result(cx ~= nil, MT_MOON .. " has open cave floor with encounters") then
    U.log(string.format("cave start (%d,%d) open=%d", cx, cy, cScore))
    placeAt(MT_MOON, cx, cy, "right")
    Encounters.resetRateModifiers()
    local hit, steps = patrol(MT_MOON, 1, 8)
    if not hit then hit = forceEncounter(MT_MOON, 1) end
    result(hit, "walking Mt Moon started a wild battle (steps=" .. steps .. ")")
    if hit then
      U.wait(120)
      local id, key = report("mt moon")
      result(id == T.CAVE, "the Mt Moon battle terrain is CAVE")
      result(key == "cave", "the cave sheet is the one drawn")
      result(loaded("cave"), "the cave sheet is loaded from the cache")
      result(U.shot(game, DIR .. "/battle_terrain_01_mt_moon_cave.png"),
        "shot the cave battle background")
      result(flee(), "left the cave battle")
      U.wait(30)
    end
  end

  -- pokefirered/src/battle_setup.c:501 MetatileBehavior_IsDeepWaterTerrain
  placeAt(SURF_MAP, 10, 10, "down")
  Player.surfing = true
  U.log("mapType(" .. SURF_MAP .. ") = " .. tostring(mapTypeOf(SURF_MAP)))
  local wx, wy, wScore = openCell(2)
  if result(wx ~= nil, SURF_MAP .. " has open surfable water") then
    U.log(string.format("water start (%d,%d) open=%d", wx, wy, wScore))
    placeAt(SURF_MAP, wx, wy, "right")
    Player.surfing = true
    U.log("water behavior = " .. string.format("0x%02X",
      tonumber(Collision.behavior(wx, wy)) or 0))
    Encounters.resetRateModifiers()
    local hit, steps = patrol(SURF_MAP, 2, 8)
    if not hit then hit = forceEncounter(SURF_MAP, 2) end
    result(hit, "surfing started a wild battle (steps=" .. steps .. ")")
    if hit then
      U.wait(120)
      local id, key = report("surf")
      result(id == T.WATER or id == T.POND, "the surf battle terrain is WATER or POND")
      result(key == "water" or key == "pond", "a water sheet is the one drawn")
      result(loaded(key), "the " .. tostring(key) .. " sheet is loaded from the cache")
      result(U.shot(game, DIR .. "/battle_terrain_02_surf.png"),
        "shot the surf battle background")
      result(flee(), "left the surf battle")
      U.wait(30)
    end
  end
  Player.surfing = false

  -- pokefirered/src/battle_setup.c:473 MetatileBehavior_IsTallGrass
  placeAt(GRASS_MAP, 9, 9, "down")
  U.log("mapType(" .. GRASS_MAP .. ") = " .. tostring(mapTypeOf(GRASS_MAP)))
  local gx, gy, gScore = openCell(1)
  if result(gx ~= nil, GRASS_MAP .. " has open tall grass") then
    U.log(string.format("grass start (%d,%d) open=%d", gx, gy, gScore))
    placeAt(GRASS_MAP, gx, gy, "right")
    Encounters.resetRateModifiers()
    local hit, steps = patrol(GRASS_MAP, 1, 8)
    if not hit then hit = forceEncounter(GRASS_MAP, 1) end
    result(hit, "walking Route 1 grass started a wild battle (steps=" .. steps .. ")")
    if hit then
      U.wait(120)
      local id, key = report("route 1")
      result(id == T.GRASS, "the Route 1 battle terrain is GRASS")
      result(key == "grass", "the grass sheet is the one drawn")
      result(U.shot(game, DIR .. "/battle_terrain_03_route1_grass.png"),
        "shot the grass battle background")
      result(flee(), "left the grass battle")
    end
  end

  -- pokefirered/src/battle_bg.c:1073 GetCurrentMapBattleScene
  placeAt(GYM_MAP, 5, 12, "up")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Trainers = require("src.core.game3.scripting.trainers")
  U.log("battleType(" .. GYM_MAP .. ") = " .. tostring(BattleBridge.mapBattleScene(GYM_MAP)))
  local liam = Trainers.foeFromId(TRAINER_CAMPER_LIAM)
  if result(liam ~= nil, "the Pewter Gym trainer came out of the cache") then
    local info = Trainers.info(TRAINER_CAMPER_LIAM)
    U.log("liam class=" .. tostring(info and info.class))
    local ok = BattleBridge.start(Runtime._mod, game, liam,
      { wild = false, trainerId = TRAINER_CAMPER_LIAM, fade = false })
    result(ok == true, "the gym trainer battle started")
    for _ = 1, 900 do
      if Battle._phase == "command" and Ui._mode == "menu" then break end
      U.wait(1)
    end
    local id, key = report("pewter gym")
    result(BattleBg.terrainId() == T.GYM, "a gym map draws the GYM background")
    result(id == T.BUILDING, "and gBattleTerrain stays BUILDING")
    result(key == "gym", "the gym sheet is the one drawn")
    result(loaded("gym"), "the gym sheet is loaded from the cache")
    result(U.shot(game, DIR .. "/battle_terrain_04_pewter_gym.png"),
      "shot the gym battle background")
    Battle.abort("run")
    for _ = 1, 600 do
      if not (Battle.isActive and Battle.isActive()) then break end
      U.wait(1)
    end
  end

  finish()
end
