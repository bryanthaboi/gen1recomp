-- The "how many?" selector (DisplayChooseQuantityMenu, home/list_menu.asm):
-- Up/Down step by 1 with 1..max roll-over, A confirms, B cancels.
-- Shows a running price when opts.unitPrice is set.

local Font = require("src.render.Font")

local QuantityBox = {}
QuantityBox.__index = QuantityBox
QuantityBox.isOpaque = false

function QuantityBox.new(game, opts)
  local self = setmetatable({}, QuantityBox)
  self.game = game
  self.max = math.max(1, opts.max or 99)
  self.qty = math.min(opts.start or 1, self.max)
  self.unitPrice = opts.unitPrice
  self.onDone = opts.onDone -- onDone(qty | nil on cancel)
  self.keepOpen = opts.keepOpen
  return self
end

-- home/print_bcd.asm:14-50
local function moneyField(amount)
  local digits = ("%06d"):format(math.max(0, math.floor(amount or 0)))
  local first = digits:find("[1-9]") or #digits
  return "¥" .. digits:sub(first)
end

local function wrap(v, max)
  if v < 1 then return max end
  if v > max then return 1 end
  return v
end

function QuantityBox:update(dt)
  local input = self.game.input
  if input:wasPressed("up") then
    self.qty = wrap(self.qty + 1, self.max)
  elseif input:wasPressed("down") then
    self.qty = wrap(self.qty - 1, self.max)
  elseif input:wasPressed("a") then
    if not self.keepOpen then self.game.stack:pop() end
    if self.onDone then self.onDone(self.qty) end
  elseif input:wasPressed("b") then
    if not self.keepOpen then self.game.stack:pop() end
    if self.onDone then self.onDone(nil) end
  end
end

function QuantityBox:draw()
  -- DisplayChooseQuantityMenu (home/list_menu.asm): non-priced box at
  -- hlcoord 15,9 (interior 3x1); priced at hlcoord 7,9 (interior 11x1).
  -- TextBoxBorder adds the frame, so outer size is +2 on each axis.
  local tw = self.unitPrice and 13 or 5
  local tx = self.unitPrice and 7 or 15
  local ty = 9
  Font.drawBox(tx, ty, tw, 3)
  love.graphics.setColor(0, 0, 0, 1)
  local y = (ty + 1) * 8
  Font.draw(("×%02d"):format(self.qty), (tx + 1) * 8, y)
  if self.unitPrice then
    -- home/list_menu.asm:293-299
    local s = moneyField(self.qty * self.unitPrice)
    Font.draw(s, (tx + tw - 1) * 8 - Font.width(s), y)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return QuantityBox
