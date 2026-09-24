local Damage = require("src.core.game3.battle.damage")
local Moves = require("src.core.game3.battle.moves")
local EffectIds = require("src.core.game3.battle.effect_ids")
local Types = require("src.core.game3.battle.types")
local Rules = require("src.core.game3.battle.rules")
local Secondary = require("src.core.game3.battle.effects.secondary")
local HeldItems = require("src.core.game3.battle.held_items")
local Oak = require("src.core.game3.battle.oak_advice")
local ModRuntime = require("src.mods.Runtime")
local H = require("src.core.game3.battle.effects._helpers")

local E = EffectIds
local Hit = {}

local MOVE_SURF, MOVE_WHIRLPOOL, MOVE_SLEEP_TALK = 57, 250, 214

local function roll(ad, lo, hi) return ad:roll(lo, hi) end

local function move_is_sleep_talk(ref)
  local m = Moves.get(ref)
  return tonumber(m and m.effect) == E.SLEEP_TALK or tonumber(ref) == MOVE_SLEEP_TALK
end

local function dealt_event(M, target, dealt, info, sub)
  if not ModRuntime.wants("battle.damage_dealt") then return end
  local State = require("src.core.game3.battle.state")
  local G3 = require("src.mods.Gen3Compat")
  local view = G3.moveView(M.move)
  local eff = tonumber(info.effectiveness)
  local mult = eff and math.floor(eff * 10 + 0.5) or 10
  local physical = info.physical
  if physical == nil then physical = Types.isPhysical(M.moveType or M.move.type) end
  ModRuntime.emit("battle.damage_dealt", {
    battle = M.st, user = M.user, target = target, move = view,
    moveId = view and view.id, moveNum = M.mnum, damage = dealt,
    crit = info.critical and true or false, typeMult = mult, effectiveness = mult,
    side = target.side, userId = State.idOf(M.user), targetId = State.idOf(target),
    kind = physical and "physical" or "special", substitute = sub or nil,
  })
end

-- pokefirered/src/battle_script_commands.c:1744
function Hit.dealDamage(M, dmg, info)
  local ad, user, target = M.adapter, M.user, M.target
  info = info or {}
  dmg = math.max(0, math.floor(dmg or 0))
  if (target.substituteHP or 0) > 0 and not info.ignoreSub then
    local subHp = target.substituteHP
    local dealt = math.min(dmg, subHp)
    target.substituteHP = subHp - dealt
    ad:sayText("STRINGID_SUBSTITUTEDAMAGED", { def = target })
    if target.substituteHP <= 0 then
      target.substituteHP = 0
      ad:playAnim("general", "SUBSTITUTE_FADE", target, target)
      ad:sayText("STRINGID_PKMNSUBSTITUTEFADED", { def = target })
    end
    M.hitSubstitute = true
    if (M.firstDmg or 0) == 0 then M.firstDmg = dmg end
    M.hpDealt = dealt
    M.hitsLanded = (M.hitsLanded or 0) + 1
    dealt_event(M, target, dealt, info, true)
    return dealt
  end
  local before = ad:hp(target)
  ad:applyHpLoss(target, dmg, { hit = true })
  local after = ad:hp(target)
  local dealt = before - after
  M.anim.hits[#M.anim.hits + 1] = {
    side = target.side or "enemy",
    battler = target.id,
    from = before,
    to = after,
    maxHp = ad:maxHp(target),
  }
  target.damageTakenThisTurn = (target.damageTakenThisTurn or 0) + dealt
  if (M.firstDmg or 0) == 0 then M.firstDmg = dealt end
  if dealt > 0 then M.targetDamaged = true end
  target.expHurtBy = user.side
  target.expHurtById = user.id
  target.expLastHitById = user.id
  local physical = info.physical
  if physical == nil then physical = Types.isPhysical(M.moveType or M.move.type) end
  -- pokefirered/src/battle_script_commands.c:1824
  if physical then
    target.lastPhysicalDamageTaken = dealt
    target.lastPhysicalById = user.id
  else
    target.lastSpecialDamageTaken = dealt
    target.lastSpecialById = user.id
    M.specialHit = true
  end
  if (target.bideTurns or 0) > 0 then
    target.expBideDamage = (target.expBideDamage or 0) + dealt
    target.expBideTarget = user
  end
  M.hpDealt = dealt
  M.hitsLanded = (M.hitsLanded or 0) + 1
  dealt_event(M, target, dealt, info, false)
  -- pokefirered/src/battle_controller_opponent.c:304
  if Oak.active(M.st) and dealt > 0 and (target.side == "enemy") and user.side == "player" then
    Oak.sayOnce(M.st, Oak.FLAG_INFLICT_DMG, "inflictingDamage", function(t, key) M:say(t, key) end)
  end
  return dealt
