package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local home = os.getenv("HOME") or ""
local roots = {}
local identity = os.getenv("POKEPORT_IDENTITY")
if identity and identity ~= "" then
  roots[#roots + 1] = home .. "/Library/Application Support/LOVE/" .. identity .. "/emerald/"
  roots[#roots + 1] = home .. "/.local/share/love/" .. identity .. "/emerald/"
end
local ROOT
for _, r in ipairs(roots) do
  local f = io.open(r .. "data/generated/gba/pokemon/hoenn.lua", "rb")
  if f then
    f:close()
    ROOT = r
    break
  end
end
if not ROOT then
  local dir = require("tests.game3_cache").gameDir("emerald", "pokemon/hoenn.lua")
  ROOT = dir and dir .. "/"
end

local fs = {}
function fs:read(rel)
  if not ROOT then return nil end
  local f = io.open(ROOT .. rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
function fs:exists(rel) return self:read(rel) ~= nil end
package.loaded["src.core.game3.dataset"] = {
  cache = function() return fs end,
  mountExtractRoots = function() end,
}

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("emerald")

local session = { version = "emerald", party = {}, flags = {}, vars = {}, store = { flags = {}, vars = {} } }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }

local C = require("src.core.game3.constants").of("emerald")
local Story = require("src.core.game3.rse.story_specials")

print("[test] Mauville Gym barriers (pokeemerald/src/field_specials.c:633)")
local function L(name) return C:require("metatile_labels", "METATILE_MauvilleGym_" .. name) end
local grid = {}
local get = function(x, y) return grid[y * 16 + x] end
local imp = {}
local set = function(x, y, mid, impassable) grid[y * 16 + x] = mid imp[y * 16 + x] = impassable end
for y = 5, 16 do for x = 0, 8 do grid[y * 16 + x] = L("FloorTile") end end
grid[10 * 16 + 4] = L("RedBeamH1_Off")
grid[11 * 16 + 4] = L("RedBeamH3_Off")
grid[8 * 16 + 6] = L("PoleBottom_On")
grid[9 * 16 + 6] = L("FloorTile")
grid[6 * 16 + 2] = L("PoleTop_Off")
Story.mauvilleSetDefaultBarriers(get, set, C)
eq(get(4, 10), L("RedBeamH1_On"), "H1 off -> on")
eq(get(4, 11), L("RedBeamH3_On"), "H3 off -> on")
check(imp[11 * 16 + 4] == true, "H3 on is impassable")
eq(get(6, 8), L("GreenBeamV1_On"), "pole bottom on -> green V1")
eq(get(6, 9), L("GreenBeamV2_On"), "floor under a fresh green V1 becomes green V2 (reads the row above live)")
eq(get(2, 6), L("PoleTop_On"), "pole top off -> on")
eq(get(0, 5), L("RedBeamV2_On"), "floor with no green V1 above becomes red V2")
Story.mauvilleDeactivatePuzzle(get, set, C)
eq(get(4, 10), L("RedBeamH1_Off"), "deactivate turns H1 off")
eq(get(6, 9), L("FloorTile"), "deactivate clears V2 beams")
for _, xy in ipairs(Story.MAUVILLE_SWITCHES) do
  eq(get(xy[1], xy[2]), L("PressedSwitch"), "deactivate presses switch " .. xy[1] .. "," .. xy[2])
end
Story.mauvillePressSwitch(2, get, set, C)
eq(get(3, 9), L("PressedSwitch"), "switch index 2 is (3,9)")
eq(get(0, 15), L("RaisedSwitch"), "other switches raise")

print("[test] Petalburg Gym sliding doors (pokeemerald/src/field_specials.c:802)")
local door = {}
local frames = {}
local step = Story.slideDoorsTask(4, function(x, y, mid) door[y * 256 + x] = mid end, C, function(f) frames[#frames + 1] = f end)
local calls, doneAt = 0, nil
for i = 1, 20 do
  calls = calls + 1
  if step() then doneAt = i break end
end
eq(table.concat(frames, ","), "0,1,2,3,4", "all five sliding frames")
eq(doneAt, 9, "frame 0 on the first run, then one frame every two runs (sSlidingDoorNextFrameDelay)")
local f4 = C:require("metatile_labels", "METATILE_PetalburgGym_SlidingDoor_Frame4")
eq(door[39 * 256 + 7], f4, "room 4 door at (7,39)")
eq(door[40 * 256 + 7], f4 + 8, "lower half + METATILE_ROW_WIDTH")
eq(#Story.PETALBURG_DOORS[1], 2, "room 1 has two doors")

print("[test] IV rater / Pacifidlog TM / week count")
local seq = { 1, 0 }
local k = 0
local total, best, val = Story.ivRater({ hp = 10, atk = 31, def = 5, spe = 31, spa = 0, spd = 2 },
  function() k = k + 1 return seq[k] or 0 end)
eq(total, 79, "IV total")
eq(best, 3, "tie on 31 takes the later stat when Random() is odd (BufferVarsForIVRater)")
eq(val, 31, "best IV value")
eq(Story.daysUntilPacifidlogTM(20, 18), 5, "7 - (days - received)")
eq(Story.daysUntilPacifidlogTM(30, 18), 0, "a week later it is available")
eq(Story.weekCount(100000), 9999, "week count caps at 9999")

print("[test] natives bound on Emerald by name")
local Natives = require("src.core.game3.scripting.natives")
Natives.bind("emerald")
local names = {
  "MauvilleGymPressSwitch", "MauvilleGymSetDefaultBarriers", "MauvilleGymDeactivatePuzzle",
  "PetalburgGymSlideOpenRoomDoors", "PetalburgGymUnlockRoomDoors", "CableCar", "CableCarWarp", "Script_DoRayquazaScene",
  "FoundAbandonedShipRoom1Key", "FoundAbandonedShipRoom2Key", "FoundAbandonedShipRoom4Key", "FoundAbandonedShipRoom6Key",
  "SetRoute119Weather", "SetRoute123Weather", "LoadWallyZigzagoon", "IsStarterInParty", "TryUpdateRusturfTunnelState",
  "BufferVarsForIVRater", "LeadMonHasEffortRibbon", "GiveLeadMonEffortRibbon", "Special_AreLeadMonEVsMaxedOut",
  "SetTrickHouseNuggetFlag", "ResetTrickHouseNuggetFlag", "GetWeekCount", "FoundBlackGlasses", "ShowScrollableMultichoice",
  "MoveElevator", "SetDeptStoreFloor", "GetDeptStoreDefaultFloorChoice", "ShowDeptStoreElevatorFloorSelect",
  "CloseDeptStoreElevatorWindow", "GetDaycareState", "StoreSelectedPokemonInDaycare", "TakePokemonFromDaycare",
  "GetDaycareCostAndPrepareString", "CheckDaycareMonReceivedMail", "GiveEggFromDaycare", "RejectEggFromDayCare",
  "ShowDaycareLevelMenu", "SetDaycareCompatibilityString", "IsMirageIslandPresent", "UpdateShoalTideFlag", "WaitWeather",
  "SavePlayerParty", "LoadPlayerParty", "Special_BeginCyclingRoadChallenge", "UpdateCyclingRoadState",
  "SwapRegisteredBike", "GetPlayerAvatarBike", "StorePlayerCoordsInVars", "CountPartyAliveNonEggMons",
}
for _, n in ipairs(names) do
  local id = C.specials.byName[n]
  check(id ~= nil and Natives.ALLOW["special:" .. id] ~= nil, n .. " is bound on Emerald")
end
local Std = require("src.core.game3.scripting.stdscripts")
local fr = {}
for _, name in pairs(Std.specialIds("firered")) do fr[name] = true end
for _, n in ipairs({ "GetDaycareCostAndPrepareString", "CheckDaycareMonReceivedMail", "SetDeptStoreFloor", "MoveElevator",
  "Script_DoRayquazaScene" }) do
  check(not fr[n], n .. " is not a FireRed special name (FR binding unchanged)")
end

print("[test] cable car destination (pokeemerald/src/field_specials.c:927)")
local CableCar = require("src.core.game3.rse.cable_car")
local up, down = CableCar.destination(0, session), CableCar.destination(1, session)
local mc = C:require("map_groups", "MAP_MT_CHIMNEY_CABLE_CAR_STATION")
local r112 = C:require("map_groups", "MAP_ROUTE112_CABLE_CAR_STATION")
check(up.group == mc.group and up.num == mc.num and up.x == 6 and up.y == 4, "going up warps to Mt Chimney (6,4)")
check(down.group == r112.group and down.num == r112.num, "going down warps to Route 112")

print("[test] mirage RND + shoal tide (pokeemerald/src/time_events.c)")
local FieldRse = require("src.core.game3.scripting.natives_field_rse")
local Flags = require("src.core.game3.scripting.flags")
package.loaded["src.core.game3.scripting.space"] = { store = session.store }
local H, Lv = C:require("vars", "VAR_MIRAGE_RND_H"), C:require("vars", "VAR_MIRAGE_RND_L")
Flags.setVar(session.store, nil, H, 0x1234)
Flags.setVar(session.store, nil, Lv, 0x5678)
FieldRse.updateMirageRnd(session, 2)
local r = 0x12345678
for _ = 1, 2 do r = (require("src.core.game3.rng").mulU32(r, 1103515245) + 12345) % 0x100000000 end
eq(Flags.getVar(session.store, nil, H), math.floor(r / 0x10000), "two ISO_RANDOMIZE2 steps (high half)")
eq(Flags.getVar(session.store, nil, Lv), r % 0x10000, "low half")
eq(FieldRse.SHOAL_TIDE[3], 0, "03:00 low tide")
eq(FieldRse.SHOAL_TIDE[9], 1, "09:00 high tide")

print("[test] elevator (pokeemerald/src/field_specials.c:1747)")
local Elevator = require("src.core.game3.scripting.natives_elevator")
local d5 = C:require("map_groups", "MAP_LILYCOVE_CITY_DEPARTMENT_STORE_5F")
session.dynamicWarp = { mapGroup = tonumber(d5.group), mapNum = tonumber(d5.num) }
eq(Elevator.deptStoreFloor(), 8, "5F dynamic warp -> DEPT_STORE_FLOORNUM_5F")
eq(Elevator.deptStoreDefaultFloorChoice(), 0, "5F is the first menu row")
session.dynamicWarp = { mapGroup = 0, mapNum = 0 }
eq(Elevator.deptStoreFloor(), 4, "unknown map defaults to 1F")
eq(Elevator.RSE_TRIP_LENGTH[8], 57, "sElevatorTripLength caps at 57 moves")

print("[test] daycare / breeding RSE deltas (pokeemerald/src/daycare.c)")
local Daycare = require("src.core.game3.daycare")
local Breeding = require("src.core.game3.breeding")
eq(Daycare.saveKey(session), "emerald_daycare", "Emerald daycare save key")
eq(Daycare.saveKey({ version = "firered" }), "firered_daycare", "FireRed key unchanged")
eq(Breeding.pendingEggFlag(session), 0x86, "FLAG_PENDING_DAYCARE_EGG by name on Emerald")
eq(Breeding.pendingEggFlag({ version = "firered" }), 0x266, "FireRed literal unchanged")
local Rng = require("src.core.game3.rng")
Rng.SeedRng(7)
local egg = { ivs = {} }
local dc = { { ivs = { hp = 1, atk = 2, def = 3, spe = 4, spa = 5, spd = 6 } },
  { ivs = { hp = 11, atk = 12, def = 13, spe = 14, spa = 15, spd = 16 } } }
local sel = Breeding.inheritIVs(egg, dc, session)
Rng.SeedRng(7)
local want = {}
local avail = { 1, 2, 3, 4, 5, 6 }
for i = 1, 3 do
  want[i] = avail[(Rng.Random() % (6 - (i - 1))) + 1]
  table.remove(avail, i)
end
eq(table.concat(sel, ","), table.concat(want, ","), "Emerald removes position i from the IV list (daycare.c InheritIVs)")

if ROOT then
  local Pokemon = require("src.core.game3.pokemon")
  Pokemon.install(fs)
  local ever = C:require("items", "ITEM_EVERSTONE")
  local femalePers = 0x0000000C
  local same, n = 0, 400
  for i = 1, n do
    Rng.SeedRng(i * 7919)
    Rng.SeedRng2(i)
    local dcx = {
      { species = C:require("species", "SPECIES_ZIGZAGOON"), personality = femalePers, item = ever },
      { species = C:require("species", "SPECIES_ZIGZAGOON"), personality = 0xFF },
      steps = { 0, 0 },
    }
    local p = Breeding.rsePersonality(session, dcx)
    if Pokemon.natureId(p) == Pokemon.natureId(femalePers) then same = same + 1 end
  end
  check(same > n * 0.4 and same < n * 0.65, "Everstone mother passes her nature about half the time (" .. same .. "/" .. n .. ")")
  session.party = {
    { species = C:require("species", "SPECIES_SLUGMA"), ability = C:require("abilities", "ABILITY_MAGMA_ARMOR") },
    { species = C:require("species", "SPECIES_PICHU"), isEgg = true, friendship = 10 },
  }
  eq(Daycare.eggCyclesToSubtract(session), 2, "Magma Armor halves egg cycles")
  session.party[1].ability = 0
  eq(Daycare.eggCyclesToSubtract(session), 1, "no Flame Body / Magma Armor -> 1")
else
  print("emerald_story_specials_test: cache-backed breeding checks skipped (set POKEPORT_IDENTITY)")
end

Natives.bind("firered")
GameVersion.set(before)
T.finish()
