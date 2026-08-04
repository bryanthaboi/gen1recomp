-- Launcher Delete affordance (src/import/RomImporter.lua): the two-click arm
-- that guards both save-slot and mod deletes (#433).  Every Delete control in
-- the FlexLove view routes through RomImporter:pressDelete, and every other
-- queued action clears self._confirmDelete (LauncherView's queueAction), so
-- the guarantees live on this seam: the first press only arms, the second
-- press on the SAME target commits, any other target or a cleared arm asks
-- again, and a stale arm expires instead of committing much later.
--   luajit tests/engine/launcher_delete_confirm.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- pressDelete timestamps the arm and expires it, so the clock has to move
local clock = 1000
love.timer.getTime = function() return clock end

local RomImporter = require("src.import.RomImporter")

local function launcher()
  local self = setmetatable({}, RomImporter)
  self.deleted = {}
  return self
end

local function press(self, kind, id, version)
  return self:pressDelete(kind, id, version, function()
    table.insert(self.deleted, tostring(kind) .. "/" .. tostring(version)
      .. "/" .. tostring(id))
  end)
end

-- ------- a save Delete needs two clicks on the same row

do
  local self = launcher()
  eq(press(self, "slot", "slot1", "red"), false,
    "the first click on Delete does not delete")
  eq(#self.deleted, 0, "nothing was committed by the arm")
  check(self._confirmDelete ~= nil and self._confirmDelete.id == "slot1",
    "the first click arms that row")
  eq(press(self, "slot", "slot1", "red"), true,
    "the second click on it deletes")
  eq(self.deleted[1], "slot/red/slot1", "the commit ran for that row")
  eq(self._confirmDelete, nil, "the arm is spent")
end

-- ------- the arm is per row, per version

do
  local self = launcher()
  press(self, "slot", "slot1", "red")
  eq(press(self, "slot", "slot2", "red"), false,
    "a click on another row's Delete only arms that row")
  eq(self._confirmDelete.id, "slot2", "the arm moved to the row just clicked")

  press(self, "slot", "slot1", "red")     -- re-arm slot1
  eq(press(self, "slot", "slot1", "blue"), false,
    "an arm from one game's tab cannot fire on another")
  eq(#self.deleted, 0, "no cross-target pair ever committed")
end

-- ------- any other action press disarms (the view clears the arm)

do
  local self = launcher()
  press(self, "slot", "slot1", "red")
  self._confirmDelete = nil               -- what queueAction does on any
                                          -- non-delete action press
  eq(press(self, "slot", "slot1", "red"), false,
    "a press elsewhere disarms, so Delete asks again")
  eq(#self.deleted, 0, "and the cleared arm never committed")
end

-- ------- a stale arm expires instead of committing much later

do
  local self = launcher()
  press(self, "slot", "slot1", "red")
  clock = clock + 30
  eq(press(self, "slot", "slot1", "red"), false,
    "an arm older than the confirm window is dead")
  eq(press(self, "slot", "slot1", "red"), true,
    "and the fresh pair still deletes")
end

-- ------- mods delete arms the same way (version is nil for mods)

do
  local self = launcher()
  eq(press(self, "mod", "bigmod", nil), false,
    "the first click on a mod's Delete does not delete")
  eq(press(self, "mod", "bigmod", nil), true,
    "the second click removes the mod")
  eq(self.deleted[1], "mod/nil/bigmod", "the mod commit ran")
end

T.finish("launcher delete confirm")
