-- Gen 2 field presentation: the teleport step types, the fishing bob, the fly
-- lift, the tilt billboard clip and the border-fill dissolve.
--
-- All five are drawing, so what is asserted is the state the drawing reads:
-- the decoded movement byte, the sprite Y offset a frame lands on, and the
-- clip / fade bookkeeping.  tests/drivers/gold_field_anim_shots.lua is the
-- half a test cannot cover.

package.path = "./?.lua;" .. package.path

love = love or {}
love.graphics = love.graphics or {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end,
  rectangle = function() end,
  draw = function() end,
  newQuad = function() return { setViewport = function() end } end,
  newImage = function()
    return { getDimensions = function() return 16, 96 end }
  end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
  getDimensions = function() return 160, 144 end,
}
love.math = love.math or { random = function(a, b) return b and a or 0.5 end }
require("src.core.Logger").warn = function() end

local BorderFill = require("src.world.gen2.BorderFill")
local Movement = require("src.script.gen2.Movement")
local NPC = require("src.world.gen2.Npc")
local Tilt = require("src.render.Tilt")

local checks, failures = 0, 0
local function check(label, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s want %s"):format(label, tostring(got),
      tostring(want)))
  end
end

-- ------------------------------------------------------- teleport_from / _to
--
-- macros/scripts/movement.asm:148: $4c teleport_from, $4d teleport_to.  Both
-- used to fall off the family ladder and decode as `nop`, so Lance's exit from
-- the Lake of Rage and Blue's off Cinnabar finished instantly.
local from = Movement.decodeByte(0x4c)
check("$4c decodes as a teleport", from.kind, "teleport")
check("and it is the leaving half", from.mode, "from")
check("two sixteen-frame beats", from.frames, 32)
local to = Movement.decodeByte(0x4d)
check("$4d decodes as a teleport", to.kind, "teleport")
check("and it is the arriving half", to.mode, "to")
check("three sixteen-frame beats", to.frames, 48)
-- The neighbours must not have moved.
check("$47 is still step_end", Movement.decodeByte(0x47).kind, "end")
check("$46 is still the last step_sleep",
  Movement.decodeByte(0x46).kind, "sleep")
check("$4e skyfall is still unmodelled", Movement.decodeByte(0x4e).kind, "nop")

-- ---------------------------------------------------------- the jump families
--
-- $2c slow_jump_step / $30 jump_step / $34 fast_jump_step all reach JumpStep
-- (engine/overworld/movement.asm:741) and run StepFunction_NPCJump
-- (engine/overworld/map_objects.asm:1129), whose `.Jump` beat calls GetNextTile
-- a SECOND time before `.Land` walks it: a jump crosses two cells.  They used
-- to decode as a plain one-cell step, which left the Ilex Forest Farfetch'd a
-- column short for the rest of its movement stream.
check("$30 jump_step DOWN is a jump", Movement.decodeByte(0x30).kind, "jump")
check("and it keeps its facing", Movement.decodeByte(0x33).dir, "right")
check("$2c slow_jump_step is one too", Movement.decodeByte(0x2c).kind, "jump")
check("$34 fast_jump_step as well", Movement.decodeByte(0x34).kind, "jump")
-- $20 turn_away / $24 turn_in / $28 turn_waterfall all `jp TurningStep`
-- (engine/overworld/movement.asm:483-513), which is InitStep with
-- OBJECT_ACTION_SPIN (:693-715): one cell crossed, spinning, not a facing
-- change.  Script_ForcedMovement's bounce out of a whirlpool is that step.
check("$28 turn_waterfall is a spinning step",
  Movement.decodeByte(0x28).kind, "step")
check("$24 turn_in is one too", Movement.decodeByte(0x24).kind, "step")
check("and it carries the spin", Movement.decodeByte(0x24).spin, true)
check("$10 big_step is untouched", Movement.decodeByte(0x10).kind, "step")

