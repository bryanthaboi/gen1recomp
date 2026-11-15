-- The static menu a script puts up: `loadmenu` then `verticalmenu` or
-- `_2dmenu` (home/menu.asm VerticalMenu / _2DMenu, engine/menus/menu.asm
-- _2DMenu_).  Nine sites in the game use one -- the vending machines, the Game
-- Corner prize counters, the coin vendor, Earl's blackboard -- and until the
-- extractor followed the MenuHeader pointer every one of them took the cancel
-- arm, because the VM had a raw address and nothing to draw.
--
-- The whole layout comes out of two routines, so nothing here is laid out by
-- eye:
--
--   MenuBox      draws the border from (left, top) to (right, bottom)
--                inclusive, which is the four bytes `menu_coords` lays down
--                Y FIRST (macros/coords.asm is `db \2, \1` twice).
--   GetMenuTextStartCoord decides where the labels and the cursor go:
--                box + 1 for the border, + 1 more row unless
--                STATICMENU_NO_TOP_SPACING, + 1 more column if
--                STATICMENU_CURSOR.  The cursor sits in the column that last
--                + 1 skipped over.
--
-- A vertical menu's items are TWO rows apart (`ld bc, 2 * SCREEN_WIDTH` in
-- PlaceMenuStrings) and its answer is wMenuCursorY.  A 2D menu lays its items
-- out row by row, `spacing` tiles apart across and the same two rows down, and
-- its answer is `(cursorY - 1) * cols + cursorX` (_2DMenu_'s SimpleMultiply).
--
-- Both are ONE-BASED and both answer 0 for B, which is why the `ifequal`
-- ladder after the command starts at 1 and the fall-through is the cancel arm.
--
-- These two routines are Gold's generic menu, so this is where the generic
-- ui.list_menu hook lands: it takes the same opts (wrap, pageJump, keyRepeat,
-- repeatDelay, repeatRate) and the same ctx the Gen 1 list takes
-- (src/ui/ListMenu.lua), and a mod that asks for wrapping once has it on every
-- script menu in the game.

local Chrome = require("src.ui.gen2.Chrome")
local CoinCase = require("src.core.gen2.CoinCase")
local Runtime = require("src.mods.Runtime")
local Sound = require("src.core.Sound")

local ScriptMenu = {}
ScriptMenu.__index = ScriptMenu
ScriptMenu.isOpaque = false

-- constants/menu_constants.asm, the wMenuDataFlags bits this screen reads.
local STATICMENU_DISABLE_B = 0x01
-- STATICMENU_WRAP (bit 2): the cursor runs off one end onto the other.  No
-- header a script loads sets it, so vanilla Gold never wraps -- it is read here
-- because it is the flag a ui.list_menu hook is turning on when it asks for
-- `wrap`, and a header that ever did set it must not need a second switch.
local STATICMENU_WRAP = 0x04
local STATICMENU_NO_TOP_SPACING = 0x40
local STATICMENU_CURSOR = 0x80

-- Key-repeat cadence, the same pair the Gen 1 generic list uses
-- (src/ui/ListMenu.lua): frames to wait before repeats start, then between
-- them.  Both are inert until a ui.list_menu hook turns keyRepeat on.
local REPEAT_DELAY = 16
local REPEAT_RATE = 4

-- ui.list_menu identity: unhooked opts pass through unchanged.
local function sameOpts(opts) return opts end

local function hasFlag(flags, bit)
  return math.floor((tonumber(flags) or 0) / bit) % 2 == 1
end

-- GetMenuTextStartCoord, exactly.  Answers the label origin in tile coords;
-- the cursor column is one to the left of it when there is a cursor at all.
function ScriptMenu.startCoord(header)
  local flags = (header and header.dataFlags) or 0
  local y = ((header and header.top) or 0) + 1
  local x = ((header and header.left) or 0) + 1
  if not hasFlag(flags, STATICMENU_NO_TOP_SPACING) then y = y + 1 end
  if hasFlag(flags, STATICMENU_CURSOR) then x = x + 1 end
  return x, y
end

-- The item list and the grid shape, whichever of the two the header carries.
-- A vertical menu is n rows by one column; a 2D menu names its own.
function ScriptMenu.layout(header, style)
  local grid = header and header.grid
  if style == "2d" and grid then
    return header.gridItems or {}, grid.rows, grid.cols, grid.spacing or 0
  end
  local items = (header and header.items) or {}
  return items, #items, 1, 0
end

-- The 1-based answer _2DMenu_ computes.  A vertical menu is one column, so
-- this collapses to the row index -- which is what wMenuCursorY holds.
function ScriptMenu.choiceIndex(row, col, cols)
  return (row - 1) * (cols or 1) + col
end

-- opts: header (the extracted MenuHeader), style ("vertical" | "2d"),
--       balance ("coins" | "money" | "moneycoins"), save,
--       onChoose(index) -- 0 for a cancel,
--       title / kind -- context for the ui.list_menu hook, nothing else reads
--       them (a script menu has neither on the cart)
function ScriptMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, ScriptMenu)
  self.game = game
  self.data = (game and game.data) or {}
  -- The balance box the `special` before the `loadmenu` put up: every
  -- DisplayCoinCaseBalance / DisplayMoneyAndCoinBalance / PlaceMoneyTopRight in
  -- the game is followed straight away by loadmenu, and the box stays on
  -- screen under the menu until CloseWindow.  See Chrome's balance boxes.
  self.balance = opts.balance
  self.save = opts.save or (game and game.save)
  self.header = opts.header or {}
  self.style = opts.style or "vertical"
  self.onChoose = opts.onChoose
  self.items, self.rows, self.cols, self.spacing =
    ScriptMenu.layout(self.header, self.style)
  self.textX, self.textY = ScriptMenu.startCoord(self.header)
  self.showCursor = hasFlag(self.header.dataFlags, STATICMENU_CURSOR)
  -- MenuHeader's last byte is wMenuCursorPosition, the option the cursor opens
  -- on.  It is 1-based and every real header sets it to 1.
  local start = math.max(1, math.min(#self.items,
    tonumber(self.header.cursor) or 1))
  self.row = math.floor((start - 1) / self.cols) + 1
  self.col = (start - 1) % self.cols + 1

  -- ui.list_menu: the same hook name and the same (opts, ctx) payload the Gen 1
  -- generic list uses (src/ui/ListMenu.lua), wrapped around Gold's own generic
  -- menu -- VerticalMenu / _2DMenu, the routine every static script menu in the
  -- game is drawn and driven by -- so a mod that asks for wrapping or
  -- hold-to-scroll once gets it on both generations' list-shaped menus.
  -- Guarded with wantsHook: a mod-free boot builds no ctx table and keeps the
  -- flags the header itself carries.
  self.wrap = hasFlag(self.header.dataFlags, STATICMENU_WRAP)
  self.pageJump = false
  self.keyRepeat = false
  self.repeatDelay = REPEAT_DELAY
  self.repeatRate = REPEAT_RATE
  self.holdDir, self.holdFrames = nil, 0
  if Runtime.wantsHook("ui.list_menu") then
    local hooked = Runtime.call("ui.list_menu", sameOpts, {
      wrap = self.wrap,
      pageJump = self.pageJump,
      keyRepeat = self.keyRepeat,
      repeatDelay = self.repeatDelay,
      repeatRate = self.repeatRate,
    }, {
      game = game,
      title = opts.title,
      -- `kind` is what a Gen 1 hook switches on ("bag", "shop", ...); a script
      -- menu has no title to fall back to, so it names the shape it is.
      kind = opts.kind or ("script_" .. self.style),
      itemCount = #self.items,
    })
    if type(hooked) == "table" then
      if hooked.wrap ~= nil then self.wrap = hooked.wrap and true or false end
      if hooked.pageJump ~= nil then
        self.pageJump = hooked.pageJump and true or false
      end
      if hooked.keyRepeat ~= nil then
        self.keyRepeat = hooked.keyRepeat and true or false
      end
      self.repeatDelay = tonumber(hooked.repeatDelay) or self.repeatDelay
      self.repeatRate = math.max(1, tonumber(hooked.repeatRate)
        or self.repeatRate)
    end
  end
  return self
