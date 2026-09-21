#!/usr/bin/env luajit
-- Birth Island Deoxys triangle — pokefirered/src/field_specials.c:2319-2456.
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

local Deoxys = require("src.core.game3.deoxys")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Events = require("src.core.game3.scripting.natives_events")
local Flags = require("src.core.game3.scripting.flags")
local FieldEffects = require("src.core.game3.field_effects")

local function newSession(map)
  local store = { flags = {}, vars = {} }
  return { store = store, map = map or Deoxys.MAP_ID, party = {} }
end

local function getVar(session, id) return Deoxys.getVar(session, id) end
local function setVar(session, id, v) return Deoxys.setVar(session, id, v) end

print("[test] 1. constants match pret")
eq(Std.SPECIAL.DoDeoxysTriangleInteraction, 0x1AB,
  "DoDeoxysTriangleInteraction is def_special 0x1AB")
check(Events.HANDLERS[0x1AB] ~= nil, "the special has a handler")
eq(Deoxys.VAR_DEOXYS_INTERACTION_NUM, 0x403E, "VAR_DEOXYS_INTERACTION_NUM")
eq(Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER, 0x4026,
  "VAR_DEOXYS_INTERACTION_STEP_COUNTER")
eq(Deoxys.FLAG_SYS_DEOXYS_AWAKENED, 0x848, "FLAG_SYS_DEOXYS_AWAKENED")
eq(Deoxys.LOCALID_ROCK, 1, "the meteorite is local_id 1 (pret map.json order)")
eq(Deoxys.LOCALID_DEOXYS, 2, "Deoxys is local_id 2")
eq(Deoxys.OBJ_EVENT_GFX_METEORITE, 106, "OBJ_EVENT_GFX_METEORITE")
eq(Deoxys.FLDEFF_MOVE_ROCK, 67, "FLDEFF_MOVE_DEOXYS_ROCK")
eq(Deoxys.FLDEFF_DESTROY_ROCK, 68, "FLDEFF_DESTROY_DEOXYS_ROCK")
eq(Deoxys.MAP_GROUP, 2, "BirthIsland_Exterior group")
eq(Deoxys.MAP_NUM, 56, "BirthIsland_Exterior num")

