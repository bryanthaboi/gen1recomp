#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local store = { flags = {}, vars = {} }
local session = { store = store, map = "FR_SILPH_CO_ELEVATOR", party = {} }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Elevator = require("src.core.game3.scripting.natives_elevator")
local ListMenu = require("src.core.game3.scripting.natives_listmenu")
local Cutscene = require("src.core.game3.scripting.natives_cutscene")
local Flags = require("src.core.game3.scripting.flags")
local Stack = require("src.ui.game3.stack")

local Menu = ListMenu.Menu
local SCR_MENU_CANCEL = 0x7F

local function newCtx()
  return { specialVars = {} }
end

local function getVar(ctx, id) return Flags.getVar(store, ctx, id) end
local function result(ctx) return getVar(ctx, 0x800D) end

print("[test] 1. ids match the 0-based def_special index of pokefirered/data/specials.inc")
local EXPECTED = {
  GetElevatorFloor = 0xD8,
  AnimateElevator = 0x111,
  SpawnCameraObject = 0x113,
  RemoveCameraObject = 0x114,
  DrawElevatorCurrentFloorWindow = 0x132,
  ListMenu = 0x158,
  ReturnToListMenu = 0x159,
  CloseElevatorCurrentFloorWindow = 0x160,
  AnimateTeleporterHousing = 0x1B5,
  AnimateTeleporterCable = 0x1B7,
  InitElevatorFloorSelectMenuPos = 0x1B8,
}
for name, id in pairs(EXPECTED) do
  eq(Std.SPECIAL[name], id, "Std.SPECIAL." .. name)
  check(Natives.ALLOW["special:" .. id] ~= nil, name .. " is bound in Natives.ALLOW")
end
local names = {}
for _, n in ipairs(Natives.MODULE_NAMES) do names[n] = true end
check(names["natives_elevator"], "discovery found natives_elevator with no natives.lua edit")
check(names["natives_listmenu"], "discovery found natives_listmenu")
check(names["natives_cutscene"], "discovery found natives_cutscene")

