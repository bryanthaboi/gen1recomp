local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_league_rerun"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_league_rerun")
    love.event.quit(0)
  else
    print("FAIL game3_league_rerun failures=" .. failures)
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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Party = require("src.core.game3.party")
  local Battle = require("src.core.game3.battle")
  local Objects = require("src.core.game3.objects")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.party = {}
  Party.giveMon(session, 6, 100)

  local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  local mapId = (okC and MapCatalog.pretToEngine and MapCatalog.pretToEngine("PokemonLeague_LoreleisRoom"))
    or "FR_POKEMON_LEAGUE_LORELEIS_ROOM"

  -- data/scripts/hall_of_fame.inc:24 leaves the E4 trainer flags set after a clear
  Flags.setFlag(Space.store, nil, Flags.trainerFlagId(410), true)
  Flags.setFlag(Space.store, nil, Flags.IDS.FLAG_DEFEATED_LORELEI, false)
  Flags.setVar(Space.store, nil, Flags.IDS.VAR_MAP_SCENE_POKEMON_LEAGUE, 1)

  Map.load(nil, game, mapId, { x = 6, y = 6, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 6, 6, "up"
  U.wait(40)
  result(Map.current == mapId, "loaded " .. tostring(mapId))
  result(Flags.getFlag(Space.store, nil, Flags.trainerFlagId(410)) == true,
    "TRAINER_ELITE_FOUR_LORELEI flag still set from the first clear")
  if not result(Objects.find(1) ~= nil, "Lorelei is in her room") then return finish() end

  U.tap(game, "a")
  local started = false
  for _ = 1, 900 do
    if Battle.isActive() then started = true break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    U.wait(2)
  end
  result(started, "second League run: Lorelei's battle starts")
  result(Flags.getFlag(Space.store, nil, Flags.IDS.FLAG_DEFEATED_LORELEI) ~= true,
    "the door script did not run (FLAG_DEFEATED_LORELEI still clear)")
  if started then
    U.wait(90)
    result(U.shot(game, DIR .. "/spec_lorelei_rerun_battle.png"), "screenshot spec_lorelei_rerun_battle")
  end
  return finish()
end
