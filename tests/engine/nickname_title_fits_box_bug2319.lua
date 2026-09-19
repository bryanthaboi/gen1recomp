-- #2319 (second report): the nickname screen's title ran past the right edge of
-- the text box. The catch flow hand-wrote "YOUR POKEMON'S NICKNAME?" (141px in a
-- 127px window), where pret composes gSpeciesNames[mon] + gText_PkmnsNickname:
--   pokefirered/src/naming_screen.c:1712 DrawMonTextEntryBox
--   pokefirered/src/strings.c:772        gText_PkmnsNickname = "'s nickname?"
-- sWindowTemplates[WIN_TEXT_ENTRY_BOX] = {tilemapLeft 9, width 16} → screen
-- x 72..200, text printed at (1,1) → x 73, so the budget is 127px.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- --- exact GBA advance widths, from the extracted FRLG latin font ------------
local function loadTable(path, pattern)
  local f = io.open(path, "r")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  local t = {}
  for a, b in src:gmatch(pattern) do t[tonumber(a)] = tonumber(b) end
  return t
end

local widths = loadTable("src/import/gba/chrome/fonts/latin_widths.lua", "%[(%d+)%]%s*=%s*(%d+)")
check(widths ~= nil and next(widths) ~= nil, "latin glyph widths are loadable")

-- TextIR.CHARMAP: glyph id -> character, inverted to character -> glyph id.
local charmap = require("src.core.game3.scripting.text_ir").CHARMAP
local glyphOf = {}
for gid, ch in pairs(charmap) do
  if type(gid) == "number" and type(ch) == "string" and #ch == 1 then
    glyphOf[ch] = gid
  end
end
check(next(glyphOf) ~= nil, "TextIR.CHARMAP is invertible to character -> glyph id")

local function px(s)
  local total = 0
  for i = 1, #s do
    local gid = glyphOf[s:sub(i, i)]
    if gid then total = total + (widths[gid] or 0) end
  end
  return total
end

local LEFT, BUDGET = 73, 127 -- text-entry window starts at x=73, 127px of room
local function endsAt(s) return LEFT + px(s) end

-- --- the reported string genuinely overflowed -------------------------------
local reported = "YOUR POKEMON'S NICKNAME?"
check(px(reported) > BUDGET,
  ("the old hardcoded title (%dpx) really did overflow the %dpx window"):format(px(reported), BUDGET))
check(endsAt(reported) > 200,
  "the old title ran past the window's right edge (x=200)")

-- --- Naming.monTitle mirrors pret -------------------------------------------
local Naming = require("src.ui.game3.naming")
eq(type(Naming.monTitle), "function", "Naming.monTitle exists")
eq(Naming.monTitle("CHARMANDER"), "CHARMANDER's nickname?",
  "mon title is gSpeciesNames[mon] + gText_PkmnsNickname")
eq(Naming.monTitle("BULBASAUR"), "BULBASAUR's nickname?", "title tracks the species")
check(Naming.monTitle("CHARMANDER") ~= Naming.monTitle("SQUIRTLE"),
  "title is species-derived, not a fixed caption")
eq(Naming.monTitle(nil), "POKéMON's nickname?", "a missing name falls back safely")

-- --- every real species title fits the window -------------------------------
-- Longest real species names (both 10 characters) plus the widest 10-character
-- name the font can produce: a strict upper bound over all caps names.
for _, name in ipairs({ "CHARMANDER", "FORRETRESS", "MASQUERAIN", "BUTTERFREE" }) do
  local title = Naming.monTitle(name)
  check(endsAt(title) <= 200,
    ("%q ends at x=%d, inside the box (<=200)"):format(title, endsAt(title)))
end

local widest = {}
for ch in pairs(glyphOf) do
  if ch:match("^[A-Z]$") then widest[#widest + 1] = ch end
end
table.sort(widest, function(a, b)
  local wa, wb = widths[glyphOf[a]] or 0, widths[glyphOf[b]] or 0
  if wa == wb then return a < b end
  return wa > wb
end)
local worstName = table.concat({ widest[1], widest[2], widest[3], widest[4], widest[5],
                                 widest[6], widest[7], widest[8], widest[9], widest[10] })
local worstTitle = Naming.monTitle(worstName)
check(endsAt(worstTitle) <= 200,
  ("worst-case 10-char name %q ends at x=%d, still inside the box"):format(worstTitle, endsAt(worstTitle)))

-- --- the screen clamps the title to the window ------------------------------
-- pret blits glyphs into the window buffer (CopyGlyphToWindow), which clips at
-- the window edge; the port must pass that window as maxWidth rather than the
-- generic 240 default, which would let text run over the frame art.
eq(Naming.L.titleMaxW, BUDGET, "L.titleMaxW is the text-entry window's usable width")
eq(Naming.L.titleX, LEFT, "the title still starts at the window's left edge")

local FrlgFont = require("src.ui.game3.frlg_font")
local realDraw = FrlgFont.draw
local seen = {}
FrlgFont.draw = function(text, x, y, opts)
  seen[#seen + 1] = { text = text, x = x, y = y, maxWidth = opts and opts.maxWidth }
  return 0
end

package.loaded["src.core.game3.pokemon"] = {
  icon = function() return nil end,
  frontPic = function() return nil end,
}
package.loaded["src.ui.game3.stack"] = {
  push = function() end, pop = function() end,
  busy = function() return false end, drawOrder = function() return {} end,
}

local title = Naming.monTitle("BUTTERFREE")
Naming.open({ template = "CAUGHT_MON", species = 12, maxLen = 10, title = title })
local ok, err = pcall(Naming.draw)
Naming.dismiss()
FrlgFont.draw = realDraw
check(ok, "nickname draw runs headless: " .. tostring(err))

local drawn
for _, s in ipairs(seen) do
  if s.text == title then drawn = s end
end
check(drawn ~= nil, "the title is drawn as its own run")
eq(drawn and drawn.x, LEFT, "title drawn at the window's left edge")
eq(drawn and drawn.y, 33, "title drawn at the template's y")
eq(drawn and drawn.maxWidth, BUDGET,
  "title is clamped to the window, not the 240px default that overran the frame")

T.finish()
