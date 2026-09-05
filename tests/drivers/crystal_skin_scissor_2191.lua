local U = require("tests.drivers.util")
local TouchSkin = require("src.core.TouchSkin")
local TouchControls = require("src.core.TouchControls")

local SHOTS = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"

return function(game)
  local fails = 0
  local function say(line) print("[skin2191] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the crystal world did not boot")
    love.event.quit(1)
    return
  end

  local skins = TouchSkin.list()
  ok(skins[1] ~= nil, "a skin is installed to select")
  if not skins[1] then love.event.quit(1) return end

  local controls = game.touchControls or TouchControls
  local skin, err = controls:selectSkin(skins[1].id)
  ok(skin ~= nil, "selected skin " .. tostring(skins[1].id) .. " " .. tostring(err or ""))
  U.wait(30)
  ok(TouchSkin.active ~= nil, "the skin is live, so Playfield sets a scissor")

  world:warpToMapId("NEW_BARK_TOWN", 5, 5, "down")
  U.wait(90)
  ok(world.map ~= nil, "the world still draws under the skin cutout")
  U.shot(game, SHOTS .. "/2191_01_crystal_world_under_skin_cutout.png")

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
