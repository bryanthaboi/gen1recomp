-- Validation and fail-closed behavior for battle.field_residual descriptors.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.modkit")
local BattleState = require("src.battle.BattleState")
local Checkpoint = require("src.core.Checkpoint")
local Events = require("src.mods.Events")
local GameMethods = require("src.core.Game")
local Hooks = require("src.mods.Hooks")
local Pokemon = require("src.pokemon.Pokemon")
local Runtime = require("src.mods.Runtime")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local TypeChart = require("src.battle.TypeChart")

local data = T.fixtures.fresh()
TypeChart.load(data)

local function newBattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(data, "FIXMON_A", 30) }
  local game = {
    data = data,
    save = save,
    stack = { top = function() return nil end, push = function() end },
  }
  local battle = BattleState.newWild(game, "FIXMON_C", 30)
  battle.phase, battle.queue = "menu", {}
  return battle
end

local savedEvents, savedHooks, savedErrors = Runtime.events, Runtime.hooks,
  Runtime.errors
local hooks = Hooks.new()
Runtime.install(savedEvents, hooks, {})

local battle = newBattle()
local playerHp, enemyHp = battle.player.mon.hp, battle.enemy.mon.hp
local playerType = battle.player.curTypes[1]
local cyclic = { label = "cycle-data" }
cyclic.self = cyclic
local metatableData = setmetatable({ label = "plain-data" }, {
  __index = { hidden = "metatable-data" },
})
battle.field.weather = {
  id = "probe", turns = 3,
  callback = function() end,
  handle = io.stdout,
  worker = coroutine.create(function() end),
  cyclic = cyclic,
  metatableData = metatableData,
}
battle.field.tokens[1] = { id = "nested", turns = 2,
  state = { intensity = 4 } }
battle:enter()
hooks:wrap("battle.field_residual", function(next, context)
  local vanilla = next(context)
  T.same(vanilla, {}, "the vanilla contribution is an empty descriptor list")
  context.battlers.player.hp = 0
  context.battlers.player.types[1] = "MUTATED"
  T.eq(context.field.sides, nil,
    "the field view has the checkpoint shape and no live side graph")
  T.eq(context.field.weather.callback, nil,
    "the field view omits executable values")
  T.eq(context.field.weather.handle, nil,
    "the field view omits userdata")
  T.eq(context.field.weather.worker, nil,
    "the field view omits threads")
  T.eq(context.field.weather.cyclic.label, "cycle-data",
    "the field view retains scalar data around a cycle")
  T.eq(context.field.weather.cyclic.self, nil,
    "the field view omits cyclic edges")
  T.eq(getmetatable(context.field.weather.metatableData), nil,
    "the field view carries no metatable")
  T.eq(context.field.weather.metatableData.label, "plain-data",
    "the field view retains raw data from a metatable-bearing table")
  T.eq(context.field.weather.metatableData.hidden, nil,
    "the field view does not expose metatable-provided values")
  context.field.weather.turns = 0
  context.field.tokens[1].state.intensity = 99
  return {
    false,
    { side = "unknown", amount = 20, message = "invalid side" },
    { side = "player", amount = "3", message = "numeric string" },
    { side = "player", amount = 0, message = "zero" },
    { side = "player", amount = -2, message = "negative" },
    { side = "player", amount = 1.5, message = "fractional" },
    { side = "player", amount = "not a number", message = "bad amount" },
    { side = "player", amount = 0 / 0, message = "not finite" },
    { side = "player", amount = math.huge, message = "non-finite" },
    { side = "player", amount = 2, message = function() end },
    { side = "enemy", amount = 3 },
  }
end, 0, "validation_probe")

battle:applyFieldResiduals()
T.eq(battle.player.mon.hp, playerHp,
  "a descriptor with a non-string message fails closed")
T.eq(battle.enemy.mon.hp, enemyHp - 3,
  "a valid descriptor may omit its message")
T.eq(battle.player.curTypes[1], playerType,
  "mutating the detached type view cannot mutate the live battler")
T.check(battle.player.mon.hp ~= 0,
  "mutating detached HP cannot replace engine damage authority")
T.eq(battle.field.weather.turns, 3,
  "mutating the detached weather view cannot mutate live field state")
T.eq(battle.field.tokens[1].state.intensity, 4,
  "mutating nested detached token state cannot mutate live field state")

local guarded = newBattle()
local fieldReads, runtimeCalls = 0, 0
guarded.field = setmetatable({}, { __index = function()
  fieldReads = fieldReads + 1
  return nil
end })
local realRuntimeCall = Runtime.call
Runtime.call = function(...)
  runtimeCalls = runtimeCalls + 1
  return realRuntimeCall(...)
