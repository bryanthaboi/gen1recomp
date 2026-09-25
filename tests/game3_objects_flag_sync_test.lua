#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Flags = require("src.core.game3.scripting.flags")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local Player = require("src.core.game3.player")
local Objects = require("src.core.game3.objects")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local TOWER = "FR_POKEMON_TOWER_7F"
local FUJI = 10
local FLAG_HIDE_TOWER_FUJI = 0x34
local FLAG_HIDE_POKEHOUSE_FUJI = 0x35
local FLAG_RESCUED_MR_FUJI = 0x23C

local function towerDef()
  return {
    midLayout = { width = 20, height = 40 },
    objects = {
      { localId = FUJI, graphicsId = 30, x = 11, y = 4, movementType = 8, flag = FLAG_HIDE_TOWER_FUJI },
      { localId = 2, graphicsId = 40, x = 11, y = 34, movementType = 8, flag = 0x3F0 },
      { localId = 3, graphicsId = 40, x = 5, y = 5, movementType = 8, flag = 0x3F1 },
    },
  }
end

local function placePlayer(x, y)
  Player.cellX, Player.cellY = x, y
  Player.targetX, Player.targetY = x, y
  Player.px, Player.py = x * 16, y * 16
  Player.moving = false
end

local function fresh()
  Objects.reset()
  Objects.loadMap(nil, TOWER, towerDef())
end

print("[test] 1. setflag on an on-screen object's hide flag leaves it visible")
fresh()
placePlayer(11, 5)
Objects.syncFlagVisibility(FLAG_HIDE_TOWER_FUJI, true)
local fuji = Objects.find(FUJI)
check(fuji and fuji.visible and not fuji.hidden, "Fuji still visible after his hide flag is set")

print("[test] 2. an object outside the camera box is culled and stays gone")
Objects.syncFlagVisibility(0x3F0, true)
local far = Objects.find(2)
check(far and far.hidden and not far.visible, "far object (11,34) hidden")

print("[test] 3. clearflag still respawns a removed object")
Objects.removeObject(3)
check(Objects.find(3).hidden, "object 3 removed")
Objects.syncFlagVisibility(0x3F1, false)
check(Objects.find(3).visible and not Objects.find(3).hidden, "clearflag brings object 3 back")

print("[test] 4. forced sync (mod SDK) still hides on-screen objects")
fresh()
placePlayer(11, 5)
Objects.syncFlagVisibility(FLAG_HIDE_TOWER_FUJI, true, true)
check(Objects.find(FUJI).hidden, "forced hide removes Fuji")

print("[test] 5. Mr Fuji's script leaves him on screen through the msgbox")
fresh()
placePlayer(11, 5)
local store = Flags.newStore()
Flags.setFlag(store, nil, FLAG_HIDE_POKEHOUSE_FUJI, true)
local vm = Vm.new({
  store = store,
  adapters = Adapters.host(nil, nil, nil),
  scripts = {
    fuji = {
      { op = "setflag", [1] = FLAG_HIDE_TOWER_FUJI },
      { op = "clearflag", [1] = FLAG_HIDE_POKEHOUSE_FUJI },
      { op = "setflag", [1] = FLAG_RESCUED_MR_FUJI },
      { op = "end" },
    },
  },
})
vm:start("fuji")
for _ = 1, 16 do
  if not vm:isRunning() then break end
  vm:tick()
end
check(Flags.getFlag(store, vm.ctx, FLAG_HIDE_TOWER_FUJI), "FLAG_HIDE_TOWER_FUJI set")
check(Flags.getFlag(store, vm.ctx, FLAG_RESCUED_MR_FUJI), "FLAG_RESCUED_MR_FUJI set")
check(not Flags.getFlag(store, vm.ctx, FLAG_HIDE_POKEHOUSE_FUJI), "FLAG_HIDE_POKEHOUSE_FUJI cleared")
fuji = Objects.find(FUJI)
check(fuji and fuji.visible and not fuji.hidden, "Fuji still drawn after the script's setflag")
local drawn = false
for _, eo in ipairs(Objects.forDraw()) do
  if eo.localId == FUJI then drawn = true end