-- ------------------------------------------ sliding, fixed facing, tree shake
--
-- Movement_set_sliding / _remove_sliding ($39 / $38) and _fix_facing /
-- _remove_fixed_facing ($3b / $3a) toggle SLIDING_F and FIXED_FACING_F
-- (engine/overworld/movement.asm:353-363), and $56 tree_shake parks the object
-- on 24 frames of OBJECT_ACTION_WEIRD_TREE (:334).  All three used to decode as
-- `nop`, which is why the Burned Tower beasts turned and walked out instead of
-- gliding, the Route 30 Rattata finished facing away, and Sudowoodo's shake
-- completed in no frames at all.
local slideOn = Movement.decodeByte(0x39)
check("$39 set_sliding decodes as sliding", slideOn.kind, "sliding")
check("and it turns the flag on", slideOn.on, true)
local slideOff = Movement.decodeByte(0x38)
check("$38 remove_sliding is the same kind", slideOff.kind, "sliding")
check("and it turns the flag off", slideOff.on, false)
local fixOn = Movement.decodeByte(0x3b)
check("$3b fix_facing decodes as fixfacing", fixOn.kind, "fixfacing")
check("and it fixes the facing", fixOn.fixed, true)
local fixOff = Movement.decodeByte(0x3a)
check("$3a remove_fixed_facing is the same kind", fixOff.kind, "fixfacing")
check("and it releases it", fixOff.fixed, false)
local shake = Movement.decodeByte(0x56)
check("$56 tree_shake decodes as treeshake", shake.kind, "treeshake")
check("and it carries the cart's 24 frames", shake.frames, 24)
check("which is the module's own constant", Movement.TREE_SHAKE_FRAMES, 24)
-- The neighbours must not have moved.
check("$54 is still unmodelled", Movement.decodeByte(0x54).kind, "nop")
check("$57 is still unmodelled", Movement.decodeByte(0x57).kind, "nop")

-- SetFacingWeirdTree increments OBJECT_STEP_FRAME BEFORE masking
-- (engine/overworld/map_object_action.asm:204), so the quarter that reaches the
-- facing table is frame+1 over four: three frames on the first quarter, four on
-- each after it.
for frame, want in ipairs({ [1] = 0, [2] = 0, [3] = 0, [4] = 1,
    [5] = 1, [6] = 1, [7] = 1, [8] = 2 }) do
  check(("tree shake frame %d is quarter %d"):format(frame - 1, want),
    Movement.treeShakeIndex(frame - 1), want)
end

-- Sine with d = $60, minus $60: 0 at a quarter turn (on the tile) and -$60 at
-- a half turn (a full sprite-height and a half above it).
check("the curve is on the tile at height 16",
  Movement.teleportYOffset(16), 0)
check("and fully lifted at height 32", Movement.teleportYOffset(32), -0x60)
check("height 0 is the top of the descent", Movement.teleportYOffset(0), -0x60)

-- ------------------------------------------------------- the step type itself
-- SpriteRenderer wants a sheet; these assertions are about the step type, so
-- the sheet is the smallest one that loads.
local SPRITE = { image = "assets/generated/sprites/lance.png", frames = 6 }
local npc = NPC.new("LAKE_OF_RAGE", { index = 1, x = 4, y = 5, movement = 1 },
  SPRITE)
check("an object starts with no sprite offset", npc.spriteYOffset, nil)
npc:scriptTeleport("from", 32)
check("scriptTeleport freezes the object", npc.frozen, true)

local facings, highest = {}, 0
for frame = 1, 32 do
  npc:update(nil, nil)
  facings[npc.facing] = true
  if frame == 16 then
    check("the first beat spins on the spot", npc.spriteYOffset, 0)
  end
  highest = math.min(highest, npc.spriteYOffset or 0)
end
check("OBJECT_ACTION_SPIN turns through every facing",
  facings.up and facings.down and facings.left and facings.right, true)
-- The cart leaves OBJECT_SPRITE_Y_OFFSET where the last frame put it (the
-- object is normally `disappear`ed on top of it); this puts the sprite back on
-- its tile instead, so the deepest offset the animation reaches is the frame
-- before the last -- five sprite rows clear of the ground either way.
check("and the second beat lifts it clear of the tile", highest <= -0x50, true)
check("the step type releases the object at the end", npc.teleport, nil)
check("and puts the sprite back on its tile", npc.spriteYOffset, 0)
-- The object never left its cell: OBJECT_SPRITE_Y_OFFSET is a draw offset.
check("the object is still on its own tile", npc.cellY, 5)

