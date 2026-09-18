-- After-hit secondaries for damaging moves (owned game3).

local EffectIds = require("src.core.game3.battle.effect_ids")
local Secondary = require("src.core.game3.battle.effects.secondary")

local Damaging = {}

function Damaging.afterHit(adapter, user, target, move, dmg)
  if not move or (dmg or 0) <= 0 then return end
  local spec = EffectIds.SECONDARY[tonumber(move.effect) or -1]
  if not spec then return end
  local M = {
    adapter = adapter, st = adapter._st, user = user, target = target,
    move = move, moveId = move.numId or move.id, mnum = tonumber(move.numId),
    hpDealt = dmg, moveName = move.id,
  }
  Secondary.withChance(M, spec.eff, spec.certain, spec.user)
end

--- Brick Break: clear foe Reflect / Light Screen.
-- pokefirered/src/battle_script_commands.c:9441
function Damaging.brickBreak(adapter, target)
  local side = adapter:ownSide(target)
  if not side then return false end
  local cleared = (side.expReflectTurns or 0) > 0 or (side.expLightScreenTurns or 0) > 0
  side.expReflectTurns = nil
  side.expLightScreenTurns = nil
  if cleared then adapter:say("The wall shattered!") end
  return cleared
end

return Damaging
