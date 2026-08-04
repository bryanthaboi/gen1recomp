-- TTF TEXT MODE: a translation registers `font:register("ttf", {})` and the
-- engine renders ordinary characters through a real TTF (the bundled Plain
-- Pixel, assets/fonts/plainpixel/) instead of demanding a hand-drawn glyph
-- page per script.  The contracts under test:
--
--   * with no ttf entry nothing changes: vanilla text stays tile-for-tile
--     identical (the same guarantee Strings makes for an absent catalog);
--   * with it, single characters become TTF glyph codes while multi-char
--     charmap sequences (<PK> macros, the 'd ligatures) and the sub-0x80
--     box chrome keep their tiles, so borders never depend on TTF coverage;
--   * advances come from the font's metrics (5px Latin, 11px double-width
--     kana/CJK in Plain Pixel), which TextBox's pixel-budget paginate and
--     its per-glyph draw pen both honor;
--   * the "ttf" id is a legal font-registry entry and merges to
--     data.font.ttf, rebuilt each merge so disabling the mod disables it.
--
--   luajit tests/engine/ttf_font_mode.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Font = require("src.render.Font")

local BASE = Font.TTF_BASE

-- a charmap with a single-char entry, a multi-byte single char, and a
-- two-char ligature: the three shapes split() has to tell apart
local CHARMAP = {
  { code = 0x80, seq = "A" },
  { code = 0xBA, seq = "\195\169" },   -- é
  { code = 0xD0, seq = "'d" },
}

-- ------------------------------------------------- vanilla stays vanilla

Font.load({ font = { charmap = CHARMAP } })
T.check(not Font.ttfActive(), "no ttf entry means tile mode")
T.eq(Font.encode("A")[1], 0x80, "charmap keeps mapping to tiles")
T.eq(Font.advanceOf(0x80), 8, "and the pen stays 8px monospace")

-- ------------------------------------------------- the ttf takes over

Font.load({ font = { charmap = CHARMAP, ttf = {} } })
T.check(Font.ttfActive(), "an empty ttf table loads the bundled font")

T.eq(Font.encode("A")[1], BASE + 65,
  "a single character routes to the TTF even with a charmap entry")
T.eq(Font.encode("\195\169")[1], BASE + 0xE9,
  "a multi-byte single character does too")
T.eq(Font.encode("'d")[1], 0xD0,
  "a multi-character ligature keeps its tile glyph")
