-- Gen 2 menu behaviour: the naming screen's keyboard, the intro menu's entries,
-- the OPTION rows, the start menu's unlock rules, and the PACK's pockets.
--
-- ROM-free and draw-free: every screen's logic is separable from its drawing, so
-- this drives them with a stub input and asserts state.  What a test cannot say
-- -- whether the layout looks right -- is what tests/drivers/gold_menu_shots.lua
-- exists for.

package.path = "./?.lua;" .. package.path

-- The UI modules require love-side helpers at load time.  Stub the pieces they
-- touch during construction and logic; nothing here draws.
local drawn = {}
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

-- No font is loaded here (these are logic assertions, not rendering ones), so
-- Font.encode would warn once per unknown glyph.  Quiet it: the noise would
-- bury a real failure.
require("src.core.Logger").warn = function() end

local Chrome = require("src.ui.gen2.Chrome")
local MainMenu = require("src.ui.gen2.MainMenu")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local PackMenu = require("src.ui.gen2.PackMenu")
local Save = require("src.core.gen2.Save")
local StartMenu = require("src.ui.gen2.StartMenu")

local failures, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(
      name, tostring(got), tostring(want)))
  end
end

-- A stub input: queue presses, then each read consumes them.
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
  local input = newInput()
  return {
    input = input,
    save = save,
    options = save and save.options or Save.defaultOptions(),
    data = { audio = {}, pokemon = {}, items = {} },
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end,
    },
  }, input
end

-- ------------------------------------------------------------ Chrome.wrap

