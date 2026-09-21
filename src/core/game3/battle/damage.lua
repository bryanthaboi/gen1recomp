-- Gen3-shaped damage formula (owned game3 battle).

local Rules = require("src.core.game3.battle.rules")
local Types = require("src.core.game3.battle.types")
local Moves = require("src.core.game3.battle.moves")
local EffectIds = require("src.core.game3.battle.effect_ids")
local ModRuntime = require("src.mods.Runtime")

local Damage = {}

-- pokefirered/src/pokemon.c:1442
local STAGE_RATIO = {
  [-6] = { 10, 40 }, [-5] = { 10, 35 }, [-4] = { 10, 30 }, [-3] = { 10, 25 },
  [-2] = { 10, 20 }, [-1] = { 10, 15 }, [0] = { 10, 10 }, [1] = { 15, 10 },
  [2] = { 20, 10 }, [3] = { 25, 10 }, [4] = { 30, 10 }, [5] = { 35, 10 }, [6] = { 40, 10 },
}

local function clamp_stage(s)
  s = math.floor(tonumber(s) or 0)
  if s < -6 then return -6 end
  if s > 6 then return 6 end
  return s
end

function Damage.stageMul(stage)
  local r = STAGE_RATIO[clamp_stage(stage)]
  return r[1] / r[2]
end

-- pokefirered/src/pokemon.c:2374
function Damage.applyStage(stat, stage)
  local r = STAGE_RATIO[clamp_stage(stage)]
  return math.floor((tonumber(stat) or 0) * r[1] / r[2])
end

local function mon_stat(mon, key, fallback)
  if not mon then return fallback end
  local v = mon[key]
  if v == nil and key == "spAtk" then v = mon.spa or mon.specialAttack end
  if v == nil and key == "spDef" then v = mon.spd or mon.specialDefense end
  if v == nil and key == "attack" then v = mon.atk end
  if v == nil and key == "defense" then v = mon.def end
  if v == nil and key == "speed" then v = mon.spe end
  return tonumber(v) or fallback
end
Damage.monStat = mon_stat

--- Fill missing battle stats from extracted species base stats + IVs.
function Damage.ensureStats(mon, level)
  level = tonumber(level or mon and mon.level) or 5
  mon = mon or {}
  mon.level = level

  local Pokemon = require("src.core.game3.pokemon")
  local species = tonumber(mon.species or mon.speciesId)
  if species and Pokemon.stats and Pokemon.stats(species) then
    if not mon.ivs then
      mon.ivs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
    end
    if not mon.evs then
      mon.evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
    end
    if mon.personality == nil then mon.personality = 0 end
    local need = (not mon.maxHp or mon.maxHp <= 0)
      or (mon_stat(mon, "attack", 0) <= 0)
      or (mon_stat(mon, "defense", 0) <= 0)
      or (mon_stat(mon, "spAtk", 0) <= 0)
      or (mon_stat(mon, "spDef", 0) <= 0)
      or (mon_stat(mon, "speed", 0) <= 0)
    if need then
      local keepHp = mon.hp
      Pokemon.applyStats(mon)
      if keepHp ~= nil and keepHp >= 0 then
        mon.hp = math.min(keepHp, mon.maxHp)
      end
    end
    if not mon.ability and not mon.abilityId and Pokemon.abilityId then
      mon.ability = Pokemon.abilityId(species, mon.personality)
      mon.abilityId = mon.ability
    end
    return mon
  end

  local base = 50
  if not mon.maxHp or mon.maxHp <= 0 then
    mon.maxHp = math.floor(((2 * base) * level) / 100) + level + 10
  end
  if not mon.hp or mon.hp < 0 then mon.hp = mon.maxHp end
  if mon.hp > mon.maxHp then mon.hp = mon.maxHp end
  local function fill(key, b)
    if mon_stat(mon, key, 0) <= 0 then
      mon[key] = math.floor(((2 * b) * level) / 100) + 5
    end
  end
  fill("attack", 55)
  fill("defense", 50)
  fill("spAtk", 50)
  fill("spDef", 50)
  fill("speed", 50)
  return mon