end

-- pokefirered/src/battle_script_commands.c:1577
function Hit.adjustDamage(M, target, dmg)
  local ad = M.adapter
  local banded = HeldItems.rollFocusBand(ad, target)
  target.expFocusBanded = nil
  if (target.substituteHP or 0) <= 0 and (target.expEnduring or banded) and dmg >= ad:hp(target) then
    return math.max(0, ad:hp(target) - 1), target.expEnduring and "endured" or "hung"
  end
  return dmg, nil
end

-- pokefirered/src/battle_script_commands.c:5602
function Hit.applySetDamage(M, dmg, flags)
  local ad, target = M.adapter, M.target
  local hung
  dmg, hung = Hit.adjustDamage(M, target, dmg)
  M:attackAnimation()
  Hit.dealDamage(M, dmg)
  if hung == "endured" then
    ad:sayText("STRINGID_PKMNENDUREDHIT", { def = target })
  elseif hung == "hung" then
    HeldItems.focusBandMessage(ad, target)
  elseif flags then
    local line = Hit.effectivenessLine(flags)
    if line then ad:sayText(line) end
  end
end

function Hit.effectivenessLine(flags)
  if not flags then return nil end
  if flags.super then return "STRINGID_SUPEREFFECTIVE" end
  if flags.notVery then return "STRINGID_NOTVERYEFFECTIVE" end
  return nil
end

-- pokefirered/src/battle_script_commands.c:6857
local function multi_hit_count(M)
  local ad = M.adapter
  local r = roll(ad, 0, 3)
  if r > 1 then return roll(ad, 0, 3) % 4 + 2 end
  return r + 2
end

local function field_sport(M, key)
  for _, b in ipairs(M.adapter:activeBattlers()) do
    if b[key] and not M.adapter:isFainted(b) then return true end
  end
  return M.st and M.st[key == "mudSport" and "expMudSport" or "expWaterSport"] and true or false
end

local MOVE_TARGET_BOTH = 8

local function calc_opts(M, extra)
  local ad, target = M.adapter, M.target
  local defSide = ad:ownSide(target)
  local st = M.st
  local twoDef = false
  if st and st.double and target then
    local State = require("src.core.game3.battle.state")
    twoDef = State.countPresentOnSide(st, target.side) == 2
  end
  local o = {
    doubleScreens = twoDef,
    spread = twoDef and tonumber(M.move and M.move.target) == MOVE_TARGET_BOTH,
    rng = ad:rng(),
    weather = Rules.weather.effective(M.st, ad),
    adapter = ad,
    dmgMultiplier = M.dmgMultiplier,
    reflect = defSide and (defSide.expReflectTurns or 0) > 0,
    lightScreen = defSide and (defSide.expLightScreenTurns or 0) > 0,
    mudSport = field_sport(M, "mudSport"),
    waterSport = field_sport(M, "waterSport"),
    pursuitSwitch = M.opts.pursuitSwitch,
  }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

local function dream_eater_blocked(M)
  local ad, target = M.adapter, M.target
  return (target.substituteHP or 0) > 0 or ad:status(target) ~= "SLP"
end

local function fail(M, id, fill)
  M:attackString()
  M:ppReduce()
  M.failed = true
  M.anim.missed = true
  if id then M.adapter:sayText(id, fill) else M.adapter:sayFail() end
end

