-- Regression test: with SHADER FX active on Gen 2 (Gold), opening the
-- START menu used to render as a flat black fill
-- instead of menu content. Root cause: ShaderFX.lua's cropToGbSource()
-- samples the scene canvas via love.graphics.draw(), which multiplies by
-- the current draw color -- the menu's own drawing (black text/border)
-- left that color at (0,0,0,1) and never reset it, so cropToGbSource's own
-- draw silently multiplied its whole output to black. push("all") at the
-- top of cropToGbSource saves/restores state for its caller but does not
-- reset color, so the function must set its own white explicitly rather
-- than trust whatever the caller left active. Fixed by an explicit
-- love.graphics.setColor(1, 1, 1, 1) immediately before that draw call.
--
-- Samples ShaderFX._lastCrop directly rather than a screenshot of the
-- final window: ShaderFX.render() always draws the correct, unmodified
-- `canvas` as a base layer before compositing the (possibly-broken) shader
-- chain output on top, so a whole-window screenshot stays mostly readable
-- even when the crop itself is fully black -- it just loses the shader
-- effect under a faint dark overlay. Only the crop canvas itself catches
-- the bug precisely.
--
--   POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/gold_shaderfx_menu_black_crop_test.lua \
--     lovec.exe .
--
-- Skips itself (does not fail) if no ShaderFX preset is installed in the
-- save dir's shaders/ folder (see ShaderFX.presetDir()) -- this test needs
-- a real preset to exercise cropToGbSource at all.
local U = require("tests.drivers.util")
local StartMenu = require("src.ui.gen2.StartMenu")

-- Same 4x4-grid luminance-range technique this bug was originally
-- characterized with.
local function luminanceRange(canvas)
  local id = canvas:newImageData()
  local w, h = id:getDimensions()
  local minL, maxL = 1, 0
  for gy = 0, 3 do
    for gx = 0, 3 do
      local x = math.min(w - 1, math.floor((gx + 0.5) * w / 4))
      local y = math.min(h - 1, math.floor((gy + 0.5) * h / 4))
      local r, g, b = id:getPixel(x, y)
      local l = 0.299 * r + 0.587 * g + 0.114 * b
      if l < minL then minL = l end
      if l > maxL then maxL = l end
    end
  end
  return maxL - minL
end

return function(game)
  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")

  local ShaderFX = require("src.render.ShaderFX")
  local entry = ShaderFX.findEntry("gameboy-color-dot-matrix.slangp")
  if not entry then
    print("[driver] SKIP no ShaderFX preset installed -- cannot exercise cropToGbSource")
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

  -- Baseline: no menu on the stack, crop should already have real content.
  U.wait(10)
  local baseline = luminanceRange(ShaderFX._lastCrop)
  assert(baseline > 0.05,
    ("sanity check failed: baseline crop (no menu) is already near-flat " ..
     "(variance %.3f) -- something else is broken, not this bug"):format(baseline))

  -- The actual repro: push the START menu, one more frame renders through
  -- it, then sample the same crop canvas again.
  game.stack:push(StartMenu.new(game, { save = game.save }))
  U.wait(3)
  local withMenu = luminanceRange(ShaderFX._lastCrop)
  game.stack:pop()

  assert(withMenu > 0.05,
    ("crop is near-flat with the START menu open (variance %.3f, baseline " ..
     "was %.3f) -- the ShaderFX Gen2 blank-menu bug is back"):format(withMenu, baseline))

  print(("[driver] PASS gold shaderfx menu-blank regression, baseline=%.3f withMenu=%.3f")
    :format(baseline, withMenu))
  love.event.quit(0)
end
