#!/usr/bin/env luajit
-- pokefirered/src/fame_checker.c:1222

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

local FameChecker = require("src.core.game3.fame_checker")
local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local Natives = require("src.core.game3.scripting.natives")
local Space = require("src.core.game3.scripting.space")
local Runtime = require("src.core.game3.runtime")

local PICK = FameChecker.PICKSTATE
local PERSON = FameChecker.PERSON
local NPERSON = FameChecker.NUM_PERSONS
local NSLOT = FameChecker.NUM_FLAVOR_TEXTS

local function newSession()
  return { modData = {} }
end

print("[test] 1. ResetFameChecker defaults")
eq(NPERSON, 16, "NUM_FAMECHECKER_PERSONS")
eq(NSLOT, 6, "flavour text slots per person")
do
  local s = newSession()
  local recs = FameChecker.records(s)
  check(recs ~= nil and #recs == NPERSON, "a fresh session lazily builds 16 records")
  local blank = 0
  for p = 0, NPERSON - 1 do
    if FameChecker.flavorTextFlags(s, p) == 0 then blank = blank + 1 end
  end
  eq(blank, NPERSON, "every person starts with no flavour text")
  eq(FameChecker.pickState(s, PERSON.OAK), PICK.COLORED, "OAK starts COLORED")
  local drawn = 0
  for p = 0, NPERSON - 1 do
    if FameChecker.pickState(s, p) ~= PICK.NO_DRAW then drawn = drawn + 1 end
  end
  eq(drawn, 1, "OAK is the only person drawn at reset")
end

print("[test] 2. setFlavorText covers every person and slot")
do
  local s = newSession()
  local bad = 0
  for p = 0, NPERSON - 1 do
    for slot = 0, NSLOT - 1 do
      if not FameChecker.setFlavorText(p, slot, s) then bad = bad + 1 end
      if not FameChecker.hasFlavorText(s, p, slot) then bad = bad + 1 end
    end
  end
  eq(bad, 0, "all 16 x 6 slots set and read back")
  local allSet = 0
  for p = 0, NPERSON - 1 do
    if FameChecker.hasUnlockedAllFlavorTexts(s, p) then allSet = allSet + 1 end
  end
  eq(allSet, NPERSON, "every person reports all flavour texts unlocked")
  eq(FameChecker.flavorTextFlags(s, PERSON.BROCK), 0x3F, "six bits, nothing above bit 5")
end

print("[test] 3. out-of-range person and slot are rejected")
do
  local s = newSession()
  eq(FameChecker.setFlavorText(NPERSON, 0, s), false, "person 16 rejected")
  eq(FameChecker.setFlavorText(-1, 0, s), false, "person -1 rejected")
  eq(FameChecker.setFlavorText(PERSON.BROCK, NSLOT, s), false, "slot 6 rejected")
  eq(FameChecker.setFlavorText(PERSON.BROCK, -1, s), false, "slot -1 rejected")
  eq(FameChecker.flavorTextFlags(s, PERSON.BROCK), 0, "a rejected call wrote nothing")
end

print("[test] 4. a slot set twice stays set")
do
  local s = newSession()
  FameChecker.setFlavorText(PERSON.MISTY, 3, s)
  local first = FameChecker.flavorTextFlags(s, PERSON.MISTY)
  FameChecker.setFlavorText(PERSON.MISTY, 3, s)
  eq(FameChecker.flavorTextFlags(s, PERSON.MISTY), first, "the second set is a no-op")
  check(FameChecker.hasFlavorText(s, PERSON.MISTY, 3), "slot 3 still unlocked")
  FameChecker.setFlavorText(PERSON.MISTY, 0, s)
  check(FameChecker.hasFlavorText(s, PERSON.MISTY, 3), "slot 3 survives another slot")
  check(FameChecker.hasFlavorText(s, PERSON.MISTY, 0), "slot 0 unlocked alongside")
end

print("[test] 5. pick state transitions")
do
  local s = newSession()
  eq(FameChecker.pickState(s, PERSON.BROCK), PICK.NO_DRAW, "BROCK starts NO_DRAW")
  eq(FameChecker.updatePickState(PERSON.BROCK, PICK.NO_DRAW, s), false, "NO_DRAW never writes")
  eq(FameChecker.pickState(s, PERSON.BROCK), PICK.NO_DRAW, "NO_DRAW left the record alone")
  eq(FameChecker.updatePickState(PERSON.BROCK, PICK.SILHOUETTE, s), true, "NO_DRAW to SILHOUETTE")
  eq(FameChecker.pickState(s, PERSON.BROCK), PICK.SILHOUETTE, "BROCK is a silhouette")
  eq(FameChecker.updatePickState(PERSON.BROCK, PICK.COLORED, s), true, "SILHOUETTE to COLORED")
  eq(FameChecker.pickState(s, PERSON.BROCK), PICK.COLORED, "BROCK is coloured")
  eq(FameChecker.updatePickState(PERSON.BROCK, PICK.SILHOUETTE, s), false,
    "SILHOUETTE cannot demote COLORED")
  eq(FameChecker.pickState(s, PERSON.BROCK), PICK.COLORED, "BROCK stays coloured")
  eq(FameChecker.updatePickState(PERSON.BROCK, 3, s), false, "state 3 rejected")
  eq(FameChecker.updatePickState(NPERSON, PICK.COLORED, s), false, "person 16 rejected")
  -- pokefirered/src/fame_checker.c:1226
  FameChecker.setFlavorText(PERSON.BROCK, 1, s)
  eq(FameChecker.pickState(s, PERSON.BROCK), PICK.COLORED,
    "unlocking flavour text does not demote a coloured person")
  FameChecker.setFlavorText(PERSON.KOGA, 0, s)
  eq(FameChecker.pickState(s, PERSON.KOGA), PICK.SILHOUETTE,
    "unlocking flavour text promotes an undrawn person to SILHOUETTE")
end

print("[test] 6. FullyUnlockFameChecker / ResetFameChecker")
do
  local s = newSession()
  check(FameChecker.fullyUnlock(s), "fullyUnlock ran")
  local bad = 0
  for p = 0, NPERSON - 1 do
    if FameChecker.pickState(s, p) ~= PICK.COLORED then bad = bad + 1 end
    if not FameChecker.hasUnlockedAllFlavorTexts(s, p) then bad = bad + 1 end
  end
  eq(bad, 0, "every person fully unlocked and coloured")
  check(FameChecker.reset(s), "reset ran")
  eq(FameChecker.pickState(s, PERSON.LANCE), PICK.NO_DRAW, "LANCE back to NO_DRAW")
  eq(FameChecker.flavorTextFlags(s, PERSON.LANCE), 0, "LANCE back to no flavour text")
  eq(FameChecker.pickState(s, PERSON.OAK), PICK.COLORED, "OAK coloured again after reset")
end

print("[test] 7. the record round trips through a save")
do
  local Schema = require("src.core.game3.save_schema_firered")
  local s = newSession()
  for p = 0, NPERSON - 1 do
    for slot = 0, NSLOT - 1 do
      if (p + slot) % 3 == 0 then FameChecker.setFlavorText(p, slot, s) end
    end
  end
  FameChecker.updatePickState(PERSON.GIOVANNI, PICK.COLORED, s)
  local before = {}
  for p = 0, NPERSON - 1 do
    before[p] = { FameChecker.pickState(s, p), FameChecker.flavorTextFlags(s, p) }
  end
  local saved = Schema.toSaveTable(s)
  check(type(saved) == "table", "toSaveTable produced a table")
  local restored = Schema.fromSaveTable(saved)
  check(type(restored) == "table", "fromSaveTable produced a session")
  local bad = 0
  for p = 0, NPERSON - 1 do
    if FameChecker.pickState(restored, p) ~= before[p][1] then bad = bad + 1 end
    if FameChecker.flavorTextFlags(restored, p) ~= before[p][2] then bad = bad + 1 end
  end
  eq(bad, 0, "every person and slot survived the save round trip")
  eq(FameChecker.pickState(restored, PERSON.GIOVANNI), PICK.COLORED,
    "GIOVANNI is still coloured after the round trip")
end

print("[test] 8. both specials resolve through Natives")
do
  local store = Flags.newStore()
  Space.store = store
  local ctx = Ctx.new({})
  local session = newSession()
  session.store = store
  Runtime.session = session

  local VAR_0x8004, VAR_0x8005 = 0x8004, 0x8005
  -- pokefirered/data/maps/PewterCity_Gym/scripts.inc:5
  Flags.setVar(store, ctx, VAR_0x8004, PERSON.BROCK)
  Flags.setVar(store, ctx, VAR_0x8005, PICK.COLORED)
  local _, _, handled = Natives.special(ctx, 0x174, nil)
  check(handled == true, "special 0x174 UpdatePickStateFromSpecialVar8005 is handled")
  eq(FameChecker.pickState(session, PERSON.BROCK), PICK.COLORED,
    "the famechecker macro coloured BROCK")

  -- pokefirered/data/maps/PewterCity_Gym/scripts.inc:13
  Flags.setVar(store, ctx, VAR_0x8004, PERSON.BROCK)
  Flags.setVar(store, ctx, VAR_0x8005, 1)
  local _, _, handled2 = Natives.special(ctx, 0x173, nil)
  check(handled2 == true, "special 0x173 SetFlavorTextFlagFromSpecialVars is handled")
  check(FameChecker.hasFlavorText(session, PERSON.BROCK, 1), "BROCK flavour text 1 unlocked")
  eq(FameChecker.pickState(session, PERSON.BROCK), PICK.COLORED, "BROCK stays coloured")
  -- pokefirered/src/fame_checker.c:1227
  eq(Flags.getVar(store, ctx, VAR_0x8005), PICK.SILHOUETTE,
    "0x173 leaves VAR_0x8005 at FCPICKSTATE_SILHOUETTE")

  Flags.setVar(store, ctx, VAR_0x8004, PERSON.ERIKA)
  Flags.setVar(store, ctx, VAR_0x8005, 4)
  Natives.special(ctx, 0x173, nil)
  check(FameChecker.hasFlavorText(session, PERSON.ERIKA, 4), "ERIKA flavour text 4 unlocked")
  eq(FameChecker.pickState(session, PERSON.ERIKA), PICK.SILHOUETTE,
    "ERIKA became a silhouette through the special")

  Flags.setVar(store, ctx, VAR_0x8004, NPERSON)
  Flags.setVar(store, ctx, VAR_0x8005, 0)
  Natives.special(ctx, 0x173, nil)
  eq(Flags.getVar(store, ctx, VAR_0x8005), 0,
    "an out-of-range person leaves VAR_0x8005 alone")
end

print("[test] 9. the unlocked person list and the Giovanni shuffle")
do
  local store = Flags.newStore()
  Space.store = store
  local session = newSession()
  session.store = store
  Runtime.session = session

  local list = FameChecker.unlockedPersons(session)
  eq(#list, 1, "only OAK is listed at reset")
  eq(list[1], PERSON.OAK, "OAK is the first row")

  FameChecker.updatePickState(PERSON.BROCK, PICK.COLORED, session)
  FameChecker.updatePickState(PERSON.LORELEI, PICK.COLORED, session)
  FameChecker.updatePickState(PERSON.GIOVANNI, PICK.COLORED, session)
  list = FameChecker.unlockedPersons(session)
  eq(#list, 4, "four people listed")
  eq(list[1], PERSON.OAK, "OAK first")
  eq(list[2], PERSON.BROCK, "BROCK second")
  eq(list[3], PERSON.LORELEI, "LORELEI before GIOVANNI while the gym is unbeaten")
  eq(list[4], PERSON.GIOVANNI, "GIOVANNI last while the gym is unbeaten")

  -- pokefirered/src/fame_checker.c:1062
  Flags.setTrainerDefeated(store, nil, 350, true)
  list = FameChecker.unlockedPersons(session)
  eq(#list, 4, "still four people listed")
  eq(list[3], PERSON.GIOVANNI, "GIOVANNI moves ahead of LORELEI once the gym is beaten")
  eq(list[4], PERSON.LORELEI, "LORELEI drops behind GIOVANNI")
  eq(FameChecker.adjustGiovanniIndex(9, true), PERSON.GIOVANNI, "row 9 becomes GIOVANNI")
  eq(FameChecker.adjustGiovanniIndex(15, true), PERSON.MRFUJI, "row 15 becomes MR FUJI")
  eq(FameChecker.adjustGiovanniIndex(8, true), PERSON.BLAINE, "row 8 is untouched")
  eq(FameChecker.adjustGiovanniIndex(9, false), PERSON.LORELEI, "unbeaten row 9 is LORELEI")
end

print("[test] 10. sTrainerIdxs")
do
  -- pokefirered/src/fame_checker.c:145
  eq(FameChecker.TRAINER_IDS[PERSON.BROCK], 414, "BROCK is TRAINER_LEADER_BROCK")
  eq(FameChecker.TRAINER_IDS[PERSON.SABRINA], 420, "SABRINA is TRAINER_LEADER_SABRINA")
  eq(FameChecker.TRAINER_IDS[PERSON.BLAINE], 419, "BLAINE is TRAINER_LEADER_BLAINE")
  eq(FameChecker.TRAINER_IDS[PERSON.GIOVANNI], 348, "GIOVANNI is TRAINER_BOSS_GIOVANNI")
  local nonTrainers = 0
  for p = 0, NPERSON - 1 do
    if FameChecker.TRAINER_IDS[p] >= FameChecker.NON_TRAINER_START then
      nonTrainers = nonTrainers + 1
    end
  end
  eq(nonTrainers, 4, "OAK, DAISY, BILL and MR FUJI are the non-trainers")
end

if failed == 0 then
  print("PASS game3_fame_model")
  os.exit(0)
end
print("FAIL game3_fame_model failures=" .. failed)
os.exit(1)