local function pre_checks(M)
  local ad, user, target, eff = M.adapter, M.user, M.target, M.effect
  if eff == E.FAKE_OUT and (user.isFirstTurn or 0) <= 0 then
    fail(M)
    return true
  end
  if eff == E.DREAM_EATER and dream_eater_blocked(M) then
    -- pokefirered/data/battle_scripts_1.s:427
    fail(M, "STRINGID_PKMNWASNTAFFECTED", { def = target })
    return true
  end
  if eff == E.COUNTER or eff == E.MIRROR_COAT then
    -- pokefirered/src/battle_script_commands.c:7568
    local taken = (eff == E.COUNTER) and user.lastPhysicalDamageTaken or user.lastSpecialDamageTaken
    local foe = ad:foeOf(user)
    if M.st and M.st.double then
      local State = require("src.core.game3.battle.state")
      local src = (eff == E.COUNTER) and user.lastPhysicalById or user.lastSpecialById
      foe = src ~= nil and State.battler(M.st, src) or nil
      if foe and src % 2 == State.idOf(user) % 2 then foe = nil end
      if foe and ad:hp(foe) > 0 then
        local Engine = require("src.core.game3.battle.engine")
        local fm = Engine.followMeId(M.st, ad, user)
        local fb = fm ~= nil and State.battler(M.st, fm) or nil
        if fb and ad:hp(fb) > 0 then foe = fb end
      end
    end
    if not taken or taken <= 0 or not foe or ad:isFainted(foe)
        or (user.expHurtBy and user.expHurtBy == user.side) then
      fail(M)
      return true
    end
    M.target = foe
    M.tname = ad:displayName(foe)
  end
  if eff == E.SNORE then
    if ad:status(user) ~= "SLP" then
      fail(M)
      return true
    end
    if not (M.opts.called and M.opts.calledBy and Moves.get(M.opts.calledBy).effect == E.SLEEP_TALK) then
      ad:sayText("STRINGID_PKMNFASTASLEEP", { atk = user })
      ad:statusAnim(user, "SLP")
    end
  end
  if eff == E.ENDEAVOR and ad:hp(target) <= ad:hp(user) then
    fail(M)
    return true
  end
  if eff == E.SPIT_UP and M:isProtected() then
    M:attackString()
    M:ppReduce()
    if (user.expStockpile or 0) <= 0 then
      ad:sayText("STRINGID_FAILEDTOSPITUP")
    else
      user.expStockpile = 0
      ad:sayText("STRINGID_PKMNPROTECTEDITSELF", { def = M.target })
    end
    M.anim.missed = true
    return true
  end
  if eff == E.EXPLOSION and not M.explosionStarted then
    for _, b in ipairs(ad:activeBattlers()) do
      if ad:abilityOf(b) == "DAMP" then
        M.stopTargets = true
        M:attackString()
        M:ppReduce()
        ad:sayText("STRINGID_PKMNPREVENTSUSAGE", {
          def = b, defAbility = H.abilityId("DAMP"), atk = user, currentMove = M.mnum,
        })
        M.failed = true
        return true
      end
    end
  end
  return false
end

local function set_multipliers(M)
  local target, eff = M.target, M.effect
  local semi = target and target.semiInvulnerable
  M.dmgMultiplier = 1
  if eff == E.GUST or eff == E.TWISTER then
    if semi == "ON_AIR" then M.ignoreOnAir = true; M.dmgMultiplier = 2 end
  elseif eff == E.EARTHQUAKE or eff == E.MAGNITUDE then
    if semi == "UNDERGROUND" then M.ignoreUnderground = true; M.dmgMultiplier = 2 end
  elseif (eff == E.HIT and M.mnum == MOVE_SURF) or (eff == E.TRAP and M.mnum == MOVE_WHIRLPOOL) then
    if semi == "UNDERWATER" then M.ignoreUnderwater = true; M.dmgMultiplier = 2 end
  elseif eff == E.FLINCH_MINIMIZE_HIT then
    if target.minimized then M.dmgMultiplier = 2 end
  elseif eff == E.THUNDER or eff == E.SKY_UPPERCUT then
    M.ignoreOnAir = true
  end
end

