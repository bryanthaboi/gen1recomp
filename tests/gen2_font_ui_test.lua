-- Glyph pages and the four screens that read them.
--
--   GOLD_CACHE="$HOME/Library/Application Support/LOVE/gold-dev/gold" \
--     luajit tests/gen2_font_ui_test.lua
--
-- The $60-$7f slot holds ONE of two sheets (engine/gfx/load_font.asm): the
-- normal FontExtra, or FontBattleExtra where the same codes are different
-- glyphs -- $73 is a closing quote in one and the "ID" ligature in the other,
-- $74 a middle dot and the "No" ligature.  A screen that places either
-- ligature has to have swapped the sheet in first, and LoadFontsBattleExtra
-- swaps only 25 tiles before `jr LoadFrame` puts the textbox frame back, so
-- the border glyphs are the SAME on both.
--
-- '#' is not a glyph at all: charmap.asm gives it $54 and home/text.asm
-- places the four characters "POKé" for it, which is how the cart's own
-- strings spell POKéMON (data/credits_strings.asm Credits_Staff).
--
-- The screen half of the suite is layout that a placement list cannot show:
-- which SHEET a print resolves against, which cells a box border may not
-- keep, and how tall a menu window is for the rows actually in it.  Every
-- assertion runs a real `drawPanel` with the chrome recorded.

package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or {}
love.graphics = love.graphics or {}
local G = love.graphics
G.getColor = G.getColor or function() return 1, 1, 1, 1 end
G.setColor = G.setColor or function() end
G.rectangle = G.rectangle or function() end
G.print = G.print or function() end
G.printf = G.printf or function() end
G.draw = G.draw or function() end
G.newQuad = G.newQuad or function() return {} end
G.newImage = G.newImage or function() return nil end
G.getShader = G.getShader or function() return nil end
G.setShader = G.setShader or function() end
G.newShader = G.newShader or function() error("no shaders in this harness") end
G.getDimensions = G.getDimensions or function() return 160, 144 end
G.push = G.push or function() end
G.pop = G.pop or function() end
G.translate = G.translate or function() end
G.scale = G.scale or function() end
G.circle = G.circle or function() end
G.clear = G.clear or function() end
G.setLineWidth = G.setLineWidth or function() end
G.getFont = G.getFont or function() return nil end
G.setFont = G.setFont or function() end
love.math = love.math or { random = function(a, b) return b and a or 0.5 end }
love.image = love.image or {}
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function() return true end,
  remove = function() return true end,
}
love.timer = love.timer or { getTime = function() return 0 end }

require("src.core.Logger").warn = function() end

local S = require("tests.harness").suite("gen2 font + ui chrome")
local check, eq = S.check, S.eq

local Chrome = require("src.ui.gen2.Chrome")
local Credits = require("src.ui.gen2.Credits")
local Font = require("src.render.Font")
local HallOfFame = require("src.ui.gen2.HallOfFame")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local PcMenu = require("src.ui.gen2.PcMenu")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")

-- --------------------------------------------------------------- recording
--
-- One log for boxes, prints and raw fills, so ORDER can be asserted: a cell
-- blanked before the string that owns it lands is the whole point.

local log = {}
local real = {}