end

function ScriptMenu:wantsFillScale() return true end

function ScriptMenu:finish(index)
  if self.done then return end
  self.done = true
  if self.onChoose then self.onChoose(index) end
end

function ScriptMenu:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

-- One cursor step along an axis.  Without `wrap` the cursor stops at the ends
-- the way _2DMenu_'s exit flags leave it, which is every header the game ships.
local function step(current, total, delta, wrap)
  if total <= 0 then return current end
  local next_ = current + delta
  if wrap then return ((next_ - 1) % total) + 1 end
  return math.max(1, math.min(total, next_))
end

-- An edge press or a key-repeat tick for a held direction.  Left and right are
-- the 2D grid's own axis wherever there is more than one column; on a vertical
-- menu they are free, so `pageJump` gives them the ends of the list -- the page
-- the Gen 1 list moves by is its whole visible window, and this menu draws
-- every row it has (src/ui/ListMenu.lua navPressed).
function ScriptMenu:nav(dir)
  if dir == "up" then
    self.row = step(self.row, self.rows, -1, self.wrap)
  elseif dir == "down" then
    self.row = step(self.row, self.rows, 1, self.wrap)
  elseif self.cols > 1 and dir == "left" then
    self.col = step(self.col, self.cols, -1, self.wrap)
  elseif self.cols > 1 and dir == "right" then
    self.col = step(self.col, self.cols, 1, self.wrap)
  elseif self.pageJump and dir == "left" then
    self.row = step(self.row, self.rows, -self.rows, self.wrap)
  elseif self.pageJump and dir == "right" then
    self.row = step(self.row, self.rows, self.rows, self.wrap)
  end