local function crash_damage(M)
  -- pokefirered/data/battle_scripts_1.s:848
  local ad, user, target = M.adapter, M.user, M.target
  local _, flags = Types.typeCalc(M.move.type, target.type1, target.type2, nil, target.expIdentified)
  if flags.immune and M.missReason ~= "protected" then return end
  ad:sayText("STRINGID_PKMNCRASHED", { atk = user })
  local dmg = Damage.calc(user, target, M.move, calc_opts(M, { forceCrit = false }))
  dmg = math.floor(dmg / 2)
  if dmg == 0 then dmg = 1 end
  local cap = math.floor(ad:maxHp(target) / 2)
  if cap < dmg then dmg = cap end
  ad:applyHpLoss(user, dmg)
  M:tryFaintUser()
end

local function on_miss(M)
  local user, eff = M.user, M.effect
  M.anim.missed = true
  M.noEffect = true
  if eff == E.RECOIL_IF_MISS and M.missReason ~= "absorbed" then crash_damage(M) end
  if eff == E.RAGE then user.rage = nil end
  if eff == E.ROLLOUT then
    local Engine = require("src.core.game3.battle.engine")
    Engine.cancelMultiTurnMoves(user)
  end
  if eff == E.FURY_CUTTER then user.expFuryCutter = 0 end
  if eff == E.SEMI_INVULNERABLE then
    user.semiInvulnerable = nil
    user.onAir, user.underground, user.underwater = nil, nil, nil
  end
end

local function flags_immune(M, info)
  local ad, target = M.adapter, M.target
  local mt = tonumber(info and info.moveType) or tonumber(M.moveType or M.move.type)
  if ad:abilityOf(target) == "LEVITATE" and mt == Types.ID.GROUND then
    ad:sayText("STRINGID_PKMNMAKESGROUNDMISS", { def = target, defAbility = H.abilityId("LEVITATE") })
    return true
  end
  if info and info.effectiveness == 0 then
    ad:sayText("STRINGID_ITDOESNTAFFECT", { def = target })
    return true
  end
  return false
end

local function wonder_guard(M, info)
  local ad = M.adapter
  if ad:abilityOf(M.target) ~= "WONDER_GUARD" then return false end
  local f = info and info.typeFlags or {}
  if f.super and not f.notVery then return false end
  ad:sayText("STRINGID_AVOIDEDDAMAGE", { def = M.target, defAbility = H.abilityId("WONDER_GUARD") })
  return true
end

local function secondary_after(M)
  local eff = M.effect
  if M.noEffect then return end
  local spec = E.SECONDARY[eff]
  if eff == E.SMELLINGSALT and M.hitSubstitute then spec = nil end
  if eff == E.SECRET_POWER then
    local Engine = require("src.core.game3.battle.engine")
    local name = E.SECRET_POWER_BY_TERRAIN[Engine.terrainOf(M.st)] or "PARALYSIS"
    spec = { eff = name }
  end
  if M.extraEffect then spec = M.extraEffect end
  if spec then
    Secondary.withChance(M, spec.eff, spec.certain, spec.user)
  end
  if eff == E.RAMPAGE and M.startRampage then
    Secondary.set(M, "THRASH", false, true, true)
  end
  if M.move.afterHit and not spec and M.move.afterHit.kind == "recoil" then
    Secondary.set(M, "RECOIL_25", false, true, true)
  end
end

local function drain(M)
  -- pokefirered/data/battle_scripts_1.s:325
  local ad, user, target = M.adapter, M.user, M.target
  if M.noEffect then return end
  local heal = math.floor((M.hpDealt or 0) / 2)
  if heal == 0 then heal = 1 end
  if M.effect == E.ABSORB and ad:abilityOf(target) == "LIQUID_OOZE" then
    ad:applyHpLoss(user, heal)
    ad:sayText("STRINGID_ITSUCKEDLIQUIDOOZE")
    M:tryFaintUser()
    return
  end
  ad:heal(user, heal)
  if M.effect == E.DREAM_EATER then
    ad:sayText("STRINGID_PKMNDREAMEATEN", { def = target })
  else
    ad:sayText("STRINGID_PKMNENERGYDRAINED", { def = target })
  end
end

