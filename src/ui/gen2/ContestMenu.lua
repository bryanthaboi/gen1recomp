-- The Bug Catching Contest's one screen: the STOCK-versus-THIS comparison the
-- park shows when you catch a second mon, and the "Switch #MON?" it asks over
-- it (engine/events/bug_contest/display_stats.asm
-- DisplayCaughtContestMonStats, driven by
-- engine/events/bug_contest/caught_mon.asm BugContest_SetCaughtContestMon).
--
-- The layout is transcribed from the ASM's hlcoord values, not laid out by
-- eye:
--
--   Textbox (0,0) `ld b, 4 / ld c, 13`   interior 13x4, so 15x6 on screen
--   Textbox (0,6) `ld b, 4 / ld c, 13`   the same box six rows down
--   PlaceString (2,0)   " STOCK <PK><MN> "  -- ON the top border, spaces and
--   PlaceString (2,6)   " THIS <PK><MN> "      all, which is what erases the
--                                              border tiles under the label
--   PlaceString (5,4)   "HEALTH"
--   PlaceString (5,10)  "HEALTH"
--   PlaceString (1,2)   the stock mon's name, then PrintLevel at the coord
--                       PlaceString returned in bc -- i.e. immediately after
--                       the name, NOT at a fixed column
--   PlaceString (1,8)   the new mon's nickname, then PrintLevel likewise
--   PrintNum   (11,4)   wContestMonMaxHP, `lb bc, 2, 3` -- 2 bytes, 3 digits
--   PrintNum   (11,10)  wEnemyMonMaxHP, same field
--   PlaceYesNoBox `lb bc, 14, 7`  -- the shared 6x5 box at (14,7)
--
-- Two things the ASM does that are easy to drop.  It sets NO_TEXT_SCROLL for
-- the duration and restores wOptions afterwards, so ContestAskSwitchText
-- appears whole instead of scrolling; and PlaceYesNoBox's `ret c` is the NO
-- arm, which means backing out with B keeps the mon already in stock.  A
-- player who mashes B therefore never loses their best catch.
--
-- The RULES are src/core/gen2/BugContest.lua.  This screen decides nothing: it
-- shows the two mons, asks, and calls BugContest.switchCaught on a yes.

local BugContest = require("src.core.gen2.BugContest")
local Chrome = require("src.ui.gen2.Chrome")

local ContestMenu = {}
ContestMenu.__index = ContestMenu
ContestMenu.isOpaque = true

-- ---------------------------------------------------------------- layout
local STOCK_BOX_X, STOCK_BOX_Y = 0, 0
local THIS_BOX_Y = 6
local BOX_INNER_W, BOX_INNER_H = 13, 4

local LABEL_X = 2
local NAME_X = 1
local NAME_ROW_OFFSET = 2   -- (1,2) against a box at row 0
local HEALTH_X = 5
local HEALTH_ROW_OFFSET = 4 -- (5,4) against a box at row 0
local HP_X = 11             -- PrintNum fills LEFT from a 3-digit field here
local HP_DIGITS = 3

local YESNO_X, YESNO_Y, YESNO_W, YESNO_H = 14, 7, 6, 5

-- The text box ContestAskSwitchText prints into is the shared one: Textbox
-- `lb bc, 4, 18` at (0,12), two lines two rows apart starting at row 14.
local TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H = 0, 12, 20, 6
local TEXT_X, TEXT_Y = 1, 14

-- ----------------------------------------------------------------- strings
--
-- display_stats.asm's .Stock / .This / .Health, spelled with the same leading
-- and trailing spaces, and data/text/common_2.asm's _ContestAskSwitchText.
-- <PK> and <MN> are one tile each, so "<PK><MN>" is two tiles and not seven.
ContestMenu.TEXT = {
  stock = " STOCK <PK><MN> ",
  this = " THIS <PK><MN> ",
  health = "HEALTH",
  askSwitch = "Switch #MON?",
  -- _ContestCaughtMonText and _ContestAlreadyCaughtText, the two lines that
  -- bracket this screen in BugContest_SetCaughtContestMon.
  caught = function(name) return { ("Caught %s!"):format(name) } end,
  alreadyCaught = function(name)
    return { "You already caught", ("a %s."):format(name) }
  end,
}

