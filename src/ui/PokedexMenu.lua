-- Pokédex CONTENTS screen: engine/menus/pokedex.asm:157-348
-- (Yellow: pokeyellow engine/menus/pokedex.asm:263-336).

local Font = require("src.render.Font")
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")
local MenuRepeat = require("src.ui.MenuRepeat")

local PokedexMenu = {}
PokedexMenu.__index = PokedexMenu
PokedexMenu.isOpaque = true

-- engine/menus/pokedex.asm:226 (`ld d, 7`), :21 (top menu item Y 3, X 0)
local ROWS = 7
local FIRST_ROW_Y = 24
local NUM_X, BALL_X, NAME_X, CURSOR_X = 8, 24, 32, 0

-- engine/menus/pokedex.asm:163-199
-- (Yellow: pokeyellow engine/menus/pokedex.asm:266-306)
local RED_ROWS = { seen = 2, own = 5, rule = 8, items = 10 }
local YELLOW_ROWS = { seen = 1, own = 4, rule = 6, items = 8 }

-- engine/menus/pokedex.asm:350 (DrawPokedexVerticalLine): column 14, $71
-- toggling to $70 down each nine-tile run, both runs restarting on $71
local function dividerCodes()
  local codes = { [0] = 0x71 }
  for _, top in ipairs({ 1, 9 }) do
    local code = 0x71
    for i = 0, 8 do
      codes[top + i] = code
      code = code == 0x71 and 0x70 or 0x71
    end
  end
  return codes
end
local DIVIDER = dividerCodes()

-- SGB: PalPacket_Pokedex, whole screen
function PokedexMenu:sgbPalettes(game)
  return require("src.render.PaletteFX").wholeNamed(game.data, "BROWNMON")
end

function PokedexMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, PokedexMenu)
  self.game = game
  self.onCancel = opts.onCancel -- B returns to the start menu when opened from it
  self.index = 1
  self.scroll = 0
  -- engine/menus/pokedex.asm:13
  self.hold = MenuRepeat.new(MenuRepeat.GEN1_DELAY, MenuRepeat.GEN1_RATE)
  self.rowsAt = require("src.core.GameVersion").isYellow()
    and YELLOW_ROWS or RED_ROWS
  local dex = game.save.pokedex or { seen = {}, owned = {} }
  local byDex = {}
  for species, def in pairs(game.data.pokemon) do
    if def.dex then byDex[def.dex] = def end
  end
  -- dex bound and number width come from constants; the fallbacks keep a
  -- cache imported before those keys existed on the Kanto numbering
  local constants = game.data.constants or {}
  local numFmt = ("%%0%dd"):format(constants.dexDigits or 3)
  local dexSize = constants.dexSize or 151
  -- engine/menus/pokedex.asm:200-216: the list stops at wDexMaxSeenMon, the
  -- highest number the player has seen, not at the end of the roster
  local maxSeen = 0
  local seen, owned = 0, 0
  for n = 1, dexSize do
    local def = byDex[n]
    if def then
      if dex.owned[def.id] then
        owned = owned + 1
        seen = seen + 1
        maxSeen = n
      elseif dex.seen[def.id] then
        seen = seen + 1
        maxSeen = n
      end
    end
  end
  local items = {}
  for n = 1, math.min(dexSize, maxSeen) do
    local def = byDex[n]
    if def then
      local known = dex.owned[def.id] or dex.seen[def.id]
      -- engine/menus/pokedex.asm:265 (.dashedLine) for anything unseen
      local name = known and def.name or "----------"
      items[#items + 1] = {
        num = numFmt:format(n),
        name = name,
        label = (numFmt .. " %s"):format(n, name),
        -- owned entries carry the pokéball marker like the original
        -- list; seen-only entries are just the name
        ball = dex.owned[def.id] or nil,
        value = known and def.id or nil,
      }
    end
  end
  self.items = items
  -- SEEN / OWN, `lb bc, 1, 3` at hlcoord 16,3 and 16,6: engine/menus/
  -- pokedex.asm HandlePokedexListMenu (#639)
  self.seenCount, self.ownedCount = seen, owned
  self.footer = Strings("SEEN %3d  OWN %3d", seen, owned)
  return self
end

-- HandleMenuInput_ replays SFX_PRESS_AB for A and B (home/window.asm)
local function beep(self)
  if not (self.game and self.game.data) then return end
  require("src.core.Sound").play(self.game.data, "Press_AB")
end

function PokedexMenu:rows()
  return math.min(ROWS, #self.items)
end

-- engine/menus/pokedex.asm:290-313
function PokedexMenu:syncScroll()
  local rows = self:rows()
  if rows == 0 then
    self.index, self.scroll = 1, 0
    return
  end
  self.index = math.max(1, math.min(#self.items, self.index))
  if self.index - self.scroll > rows then self.scroll = self.index - rows end
  if self.index - self.scroll < 1 then self.scroll = self.index - 1 end
end

-- engine/menus/pokedex.asm:314-342: Left and Right move wListScrollOffset
-- by seven and never touch wCurrentMenuItem, so the cursor keeps its row
function PokedexMenu:pageScroll(dir)
  local n = #self.items
  if n < ROWS then return end
  local row = self.index - self.scroll
  local scroll = self.scroll + dir * ROWS
  scroll = math.max(0, math.min(n - ROWS, scroll))
  self.scroll = scroll
  self.index = math.min(n, scroll + row)
end

function PokedexMenu:close()
  local top = self.game.stack:top()
  if top == self then self.game.stack:pop() end
end

function PokedexMenu:update(dt)
  -- back on top of the stack, so the side menu's hollow '▷' is gone
  -- (engine/menus/pokedex.asm:61, PlaceUnfilledArrowMenuCursor)
  self.hollowIndex = nil
  local input = self.game.input
  if #self.items == 0 then
    if input:wasPressed("a") or input:wasPressed("b") then
      beep(self)
      self.game.stack:pop()
      if self.onCancel then self.onCancel() end
    end
    return
  end
  local dir = MenuRepeat.direction(self.hold, input)
  if dir == "up" then
    self.index = self.index - 1
  elseif dir == "down" then
    self.index = self.index + 1
  elseif dir == "left" then
    self:pageScroll(-1)
  elseif dir == "right" then
    self:pageScroll(1)
  elseif input:wasPressed("b") then
    beep(self)
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
    return
  elseif input:wasPressed("a") then
    beep(self)
    self.onChoose(self.items[self.index], self)
    return
  end
  self:syncScroll()
end

-- engine/menus/pokedex.asm:371-375, :81-85
function PokedexMenu:sideItems()
  local labels = { Strings("DATA"), Strings("CRY"), Strings("AREA") }
  if require("src.core.GameVersion").isYellow() then
    labels[#labels + 1] = Strings("PRNT")
  end
  labels[#labels + 1] = Strings("QUIT")
  return labels
end

local function sideRowY(menu, row)
  return (menu.ty + menu.th - 2 - (#menu.items - row) * 2) * 8
end

local function drawSideMenu(self)
  love.graphics.setColor(0, 0, 0, 1)
  for row = 1, #self.items do
    Font.draw(self.items[row].label, (self.tx + 2) * 8, sideRowY(self, row))
  end
  Font.drawCode(Theme.cursor, (self.tx + 1) * 8, sideRowY(self, self.index))
  love.graphics.setColor(1, 1, 1, 1)
end

-- engine/menus/pokedex.asm HandlePokedexSideMenu, ShowPokedexMenu
-- .exitPokedex (#571)
local function chooseEntry(item, dexList)
  local game = dexList.game
  -- engine/menus/pokedex.asm:77-80: an unseen row hands back b=2 at once
  if not item.value then return end
  local Menu = require("src.ui.Menu")
  local Screens = require("src.ui.Screens")
  local entries = {
    { label = Strings("DATA"), onSelect = function()
        Screens.push(game, "DexEntryMenu", item.value)
      end },
    { label = Strings("CRY"), keepOpen = true, onSelect = function()
        require("src.core.Sound").playCry(game.data, item.value)
      end },
    { label = Strings("AREA"), onSelect = function()
        Screens.push(game, "TownMap", { nestSpecies = item.value })
      end },
  }
  -- pokeyellow engine/menus/pokedex.asm PokedexMenuItemsText,
  -- PrintPokedexEntry
  if require("src.core.GameVersion").isYellow() then
    entries[#entries + 1] = { label = Strings("PRNT"), onSelect = function()
      local DexEntryMenu = require("src.ui.DexEntryMenu")
      local Printer = require("src.core.Printer")
      local TextBox = require("src.render.TextBox")
      local def = game.data.pokemon[item.value]
      local path = require("src.pokemon.Sprites").path(
        game.data, item.value, "front", { kind = "dex" })
      local ok, sprite = false, nil
      if path then ok, sprite = pcall(love.graphics.newImage, path) end
      local saved, err = Printer.save("dex_" .. item.value, 160, 144,
        function()
          DexEntryMenu.render(game, def, ok and sprite or nil, false)
        end)
      game.stack:push(TextBox.new(game, saved
        and (Strings("Printed %s's\ndata!\f", def.name)
             .. Printer.savedWhereText(saved))
        or Strings("Printer error!\n%s", tostring(err))))
    end }
  end
  entries[#entries + 1] = { label = Strings("QUIT"), onSelect = function()
    -- engine/menus/pokedex.asm .exitPokedex
    dexList:close()
    if dexList.onCancel then dexList.onCancel() end
  end }
  local ty = dexList.rowsAt.items - 2
  local side = Menu.new(game, entries, { tx = 14, ty = ty, tw = 6 })
  -- the block is already on screen, so the side menu is the cursor alone:
  -- text at column 16, cursor at 15 (engine/menus/pokedex.asm:82-86)
  side.tx, side.tw, side.ty, side.th = 14, 6, ty, #entries * 2 + 2
  side.draw = drawSideMenu
  dexList.hollowIndex = dexList.index
  game.stack:push(side)
end
PokedexMenu.onChoose = chooseEntry

-- engine/menus/pokedex.asm:256, engine/gfx/load_pokedex_tiles.asm:8-11
local function drawBall(game, x, y)
  local DexEntryMenu = require("src.ui.DexEntryMenu")
  love.graphics.setColor(1, 1, 1, 1)
  DexEntryMenu.tile(game, 0x72, x / 8, y / 8)
  love.graphics.setColor(0, 0, 0, 1)
end

function PokedexMenu:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  local at = self.rowsAt
  local DexEntryMenu = require("src.ui.DexEntryMenu")
  -- engine/menus/pokedex.asm:159-176: the divider column and the rule that
  -- fences SEEN / OWN off from the side-menu block
  for ty = 0, 17 do
    DexEntryMenu.tile(self.game, DIVIDER[ty], 14, ty)
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(("─"):rep(5), 120, at.rule * 8)
  Font.draw(Strings("CONTENTS"), 8, 8)
  Font.draw(Strings("SEEN"), 128, at.seen * 8)
  Font.draw(Strings("OWN"), 128, at.own * 8)
  -- PrintNumber's fixed three-digit field ends on column 19
  local function count(n, ty)
    local text = tostring(n)
    Font.draw(text, 152 - Font.width(text), ty * 8)
  end
  count(self.seenCount, at.seen + 1)
  count(self.ownedCount, at.own + 1)
  local labels = self:sideItems()
  for i, label in ipairs(labels) do
    Font.draw(label, 128, (at.items + (i - 1) * 2) * 8)
  end
  for row = 1, self:rows() do
    local i = self.scroll + row
    local item = self.items[i]
    if not item then break end
    local y = FIRST_ROW_Y + (row - 1) * 16
    -- the number sits one row above its name (engine/menus/pokedex.asm:242-246)
    Font.draw(item.num, NUM_X, y - 8)
    if item.ball then drawBall(self.game, BALL_X, y) end
    Font.draw(item.name, NAME_X, y)
    if i == self.index then
      Font.drawCode(self.hollowIndex == i
                    and Theme.cursorHollow or Theme.cursor, CURSOR_X, y)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return PokedexMenu
