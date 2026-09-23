local Secondary = require("src.core.game3.battle.effects.secondary")
local State = require("src.core.game3.battle.state")
local RomText = require("src.core.game3.rom_text")

local HeldItems = {}

-- pokefirered/include/constants/hold_effects.h:4
local H = {
  RESTORE_HP = 1, CURE_PAR = 2, CURE_SLP = 3, CURE_PSN = 4, CURE_BRN = 5, CURE_FRZ = 6,
  RESTORE_PP = 7, CURE_CONFUSION = 8, CURE_STATUS = 9, CONFUSE_SPICY = 10, CONFUSE_DRY = 11,
  CONFUSE_SWEET = 12, CONFUSE_BITTER = 13, CONFUSE_SOUR = 14, ATTACK_UP = 15, DEFENSE_UP = 16,
  SPEED_UP = 17, SP_ATTACK_UP = 18, SP_DEFENSE_UP = 19, CRITICAL_UP = 20, RANDOM_STAT_UP = 21,
  EVASION_UP = 22, RESTORE_STATS = 23, MACHO_BRACE = 24, EXP_SHARE = 25, QUICK_CLAW = 26,
  FRIENDSHIP_UP = 27, CURE_ATTRACT = 28, CHOICE_BAND = 29, FLINCH = 30, BUG_POWER = 31,
  DOUBLE_PRIZE = 32, REPEL = 33, SOUL_DEW = 34, DEEP_SEA_TOOTH = 35, DEEP_SEA_SCALE = 36,
  CAN_ALWAYS_RUN = 37, PREVENT_EVOLVE = 38, FOCUS_BAND = 39, LUCKY_EGG = 40, SCOPE_LENS = 41,
  STEEL_POWER = 42, LEFTOVERS = 43, DRAGON_SCALE = 44, LIGHT_BALL = 45, GROUND_POWER = 46,
  ROCK_POWER = 47, GRASS_POWER = 48, DARK_POWER = 49, FIGHTING_POWER = 50, ELECTRIC_POWER = 51,
  WATER_POWER = 52, FLYING_POWER = 53, POISON_POWER = 54, ICE_POWER = 55, GHOST_POWER = 56,
  PSYCHIC_POWER = 57, FIRE_POWER = 58, DRAGON_POWER = 59, NORMAL_POWER = 60, UP_GRADE = 61,
  SHELL_BELL = 62, LUCKY_PUNCH = 63, METAL_POWDER = 64, THICK_CLUB = 65, STICK = 66,
}
HeldItems.HOLD = H

-- pokefirered/src/data/items.json:1
local ITEM_HOLD = {
  [44] = { 1, 20 }, [133] = { 2, 0 }, [134] = { 3, 0 }, [135] = { 4, 0 }, [136] = { 5, 0 },
  [137] = { 6, 0 }, [138] = { 7, 10 }, [139] = { 1, 10 }, [140] = { 8, 0 }, [141] = { 9, 0 },
  [142] = { 1, 30 }, [143] = { 10, 8 }, [144] = { 11, 8 }, [145] = { 12, 8 }, [146] = { 13, 8 },
  [147] = { 14, 8 }, [168] = { 15, 4 }, [169] = { 16, 4 }, [170] = { 17, 4 }, [171] = { 18, 4 },
  [172] = { 19, 4 }, [173] = { 20, 4 }, [174] = { 21, 4 }, [179] = { 22, 10 }, [180] = { 23, 0 },
  [181] = { 24, 0 }, [182] = { 25, 0 }, [183] = { 26, 20 }, [184] = { 27, 0 }, [185] = { 28, 0 },
  [186] = { 29, 0 }, [187] = { 30, 10 }, [188] = { 31, 10 }, [189] = { 32, 10 }, [190] = { 33, 0 },
  [191] = { 34, 0 }, [192] = { 35, 0 }, [193] = { 36, 0 }, [194] = { 37, 0 }, [195] = { 38, 0 },
  [196] = { 39, 10 }, [197] = { 40, 0 }, [198] = { 41, 0 }, [199] = { 42, 10 }, [200] = { 43, 10 },
  [201] = { 44, 10 }, [202] = { 45, 0 }, [203] = { 46, 10 }, [204] = { 47, 10 }, [205] = { 48, 10 },
  [206] = { 49, 10 }, [207] = { 50, 10 }, [208] = { 51, 10 }, [209] = { 52, 10 }, [210] = { 53, 10 },
  [211] = { 54, 10 }, [212] = { 55, 10 }, [213] = { 56, 10 }, [214] = { 57, 10 }, [215] = { 58, 10 },
  [216] = { 59, 10 }, [217] = { 60, 10 }, [218] = { 61, 0 }, [219] = { 62, 8 }, [220] = { 52, 5 },
  [221] = { 22, 5 }, [222] = { 63, 0 }, [223] = { 64, 0 }, [224] = { 65, 0 }, [225] = { 66, 0 },
}

