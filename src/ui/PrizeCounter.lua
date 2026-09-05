-- engine/events/prize_menu.asm CeladonPrizeMenu

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local PrizeCounter = {}
PrizeCounter.__index = PrizeCounter

local NAME_X, TOP_Y, ROW_STEP = 16, 32, 16
local CURSOR_X = 8
local FIELD_END = 136
local ROWS = 4

function PrizeCounter.new(game, prizes, opts)
  opts = opts or {}
  return setmetatable({
    game = game,
    prizes = prizes,
    index = 1,
    onPick = opts.onPick,
    onCancel = opts.onCancel,
  }, PrizeCounter)
end

function PrizeCounter:update(dt)
  local input = self.game.input
  -- home/window.asm:56-83
  if input:wasPressed("up") then
    if self.index > 1 then self.index = self.index - 1 end
  elseif input:wasPressed("down") then
    if self.index < ROWS then self.index = self.index + 1 end
  elseif input:wasPressed("a") or input:wasPressed("b") then
    require("src.core.Sound").play(self.game.data, "Press_AB")
    if input:wasPressed("b") or self.index >= ROWS then
      if self.onCancel then self.onCancel() end
    elseif self.onPick then
      self.onPick(self.prizes[self.index], self.index)
    end
  end
end

-- engine/events/prize_menu.asm:24-28
function PrizeCounter.drawWindow(game, prizes, index)
  local coins = tostring((game.save and game.save.coins) or 0)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(11, 0, 9, 3)
  love.graphics.rectangle("fill", 12 * 8, 0, 4 * 8, 8)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("COIN"), 12 * 8, 0)
  Font.draw(coins, FIELD_END - Font.width(coins), 8)
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(0, 2, 18, 10)
  love.graphics.setColor(0, 0, 0, 1)
  for i, p in ipairs(prizes) do
    local y = TOP_Y + (i - 1) * ROW_STEP
    Font.draw(p.name, NAME_X, y)
    local cost = tostring(p.cost)
    Font.draw(cost, FIELD_END - Font.width(cost), y + 8)
  end
  -- data/events/prizes.asm
  Font.draw(Strings("NO THANKS"), NAME_X, TOP_Y + 3 * ROW_STEP)
  if index then
    Font.drawCode(Theme.cursor, CURSOR_X, TOP_Y + (index - 1) * ROW_STEP)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function PrizeCounter:draw()
  PrizeCounter.drawWindow(self.game, self.prizes, self.index)
end

return PrizeCounter
