-- Generic full-screen scrollable list: items are { label=..., right=...,
-- value=... }; onChoose(item) / onCancel().  Used by the bag, shops, the
-- box and the Pokédex.

local Font = require("src.render.Font")
local Runtime = require("src.mods.Runtime")
local Theme = require("src.ui.Theme")
local MenuRepeat = require("src.ui.MenuRepeat")
local Strings = require("src.core.Strings")

local ListMenu = {}
ListMenu.__index = ListMenu
ListMenu.isOpaque = true

-- SGB: generic whole-screen palette (SET_PAL_GENERIC)
function ListMenu:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
end

local BLACK = { 0, 0, 0, 1 }
local MUTED_TEXT = { 0.55, 0.55, 0.55, 1 }

-- row text runs from x=16 to the 160px screen's right margin (160-8, same
-- margin item.right right-aligns against); GAP is the blank strip kept
-- between a truncated label and item.right so the two never touch.
local ROW_LEFT = 16
local ROW_RIGHT_MARGIN = 160 - 8
local LABEL_GAP = 4

-- Truncate `text` to `pixels`, same convention as WideBattle.lua's own
-- fitName (HP-bar names facing the identical "arbitrary text vs. fixed
-- pixel budget" problem): cut on a whole glyph span, never mid-character,
-- and mark the cut with a trailing '.'. ShaderFXScreen's preset names are
-- player-supplied filenames of arbitrary length -- unclipped, a long one
-- either overlapped/garbled item.right's "CONVERT" hint or ran past the
-- screen's right edge outright.
local function fitLabel(text, pixels)
  local spans = Font.split(text or "")
  local n = Font.spansFitting(spans, pixels)
  if n >= #spans then return text or "" end
  local out = {}
  for i = 1, math.max(0, n - 1) do
    out[#out + 1] = (text or ""):sub(spans[i].from, spans[i].to)
  end
  return table.concat(out) .. "."
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
-- Delay3 (home/list_menu.asm:61-64, 338-342, 47; home/window.asm:14-18)
local SCROLL_BLANK = 3
-- menu idles (home/window.asm:26-35, 217-263)
local ARROW_BLINK_PERIOD = 60
local ARROW_BLINK_ON = 30
-- frames to wait before key-repeat kicks in, then between repeats
local REPEAT_DELAY = MenuRepeat.GEN1_DELAY
local REPEAT_RATE = MenuRepeat.GEN1_RATE
local UPDOWN_DIRS = { "up", "down" }
local NAV_DIRS = { "up", "down", "left", "right" }

-- ui.list_menu identity: unhooked opts pass through unchanged
local function sameOpts(opts) return opts end

function ListMenu.new(game, title, items, opts)
  opts = opts or {}
  -- home/list_menu.asm:8
  opts.keyRepeat = opts.keyRepeat ~= false
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
  self.cursorBlank = 0
  self.arrowBlink = 0
  self.onChoose = opts.onChoose
  self.onCancel = opts.onCancel
  self.footer = opts.footer
  self.pageJump = opts.pageJump    -- Left/Right move a page at a time
  self.wrap = opts.wrap            -- Up on first / Down on last wraps
  self.keyRepeat = opts.keyRepeat  -- hold Up/Down (and pageJump L/R) to scroll
  self.repeatDelay = opts.repeatDelay or REPEAT_DELAY
  self.repeatRate = opts.repeatRate or REPEAT_RATE
  self.hold = MenuRepeat.new(self.repeatDelay, self.repeatRate, self.keyRepeat)
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
  -- screen of its own (home/list_menu.asm:29-31).  Every DisplayListMenuID
  -- caller gets the same box, the PC item lists included (#1845).
  self.itemBox = opts.itemBox or opts.messageBox or false
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
  local before = self.scroll
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
  -- the loop reaches PlaceMenuCursor again (home/list_menu.asm:176-190)
  if self.itemBox and self.scroll ~= before then
    self.cursorBlank = SCROLL_BLANK
  end
  -- (home/window.asm:29-35; home/list_menu.asm:518-524)
  self.arrowBlink = 0
  return true
end

function ListMenu:update(dt)
  if self.script then
    self.script(self)
    return
  end
  -- home/window.asm:119-192; engine/menus/start_sub_menus.asm:330-337
  self.hollowIndex = nil
  if (self.cursorBlank or 0) > 0 then self.cursorBlank = self.cursorBlank - 1 end
  -- home/window.asm:32-33, 217-263
  self.arrowBlink = ((self.arrowBlink or 0) + 1) % ARROW_BLINK_PERIOD
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
  local dir = MenuRepeat.direction(self.hold, input,
                                   self.pageJump and NAV_DIRS or UPDOWN_DIRS)
  if dir then
    moved = navPressed(self, dir)
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

-- standard bottom text box (PrintText); long prompts wrap and keep
-- their last two lines, like the GB's scrolled box (#115/#174)
local function drawMessageBox(self)
  Font.drawBox(0, 12, 20, 6)
  love.graphics.setColor(0, 0, 0, 1)
  if not self.footer then return end
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

-- the Pokédex owned-ball marker tile, also the CHANGE BOX screen's
-- PokeballTileGraphics marker (engine/menus/save.asm:495-499)
function ListMenu.drawBall(x, y)
  local r, g, b, a = love.graphics.getColor()
  love.graphics.circle("fill", x, y, 3.5)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", x - 3.5, y - 0.5, 7, 1)
  love.graphics.circle("fill", x, y, 1.2)
  love.graphics.setColor(r, g, b, a)
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
  local shown, sawCancel = 0, false
  for row = 1, self.rows do
    local i = self.scroll + row
    local item = self.items[i]
    if not item then break end
    shown = shown + 1
    if item.cancel then sawCancel = true end
    local y = ITEM_TOP_Y + (row - 1) * 16
    Font.draw(item.label, ITEM_NAME_X, y)
    if item.sub then
      -- PrintLevel, one row down and 8 columns right (home/list_menu.asm:459-461)
      Font.draw(item.sub, ITEM_QTY_X, y + 8)
    elseif item.price then
      -- home/list_menu.asm:410-424
      Font.draw(item.price, ITEM_QTY_END - Font.width(item.price), y + 8)
    elseif item.count then
      -- '×' at column 14, PrintNumber's two right-aligned digits after it
      -- (home/list_menu.asm:479-490)
      local count = tostring(item.count)
      Font.draw("\xc3\x97", ITEM_QTY_X, y + 8)
      Font.draw(count, ITEM_QTY_END - Font.width(count), y + 8)
    elseif item.right then
      Font.draw(item.right, ITEM_QTY_END - Font.width(item.right), y + 8)
    end
    if i == self.index and (self.cursorBlank or 0) == 0 then
      Font.drawCode(self.hollowIndex == i
                    and Theme.cursorHollow or Theme.cursor, ITEM_CURSOR_X, y)
    end
    if self.swapIndex == i and i ~= self.index then
      Font.drawCode(Theme.cursorHollow, ITEM_CURSOR_X, y)
    end
  end
  -- the terminator prints CANCEL and returns before the '▼'
  -- (home/list_menu.asm:372, 518-524)
  if shown == self.rows and not sawCancel
     and (self.arrowBlink or 0) < ARROW_BLINK_ON then
    Font.drawCode(Theme.moreArrow, ITEM_MORE_X, ITEM_MORE_Y)
  end
  -- players_pc.asm:97/151/205 PrintText the prompt before DisplayListMenuID,
  -- so the bottom box sits under the list from the first frame
  if self.messageBox or self.footer then drawMessageBox(self) end
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
    -- item.muted: a real, selectable row that isn't fully "ready" yet (e.g.
    -- ShaderFXScreen's unconverted presets) -- readable, never hidden, same
    -- "always still readable" convention kit/Theme.lua's own disabled state
    -- documents, just not the generic list-item shape that lived here
    -- before ShaderFXScreen needed it.
    local textColor = item.muted and MUTED_TEXT or BLACK
    love.graphics.setColor(unpack(textColor))
    local budget = ROW_RIGHT_MARGIN - ROW_LEFT
    if item.right then budget = budget - Font.width(item.right) - LABEL_GAP end
    local label = fitLabel(item.label, budget)
    Font.draw(label, 16, y)
    if item.ball then -- the Pokédex owned-ball marker tile
      -- one blank glyph after the name, measured in glyph advances rather
      -- than bytes: NIDORAN♂/♀ carry a multi-byte charmap entry, so
      -- `#item.label` overcounted by 2 and pushed their ball 16px right (#285)
      ListMenu.drawBall(16 + Font.width(label) + 8 + 3, y + 3)
    end
    if item.right then
      Font.draw(item.right, 160 - 8 - Font.width(item.right), y)
    end
    love.graphics.setColor(unpack(BLACK))
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
  if self.dialogue then
    drawMessageBox(self)
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
