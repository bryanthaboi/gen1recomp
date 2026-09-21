#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local Runtime = require("src.core.game3.runtime")
local Storage = require("src.core.game3.storage")
local Natives = require("src.core.game3.scripting.natives")
local Std = require("src.core.game3.scripting.stdscripts")

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

local VAR_TEMP_1 = 0x4001
local VAR_TEMP_2 = 0x4002
local VAR_TEMP_3 = 0x4003
local VAR_ELEVATOR_FLOOR = 0x403A
local SPECIES_MAGIKARP = 129
local SPECIES_TOGEPI = 175

local prevSession = Runtime.session

local function newSession()
  local session = {
    party = {},
    store = Flags.newStore(),
    dex = { seen = {}, owned = {} },
    name = "RED",
    trainerId = 1,
  }
  Storage.ensure(session)
  Runtime.session = session
  return session
end

local function run(rows, store)
  store = store or Flags.newStore()
  local vm = Vm.new({
    store = store,
    scripts = { t = rows },
    adapters = Adapters.host(nil, nil, nil),
  })
  vm:start("t")
  return vm, store
end

local function result(_, store)
  return Flags.getVar(store, nil, VAR_TEMP_3)
end

print("[test] 1. setdynamicwarp stores the destination the elevator specials read")
local s1 = newSession()
local vm1, st1 = run({
  { op = "setdynamicwarp", [1] = 1, [2] = 51, [3] = 255, [4] = 22, [5] = 3 },
  { op = "end" },
})
check(type(s1.dynamicWarp) == "table", "setdynamicwarp wrote session.dynamicWarp")
local dw = s1.dynamicWarp or {}
eq(dw.map, "FR_SILPH_CO_5F", "SilphCo_Elevator scripts.inc:70 maps to the engine id")
eq(dw.warpId, -1, "WARP_ID_NONE 255 stores as the s8 -1")
eq(dw.x, 22, "x from the script row")
eq(dw.y, 3, "y from the script row")

local Elevator = require("src.core.game3.scripting.natives_elevator")
eq(Elevator.dynamicWarpMap(), "FR_SILPH_CO_5F", "Elevator.dynamicWarpMap reads it back")

s1.store = st1
local ctx1 = { specialVars = {} }
Natives.special(ctx1, Std.SPECIAL.GetElevatorFloor, Adapters.host(nil, nil, nil))
eq(Flags.getVar(st1, ctx1, VAR_ELEVATOR_FLOOR), 8,
  "GetElevatorFloor reports 5F end to end from the script op")

print("[test] 2. every set*warp variant owns its own slot")
local s2 = newSession()
run({
  { op = "setdynamicwarp", [1] = 1, [2] = 42, [3] = 255, [4] = 24, [5] = 25 },
  { op = "setescapewarp", [1] = 3, [2] = 48, [3] = 255, [4] = 12, [5] = 6 },
  { op = "setwarp", [1] = 0, [2] = 1, [3] = 255, [4] = 5, [5] = 8 },
  { op = "setdivewarp", [1] = 1, [2] = 47, [3] = 0, [4] = 4, [5] = 9 },
  { op = "setholewarp", [1] = 1, [2] = 48, [3] = 1, [4] = 6, [5] = 7 },
  { op = "end" },
})
eq((s2.dynamicWarp or {}).map, "FR_ROCKET_HIDEOUT_B1F", "dynamicWarp survives the later variants")
eq((s2.escapeWarp or {}).map, "FR_THREE_ISLAND_BOND_BRIDGE", "setescapewarp slot")
eq((s2.escapeWarp or {}).x, 12, "escape warp x")
eq((s2.warpDestination or {}).map, "FR_TRADE_CENTER", "setwarp slot")
eq((s2.diveWarp or {}).map, "FR_SILPH_CO_1F", "setdivewarp slot")
eq((s2.diveWarp or {}).warpId, 0, "a real warp id is kept as is")
eq((s2.holeWarp or {}).map, "FR_SILPH_CO_2F", "setholewarp slot")

