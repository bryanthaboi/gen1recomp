-- #1558: menu_gfx.stats -> $31..$41 quads (engine/gfx/load_font.asm:90-95);
-- PAGE_PALETTES is gfx/stats/pages.pal (cgb_layouts.asm:199-212)
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")

-- gfx/stats/pages.pal, RGB 5-bit rows in ROM order: pink, green, blue
local ROM_PALS = {
  { { 31, 31, 31 }, { 31, 19, 31 }, { 31, 15, 31 }, { 0, 0, 0 } },
  { { 31, 31, 31 }, { 21, 31, 14 }, { 17, 31, 0 }, { 0, 0, 0 } },
  { { 31, 31, 31 }, { 17, 31, 31 }, { 17, 31, 31 }, { 0, 0, 0 } },
}
local function up(v) return math.floor(v * 255 / 31 + 0.5) end
for p = 1, 3 do
  for c = 1, 4 do
    for ch = 1, 3 do
      T.eq(SummaryMenu.PAGE_PALETTES[p][c][ch], up(ROM_PALS[p][c][ch]),
        ("pages.pal palette %d color %d channel %d"):format(p, c, ch))
    end
  end
end

-- gfx/stats/stats.pal, the colour LoadStatsScreenPals drops into colour 0 of
-- BG palettes 0 and 2 (engine/gfx/color.asm:386-390)
local ROM_TINTS = { { 31, 19, 31 }, { 21, 31, 14 }, { 17, 31, 31 } }
for p = 1, 3 do
  for ch = 1, 3 do
    T.eq(SummaryMenu.PAGE_TINTS[p][ch], up(ROM_TINTS[p][ch]),
      ("stats.pal tint %d channel %d"):format(p, ch))
  end
  local page = setmetatable({ page = p }, { __index = SummaryMenu })
  local lower = page:lowerColors()
  T.eq(lower[1][1], SummaryMenu.PAGE_TINTS[p][1],
    ("lower half palette %d takes the page tint as colour 0"):format(p))
  T.eq(lower[4][1], 0, ("lower half palette %d keeps black ink"):format(p))
end

-- the quads: 17 tiles from $31, one 8x8 cell each off the 136x8 sheet
love.graphics = love.graphics or {}
local realNewQuad = love.graphics.newQuad
love.graphics.newQuad = function(x, y, w, h)
  return { x = x, y = y, w = w, h = h }
end
local menu = setmetatable({
  menuGfx = { stats = { sheet = "stats", tiles = 17, firstTile = 0x31 } },
  picImage = function()
    return { getDimensions = function() return 136, 8 end }
  end,
}, { __index = SummaryMenu })
local sheet = menu:statsTiles()
if T.check(sheet ~= nil, "menu_gfx.stats builds the tile sheet") then
  for id = 0x31, 0x41 do
    local q = sheet.quads[id]
    T.check(q ~= nil and q.x == (id - 0x31) * 8 and q.w == 8 and q.h == 8,
      ("tile $%02x maps to sheet cell %d"):format(id, id - 0x31))
  end
  T.check(sheet.quads[0x42] == nil, "and exactly 17 tiles, no more")
end

-- a cache built before menu_gfx.stats existed keeps the hand-drawn fallback
local old = setmetatable({ menuGfx = {} }, { __index = SummaryMenu })
T.check(old:statsTiles() == nil, "no menu_gfx.stats falls back, not crashes")
love.graphics.newQuad = realNewQuad

T.finish("gen2 stats tiles and page palettes (#1558, #1693)")