-- pokefirered/src/pokemon.c:1461
HeldItems.TYPE_BOOST = {
  [H.BUG_POWER] = 6, [H.STEEL_POWER] = 8, [H.GROUND_POWER] = 4, [H.ROCK_POWER] = 5,
  [H.GRASS_POWER] = 12, [H.DARK_POWER] = 17, [H.FIGHTING_POWER] = 1, [H.ELECTRIC_POWER] = 13,
  [H.WATER_POWER] = 11, [H.FLYING_POWER] = 2, [H.POISON_POWER] = 3, [H.ICE_POWER] = 15,
  [H.GHOST_POWER] = 7, [H.PSYCHIC_POWER] = 14, [H.FIRE_POWER] = 10, [H.DRAGON_POWER] = 16,
  [H.NORMAL_POWER] = 0,
}

-- pokefirered/src/pokemon.c:1398
local FLAVOR_TABLE = {
  [0] = { 0, 0, 0, 0, 0 }, { 1, 0, 0, 0, -1 }, { 1, 0, -1, 0, 0 }, { 1, -1, 0, 0, 0 },
  { 1, 0, 0, -1, 0 }, { -1, 0, 0, 0, 1 }, { 0, 0, 0, 0, 0 }, { 0, 0, -1, 0, 1 },
  { 0, -1, 0, 0, 1 }, { 0, 0, 0, -1, 1 }, { -1, 0, 1, 0, 0 }, { 0, 0, 1, 0, -1 },
  { 0, 0, 0, 0, 0 }, { 0, -1, 1, 0, 0 }, { 0, 0, 1, -1, 0 }, { -1, 1, 0, 0, 0 },
  { 0, 1, 0, 0, -1 }, { 0, 1, -1, 0, 0 }, { 0, 0, 0, 0, 0 }, { 0, 1, 0, -1, 0 },
  { -1, 0, 0, 1, 0 }, { 0, 0, 0, 1, -1 }, { 0, 0, -1, 1, 0 }, { 0, -1, 0, 1, 0 },
  { 0, 0, 0, 0, 0 },
}

local STAT_ORDER = { "attack", "defense", "speed", "spAtk", "spDef" }

function HeldItems.flavorRelation(personality, flavor)
  local row = FLAVOR_TABLE[(tonumber(personality) or 0) % 25]
  return row[flavor + 1] or 0
end

function HeldItems.effectOf(item)
  item = tonumber(item) or 0
  if item == 0 then return 0, 0 end
  local row = ITEM_HOLD[item]
  if row then return row[1], row[2] end
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  if ok and ItemsData and ItemsData.info then
    local ok2, info = pcall(ItemsData.info, item)
    if ok2 and info and tonumber(info.holdEffect) then
      return tonumber(info.holdEffect), tonumber(info.holdEffectParam) or 0
    end
  end
  return 0, 0
end

function HeldItems.itemOf(b)
  return b and tonumber(b.item) or 0
end

function HeldItems.of(b)
  local item = HeldItems.itemOf(b)
  local he, param = HeldItems.effectOf(item)
  return he, param, item
end

function HeldItems.has(b, he)
  return (HeldItems.of(b)) == he
end

function HeldItems.name(item)
  return Secondary.itemName(item)
end

local function say_id(ad, id, fill)
  ad:sayText(id, fill)
end

local function item_anim(ad, b)
  ad:playAnim("general", "HELD_ITEM_EFFECT", b, b)
end

-- pokefirered/src/battle_script_commands.c:5642
function HeldItems.consume(ad, b)
  local item = HeldItems.itemOf(b)
  if item == 0 then return end
  b.item = 0
  b.expUsedHeldItem = item
  local side = ad:ownSide(b)
  if side then side.expUsedHeldItem = item end
  Secondary.persistItem(b, 0)
end