-- pokefirered/src/battle_script_commands.c:8238
local function present(M)
  local ad, target = M.adapter, M.target
  local r = roll(ad, 0, 255)
  if r < 102 then return 40 end
  if r < 178 then return 80 end
  if r < 204 then return 120 end
  if ad:hp(target) >= ad:maxHp(target) then
    ad:sayText("STRINGID_PKMNHPFULL", { def = target })
    return nil
  end
  M:attackAnimation()
  local heal = math.max(1, math.floor(ad:maxHp(target) / 4))
  ad:heal(target, heal)
  ad:sayText("STRINGID_PKMNREGAINEDHEALTH", { def = target })
  return nil
end

-- pokefirered/src/battle_script_commands.c:8161
local function rollout_power(M)
  local user = M.user
  if (user.expRolloutTimer or 0) <= 0 then
    user.expRolloutTimer = 5
    user.expLockedMove = M.moveId
    user.expLockedSlot = M.slot
  end
  user.expRolloutTimer = user.expRolloutTimer - 1
  if user.expRolloutTimer == 0 then
    user.expLockedMove = nil
    user.expLockedSlot = nil
  end
  local power = tonumber(M.move.power) or 30
  for _ = 1, (5 - user.expRolloutTimer) - 1 do power = power * 2 end
  if user.defenseCurl then power = power * 2 end
  return power
end

-- pokefirered/src/battle_script_commands.c:8205
local function fury_cutter_power(M)
  local user = M.user
  local c = user.expFuryCutter or 0
  if c ~= 5 then c = c + 1 end
  user.expFuryCutter = c
  local power = tonumber(M.move.power) or 10
  for _ = 1, c - 1 do power = power * 2 end
  return power
end

-- pokefirered/src/battle_script_commands.c:1209
local function damage_calc(M, target, calcOpts)
  if not ModRuntime.wantsHook("battle.damage") then
    return Damage.calc(M.user, target, M.move, calcOpts)
  end
  local G3 = require("src.mods.Gen3Compat")
  local view = G3.moveView(M.move)
  local vanillaInfo
  local dmg, info = ModRuntime.call("battle.damage", function(c)
    local d, i = Damage.calc(c.user, c.target, M.move, c.opts)
    vanillaInfo = i
    return d, i
  end, { battle = M.st, user = M.user, target = target, move = view,
         moveId = view and view.id, moveNum = M.mnum, opts = calcOpts,
         rng = calcOpts and calcOpts.rng })
  if type(info) ~= "table" then
    info = vanillaInfo or {
      move = M.move, effectiveness = 1, critical = false,
      moveType = tonumber(M.move.type), power = tonumber(M.move.power),
      typeFlags = { super = false, notVery = false, immune = false },
    }
  end
  return math.max(0, math.floor(tonumber(dmg) or 0)), info
end

local function hit_once(M, opts)
  local ad, user, target = M.adapter, M.user, M.target
  opts = opts or {}
  local dmg, info = damage_calc(M, target, calc_opts(M, opts.calc))
  M.moveType = info.moveType or M.moveType
  if info.failed then
    M.failed = true
    ad:sayFail()
    return nil, info, "fail"
  end
  if flags_immune(M, info) then
    M.noEffect = true
    M.anim.missed = true
    return nil, info, "immune"
  end
  if wonder_guard(M, info) then
    M.noEffect = true
    M.anim.missed = true
    return nil, info, "immune"
  end
  local hung
  dmg, hung = Hit.adjustDamage(M, target, dmg)
  if opts.onBeforeAnim then opts.onBeforeAnim() end
  M._animDmg, M._animPower = dmg, info.power
  M:attackAnimation(nil, opts.multihitLeft)
  if opts.onAfterAnim then opts.onAfterAnim() end
  Hit.dealDamage(M, dmg, info)
  if info.critical then ad:sayText("STRINGID_CRITICALHIT") end
  if M.anim.effectiveness == nil then M.anim.effectiveness = info.effectiveness or 1 end
  return dmg, info, hung or "ok"
end

