-- Semantic, data-only capture for settled single-player battle checkpoints.
-- Reconstruction lives here too; public mods only see the opaque checkpoint
-- facade in Loader.

local BattleCheckpoint = {}
local BattleState = require("src.battle.BattleState")
local ScriptRunner = require("src.script.ScriptRunner")
local BUILTIN_RULESETS = {
  gen1_faithful = require("src.battle.rulesets.gen1_faithful"),
  modern_clean = require("src.battle.rulesets.modern_clean"),
}

local function rulesets(game)
  return game.data.rulesets or BUILTIN_RULESETS
end

local function rulesetId(game, record)
  for id, candidate in pairs(rulesets(game)) do
    if candidate == record then return id end
  end
end

local BATTLER_FIELDS = {
  "shownHP", "shownStatus", "stages", "curStats", "curTypes", "curMoves",
  "sleepTurns", "confusedTurns", "disabledSlot", "disabledTurns",
  "toxicCounter", "substituteHP", "bideDamage", "bideTurns", "boundTurns",
  "chargeReady", "invulnerable", "mustRecharge",
  "thrashTurns", "thrashAnnounced", "focusEnergy", "leechSeeded",
  "lightScreen", "reflect", "mist", "xAccuracy", "lastMove", "flinched",
  "skipMove", "hazeStatReset", "badgeExtraBoosts", "drainFloor", "drainHold", "trappingTurns",
  "trapMove", "trapDamage", "fainted",
  "aiLayer2",
}

local MOVE_REFERENCE_FIELDS = {
  charging = "chargingSlot",
  thrashMove = "thrashMoveSlot",
  rageMove = "rageMoveSlot",
}

local BATTLE_FIELDS = {
  "oppClass", "partyIndex", "enemyIndex", "turnCount", "menuIndex",
  "moveIndex", "moveSwapIndex", "aiUses", "runAttempts", "payDay",
  "sideToxic", "isGymLeader", "musicKind", "lastBall", "lockedBall",
  "lowHealthAlarmDisabled", "lowHealthAlarmOn", "victoryMusicPlayed",
  "endBattleText",
  "playerPartyIndices",
}

local function partyIndex(party, mon)
  for index, candidate in ipairs(party or {}) do
    if candidate == mon then return index end
  end
end