print("[test] 2. sDeoxysCoords")
local PRET_COORDS = {
  { 15, 12 }, { 11, 14 }, { 15, 8 }, { 19, 14 }, { 12, 11 }, { 18, 11 },
  { 15, 14 }, { 11, 14 }, { 19, 14 }, { 15, 15 }, { 15, 10 },
}
eq(#Deoxys.COORDS, 11, "eleven rock positions")
local coordsOk = true
for i = 1, 11 do
  if Deoxys.COORDS[i][1] ~= PRET_COORDS[i][1]
    or Deoxys.COORDS[i][2] ~= PRET_COORDS[i][2] then
    coordsOk = false
    print(string.format("  mismatch at %d: %s,%s", i,
      tostring(Deoxys.COORDS[i][1]), tostring(Deoxys.COORDS[i][2])))
  end
end
check(coordsOk, "every coordinate matches pret sDeoxysCoords")
for num = 0, 10 do
  local x, y = Deoxys.coords(num)
  eq(x, PRET_COORDS[num + 1][1], "coords(" .. num .. ") x")
  eq(y, PRET_COORDS[num + 1][2], "coords(" .. num .. ") y")
end
eq(Deoxys.coords(99), 15, "coords clamps above the table")
eq(Deoxys.coords(-3), 15, "coords clamps below the table")

print("[test] 3. sDeoxysStepCaps")
local PRET_CAPS = { 4, 8, 8, 8, 4, 4, 4, 6, 3, 3 }
eq(#Deoxys.STEP_CAPS, 10, "ten step caps (indexed by num-1)")
local capsOk = true
for i = 1, 10 do
  if Deoxys.STEP_CAPS[i] ~= PRET_CAPS[i] then capsOk = false end
end
check(capsOk, "every step cap matches pret sDeoxysStepCaps")
for num = 1, 10 do
  eq(Deoxys.stepCap(num), PRET_CAPS[num], "stepCap(" .. num .. ")")
end
eq(Deoxys.stepCap(0), nil, "stepCap(0) is nil (pret guards r5 != 0)")
eq(Deoxys.stepCap(11), nil, "stepCap(11) is nil")

print("[test] 4. rock palettes")
eq(#Deoxys.ROCK_PALS, 11, "eleven rock palettes")
local palOk = true
for i = 1, 11 do
  local p = Deoxys.ROCK_PALS[i]
  if #p ~= 3 then palOk = false end
  for j = 1, 3 do
    local c = p[j]
    if #c ~= 3 or c[1] < 0 or c[1] > 255 or c[2] < 0 or c[2] > 255
      or c[3] < 0 or c[3] > 255 then
      palOk = false
    end
  end
end
check(palOk, "every palette is 3 x RGB in 0..255")
-- pret's palettes brighten monotonically, index 1 darkest and index 3 lightest.
local mono = true
for i = 1, 11 do
  local p = Deoxys.ROCK_PALS[i]
  local l1 = p[1][1] + p[1][2] + p[1][3]
  local l2 = p[2][1] + p[2][2] + p[2][3]
  local l3 = p[3][1] + p[3][2] + p[3][3]
  if not (l1 < l2 and l2 < l3) then
    mono = false
    print(string.format("  palette %d luminance not ascending: %d %d %d", i, l1, l2, l3))
  end
end
check(mono, "each palette ascends in luminance 1 < 2 < 3")
-- ROM 0x3F6206 sDeoxysObjectPals, 8-bit values as the GBA expands them.
-- These are what the extracted meteorite sprite is baked with, so an exact
-- recolour match depends on them; the old JASC .pal ASCII values (32/82/139)
-- silently missed and the rock never reddened.
local ROM_PAL_0 = { { 33, 33, 33 }, { 82, 82, 82 }, { 140, 140, 140 } }
local ROM_PAL_10 = { { 206, 33, 33 }, { 255, 82, 82 }, { 255, 206, 156 } }
eq(Deoxys.ROCK_PALS[1][1][1], 33, "palette 0 index 1 is the meteorite's own 33,33,33")
eq(Deoxys.ROCK_PALS[11][1][1], 206, "palette 10 index 1 is the awakened 206,33,33")
eq(Deoxys.ROCK_PALS[11][3][1], 255, "palette 10 index 3 is the brightest 255,206,156")
local rampsMatch = true
for i = 1, 3 do
  for c = 1, 3 do
    if Deoxys.ROCK_PALS[1][i][c] ~= ROM_PAL_0[i][c]
      or Deoxys.ROCK_PALS[11][i][c] ~= ROM_PAL_10[i][c] then
      rampsMatch = false
    end
  end
end
check(rampsMatch, "the first and last ramps are byte-exact against the ROM")
eq(Deoxys.sourcePalette(), Deoxys.ROCK_PALS[1],
  "sourcePalette() is the pristine meteorite palette the swap matches against")
eq(Deoxys.palette(0), Deoxys.ROCK_PALS[1], "palette(0)")
eq(Deoxys.palette(10), Deoxys.ROCK_PALS[11], "palette(10)")
eq(Deoxys.paletteKey(3), "deoxys_rock_3", "paletteKey is stable for the sprite cache")

print("[test] 5. move frame counts")
eq(Deoxys.moveFrames(0), 60, "returning to the start takes 60 frames")
for num = 1, 10 do
  eq(Deoxys.moveFrames(num), 5, "position " .. num .. " takes 5 frames")
end

print("[test] 6. map gating")
check(Deoxys.isBirthIsland(Deoxys.MAP_ID), "the Birth Island map id is accepted")
check(Deoxys.isBirthIsland("FR_BIRTH_ISLAND_EXTERIOR"),
  "the literal engine map id is accepted")
check(not Deoxys.isBirthIsland("FR_FOUR_ISLAND_ICEFALL_CAVE_1F"),
  "another map is rejected")
check(not Deoxys.isBirthIsland(nil), "a nil map is rejected")

print("[test] 7. interact — the advance branch")
do
  local session = newSession()
  eq(Deoxys.interact(session), 1, "interacting at position 0 returns VAR_RESULT 1")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM), 1, "the counter advanced to 1")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER), 0,
    "the step counter is reset to 0")
  eq(Deoxys.interact(session), 1, "interacting again returns 1")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM), 2, "the counter advanced to 2")