end
check(drawn, "Fuji in forDraw")

print("[test] 6. ON_TRANSITION / ON_LOAD hides run before spawn: in-view objects are gone")
local Space = require("src.core.game3.scripting.space")
local VERMILION = "FR_VERMILION_CITY"
local AIDE = 8
local FLAG_HIDE_AIDE = 0x0A1
local FLAG_HIDE_LOAD = 0x3F2
local function vermilionDef()
  return {
    midLayout = { width = 50, height = 40 },
    objects = {
      { localId = AIDE, graphicsId = 30, x = 25, y = 7, movementType = 8, flag = FLAG_HIDE_AIDE },
      { localId = 9, graphicsId = 40, x = 16, y = 8, movementType = 8, flag = FLAG_HIDE_LOAD },
    },
  }
end
local enterStore = Flags.newStore()
local saved = {
  bundle = Space.bundle, vm = Space.vm, store = Space.store,
  mapId = Space.mapId, active = Space.active,
}
Space.bundle = {
  events = {
    [VERMILION] = { mapScripts = { onTransition = "vermilion_transition", onLoad = "vermilion_load" } },
  },
}
Space.store = enterStore
Space.vm = Vm.new({
  store = enterStore,
  adapters = Adapters.host(nil, nil, nil),
  scripts = {
    -- data/maps/VermilionCity/scripts.inc:28
    vermilion_transition = {
      { op = "setflag", [1] = FLAG_HIDE_AIDE },
      { op = "end" },
    },
    vermilion_load = {
      { op = "setflag", [1] = FLAG_HIDE_LOAD },
      { op = "end" },
    },
    later = {
      { op = "setflag", [1] = FLAG_HIDE_AIDE },
      { op = "end" },
    },
  },
})
Space.mapId = VERMILION
Space.active = true
Objects.reset()
Objects.loadMap(nil, VERMILION, vermilionDef())
placePlayer(15, 7)
local okEnter, errEnter = pcall(Space.runEnterScripts, nil, VERMILION, nil, nil, { enterVia = "warp" })
check(okEnter, "runEnterScripts ran" .. (okEnter and "" or (": " .. tostring(errEnter))))
check(Flags.getFlag(enterStore, nil, FLAG_HIDE_AIDE), "ON_TRANSITION set the aide hide flag")
local aide = Objects.find(AIDE)
check(aide and aide.hidden and not aide.visible, "aide at (25,7) hidden though in view of (15,7)")
check(Objects.find(9) and Objects.find(9).hidden, "ON_LOAD setflag hides an in-view object")
check(not Space._inTransition, "transition window closed after the drain")

print("[test] 7. setflag after the entry drain keeps cart semantics")
Objects.syncFlagVisibility(FLAG_HIDE_AIDE, false)
check(Objects.find(AIDE).visible, "aide respawned by clearflag")
Flags.setFlag(enterStore, nil, FLAG_HIDE_AIDE, false)
Space.vm:start("later")
for _ = 1, 16 do
  if not Space.vm:isRunning() then break end
  Space.vm:tick()
end
check(Objects.find(AIDE).visible, "mid-map setflag leaves the in-view aide drawn")

Space.bundle, Space.vm, Space.store = saved.bundle, saved.vm, saved.store
Space.mapId, Space.active = saved.mapId, saved.active

local PEWTER = "FR_PEWTER_CITY"
local GYM_GUIDE, MUSEUM_GUIDE = 5, 2
local FLAG_HIDE_GYM_GUIDE, FLAG_HIDE_MUSEUM_GUIDE = 0x2E, 0x2F
local function pewterDef()
  return {
    midLayout = { width = 50, height = 40 },
    objects = {
      { localId = MUSEUM_GUIDE, graphicsId = 30, x = 33, y = 17, movementType = 8, flag = FLAG_HIDE_MUSEUM_GUIDE },
      { localId = GYM_GUIDE, graphicsId = 30, x = 42, y = 20, movementType = 8, flag = FLAG_HIDE_GYM_GUIDE },
    },
  }
end
local function freshPewter()
  Objects.reset()
  Objects.loadMap(nil, PEWTER, pewterDef())
