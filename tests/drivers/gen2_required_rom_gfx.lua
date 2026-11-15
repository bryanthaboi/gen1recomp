-- engine/tilesets/tileset_anims.asm:167
local U = require("tests.drivers.util")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2-required-rom-gfx"
  local GameVersion = require("src.core.GameVersion")
  local fails = 0
  local function check(cond, label)
    print(((cond and "PASS " or "FAIL ") .. label))
    if not cond then fails = fails + 1 end
    return cond
  end

  U.wait(45)
  local world = game.world
  if not check(world and world.map, "gen2_rom_gfx_world_boots") then
    love.event.quit(1)
    return
  end
  local crystal = GameVersion.engine() == "crystal"

  check(world.grassRustleImage and world.jumpShadowImage
    and world.cutGrassImage and world.fishingSheet,
    "gen2_rom_gfx_emotes_loaded")
  check((world.fishingSheetFemale ~= nil) == crystal,
    "gen2_rom_gfx_kris_fishing_only_on_crystal")
  check(world.healMachineImage and world.healMachinePalette,
    "gen2_rom_gfx_heal_machine_loaded")

  world:warpToMapId("CHERRYGROVE_CITY", 22, 16, "down")
  U.wait(30)
  local tileset = world.tilesets[world.map.def.tileset]
  local wanted = world:animLayers(tileset) or {}
  local kinds = {}
  for _, layer in pairs(wanted) do kinds[layer.kind] = true end
  check(kinds.water, "gen2_rom_gfx_water_layer")
  check(kinds.flower, "gen2_rom_gfx_flower_layer")
  check(world:animSheets().water ~= nil, "gen2_rom_gfx_border_water_sheet")
  local timer = world.animTimer
  U.wait(60)
  check(world.animTimer ~= timer, "gen2_rom_gfx_tile_anim_ticks")
  check(U.still(game, out .. "/cherrygrove_water_flowers.png"),
    "gen2_rom_gfx_cherrygrove_shot")

  print(("gen2 required rom gfx: %d failure(s)"):format(fails))
  love.event.quit(fails == 0 and 0 or 1)
end
