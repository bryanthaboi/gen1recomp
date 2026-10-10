local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("em_mossdeep_rotated_sight_2827")

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

return function(game)
  if not F.boot(game) then return F.finish() end
  F.givePartyAndRepel()
  local Objects = require("src.core.game3.objects")
  local TrainerSight = require("src.core.game3.trainer_sight")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Collision = require("src.core.game3.collision")

  F.check(F.goTo(game, "EM_MOSSDEEP_CITY_GYM", 3, 31, "up"), "Mossdeep Gym loads")
  local trainers = {}
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    local tid = eo and TrainerSight.getTrainerId(eo)
    if tid and TrainerSight.isTrainerType(eo) then
      trainers[#trainers + 1] = { eo = eo, tid = tid, x = eo.cellX, y = eo.cellY, facing = eo.facing }
      Flags.setFlag(Space.store, nil, Flags.trainerFlagId(tid), true)
    end
  end

  Player.facing = "up"
  for _ = 1, 20 do
    if Player.moving then break end
    U.hold(game, "up", 1)
  end
  for _ = 1, 120 do
    if Space.vm and Space.vm:isRunning() then break end
    U.wait(1)
  end
  for _ = 1, 3000 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    U.wait(1)
  end
  F.check(not (Space.vm and Space.vm:isRunning()), "yellow switch script finishes")
  U.wait(10)

  local target
  for _, t in ipairs(trainers) do
    local eo = t.eo
    print(string.format("[driver] INFO lid=%d tid=%d (%d,%d) %s -> (%d,%d) %s frozen=%s busy=%s mv=%s def=(%s,%s)",
      eo.localId, t.tid, t.x, t.y, t.facing, eo.cellX, eo.cellY, tostring(eo.facing),
      tostring(eo.frozen), tostring(eo.scriptBusy), tostring(eo.movement),
      tostring(eo.def and eo.def.x), tostring(eo.def and eo.def.y)))
    if not target and eo.facing ~= t.facing and (eo.cellX ~= t.x or eo.cellY ~= t.y) then target = t end
  end
  if not F.check(target ~= nil, "a trainer was shifted and rotated by the yellow switch") then return F.finish() end
  local eo = target.eo
  local d = DELTA[eo.facing]
  local px, py = eo.cellX + d[1], eo.cellY + d[2]
  F.check(Collision.inBounds(px, py), string.format("cell in front of rotated trainer (%d,%d)", px, py))

  Flags.setFlag(Space.store, nil, Flags.trainerFlagId(target.tid), false)
  Player.cellX, Player.cellY = px, py
  Player.prevCellX, Player.prevCellY = px, py
  Player.px, Player.py = px * 16, py * 16
  Player.targetX, Player.targetY = px, py
  Player.facing = ({ up = "down", down = "up", left = "right", right = "left" })[eo.facing]
  local s = require("src.core.game3.runtime").getSession()
  if s then s.x, s.y, s.facing = px, py, Player.facing end

  local spotted = false
  for _ = 1, 90 do
    if Field.locked or eo.scriptBusy or (Space.vm and Space.vm:isRunning()) then spotted = true break end
    U.wait(1)
  end
  F.shot(game, "2827_01_player_in_rotated_sight.png", true)
  F.check(spotted, "rotated trainer spots a standing player in its new sight line")
  F.finish()
end
