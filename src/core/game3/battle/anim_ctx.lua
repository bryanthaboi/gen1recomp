local Anim = require("src.core.game3.battle.anim")
local AnimCoords = require("src.core.game3.battle.anim_coords")

local AnimCtx = {}

local function battle_state()
  local Battle = package.loaded["src.core.game3.battle"]
  return Battle and Battle._st
end

local function battler_id(key)
  return AnimCoords.fixedId(key) or ((key == "enemy") and 1 or 0)
end

-- pokefirered/src/battle_anim_utility_funcs.c:840
local function terrain_id(st)
  local v = st and tonumber(st.terrain)
  if v ~= nil then return v end
  local ok, BattleBg = pcall(require, "src.core.game3.battle.bg")
  return ok and BattleBg.terrainId and BattleBg.terrainId() or nil
end

function AnimCtx.behindSubstitute(lowered)
  local out = AnimCoords.idTable()
  for id = 0, 3 do
    local p = rawget(Anim._present, id)
    local low = lowered and (lowered[id] or (id < 2 and lowered[AnimCoords.sideOf(id)]))
    out[id] = ((p and p.substitute) or low) and true or false
  end
  return out
end

-- pokefirered/src/battle_controller_player.c:2316
function AnimCtx.build(attacker, target, opts)
  opts = opts or {}
  local st = battle_state()
  attacker = attacker or "player"
  target = target or attacker
  local atkId = battler_id(attacker)
  local a = AnimCoords.battler(st, atkId)
  local mon = a and a.mon or {}
  local ap = rawget(Anim._present, atkId)
  local ctx = {
    behindSubstitute = AnimCtx.behindSubstitute(opts.lowered),
    battlerAttacker = atkId,
    battlerTarget = battler_id(target),
    effectBattler = battler_id(opts.effectBattler or target),
    isDouble = AnimCoords.isDouble(st),
    animArg = tonumber(opts.animArg) or 0,
    movePower = 0,
    moveDmg = tonumber(opts.moveDmg) or 0,
    friendship = tonumber(mon.friendship or mon.happiness) or 0,
    weather = st and st.weather or nil,
    battleTerrain = terrain_id(st),
    furyCutterCounter = a and tonumber(a.expFuryCutter) or 0,
    rolloutTimer = a and tonumber(a.expRolloutTimer) or 0,
    rolloutTimerStartValue = 5,
    attackerHp = (ap and ap.displayHp) or tonumber(mon.hp) or 0,
    attackerMaxHp = (ap and ap.displayMaxHp) or tonumber(mon.maxHp) or 1,
    playerGender = st and st.playerGender or 0,
    lastUsedItem = st and st.lastUsedItem or nil,
    ballThrowCaseId = st and st.ballThrowCaseId or 0,
    -- pokefirered/src/battle_anim_special.c:2273
    safariReaction = (st and tonumber(st.safariReaction)) or 0,
    oldManTutorial = st and st.oldManTutorial or false,
    pokeball = mon.pokeball,
    ballItem = {
      player = st and st.player and st.player.mon and st.player.mon.pokeball,
      enemy = st and st.enemy and st.enemy.mon and st.enemy.mon.pokeball,
    },
  }
  ctx.animMoveDmg = ctx.moveDmg
  ctx.damage = ctx.moveDmg
  ctx.animFriendship = ctx.friendship
  ctx.weatherMoveAnim = ctx.weather
  ctx.furyCutter = ctx.furyCutterCounter
  if opts.moveId then
    local ok, Moves = pcall(require, "src.core.game3.battle.moves")
    local mv = ok and Moves.get and Moves.get(opts.moveId)
    ctx.movePower = mv and tonumber(mv.power) or 0
  end
  return ctx
end

return AnimCtx
