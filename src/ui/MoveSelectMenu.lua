-- (engine/battle/core.asm:2520 .relearnmenu, engine/items/item_effects.asm:1971)

local Font = require("src.render.Font")

local MoveSelectMenu = {}
MoveSelectMenu.__index = MoveSelectMenu

local CURSOR = 0xED

function MoveSelectMenu.new(game, mon, prompt, onChoose, onCancel, owner)
  local self = setmetatable({}, MoveSelectMenu)
  self.game = game
  self.mon = mon
  self.rawPrompt = prompt or ""
  -- pokered engine/items/item_effects.asm:2136
  self.prompt = require("src.render.TextBox").strip(prompt or "")
  self.onChoose = onChoose
  self.onCancel = onCancel
  self.owner = owner
  -- pokered engine/battle/core.asm:2542-2543
  self.index = 1
  self.ready = false
  self.held = false
  self.boxShown = false
  return self
end

function MoveSelectMenu:enter()
  self:ask()
end

-- engine/items/item_effects.asm:1979
function MoveSelectMenu:ask(text)
  local TextBox = require("src.render.TextBox")
  local game = self.game
  self.ready, self.held = false, false
  local box
  box = TextBox.new(game, text or self.rawPrompt, nil, { stay = {
    onShown = function()
      if game.stack:top() == box then game.stack:pop() end
      -- engine/battle/core.asm:2542-2543
      self.index = 1
      self.boxShown = true
      self.ready = true
    end,
  } })
  game.stack:push(box)
end

function MoveSelectMenu:release()
  self.held = false
  if self.game.stack:top() == self then self.game.stack:pop() end
end

function MoveSelectMenu:update()
  if not self.ready then return end
  local input = self.game.input
  local n = #self.mon.moves
  -- engine/battle/core.asm:2692
  if n > 0 and input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or n
  elseif n > 0 and input:wasPressed("down") then
    self.index = self.index < n and self.index + 1 or 1
  elseif input:wasPressed("b") or (n < 1 and input:wasPressed("a")) then
    -- engine/items/item_effects.asm:1985
    self.ready = false
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  elseif input:wasPressed("a") then
    self.ready = false
    self.held = true
    if self.onChoose then self.onChoose(self.index, self) end
    if self.held and self.game.stack:top() == self then self:release() end
  end
end

function MoveSelectMenu:draw()
  if not self.boxShown then return end
  if self.ready then
    -- engine/items/item_effects.asm:1979
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    local first, rest = self.prompt:match("^(.-)\n(.*)$")
    Font.draw(first or self.prompt, 8, 14 * 8)
    if rest then Font.draw(rest, 8, 16 * 8) end
    love.graphics.setColor(1, 1, 1, 1)
  end
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
  love.graphics.setColor(1, 1, 1, 1)
end

return MoveSelectMenu