end

local function roll_from(rng, lo, hi)
  if type(rng) == "function" then
    local ok, v = pcall(rng, lo, hi)
    if ok and type(v) == "number" then return v end
  end
  local okR, Rng = pcall(require, "src.core.game3.rng")
  if okR and Rng and Rng.compat then
    return Rng.compat(lo, hi)
  end
  return math.random(lo, hi)
end

local function ability_of(battler, adapter)
  if adapter and adapter.abilityOf then return adapter:abilityOf(battler) end
  if not battler then return nil end
  if battler.expTracedAbility then return battler.expTracedAbility end
  local id = battler.ability or (battler.mon and (battler.mon.ability or battler.mon.abilityId))
  if type(id) == "string" then return (id:upper():gsub("%s+", "_")) end
  local ok, Adapter = pcall(require, "src.core.game3.battle.adapter")
  if ok and Adapter and Adapter.ABILITY_BY_ID and tonumber(id) then return Adapter.ABILITY_BY_ID[tonumber(id)] end
  return nil
end

local function status_of(battler)
  local s = battler and (battler.status or (battler.mon and battler.mon.status))
  if s == 0 then return nil end
  return s
end

-- pokefirered/src/battle_script_commands.c:8503
function Damage.hiddenPower(mon)
  local iv = mon and (mon.ivs or mon.dvs) or {}
  local function g(k1, k2) return math.floor(tonumber(iv[k1] or iv[k2]) or 0) end
  local hp, atk, def = g("hp", "HP"), g("atk", "attack"), g("def", "defense")
  local spe, spa, spd = g("spe", "speed"), g("spa", "spAtk"), g("spd", "spDef")
  local function b(v, bit) return math.floor(v / bit) % 2 end
  local powerBits = b(hp, 2) + 2 * b(atk, 2) + 4 * b(def, 2) + 8 * b(spe, 2) + 16 * b(spa, 2) + 32 * b(spd, 2)
  local typeBits = b(hp, 1) + 2 * b(atk, 1) + 4 * b(def, 1) + 8 * b(spe, 1) + 16 * b(spa, 1) + 32 * b(spd, 1)
  local power = math.floor(40 * powerBits / 63) + 30
  local t = math.floor(15 * typeBits / 63) + 1
  if t >= 9 then t = t + 1 end
  return power, t
end

-- pokefirered/src/battle_script_commands.c:7928
function Damage.flailPower(hp, maxHp)
  hp = tonumber(hp) or 1
  maxHp = math.max(1, tonumber(maxHp) or 1)
  local n = math.floor(hp * 48 / maxHp)
  if n == 0 and hp > 0 then n = 1 end
  if n <= 1 then return 200 end
  if n <= 4 then return 150 end
  if n <= 9 then return 100 end
  if n <= 16 then return 80 end
  if n <= 32 then return 40 end
  return 20
end

-- pokefirered/src/battle_script_commands.c:9074
function Damage.lowKickPower(dMon, defender)
  local wt
  if dMon and dMon.weight then
    wt = tonumber(dMon.weight) or 0
  else
    local Pokemon = require("src.core.game3.pokemon")
    local sp = (defender and defender.species) or Pokemon.speciesOf(dMon)
    local dex = sp and Pokemon.dexEntry(sp)
    wt = dex and tonumber(dex.weight) or 0
  end
  local tbl = { { 100, 20 }, { 250, 40 }, { 500, 60 }, { 1000, 80 }, { 2000, 100 } }
  for _, row in ipairs(tbl) do
    if row[1] > wt then return row[2] end
  end
  return 120
end

