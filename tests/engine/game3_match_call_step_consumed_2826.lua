-- pokeemerald/src/field_control_avatar.c:159
-- pokeemerald/src/field_control_avatar.c:483 TryStartStepBasedScript
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")
local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")

local noop = function() end
local W, H = 16, 16
local grid = {}

local rolls, battles = 0, 0
package.loaded["src.core.game3.encounters"] = {
  onStep = function() rolls = rolls + 1 return { species = 72, level = 15 } end,
  noteGrass = noop,
}
package.loaded["src.core.game3.battle_bridge"] = {
  startWild = function() battles = battles + 1 return true end,
}

local consume = false
local stepCalls = 0
local stubSteps = {
  onStepTaken = function() stepCalls = stepCalls + 1 return consume end,
  busy = function() return false end,
}

local realIsGrass = Collision.isGrass
local function setup(version)
  GameVersion.set(version)
  for i = 1, W * H do grid[i] = 0x00 end
  Collision._grid, Collision._widthCells, Collision._heightCells = grid, W, H
  Collision.isGrass = function() return true end
  Player.reset(5, 8, "up")
  Player.biking = false
  Player.surfing = false
  Player.canDash = function() return false end
  rolls, battles, stepCalls = 0, 0, 0
end

local function input(held)
  return {
    isDown = function(_, k) return k == held end,
    wasPressed = function() return false end,
  }
end

local function oneStep()
  local startY = Player.cellY
  for _ = 1, 40 do
    Player.update(nil, input(Player.moving and nil or "up"))
    if Player.cellY ~= startY then return true end
  end
  return false
end

local spot, spotted, stepsAtSpot = false, 0, nil
local stubSight = {
  check = function()
    if not spot then return false end
    spot = false
    spotted = spotted + 1
    stepsAtSpot = stepCalls
    return true
  end,
}

local function oneSpottedStep()
  local startY = Player.cellY
  for _ = 1, 40 do
    Player.update(nil, input(Player.moving and nil or "up"))
    if Player.moving then spot = true end
    if Player.cellY ~= startY then return true end
  end
  return false
end

local savedSteps = package.loaded["src.core.game3.step_events"]
local savedSight = package.loaded["src.core.game3.trainer_sight"]
package.loaded["src.core.game3.step_events"] = stubSteps
package.loaded["src.core.game3.trainer_sight"] = stubSight
for _, v in ipairs({ "emerald", "ruby", "firered" }) do
  setup(v)
  consume = true
  check(oneStep(), v .. " consumed step completes")
  eq(stepCalls, 1, v .. " step events ran once")
  eq(rolls, 0, v .. " no wild roll on a step a step-count script took")
  eq(battles, 0, v .. " no wild battle on a step a step-count script took")

  setup(v)
  consume = false
  check(oneStep(), v .. " plain step completes")
  eq(rolls, 1, v .. " plain grass step rolls the encounter")
  eq(battles, 1, v .. " plain grass step can start a battle")

  setup(v)
  consume = true
  spotted, stepsAtSpot = 0, nil
  check(oneSpottedStep(), v .. " spotted step completes")
  eq(spotted, 1, v .. " a trainer spots the player on the landing step")
  eq(stepsAtSpot, 0, v .. " the trainer check runs before the step-count scripts")
  eq(stepCalls, 0, v .. " no step-count script on a step a trainer took")
  eq(rolls, 0, v .. " no wild roll on a step a trainer took")
end
package.loaded["src.core.game3.step_events"] = savedSteps
package.loaded["src.core.game3.trainer_sight"] = savedSight
Collision.isGrass = realIsGrass

local family = "rse"
local mcFires = false
local mcCalls = 0
local saved = {}
local function stub(name, mod)
  saved[name] = package.loaded[name] or false
  package.loaded[name] = mod
end
stub("src.core.game3.pokemon", {
  FRIENDSHIP_EVENT_WALKING = 0,
  FRIENDSHIP_EVENT_FAINT_OUTSIDE_BATTLE = 1,
  adjustFriendship = noop,
  currentMapSec = function() return 0 end,
  displayMonName = function(mon) return mon.name or "MON" end,
})
stub("src.core.game3.rom_text", { box = function(key) return key end })
local vars = {}
stub("src.core.game3.field_semantics", {
  var = function(_, name) return name end,
  getVar = function(_, name) return vars[name] or 0 end,
  setVar = function(_, name, v) vars[name] = v end,
})
stub("src.core.game3.field_modules", { enabled = function() return false end })
stub("src.core.game3.profile", {
  family = function() return family end,
  forSession = function() return { field = {}, id = "emerald" } end,
})
stub("src.core.game3.capabilities", { gate = function(_, k) return k == "match_call" and family == "rse" end })
stub("src.core.game3.rs.rematch", { enabled = function() return false end })
stub("src.core.game3.rse.match_call", {
  incrementRematchStepCounter = noop,
  tryStepCountScripts = function() return false end,
  tryStartMatchCall = function()
    mcCalls = mcCalls + 1
    if mcFires then
      package.loaded["src.core.game3.step_events"].queueEvent({ type = "match_call", run = noop })
    end
    return mcFires
  end,
})
stub("src.core.game3.faraway_island", { updateStepCounter = noop })
stub("src.core.game3.mystery_gift", { incrementNewsStepCounter = noop })
stub("src.core.game3.rse.init", { call = noop, isRse = function() return family == "rse" end })
stub("src.core.game3.forced_movement", {
  isForced = function() return false end,
  isForcedMovementTile = function() return false end,
})
stub("src.core.game3.map", { currentDef = function() return { mapType = 3 } end })
stub("src.core.game3.special_scene_rse", { countSSTidalStep = function() return false end })
stub("src.core.game3.safari", { takeStep = function() return false end })
stub("src.core.game3.daycare", { step = function() return nil end })
stub("src.core.game3.braille_field", { shouldDoRegicePuzzle = function() return false end })
stub("src.core.game3.field", {})
package.loaded["src.core.game3.step_events"] = nil
local StepEvents = require("src.core.game3.step_events")

local function session()
  return { vars = {}, party = { { name = "TORCHIC", hp = 30 } } }
end

StepEvents.flush()
mcFires = true
vars.repelSteps = 5
eq(StepEvents.onStepTaken(session(), {}), true, "match call step reports the step as taken")
check(StepEvents.busy(), "match call window queued")
eq(vars.repelSteps, 5, "repel counter skipped on a step a match call took")
StepEvents.flush()

mcFires = false
eq(StepEvents.onStepTaken(session(), {}), false, "quiet step is not consumed")
eq(vars.repelSteps, 4, "repel counter runs on a quiet step")

vars.repelSteps = 1
eq(StepEvents.onStepTaken(session(), {}), true, "repel wearing off takes the step")
StepEvents.flush()

family = "frlg"
mcCalls = 0
eq(StepEvents.onStepTaken(session(), {}), false, "frlg quiet step is not consumed")
eq(mcCalls, 0, "frlg never asks for a match call")

local poisoned = session()
poisoned.party[1].hp, poisoned.party[1].status = 1, "PSN"
family = "rse"
mcFires = true
mcCalls = 0
poisoned.vars.poisonSteps = 3
eq(StepEvents.onStepTaken(poisoned, {}), true, "poison faint takes the step")
eq(mcCalls, 0, "no match call after a poison faint")
StepEvents.flush()

for name, mod in pairs(saved) do
  package.loaded[name] = mod or nil
end

T.finish("game3_match_call_step_consumed_2826")
