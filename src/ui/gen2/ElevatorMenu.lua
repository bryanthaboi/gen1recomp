-- The elevator's floor list (engine/events/elevator.asm Elevator_AskWhichFloor).
--
-- Three maps have one -- Celadon's and Goldenrod's dept stores, and the Radio
-- Tower -- and each names its floors in its own script bank with
-- `elevfloor floor, warp, map`.  The extractor follows that list now, so this
-- screen has floors to offer; before it did, `elevator` answered 0 and the
-- doors never opened.
--
-- Two panels, both transcribed:
--
--   "Now on:"   Elevator_GetCurrentFloorText -- `ld b, 4 / ld c, 8` at
--               hlcoord 0,0, i.e. a Textbox whose INTERIOR is 8 wide by 4
--               tall.  The label goes at (1,2) and the floor name at (4,4).
--   the list    Elevator_MenuHeader, `menu_coords 12, 1, 18, 9`, a SCROLLING
--               menu of `db 4, 0` -- four visible rows -- with
--               SCROLLINGMENU_DISPLAY_ARROWS.  Rows are two apart and the
--               first sits one below the border, which is the arithmetic
--               ScrollingMenu_PlaceCursor spells out: `dec a / add a / add $1`
--               added to wMenuBorderTopCoord.
--
-- The ride itself is Elevator_GoToFloor, which does NOT warp: it writes the
-- chosen row's warp number and destination map into wBackupWarpNumber /
-- wBackupMapGroup / wBackupMapNumber, and the elevator's own door warp -- a
-- `warp_event` whose destination warp is -1 -- reads them when the player
-- walks out.  World:takeWarp owns that half.

local Chrome = require("src.ui.gen2.Chrome")
local RomText = require("src.core.RomText")
local Sound = require("src.core.Sound")

local ElevatorMenu = {}
ElevatorMenu.__index = ElevatorMenu
ElevatorMenu.isOpaque = false

-- Elevator_GetCurrentFloorText's Textbox: interior 8x4 at (0,0).
local NOW_X, NOW_Y, NOW_W, NOW_H = 0, 0, 8, 4
local NOW_LABEL_X, NOW_LABEL_Y = 1, 2
local NOW_FLOOR_X, NOW_FLOOR_Y = 4, 4

-- Elevator_MenuHeader's `menu_coords 12, 1, 18, 9`, and
-- GetMenuTextStartCoord's border + cursor offsets on it.
local LIST_X, LIST_Y, LIST_W, LIST_H = 12, 1, 7, 9
local ITEM_X, ITEM_Y = 14, 2
local VISIBLE = 4

-- engine/events/elevator.asm:163
local NOW_ON = "Elevator_CurrentFloorText"

-- FloorToString hands back the FLOOR_* name; the cache's floorNames carries
-- the same strings out of ElevatorFloorNames.
function ElevatorMenu.floorName(floors, row)
  local name = type(floors) == "table" and row and floors[row + 1]
  if not name then
    error(("events.lua floorNames has no floor %s"):format(tostring(row)), 2)
  end
  return name
end

-- The scroll window a four-row list shows: the cursor stays inside it and the
-- window follows, which is what SCROLLINGMENU_DISPLAY_ARROWS' arrows mark.
function ElevatorMenu.scrollFor(index, count, scroll)
  scroll = scroll or 0
  if index - 1 < scroll then scroll = index - 1 end
  if index > scroll + VISIBLE then scroll = index - VISIBLE end
  return math.max(0, math.min(scroll, math.max(0, count - VISIBLE)))
end

-- opts: floors (the extracted elevfloor rows), currentMap (wBackupMapNumber's
--       map, i.e. the floor the player got in on), floorNames, onDone(row)
function ElevatorMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, ElevatorMenu)
  self.game = game
  self.data = (game and game.data) or {}
  self.floors = opts.floors or {}
  self.floorNames = opts.floorNames
  self.onDone = opts.onDone
  -- .FindCurrentFloor: the row whose destination map is the one the player
  -- came in from.  A miss is `scf` -- the whole command quits without a menu,
  -- which the caller checks before building this screen.
  self.origin = nil
  for i, row in ipairs(self.floors) do
    if row.destMap == opts.currentMap then self.origin = i break end
  end
  self.index = 1
  self.scroll = ElevatorMenu.scrollFor(self.index, #self.floors, 0)
  return self
end

function ElevatorMenu:wantsFillScale() return true end

function ElevatorMenu:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

function ElevatorMenu:finish(row)
  if self.done then return end
  self.done = true
  if self.onDone then self.onDone(row) end
end

function ElevatorMenu:update(_dt)
  if self.done then return end
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("up") and self.index > 1 then
    self.index = self.index - 1
  elseif input:wasPressed("down") and self.index < #self.floors then
    self.index = self.index + 1
  elseif input:wasPressed("b") then
    self:playSfx("Sfx_ReadText2")
    return self:finish(nil)
  elseif input:wasPressed("a") then
    self:playSfx("Sfx_ReadText2")
    -- `ld hl, wElevatorOriginFloor / cp [hl] / jr z, .quit`: picking the floor
    -- you are already on quits with carry, which is the same FALSE the cancel
    -- gives.  So the doors do not close and the script skips its own SFX.
    if self.index == self.origin then return self:finish(nil) end
    return self:finish(self.floors[self.index])
  end
  self.scroll = ElevatorMenu.scrollFor(self.index, #self.floors, self.scroll)
end

function ElevatorMenu:drawPanel()
  Chrome.textbox(NOW_X, NOW_Y, NOW_W, NOW_H)
  Chrome.print(RomText(self.data, NOW_ON), NOW_LABEL_X, NOW_LABEL_Y)
  local origin = self.origin and self.floors[self.origin]
  Chrome.print(
    ElevatorMenu.floorName(self.floorNames, origin and origin.floorId),
    NOW_FLOOR_X, NOW_FLOOR_Y)

  Chrome.box(LIST_X, LIST_Y, LIST_W, LIST_H)
  for slot = 1, math.min(VISIBLE, #self.floors) do
    local row = self.floors[self.scroll + slot]
    if row then
      Chrome.print(ElevatorMenu.floorName(self.floorNames, row.floorId),
        ITEM_X, ITEM_Y + (slot - 1) * 2)
    end
  end
  Chrome.cursor(ITEM_X - 1, ITEM_Y + (self.index - self.scroll - 1) * 2)
  love.graphics.setColor(1, 1, 1, 1)
end

function ElevatorMenu:draw()
  self:drawPanel()
end

return ElevatorMenu