end
Runtime.install(savedEvents, Hooks.new(), {})
guarded:applyFieldResiduals()
Runtime.call = realRuntimeCall
T.eq(runtimeCalls, 0,
  "a disabled field hook never enters Runtime.call")
T.eq(fieldReads, 0,
  "a disabled field hook does not construct its field context")

local nilBattle = newBattle()
local nilHp = nilBattle.player.mon.hp
local nilHooks = Hooks.new()
Runtime.install(savedEvents, nilHooks, {})
nilHooks:wrap("battle.field_residual", function() return nil end,
  0, "nil_probe")
nilBattle:applyFieldResiduals()
T.eq(nilBattle.player.mon.hp, nilHp,
  "a non-table hook result fails closed")

local settled = newBattle()
local settledCalls = 0
local settledHooks = Hooks.new()
Runtime.install(savedEvents, settledHooks, {})
settledHooks:wrap("battle.field_residual", function(next, context)
  settledCalls = settledCalls + 1
  return next(context)
end, 0, "settled_probe")
settled.result = "win"
settled:endOfTurn()
T.eq(settledCalls, 0,
  "a settled battle never invokes field residual policy")

local function drainQueue(battle)
  local rows, guard = {}, 0
  while battle.queue[1] and guard < 1000 do
    guard = guard + 1
    local row = table.remove(battle.queue, 1)
    rows[#rows + 1] = row
    if row.fn then
      battle.nextInsert = 0
      row.fn()
    end
  end
  T.check(guard < 1000, "the simultaneous-faint queue completes")
  return rows
end

local function simultaneousTerminal(order)
  local save = SaveData.newGame()
  save.party = { Pokemon.new(data, "FIXMON_A", 30) }
  local game = {
    data = data,
    save = save,
    stack = { top = function() return nil end, push = function() end },
  }
  local double = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
  double.phase, double.queue = "menu", {}
  local originalEnemy, originalEnemyIndex = double.enemy, double.enemyIndex
  local startingExp = double.player.mon.exp
  local events, doubleHooks = Events.new(), Hooks.new()
  local awardCalls, expEvents, switches = 0, 0, 0
  events:on("battle.exp_gained", function() expEvents = expEvents + 1 end,
    0, "double_probe")
  events:on("battle.battler_switched", function() switches = switches + 1 end,
    0, "double_probe")
  Runtime.install(events, doubleHooks, {})
  doubleHooks:wrap("battle.field_residual", function(next, context)
    local rows = next(context)
    for _, side in ipairs(order) do
      rows[#rows + 1] = {
        side = side,
        amount = context.battlers[side].hp,
      }
    end
    return rows
  end, 0, "double_probe")
  doubleHooks:wrap("battle.exp_award", function(next, context)
    awardCalls = awardCalls + 1
    return next(context)
  end, 0, "double_probe")
  double:endOfTurn()
  local queued = drainQueue(double)
  T.eq(double.player.mon.hp, 0,
    "simultaneous residuals settle the player side")
  T.eq(double.enemy.mon.hp, 0,
    "simultaneous residuals settle the enemy side")
  T.eq(double.result, "lose",
    "a simultaneous terminal residual resolves as player blackout")
  T.eq(double.afterQueue, "finish",
    "the completed simultaneous-faint queue closes the battle")
  T.eq(double.player.faintQueued, true,
    "the terminal hook batch queues player faint authority")
  T.eq(double.enemy.faintQueued, nil,
    "the terminal hook batch suppresses only its enemy faint authority")
  T.eq(double.player.mon.exp, startingExp,
    "a blackout does not award contradictory enemy-faint EXP")
  T.eq(awardCalls, 0,
    "a blackout never enters the enemy EXP-award policy")
  T.eq(expEvents, 0,
    "a blackout emits no contradictory EXP event")
  T.eq(switches, 0,
    "a blackout does not send the trainer's reserve into battle")
  T.eq(double.enemyIndex, originalEnemyIndex,
    "a blackout leaves the enemy roster position unchanged")
  T.check(double.enemy == originalEnemy,
    "a blackout queues no contradictory enemy replacement")
  for _, row in ipairs(queued) do
    T.eq(row.ui, nil,
      "a simultaneous terminal residual queues no replacement UI")
  end
end

simultaneousTerminal({ "player", "enemy" })
simultaneousTerminal({ "enemy", "player" })

local timing = newBattle()
local timingOrder = {}
timing.ruleset = require("src.battle.rulesets.modern_clean")
timing.player.mon.status = "PSN"
timing.field.tokens[1] = { id = "expires", turns = 1,
  onExpire = function() timingOrder[#timingOrder + 1] = "token_expired" end }
local timingEvents, timingHooks = Events.new(), Hooks.new()
timingEvents:on("battle.turn_ended", function()
  timingOrder[#timingOrder + 1] = "turn_ended"
end, 0, "timing_probe")
Runtime.install(timingEvents, timingHooks, {})
local preStatusHp = timing.player.mon.hp
timingHooks:wrap("battle.field_residual", function(next, context)
  timingOrder[#timingOrder + 1] = "field_residual"
  T.check(context.battlers.player.hp < preStatusHp,
    "the hook snapshot observes completed vanilla status residuals")
  return next(context)
end, 0, "timing_probe")
timing:endOfTurn()
T.same(timingOrder,
  { "field_residual", "token_expired", "turn_ended" },
  "the hook runs before token expiry and battle.turn_ended")

local oldGetState, oldSetState = love.math.getRandomState,
  love.math.setRandomState
local checkpointRng = "field-residual-rng"
love.math.getRandomState = function() return checkpointRng end
love.math.setRandomState = function(state) checkpointRng = state end

local function checkpointBattle()
  local save = SaveData.newGame()
  save.meta.playthroughId = "field-residual-checkpoint"
  save.party = { Pokemon.new(data, "FIXMON_A", 30) }
  SaveData.validate(save, data)
  save.player.map, save.player.x, save.player.y = "FIX_TOWN", 2, 3
  save.player.facing, save.player.surfing = "left", false
  local stack = setmetatable({ states = {} }, { __index = StateStack })
  local overworld = {
    map = { id = "FIX_TOWN" },
    player = { cellX = 2, cellY = 3, facing = "left", surfing = false },
    runner = { isRunning = function() return false end },
    parallelRunners = {}, pendingScripts = {}, parallelQueue = {},
    scriptMoves = {},
  }
  function overworld:captureSave(target)
    target.player.map = self.map.id
    target.player.x, target.player.y = self.player.cellX, self.player.cellY
    target.player.facing = self.player.facing
    target.player.surfing = self.player.surfing and true or false
  end
  function overworld:restoreBattleContinuation(restored, origin)
    restored.onFinish = function() end
    return origin.kind == "wild_encounter" and origin.map == self.map.id
  end
  local game = setmetatable({ data = data, save = save, stack = stack,
    overworld = overworld }, { __index = GameMethods })
  stack.states[1] = overworld
  local battle = BattleState.newWild(game, "FIXMON_C", 30)
  battle.phase, battle.queue = "menu", {}
  battle.checkpointOrigin = { kind = "wild_encounter", map = "FIX_TOWN" }
  battle.musicKind = battle:computeMusicKind()
  battle.onFinish = function() end
  battle.field.weather = { id = "checkpoint-weather", turns = 5 }
  stack.states[2] = battle
  return game, battle
end

local checkpointGame = checkpointBattle()
local checkpointHooks, restoredCalls = Hooks.new(), 0
Runtime.install(Events.new(), checkpointHooks, {})
checkpointHooks:wrap("battle.field_residual", function(next, context)
  restoredCalls = restoredCalls + 1
  T.same(context.field.weather,
    { id = "checkpoint-weather", turns = 5 },
    "the enabled hook observes checkpointed field state after restore")
  return next(context)
end, 0, "checkpoint_probe")
local snapshot, captureCode = Checkpoint.capture(checkpointGame)
T.check(snapshot ~= nil,
  "an enabled process-local hook does not enter the checkpoint: "
    .. tostring(captureCode))
if snapshot then
  checkpointGame.stack:top().field.weather.turns = 1
  local restored, restoreCode, restoreMessage =
    Checkpoint.restore(checkpointGame, snapshot)
  T.check(restored == true,
    "field state reconstructs while the hook remains enabled: "
      .. tostring(restoreCode or restoreMessage))
  if restored then checkpointGame.stack:top():applyFieldResiduals() end
  if restored then
    T.same(Checkpoint.capture(checkpointGame), snapshot,
      "enabled-hook field state completes capture/restore/capture round-trip")
  end
end
T.eq(restoredCalls, 1,
  "the process-local hook still runs after checkpoint reconstruction")
love.math.getRandomState, love.math.setRandomState = oldGetState, oldSetState

Runtime.install(savedEvents, savedHooks, savedErrors)
T.finish("battle.field_residual validation")