function Hit.run(M)
  local ad, user, eff = M.adapter, M.user, M.effect
  M.moveType = tonumber(M.move.type)

  if pre_checks(M) then return end
  set_multipliers(M)

  if (eff == E.RAMPAGE and (user.expRampageTurns or 0) > 0)
      or (eff == E.UPROAR and (user.expUproarTurns or 0) > 0)
      or (eff == E.ROLLOUT and (user.expRolloutTimer or 0) > 0) then
    M.noPP = true
  end
  if eff == E.RAMPAGE and (user.expRampageTurns or 0) <= 0 then M.startRampage = true end

  if eff == E.EXPLOSION then
    -- pokefirered/data/battle_scripts_1.s:376
    M:attackString()
    M:ppReduce()
    M.explosionStarted = true
    ad:setHp(user, 0)
    local dmg, info = damage_calc(M, M.target, calc_opts(M))
    if not M:accuracyCheck("normal", true) then
      M.anim.missed = true
      M.noEffect = true
      if not M.deferUserFaint then M:tryFaintUser() end
      return
    end
    if flags_immune(M, info) then
      M.noEffect = true
      if not M.deferUserFaint then M:tryFaintUser() end
      return
    end
    local target = M.target
    local hung
    dmg, hung = Hit.adjustDamage(M, target, dmg)
    M:attackAnimation()
    Hit.dealDamage(M, dmg, info)
    if info.critical then ad:sayText("STRINGID_CRITICALHIT") end
    M.anim.effectiveness = info.effectiveness
    if hung == "endured" then ad:sayText("STRINGID_PKMNENDUREDHIT", { def = target })
    elseif hung == "hung" then HeldItems.focusBandMessage(ad, target)
    else
      local line = Hit.effectivenessLine(info.typeFlags)
      if line then ad:sayText(line) end
    end
    M:tryFaintTarget()
    if not M.deferUserFaint then M:tryFaintUser() end
    return
  end

  M:attackString()
  M:ppReduce()

  local magnitude = M.magnitude
  if eff == E.MAGNITUDE and not magnitude then
    local r = roll(ad, 0, 99)
    local _, info = Damage.calc(user, M.target, M.move, calc_opts(M, { magnitudeRoll = r, forceCrit = false, noRandom = true }))
    magnitude = { power = info.power, value = info.magnitude }
    M.magnitude = magnitude
    ad:sayText("STRINGID_MAGNITUDESTRENGTH", { buff1 = tostring(magnitude.value) })
  end

  if eff == E.TRIPLE_KICK then return Hit.tripleKick(M) end
  if eff == E.BEAT_UP then return Hit.beatUp(M) end

  if not M:accuracyCheck("normal", true) then
    on_miss(M)
    return
  end

  if eff == E.SEMI_INVULNERABLE then
    user.semiInvulnerable = nil
    user.onAir, user.underground, user.underwater = nil, nil, nil
  end

  if eff == E.RAGE then user.rage = true end

  local target = M.target
  local calcExtra = {}
  if magnitude then calcExtra.power = magnitude.power end

  if eff == E.ROLLOUT then
    local _, f = Types.typeCalc(M.move.type, target.type1, target.type2, nil, target.expIdentified)
    if f.immune then
      local Engine = require("src.core.game3.battle.engine")
      Engine.cancelMultiTurnMoves(user)
      ad:sayText("STRINGID_ITDOESNTAFFECT", { def = target })
      M.noEffect = true
      return
    end
    calcExtra.power = rollout_power(M)
  elseif eff == E.FURY_CUTTER then
    calcExtra.power = fury_cutter_power(M)
  elseif eff == E.PRESENT then
    local p = present(M)
    if not p then return end
    calcExtra.power = p
  elseif eff == E.SPIT_UP then
    -- pokefirered/src/battle_script_commands.c:6586
    local n = user.expStockpile or 0
    if n <= 0 then
      ad:sayText("STRINGID_FAILEDTOSPITUP")
      M.failed = true
      return
    end
    user.expStockpile = 0
    local ok, Stats = pcall(require, "src.core.game3.battle.effects.stats")
    if ok and Stats and Stats.clearStockpileBoost then Stats.clearStockpileBoost(user) end
    local base = Damage.base(user, target, M.move, {
      adapter = ad, weatherKind = Rules.weather.effective(M.st, ad),
      reflect = calc_opts(M).reflect, lightScreen = calc_opts(M).lightScreen,
      doubleScreens = calc_opts(M).doubleScreens,
    }) * n
    -- pokefirered/src/battle_script_commands.c:6603
    if user.expHelpingHand then base = math.floor(base * 15 / 10) end
    local aT1, aT2 = user.type1, user.type2
    if aT1 == tonumber(M.move.type) or aT2 == tonumber(M.move.type) then base = math.floor(base * 15 / 10) end
    local dmg, flags = Types.typeCalc(M.move.type, target.type1, target.type2, base, target.expIdentified)
    if flags.immune then
      ad:sayText("STRINGID_ITDOESNTAFFECT", { def = target })
      M.noEffect = true
      return
    end
    Hit.applySetDamage(M, dmg, flags)
    M:tryFaintTarget()
    return
  elseif eff == E.BRICK_BREAK then
    local side = ad:ownSide(target)
    if side and ((side.expReflectTurns or 0) > 0 or (side.expLightScreenTurns or 0) > 0) then
      side.expReflectTurns = nil
      side.expLightScreenTurns = nil
      M.brokeWall = true
    end
  end

  local fixed = eff == E.DRAGON_RAGE or eff == E.SONICBOOM or eff == E.LEVEL_DAMAGE
    or eff == E.SUPER_FANG or eff == E.PSYWAVE or eff == E.ENDEAVOR
  local setDmg = fixed or eff == E.COUNTER or eff == E.MIRROR_COAT

  local nHits = 1
  local isMulti = false
  if eff == E.MULTI_HIT then nHits = multi_hit_count(M); isMulti = true
  elseif eff == E.DOUBLE_HIT or eff == E.TWINEEDLE then nHits = 2; isMulti = true
  elseif type(M.move.hits) == "table" then nHits = multi_hit_count(M); isMulti = true
  elseif tonumber(M.move.hits) then nHits = tonumber(M.move.hits); isMulti = nHits > 1 end

  local landed = 0
  local lastInfo, lastStatus
  for i = 1, nHits do
    if ad:isFainted(user) or ad:isFainted(target) then break end
    if isMulti and i > 1 and ad:status(user) == "SLP" and not (M.opts.calledBy and move_is_sleep_talk(M.opts.calledBy)) then break end
    local _, info, status = hit_once(M, {
      calc = calcExtra,
      multihitLeft = isMulti and (nHits - i + 1) or 0,
      onAfterAnim = (i == 1 and M.brokeWall) and function() ad:sayText("STRINGID_THEWALLSHATTERED") end or nil,
    })
    lastInfo, lastStatus = info, status
    if status ~= "ok" and status ~= "endured" and status ~= "hung" then break end
    landed = landed + 1
    if status == "endured" then
      ad:sayText("STRINGID_PKMNENDUREDHIT", { def = target })
      break
    end
    if status == "hung" then
      HeldItems.focusBandMessage(ad, target)
    elseif not isMulti then
      local f = info.typeFlags
      if setDmg and not (eff == E.COUNTER or eff == E.MIRROR_COAT) then f = nil end
      local line = Hit.effectivenessLine(f)
      if line then ad:sayText(line) end
    end
  end
  if isMulti and landed > 0 then
    if lastStatus ~= "endured" and lastStatus ~= "hung" then
      local line = Hit.effectivenessLine(lastInfo and lastInfo.typeFlags)
      if line then ad:sayText(line) end
    end
    ad:sayText("STRINGID_HITXTIMES", { buff1 = tostring(landed) })
  end
  if landed == 0 then
    M.noEffect = true
    if eff == E.ROLLOUT then
      local Engine = require("src.core.game3.battle.engine")
      Engine.cancelMultiTurnMoves(user)
    end
    return
  end

  if eff == E.ABSORB or eff == E.DREAM_EATER then drain(M) end
  secondary_after(M)
  M:tryFaintTarget()
  if M.checkUserFaint then M:tryFaintUser() end