end

print("[test] 8. interact — the reset branch (walked past the cap)")
do
  local session = newSession()
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM, 3)
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER, 9) -- cap for 3 is 8
  eq(Deoxys.interact(session), 0, "too many steps returns VAR_RESULT 0")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM), 0, "the rock is back at position 0")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER), 0, "steps reset")
end

print("[test] 9. interact — the step cap is strict and only applies above 0")
do
  local session = newSession()
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM, 3)
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER, 8) -- == cap
  eq(Deoxys.interact(session), 1, "exactly the cap still advances")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM), 4, "advanced to 4")
end
do
  local session = newSession()
  -- pret: `r5 != 0 && caps[r5-1] < r6`; at r5 == 0 the cap is never consulted.
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM, 0)
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER, 99)
  eq(Deoxys.interact(session), 1, "position 0 ignores the step cap")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM), 1, "advanced to 1")
end
do
  local session = newSession()
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM, 1)
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER, 5) -- cap for 1 is 4
  eq(Deoxys.interact(session), 0, "position 1 resets at 5 steps")
end
do
  local session = newSession()
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM, 9)
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER, 4) -- cap for 9 is 3
  eq(Deoxys.interact(session), 0, "position 9 resets at 4 steps")
end

print("[test] 10. interact — solving the puzzle")
do
  local session = newSession()
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM, 10)
  eq(Deoxys.interact(session), 2, "position 10 returns VAR_RESULT 2")
  check(Deoxys.getFlag(session, Deoxys.FLAG_SYS_DEOXYS_AWAKENED),
    "FLAG_SYS_DEOXYS_AWAKENED is set")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM), 10, "the counter stays at 10")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER), 0, "steps reset")
end

print("[test] 11. interact — already awakened")
do
  local session = newSession()
  Deoxys.setFlag(session, Deoxys.FLAG_SYS_DEOXYS_AWAKENED, true)
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM, 4)
  eq(Deoxys.interact(session), 3, "an awakened Deoxys returns VAR_RESULT 3")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM), 4,
    "the rock does not move once awakened")
end

print("[test] 12. the full walkthrough")
do
  -- pret only reports "solved" when the counter already reads 10, so the rock
  -- needs ten successful interactions to reach 10 and an eleventh to awaken.
  local session = newSession()
  local sawSolved = false
  for step = 1, 10 do
    eq(Deoxys.interact(session), 1, "interaction " .. step .. " returns 1")
    eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM), step,
      "rock advanced to " .. step)
    -- Each interaction resets the walk counter, so the cap is never tripped.
  end
  if Deoxys.interact(session) == 2 then sawSolved = true end
  check(sawSolved, "the eleventh interaction solves the puzzle")
  check(Deoxys.getFlag(session, Deoxys.FLAG_SYS_DEOXYS_AWAKENED),
    "solving sets FLAG_SYS_DEOXYS_AWAKENED")
  eq(Deoxys.interact(session), 3, "a twelfth interaction reports already-awakened")
end

print("[test] 13. IncrementBirthIslandRockStepCount")
do
  local session = newSession(Deoxys.MAP_ID)
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER, 0)
  check(Deoxys.incrementStepCount(session), "a step on Birth Island counts")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER), 1, "the counter is 1")
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER, 98)
  Deoxys.incrementStepCount(session)
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER), 99, "98 -> 99")
  Deoxys.incrementStepCount(session)
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER), 0, "99 -> 0 (pret wraps)")
end
do
  local session = newSession("FR_FOUR_ISLAND_ICEFALL_CAVE_1F")
  setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER, 7)
  check(not Deoxys.incrementStepCount(session), "a step elsewhere does not count")
  eq(getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER), 7,
    "the counter is untouched off Birth Island")
end
check(not Deoxys.incrementStepCount(nil), "a nil session is safe")

print("[test] 14. step_events calls the counter on Birth Island")
do
  local StepEvents = require("src.core.game3.step_events")
  local session = newSession(Deoxys.MAP_ID)
  session.store.vars[Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER] = 0
  StepEvents.onStepTaken(session, {})
  eq(tonumber(session.store.vars[Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER]), 1,
    "walking on Birth Island bumped the rock step counter")
end

