-- Launcher Delete affordance (src/import/RomImporter.lua): the per-frame hit
-- rects a draw() clears, and the two-click arm that guards both save-slot and
-- mod deletes (#433).  Drives RomImporter:mousepressed / :_resetFrameRects on a
-- bare instance, so no window, no cache and no real save files are involved.
--   luajit tests/engine/launcher_delete_confirm.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- mousepressed timestamps the arm and expires it, so the clock has to move
local clock = 1000
love.timer.getTime = function() return clock end

local RomImporter = require("src.import.RomImporter")

local function rect(id, y)
  return { x = 100, y = y or 200, width = 40, height = 14, id = id }
end

-- Only the fields mousepressed reads on its way to the Delete loops, plus
-- recorders in place of the two destructive calls.
local function launcher()
  local self = setmetatable({}, RomImporter)
  self.android = false
  self.panelVersion = "red"
  self.tab = "red"
  self.slotScroll = {}
  self.deletedSlots = {}
  self.deletedMods = {}
  self.selected = {}
  self._deleteSlot = function(_, version, id)
    table.insert(self.deletedSlots, version .. "/" .. id)
  end
  self._deleteMod = function(_, id) table.insert(self.deletedMods, id) end
  self._selectSlot = function(_, version, id)
    table.insert(self.selected, version .. "/" .. id)
  end
  return self
end

local function clickDelete(self, r)
  self:mousepressed(r.x + 2, r.y + 2, 1)
end

-- ------- a frame that draws no panel leaves no Delete rect behind

do
  local self = launcher()
  self.slotDeleteRects = { rect("slot1") }
  self.modDeleteRects = { rect("bigmod", 260) }
  self.slotRects = { rect("slot1") }
  self.modRects = { rect("bigmod", 260) }
  self:_resetFrameRects()
  eq(self.slotDeleteRects, nil, "a frame reset drops the save Delete rects")
  eq(self.modDeleteRects, nil, "a frame reset drops the mod Delete rects")
  eq(self.slotRects, nil, "and the slot rows they sit on")
  eq(self.modRects, nil, "and the mod toggles")

  -- the reporter's click: mods tab is up, the press lands where the game tab
  -- drew Delete last time it was shown
  self.tab = "mods"
  clickDelete(self, rect("slot1"))
  eq(#self.deletedSlots, 0, "a press on a stale Delete spot deletes nothing")
end

-- ------- a save Delete needs two clicks on the same row

do
  local self = launcher()
  local r = rect("slot1")
  self.slotDeleteRects = { r }
  clickDelete(self, r)
  eq(#self.deletedSlots, 0, "the first click on Delete does not delete")
  check(self._confirmDelete ~= nil and self._confirmDelete.id == "slot1",
    "the first click arms that row")
  clickDelete(self, r)
  eq(self.deletedSlots[1], "red/slot1", "the second click on it deletes")
  eq(self._confirmDelete, nil, "the arm is spent")
end

-- ------- the arm is per row, per version, and any other press clears it

do
  local self = launcher()
  local one, two = rect("slot1", 200), rect("slot2", 230)
  self.slotDeleteRects = { one, two }
  clickDelete(self, one)
  clickDelete(self, two)
  eq(#self.deletedSlots, 0, "a click on another row's Delete only arms that row")
  eq(self._confirmDelete.id, "slot2", "the arm moved to the row just clicked")

  self.slotRects = { rect("slot3", 260) }
  clickDelete(self, one)                    -- re-arm slot1
  self:mousepressed(102, 262, 1)            -- press somewhere else entirely
  clickDelete(self, one)
  eq(#self.deletedSlots, 0, "a press elsewhere disarms, so Delete asks again")

  self:mousepressed(102, 262, 1)            -- clear the arm left by the pair above
  clickDelete(self, one)
  self.panelVersion = "blue"
  clickDelete(self, one)
  eq(#self.deletedSlots, 0, "an arm from one game's tab cannot fire on another")
end

-- ------- a stale arm expires instead of committing much later

do
  local self = launcher()
  local r = rect("slot1")
  self.slotDeleteRects = { r }
  clickDelete(self, r)
  clock = clock + 30
  clickDelete(self, r)
  eq(#self.deletedSlots, 0, "an arm older than the confirm window is dead")
  clickDelete(self, r)
  eq(self.deletedSlots[1], "red/slot1", "and the fresh pair still deletes")
end

-- ------- mods delete arms the same way

do
  local self = launcher()
  local r = rect("bigmod", 260)
  self.modDeleteRects = { r }
  clickDelete(self, r)
  eq(#self.deletedMods, 0, "the first click on a mod's Delete does not delete")
  clickDelete(self, r)
  eq(self.deletedMods[1], "bigmod", "the second click removes the mod")
end

T.finish("launcher delete confirm")