-- src/battle_script_commands.c:6788
local function stat_up(ad, b, item, stat, delta)
  item_anim(ad, b)
  b.stages[stat] = math.min(6, (b.stages[stat] or 0) + delta)
  ad:playAnim("general", "STATS_CHANGE", b, b, Secondary.statAnimArg(stat, delta))
  local change = RomText.plain("STRINGID_STATROSE")
  if delta >= 2 then change = RomText.plain("STRINGID_STATSHARPLY") .. change end
  say_id(ad, "STRINGID_USINGITEMSTATOFPKMNROSE", {
    lastItem = item, buff1 = Secondary.statName(stat), scrActive = b, buff2 = change,
  })
  HeldItems.consume(ad, b)
end

-- data/battle_scripts_1.s:4216
local CURE_TEXT = {
  [H.CURE_PAR] = "STRINGID_PKMNSITEMCUREDPARALYSIS",
  [H.CURE_PSN] = "STRINGID_PKMNSITEMCUREDPOISON",
  [H.CURE_BRN] = "STRINGID_PKMNSITEMHEALEDBURN",
  [H.CURE_FRZ] = "STRINGID_PKMNSITEMDEFROSTEDIT",
  [H.CURE_SLP] = "STRINGID_PKMNSITEMWOKEIT",
}

local function cure_status_item(ad, b, item, he)
  local s = ad:status(b)
  local ok = (he == H.CURE_PAR and s == "PAR") or (he == H.CURE_PSN and (s == "PSN" or s == "TOX"))
    or (he == H.CURE_BRN and s == "BRN") or (he == H.CURE_FRZ and s == "FRZ") or (he == H.CURE_SLP and s == "SLP")
  if not ok then return false end
  if he == H.CURE_SLP then b.expNightmare = nil end
  ad:clearStatus(b)
  item_anim(ad, b)
  say_id(ad, CURE_TEXT[he], { scrActive = b, lastItem = item })
  HeldItems.consume(ad, b)
  return true
end

-- src/battle_util.c:2778
local function lum(ad, b, item, allowNormalized)
  local s = ad:status(b)
  local confused = (b.confusionTurns or 0) > 0
  if not s and not confused then return false end
  local count, word = 0, nil
  if s == "PSN" or s == "TOX" then word = "gText_Poison"; count = count + 1 end
  if s == "SLP" then b.expNightmare = nil; word = "gText_Sleep"; count = count + 1 end
  if s == "PAR" then word = "gText_Paralysis"; count = count + 1 end
  if s == "BRN" then word = "gText_Burn"; count = count + 1 end
  if s == "FRZ" then word = "gText_Ice"; count = count + 1 end
  if confused then word = "gText_Confusion"; count = count + 1 end
  ad:clearStatus(b)
  b.confusionTurns = nil
  item_anim(ad, b)
  if allowNormalized and count > 1 then
    say_id(ad, "STRINGID_PKMNSITEMNORMALIZEDSTATUS", { scrActive = b, lastItem = item })
  else
    say_id(ad, "STRINGID_PKMNSITEMCUREDPROBLEM", { scrActive = b, lastItem = item, buff1 = RomText.plain(word) })
  end
  HeldItems.consume(ad, b)
  return true
end

local function white_herb(ad, b, item)
  local any = false
  for k, v in pairs(b.stages or {}) do
    if v < 0 then b.stages[k] = 0; any = true end
  end
  if not any then return false end
  item_anim(ad, b)
  say_id(ad, "STRINGID_PKMNSITEMRESTOREDSTATUS", { scrActive = b, lastItem = item })
  HeldItems.consume(ad, b)
  return true
end

local function mental_herb(ad, b, item)
  if not b.expInfatuated then return false end
  b.expInfatuated, b.expInfatuatedWith, b.expInfatuatedBy = nil, nil, nil
  item_anim(ad, b)
  say_id(ad, "STRINGID_PKMNSITEMCUREDPROBLEM", { scrActive = b, lastItem = item, buff1 = RomText.plain("gText_Love") })
  HeldItems.consume(ad, b)
  return true
end

local function persim(ad, b, item)
  if (b.confusionTurns or 0) <= 0 then return false end
  b.confusionTurns = nil
  item_anim(ad, b)
  say_id(ad, "STRINGID_PKMNSITEMSNAPPEDOUT", { scrActive = b, lastItem = item })
  HeldItems.consume(ad, b)
  return true
