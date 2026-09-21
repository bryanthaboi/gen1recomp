local Types = require("src.core.game3.battle.types")
local Oak = require("src.core.game3.battle.oak_advice")
local Strings = require("src.core.Strings")

local Secondary = {}

-- pokefirered/src/battle_message.c:437
Secondary.STAT_NAME = {
  attack = "ATTACK", defense = "DEFENSE", speed = "SPEED",
  spAtk = "SP. ATK", spDef = "SP. DEF", accuracy = "accuracy", evasion = "evasiveness",
}

-- pokefirered/include/constants/pokemon.h:167
Secondary.STAT_ID = {
  attack = 1, defense = 2, speed = 3, spAtk = 4, spDef = 5, accuracy = 6, evasion = 7,
}

-- pokefirered/include/battle_anim.h:41
Secondary.STAT_ANIM = {
  PLUS1 = 15, PLUS2 = 39, MINUS1 = 22, MINUS2 = 46,
  MULTIPLE_PLUS1 = 55, MULTIPLE_PLUS2 = 56, MULTIPLE_MINUS1 = 57, MULTIPLE_MINUS2 = 58,
}

-- pokefirered/src/battle_script_commands.c:3934
function Secondary.statAnimArg(stat, delta)
  local id = Secondary.STAT_ID[stat] or 1
  local base
  if delta >= 2 then base = Secondary.STAT_ANIM.PLUS2
  elseif delta >= 1 then base = Secondary.STAT_ANIM.PLUS1
  elseif delta <= -2 then base = Secondary.STAT_ANIM.MINUS2
  else base = Secondary.STAT_ANIM.MINUS1 end
  return id + base - 1
end

local function name(ad, b) return ad:displayName(b) end

-- The stat's display name, translated at the time it is said.
function Secondary.statName(stat)
  return Strings(Secondary.STAT_NAME[stat] or stat)
end

local function stat_text(ad, battler, stat, delta)
  local who, what = name(ad, battler), Secondary.statName(stat)
  if delta >= 2 then return Strings("%s's %s\nsharply rose!", who, what) end
  if delta >= 1 then return Strings("%s's %s\nrose!", who, what) end
  if delta <= -2 then return Strings("%s's %s\nharshly fell!", who, what) end
  return Strings("%s's %s\nfell!", who, what)
end

-- pokefirered/src/battle_script_commands.c:6655
function Secondary.changeStat(ad, battler, stat, delta, flags)
  flags = flags or {}
  if not battler or not battler.stages then return "blocked" end
  local cur = battler.stages[stat] or 0
  if delta < 0 then
    local side = ad:ownSide(battler)
    local ab = ad:abilityOf(battler)
    if side and (side.expMistTurns or 0) > 0 and not flags.certain and not flags.curse then
      if flags.allowPtr and not battler._statLoweredMsg then
        battler._statLoweredMsg = true
        ad:say(Strings("%s is protected\nby MIST!", name(ad, battler)))
      end
      return "blocked"
    end
    if (ab == "CLEAR_BODY" or ab == "WHITE_SMOKE") and not flags.certain and not flags.curse then
      if flags.allowPtr and not battler._statLoweredMsg then
        battler._statLoweredMsg = true
        ad:say(Strings("%s's %s\nprevents stat loss!", name(ad, battler), require("src.core.game3.battle.abilities").name(ab)))
      end
      return "blocked"
    end
    if ab == "KEEN_EYE" and stat == "accuracy" and not flags.certain then
      if flags.allowPtr then
        ad:say(Strings("%s's KEEN EYE\nprevents accuracy loss!", name(ad, battler)))
      end
      return "blocked"
    end
    if ab == "HYPER_CUTTER" and stat == "attack" and not flags.certain then
      if flags.allowPtr then
        ad:say(Strings("%s's HYPER CUTTER\nprevents ATTACK loss!", name(ad, battler)))
      end
      return "blocked"
    end
    if ab == "SHIELD_DUST" and not flags.allowPtr and not flags.user then
      return "blocked"
    end
    if cur <= -6 then
      if not flags.noMsg then
        ad:say(Strings("%s's %s\nwon't go lower!", name(ad, battler), Secondary.statName(stat)))
      end
      return "wont"
    end
  else
    if cur >= 6 then
      if not flags.noMsg then
        ad:say(Strings("%s's %s\nwon't go higher!", name(ad, battler), Secondary.statName(stat)))
      end
      return "wont"
    end
  end
  local nxt = cur + delta
  if nxt < -6 then nxt = -6 elseif nxt > 6 then nxt = 6 end
  battler.stages[stat] = nxt
  if not flags.noAnim then
    ad:playAnim("general", "STATS_CHANGE", battler, battler, Secondary.statAnimArg(stat, delta))
  end
  if not flags.noMsg then
    ad:say(stat_text(ad, battler, stat, delta))
    -- pokefirered/src/battle_controller_oak_old_man.c:1768
    if Oak.active(ad._st) and delta < 0 and battler.side == "enemy" then
      Oak.sayOnce(ad._st, Oak.FLAG_STAT_CHG, "loweringStats", function(t) ad:say(t) end)
    end
  end
  return "worked"
