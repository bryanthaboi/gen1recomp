-- Shared settled supported player-decision predicate. Checkpoint capture and
-- the public auxiliary action deliberately use this one engine-owned rule so
-- a tool cannot open at a phase that it could not subsequently checkpoint.
-- It exposes no controller; callers receive only the result/reason.

local BattleSafety = {}

local BATTLE_BUSY_FIELDS = {
  "current", "afterQueue", "nextInsert", "pendingHit", "waitingUI",
  "waitingSound", "waitFrames", "draining", "animPlaying", "growIn",
  "shrinkOut",
  "introSlide", "ghostReveal", "mimicCtx", "mimicMoves", "result",
}

local function nonempty(value)
  return type(value) == "table" and next(value) ~= nil
end

local function running(runner)
  return runner and runner.isRunning and runner:isRunning()
end

local function scriptsBusy(overworld)
  return running(overworld and overworld.runner)
    or nonempty(overworld and overworld.parallelRunners)
    or nonempty(overworld and overworld.pendingScripts)
    or nonempty(overworld and overworld.parallelQueue)
    or nonempty(overworld and overworld.scriptMoves)
end

function BattleSafety.inspect(game, battle)
  if type(game) ~= "table" or type(game.save) ~= "table"
      or type(game.save.version) ~= "string" then
    return nil, "not_in_playthrough", "A checkpoint requires an identified active playthrough."
  end
  if type(battle) ~= "table" then
    return nil, "not_battle", "No battle is active."
  end
  if battle.kind == "link" then
    return nil, "link_battle_unsupported", "Network battles cannot be checkpointed."
  end
  if battle.safari or battle.ghost or battle.scopeReveal or battle.demo or battle.noCatch then
    return nil, "battle_variant_unsupported",
      "This battle variant does not have a checkpoint contract."
  end
  if battle.kind ~= "wild" and battle.kind ~= "trainer" then
    return nil, "battle_variant_unsupported",
      "This battle kind does not have a checkpoint contract."
  end
  local origin = battle.checkpointOrigin
  local ordinaryOrigin = battle.kind == "wild" and "wild_encounter"
    or "trainer_encounter"
  local scriptedOrigin = type(origin) == "table"
    and origin.kind == "script_battle"
  if type(origin) ~= "table"
      or (origin.kind ~= ordinaryOrigin and not scriptedOrigin) then
    return nil, "battle_origin_unsupported",
      "The battle completion path cannot be reconstructed safely."
  end
  local overworld = game.overworld or {}
  local scriptedRunner = scriptedOrigin and (battle.checkpointScriptContinuation
    or (overworld.runner
    and overworld.runner.isCheckpointBattle
    and overworld.runner:isCheckpointBattle(battle)))
  local otherScriptWork = nonempty(overworld.parallelRunners)
    or nonempty(overworld.pendingScripts) or nonempty(overworld.parallelQueue)
    or nonempty(overworld.scriptMoves)
  if (scriptedOrigin and (not scriptedRunner or otherScriptWork))
      or (not scriptedOrigin and scriptsBusy(overworld)) then
    return nil, "script_busy", "A suspended or queued script cannot be checkpointed."
  end
  if battle.phase ~= "menu" or nonempty(battle.queue) then
    return nil, "battle_phase_busy",
      "Wait for the player command menu before creating a checkpoint."
  end
  for _, field in ipairs(BATTLE_BUSY_FIELDS) do
    if battle[field] ~= nil and battle[field] ~= false then
      return nil, "battle_phase_busy", "Wait for the current battle action to finish."
    end
  end
  if not battle.player or not battle.enemy or not battle.player.mon
      or battle.player.mon.hp <= 0
      or (battle.menuLockedAction and battle:menuLockedAction(battle.player)) then
    return nil, "battle_phase_busy",
      "Wait for a supported player decision before creating a checkpoint."
  end
  for _, battler in ipairs({ battle.player, battle.enemy }) do
    if not battler.mon or battler.shownHP ~= battler.mon.hp
        or battler.shownStatus ~= battler.mon.status
        or battler.drainFloor ~= nil or battler.drainHold ~= nil
        or battler.faintQueued then
      return nil, "battle_phase_busy",
        "Wait for battle status and HP presentation to settle."
    end
  end
  return true
end

return BattleSafety
