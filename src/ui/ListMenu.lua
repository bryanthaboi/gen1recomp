-- Generic full-screen scrollable list: items are { label=..., right=...,
-- value=... }; onChoose(item) / onCancel().  Used by the bag, shops, the
-- box and the Pokédex.

local Font = require("src.render.Font")
local Runtime = require("src.mods.Runtime")
local Theme = require("src.ui.Theme")

local ListMenu = {}
ListMenu.__index = ListMenu
ListMenu.isOpaque = true

-- SGB: generic whole-screen palette (SET_PAL_GENERIC)
function ListMenu:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end

local ROWS = 7
-- frames to wait before key-repeat kicks in, then between repeats
local REPEAT_DELAY = 16
local REPEAT_RATE = 4

-- ui.list_menu identity: unhooked opts pass through unchanged
local function sameOpts(opts) return opts end

function ListMenu.new(game, title, items, opts)
  opts = opts or {}
  -- bag / shop / dex / generic: mods may enable wrap, pageJump, keyRepeat
  if Runtime.wantsHook("ui.list_menu") then
    local hooked = Runtime.call("ui.list_menu", sameOpts, {
      wrap = opts.wrap,
      pageJump = opts.pageJump,
      keyRepeat = opts.keyRepeat,
      repeatDelay = opts.repeatDelay,
      repeatRate = opts.repeatRate,
    }, {
      game = game,
      title = title,
      kind = opts.kind or title,
      itemCount = items and #items or 0,
    })
    if type(hooked) == "table" then
      if hooked.wrap ~= nil then opts.wrap = hooked.wrap end
      if hooked.pageJump ~= nil then opts.pageJump = hooked.pageJump end
      if hooked.keyRepeat ~= nil then opts.keyRepeat = hooked.keyRepeat end
      if hooked.repeatDelay ~= nil then opts.repeatDelay = hooked.repeatDelay end
      if hooked.repeatRate ~= nil then opts.repeatRate = hooked.repeatRate end
    end
  end
  local self = setmetatable({}, ListMenu)
  self.game = game
  self.title = title
  self.items = items
  self.index = 1
  self.scroll = 0
  self.onChoose = opts.onChoose
  self.onCancel = opts.onCancel
  self.footer = opts.footer
  self.pageJump = opts.pageJump    -- Left/Right move a page at a time
  self.wrap = opts.wrap            -- Up on first / Down on last wraps
  self.keyRepeat = opts.keyRepeat  -- hold Up/Down (and pageJump L/R) to scroll
  self.repeatDelay = opts.repeatDelay or REPEAT_DELAY
  self.repeatRate = opts.repeatRate or REPEAT_RATE
  self.holdDir = nil
  self.holdFrames = 0
  self.onSelectKey = opts.onSelectKey -- SELECT pressed on an item
  -- scripted mode (the old man tutorial): update() runs the script
  -- every frame INSTEAD of reading input -- DisplayListMenuID's old-man
  -- branch (home/list_menu.asm:65-80) never calls HandleMenuInput
  self.script = opts.script
  -- shop mode: the footer becomes the clerk's line in a framed bottom
  -- text box, a money box sits top-right, and the list shortens to
  -- clear them (DisplayPokemartDialogue_'s screen)
  self.dialogue = opts.dialogue
  -- PC item lists (players_pc.asm): PrintListMenuEntries shows 4 names
  -- and PrintText footers ("How many?", stored/withdrew) use the standard
  -- bottom text box — same row budget as the mart, without the money box.
  self.messageBox = opts.messageBox
  self.money = opts.money          -- () -> current money for the box
  self.rows = opts.rows or ((opts.dialogue or opts.messageBox) and 4 or ROWS)
  return self
end

local function moveIndex(self, delta)
  local n = #self.items
  if n == 0 then return end
  local next = self.index + delta
  if self.wrap then
    next = ((next - 1) % n) + 1
  else
    next = math.max(1, math.min(n, next))
  end
  self.index = next
end

local function syncScroll(self)
  if self.index - self.scroll > self.rows then
    self.scroll = self.index - self.rows
  end
  if self.index - self.scroll < 1 then self.scroll = self.index - 1 end
end

-- edge press or key-repeat tick for a held direction
local function navPressed(self, dir)
  if dir == "up" then
    moveIndex(self, -1)
  elseif dir == "down" then
    moveIndex(self, 1)
  elseif dir == "left" and self.pageJump then
    moveIndex(self, -self.rows)
  elseif dir == "right" and self.pageJump then
    moveIndex(self, self.rows)
  else
    return false
  end
  syncScroll(self)
  return true
end

function ListMenu:update(dt)
  if self.script then
    self.script(self)
    return
  end
  local input = self.game.input
  if #self.items == 0 then
    if input:wasPressed("a") or input:wasPressed("b") then
      self.game.stack:pop()
      if self.onCancel then self.onCancel() end
    end
    return
  end

  local moved = false
  if input:wasPressed("up") then
    moved = navPressed(self, "up")
    self.holdDir, self.holdFrames = "up", 0
  elseif input:wasPressed("down") then
    moved = navPressed(self, "down")
    self.holdDir, self.holdFrames = "down", 0
  elseif self.pageJump and input:wasPressed("left") then
    moved = navPressed(self, "left")
    self.holdDir, self.holdFrames = "left", 0
  elseif self.pageJump and input:wasPressed("right") then
    moved = navPressed(self, "right")
    self.holdDir, self.holdFrames = "right", 0
  elseif self.onSelectKey and input:wasPressed("select") then
    self.onSelectKey(self.items[self.index], self)
  elseif input:wasPressed("b") then
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
    return
  elseif input:wasPressed("a") then
    local item = self.items[self.index]
    if self.onChoose then
      self.onChoose(item, self)
    end
    return
  end

  -- hold-to-scroll (opt-in via ui.list_menu keyRepeat)
  if self.keyRepeat then
    local dir = self.holdDir
    if dir and input:isDown(dir) then
      self.holdFrames = self.holdFrames + 1
      local afterDelay = self.holdFrames - self.repeatDelay
      if afterDelay >= 0 and afterDelay % self.repeatRate == 0 then
        navPressed(self, dir)
      end
    else
      self.holdDir, self.holdFrames = nil, 0
    end
  end

  if not moved then syncScroll(self) end
end

-- remove current item (e.g. consumed); keeps cursor valid
function ListMenu:removeCurrent()
  table.remove(self.items, self.index)
  self.index = math.max(1, math.min(self.index, #self.items))
end

function ListMenu:close()
  local top = self.game.stack:top()
  if top == self then self.game.stack:pop() end
end

function ListMenu:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.title, 8, 4)
  if #self.items == 0 then
    Font.draw("Nothing here.", 16, 64)
  end
  for row = 1, self.rows do
    local i = self.scroll + row
    local item = self.items[i]
    if not item then break end
    local y = 8 + row * 16
    Font.draw(item.label, 16, y)
    if item.ball then -- the Pokédex owned-ball marker tile
      -- one blank glyph after the name, measured in glyph advances rather
      -- than bytes: NIDORAN♂/♀ carry a multi-byte charmap entry, so
      -- `#item.label` overcounted by 2 and pushed their ball 16px right (#285)
      local bx = 16 + Font.width(item.label) + 8 + 3
      local by = y + 3
      love.graphics.circle("fill", bx, by, 3.5)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.rectangle("fill", bx - 3.5, by - 0.5, 7, 1)
      love.graphics.circle("fill", bx, by, 1.2)
      love.graphics.setColor(0, 0, 0, 1)
    end
    if item.right then
      Font.draw(item.right, 160 - 8 - Font.width(item.right), y)
    end
    if i == self.index then
      -- hollowIndex: a chosen row keeps the hollow '▷' left behind by
      -- pokered's PlaceUnfilledArrowMenuCursor (the old man demo's
      -- auto A-press, home/list_menu.asm:89-91)
      Font.drawCode((self.swapIndex == i or self.hollowIndex == i)
                    and Theme.cursorHollow or Theme.cursor, 8, y)
    end
    if self.swapIndex == i and i ~= self.index then
      Font.drawCode(Theme.cursorHollow, 8, y) -- ▷ marks the item being moved
    end
  end
  if self.dialogue then
    -- money box (DisplayTextBoxID MONEY_BOX, hlcoord 11,0): the amount
    -- right-aligned on its middle row
    Font.drawBox(11, 0, 9, 3)
    love.graphics.setColor(0, 0, 0, 1)
    local money = ("¥%d"):format(self.money and self.money() or 0)
    Font.draw(money, 152 - Font.width(money), 8)
  end
  if self.dialogue or (self.messageBox and self.footer) then
    -- standard bottom text box (PrintText); long prompts wrap and keep
    -- their last two lines, like the GB's scrolled box (#115/#174)
    Font.drawBox(0, 12, 20, 6)
    love.graphics.setColor(0, 0, 0, 1)
    if self.footer then
      local flat = {}
      for _, page in ipairs(require("src.render.TextBox").paginate(self.footer)) do
        for _, line in ipairs(page) do flat[#flat + 1] = line end
      end
      local y = 112
      for i = math.max(1, #flat - 1), #flat do
        Font.draw(flat[i], 8, y)
        y = y + 16
      end
    end
  elseif self.footer then
    -- bare footer (bag money line, etc.)
    local flat = {}
    for _, page in ipairs(require("src.render.TextBox").paginate(self.footer)) do
      for _, line in ipairs(page) do flat[#flat + 1] = line end
    end
    local y = (#flat >= 2) and 120 or 136
    for i = math.max(1, #flat - 1), #flat do
      Font.draw(flat[i], 8, y)
      y = y + 16
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return ListMenu
