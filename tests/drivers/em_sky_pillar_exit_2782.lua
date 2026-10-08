local F = require("tests.drivers.em_fa_util")
local S = F.new("em_sky_pillar_exit_2782", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_sky_pillar_exit_2782")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local session = Runtime.getSession()
  if not S.check(session.version == "emerald", "driver runs Emerald") then return S.finish() end
  S.check(F.goTo(game, "EM_ROUTE131", 36, 8, "up"), "Route 131 south of Sky Pillar door")
  Player.surfing = true
  F.settle(game, 30)
  F.holdKeys(game, { "up" }, 200, function() return F.map() == "EM_SKY_PILLAR_ENTRANCE" end)
  F.settle(game, 300)
  if not S.check(F.map() == "EM_SKY_PILLAR_ENTRANCE", "entered Sky Pillar Entrance") then return S.finish() end
  S.check(not Player.surfing, "inside on foot")
  S.check(S.still(game, "2782_01_inside.png"), "inside screenshot")
  F.holdKeys(game, { "down" }, 200, function() return F.map() == "EM_ROUTE131" end)
  S.note(("spawn cell %d,%d behavior=%s surfing=%s"):format(Player.cellX, Player.cellY,
    tostring(Collision.behavior(Player.cellX, Player.cellY)), tostring(Player.surfing)))
  F.settle(game, 300)
  S.check(F.map() == "EM_ROUTE131", "exited to Route 131")
  S.note(("exit cell %d,%d behavior=%s surfing=%s"):format(Player.cellX, Player.cellY,
    tostring(Collision.behavior(Player.cellX, Player.cellY)), tostring(Player.surfing)))
  S.check(not Player.surfing, "exit on foot, not surfing")
  S.check(S.still(game, "2782_02_exit_route131.png"), "exit screenshot")
  S.finish()
end
