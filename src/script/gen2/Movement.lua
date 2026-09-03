-- Gen 2 overworld movement-script helpers (macros/scripts/movement.asm).
-- Import stores raw byte streams; the world steps them one command at a time.

local bit = require("bit")

local Movement = {}

local DIR = { [0] = "down", [1] = "up", [2] = "left", [3] = "right" }
Movement.DIR = DIR
Movement.FACING = DIR

-- High nibble / command family (low 2 bits = facing when directional).
local STEP_END = 0x47
local STEP_WAIT_END = 0x48
-- The two warp-exit bytes.  Each of StepFunction_TeleportFrom's two beats runs
-- for 16 frames (`ld [hl], 16` into OBJECT_STEP_DURATION), and TeleportTo's
-- three -- wait, descent, final spin -- for 16 each.
local TELEPORT_FROM = 0x4c
local TELEPORT_TO = 0x4d
local TELEPORT_BEAT_FRAMES = 16
local TELEPORT_FROM_FRAMES = 2 * TELEPORT_BEAT_FRAMES
local TELEPORT_TO_FRAMES = 3 * TELEPORT_BEAT_FRAMES
-- The four OBJECT_FLAGS1 control bytes (macros/scripts/movement.asm:78-96).
-- None of them consume a frame: each Movement_* handler ends in
-- `jp ContinueReadingMovement` (engine/overworld/movement.asm:353-375), so the
-- next byte is read in the same pass.
local REMOVE_SLIDING = 0x38
local SET_SLIDING = 0x39
local REMOVE_FIXED_FACING = 0x3a
local FIX_FACING = 0x3b
-- Movement_tree_shake (engine/overworld/movement.asm:334): 24 frames of
-- STEP_TYPE_SLEEP with OBJECT_ACTION set to OBJECT_ACTION_WEIRD_TREE.
local TREE_SHAKE = 0x56
local TREE_SHAKE_FRAMES = 24
-- engine/events/forced_movement.asm:25-51; step_dig's frame count is the
-- byte after it (macros/scripts/movement.asm:163-167)
local TURN_HEAD = 0x00
local TURN_IN = 0x24
local STEP_DIG = 0x4f
local STEP_DIG_FRAMES = 16

function Movement.dir(nibble)
  return DIR[nibble % 4] or "down"
end