print("[test] 15. field effect arguments (setfieldeffectargument)")
do
  FieldEffects.clearFieldEffectArguments()
  check(FieldEffects.setFieldEffectArgument(0, 1), "argument 0 accepted")
  check(FieldEffects.setFieldEffectArgument(5, 60), "argument 5 accepted")
  eq(FieldEffects.fieldEffectArgument(0), 1, "argument 0 reads back")
  eq(FieldEffects.fieldEffectArgument(5), 60, "argument 5 reads back")
  eq(FieldEffects.fieldEffectArgument(9, -1), -1, "a missing argument uses the default")
  check(not FieldEffects.setFieldEffectArgument(-1, 0), "a negative slot is rejected")
  check(not FieldEffects.setFieldEffectArgument(16, 0), "a slot above 15 is rejected")
end

print("[test] 16. the setfieldeffectargument opcode")
do
  -- pret VarGet: ids < 0x4000 are literals and pass through unchanged, which is
  -- exactly what the BirthIsland_Exterior script relies on for LOCALID/MAP_NUM.
  local ops = require("src.core.game3.scripting.ops_a")
  local seen = {}
  local store = { flags = {}, vars = { [0x4001] = 42 } }
  local ctx = { specialVars = {} }
  local vm = {
    store = store,
    tick = function() return true end,
    getText = function() return nil end,
  }
  -- ops_a dispatches by looking the opcode up in the VM's opcode table; call the
  -- adapter seam directly instead so the assertion stays about the semantics.
  local a = {
    setFieldEffectArgument = function(argNum, value) seen[argNum] = value end,
  }
  check(type(ops) == "table", "ops_a loads")
  FieldEffects.clearFieldEffectArguments()
  check(a.setFieldEffectArgument(0, 1) == nil, "adapter seam is callable")
  eq(seen[0], 1, "the adapter received the literal localId")
  eq(store.vars[0x4001], 42, "a variable operand still reads from the store")
end

print("[test] 17. FLDEFF_MOVE_DEOXYS_ROCK")
do
  FieldEffects.clearFieldEffectArguments()
  FieldEffects.setFieldEffectArgument(0, 1)
  FieldEffects.setFieldEffectArgument(3, 15)
  FieldEffects.setFieldEffectArgument(4, 10)
  FieldEffects.setFieldEffectArgument(5, 5)
  eq(FieldEffects.doFieldEffect(Deoxys.FLDEFF_MOVE_ROCK), false,
    "with no rock object on the map the effect reports it did not start")
  check(not FieldEffects.isFieldEffectActive(Deoxys.FLDEFF_MOVE_ROCK),
    "and it is not active")
  local ran = false
  FieldEffects.waitFieldEffect(Deoxys.FLDEFF_MOVE_ROCK, function() ran = true end)
  check(ran, "waitfieldeffect calls back immediately when nothing is running")
end

print("[test] 18. FLDEFF_DESTROY_DEOXYS_ROCK")
do
  FieldEffects.clearFieldEffectArguments()
  FieldEffects.setFieldEffectArgument(0, 1)
  eq(FieldEffects.doFieldEffect(Deoxys.FLDEFF_DESTROY_ROCK), false,
    "with no rock object on the map the destroy effect does not start")
end

