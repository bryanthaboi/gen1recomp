local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchimp_heal_locations"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchimp_heal_locations")
    love.event.quit(0)
  else
    print("FAIL stitchimp_heal_locations failures=" .. failures)
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
  local Field = require("src.core.game3.field")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local HealLocations = require("src.core.game3.heal_locations")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  HealLocations.invalidate()
  Field.invalidateFlyDestinations()
  local healRows = HealLocations.load()
  local flyRows = Field.loadFlyDestinations()
  result(healRows == 20, "the mounted cache bakes 20 respawn points (" .. tostring(healRows) .. ")")
  result(flyRows == 20, "the mounted cache bakes 20 Fly destinations (" .. tostring(flyRows) .. ")")
  if healRows ~= 20 or flyRows ~= 20 then
    print("[driver] the mounted cache predates this bake; re-import the identity")
    return finish()
  end

  if #(session.party or {}) == 0 then Party.giveMon(session, 1, 5) end
  result(#(session.party or {}) > 0, "the player has a starter to lose with")

  BattleBridge.installWhiteoutIntercept(nil, game)
  if not result(type(BattleBridge._whiteoutHook) == "function",
    "the whiteout intercept is installed") then
    return finish()
  end

  -- pokefirered/src/heal_location.c:62 SetWhiteoutRespawnWarpAndHealerNpc
  local function whiteoutTo(healId, wantMap, x, y, label, shot)
    local baked = HealLocations.get(healId)
    result(baked ~= nil and baked.map == wantMap,
      label .. ": the baked row names " .. wantMap)
    result(Field.setRespawn(healId) == true, label .. ": setrespawn " .. healId .. " applies")
    result(session.healMap == wantMap, label .. ": the session carries " .. wantMap)
    for _, mon in ipairs(session.party or {}) do
      if type(mon) == "table" then mon.hp = 0 end
    end
    BattleBridge._whiteoutHook()
    U.wait(180)
    print(string.format("[driver] %s map=%s at (%s,%s) lastTalked=%s",
      label, tostring(Map.current), tostring(Player.cellX), tostring(Player.cellY),
      tostring(session.healHealerLocalId)))
    result(Map.current == wantMap, label .. ": the whiteout loaded " .. wantMap)
    result(Map.currentDef() ~= nil, label .. ": the respawn map has a live def")
    result(Player.cellX == x and Player.cellY == y,
      label .. ": the player stands at (" .. x .. "," .. y .. ")")
    if shot then result(U.shot(game, DIR .. "/" .. shot), label .. ": screenshot") end
  end

  whiteoutTo(12, "FR_ROUTE_4_POKEMON_CENTER_1F", 7, 4,
    "Route 4 center", "stitchimp_heal_locations_01_route4_center.png")
  whiteoutTo(20, "FR_SIX_ISLAND_POKEMON_CENTER_1F", 7, 4,
    "Six Island center", "stitchimp_heal_locations_02_six_island_center.png")
  whiteoutTo(10, "FR_INDIGO_PLATEAU_POKEMON_CENTER_1F", 13, 12,
    "Indigo Plateau center", "stitchimp_heal_locations_03_indigo_center.png")

  -- pokefirered/src/region_map.c:4024 SetFlyWarpDestination
  local function flyTo(sec, wantMap, x, y, label, shot)
    local dest = Field.flyDestination(sec)
    result(dest ~= nil and dest.map == wantMap and dest.x == x and dest.y == y,
      label .. ": " .. sec .. " resolves to " .. wantMap .. " (" .. x .. "," .. y .. ")")
    result(Field.flyTo(sec) == true, label .. ": Fly leaves for " .. wantMap)
    for _ = 1, 600 do
      U.wait(1)
      if Map.current == wantMap and not Field.locked then break end
    end
    print(string.format("[driver] %s map=%s at (%s,%s)",
      label, tostring(Map.current), tostring(Player.cellX), tostring(Player.cellY)))
    result(Map.current == wantMap, label .. ": Fly landed on " .. wantMap)
    result(Player.cellX == x and Player.cellY == y,
      label .. ": the player lands at (" .. x .. "," .. y .. ")")
    if shot then result(U.shot(game, DIR .. "/" .. shot), label .. ": screenshot") end
  end

  flyTo("MAPSEC_PEWTER_CITY", "FR_PEWTER_CITY", 17, 26,
    "Fly to Pewter", "stitchimp_heal_locations_04_fly_pewter.png")
  flyTo("MAPSEC_ONE_ISLAND", "SEVII_ONE_ISLAND", 14, 6,
    "Fly to One Island", "stitchimp_heal_locations_05_fly_one_island.png")

  -- pokefirered/src/region_map.c:842 MAPSEC_ROUTE_1 carries HEAL_LOCATION_NONE
  result(Field.flyDestination("MAPSEC_ROUTE_1") == nil, "Route 1 is not a Fly destination")

  finish()
end