local function startRecording()
  log = {}
  real.print, real.box, real.cursor = Chrome.print, Chrome.box, Chrome.cursor
  real.clear, real.rect = Chrome.clear, love.graphics.rectangle
  Chrome.print = function(text, tx, ty)
    log[#log + 1] = { kind = "print", text = tostring(text), x = tx, y = ty,
                      battleExtra = Font.battleExtraActive() }
    return 0
  end
  Chrome.box = function(tx, ty, tw, th)
    log[#log + 1] = { kind = "box", x = tx, y = ty, w = tw, h = th }
  end
  Chrome.cursor = function(tx, ty)
    log[#log + 1] = { kind = "cursor", x = tx, y = ty }
  end
  Chrome.clear = function() log[#log + 1] = { kind = "clear" } end
  love.graphics.rectangle = function(mode, x, y, w, h)
    log[#log + 1] = { kind = "fill", mode = mode, x = x, y = y, w = w, h = h }
  end
end

local function stopRecording()
  Chrome.print, Chrome.box, Chrome.cursor = real.print, real.box, real.cursor
  Chrome.clear, love.graphics.rectangle = real.clear, real.rect
end

local function find(kind, predicate)
  for i, entry in ipairs(log) do
    if entry.kind == kind and (not predicate or predicate(entry)) then
      return entry, i
    end
  end
  return nil, nil
end

local function findPrint(text)
  return find("print", function(e) return e.text == text end)
end

-- A fill that covers the whole of a tile-coordinate rectangle.
local function coveringFill(tx, ty, tw, th)
  return find("fill", function(e)
    return e.mode == "fill" and e.x <= tx * 8 and e.y <= ty * 8
      and e.x + e.w >= (tx + tw) * 8 and e.y + e.h >= (ty + th) * 8
      -- the panel-wide clear is not a cell blank
      and e.w < 20 * 8
  end)
end

-- --------------------------------------------------------------- the sheets
--
-- Real cache, real charmap: the codes and the page routing are the thing
-- under test, so a fixture font would assert nothing.

local cacheDir = os.getenv("GOLD_CACHE")
if not cacheDir or cacheDir == "" then
  cacheDir = (os.getenv("HOME") or "") ..
    "/Library/Application Support/LOVE/gold-dev/gold"
end

local fontDef = loadfile(cacheDir .. "/data/generated/font.lua")
fontDef = fontDef and fontDef()

-- Font is a singleton and this suite is also dofile'd into
-- tests/run_tests.lua, which put Red's Data through it; that goes back at the
-- end of the section.
local haveData, Data = pcall(require, "src.core.Data")
haveData = haveData and type(Data) == "table" and type(Data.font) == "table"

if not fontDef then
  check(true, "no Gold cache (SKIP the glyph page checks)")
else
  local images = {}
  local realImage = require("src.render.Assets").image
  require("src.render.Assets").image = function(path)
    images[path] = images[path] or
      { path = path, getDimensions = function(self) return 128, 16 end }
    if path:find("font%.png$") then
      images[path].getDimensions = function() return 128, 64 end
    end
    return images[path]
  end
  Font.load({ font = fontDef })
  require("src.render.Assets").image = realImage

  -- Which sheet a code lands on, by the image drawCode reaches for.
  local drawn
  local realDraw = love.graphics.draw
  love.graphics.draw = function(image) drawn = image and image.path end
  local function sheetOf(code)
    drawn = nil
    Font.drawCode(code, 0, 0)
    return (drawn or "none"):match("[^/]+$")
  end

  Font.useBattleExtra(false)
  eq(sheetOf(0x73), "font_extra.png", "$73 is FontExtra's closing quote by default")
  eq(sheetOf(0x74), "font_extra.png", "$74 is FontExtra's middle dot by default")

  Font.useBattleExtra(true)
  eq(sheetOf(0x73), "font_battle_extra.png",
    "LoadFontsBattleExtra puts the <ID> ligature at $73")
  eq(sheetOf(0x74), "font_battle_extra.png",
    "and the No ligature at $74")
  eq(sheetOf(0x78), "font_battle_extra.png",
    "the swap runs to the last of the 25 tiles it loads")
  -- `jr LoadFrame` at the end of _LoadFontsBattleExtra: $79-$7e are the
  -- textbox frame on a battle-sheet screen too, so a box drawn there is the
  -- same box as everywhere else.
  local frameSheet = fontDef.imageFrames and
    fontDef.imageFrames:match("[^/]+$") or "font_extra.png"
  for code, name in pairs({ [0x79] = "tl", [0x7a] = "h", [0x7b] = "tr",
      [0x7c] = "v", [0x7d] = "bl", [0x7e] = "br" }) do
    eq(sheetOf(code), frameSheet,
      ("LoadFrame restores the %s border glyph from the selected frame"):format(name))
  end
  Font.useBattleExtra(false)
  love.graphics.draw = realDraw

  -- '#' places "POKé": four glyphs, on the byte the command sits on.
  local codes = Font.encode("#MON")
  eq(#codes, 7, "'#MON' is seven glyphs")
  eq(codes[1], 0x8F, "P")
  eq(codes[2], 0x8E, "O")
  eq(codes[3], 0x8A, "K")
  eq(codes[4], 0xEA, "é")
  eq(codes[5], 0x8C, "M")
  eq(codes[7], 0x8D, "N")
  eq(Font.width("#MON"), 7 * 8, "and seven tiles wide")
  local spans = Font.split("#MON")
  eq(spans[1].from, 1, "the expansion stays on the '#' byte")
  eq(spans[4].to, 1, "all four of it, so a cut never lands inside")
  eq(spans[5].from, 2, "the next glyph resumes after the command")

  -- Credits_Staff is `db "      #MON"` verbatim; six spaces centre the seven
  -- tiles POKéMON occupies on the 20-tile row.
  local staff = Credits.STRINGS[Credits.STAFF]
  eq(type(staff), "table", "the STAFF heading is three lines")
  eq(#Font.split(staff[1]), 13, "its first line is six spaces plus POKéMON")
  local line = Font.encode(staff[1])
  eq(line[7], 0x8F, "which starts at column 6 with a P")
  eq(line[10], 0xEA, "and carries the é of POKé")

  -- The Hall of Fame roster line: '№' '.' then the dex number, and
  -- '<ID>' '№' '/' then the trainer id (halloffame.asm :472 and :504).
  eq(Font.encode("№.")[1], 0x74, "the roster's No ligature is $74")
  local id = Font.encode("<ID>№/")
  eq(#id, 3, "IDNo/ is three tiles")
  eq(id[1], 0x73, "<ID> is $73")
  eq(id[2], 0x74, "No is $74")

  if haveData then Font.load(Data) end
end

-- The screen assertions below care about the active VRAM-slot selection, not
-- the extracted pixels.  When this suite is run by itself there may be no
-- Gold cache (and, unlike the old shared-process runner, no earlier suite has
-- happened to initialize Font).  Load tiny stand-in pages so those assertions
-- exercise the same state transition in complete isolation.
if not fontDef then
  local Assets = require("src.render.Assets")
  local realImage = Assets.image
  Assets.image = function(path)
    return { path = path, getDimensions = function() return 128, 16 end }
  end
  Font.load({ font = {
    image = "font.png",
    imageExtra = "font_extra.png",
    imageBattleExtra = "font_battle_extra.png",
    charmap = {},
  } })
  Assets.image = realImage
end

-- ------------------------------------------------------- naming keyboard
--
-- data/text/name_input_chars.asm: the last row of NameInputUpper is
-- "lower  DEL   END" and the last row of NameInputLower is
-- "UPPER  DEL   END".  The case target names the board it switches TO.

local naming = NamingScreen.new({}, { type = "player" })
eq(naming.lower, false, "the keyboard opens on the uppercase board")

startRecording()
naming:drawPanel()
stopRecording()
local caseLabel = find("print", function(e) return e.y == 16 and e.x == 2 end)
eq(caseLabel and caseLabel.text, "lower",
  "the uppercase board offers 'lower'")
check(findPrint("A") ~= nil, "and it really is the uppercase board")
eq((find("print", function(e) return e.y == 16 and e.x == 9 end) or {}).text,
  "DEL", "DEL keeps its column")
eq((find("print", function(e) return e.y == 16 and e.x == 15 end) or {}).text,
  "END", "END keeps its column")

naming:toggleCase()
startRecording()
naming:drawPanel()
stopRecording()
eq((find("print", function(e) return e.y == 16 and e.x == 2 end) or {}).text,
  "UPPER", "the lowercase board offers 'UPPER'")
check(findPrint("a") ~= nil, "and it really is the lowercase board")

-- ------------------------------------------------- summary move detail
--
-- SetUpMoveScreenBG draws Textbox (0,1) and Textbox (0,11) and only THEN
-- places the nickname at (5,1) and PlaceMoveData the TYPE plaque at (0,10) /
-- (0,11).  Both land on a border row of a box already on screen, and a
-- tilemap write replaces the cell it lands on.

local MOVES = {
  LEER = { name = "LEER", type = "NORMAL", power = 0,
    description = "Reduces the foe's<NEXT>DEFENSE." },
}
local CYNDA = {
  species = "CYNDAQUIL", nickname = "CYNDAQUIL", level = 22, hp = 50,
  maxHp = 50, stats = {}, otName = "GOLD", otId = 52049,
  moves = { { id = "LEER", pp = 27, maxPp = 30 } },
}
local summary = SummaryMenu.new({ data = { moves = MOVES } },
  { party = { CYNDA }, index = 1, moves = MOVES })
summary.moveDetail = true

startRecording()
summary:drawMoveDetail()
stopRecording()

local header, headerAt = findPrint("CYNDAQUIL")
check(header ~= nil and header.y == 1 and header.x == 5,
  "the nickname is placed at (5,1), the upper box's top border row")
local upperBox, upperAt = find("box", function(e) return e.y == 1 end)
check(upperBox ~= nil, "the upper box is drawn")
-- "CYNDAQUIL" is 9 tiles and "<LV>22" three, so the header owns (5,1)-(16,1).
local headerClear, headerClearAt = coveringFill(5, 1, 12, 1)
check(headerClear ~= nil, "the cells the header owns are blanked")
check(upperAt and headerClearAt and upperAt < headerClearAt,
  "after the box goes down, the way SetUpMoveScreenBG orders them")
check(headerClearAt and headerAt and headerClearAt < headerAt,
  "and before the header prints, so no border runs through the letters")

local plaque, plaqueAt = findPrint("│TYPE/└")
check(plaque ~= nil and plaque.x == 0 and plaque.y == 11,
  "String_MoveType_Bottom sits on the lower box's top border row")
local plaqueClear, plaqueClearAt = coveringFill(0, 10, 7, 2)
check(plaqueClear ~= nil, "the seven cells of the TYPE plaque are blanked")
check(plaqueClearAt and plaqueAt and plaqueClearAt < plaqueAt,
  "before either of its two lines prints")

-- Nothing outside the strings' own cells is touched: the move list keeps the
-- box it is drawn in.
check(coveringFill(1, 3, 8, 1) == nil, "the move rows are not blanked")

-- ---------------------------------------------------------- storage menu
--
-- _BillsPC's five rows fit ClearPCItemScreen's (0,0) 10x18 box exactly, with
-- SEE YA! on row 10.  The folded MAIL BOX makes six, and a window sized for
-- five closes under the fifth.

local function pcRows(opts)
  local menu = PcMenu.new({ save = { party = { { species = "CYNDAQUIL" } } } },
    opts)
  startRecording()
  menu:drawPanel()
  stopRecording()
  return menu
end

local bills = pcRows({ bills = true })
eq(#bills.entries, 5, "BILL's PC shows the cart's own five rows")
local billsBox = find("box", function(e) return e.y == 0 end)
eq(billsBox and billsBox.h, 12, "in ClearPCItemScreen's own 12-row window")
local seeya = findPrint("SEE YA!")
check(seeya ~= nil and seeya.y == 10, "SEE YA! on row 10")
check(seeya and billsBox and seeya.y <= billsBox.y + billsBox.h - 2,
  "inside the window's interior")

local folded = pcRows({})
eq(#folded.entries, 6, "a directly-built PC folds the item PC's MAIL BOX in")
local foldedBox = find("box", function(e) return e.y == 0 end)
eq(foldedBox and foldedBox.h, 14, "and the window grows a row for it")
local seeya6 = findPrint("SEE YA!")
check(seeya6 ~= nil and seeya6.y == 12, "SEE YA! moves to row 12")
check(seeya6 and foldedBox and seeya6.y <= foldedBox.y + foldedBox.h - 2,
  "still inside the window's interior")
-- .LogIn's text box goes down first so the taller window overlays it.
local whatBox, whatAt = find("box", function(e) return e.y == 12 end)
local topAt = select(2, find("box", function(e) return e.y == 0 end))
check(whatBox ~= nil and whatAt and topAt and whatAt < topAt,
  "the What? box is drawn under the menu window, not over it")
check(findPrint("What?") ~= nil, "and its one word still prints")

-- ------------------------------------------------------- hall of fame
--
-- InitDisplayForHallOfFame (engine/movie/init_hof_credits.asm) and the top of
-- _HallOfFamePC both call LoadFontsBattleExtra, so every string on this
-- screen resolves against the battle sheet.

local hof = HallOfFame.new({ data = {} }, {
  mode = "induct",
  save = { player = { name = "GOLD", id = 52049 }, playTime = {} },
  entry = { winCount = 1, mons = { {
    species = "TYPHLOSION", nickname = "BLAZE", level = 50, otId = 52049,
  } } },
})
hof.phase = "display"

Font.useBattleExtra(false)
startRecording()
hof:drawPanel()
stopRecording()

local dexLine = findPrint("№.")
check(dexLine ~= nil, "the roster line places the No ligature")
check(dexLine and dexLine.battleExtra == true,
  "with the battle sheet in the $60 slot, where that glyph lives")
local idLine = findPrint("<ID>№/")
check(idLine ~= nil and idLine.battleExtra == true,
  "and so does the trainer id line")
eq(Font.battleExtraActive(), false,
  "the sheet the caller had is put back when the screen is done")

-- The photo studio's card is the same three glyphs out of the same sheet:
-- PrintPartyMonPage1 (engine/printer/print_party.asm) opens with
-- LoadFontsBattleExtra before it writes any of them.
local PhotoStudio = require("src.ui.gen2.PhotoStudio")
local photo = PhotoStudio.new({ data = {} }, {
  mon = { species = "CYNDAQUIL", nickname = "CYNDAQUIL", level = 22,
    maxHp = 55, otId = 52049, moves = { { id = "TACKLE" } } },
  playerName = "GOLD",
})

startRecording()
photo:draw()
stopRecording()

local photoDex = findPrint("№.")
check(photoDex ~= nil and photoDex.battleExtra == true,
  "the photo card's No ligature resolves against the battle sheet")
local photoId = findPrint("<ID>№")
check(photoId ~= nil and photoId.battleExtra == true, "and its <ID> does too")
eq(Font.battleExtraActive(), false, "and the card puts the sheet back")

S.finish()