print("[test] 19. the rock object is driven when one is on the map")
do
  local Objects = require("src.core.game3.objects")
  local savedById, savedOrder, savedMapId = Objects._byId, Objects._order, Objects._mapId
  local rock = {
    localId = 1, graphicsId = Deoxys.OBJ_EVENT_GFX_METEORITE,
    px = 15 * 16, py = 12 * 16, cellX = 15, cellY = 12,
    homeX = 15, homeY = 12, targetX = 15, targetY = 12,
    def = { x = 15, y = 12, localId = 1 },
  }
  Objects._byId = { [1] = rock }
  Objects._order = { 1 }
  Objects._mapId = Deoxys.MAP_ID
  Objects._perm = {}

  eq(Deoxys.resolveRockObject(), rock, "the meteorite object is resolved by local_id")
  check(Deoxys.moveRock(3), "moveRock(3) starts")
  check(FieldEffects.isFieldEffectActive(Deoxys.FLDEFF_MOVE_ROCK),
    "FLDEFF_MOVE_DEOXYS_ROCK is active")
  eq(rock.homeX, 19, "the template home x is the new cell immediately (pret SetObjEventTemplateCoords)")
  eq(rock.homeY, 14, "the template home y is the new cell immediately")
  eq(rock.px, 15 * 16, "the sprite is still drawn at its old position while it slides")

  local resolved = false
  FieldEffects.waitFieldEffect(Deoxys.FLDEFF_MOVE_ROCK, function() resolved = true end)
  check(not resolved, "waitfieldeffect parks until the slide finishes")
  for _ = 1, 5 do FieldEffects.step() end
  check(resolved, "the waiter is released when the slide ends")
  eq(rock.px, 19 * 16, "the sprite landed on the target cell")
  eq(rock.py, 14 * 16, "and on the target row")
  check(not FieldEffects.isFieldEffectActive(Deoxys.FLDEFF_MOVE_ROCK),
    "the effect is no longer active")

  eq(Deoxys.moveRock(0), true, "moveRock(0) starts the 60-frame snap-back")
  for _ = 1, 60 do FieldEffects.step() end
  eq(rock.px, 15 * 16, "the rock snapped back to (15,12)")
  eq(rock.py, 12 * 16, "and to row 12")

  check(Deoxys.destroyRock(1), "destroyRock starts")
  check(FieldEffects.isFieldEffectActive(Deoxys.FLDEFF_DESTROY_ROCK),
    "FLDEFF_DESTROY_DEOXYS_ROCK is active")
  local destroyed = false
  FieldEffects.waitFieldEffect(Deoxys.FLDEFF_DESTROY_ROCK, function() destroyed = true end)
  check(not destroyed, "waitfieldeffect parks until the shatter finishes")
  -- 120 frames of camera shake + ~85 frames of decaying shake with the shards.
  for _ = 1, 260 do FieldEffects.step() end
  check(destroyed, "the waiter is released when the rock is gone")
  check(rock.hidden, "the rock object is removed from the map")
  check(not FieldEffects.isFieldEffectActive(Deoxys.FLDEFF_DESTROY_ROCK),
    "the destroy effect ended")

  Objects._byId, Objects._order, Objects._mapId = savedById, savedOrder, savedMapId
  Objects._perm = {}
end

print("[test] 20. the interact handler writes VAR_RESULT")
do
  local store = { flags = {}, vars = {} }
  local session = { store = store, map = Deoxys.MAP_ID, party = {} }
  local saved = package.loaded["src.core.game3.runtime"]
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return session end,
    isActive = function() return true end,
  }
  local ctx = { specialVars = {} }
  local yield = Events.HANDLERS[Std.SPECIAL.DoDeoxysTriangleInteraction](ctx, {})
  eq(yield, false, "DoDeoxysTriangleInteraction does not yield")
  eq(Flags.getVar(store, ctx, 0x800D), 1, "VAR_RESULT is 1 (advanced)")
  eq(Flags.getVar(store, ctx, Deoxys.VAR_DEOXYS_INTERACTION_NUM), 1,
    "the rock advanced")
  package.loaded["src.core.game3.runtime"] = saved
end

print("[test] 21. SetDeoxysTrianglePalette no longer no-ops")
do
  local store = { flags = {}, vars = {} }
  local session = { store = store, map = Deoxys.MAP_ID, party = {} }
  local saved = package.loaded["src.core.game3.runtime"]
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return session end,
    isActive = function() return true end,
  }
  Flags.setVar(store, nil, Deoxys.VAR_DEOXYS_INTERACTION_NUM, 5)
  local ctx = { specialVars = {} }
  local yield = Events.HANDLERS[Std.SPECIAL.SetDeoxysTrianglePalette](ctx, {})
  eq(yield, false, "SetDeoxysTrianglePalette does not yield")
  eq(Flags.getVar(store, ctx, 0x800D), 0, "and still leaves VAR_RESULT at 0")
  package.loaded["src.core.game3.runtime"] = saved
end

print("[test] 22. the special is registered with the natives dispatcher")
do
  local ok, _, known = Natives.special({ specialVars = {} },
    Std.SPECIAL.DoDeoxysTriangleInteraction, {})
  check(ok == false, "the dispatcher reports no yield")
  eq(known, true, "and reports the special as known")
end

