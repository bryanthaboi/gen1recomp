-- Generic full-screen scrollable list: items are { label=..., right=...,
-- value=... }; onChoose(item) / onCancel().  Used by the bag, shops, the
-- box and the Pokédex.

local Font = require("src.render.Font")
local Runtime = require("src.mods.Runtime")
local Theme = require("src.ui.Theme")
local Strings = require("src.core.Strings")

local ListMenu = {}
ListMenu.__index = ListMenu
ListMenu.isOpaque = true

-- SGB: generic whole-screen palette (SET_PAL_GENERIC)
function ListMenu:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end

local ROWS = 7
-- LIST_MENU_BOX 4,2 - 19,12 (data/text_boxes.asm:13); 4 names from
-- hlcoord 6,4 two rows apart (home/list_menu.asm:51-52, 364-365, 471-479)
local ITEM_BOX = { tx = 4, ty = 2, tw = 16, th = 11 }
local ITEM_ROWS = 4
local ITEM_NAME_X, ITEM_TOP_Y = 48, 32
local ITEM_CURSOR_X = 40
local ITEM_QTY_X, ITEM_QTY_END = 112, 136
local ITEM_MORE_X, ITEM_MORE_Y = 144, 88
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
  self.kind = opts.kind or title
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
  -- bottom text box -- same row budget as the mart, without the money box.
  self.messageBox = opts.messageBox
  self.money = opts.money          -- () -> current money for the box
  -- BIT_NO_MENU_BUTTON_SOUND (wMiscFlags): both PC sessions hold the flag
  -- for their whole run (engine/menus/pc.asm, engine/menus/players_pc.asm),
  -- so their lists opt out of the A/B beep the same way Menu's noSound does
  self.noSound = opts.noSound or false
  -- the bag's item list: a partial box the map stays visible around, not a
  -- screen of its own (home/list_menu.asm:29-31)
  self.itemBox = opts.itemBox or false
  if self.itemBox then
    self.isOpaque = false
    -- keep RunDefaultPaletteCommand's last palette: ItemMenuLoop never sets
    -- its own (engine/menus/start_sub_menus.asm:300)
    self.sgbPalettes = false
    -- wMaxMenuItem is 2 for item lists; the fourth printed row is a
    -- look-ahead the cursor cannot reach (home/list_menu.asm:46-48)
    self.cursorRows = 3
  end
  self.rows = opts.rows or (self.itemBox and ITEM_ROWS)
    or ((opts.dialogue or opts.messageBox) and 4 or ROWS)
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
  local maxRow = self.cursorRows or self.rows
  if self.index - self.scroll > maxRow then
    self.scroll = self.index - maxRow
  end
  if self.index - self.scroll < 1 then self.scroll = self.index - 1 end
end

-- HandleMenuInput_ (home/window.asm) replays SFX_PRESS_AB for any watched
-- A or B press; DisplayListMenuID's mask is PAD_A | PAD_B | PAD_SELECT
-- (home/list_menu.asm), so the SELECT swap key stays silent (#570)
local function beep(self)
  -- game.data is nil under the UI harnesses that drive a list with a stub
  -- game (tests/engine/rebind_capture_bug510.lua), where there is no audio
  -- cache to play out of
  if self.noSound or not (self.game and self.game.data) then return end
  require("src.core.Sound").play(self.game.data, "Press_AB")
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
      beep(self)
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
    beep(self)
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
    return
  elseif input:wasPressed("a") then
    beep(self)
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

-- PrintListMenuEntries, minus the price column StartMenu_Item never asks for
-- (wPrintItemPrices = 0, engine/menus/start_sub_menus.asm)
function ListMenu:drawItemBox()
  love.graphics.setColor(1, 1, 1, 1)
  Font.drawBox(ITEM_BOX.tx, ITEM_BOX.ty, ITEM_BOX.tw, ITEM_BOX.th)
  love.graphics.setColor(0, 0, 0, 1)
  if #self.items == 0 then
    Font.draw(Strings("Nothing here."), ITEM_NAME_X, ITEM_TOP_Y)
  end
  local shown = 0
  for row = 1, self.rows do
    local i = self.scroll + row
    local item = self.items[i]
    if not item then break end
    shown = shown + 1
    local y = ITEM_TOP_Y + (row - 1) * 16
    Font.draw(item.label, ITEM_NAME_X, y)
    if item.right then
      -- '×' at column 14, PrintNumber's two right-aligned digits after it
      -- (home/list_menu.asm:479-490)
      local count = item.right:sub(2)
      Font.draw(item.right:sub(1, 1), ITEM_QTY_X, y + 8)
      Font.draw(count, ITEM_QTY_END - Font.width(count), y + 8)
    end
    if i == self.index then
      Font.drawCode(self.hollowIndex == i
                    and Theme.cursorHollow or Theme.cursor, ITEM_CURSOR_X, y)
    end
    if self.swapIndex == i and i ~= self.index then
      Font.drawCode(Theme.cursorHollow, ITEM_CURSOR_X, y)
    end
  end
  -- the terminator prints CANCEL and returns before the '▼'
  -- (home/list_menu.asm:372, 518-524)
  if shown == self.rows then
    Font.drawCode(Theme.moreArrow, ITEM_MORE_X, ITEM_MORE_Y)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function ListMenu:draw()
  if self.itemBox then return self:drawItemBox() end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings(self.title), 8, 4)
  if #self.items == 0 then
    Font.draw(Strings("Nothing here."), 16, 64)
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
      -- auto A-press, home/list_menu.asm:89-91).  A swap-marked row does
      -- NOT stay hollow under the cursor: PlaceMenuCursor writes '▶'
      -- into the tilemap over the '▷' whenever the cursor sits there
      -- (home/window.asm:184-185) and restores it on the way out (#814)
      Font.drawCode(self.hollowIndex == i
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