-- Nothing may print past the 160px frame, so long text has to wrap.  Without a
-- loaded font Font.width falls back to a fixed advance, which is enough to
-- assert that wrapping happens at all and never loses a word.
local wrapped = Chrome.wrap("What will CYNDAQUIL do?", 8)
check("wrap splits", #wrapped > 1, true)
local rejoined = table.concat(wrapped, " ")
check("wrap loses no words", rejoined, "What will CYNDAQUIL do?")
check("empty wraps to nothing", #Chrome.wrap("", 8), 0)
check("wrap keeps a single word whole", #Chrome.wrap("CYNDAQUIL", 2), 1)

-- Chrome.number pads the way PrintNum does.
check("number pads with spaces", Chrome.number(5, 3), "  5")
check("number pads with zeroes", Chrome.number(5, 3, true), "005")
check("number does not truncate", Chrome.number(1234, 2), "1234")

-- ------------------------------------------------------- Chrome.List

local chosen, cancelled
local list = Chrome.List.new({
  items = { "ONE", "TWO", "THREE" },
  onChoose = function(value) chosen = value end,
  onCancel = function() cancelled = true end,
})
local input = newInput()
check("list starts at 1", list.index, 1)
input:press("down")
list:update(input)
check("down moves", list.index, 2)
input:press("up")
list:update(input)
check("up moves back", list.index, 1)
input:press("up")
list:update(input)
check("up wraps to the end", list.index, 3)
input:press("down")
list:update(input)
check("down wraps to the start", list.index, 1)
input:press("a")
list:update(input)
check("a chooses", chosen, "ONE")
input:press("b")
list:update(input)
check("b cancels", cancelled, true)

-- A no-wrap list stops at the ends.
local bounded = Chrome.List.new({ items = { "A", "B" }, wrap = false })
input:press("up")
bounded:update(input)
check("no-wrap stays at the top", bounded.index, 1)

-- A list longer than its window scrolls.
local scrolling = Chrome.List.new({ items = { "A", "B", "C", "D", "E" },
  rows = 3 })
for _ = 1, 3 do
  input:press("down")
  scrolling:update(input)
end
check("scrolled", scrolling.index, 4)
check("window followed", scrolling.scroll, 1)

-- --------------------------------------------------------- intro menu

-- MainMenu_GetWhichMenu: no save file means NEW GAME / OPTION only.
local fresh = MainMenu.new(newGame(nil), { hasSave = false, save = false })
-- Plus the port's own EXIT GAME row, which the cart has no equivalent for.
check("no save has three entries", #fresh.list.items, 3)
check("first entry is NEW GAME", fresh.list.items[1].value, "new")
check("second is OPTION", fresh.list.items[2].value, "option")
check("last is EXIT GAME", fresh.list.items[3].value, "exit")

local withSave = MainMenu.new(newGame(Save.newGame()),
  { hasSave = true, save = Save.newGame() })
check("a save adds CONTINUE", #withSave.list.items, 4)
check("CONTINUE is first", withSave.list.items[1].value, "continue")
-- MenuHeader's default option is the first entry, so a save lands on CONTINUE.
check("default lands on CONTINUE", withSave.list.index, 1)

-- CONTINUE shows the save panel first and only then hands off; B backs out.
local continued
local confirmGame, confirmInput = newGame(Save.newGame())
local confirm = MainMenu.new(confirmGame, {
  hasSave = true, save = Save.newGame(),
  onContinue = function() continued = true end,
})
confirmInput:press("a")
confirm:update(0)
check("A opens the save panel", confirm.phase, "confirm")
check("no hand-off yet", continued, nil)
confirm.confirmDelay = 0
confirmInput:press("b")
confirm:update(0)
check("B returns to the menu", confirm.phase, "menu")
confirmInput:press("a")
confirm:update(0)
confirm.confirmDelay = 0
confirmInput:press("a")
confirm:update(0)
check("A confirms", continued, true)

-- ../pokecrystal/engine/rtc/timeset.asm:675
do
  local function pinnedTime(hour, minute)
    local m = MainMenu.new(newGame(nil), { hasSave = false, save = false,
      clock = { hour = hour, minute = minute, weekday = 1 } })
    return MainMenu.timeString(m:clockParts())
  end
  check("midnight is NITE 12", pinnedTime(0, 0), "NITE 12:00")
  check("morning keeps its word", pinnedTime(5, 9), "MORN 5:09")
  check("noon is DAY 12", pinnedTime(12, 30), "DAY 12:30")
  check("evening wraps back to NITE", pinnedTime(20, 5), "NITE 8:05")
end
check("weekday names", MainMenu.DAYS[6], "FRIDAY")

-- ../pokecrystal/engine/menus/intro_menu.asm:479
check("CONTINUE reuses SAVE's panel constants",
  MainMenu.PANEL == require("src.ui.gen2.SaveMenu").PANEL, true)
check("CONTINUE offsets it to row 8", MainMenu.PANEL_Y, 8)

-- ------------------------------------------------------- naming screen

local namingGame, namingInput = newGame(Save.newGame())
local naming = NamingScreen.new(namingGame, { type = "player" })
check("player field is 7 long", naming.maxLength, 7)
check("starts uppercase", naming.lower, false)
check("cursor starts at A", naming:cursorCharacter(), "A")

-- The grid is nine wide; right wraps.
namingInput:press("right")
naming:update(0)
check("moved right", naming:cursorCharacter(), "B")
naming.col = 8
namingInput:press("right")
naming:update(0)
check("right wraps to the start", naming.col, 0)
namingInput:press("left")
naming:update(0)
check("left wraps to the end", naming.col, 8)

-- Typing appends; B deletes rather than cancelling.
naming.col, naming.row = 0, 0
namingInput:press("a")
naming:update(0)
check("typed A", naming.text, "A")
namingInput:press("right")
naming:update(0)
namingInput:press("a")
naming:update(0)
check("typed AB", naming.text, "AB")
namingInput:press("b")
naming:update(0)
check("B deleted", naming.text, "A")
namingInput:press("b")
naming:update(0)
namingInput:press("b")
naming:update(0)
check("B on an empty field is safe", naming.text, "")

-- SELECT toggles case; the same cell then types lowercase.
namingInput:press("select")
naming:update(0)
check("now lowercase", naming.lower, true)
naming.col, naming.row = 0, 0
namingInput:press("a")
naming:update(0)
check("typed a", naming.text, "a")
check("lower label says UPPER", naming:cursorCharacter(), "a")

-- The bottom row's three fat targets: case / DEL / END.
naming.lower = false
naming.row = naming:bottomRow()
naming.col = 0
check("target 1 is the case switch", naming:bottomTarget(), 1)
check("cursor reads CASE", naming:cursorCharacter(), "CASE")
naming.col = 3
check("target 2 is DEL", naming:bottomTarget(), 2)
naming.col = 6
check("target 3 is END", naming:bottomTarget(), 3)
-- Left/right hop between targets rather than stepping a column at a time.
namingInput:press("left")
naming:update(0)
check("left hops a whole target", naming:bottomTarget(), 2)
namingInput:press("right")
naming:update(0)
check("right hops back", naming:bottomTarget(), 3)

-- START parks the cursor on END, wherever it was.
naming.row, naming.col = 0, 0
namingInput:press("start")
naming:update(0)
check("START jumps to END row", naming.row, naming:bottomRow())
check("START jumps to END target", naming:bottomTarget(), 3)

-- END hands the typed name back.
local finished
local endGame, endInput = newGame(Save.newGame())
local ending = NamingScreen.new(endGame, {
  type = "player",
  onDone = function(name) finished = name end,
})
ending.text = "GOLD"
ending.row = ending:bottomRow()
ending.col = 6
endInput:press("a")
ending:update(0)
check("END returned the name", finished, "GOLD")

-- Filling the last slot does NOT end entry: `.a` is `ret nc` and
-- AdvanceCursor_CheckEndOfString answers carry once the buffer is full, so the
-- handler falls through into `.start` and parks the cursor on END with the
-- screen still up (engine/menus/naming_screen.asm:401-410).  Only `.end` calls
-- StoreEntry.  This case used to assert the auto-accept the port did instead.
local autoDone
local autoGame, autoInput = newGame(Save.newGame())
local auto = NamingScreen.new(autoGame, {
  type = "player", onDone = function(name) autoDone = name end,
})
auto.text = "ABCDEF" -- one short of 7
auto.row, auto.col = 0, 0
autoInput:press("a")
auto:update(0)
check("the seventh character is typed", auto.text, "ABCDEFA")
check("but entry is not over", autoDone, nil)
check("the cursor parks on the END row", auto.row, auto:bottomRow())
check("on END itself", auto:cursorCharacter(), "END")
-- A further letter press is the `cp c / ret nc` no-op, and A on END is what
-- finally hands the name back.
auto.row, auto.col = 0, 0
autoInput:press("a")
auto:update(0)
check("a full buffer takes no more letters", auto.text, "ABCDEFA")
auto.row, auto.col = auto:bottomRow(), 6
autoInput:press("a")
auto:update(0)
check("A on END stores the entry", autoDone, "ABCDEFA")

-- The blank cells are real spaces, not dead keys: the NameInput* rows are
-- written into the tilemap and GetLastCharacter reads the tile under the cursor
-- back out, so the trailing blanks of "S T U V W X Y Z  " type a space
-- (data/text/name_input_chars.asm, engine/menus/naming_screen.asm
-- GetLastCharacter).
local spaceGame, spaceInput = newGame(Save.newGame())
local spacer = NamingScreen.new(spaceGame, { type = "player" })
spacer.text = "AB"
spacer.row, spacer.col = 2, 8 -- the blank after Z
check("the cell after Z is a space", spacer:cursorCharacter(), " ")
spaceInput:press("a")
spacer:update(0)
check("and pressing A types it", spacer.text, "AB ")

-- A box name is longer and gets an extra keyboard row.
local box = NamingScreen.new(newGame(Save.newGame()), { type = "box" })
check("box field is 8 long", box.maxLength, 8)
check("box has six rows", box:bottomRow(), 5)
check("box keyboard starts higher", box:keyboardTop(), 6)
check("name keyboard start", naming:keyboardTop(), 8)

-- ------------------------------------------------------------- options

local optionsGame, optionsInput = newGame(Save.newGame())
local options = OptionsMenu.new(optionsGame, {
  options = Save.defaultOptions(),
})
-- The cart's seven rows, then the port's: CONTROLS, audio, PERFORMANCE,
-- speed, display, SHADER FX + SHADER FX 2 (the second slot added alongside
check("thirty-three rows", #OptionsMenu.ROWS, 33)
check("the cart's rows come first", OptionsMenu.ROWS[7].key, "frame")
check("then the rebind screen", OptionsMenu.ROWS[8].id, "controls")
check("then the port's audio group", OptionsMenu.ROWS[9].key, "musicVol")
check("last row is BACK", OptionsMenu.ROWS[#OptionsMenu.ROWS].cancel, true)
-- PRINT is wGBPrinterBrightness and there is no Game Boy Printer here, so
-- buildRows hides it: the descriptor and the save key survive, the row does
-- not reach the screen.
local function hasRow(rows, key)
  for _, row in ipairs(rows) do if row.key == key then return true end end
  return false
end
check("PRINT is still a descriptor", hasRow(OptionsMenu.ROWS, "print"), true)
check("but never reaches the screen", hasRow(options.rows, "print"), false)
check("and the save keeps its value",
  Save.defaultOptions().print ~= nil, true)
-- The rows are grouped into pages now, so the top level opens on the SPEED
-- group and TEXT SPEED is the first row of the page it opens.
check("starts on the SPEED group", options:row().id, "group.speed")
local speedPage = options:focusRow("textSpeed")
check("TEXT SPEED is on a page", speedPage ~= options, true)
check("and the cursor lands on it", speedPage:row().key, "textSpeed")
check("default text speed", speedPage.options.textSpeed, "MID")
optionsInput:press("right")
speedPage:update(0)
check("right cycles forward", options.options.textSpeed, "SLOW")
optionsInput:press("right")
speedPage:update(0)
check("right wraps", options.options.textSpeed, "FAST")
optionsInput:press("left")
speedPage:update(0)
check("left wraps back", options.options.textSpeed, "SLOW")
check("a page edits the caller's own options table",
  speedPage.options == options.options, true)

local battlePage = options:focusRow("battleScene")
check("BATTLE SCENE is on the battle page", battlePage:row().key, "battleScene")
optionsInput:press("right")
battlePage:update(0)
check("battle scene toggles off", options.options.battleScene, false)

-- FRAME is 1-8 and wraps.
local framePage = options:focusRow("frame")
check("frame row", framePage:row().frame, true)
options = framePage
options.options.frame = 8
optionsInput:press("right")
options:update(0)
check("frame wraps to 1", options.options.frame, 1)
optionsInput:press("left")
options:update(0)
check("frame wraps to 8", options.options.frame, 8)
-- options_menu.asm:475 UpdateFrame calls LoadFontsExtra, so the value is live.
check("frame reaches the font", require("src.render.Font").frameIndex(), 8)

-- CANCEL and START both leave, handing the edited table back.
local savedOptions
local exitGame, exitInput = newGame(Save.newGame())
local exiting = OptionsMenu.new(exitGame, {
  options = Save.defaultOptions(),
  onDone = function(o) savedOptions = o end,
})
-- The screen's own rows, not ROWS: buildRows drops the touch three off a
-- desktop, so the raw descriptor count overshoots CANCEL.
exiting.index = #exiting.view
exitInput:press("a")
exiting:update(0)
check("BACK leaves", savedOptions ~= nil, true)

-- --------------------------------------------------------- start menu

local save = Save.newGame()
local bare = StartMenu.new(newGame(save), { save = save })
-- With no party, no dex and no Pokegear, only PACK and the always-on entries.
local function labels(menu)
  local out = {}
  for _, item in ipairs(menu.items) do out[#out + 1] = item.value end
  return table.concat(out, ",")
end
check("bare start menu", labels(bare), "pack,status,save,option,quit")

save.party = { { species = "CYNDAQUIL" } }
save.pokedexReceived = true
save.inventory = { POKEGEAR = 1 }
local full = StartMenu.new(newGame(save), { save = save })
check("unlocked start menu", labels(full),
  "pokedex,pokemon,pack,pokegear,status,save,option,quit")
-- The player's own name is the STATUS entry's label.
save.player.name = "SILVER"
local named = StartMenu.new(newGame(save), { save = save })
for _, item in ipairs(named.items) do
  if item.value == "status" then
    check("status label is the player name", item.label, "SILVER")
  end
end

-- MENU ACCOUNT off hides the description box.
save.options = Save.defaultOptions()
save.options.menuAccount = false
local quiet = StartMenu.new(newGame(save), { save = save })
check("description hidden", quiet.showDescription, false)
save.options.menuAccount = true
check("description shown",
  StartMenu.new(newGame(save), { save = save }).showDescription, true)

-- ---------------------------------------------------------------- pack

local packSave = Save.newGame()
packSave.inventory = {
  POTION = 3, POKE_BALL = 5, BICYCLE = 1, TM_HEADBUTT = 1,
}
local packGame, packInput = newGame(packSave)
packGame.data.items = {
  POTION = { id = "POTION", name = "POTION", pocket = "ITEM", index = 1 },
  POKE_BALL = { id = "POKE_BALL", name = "POKé BALL", pocket = "BALL",
    index = 2 },
  BICYCLE = { id = "BICYCLE", name = "BICYCLE", pocket = "KEY_ITEM",
    index = 3 },
  TM_HEADBUTT = { id = "TM_HEADBUTT", name = "TM02", pocket = "TM_HM",
    index = 4, teaches = "HEADBUTT", tmNumber = 2 },
}
local pack = PackMenu.new(packGame, { pocket = "ITEM" })
check("four pockets", #PackMenu.POCKETS, 4)
check("items pocket has the potion", pack.rows[1].id, "POTION")
check("items pocket has only it", #pack.rows, 1)
check("potion shows a count", pack.rows[1].showCount, true)

packInput:press("right")
pack:update(0)
check("right switches pocket", pack:pocket().id, "BALL")
check("balls pocket", pack.rows[1].id, "POKE_BALL")
packInput:press("right")
pack:update(0)
check("next is key items", pack:pocket().id, "KEY_ITEM")
check("key items show no count", pack.rows[1].showCount, false)
packInput:press("right")
pack:update(0)
check("then TM/HM", pack:pocket().id, "TM_HM")
check("TM row names its move", pack.rows[1].teaches, "HEADBUTT")
packInput:press("right")
pack:update(0)
check("pocket wraps around", pack:pocket().id, "ITEM")

-- engine/items/tmhm.asm:341 -- TMHM_DisplayPocketItems walks wTMsHMs 1..57, so
-- the pocket is TM01..TM50 then HM01..HM07 whatever order the player picked
-- them up in, and tmhm.asm:207 keeps SELECT out of it entirely.
do
  local tmSave2 = Save.newGame()
  tmSave2.inventory = {
    HM_WATERFALL = 1, TM_NIGHTMARE = 2, HM_CUT = 1, TM_ROAR = 3,
    TM_DYNAMICPUNCH = 12, TM_LEGACY = 1,
  }
  tmSave2.bagOrder = {
    "HM_WATERFALL", "TM_NIGHTMARE", "HM_CUT", "TM_ROAR", "TM_DYNAMICPUNCH",
    "TM_LEGACY",
  }
  local tmGame2, tmInput2 = newGame(tmSave2)
  tmGame2.data.items = {
    TM_DYNAMICPUNCH = { id = "TM_DYNAMICPUNCH", name = "TM01",
      pocket = "TM_HM", index = 191, tmNumber = 1 },
    TM_ROAR = { id = "TM_ROAR", name = "TM05", pocket = "TM_HM",
      index = 195, tmNumber = 5 },
    TM_NIGHTMARE = { id = "TM_NIGHTMARE", name = "TM50", pocket = "TM_HM",
      index = 240, tmNumber = 50 },
    HM_CUT = { id = "HM_CUT", name = "HM01", pocket = "TM_HM",
      index = 241, tmNumber = 51 },
    HM_WATERFALL = { id = "HM_WATERFALL", name = "HM07", pocket = "TM_HM",
      index = 247, tmNumber = 57 },
    -- A cache (or a mod) with no tmNumber falls back to the ItemNames index.
    TM_LEGACY = { id = "TM_LEGACY", name = "TM??", pocket = "TM_HM",
      index = 300 },
  }
  local tmPack = PackMenu.new(tmGame2, { pocket = "TM_HM" })
  local function ids(rows)
    local out = {}
    for i = 1, #rows do out[i] = rows[i].id end
    return table.concat(out, ",")
  end
  check("TM/HM pocket is TM-number ordered, not pickup ordered",
    ids(tmPack.rows),
    "TM_DYNAMICPUNCH,TM_ROAR,TM_NIGHTMARE,HM_CUT,HM_WATERFALL,TM_LEGACY")
  check("the first row is TM01", tmPack.rows[1].id, "TM_DYNAMICPUNCH")
  check("and a tmNumber-less item lands after HM07",
    tmPack.rows[#tmPack.rows].id, "TM_LEGACY")
  check("the TM keeps its count", tmPack.rows[1].showCount, true)
  check("the HM shows none", tmPack.rows[4].showCount, false)

  tmPack.index = 1
  tmInput2:press("select")
  tmPack:update(0)
  check("SELECT cannot arm a TM/HM row", tmPack.switching, nil)
  check("and prints no move prompt", tmPack.message, nil)

  -- The other three pockets still reorder on SELECT (pack.asm:1290).
  tmSave2.inventory.POTION = 1
  tmSave2.inventory.SUPER_POTION = 1
  tmSave2.bagOrder = { "POTION", "SUPER_POTION" }
  tmGame2.data.items.POTION =
    { id = "POTION", name = "POTION", pocket = "ITEM", index = 1 }
  tmGame2.data.items.SUPER_POTION =
    { id = "SUPER_POTION", name = "SUPER POTION", pocket = "ITEM", index = 2 }
  tmPack.pocketIndex = 1
  tmPack:rebuild()
  tmPack.index = 1
  tmInput2:press("select")
  tmPack:update(0)
  check("but the ITEM pocket still arms", tmPack.switching, 1)
end

-- item_data_constants.asm:47 MAX_ITEMS / MAX_BALLS / MAX_KEY_ITEMS, and the
-- TM/HM pocket is wTMsHMs (ram/wram.asm:2421), NUM_TMS + NUM_HMS = 57 bytes:
-- 50 add_tm rows and 7 add_hm rows in constants/item_constants.asm:220-293.
do
  local Bag = require("src.inventory.Bag")
  check("ITEM pocket is MAX_ITEMS", Bag.capacity(packGame.data, "ITEM"), 20)
  check("BALL pocket is MAX_BALLS", Bag.capacity(packGame.data, "BALL"), 12)
  check("KEY_ITEM pocket is MAX_KEY_ITEMS",
    Bag.capacity(packGame.data, "KEY_ITEM"), 25)
  check("TM/HM pocket is NUM_TMS + NUM_HMS",
    Bag.capacity(packGame.data, "TM_HM"), 57)

  -- Bag.add tests the cap before inserting, so all 57 cart TM/HMs fit.
  local tmData = { items = {}, constants = { bagSize = 2 } }
  for i = 1, 58 do
    tmData.items["TM_FIX_" .. i] = { id = "TM_FIX_" .. i, name = "TM" .. i,
      pocket = "TM_HM", index = 200 + i }
  end
  check("a mod's bagSize resizes the ITEM pocket only",
    Bag.capacity(tmData, "TM_HM"), 57)
  local tmSave = { inventory = {}, bagOrder = {} }
  for i = 1, 57 do Bag.add(tmSave, "TM_FIX_" .. i, 1, tmData) end
  check("all 57 of them fit", Bag.slots(tmSave, tmData, "TM_HM"), 57)
  check("and a 58th TM/HM id has no byte to live in",
    Bag.add(tmSave, "TM_FIX_58", 1, tmData), false)
end

-- CANCEL sits one past the last row.
check("cancel is past the end", pack:total(), #pack.rows + 1)
pack.index = pack:total()
check("on cancel", pack:isCancel(), true)

-- ---- the item submenu (.ItemBallsKey_LoadSubmenu, engine/items/pack.asm:243)
--
-- A on a row picks the row; it does not use it.  Without this menu there is no
-- TOSS anywhere in the PACK, which is the bug this block pins.
do
  local items = {
    POTION = { id = "POTION", name = "POTION", pocket = "ITEM", index = 1,
      canToss = true, canSelect = false, fieldMenu = "ITEMMENU_PARTY" },
    -- ITEMMENU_NOUSE + tossable: MenuHeader_HoldableItem, no USE row at all.
    BERRY = { id = "BERRY", name = "BERRY", pocket = "ITEM", index = 2,
      canToss = true, canSelect = false, fieldMenu = "ITEMMENU_NOUSE" },
    -- CANT_TOSS + selectable: MenuHeader_UnusableKeyItem.
    BICYCLE = { id = "BICYCLE", name = "BICYCLE", pocket = "KEY_ITEM",
      index = 3, canToss = false, canSelect = true,
      fieldMenu = "ITEMMENU_CLOSE" },
    -- CANT_TOSS + not selectable: MenuHeader_UnusableItem.
    SECRETPOTION = { id = "SECRETPOTION", name = "SECRETPOTION",
      pocket = "KEY_ITEM", index = 4, canToss = false, canSelect = false,
      fieldMenu = "ITEMMENU_NOUSE" },
    HM_CUT = { id = "HM_CUT", name = "HM01", pocket = "TM_HM", index = 5,
      canToss = false, canSelect = false, teaches = "CUT" },
    TM_HEADBUTT = { id = "TM_HEADBUTT", name = "TM02", pocket = "TM_HM",
      index = 6, canToss = true, canSelect = false, teaches = "HEADBUTT" },
  }
  local save = Save.newGame()
  save.inventory = { POTION = 5, BERRY = 1, BICYCLE = 1, SECRETPOTION = 1,
    HM_CUT = 1, TM_HEADBUTT = 1 }
  local game, input = newGame(save)
  game.data.items = items
  game.data.moves = { CUT = { name = "CUT" }, HEADBUTT = { name = "HEADBUTT" } }
  -- A world with a useFieldItem is what makes this a field PACK rather than a
  -- chooser: the mart's SELL and the item PC's DEPOSIT pass `world = {}`.
  game.world = { useFieldItem = function() return nil end }
  local menu = PackMenu.new(game, { pocket = "ITEM" })

  local function rows(id) return table.concat(menu:submenuRows(id), ",") end
  check("a usable tossable item", rows("POTION"), "use,give,toss,quit")
  check("an unusable tossable item", rows("BERRY"), "give,toss,quit")
  check("a registerable key item", rows("BICYCLE"), "use,sel,quit")
  check("a plain key item", rows("SECRETPOTION"), "use,quit")
  menu.pocketIndex = 4
  check("an HM", rows("HM_CUT"), "use,quit")
  check("a TM", rows("TM_HEADBUTT"), "use,give,quit")
  menu.pocketIndex = 1
  menu:rebuild()

  menu.index = 1
  check("the row under the cursor", menu.rows[1].id, "POTION")
  input:press("a")
  menu:update(0)
  check("A opens the submenu", menu.submenu ~= nil, true)
  check("on USE", menu.submenu.rows[menu.submenu.index], "use")
  check("and uses nothing yet", save.inventory.POTION, 5)

  -- TOSS: "Throw away how many?", the count, the yes/no, then TossItem.
  input:press("down")
  menu:update(0)
  input:press("down")
  menu:update(0)
  check("down twice reaches TOSS", menu.submenu.rows[menu.submenu.index],
    "toss")
  input:press("a")
  menu:update(0)
  check("TOSS asks how many", menu.message and menu.message[1],
    "Throw away how")
  check("starting at one", menu.qtyState and menu.qtyState.qty, 1)
  input:press("up")
  menu:update(0)
  check("up steps the count", menu.qtyState.qty, 2)
  input:press("a")
  menu:update(0)
  check("A asks to confirm", menu.confirm and menu.confirm.prompt[1],
    "Throw away 2")
  check("naming the item", menu.confirm.prompt[2], "POTION(S)?")
  check("and still nothing tossed", save.inventory.POTION, 5)
  input:press("down")
  menu:update(0)
  input:press("a")
  menu:update(0)
  check("NO keeps the item", save.inventory.POTION, 5)

  -- ...and YES spends it.
  input:press("a")
  menu:update(0)
  input:press("down")
  menu:update(0)
  input:press("down")
  menu:update(0)
  input:press("a")
  menu:update(0)
  input:press("a")
  menu:update(0)
  input:press("a")
  menu:update(0)
  check("YES tosses the count", save.inventory.POTION, 4)
  check("with _ThrewAwayText", menu.message and menu.message[1], "Threw away")

  -- B out of the submenu is QuitItemSubmenu: nothing happens at all.
  menu.message = nil
  input:press("a")
  menu:update(0)
  input:press("b")
  menu:update(0)
  check("B closes the submenu", menu.submenu, nil)
  check("spending nothing", save.inventory.POTION, 4)

  -- GIVE is the party list under PARTYMENUACTION_GIVE_ITEM, then the same
  -- TryGiveItemToPartymon the party's own GIVE row runs.
  save.party = { { species = "CYNDAQUIL", nickname = "CYNDA", hp = 20,
    maxHp = 20, level = 5 } }
  menu.index = 1
  input:press("a")
  menu:update(0)
  input:press("down")
  menu:update(0)
  check("down once reaches GIVE", menu.submenu.rows[menu.submenu.index],
    "give")
  input:press("a")
  menu:update(0)
  check("GIVE opens the party list", game.stack:top().prompt,
    "To which <PK><MN>?")
  input:press("a")
  game.stack:top():update(0)
  input:press("a")
  game.stack:top():update(0)
  check("the mon is holding it", save.party[1].item, "POTION")
  check("and the bag is one lighter", save.inventory.POTION, 3)
  while game.stack:top() do game.stack:pop() end

  -- A chooser PACK still answers its caller on the first press: DepositSellPack
  -- and TutorialPack have no submenu on the cart.
  local chosen = nil
  local chooser = PackMenu.new(game, { pocket = "ITEM", give = true,
    onChoose = function(id) chosen = id end })
  chooser.index = 1
  input:press("a")
  chooser:update(0)
  check("a chooser opens no submenu", chooser.submenu, nil)
  check("and answers straight away", chosen, "POTION")
end

-- ------------------------------------------------------------------- #DEX
--
-- The dex's numbers are PrintNum fields, and getting them wrong is what put
-- "1.08" where the cart prints 1'08".  The height word is four digits with
-- two in front of the point; the weight word is five with four in front; and
-- both blank their leading zeroes rather than printing them.
local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local num = PokedexMenu.printNumString

check("3-digit count is space padded", num(7, 3), "  7")
check("leading zeros when asked", num(7, 3, true), "007")
check("a full field is untouched", num(250, 3), "250")
check("Bulbasaur is 2'04\"", num(204, 4, false, 2), " 2.04")
check("Mewtwo is 6'07\"", num(607, 4, false, 2), " 6.07")
check("a ten-foot mon keeps both digits", num(1300, 4, false, 2), "13.00")
check("Bulbasaur weighs 15.0", num(150, 5, false, 4), "  15.0")
check("Mewtwo weighs 269.0", num(2690, 5, false, 4), " 269.0")
-- .PrintDigit forces the digit in front of the point, so a sub-pound mon
-- reads 0.1 rather than losing its zero.
check("a light mon keeps its tenth", num(1, 5, false, 4), "   0.1")
check("a short mon keeps its zero feet", num(3, 4, false, 2), " 0.03")

-- The listing lives on the window layer, and OLD mode is the only one that
-- moves it (hWX $4a rather than $47) or prints dex numbers.
local dexSave = Save.newGame("GOLD")
dexSave.pokedex = { seen = {}, caught = {} }
local dexGame = newGame(dexSave)
dexGame.data.gen2Pokedex = {
  entries = {
    BULBASAUR = { dex = 1, kind = "SEED", height = 204, weight = 150,
      text = "a<NEXT>b<NEXT>c", text2 = "d<NEXT>e" },
    IVYSAUR = { dex = 2, kind = "SEED", height = 303, weight = 290 },
  },
  newOrder = { "BULBASAUR", "IVYSAUR" },
  alphabeticalOrder = { "BULBASAUR", "IVYSAUR" },
}
dexGame.data.pokemon.BULBASAUR = { types = { "GRASS", "POISON" } }
dexGame.data.pokemon.IVYSAUR = { types = { "GRASS", "POISON" } }
local dex = PokedexMenu.new(dexGame, {})
check("dex lists every entry", #dex.rows, 2)
check("dex starts in NEW mode", dex:mode(), "NEW")

-- The dex's ROM `db` labels are catalog strings, resolved at draw time.  Stub
-- its tile primitives and inspect the exact text writes without a GPU.
require("src.core.Strings").load({ strings = {
  SEEN = "VUS", OWN = "PRIS", HT = "TAILLE", WT = "POIDS",
  NEW = "JOHTO", ["NEW POKéDEX MODE"] = "MODE JOHTO",
  ["<PK><MN> are listed by"] = "Les POKéMON suivent",
  ["evolution type."] = "leur évolution.", TYPE1 = "TYPE A",
  TYPE2 = "TYPE B", ["BEGIN SEARCH!!"] = "CHERCHER !!",
  CANCEL = "ANNULER",
} })
drawn = {}
dex.text = function(_, text, x, y) drawn[x .. ":" .. y] = text end
dex.fill, dex.border, dex.tile = function() end, function() end, function() end
dex.blank, dex.drawPic, dex.drawFootprint = function() end, function() end,
  function() end
dex:drawMainBackground()
check("SEEN is localizable", drawn["1:11"], "VUS")
check("OWN is localizable", drawn["1:14"], "PRIS")
drawn = {}
dex.optionIndex = 1
dex:drawOption()
check("a mode label is localizable", drawn["3:4"], "MODE JOHTO")
check("a mode description is localizable",
  drawn["1:14"], "Les POKéMON suivent")
drawn = {}
dex:drawSearch()
check("TYPE1 is localizable", drawn["3:4"], "TYPE A")
check("TYPE2 is localizable", drawn["3:6"], "TYPE B")
check("BEGIN SEARCH is localizable", drawn["3:13"], "CHERCHER !!")
check("the dex CANCEL row is localizable", drawn["3:15"], "ANNULER")
drawn = {}
dex.newEntry = true
dex:drawEntryBody(dex.rows[1], dex.data.gen2Pokedex.entries.BULBASAUR)
check("HT is localizable", drawn["9:7"], "TAILLE")
check("WT is localizable", drawn["9:9"], "POIDS")
dex.text, dex.fill, dex.border, dex.tile = nil, nil, nil, nil
dex.blank, dex.drawPic, dex.drawFootprint = nil, nil, nil
dex.newEntry = nil
require("src.core.Strings").load(nil)
-- Pokedex_UpdateMainScreen: SELECT opens the OPTION screen and START the
-- SEARCH screen.  Neither cycles anything in place -- the mode changes when
-- the OPTION screen's own cursor picks one and A confirms it.
check("SELECT opens the OPTION screen", (function()
  dexGame.input:press("select")
  dex:update(0)
  return dex.view
end)(), "option")
check("...with the cursor on the current mode", dex.optionIndex, 1)
check("moving to OLD and confirming changes the mode", (function()
  dexGame.input:press("down")
  dex:update(0)
  dexGame.input:press("a")
  dex:update(0)
  return dex:mode()
end)(), "OLD")
check("...and closes the OPTION screen", dex.view, "list")
check("START opens the SEARCH screen", (function()
  dexGame.input:press("start")
  dex:update(0)
  return dex.view
end)(), "search")
-- Pokedex_InitSearchScreen: TYPE1 starts on NORMAL and TYPE2 on "-----".
check("TYPE1 starts on NORMAL", dex:searchTypeName(1), "NORMAL")
check("TYPE2 starts blank", dex:searchTypeName(2), "-----")
-- Display names come from the type registry, while matching stays on the
-- stable type id.  Translating GRASS must still find a GRASS species.
dex.data.type_chart = { types = { GRASS = { name = "HERBE" } } }
dex.searchType[1] = 12 -- GRASS in SEARCH_TYPES
check("the search wheel draws the translated type name",
  dex:searchTypeName(1), "HERBE")
dexSave.pokedex.seen.BULBASAUR = true
dex:rebuild()
dex:beginSearch()
check("translated type display does not change search identity",
  #dex.searchResults, 1)
dex.data.type_chart = nil
dexSave.pokedex.seen.BULBASAUR = nil
dex.searchType[1] = 1
dex.searchResults = nil
dex.searchMessage = nil
dex.view = "search"
check("B leaves the SEARCH screen", (function()
  dexGame.input:press("b")
  dex:update(0)
  return dex.view
end)(), "list")
-- Back to NEW so the assertions below are unaffected.
dex.modeIndex = 1
dex:rebuild()

-- A only opens the entry for a mon that has been seen (Pokedex_UpdateMainScreen
-- returns early otherwise), and once open, left/right flips the two pages.
dexGame.input:press("a")
dex:update(0)
check("an unseen mon has no entry to open", dex.view, "list")
dexSave.pokedex.seen.BULBASAUR = true
dex:rebuild()
dex.index = 1
dexGame.input:press("a")
dex:update(0)
check("a seen mon opens", dex.view, "entry")
check("on page 1", dex.page, 1)

-- DexEntryScreen_ArrowCursorData: LEFT/RIGHT walk an arrow across PAGE, AREA,
-- CRY and PRNT, and A runs whichever it is parked on. This block used to press
-- RIGHT and expect the page to flip, which was the port taking a shortcut --
-- and that shortcut is exactly why AREA could never be opened.
check("the cursor starts on PAGE", dex.entryAction, 1)
dexGame.input:press("right")
dex:update(0)
check("RIGHT walks the cursor, it does not flip the page", dex.page, 1)
check("the cursor is on AREA", dex.entryAction, 2)
dexGame.input:press("a")
dex:update(0)
check("A on AREA opens the nest map", dex.view, "area")
dexGame.input:press("b")
dex:update(0)
check("B backs out of AREA to the entry", dex.view, "entry")
dexGame.input:press("left")
dex:update(0)
check("LEFT walks it back to PAGE", dex.entryAction, 1)
dexGame.input:press("a")
dex:update(0)
check("A on PAGE flips to 2", dex.page, 2)
dexGame.input:press("b")
dex:update(0)
check("B backs out to the listing", dex.view, "list")

-- ------------------------------------------------------------- QUIT / EXIT

-- The start menu's last row is the port's QUIT, and it asks before throwing
-- away everything since the last save.  NO is the default.
local quitSave = Save.newGame("GOLD")
local quitGame, quitInput = newGame(quitSave)
local returned = false
quitGame.returnToTitle = function() returned = true end
local quitMenu = StartMenu.new(quitGame, { save = quitSave })
quitMenu.list.index = #quitMenu.items
check("last row is QUIT", quitMenu.items[#quitMenu.items].value, "quit")
quitInput:press("a")
quitMenu:update(0)
check("QUIT asks first", quitMenu.phase, "confirm")
check("and defaults to NO", quitMenu.confirmChoice, 2)
check("nothing has happened yet", returned, false)
quitInput:press("a")
quitMenu:update(0)
check("NO backs out", quitMenu.phase, nil)
check("still nothing", returned, false)

quitInput:press("a")
quitMenu:update(0)
quitInput:press("up")
quitMenu:update(0)
check("up selects YES", quitMenu.confirmChoice, 1)
quitInput:press("a")
quitMenu:update(0)
check("YES returns to the title", returned, true)

-- B out of the confirmation is NO as well.
local backGame, backInput = newGame(quitSave)
backGame.returnToTitle = function() returned = "again" end
local backMenu = StartMenu.new(backGame, { save = quitSave })
backMenu.phase = "confirm"
backMenu.confirmChoice = 1
backInput:press("b")
backMenu:update(0)
check("B is NO", backMenu.phase, nil)
check("B ran nothing", returned, true)

-- EXIT GAME on the intro menu leaves through the host rather than the cart.
local exited = false
local exitMenuGame, exitMenuInput = newGame(nil)
local exitMenu = MainMenu.new(exitMenuGame, {
  hasSave = false, save = false,
  onExit = function() exited = true end,
})
exitMenu.list.index = #exitMenu.list.items
exitMenuInput:press("a")
exitMenu:update(0)
check("EXIT GAME quits", exited, true)

-- ----------------------------------------------------- scrolling OPTION

-- Twelve rows do not fit on an 18-row screen, so the screen scrolls: the
-- window only moves once the cursor would leave it.
local scrollGame, scrollInput = newGame(Save.newGame())
local scrollOptions = OptionsMenu.new(scrollGame, {
  options = Save.defaultOptions(),
})
check("starts unscrolled", scrollOptions.scroll, 0)
for _ = 1, 7 do
  scrollInput:press("down")
  scrollOptions:update(0)
end
check("cursor moved", scrollOptions.index, 8)
check("window followed by one", scrollOptions.scroll, 1)
scrollOptions.index = 1
scrollOptions:ensureVisible()
check("back to the top", scrollOptions.scroll, 0)

-- The port rows step their own shared module rather than a values list.
local function rowNamed(label)
  for i, row in ipairs(OptionsMenu.ROWS) do
    if row.label == label then return i, row end
  end
end
local speedRow = select(2, rowNamed("GAME SPEED"))
scrollOptions:cycle(speedRow, 1)
check("speed left NORMAL", scrollOptions.options.speed ~= 1, true)
local volRow = select(2, rowNamed("MUSIC VOL"))
scrollOptions:cycle(volRow, -1)
check("music volume stepped down", scrollOptions.options.musicVol, 6)
for _ = 1, 10 do scrollOptions:cycle(volRow, -1) end
check("and clamps at OFF rather than wrapping", scrollOptions.options.musicVol, 0)
local filterRow = select(2, rowNamed("MUSIC FILTER"))
scrollOptions:cycle(filterRow, 1)
check("filter steps to 1X", scrollOptions.options.musicFilter, 1)
for _ = 1, 3 do scrollOptions:cycle(filterRow, 1) end
check("and wraps back to OFF", scrollOptions.options.musicFilter, 0)

-- COLOR: the Gen 2 answer to the Gen 1 screen's COLORS row.  GBC is the
-- default because Gold IS a colour game -- the other rungs turn it off.
local GbcPalette = require("src.render.GbcPalette")
local colorRow = select(2, rowNamed("COLOR"))
check("COLOR is a row", colorRow ~= nil, true)
check("and it defaults to the cart's own colour",
  Save.DEFAULT_OPTIONS.color, "gbc")
-- COLOR no longer cycles in place (tests/engine/gen2_palette_picker_test.lua
-- covers the picker it opens instead, end to end); the ladder itself still
-- steps via the `2` hotkey (src/core/Game2.lua:hotkey), untouched here.
check("COLOR no longer cycles in place", colorRow.cycle, nil)
check("COLOR opens the picker instead", type(colorRow.activate), "function")
scrollOptions.options.color = "classic"
GbcPalette.setMode("classic")
check("CLASSIC is the only mode with a present pass",
  GbcPalette.presentColors() ~= nil, true)
GbcPalette.setMode("dmg")
check("DMG substitutes the hardware shades for any palette",
  GbcPalette.color({ { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 10, 11, 12 } },
    1)[1], 255)
GbcPalette.setMode("gbc")
check("GBC leaves a palette alone",
  GbcPalette.color({ { 1, 2, 3 }, { 4, 5, 6 }, { 7, 8, 9 }, { 10, 11, 12 } },
    1)[1], 1)
check("and has no present pass", GbcPalette.presentColors(), nil)

local zoomIndex, tiltIndex
for i, row in ipairs(OptionsMenu.ROWS) do
  if row.label == "ZOOM" then zoomIndex = i end
  if row.label == "TILT" then tiltIndex = i end
end
check("VOID FILL follows ZOOM", OptionsMenu.ROWS[zoomIndex + 1].label,
  "VOID FILL")
check("and TILT follows VOID FILL", OptionsMenu.ROWS[zoomIndex + 2].label,
  "TILT")
-- By sequence rather than by offset, so inserting a row in the display block
-- moves the whole run instead of breaking six separate index assertions.
do
  local run = { "TILT", "COLOR", "UI LETTERBOX", "SHADER FX",
                "SHADER FX 2", "VIDEO MODE", "SCREEN POS", "TOUCH PAD" }
  for at, want in ipairs(run) do
    check("display block order: " .. want,
      OptionsMenu.ROWS[tiltIndex + at - 1].label, want)
  end
end

local videoRow = select(2, rowNamed("VIDEO MODE"))
check("VIDEO MODE is a row", videoRow ~= nil, true)

local videoBuilt
for _, row in ipairs(scrollOptions.rows) do
  if row.key == "videoMode" then videoBuilt = row end
end
check("buildRows gives it id videoMode", videoBuilt and videoBuilt.id,
  "videoMode")

check("default video mode is windowed", Save.DEFAULT_OPTIONS.videoMode,
  "windowed")

scrollOptions.options.videoMode = "windowed"
scrollOptions:cycle(videoRow, 1)
check("right stores borderless, not the display string",
  scrollOptions.options.videoMode, "borderless")
scrollOptions:cycle(videoRow, 1)
check("right again stores windowed",
  scrollOptions.options.videoMode, "windowed")
scrollOptions:cycle(videoRow, -1)
check("left also toggles, stored as borderless",
  scrollOptions.options.videoMode, "borderless")
scrollOptions:cycle(videoRow, -1)
check("left toggles back to windowed",
  scrollOptions.options.videoMode, "windowed")

local voidRow = select(2, rowNamed("VOID FILL"))
check("VOID FILL is a row", voidRow ~= nil, true)
check("and it defaults to FADE", Save.DEFAULT_OPTIONS.voidFill, "fade")
scrollOptions.options.voidFill = "fade"
local BorderFill = require("src.world.gen2.BorderFill")
BorderFill.setVoidFill("fade")
scrollOptions:cycle(voidRow, 1)
check("right steps to WATER", scrollOptions.options.voidFill, "water")
check("and the live fill tracks it", BorderFill.voidFill, "water")
scrollOptions:cycle(voidRow, 1)
check("then TREES", scrollOptions.options.voidFill, "trees")
scrollOptions:cycle(voidRow, 1)
check("then BLACK", scrollOptions.options.voidFill, "black")
scrollOptions:cycle(voidRow, 1)
check("and wraps back to FADE", scrollOptions.options.voidFill, "fade")
check("FADE blanks the longer labels", voidRow.text(scrollOptions.options),
  "FADE ")
scrollOptions.options.voidFill = "water"
check("WATER fits the value column", voidRow.text(scrollOptions.options),
  "WATER")
BorderFill.setVoidFill("fade")

check("text reads WINDOWED", videoRow.text(scrollOptions.options), "WINDOWED")
scrollOptions.options.videoMode = "borderless"
check("text reads FULL, not BORDERLESS", videoRow.text(scrollOptions.options),
  "FULL")
for _, mode in ipairs({ "windowed", "borderless" }) do
  scrollOptions.options.videoMode = mode
  local text = videoRow.text(scrollOptions.options)
  check("value fits the 8-char column: " .. mode, #text <= 8, true)
end

-- ------------------------------------------------------------- name picker
--
-- NameMenuHeader's coordinates, which is the whole point of this screen: the
-- box, the label origin GetMenuTextStartCoord derives from its flags, and the
-- pic walk NamePlayer opens with.
local NamePick = require("src.ui.gen2.NamePick")
local pickInput = newInput()
local pickGame = {
  input = pickInput,
  data = {},
  stack = { push = function() end, pop = function() end, top = function() end },
}
local picked
local pick = NamePick.new(pickGame, {
  onDone = function(name) picked = name end,
})
check("five items: NEW NAME and Gold's four presets", #pick.items, 5)
check("NEW NAME first", pick.items[1], "NEW NAME")
check("then the PlayerNameArray order", pick.items[2] .. pick.items[5],
  "GOLDKARL")
check("default option 1 is NEW NAME", pick.cursor, 1)
check("the pic starts where Oak left it", pick.picX, 6)
-- MovePlayerPicRight is a blocking loop: no input until it lands on 13.
pickInput:press("down")
pick:update(0)
check("input is ignored while the pic walks", pick.cursor, 1)
-- The stub latches a press until something reads it, so drop it by hand --
-- otherwise it fires the instant the walk ends and the rest of this reads a
-- cursor one row further on than it looks.
pickInput.pressed = {}
for _ = 1, 20 do pick:update(0) end
check("and it stops at hlcoord 13", pick.picX, 13)
check("the menu is up once the walk is done", pick.slide, nil)
pickInput:press("down")
pick:update(0)
check("now the cursor moves", pick.cursor, 2)
pickInput:press("a")
pick:update(0)
check("a preset walks the pic back before answering", pick.slide, "out")
check("and answers nothing yet", picked, nil)
for _ = 1, 20 do pick:update(0) end
check("the pic returns to hlcoord 6", pick.picX, 6)
check("and the name is handed over", picked, "GOLD")
-- STATICMENU_DISABLE_B: there is no way out of this menu but choosing.
local pick2 = NamePick.new(pickGame, { onDone = function() picked = "B" end })
for _ = 1, 20 do pick2:update(0) end
pickInput:press("b")
pick2:update(0)
check("B does nothing", picked, "GOLD")

-- ============================================================= POKeGEAR
--
-- The radio's shows and the town map's cursor, both transcribed from
-- engine/pokegear/radio.asm and engine/pokegear/pokegear.asm.  The shows are
-- state machines with their own random rolls, so everything below seeds the
-- roll source and asserts the exact line sequence that comes out; the cursor
-- is a landmark INDEX walked between two limit registers, so everything below
-- asserts which landmark a d-pad press lands on.

local Pokegear = require("src.ui.gen2.Pokegear")

-- `call Random` yields one byte.  This hands back the listed bytes in order
-- and then starts the list again, so a test only has to name the rolls one
-- pass through a show actually spends.  It cycles rather than repeating the
-- last byte because the shows sample by rejection: a source stuck on one
-- value that every sampler rejects would never terminate.
local function rolls(...)
  local list = { ... }
  local index = 0
  return function()
    index = index % #list + 1
    return list[index]
  end
end

-- Oak's Pokemon Talk indexes the grass table by time of day (0 morn, 1 day,
-- 2 nite) and then by one of the middle three of the seven slots, so the
-- fixture makes the third slot of each block distinct: a wrong index shows up
-- as the wrong species rather than as no species.
local radioClasses = {}
for i = 1, 66 do radioClasses[i] = { name = "CLASS" .. i, trainer = "T" .. i } end

local radioData = {
  landmarks = { [2] = { name = "ROUTE 29" }, [46] = { name = "PALLET TOWN" } },
  mapLandmark = { ROUTE_29 = 2, PALLET_TOWN = 46 },
  grass = { ROUTE_29 = {
    [0] = { "RATTATA", "SENTRET", "LEDYBA", "PIDGEY", "PIDGEY", "PIDGEY",
            "PIDGEY" },
    [1] = { "RATTATA", "SENTRET", "SPINARAK", "PIDGEY", "PIDGEY", "PIDGEY",
            "PIDGEY" },
    [2] = { "RATTATA", "SENTRET", "HOOTHOOT", "PIDGEY", "PIDGEY", "PIDGEY",
            "PIDGEY" },
  } },
  species = { [16] = "PIDGEY" },
  caught = function(name) return name == "PIDGEY" end,
  dex = { PIDGEY = { kind = "TINY BIRD", lines = {
    "It usually hides", "in tall grass. Be-", "cause it dislikes",
    "fighting, it pro-", "tects itself by", "kicking up sand." } } },
  classes = radioClasses,
  -- CLASS2 stands in for PnP_HiddenPeople: the show must roll past it.
  hidden = { [2] = true },
  weekday = 1,
  luckyNumber = 42,
}

-- A copy with one field changed, so a test can vary the world without the
-- other tests seeing it.
local function radioDataWith(overrides)
  local copy = {}
  for key, value in pairs(radioData) do copy[key] = value end
  for key, value in pairs(overrides) do copy[key] = value end
  return copy
end

-- PrintRadioLine parks 100 frames on wRadioTextDelay and RadioScroll burns
-- them one per frame, so a line lands roughly every 102 steps.  Step until the
-- show has printed as many lines as the test wants, with a cap so a machine
-- that has stopped advancing fails instead of hanging.
local function runRadio(station, rng, lines, data)
  local radio = Pokegear.Radio.new({ data = data or radioData, rng = rng })
  radio:tune(station)
  for _ = 1, (lines + 2) * 200 do
    if #radio.log >= lines then break end
    radio:step()
  end
  return radio
end

local function checkLines(name, radio, want)
  check(name .. " line count", #radio.log >= #want, true)
  for index, line in ipairs(want) do
    check(("%s line %d"):format(name, index), radio.log[index], line)
  end
end

-- ------------------------------------------------- Oak's Pokemon Talk
--
-- Rolls per wild-mon segment: the route, the time of day, the grass slot.
-- Then one for OaksPKMNTalk8's adverb and one for OaksPKMNTalk9's adjective.
-- 0/1/2 picks OaksPKMNTalkRoutes' first route (ROUTE_29), the DAY block and
-- the first of the three legal slots; 0/0 picks the first adverb and the first
-- adjective.
local optRadio = runRadio("OAKS_POKEMON_TALK", rolls(0, 1, 2, 0, 0), 9)
checkLines("OPT", optRadio, {
  "MARY: PROF.OAK'S",
  "POKéMON TALK!",
  "With me, MARY!",
  "OAK: SPINARAK",
  "may be seen around",
  "ROUTE 29.",
  "MARY: SPINARAK's",
  "sweet and adorably",
  "cute.",
})

-- StartRadioStation reaches RadioChannelSongs with the station id still in
-- wCurRadioLine, so tuning is what starts the song.
check("OPT starts its own song", optRadio.music, "Music_ProfOaksPokemonTalk")

-- The rolls reject rather than wrap.  A route byte of 15 or more is thrown
-- away (`cp 15` after `and %11111`), a daytime of 3 is DARKNESS_F, and a slot
-- below 2 or of 5 and up is outside the middle three -- so this sequence
-- burns three rejects before landing on exactly the same line as above.
local optReject = runRadio("OAKS_POKEMON_TALK",
  rolls(20, 0, 3, 1, 7, 2, 0, 0), 4)
check("OPT rerolls a route past the table", optReject.log[4], "OAK: SPINARAK")

-- wOaksPKMNTalkSegmentCounter counts five wild-mon segments and then hands
-- over to the Pokemon Channel jingle, which is NOT a scrolled radio line: it
-- redraws the box and stamps two more strings into it with PlaceRadioString.
local optJingle = runRadio("OAKS_POKEMON_TALK", rolls(0, 1, 2, 0, 0), 37)
check("OPT runs five wild-mon segments", optJingle.log[33], "cute.")
check("then the jingle takes the box", optJingle.log[34], "POKéMON")
-- `hlcoord 9, 14` is eight cells right of the box's own first column.
check("and stamps the second at column 9", optJingle.log[35],
  "POKéMON POKéMON")
check("with the channel name below it", optJingle.log[36], "POKéMON Channel")
-- OaksPKMNTalk14 zeroes wNumRadioLinesPrinted and names OAKS_POKEMON_TALK_4,
-- so the show resumes at the wild mon rather than at MARY's intro.
check("then it drops back into the wild-mon segment", optJingle.log[37],
  "OAK: SPINARAK")

-- ------------------------------------------------------- Pokedex Show
--
-- A byte of 15 is species index 16 (PIDGEY, the only caught mon in the
-- fixture); the `inc c` after CheckCaughtMon is what makes the roll one-based.
local dexRadio = runRadio("POKEDEX_SHOW", rolls(15), 9)
checkLines("dex show", dexRadio, {
  "PIDGEY",
  "TINY BIRD",
  "It usually hides",
  "in tall grass. Be-",
  "cause it dislikes",
  "fighting, it pro-",
  "tects itself by",
  "kicking up sand.",
  "PIDGEY",
})

-- CheckCaughtMon rejects anything the player has not caught, so an uncaught
-- roll is spent and the loop goes round again.
local dexReject = runRadio("POKEDEX_SHOW", rolls(0, 15), 1)
check("dex show skips an uncaught roll", dexReject.log[1], "PIDGEY")

-- --------------------------------------- Pokemon Music / Let's All Sing
--
-- FernMonMusic2 names POKEMON_MUSIC_4, not a LETS_ALL_SING segment: Kanto's
-- station hands over to Johto's code after two lines and both DJs read the
-- same closing three.
local singRadio = runRadio("LETS_ALL_SING", rolls(0), 5,
  radioDataWith({ weekday = 2 }))
checkLines("let's all sing", singRadio, {
  "FERN: POKéMUSIC!",
  "With DJ FERN!",
  "Today's TUESDAY,",
  "so let us jam to",
  "POKéMON March!",
})
check("an even weekday marches", singRadio.music, "Music_PokemonMarch")
-- BenFernMusic7 is a bare `ret`: the show stops talking and plays out.  The
-- scroll after its last line still runs, so that line ends up on the box's
-- TOP row with nothing under it, and there it stays.
for _ = 1, 500 do singRadio:step() end
check("and the show ends there", singRadio.cur, "POKEMON_MUSIC_7")
check("nothing follows it", singRadio.log[6], nil)
check("and the last line stays up", singRadio.top, "POKéMON March!")
check("with the bottom row left clear", singRadio.bottom, "")

local benRadio = runRadio("POKEMON_MUSIC", rolls(0), 6,
  radioDataWith({ weekday = 3 }))
checkLines("pokemon music", benRadio, {
  "BEN: POKéMON MUSIC",
  "CHANNEL!",
  "It's me, DJ BEN!",
  "Today's WEDNESDAY,",
  "so chill out to",
  "POKéMON Lullaby!",
})
check("an odd weekday lulls", benRadio.music, "Music_PokemonLullaby")

-- ---------------------------------------------------- Lucky Number Show
--
-- LuckyNumberShow13's `call Random / and a` only branches on a rolled zero, so
-- anything else restarts the show and one byte in 256 gets the drag lines.
local luckyRadio = runRadio("LUCKY_CHANNEL", rolls(1), 14)
checkLines("lucky channel", luckyRadio, {
  "REED: Yeehaw! How",
  "y'all doin' now?",
  "Whether you're up",
  "or way down low,",
  "don't you miss the",
  "LUCKY NUMBER SHOW!",
  "This week's Lucky",
  "Number is 00042!",
  "I'll repeat that!",
  "This week's Lucky",
  "Number is 00042!",
  "Match it and go to",
  "the RADIO TOWER!",
  "REED: Yeehaw! How",
})
local luckyDrag = runRadio("LUCKY_CHANNEL", rolls(0), 16)
check("a rolled zero drags", luckyDrag.log[14], "…Repeating myself")
check("and drags again", luckyDrag.log[15], "gets to be a drag…")
check("before starting over", luckyDrag.log[16], "REED: Yeehaw! How")

-- ---------------------------------------------------- Places and People
--
-- PeoplePlaces3 rolls once: below 49 percent - 1 (123) takes the People
-- branch, anything else takes Places.  PeoplePlaces4 then rolls a trainer
-- class, PeoplePlaces5 an adjective, then a 4 percent (10) restart chance,
-- then the People/Places coin again.
local pnpPeople = runRadio("PLACES_AND_PEOPLE", rolls(0), 6)
checkLines("places and people", pnpPeople, {
  "PLACES AND PEOPLE!",
  "Brought to you by",
  "me, DJ LILY!",
  "CLASS1 T1",
  "is cute.",
  -- A zero is under the 4 percent mark, so the show restarts from its intro.
  "PLACES AND PEOPLE!",
})
-- PnP_HiddenPeople is a rejection list, not a skip: the roll is spent and
-- another one is taken.  A byte of 1 asks for class 2, which the fixture
-- hides, so the show falls through to the next roll.
local pnpHidden = runRadio("PLACES_AND_PEOPLE", rolls(0, 1, 0), 4)
check("a hidden class is rerolled", pnpHidden.log[4], "CLASS1 T1")
-- 200 is over the People threshold, so DJ LILY talks about a place instead.
local pnpPlaces = runRadio("PLACES_AND_PEOPLE", rolls(200, 0, 5, 20, 20), 6)
check("a high roll takes the Places branch", pnpPlaces.log[4], "PALLET TOWN")
check("with its own adjective", pnpPlaces.log[5], "is somewhat bold.")
-- 20 clears the 4 percent restart and then falls under the People threshold;
-- the class roll wraps back to 200, which is past the sixty-six classes and
-- so is spent on nothing before 0 lands on the first one.
check("and hands back to People", pnpPlaces.log[6], "CLASS1 T1")

-- --------------------------------------------------------- Rocket Radio
--
-- Ten fixed lines, nothing rolled, and RocketRadio10 names ROCKET_RADIO so it
-- runs round again.
local rocketRadio = runRadio("ROCKET_RADIO", rolls(0), 11)
checkLines("rocket radio", rocketRadio, {
  "… …Ahem, we are",
  "TEAM ROCKET!",
  "After three years",
  "of preparation, we",
  "have risen again",
  "from the ashes!",
  "GIOVANNI! Can you",
  "hear? We did it!",
  "Where is our Boss?",
  "Is he listening?",
  "… …Ahem, we are",
})
check("rocket radio plays the overture", rocketRadio.music,
  "Music_RocketTheme")

-- PlayRadioShow forces ROCKET_RADIO over any station id below
-- POKE_FLUTE_RADIO while the tower is occupied and the player is in Johto.
local takeover = Pokegear.Radio.new({
  data = radioDataWith({ rocketsInRadioTower = true, inJohto = true }),
  rng = rolls(0),
})
takeover:tune("OAKS_POKEMON_TALK")
takeover:step()
check("Team Rocket broadcasts on every station", takeover.cur ~= nil, true)
check("and it is their script that runs", takeover.log[1], "… …Ahem, we are")
-- The override compares the station id, and every mid-show segment is $0a or
-- above, so a show already running is never interrupted mid-sentence.
local midShow = Pokegear.Radio.new({
  data = radioDataWith({ rocketsInRadioTower = true, inJohto = true }),
  rng = rolls(0, 1, 2, 0, 0),
})
midShow:tune("OAKS_POKEMON_TALK")
midShow.cur = "OAKS_POKEMON_TALK_4"
midShow:step()
check("a show mid-sentence is left alone", midShow.log[1], "OAK: SPINARAK")

-- ------------------------------------------- the three music stations
--
-- PokeFluteRadio, UnownRadio and EvolutionRadio set wNumRadioLinesPrinted to 1
-- and return: they start a song and never print a word.
for _, station in ipairs({ "POKE_FLUTE_RADIO", "UNOWN_RADIO",
  "EVOLUTION_RADIO" }) do
  local music = Pokegear.Radio.new({ data = radioData, rng = rolls(0) })
  music:tune(station)
  for _ = 1, 1000 do music:step() end
  check(station .. " says nothing", #music.log, 0)
  check(station .. " still plays", music.music ~= nil, true)
end

-- --------------------------------------------------------- the scroll
--
-- PrintRadioLine fills the box's top row first and its bottom row second;
-- from the third line on, CopyBottomLineToTopLine moves the previous line up.
local scroll = Pokegear.Radio.new({ data = radioData, rng = rolls(1) })
scroll:tune("LUCKY_CHANNEL")
scroll:step()
check("the first line lands on the top row", scroll.top, "REED: Yeehaw! How")
check("with nothing under it", scroll.bottom, "")
check("and 100 frames on the clock", scroll.delay, 100)
-- RadioScroll decrements before it tests, so the 100 frames are spent over
-- the next 100 steps and the handover happens on the step after that.
for _ = 1, 101 do scroll:step() end
check("the delay has to run out first", #scroll.log, 1)
scroll:step()
check("then the second line lands on the bottom row", scroll.bottom,
  "y'all doin' now?")
check("and the first is still above it", scroll.top, "REED: Yeehaw! How")
for _ = 1, 103 do scroll:step() end
check("the third line scrolls the second up", scroll.top, "y'all doin' now?")
check("and takes the bottom row itself", scroll.bottom, "Whether you're up")

-- ---------------------------------------------------------- the tuner
--
-- RadioChannels is eight knob positions, each with its own test.  A position
-- whose test fails is not a station: NoRadioStation wipes the name and plays
-- nothing.
local gearLandmarks = { landmarks = {}, order = {} }
for _, row in ipairs({
  { "LANDMARK_NEW_BARK_TOWN", 1, 140, 100 },
  { "LANDMARK_ROUTE_29", 2, 128, 100 },
  { "LANDMARK_RUINS_OF_ALPH", 9, 76, 76 },
  { "LANDMARK_LAKE_OF_RAGE", 37, 100, 20 },
  { "LANDMARK_SILVER_CAVE", 45, 20, 20 },
  { "LANDMARK_PALLET_TOWN", 46, 60, 100 },
  { "LANDMARK_VICTORY_ROAD", 87, 30, 40 },
  { "LANDMARK_ROUTE_28", 93, 20, 30 },
  { "LANDMARK_FAST_SHIP", 94, 80, 80 },
}) do
  gearLandmarks.landmarks[row[1]] =
    { id = row[1], index = row[2], x = row[3], y = row[4], name = row[1] }
  gearLandmarks.order[row[2] + 1] = row[1]
end

local function newGear(opts)
  opts = opts or {}
  local save = opts.save or {}
  save.pokegearFlags = save.pokegearFlags
    or { map = true, radio = true, phone = true }
  local gearGame = newGame(save)
  return Pokegear.new(gearGame, {
    save = save,
    landmarks = gearLandmarks,
    currentLandmark = opts.landmark or "LANDMARK_NEW_BARK_TOWN",
    clock = opts.clock,
  })
end

-- Standing in Johto in the afternoon: the first three frequencies air and the
-- Kanto half of the dial is dead.
local johtoGear = newGear({ clock = { hour = 14, minute = 0, weekday = 1 } })
local johtoDial = johtoGear:stations()
check("the dial is eight frequencies", #johtoDial, 8)
check("04.5 is Oak's talk in the afternoon", johtoDial[1].station,
  "OAKS_POKEMON_TALK")
check("07.5 is the music channel", johtoDial[2].station, "POKEMON_MUSIC")
check("08.5 is the Lucky Channel", johtoDial[3].station, "LUCKY_CHANNEL")
check("13.5 needs the Ruins of Alph", johtoDial[4].station, nil)
check("16.5 is Kanto's", johtoDial[5].station, nil)
check("and the tuner still stops there", johtoDial[5].frequency, "16.5")

-- .PKMNTalkAndPokedexShow reads wTimeOfDay: MORN, and only MORN, swaps the
-- talk out for the Pokedex Show.
local mornGear = newGear({ clock = { hour = 7, minute = 0, weekday = 1 } })
check("04.5 is the Pokedex Show in the morning",
  mornGear:stations()[1].station, "POKEDEX_SHOW")

-- .RuinsOfAlphRadio is the one station that wants a single landmark.
local ruinsGear = newGear({ landmark = "LANDMARK_RUINS_OF_ALPH",
  clock = { hour = 14, minute = 0, weekday = 1 } })
check("13.5 airs in the Ruins of Alph", ruinsGear:stations()[4].station,
  "UNOWN_RADIO")

-- Kanto: the Johto half goes quiet and Places & People takes over.  The POKe
-- FLUTE station also wants the EXPN card.
local kantoGear = newGear({ landmark = "LANDMARK_PALLET_TOWN",
  clock = { hour = 14, minute = 0, weekday = 1 } })
local kantoDial = kantoGear:stations()
check("04.5 is silent in Kanto", kantoDial[1].station, nil)
check("16.5 is Places & People", kantoDial[5].station, "PLACES_AND_PEOPLE")
check("18.5 is Let's All Sing", kantoDial[6].station, "LETS_ALL_SING")
check("20.0 wants the EXPN card", kantoDial[7].station, nil)
local expnGear = newGear({ landmark = "LANDMARK_PALLET_TOWN",
  save = { pokegearFlags = { map = true, radio = true, phone = true,
    expn = true } },
  clock = { hour = 14, minute = 0, weekday = 1 } })
check("and airs with it", expnGear:stations()[7].station, "POKE_FLUTE_RADIO")

-- .EvolutionRadio wants STATUSFLAGS_ROCKET_SIGNAL_F.
-- pokegold constants/engine_flags.asm
local rageGear = newGear({ landmark = "LANDMARK_LAKE_OF_RAGE",
  save = { engineFlags = { [14] = true } },
  clock = { hour = 14, minute = 0, weekday = 1 } })
check("20.5 airs by the Lake of Rage", rageGear:stations()[8].station,
  "EVOLUTION_RADIO")
check("but not without the signal", johtoDial[8].station, nil)

-- LoadStation_RocketRadio hands the tuner LetsAllSingName, and
-- LoadStation_EvolutionRadio hands it UnownStationName: two stations really do
-- broadcast under another one's name.
check("Rocket Radio wears Let's All Sing's name",
  Pokegear.STATION_NAMES.ROCKET_RADIO, "Let's All Sing!")
check("the evolution station wears the Unown one",
  Pokegear.STATION_NAMES.EVOLUTION_RADIO, "?????")

-- .InJohto counts the S.S. Aqua as Johto even though LANDMARK_FAST_SHIP sits
-- past every Kanto landmark.
check("the S.S. Aqua is Johto",
  newGear({ landmark = "LANDMARK_FAST_SHIP" }):region(), "johto")

-- ----------------------------------------------------- the map cursor
--
-- PokegearMap_JohtoMap / PokegearMap_KantoMap walk the cursor by landmark
-- INDEX between two limits: d, the last landmark of the region, and e, the
-- first.  Up steps forward and wraps to e; down steps back and wraps to d.
local mapInput
local function newMapGear(opts)
  local gear = newGear(opts)
  mapInput = gear.game.input
  return gear
end

local johtoMap = newMapGear({})
check("Johto's limits are Silver Cave and New Bark",
  select(1, johtoMap:cursorLimits()), 0x2d)
check("with New Bark as the first", select(2, johtoMap:cursorLimits()), 0x01)
check("and the cursor starts on the player", johtoMap:mapCursorIndex(), 1)
mapInput:press("up")
johtoMap:moveMapCursor(mapInput)
check("up steps to the next landmark", johtoMap:mapCursorIndex(), 2)
mapInput:press("down")
johtoMap:moveMapCursor(mapInput)
check("down steps back", johtoMap:mapCursorIndex(), 1)
-- `cp e / jr nz` then the shared `dec [hl]`: only the first landmark wraps,
-- and it wraps to d + 1 so the decrement lands on d itself.
mapInput:press("down")
johtoMap:moveMapCursor(mapInput)
check("down from the first wraps to the last", johtoMap:mapCursorIndex(), 0x2d)
check("which is Silver Cave", johtoMap:mapLandmark().id, "LANDMARK_SILVER_CAVE")
-- `cp d / jr c` then the shared `inc [hl]`: at or past d the cursor is slammed
-- to e - 1 so the increment lands on e.
mapInput:press("up")
johtoMap:moveMapCursor(mapInput)
check("up from the last wraps to the first", johtoMap:mapCursorIndex(), 0x01)

-- The player icon never moves: PokegearMap_UpdateCursorPosition writes the
-- cursor's landmark, and PokegearMap_InitPlayerIcon wrote the player's once.
johtoMap.mapCursor = 0x2d
check("the icon stays where the player is", johtoMap:playerLandmark().id,
  "LANDMARK_NEW_BARK_TOWN")
check("while the name box follows the cursor", johtoMap:mapLandmark().id,
  "LANDMARK_SILVER_CAVE")
-- The landmark macro stores x + 8 / y + 16 because the sprite lives in OAM;
-- the extractor takes both offsets back off, so the cursor sits on the
-- landmark's own screen coordinates.
check("and the cursor sprite sits on the landmark's own x",
  johtoMap:mapLandmark().x, 20)

-- TownMap_GetKantoLandmarkLimits: before the Hall of Fame the Kanto map only
-- walks Victory Road to Route 28, the seven landmarks on the road to Indigo.
local kantoMap = newMapGear({ landmark = "LANDMARK_PALLET_TOWN" })
check("Kanto's last landmark is Route 28",
  select(1, kantoMap:cursorLimits()), 0x5d)
check("and its first is Victory Road without the Hall of Fame",
  select(2, kantoMap:cursorLimits()), 0x57)
kantoMap.mapCursor = 0x57
mapInput:press("down")
kantoMap:moveMapCursor(mapInput)
check("down from Victory Road wraps to Route 28", kantoMap:mapCursorIndex(),
  0x5d)
mapInput:press("up")
kantoMap:moveMapCursor(mapInput)
check("and up wraps back", kantoMap:mapCursorIndex(), 0x57)

local hofMap = newMapGear({ landmark = "LANDMARK_PALLET_TOWN",
  save = { flags = { HALL_OF_FAME = true } } })
check("the Hall of Fame opens Kanto back to Pallet Town",
  select(2, hofMap:cursorLimits()), 0x2e)
mapInput:press("down")
hofMap:moveMapCursor(mapInput)
check("so down from Pallet Town wraps to Route 28", hofMap:mapCursorIndex(),
  0x5d)

-- Left and right are not cursor moves on this card at all: PokegearMap_
-- ContinueMap pages the gear with them.  .right takes the PHONE if it is
-- owned and the RADIO if it is not; .left always takes the CLOCK.
local pageMap = newMapGear({})
for index, card in ipairs(pageMap.cards) do
  if card.id == "map" then pageMap.cardIndex = index end
end
mapInput:press("right")
pageMap:moveMapCursor(mapInput)
check("right pages to the phone", pageMap:card().id, "phone")
mapInput:press("left")
pageMap.cardIndex = 2
pageMap:moveMapCursor(mapInput)
check("left pages to the clock", pageMap:card().id, "clock")
local noPhone = newMapGear({
  save = { pokegearFlags = { map = true, radio = true } } })
mapInput:press("right")
noPhone:moveMapCursor(mapInput)
check("without a phone, right pages to the radio", noPhone:card().id, "radio")

-- --------------------------------------------------- the knob, in the card
--
-- AnimateTuningKnob.TuningKnob winds wRadioTuningKnob up towards 80 and down
-- towards 0 and stops dead at either end -- `ret z` at the bottom and
-- `ret nc` at the top.  It does not wrap, so neither does the port's row.
local knobGear = newMapGear({ clock = { hour = 14, minute = 0, weekday = 1 } })
for index, card in ipairs(knobGear.cards) do
  if card.id == "radio" then knobGear.cardIndex = index end
end
knobGear.mode = "card"
knobGear:update(0)
check("entering the card resolves the frequency", knobGear.radioShow,
  "OAKS_POKEMON_TALK")
mapInput:press("up")
knobGear:update(0)
check("up winds the knob on", knobGear.station, 2)
check("and retunes", knobGear.radioShow, "POKEMON_MUSIC")
mapInput:press("down")
knobGear:update(0)
mapInput:press("down")
knobGear:update(0)
check("down stops dead at the bottom of the dial", knobGear.station, 1)
knobGear.station = #Pokegear.RADIO_CHANNELS
mapInput:press("up")
knobGear:update(0)
check("and up stops dead at the top", knobGear.station,
  #Pokegear.RADIO_CHANNELS)

-- The show only advances while the card is up, and B hands the map's music
-- back (ExitPokegearRadio_HandleMusic) and throws the machine away.
knobGear.station = 1
knobGear:tuneRadio()
for _ = 1, 300 do knobGear:update(0) end
check("the show runs while the card is up", #knobGear.radio.log >= 2, true)
mapInput:press("b")
knobGear:update(0)
check("and B leaves the card", knobGear.mode, "strip")
check("taking the show with it", knobGear.radio, nil)

-- ============================================================== POKeMART
--
-- engine/items/mart.asm: StandardMart's jumptable loop, the buy list, the
-- quantity selector's wraps and clamps, and SellMenu's half price.  What the
-- screen LOOKS like is what tests/drivers/gold_menu_shots.lua is for; this
-- asserts the state machine and the arithmetic a player would notice.
local MartMenu = require("src.ui.gen2.MartMenu")

local martItems = {
  POTION = { id = "POTION", name = "POTION", pocket = "ITEM", index = 18,
    price = 300, canToss = true, description = "Restores HP\nby 20." },
  ANTIDOTE = { id = "ANTIDOTE", name = "ANTIDOTE", pocket = "ITEM", index = 19,
    price = 100, canToss = true },
  NUGGET = { id = "NUGGET", name = "NUGGET", pocket = "ITEM", index = 36,
    price = 10000, canToss = true },
  -- A TM carries the move it teaches; the SELL pack must hand it to the
  -- mart rather than opening the teach party (issue #1243).
  TM_HEADBUTT = { id = "TM_HEADBUTT", name = "TM02", pocket = "TM_HM",
    index = 234, price = 2000, canToss = true, teaches = "HEADBUTT",
    tmNumber = 2 },
  -- Every KEY ITEM carries CANT_TOSS, which is the flag SellMenu's
  -- _CheckTossableItem actually refuses on.
  BICYCLE = { id = "BICYCLE", name = "BICYCLE", pocket = "KEY_ITEM", index = 7,
    price = 0, canToss = false },
}
-- The shape data/generated/marts.lua will have: `lists` is a 1-based array in
-- MART_* order and `bargain` is BargainShopData's own item/price rows.
local martData = {
  lists = { { "POTION", "ANTIDOTE" } }, -- MART_CHERRYGROVE
  bargain = { { item = "NUGGET", price = 4500 } },
}

local function newMart(save, opts)
  local game, input = newGame(save)
  game.data.items = martItems
  opts = opts or {}
  opts.save = save
  opts.items = martItems
  opts.marts = martData
  local mart = MartMenu.new(game, opts)
  -- ../pokecrystal/home/print_text.asm:1
  local step = mart.update
  function mart:update(dt)
    local saved = input.wasPressed
    input.wasPressed = function() return false end
    for _ = 1, 600 do
      if not (self.typer and not self.typer:done()) then break end
      step(self, dt)
    end
    input.wasPressed = saved
    return step(self, dt)
  end
  return mart, input, game
end

-- GetMart: only an id below NUM_MARTS is a mart at all, and everything else
-- gets DefaultMart's two items.
check("a listed mart is its own shelf", #MartMenu.inventory(martData, 0), 2)
check("in the ROM's order", MartMenu.inventory(martData, 0)[1], "POTION")
check("an id past NUM_MARTS falls back to DefaultMart",
  MartMenu.inventory(martData, 200)[1], "POKE_BALL")
check("as does a mart id the table has no row for",
  MartMenu.inventory(martData, 5)[1], "POKE_BALL")
check("and no marts.lua at all is an empty shelf, not invented stock",
  #MartMenu.inventory(nil, 0), 0)

-- BuySell_MultiplyPrice, then Sell_HalvePrice on the PRODUCT: three of a
-- 15-unit item sells for 22, not for three times seven.
check("buying multiplies", MartMenu.buyPrice(300, 4), 1200)
check("selling halves the product, not the unit",
  MartMenu.sellPrice(15, 3), 22)
check("and a single item is simply half", MartMenu.sellPrice(300, 1), 150)

-- .HowMayIHelpYou prints and returns TOPMENU without waiting, so the welcome
-- line is still up under the BUY/SELL/QUIT menu.
local shopSave = Save.newGame()
shopSave.inventory = {}
local shop, shopInput = newMart(shopSave)
check("a standard mart opens on the top menu", shop.phase, "top")
check("with the welcome line under it", shop.topLines[1], "Welcome! How may I")
check("BUY is the default option", shop.topIndex, 1)

shopInput:press("a")
shop:update(0)
check("BUY opens the list", shop.phase, "buy")
check("the shelf is the mart's", #shop.entries, 2)
check("priced out of ItemAttributes", shop.entries[1].price, 300)
check("CANCEL sits one past the last row", shop:total(), 3)
shop.index = shop:total()
check("and is not an item", shop:isCancel(), true)

-- A on CANCEL is B (.a_button treats a -1 selection as a cancel), and BuyMenu
-- returns into .AnythingElse rather than straight out of the shop.
shopInput:press("a")
shop:update(0)
check("CANCEL leaves the list", shop.phase, "top")
check("with the ask-more line", shop.topLines[1], "Can I do anything")

-- Back into BUY, and buy two POTIONs.
shopInput:press("a")
shop:update(0)
check("the cursor is back at the top of the list", shop.index, 1)
shopInput:press("a")
shop:update(0)
check("A on a row opens the quantity selector", shop.phase, "buyQuantity")
check("starting at one", shop.qty, 1)
check("with MAX_ITEM_STACK as the ceiling", shop.qtyMax, 99)

-- BuySellToss_InterpretJoypad: up/down wrap, left/right step ten and clamp.
shopInput:press("down")
shop:update(0)
check("down from one wraps to the ceiling", shop.qty, 99)
shopInput:press("right")
shop:update(0)
check("right at the ceiling clamps", shop.qty, 99)
shopInput:press("up")
shop:update(0)
check("up from the ceiling wraps to one", shop.qty, 1)
shopInput:press("right")
shop:update(0)
check("right steps ten", shop.qty, 11)
shopInput:press("left")
shop:update(0)
check("left steps ten back", shop.qty, 1)
shopInput:press("left")
shop:update(0)
check("and never below one", shop.qty, 1)
shopInput:press("up")
shop:update(0)
check("up steps one", shop.qty, 2)

shopInput:press("a")
shop:update(0)
check("A asks to confirm", shop.confirm ~= nil, true)
check("the price line names the quantity and the item",
  shop.confirm.pages[1][1], "2 POTION(S)")
check("and the total", shop.confirm.pages[1][2], "will be \xc2\xa5600.")
check("YES is the default", shop.confirm.choice, 1)
shopInput:press("a")
shop:update(0)
check("the potions arrive", shopSave.inventory.POTION, 2)
check("the money leaves", shopSave.player.money, 2400)
check("and the clerk thanks you", shop.message.pages[1][1], "Here you are.")
shopInput:press("a")
shop:update(0)
check("dismissing the thanks returns to the list", shop.phase, "buy")

-- NO backs out of the confirmation without spending anything.
shopInput:press("a")
shop:update(0)
shopInput:press("a")
shop:update(0)
shopInput:press("down")
shop:update(0)
check("down picks NO", shop.confirm.choice, 2)
shopInput:press("a")
shop:update(0)
check("NO buys nothing", shopSave.inventory.POTION, 2)
check("and spends nothing", shopSave.player.money, 2400)
check("and drops back into the list", shop.phase, "buy")

-- BuyMenuLoop compares money BEFORE it asks the bag for room, so a broke
-- player is told about the money and never about the PACK.
local brokeSave = Save.newGame()
brokeSave.inventory = {}
brokeSave.player.money = 100
local broke, brokeInput = newMart(brokeSave)
brokeInput:press("a") broke:update(0) -- BUY
brokeInput:press("a") broke:update(0) -- POTION
brokeInput:press("a") broke:update(0) -- quantity 1
brokeInput:press("a") broke:update(0) -- YES
check("a broke player is refused", broke.message.pages[1][1], "You don't have")
check("nothing is bought", brokeSave.inventory.POTION, nil)
check("and nothing is spent", brokeSave.player.money, 100)

-- ReceiveItem failing is the OTHER refusal: AddItemToInventory caps a slot at
-- 99, which Bag.add already enforces.
local fullSave = Save.newGame()
fullSave.inventory = { POTION = 99 }
local full, fullInput = newMart(fullSave)
fullInput:press("a") full:update(0)
fullInput:press("a") full:update(0)
fullInput:press("a") full:update(0)
fullInput:press("a") full:update(0)
check("a full pocket is refused", full.message.pages[1][1], "You can't carry")
check("the stack stays at its cap", fullSave.inventory.POTION, 99)
check("and the money is untouched", fullSave.player.money, 3000)

-- .Quit: the come-again line, then STANDARDMART_EXIT.
local byeSave = Save.newGame()
local bye, byeInput = newMart(byeSave)
local byeClosed = false
bye.onClose = function() byeClosed = true end
byeInput:press("down") bye:update(0)
byeInput:press("down") bye:update(0)
check("QUIT is the third row", bye.topIndex, 3)
byeInput:press("a") bye:update(0)
check("it says goodbye first", bye.message.pages[1][1], "Please come again!")
check("and has not closed yet", byeClosed, false)
byeInput:press("a") bye:update(0)
check("then the shop closes", byeClosed, true)
-- B out of the top menu is the same exit (VerticalMenu returns carry).
local bye2, bye2Input = newMart(Save.newGame())
bye2Input:press("b") bye2:update(0)
check("B quits too", bye2.phase, "outro")

-- MenuHeader_Buy shows four entries at a time and .d_up refuses to move at
-- scroll zero: the buy list does NOT wrap the way the PACK's does, and its
-- scroll ceiling leaves room for the CANCEL row.
local longData = {
  lists = { { "POTION", "ANTIDOTE", "POTION", "ANTIDOTE", "POTION",
    "ANTIDOTE" } },
}
local longGame, longInput = newGame(Save.newGame())
longGame.data.items = martItems
local long = MartMenu.new(longGame, { save = longGame.save, items = martItems,
  marts = longData })
longInput:press("a") long:update(0)
check("a six-item shelf plus CANCEL", long:total(), 7)
check("starts unscrolled", long.scroll, 0)
longInput:press("up") long:update(0)
check("up at the top does nothing", long.index, 1)
for _ = 1, 4 do longInput:press("down") long:update(0) end
check("the cursor walked", long.index, 5)
check("and the window followed by one", long.scroll, 1)
for _ = 1, 5 do longInput:press("down") long:update(0) end
check("down stops on CANCEL rather than wrapping", long.index, 7)
check("with the window at its ceiling", long.scroll, 3)

-- ------------------------------------------------------------------ SELL
local sellSave = Save.newGame()
sellSave.inventory = { POTION = 5, BICYCLE = 1, NUGGET = 1 }
sellSave.player.money = 1000
local sell, sellInput = newMart(sellSave)
sellInput:press("down") sell:update(0)
sellInput:press("a") sell:update(0)
check("SELL opens the PACK", sell.phase, "sell")
check("and the PACK is real", sell.pack ~= nil, true)

-- _CheckTossableItem is the gate: a CANT_TOSS item gets MartCantBuyText and
-- never reaches a price.
sell:offerToSell("BICYCLE", 1)
check("a key item is refused", sell.message.pages[1][1], "Sorry, I can't buy")
check("and no quantity is asked for", sell.phase, "sell")
sellInput:press("a") sell:update(0)
-- Nothing in stock is not a sale either.
sell:offerToSell("POTION", 0)
check("selling none of something is refused too",
  sell.message.pages[1][1], "Sorry, I can't buy")
sellInput:press("a") sell:update(0)

sell:offerToSell("POTION", 5)
check("a sellable item asks how many", sell.phase, "sellQuantity")
check("the ceiling is what you hold", sell.qtyMax, 5)
sellInput:press("right") sell:update(0)
check("right clamps to what you hold", sell.qty, 5)
sellInput:press("up") sell:update(0)
check("up from the ceiling wraps to one", sell.qty, 1)
sellInput:press("up") sell:update(0)
check("and up steps one", sell.qty, 2)

sellInput:press("a") sell:update(0)
check("the offer is a page of its own", sell.confirm.pages[1][1],
  "I can pay you")
check("half of two potions", sell.confirm.pages[1][2], "\xc2\xa5300.")
check("and the question is the next page", #sell.confirm.pages, 2)
sellInput:press("a") sell:update(0)
check("which the YES/NO box sits on", sell.confirm.page, 2)
check("still nothing sold", sellSave.inventory.POTION, 5)
sellInput:press("a") sell:update(0)
check("YES takes the potions", sellSave.inventory.POTION, 3)
check("and pays for them", sellSave.player.money, 1300)
check("with a receipt", sell.message.pages[1][1], "Got \xc2\xa5300 for")

-- GiveMoney clamps at MaxMoney; nothing can push a wallet past 999999.
sellInput:press("a") sell:update(0)
sellSave.player.money = 999900
sell:offerToSell("NUGGET", 1)
sellInput:press("a") sell:update(0) -- confirm at quantity 1
sellInput:press("a") sell:update(0) -- page 2
sellInput:press("a") sell:update(0) -- YES
check("the wallet clamps at MAX_MONEY", sellSave.player.money, 999999)
check("and the nugget is gone", sellSave.inventory.NUGGET, nil)

-- A TM is not a key item: DepositSellPack's jumptable is four ScrollingMenus
-- and has no teach arm, so picking a TM from the SELL pack must ask "How
-- many?" and price it at half of its ItemAttributes price -- never open the
-- teach party (issue #1243).
local tmSave = Save.newGame()
tmSave.inventory = { TM_HEADBUTT = 1 }
tmSave.player.money = 0
local tm, tmInput = newMart(tmSave)
tmInput:press("down") tm:update(0)
tmInput:press("a") tm:update(0) -- SELL
check("SELL builds the pack", tm.pack ~= nil, true)
-- The PACK opens on the ITEM pocket; cross to TM/HM the way the player would.
tm.pack.pocketIndex = 4
tm.pack:rebuild()
check("the TM is the TM pocket's row", tm.pack.rows[1].id, "TM_HEADBUTT")
tmInput:press("a") tm:update(0)
check("picking a TM asks how many", tm.phase, "sellQuantity")
check("with no teach screen opened", #tm.game.stack._items, 0)
check("and no pack refusal printed", tm.pack.message, nil)
check("at the TM's own price", tm.qtyItem.price, 2000)
check("and the ceiling is what you hold", tm.qtyMax, 1)
tmInput:press("a") tm:update(0)
check("the offer prices half of the TM", tm.confirm.pages[1][2],
  "\xc2\xa51000.")
tmInput:press("a") tm:update(0) -- page 2
tmInput:press("a") tm:update(0) -- YES
check("the TM leaves the bag", tmSave.inventory.TM_HEADBUTT, nil)
check("and the money arrives", tmSave.player.money, 1000)

-- ------------------------------------------------- PlayTransactionSound
--
-- engine/items/mart.asm rings SFX_TRANSACTION in exactly two places, both of
-- them past every gate: BuyMenuLoop's .proceed (after the money and bag checks,
-- before TakeMoney) and the sell flow's own line after MartBoughtText.  So the
-- till is the money moving, and a refusal -- broke, full pocket, CANT_TOSS --
-- is silent.  Stubbing the instance method rather than Sound keeps this an
-- assertion about the call sites, which is what was missing.
local tillSave = Save.newGame()
tillSave.inventory = {}
tillSave.player.money = 3000
local till, tillInput = newMart(tillSave)
local rings = 0
till.playTransaction = function() rings = rings + 1 end
tillInput:press("a") till:update(0) -- BUY
tillInput:press("a") till:update(0) -- POTION
tillInput:press("a") till:update(0) -- quantity 1
check("nothing rings before the confirmation is answered", rings, 0)
tillInput:press("a") till:update(0) -- YES
check("a completed purchase rings the till", rings, 1)
tillInput:press("a") till:update(0) -- dismiss the thanks

-- Same shop, no money left: the refusal must not ring.
tillSave.player.money = 0
tillInput:press("a") till:update(0) -- POTION
tillInput:press("a") till:update(0) -- quantity 1
tillInput:press("a") till:update(0) -- YES
check("a refused purchase is silent", rings, 1)

local tillSellSave = Save.newGame()
tillSellSave.inventory = { POTION = 5, BICYCLE = 1 }
local tillSell, tillSellInput = newMart(tillSellSave)
local sellRings = 0
tillSell.playTransaction = function() sellRings = sellRings + 1 end
tillSellInput:press("down") tillSell:update(0)
tillSellInput:press("a") tillSell:update(0) -- SELL
tillSell:offerToSell("BICYCLE", 1)
check("a CANT_TOSS item is refused without a sound", sellRings, 0)
tillSellInput:press("a") tillSell:update(0) -- clear the refusal
tillSell:offerToSell("POTION", 2)
tillSellInput:press("a") tillSell:update(0) -- accept the quantity, still one
tillSellInput:press("a") tillSell:update(0) -- second page
tillSellInput:press("a") tillSell:update(0) -- YES
check("a completed sale rings it once", sellRings, 1)
check("and the potion really left", tillSellSave.inventory.POTION, 4)

-- --------------------------------------------------------- other dialogs
--
-- HerbShop / BargainShop / Pharmacist never show a top menu: intro, BuyMenu,
-- come again.
local herbSave = Save.newGame()
local herb, herbInput = newMart(herbSave, { martType = 1, martId = 33 })
check("the herb shop opens on its intro", herb.phase, "intro")
check("which is five pages", #herb.message.pages, 5)
check("starting with her greeting", herb.message.pages[1][1], "Hello, dear.")
for _ = 1, 5 do herbInput:press("a") herb:update(0) end
check("and lands in the buy list", herb.phase, "buy")
herbInput:press("b") herb:update(0)
check("B out of it goes straight to goodbye", herb.phase, "outro")
check("in her own words", herb.message.pages[1][1], "Come again, dear.")

-- BargainShop carries its own prices and sells one of each, tracked by
-- wBargainShopFlags.
local dealSave = Save.newGame()
dealSave.inventory = {}
dealSave.player.money = 5000
local deal, dealInput = newMart(dealSave, { martType = 2, martId = 0 })
for _ = 1, 3 do dealInput:press("a") deal:update(0) end
check("the bargain shop lands in its list", deal.phase, "buy")
check("with one row", #deal.entries, 1)
check("at BargainShopData's price, not the item's",
  deal.entries[1].price, 4500)
dealInput:press("a") deal:update(0)
check("and no quantity selector at all", deal.confirm ~= nil, true)
check("its price line is its own", deal.confirm.pages[1][1], "NUGGET costs")
dealInput:press("a") deal:update(0)
check("the nugget arrives", dealSave.inventory.NUGGET, 1)
check("the money leaves", dealSave.player.money, 500)
check("and the shelf remembers", dealSave.bargainShop.NUGGET, true)
dealInput:press("a") deal:update(0)
dealInput:press("a") deal:update(0)
check("a second try is sold out", deal.message.pages[1][1], "You bought that")
check("nothing else is bought", dealSave.inventory.NUGGET, 1)

-- Pharmacist wording, so a repointed text table cannot silently swap kinds.
local drugSave = Save.newGame()
local drug = newMart(drugSave, { martType = 3, martId = 4 })
check("the pharmacy has its own intro", drug.message.pages[1][1],
  "What's up? Need")
check("and its own goodbye", MartMenu.TEXTS.PHARMACY.comeAgain[1][1],
  "All right.")
check("and its own price wording",
  MartMenu.TEXTS.PHARMACY.finalPrice(1, "POTION", 300)[1][2],
  "will cost \xc2\xa5300.")

-- PRINTNUM_MONEY floats the ¥ in front of the first significant digit inside
-- a six-digit field, so the string is always seven tiles wide.
check("a small amount is space padded", MartMenu.moneyText(300),
  "   \xc2\xa5300")
check("a full field keeps every digit", MartMenu.moneyText(999999),
  "\xc2\xa5999999")
check("and zero still prints one digit", MartMenu.moneyText(0),
  "     \xc2\xa50")

-- --------------------------------------------------------------- mod screens
--
-- Every Gold screen is reached through a src/ui/Screens.lua id, so a mod
-- replaces one by registering a factory under that id, exactly the way it does
-- in the Gen 1 port.  Two properties are the whole contract:
--
--   * with nothing registered, an id resolves to EXACTLY the module the engine
--     used to require -- routing the pushes through Screens moved no screen,
--     and
--   * a registered record wins over that module.
--
-- The ids carry a "Gen2" prefix because a dozen Gold screens share a module
-- name with a Gen 1 screen (PartyMenu, StartMenu, TitleState, ...); the last
-- assertion below is that the two namespaces really are separate.
local Screens = require("src.ui.Screens")

-- A stack double.  Screens.push lands the instance on game.stack and nothing
-- here draws or updates it, so a bare collector is the whole surface needed.
local screenStack = { pushed = {} }
function screenStack:push(state) self.pushed[#self.pushed + 1] = state end
local screenGame = { data = {}, stack = screenStack }

-- The cache is module-global and this file is dofile'd alongside the rest of
-- the tier, so bracket the whole block with invalidations.
Screens.invalidate()

local registered = {}
for _, id in ipairs(Screens.GEN2_IDS) do registered[id] = true end
for _, id in ipairs({ "Gen2TitleState", "Gen2MainMenu", "Gen2OakSpeech",
    "Gen2StartMenu", "Gen2PartyMenu", "Gen2SummaryMenu", "Gen2PackMenu",
    "Gen2MartMenu", "Gen2BattleState", "Gen2EvolutionAnim", "Gen2PcMenu",
    "Gen2BoxMenu", "Gen2NamingScreen", "Gen2Pokegear" }) do
  check("the id list carries " .. id, registered[id], true)
end

for _, id in ipairs(Screens.GEN2_IDS) do
  -- "Gen2PartyMenu" -> src.ui.gen2.PartyMenu, the module the push sites used
  -- to require by hand.
  check("no mod: " .. id .. " resolves to its builtin",
    Screens.get(screenGame, id), require("src.ui.gen2." .. id:sub(5)))
end

-- A registry record wins, Screens.push stamps the id on the instance and lands
-- it on the stack -- the same three things tests/mod_ui_tests.lua asserts for
-- the Gen 1 ids.
Screens.invalidate()
screenGame.data.screens = {
  Gen2PartyMenu = { new = function() return { modded = "party" } end },
}
local moddedParty = Screens.push(screenGame, "Gen2PartyMenu", {})
check("a registered record replaces the Gold screen", moddedParty.modded,
  "party")
check("and the push stamps the id", moddedParty.screenId, "Gen2PartyMenu")
check("and lands the instance on the stack", screenStack.pushed[1],
  moddedParty)

-- Screens.build is that same resolution without the stack: the mart holds its
-- sell-mode PACK rather than pushing it (src/ui/gen2/MartMenu.lua enterSell),
-- and an override has to reach it there too.
Screens.invalidate()
screenGame.data.screens = {
  Gen2PackMenu = { new = function() return { modded = "pack" } end },
}
local builtPack = Screens.build(screenGame, "Gen2PackMenu", {})
check("build honours the same registry", builtPack.modded, "pack")
check("and stamps the id", builtPack.screenId, "Gen2PackMenu")
check("without touching the stack", #screenStack.pushed, 1)

-- The prefix is load bearing: replacing Gold's party menu must leave Red's
-- alone, and vice versa.
check("the Gen 1 id of the same name is untouched",
  Screens.get(screenGame, "PartyMenu"), require("src.ui.PartyMenu"))

-- The registry only reaches a screen the PUSH SITE looked up by id, and
-- src/core/Game2.lua is the one file that opens the boot cinema, the
-- START menu and every one of its submenus.  It used to require those modules
-- and push them by hand, which quietly exempted fourteen ids from the contract
-- above, so this reads the source and asserts the exemption is gone: no
-- `stack:push(<Module>.new(` for anything under src/ui/gen2/.  A textual check
-- is the honest one here -- constructing a Game2 needs love.
local game2Source = (function()
  local f = io.open("src/core/Game2.lua", "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end)()
check("Game2's source is readable", game2Source ~= nil, true)
if game2Source then
  check("it resolves screens through the registry",
    game2Source:find('require("src.ui.Screens")', 1, true) ~= nil, true)
  local handRolled = {}
  for name in game2Source:gmatch("stack:push%(([%w_]+)%.new%(") do
    -- TextBox is src/render, shared with the Gen 1 path and not a screen id.
    if name ~= "TextBox" then handRolled[#handRolled + 1] = name end
  end
  check("and pushes no Gold screen by hand", table.concat(handRolled, ","), "")
  for _, id in ipairs({ "Gen2CopyrightSplash", "Gen2GameFreakPresents",
      "Gen2GoldSilverIntro", "Gen2TitleState", "Gen2MainMenu", "Gen2OakSpeech",
      "Gen2OptionsMenu", "Gen2StartMenu", "Gen2PokedexMenu", "Gen2PartyMenu",
      "Gen2PackMenu", "Gen2Pokegear", "Gen2TrainerCard", "Gen2SaveMenu" }) do
    check("it opens " .. id .. " by id",
      game2Source:find('"' .. id .. '"', 1, true) ~= nil, true)
  end
end

screenGame.data.screens = nil
Screens.invalidate()

-- ---------------------------------------------------------------------------
-- The scripted static menu (src/ui/gen2/ScriptMenu.lua)
--
-- `loadmenu` then `verticalmenu` / `_2dmenu`.  Everything below is
-- GetMenuTextStartCoord and _2DMenu_'s own arithmetic.  The two headers are
-- transcribed from pokegold (the dept-store vending machine and Earl's
-- blackboard, the only `_2dmenu` in the game); the block at the end reads the
-- cache and asserts the extractor produced the same bytes, so a re-import that
-- reads a MenuHeader wrong fails here rather than by a menu drawn askew.
-- Wrapped in a function rather than a `do` block: the main chunk is close
-- to Lua's 200-local ceiling and these would push it over.
local function scriptMenuChecks()

  local ScriptMenu = require("src.ui.gen2.ScriptMenu")

  -- CeladonDeptStore6F's vending machine: `menu_coords 0, 2, 19, 11` with
  -- STATICMENU_CURSOR and no STATICMENU_NO_TOP_SPACING.  Border + 1 is (1,3),
  -- the missing NO_TOP_SPACING adds a row and the cursor a column: (2,4).
  local vending = {
    flags = 0x40, top = 2, left = 0, bottom = 11, right = 19, cursor = 1,
    dataFlags = 0x80,
    items = { "FRESH WATER", "SODA POP", "LEMONADE", "CANCEL" },
  }
  local x, y = ScriptMenu.startCoord(vending)
  check("a cursor menu with top spacing starts at x", x, 2)
  check("and at y", y, 4)

  -- YesNoMenuHeader sets both bits, which is what puts YES on the row straight
  -- under the border rather than one below it.
  local both = { top = 7, left = 14, dataFlags = 0x80 + 0x40 }
  local bx, by = ScriptMenu.startCoord(both)
  check("NO_TOP_SPACING keeps the first row against the border", by, 8)
  check("and the cursor column is still reserved", bx, 16)

  local none = { top = 0, left = 0, dataFlags = 0 }
  local nx, ny = ScriptMenu.startCoord(none)
  check("no cursor, no spacing flag: x", nx, 1)
  check("no cursor, no spacing flag: y", ny, 2)

  -- Earl's blackboard, the only `_2dmenu` in the game: `dn 3, 2` is three rows
  -- of two, spacing 5.
  local blackboard = {
    flags = 0x40, top = 0, left = 0, bottom = 8, right = 11, cursor = 1,
    dataFlags = 0x80,
    grid = { rows = 3, cols = 2, spacing = 5 },
    gridItems = { "PSN", "PAR", "SLP", "BRN", "FRZ", "QUIT" },
  }
  local items, rows, cols, spacing = ScriptMenu.layout(blackboard, "2d")
  check("the grid is three rows", rows, 3)
  check("of two columns", cols, 2)
  check("five tiles apart", spacing, 5)
  check("with six labels", #items, 6)
  -- A vertical menu reads the SAME header as n rows of one column, which is
  -- why the answer arithmetic below collapses to the row index for it.
  local _, vRows, vCols = ScriptMenu.layout(vending, "vertical")
  check("the vending machine is four rows", vRows, 4)
  check("of one column", vCols, 1)

  -- _2DMenu_: `(cursorY - 1) * cols + cursorX`, one-based both ways.
  check("2D row 1 col 1 is choice 1", ScriptMenu.choiceIndex(1, 1, 2), 1)
  check("row 1 col 2 is choice 2", ScriptMenu.choiceIndex(1, 2, 2), 2)
  check("row 3 col 2 is choice 6 (QUIT)", ScriptMenu.choiceIndex(3, 2, 2), 6)
  check("a one-column menu answers its row", ScriptMenu.choiceIndex(3, 1, 1), 3)

  -- The cursor and the labels: rows are TWO apart in both menus
  -- (PlaceMenuStrings and Place2DMenuItemStrings both `add hl, 2 * SCREEN_WIDTH`),
  -- columns `spacing` apart, and the cursor sits one column left of the label.
  local menu = ScriptMenu.new({ data = {} },
    { header = blackboard, style = "2d" })
  local ix, iy = menu:itemPosition(1)
  check("blackboard item 1 x", ix, 2)
  check("blackboard item 1 y", iy, 2)
  local jx, jy = menu:itemPosition(4) -- row 2, col 2 = BRN
  check("BRN sits a column across", jx, 7)
  check("and a row pair down", jy, 4)

  -- Pressing A answers the 1-based index; B answers 0, which is the cancel arm
  -- every `ifequal` ladder falls through to.
  local pressed = {}
  local input = {
    wasPressed = function(_, name) return pressed[name] == true end,
  }
  local picked
  local vm = ScriptMenu.new({ data = {}, input = input },
    { header = vending, style = "vertical",
      onChoose = function(index) picked = index end })
  check("the cursor opens on the header's own default", vm.row, 1)
  pressed = { down = true }
  vm:update(0)
  pressed = { down = true }
  vm:update(0)
  check("down twice moves two rows", vm.row, 3)
  pressed = { down = true }
  vm:update(0)
  pressed = { down = true }
  vm:update(0)
  check("and it stops at the last item rather than wrapping", vm.row, 4)
  pressed = { a = true }
  vm:update(0)
  check("A answers the 1-based index", picked, 4)
  pressed = { a = true }
  vm:update(0)
  check("and a finished menu answers once", picked, 4)

  picked = nil
  local bm = ScriptMenu.new({ data = {}, input = input },
    { header = vending, style = "vertical",
      onChoose = function(index) picked = index end })
  pressed = { b = true }
  bm:update(0)
  check("B answers 0, the cancel arm", picked, 0)

  -- STATICMENU_DISABLE_B: the one flag that makes a menu inescapable.
  picked = nil
  local locked = ScriptMenu.new({ data = {}, input = input },
    { header = { top = 0, left = 0, bottom = 5, right = 9, dataFlags = 0x81,
                 items = { "A", "B" } },
      style = "vertical", onChoose = function(index) picked = index end })
  pressed = { b = true }
  locked:update(0)
  check("STATICMENU_DISABLE_B ignores B", picked, nil)

  -- The same two headers, out of the cache this time.  Every `loadmenu` in
  -- the game must carry a header with items, or that site takes the cancel
  -- arm the way all seventeen of them did before the extractor followed the
  -- pointer.
  local cacheDir = os.getenv("GOLD_CACHE")
  if not cacheDir then
    cacheDir = (os.getenv("HOME") or "") ..
      "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local scriptsFile = loadfile(cacheDir .. "/data/generated/scripts.lua")
  if not scriptsFile then
    check("cache absent (SKIP extracted menu headers)", true, true)
    return
  end
  local sites, grids = 0, 0
  for key, cmds in pairs(scriptsFile()) do
    if type(cmds) == "table" and key ~= "movements" then
      for i, cmd in ipairs(cmds) do
        if cmd.op == "loadmenu" then
          sites = sites + 1
          local header = cmd.menu
          check(("%s: loadmenu carries a header"):format(key),
            type(header) == "table", true)
          local list = header and (header.items or header.gridItems)
          check(("%s: with at least one item"):format(key),
            type(list) == "table" and #list > 0, true)
          -- The command after it is what decides how the header is read, and
          -- it is always one of the two static menus.
          local next_ = cmds[i + 1] and cmds[i + 1].op
          check(("%s: opens a static menu"):format(key),
            next_ == "verticalmenu" or next_ == "_2dmenu", true)
          if next_ == "_2dmenu" then
            grids = grids + 1
            check(("%s: the 2D menu is 3x2"):format(key),
              header.grid and header.grid.rows == 3 and header.grid.cols == 2,
              true)
            check(("%s: five spacing"):format(key), header.grid.spacing, 5)
            check(("%s: last item is QUIT"):format(key),
              header.gridItems[#header.gridItems], "QUIT")
          end
        end
      end
    end
  end
  check("every loadmenu site in the cache was seen", sites, 17)
  -- Earl's blackboard is reached from two entry points, so its command is
  -- disassembled twice; the game has exactly one `_2dmenu` source site.
  check("and both entries into the one _2dmenu", grids, 2)
end

scriptMenuChecks()

-- --------------------------------------------------------- trainer card
--
-- TrainerCard_Page3_Joypad hands TrainerCard_Page2_3_AnimateBadges the exact
-- same TrainerCard_JohtoBadgesOAM pointer page 2 does, and that table's own
-- header word is `dw wJohtoBadges` -- so the "Kanto badges" page never once
-- reads wKantoBadges, it draws the Johto flags under Kanto's caption and gym
-- leader faces (which are themselves LeaderGFX2/BadgeGFX2, byte-identical
-- INCBINs of LeaderGFX/BadgeGFX).  drawBadgeSprites is exercised directly
-- with a stub sheet so the gating itself is proven, and the source is read
-- back the way tests/gen2_menus_test.lua already checks Game2, since
-- driving TrainerCard.new all the way to a styled draw needs real image
-- assets this harness does not have.
local function trainerCardChecks()
  local TrainerCard = require("src.ui.gen2.TrainerCard")

  local draws = 0
  local realDraw = love.graphics.draw
  love.graphics.draw = function(...) draws = draws + 1 end

  local stubSheet = {}
  stubSheet.__index = stubSheet
  function stubSheet:available() return true end
  function stubSheet:quad() return { getViewport = function() return 0, 0 end } end
  function stubSheet:image() return "stub" end

  local fake = {
    frames = 0,
    badges = setmetatable({}, stubSheet),
    gfx = { badgeOam = { {
      y = 0, x = 0, palette = 0, frames = { 0, 0, 0, 0, 0, 0, 0, 0 },
    } } },
  }

  -- BADGE_OAM_ORDER[1] is ZEPHYR: owned by name, Johto-keyed, is the shape
  -- player.badges takes.
  draws = 0
  TrainerCard.drawBadgeSprites(fake, { ZEPHYR = true }, TrainerCard.JOHTO_BADGES)
  check("a Johto-keyed owned table draws the badge", draws > 0, true)

  -- The bug this item fixes: page 3 used to look the badge up by Kanto names
  -- against a Kanto-keyed table, which the Johto-named OAM order can never
  -- match, so nothing ever drew.  Confirm that shape still draws nothing --
  -- it is the wrong table for either page now.
  draws = 0
  TrainerCard.drawBadgeSprites(fake, { BOULDER = true }, TrainerCard.KANTO_BADGES)
  check("a Kanto-keyed table never matches the Johto OAM order", draws, 0)

  love.graphics.draw = realDraw

  local source = (function()
    local f = io.open("src/ui/gen2/TrainerCard.lua", "r")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    return body
  end)()
  check("TrainerCard.lua is readable", source ~= nil, true)
  if source then
    check("page 3 draws badges off player.badges, not kantoBadges",
      source:find("self:drawBadges(JOHTO_BADGES, player.badges or {})",
        1, true) ~= nil, true)
    check("page 3 does not gate on player.kantoBadges",
      source:find("drawBadges(%w+, player%.kantoBadges") ~= nil, false)
    check("the plain fallback also reads player.badges unconditionally",
      source:find("local held = player.badges or {}", 1, true) ~= nil, true)
  end
end

trainerCardChecks()

-- ------------------------------------------------------------ Bag pockets
-- Gen 2's four pockets fill independently (item_data_constants.asm): a full
-- ITEM pocket does not keep a KEY_ITEM or an HM out.  Modelling one 20-slot
-- bag filled with TMs and key items refused HM07 WATERFALL at the Ice Path.
local function bagPocketChecks()
  local Bag = require("src.inventory.Bag")
  local data = { items = {
    POTION = { id = "POTION", pocket = "ITEM", index = 1 },
    POKE_BALL = { id = "POKE_BALL", pocket = "BALL", index = 2 },
    TM_ROCK_SMASH = { id = "TM_ROCK_SMASH", pocket = "TM_HM", index = 3 },
    HM_WATERFALL = { id = "HM_WATERFALL", pocket = "TM_HM", index = 4 },
    CARD_KEY = { id = "CARD_KEY", pocket = "KEY_ITEM", index = 5 },
  } }
  -- Fill the ITEM pocket to its cap with 20 distinct junk ids.
  local save = { inventory = {} }
  for i = 1, 20 do
    local id = "JUNK_" .. i
    data.items[id] = { id = id, pocket = "ITEM", index = 100 + i }
    save.inventory[id] = 1
  end
  check("ITEM pocket at cap", Bag.slots(save, data, "ITEM"), 20)
  check("a full ITEM pocket refuses another ITEM",
    Bag.add(save, "POTION", 1, data), false)
  check("but still takes a BALL",
    Bag.add(save, "POKE_BALL", 5, data), true)
  check("and a KEY_ITEM", Bag.add(save, "CARD_KEY", 1, data), true)
  check("and an HM", Bag.add(save, "HM_WATERFALL", 1, data), true)
  check("the HM went to the TM/HM pocket",
    Bag.slots(save, data, "TM_HM"), 1)

  -- The TM/HM pocket holds far more than 20 (one of each TM plus HMs).
  local tm = { inventory = {} }
  local tmData = { items = {} }
  for i = 1, 30 do
    local id = "TM_" .. i
    tmData.items[id] = { id = id, pocket = "TM_HM", index = i }
    check("TM #" .. i .. " fits", Bag.add(tm, id, 1, tmData), true)
  end
  check("30 TMs held, where a 20-bag would have stopped at 20",
    Bag.slots(tm, tmData, "TM_HM"), 30)

  -- No pocket field (Gen 1 cache) resolves to ITEM, so the single-bag limit
  -- is exactly what it was.
  local g1 = { inventory = {} }
  local g1Data = { items = {} }
  for i = 1, 20 do
    local id = "I" .. i
    g1Data.items[id] = { id = id, index = i } -- no pocket
    Bag.add(g1, id, 1, g1Data)
  end
  check("Gen 1 (no pockets) still caps at 20",
    Bag.add(g1, "I21", 1, g1Data), false)
end
bagPocketChecks()

-- ---------------------------------------------------------------------------
-- SaveMenu's save chime (engine/menus/save.asm:259, `ld de, SFX_SAVE / call
--
-- SFX_SAVE is an INDEX into the sfx pointer table, so a wrong id plays the
-- wrong sound rather than nothing, and no assertion here can see the mistake
-- SaveMenu:playSfx -> sfxOrder[id + 1], against the shipped Gold cache, must
-- name Sfx_Save.  $1f used to sit there, which is SFX_ENTER_DOOR.
-- Wrapped in a function for the same 200-local reason as the blocks above.
local function saveSfxChecks()
  local cacheDir = os.getenv("GOLD_CACHE")
  if not cacheDir then
    cacheDir = (os.getenv("HOME") or "") ..
      "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local audioFile = loadfile(cacheDir .. "/data/generated/audio.lua")
  if not audioFile then
    check("cache absent (SKIP the save chime)", true, true)
    return
  end
  local audio = audioFile()
  check("the cache carries an sfx order", type(audio.sfxOrder) == "table", true)

  -- Sound.play is the far side of SaveMenu:playSfx; swap it for a recorder so
  -- the label the id resolved to is readable without an audio device.
  local Sound = require("src.core.Sound")
  local realPlay, rang = Sound.play, nil
  Sound.play = function(_, name) rang = name end
  local SaveMenu = require("src.ui.gen2.SaveMenu")
  local menu = SaveMenu.new({ data = { audio = audio } },
    { save = {}, existed = false, writer = function() return true end })
  menu:playSfx(SaveMenu.SFX_SAVE)
  Sound.play = realPlay

  check("saving rings SFX_SAVE", rang, "Sfx_Save")
end
saveSfxChecks()

-- engine/items/pack.asm:1307 .place_insert, home/audio.asm:220 WaitPlaySFX
local function packSwitchSfxChecks()
  local Sound = require("src.core.Sound")
  local realPlay, realBusy, realFrames =
    Sound.play, Sound.sfxBusy, Sound.waitFramesFor
  local rang = {}
  Sound.play = function(_, name) rang[#rang + 1] = name end

  local save = Save.newGame()
  save.inventory = { POTION = 1, ANTIDOTE = 1 }
  local game, input = newGame(save)
  game.data.items = {
    POTION = { id = "POTION", name = "POTION", pocket = "ITEM", index = 1 },
    ANTIDOTE = { id = "ANTIDOTE", name = "ANTIDOTE", pocket = "ITEM",
      index = 2 },
  }
  game.data.audio = { sfx = { Sfx_SwitchPokemon = {} } }
  local menu = PackMenu.new(game, { pocket = "ITEM" })
  check("two rows to shuffle", #menu.rows, 2)

  menu.index = 1
  input:press("select")
  menu:update(0)
  check("SELECT picks the row up", menu.switching, 1)
  input:press("down")
  menu:update(0)
  check("the cursor moves under it", menu.index, 2)
  input:press("a")
  menu:update(0)
  check("the place ends the switch", menu.switching, nil)
  check("and beeps once in that frame", #rang, 1)
  menu:update(0)
  check("the second beep follows on the next tick", #rang, 2)
  check("both are the switch cue",
    rang[1] == "Sfx_SwitchPokemon" and rang[2] == "Sfx_SwitchPokemon", true)
  menu:update(0)
  check("and there is no third", #rang, 2)

  -- home/audio.asm:225 WaitSFX, home/delay.asm:14
  Sound.sfxBusy = function() return true end
  Sound.waitFramesFor = function() return 3 end
  rang = {}
  menu.index = 1
  input:press("select")
  menu:update(0)
  input:press("down")
  menu:update(0)
  input:press("a")
  menu:update(0)
  check("the place beeps", #rang, 1)
  local held = menu.index
  input:press("down")
  menu:update(0)
  check("the pending beep holds the list", menu.index, held)
  check("with no second beep yet", #rang, 1)
  menu:update(0)
  check("still waiting", #rang, 1)
  menu:update(0)
  check("the budget releases the second beep", #rang, 2)

  Sound.play, Sound.sfxBusy, Sound.waitFramesFor = realPlay, realBusy,
    realFrames
end
packSwitchSfxChecks()

-- ------------------------------------------------- the mod row contract
--
-- Gold's screens raise the same three hooks the Gen 1 ones do, which is only
-- half a contract: a row a mod adds has to DO something on A too.  Each of
-- these three is one line in the screen's dispatch, and the failure without it
-- is invisible (the row draws, the press is eaten, nothing happens).
local function modRowChecks()
  local Runtime = require("src.mods.Runtime")
  local Hooks = require("src.mods.Hooks")
  local hooks = Hooks.new()
  -- restored below: run_tests.lua dofiles every suite into ONE process, so a
  -- blanked Runtime here takes out every suite listed after this file
  local prevEvents, prevHooks, prevErrors =
    Runtime.events, Runtime.hooks, Runtime.errors
  Runtime.install(prevEvents, hooks, prevErrors or {})

  -- ui.options.rows: activate on A, step on Left/Right, value on the panel
  local fired, stepped = 0, 0
  hooks:wrap("ui.options.rows", function(nextFn, game, rows)
    rows = nextFn(game, rows)
    rows[#rows + 1] = { id = "modrow", label = "MOD ROW",
      value = function() return "ON" end,
      step = function() stepped = stepped + 1 end,
      activate = function() fired = fired + 1 end }
    return rows
  end)
  local og, oi = newGame(nil)
  local om = OptionsMenu.new(og, { options = Save.defaultOptions() })
  check("gen2 OPTION takes the hook's row", om.rows[#om.rows].id, "modrow")
  -- A hook row is in no group, so it stays on the top level.
  check("and keeps it reachable there", om:focusRow("modrow"), om)
  oi:press("a")
  om:update(0)
  check("A on a mod row calls activate", fired, 1)
  oi:press("right")
  om:update(0)
  check("Right on a mod row calls step", stepped, 1)

  -- ui.start_menu.items: an entry with onSelect and no value
  hooks.chains = {}
  local chose = 0
  hooks:wrap("ui.start_menu.items", function(nextFn, game, items)
    items = nextFn(game, items)
    items[#items + 1] = { label = "MOD", onSelect = function() chose = chose + 1 end }
    return items
  end)
  local ssave = Save.newGame({ playerName = "GOLD" })
  local sg, si = newGame(ssave)
  local sm = StartMenu.new(sg, { save = ssave })
  check("gen2 START takes the hook's item", sm.items[#sm.items].label, "MOD")
  sm.list.index = #sm.items
  si:press("a")
  sm.list:update(si)
  check("A on a mod item calls onSelect", chose, 1)

  -- ui.party.submenu: an entry with onSelect and no vanilla id
  hooks.chains = {}
  local picked = 0
  hooks:wrap("ui.party.submenu", function(nextFn, game, items, mon, ctx)
    items = nextFn(game, items, mon, ctx)
    items[#items + 1] = { label = "WALK", onSelect = function() picked = picked + 1 end }
    return items
  end)
  local PartyMenu = require("src.ui.gen2.PartyMenu")
  local psave = Save.newGame({ playerName = "GOLD" })
  psave.party = { { species = "CYNDAQUIL", level = 5, hp = 20, maxHp = 20,
                    moves = {}, nickname = "CYNDA" } }
  local pg, pi = newGame(psave)
  local pm = PartyMenu.new(pg, { save = psave })
  local items = pm:submenuItems(psave.party[1])
  check("gen2 party submenu takes the hook's entry", items[#items].label, "WALK")
  pm.submenu = { items = items, index = #items, mon = psave.party[1], slot = 1 }
  pi:press("a")
  pm:updateSubmenu(pi)
  check("A on a mod entry calls onSelect", picked, 1)

  hooks.chains = {}
  Runtime.install(prevEvents, prevHooks, prevErrors)
end
modRowChecks()

print(("gen2 menus: %d checks, %d failures"):format(checks, failures))
-- Raise rather than os.exit: tests/run_tests.lua dofiles this file, so an
-- exit here takes the whole tier down with it and silently skips every
-- suite listed after this one (see tests/harness.lua's T.suite note).
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
