package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local MB = require("src.core.game3.mb")
local Collision = require("src.core.game3.collision")
local InteractionScripts = require("src.core.game3.scripting.interaction_scripts")
local session = { version = "emerald", map = "SURF_BRIDGE_TEST" }
local stops = 0
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
package.loaded["src.core.game3.audio"] = { stopSurfMusic = function() stops = stops + 1 end }
package.loaded["src.core.game3.bike"] = { rse = function() return nil end }
package.loaded["src.core.game3.field_effects"] = {
  leaveTallGrass = function() end,
  tallGrassAt = function() end,
}
package.loaded["src.core.game3.field"] = { locked = false }
package.loaded["src.core.game3.objects"] = { hasMap = function() return false end }
local Player = require("src.core.game3.player")
local game = { save = { position = {} } }

local function setup(version, cells, surfing, elevation)
  GameVersion.set(version)
  session.version = version
  local layout = { width = #cells, height = 1, pair = "surf_bridge_test" }
  function layout:collAt(x) return cells[x + 1][1] end
  function layout:elevAt(x) return cells[x + 1][2] end
  function layout:midAt(x) return x end
  function layout:collArray()
    local coll = {}
    for i, cell in ipairs(cells) do coll[i] = cell[1] end
    return coll
  end
  local behaviors = {}
  for i, cell in ipairs(cells) do behaviors[i - 1] = cell[3] or MB.NORMAL end
  InteractionScripts.behaviors[layout.pair] = behaviors
  Collision.bindMap(game, session.map, { midLayout = layout, pair = layout.pair, warps = {} })
  game.world = nil
  Player.reset(0, 0, "right")
  Player.surfing = surfing == true
  Player.underwater = false
  Player.elevation = elevation or cells[1][2]
  Player.currentElevation = Player.elevation
  stops = 0
end

local function settle()
  Player._onStepDone = function() end
  for _ = 1, 40 do
    if not Player.moving then break end
    Player.tick(game)
  end
  check(not Player.moving, "step completes")
end

local function step(label)
  eq(Player.tryMove("right", game, false), "step", label .. " accepted")
  settle()
end

local water = { 0x29, 1, MB.OCEAN_WATER }
local bridge15 = { 0, 15, MB.BRIDGE_OVER_OCEAN }
local bridge1 = { 0, 1, MB.BRIDGE_OVER_OCEAN }
local shore = { 0, 3, MB.NORMAL }

-- pokeemerald/src/field_player_avatar.c:693
setup("emerald", { water, bridge15, bridge1, water, shore }, true, 1)
step("water to multilevel bridge")
check(Player.surfing and not Player.dismounting, "retain_surf_under_bridge")
eq(Player.currentElevation, 1, "multilevel bridge keeps lower layer")
check(not Collision.isWater(1, 0), "bridge collision stays land for upper deck")
step("multilevel bridge to lower bridge")
check(Player.surfing, "retain_surf_on_elevation1_bridge")
step("bridge to water")
check(Player.surfing and Player.cellX == 3, "exit_bridge_to_water")
eq(stops, 0, "bridge traversal keeps Surf music")
eq(Player.tryMove("right", game, false), "step", "elevation3 shore accepted")
check(Player.surfing and Player.dismounting and Player.jumping, "shore starts Surf dismount hop")
eq(stops, 1, "shore stops Surf music once")
settle()
check(not Player.surfing and not Player.dismounting, "shore finishes on foot")
eq(Player.currentElevation, 3, "shore reaches default elevation")

setup("emerald", { { 0, 4 }, bridge15, { 0, 4 } }, false, 4)
step("upper deck to multilevel bridge")
check(not Player.surfing and not Player.jumping, "upper deck remains walking")
eq(Player.currentElevation, 4, "upper deck keeps upper layer")
step("multilevel bridge to upper deck")
check(not Player.surfing, "upper deck never enables Surf")

setup("emerald", { water, { 0x07, 15, MB.BRIDGE_OVER_OCEAN } }, true, 1)
eq(Player.tryMove("right", game, false), "blocked", "bridge support blocks Surf")
check(Player.surfing and not Player.moving and Player.cellX == 0, "support bump preserves Surf")

setup("emerald", { water, { 0, 4 } }, true, 1)
local result, why = Player.tryMove("right", game, false)
eq(result, "blocked", "wrong elevation land rejects dismount")
eq(why, "elevation", "wrong elevation collision reason")
check(Player.surfing, "wrong elevation bump preserves Surf")

setup("emerald", { water, shore }, true, 1)
game.world = { npcs = { { cellX = 1, cellY = 0, passable = false } } }
result, why = Player.tryMove("right", game, false)
eq(result, "blocked", "occupied shore rejects dismount")
eq(why, "entity", "occupied shore collision reason")
eq(stops, 0, "occupied shore keeps Surf music")

-- pokeemerald/src/field_player_avatar.c:443
setup("emerald", { water, bridge15 }, true, 1)
check(Player.forcedStep("right", 8), "forced bridge step accepted")
check(not Player.dismounting and not Player.jumping, "forced bridge step keeps Surf movement")
eq(Player.stepFrames, 8, "forced bridge retains requested speed")
settle()
check(Player.surfing, "forced_step_retains_surf_under_bridge")
eq(stops, 0, "forced bridge keeps Surf music")

setup("emerald", { water, shore }, true, 1)
check(Player.forcedStep("right", 8), "forced shore step accepted")
check(Player.dismounting and Player.jumping, "forced shore starts dismount")
eq(Player.stepFrames, 32, "forced shore retains dismount timing")
settle()
check(not Player.surfing, "forced shore finishes on foot")

setup("emerald", { water, bridge15 }, true, 1)
check(Player.forceStep("right"), "step without dismount setup accepted")
check(not Player.dismounting, "forceStep has no dismount setup")
settle()
check(Player.surfing, "finish_step_retains_surf_without_dismount")

for _, version in ipairs({ "firered", "leafgreen" }) do
  -- pokefirered/src/field_player_avatar.c:568
  setup(version, { water, { 0, 1, MB.PUDDLE }, { 0, 1, MB.SHALLOW_WATER }, water, shore }, true, 1)
  for i = 1, 3 do
    step(version .. " shallow step " .. i)
    check(Player.surfing and not Player.dismounting, version .. " shallow water retains Surf")
  end
  step(version .. " shore")
  check(not Player.surfing and Player.currentElevation == 3, version .. " shore dismount preserved")
  eq(stops, 1, version .. " shore stops Surf music once")
end

GameVersion.set("firered")
T.finish("game3_surf_bridge_bug2617_test")
