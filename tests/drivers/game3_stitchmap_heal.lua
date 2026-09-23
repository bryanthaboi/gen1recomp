local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchmap_heal"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS stitchmap_heal")
    love.event.quit(0)
  else
    print("FAIL stitchmap_heal failures=" .. failures)
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
  local BattleBridge = require("src.core.game3.battle_bridge")
  local MapCatalog = require("src.import.gba.map_catalog")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  BattleBridge.installWhiteoutIntercept(nil, game)
  if not result(type(BattleBridge._whiteoutHook) == "function", "the whiteout intercept is installed") then
    return finish()
  end

  local Party = require("src.core.game3.party")
  if #(session.party or {}) == 0 then
    Party.giveMon(session, 1, 5)
  end
  result(#(session.party or {}) > 0, "the player has a starter to lose with")

  local function faintParty()
    local n = 0
    for _, mon in ipairs(session.party or {}) do
      if type(mon) == "table" then
        mon.hp = 0
        n = n + 1
      end
    end
    return n
  end

  local function whiteoutTo(healId, pretMap, x, y, label, shot)
    if not result(Field.setRespawn(healId) == true, label .. ": setrespawn " .. healId .. " applies") then
      return
    end
    local want = MapCatalog.pretToEngine(pretMap)
    result(session.healMap == want, label .. ": session heal map is " .. tostring(want))
    local fainted = faintParty()
    result(fainted > 0, label .. ": party is fainted before the whiteout")
    BattleBridge._whiteoutHook()
    U.wait(2)
    print(string.format("[driver] %s map=%s at (%s,%s)",
      label, tostring(Map.current), tostring(Player.cellX), tostring(Player.cellY)))
    result(Map.current == want, label .. ": whiteout loaded " .. tostring(want))
    result(Map.currentDef() ~= nil, label .. ": the respawn map has a live def")
    result(Player.cellX == x and Player.cellY == y, label .. ": player stands at (" .. x .. "," .. y .. ")")
    local healed = true
    for _, mon in ipairs(session.party or {}) do
      if type(mon) == "table" and (mon.hp or 0) <= 0 then healed = false end
    end
    result(healed, label .. ": the party was healed on arrival")
    U.clearWhiteoutRush(game)
    if shot then result(U.shot(game, DIR .. "/" .. shot), label .. ": screenshot") end
  end

  whiteoutTo(12, "Route4_PokemonCenter_1F", 7, 4, "Route 4 center", "stitchmap_heal_01_route4.png")
  whiteoutTo(20, "SixIsland_PokemonCenter_1F", 7, 4, "Six Island center", "stitchmap_heal_02_six_island.png")
  whiteoutTo(1, "PalletTown_PlayersHouse_1F", 8, 5, "Pallet Town", "stitchmap_heal_03_pallet_house.png")

  finish()
end