end

-- pokefirered/src/battle_script_commands.c:3957
function Secondary.multiStatAnim(ad, battler, stats, delta, opts)
  opts = opts or {}
  local count, only = 0, nil
  for _, s in ipairs(stats) do
    local cur = battler.stages and battler.stages[s] or 0
    local can
    if delta < 0 then
      local side = ad:ownSide(battler)
      local ab = ad:abilityOf(battler)
      if opts.cantPrevent then
        can = cur > -6
      else
        can = not (side and (side.expMistTurns or 0) > 0)
          and ab ~= "CLEAR_BODY" and ab ~= "WHITE_SMOKE"
          and not (ab == "KEEN_EYE" and s == "accuracy")
          and not (ab == "HYPER_CUTTER" and s == "attack")
          and cur > -6
      end
    else
      can = cur < 6
    end
    if can then count = count + 1; only = s end
  end
  if count == 0 then return 0 end
  local arg
  if count > 1 then
    if delta >= 2 then arg = Secondary.STAT_ANIM.MULTIPLE_PLUS2
    elseif delta >= 1 then arg = Secondary.STAT_ANIM.MULTIPLE_PLUS1
    elseif delta <= -2 then arg = Secondary.STAT_ANIM.MULTIPLE_MINUS2
    else arg = Secondary.STAT_ANIM.MULTIPLE_MINUS1 end
  else
    arg = Secondary.statAnimArg(only, delta)
  end
  ad:playAnim("general", "STATS_CHANGE", battler, battler, arg)
  return count
end

Secondary.STAT_EFFECTS = {
  ATK_PLUS_1 = { "attack", 1 }, DEF_PLUS_1 = { "defense", 1 }, SPD_PLUS_1 = { "speed", 1 },
  SP_ATK_PLUS_1 = { "spAtk", 1 }, SP_DEF_PLUS_1 = { "spDef", 1 }, ACC_PLUS_1 = { "accuracy", 1 },
  EVS_PLUS_1 = { "evasion", 1 },
  ATK_MINUS_1 = { "attack", -1 }, DEF_MINUS_1 = { "defense", -1 }, SPD_MINUS_1 = { "speed", -1 },
  SP_ATK_MINUS_1 = { "spAtk", -1 }, SP_DEF_MINUS_1 = { "spDef", -1 }, ACC_MINUS_1 = { "accuracy", -1 },
  EVS_MINUS_1 = { "evasion", -1 },
}

local STATUS_MSG = {
  SLP = Strings.source("%s\nfell asleep!"),
  PSN = Strings.source("%s\nwas poisoned!"),
  BRN = Strings.source("%s was burned!"),
  FRZ = Strings.source("%s was\nfrozen solid!"),
  PAR = Strings.source("%s is paralyzed!\nIt may be unable to move!"),
  TOX = Strings.source("%s is badly\npoisoned!"),
}
Secondary.STATUS_MSG = STATUS_MSG

local EFFECT_TO_STATUS = {
  SLEEP = "SLP", POISON = "PSN", BURN = "BRN", FREEZE = "FRZ", PARALYSIS = "PAR", TOXIC = "TOX",
}

-- pokefirered/src/battle_script_commands.c:2110
local STATUS_EFFECT_RANK = {
  SLEEP = 1, POISON = 2, BURN = 3, FREEZE = 4, PARALYSIS = 5, TOXIC = 6, CONFUSION = 7,
  FLINCH = 8, TRI_ATTACK = 9,
}

-- template: holder, then ability (battle_message.c sText_PkmnPrevents*With)
local function ability_prevention_msg(ad, b, ab, template)
  ad:say(Strings(template, name(ad, b), require("src.core.game3.battle.abilities").name(ab)))
