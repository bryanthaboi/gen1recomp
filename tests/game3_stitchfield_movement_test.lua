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

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Movement = require("src.core.game3.scripting.movement")

local DIRS = { "down", "up", "left", "right" }

print("[test] 1. MOVEMENT_ACTION_PLAYER_RUN_DOWN/UP/LEFT/RIGHT 0x3D-0x40")
-- pokefirered/include/constants/event_object_movement.h:149
-- pokefirered/src/event_object_movement.c:5333 StartRunningAnim
for i, dir in ipairs(DIRS) do
  local b = 0x3D + i - 1
  local act = Movement.decodeAction(b)
  check(act.kind == "step", string.format("0x%02X is a step, got %s", b, tostring(act.kind)))
  check(act.dir == dir, string.format("0x%02X goes %s, got %s", b, dir, tostring(act.dir)))
  check(act.run == true, string.format("0x%02X is flagged as a run", b))
end

print("[test] 2. the _SLOW variants 0x41-0x44")
-- pokefirered/include/constants/event_object_movement.h:153
-- pokefirered/src/event_object_movement.c:6529 InitRunSlow
for i, dir in ipairs(DIRS) do
  local b = 0x41 + i - 1
  local act = Movement.decodeAction(b)
  check(act.kind == "step", string.format("0x%02X is a step, got %s", b, tostring(act.kind)))
  check(act.dir == dir, string.format("0x%02X goes %s, got %s", b, dir, tostring(act.dir)))
  check(act.run == true and act.slow == true,
    string.format("0x%02X is a slow run", b))
end

print("[test] 3. the neighbours are untouched")
-- pokefirered/include/constants/event_object_movement.h:145 MOVEMENT_ACTION_SLIDE_DOWN
for i, dir in ipairs(DIRS) do
  local slide = Movement.decodeAction(0x39 + i - 1)
  check(slide.kind == "step" and slide.dir == dir and slide.run == nil,
    string.format("0x%02X SLIDE_%s still a plain step", 0x39 + i - 1, dir:upper()))
end
-- pokefirered/include/constants/event_object_movement.h:157
check(Movement.decodeAction(0x45).kind == "nop",
  "0x45 START_ANIM_IN_DIRECTION is still undecoded")
for i, dir in ipairs(DIRS) do
  local jump = Movement.decodeAction(0x46 + i - 1)
  check(jump.kind == "jump" and jump.dir == dir,
    string.format("0x%02X JUMP_SPECIAL_%s is still a jump", 0x46 + i - 1, dir:upper()))
end

