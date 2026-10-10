package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("emerald")

local FxRse = require("src.core.game3.field_effects_rse")

local a = FxRse.anim({ { "frame", 0, 2 }, { "loop", 0 }, { "frame", 1, 1 }, { "loop", 2 }, { "frame", 2, 1 }, { "end" } })
local seq = { a.frame }
for _ = 1, 8 do
  FxRse.animTick(a)
  seq[#seq + 1] = a.frame
end
eq(table.concat(seq, ""), "001112222", "AnimCmd loop(0)/loop(2) plays the loop body three times")
check(a.ended, "anim ends on the end command")
local j = FxRse.anim({ { "frame", 0, 1 }, { "frame", 1, 1 }, { "jump", 0 } })
FxRse.animTick(j)
FxRse.animTick(j)
eq(j.frame, 0, "jump command restarts the anim")
check(not j.ended, "jump anims never end")
local sk = FxRse.anim({ { "frame", 0, 4 }, { "frame", 1, 4 }, { "frame", 2, 4 }, { "end" } }, 2)
eq(sk.frame, 2, "SeekSpriteAnim(2) starts at the third command")

eq(FxRse.tireTrackAnim("down", "down"), 1, "tire tracks south to south")
eq(FxRse.tireTrackAnim("down", "left"), 7, "tire tracks south to west curve")
eq(FxRse.tireTrackAnim("left", "up"), 8, "tire tracks west to north curve")
eq(FxRse.tireTrackAnim("right", "right"), 4, "tire tracks east to east")

local MB = require("src.core.game3.mb")
check(FxRse.B.reflective(MB.id("POND_WATER")), "pond water is reflective")
check(FxRse.B.reflective(MB.id("ICE")), "ice is reflective")
check(not FxRse.B.reflective(MB.id("NORMAL")), "normal ground does not reflect")
eq(FxRse.B.bridgeType(MB.id("BRIDGE_OVER_POND_MED_EDGE_1")), 2, "pond bridge med edge is bridge type 2")
eq(FxRse.B.bridgeType(MB.id("BRIDGE_OVER_POND_HIGH")), 3, "pond bridge high is bridge type 3")
eq(FxRse.B.bridgeType(MB.id("NORMAL")), 0, "no bridge")
check(FxRse.B.ripples(MB.id("SOOTOPOLIS_DEEP_WATER")), "Sootopolis deep water ripples")
check(FxRse.B.seaweed(MB.id("SEAWEED_NO_SURFACING")), "seaweed (no surfacing) is seaweed")

FxRse._fc = {
  palTagNone = 0x11FF,
  slotTags = { [0] = 0x1100, [1] = 0x1101, [2] = 0x1103, [6] = 0x1107, [10] = 0x1110, [11] = 0x1111 },
  reflectionMap = { [0] = 1, [1] = 1, [2] = 6, [3] = 7, [4] = 8, [5] = 9, [10] = 11 },
  playerReflections = { [0x1100] = 0x1101, [0x1110] = 0x1111 },
  specialReflections = {},
  gfx = {
    [0] = { paletteTag = 0x1100, reflectionTag = 0x1102, slot = 0 },
    [89] = { paletteTag = 0x1110, reflectionTag = 0x1102, slot = 0 },
    [7] = { paletteTag = 0x1103, reflectionTag = 0x11FF, slot = 2 },
    [8] = { paletteTag = 0x1103, reflectionTag = 0x1107, slot = 2 },
  },
}
eq(FxRse.reflectionPaletteTag(0, 0), 0x1101, "Brendan reflects with BrendanReflection")
eq(FxRse.reflectionPaletteTag(89, 0), 0x1111, "May reflects with MayReflection")
eq(FxRse.reflectionPaletteTag(0, 2), 0x1102, "high bridge loads the bridge reflection palette")
eq(FxRse.reflectionPaletteTag(7, 0), 0x1107, "NPC with no reflection tag keeps the slot default")
eq(FxRse.reflectionPaletteTag(8, 0), 0x1107, "NPC slot 2 reflects in slot 6")
FxRse._fc = nil

local Objects = require("src.core.game3.objects")
eq(Objects.copyDirection("up", "up", "left"), "left", "COPY_PLAYER copies the move when entered facing north")
eq(Objects.copyDirection("down", "up", "left"), "right", "COPY_PLAYER_OPPOSITE mirrors")
eq(Objects.copyDirection("up", "down", "left"), "right", "player entered facing south flips the copy")
eq(Objects.copyDirection("left", "up", "up"), "left", "counterclockwise copy")
eq(Objects.copyDirection("right", "up", "up"), "right", "clockwise copy")
local fx, fy = 0, 0
for i = 1, #Objects.FIG8_X do
  fx, fy = fx + Objects.FIG8_X[i], fy + Objects.FIG8_Y[i]
end
eq(#Objects.FIG8_X, 72, "figure 8 table length")
eq(Objects.JUMP_Y.high[6], -12, "high jump peak")
eq(Objects.JUMP_Y.normal[7], -10, "normal jump peak")

local eo = { cellX = 3, cellY = 4, px = 48, py = 64, targetX = 3, targetY = 4, facing = "down" }
Objects.startJumpArc(eo, 0, {})
eq(eo.stepFrames, 16, "jump in place lasts 16 frames")
check(eo.jumpArc and eo.jumpArc.shadow, "jumping objects draw a shadow")
Objects.startJumpArc(eo, 2, {})
eq(eo.stepFrames, 32, "jump 2 lasts 32 frames")
eq(eo.jumpArc.shift, 1, "jump 2 indexes the arc every other frame")

local RG = require("src.core.game3.rotating_gate")
local vars = {}
RG.setStore(function(id) return vars[id] or 0 end, function(id, v) vars[id] = v end)
RG._p = { map = nil, gates = { { x = 5, y = 5, shape = 0, orientation = 0 }, { x = 9, y = 9, shape = 4, orientation = 1 } }, anims = {} }
RG.setOrientation(0, 0)
RG.setOrientation(1, 3)
eq(RG.getOrientation(0), 0, "gate 0 orientation low byte")
eq(RG.getOrientation(1), 3, "gate 1 orientation high byte")
local free = function() return false end
local wall = function() return true end
check(RG.hasArm(0, 0, 0), "L1 gate has a short north arm at 0 degrees")
check(RG.hasArm(0, 1, 0), "L1 gate has a short east arm at 0 degrees")
check(not RG.hasArm(0, 2, 0), "L1 gate has no south arm")
check(RG.canRotate(0, RG.ROTATE_CLOCKWISE, free), "a gate with room rotates")
check(not RG.canRotate(0, RG.ROTATE_CLOCKWISE, wall), "a wall blocks the swing")
RG.rotate(0, RG.ROTATE_ANTICLOCKWISE)
eq(RG.getOrientation(0), 3, "anticlockwise from 0 wraps to 270")
RG.rotate(0, RG.ROTATE_CLOCKWISE)
eq(RG.getOrientation(0), 0, "clockwise from 270 wraps to 0")
RG._p = nil
RG.setStore(nil, nil)

local RTP = require("src.core.game3.rotating_tile_puzzle")
eq(RTP.rotation(1, 0), "ccw", "arrow tiles rotate objects counterclockwise")
eq(RTP.rotation(0, 3), "ccw", "wrap from right arrow to up arrow is counterclockwise")
eq(RTP.rotation(1, 1), nil, "no rotation on the same tile")
do
  local Objects = require("src.core.game3.objects")
  local saved = Objects._byId
  local shifted, other = { localId = 2, frozen = true }, { localId = 9, frozen = true }
  Objects._byId = { [2] = shifted, [9] = other }
  RTP.init(false)
  RTP._p.objects[1] = { lid = 2, prev = 1 }
  RTP.free()
  check(not shifted.frozen, "freerotatingtilepuzzle unfreezes the shifted objects")
  check(other.frozen, "freerotatingtilepuzzle leaves objects it never moved alone")
  check(RTP._p == nil, "freerotatingtilepuzzle clears the puzzle state")
  Objects._byId = saved
end

local BerryTrees = require("src.core.game3.rse.berry_trees")
BerryTrees.berries = function()
  return { [0] = { name = "CHERI", stageDuration = 3, maxYield = 3, minYield = 2 } }
end
local s = {}
local r = function() return 0 end
BerryTrees.plant(1, 1, BerryTrees.STAGE_PLANTED, true, s, r)
local tree = BerryTrees.peek(s, 1)
eq(tree.minutesUntilNextStage, 180, "stage duration is hours times 60")
check(BerryTrees.water(1, s), "planted tree can be watered")
BerryTrees.timeUpdate(s, 180, r)
eq(tree.stage, BerryTrees.STAGE_SPROUTED, "180 minutes grows one stage")
BerryTrees.timeUpdate(s, 540, r)
eq(tree.stage, BerryTrees.STAGE_BERRIES, "three more stages reach berries")
eq(tree.minutesUntilNextStage, 720, "berries stay four stage lengths")
eq(tree.berryYield, BerryTrees.yieldInternal(3, 2, 1, r), "yield uses the watered stage count")
BerryTrees.timeUpdate(s, 720, r)
eq(tree.stage, BerryTrees.STAGE_SPROUTED, "berries fall and the tree regrows from sprout")
eq(tree.regrowthCount, 1, "regrowth counted")
BerryTrees.timeUpdate(s, 180 * 71, r)
eq(BerryTrees.peek(s, 1).berry, 0, "a very long absence clears the tree")
BerryTrees.plant(2, 1, BerryTrees.STAGE_BERRIES, false, s, r)
BerryTrees.timeUpdate(s, 5000, r)
eq(BerryTrees.peek(s, 2).stage, BerryTrees.STAGE_BERRIES, "unseen trees do not grow")
BerryTrees.berries = nil
package.loaded["src.core.game3.rse.berry_trees"] = nil

local SpecialScene = require("src.core.game3.special_scene_rse")
local rows = SpecialScene.orbSpans(120, 80, 10)
eq(rows[80] and rows[80][1], 110, "orb window left edge at the center row")
eq(rows[80] and rows[80][2], 130, "orb window right edge at the center row")
check(rows[70] ~= nil and rows[91] == nil, "orb window spans the radius")

local ready, frames = false, 0
SpecialScene.startOrb(1, function() ready = true end)
eq(SpecialScene._orb.blue and SpecialScene._orb.cx, 136, "VAR_RESULT 1 is the blue orb centred at x 136")
while not ready and frames < 1000 do
  SpecialScene.step()
  frames = frames + 1
end
eq(frames, 320, "the orb window grows one pixel every two frames to radius 160")
local faded = false
SpecialScene.fadeOutOrb(function() faded = true end)
frames = 0
while not faded and frames < 1000 do
  SpecialScene.step()
  frames = frames + 1
end
check(faded and SpecialScene._orb == nil, "FadeOutOrbEffect blends the orb away and ends the effect")
eq(frames, 2 + 8 * 23, "orb fade-out takes 23 blend steps of 8 frames")

local Task = require("src.core.game3.task")
Task.clear()
FxRse._fc = { mirageTower = { crumblePositions = { { 0, 10, 65 }, { 17, 3, 50 } }, invisibleMetatiles = {} } }
local MirageTower = require("src.core.game3.mirage_tower")
local crumbled = false
MirageTower.ceilingCrumble(function() crumbled = true end)
eq(#MirageTower._crumbles, 4, "each crumble position drops a large and a small piece")
local n = 0
while not crumbled and n < 2000 do
  Task.update(1 / 60)
  n = n + 1
end
check(crumbled and MirageTower._crumbles == nil, "ceiling crumble ends once the pieces land and the shake stops")
FxRse._fc = nil
Task.clear()

local FieldEffects = require("src.core.game3.field_effects")
FieldEffects._manifest = { family = "rse", _byName = {} }
local Constants = require("src.core.game3.constants")
local C = Constants.of("emerald")
local used = {
  "FLDEFF_NPCFLY_OUT", "FLDEFF_USE_STRENGTH", "FLDEFF_USE_SECRET_POWER_TREE", "FLDEFF_USE_SECRET_POWER_SHRUB",
  "FLDEFF_USE_SECRET_POWER_CAVE", "FLDEFF_USE_ROCK_SMASH", "FLDEFF_USE_DIVE", "FLDEFF_USE_CUT_ON_TREE",
  "FLDEFF_PCTURN_ON", "FLDEFF_USE_WATERFALL", "FLDEFF_USE_SURF", "FLDEFF_SAND_PILLAR", "FLDEFF_POKECENTER_HEAL",
  "FLDEFF_HALL_OF_FAME_RECORD", "FLDEFF_DESTROY_DEOXYS_ROCK", "FLDEFF_SPARKLE",
}
for _, name in ipairs(used) do
  check(C:id("field_effects", name) ~= nil, name .. " exists in Emerald")
  check(FieldEffects.handlerFor(name) ~= nil, name .. " has a handler on Emerald")
end
FieldEffects._manifest = nil

local NB = require("src.core.game3.scripting.natives_berry")
local NP = require("src.core.game3.scripting.natives_puzzles_rse")
for _, mod in ipairs({ NB, NP }) do
  for name in pairs(mod.BY_NAME) do
    check(C:special(name) ~= nil, name .. " is an Emerald special")
  end
end

GameVersion.set("firered")
FieldEffects._manifest = false
check(FieldEffects.rse() == nil, "FireRed never loads the RSE field effects")
check(not Objects.isRse(), "FireRed objects are not RSE")
local FieldView = require("src.core.game3.field_view")
eq(FieldView.maxFlashLevel(), 4, "FireRed keeps four flash levels")
eq(FieldView.radiusForLevel(2), 56, "FireRed flash level 2 radius")
FieldEffects._manifest = nil

GameVersion.set(before)
T.finish()
