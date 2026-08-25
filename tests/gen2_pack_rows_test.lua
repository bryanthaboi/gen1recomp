-- The PACK's list row and description box, as coordinates.
--
-- Most of what these three bugs broke is an integer the ASM names outright:
-- TMHMPocket_GetCurrentLineCoord's column 5 and the `ld bc, 3` that puts the
-- move name at column 8 (engine/items/tmhm.asm:355-403, #1695), the 1x9 cursor
-- column at (7,2) whose palette carries the red (engine/gfx/cgb_layouts.asm:
-- 723-726, #1694), and TEXTBOX_INNERY for anything printed in the description
-- box (#1725).  Chrome is swapped for a recorder here, so what is asserted is
-- the write list rather than the pixels -- whether the cursor comes out RED on
-- the real screen is tests/drivers/gold_pack_rows_bug1695_test.lua's job.

package.path = "./?.lua;" .. package.path

-- The UI modules require love-side helpers at load time.  Stub the pieces they
-- touch during construction and logic; nothing here draws.
love = love or {}
love.graphics = love.graphics or {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end,
  rectangle = function() end,
  print = function() end,
  printf = function() end,
  draw = function() end,
  newQuad = function() return {} end,
  newImage = function() return nil end,
  getShader = function() return nil end,
  setShader = function() end,
  newShader = function() error("no shaders in this harness") end,
  getDimensions = function() return 160, 144 end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
  circle = function() end, clear = function() end,
}
love.math = love.math or {
  random = function(a, b)
    if b then return a end
    return a and 1 or 0.5
  end,
}
love.image = love.image or {}
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function() return true end,
  remove = function() return true end,
}
love.timer = love.timer or { getTime = function() return 0 end }

-- No font is loaded here, so Font.encode would warn once per unknown glyph.
require("src.core.Logger").warn = function() end

local Chrome = require("src.ui.gen2.Chrome")
local PackGfx = require("src.ui.gen2.PackGfx")
local PackMenu = require("src.ui.gen2.PackMenu")
local Save = require("src.core.gen2.Save")

local failures, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(
      name, tostring(got), tostring(want)))
  end
end

-- ---------------------------------------------------------------- fixtures

local ITEMS = {
  POTION = { id = "POTION", name = "POTION", pocket = "ITEM", index = 17,
    canToss = true, canSelect = false, fieldMenu = "ITEMMENU_PARTY",
    description = "Restores HP<NEXT>by 20." },
  ITEMFINDER = { id = "ITEMFINDER", name = "ITEMFINDER", pocket = "KEY_ITEM",
    index = 55, canToss = false, canSelect = true,
    fieldMenu = "ITEMMENU_CLOSE",
    description = "Checks for unseen<NEXT>items in the area." },
  TM_DYNAMICPUNCH = { id = "TM_DYNAMICPUNCH", name = "TM01", pocket = "TM_HM",
    index = 191, tmNumber = 1, tmLabel = "TM01", teaches = "DYNAMICPUNCH" },
  TM_HEADBUTT = { id = "TM_HEADBUTT", name = "TM02", pocket = "TM_HM",
    index = 192, tmNumber = 2, tmLabel = "TM02", teaches = "HEADBUTT" },
  TM_NIGHTMARE = { id = "TM_NIGHTMARE", name = "TM50", pocket = "TM_HM",
    index = 240, tmNumber = 50, tmLabel = "TM50", teaches = "NIGHTMARE" },
  HM_CUT = { id = "HM_CUT", name = "HM01", pocket = "TM_HM", index = 243,
    tmNumber = 51, tmLabel = "HM01", teaches = "CUT" },
  HM_WATERFALL = { id = "HM_WATERFALL", name = "HM07", pocket = "TM_HM",
    index = 249, tmNumber = 57, tmLabel = "HM07", teaches = "WATERFALL" },
  -- A cache old enough to carry neither tmLabel nor a numbered name: the row
  -- has no number to print and must fall back to the item's own name.
  TM_LEGACY = { id = "TM_LEGACY", name = "TM??", pocket = "TM_HM", index = 300,
    teaches = "SWIFT" },
}

local MOVES = {}
for _, name in ipairs({ "DYNAMICPUNCH", "HEADBUTT", "NIGHTMARE", "CUT",
    "WATERFALL", "SWIFT" }) do
  MOVES[name] = { id = name, name = name, description = "Move<NEXT>text." }
end

local function newInput()
  local input = { pressed = {} }
  function input:press(...)
    for _, button in ipairs({ ... }) do self.pressed[button] = true end
  end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

local function newGame(save)
  return {
    input = newInput(),
    save = save,
    options = save and save.options or Save.defaultOptions(),
    data = { audio = {}, pokemon = {}, items = ITEMS, moves = MOVES },
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end,
    },
  }
