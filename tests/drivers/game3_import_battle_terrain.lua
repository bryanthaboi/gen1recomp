local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_import_battle_terrain"

-- include/constants/battle.h:287
local TERRAINS = {
  "grass", "long_grass", "sand", "underwater", "water", "pond", "mountain",
  "cave", "building", "plain", "link", "gym", "leader", "indoor_2", "indoor_1",
  "lorelei", "bruno", "agatha", "lance", "champion",
}

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS import_battle_terrain")
    love.event.quit(0)
  else
    print("FAIL import_battle_terrain failures=" .. failures)
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
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local BattleChrome = require("src.ui.game3.battle_chrome")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local loaded = BattleChrome._terrains or {}
  local missing = {}
  for _, key in ipairs(TERRAINS) do
    local entry = loaded[key]
    if not (entry and entry.image and entry.bgImage and entry.enemyPlat and entry.playerPlat) then
      missing[#missing + 1] = key
    end
  end
  result(#missing == 0, "every sBattleTerrainTable sheet loaded from the cache, missing=" ..
    (#missing == 0 and "none" or table.concat(missing, ",")))

  session.party = {}
  Party.giveMon(session, 1, 12)
  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 19, level = 5 },
    { fade = false })
  result(ok == true, "wild battle started " .. tostring(err or ""))
  if not ok then return finish() end

  local lastTap = 0
  local f = 0
  for _ = 1, 3000 do
    f = f + 1
    if Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" then break end
    if Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
      lastTap = f
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  result(Battle.isActive() and Battle._phase == "command",
    "the battle reached the command menu")
  U.wait(30)
  U.shot(game, DIR .. "/import_battle_terrain_01_indoor_battle.png")

  finish()
end