end
local function strand(lid, x, y, facing)
  local eo = Objects.find(lid)
  eo.cellX, eo.cellY, eo.targetX, eo.targetY = x, y, x, y
  eo.px, eo.py = x * 16, y * 16
  eo.facing = facing
  eo.frozen, eo.scriptBusy = true, true
  if eo.def then eo.def.x, eo.def.y = x, y end
  Objects._tracks[lid] = { done = false }
  return eo
end
local function atTemplate(lid, x, y, label)
  local eo = Objects.find(lid)
  check(eo and eo.visible and not eo.hidden, label .. ": visible")
  check(eo and eo.cellX == x and eo.cellY == y, label .. string.format(": at template (%d,%d), got (%s,%s)",
    x, y, tostring(eo and eo.cellX), tostring(eo and eo.cellY)))
  check(eo and eo.homeX == x and eo.homeY == y and eo.px == x * 16 and eo.py == y * 16, label .. ": home/px reset")
  check(eo and eo.facing == "down", label .. ": template facing down, got " .. tostring(eo and eo.facing))
  check(eo and not eo.moving and not eo.frozen and not eo.scriptBusy, label .. ": idle")
  check(Objects._tracks[lid] == nil, label .. ": no stale track")
end

print("[test] 8. removeobject + clearflag respawns the Pewter gym guide at his template cell")
freshPewter()
placePlayer(15, 18)
local stale = strand(GYM_GUIDE, 7, 19, "left")
Objects.removeObject(GYM_GUIDE)
Objects.syncFlagVisibility(FLAG_HIDE_GYM_GUIDE, false)
atTemplate(GYM_GUIDE, 42, 20, "gym guide")
check(Objects.find(GYM_GUIDE) ~= stale, "gym guide is a fresh object")

print("[test] 9. museum guide sibling")
freshPewter()
placePlayer(20, 17)
strand(MUSEUM_GUIDE, 24, 15, "up")
Objects.removeObject(MUSEUM_GUIDE)
Objects.syncFlagVisibility(FLAG_HIDE_MUSEUM_GUIDE, false)
atTemplate(MUSEUM_GUIDE, 33, 17, "museum guide")

print("[test] 10. removeobject + addobject respawns from the template too")
freshPewter()
placePlayer(15, 18)
strand(GYM_GUIDE, 7, 19, "left")
Objects.removeObject(GYM_GUIDE)
check(Objects.addObject(GYM_GUIDE), "addobject ok")
atTemplate(GYM_GUIDE, 42, 20, "addobject gym guide")
local n = 0
for _, id in ipairs(Objects._order) do if id == GYM_GUIDE then n = n + 1 end end
check(n == 1, "gym guide listed once in draw order")

print("[test] 11. a perm row still places the respawn (Oak's lab shape)")
freshPewter()
placePlayer(15, 18)
strand(GYM_GUIDE, 7, 19, "left")
Objects.removeObject(GYM_GUIDE)
Objects.setObjectXY(GYM_GUIDE, 6, 3)
Objects.setMovementType(GYM_GUIDE, 8)
Objects.syncFlagVisibility(FLAG_HIDE_GYM_GUIDE, false)
local permEo = Objects.find(GYM_GUIDE)
check(permEo.visible and permEo.cellX == 6 and permEo.cellY == 3 and permEo.facing == "down",
  "perm row wins over the template")

print("[test] 12. clearflag leaves an active object where it is")
freshPewter()
placePlayer(15, 18)
local live = strand(GYM_GUIDE, 16, 18, "left")
live.frozen, live.scriptBusy = false, false
Objects._tracks[GYM_GUIDE] = nil
Objects.rememberPerm(PEWTER, GYM_GUIDE, { x = 6, y = 3, movementType = 7 })
Objects.syncFlagVisibility(FLAG_HIDE_GYM_GUIDE, false)
check(Objects.find(GYM_GUIDE) == live and live.cellX == 16 and live.cellY == 18 and live.facing == "left",
  "active gym guide untouched by clearflag")
check(Objects.addObject(GYM_GUIDE) and Objects.find(GYM_GUIDE) == live, "addobject on an active object is a no-op")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
