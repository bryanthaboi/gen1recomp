-- pokeemerald/src/field_player_avatar.c:1011 PlayerNotOnBikeCollide
local F = require("tests.drivers.em_fa_util")
local S = F.new("em_wall_bump_2787", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_wall_bump_2787")

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  local session = Runtime.getSession()
  if not S.check(session.version == "emerald", "driver runs Emerald") then return S.finish() end
  F.noTrainerSight()

  S.check(F.goTo(game, "EM_MAUVILLE_CITY", 22, 10, "down"), "Mauville reached")
  local spot
  for y = 6, 30 do
    for x = 4, 40 do
      if not spot and Collision.canEnter(game, x, y, {}) then
        for _, dir in ipairs({ "left", "right", "down" }) do
          local d = DELTA[dir]
          local nx, ny = x + d[1], y + d[2]
          local beh = Collision.behavior(x, y)
          if not spot and Collision.arrowWarpDir(beh) ~= dir
              and not Collision.warpAt(nx, ny)
              and not Collision.canEnter(game, nx, ny, { fromX = x, fromY = y, dir = dir }) then
            spot = { x = x, y = y, dir = dir }
          end
        end
      end
    end
  end
  if not S.check(spot ~= nil, "found a wall to walk into") then return S.finish() end
  S.note(("bumping %s at (%d,%d)"):format(spot.dir, spot.x, spot.y))
  F.goTo(game, "EM_MAUVILLE_CITY", spot.x, spot.y, spot.dir)

  local hits = 0
  local orig = Audio.playSe
  Audio.playSe = function(id, ...)
    if id == SE.SE_WALL_HIT then hits = hits + 1 end
    return orig(id, ...)
  end
  local sawWalk, moved, shot = false, false, false
  F.holdKeys(game, { spot.dir }, 70, function()
    if Player.walkInPlace then sawWalk = true end
    if Player.cellX ~= spot.x or Player.cellY ~= spot.y then moved = true end
    if sawWalk and not shot and Player.walkPhase() == 1 then
      shot = true
      S.still(game, "2787_01_wall_bump_stride.png")
    end
  end)
  Audio.playSe = orig

  S.note("SE_WALL_HIT plays=" .. hits)
  S.check(not moved, "the player stays on the tile")
  S.check(sawWalk, "the player walks in place against the wall")
  S.check(hits >= 2, "holding into the wall repeats the bump sound every 32 frames")
  S.finish()
end