T.eq(#Font.encode("'d"), 1, "and still consumes the whole sequence")
T.eq(Font.encode("\227\129\130")[1], BASE + 0x3042,
  "kana with no charmap entry at all still gets a glyph")

-- metrics come straight from the font object (the stub: half the point
-- size per codepoint, doubled from U+1000 up, mimicking Plain Pixel's
-- single/double width split)
local latin = Font.advanceOf(BASE + 65)
local kana = Font.advanceOf(BASE + 0x3042)
T.check(latin > 0, "a TTF glyph reports a positive advance")
T.eq(kana, latin * 2, "double-width kana advances twice a Latin glyph")
T.eq(Font.width("AB"), latin * 2, "width() sums TTF advances")
T.eq(Font.draw("AB", 0, 0), latin * 2, "draw() returns the same pen travel")

-- border chrome stays on tiles: below every page base here, drawCode must
-- not touch the TTF path (nothing to assert beyond "does not blow up",
-- because with no page image loaded the tile path draws nothing)
Font.drawCode(Font.BORDER.tl, 0, 0)

-- ------------------------------------------------- draw details

-- drawCode prints through the TTF at the configured vertical offset
-- (default bottom-aligns the tall glyph to the 8px cell) and restores
-- whatever font the caller had set
do
  local g = love.graphics
  local prints = {}
  local oldPrint, oldSetFont = g.print, g.setFont
  local marker = { marker = true }
  g.setFont(marker)
  g.print = function(text, x, y) prints[#prints + 1] = { text = text, x = x, y = y } end
  Font.drawCode(BASE + 65, 10, 20)
  g.print = oldPrint
  T.eq(#prints, 1, "a TTF code draws through one love.graphics.print")
  T.eq(prints[1].text, "A", "printing the character it encodes")
  T.eq(prints[1].x, 10, "at the pen x")
  -- stub baseline is px - 2 = 13 at the size-15 default; tile row 7
  T.eq(prints[1].y, 20 + (7 - 13), "baseline-aligned to row 7 of the cell")
  T.eq(g.getFont(), marker, "the caller's font is restored")
  g.setFont = oldSetFont
end

-- bold = true double-prints at a 1px offset and widens the advance
Font.load({ font = { charmap = {}, ttf = { bold = true } } })
do
  local g = love.graphics
  local prints = {}
  local oldPrint = g.print
  g.print = function(_, x) prints[#prints + 1] = x end
  Font.drawCode(BASE + 65, 10, 20)
  g.print = oldPrint
  T.eq(#prints, 2, "bold prints twice")
  T.eq(prints[2], 11, "the second pass sits 1px over")
  T.eq(Font.advanceOf(BASE + 65), latin + 1, "and the advance grows with it")
end
Font.load({ font = { charmap = CHARMAP, ttf = {} } })

-- spacing and yOffset are honored when a mod tunes them
Font.load({ font = { charmap = {}, ttf = { spacing = 2, yOffset = -2 } } })
T.eq(Font.advanceOf(BASE + 65), latin + 2, "spacing pads every advance")
do
  local g = love.graphics
  local y
  local oldPrint = g.print
  g.print = function(_, _, py) y = py end
  Font.drawCode(BASE + 65, 0, 20)
  g.print = oldPrint
  T.eq(y, 18, "yOffset overrides the bottom-align default")
end

-- a bad file degrades to tile mode instead of crashing the boot
Font.load({ font = { charmap = CHARMAP,
                     ttf = { file = "no/such/font.ttf" } } })
T.check(not Font.ttfActive(), "an unloadable ttf falls back to tiles")
T.eq(Font.encode("A")[1], 0x80, "and the charmap works as if never asked")

-- ------------------------------------------------- TextBox draws with it

-- the dialogue box pen must advance per glyph (it measured that way in
-- paginate all along); with the TTF active a line of 5px glyphs would
-- otherwise be drawn spread across the 8px grid
Font.load({ font = { charmap = CHARMAP, ttf = {} } })
do
  local TextBox = require("src.render.TextBox")
  local box = setmetatable({
    boxTx = 0, boxTy = 12, boxTw = 20, boxTh = 6,
    textX = 8, line1Y = 112, line2Y = 128,
    shown = { Font.encode("AB'd") }, blink = 0,
  }, TextBox)
  local pens = {}
  local oldDraw = Font.drawCode
  Font.drawCode = function(code, x, y)
    if code >= BASE or code == 0xD0 then pens[#pens + 1] = { code = code, x = x } end
  end
  box:draw()
  Font.drawCode = oldDraw
  T.eq(#pens, 3, "three glyphs drawn for AB'd")
  T.eq(pens[1].x, 8, "the pen starts at textX")
  T.eq(pens[2].x, 8 + latin, "and moves by the TTF advance, not 8px")
  T.eq(pens[3].x, 8 + latin * 2, "the ligature tile sits after the TTF pair")
end

-- ------------------------------------------------- the registry entry

do
  local Schemas = require("src.mods.Schemas")
  local spec = Schemas.REGISTRIES["font"]
  T.check(select(1, Schemas.check(spec, "font", "ttf", {})) == true,
    'register("ttf", {}) is legal: every field is optional')
  T.check(select(1, Schemas.check(spec, "font", "ttf",
    { file = "mods/x/f.ttf", size = 11, spacing = 1, yOffset = -3 })) == true,
    "so is a fully tuned entry")
  T.check(Schemas.check(spec, "font", "ttf", { image = "x.png", base = 0x100 })
    == nil, "a page payload under the ttf id is refused")
  T.check(Schemas.check(spec, "font", "page", {}) == nil,
    "and a bare page still needs image and base")

  -- write(): the entry lands on data.font.ttf and is rebuilt per merge
  local target = { charmap = {}, pages = {} }
  local registry = { order = { "ttf" },
                     get = function(_, id) return { size = 11 } end }
  spec.write(target, registry)
  T.eq(target.ttf and target.ttf.size, 11, "write() fills data.font.ttf")
  T.check(target.pages.ttf == nil, "and does not mistake it for a page")
  spec.write(target, { order = {}, get = function() return nil end })
  T.check(target.ttf == nil, "a merge without the mod clears it again")
end

-- leave the shared Font module in tile mode for whatever runs next
Font.load({ font = { charmap = {} } })

T.finish("ttf font mode")
