-- Driver: the TOWN MAP player marker wears the OBJ palette (#1437).
-- LoadPlayerSpriteGraphics hands the town map the same walking sheet the
-- overworld draws (engine/items/town_map.asm:342), so the marker has to go
-- through the OBJ ramp and the shade-0 keying every other sprite gets --
-- green on Red, pink on Blue, never a raw white block on the BG ramp.
--
--   POKEPORT_DRIVER=tests/drivers/town_map_marker_bug1437_test.lua \
--     POKEPORT_IDENTITY=bug1437 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local PaletteFX = require("src.render.PaletteFX")
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  game.save.player.name = "bryan"
  game.save.visited = {
    PALLET_TOWN = true, VIRIDIAN_CITY = true, PEWTER_CITY = true,
    CERULEAN_CITY = true, CELADON_CITY = true,
  }
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  local function openMap(mode, tag)
    game.save.options = game.save.options or {}
    game.save.options.colors = mode
    PaletteFX.setMode(mode)
    U.wait(4)
    Screens.push(game, "TownMap")
    U.wait(20)
    local top = game.stack:top()
    check(tag .. ": the TOWN MAP is up", top and top.playerQuad ~= nil)
    -- the marker must be a baked OBJ image, not a fresh newImage of the sheet
    local sprites = game.data.sprites or {}
    local red = sprites.SPRITE_RED
    local colors, group
    if PaletteFX.usesSpriteObp() then
      colors, group = PaletteFX.ogObj()
    else
      colors, group = PaletteFX.dmgObj()
    end
    local want = red and SpriteRenderer.obpImage(red.image, colors, group)
    check(tag .. ": the marker is the OBP-baked sheet",
          top and want ~= nil and top.playerSheet == want)
    -- hold the shot on a frame the blink is showing the marker
    for _ = 1, 40 do
      if top.blink < 16 then break end
      coroutine.yield()
    end
    U.shot(game, DIR .. "/bug1437_" .. tag .. ".png")
    U.tap(game, "b")
    U.wait(10)
  end

  openMap("ogred", "ogred")
  openMap("gbc", "gbc")
  openMap("og", "og")

  U.log("Open the shots: in OG RED the marker over PALLET TOWN is the green")
  U.log("boot-ROM trainer, in the other modes it is coloured by the map zone")
  U.log("like any overworld sprite.  A white box, or a red/black marker on")
  U.log("the BG ramp, is the bug.  The pad is yours -- the TOWN MAP is one")
  U.log("B away and the ITEM bag reopens it.")

  while true do coroutine.yield() end
end
