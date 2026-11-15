-- The six-digit money keypad BankOfMom's GET and SAVE both put up
-- (engine/events/mom.asm Mom_SetUpWithdrawMenu / Mom_SetUpDepositMenu /
-- Mom_WithdrawDepositMenuJoypad).  Not a generic ScriptMenu: nothing else in
-- the game edits a number digit by digit, so this is its own screen the way
-- the naming keyboard and the move-list are theirs.
--
-- Layout, from the ASM's own coordinates:
--   `hlcoord 0, 0 / lb bc, 6, 18 / call Textbox` -- an interior 18x6 box at
--   (0,0), i.e. a 20x8 outer box.
--   (1,2) "SAVED@" / (12,2) wMomsMoney, PRINTNUM_MONEY | 3 bytes, width 6
--   (1,4) "HELD@"  / (12,4) wMoney,     PRINTNUM_MONEY | 3 bytes, width 6
--   (1,6) "DEPOSIT@" or "WITHDRAW@" / (12,6) the typed amount,
--   PRINTNUM_MONEY | PRINTNUM_LEADINGZEROS | 3, width 6
-- PRINTNUM_MONEY puts the yen sign right before the field and the six digits
-- after it, so column 12 is the yen and 13..18 are the digits -- which is
-- where Mom_WithdrawDepositMenuJoypad's blinking cursor (`hlcoord 13, 6` plus
-- wMomBankDigitCursorPosition) lands.
--
-- Mom_WithdrawDepositMenuJoypad's own joypad loop: UP/DOWN add or subtract
-- the place value under the cursor (through GiveMoney/TakeMoney, so a digit
-- clamps at 999999 or 0 rather than wrapping), LEFT/RIGHT move the cursor,
-- A accepts, B cancels.  wMomBankDigitCursorPosition starts at 5 -- the ones
-- digit, rightmost -- which is `.DigitQuantities`' own indexing: position 0
-- is the hundred-thousands digit, position 5 is the ones digit.  Only the
-- table's first six entries are ever read (`.getdigitquantity` always starts
-- at `.DigitQuantities` and offsets by the cursor position alone); the two
-- further groups of six the ASM lays down after it are unreachable from this
-- routine and are not carried here.

local Chrome = require("src.ui.gen2.Chrome")
local Sound = require("src.core.Sound")
local RomText = require("src.core.RomText")

local BankOfMom = {}
BankOfMom.__index = BankOfMom
BankOfMom.isOpaque = false

local BOX_X, BOX_Y, BOX_W, BOX_H = 0, 0, 20, 8
local SAVED_LABEL_X, SAVED_Y = 1, 2
local HELD_LABEL_X, HELD_Y = 1, 4
local KIND_LABEL_X, KIND_Y = 1, 6
local MONEY_X = 12
local DIGIT_X = 13 -- first digit column; DIGIT_X + position is the cursor

local MAX_MONEY = 999999

-- `.DigitQuantities`' first (and only reachable) six entries, 10^5..10^0.
local PLACE_VALUES = { 100000, 10000, 1000, 100, 10, 1 }

-- engine/events/mom.asm:631-641
local SAVED_LABEL = "Mom_SavedString"
local HELD_LABEL = "Mom_HeldString"
local DEPOSIT_LABEL = "Mom_DepositString"
local WITHDRAW_LABEL = "Mon_WithdrawString"

-- charmap.asm: ¥ is the currency glyph, same one MartMenu's moneyText uses.
local YEN = "\xc2\xa5"

-- PrintNum with PRINTNUM_MONEY, no PRINTNUM_LEADINGZEROS: the ¥ floats to
-- just before the first significant digit and the field stays 6 digits wide.
local function moneyText(amount)
  local digits = ("%06d"):format(math.max(0, math.floor(amount or 0)))
  local first = digits:find("[1-9]") or #digits
  return (" "):rep(first - 1) .. YEN .. digits:sub(first)
end

-- PrintNum with PRINTNUM_MONEY | PRINTNUM_LEADINGZEROS: all six digits shown.
local function moneyTextZeroed(amount)
  return YEN .. ("%06d"):format(math.max(0, math.floor(amount or 0)))
end

-- opts: kind ("deposit" | "withdraw"), saved (wMomsMoney), held (wMoney),
--       onDone(amount) -- nil for B
function BankOfMom.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, BankOfMom)
  self.game = game
  self.data = (game and game.data) or {}
  self.kind = opts.kind or "deposit"
  self.saved = opts.saved or 0
  self.held = opts.held or 0
  self.onDone = opts.onDone
  self.amount = 0
  self.position = 5 -- ones digit, rightmost
  self.blink = 0
  return self
end

function BankOfMom:wantsFillScale() return true end

function BankOfMom:finish(amount)
  if self.done then return end
  self.done = true
  if self.onDone then self.onDone(amount) end
end

function BankOfMom:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

function BankOfMom:update(dt)
  if self.done then return end
  self.blink = self.blink + (dt or 0)
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("up") then
    self.amount = math.min(self.amount + PLACE_VALUES[self.position + 1],
      MAX_MONEY)
  elseif input:wasPressed("down") then
    self.amount = math.max(self.amount - PLACE_VALUES[self.position + 1], 0)
  elseif input:wasPressed("left") then
    self.position = math.max(0, self.position - 1)
  elseif input:wasPressed("right") then
    self.position = math.min(5, self.position + 1)
  elseif input:wasPressed("a") then
    self:playSfx("Sfx_ReadText2")
    self:finish(self.amount)
  elseif input:wasPressed("b") then
    self:playSfx("Sfx_ReadText2")
    self:finish(nil)
  end
end

function BankOfMom:drawPanel()
  Chrome.box(BOX_X, BOX_Y, BOX_W, BOX_H)
  Chrome.print(RomText(self.data, SAVED_LABEL, nil), SAVED_LABEL_X, SAVED_Y)
  Chrome.print(moneyText(self.saved), MONEY_X, SAVED_Y)
  Chrome.print(RomText(self.data, HELD_LABEL, nil), HELD_LABEL_X, HELD_Y)
  Chrome.print(moneyText(self.held), MONEY_X, HELD_Y)
  Chrome.print(RomText(self.data, self.kind == "withdraw" and WITHDRAW_LABEL or DEPOSIT_LABEL, nil),
    KIND_LABEL_X, KIND_Y)
  Chrome.print(moneyTextZeroed(self.amount), MONEY_X, KIND_Y)
  -- `hlcoord 13, 6 / ... / ld [hl], ' '` blanks the digit under the cursor
  -- for one beat every `hVBlankCounter and $10` window; a plain white square
  -- over that one tile every half second reads the same without a real
  -- VBlank counter to poll it against.
  if math.floor(self.blink * 2) % 2 == 1 then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill",
      (DIGIT_X + self.position) * 8, KIND_Y * 8, 8, 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function BankOfMom:draw()
  self:drawPanel()
end

return BankOfMom
