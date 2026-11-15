local GameVersion = require("src.core.GameVersion")

local Rules = {}

local function text(battle, label, mon, item)
  return battle:romText(label, mon, mon, item)
end

local function byte(battle)
  if battle.random then return battle.random(256) end
  if love and love.math then return love.math.random(256) - 1 end
  return math.random(256) - 1
end

-- engine/battle/effect_commands.asm:333
function Rules.cancelMove(state)
  state.bideTurns, state.bideStored, state.bideMove = nil, nil, nil
  state.rampageMove, state.rampageTurns = nil, nil
  state.chargeMove, state.vanished = nil, nil
  state.rolloutLock, state.rolloutCount = nil, nil
  state.furyCutterCount, state.rampCount, state.rampMove = nil, nil, nil
end

function Rules.install(Battle, Damage)
  local originalStatus = Battle.applyStatus
  local originalConfusion = Battle.applyConfusion
  local originalRefused = Battle.statusRefusedByType
  local originalCounters = Battle.tickCounters

  -- data/moves/effects.asm:1466
  for effect, status in pairs({ EFFECT_THUNDER = "paralyze",
      EFFECT_FLAME_WHEEL = "burn" }) do
    Battle.SECONDARY_EFFECTS[effect] = status
    Battle.MOVE_EFFECT_RECORDS[effect] = { kind = "secondary", status = status }
  end

  -- engine/battle/effect_commands.asm:193
  Battle.STATUSES.freeze.beforeMove = function(battle, mon)
    battle:emit({ kind = "message", text = text(battle, "FrozenSolidText", mon) })
    return false
  end

  -- engine/battle/effect_commands.asm:323
  Battle.STATUSES.paralyze.beforeMove = function(battle, mon)
    if byte(battle) >= 63 then return true end
    battle:emit({ kind = "message", text = text(battle, "FullyParalyzedText", mon) })
    return false
  end

  -- engine/battle/effect_commands.asm:147
  function Battle:canAct(mon, moveId)
    local state = self:volatile(mon)
    state.destinyBond = nil
    -- engine/battle/core.asm:961
    self.moveRuleTurnMon = mon
    local function spent()
      Rules.cancelMove(state)
      return false
    end
    if state.recharge then
      state.recharge = nil
      self:emit({ kind = "message", text = text(self, "MustRechargeText", mon) })
      return spent()
    end
    local record = Battle.statusRecordFor(self.data, mon.status)
    local before = record and record.beforeMove
    if mon.status == "freeze" and
        (moveId == "FLAME_WHEEL" or moveId == "SACRED_FIRE") then before = nil end
    if before and (record.beforeMovePriority or 0) > Battle.VOLATILE_PRIORITY then
      local bypass = mon.status == "sleep" and Battle.SLEEP_BYPASS_MOVES[moveId]
      local acted = before(self, mon, self:battlerName(mon))
      if acted then
        Rules.cancelMove(state)
      elseif not bypass then
        return spent()
      end
      before = nil
    end
    if state.flinched then
      state.flinched = nil
      self:emit({ kind = "message", text = text(self, "FlinchedText", mon) })
      return spent()
    end
    -- engine/battle/effect_commands.asm:225
    if state.disabledTurns then
      state.disabledTurns = state.disabledTurns - 1
      if state.disabledTurns <= 0 then
        state.disabled, state.disabledTurns = nil, nil
        self:emit({ kind = "message",
          text = text(self, "DisabledNoMoreText", mon) })
      end
    end
    if state.confuseCount then
      state.confuseCount = state.confuseCount - 1
      if state.confuseCount <= 0 then
        state.confuseCount = nil
        self:emit({ kind = "message", text = text(self, "ConfusedNoMoreText", mon) })
      else
        self:emit({ kind = "message", text = text(self, "IsConfusedText", mon) })
        if byte(self) < 128 then
          state.flinched = nil
          self:confusionSelfHit(mon, moveId)
          return spent()
        end
      end
    end
    if state.attract then
      local partner = mon == self.player and self.enemy or self.player
      self:emit({ kind = "message", text = self:romText("InLoveWithText", mon, partner) })
      if byte(self) >= 128 then
        self:emit({ kind = "message", text = text(self, "InfatuationText", mon) })
        return spent()
      end
    end
    if state.disabled and state.disabled == moveId then
      self:emit({ kind = "message", text = text(self, "DisabledMoveText", mon, self:moveDef(moveId).name) })
      return spent()
    end
    if before and not before(self, mon, self:battlerName(mon)) then return spent() end
    return true
  end

  -- engine/battle/effect_commands.asm:5909
  function Battle:statusRefusedByType(mon, moveType, status)
    if status == "burn" or status == "freeze" then
      if status == "freeze" and self.weather == "sun" then return true end
      if moveType == "NORMAL" then return false end
      for _, kind in ipairs(self:battlerTypes(mon)) do
        if kind == moveType then return true end
      end
      return false
    end
    return originalRefused(self, mon, moveType, status)
  end

  -- engine/battle/effect_commands.asm:3930
  function Battle:thaw(mon)
    if mon.status ~= "freeze" then return false end
    mon.status = nil
    self:emit({ kind = "status", side = self:sideOf(mon), status = nil,
      text = text(self, "DefrostedOpponentText", mon) })
    return true
  end

  -- engine/battle/effect_commands.asm:3571
  -- engine/battle/effect_commands.asm:3701
  -- engine/battle/effect_commands.asm:5831
  function Battle:primaryStatusRefusal(mon, status, source, moveType)
    local state = self:volatile(mon)
    if status == "confuse" then
      if not state.confuseCount and (state.substitute or 0) > 0 then
        return "DidntAffect1Text"
      end
      return nil
    end
    local poison = status == "poison" or status == "toxic"
    local already = ({ sleep = "AlreadyAsleepText", poison = "AlreadyPoisonedText",
      toxic = "AlreadyPoisonedText", paralyze = "AlreadyParalyzedText" })[status]
    local same = mon.status == status or
      (poison and (mon.status == "poison" or mon.status == "toxic"))
    local refused = moveType and self:statusRefusedByType(mon, moveType, status)
    if poison and refused then return "DoesntAffectText" end
    if already and same then return already end
    if refused then return "DoesntAffectText" end
    if poison and mon.status then return "DidntAffect1Text" end
    if Battle.AI_FAIL_STATUSES[status] and self:aiRandomFail(source, mon) then
      return "DidntAffect1Text"
    end
    if mon.status then return "DidntAffect1Text" end
    if (state.substitute or 0) > 0 then return "DidntAffect1Text" end
  end

  -- engine/battle/effect_commands.asm:3571
  function Battle:applyStatus(mon, status, source, opts)
    opts = opts or {}
    local hostile = source and source ~= mon
    if opts.primary and hostile and (mon.hp or 0) > 0 then
      if self:safeguarded(mon) then return originalStatus(self, mon, status, source) end
      local label = self:primaryStatusRefusal(mon, status, source, opts.moveType)
      if label then
        self:emit({ kind = "message", text = text(self, label, mon) })
        return false
      end
    end
    -- engine/battle/effect_commands.asm:5732
    if status == "confuse" and opts.secondary and
        (self:safeguarded(mon) or self:volatile(mon).confuseCount) then
      return false
    end
    if hostile and (self:volatile(mon).substitute or 0) > 0 then return false end
    if opts.moveType and self:statusRefusedByType(mon, opts.moveType, status) then
      return false
    end
    if opts.secondary and status ~= "confuse" and (mon.status or self:safeguarded(mon)) then
      return false
    end
    if mon.status and not opts.secondary then
      local templates = { sleep = "AlreadyAsleepText",
        poison = "AlreadyPoisonedText", toxic = "AlreadyPoisonedText",
        paralyze = "AlreadyParalyzedText" }
      local same = mon.status == status or
        ((status == "poison" or status == "toxic") and
          (mon.status == "poison" or mon.status == "toxic"))
      if same and templates[status] then
        self:emit({ kind = "message",
          text = text(self, templates[status], mon) })
        return false
      end
    end
    local landed = originalStatus(self, mon, status, source)
    local kept = self:volatile(mon).toxicKept
    if landed and status == "poison" and mon.status == "poison" and kept then
      -- engine/battle/core.asm:1043
      mon.status, mon.toxicCounter = "toxic", kept
      self:volatile(mon).toxicKept = nil
    end
    if landed then
      self:cureHeldStatus(mon)
      if status == "freeze" and mon.status == "freeze" then
        local state = self:volatile(mon)
        state.justFrozen, state.recharge = true, nil
        Rules.cancelMove(state)
      end
      -- engine/battle/effect_commands.asm:3631
      if status == "sleep" and mon.status == "sleep" and hostile then
        Rules.cancelMove(self:volatile(mon))
      end
    end
    return landed
  end

  -- engine/battle/effect_commands.asm:5750
  function Battle:applyConfusion(mon, turns, source)
    local landed = originalConfusion(self, mon, turns, source)
    if landed then self:cureHeldStatus(mon) end
    return landed
  end

  -- engine/battle/effect_commands.asm:4320
  function Battle:statDropBlocked(mon)
    local state = self:volatile(mon)
    return (state.substitute or 0) > 0 or state.vanished
  end

  -- engine/battle/effect_commands.asm:4351
  function Battle:aiStatDropFailed(attacker, defender, effect)
    if self.inBattleTowerBattle or effect == "EFFECT_ACCURACY_DOWN_HIT" then
      return false
    end
    return self:aiRandomFail(attacker, defender)
  end

  -- engine/battle/effect_commands.asm:5357
  function Battle:flinch(mon, held)
    if not held and self.firstMover == self:sideOf(mon) then return false end
    if not held and (mon.status == "sleep" or mon.status == "freeze") then
      return false
    end
    local state = self:volatile(mon)
    state.flinched, state.recharge = true, nil
    return true
  end

  -- engine/battle/effect_commands.asm:1851
  function Battle:applyMoveSecondary(attacker, defender, def, blockedBySubstitute)
    local tri = def.effect == "EFFECT_TRI_ATTACK"
    if tri and (defender.hp or 0) <= 0 then return end
    local failed = (blockedBySubstitute and not tri) or self:effectChanceFailed(def, defender)
    local record = Battle.moveEffectRecordFor(self.data, def.effect)
    local status = record and record.kind == "secondary" and record.status
    -- engine/battle/effect_commands.asm:4730
    if tri then
      local roll
      repeat roll = math.floor(byte(self) / 16) % 4 until roll ~= 0
      status = ({ "paralyze", "freeze", "burn" })[roll]
    end
    if (defender.hp or 0) <= 0 then return end
    if (self:volatile(defender).substitute or 0) > 0 then return end
    -- engine/battle/effect_commands.asm:3938
    if status == "burn" and defender.status == "freeze" then
      self:thaw(defender)
      return
    end
    if failed then return end
    if status then
      self:applyStatus(defender, status, attacker,
        { secondary = true, moveType = def.type })
    end
  end

  -- engine/battle/core.asm:4383
  function Battle:cureHeldStatus(mon)
    local effect = self:heldEffect(mon, "status")
    local cure = Battle.HELD_STATUS_CURES[effect]
    local major = (cure == mon.status and cure ~= nil) or
      (effect == "HELD_HEAL_STATUS" and mon.status ~= nil) or
      (effect == "HELD_HEAL_POISON" and mon.status == "toxic")
    local state = self:volatile(mon)
    local confuse = state.confuseCount and
      (effect == "HELD_HEAL_CONFUSION" or effect == "HELD_HEAL_STATUS")
    if not major and not confuse then return false end
    local item = self:itemDef(mon.item)
    if major then
      mon.status, mon.statusTurns, mon.toxicCounter = nil, nil, nil
      state.nightmare, state.toxicKept = nil, nil
    end
    if confuse then state.confuseCount = nil end
    mon.item = nil
    self:emit({ kind = "status", side = self:sideOf(mon), status = mon.status,
      text = text(self, major and "RecoveredUsingText" or "BattleText_ItemHealedConfusion",
        mon, item.name) })
    return true
  end

  -- engine/battle/core.asm:1328
  function Battle:tickMysteryBerry(mon)
    if (mon.hp or 0) <= 0 or self:heldEffect(mon, "pp") ~= "HELD_RESTORE_PP" then
      return
    end
    for slot, move in ipairs(self:partyMoves(mon) or {}) do
      if move.pp == 0 then
        local restored = move.id == "SKETCH" and 1 or 5
        move.pp = restored
        local active = mon.moves and mon.moves[slot]
        if active and active ~= move and active.id == move.id
            and not self:volatile(mon).preTransform then
          active.pp = active.pp + restored
        end
        local item = self:itemDef(mon.item)
        mon.item = nil
        self:emit({ kind = "message",
          text = text(self, "BattleText_UserRecoveredPPUsing", mon, item.name) })
        return
      end
    end
  end

  -- engine/battle/core.asm:1524
  function Battle:tickDefrost(mon)
    local state = self:volatile(mon)
    if mon.status == "freeze" and not state.justFrozen and byte(self) < 25 then
      self:thaw(mon)
    end
    state.justFrozen = nil
  end

  -- engine/battle/core.asm:4272
  function Battle:tickHeldItem(mon, category)
    if (mon.hp or 0) <= 0 then return end
    local effect, parameter = self:heldEffect(mon, "residual")
    local maxHp = mon.maxHp or mon.stats.hp
    local item = self:itemDef(mon.item)
    if effect == "HELD_LEFTOVERS" and category ~= "healing" then
      local healed = self:heal(mon, math.max(1, math.floor(maxHp / 16)))
      if healed > 0 then
        self:emit({ kind = "message", text = text(self, "BattleText_TargetRecoveredWithItem", mon, item.name) })
      end
    elseif category ~= "leftovers" then
      if effect == "HELD_BERRY" and mon.hp * 2 < maxHp then
        self:heal(mon, parameter, { anim = "RECOVER" })
        mon.item = nil
        self:emit({ kind = "message", text = text(self, "RecoveredUsingText", mon, item.name) })
      else
        self:cureHeldStatus(mon)
      end
    end
  end

  -- engine/battle/effect_commands.asm:225
  function Battle:tickCounters(mon)
    local state = self:volatile(mon)
    local disabledTurns = state.disabledTurns
    state.disabledTurns = nil
    originalCounters(self, mon)
    state.disabledTurns = disabledTurns
  end

  -- engine/battle/core.asm:1583
  function Battle:tickScreens()
    local sides = self.mirrored and { "enemy", "player" } or { "player", "enemy" }
    local function tick(side, field, label)
      local screens = self.screens[side]
      if not screens[field] then return end
      screens[field] = screens[field] - 1
      if screens[field] > 0 then return end
      screens[field] = nil
      self:emit({ kind = "message", text = self:romText(label, self[side], self[side],
        self:romText(side == "player" and "HandleScreens.Your" or "HandleScreens.Enemy")) })
    end
    for _, side in ipairs(sides) do tick(side, "safeguard", "BattleText_SafeguardFaded") end
    for _, side in ipairs(sides) do
      tick(side, "lightScreen", "BattleText_MonsLightScreenFell")
      tick(side, "reflect", "BattleText_MonsReflectFaded")
    end
  end

  -- engine/battle/core.asm:250
  function Battle:betweenTurnEffects()
    local first, second = self.player, self.enemy
    if self.mirrored then first, second = second, first end
    -- engine/battle/core.asm:298
    local function fainted()
      if (self.player.hp or 0) <= 0 or (self.enemy.hp or 0) <= 0 then
        self:resolveFaints(not self.mirrored)
      end
      return self.over
    end
    if fainted() then return end
    self:tickFutureSight(first)
    self:tickFutureSight(second)
    if fainted() then return end
    self:tickWeather()
    if fainted() then return end
    self:tickWrap(first)
    self:tickWrap(second)
    if fainted() then return end
    self:tickPerish(first)
    self:tickPerish(second)
    if fainted() then return end
    self:tickHeldItem(first, "leftovers")
    self:tickHeldItem(second, "leftovers")
    self:tickMysteryBerry(first)
    self:tickMysteryBerry(second)
    self:tickDefrost(first)
    self:tickDefrost(second)
    self:tickScreens()
    self:tickHeldItem(first, "healing")
    self:tickHeldItem(second, "healing")
    self:tickCounters(first)
    self:tickCounters(second)
  end

  -- engine/battle/effect_commands.asm:2864
  function Battle:confusionSelfHit(mon, moveId)
    local stages = self.stages[self:sideOf(mon)]
    local boosts = self:battleBadgeBoosts(mon)
    local function stat(key)
      local value = Damage.applyStage(mon.stats[key], stages[key])
      if boosts[key] then value = math.min(Damage.MAX_STAT_VALUE,
        value + math.floor(value / 8)) end
      return value
    end
    local attack = Battle.statusPenaltyFor(self.data, mon, "attack", stat("attack"))
    local defense = stat("defense")
    if self.screens[self:sideOf(mon)].reflect then defense = defense * 2 end
    local fixed = self:reflectOverflowFixed()
    if fixed == nil then fixed = GameVersion.fixes().reflectOverflow == true end
    attack, defense = Damage.truncateStats(attack, defense, fixed)
    local move = moveId and self:moveDef(moveId)
    if move and move.effect == "EFFECT_SELFDESTRUCT" then
      defense = math.max(1, math.floor(defense / 2))
    end
    local damage = Damage.base(mon.level or 1, 40, attack, defense)
    local effect, parameter = self:heldEffect(mon, "damage")
    if move and effect == "HELD_" ..
        (move.type == "PSYCHIC_TYPE" and "PSYCHIC" or move.type) .. "_BOOST" then
      damage = math.floor(damage * (100 + parameter) / 100)
    end
    damage = math.min(damage, Damage.MAX_DAMAGE - Damage.MIN_DAMAGE) + Damage.MIN_DAMAGE
    -- engine/battle/effect_commands.asm:586
    self.moveRuleLastDamage = 0
    self:emit({ kind = "message", text = text(self, "HurtItselfText", mon) })
    mon.hp = math.max(0, mon.hp - damage)
    self:emit({ kind = "damage", side = self:sideOf(mon), amount = damage, hp = mon.hp,
      anim = "ANIM_HIT_CONFUSION", animSide = self:sideOf(mon) })
    return damage
  end
end

return Rules