function ContestMenu:wantsFillScale() return true end
function ContestMenu:drawsWidescreen() return true end

-- PrintLevel writes the <LV> tile at the coordinate it is given and then the
-- number, so a name and its level are one string here rather than two prints
-- at fixed columns.
local function nameAndLevel(mon)
  if not mon then return "" end
  local name = mon.nickname or mon.name or mon.species or "?"
  return ("%s<LV>%d"):format(name, mon.level or 1)
end

local function maxHp(mon)
  if not mon then return 0 end
  return mon.maxHp or (mon.stats and mon.stats.hp) or 0
end

-- opts:
--   save     the save the contest state hangs off
--   stock    wContestMon, the mon already caught
--   caught   the mon just caught, wEnemyMon's party form
--   onClose(kept)  kept is the mon that ends up in stock
function ContestMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, ContestMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.stock = opts.stock or BugContest.caughtMon(self.save)
  self.caught = opts.caught
  self.onClose = opts.onClose
  -- PlaceYesNoBox opens on YES, and YesNoMenuHeader has no
  -- STATICMENU_DISABLE_B, so B is the same as picking NO.
  self.choice = 1
  return self
end

function ContestMenu:close(kept)
  if self.onClose then self.onClose(kept) end
end

function ContestMenu:answer(yes)
  local kept = self.stock
  if yes then
    kept = BugContest.switchCaught(self.save, self.caught) or self.caught
  end
  self:close(kept)
end

function ContestMenu:update(_dt)
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("up") or input:wasPressed("down") then
    self.choice = self.choice == 1 and 2 or 1
    return
  end
  if input:wasPressed("b") then return self:answer(false) end
  if input:wasPressed("a") then return self:answer(self.choice == 1) end
end

-- ------------------------------------------------------------------- draw

function ContestMenu:drawMonBox(boxY, label, mon)
  Chrome.textbox(STOCK_BOX_X, boxY, BOX_INNER_W, BOX_INNER_H)
  Chrome.print(label, LABEL_X, boxY)
  Chrome.print(nameAndLevel(mon), NAME_X, boxY + NAME_ROW_OFFSET)
  Chrome.print(ContestMenu.TEXT.health, HEALTH_X, boxY + HEALTH_ROW_OFFSET)
  -- `lb bc, 2, 3`: two source bytes into a three-digit field, space padded
  -- because PRINTNUM_LEADINGZEROS is not set, laid down FROM hlcoord 11 --
  -- so the field starts at HP_X and the padding is part of the string.
  Chrome.print(Chrome.number(maxHp(mon), HP_DIGITS), HP_X,
    boxY + HEALTH_ROW_OFFSET)
end

function ContestMenu:drawYesNo()
  Chrome.box(YESNO_X, YESNO_Y, YESNO_W, YESNO_H)
  -- GetMenuTextStartCoord: the box corner, + 1 for the border, + 1 for
  -- STATICMENU_CURSOR, and YesNoMenuHeader sets STATICMENU_NO_TOP_SPACING so
  -- there is no third row of padding -- YES at (16,8), NO at (16,10), cursor
  -- column 15.
  Chrome.print("YES", YESNO_X + 2, YESNO_Y + 1)
  Chrome.print("NO", YESNO_X + 2, YESNO_Y + 3)
  Chrome.cursor(YESNO_X + 1, YESNO_Y + (self.choice == 1 and 1 or 3))
end

function ContestMenu:drawPanel()
  Chrome.clear()
  self:drawMonBox(STOCK_BOX_Y, ContestMenu.TEXT.stock, self.stock)
  self:drawMonBox(THIS_BOX_Y, ContestMenu.TEXT.this, self.caught)
  Chrome.box(TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H)
  Chrome.print(ContestMenu.TEXT.askSwitch, TEXT_X, TEXT_Y)
  self:drawYesNo()
  love.graphics.setColor(1, 1, 1, 1)
end

function ContestMenu:draw()
  self:drawPanel()
end

function ContestMenu:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return ContestMenu
