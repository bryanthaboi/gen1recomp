package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local SpriteRenderer = require("src.render.SpriteRenderer")
local IntroMovie = require(os.getenv("INTRO_MOVIE_MODULE") or "src.ui.IntroMovie")

local prevVersion, prevMode = GameVersion.get(), PaletteFX.mode

local function frames(prefix)
  local t = {}
  for i = 1, 3 do
    t["frame" .. i] = { path = "tests/fixtures/missing_" .. prefix .. i .. "_2264.png" }
  end
  return t
end

local game = {
  data = { field = { intro = { nidorino = frames("nido"), gengar = frames("gengar") } } },
  stack = { pop = function() end },
}

local bakes = {}
local realObp = SpriteRenderer.obpImage
SpriteRenderer.obpImage = function(path, colors, group)
  bakes[#bakes + 1] = { path = path, colors = colors, group = group }
  return realObp(path, colors, group)
end

local function drawFight(mode, version, setup)
  GameVersion.set(version)
  PaletteFX.setMode(mode)
  local movie = IntroMovie.new(game)
  movie.phase = 3
  movie.nidoX, movie.nidoY = 72, 72
  movie.gengarX, movie.gengarY = 24, 56
  if setup then setup(movie) end
  local before = #bakes
  PaletteFX.clearSpriteRedraws()
  PaletteFX.setPass("ui")
  local ok, err = pcall(movie.draw, movie)
  PaletteFX.setPass(nil)
  check(ok, mode .. "/" .. version .. " draw runs headless" .. (ok and "" or (": " .. tostring(err))))
  local out, newBakes = {}, {}
  for i, r in ipairs(PaletteFX.uiSpriteRedraws()) do out[i] = r end
  for i = before + 1, #bakes do newBakes[#newBakes + 1] = bakes[i] end
  PaletteFX.clearSpriteRedraws()
  return out, newBakes, movie
end

local function sameClip(c)
  return c and c[1] == 0 and c[2] == 32 and c[3] == 160 and c[4] == 80
end

do
  local r, b, movie = drawFight("ogred", "red")
  eq(#r, 2, "ogred red: Nidorino and the Gengar restack are replayed")
  local nido, gengar = r[1] or {}, r[2] or {}
  eq(b[1] and b[1].path, movie.nidoPaths[1], "Nidorino bakes its current frame")
  eq(b[1] and b[1].colors, PaletteFX.GBC_OBJ, "red Nidorino bakes the boot-ROM OBJ ramp")
  eq(b[1] and b[1].group, "gbcobj", "red Nidorino bakes under the red OBJ group")
  eq(nido.image, SpriteRenderer.obpImage(movie.nidoPaths[1], PaletteFX.GBC_OBJ, "gbcobj"),
     "the replayed Nidorino image is the OBJ bake")
  eq(nido.x, 72, "Nidorino replays at nidoX")
  eq(nido.y, 72, "Nidorino replays at nidoY")
  check(sameClip(nido.clip), "Nidorino replay is clipped to the playfield under the bars")
  eq(b[2] and b[2].path, movie.gengarPaths[1], "Gengar restack bakes its current pose")
  eq(b[2] and b[2].colors, PaletteFX.GBC_BG, "red Gengar restack bakes the boot-ROM BG ramp")
  eq(gengar.x, 24, "Gengar replays at gengarX")
  eq(gengar.y, 56, "Gengar replays at gengarY")
  check(sameClip(gengar.clip), "Gengar restack is clipped to the playfield")
end

do
  local r, b = drawFight("ogred", "blue")
  eq(#r, 2, "ogred blue: Jigglypuff and the Gengar restack are replayed")
  eq(b[1] and b[1].colors, PaletteFX.GBC_OBJ_BLUE, "blue Jigglypuff bakes Blue's pink OBJ ramp")
  eq(b[1] and b[1].group, "gbcobj_blue", "blue bake uses its own cache group")
  eq(b[2] and b[2].colors, PaletteFX.GBC_BG_BLUE, "blue Gengar restack bakes Blue's BG ramp")
  check(b[2] and b[2].group ~= "ogbg", "blue Gengar bake never shares the red cache group")
end

do
  local r, b, movie = drawFight("ogred", "red", function(m)
    m.nidoFrame, m.gengarPose = 3, 2
  end)
  eq(b[1] and b[1].path, movie.nidoPaths[3], "lunge frame bakes frame 3")
  eq(b[2] and b[2].path, movie.gengarPaths[2], "raised pose bakes pose 2")
  eq(#r, 2, "no fade entry while fade is 0")
end

do
  local r = drawFight("ogred", "red", function(m) m.fade = 0.5 end)
  eq(#r, 3, "GBFadeOutToWhite adds a white wash over the replayed layer")
  local w = r[3] or {}
  eq(w.color and w.color[4], 0.5, "the wash carries the fade alpha")
  eq(w.sx, 160, "the wash spans the playfield width")
  eq(w.sy, 80, "the wash spans the playfield height")
  eq(w.x, 0, "the wash starts at the playfield left")
  eq(w.y, 32, "the wash starts under the top bar")
  check(sameClip(w.clip), "the wash is clipped to the playfield")
end

do
  PaletteFX.setDarkWorld(true)
  PaletteFX.setFadeObp({ [0] = 3, 3, 3, 3 })
  local _, b = drawFight("ogred", "red")
  PaletteFX.setDarkWorld(false)
  PaletteFX.setFadeObp(nil)
  eq(b[1] and b[1].colors, PaletteFX.GBC_OBJ, "stale dark / fade OBP state never reaches the identity rOBP0 bake")
end

do
  local r, b = drawFight("gbc", "red")
  eq(#r, 0, "SGB keeps the PURPLEMON zone Nidorino with no OBJ replay")
  eq(#b, 0, "SGB never bakes the boot-ROM ramps")
  r = drawFight("gbc", "blue")
  eq(#r, 0, "SGB blue keeps the zone Jigglypuff")
  for _, mode in ipairs({ "redpp", "og", "classic" }) do
    r = drawFight(mode, "red")
    eq(#r, 0, mode .. " records no intro OBJ replay")
  end
  r = drawFight("ogred", "yellow")
  eq(#r, 0, "OG YELLOW keeps the CGB zone path")
end

do
  local r = drawFight("ogred", "red", function(m) m.phase = 2 end)
  eq(#r, 0, "the splash never records the fight replay")
  r = drawFight("ogred", "red", function(m) m.phase = 4 end)
  eq(#r, 0, "the post-fade white hold records nothing")
end

SpriteRenderer.obpImage = realObp
GameVersion.set(prevVersion)
PaletteFX.setMode(prevMode)

T.finish()
