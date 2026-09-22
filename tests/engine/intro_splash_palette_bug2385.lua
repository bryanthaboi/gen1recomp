package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local SpriteRenderer = require("src.render.SpriteRenderer")
local IntroMovie = require("src.ui.IntroMovie")

local prevVersion, prevMode = GameVersion.get(), PaletteFX.mode

local STAR_START, FLASH_START = 64, 104
local WAVES_START, SPLASH_FRAMES = 134, 318

local LOGO = "tests/fixtures/missing_gflogo_2385.png"
local TEXT = "tests/fixtures/missing_gftext_2385.png"
local STAR = "tests/fixtures/missing_bigstar_2385.png"

local function pal(n)
  return { { 255, 239, 255 }, { n, 200, 100 }, { n, 90, 40 }, { 16, 16, 16 } }
end
local PALS = { palettes = {
  GAMEFREAK = pal(1), REDMON = pal(2), VIRIDIAN = pal(3), BLUEMON = pal(4),
} }

local function newGame(studio)
  return {
    data = { palettes = PALS, field = { intro = {
      gamefreakLogo = { path = LOGO },
      gamefreakText = { path = TEXT },
      bigStar = { path = STAR },
      studio = studio,
    } } },
    stack = { pop = function() end },
  }
end

local bakes = {}
local realObp = SpriteRenderer.obpImage
SpriteRenderer.obpImage = function(path, colors, group)
  bakes[#bakes + 1] = { path = path, colors = colors, group = group }
  return realObp(path, colors, group)
end

local function sameRamp(a, b)
  if not (a and b) then return false end
  for i = 1, 4 do
    if a[i] ~= b[i] then return false end
  end
  return true
end

local function ramp(base, i1, i2, i3)
  return { base[1], base[i1 + 1], base[i2 + 1], base[i3 + 1] }
end

local function bakeFor(list, path, group)
  for _, b in ipairs(list) do
    if b.path == path and b.group == group then return b end
  end
end

local function drawSplash(mode, version, timer)
  GameVersion.set(version)
  PaletteFX.setMode(mode)
  local movie = IntroMovie.new(newGame())
  movie.phase = 2
  movie.timer = timer
  local before = #bakes
  PaletteFX.clearSpriteRedraws()
  PaletteFX.setPass("ui")
  local ok, err = pcall(movie.draw, movie)
  PaletteFX.setPass(nil)
  check(ok, mode .. "/" .. version .. " splash draw runs headless" .. (ok and "" or (": " .. tostring(err))))
  local out, newBakes = {}, {}
  for i, r in ipairs(PaletteFX.uiSpriteRedraws()) do out[i] = r end
  for i = before + 1, #bakes do newBakes[#newBakes + 1] = bakes[i] end
  PaletteFX.clearSpriteRedraws()
  return out, newBakes, movie
end

do
  local game = newGame()
  for _, v in ipairs({ "red", "blue" }) do
    GameVersion.set(v)
    PaletteFX.setMode("ogred")
    local movie = IntroMovie.new(game)
    local z = movie:sgbPalettes(game)
    check(z and z[1], "ogred/" .. v .. ": the copyright card has palette zones")
    check(z and z[1] and sameRamp(z[1].colors, PaletteFX.ogBg()),
          "ogred/" .. v .. ": the copyright card wears the boot-ROM BG ramp")
    PaletteFX.setMode("gbc")
    z = movie:sgbPalettes(game)
    eq(z and #z, 4, "gbc/" .. v .. ": the copyright card gets PalPacket_GameFreakIntro's four zones")
    movie.phase = 2
    local z2 = movie:sgbPalettes(game)
    check(z and z2 and sameRamp(z[1].colors, z2[1].colors),
          "gbc/" .. v .. ": the card and the splash share PAL_GAMEFREAK")
  end
  GameVersion.set("red")
  PaletteFX.setMode("ogred")
  local mod = newGame()
  mod.data.field.intro.studio = { card = "A MOD" }
  local movie = IntroMovie.new(mod)
  eq(movie:sgbPalettes(mod), nil, "a studio text card stays untinted")
end

do
  local movie = IntroMovie.new(newGame())
  local function at(t)
    movie.timer = t
    return movie.logoObp0 and movie:logoObp0()
  end
  eq(at(STAR_START), 0xF9, "rOBP0 starts at $F9")
  eq(at(FLASH_START - 1), 0xF9, "rOBP0 holds $F9 until the flash loop")
  eq(at(FLASH_START), 0x7E, "first rrc rrc gives $7E")
  eq(at(FLASH_START + 9), 0x7E, "$7E holds 10 frames")
  eq(at(FLASH_START + 10), 0x9F, "second rotation gives $9F")
  eq(at(FLASH_START + 20), 0xE7, "third rotation gives $E7")
  eq(at(WAVES_START + 10), 0xE7, "$E7 stays through the small-star waves")
  eq(at(SPLASH_FRAMES - 1), 0xE7, "$E7 stays through the 40-frame tail")
end

do
  local G = PaletteFX.GRAYS
  local _, b = drawSplash("gbc", "red", STAR_START + 5)
  local logo = bakeFor(b, LOGO, "gfobp" .. 0xF9)
  check(logo and sameRamp(logo.colors, ramp(G, 2, 3, 3)),
        "$F9 draws the logo's colour 2 as black on the canvas")
  local text = bakeFor(b, TEXT, "gfobp" .. 0xF9)
  check(text and sameRamp(text.colors, ramp(G, 2, 3, 3)),
        "$F9 draws the text's colour 3 as black on the canvas")
  local star = bakeFor(b, STAR, "gfobp" .. 0xA4)
  check(star and sameRamp(star.colors, ramp(G, 1, 2, 2)),
        "rOBP1 $A4 draws the big star's colour 3 as shade 2")
  _, b = drawSplash("gbc", "red", FLASH_START + 5)
  logo = bakeFor(b, LOGO, "gfobp" .. 0x7E)
  check(logo and sameRamp(logo.colors, ramp(G, 3, 3, 1)),
        "$7E: logo black, text light")
  _, b = drawSplash("gbc", "red", FLASH_START + 15)
  logo = bakeFor(b, LOGO, "gfobp" .. 0x9F)
  check(logo and sameRamp(logo.colors, ramp(G, 3, 1, 2)),
        "$9F: logo light, text dark")
  _, b = drawSplash("og", "red", WAVES_START + 10)
  logo = bakeFor(b, LOGO, "gfobp" .. 0xE7)
  check(logo and sameRamp(logo.colors, ramp(G, 1, 2, 3)),
        "$E7 settles the logo on shade 2 and the text on black")
end

do
  local O = PaletteFX.GBC_OBJ
  local r, b = drawSplash("ogred", "red", STAR_START + 5)
  eq(#r, 3, "ogred red: logo, text and big star are replayed over the zone pass")
  local logo, text, star = r[1] or {}, r[2] or {}, r[3] or {}
  eq(logo.x, 72, "logo replays at x 72")
  eq(logo.y, 56, "logo replays at y 56")
  eq(text.x, 40, "text replays at x 40")
  eq(text.y, 80, "text replays at y 80")
  local lb = bakeFor(b, LOGO, "gfobj" .. 0xF9)
  check(lb and sameRamp(lb.colors, { O[1], O[3], O[4], O[4] }),
        "ogred red: the logo starts black through OBJ0")
  eq(logo.image, SpriteRenderer.obpImage(LOGO, lb and lb.colors or O, "gfobj" .. 0xF9),
     "the replayed logo is the OBJ0 bake")
  local sb = bakeFor(b, STAR, "gfobj1" .. 0xA4)
  check(sb and sameRamp(sb.colors, ramp(PaletteFX.GBC_BG, 1, 2, 2)),
        "ogred red: the big star replays through OBJ1 = the BG ramp")
  eq(star.image, SpriteRenderer.obpImage(STAR, sb and sb.colors or O, "gfobj1" .. 0xA4),
     "the big star replays last so it stays over the logo")

  r, b = drawSplash("ogred", "red", WAVES_START + 10)
  eq(#r, 2, "ogred red: after the star, only logo and text replay")
  lb = bakeFor(b, LOGO, "gfobj" .. 0xE7)
  check(lb and sameRamp(lb.colors, { O[1], O[2], O[3], O[4] }),
        "ogred red: $E7 leaves the logo dark green and the text black")
  _, b = drawSplash("ogred", "red", FLASH_START + 5)
  lb = bakeFor(b, TEXT, "gfobj" .. 0x7E)
  check(lb and sameRamp(lb.colors, { O[1], O[4], O[4], O[2] }),
        "ogred red: the first flash turns the text light green")
end

do
  local OB = PaletteFX.GBC_OBJ_BLUE
  local r, b = drawSplash("ogred", "blue", WAVES_START + 10)
  eq(#r, 2, "ogred blue: logo and text replay")
  local lb = bakeFor(b, LOGO, "gfobj_blue" .. 0xE7)
  check(lb and sameRamp(lb.colors, { OB[1], OB[2], OB[3], OB[4] }),
        "ogred blue: the logo bakes Blue's pink OBJ0 under its own group")
  check(not bakeFor(b, LOGO, "gfobj" .. 0xE7), "ogred blue never bakes into the red group")
end

do
  for _, mode in ipairs({ "gbc", "og", "classic", "redpp" }) do
    local r = drawSplash(mode, "red", WAVES_START + 10)
    eq(#r, 0, mode .. " records no splash OBJ replay")
  end
  local r = drawSplash("ogred", "yellow", WAVES_START + 10)
  eq(#r, 0, "OG YELLOW keeps the CGB zone path")
  r = drawSplash("ogred", "red", 0)
  eq(#r, 0, "nothing replays before the star")
end

SpriteRenderer.obpImage = realObp
GameVersion.set(prevVersion)
PaletteFX.setMode(prevMode)

T.finish()