end

-- StaticMenuJoypad, and then MenuClickSound on the way out.
function ScriptMenu:update(_dt)
  if self.done then return end
  local input = self.game and self.game.input
  if not input then return end
  local pressed = nil
  if input:wasPressed("up") then
    pressed = "up"
  elseif input:wasPressed("down") then
    pressed = "down"
  elseif input:wasPressed("left") then
    pressed = "left"
  elseif input:wasPressed("right") then
    pressed = "right"
  end
  if pressed then
    self:nav(pressed)
    self.holdDir, self.holdFrames = pressed, 0
  elseif input:wasPressed("a") then
    self:playSfx("Sfx_ReadText2")
    self:finish(ScriptMenu.choiceIndex(self.row, self.col, self.cols))
  elseif input:wasPressed("b")
      and not hasFlag(self.header.dataFlags, STATICMENU_DISABLE_B) then
    self:playSfx("Sfx_ReadText2")
    self:finish(0)
  end
  if self.done then return end

  -- Hold-to-scroll, opt-in through ui.list_menu's keyRepeat and driven exactly
  -- as the Gen 1 list drives it (src/ui/ListMenu.lua): the held direction
  -- repeats once repeatDelay frames have passed, then every repeatRate frames.
  if not self.keyRepeat then return end
  local dir = self.holdDir
  if dir and input.isDown and input:isDown(dir) then
    self.holdFrames = self.holdFrames + 1
    local afterDelay = self.holdFrames - self.repeatDelay
    if afterDelay >= 0 and afterDelay % self.repeatRate == 0 then
      self:nav(dir)
    end
  else
    self.holdDir, self.holdFrames = nil, 0
  end
end

function ScriptMenu:itemPosition(index)
  local row = math.floor((index - 1) / self.cols)
  local col = (index - 1) % self.cols
  return self.textX + col * self.spacing, self.textY + row * 2
end

-- Drawn BEFORE the menu box, which is the order the cart draws them in: the
-- Celadon TM counter's menu runs to column 15 on row 2 and the coin box's
-- bottom border is on that row, so the menu's own border is what survives the
-- overlap.
function ScriptMenu:drawBalance()
  local kind = self.balance
  if not kind then return end
  local player = self.save and self.save.player
  local money = (player and player.money) or 0
  if kind == "coins" then
    Chrome.coinBalanceBox(self.game and self.game.data, CoinCase.coins(self.save))
  elseif kind == "moneycoins" then
    Chrome.moneyAndCoinBalanceBox(self.game and self.game.data, money,
      CoinCase.coins(self.save))
  else
    Chrome.moneyBalanceBox(money)
  end
end

function ScriptMenu:drawPanel()
  self:drawBalance()
  local h = self.header
  local left, top = h.left or 0, h.top or 0
  Chrome.box(left, top,
    (h.right or left) - left + 1, (h.bottom or top) - top + 1)
  for index, label in ipairs(self.items) do
    local x, y = self:itemPosition(index)
    Chrome.print(label, x, y)
  end
  if self.showCursor then
    local x, y = self:itemPosition(
      ScriptMenu.choiceIndex(self.row, self.col, self.cols))
    Chrome.cursor(x - 1, y)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function ScriptMenu:draw()
  self:drawPanel()
end

return ScriptMenu
