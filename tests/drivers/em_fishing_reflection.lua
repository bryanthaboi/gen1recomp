local U = require("tests.drivers.util")

local DIR = os.getenv("POKEPORT_SHOT_DIR") or "shots"

local function fail(msg)
  print("FAIL " .. msg)
  love.event.quit(1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  local Map = require("src.core.game3.map")
  local Field = require("src.core.game3.field")
  local FxRse = require("src.core.game3.field_effects_rse")
  local FieldEffects = require("src.core.game3.field_effects")
  local Ow = require("src.core.game3.ow_sprites")
  local Player = require("src.core.game3.player")

  Map.load(nil, game, "EM_ROUTE104", { x = 28, y = 1, facing = "down" })
  U.wait(60)
  if not Field.startFishing(1) then return fail("could not start fishing") end
  local cast
  for _ = 1, 120 do
    U.wait(1)
    local g = Field.fishingPose()
    if g and g >= 2 then cast = g break end
  end
  if not cast then return fail("fishing never reached the cast frame") end
  U.wait(2)
  U.still(game, DIR .. "/2779_em_fishing_south_reflection.png")
  local refl = FxRse.lastReflections or 0
  print("REFLECTIONS", refl)
  if refl < 1 then return fail("player has no reflection while fishing") end
  local opts = FieldEffects.playerReflectionPose(Player, Ow)
  local spr = Ow.getDraw(Ow.playerGraphicsId(game))
  local frame = Ow.pose(spr, "down", 0, false, opts)
  local want = Ow.fishingAbsFrame("down", Field.fishingPose())
  print("REFL_FRAME", frame, "WANT", want)
  if frame ~= want then return fail("reflection frame " .. tostring(frame) .. " is not the south cast frame") end
  print("PASS reflection uses the south fishing frame")
  love.event.quit(0)
end