end

-- pokefirered/data/battle_scripts_1.s:1380
function Hit.tripleKick(M)
  local ad, user, target = M.adapter, M.user, M.target
  local power = 0
  local landed = 0
  local lastInfo
  for i = 1, 3 do
    if ad:isFainted(user) then break end
    if ad:isFainted(target) then break end
    if ad:status(user) == "SLP" and not (M.opts.calledBy and move_is_sleep_talk(M.opts.calledBy)) then break end
    if not M:accuracyCheck("normal", landed == 0) then
      if landed == 0 then on_miss(M) end
      break
    end
    power = power + 10
    local _, info, status = hit_once(M, { calc = { power = power }, multihitLeft = 4 - i })
    lastInfo = info
    if status ~= "ok" and status ~= "endured" and status ~= "hung" then break end
    landed = landed + 1
    if status == "endured" then
      ad:sayText("STRINGID_PKMNENDUREDHIT", { def = target })
      break
    end
    if status == "hung" then HeldItems.focusBandMessage(ad, target) end
  end
  if landed > 0 then
    local line = Hit.effectivenessLine(lastInfo and lastInfo.typeFlags)
    if line then ad:sayText(line) end
    ad:sayText("STRINGID_HITXTIMES", { buff1 = tostring(landed) })
    M:tryFaintTarget()
  end
