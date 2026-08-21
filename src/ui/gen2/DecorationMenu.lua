-- The bedroom PC's DECORATION option: _PlayerDecorationMenu
-- (engine/overworld/decorations.asm), reached from PLAYERSPCITEM_DECORATION in
-- the PLAYERSPC_HOUSE list (engine/events/pokecenter_pc.asm).
--
-- Two menus stacked, plus one question:
--
--   .MenuHeader           the categories the player owns something in, at
--                         menu_coords 5, 0, 19, 17, with EXIT always last
--   .NonscrollingMenuHeader / .ScrollingMenuHeader
--                         that category's decorations, then its PUT IT AWAY
--                         row, then CANCEL.  The cart swaps to the scrolling
--                         menu past eight rows; one list that scrolls covers
--                         both, since the rows are identical either way
--   DecoSideMenuHeader    RIGHT SIDE / LEFT SIDE / CANCEL, for the two
--                         ornament slots
--
-- Nothing here touches the map.  wChangedDecorations is carried back through
-- onDone so the PC can answer TRUE to `special PlayersHousePC`, whose script
-- then does `warp NONE, 0, 0` -- the map reload that runs the two callbacks
-- and is the only thing that makes a placement visible.

local Chrome = require("src.ui.gen2.Chrome")
local Decorations = require("src.core.gen2.Decorations")
local Strings = require("src.core.Strings")

local DecorationMenu = {}
DecorationMenu.__index = DecorationMenu
DecorationMenu.isOpaque = true

-- .category_pointers' eighth row, which is not a category and is always shown.
local EXIT = Strings.source("EXIT")
-- DecoSideMenuHeader's three items, in its order.
local SIDES = {
  { id = "right", label = Strings.source("RIGHT SIDE") },
  { id = "left", label = Strings.source("LEFT SIDE") },
  { id = nil, label = Strings.source("CANCEL") },
}

