-- engine/overworld/player_object.asm:29-41
local U = require("tests.drivers.util")

local FieldMoves = require("src.world.gen2.FieldMoves")
local Palettes = require("src.world.gen2.Palettes")

return function(game)
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/surf-palette-2280"
  local TAG = os.getenv("POKEPORT_VERSION") or "crystal"
  local fails = 0
  local function say(line) print("[2280] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then
    say("FAIL the gen2 world did not boot")
    love.event.quit(1)
    return
  end

  local function surfAs(gender, shot, wantId, label)
    game.save.player = game.save.player or {}
    game.save.player.gender = gender
    world:applyPlayerState(FieldMoves.PLAYER_SURF)
    U.wait(20)
    local id = Palettes.objectPaletteId(world:playerObjectDef())
      or (world.player.spriteDef and world.player.spriteDef.paletteId) or 0
    ok(id == wantId, label .. " (palette id " .. tostring(id)
      .. ", want " .. tostring(wantId) .. ")")
    U.shot(game, DIR .. "/" .. shot)
  end

  world:warpToMapId("NEW_BARK_TOWN", 13, 7, "down")
  U.wait(45)
  say("standing on " .. tostring(world.map.id))

  if TAG == "crystal" then
    surfAs("male", "2280_01_crystal_chris_surf.png", 0, "Chris surfs orange")
    surfAs("female", "2280_02_crystal_kris_surf.png", 1, "Kris surfs blue")
  else
    surfAs("male", "2280_03_gold_surf.png", 1, "Gold's surf blob stays blue")
  end

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
