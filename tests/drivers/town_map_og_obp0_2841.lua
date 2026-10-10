-- engine/items/town_map.asm:325
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local PaletteFX = require("src.render.PaletteFX")
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"

  local ok = true
  local function check(label, cond)
    if not cond then ok = false end
    U.log(cond and "PASS" or "FAIL", label)
  end

  game.save.visited = { PALLET_TOWN = true, VIRIDIAN_CITY = true }
  U.teleport(game, "VIRIDIAN_CITY", 20, 20, "down")
  U.wait(10)
  game.save.options = game.save.options or {}
  game.save.options.colors = "ogred"
  PaletteFX.setMode("ogred")
  U.wait(4)
  Screens.push(game, "TownMap")
  U.wait(20)
  local top = game.stack:top()
  check("town map is up", top and top.playerQuad ~= nil)
  local red = (game.data.sprites or {}).SPRITE_RED
  local colors, group = PaletteFX.ogObjNormal()
  local want = red and SpriteRenderer.obpImage(red.image, colors, group)
  check("marker is the rOBP0 $D0 bake", top and want ~= nil and top.playerSheet == want)
  local base = PaletteFX.ogObjBase()
  check("OBJ color 1 is white", table.concat(colors[2], ",") == table.concat(base[1], ","))
  for _ = 1, 60 do
    if top.blink < 16 then break end
    coroutine.yield()
  end
  U.shot(game, DIR .. "/2841_01_town_map_ogred_marker.png")
  love.event.quit(ok and 0 or 1)
end
