-- Buena's two windows, Crystal only, chosen by `mode`:
--
--   password  ../pokecrystal/engine/events/buena.asm:1 BuenasPassword, whose
--             .MenuHeader is `menu_coords 0, 0, 10, 7` with the right edge
--             moved to left + the category's points byte + 2 (:9-12), and
--             whose .PasswordIndices answer is zero based (:44-49).
--   prize     :64 BuenaPrize -- Buena_PlacePrizeMenuBox (:219),
--             Buena_PrizeMenu's scrolling list (:249-261) and
--             PrintBlueCardBalance's "Points" box (:210).  0 is a B press
--             (:236-245).
--
-- Neither is opaque: engine/events/buena.asm:71-83 prints the prize question
-- BEFORE the list goes up over it, and the password menu stands on the map.

local Chrome = require("src.ui.gen2.Chrome")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")

local BuenaPassword = {}
BuenaPassword.__index = BuenaPassword
BuenaPassword.isOpaque = false

-- GetMenuTextStartCoord (../pokecrystal/home/menu.asm:214) on STATICMENU_CURSOR
-- with no STATICMENU_NO_TOP_SPACING: labels at box + (2,2), cursor one left.
local WORD_X, WORD_Y, WORD_SPACING = 2, 2, 2
local WORD_BOX_H = 8

-- engine/events/buena.asm:219 and :249, as menu_coords lays them down.
local FIELD_X, FIELD_Y, FIELD_W, FIELD_H = 0, 0, 18, 12
local LIST_BOX_X, LIST_BOX_Y, LIST_BOX_W, LIST_BOX_H = 1, 1, 16, 9
local LIST_X, LIST_Y, LIST_SPACING = 2, 2, 2
-- ScrollingMenu_CallFunctions1and2's `add hl, de` on
-- wMenuData_ScrollingMenuWidth (engine/menus/scrolling_menu.asm:424-431).
local POINTS_X = LIST_X + 13
local VISIBLE_ROWS = 4
local ARROW_X = LIST_BOX_X + LIST_BOX_W - 1
local ARROW_UP_Y, ARROW_DOWN_Y = LIST_BOX_Y, LIST_BOX_Y + LIST_BOX_H - 1

-- BlueCardBalanceMenuHeader (engine/events/buena.asm:208) and .DrawBox's
-- PlaceString / two spaces / `lb bc, 1, 2` PrintNum (:181-203).
local BALANCE_BOX_X, BALANCE_BOX_Y, BALANCE_BOX_W, BALANCE_BOX_H = 0, 11, 12, 3
local BALANCE_LABEL_X, BALANCE_LABEL_Y = 1, 12
local BALANCE_NUM_X = 8
local POINTS_LABEL = Strings.source("Points")

local UP_ARROW = "\xe2\x96\xb2"
local DOWN_ARROW = "\xe2\x96\xbc"

-- opts: mode, and then words/width/onDone(0..2) or prizes/balance/onDone(row)
function BuenaPassword.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, BuenaPassword)
  self.game = game
  self.data = (game and game.data) or {}
  self.mode = opts.mode == "prize" and "prize" or "password"
  self.words = opts.words or {}
  self.width = math.max(1, math.floor(tonumber(opts.width) or 10))
  self.prizes = opts.prizes or {}
  self.balance = math.max(0, math.floor(tonumber(opts.balance) or 0))
  self.onDone = opts.onDone
  -- engine/events/buena.asm:34 `db 1 ; default option` and :67-68
  -- `ld a, $1 / ld [wMenuSelection], a`.
  self.index = 1
  self.scroll = 0
  return self
end

function BuenaPassword:wantsFillScale() return true end

function BuenaPassword:count()
  if self.mode == "prize" then return #self.prizes end
  return #self.words
end

function BuenaPassword:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

function BuenaPassword:finish(value)
  if self.done then return end
  self.done = true
  local stack = self.game and self.game.stack
  if stack then stack:pop() end
  if self.onDone then self.onDone(value) end
end

function BuenaPassword:ensureVisible()
  local rows = math.min(VISIBLE_ROWS, self:count())
  if rows <= 0 then return end
  if self.index <= self.scroll then
    self.scroll = self.index - 1
  elseif self.index > self.scroll + rows then
    self.scroll = self.index - rows
  end
  self.scroll = math.max(0, math.min(self.scroll, self:count() - rows))
end

function BuenaPassword:update(_dt)
  if self.done then return end
  local input = self.game and self.game.input
  if not input then return end
  local total = self:count()
  if total <= 0 then return self:finish(self.mode == "prize" and 0 or -1) end
  -- Neither header sets STATICMENU_WRAP (engine/events/buena.asm:39, :256).
  if input:wasPressed("up") then
    if self.index > 1 then self.index = self.index - 1 end
  elseif input:wasPressed("down") then
    if self.index < total then self.index = self.index + 1 end
  elseif input:wasPressed("a") then
    self:playSfx("Sfx_ReadText2")
    if self.mode == "prize" then return self:finish(self.index) end
    -- engine/events/buena.asm:44-49 .PasswordIndices is zero based.
    return self:finish(self.index - 1)
  elseif input:wasPressed("b") then
    -- STATICMENU_DISABLE_B (engine/events/buena.asm:39).
    if self.mode == "prize" then
      self:playSfx("Sfx_ReadText2")
      return self:finish(0)
    end
  end
  self:ensureVisible()
end

function BuenaPassword:drawPasswordPanel()
  Chrome.box(0, 0, self.width + 3, WORD_BOX_H)
  for i, word in ipairs(self.words) do
    local ty = WORD_Y + (i - 1) * WORD_SPACING
    if i == self.index then Chrome.cursor(WORD_X - 1, ty) end
    Chrome.print(word, WORD_X, ty)
  end
end

function BuenaPassword:drawPrizePanel()
  Chrome.box(FIELD_X, FIELD_Y, FIELD_W, FIELD_H)
  Chrome.box(LIST_BOX_X, LIST_BOX_Y, LIST_BOX_W, LIST_BOX_H)
  for row = 1, VISIBLE_ROWS do
    local i = row + self.scroll
    local prize = self.prizes[i]
    if prize then
      local ty = LIST_Y + (row - 1) * LIST_SPACING
      if i == self.index then Chrome.cursor(LIST_X - 1, ty) end
      Chrome.print(prize.name, LIST_X, ty)
      -- .PrintPrizePoints writes one char, `'0' + cost` (buena.asm:281-289).
      Chrome.print(tostring(prize.cost % 10), POINTS_X, ty)
    end
  end
  -- SCROLLINGMENU_DISPLAY_ARROWS: the ▲ only once scrolled, the ▼ every pass
  -- (engine/menus/scrolling_menu.asm:348-358, :387-395).
  if self.scroll > 0 then Chrome.print(UP_ARROW, ARROW_X, ARROW_UP_Y) end
  Chrome.print(DOWN_ARROW, ARROW_X, ARROW_DOWN_Y)

  Chrome.box(BALANCE_BOX_X, BALANCE_BOX_Y, BALANCE_BOX_W, BALANCE_BOX_H)
  Chrome.print(Strings(POINTS_LABEL), BALANCE_LABEL_X, BALANCE_LABEL_Y)
  Chrome.print(Chrome.number(self.balance, 2), BALANCE_NUM_X, BALANCE_LABEL_Y)
end

function BuenaPassword:drawPanel()
  if self.mode == "prize" then return self:drawPrizePanel() end
  return self:drawPasswordPanel()
end

function BuenaPassword:draw()
  self:drawPanel()
  love.graphics.setColor(1, 1, 1, 1)
end

return BuenaPassword