-- pokefirered/src/pokemon.c:2385
function Damage.base(attacker, defender, move, opts)
  opts = opts or {}
  local aMon = attacker.mon or attacker
  local dMon = defender.mon or defender
  local power = tonumber(opts.power) or tonumber(move.power) or 0
  local moveType = tonumber(opts.moveType) or tonumber(move.type) or 0
  local crit = opts.crit and true or false
  local adapter = opts.adapter

  local attack = mon_stat(aMon, "attack", 50)
  local defense = mon_stat(dMon, "defense", 50)
  local spAttack = mon_stat(aMon, "spAtk", 50)
  local spDefense = mon_stat(dMon, "spDef", 50)
  if attacker.expTransform then
    local t = attacker.expTransform
    attack, spAttack = t.attack or attack, t.spAtk or spAttack
  end
  if defender.expTransform then
    local t = defender.expTransform
    defense, spDefense = t.defense or defense, t.spDef or spDefense
  end

  local aAb = ability_of(attacker, adapter)
  local dAb = ability_of(defender, adapter)
  if aAb == "HUGE_POWER" or aAb == "PURE_POWER" then attack = attack * 2 end
  local st = adapter and adapter._st
  local Engine = package.loaded["src.core.game3.battle.engine"]
  if st and Engine and Engine.hasBadge then
    if attacker.side == "player" and Engine.hasBadge(st, 1) then attack = math.floor(110 * attack / 100) end
    if defender.side == "player" and Engine.hasBadge(st, 5) then defense = math.floor(110 * defense / 100) end
    if attacker.side == "player" and Engine.hasBadge(st, 7) then spAttack = math.floor(110 * spAttack / 100) end
    if defender.side == "player" and Engine.hasBadge(st, 7) then spDefense = math.floor(110 * spDefense / 100) end
  end
  local HeldItems = require("src.core.game3.battle.held_items")
  local HOLD = HeldItems.HOLD
  local aHe, aParam = HeldItems.of(attacker)
  local dHe = HeldItems.of(defender)
  if HeldItems.TYPE_BOOST[aHe] == moveType then
    if Types.isPhysical(moveType) then
      attack = math.floor(attack * (aParam + 100) / 100)
    else
      spAttack = math.floor(spAttack * (aParam + 100) / 100)
    end
  end
  local aSp = tonumber(attacker.species or aMon.species) or 0
  local dSp = tonumber(defender.species or dMon.species) or 0
  if aHe == HOLD.CHOICE_BAND then attack = math.floor(150 * attack / 100) end
  if aHe == HOLD.SOUL_DEW and (aSp == 407 or aSp == 408) then spAttack = math.floor(150 * spAttack / 100) end
  if dHe == HOLD.SOUL_DEW and (dSp == 407 or dSp == 408) then spDefense = math.floor(150 * spDefense / 100) end
  if aHe == HOLD.DEEP_SEA_TOOTH and aSp == 373 then spAttack = spAttack * 2 end
  if dHe == HOLD.DEEP_SEA_SCALE and dSp == 373 then spDefense = spDefense * 2 end
  if aHe == HOLD.LIGHT_BALL and aSp == 25 then spAttack = spAttack * 2 end
  if dHe == HOLD.METAL_POWDER and dSp == 132 then defense = defense * 2 end
  if aHe == HOLD.THICK_CLUB and (aSp == 104 or aSp == 105) then attack = attack * 2 end
  if dAb == "THICK_FAT" and (moveType == Types.ID.FIRE or moveType == Types.ID.ICE) then
    spAttack = math.floor(spAttack / 2)
  end
  if aAb == "HUSTLE" then attack = math.floor(150 * attack / 100) end
  if (aAb == "PLUS" or aAb == "MINUS") and adapter and adapter.activeBattlers then
    local want = (aAb == "PLUS") and "MINUS" or "PLUS"
    for _, b in ipairs(adapter:activeBattlers()) do
      if ability_of(b, adapter) == want then spAttack = math.floor(150 * spAttack / 100); break end
    end
  end
  if aAb == "GUTS" and status_of(attacker) then attack = math.floor(150 * attack / 100) end
  if dAb == "MARVEL_SCALE" and status_of(defender) then defense = math.floor(150 * defense / 100) end
  if moveType == Types.ID.ELECTRIC and opts.mudSport then power = math.floor(power / 2) end
  if moveType == Types.ID.FIRE and opts.waterSport then power = math.floor(power / 2) end
  local aHp = tonumber(aMon.hp) or 0
  local aMax = math.max(1, tonumber(aMon.maxHp) or 1)
  local pinch = aHp <= math.floor(aMax / 3)
  if pinch and ((moveType == Types.ID.GRASS and aAb == "OVERGROW")
      or (moveType == Types.ID.FIRE and aAb == "BLAZE")
      or (moveType == Types.ID.WATER and aAb == "TORRENT")
      or (moveType == Types.ID.BUG and aAb == "SWARM")) then
    power = math.floor(150 * power / 100)
  end

  if tonumber(move.effect) == EffectIds.EXPLOSION then
    defense = math.floor(defense / 2)
  end

  local aStages = attacker.stages or {}
  local dStages = defender.stages or {}
  local level = tonumber(aMon.level or attacker.level) or 5
  local levelFactor = math.floor(2 * level / 5) + 2
  local damage = 0

  if Types.isPhysical(moveType) then
    local atkStage = aStages.attack or 0
    if crit and atkStage <= 0 then atkStage = 0 end
    damage = Damage.applyStage(attack, atkStage)
    damage = damage * power
    damage = damage * levelFactor
    local defStage = dStages.defense or 0
    if crit and defStage >= 0 then defStage = 0 end
    local helper = math.max(1, Damage.applyStage(defense, defStage))
    damage = math.floor(damage / helper)
    damage = math.floor(damage / 50)
    if status_of(attacker) == "BRN" and aAb ~= "GUTS" then damage = math.floor(damage / 2) end
    if opts.reflect and not crit then
      if opts.doubleScreens then
        damage = 2 * math.floor(damage / 3)
      else
        damage = math.floor(damage / 2)
      end
    end
    -- pokefirered/src/pokemon.c:2552
    if opts.spread then damage = math.floor(damage / 2) end
    if damage == 0 then damage = 1 end
  end

  if moveType == Types.ID.MYSTERY then damage = 0 end

  if not Types.isPhysical(moveType) and moveType ~= Types.ID.MYSTERY then
    local atkStage = aStages.spAtk or 0
    if crit and atkStage <= 0 then atkStage = 0 end
    damage = Damage.applyStage(spAttack, atkStage)
    damage = damage * power
    damage = damage * levelFactor
    local defStage = dStages.spDef or 0
    if crit and defStage >= 0 then defStage = 0 end
    local helper = math.max(1, Damage.applyStage(spDefense, defStage))
    damage = math.floor(damage / helper)
    damage = math.floor(damage / 50)
    if opts.lightScreen and not crit then
      if opts.doubleScreens then
        damage = 2 * math.floor(damage / 3)
      else
        damage = math.floor(damage / 2)
      end
    end
    -- pokefirered/src/pokemon.c:2604
    if opts.spread then damage = math.floor(damage / 2) end
    local weather = opts.weatherKind
    if weather == "RAIN" then
      if moveType == Types.ID.FIRE then damage = math.floor(damage / 2)
      elseif moveType == Types.ID.WATER then damage = math.floor(15 * damage / 10) end
    end
    if (weather == "RAIN" or weather == "SAND" or weather == "HAIL") and opts.isSolarBeam then
      damage = math.floor(damage / 2)
    end
    if weather == "SUN" then
      if moveType == Types.ID.FIRE then damage = math.floor(15 * damage / 10)
      elseif moveType == Types.ID.WATER then damage = math.floor(damage / 2) end
    end
    if attacker.expFlashFire and moveType == Types.ID.FIRE then
      damage = math.floor(15 * damage / 10)
    end
  end

  return damage + 2