end

local function leppa(ad, b, item, param)
  local mon = b.mon
  if not mon or not mon.moves then return false end
  local slot
  for i = 1, 4 do
    local mv = mon.moves[i]
    if mv and mv ~= 0 and mv ~= "" and tonumber(mon.pp and mon.pp[i]) == 0 then slot = i; break end
  end
  if not slot then return false end
  local Moves = require("src.core.game3.battle.moves")
  local base = mon.maxPp and tonumber(mon.maxPp[slot])
  if not base then base = tonumber(Moves.get(mon.moves[slot]).pp) or param end
  local pp = math.min(base, param)
  item_anim(ad, b)
  say_id(ad, "STRINGID_PKMNSITEMRESTOREDPP", {
    scrActive = b, lastItem = item, buff1 = Moves.displayName(mon.moves[slot]),
  })
  HeldItems.consume(ad, b)
  local State = require("src.core.game3.battle.state")
  local perm = b.permanentSlots
  if not perm or perm[slot] then
    mon.pp[slot] = pp
  end
  local pm = State.partyMon(b)
  if pm and pm ~= mon and pm.pp then pm.pp[slot] = pp end
  return true
end

local function heal_berry(ad, b, item, amount)
  item_anim(ad, b)
  say_id(ad, "STRINGID_PKMNSITEMRESTOREDHEALTH", { scrActive = b, lastItem = item })
  ad:heal(b, amount)
end

-- pokefirered/src/battle_util.c:2557
function HeldItems.normal(ad, b, moveTurn)
  if not b or ad:hp(b) <= 0 then return false end
  local he, param, item = HeldItems.of(b)
  if he == 0 then return false end
  local hp, maxHp = ad:hp(b), ad:maxHp(b)
  if he == H.RESTORE_HP then
    if hp <= math.floor(maxHp / 2) and not moveTurn then
      local amt = param
      if hp + param > maxHp then amt = maxHp - hp end
      heal_berry(ad, b, item, amt)
      HeldItems.consume(ad, b)
      return true
    end
  elseif he == H.RESTORE_PP then
    if not moveTurn then return leppa(ad, b, item, param) end
  elseif he == H.RESTORE_STATS then
    return white_herb(ad, b, item)
  elseif he == H.LEFTOVERS then
    if hp < maxHp and not moveTurn then
      local amt = math.floor(maxHp / 16)
      if amt == 0 then amt = 1 end
      item_anim(ad, b)
      say_id(ad, "STRINGID_PKMNSITEMRESTOREDHPALITTLE", { scrActive = b, lastItem = item })
      ad:heal(b, amt)
      return true
    end
  elseif he >= H.CONFUSE_SPICY and he <= H.CONFUSE_SOUR then
    if hp <= math.floor(maxHp / 2) and not moveTurn then
      local flavor = he - H.CONFUSE_SPICY
      local amt = math.floor(maxHp / math.max(1, param))
      if amt == 0 then amt = 1 end
      if hp + amt > maxHp then amt = maxHp - hp end
      heal_berry(ad, b, item, amt)
      local mon = b.mon or {}
      if HeldItems.flavorRelation(mon.personality, flavor) < 0 then
        -- src/battle_message.c:2282
        say_id(ad, "STRINGID_FORXCOMMAYZ", {
          scrActive = b, lastItem = item, buff1 = RomText.at("gPokeblockWasTooXStringTable", flavor),
        })
        if ad:abilityOf(b) ~= "OWN_TEMPO" and (b.confusionTurns or 0) <= 0 then
          b.confusionTurns = ad:roll(0, 3) % 4 + 2
          ad:playAnim("status", "CONFUSION", b, b)
          say_id(ad, "STRINGID_PKMNWASCONFUSED", { eff = b })
        end
      end
      HeldItems.consume(ad, b)
      return true
    end
  elseif he >= H.ATTACK_UP and he <= H.SP_DEFENSE_UP then
    local stat = STAT_ORDER[he - H.ATTACK_UP + 1]
    if hp <= math.floor(maxHp / math.max(1, param)) and not moveTurn and (b.stages[stat] or 0) < 6 then
      stat_up(ad, b, item, stat, 1)
      return true
    end
  elseif he == H.CRITICAL_UP then
    if hp <= math.floor(maxHp / math.max(1, param)) and not moveTurn and not (b.focusEnergy or b.expFocusEnergy) then
      b.focusEnergy = true
      b.expFocusEnergy = true
      item_anim(ad, b)
      say_id(ad, "STRINGID_PKMNUSEDXTOGETPUMPED", { scrActive = b, lastItem = item })
      HeldItems.consume(ad, b)
      return true
    end
  elseif he == H.RANDOM_STAT_UP then
    if not moveTurn and hp <= math.floor(maxHp / math.max(1, param)) then
      local any = false
      for _, s in ipairs(STAT_ORDER) do
        if (b.stages[s] or 0) < 6 then any = true end
      end
      if any then
        local stat
        repeat
          stat = STAT_ORDER[ad:roll(0, 4) % 5 + 1]
        until (b.stages[stat] or 0) < 6
        stat_up(ad, b, item, stat, 2)
        return true
      end
    end
  elseif he >= H.CURE_PAR and he <= H.CURE_FRZ then
    return cure_status_item(ad, b, item, he)
  elseif he == H.CURE_CONFUSION then
    return persim(ad, b, item)
  elseif he == H.CURE_STATUS then
    return lum(ad, b, item, true)
  elseif he == H.CURE_ATTRACT then
    return mental_herb(ad, b, item)
  end
  return false