-- teleport_to descends onto the tile instead.
local lander = NPC.new("CINNABAR_ISLAND",
  { index = 2, x = 1, y = 1, movement = 1 }, SPRITE)
lander:scriptTeleport("to", 48)
lander:update(nil, nil)
check("the wait beat holds it above the tile",
  lander.spriteYOffset <= -0x60, true)
for _ = 2, 48 do lander:update(nil, nil) end
check("and it ends standing on it", lander.spriteYOffset, 0)

-- ------------------------------------------------------- tilt billboard clip
--
-- groundPoint projects any point at all, so without this an NPC two screens
-- away was pulled back toward the horizon and drawn over the border fill.
Tilt.setLevel(2)
Tilt.update(1)
check("a foot inside the view is on the ground",
  Tilt.onGround(80, 70, 160, 144), true)
check("one far above it is not", Tilt.onGround(80, -400, 160, 144), false)
check("one far below it is not", Tilt.onGround(80, 900, 160, 144), false)
check("one far to the side is not", Tilt.onGround(-500, 70, 160, 144), false)
check("the margin keeps a sprite half off the edge",
  Tilt.onGround(-8, 70, 160, 144, 32), true)
Tilt.reset()

-- ------------------------------------------------------- border-fill dissolve
local owner = {}
local water, trees, alpha = "water", "trees", nil
local previous
previous, alpha = BorderFill.crossfade(owner, water, "CHERRYGROVE_CITY")
check("the first fill of a session appears at once", previous, nil)
check("at full strength", alpha, 1)
previous, alpha = BorderFill.crossfade(owner, water, "CHERRYGROVE_CITY")
check("and standing still does not start a fade", previous, nil)

-- A re-bake of the SAME map (the daytime rollover, the COLOR option, the
-- two-frame cave flicker) swaps the image without dissolving.
previous, alpha = BorderFill.crossfade(owner, "water_night",
  "CHERRYGROVE_CITY")
check("a re-bake of the same map cuts", previous, nil)
check("at full strength", alpha, 1)

-- Crossing into Route 30 dissolves instead of popping.
previous, alpha = BorderFill.crossfade(owner, trees, "ROUTE_30")
check("the boundary fades from the old block", previous, "water_night")
check("starting near transparent", alpha < 0.2, true)
local seen = 1
for _ = 2, BorderFill.CROSSFADE_FRAMES - 1 do
  local from2, a2 = BorderFill.crossfade(owner, trees, "ROUTE_30")
  check("the old block stays under it", from2, "water_night")
  seen = seen + 1
  check("and the new one climbs", a2 > alpha, true)
  alpha = a2
end
check("the dissolve runs for its whole length",
  seen, BorderFill.CROSSFADE_FRAMES - 1)
previous, alpha = BorderFill.crossfade(owner, trees, "ROUTE_30")
check("then it is over", previous, nil)
check("and the new block owns the void", alpha, 1)

-- Forced WATER on two Johto maps shares a fill key, so the dissolve does
-- not run identical water against itself.
BorderFill.setVoidFill("water")
local johtoWater = { id = "CHERRYGROVE_CITY", tileset = "TILESET_JOHTO",
  borderBlock = 0x35 }
local routeTrees = { id = "ROUTE_30", tileset = "TILESET_JOHTO",
  borderBlock = 0x05 }
check("WATER fill keys match across Johto",
  BorderFill.fillKey(johtoWater), BorderFill.fillKey(routeTrees))
local forced = {}
BorderFill.crossfade(forced, "water", BorderFill.fillKey(johtoWater))
local fromForced = BorderFill.crossfade(forced, "water",
  BorderFill.fillKey(routeTrees))
check("so walking Route 30 does not start a fade", fromForced, nil)
BorderFill.setVoidFill("fade")

-- No key at all (an old caller) is the plain single draw.
local bare = {}
previous, alpha = BorderFill.crossfade(bare, trees, nil)
check("a caller with no map key never fades", previous, nil)
check("and draws opaque", alpha, 1)

print(("gen2 field anim: %d checks, %d failures"):format(checks, failures))
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
