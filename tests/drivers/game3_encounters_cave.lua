local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_encounters_cave"

local MT_MOON = "FR_MT_MOON_1F"
local ROUTE_1 = "FR_ROUTE_1"
local SURF_MAP = "FR_ROUTE_21_NORTH"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
    return ok
  end
  local function finish()
    if fails == 0 then
      print("PASS encounters_cave")
      love.event.quit(0)
    else
      print("FAIL encounters_cave failures=" .. fails)
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

  local function enemySpecies()
    local st = Battle.getState and Battle.getState()
    local mon = st and st.enemy and st.enemy.mon
    return mon and (tonumber(mon.species) or mon.species), mon and mon.level
  end

  local function speciesSet(area)
    local out = {}
    for _, slot in ipairs((area and area.slots) or {}) do out[slot.species] = true end
    return out
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

  -- pokefirered/src/wild_encounter.c:404
  placeAt(SURF_MAP, 10, 10, "down")
  Player.surfing = true
  local waterTable = Encounters.tableFor(SURF_MAP)
  local wx, wy, wScore = openCell(2)
  result(wx ~= nil, SURF_MAP .. " has open surfable water (TILE_ENCOUNTER_WATER)")
  result(type(waterTable) == "table" and type(waterTable.water) == "table",
    SURF_MAP .. " carries a water encounter table")
  if wx and waterTable and waterTable.water then
    U.log(string.format("water start (%d,%d) open=%d", wx, wy, wScore))
    placeAt(SURF_MAP, wx, wy, "right")
    Player.surfing = true
    U.wait(60)
    Rng.SeedRng(0x4321)
    Rng.SeedWildEncounterRng(0x4321)
    Encounters.resetRateModifiers()
    local hit, steps = patrol(SURF_MAP, 2, 220)
    U.log(string.format("surf patrol ended at (%d,%d) after %d steps",
      Player.cellX, Player.cellY, steps))
    result(hit, "surfing started a wild battle (steps=" .. steps .. ")")
    if hit then
      U.wait(120)
      local sp, lv = enemySpecies()
      U.log(string.format("surf wild: species=%s level=%s", tostring(sp), tostring(lv)))
      result(speciesSet(waterTable.water)[sp] == true,
        "species " .. tostring(sp) .. " comes from the " .. SURF_MAP .. " water table")
      U.shot(game, DIR .. "/encounters_cave_01_surf_battle.png")
      result(flee(), "left the surf battle")
      U.wait(90)
    end
  end

  -- pokefirered/src/wild_encounter.c:712
  placeAt(ROUTE_1, 9, 18, "down")
  local rx, ry = openCell(0)
  result(rx ~= nil, "Route 1 has open road (TILE_ENCOUNTER_NONE)")
  if rx then
    U.log(string.format("Route 1 road start (%d,%d)", rx, ry))
    placeAt(ROUTE_1, rx, ry, "right")
    Rng.SeedRng(0x1234)
    Rng.SeedWildEncounterRng(0x1234)
    Encounters.resetRateModifiers()
    local hit, steps = patrol(ROUTE_1, 0, 24)
    U.log(string.format("road walk ended at (%d,%d) after %d steps",
      Player.cellX, Player.cellY, steps))
    result(steps >= 8, "the road walk actually moved (" .. steps .. " steps)")
    result(not hit, "no wild battle after " .. steps .. " steps on the Route 1 road")
    U.shot(game, DIR .. "/encounters_cave_02_route1_road.png")
  end

  -- pokefirered/src/wild_encounter.c:366
  placeAt(MT_MOON, 5, 33, "down")
  local cx, cy, cScore = openCell(1)
  result(cx ~= nil, "Mt Moon 1F has open cave floor (TILE_ENCOUNTER_LAND)")
  local landTable = Encounters.tableFor(MT_MOON)
  result(type(landTable) == "table" and type(landTable.land) == "table",
    "Mt Moon 1F carries a land encounter table")
  if cx and landTable and landTable.land then
    U.log(string.format("Mt Moon cave start (%d,%d) open=%d", cx, cy, cScore))
    placeAt(MT_MOON, cx, cy, "right")
    U.shot(game, DIR .. "/encounters_cave_03_mt_moon_floor.png")
    Rng.SeedRng(0x1234)
    Rng.SeedWildEncounterRng(0x1234)
    Encounters.resetRateModifiers()
    local hit, steps = patrol(MT_MOON, 1, 100)
    U.log(string.format("Mt Moon patrol ended at (%d,%d) after %d steps",
      Player.cellX, Player.cellY, steps))
    result(hit, "walking Mt Moon 1F started a wild battle (steps=" .. steps .. ")")
    if hit then
      U.wait(120)
      local sp, lv = enemySpecies()
      U.log(string.format("Mt Moon wild: species=%s level=%s", tostring(sp), tostring(lv)))
      result(speciesSet(landTable.land)[sp] == true,
        "species " .. tostring(sp) .. " comes from the Mt Moon 1F land table")
      U.shot(game, DIR .. "/encounters_cave_04_mt_moon_battle.png")
      result(flee(), "left the Mt Moon battle")
      U.wait(90)
    end
  end

  -- pokefirered/src/wild_encounter.c:601
  if cx and landTable and landTable.land then
    local topLevel = 0
    for _, slot in ipairs(landTable.land.slots or {}) do
      local hi = tonumber(slot.maxLevel or slot.level) or 0
      if hi > topLevel then topLevel = hi end
    end
    U.log("Mt Moon 1F land table top level " .. topLevel)

    placeAt(MT_MOON, cx, cy, "right")
    session.party = {}
    Party.giveMon(session, 6, topLevel + 1)
    session.repelSteps = 250
    Rng.SeedRng(0x5150)
    Rng.SeedWildEncounterRng(0x5150)
    Encounters.resetRateModifiers()
    local blocked, bSteps = patrol(MT_MOON, 1, 70)
    U.log(string.format("repel patrol (lead L%d) ended at (%d,%d) after %d steps",
      topLevel + 1, Player.cellX, Player.cellY, bSteps))
    result(bSteps >= 30, "the repel walk actually moved (" .. bSteps .. " steps)")
    result(not blocked,
      "Repel with a Lv" .. (topLevel + 1) .. " lead blocked every Mt Moon wild in " .. bSteps .. " steps")
    U.shot(game, DIR .. "/encounters_cave_05_mt_moon_repel.png")

    placeAt(MT_MOON, cx, cy, "right")
    session.party = {}
    Party.giveMon(session, 6, topLevel)
    session.repelSteps = 250
    Rng.SeedRng(0x1234)
    Rng.SeedWildEncounterRng(0x1234)
    Encounters.resetRateModifiers()
    local equalHit, eSteps = patrol(MT_MOON, 1, 150)
    U.log(string.format("repel patrol (lead L%d) ended at (%d,%d) after %d steps",
      topLevel, Player.cellX, Player.cellY, eSteps))
    result(equalHit,
      "a wild at exactly the lead's level still battles under Repel (steps=" .. eSteps .. ")")
    if equalHit then
      U.wait(120)
      local sp, lv = enemySpecies()
      U.log(string.format("repel boundary wild: species=%s level=%s", tostring(sp), tostring(lv)))
      result(lv == topLevel,
        "the wild that got through is Lv" .. tostring(lv) .. ", the lead's level")
      U.shot(game, DIR .. "/encounters_cave_06_mt_moon_repel_equal.png")
    end
  end

  finish()
end