end

-- pokefirered/src/battle_util.c:2851
function HeldItems.moveEnd(ad)
  local any = false
  local list = { ad._st.player, ad._st.enemy }
  if ad._st.double then list = ad:activeBattlers() end
  for _, b in ipairs(list) do
    if b and not ad:isFainted(b) then
      local he, _, item = HeldItems.of(b)
      local did = false
      if he >= H.CURE_PAR and he <= H.CURE_FRZ then
        did = cure_status_item(ad, b, item, he)
      elseif he == H.CURE_CONFUSION then
        did = persim(ad, b, item)
      elseif he == H.CURE_ATTRACT then
        did = mental_herb(ad, b, item)
      elseif he == H.CURE_STATUS then
        did = lum(ad, b, item, false)
      elseif he == H.RESTORE_STATS then
        did = white_herb(ad, b, item)
      end
      any = any or did
    end
  end
  return any
end

-- pokefirered/src/battle_util.c:2995
function HeldItems.kingsRockShellBell(M)
  local ad, user, target = M.adapter, M.user, M.target
  if not user or not target or (M.firstDmg or 0) == 0 then return false end
  local he, param, item = HeldItems.of(user)
  if he == H.FLINCH then
    local _, p0 = HeldItems.of(ad._st.player)
    if not M.noEffect and M.targetDamaged and ad:roll(0, 99) < p0
        and M.move and M.move.flags and math.floor((tonumber(M.move.flags) or 0) / 32) % 2 == 1
        and ad:hp(target) > 0 then
      Secondary.set(M, "FLINCH", false, false, false)
      return true
    end
  elseif he == H.SHELL_BELL then
    if not M.noEffect and user ~= target and ad:hp(user) ~= ad:maxHp(user) and ad:hp(user) > 0 then
      local amt = math.floor(M.firstDmg / math.max(1, param))
      if amt == 0 then amt = 1 end
      M.firstDmg = 0
      item_anim(ad, user)
      say_id(ad, "STRINGID_PKMNSITEMRESTOREDHPALITTLE", { scrActive = user, lastItem = item })
      ad:heal(user, amt)
      return true
    end
  end
  return false
end

-- pokefirered/src/battle_util.c:2532
function HeldItems.onSwitchIn(ad, b)
  if not b then return false end
  local he, _, item = HeldItems.of(b)
  if he == H.DOUBLE_PRIZE then
    ad._st.moneyMultiplier = 2
  elseif he == H.RESTORE_STATS then
    return white_herb(ad, b, item)
  end
  return false
end

-- pokefirered/src/battle_script_commands.c:1596
function HeldItems.rollFocusBand(ad, target)
  local he, param = HeldItems.of(target)
  if he == H.FOCUS_BAND and ad:roll(0, 99) < param then
    target.expFocusBanded = true
    return true
  end
  return false
end

-- pokefirered/data/battle_scripts_1.s:4340
function HeldItems.focusBandMessage(ad, target)
  ad:playAnim("general", "FOCUS_BAND", target, target)
  say_id(ad, "STRINGID_PKMNHUNGONWITHX", { def = target, lastItem = HeldItems.itemOf(target) })
end

return HeldItems