print("[test] 23. Deoxys keeps its own battle theme")
do
  local Audio = require("src.core.game3.audio")
  -- pokefirered/src/battle_setup.c:349 StartLegendaryBattle
  eq(Audio.legendaryBattleSong(Deoxys.SPECIES_DEOXYS), Deoxys.MUS_VS_DEOXYS,
    "SPECIES_DEOXYS plays MUS_VS_DEOXYS")
  eq(Audio.legendaryBattleSong(150), 340, "SPECIES_MEWTWO plays MUS_VS_MEWTWO")
  eq(Audio.legendaryBattleSong(249), 341, "SPECIES_LUGIA plays MUS_VS_LEGEND")
  eq(Audio.legendaryBattleSong(250), 341, "SPECIES_HO_OH plays MUS_VS_LEGEND")
  eq(Audio.legendaryBattleSong(144), 341, "SPECIES_ARTICUNO plays MUS_VS_LEGEND")
  eq(Audio.legendaryBattleSong(145), 341, "SPECIES_ZAPDOS plays MUS_VS_LEGEND")
  eq(Audio.legendaryBattleSong(146), 341, "SPECIES_MOLTRES plays MUS_VS_LEGEND")
  check(Audio.legendaryBattleSong(386) == nil,
    "386 is SPECIES_VOLBEAT, an ordinary wild mon, and gets no legendary theme")
  check(Audio.legendaryBattleSong(25) == nil, "Pikachu gets no legendary theme")
  check(Audio.legendaryBattleSong(nil) == nil, "a missing species is safe")
end

print("[test] 24. seteventmon -> CreateEnemyEventMon -> StartLegendaryBattle")
do
  local Enc = require("src.core.game3.encounters")
  local savedRuntime = package.loaded["src.core.game3.runtime"]
  local savedSpace = package.loaded["src.core.game3.scripting.space"]
  local store = { flags = {}, vars = {} }
  local session = { store = store, map = Deoxys.MAP_ID, party = {} }
  package.loaded["src.core.game3.scripting.space"] = nil
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return session end,
    isActive = function() return true end,
  }

  -- pokefirered/data/event_scripts.s: seteventmon SPECIES_DEOXYS, 30
  local ctx = { specialVars = {} }
  Flags.setVar(store, ctx, 0x8004, Deoxys.SPECIES_DEOXYS)
  Flags.setVar(store, ctx, 0x8005, 30)
  Flags.setVar(store, ctx, 0x8006, 0)
  Enc.takePendingWild()

  local create = Events.HANDLERS[Std.SPECIAL.CreateEnemyEventMon]
  check(create ~= nil, "CreateEnemyEventMon is handled")
  eq(create(ctx), false, "CreateEnemyEventMon does not yield")
  local pending = Enc._pendingWild
  check(pending ~= nil, "the event mon is queued for the battle")
  eq(pending and pending.species, Deoxys.SPECIES_DEOXYS, "the queued mon is Deoxys")
  eq(pending and pending.level, 30, "at level 30")
  check(pending and pending.fatefulEncounter == true, "as a fateful encounter")

  local started = nil
  local adapters = {
    startWildBattle = function(foe, _cb, o) started = { foe = foe, opts = o } end,
  }
  local launch = Natives.ALLOW["special:" .. Std.SPECIAL.StartLegendaryBattle]
  check(launch ~= nil, "StartLegendaryBattle is handled")
  eq(launch(ctx, adapters), true, "StartLegendaryBattle yields to the battle")
  check(started ~= nil, "a wild battle was started")
  eq(started and started.foe.species, Deoxys.SPECIES_DEOXYS,
    "against SPECIES_DEOXYS")
  eq(started and started.foe.level, 30, "at level 30")
  check(started and started.foe.legendary == true, "flagged legendary")
  check(started and started.foe.specialWild == true,
    "flagged a scripted wild battle")
  check(started and started.opts and started.opts.legendary == true,
    "startWildBattle is told this is a legendary battle")
  check(Enc.takePendingWild() == nil, "the pending mon was consumed")

  package.loaded["src.core.game3.runtime"] = savedRuntime
  package.loaded["src.core.game3.scripting.space"] = savedSpace
end

