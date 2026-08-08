-- Cross-mod checkpoint ownership and lifecycle contract through public API only.
-- The Pokemon metadata case models masterwebx/SHINY_POKEMON 1.0.8 at 2141b2e:
-- shiny identity is data on the plain Pokemon record (`dvs` plus `shiny`).

package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness").suite("checkpoint cross-mod compatibility")
local BattleState = require("src.battle.BattleState")
local Fixtures = require("tests.modkit").fixtures
local GameMethods = require("src.core.Game")
local Loader = require("src.mods.Loader")
local Pokemon = require("src.pokemon.Pokemon")
local Runtime = require("src.mods.Runtime")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local Stats = require("src.pokemon.Stats")

local savedEvents, savedHooks = Runtime.events, Runtime.hooks
local oldGetRandomState = love.math.getRandomState
local oldSetRandomState = love.math.setRandomState
local rngState = "cross-mod-rng-A"
love.math.getRandomState = function() return rngState end
love.math.setRandomState = function(state) rngState = state end

local function memfs(files)
  return {
    read = function(path) return files[path] end,
    write = function(path, body) files[path] = body return true end,
    remove = function(path) files[path] = nil return true end,
    createDirectory = function() return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    load = function(path)
      if not files[path] then return nil, "no file: " .. path end
      return load(files[path], path)
    end,
    getDirectoryItems = function(path)
      local prefix, seen, out = path .. "/", {}, {}
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            out[#out + 1] = child
          end
        end
      end
      table.sort(out)
      return out
    end,
  }
end

local function shinyDvs()
  return { attack = 2, defense = 10, speed = 10, special = 10, hp = 0 }
end

local function ordinaryDvs()
  return { attack = 1, defense = 1, speed = 1, special = 1, hp = 15 }
end

local function setPokemonIdentity(data, mon, shiny)
  mon.dvs = shiny and shinyDvs() or ordinaryDvs()
  mon.shiny = shiny and true or false
  mon.stats = Stats.calc(data.pokemon[mon.species], mon.level, mon.dvs, mon.statExp)
  mon.hp = math.min(mon.hp or mon.stats.hp, mon.stats.hp)
end

local function setBattlerIdentity(data, battler, shiny)
  setPokemonIdentity(data, battler.mon, shiny)
  battler.curStats = battler.mon.stats
  battler.shownHP = battler.mon.hp
  battler.shownStatus = battler.mon.status
end

local function makeGame()
  local data = Fixtures.fresh()
  local save = SaveData.newGame()
  save.meta.playthroughId = "cross-mod-playthrough"
  save.party = { Pokemon.new(data, "FIXMON_A", 20) }
  SaveData.validate(save, data)
  save.player.map, save.player.x, save.player.y = "FIX_TOWN", 2, 3
  save.player.facing, save.player.surfing = "left", false
  save.options.modOptions = {}

  local stack = setmetatable({ states = {} }, { __index = StateStack })
  local game
  local ow = {
    map = { id = "FIX_TOWN" },
    player = { cellX = 2, cellY = 3, facing = "left", surfing = false },
    runner = { isRunning = function() return false end },
    parallelRunners = {}, pendingScripts = {}, parallelQueue = {}, scriptMoves = {},
  }
  function ow:captureSave(target)
    target.player.map = self.map.id
    target.player.x, target.player.y = self.player.cellX, self.player.cellY
    target.player.facing = self.player.facing
    target.player.surfing = self.player.surfing and true or false
  end
  function ow:enter(mapId, x, y, facing, opts)
    if game.failNextEnter then
      game.failNextEnter = false
      error("injected cross-mod reconstruction failure")
    end
    self.map = { id = mapId }
    self.player = {
      cellX = x, cellY = y, facing = facing,
      surfing = game.save.player.surfing and true or false,
    }
    self.runner = { isRunning = function() return false end }
    self.parallelRunners, self.pendingScripts = {}, {}
    self.parallelQueue, self.scriptMoves = {}, {}
    game.lastCheckpointEnter = opts
  end
  function ow:restoreBattleContinuation(battle, origin)
    if origin.kind ~= "wild_encounter" or origin.map ~= self.map.id then
      return false
    end
    battle.onFinish = function() end
    return true
  end

  game = setmetatable({
    data = data, save = save, stack = stack, overworld = ow,
  }, { __index = GameMethods })
  stack.states[1] = ow
  return game, ow
end

local function manifest(id)
  return ('{"id":"%s","name":"%s","version":"1.0.0",')
    :format(id, id) .. '"entry":"main.lua","api":2,"profile":"content"}'
end

local files = {
  ["mods/cooperator/manifest.json"] = manifest("cooperator"),
  ["mods/cooperator/main.lua"] = [[
return function(mod)
  local cachedStage = mod.save:get("stage", "unset")
  local restoreCount = 0
  mod.options:define({
    { key = "mode", type = "choice", default = "default",
      choices = { { "A", "A" }, { "B", "B" }, { "C", "C" } } },
  })
  mod.exports.checkpoints = mod.checkpoints
  mod.exports.storage = mod.storage
  mod.exports.setStage = function(stage)
    mod.save:set("stage", stage)
    cachedStage = stage
  end
  mod.exports.stage = function() return mod.save:get("stage", "unset") end
  mod.exports.cachedStage = function() return cachedStage end
  mod.exports.restoreCount = function() return restoreCount end
  mod.events:on("checkpoint.restored", function(ev)
    restoreCount = restoreCount + 1
    cachedStage = mod.save:get("stage", "unset")
    mod.exports.lastRestore = {
      game = ev.game,
      kind = ev.kind,
      top = ev.game.stack:top(),
    }
  end)
end
]],
  ["mods/passive/manifest.json"] = manifest("passive"),
  ["mods/passive/main.lua"] = [[
return function(mod)
  local cachedStage = mod.save:get("stage", "unset")
  mod.exports.setStage = function(stage)
    mod.save:set("stage", stage)
    cachedStage = stage
  end
  mod.exports.stage = function() return mod.save:get("stage", "unset") end
  mod.exports.cachedStage = function() return cachedStage end
end
]],
}

local game, ow = makeGame()
local loader = Loader.new({ fs = memfs(files) })
loader.game, game.mods = game, loader
T.check(loader:load({}) == true, "cooperating fixture mods load")
local cooperator = loader.exports.cooperator
local passive = loader.exports.passive
T.check(type(cooperator) == "table" and type(passive) == "table",
  "fixture exposes only public mod exports")
if type(cooperator) ~= "table" or type(passive) ~= "table" then
  Runtime.events, Runtime.hooks = savedEvents, savedHooks
  love.math.getRandomState = oldGetRandomState
  love.math.setRandomState = oldSetRandomState
  T.finish()
end

cooperator.setStage("A")
passive.setStage("A")
game:adoptSave(game.save, true)
local optionBucket = { mode = "A" }
game.save.options.modOptions.cooperator = optionBucket
loader.modOptions.cooperator = optionBucket
setPokemonIdentity(game.data, game.save.party[1], true)
T.check(Stats.isShiny(game.save.party[1].dvs),
  "condition A uses the real Gen 2 DV shiny predicate")
T.check(cooperator.storage:write(game, "history", { generation = "A" }),
  "independent history condition A writes through mod.storage")

local overworldA, captureCode = cooperator.checkpoints:capture(game)
T.check(overworldA ~= nil, "condition A overworld captures: " .. tostring(captureCode))

-- Mutate canonical progress, both mod.save buckets, independent storage,
-- options, and runtime caches to condition B.
game.save.money = 999999
setPokemonIdentity(game.data, game.save.party[1], false)
cooperator.setStage("B")
passive.setStage("B")
optionBucket.mode = "B"
rngState = "cross-mod-rng-B"
T.check(cooperator.storage:write(game, "history", { generation = "B" }),
  "independent history advances to condition B")

local bad = cooperator.checkpoints:capture(game)
bad.format = 99
local rejected, rejectCode = cooperator.checkpoints:restore(game, bad)
T.check(rejected == false and rejectCode == "unsupported_format",
  "failed checkpoint validation is reported")
T.eq(cooperator.restoreCount(), 0, "failed restore emits no lifecycle event")
T.eq(cooperator.cachedStage(), "B", "failed restore leaves runtime cache at B")
T.eq(cooperator.stage(), "B", "failed restore leaves mod.save at B")

local failedTarget = cooperator.checkpoints:capture(game)
game.failNextEnter = true
local failed, failedCode = cooperator.checkpoints:restore(game, failedTarget)
T.check(failed == false and failedCode == "restore_failed",
  "failed reconstruction rolls back without committing")
T.eq(cooperator.restoreCount(), 0,
  "failed reconstruction and successful rollback emit no lifecycle event")
T.eq(cooperator.cachedStage(), "B",
  "failed reconstruction leaves cooperating runtime cache at B")
T.eq(cooperator.stage(), "B",
  "failed reconstruction rollback leaves mod.save at B")

local restored, restoreCode, restoreMessage =
  cooperator.checkpoints:restore(game, overworldA)
T.check(restored == true,
  "condition A overworld restores: " .. tostring(restoreCode or restoreMessage))
T.eq(game.save.money, overworldA.save.money, "core game progress rewinds to A")
T.eq(game.save.party[1].shiny, true,
  "shiny marker rewinds with its Pokemon record")
T.check(Stats.isShiny(game.save.party[1].dvs),
  "authoritative shiny DVs rewind with the Pokemon record")
T.eq(cooperator.stage(), "A", "cooperating mod.save progress rewinds to A")
T.eq(passive.stage(), "A", "all mods' mod.save progress rewinds generically")
T.eq(passive.cachedStage(), "B",
  "runtime-only state is not serialized for a non-cooperating mod")
T.eq(cooperator.cachedStage(), "A",
  "checkpoint lifecycle lets a cooperating mod rebuild its runtime cache")
T.same(cooperator.storage:read(game, "history"), { generation = "B" },
  "independent mod.storage history does not rewind")
T.eq(cooperator.restoreCount(), 1, "successful overworld restore emits once")
local overworldEvent = cooperator.lastRestore or {}
T.eq(overworldEvent.game, game, "restore event carries the final live game")
T.eq(overworldEvent.kind, "overworld", "restore event identifies overworld")
T.eq(overworldEvent.top, ow,
  "restore event runs after the reconstructed overworld is installed")
T.eq(loader.modOptions.cooperator.mode, "B",
  "per-mod global options stay at condition B")
T.eq(game.save.options.modOptions.cooperator.mode, "B",
  "checkpoint reattaches the current global options table")

-- Repeat the same ownership rules at a supported ordinary wild battle safe point.
cooperator.setStage("battle-A")
passive.setStage("battle-A")
setPokemonIdentity(game.data, game.save.party[1], true)
local battle = BattleState.newWild(game, "FIXMON_B", 12)
battle.phase, battle.queue = "menu", {}
battle.checkpointOrigin = { kind = "wild_encounter", map = "FIX_TOWN" }
battle.musicKind = battle:computeMusicKind()
battle.onFinish = function() end
setBattlerIdentity(game.data, battle.enemy, true)
game.stack.states[2] = battle
rngState = "cross-mod-battle-rng-A"

local battleA, battleCaptureCode = cooperator.checkpoints:capture(game)
T.check(battleA and battleA.kind == "battle",
  "condition A battle captures: " .. tostring(battleCaptureCode))
if battleA then
  setBattlerIdentity(game.data, battle.player, false)
  setBattlerIdentity(game.data, battle.enemy, false)
  cooperator.setStage("battle-B")
  passive.setStage("battle-B")
  optionBucket.mode = "C"
  rngState = "cross-mod-battle-rng-B"
  T.check(cooperator.storage:write(game, "history", { generation = "battle-B" }),
    "independent history advances during battle")

  local battleRestored, battleRestoreCode, battleRestoreMessage =
    cooperator.checkpoints:restore(game, battleA)
  T.check(battleRestored == true,
    "condition A battle restores: "
      .. tostring(battleRestoreCode or battleRestoreMessage))
  local restoredBattle = game.stack:top()
  T.eq(restoredBattle.player.mon, game.save.party[1],
    "restored player battler rebinds to canonical party Pokemon")
  T.eq(restoredBattle.player.mon.shiny, true,
    "player shiny metadata rewinds through battle reconstruction")
  T.check(Stats.isShiny(restoredBattle.player.mon.dvs),
    "player shiny DVs rewind through battle reconstruction")
  T.eq(restoredBattle.enemy.mon.shiny, true,
    "enemy shiny metadata rewinds with copied battle Pokemon")
  T.check(Stats.isShiny(restoredBattle.enemy.mon.dvs),
    "enemy shiny DVs rewind through battle reconstruction")
  T.eq(cooperator.stage(), "battle-A", "battle restore rewinds mod.save progress")
  T.eq(cooperator.cachedStage(), "battle-A",
    "battle restore event rebuilds cooperating runtime cache")
  T.eq(passive.cachedStage(), "battle-B",
    "battle restore still does not serialize arbitrary mod runtime")
  T.same(cooperator.storage:read(game, "history"), { generation = "battle-B" },
    "battle restore leaves independent history current")
  T.eq(loader.modOptions.cooperator.mode, "C",
    "battle restore leaves per-mod global options current")
  T.eq(cooperator.restoreCount(), 2, "successful battle restore emits once")
  local battleEvent = cooperator.lastRestore or {}
  T.eq(battleEvent.kind, "battle", "restore event identifies battle")
  T.eq(battleEvent.top, restoredBattle,
    "battle restore event runs after final battle installation")
  T.same(cooperator.checkpoints:capture(game), battleA,
    "combined battle and mod progress is a differential roundtrip")
end

Runtime.events, Runtime.hooks = savedEvents, savedHooks
Runtime.currentMod = nil
love.math.getRandomState = oldGetRandomState
love.math.setRandomState = oldSetRandomState
_G.CROSS_MOD_CHECKPOINT = nil

T.finish()