local function indexSet(set, party)
  local out = {}
  for mon, present in pairs(set or {}) do
    if present then
      local index = partyIndex(party, mon)
      if index then out[#out + 1] = index end
    end
  end
  table.sort(out)
  return out
end

local function captureBattler(battler, index, copy)
  local out = {
    index = index,
    curStatsFromMon = battler.curStats == battler.mon.stats,
    curTypesFromDefinition = battler.curTypes == battler.def.types,
    curMovesFromMon = battler.curMoves == battler.mon.moves,
  }
  for _, field in ipairs(BATTLER_FIELDS) do
    if battler[field] ~= nil then out[field] = battler[field] end
  end
  for field, slotField in pairs(MOVE_REFERENCE_FIELDS) do
    local reference = battler[field]
    if reference ~= nil then
      for slot, move in ipairs(battler.curMoves or {}) do
        if move == reference then out[slotField] = slot break end
      end
      if out[slotField] == nil then return nil end
    end
  end
  return copy(out)
end

local function integer(value, min, max)
  return type(value) == "number" and value % 1 == 0
    and value >= (min or -math.huge) and value <= (max or math.huge)
end

local function exactIndexSet(indices, maxIndex, requireMember)
  if type(indices) ~= "table" then return nil end
  local count, keys = #indices, 0
  for key in pairs(indices) do
    keys = keys + 1
    if not integer(key, 1, count) then return nil end
  end
  if keys ~= count or (requireMember and count == 0) then return nil end
  local seen = {}
  for i = 1, count do
    local index = indices[i]
    if not integer(index, 1, maxIndex) or seen[index] then return nil end
    seen[index] = true
  end
  return seen
end

local function validateMoveList(data, moves)
  if type(moves) ~= "table" then return false end
  for _, move in ipairs(moves) do
    if type(move) ~= "table" or type(move.id) ~= "string"
        or type(data.moves[move.id]) ~= "table" or type(move.pp) ~= "number" then
      return false
    end
  end
  return true
end

local function validateMon(data, mon)
  return type(mon) == "table" and type(mon.species) == "string"
    and type(data.pokemon[mon.species]) == "table" and integer(mon.level, 1, 100)
    and type(mon.hp) == "number" and type(mon.stats) == "table"
    and validateMoveList(data, mon.moves)
end

local function validateBattler(data, battler, maxIndex)
  if type(battler) ~= "table" or not integer(battler.index, 1, maxIndex) then
    return false
  end
  if type(battler.curMoves) ~= "table" then return false end
  if battler.stages ~= nil then
    if type(battler.stages) ~= "table" then return false end
    for _, stage in pairs(battler.stages) do
      if not integer(stage, -6, 6) then return false end
    end
  end
  for _, slotField in pairs(MOVE_REFERENCE_FIELDS) do
    if battler[slotField] ~= nil
        and not integer(battler[slotField], 1, #battler.curMoves) then
      return false
    end
  end
  return validateMoveList(data, battler.curMoves)
    and type(battler.curStats) == "table" and type(battler.curTypes) == "table"
end

local function clone(value, copy)
  if type(value) ~= "table" then return value end
  return assert(copy(value))
end

local function captureMimicRestores(battle)
  local out = {}
  for _, restore in ipairs(battle.mimicRestores or {}) do
    local side = restore.battler == battle.player and "player"
      or restore.battler == battle.enemy and "enemy" or nil
    local slot
    for index, move in ipairs(restore.battler and restore.battler.curMoves or {}) do
      if move == restore.entry then slot = index break end
    end
    if not side or not slot or type(restore.id) ~= "string" then return nil end
    out[#out + 1] = { side = side, slot = slot, id = restore.id }
  end
  return out
end

function BattleCheckpoint.validate(game, checkpoint)
  local model = checkpoint.runtime and checkpoint.runtime.battle
  local rngState = checkpoint.rng and checkpoint.rng.love
  if type(model) ~= "table" or type(model.origin) ~= "table"
      or type(rngState) ~= "string" or rngState == "" then
    return nil, "invalid_checkpoint", "Battle checkpoint data or RNG is missing."
  end
  local expectedOrigin = model.kind == "wild" and "wild_encounter"
    or model.kind == "trainer" and "trainer_encounter" or nil
  local scripted = model.origin.kind == "script_battle"
  if not expectedOrigin
      or (model.origin.kind ~= expectedOrigin and not scripted)
      or model.origin.map ~= checkpoint.runtime.overworld.map then
    return nil, "battle_origin_unsupported",
      "Battle continuation data is unsupported or inconsistent."
  end
  if type(model.rulesetId) ~= "string"
      or type(rulesets(game)[model.rulesetId]) ~= "table" then
    return nil, "invalid_content", "Battle ruleset is unavailable."
  end
  if scripted then
    local origin = model.origin
    local row = type(origin.script) == "table" and origin.script[origin.pc]
    local allowed = { start_battle = true, static_battle = true, rival_battle = true }
    if type(origin.pc) ~= "number" or origin.pc % 1 ~= 0
        or type(row) ~= "table" or row[1] ~= origin.command
        or not allowed[origin.command] or origin.battleKind ~= model.kind
        or (model.kind == "trainer" and (origin.trainerClass ~= model.oppClass
          or origin.partyIndex ~= (model.partyIndex or 1)))
        or (model.kind == "wild" and (origin.wildSpecies ~= model.enemyMon.species
          or origin.wildLevel ~= model.enemyMon.level))
        or (origin.npcId ~= nil and type(origin.npcId) ~= "string") then
      return nil, "battle_origin_unsupported",
        "Script battle continuation data is incomplete or inconsistent."
    end
    local problems = ScriptRunner.validate(origin.script)
    if #problems > 0 then
      return nil, "battle_origin_unsupported",
        "Script battle continuation commands are unavailable."
    end
  elseif model.kind == "trainer" and (type(model.origin.npcId) ~= "string"
      or model.origin.trainerClass ~= model.oppClass
      or model.origin.partyIndex ~= (model.partyIndex or 1)) then
    return nil, "battle_origin_unsupported",
      "Trainer continuation data is incomplete or inconsistent."
  end
  local party = checkpoint.save.party
  if type(party) ~= "table" or not validateBattler(game.data, model.player, #party) then
    return nil, "invalid_content", "Player battle state is invalid."
  end
  local scopedIndices
  if model.playerPartyIndices ~= nil then
    if model.kind ~= "trainer" then
      return nil, "invalid_checkpoint", "Battle party scope is invalid."
    end
    scopedIndices = exactIndexSet(model.playerPartyIndices, #party, true)
    if not scopedIndices or not scopedIndices[model.player.index] then
      return nil, "invalid_checkpoint", "Battle party scope is invalid."
    end
  end
  if model.kind == "wild" then
    if not validateMon(game.data, model.enemyMon)
        or not validateBattler(game.data, model.enemy, 1) then
      return nil, "invalid_content", "Wild opponent state is invalid."
    end
  else
    local trainer = game.data.trainers and game.data.trainers[model.oppClass]
    if type(trainer) ~= "table" or not integer(model.partyIndex, 1)
        or type(model.enemyParty) ~= "table" or #model.enemyParty == 0
        or not integer(model.enemyIndex, 1, #model.enemyParty)
        or not validateBattler(game.data, model.enemy, #model.enemyParty) then
      return nil, "invalid_content", "Trainer battle identity or roster is invalid."
    end
    for _, mon in ipairs(model.enemyParty) do
      if not validateMon(game.data, mon) then
        return nil, "invalid_content", "Trainer opponent state is invalid."
      end
    end
  end
  for _, indices in ipairs({ model.participants, model.leveledUp }) do
    local referenced = exactIndexSet(indices, #party, false)
    if not referenced then
      return nil, "invalid_checkpoint", "Battle party reference set is missing."
    end
    if scopedIndices then
      for index in pairs(referenced) do
        if not scopedIndices[index] then
          return nil, "invalid_checkpoint", "Battle party reference is invalid."
        end
      end
    end
  end
  if type(model.mimicRestores) ~= "table" then
    return nil, "invalid_checkpoint", "Mimic restore state is missing."
  end
  for _, restore in ipairs(model.mimicRestores) do
    local battler = restore.side == "player" and model.player
      or restore.side == "enemy" and model.enemy or nil
    if not battler or not integer(restore.slot, 1, #battler.curMoves)
        or type(restore.id) ~= "string"
        or type(game.data.moves[restore.id]) ~= "table" then
      return nil, "invalid_content", "Mimic restore state is invalid."
    end
  end
  return true
end

local function applyBattler(target, captured, copy)
  for _, field in ipairs(BATTLER_FIELDS) do
    if field ~= "curStats" and field ~= "curTypes" and field ~= "curMoves" then
      if captured[field] ~= nil then
        target[field] = clone(captured[field], copy)
      else
        target[field] = nil
      end
    end
  end
  target.curStats = captured.curStatsFromMon and target.mon.stats
    or assert(copy(captured.curStats))
  target.curTypes = captured.curTypesFromDefinition and target.def.types
    or assert(copy(captured.curTypes))
  target.curMoves = captured.curMovesFromMon and target.mon.moves
    or assert(copy(captured.curMoves))
  for field, slotField in pairs(MOVE_REFERENCE_FIELDS) do
    target[field] = captured[slotField] and target.curMoves[captured[slotField]] or nil
  end
  return target
end

local function restoreIndexSet(indices, party)
  local out = {}
  for _, index in ipairs(indices or {}) do out[party[index]] = true end
  return next(out) and out or nil
end

function BattleCheckpoint.restore(game, checkpoint, copy)
  local model = checkpoint.runtime.battle
  local battle
  if model.kind == "trainer" then
    battle = BattleState.newTrainer(game, model.oppClass, model.partyIndex, {
      playerPartyIndices = model.playerPartyIndices,
    })
    battle.enemyParty = assert(copy(model.enemyParty))
    battle.enemyIndex = model.enemyIndex
  else
    battle = BattleState.newWild(game, model.enemyMon.species, model.enemyMon.level)
  end

  battle.player = BattleState.makeBattler(game.data,
    game.save.party[model.player.index], true, game.save)
  applyBattler(battle.player, model.player, copy)
  local enemyMon
  if model.kind == "trainer" then
    enemyMon = battle.enemyParty[model.enemy.index]
  else
    enemyMon = assert(copy(model.enemyMon))
  end
  battle.enemy = BattleState.makeBattler(game.data, enemyMon, false)
  applyBattler(battle.enemy, model.enemy, copy)

  battle.mimicRestores = {}
  for _, restore in ipairs(model.mimicRestores or {}) do
    local battler = restore.side == "player" and battle.player or battle.enemy
    battle.mimicRestores[#battle.mimicRestores + 1] = {
      battler = battler,
      entry = battler.curMoves[restore.slot],
      id = restore.id,
    }
  end
  if #battle.mimicRestores == 0 then battle.mimicRestores = nil end

  for _, field in ipairs(BATTLE_FIELDS) do
    if model[field] ~= nil then
      battle[field] = clone(model[field], copy)
    else
      battle[field] = nil
    end
  end
  battle.kind = model.kind
  battle.ruleset = rulesets(game)[model.rulesetId]
  battle.checkpointOrigin = assert(copy(model.origin))
  battle.participants = restoreIndexSet(model.participants, game.save.party)
  battle.leveledUp = restoreIndexSet(model.leveledUp, game.save.party)
  battle.sides = assert(copy(model.sides))
  battle.sides[1].battlers = { battle.player }
  battle.sides[2].battlers = { battle.enemy }
  battle.field = assert(copy(model.field))
  battle.field.sides = battle.sides
  battle.phase, battle.queue = "menu", {}
  battle.frame = 0
  battle.current, battle.afterQueue, battle.nextInsert = nil, nil, nil
  battle.pendingHit, battle.waitingUI, battle.waitingSound = nil, nil, nil
  battle.waitFrames, battle.draining, battle.animPlaying = nil, nil, nil
  battle.introText, battle.introBalls, battle.introSlide = nil, nil, nil
  battle.showPlayerBack, battle.showEnemyTrainer, battle.showEnemyBalls = nil, nil, nil
  battle.player.shownHP, battle.player.shownStatus =
    battle.player.mon.hp, battle.player.mon.status
  battle.enemy.shownHP, battle.enemy.shownStatus =
    battle.enemy.mon.hp, battle.enemy.mon.status
  -- the bar's own pixel length is derived HUD state, not captured: it
  -- settles with shownHP above (UpdateHPBar_AnimateHPBar's end position)
  local Timing = require("src.core.Timing")
  for _, b in ipairs({ battle.player, battle.enemy }) do
    b.shownPx = Timing.hpBarPixels(b.mon.hp, math.max(1, b.mon.stats.hp))
  end

  local ow = game.overworld
  if not ow or type(ow.restoreBattleContinuation) ~= "function"
      or ow:restoreBattleContinuation(battle, battle.checkpointOrigin) ~= true then
    error("battle continuation reconstruction is unavailable", 0)
  end
  if type(game.restoreCheckpointBattle) ~= "function" then
    error("game has no battle checkpoint reconstruction path", 0)
  end
  game:restoreCheckpointBattle(battle)
  local setState = love and love.math and love.math.setRandomState
  if type(setState) ~= "function" then error("battle RNG restore is unavailable", 0) end
  setState(checkpoint.rng.love)
  return battle
end

local function captureExtensions(battle, copy)
  local sides = {}
  for i = 1, 2 do
    local side = battle.sides and battle.sides[i] or {}
    local encoded, err = copy({
      index = i,
      screens = side.screens or {},
      hazards = side.hazards or {},
      tokens = side.tokens or {},
    })
    if not encoded then return nil, err end
    sides[i] = encoded
  end
  local field, err = copy({
    weather = battle.field and battle.field.weather or nil,
    tokens = battle.field and battle.field.tokens or {},
  })
  if not field then return nil, err end
  return sides, field
end

function BattleCheckpoint.capture(game, battle, progress, copy)
  local getState = love and love.math and love.math.getRandomState
  local setState = love and love.math and love.math.setRandomState
  if type(getState) ~= "function" or type(setState) ~= "function" then
    return nil, "rng_state_unavailable",
      "This runtime cannot preserve deterministic battle randomness."
  end
  local ok, rngState = pcall(getState)
  if not ok or type(rngState) ~= "string" or rngState == "" then
    return nil, "rng_state_unavailable",
      "The gameplay random-number state could not be captured."
  end

  local origin, originErr = copy(battle.checkpointOrigin)
  if not origin then
    return nil, "battle_origin_unsupported",
      "The battle completion path is not data-only: " .. tostring(originErr)
  end
  local sides, fieldOrErr = captureExtensions(battle, copy)
  if not sides then
    return nil, "battle_extension_unsafe",
      "Battle extension state is not data-only: " .. tostring(fieldOrErr)
  end
  local field = fieldOrErr

  local liveParty = game.save.party
  local playerIndex = partyIndex(liveParty, battle.player.mon)
  if not playerIndex then
    return nil, "battle_state_invalid",
      "The active player battler is not in the current party."
  end

  local model = {
    kind = battle.kind,
    rulesetId = rulesetId(game, battle.ruleset),
    origin = origin,
    player = captureBattler(battle.player, playerIndex, copy),
    participants = indexSet(battle.participants, liveParty),
    leveledUp = indexSet(battle.leveledUp, liveParty),
    sides = sides,
    field = field,
    mimicRestores = captureMimicRestores(battle),
  }
  if not model.rulesetId then
    return nil, "battle_state_invalid", "Battle ruleset identity is unavailable."
  end
  if not model.player then
    return nil, "battle_state_invalid", "Player move references are inconsistent."
  end
  if not model.mimicRestores then
    return nil, "battle_state_invalid", "Mimic restore state is inconsistent."
  end
  if battle.kind == "trainer" then
    model.enemyParty = copy(battle.enemyParty)
    model.enemy = captureBattler(battle.enemy, battle.enemyIndex, copy)
  else
    model.enemyMon = copy(battle.enemy.mon)
    model.enemy = captureBattler(battle.enemy, 1, copy)
  end
  if not model.enemy then
    return nil, "battle_state_invalid", "Enemy move references are inconsistent."
  end
  for _, fieldName in ipairs(BATTLE_FIELDS) do
    if battle[fieldName] ~= nil then model[fieldName] = battle[fieldName] end
  end

  model = copy(model)
  if not model then
    return nil, "battle_state_invalid",
      "Battle state contains non-serializable runtime data."
  end
  local player = progress.player
  return {
    overworld = {
      map = player.map, x = player.x, y = player.y,
      facing = player.facing, surfing = player.surfing and true or false,
    },
    battle = model,
  }, { love = rngState }
end

return BattleCheckpoint