print("[test] 2. no registered handler logs as unknown")
Natives.resetLog()
local logs = {}
local quiet = { log = function(m) logs[#logs + 1] = m end }
for _, mod in ipairs({ Elevator, ListMenu, Cutscene }) do
  for id in pairs(mod.HANDLERS) do
    local _, _, known = Natives.special(newCtx(), id, quiet)
    check(known, string.format("special 0x%X dispatches to a handler", id))
  end
end
Menu.close()
eq(#logs, 0, "nothing reached the unknown-special log")

print("[test] 3. GetElevatorFloor writes VAR_ELEVATOR_FLOOR from the dynamic warp")
local FLOORS = {
  FR_SILPH_CO_1F = 4,
  FR_SILPH_CO_5F = 8,
  FR_SILPH_CO_11F = 14,
  FR_ROCKET_HIDEOUT_B1F = 3,
  FR_ROCKET_HIDEOUT_B2F = 2,
  FR_ROCKET_HIDEOUT_B4F = 0,
  FR_CELADON_CITY_DEPARTMENT_STORE_5F = 8,
  FR_TRAINER_TOWER_LOBBY = 3,
  FR_TRAINER_TOWER_ROOF = 15,
}
for mapId, floor in pairs(FLOORS) do
  session.dynamicWarp = { map = mapId }
  local ctx = newCtx()
  Elevator.HANDLERS[Std.SPECIAL.GetElevatorFloor](ctx, {})
  eq(getVar(ctx, 0x403A), floor, "VAR_ELEVATOR_FLOOR after GetElevatorFloor on " .. mapId)
end
session.dynamicWarp = nil
local ctx3 = newCtx()
Elevator.HANDLERS[Std.SPECIAL.GetElevatorFloor](ctx3, {})
eq(getVar(ctx3, 0x403A), 4, "an unset dynamic warp leaves the cart default 1F")
session.dynamicWarp = { map = "FR_SILPH_CO_5F" }
Elevator.HANDLERS[Std.SPECIAL.GetElevatorFloor](newCtx(), {})
eq(Flags.getVar(store, nil, 0x403A), 8, "VAR_ELEVATOR_FLOOR round trips through the store")

print("[test] 4. InitElevatorFloorSelectMenuPos returns the cursor for the current floor")
local POS = {
  FR_SILPH_CO_11F = { 0, 0 },
  FR_SILPH_CO_7F = { 0, 4 },
  FR_SILPH_CO_5F = { 2, 4 },
  FR_SILPH_CO_1F = { 5, 5 },
  FR_ROCKET_HIDEOUT_B4F = { 0, 2 },
  FR_CELADON_CITY_DEPARTMENT_STORE_1F = { 0, 4 },
}
for mapId, want in pairs(POS) do
  session.dynamicWarp = { map = mapId }
  local ctx = newCtx()
  local yield, value = Elevator.HANDLERS[Std.SPECIAL.InitElevatorFloorSelectMenuPos](ctx, {})
  eq(yield, false, "InitElevatorFloorSelectMenuPos does not yield on " .. mapId)
  eq(value, want[2], "cursor returned for " .. mapId)
  eq(ListMenu.elevatorScroll, want[1], "scroll staged for " .. mapId)
  eq(ListMenu.elevatorCursorPos, want[2], "cursor staged for " .. mapId)
end

print("[test] 5. the elevator floor window drives the adapter seams")
local shown, closed = nil, 0
local adapters5 = {
  elevatorWindow = function(label) shown = label end,
  elevatorWindowClose = function() closed = closed + 1 end,
}
local ctx5 = newCtx()
Flags.setVar(store, ctx5, 0x8005, 8)
Elevator.HANDLERS[Std.SPECIAL.DrawElevatorCurrentFloorWindow](ctx5, adapters5)
eq(shown, "5F", "floor 8 draws the 5F window")
Flags.setVar(store, ctx5, 0x8005, 0)
Elevator.HANDLERS[Std.SPECIAL.DrawElevatorCurrentFloorWindow](ctx5, adapters5)
eq(shown, "B4F", "floor 0 draws the B4F window")
Flags.setVar(store, ctx5, 0x8005, 15)
Elevator.HANDLERS[Std.SPECIAL.DrawElevatorCurrentFloorWindow](ctx5, adapters5)
eq(shown, "ROOFTOP", "floor 15 draws the ROOFTOP window")
Elevator.HANDLERS[Std.SPECIAL.CloseElevatorCurrentFloorWindow](ctx5, adapters5)
eq(closed, 1, "CloseElevatorCurrentFloorWindow closes it")
local okSeamless = pcall(function()
  Elevator.HANDLERS[Std.SPECIAL.DrawElevatorCurrentFloorWindow](ctx5, {})
  Elevator.HANDLERS[Std.SPECIAL.CloseElevatorCurrentFloorWindow](ctx5, {})
end)
check(okSeamless, "both window specials are safe with no host seam")

print("[test] 6. AnimateElevator holds the script for the cart's frame count")
local Field = require("src.core.game3.field")
local realSetMetatile = Field.setMetatile
local writes = {}
Field.setMetatile = function(x, y, mid, impassable)
  writes[#writes + 1] = { x = x, y = y, mid = mid, impassable = impassable }
end
local FieldView = package.loaded["src.core.game3.field_view"]
if not FieldView then
  FieldView = { _nativeDirty = false }
  package.loaded["src.core.game3.field_view"] = FieldView
end
local ctx6 = newCtx()
Flags.setVar(store, ctx6, 0x8005, 4)
Flags.setVar(store, ctx6, 0x8006, 8)
eq(Elevator.HANDLERS[Std.SPECIAL.AnimateElevator](ctx6, {}), false, "AnimateElevator returns to waitstate")
local task = ctx6.stateWait
check(type(task) == "function", "AnimateElevator armed a state task")
local ticks = 0
-- pokefirered/src/field_specials.c:812 sElevatorAnimationDuration
for _ = 1, 400 do
  ticks = ticks + 1
  if task() then break end
end
eq(ticks, 114, "four floors takes 3 frames per shake step, 38 steps")
eq(#writes, 135, "the window view wrote nine metatiles on each of fifteen steps")
eq(writes[1] and writes[1].x, 1, "window view starts at map x 1")
eq(writes[1] and writes[1].y, 0, "window view starts at map y 0")
eq(writes[1] and writes[1].impassable, true, "MAPGRID_COLLISION_MASK on the window metatiles")
eq(writes[1] and writes[1].mid, 0x2E9, "going up writes Top1 on the first step")
eq(FieldView.cameraPanY, 0, "the camera pan is released when the elevator stops")
local ctx6b = newCtx()
Flags.setVar(store, ctx6b, 0x8005, 8)
Flags.setVar(store, ctx6b, 0x8006, 8)
Elevator.HANDLERS[Std.SPECIAL.AnimateElevator](ctx6b, {})
local task6b, ticks6b = ctx6b.stateWait, 0
for _ = 1, 100 do
  ticks6b = ticks6b + 1
  if task6b() then break end
end
eq(ticks6b, 24, "a zero-floor move still runs sElevatorAnimationDuration[0]")
writes = {}
local Task = require("src.core.game3.task")
Task.clear()
local ctx6c = newCtx()
Flags.setVar(store, ctx6c, 0x8005, 14)
Flags.setVar(store, ctx6c, 0x8006, 4)
Elevator.HANDLERS[Std.SPECIAL.AnimateElevator](ctx6c, {})
local task6c, ticks6c = ctx6c.stateWait, 0
for _ = 1, 400 do
  ticks6c = ticks6c + 1
  if task6c() then break end
end
eq(writes[1] and writes[1].mid, 0x2EA, "going down writes Top2 on the first step")
eq(ticks6c, 171, "ten floors clamps to eight, 57 shake steps of 3 frames")
eq(#writes, 24 * 9, "the shake ended with the window view unfinished")
-- pokefirered/src/field_specials.c:1119 AnimateElevatorWindowView is its own task
eq(Task.count(), 1, "the unfinished window view kept running as a task")
for _ = 1, 40 do Task.update(1 / 60) end
eq(#writes, 27 * 9, "it ran on to sElevatorWindowAnimDuration[8] steps after the script resumed")
eq(Task.count(), 0, "and then finished")
Field.setMetatile = realSetMetatile

print("[test] 7. ListMenu picks a real Silph floor")
local ctx7 = newCtx()
Flags.setVar(store, ctx7, 0x8004, ListMenu.LISTMENU_SILPHCO_FLOORS)
session.dynamicWarp = { map = "FR_SILPH_CO_1F" }
Elevator.HANDLERS[Std.SPECIAL.InitElevatorFloorSelectMenuPos](ctx7, {})
eq(ListMenu.HANDLERS[Std.SPECIAL.ListMenu](ctx7, {}), false, "ListMenu returns to waitstate")
check(Menu.isOpen(), "the list menu is open")
check(Stack.has("script_list_menu"), "the list menu owns the modal stack")
local wait7 = ctx7.stateWait
check(type(wait7) == "function" and wait7() == false, "the script waits while the list is open")
eq(Menu.scroll, 5, "the Silph list opens scrolled to the bottom on 1F")
eq(Menu.row, 6, "the cursor sits on 1F")
eq(Menu.selection(), 10, "1F is index 10")
Menu.move(-1)
Menu.move(-1)
Menu.move(-1)
Menu.move(-1)
eq(Menu.selection(), 6, "four presses up reach 5F")
Menu.confirm()
eq(result(ctx7), 6, "VAR_RESULT is the 5F case of the switch")
check(wait7() == true, "the script resumes once a floor is picked")
check(not Menu.isOpen(), "the list menu closed")
check(not Stack.has("script_list_menu"), "the modal stack is empty again")

print("[test] 8. scrolling stops at both ends and B cancels")
local ctx8 = newCtx()
Flags.setVar(store, ctx8, 0x8004, ListMenu.LISTMENU_SILPHCO_FLOORS)
ListMenu.elevatorScroll, ListMenu.elevatorCursorPos = 0, 0
ListMenu.HANDLERS[Std.SPECIAL.ListMenu](ctx8, {})
eq(Menu.selection(), 0, "11F is the first entry")
Menu.move(-1)
eq(Menu.selection(), 0, "up at the top does not wrap")
for _ = 1, 20 do Menu.move(1) end
eq(Menu.selection(), 11, "down stops on EXIT, the twelfth entry")
eq(Menu.scroll, 5, "the viewport scrolled to the bottom")
eq(Menu.row, 7, "seven rows are visible at once")
Menu.cancel()
eq(result(ctx8), SCR_MENU_CANCEL, "B sets VAR_RESULT to 0x7F")
check(ctx8.stateWait() == true, "cancel resumes the script")

print("[test] 9. the badge list keeps its place across ReturnToListMenu")
local ctx9 = newCtx()
Flags.setVar(store, ctx9, 0x8004, ListMenu.LISTMENU_BADGES)
ListMenu.HANDLERS[Std.SPECIAL.ListMenu](ctx9, {})
Menu.move(1)
Menu.move(1)
eq(Menu.selection(), 2, "THUNDERBADGE is index 2")
Menu.confirm()
eq(result(ctx9), 2, "VAR_RESULT is the chosen badge")
check(not Menu.isOpen(), "the window is not left on screen while the badge text runs")
check(ListMenu._suspended ~= nil, "a keep-open list stays suspended")
local ctx9b = newCtx()
ListMenu.HANDLERS[Std.SPECIAL.ReturnToListMenu](ctx9b, {})
check(Menu.isOpen(), "ReturnToListMenu reopens the badge list")
eq(Menu.selection(), 2, "it reopens on the badge that was described")
Menu.move(1)
Menu.move(1)
Menu.move(1)
Menu.move(1)
Menu.move(1)
Menu.move(1)
eq(Menu.selection(), 8, "EXIT is the ninth badge-list entry")
Menu.confirm()
eq(result(ctx9b), 8, "EXIT reports its own index")
check(ListMenu._suspended == nil, "picking EXIT ends the keep-open list")
local ctx9c = newCtx()
eq(ListMenu.HANDLERS[Std.SPECIAL.ReturnToListMenu](ctx9c, {}), false,
  "ReturnToListMenu with nothing suspended is a no-op")
check(not Menu.isOpen(), "and opens no window")

print("[test] 10. an unknown list id cancels instead of hanging the script")
local ctx10 = newCtx()
Flags.setVar(store, ctx10, 0x8004, 99)
ListMenu.HANDLERS[Std.SPECIAL.ListMenu](ctx10, {})
eq(result(ctx10), SCR_MENU_CANCEL, "VAR_RESULT is 0x7F")
check(ctx10.stateWait() == true, "waitstate is satisfied immediately")
check(not Menu.isOpen(), "no window was opened")

print("[test] 11. camera object specials drive game3/camera_object.lua when it exists")
local saved = package.loaded["src.core.game3.camera_object"]
local calls = {}
package.loaded["src.core.game3.camera_object"] = {
  spawn = function() calls[#calls + 1] = "spawn" end,
  remove = function() calls[#calls + 1] = "remove" end,
}
Cutscene.HANDLERS[Std.SPECIAL.SpawnCameraObject](newCtx(), {})
Cutscene.HANDLERS[Std.SPECIAL.RemoveCameraObject](newCtx(), {})
eq(table.concat(calls, ","), "spawn,remove", "SpawnCameraObject / RemoveCameraObject call it")
package.loaded["src.core.game3.camera_object"] = {}
local okNoApi = pcall(function()
  Cutscene.HANDLERS[Std.SPECIAL.SpawnCameraObject](newCtx(), {})
  Cutscene.HANDLERS[Std.SPECIAL.RemoveCameraObject](newCtx(), {})
end)
check(okNoApi, "the camera seam is safe while game3/camera_object.lua has no spawn/remove")
package.loaded["src.core.game3.camera_object"] = saved
for _, name in ipairs({ "AnimateTeleporterHousing", "AnimateTeleporterCable" }) do
  local ctx = newCtx()
  eq(Cutscene.HANDLERS[Std.SPECIAL[name]](ctx, {}), false, name .. " does not yield")
  eq(result(ctx), 0, name .. " leaves VAR_RESULT at 0")
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