-- Decode one byte into an action table, or nil to ignore / end.
-- Returns { kind="step"|"turn"|"sleep"|"end", dir=?, frames=? }.
function Movement.decodeByte(b)
  if b == STEP_END or b == STEP_WAIT_END then
    return { kind = "end" }
  end
  local family = bit.band(b, 0xfc)
  local dir = Movement.dir(bit.band(b, 0x03))
  if family == 0x00 then -- turn_head
    return { kind = "turn", dir = dir }
  elseif family == 0x04 then -- turn_step (face then step)
    return { kind = "step", dir = dir }
  elseif family == 0x08 then -- slow_step
    return { kind = "step", dir = dir }
  elseif family == 0x0c then -- step
    return { kind = "step", dir = dir }
  elseif family == 0x10 then -- big_step
    return { kind = "step", dir = dir }
  elseif family == 0x14 or family == 0x18 or family == 0x1c then -- slides
    return { kind = "step", dir = dir }
  elseif family == 0x20 or family == 0x24 or family == 0x28 then
    -- turn_away / turn_in / turn_waterfall all `jp TurningStep`, which steps a
    -- cell under OBJECT_ACTION_SPIN -- movement.asm:483-513, :693-715 (#1716)
    return { kind = "step", dir = dir, spin = true }
  elseif family == 0x2c or family == 0x30 or family == 0x34 then
    -- slow_jump_step / jump_step / fast_jump_step, all of which reach
    -- JumpStep (engine/overworld/movement.asm:741) and so run under
    -- StepFunction_NPCJump (engine/overworld/map_objects.asm:1129).  That
    -- step type is TWO beats: `.Jump` walks a cell and then calls GetNextTile
    -- a second time (map_objects.asm:1143), which re-advances OBJECT_MAP_X/Y,
    -- and `.Land` walks that second cell.  A jump therefore covers two cells,
    -- not one; folding it into a plain step left every scripted jump a cell
    -- short and carried the offset through the rest of the stream (the Ilex
    -- Forest Farfetch'd ended up walking its last six UP steps through the
    -- trees one column over).
    return { kind = "jump", dir = dir }
  elseif b == SET_SLIDING or b == REMOVE_SLIDING then
    -- Movement_set_sliding / _remove_sliding toggle SLIDING_F in
    -- OBJECT_FLAGS1 (engine/overworld/movement.asm:353-363).  Both
    -- SetFacingStepAction and SetFacingBumpAction bail straight to
    -- SetFacingCurrent while it is set (engine/overworld/map_object_action.asm
    -- :48 and :74), so the object keeps BOTH its facing and its current step
    -- frame for the whole stream: it is a slide, not a walk.  Dropping the
    -- byte is what turned the three beasts around to face the way they flee
    -- out of the Burned Tower and gave them a walk cycle on the way
    -- (maps/BurnedTowerB1F.asm:103-125 wrap every beast stream in it).
    return { kind = "sliding", on = (b == SET_SLIDING) }
  elseif b == FIX_FACING or b == REMOVE_FIXED_FACING then
    -- Movement_fix_facing / _remove_fixed_facing toggle FIXED_FACING_F in
    -- OBJECT_FLAGS1 (engine/overworld/movement.asm:365-375).  InitStep tests
    -- it and jumps PAST the write to OBJECT_DIRECTION
    -- (engine/overworld/map_objects.asm:284-294), so a fixed-facing object
    -- steps without turning; ApplyObjectFacing refuses it too
    -- (engine/overworld/scripting.asm:856), which is why faceplayer cannot
    -- turn one either.  Route 30's two Rattata lunge under it
    -- (maps/Route30.asm:183-193) and ended up facing away from the fight.
    return { kind = "fixfacing", fixed = (b == FIX_FACING) }
  elseif b == 0x3c or b == 0x3d then -- show/hide object
    return { kind = "nop" }
  elseif b >= 0x3e and b <= 0x46 then -- step_sleep N
    return { kind = "sleep", frames = (b - 0x3e + 1) * 16 }
  elseif b == TELEPORT_FROM or b == TELEPORT_TO then
    -- Movement_teleport_from / _to set STEP_TYPE_TELEPORT_FROM / _TO
    -- (engine/overworld/movement.asm:95), whose step functions are
    -- StepFunction_TeleportFrom / _TeleportTo in
    -- engine/overworld/map_objects.asm: a spin on the spot, then a spinning
    -- rise (or a wait, a spinning descent and a last spin) driven off
    -- OBJECT_JUMP_HEIGHT through Sine.  Without a branch here the byte fell off
    -- the family ladder and read as `nop`, so Lance blinked out of the Lake of
    -- Rage and Blue off Cinnabar with no animation at all.
    return {
      kind = "teleport",
      mode = (b == TELEPORT_FROM) and "from" or "to",
      frames = (b == TELEPORT_FROM) and TELEPORT_FROM_FRAMES
        or TELEPORT_TO_FRAMES,
    }
  elseif b == TREE_SHAKE then
    -- Movement_tree_shake (engine/overworld/movement.asm:334) puts 24 in
    -- OBJECT_STEP_DURATION, sets STEP_TYPE_SLEEP and sets OBJECT_ACTION to
    -- OBJECT_ACTION_WEIRD_TREE, so SetFacingWeirdTree
    -- (engine/overworld/map_object_action.asm:204) rocks the tree through
    -- FACING_WEIRD_TREE_0..3 for those 24 frames.  $56 sits above the
    -- step_sleep window and matches no family, so it used to reach the
    -- trailing nop: the world then ate it and the step_end after it in one
    -- pass and Sudowoodo's shake played in zero frames
    -- (maps/Route36.asm:260-262 SudowoodoShakeMovement is this byte alone).
    return { kind = "treeshake", frames = TREE_SHAKE_FRAMES }
  end
  return { kind = "nop" }
end

function Movement.isEnd(b)
  return b == STEP_END or b == STEP_WAIT_END
end

Movement.STEP_END = STEP_END
Movement.STEP_WAIT_END = STEP_WAIT_END
Movement.TELEPORT_FROM = TELEPORT_FROM
Movement.TELEPORT_TO = TELEPORT_TO
Movement.TELEPORT_BEAT_FRAMES = TELEPORT_BEAT_FRAMES
Movement.REMOVE_SLIDING = REMOVE_SLIDING
Movement.SET_SLIDING = SET_SLIDING
Movement.REMOVE_FIXED_FACING = REMOVE_FIXED_FACING
Movement.FIX_FACING = FIX_FACING
Movement.TREE_SHAKE = TREE_SHAKE
Movement.TREE_SHAKE_FRAMES = TREE_SHAKE_FRAMES
Movement.STEP_DIG = STEP_DIG
Movement.STEP_DIG_FRAMES = STEP_DIG_FRAMES

-- SetFacingWeirdTree's own index: it increments OBJECT_STEP_FRAME BEFORE
-- masking (`inc a / maskbits NUM_DIRECTIONS, 2 / rrca / rrca`), so the count
-- that reaches the facing table is frame+1 and the quarter changes every four
-- frames (engine/overworld/map_object_action.asm:204).  FacingWeirdTree0 and
-- FacingWeirdTree2 are FacingStepDown0's tiles $00-$03, FacingWeirdTree1 is
-- $04-$07 and FacingWeirdTree3 is those same four with the columns swapped and
-- OAM_XFLIP on each, i.e. the mirror image (data/sprites/facings.asm:46-52,
-- :185-190, :192-197).
function Movement.treeShakeIndex(frame)
  return math.floor(((frame or 0) + 1) % 16 / 4) % 4
end

-- Sine (home/sine.asm) with the amplitude StepFunction_TeleportFrom passes:
-- `ld d, $60 / call Sine / ld a, h / sub $60`, i.e. the high byte of
-- $60 * sin(height * 2pi / 64) minus $60.  Both teleport beats walk
-- OBJECT_JUMP_HEIGHT through this and write the answer to
-- OBJECT_SPRITE_Y_OFFSET, so the sprite lifts a hundred-odd pixels off its
-- tile over sixteen frames and comes back down the same curve.
function Movement.teleportYOffset(height)
  return math.floor(0x60 * math.sin((height % 64) * math.pi / 32)) - 0x60
end

-- OBJECT_JUMP_HEIGHT's own start values: $10 for the rise (.InitSpinRise) and
-- 0 for the descent (.InitDescent).
Movement.TELEPORT_RISE_HEIGHT = 0x10
Movement.TELEPORT_FALL_HEIGHT = 0

-- engine/overworld/map_objects.asm:1796-1817
Movement.JUMP_Y = {
  -4, -6, -8, -10, -11, -12, -12, -12,
  -11, -10, -9, -8, -6, -4, 0, 0,
}

function Movement.jumpYOffset(progress, frames)
  local curve = Movement.JUMP_Y
  local n = #curve
  local t = ((progress or 0) - 1) * (n - 1) / math.max((frames or n) - 1, 1) + 1
  local idx = math.floor(t)
  if idx < 1 then idx = 1 end
  if idx >= n then return curve[n] end
  return math.floor(curve[idx] + (curve[idx + 1] - curve[idx]) * (t - idx) + 0.5)
end

local DIR_BYTE = { down = 0, up = 1, left = 2, right = 3 }

-- The `step <dir>` family ($0c-$0f), which is what InitMovementBuffer fills
-- for a trainer walking up to the player.
function Movement.stepByte(dir)
  return 0x0c + (DIR_BYTE[dir] or 0)
end

-- Script_ForcedMovement's stream, `back` being the direction thrown in
-- -- engine/events/forced_movement.asm:25-51
function Movement.forcedMovementBytes(back)
  local d = DIR_BYTE[back] or 0
  return {
    STEP_DIG, STEP_DIG_FRAMES, TURN_IN + d,
    STEP_DIG, STEP_DIG_FRAMES, TURN_HEAD + d,
    STEP_END,
  }
end

return Movement