end

local function apply_status_effect(M, eff, primary, certain, effBattler)
  local ad = M.adapter
  local status = EFFECT_TO_STATUS[eff]
  local ab = ad:abilityOf(effBattler)
  local strict = primary or certain
  if status == "PSN" or status == "TOX" then
    if ab == "IMMUNITY" and strict then
      ability_prevention_msg(ad, effBattler, ab, Strings.source("%s's %s\nprevents poisoning!"))
      return false
    end
  elseif status == "BRN" then
    if ab == "WATER_VEIL" and strict then
      ad:say(Strings("%s's WATER VEIL\nprevents burns!", name(ad, effBattler)))
      return false
    end
  elseif status == "PAR" then
    if ab == "LIMBER" and strict then
      ability_prevention_msg(ad, effBattler, ab, Strings.source("%s's %s\nprevents paralysis!"))
      return false
    end
  end
  if not ad:canApplyStatus(effBattler, status, M.user, { ignoreSafeguard = true }) then
    if status == "TOX" and not ad:status(effBattler)
        and (ad:hasType(effBattler, Types.ID.POISON) or ad:hasType(effBattler, Types.ID.STEEL)) then
      M.doesntAffect = true
    end
    return false
  end
  ad:applyStatus(effBattler, status, M.user, { ignoreSafeguard = true, force = true })
  ad:statusAnim(effBattler, status)
  ad:say(Strings(STATUS_MSG[status], name(ad, effBattler)))
  -- pokefirered/src/battle_script_commands.c:2376
  if status == "PSN" or status == "TOX" or status == "PAR" or status == "BRN" then
    ad._syncEffect = { status = status }
  end
  return true
end

local function item_name(id)
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  if ok and ItemsData and ItemsData.displayName then
    local n = ItemsData.displayName(id)
    if n and n ~= "" then return tostring(n) end
  end
  return Strings("ITEM %s", tostring(id))
end
Secondary.itemName = item_name

local function is_mail(id)
  id = tonumber(id) or 0
  return id >= 121 and id <= 132
end
Secondary.isMail = is_mail

local TRAP_MSG = {
  [20] = function(t, u) return Strings("%s was squeezed by\n%s's BIND!", t, u) end,
  [35] = function(t, u) return Strings("%s was WRAPPED by\n%s!", t, u) end,
  [83] = function(t) return Strings("%s was trapped\nin the vortex!", t) end,
  [128] = function(t, u) return Strings("%s CLAMPED\n%s!", u, t) end,
  [250] = function(t) return Strings("%s was trapped\nin the vortex!", t) end,
  [328] = function(t) return Strings("%s was trapped\nby SAND TOMB!", t) end,
}

local function persist_item(b, item)
  local Engine = package.loaded["src.core.game3.battle.state"]
  local mon = Engine and Engine.partyMon and Engine.partyMon(b) or (b and b.mon)
  if mon then
    if item and item ~= 0 then
      mon.item = item
      mon.heldItem = item
    else
      mon.item = nil
      mon.heldItem = nil
    end
  end
end
Secondary.persistItem = persist_item

