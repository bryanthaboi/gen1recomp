-- (engine/battle/core.asm:2520 .relearnmenu, engine/items/item_effects.asm:1971)

local Font = require("src.render.Font")

local MoveSelectMenu = {}
MoveSelectMenu.__index = MoveSelectMenu

local CURSOR = 0xED

function MoveSelectMenu.new(game, mon, prompt, onChoose, onCancel)
  local self = setmetatable({}, MoveSelectMenu)
  self.game = game
  self.mon = mon
  -- pokered engine/items/item_effects.asm:2136
  self.prompt = require("src.render.TextBox").strip(prompt or "")
  self.onChoose = onChoose
  self.onCancel = onCancel
  -- pokered engine/battle/core.asm:2542-2543
  self.index = 1
  return self
end

function MoveSelectMenu:update()
  local input = self.game.input
  local n = #self.mon.moves
  -- engine/battle/core.asm:2692
  if n > 0 and input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or n
  elseif n > 0 and input:wasPressed("down") then
    self.index = self.index < n and self.index + 1 or 1
  elseif input:wasPressed("b") or (n < 1 and input:wasPressed("a")) then
    -- engine/items/item_effects.asm:1985
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  elseif input:wasPressed("a") then
    local picked = self.index
    self.game.stack:pop()
    if self.onChoose then self.onChoose(picked) end
  end
end

function MoveSelectMenu:draw()
  -- engine/battle/core.asm:2526
  Font.drawBox(4, 7, 16, 6)
  love.graphics.setColor(0, 0, 0, 1)
  for i = 1, 4 do
    local mv = self.mon.moves[i]
    local mdef = mv and self.game.data.moves[mv.id]
    -- engine/battle/misc.asm:37
    Font.draw(mv and (mdef and mdef.name or mv.id) or "-", 48, (7 + i) * 8)
  end
  Font.drawCode(CURSOR, 40, (7 + self.index) * 8)
  -- engine/items/item_effects.asm:1979
  Font.drawBox(0, 12, 20, 6)
  local first, rest = self.prompt:match("^(.-)\n(.*)$")
  Font.draw(first or self.prompt, 8, 14 * 8)
  if rest then Font.draw(rest, 8, 16 * 8) end
  love.graphics.setColor(1, 1, 1, 1)
end

return MoveSelectMenu