print("[test] 3. setdynamicwarp coords go through VarGet")
local s3 = newSession()
run({
  { op = "setvar", [1] = VAR_TEMP_1, [2] = 13 },
  { op = "setvar", [1] = VAR_TEMP_2, [2] = 3 },
  { op = "setdynamicwarp", [1] = 1, [2] = 57, [3] = 255, [4] = VAR_TEMP_1, [5] = VAR_TEMP_2 },
  { op = "end" },
})
eq((s3.dynamicWarp or {}).map, "FR_SILPH_CO_11F", "11F from group 1 num 57")
eq((s3.dynamicWarp or {}).x, 13, "x resolved from VAR_TEMP_1")
eq((s3.dynamicWarp or {}).y, 3, "y resolved from VAR_TEMP_2")

print("[test] 4. givemon returns MON_GIVEN_TO_PARTY until the party is full")
local s4 = newSession()
local giveMagikarp = {
  { op = "givemon", [1] = SPECIES_MAGIKARP, [2] = 5, [3] = 0, [4] = 0, [5] = 0 },
  { op = "copyvar", [1] = VAR_TEMP_3, [2] = Ctx.VAR_RESULT },
  { op = "end" },
}
for i = 1, 6 do
  local vm, store = run(giveMagikarp)
  eq(result(vm, store), 0, "gift " .. i .. " joined the party")
end
eq(#s4.party, 6, "the party filled up")

print("[test] 5. a gift mon with a full party is sent to the PC, not refused")
local vm5, st5 = run(giveMagikarp)
eq(result(vm5, st5), 1, "VAR_RESULT is MON_GIVEN_TO_PC")
eq(#s4.party, 6, "the party did not grow")
check(s4.storage.boxes[1].mons[1] ~= nil, "the mon landed in box 1 slot 1")
eq(s4.monBoxId, 0, "session.monBoxId is the 0-based box")
eq(s4.monBoxPos, 0, "session.monBoxPos is the 0-based slot")
check(s4.dex.owned[SPECIES_MAGIKARP] == true, "the dex was still flagged")

print("[test] 6. only a full party and a full PC report MON_CANT_GIVE")
local s6 = newSession()
for _ = 1, 6 do run(giveMagikarp) end
for b = 1, Storage.TOTAL_BOXES_COUNT do
  local box = s6.storage.boxes[b]
  for slot = 1, Storage.IN_BOX_COUNT do
    box.mons[slot] = { species = 19, speciesId = 19, level = 3 }
  end
end
local vm6, st6 = run(giveMagikarp)
eq(result(vm6, st6), 2, "VAR_RESULT is MON_CANT_GIVE")

print("[test] 7. giveegg uses the same three-valued code")
local s7 = newSession()
local giveEgg = {
  { op = "giveegg", [1] = SPECIES_TOGEPI },
  { op = "copyvar", [1] = VAR_TEMP_3, [2] = Ctx.VAR_RESULT },
  { op = "end" },
}
local vm7, st7 = run(giveEgg)
eq(result(vm7, st7), 0, "the first egg joined the party")
check(s7.party[1] and s7.party[1].isEgg == true, "it is an egg")
for _ = 1, 5 do run(giveMagikarp) end
eq(#s7.party, 6, "the party filled up")
local vm7b, st7b = run(giveEgg)
eq(result(vm7b, st7b), 1, "an egg with a full party goes to the PC")
check(s7.storage.boxes[1].mons[1] ~= nil, "the egg reached box 1")
for b = 1, Storage.TOTAL_BOXES_COUNT do
  local box = s7.storage.boxes[b]
  for slot = 1, Storage.IN_BOX_COUNT do
    box.mons[slot] = { species = 19, speciesId = 19, level = 3 }
  end
end
local vm7c, st7c = run(giveEgg)
eq(result(vm7c, st7c), 2, "a full party and a full PC refuse the egg")

Runtime.session = prevSession

if failed > 0 then
  print(string.format("FAILED %d check(s)", failed))
  os.exit(1)
end
print("PASS game3_stitchscript_warp_gifts")
os.exit(0)
