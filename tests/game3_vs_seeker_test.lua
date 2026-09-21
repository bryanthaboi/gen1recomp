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

local Flags = require("src.core.game3.scripting.flags")
local store = Flags.newStore()
package.loaded["src.core.game3.scripting.space"] = { store = store }

local Rng = require("src.core.game3.rng")
local Data = require("src.core.game3.vs_seeker_data")
local VsSeeker = require("src.core.game3.vs_seeker")

local session = { flags = {}, vars = {} }
local s = VsSeeker.state(session)

local function fightFlag(id, on) Flags.setFlag(store, nil, Flags.trainerFlagId(id), on ~= false) end
local function sysFlag(id, on) Flags.setFlag(store, nil, id, on ~= false) end
local function resetFlags()
  store.flags = {}
end

local BEN, BEN_2, BEN_3 = 89, 101, 498
local MEGAN, MEGAN_2 = 130, 648
local TWINS, TWINS_2 = 484, 533

print("=== table ===")
check(#Data.REMATCHES == 221, "sRematches has 221 rows")
check(Data.REMATCHES[Data.byBase[TWINS]][4] == TWINS_2, "twins row carries TWINS_ELI_ANNE_2 in column 3")
check(Data.byAny[TWINS_2] == Data.byBase[TWINS], "rematch id maps back to its base row")

print("=== GetNextAvailableRematchTrainer ===")
local calvin = Data.REMATCHES[2][1]
check(Data.REMATCHES[2][2] == calvin, "row 2 is a {X, X} row")
fightFlag(calvin)
check(VsSeeker.nextAvailable(calvin, store) == 1, "{X, X} row returns 1")
check(VsSeeker.rematchTrainerId(calvin, store) == calvin, "{X, X} rematch without the VS SEEKER flag steps down to column 0")
sysFlag(0x292)
check(VsSeeker.rematchTrainerId(calvin, store) == calvin, "{X, X} rematch with VS SEEKER flag uses the same id")

fightFlag(BEN)
check(VsSeeker.nextAvailable(BEN, store) == 1, "BEN row returns 1 after the base fight")
fightFlag(BEN_2)
check(VsSeeker.nextAvailable(BEN, store) == 3, "BEN row skips SKIP and returns 3 after BEN_2")
check(VsSeeker.rematchTrainerId(BEN, store) == BEN_2, "FUCHSIA flag unset steps tier 3 down to BEN_2")
sysFlag(0x897)
check(VsSeeker.rematchTrainerId(BEN, store) == BEN_3, "FUCHSIA flag set gives BEN_3")
check(VsSeeker.nextAvailable(9999, store) == 0, "trainer outside the table returns 0")

fightFlag(MEGAN)
sysFlag(0x896)
check(VsSeeker.rematchTrainerId(MEGAN, store) == MEGAN_2, "MEGAN tier 2 with CELADON flag is MEGAN_2")
sysFlag(0x896, false)
check(VsSeeker.rematchTrainerId(MEGAN, store) == MEGAN, "MEGAN tier 2 without CELADON steps down to the base party")

print("=== ShouldTryRematchBattle / IsTrainerReadyForRematch ===")
resetFlags()
check(not VsSeeker.shouldTryRematchBattle(BEN, 5, store, session), "unfought, not ready: no rematch branch")
fightFlag(BEN)
check(VsSeeker.shouldTryRematchBattle(BEN, 5, store, session), "base flag set: rematch branch taken")
check(not VsSeeker.shouldTryRematchBattle(9999, 5, store, session), "trainer outside the table never branches")
check(not VsSeeker.shouldTryRematchBattle(BEN_2, 5, store, session), "only column-0 ids branch")
s.rematches = { [5] = 1 }
check(VsSeeker.isTrainerReadyForRematch(BEN, 5, session), "ready when lastTalked has a rematch state")
check(not VsSeeker.isTrainerReadyForRematch(BEN, 6, session), "not ready for another localId")
check(VsSeeker.isTrainerReadyForRematch(BEN_2, 5, session), "rematch ids hit the table in any column")
VsSeeker.clearRematchStateOfLastTalked(5, BEN_2, store, session)
check(VsSeeker.getRematch(s, 5) == 0, "ClearRematchStateOfLastTalked clears the state")
check(Flags.getFlag(store, nil, Flags.trainerFlagId(BEN_2)), "and sets the rematch trainer flag")

print("=== GetVsSeekerResponseInArea ===")
local function firstRoll(target)
  for seed = 0, 65535 do
    Rng.SeedRng(seed)
    if Rng.Random() % 100 == target then return seed end
  end
end

resetFlags()
fightFlag(BEN)
sysFlag(0x292)
local single = { { localId = 3, trainerIdx = BEN, x = 2, y = 2, graphicsId = 18, sane = true } }
local seed29, seed30 = firstRoll(29), firstRoll(30)
s.rematches = {}
Rng.SeedRng(seed29)
local code = VsSeeker.computeResponse(single, 0, 0, s, store)
check(code == VsSeeker.RESPONSE_NO_RESPONSE and VsSeeker.getRematch(s, 3) == 0, "rval 29 refuses")
check(not Flags.getFlag(store, nil, 0x801), "refusal does not set the charging flag")
s.rematches = {}
s.charging = 7
Rng.SeedRng(seed30)
local actions, responders
code, actions, responders = VsSeeker.computeResponse(single, 0, 0, s, store)
check(code == VsSeeker.RESPONSE_FOUND_REMATCHES and VsSeeker.getRematch(s, 3) == 1, "rval 30 accepts and stamps j")
check(Flags.getFlag(store, nil, 0x801) and s.charging == 0, "accept sets the charging flag and resets the counter")
check(actions[1].rematch and responders[1].behavior == 0x4E, "youngster responds with RAISE_HAND_AND_JUMP")

local far = { { localId = 3, trainerIdx = BEN, x = 8, y = 0, graphicsId = 18, sane = true },
  { localId = 4, trainerIdx = BEN, x = 0, y = 6, graphicsId = 18, sane = true } }
Rng.SeedRng(seed30)
code = VsSeeker.computeResponse(far, 0, 0, s, store)
check(code == VsSeeker.RESPONSE_NO_RESPONSE and Rng._value == seed30, "outside the 7x5 box: skipped, no RNG")

resetFlags()
local unfought = { { localId = 3, trainerIdx = BEN, x = 1, y = 1, graphicsId = 18, sane = true } }
Rng.SeedRng(1)
code, actions = VsSeeker.computeResponse(unfought, 0, 0, s, store)
check(code == VsSeeker.RESPONSE_UNFOUGHT_TRAINERS and actions[1].movement[1] == 0x62, "unfought trainer gets ! and no RNG")
check(Rng._value == 1, "unfought branch does not consume RNG")

resetFlags()
fightFlag(TWINS)
sysFlag(0x292)
sysFlag(0x896)
sysFlag(0x897)
local twins = {
  { localId = 10, trainerIdx = TWINS, x = 0, y = -2, graphicsId = 17, sane = true },
  { localId = 11, trainerIdx = TWINS, x = 1, y = -2, graphicsId = 17, sane = true },
}
local mirrored, sawYes, sawNo = true, false, false
for seed = 1, 40 do
  s.rematches = {}
  Rng.SeedRng(seed)
  local c, acts = VsSeeker.computeResponse(twins, 0, 0, s, store)
  local a1, a2 = acts[1].rematch == true, acts[2].rematch == true
  if a1 ~= a2 then mirrored = false end
  if a1 then
    sawYes = true
    if VsSeeker.getRematch(s, 10) ~= 3 or VsSeeker.getRematch(s, 11) ~= 3 then mirrored = false end
    if c ~= VsSeeker.RESPONSE_FOUND_REMATCHES then mirrored = false end
  else
    sawNo = true
  end
  Rng.SeedRng(seed)
  Rng.Random()
  Rng.Random()
  local expect = Rng._value
  Rng.SeedRng(seed)
  s.rematches = {}
  VsSeeker.computeResponse(twins, 0, 0, s, store)
  if Rng._value ~= expect then mirrored = false end
end
check(mirrored, "twin pair mirrors the first twin's answer and consumes one Random() each")
check(sawYes and sawNo, "seed sweep covered both answers")

print("=== CanUseVsSeeker ===")
s.steps = 99
check(VsSeeker.canUse(twins, 0, 0, s, store) == VsSeeker.NOT_CHARGED, "99 steps is not charged")
s.steps = 100
check(VsSeeker.canUse(twins, 0, 0, s, store) == VsSeeker.CAN_USE, "charged with a rematchable twin in range")
check(VsSeeker.canUse(twins, 20, 0, s, store) == VsSeeker.NO_ONE_IN_RANGE, "no one in range")

print("=== step counter ===")
local Bag = require("src.core.game3.bag")
session.bag = Bag.new()
-- pokefirered/include/constants/items.h:434 ITEM_VS_SEEKER
Bag.add(session.bag, 362, 1)
s.steps = 99
s.charging = 98
s.rematches = { [10] = 3 }
sysFlag(0x801)
check(not VsSeeker.onStep(session, store) and s.steps == 100 and s.charging == 99, "step 99 charges both bytes")
check(VsSeeker.onStep(session, store), "charging reaches 100 and fires the charging-done event")
check(not Flags.getFlag(store, nil, 0x801) and s.charging == 0, "charging flag and counter cleared")
check(next(s.rematches) == nil, "all rematch states cleared")
check(s.steps == 100, "in-bag charge caps at 100")

print("=== object movement ===")
check(VsSeeker.runningBehavior(22) == 0x4E and VsSeeker.runningBehavior(43) == 0x4F
  and VsSeeker.runningBehavior(5) == 0x4D, "GetRunningBehaviorFromGraphicsId")

local live, template = {}, {}
local stubObjects = {
  _defs = {
    { localId = 10, trainerType = 1, trainerId = TWINS, movementType = 8, graphicsId = 17 },
    { localId = 11, trainerType = 1, trainerId = TWINS, movementType = 8, graphicsId = 17 },
    { localId = 12, trainerType = 0, trainerId = TWINS, movementType = 8, graphicsId = 17 },
  },
  _byId = {
    [10] = { localId = 10, facing = "left", visible = true },
    [11] = { localId = 11, facing = "down", visible = true },
  },
  _order = { 10, 11 },
  setTrainerMovementType = function(lid, mt)
    if type(lid) == "table" then lid = lid.localId end
    live[lid] = mt
  end,
  overrideTemplateMovementType = function(lid, mt) template[lid] = mt end,
  templateMovementType = function(lid) return template[lid] or 8 end,
}

s.rematches = { [10] = 3, [11] = 3 }
Rng.SeedRng(77)
VsSeeker.clearRematchStateByTrainerId(TWINS_2, 10, store, session, stubObjects)
Rng.SeedRng(77)
Rng.Random()
Rng.Random()
local afterTwo = Rng._value
Rng.SeedRng(77)
VsSeeker.clearRematchStateByTrainerId(TWINS_2, 10, store, session, stubObjects)
check(Rng._value == afterTwo, "ClearRematchStateByTrainerId consumes one Random() per matching trainer template")
check(VsSeeker.getRematch(s, 10) == 0 and VsSeeker.getRematch(s, 11) == 0, "both twins cleared by the rematch id")
check(live[10] == 9 and live[11] == 8, "selected twin keeps its facing type, the other gets FACE_DOWN")
check(template[10] == 9 and template[11] == 8, "templates take each twin's facing type")

live, template = {}, { [10] = 0x4E, [11] = 0x4E }
Rng.SeedRng(5)
VsSeeker.resetObjectMovementAfterChargeComplete(stubObjects)
local face = { [7] = true, [8] = true, [9] = true, [10] = true }
check(face[live[10]] and face[live[11]] and face[template[10]] and face[template[11]],
  "charge-complete reset replaces raise-hand types with random face types")

if failed == 0 then
  print("ALL TESTS PASSED")
else
  print(string.format("TESTS FAILED: %d", failed))
  os.exit(1)
end