end

-- ------------------------------------------------------------- the recorder
--
-- PackMenu reaches Chrome through the module table on every call, so swapping
-- the four entry points it draws through collects the screen as a write list.

local writes, cursors
local real = {
  print = Chrome.print, cursor = Chrome.cursor,
  cursorThrough = Chrome.cursorThrough, box = Chrome.box, clear = Chrome.clear,
}

local function install()
  writes, cursors = {}, {}
  Chrome.print = function(text, tx, ty)
    writes[#writes + 1] = { text = text, x = tx, y = ty }
  end
  Chrome.cursor = function(tx, ty, hollow)
    cursors[#cursors + 1] =
      { x = tx, y = ty, hollow = hollow or false, palette = nil }
  end
  Chrome.cursorThrough = function(tx, ty, palette, _invert, hollow)
    cursors[#cursors + 1] =
      { x = tx, y = ty, hollow = hollow or false, palette = palette }
  end
  Chrome.box = function() end
  Chrome.clear = function() end
end

local function restore()
  Chrome.print, Chrome.cursor = real.print, real.cursor
  Chrome.cursorThrough, Chrome.box, Chrome.clear =
    real.cursorThrough, real.box, real.clear
end

-- Where a string landed, as "x,y", so a miss reads as the coordinate it wanted.
local function at(text)
  for _, write in ipairs(writes) do
    if write.text == text then return write.x .. "," .. write.y end
  end
  return "absent"
end

local function drew(text)
  for _, write in ipairs(writes) do
    if write.text == text then return true end
  end
  return false
end

-- The cart's own PACK chrome, stubbed: PackGfx needs a real PNG to answer
-- available(), and none of that matters to where the writes land.
local RED = { { 255, 255, 255 }, { 123, 123, 255 }, { 0, 0, 255 }, { 255, 0, 0 } }
local function withPackGfx(pack)
  pack.gfx = {
    available = function() return true end,
    draw = function() end,
    colorsAt = function(_self, tx, ty)
      if tx == 7 and ty >= 2 and ty <= 10 then return RED end
      return nil
    end,
  }
  return pack
end

local function openPack(inventory, order, pocket)
  local save = Save.newGame()
  save.player.name = "GOLD"
  save.inventory = inventory
  save.bagOrder = order
  local game = newGame(save)
  local pack = PackMenu.new(game, { save = save, pocket = pocket })
  return withPackGfx(pack), save, game
end

-- ------------------------------------------- the TM/HM row's number (#1695)
--
-- TMHM_DisplayPocketItems writes the number itself: PRINTNUM_LEADINGZEROS on a
-- two-digit field for a TM, and the literal 'H' plus a PRINTNUM_LEFTALIGN
-- ordinal for an HM.  The item's own name is never printed in this pocket.

do
  local pack = openPack({
    TM_DYNAMICPUNCH = 1, TM_HEADBUTT = 3, TM_NIGHTMARE = 24,
    HM_CUT = 1, HM_WATERFALL = 1, TM_LEGACY = 1,
  }, {
    "HM_WATERFALL", "TM_NIGHTMARE", "HM_CUT", "TM_HEADBUTT",
    "TM_DYNAMICPUNCH", "TM_LEGACY",
  }, "TM_HM")

  check("TM01 prints as 01", pack.rows[1].tmhmLabel, "01")
  check("TM02 prints as 02", pack.rows[2].tmhmLabel, "02")
  check("TM50 keeps both digits", pack.rows[3].tmhmLabel, "50")
  -- HM01 is TM/HM 51: PrintNum sees 51 - NUM_TMS = 1, left aligned.
  check("HM01 prints as H1", pack.rows[4].tmhmLabel, "H1")
  check("HM07 prints as H7", pack.rows[5].tmhmLabel, "H7")
  check("a numberless TM row has no number to print",
    pack.rows[6].tmhmLabel, nil)

  install()
  pack.index = 1
  pack:drawPanel()
  restore()

  -- hlcoord 5 for the number, `ld bc, 3` on to column 8 for the move name, and
  -- the cursor gutter between them at LIST_X - 1.
  check("the number sits at column 5", at("01"), "5,2")
  check("the move name sits at column 8", at("DYNAMICPUNCH"), "8,2")
  check("the item's own name is never printed", drew("TM01"), false)
  check("nor is an invented HM prefix", drew("HM01"), false)
  check("the cursor is one tile left of the name", cursors[1].x, 7)
  check("and level with the row it marks", cursors[1].y, 2)
  -- engine/items/tmhm.asm:392-403 -- SCREEN_WIDTH + 9 from the number's coord.
  check("a TM's count is at column 17 on the row below", at("\xc3\x97 1"), "17,3")
  check("the fourth row is the first HM", at("H1"), "5,8")
  check("its move name shares that row", at("CUT"), "8,8")
  check("and an HM prints no count", drew("\xc3\x97 1"), true)

  -- The fifth row is HM07, whose count would be the only other "× 1".
  local ones = 0
  for _, write in ipairs(writes) do
    if write.text == "\xc3\x97 1" then ones = ones + 1 end
  end
  check("exactly one count on screen, the TM's", ones, 1)
end

-- A row with no number to print still has to draw something a person can read,
-- so the item's own name stands in rather than the row going blank.
do
  local pack = openPack({ TM_LEGACY = 1 }, { "TM_LEGACY" }, "TM_HM")
  install()
  pack.index = 1
  pack:drawPanel()
  restore()
  check("a numberless row falls back to the item name", at("TM??"), "8,2")
  check("and prints nothing in the number column", drew("SWIFT"), false)
end

-- ------------------------------------------------- an ordinary pocket's row

do
  local pack = openPack({ POTION = 5 }, { "POTION" }, "ITEM")
  install()
  pack.index = 1
  pack:drawPanel()
  restore()
  check("an ITEM row starts at column 8", at("POTION"), "8,2")
  check("with no number beside it", drew("01"), false)
  check("and its count in the same column a TM's uses",
    at("\xc3\x97 5"), "17,3")
end

-- ------------------------------------------------ the cursor's palette (#1694)
--
-- _CGB_PackPals fills (7,2) 1x9 with palette $3, whose colour 3 is red, and
-- that rectangle is exactly the five list rows' cursor gutter.

do
  local pack = openPack({ POTION = 5, ESCAPE_ROPE = 1 }, { "POTION" }, "ITEM")
  install()
  pack.index = 1
  pack:drawPanel()
  restore()
  check("the cursor asks the pack for its cell's palette",
    cursors[1] and cursors[1].palette, RED)
  local ink = cursors[1] and cursors[1].palette and cursors[1].palette[4]
  check("which is the one whose colour 3 is red",
    ink and table.concat(ink, ","), "255,0,0")

  -- SELECT arms a row: ScrollingMenu_PlaceCursor's hollow arrow takes the same
  -- palette, so `hollow` has to survive the call.
  pack.rows[2] = { id = "ESCAPE_ROPE", count = 1, name = "ESCAPE ROPE",
    showCount = true }
  pack.switching = 1
  pack.index = 2
  install()
  pack:drawPanel()
  restore()
  local armed
  for _, cursor in ipairs(cursors) do
    if cursor.hollow then armed = cursor end
  end
  check("the armed row's hollow arrow is drawn", armed ~= nil, true)
  check("in the cursor column", armed and armed.x, 7)
  check("and through the same red palette", armed and armed.palette, RED)

  -- No pack tiles in the cache: the fallback must still draw a cursor rather
  -- than nothing at all.
  pack.gfx = { available = function() return false end, draw = function() end }
  pack.switching = nil
  pack.index = 1
  install()
  pack:drawPanel()
  restore()
  check("a cache with no pack tiles falls back to the plain arrow",
    cursors[1] and cursors[1].palette, nil)
end

-- PackGfx flattens paletteZones to a per-cell lookup; the cursor zone is the
-- one PackMenu reads, so check the rectangle resolves over its whole height.
do
  local pals = { { { 1, 1, 1 } }, { { 2, 2, 2 } }, { { 3, 3, 3 } }, RED }
  local gfx = PackGfx.new({ pack = {
    palettes = pals,
    paletteZones = { { 0, 0, 10, 1, 2 }, { 7, 2, 1, 9, 4 } },
  } })
  check("the cursor column starts at row 2", gfx:colorsAt(7, 2), RED)
  check("and runs nine rows down to row 10", gfx:colorsAt(7, 10), RED)
  check("row 11 is outside it", gfx:colorsAt(7, 11), pals[1])
  check("so is the name column", gfx:colorsAt(8, 2), pals[1])
  check("the header keeps its own zone", gfx:colorsAt(0, 0), pals[2])
end

-- ------------------------------------------ the description box's rows (#1725)
--
-- Every text box in the game starts at TEXTBOX_INNERY and steps two rows a
-- line.  The item description already did; a message printed over the same box
-- did not.

do
  local pack = openPack({ ITEMFINDER = 1 }, { "ITEMFINDER" }, "KEY_ITEM")

  install()
  pack.index = 1
  pack:drawPanel()
  restore()
  check("an item description starts on row 14",
    at("Checks for unseen"), "1,14")
  check("and its second line is row 16", at("items in the area."), "1,16")

  -- RegisteredItemText, the case the report filed.
  pack.message = { "Registered the", "ITEMFINDER." }
  install()
  pack:drawPanel()
  restore()
  check("a message's first line shares the description's row",
    at("Registered the"), "1,14")
  check("and its second line lands on row 16", at("ITEMFINDER."), "1,16")

  -- _AskThrowAwayText, the other two-line message in this box.
  pack.message = { "Throw away how", "many?" }
  install()
  pack:drawPanel()
  restore()
  check("the toss question starts on row 14", at("Throw away how"), "1,14")
  check("with a blank row under it", at("many?"), "1,16")

  -- OakThisIsntTheTimeText is three lines, which two double-spaced rows cannot
  -- hold: those pack one row apart so the last is inside the box.
  pack.message = { "OAK: {PLAYER}!", "This isn't the", "time to use that!" }
  install()
  pack:drawPanel()
  restore()
  check("a three-line message starts a row higher", at("OAK: GOLD!"), "1,13")
  check("its second line is row 14", at("This isn't the"), "1,14")
  check("and its third clears the bottom border",
    at("time to use that!"), "1,15")

  -- The yes/no prompt is printed in the same box by the same path.
  pack.message = nil
  pack.confirm = { prompt = { "Throw away 1", "POTION(S)?" }, choice = 1 }
  install()
  pack:drawPanel()
  restore()
  check("the toss confirmation uses the same two rows",
    at("Throw away 1"), "1,14")
  check("and the same gap", at("POTION(S)?"), "1,16")
end

print(("gen2 pack rows: %d checks, %d failures"):format(checks, failures))
-- Raise rather than os.exit: tests/run_tests.lua dofiles this file, so an
-- exit here takes the whole tier down with it and silently skips every
-- suite listed after this one (see tests/harness.lua's T.suite note).
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