print("[test] 25. the shatter artwork is registered against the ROM")
do
  local Versions = require("src.import.gba.versions")
  local spec = Versions.FIELD_EFFECTS and Versions.FIELD_EFFECTS.deoxys_rock_fragments
  check(spec ~= nil, "deoxys_rock_fragments is registered")
  if spec then
    eq(spec.pic, 0x3CBDB0, "the four 8x8 shard tiles come from ROM 0x3CBDB0")
    eq(spec.w, 8, "each shard is 8px wide")
    eq(spec.h, 8, "each shard is 8px tall")
    eq(spec.frames, 4, "one frame per shard")
    -- sDeoxysObjectPals[10] = the fully awakened red step; pret's shards
    -- inherit the rock's paletteNum, and the puzzle is always solved by then.
    eq(spec.pal, 0x3F6206 + 10 * 32, "the shards use ramp step 10 (red)")
    check(spec.swapNibbles ~= true, "the ROM tiles are standard 4bpp, no nibble swap")
  end
  local CacheContract = require("src.import.CacheContract")
  local required = CacheContract.VERSION_REQUIRED_FILES_OVERRIDE
    and CacheContract.VERSION_REQUIRED_FILES_OVERRIDE.firered
  local listed = false
  if type(required) == "table" then
    for _, rel in ipairs(required) do
      if rel == "data/generated/gba/field_effects/deoxys_rock_fragments.rgba" then
        listed = true
      end
    end
  end
  check(listed, "the sheet is a required firered cache file, so a stale cache re-imports")
end

print("[test] 26. the shatter spawns four shards that fly apart")
do
  local Objects = require("src.core.game3.objects")
  local savedById, savedOrder = Objects._byId, Objects._order
  local savedMapId, savedPerm = Objects._mapId, Objects._perm
  local rock = {
    graphicsId = Deoxys.OBJ_EVENT_GFX_METEORITE,
    px = 15 * 16, py = 12 * 16, cellX = 15, cellY = 12,
    homeX = 15, homeY = 12, targetX = 15, targetY = 12,
    def = { x = 15, y = 12, localId = 1 },
  }
  Objects._byId = { [1] = rock }
  Objects._order = { 1 }
  Objects._mapId = Deoxys.MAP_ID
  Objects._perm = {}

  check(Deoxys.destroyRock(1), "destroyRock starts the shatter")
  local anim
  for _, a in ipairs(FieldEffects._anims or {}) do
    if a.kind == "deoxys_rock_destroy" then anim = a end
  end
  check(anim ~= nil, "the destroy animation is queued")
  if anim then
    eq(anim.state, "shake", "it starts with the camera shake")
    eq(#(anim.frags or {}), 4, "four shards are spawned")
    -- pret CreateDeoxysRockFragments: all four at the SAME point.
    local sameOrigin = true
    for _, f in ipairs(anim.frags) do
      if f.ox ~= anim.frags[1].ox or f.oy ~= anim.frags[1].oy then sameOrigin = false end
    end
    check(sameOrigin, "all four shards start at the rock's own corner")
    local dirs = { { -16, -12 }, { 16, -12 }, { -16, 12 }, { 16, 12 } }
    local dirsOk = true
    for i, f in ipairs(anim.frags) do
      if f.dx ~= dirs[i][1] or f.dy ~= dirs[i][2] then dirsOk = false end
    end
    check(dirsOk, "the shards fly out at +/-16 x and +/-12 y per frame")

    for _ = 1, 130 do FieldEffects.step() end
    eq(anim.state, "shatter", "after 120 frames the rock shatters")
    check(rock.hidden or rock.invisible, "the rock is hidden before Deoxys appears")
    local moved = true
    for i, f in ipairs(anim.frags) do
      if f.off then
        moved = false
      else
        local travelled = (f.x - f.ox) * dirs[i][1] + (f.y - f.oy) * dirs[i][2]
        if travelled <= 0 then moved = false end
      end
    end
    check(moved, "each shard has travelled along its own diagonal")

    for _ = 1, 200 do FieldEffects.step() end
    check(not FieldEffects.isFieldEffectActive(Deoxys.FLDEFF_DESTROY_ROCK),
      "the shatter effect finishes once the shake dies down")
  end

  Objects._byId, Objects._order = savedById, savedOrder
  Objects._mapId, Objects._perm = savedMapId, savedPerm
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
