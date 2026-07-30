-- Manual check for the two faint horizontal lines across the title (#373):
-- black gaps between the SGB zone clips plus a too-bright ribbon band.
-- Zones are pokered data/sgb/sgb_packets.asm BlkPacket_Titlescreen (rows
-- 0-7 / 8-9 / 10-17), whose whites all match (data/sgb/sgb_palettes.asm).
--   POKEPORT_DRIVER=tests/drivers/title_seam_bug373_test.lua POKEPORT_IDENTITY=bug373 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
-- Do not set POKEPORT_SPEED: fast-forward desynchronizes the title music.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local Renderer = require("src.render.Renderer")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- past the copyright splash / attract movie (engine/movie/splash.asm)
  U.wait(5)
  U.tap(game, "start")
  U.wait(30)

  local title = game.stack:top()
  check("the title screen is on top",
        title ~= nil and title.screenId == "TitleState")
  if not (title and title.sgbPalettes) then
    U.log("No title state to look at; nothing below can run.")
    while true do coroutine.yield() end
  end

  local opts = game.save.options
  local mode = opts and opts.colors or PaletteFX.mode
  -- the seam only exists under the SGB zone clips, so put the renderer there
  -- rather than trusting whatever COLORS the save was last left on (setMode
  -- is display-only; the option itself is restored below)
  if PaletteFX.mode ~= "gbc" then
    U.log("COLORS is", tostring(mode) .. "; switching the view to SGB for the check")
    PaletteFX.setMode("gbc")
    U.wait(20)
  end
  check("the view is in SGB (the mode this bug shows in)",
        PaletteFX.mode == "gbc")
  if (opts and opts.musicVol or 0) == 0 then
    U.log("WARNING music volume is 0: the title theme will be silent.")
  end
  if (opts and opts.sfxVol or 0) == 0 then
    U.log("WARNING sfx volume is 0: the START press will make no sound.")
  end

  -- the three palette names the zones are built from
  for _, name in ipairs({ "LOGO1", "LOGO2", "MEWMON" }) do
    local pal = PaletteFX.pal(game.data, name)
    check(name .. " resolves to a four-color palette",
          type(pal) == "table" and #pal == 4)
  end

  local function report(z)
    if not z then return end
    for i = 1, #z do
      local c = z[i].colors
      U.log(("zone %d rows %d-%d, white %s"):format(
        i, z[i].y, z[i].y + z[i].h - 1,
        c and c[1] and table.concat(c[1], ",") or "none"))
    end
  end

  local z = title:sgbPalettes(game)
  check("the title builds three zones", z ~= nil and #z == 3)
  if z and #z == 3 then
    check("the ribbon band starts at tile row 8 (y=64)", z[2].y == 64)
    check("the player/mon zone starts at tile row 10 (y=80)", z[3].y == 80)
    check("logo and ribbon share a boundary", z[1].y + z[1].h == z[2].y)
    check("ribbon and mon zone share a boundary", z[2].y + z[2].h == z[3].y)
    local w1, w2, w3 = z[1].colors[1], z[2].colors[1], z[3].colors[1]
    local function sameColor(a, b)
      return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
    end
    check("all three zones share color 0", sameColor(w1, w2) and sameColor(w1, w3))
    report(z)
  end

  -- The black-gap half only exists where the framebuffer is not an integer
  -- multiple of the window, i.e. Android's truncated density (#208).
  local ww, wh = love.graphics.getDimensions()
  local pw, ph = ww, wh
  if love.graphics.getPixelDimensions then
    pw, ph = love.graphics.getPixelDimensions()
  end
  local dpiX, dpiY = pw / ww, ph / wh
  U.log(("surface %dx%d units, %dx%d pixels, dpi %.4f/%.4f, fit scale %d")
    :format(ww, wh, pw, ph, dpiX, dpiY, Renderer:fitScale()))
  if dpiX % 1 == 0 and dpiY % 1 == 0 then
    U.log("Integer DPI here, so the black-gap half cannot show on this")
    U.log("screen at all; only the Android build reproduces it.")
  end

  U.shot(game, SHOT_DIR .. "/bug373_title_gbc.png")
  U.log("captured", SHOT_DIR .. "/bug373_title_gbc.png")

  PaletteFX.setMode("redpp")
  U.wait(20)
  U.shot(game, SHOT_DIR .. "/bug373_title_redpp.png")
  U.log("captured", SHOT_DIR .. "/bug373_title_redpp.png")
  PaletteFX.setMode(mode)
  U.wait(10)

  U.log("The title is on screen and the pad is yours; START replays it.")
  U.log("In SGB the whole background is one off-white: sample left-edge")
  U.log("background above, inside and below the \"Version\" band and all three")
  U.log("read the same, no brighter strip and no dark hairline at rows 64/80.")
  U.log("The redpp shot is pure white throughout with the ink still red on")
  U.log("Red and blue on Blue; run POKEPORT_VERSION=blue to confirm that half.")

  while true do
    coroutine.yield()
  end
end
