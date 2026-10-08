local F = require("tests.drivers.em_fa_util")
local S = F.new("em_bike_door_speed_2784", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_bike_door_speed_2784")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Bike = require("src.core.game3.bike")
  local session = Runtime.getSession()
  if not S.check(session.version == "emerald", "driver runs Emerald") then return S.finish() end
  for _, kind in ipairs({ "mach", "acro" }) do
    if Player.biking then Bike.rse(session).getOnOff(Player.bikeType, session) end
    S.check(F.goTo(game, "EM_MAUVILLE_CITY", 22, 10, "up"), kind .. " Mauville Center door approach")
    F.useRegistered(game, F.give(kind == "mach" and "ITEM_MACH_BIKE" or "ITEM_ACRO_BIKE"))
    S.check(Player.biking and Player.bikeType == kind, kind .. " mounted")
    local frames, sawStep = 0, false
    local approach = 0
    F.holdKeys(game, { "up" }, 120, function()
      if Player.moving and Player.targetY == 6 then approach = Player.stepFrames end
      if Player.moving and Player.targetY == 5 then
        sawStep = true
        frames = math.max(frames, Player.stepFrames or 0)
      end
      return sawStep and not Player.moving
    end)
    S.note(kind .. " approach stepFrames=" .. approach .. " door step stepFrames=" .. frames)
    S.check(sawStep, kind .. " door entrance step happened")
    S.check(frames == 16, kind .. " door entrance step at walk speed (16 frames)")
    F.settle(game, 400)
    S.check(F.map() ~= "EM_MAUVILLE_CITY", kind .. " entered the Center")
  end
  S.finish()
end
