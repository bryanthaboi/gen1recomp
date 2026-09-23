-- #2319: the Gen 3 nickname screen drew the mon's 32x32 menu icon at half
-- size, because the mon branch reused the player OW sprite's 16x32 box.
-- pret pokefirered/src/naming_screen.c:1422 CreateMonIcon(species,
-- SpriteCallbackDummy, 56, 40, ...) draws it unscaled, showing frame 0.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local function fakeImage(w, h)
  return {
    w = w, h = h,
    getWidth = function() return w end,
    getHeight = function() return h end,
    getDimensions = function() return w, h end,
  }
end

-- 32x32 icon frames stacked two high.
local ICON_IMG = fakeImage(32, 64)
local QUAD0, QUAD1 = { frame = 0 }, { frame = 1 }

local monIcon
package.loaded["src.core.game3.pokemon"] = {
  icon = function() return monIcon end,
  picSpecies = function(sp) return sp end,
}
package.loaded["src.ui.game3.stack"] = {
  push = function() end, pop = function() end,
  busy = function() return false end, drawOrder = function() return {} end,
}

local Versions = require("src.import.gba.versions")
local Naming = require("src.ui.game3.naming")

eq(Naming.L.monIconW, Versions.MON_ICON_W,
  "mon box width matches the extracted icon width")
eq(Naming.L.monIconH, Versions.MON_ICON_H,
  "mon box height matches the extracted icon height")

-- Normalise both draw signatures into one record:
--   draw(img, quad, x, y, rot, sx, sy, ox, oy)  and  draw(img, x, y, rot, sx, sy, ox, oy)
local draws = {}
local realDraw = love.graphics.draw
love.graphics.draw = function(a, b, c, d, e, f, g, h, i)
  local rec
  if type(b) == "table" then
    rec = { img = a, quad = b, x = c, y = d, rot = e, sx = f, sy = g, ox = h, oy = i }
  else
    rec = { img = a, x = b, y = c, rot = d, sx = e, sy = f, ox = g, oy = h }
  end
  draws[#draws + 1] = rec
end

local function render(opts)
  draws = {}
  Naming.open(opts)
  local ok, err = pcall(Naming.draw)
  Naming.dismiss()
  return draws, ok, err
end

local function drawsOf(ds, img)
  local out = {}
  for _, d in ipairs(ds) do
    if d.img == img then out[#out + 1] = d end
  end
  return out
end

-- The mon icon: 1:1 on the (56, 40) frame centre, static frame 0.
monIcon = { image = ICON_IMG, w = 32, h = 32, sheetH = 64, frames = 2,
            quads = { [0] = QUAD0, [1] = QUAD1 } }
local ds, ok, err = render({ template = "NICKNAME", species = 1, maxLen = 10 })
check(ok, "nickname draw runs headless: " .. tostring(err))
local icon = drawsOf(ds, ICON_IMG)
eq(#icon, 1, "the mon icon is drawn once")
local d = icon[1] or {}
eq(d.quad, QUAD0, "static frame 0, not the 1px-shifted frame 1")
eq(d.x, 56, "icon centre x = 56 (naming_screen.c:1422)")
eq(d.y, 40, "icon centre y = 40 (naming_screen.c:1422)")
eq(d.rot, 0, "no rotation")
eq(d.sx, 1, "32x32 icon drawn 1:1, not the player box's 0.5")
eq(d.sy, 1, "uniform scale")
eq(d.ox, 16, "origin x is the frame centre, so the draw covers the frame")
eq(d.oy, 16, "origin y is the frame centre")

-- Player/rival slot: still the 16x32 OW box.
monIcon = nil
local portrait = fakeImage(64, 64)
local ds3 = render({ template = "PLAYER", icon = portrait })
local p = drawsOf(ds3, portrait)
eq(#p, 1, "the player-slot portrait is drawn once")
eq(p[1] and p[1].x, 56, "player slot keeps its OW centre x")
eq(p[1] and p[1].y, 37, "player slot keeps its OW centre y")
eq(p[1] and p[1].sx, 0.25, "player OW box math is unchanged (16/64)")
eq(p[1] and p[1].sy, 0.25, "player OW box scale is uniform")
eq(p[1] and p[1].ox, 32, "player OW origin is the portrait centre")

-- Guard: the mon icon is never letterboxed below 1:1 again.
for _, dl in ipairs({ ds }) do
  for _, e in ipairs(drawsOf(dl, ICON_IMG)) do
    check((e.sx or 0) >= 1, "mon icon scale is never below 1:1")
  end
end

love.graphics.draw = realDraw
T.finish()