end

-- pokefirered/src/battle_script_commands.c:8601
local function speciesInfoStats(Pokemon, sp)
  local meta = Pokemon.speciesMeta and Pokemon.speciesMeta(sp)
  local row = meta and meta.linkStats
  if type(row) == "table" and #row >= 6 then return { atk = row[2], def = row[3] } end
  return Pokemon.stats(sp)
end

-- pokefirered/src/battle_script_commands.c:8571
function Hit.beatUp(M)
  local ad, user, target = M.adapter, M.user, M.target
  if not M:accuracyCheck("normal", true) then
    on_miss(M)
    return
  end
  local Pokemon = require("src.core.game3.pokemon")
  local party = ad:partyMons(user)
  local any = false
  for i, mon in ipairs(party) do
    if ad:isFainted(target) then break end
    local hp = tonumber(mon and mon.hp) or 0
    local status = mon and mon.status
    if i == user.partyIndex then
      hp = ad:hp(user)
      status = ad:status(user)
    end
    if mon and hp > 0 and (mon.species or 0) ~= 0 and not mon.isEgg and (status == nil or status == 0) then
      any = true
      local sp = tonumber(mon.species) or 0
      local aBase = speciesInfoStats(Pokemon, sp)
      local dBase = speciesInfoStats(Pokemon, tonumber(target.species) or 0)
      local atk = aBase and aBase.atk or 50
      local def = dBase and dBase.def or 50
      local lvl = tonumber(mon.level) or 1
      local dmg = atk * (tonumber(M.move.power) or 10) * (math.floor(lvl * 2 / 5) + 2)
      dmg = math.floor(dmg / math.max(1, def))
      dmg = math.floor(dmg / 50) + 2
      -- pokefirered/src/battle_script_commands.c:8606
      if user.expHelpingHand then dmg = math.floor(dmg * 15 / 10) end
      local name = (mon.nickname and mon.nickname ~= "") and mon.nickname or Pokemon.name(sp)
      -- src/battle_script_commands.c:8597
      ad:sayText("STRINGID_PKMNATTACK", { buff1 = require("src.core.game3.battle.state").prefixedName(M.st, user, name) })
      local crit = Rules.crit.roll(user, M.move, nil, ad:rng(), M.st)
      if crit then dmg = dmg * 2 end
      local r = roll(ad, 85, 100)
      dmg = math.floor(dmg * r / 100)
      if dmg == 0 then dmg = 1 end
      local hung
      dmg, hung = Hit.adjustDamage(M, target, dmg)
      M:attackAnimation()
      Hit.dealDamage(M, dmg, { physical = false })
      if crit then ad:sayText("STRINGID_CRITICALHIT") end
      if hung == "endured" then ad:sayText("STRINGID_PKMNENDUREDHIT", { def = target })
      elseif hung == "hung" then HeldItems.focusBandMessage(ad, target) end
      M:tryFaintTarget()
    end
  end
  if not any then
    M.failed = true
    ad:sayFail()
  end
end

return Hit
