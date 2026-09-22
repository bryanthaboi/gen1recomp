local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_leafgreen"

return function(game)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
  end
  local GV = require("src.core.GameVersion")
  local CF = require("src.import.CacheFs")
  local Contract = require("src.import.CacheContract")
  check(GV.get() == "leafgreen", "LeafGreen selected")
  check(Contract.isReady("leafgreen", CF), "fresh LeafGreen cache satisfies contract")
  local Title = require("src.ui.game3.title_screen")
  local Boot = require("src.ui.game3.boot")
  game.boot.phase = Boot.PHASE.TITLE
  Title.enter(game.boot)
  U.wait(480)
  check(game.boot.title and game.boot.title.leafgreen, "LeafGreen title runs")
  check(game.boot.assets.titleStreak ~= nil, "LeafGreen streak graphics loaded")
  check(game.boot.assets.titleFlames:getHeight() == 176, "eleven leaf animation frames")
  U.shot(game, DIR .. "/title.png")

  game:_handleBootAction({ action = "new_game", name = "LEAF", rivalName = "RED" })
  U.wait(180)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  check(session and session.version == "leafgreen", "new game keeps LeafGreen identity")
  if not session then love.event.quit(1); return end
  local Pokemon = require("src.core.game3.pokemon")
  local stats = Pokemon.stats(410)
  check(stats and stats.atk == 70 and stats.def == 160 and stats.spe == 90, "Deoxys Defense Forme stats")
  local Party = require("src.core.game3.party")
  check(Party.metGame() == 5, "caught Pokemon carry LeafGreen origin")
  Party.giveMon(session, 1, 5)
  local Trade = require("src.core.game3.scripting.natives_trade")
  check(Trade.entry(2).species == 32 and Trade.entry(5).requestedSpecies == 80, "LeafGreen NPC trades")
  local Scene = require("src.ui.game3.new_game_scene")
  check(Scene.nameChoices(0, false)[1] == "GREEN" and Scene.nameChoices(0, true)[1] == "RED", "LeafGreen naming choices")
  local encounters = assert(love.filesystem.load("data/generated/gba/encounters.lua"))()
  local route24 = encounters.FR_ROUTE_24
  local found = false
  for _, slot in ipairs(route24 and route24.land and route24.land.slots or {}) do
    if slot.species == 69 then found = true end
  end
  check(found, "Route 24 has LeafGreen Bellsprout encounters")
  check(game:saveGame(), "LeafGreen save writes to disk")
  local save = require("src.core.SaveData").load()
  check(save and save.version == "leafgreen", "disk save preserves LeafGreen identity")
  local restored = require("src.core.game3.save_schema_firered").fromSaveTable(save)
  check(restored.version == "leafgreen" and #restored.party == #session.party, "LeafGreen save round trip")
  U.shot(game, DIR .. "/bedroom.png")
  if require("src.import.RomImporter").isReady("firered") then
    local Lifecycle = require("src.core.SessionLifecycle")
    for _, edition in ipairs({ "firered", "leafgreen" }) do
      local oldBundle = require("src.core.game3.scripting.space").bundle
      local previous = GV.get()
      Lifecycle.endGameSession(game)
      Lifecycle.endMountedSession(previous)
      GV.set(edition)
      CF.prefix = GV.cachePrefix()
      CF.mountVersion(edition)
      local fresh = require("src.core.Game3").new()
      for k in pairs(game) do game[k] = nil end
      for k, v in pairs(fresh) do game[k] = v end
      setmetatable(game, getmetatable(fresh))
      game:load()
      U.wait(30)
      local bundle = require("src.core.game3.scripting.space").bundle
      check(bundle ~= oldBundle, edition .. " loads its own script bundle after switching")
      local stat = require("src.core.game3.pokemon").stats(410)
      check(stat.atk == (edition == "leafgreen" and 70 or 180), edition .. " reloads edition stats after switching")
      check(require("src.core.game3.party").metGame() == (edition == "leafgreen" and 5 or 4), edition .. " origin after switching")
      game:_handleBootAction({ action = "new_game", name = "SWITCH" })
      U.wait(90)
      check(game.session and game.session.version == edition, edition .. " reaches field after switching")
    end
  end
  print((failures == 0 and "PASS " or "FAIL ") .. "LeafGreen integration")
  love.event.quit(failures == 0 and 0 or 1)
end