end

local function fixed_info(move, eff, flags, physical, extra)
  local info = {
    move = move,
    effectiveness = eff,
    critical = false,
    physical = physical,
    fixed = true,
    typeFlags = flags,
  }
  for k, v in pairs(extra or {}) do info[k] = v end
  return info
end

function Damage.calc(attacker, defender, moveId, opts)
  opts = opts or {}
  local move = type(moveId) == "table" and moveId.effect ~= nil and moveId or Moves.get(moveId)
  local aMon = attacker.mon or attacker
  local dMon = defender.mon or defender
  Damage.ensureStats(aMon, aMon.level)
  Damage.ensureStats(dMon, dMon.level)

  local effectByte = tonumber(move.effect)
  local power = tonumber(opts.power) or tonumber(move.power) or 0
  local moveType = tonumber(opts.moveType) or tonumber(move.type) or 0
  local dmgMultiplier = tonumber(opts.dmgMultiplier) or 1
  local magnitudeVal = nil
  local weatherKind = opts.weatherKind or Rules.weather.kind(opts.weather)
  local rng = opts.rng or math.random
  local level = tonumber(aMon.level or attacker.level) or 5

  if power <= 0 and not opts.power then
    return 0, { move = move, effectiveness = 1, critical = false, status = true }
  end

  if effectByte == EffectIds.MAGNITUDE and not opts.power then
    local r = opts.magnitudeRoll or roll_from(rng, 0, 99)
    -- pokefirered/src/battle_script_commands.c:8284
    if r < 5 then magnitudeVal, power = 4, 10
    elseif r < 15 then magnitudeVal, power = 5, 30
    elseif r < 35 then magnitudeVal, power = 6, 50
    elseif r < 65 then magnitudeVal, power = 7, 70
    elseif r < 85 then magnitudeVal, power = 8, 90
    elseif r < 95 then magnitudeVal, power = 9, 110
    else magnitudeVal, power = 10, 150 end
  elseif effectByte == EffectIds.RETURN and not opts.power then
    local friendship = tonumber(aMon.friendship or aMon.happiness) or 70
    power = math.floor(10 * friendship / 25)
  elseif effectByte == EffectIds.FRUSTRATION and not opts.power then
    local friendship = tonumber(aMon.friendship or aMon.happiness) or 70
    power = math.floor(10 * (255 - friendship) / 25)
  elseif effectByte == EffectIds.ERUPTION and not opts.power then
    local curHp = tonumber(aMon.hp) or 1
    local maxHp = math.max(1, tonumber(aMon.maxHp) or 1)
    power = math.floor(curHp * power / maxHp)
    if power == 0 then power = 1 end
  elseif effectByte == EffectIds.FLAIL and not opts.power then
    power = Damage.flailPower(aMon.hp, aMon.maxHp)
  elseif effectByte == EffectIds.LOW_KICK and not opts.power then
    power = Damage.lowKickPower(dMon, defender)
  elseif effectByte == EffectIds.HIDDEN_POWER and not opts.power then
    local p, t = Damage.hiddenPower(aMon)
    power = p
    if not opts.moveType then moveType = t end
  elseif effectByte == EffectIds.WEATHER_BALL and not opts.moveType then
    -- pokefirered/src/battle_script_commands.c:9345
    if weatherKind then
      dmgMultiplier = dmgMultiplier * 2
      if weatherKind == "RAIN" then moveType = Types.ID.WATER
      elseif weatherKind == "SAND" then moveType = Types.ID.ROCK
      elseif weatherKind == "SUN" then moveType = Types.ID.FIRE
      elseif weatherKind == "HAIL" then moveType = Types.ID.ICE end
    end
  end

  if effectByte == EffectIds.PURSUIT and opts.pursuitSwitch then
    dmgMultiplier = dmgMultiplier * 2
  elseif effectByte == EffectIds.FACADE and not opts.dmgMultiplier then
    local st = status_of(attacker)
    if st == "BRN" or st == "PAR" or st == "PSN" or st == "TOX" then
      dmgMultiplier = dmgMultiplier * 2
    end
  elseif effectByte == EffectIds.REVENGE and not opts.dmgMultiplier then
    -- pokefirered/src/battle_script_commands.c:8946
    local hurtOk
    if opts.adapter and opts.adapter._st and opts.adapter._st.double then
      hurtOk = attacker.expHurtById == nil or attacker.expHurtById == defender.id
    else
      hurtOk = attacker.expHurtBy == nil or attacker.expHurtBy == defender.side
    end
    if (attacker.damageTakenThisTurn or 0) > 0 and hurtOk then
      dmgMultiplier = dmgMultiplier * 2
    end
  elseif effectByte == EffectIds.SMELLINGSALT and not opts.dmgMultiplier then
    if status_of(defender) == "PAR" and (defender.substituteHP or 0) <= 0 then
      dmgMultiplier = dmgMultiplier * 2
    end
  end

  local physical = Types.isPhysical(moveType)
  local foresight = opts.foresight
  if foresight == nil then foresight = defender.expIdentified and true or false end
  local dType1 = defender.type1
  local dType2 = defender.type2
  if defender.expTransform then
    dType1 = defender.expTransform.type1 or dType1
    dType2 = defender.expTransform.type2 or dType2
  end
  local _, flags, eff = Types.typeCalc(moveType, dType1, dType2, nil, foresight)

  local fixedAmount = nil
  if effectByte == EffectIds.COUNTER then
    local taken = attacker.lastPhysicalDamageTaken or 0
    if taken <= 0 then
      return 0, { move = move, effectiveness = eff, critical = false, physical = physical, failed = true }
    end
    return (flags.immune and 0 or taken * 2), {
      move = move, effectiveness = eff, critical = false, physical = physical,
      typeFlags = flags, setDamage = true,
    }
  elseif effectByte == EffectIds.MIRROR_COAT then
    local taken = attacker.lastSpecialDamageTaken or 0
    if taken <= 0 then
      return 0, { move = move, effectiveness = eff, critical = false, physical = physical, failed = true }
    end
    return (flags.immune and 0 or taken * 2), {
      move = move, effectiveness = eff, critical = false, physical = physical,
      typeFlags = flags, setDamage = true,
    }
  elseif effectByte == EffectIds.DRAGON_RAGE then
    fixedAmount = 40
  elseif effectByte == EffectIds.SONICBOOM then
    fixedAmount = 20
  elseif effectByte == EffectIds.LEVEL_DAMAGE then
    fixedAmount = level
  elseif effectByte == EffectIds.SUPER_FANG then
    fixedAmount = math.max(1, math.floor((tonumber(dMon.hp) or 1) / 2))
  elseif effectByte == EffectIds.ENDEAVOR then
    local uHp = tonumber(aMon.hp) or 0
    local dHp = tonumber(dMon.hp) or 0
    if dHp <= uHp then
      return 0, { move = move, effectiveness = eff, critical = false, physical = physical, failed = true }
    end
    fixedAmount = dHp - uHp
  elseif effectByte == EffectIds.PSYWAVE then
    -- pokefirered/src/battle_script_commands.c:7557
    local r = opts.psywaveRoll or roll_from(rng, 0, 10)
    r = math.max(0, math.min(10, math.floor(r)))
    fixedAmount = math.floor(level * (r * 10 + 50) / 100)
  elseif opts.fixedDamage then
    fixedAmount = opts.fixedDamage
  end
  if fixedAmount then
    if flags.immune then
      return 0, fixed_info(move, 0, flags, physical)
    end
    return fixedAmount, fixed_info(move, eff, flags, physical)
  end

  local crit = false
  local defAb = ability_of(defender, opts.adapter)
  if opts.forceCrit ~= nil then
    crit = opts.forceCrit and true or false
  elseif defAb ~= "BATTLE_ARMOR" and defAb ~= "SHELL_ARMOR" and not opts.noCrit then
    -- pokefirered/src/battle_script_commands.c:1170
    local critSt = opts.st or (opts.adapter and opts.adapter._st)
    if opts.adapter and ModRuntime.wantsHook("battle.crit") then
      local G3 = require("src.mods.Gen3Compat")
      local num = tonumber(move.numId) or G3.moveId(move.id)
      crit = ModRuntime.call("battle.crit", function(c)
        return Rules.crit.roll(c.attacker, move, c.highCrit, c.rng, critSt)
      end, { battle = opts.adapter._st, attacker = attacker, target = defender,
             moveId = G3.moveName(num) or move.id, moveNum = num, rng = rng,
             highCrit = opts.highCrit,
             stage = Rules.crit.stage(attacker, move, opts.highCrit) }) and true or false
    else
      crit = Rules.crit.roll(attacker, move, opts.highCrit, rng, critSt)
    end
  end
  local critMul = crit and Rules.crit.multiplier() or 1

  local dmg = Damage.base(attacker, defender, move, {
    power = power,
    moveType = moveType,
    crit = crit,
    adapter = opts.adapter,
    reflect = opts.reflect,
    lightScreen = opts.lightScreen,
    doubleScreens = opts.doubleScreens,
    spread = opts.spread,
    weatherKind = weatherKind,
    isSolarBeam = effectByte == EffectIds.SOLAR_BEAM,
    mudSport = opts.mudSport,
    waterSport = opts.waterSport,
  })
  -- pokefirered/src/battle_script_commands.c:1209
  dmg = dmg * critMul * dmgMultiplier
  if attacker.expCharged and tonumber(move.type) == Types.ID.ELECTRIC then
    dmg = dmg * 2
  end
  -- pokefirered/src/battle_script_commands.c:1219
  if attacker.expHelpingHand then dmg = math.floor(dmg * 15 / 10) end

  local stab = 1
  local aT1, aT2 = attacker.type1, attacker.type2
  if attacker.expTransform then
    aT1 = attacker.expTransform.type1 or aT1
    aT2 = attacker.expTransform.type2 or aT2
  end
  if move.id ~= "STRUGGLE" and tonumber(move.numId) ~= 165 then
    if aT1 == moveType or aT2 == moveType then
      stab = 1.5
      dmg = math.floor(dmg * 15 / 10)
    end
    dmg, flags, eff = Types.typeCalc(moveType, dType1, dType2, dmg, foresight)
  else
    flags = { super = false, notVery = false, immune = false }
    eff = 1
  end
  if flags.immune then
    return 0, {
      move = move, effectiveness = 0, critical = false, physical = physical,
      stab = stab, magnitude = magnitudeVal, moveType = moveType, typeFlags = flags,
    }
  end

  -- pokefirered/src/battle_script_commands.c:1558
  if dmg ~= 0 and not opts.noRandom then
    local roll = tonumber(opts.forceRoll) or roll_from(rng, 85, 100)
    dmg = math.floor(dmg * roll / 100)
    if dmg == 0 then dmg = 1 end
  end

  if effectByte == EffectIds.FALSE_SWIPE and (defender.substituteHP or 0) <= 0 then
    local curHp = tonumber(dMon.hp) or 1
    if dmg >= curHp then dmg = math.max(0, curHp - 1) end
  end

  return dmg, {
    move = move,
    effectiveness = eff,
    critical = crit,
    physical = physical,
    stab = stab,
    magnitude = magnitudeVal,
    moveType = moveType,
    typeFlags = flags,
    power = power,
  }
end

return Damage
