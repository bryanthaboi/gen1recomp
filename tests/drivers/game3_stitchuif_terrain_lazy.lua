local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchuif_terrain_lazy"

local GRASS_MAP = "FR_ROUTE_1"
local SPECIES_PIDGEY = 16

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchuif_terrain_lazy")
    love.event.quit(0)
  else
    print("FAIL stitchuif_terrain_lazy failures=" .. failures)
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
  local Party = require("src.core.game3.party")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Battle = require("src.core.game3.battle")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local BattleBg = require("src.core.game3.battle.bg")
  local Ui = require("src.core.game3.battle.ui")
  local BattleChrome = require("src.ui.game3.battle_chrome")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function cached()
    local keys = {}
    for key in pairs(BattleChrome._terrainInfo or {}) do
      if rawget(BattleChrome._terrains, key) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
  end

  local declared = 0
  for _ in pairs(BattleChrome._terrainInfo or {}) do declared = declared + 1 end
  result(declared >= 20, "the cache declares the whole sBattleTerrainTable (" .. declared .. ")")

  local before = cached()
  result(#before == 0,
    "no terrain sheet is decoded before the first battle (" .. table.concat(before, ",") .. ")")

  Map.load(nil, game, GRASS_MAP, { x = 8, y = 8, facing = "down" })
  session.x, session.y, session.facing = 8, 8, "down"
  Player.cellX, Player.cellY = 8, 8
  Player.px, Player.py = 8 * 16, 8 * 16
  Player.targetX, Player.targetY = 8, 8
  U.wait(90)

  session.party = {}
  Party.giveMon(session, 1, 10)

  local ok = BattleBridge.startWild(Runtime._mod, game, { species = SPECIES_PIDGEY, level = 4 },
    { fade = false })
  if not result(ok == true, "a wild battle started on " .. GRASS_MAP) then return finish() end

  local lastTap, f = 0, 0
  for _ = 1, 4000 do
    f = f + 1
    if Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" then break end
    if f - lastTap >= 20 then
      lastTap = f
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  result(Battle.isActive(), "the battle reached the command menu")
  U.wait(30)
  U.shot(game, DIR .. "/stitchuif_terrain_lazy_01_grass_battle.png")

  local key = BattleBg.sheetKey(BattleBg.terrainId())
  result(BattleChrome.drawTerrain(key, 0, 0, 0) == true,
    "the battle's terrain sheet draws (" .. tostring(key) .. ")")

  local after = cached()
  result(#after > 0, "the battle loaded its own sheet (" .. table.concat(after, ",") .. ")")
  local hasKey = false
  for _, k in ipairs(after) do if k == key then hasKey = true end end
  result(hasKey, "and it is the sheet the map asked for")
  result(#after < declared,
    "the other " .. (declared - #after) .. " sheets were never read")

  U.wait(60)
  finish()
end