print("[test] 4. actionsFromBytes keeps a run stream instead of dropping it")
local stream = { 0x3D, 0x3D, 0x3D, 0x3D, 0x3D, 0x3D, Movement.STEP_END }
local acts = Movement.actionsFromBytes(stream)
check(#acts == 6, "six actions survive, got " .. #acts)
local allDown = true
for _, a in ipairs(acts) do
  if a.kind ~= "step" or a.dir ~= "down" or a.run ~= true then allDown = false end
end
check(allDown, "every one is a downward run")

print("[test] 4b. face_player, the facing lock, the animation toggle and the obstacle breaks")
-- pokefirered/src/event_object_movement.c:6772 MovementAction_FacePlayer_Step0
local facePlayer = Movement.decodeAction(0x4A)
check(facePlayer.kind == "face_player",
  "0x4A FACE_PLAYER decodes, got " .. tostring(facePlayer.kind))
check(facePlayer.away == nil, "0x4A turns toward the player, not away")
-- pokefirered/src/event_object_movement.c:6784 MovementAction_FaceAwayPlayer_Step0
local faceAway = Movement.decodeAction(0x4B)
check(faceAway.kind == "face_player" and faceAway.away == true,
  "0x4B FACE_AWAY_PLAYER is the opposite direction")
-- pokefirered/src/event_object_movement.c:6796 MovementAction_LockFacingDirection_Step0
local lock = Movement.decodeAction(0x4C)
check(lock.kind == "lock_facing" and lock.locked == true,
  "0x4C LOCK_FACING_DIRECTION decodes, got " .. tostring(lock.kind))
-- pokefirered/src/event_object_movement.c:6803 MovementAction_UnlockFacingDirection_Step0
local unlock = Movement.decodeAction(0x4D)
check(unlock.kind == "lock_facing" and unlock.locked == false,
  "0x4D UNLOCK_FACING_DIRECTION decodes, got " .. tostring(unlock.kind))
-- pokefirered/src/event_object_movement.c:7040 MovementAction_DisableAnimation_Step0
local disable = Movement.decodeAction(0x5E)
check(disable.kind == "animate" and disable.inanimate == true,
  "0x5E DISABLE_ANIMATION decodes, got " .. tostring(disable.kind))
-- pokefirered/src/event_object_movement.c:7047 MovementAction_RestoreAnimation_Step0
local restore = Movement.decodeAction(0x5F)
check(restore.kind == "animate" and restore.inanimate == false,
  "0x5F RESTORE_ANIMATION decodes, got " .. tostring(restore.kind))
-- pokefirered/src/data/object_events/object_event_anims.h:861 sAnim_RockBreak
-- pokefirered/src/event_object_movement.c:7146 SetMovementDelay
local smash = Movement.decodeAction(0x68)
check(smash.kind == "remove_obstacle", "0x68 ROCK_SMASH_BREAK decodes, got " .. tostring(smash.kind))
check(smash.frames == 64, "the rock break runs 4*8 + 32 = 64 frames, got " .. tostring(smash.frames))
-- pokefirered/src/data/object_events/object_event_anims.h:869 sAnim_TreeCut
local cut = Movement.decodeAction(0x69)
check(cut.kind == "remove_obstacle", "0x69 CUT_TREE decodes, got " .. tostring(cut.kind))
check(cut.frames == 56, "the tree cut runs 4*6 + 32 = 56 frames, got " .. tostring(cut.frames))
-- pokefirered/include/constants/event_object_movement.h:180
check(Movement.decodeAction(0x5C).kind == "nop",
  "0x5C ENABLE_JUMP_LANDING_GROUND_EFFECT is still undecoded, no cart stream uses it")

print("[test] 4c. a one-action stream no longer decodes to nothing")
-- pokefirered/data/scripts/movement.inc:15 Common_Movement_FacePlayer
check(#Movement.actionsFromBytes({ 0x4A, Movement.STEP_END }) == 1,
  "face_player + step_end is one action, not zero")
-- pokefirered/data/scripts/field_moves.inc:33 Movement_CutTreeDown
check(#Movement.actionsFromBytes({ 0x69, Movement.STEP_END }) == 1,
  "cut_tree + step_end is one action, not zero")
-- pokefirered/data/scripts/field_moves.inc:98 Movement_BreakRock
check(#Movement.actionsFromBytes({ 0x68, Movement.STEP_END }) == 1,
  "rock_smash_break + step_end is one action, not zero")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_stitchfield_movement_test cart checks: " .. tostring(Cache.reason))
  done()
end
print("[info] FireRed cache at " .. cacheRoot)

print("[test] 5. the one cart stream that uses them")
-- pokefirered/data/maps/IndigoPlateau_Exterior/scripts.inc:85 Movement_PlayerLeave
local ExtractScripts = require("src.import.gba.extract_scripts")
local bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })
local PLAYER_LEAVE = "g3:08167311"
local bytes = bundle.movements and bundle.movements[PLAYER_LEAVE]
check(type(bytes) == "table", PLAYER_LEAVE .. " is in the cache")
if type(bytes) == "table" then
  local raw = {}
  for i = 1, #bytes do raw[i] = bytes[i] end
  check(table.concat(raw, ",") == "61,61,61,61,61,61,254",
    "it is six player_run_down then step_end, got " .. table.concat(raw, ","))
  local cart = Movement.actionsFromBytes(bytes)
  check(#cart == 6, "it decodes to six actions, got " .. #cart)
  local ok = #cart == 6
  for _, a in ipairs(cart) do
    if a.kind ~= "step" or a.dir ~= "down" then ok = false end
  end
  check(ok, "all six walk the player south off the Indigo Plateau steps")
end

print("[test] 6. no other cached stream regressed into a nop")
local nops = {}
for _, v in pairs(bundle.movements or {}) do
  for i = 1, #v do
    local b = v[i]
    if b == Movement.STEP_END then break end
    if Movement.decodeAction(b).kind == "nop" then nops[b] = true end
  end
end
check(nops[0x3D] == nil and nops[0x41] == nil, "no run action is a nop any more")
for _, b in ipairs({ 0x4A, 0x4C, 0x4D, 0x5E, 0x5F, 0x68, 0x69 }) do
  check(nops[b] == nil, string.format("0x%02X is no longer a nop in any cached stream", b))
end
local left = {}
for b in pairs(nops) do left[#left + 1] = string.format("0x%02X", b) end
table.sort(left)
check(#left == 0, "every byte the cart's movement streams use now decodes, "
  .. tostring(#left) .. " left: " .. table.concat(left, ", "))

print("[test] 7. the cart streams that used to decode to nothing")
local function stream(key)
  local v = bundle.movements and bundle.movements[key]
  if type(v) ~= "table" then return nil end
  local raw = {}
  for i = 1, #v do raw[i] = string.format("%02X", v[i]) end
  return v, table.concat(raw, " ")
end

local fp, fpRaw = stream("g3:081a75e1")
check(fp ~= nil, "Common_Movement_FacePlayer g3:081a75e1 is in the cache")
if fp then
  check(fpRaw == "4A FE", "it is face_player then step_end, got " .. fpRaw)
  local a = Movement.actionsFromBytes(fp)
  check(#a == 1 and a[1].kind == "face_player",
    "it decodes to one face_player, got " .. #a .. " actions")
end

local ct, ctRaw = stream("g3:081bdf85")
check(ct ~= nil, "Movement_CutTreeDown g3:081bdf85 is in the cache")
if ct then
  check(ctRaw == "69 FE", "it is cut_tree then step_end, got " .. ctRaw)
  local a = Movement.actionsFromBytes(ct)
  check(#a == 1 and a[1].kind == "remove_obstacle" and a[1].frames == 56,
    "it decodes to one 56-frame remove_obstacle, got " .. #a .. " actions")
end

-- pokefirered/data/scripts/field_moves.inc:98 Movement_BreakRock
local br, brRaw = stream("g3:081be08f")
check(br ~= nil, "Movement_BreakRock g3:081be08f is in the cache")
if br then
  check(brRaw == "68 FE", "it is rock_smash_break then step_end, got " .. brRaw)
  local a = Movement.actionsFromBytes(br)
  check(#a == 1 and a[1].kind == "remove_obstacle" and a[1].frames == 64,
    "it decodes to one 64-frame remove_obstacle, got " .. #a .. " actions")
end

-- pokefirered/data/maps/IndigoPlateau_Exterior/scripts.inc:136 Movement_PushPlayerOutOfWay
local push, pushRaw = stream("g3:08167337")
check(push ~= nil, "Movement_PushPlayerOutOfWay g3:08167337 is in the cache")
if push then
  check(pushRaw == "03 4C 12 4D FE",
    "it is face_right, lock, walk_left, unlock, got " .. pushRaw)
  local a = Movement.actionsFromBytes(push)
  check(#a == 4, "all four survive now, got " .. #a)
  check(a[2].kind == "lock_facing" and a[2].locked == true, "the lock is action 2")
  check(a[3].kind == "step" and a[3].dir == "left", "the walk_left is action 3")
  check(a[4].kind == "lock_facing" and a[4].locked == false, "the unlock is action 4")
end

local fall, fallRaw = stream("g3:0816440f")
check(fall ~= nil, "Movement_ThiefFallIn g3:0816440f is in the cache")
if fall then
  check(fallRaw == "00 5E 39 39 39 39 39 39 39 39 39 5F FE",
    "it is face_down, disable_animation, nine slides, restore_animation, got " .. fallRaw)
  local a = Movement.actionsFromBytes(fall)
  check(#a == 12, "all twelve survive now, got " .. #a)
  check(a[2].kind == "animate" and a[2].inanimate == true,
    "the thief's walk animation is switched off for the fall")
  check(a[12].kind == "animate" and a[12].inanimate == false,
    "and restored when he lands")
end

done()
