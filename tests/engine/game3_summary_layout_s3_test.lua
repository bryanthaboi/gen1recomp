#!/usr/bin/env luajit
-- pokefirered/src/pokemon_summary_screen.c:1615

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_map_sections").install()

local T = require("tests.harness")
local check, eq = T.check, T.eq
require("tests.game3_cache").stubSpeciesNames()

require("src.core.GameVersion").set("firered")

package.loaded["src.core.game3.audio"] = {
  playSe = function() end, playCry = function() end,
  playSong = function() end, stopAll = function() end,
}
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.newImage = function() return nil end
gfx.getWidth = function() return 240 end
gfx.getHeight = function() return 160 end
_G.love = { graphics = gfx, timer = { getTime = function() return 0 end } }

local FrlgFont = require("src.ui.game3.frlg_font")
local Pokemon = require("src.core.game3.pokemon")
local SummaryMenu = require("src.ui.game3.summary_menu")
local SummaryChrome = require("src.ui.game3.summary_chrome")

local calls
local function reset_calls() calls = {} end
reset_calls()
for _, name in ipairs({ "drawBg3", "drawProgress", "drawLayer", "drawPageBg", "drawShinyStar", "drawStatusIcon",
                        "drawTypeBadge", "drawHpBar", "drawExpBar", "drawPokerus", "drawMoveSelectionCursor",
                        "drawMarkings" }) do
  SummaryChrome[name] = function(...)
    calls[#calls + 1] = { name = name, args = { ... } }
  end
end
local MANIFEST = nil
SummaryChrome.manifest = function() return MANIFEST end
local SESSION = nil
package.loaded["src.core.game3.runtime"] = { getSession = function() return SESSION end }
local SummaryData = require("src.core.game3.summary_data")
SummaryData.moveDescription = function() return "" end
SummaryData.abilityDescription = function() return "" end
local realMemo = SummaryData.formatTrainerMemo
SummaryData.formatTrainerMemo = function() return {} end
SummaryData.expProgress = function() return { totalExp = 0, expNeeded = 0, progressPercent = 0 } end
Pokemon.abilityName = function() return "STATIC" end
Pokemon.abilityId = function() return 9 end
Pokemon.monFrontPic = function() calls[#calls + 1] = { name = "pic", args = {} } return nil end
Pokemon.monIcon = function() calls[#calls + 1] = { name = "icon", args = {} } return nil end
local texts = {}
local NORMAL = FrlgFont.COLOR.NORMAL
FrlgFont.draw = function(text, x, y, opts)
  texts[#texts + 1] = { text = tostring(text), x = x, y = y, colors = opts and opts.colors }
end

local function find(name, pred)
  for _, c in ipairs(calls) do
    if c.name == name and (not pred or pred(c.args)) then return c end
  end
  return nil
end
local function text_at(str)
  for _, t in ipairs(texts) do if t.text == str then return t end end
  return nil
end

local function mon()
  return {
    species = 25, level = 20, hp = 20, maxHp = 47, status = "PSN", isShiny = true, markings = 5,
    attack = 29, defense = 7, spAtk = 125, spDef = 22, speed = 45,
    moves = { "THUNDER WAVE", "GROWL" }, pp = { 4, 40 }, maxPp = { 20, 40 },
    otName = "RED", otId = 1, personality = 1,
  }
end

local pressed
local input = { wasPressed = function(_, b) return pressed == b end }
local function press(b)
  pressed = b
  SummaryMenu.handleInput(input)
  pressed = nil
end
local function frames(n) for _ = 1, n do SummaryMenu.update(1 / 60) end end
local function settle()
  for _ = 1, 60 do
    if not SummaryMenu._slide.active then break end
    frames(1)
  end
  SummaryMenu.handleInput(input)
end
local function draw()
  reset_calls()
  texts = {}
  SummaryMenu.draw()
end

print("[test] 1. pret's sprite table: the picture pane stays on KNOWN MOVES")
check(type(SummaryMenu.leftPaneSprites) == "function", "SummaryMenu.leftPaneSprites exists")
if type(SummaryMenu.leftPaneSprites) == "function" then
  local moves = SummaryMenu.leftPaneSprites(SummaryMenu.PAGE_MOVES, nil)
  check(moves.pic and moves.ball and moves.markings and not moves.icon, "KNOWN MOVES keeps pic, ball, markings; no icon")
  eq(moves.status and moves.status.x, 0, "KNOWN MOVES status x is the INFO top-left")
  eq(moves.status and moves.status.y, 34, "KNOWN MOVES status y is the INFO top-left")
  eq(moves.shiny and moves.shiny.x, 102, "KNOWN MOVES star x")
  local detail = SummaryMenu.leftPaneSprites(SummaryMenu.PAGE_MOVES_INFO, nil)
  check(detail.icon and not detail.pic and not detail.ball and not detail.markings, "move detail swaps the pic for the icon")
  eq(detail.icon and detail.icon.y, 16, "move detail icon top-left y")
  check(detail.status == nil, "move detail from A hides the status icon")
  local learn = SummaryMenu.leftPaneSprites(SummaryMenu.PAGE_MOVES_INFO, "select_move")
  eq(learn.status and learn.status.y, 41, "learn/forget screen shows status at y 41")
  eq(detail.shiny and detail.shiny.x, 4, "move detail star x")
end

print("[test] 2. PP colours")
check(type(SummaryMenu.ppColorIndex) == "function", "SummaryMenu.ppColorIndex exists")
if type(SummaryMenu.ppColorIndex) == "function" then
  eq(SummaryMenu.ppColorIndex(20, 20, true), 0, "full PP is normal")
  eq(SummaryMenu.ppColorIndex(10, 20, true), 1, "half PP is yellow")
  eq(SummaryMenu.ppColorIndex(5, 20, true), 2, "quarter PP is orange")
  eq(SummaryMenu.ppColorIndex(0, 20, true), 3, "no PP is red")
  eq(SummaryMenu.ppColorIndex(2, 3, true), 2, "2/3 is orange")
  eq(SummaryMenu.ppColorIndex(1, 2, true), 1, "1/2 is yellow")
  eq(SummaryMenu.ppColorIndex(0, 0, false), 0, "empty slot is normal")
end

print("[test] 3. move detail cursor")
check(type(SummaryMenu.detailCursorStep) == "function", "SummaryMenu.detailCursorStep exists")
if type(SummaryMenu.detailCursorStep) == "function" then
  local two = { {}, {} }
  eq(SummaryMenu.detailCursorStep(two, 1, 1, false), 4, "down past the last move lands on CANCEL")
  eq(SummaryMenu.detailCursorStep(two, 4, 1, false), 0, "down from CANCEL wraps to the first move")
  eq(SummaryMenu.detailCursorStep(two, 0, -1, false), 4, "up from the first move lands on CANCEL")
  eq(SummaryMenu.detailCursorStep(two, 0, -1, true), 1, "swapping never lands on CANCEL")
  eq(SummaryMenu.detailCursorStep(two, 1, 1, true), 0, "swapping wraps down to the first move")
end

print("[test] 4. page flips, A on INFO, slides")
local party = { mon() }
local closed = false
SummaryMenu.openMenu(party, 1, { onClose = function() closed = true end })
eq(SummaryMenu._page, SummaryMenu.PAGE_INFO, "opens on INFO")
press("left")
eq(SummaryMenu._page, SummaryMenu.PAGE_INFO, "left on INFO does not wrap to MOVES")
press("right")
eq(SummaryMenu._page, SummaryMenu.PAGE_SKILLS, "right flips to SKILLS")
check(SummaryMenu._slide.active, "the flip slides")
frames(14)
check(SummaryMenu._slide.active, "the flip task still runs 14 frames after the press")
frames(1)
check(not SummaryMenu._slide.active, "the flip task ends on frame 15 (hop + Task_PokeSum_FlipPages)")
press("right")
settle()
eq(SummaryMenu._page, SummaryMenu.PAGE_MOVES, "right flips to KNOWN MOVES")
press("right")
eq(SummaryMenu._page, SummaryMenu.PAGE_MOVES, "right on KNOWN MOVES does not wrap to INFO")

draw()
check(find("pic") ~= nil and find("icon") == nil, "KNOWN MOVES draws the front pic, not the icon")
check(find("drawBg3", function(a) return a[1] == "info" end) ~= nil, "KNOWN MOVES keeps the picture-frame bg3")
check(find("drawStatusIcon", function(a) return a[1] == 0 and a[2] == 34 end) ~= nil, "KNOWN MOVES status at 0,34")
check(find("drawShinyStar", function(a) return a[1] == 102 and a[2] == 36 end) ~= nil, "KNOWN MOVES shiny star at 102,36")
check(find("drawMarkings", function(a) return a[1] == 5 end) ~= nil, "KNOWN MOVES draws the markings")
local pp = text_at("gText_PokeSum_PP")
check(pp ~= nil and pp.x == 196, "the PP glyph prints at x 196")
local cur = text_at("4")
eq(cur and cur.x, 212, "a one-digit current PP right-aligns to end at 217")
local hy = text_at("gText_PokeSum_OneHyphen")
eq(hy and hy.x, 163, "an empty slot prints one hyphen at the name column")
local two = text_at("gText_PokeSum_TwoHyphens")
eq(two and two.x, 205, "an empty slot's PP prints two hyphens at x 205")

press("a")
eq(SummaryMenu._page, SummaryMenu.PAGE_MOVES_INFO, "A opens move detail")
check(SummaryMenu._slide.active and SummaryMenu._slide.kind == "detail", "move detail slides in")
settle()
draw()
check(find("icon") ~= nil and find("pic") == nil, "move detail draws the icon")
check(find("drawStatusIcon") == nil, "move detail hides the status icon")
check(find("drawLayer", function(a) return a[1] == "moves" end) ~= nil, "move detail keeps the move list panel")
check(find("drawTypeBadge", function(a) return a[2] == 48 and a[3] == 35 end) ~= nil, "move detail shows the mon's type")
press("b")
settle()
eq(SummaryMenu._page, SummaryMenu.PAGE_MOVES, "B returns to KNOWN MOVES")

press("left") settle()
press("left") settle()
eq(SummaryMenu._page, SummaryMenu.PAGE_INFO, "back on INFO")
draw()
check(find("drawShinyStar", function(a) return a[1] == 102 end) ~= nil, "INFO star at 102,36")
press("a")
check(closed and not SummaryMenu.isOpen(), "A on INFO closes the summary")

print("[test] 5. SKILLS numbers right-align, one colour")
SummaryMenu.openMenu({ mon() }, 1, { page = SummaryMenu.PAGE_SKILLS })
draw()
local hp = text_at("20/47")
eq(hp and hp.x, 174 + 63 - 5 * 6, "HP right-aligns in 63 px")
local spa = text_at("125")
eq(spa and spa.x, 210 + 27 - 3 * 6, "a stat right-aligns in 27 px")
local atk = text_at("29")
check(atk and atk.colors == NORMAL and spa and spa.colors == NORMAL, "every stat prints in the one skills colour")
local def = text_at("7")
eq(def and def.x, 210 + 27 - 6, "a one-digit stat right-aligns too")
SummaryMenu.close()

local function text_xy(x, y)
  for _, t in ipairs(texts) do if t.x == x and t.y == y then return t end end
  return nil
end
local function layer_at(name, x)
  return find("drawLayer", function(a) return a[1] == name and a[2] == x end) ~= nil
end

print("[test] 6. flips wait for the cart's task frames before sliding")
SummaryMenu.openMenu({ mon() }, 1, {})
press("right")
frames(6) draw()
check(layer_at("info", 0), "six frames after the press INFO has not moved")
frames(1) draw()
check(layer_at("info", 60), "frame 7 slides INFO 60 px")
frames(3) draw()
check(layer_at("info", 240), "frame 10 has INFO fully off")
check(text_at("20/47") == nil, "the SKILLS right pane waits for ShowBg(0)")
frames(4) draw()
check(text_at("20/47") ~= nil, "frame 14 shows the SKILLS right pane")
settle()
press("right") settle()
press("a")
frames(8) draw()
check(find("drawLayer", function(a) return a[1] == "moves_info" end) == nil, "eight frames after A the detail layer has not entered")
frames(1) draw()
check(layer_at("moves_info", 180), "frame 9 slides the detail layer in 60 px")
settle()
press("b")
frames(7) draw()
check(layer_at("moves_info", 0), "seven frames after B the detail layer has not left")
frames(1) draw()
check(layer_at("moves_info", 60), "frame 8 slides the detail layer out 60 px")
settle()
SummaryMenu.close()

print("[test] 7. header and name strip ride the page layers")
SummaryMenu.openMenu({ mon() }, 1, { page = SummaryMenu.PAGE_MOVES })
press("left")
frames(5) draw()
check(text_xy(4, 1) and text_xy(4, 1).text == "gText_PokeSum_PageName_KnownMoves", "before case 4 the old title stays")
frames(3) draw()
local title = text_xy(124, 1)
check(title and title.text == "gText_PokeSum_PageName_PokemonSkills", "a left flip carries the new title on the incoming layer")
check(text_xy(160, 18) ~= nil, "the name strip rides the incoming layer too")
check(text_xy(40, 18) == nil, "nothing is left at the static name position")
settle()
press("right")
frames(8) draw()
check(text_xy(4, 1) and text_xy(4, 1).text == "gText_PokeSum_PageName_KnownMoves", "a right flip prints the new title on the layer underneath")
check(layer_at("skills", 120), "while SKILLS slides off")
settle()
press("a")
frames(10) draw()
check(text_xy(40, 18) == nil and text_xy(4, 18) == nil, "the name strip is blank while move detail slides in")
title = text_xy(124, 1)
check(title and title.text == "gText_PokeSum_PageName_KnownMoves", "the detail title rides the sliding layer")
frames(6) draw()
check(text_xy(40, 18) ~= nil, "FromInfo case 11 reprints the name strip")
settle()
press("b")
frames(9) draw()
check(text_xy(40, 18) == nil, "the name strip is blank while move detail slides out")
check(text_xy(4, 1) ~= nil, "the KNOWN MOVES title stays put on the back-out")
frames(4) draw()
check(text_xy(40, 18) ~= nil and text_xy(4, 18) ~= nil, "back-out case 9 reprints the name strip with the level")
settle()
SummaryMenu.close()

print("[test] 8. a same-direction press during a flip is queued")
SummaryMenu.openMenu({ mon() }, 1, {})
press("right") frames(3)
press("right")
eq(SummaryMenu._slide.queued, 1, "lastPageFlipDirection holds the second right")
settle()
eq(SummaryMenu._page, SummaryMenu.PAGE_MOVES, "right-right from INFO lands on KNOWN MOVES")
settle()
press("left") frames(3)
press("right")
eq(SummaryMenu._slide.queued, nil, "an opposite press during a flip is dropped")
settle()
eq(SummaryMenu._page, SummaryMenu.PAGE_SKILLS, "the dropped press does not flip back")
SummaryMenu.close()

print("[test] 9. L/R flip pages only in the LR button mode")
SESSION = { options = { buttonMode = 1 } }
SummaryMenu.openMenu({ mon() }, 1, {})
press("r")
eq(SummaryMenu._page, SummaryMenu.PAGE_SKILLS, "R flips right in LR mode")
settle()
press("l")
eq(SummaryMenu._page, SummaryMenu.PAGE_INFO, "L flips left in LR mode")
settle()
SummaryMenu.close()
for _, mode in ipairs({ 0, 2 }) do
  SESSION = { options = { buttonMode = mode } }
  SummaryMenu.openMenu({ mon() }, 1, {})
  press("r")
  eq(SummaryMenu._page, SummaryMenu.PAGE_INFO, "R does not flip in button mode " .. mode)
  check(not SummaryMenu._slide.active, "no flip starts in button mode " .. mode)
  SummaryMenu.close()
end
SESSION = nil

print("[test] 10. the move cursor survives detail and page flips")
SummaryMenu.openMenu({ mon() }, 1, { page = SummaryMenu.PAGE_MOVES })
press("a") settle()
press("down")
eq(SummaryMenu._moveCursor, 2, "cursor on the second move")
press("b") settle()
press("a") settle()
eq(SummaryMenu._moveCursor, 2, "A back into detail keeps the cursor (only :989 and :5055 reset it)")
press("b") settle()
press("left") settle()
press("right") settle()
press("a") settle()
eq(SummaryMenu._moveCursor, 2, "page flips keep the cursor")
press("down")
eq(SummaryMenu._moveCursor, 5, "down past the last move lands on CANCEL")
press("b") settle()
press("a") settle()
eq(SummaryMenu._moveCursor, 1, "B on CANCEL resets the cursor to the first move")
SummaryMenu.close()

print("[test] 11. egg STATE box and memo")
local egg = { species = 1, isEgg = true, friendship = 5, otName = "RED", otId = 1, metLocation = 1 }
local memo = realMemo(egg, nil)
eq(#memo, 1, "the egg memo holds only the origin text")
check(memo[1] and not tostring(memo[1]):find("sEggHatchTimeTexts", 1, true), "the hatch text is not in the memo")
SummaryMenu.openMenu({ egg }, 1, {})
draw()
local st = text_at("sEggHatchTimeTexts[3]")
eq(st and st.x, 127, "the hatch text prints at the STATE box x (right pane + 7)")
eq(st and st.y, 61, "the hatch text prints at the STATE box y (right pane + 45)")
local nm = text_at("gText_EggNickname")
check(nm and nm.x == 167 and nm.y == 35, "the egg's name prints in the right pane, not the name strip")
SummaryMenu.close()

print("[test] 12. egg pic shake")
MANIFEST = { eggPicShake = {
  { 1, 1, 0, -1, -1, 0, -1, -1, 0, 1, 1 },
  { 2, 1, 0, -1, -2, 0, -2, -1, 0, 1, 2 },
  { 2, 1, 1, 0, -1, -1, -2, 0, -2, -1, -1, 0, 1, 1, 2 },
} }
local eggImg = {}
local drawn
gfx.draw = function(img, a, b)
  if img == eggImg then drawn = a end
end
local realFront = Pokemon.frontPic
Pokemon.frontPic = function() return { image = eggImg, w = 64, h = 64 } end
for _, c in ipairs({ { 5, 60, 2, 15 }, { 10, 90, 2, 11 }, { 40, 120, 1, 11 }, { 41, 120, 1, 11 } }) do
  local cycles, wait, first, len = c[1], c[2], c[3], c[4]
  SummaryMenu.openMenu({ { species = 1, isEgg = true, friendship = cycles } }, 1, {})
  frames(wait)
  eq(SummaryMenu._bounce.dx, 0, cycles .. " cycles: still for " .. wait .. " frames")
  frames(1)
  eq(SummaryMenu._bounce.dx, first, cycles .. " cycles: first jiggle step")
  frames(len - 1)
  eq(SummaryMenu._bounce.dx, 0, cycles .. " cycles: jiggle ends centred")
  eq(SummaryMenu._bounce.count, 1, cycles .. " cycles: one jiggle done")
  frames(wait + 1)
  eq(SummaryMenu._bounce.dx, first, cycles .. " cycles: second jiggle after the same delay")
  frames(len - 1 + 400)
  eq(SummaryMenu._bounce.count, 2, cycles .. " cycles: two jiggles only")
  eq(SummaryMenu._bounce.dx, 0, cycles .. " cycles: rests centred")
  SummaryMenu.close()
end
SummaryMenu.openMenu({ { species = 1, isEgg = true, friendship = 5 } }, 1, {})
frames(61)
drawn = nil
draw()
eq(drawn, 60 - 32 + 2 + 64, "the egg pic draws h-flipped at its shaken x")
SummaryMenu.close()
Pokemon.frontPic = realFront
MANIFEST = nil

T.finish("game3_summary_layout_s3_test")
