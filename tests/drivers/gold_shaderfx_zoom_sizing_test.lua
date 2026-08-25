-- Regression test: on Gen 2, SHADER FX only ever shaded the small centred
-- "faithful ratio" 160x144 box, never the
-- real on-screen footprint of the live overworld -- unlike Gen 1, whose
-- Renderer.lua grows ShaderFX's rect to the real world canvas/zoom footprint
-- whenever the live overworld is what's on screen (src/render/Renderer.lua,
-- the `self.worldActive` branch around line 977). Gen2's drawViewportFrame
-- instead always built ShaderFX's rect from Chrome.fitScale's fixed
-- faithful-ratio box (src/core/Game2.lua), so on any window that is not
-- exactly 4:3 -- every real phone, and any resized desktop window -- the
-- live world already draws edge to edge past that box (Chrome.lua's own
-- comment: "The live overworld IS the background here -- it draws edge to
-- edge... with no surround to paint first"), and SHADER FX only ever shaded
-- the small box in the middle, leaving the rest of the visible map unshaded.
--
--   POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/gold_shaderfx_zoom_sizing_test.lua \
--     lovec.exe .
--
-- Skips itself (does not fail) if no ShaderFX preset is installed in the
-- save dir's shaders/ folder (see ShaderFX.presetDir()).
local U = require("tests.drivers.util")
local GameViewport = require("src.render.GameViewport")

return function(game)
  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")

  local ShaderFX = require("src.render.ShaderFX")
  local entry = ShaderFX.findEntry("gameboy-color-dot-matrix.slangp")
  if not entry then
    print("[driver] SKIP no ShaderFX preset installed -- cannot exercise ShaderFX.render")
    love.event.quit(0)
    return
  end
  if not entry.converted then
    local ok, err = ShaderFX.convert(entry)
    assert(ok, "ShaderFX.convert failed: " .. tostring(err))
  end
  game.options = game.options or {}
  game.options.shaderfx = entry.name
  game:applyOptions()
  assert(ShaderFX.active("main"), "ShaderFX main slot did not activate")

  -- conf.lua's bare-desktop default (1024x768) is exactly 4:3, which
  -- coincidentally hides this bug -- resize to a 16:9 window, the shape of
  -- every real phone/handheld this project actually ships on, where the
  -- live world draws well past the small faithful-ratio box.
  love.window.setMode(1280, 720, { resizable = true })
  U.wait(5)

  local w, h = GameViewport.dimensions()
  local pw, ph = GameViewport.pixelDimensions()
  assert(game.frameWorldActive, "expected the live overworld to be on screen")

  local rect = ShaderFX._lastRect
  assert(rect, "ShaderFX._lastRect was never set -- ShaderFX.render did not run")
  print(("[driver] window %dx%d (%dx%d px), faithful box would be %dx%d, " ..
    "ShaderFX rect is %.1fx%.1f"):format(
    w, h, pw, ph,
    160 * math.floor(math.min(w / 160, h / 144)),
    144 * math.floor(math.min(w / 160, h / 144)),
    rect.w, rect.h))

  -- Real assertion: with the live overworld on screen, ShaderFX's rect
  -- should track the world's real edge-to-edge footprint (~ the full
  -- window), not the small integer-multiple 4:3 box centered inside it.
  assert(rect.w >= pw - 2 and rect.h >= ph - 2,
    ("SHADER FX's rect only covers %.1fx%.1f of a %dx%d px window -- still " ..
     "the fixed faithful-ratio box, not the live world's real on-screen " ..
     "footprint"):format(rect.w, rect.h, pw, ph))

  print("[driver] PASS gold shaderfx zoom-sizing regression")
  love.event.quit(0)
end