function Secondary.set(M, eff, primary, certain, affectsUser)
  local ad = M.adapter
  local user, target = M.user, M.target
  local effBattler = affectsUser and user or target
  local rank = STATUS_EFFECT_RANK[eff]
  if not effBattler then return false end
  if rank and rank <= 9 and not primary and ad:abilityOf(effBattler) == "SHIELD_DUST" and not affectsUser then
    return false
  end
  if rank and rank <= 7 and not primary and not affectsUser then
    local side = ad:ownSide(effBattler)
    if side and (side.expSafeguardTurns or 0) > 0 then return false end
  end
  if ad:hp(effBattler) <= 0 and eff ~= "PAYDAY" and eff ~= "STEAL_ITEM" then return false end
  if not affectsUser and (effBattler.substituteHP or 0) > 0 then return false end

  if EFFECT_TO_STATUS[eff] then
    return apply_status_effect(M, eff, primary, certain, effBattler)
  end

  if eff == "CONFUSION" then
    if ad:abilityOf(effBattler) == "OWN_TEMPO" or (effBattler.confusionTurns or 0) > 0 then return false end
    effBattler.confusionTurns = ad:roll(0, 3) % 4 + 2
    ad:playAnim("status", "CONFUSION", effBattler, effBattler)
    ad:say(Strings("%s became\nconfused!", name(ad, effBattler)))
    return true
  elseif eff == "FLINCH" then
    if ad:abilityOf(effBattler) == "INNER_FOCUS" then
      if primary or certain then
        ad:say(Strings("%s's INNER FOCUS\nprevents flinching!", name(ad, effBattler)))
      end
      return false
    end
    if not effBattler.expMovedThisTurn then effBattler.flinched = true end
    return true
  elseif eff == "UPROAR" then
    if (effBattler.expUproarTurns or 0) > 0 then return false end
    effBattler.expLockedMove = M.moveId
    effBattler.expLockedSlot = M.slot
    effBattler.expUproarTurns = ad:roll(0, 3) % 4 + 2
    effBattler.uproar = true
    ad:say(Strings("%s caused\nan UPROAR!", name(ad, effBattler)))
    return true
  elseif eff == "PAYDAY" then
    -- pokefirered/src/battle_script_commands.c:2455
    if (user.side or "player") == "player" then
      local lvl = tonumber(user.mon and user.mon.level) or 1
      M.st.payDayCoins = math.min(0xFFFF, (M.st.payDayCoins or 0) + lvl * 5)
    end
    ad:say(Strings("Coins scattered everywhere!"))
    return true
  elseif eff == "TRI_ATTACK" then
    if ad:status(effBattler) then return false end
    local r = ad:roll(0, 2) % 3
    local pick = ({ [0] = "BURN", [1] = "FREEZE", [2] = "PARALYSIS" })[r]
    return Secondary.set(M, pick, false, false, false)
  elseif eff == "WRAP" then
    if (effBattler.expTrapTurns or 0) > 0 then return false end
    local Rules = require("src.core.game3.battle.rules")
    if Rules.partialTrap.active and not Rules.partialTrap.active() then return false end
    effBattler.expTrapTurns = Rules.partialTrap.rollTurns(ad:rng())
    effBattler.expTrapMove = M.mnum
    effBattler.expTrapMoveName = M.moveName
    effBattler.expTrapSource = user
    effBattler.wrapped = true
    local fn = TRAP_MSG[M.mnum] or TRAP_MSG[20]
    ad:say(fn(name(ad, effBattler), name(ad, user)))
    return true
  elseif eff == "RECOIL_25" or eff == "RECOIL_33" then
    local div = (eff == "RECOIL_25") and 4 or 3
    local dmg = math.floor((M.hpDealt or 0) / div)
    if dmg == 0 then dmg = 1 end
    if M.mnum ~= 165 and ad:abilityOf(user) == "ROCK_HEAD" then return false end
    ad:applyHpLoss(user, dmg)
    ad:say(Strings("%s is hit\nwith recoil!", name(ad, user)))
    M.checkUserFaint = true
    return true
  elseif Secondary.STAT_EFFECTS[eff] then
    local spec = Secondary.STAT_EFFECTS[eff]
    local res = Secondary.changeStat(ad, effBattler, spec[1], spec[2], {
      user = affectsUser, certain = certain, allowPtr = false,
    })
    return res == "worked"
  elseif eff == "RECHARGE" then
    effBattler.expRechargeTurns = 2
    effBattler.expMustRecharge = true
    effBattler.recharge = true
    return true
  elseif eff == "RAGE" then
    user.rage = true
    return true
  elseif eff == "STEAL_ITEM" then
    if user.side ~= "player" then return false end
    if user.expKnockedOff then return false end
    local tItem = tonumber(target.item) or 0
    if tItem ~= 0 and ad:abilityOf(target) == "STICKY_HOLD" then
      ad:say(Strings("%s's STICKY HOLD\nmade %s ineffective!", name(ad, target), (M.moveName or "THIEF")))
      return false
    end
    if (tonumber(user.item) or 0) ~= 0 or tItem == 0 or tItem == 175 or is_mail(tItem) then
      return false
    end
    user.item = tItem
    target.item = 0
    persist_item(user, tItem)
    if target.side == "player" then persist_item(target, 0) end
    ad:playAnim("general", "ITEM_STEAL", user, target)
    ad:say(Strings("%s stole\n%s's %s!", name(ad, user), name(ad, target), item_name(tItem)))
    return true
  elseif eff == "PREVENT_ESCAPE" then
    target.expTrapped = true
    target.escapePrevention = true
    target.expTrappedBy = user
    return true
  elseif eff == "NIGHTMARE" then
    target.expNightmare = true
    return true
  elseif eff == "ALL_STATS_UP" then
    local order = { "attack", "defense", "speed", "spAtk", "spDef" }
    local any = false
    for _, s in ipairs(order) do
      if (user.stages[s] or 0) < 6 then any = true end
    end
    if not any then return false end
    Secondary.multiStatAnim(ad, user, order, 1)
    for _, s in ipairs(order) do
      if (user.stages[s] or 0) < 6 then
        Secondary.changeStat(ad, user, s, 1, { user = true, noAnim = true })
      end
    end
    return true
  elseif eff == "RAPIDSPIN" then
    -- pokefirered/src/battle_script_commands.c:8435
    local did = false
    if (user.expTrapTurns or 0) > 0 then
      local src = user.expTrapSource
      ad:say(Strings("%s got free of\n%s's %s!", name(ad, user), name(ad, src or target), tostring(user.expTrapMoveName or "BIND")))
      user.expTrapTurns = nil
      user.expTrapMove = nil
      user.expTrapSource = nil
      user.wrapped = nil
      did = true
    end
    if user.expSeeded or user.leechSeed then
      user.expSeeded = nil
      user.expSeedSource = nil
      user.leechSeed = nil
      ad:say(Strings("%s shed\nLEECH SEED!", name(ad, user)))
      did = true
    end
    local side = ad:ownSide(user)
    local Hazards = require("src.core.game3.battle.effects.hazards")
    if side and Hazards.layers(side) > 0 then
      Hazards.clear(side)
      ad:say(Strings("%s blew away\nSPIKES!", name(ad, user)))
      did = true
    end
    user.trapped = nil
    return did
  elseif eff == "REMOVE_PARALYSIS" then
    if ad:status(target) ~= "PAR" then return false end
    ad:clearStatus(target)
    ad:say(Strings("%s was\nhealed of paralysis!", name(ad, target)))
    return true
  elseif eff == "ATK_DEF_DOWN" then
    Secondary.multiStatAnim(ad, user, { "attack", "defense" }, -1, { cantPrevent = true })
    Secondary.changeStat(ad, user, "attack", -1, { user = true, certain = true, allowPtr = true, noAnim = true, noMsg = (user.stages.attack or 0) <= -6 })
    Secondary.changeStat(ad, user, "defense", -1, { user = true, certain = true, allowPtr = true, noAnim = true, noMsg = (user.stages.defense or 0) <= -6 })
    return true
  elseif eff == "SP_ATK_TWO_DOWN" then
    if (user.stages.spAtk or 0) > -6 then
      ad:playAnim("general", "STATS_CHANGE", user, user, Secondary.statAnimArg("spAtk", -2))
      Secondary.changeStat(ad, user, "spAtk", -2, { user = true, certain = true, allowPtr = true, noAnim = true })
    end
    return true
  elseif eff == "THRASH" then
    if (effBattler.expRampageTurns or 0) > 0 then return false end
    effBattler.expLockedMove = M.moveId
    effBattler.expLockedSlot = M.slot
    effBattler.expRampageTurns = ad:roll(0, 1) % 2 + 2
    return true
  elseif eff == "KNOCK_OFF" then
    local tItem = tonumber(effBattler.item) or 0
    if ad:abilityOf(effBattler) == "STICKY_HOLD" then
      if tItem == 0 then return false end
      ad:say(Strings("%s's STICKY HOLD\nmade %s ineffective!", name(ad, effBattler), (M.moveName or "KNOCK OFF")))
      return false
    end
    if tItem == 0 then return false end
    effBattler.item = 0
    effBattler.expKnockedOff = true
    ad:playAnim("general", "ITEM_KNOCKOFF", user, effBattler)
    ad:say(Strings("%s knocked off\n%s's %s!", name(ad, user), name(ad, effBattler), item_name(tItem)))
    return true
  end
  return false
end

-- pokefirered/src/battle_script_commands.c:2774
function Secondary.withChance(M, eff, certainFlag, affectsUser)
  if not eff then return false end
  if M.noEffect then return false end
  local ad = M.adapter
  local chance = tonumber(M.move and M.move.secondaryChance) or 0
  if ad:abilityOf(M.user) == "SERENE_GRACE" then chance = chance * 2 end
  if certainFlag then
    return Secondary.set(M, eff, false, true, affectsUser)
  end
  if ad:roll(0, 99) <= chance then
    return Secondary.set(M, eff, false, chance >= 100, affectsUser)
  end
  return false
end

return Secondary
