package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local SpriteRenderer = require("src.render.SpriteRenderer")
local PartyMenu = require("src.ui.PartyMenu")

local prevVersion, prevMode = GameVersion.get(), PaletteFX.mode

local MON_PATH = "tests/fixtures/missing_icon_mon_2268.png"
local HELIX_PATH = "tests/fixtures/missing_icon_helix_2268.png"
local MOD_PATH = "tests/fixtures/missing_icon_mod_2268.png"

local game = {
  data = {
    icons = {
      icons = { MON = MON_PATH, HELIX = HELIX_PATH },
      byDex = { [34] = "MON", [138] = "HELIX" },
      bySpecies = { MEWTWO = { image = MOD_PATH, trueColor = true } },
    },
    pokemon = {
      NIDOKING = { dex = 34 }, OMANYTE = { dex = 138 }, MEWTWO = { dex = 150 },
    },
  },
}

local function mon(species)
  return { species = species, hp = 10, stats = { hp = 10 } }
end

local bakes = {}
local realObp = SpriteRenderer.obpImage
SpriteRenderer.obpImage = function(path, colors, group)
  bakes[#bakes + 1] = { path = path, colors = colors, group = group }
  return realObp(path, colors, group)
end

local function same(a, b)
  return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

local function drawIn(species, mode, version)
  GameVersion.set(version or "red")
  PaletteFX.setMode(mode)
  PaletteFX.clearSpriteRedraws()
  PaletteFX.clearTrueColor()
  PaletteFX.setPass("ui")
  local draws = {}
  local realDraw = love.graphics.draw
  love.graphics.draw = function(img) draws[#draws + 1] = img end
  local ok, err = pcall(PartyMenu.drawIcon, game, mon(species), 8, 8, false, 0)
  love.graphics.draw = realDraw
  PaletteFX.setPass(nil)
  check(ok, species .. " drawIcon runs headless" .. (ok and "" or (": " .. tostring(err))))
  local out = {}
  for i, r in ipairs(PaletteFX.uiSpriteRedraws()) do out[i] = r end
  return out, draws
end

do
  GameVersion.set("red")
  local c, g = PaletteFX.ogObjNormal()
  check(same(c and c[2], PaletteFX.GBC_OBJ[1]), "red: OBJ color 1 -> boot OBJ shade 0")
  check(same(c and c[3], PaletteFX.GBC_OBJ[2]), "red: OBJ color 2 -> boot OBJ shade 1 (light green)")
  check(same(c and c[4], PaletteFX.GBC_OBJ[4]), "red: OBJ color 3 -> boot OBJ shade 3")
  GameVersion.set("blue")
  local cb, gb = PaletteFX.ogObjNormal()
  check(same(cb and cb[3], PaletteFX.GBC_OBJ_BLUE[2]), "blue: OBJ color 2 -> pink OBJ shade 1")
  check(g ~= nil and gb ~= nil and g ~= gb, "red and blue bakes use distinct cache groups")

  GameVersion.set("red")
  PaletteFX.setDarkWorld(true)
  PaletteFX.setFadeObp({ [0] = 3, 3, 3, 3 })
  local cd, gd = PaletteFX.ogObjNormal()
  PaletteFX.setDarkWorld(false)
  PaletteFX.setFadeObp(nil)
  eq(cd, c, "dark / fade OBP state never reaches the GBPalNormal ramp")
  eq(gd, g, "dark / fade OBP state never changes the cache group")
end

do
  local redraws, draws = drawIn("NIDOKING", "ogred", "red")
  eq(#redraws, 2, "ogred red: mirrored icon records both OAM halves")
  local a, b = redraws[1] or {}, redraws[2] or {}
  eq(a.x, 8, "left half replays at x")
  eq(a.sx, 1, "left half is unflipped")
  eq(b.x, 24, "flipped half replays about the block's right edge")
  eq(b.sx, -1, "flipped half carries sx = -1")
  check(a.quad ~= nil and a.quad == b.quad, "both halves replay the same 8x16 quad")
  check(a.image ~= nil and a.image == draws[1] and a.image == draws[2],
        "the replayed image is the one drawn into the canvas")
  local bake = bakes[#bakes] or {}
  eq(bake.path, MON_PATH, "ogred red bakes the icon art")
  local c, g = PaletteFX.ogObjNormal()
  eq(bake.colors, c, "ogred red bakes the GBPalNormal OBJ ramp")
  eq(bake.group, g, "ogred red bakes under its own cache group")
end

do
  local before = #bakes
  local redraws = drawIn("NIDOKING", "ogred", "blue")
  eq(#redraws, 2, "ogred blue: mirrored icon records both OAM halves")
  local bake = bakes[before + 1] or {}
  check(bake.colors and same(bake.colors[3], PaletteFX.GBC_OBJ_BLUE[2]),
        "ogred blue bakes Blue's pink OBJ ramp")
end

do
  local redraws = drawIn("OMANYTE", "ogred", "red")
  eq(#redraws, 1, "ogred: single-frame HELIX records one redraw")
  local r = redraws[1] or {}
  eq(r.quad, nil, "HELIX replays the whole image")
  eq(r.sx, 1, "HELIX is unflipped")
end

do
  local before = #bakes
  local redraws = drawIn("NIDOKING", "gbc", "red")
  eq(#redraws, 0, "SGB keeps the zone-colored icon with no OBJ replay")
  eq(#bakes, before, "SGB never bakes the boot OBJ ramp")
  redraws = drawIn("NIDOKING", "redpp", "red")
  eq(#redraws, 0, "RED++ keeps the zone-colored icon with no OBJ replay")
  redraws = drawIn("NIDOKING", "ogred", "yellow")
  eq(#redraws, 0, "OG YELLOW keeps the CGB zone path")
end

do
  local before = #bakes
  local redraws = drawIn("MEWTWO", "ogred", "red")
  eq(#redraws, 0, "trueColor mod art records no OBJ replay under ogred")
  eq(#bakes, before, "trueColor mod art is never OBP-baked")
  eq(#PaletteFX.trueColorRects("ui"), 1, "trueColor mod art keeps its unshaded rect")
end

do
  PaletteFX.clearSpriteRedraws()
  PaletteFX.clearTrueColor()
  PaletteFX.setPass("ui")
  PaletteFX.setMarkOffset(72)
  local img = {}
  PaletteFX.markUiSpriteRedraw(img, nil, 4, 5)
  PaletteFX.markUiSpriteRedraw(img, nil, 0, 32,
    { sx = 160, sy = 80, clip = { 0, 32, 160, 80 }, color = { 1, 1, 1, 0.5 } })
  PaletteFX.setMarkOffset(0)
  PaletteFX.setPass(nil)
  local r = PaletteFX.uiSpriteRedraws()
  local p, q = r[1] or {}, r[2] or {}
  eq(p.x, 76, "plain mark shifts by the mark offset")
  eq(p.sx, 1, "plain mark defaults sx to 1")
  eq(p.sy, 1, "plain mark defaults sy to 1")
  eq(p.clip, nil, "plain mark has no clip")
  eq(p.color, nil, "plain mark has no tint")
  eq(q.sx, 160, "opts.sx is stored")
  eq(q.sy, 80, "opts.sy is stored")
  eq(q.clip and q.clip[1], 72, "opts.clip shifts by the mark offset")
  eq(q.clip and q.clip[4], 80, "opts.clip keeps its size")
  eq(q.color and q.color[4], 0.5, "opts.color is stored")
  PaletteFX.clearSpriteRedraws()
end

SpriteRenderer.obpImage = realObp
GameVersion.set(prevVersion)
PaletteFX.setMode(prevMode)

T.finish()