-- The scrolling list shows eight rows (.ScrollingMenuData's `db 8, 0`).
local VISIBLE = 8

function DecorationMenu:wantsFillScale() return true end

-- opts: save, events (the wEventFlags bitfield), onDone(changed)
function DecorationMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, DecorationMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.events = opts.events
  self.onDone = opts.onDone
  self.state = Decorations.state(self.save)
  -- wChangedDecorations, cleared once on the way in.
  self.changed = false
  self.mode = "category"
  self.index = 1
  self.scroll = 0
  self.pages = nil
  self:buildCategories()
  return self
end

function DecorationMenu:buildCategories()
  self.categories = Decorations.ownedCategories(self.events)
  self.index = math.min(self.index, #self.categories + 1)
end

function DecorationMenu:finish()
  if self.done then return end
  self.done = true
  if self.onDone then self.onDone(self.changed) end
end

-- The name of one row of the item list.  Row 0 is CANCEL and the category's
-- own row is PUT IT AWAY; both are plain DecorationAttributes rows, so they
-- spell themselves.
function DecorationMenu:rowName(decoId)
  return Decorations.name(decoId)
end

function DecorationMenu:openCategory(category)
  local rows = Decorations.rows(self.events, category)
  if #rows == 0 then
    -- PopulateDecoCategoryMenu .empty.  Cannot happen from the filtered
    -- category list, but the routine is reachable from a driver that sets a
    -- flag by hand, and the cart answers rather than opening an empty menu.
    self:say({ Strings(Decorations.NOTHING_TO_CHOOSE) })
    return
  end
  self.category = category
  self.rows = rows
  self.mode = "items"
  self.index = 1
  self.scroll = 0
end

function DecorationMenu:say(pages)
  if not pages or #pages == 0 then return end
  self.pages = pages
  self.pageIndex = 1
end

-- MenuTextboxBackup returns to whatever menu was underneath, so a message is
-- not a mode of its own: it sits over the list it was printed from.
function DecorationMenu:advanceMessage()
  self.pageIndex = self.pageIndex + 1
  if self.pageIndex <= #self.pages then return end
  self.pages = nil
end

-- One row of the item list chosen: DoDecorationAction2.  An ornament row asks
-- which side first, and only then applies.
function DecorationMenu:chooseRow(decoId)
  local attr = Decorations.attributes(decoId)
  local action = attr and attr.action and Decorations.ACTIONS[attr.action]
  if not action then
    -- DecoAction_nothing sets carry, which drops the player back to the
    -- category list without a word.
    self.mode = "category"
    self:buildCategories()
    return
  end
  if action.ornament then
    self.mode = "side"
    self.pendingDeco = decoId
    self.sideIndex = 1
    return
  end
  self:applyRow(decoId, nil)
end

function DecorationMenu:applyRow(decoId, side)
  local changed, pages = Decorations.apply(self.state, decoId, side)
  if changed then
    self.changed = true
    local attr = Decorations.attributes(decoId)
    local action = attr and attr.action and Decorations.ACTIONS[attr.action]
    if action and action.ornament and not action.put then
      Decorations.clearOtherSide(self.state, decoId, side)
    end
  end
  self:say(pages)
end

function DecorationMenu:update(_dt)
  local input = self.game and self.game.input
  if not (input and not self.done) then return end

  if self.pages then
    if input:wasPressed("a") or input:wasPressed("b") then
      self:advanceMessage()
    end
    return
  end

  if self.mode == "side" then
    if input:wasPressed("up") then
      self.sideIndex = self.sideIndex > 1 and self.sideIndex - 1 or #SIDES
    elseif input:wasPressed("down") then
      self.sideIndex = self.sideIndex < #SIDES and self.sideIndex + 1 or 1
    elseif input:wasPressed("a") then
      local pick = SIDES[self.sideIndex]
      self.mode = "items"
      -- .nope: CANCEL and B are the same arm, and neither prints anything.
      self:applyRow(self.pendingDeco, pick and pick.id)
      self.pendingDeco = nil
    elseif input:wasPressed("b") then
      self.mode = "items"
      self.pendingDeco = nil
    end
    return
  end

  if self.mode == "items" then
    local total = #self.rows
    if input:wasPressed("up") then
      self.index = self.index > 1 and self.index - 1 or total
    elseif input:wasPressed("down") then
      self.index = self.index < total and self.index + 1 or 1
    elseif input:wasPressed("a") then
      self:chooseRow(self.rows[self.index])
    elseif input:wasPressed("b") then
      self.mode = "category"
      self:buildCategories()
    end
    self.scroll = math.max(0,
      math.min(self.scroll, math.max(0, total - VISIBLE)))
    if self.index - 1 < self.scroll then self.scroll = self.index - 1 end
    if self.index > self.scroll + VISIBLE then
      self.scroll = self.index - VISIBLE
    end
    return
  end

  local total = #self.categories + 1
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or total
  elseif input:wasPressed("down") then
    self.index = self.index < total and self.index + 1 or 1
  elseif input:wasPressed("a") then
    local category = self.categories[self.index]
    if category then
      self:openCategory(category)
    else
      self:finish() -- DecoExitMenu: `scf`, which leaves the whole menu
    end
  elseif input:wasPressed("b") then
    self:finish()
  end
end

function DecorationMenu:drawList(x, y, w, h, labels, index, scroll)
  Chrome.box(x, y, w, h)
  -- GetMenuTextStartCoord: the first label sits one row inside the border and
  -- one more down for STATICMENU_CURSOR, and rows are two apart -- the same
  -- spacing every other Gold list menu in this port draws with.
  for row = 1, math.min(#labels - scroll, VISIBLE) do
    local i = row + scroll
    local ty = y + row * 2
    if i == index then Chrome.cursor(x + 1, ty) end
    Chrome.print(labels[i], x + 2, ty)
  end
end

function DecorationMenu:drawPanel()
  Chrome.clear()

  if self.mode == "category" then
    local labels = {}
    for i, category in ipairs(self.categories) do labels[i] = category.label end
    labels[#labels + 1] = Strings(EXIT)
    -- menu_coords 5, 0, 19, 17: the list hugs the right edge and the room
    -- stays visible down the left, which is the whole point of the offset.
    self:drawList(5, 0, 15, 18, labels, self.index, 0)
  elseif self.mode == "items" then
    local labels = {}
    for i, decoId in ipairs(self.rows) do labels[i] = self:rowName(decoId) end
    self:drawList(0, 0, 20, 18, labels, self.index, self.scroll)
  end

  if self.mode == "side" then
    local labels = {}
    for i, side in ipairs(SIDES) do labels[i] = Strings(side.label) end
    -- menu_coords 0, 0, 12, 7
    self:drawList(0, 0, 13, 8, labels, self.sideIndex, 0)
  end

  if self.pages then
    Chrome.box(0, 12, 20, 6)
    local line = 14
    for part in ((self.pages[self.pageIndex] or "") .. "\n"):gmatch("(.-)\n") do
      Chrome.print(part, 1, line)
      line = line + 2
    end
  end

  love.graphics.setColor(1, 1, 1, 1)
end

function DecorationMenu:draw()
  self:drawPanel()
end

function DecorationMenu:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

function DecorationMenu:drawsWidescreen() return true end

return DecorationMenu
