-- Generic bordered list menu with the blinking ▶ cursor.
-- items: { { label=..., onSelect=function }, ... }
-- Pops itself on B (unless cancelable=false); also on START only when
-- opts.startCloses is set -- pokered's wMenuWatchedKeys mask varies per
-- menu and only the start menu's adds PAD_START.

local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")

local Menu = {}
Menu.__index = Menu

function Menu.new(game, items, opts)
  local self = setmetatable({}, Menu)
  opts = opts or {}
  self.game = game
  self.items = items
  self.index = 1
  self.tx = opts.tx or 10
  self.ty = opts.ty or 0
  self.tw = opts.tw or 10
  -- grow the box to the widest label so longer (e.g. localized) labels don't
  -- overflow the frame; nudge tx left to keep the box on-screen (20 tiles).
  do
    local widest = 0
    for _, it in ipairs(items) do
      if it.label then
        local n = #Font.split(it.label)
        if n > widest then widest = n end
      end
    end
    local needed = widest + 3
    if needed > self.tw then self.tw = needed end
    if self.tx + self.tw > 20 then self.tx = math.max(0, 20 - self.tw) end
  end
  self.rowStep = opts.rowStep or 2
  -- maxVisible: cap the box to this many rows and scroll the rest instead
  -- of growing past it (e.g. the start menu, whose row count varies with
  -- save state and mod hooks); nil/unset keeps every caller's old
  -- behavior of sizing the box to fit all items.
  self.maxVisible = opts.maxVisible
  self.scroll = 0
  local visible = (self.maxVisible and math.min(self.maxVisible, #items))
    or #items
  self.th = opts.th or (visible * self.rowStep + 2)
  self.cancelable = opts.cancelable ~= false
  -- Whether START closes the menu.  In pokered a menu responds only to the
  -- keys in its wMenuWatchedKeys mask; the common PAD_A | PAD_B (and the
  -- list menu's PAD_A | PAD_B | PAD_SELECT) masks leave START unwatched, so
  -- only menus whose real mask includes PAD_START -- the start menu
  -- (engine/menus/draw_start_menu.asm) -- opt in here.
  self.startCloses = opts.startCloses or false
  -- screen-edge anchor for this menu (see Menu:draw); nil keeps it in the
  -- classic centred letterbox
  self.anchor = opts.anchor
  self.onCancel = opts.onCancel
  -- BIT_NO_MENU_BUTTON_SOUND (wMiscFlags): the PC session runs its
  -- menus silent (home/window.asm HandleMenuInput_)
  self.noSound = opts.noSound or false
  self:clampScroll()
  return self
end

-- keeps self.index inside the visible [scroll+1, scroll+maxVisible] window;
-- callers that move self.index directly (e.g. restoring a saved cursor
-- position) should call this afterwards to scroll it into view
function Menu:clampScroll()
  if not (self.maxVisible and #self.items > self.maxVisible) then
    self.scroll = 0
    return
  end
  if self.index - self.scroll > self.maxVisible then
    self.scroll = self.index - self.maxVisible
  elseif self.index - self.scroll < 1 then
    self.scroll = self.index - 1
  end
end

function Menu:update(dt)
  local input = self.game.input
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #self.items
  elseif input:wasPressed("down") then
    self.index = self.index < #self.items and self.index + 1 or 1
  elseif input:wasPressed("a") then
    -- HandleMenuInput_ (home/window.asm): SFX_PRESS_AB on every A press
    if not self.noSound then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    local item = self.items[self.index]
    -- keepOpen entries run without closing the menu (e.g. the
    -- Pokédex CRY option keeps the side menu up)
    if not item.keepOpen then self.game.stack:pop() end
    if item.onSelect then item.onSelect() end
  elseif self.cancelable and (input:wasPressed("b")
      or (self.startCloses and input:wasPressed("start"))) then
    -- HandleMenuInput_ returns for any watched key, but only replays
    -- SFX_PRESS_AB for the PAD_A | PAD_B branch -- so B beeps and START
    -- (when watched, e.g. the start menu) closes silently.
    if input:wasPressed("b") and not self.noSound then
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
  end
  self:clampScroll()
end

function Menu:draw()
  -- opts.anchor opts a menu out of the centred letterbox and onto a screen
  -- edge (the START menu asks for "topright").  Only menus that ask for it
  -- move; every other menu is placed exactly as before.
  local r = self.anchor and self.game and self.game.renderer
  if r and r.setUIAnchor then
    r:setUIAnchor(self.tx * 8, self.ty * 8,
                  self.tw * 8, self.th * 8, self.anchor)
  end
  Font.drawBox(self.tx, self.ty, self.tw, self.th)
  love.graphics.setColor(0, 0, 0, 1)
  local visible = (self.maxVisible and math.min(self.maxVisible, #self.items))
    or #self.items
  -- Row Y: pokered's boxed menus anchor the choices to the BOTTOM interior
  -- row and let any slack fall as a blank row under the top edge --
  -- draw_start_menu.asm (TextBoxBorder 10,0, then hlcoord 12,2 /
  -- wTopMenuItemY 2), players_pc.asm and bills_pc.asm all do the same.  The
  -- bottom border is ty + th - 1, so the last choice sits on ty + th - 2 and
  -- row r counts back up from there.  Anchoring from the top instead only
  -- agrees when th is exactly visible * rowStep + 2, which is Menu.new's
  -- default but NOT what a caller sizing its own box passes: BagMenu's
  -- USE/TOSS is th = 5 for two choices (#284, matching text_boxes.asm's
  -- USE_TOSS_MENU_TEMPLATE rows 10..14), and a top anchor pushed TOSS onto
  -- the bottom border (#564, #572).
  for row = 1, visible do
    local item = self.items[self.scroll + row]
    if not item then break end
    Font.draw(item.label, (self.tx + 2) * 8,
      (self.ty + self.th - 2 - (visible - row) * self.rowStep) * 8)
  end
  local cursorRow = self.index - self.scroll
  Font.drawCode(Theme.cursor, (self.tx + 1) * 8,
    (self.ty + self.th - 2 - (visible - cursorRow) * self.rowStep) * 8)
  -- moreArrow ($EE): the same "more below" glyph OptionRows/ManagerState
  -- use, sat on the bottom border like TextBox's page-advance cursor.  It
  -- has to be the border row, not ty + th - 2: that is the last interior
  -- row, which the last choice now occupies, and Menu.new widens the box to
  -- widest + 3 so tx + tw - 2 is exactly that label's final glyph (#564).
  if self.maxVisible and self.scroll + self.maxVisible < #self.items then
    Font.drawCode(Theme.moreArrow, (self.tx + self.tw - 2) * 8,
      (self.ty + self.th - 1) * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Menu
