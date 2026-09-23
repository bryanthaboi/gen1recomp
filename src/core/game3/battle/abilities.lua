local Rules = require("src.core.game3.battle.rules")
local Types = require("src.core.game3.battle.types")
local Secondary = require("src.core.game3.battle.effects.secondary")
local RomText = require("src.core.game3.rom_text")
local State = require("src.core.game3.battle.state")

local Abilities = {}

local ID_BY_NAME
function Abilities.id(ab)
  if not ID_BY_NAME then
    ID_BY_NAME = {}
    for id, key in pairs(require("src.core.game3.battle.adapter").ABILITY_BY_ID) do ID_BY_NAME[key] = id end
  end
  return assert(ID_BY_NAME[ab], "unknown ability " .. tostring(ab))
end

function Abilities.name(ab)
  return require("src.core.game3.pokemon").abilityName(Abilities.id(ab))
end

local function say_id(ad, id, fill)
  ad:sayText(id, fill)
end

-- src/battle_main.c:601
local STATUS_WORD = {
  PSN = "gText_Poison", TOX = "gText_Poison", SLP = "gText_Sleep", PAR = "gText_Paralysis",
  BRN = "gText_Burn", FRZ = "gText_Ice",
}

-- pokefirered/src/battle_util.c:31
local SOUND_MOVES = { [45] = true, [46] = true, [47] = true, [48] = true, [103] = true, [173] = true,
  [253] = true, [319] = true, [320] = true, [304] = true }
Abilities.SOUND_MOVES = SOUND_MOVES

local SPECIES_CASTFORM = 385

local function ab_id(ad, b) return Abilities.id(ad:abilityOf(b)) end

local function is_type(b, t)
  if not b then return false end
  return b.type1 == t or b.type2 == t
end

local function set_type(b, t)
  b.type1 = t
  b.type2 = nil
end

local function gender_of(b)
  local mon = b and b.mon
  if not mon then return "U" end
  local g = mon.gender
  if g == "M" or g == "F" or g == "U" then return g end
  local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
  if ok and Pokemon and Pokemon.gender then
    local ok2, gg = pcall(Pokemon.gender, b.species or mon.species, mon.personality)
    if ok2 and gg then return gg end
  end
  return "U"
end
Abilities.genderOf = gender_of

local function weather_active(ad)
  return Rules.weather.effective(ad._st, ad)
end

local function weather_permanent(st, kind)
  return Rules.weather.kind(st.weather) == kind and (tonumber(st.weatherTurns) or 0) <= 0
end

-- pokefirered/src/battle_util.c:1611
function Abilities.castformChange(ad, b)
  if not b or tonumber(b.species) ~= SPECIES_CASTFORM or ad:abilityOf(b) ~= "FORECAST" or ad:hp(b) <= 0 then
    return 0
  end
  local w = weather_active(ad)
  if not w and not is_type(b, Types.ID.NORMAL) then
    set_type(b, Types.ID.NORMAL)
    return 1
  end
  if not w then return 0 end
  local form = 0
  if w ~= "RAIN" and w ~= "SUN" and w ~= "HAIL" and not is_type(b, Types.ID.NORMAL) then
    set_type(b, Types.ID.NORMAL); form = 1
  end
  if w == "SUN" and not is_type(b, Types.ID.FIRE) then set_type(b, Types.ID.FIRE); form = 2 end
  if w == "RAIN" and not is_type(b, Types.ID.WATER) then set_type(b, Types.ID.WATER); form = 3 end
  if w == "HAIL" and not is_type(b, Types.ID.ICE) then set_type(b, Types.ID.ICE); form = 4 end
  return form
end

-- pokefirered/data/battle_scripts_1.s:3972
local function castform_script(ad, b, form)
  b.expCastformForm = form - 1
  -- pokefirered/src/battle_script_commands.c:9293
  local arg = ((b.substituteHP or 0) > 0) and (form - 1 + 128) or (form - 1)
  ad:playAnim("general", "CASTFORM_CHANGE", b, b, arg)
  say_id(ad, "STRINGID_PKMNTRANSFORMED", { scrActive = b })
end

-- pokefirered/src/battle_util.c:2169
function Abilities.forecast(ad)
  for _, b in ipairs(ad:activeBattlers()) do
    if ad:abilityOf(b) == "FORECAST" then
      local form = Abilities.castformChange(ad, b)
      if form ~= 0 then
        castform_script(ad, b, form)
        return true
      end
    end
  end
  return false
end

local function weather_form_changes(ad)
  for _ = 1, 2 do
    if not Abilities.forecast(ad) then break end
  end
end

-- pokefirered/src/battle_util.c:1698
function Abilities.ghostBlocks(st, ab)
  return st and st.ghostBattle and not st.ghostUnveiled and (ab == "INTIMIDATE" or ab == "TRACE") or false
end

-- pokefirered/src/battle_util.c:1704
function Abilities.switchIn(ad, b)
  if not b or ad:isFainted(b) then return false end
  local st = ad._st
  local ab = ad:abilityOf(b)
  if Abilities.ghostBlocks(st, ab) then return false end
  if ab == "DRIZZLE" then
    if not weather_permanent(st, "RAIN") then
      st.weather, st.weatherTurns = "RAIN", 0
      say_id(ad, "STRINGID_PKMNMADEITRAIN", { scrActive = b, scrActiveAbility = Abilities.id(ab) })
      ad:playAnim("general", "RAIN_CONTINUES", nil, nil)
      weather_form_changes(ad)
      return true
    end
  elseif ab == "SAND_STREAM" then
    if not weather_permanent(st, "SAND") then
      st.weather, st.weatherTurns = "SAND", 0
      say_id(ad, "STRINGID_PKMNSXWHIPPEDUPSANDSTORM", { scrActive = b, scrActiveAbility = Abilities.id(ab) })
      ad:playAnim("general", "SANDSTORM_CONTINUES", nil, nil)
      weather_form_changes(ad)
      return true
    end
  elseif ab == "DROUGHT" then
    if not weather_permanent(st, "SUN") then
      st.weather, st.weatherTurns = "SUN", 0
      say_id(ad, "STRINGID_PKMNSXINTENSIFIEDSUN", { scrActive = b, scrActiveAbility = Abilities.id(ab) })
      ad:playAnim("general", "SUN_CONTINUES", nil, nil)
      weather_form_changes(ad)
      return true
    end
  elseif ab == "INTIMIDATE" then
    if not b.expIntimidated then
      b.expIntimidatePending = true
      b.expIntimidated = true
    end
  elseif ab == "FORECAST" then
    local form = Abilities.castformChange(ad, b)
    if form ~= 0 then
      castform_script(ad, b, form)
      return true
    end
  elseif ab == "TRACE" then
    if not b.expTraced then
      b.expTracePending = true
      b.expTraced = true
    end
  elseif ab == "CLOUD_NINE" or ab == "AIR_LOCK" then
    for _, o in ipairs(ad:activeBattlers()) do
      local form = Abilities.castformChange(ad, o)
      if form ~= 0 then
        castform_script(ad, o, form)
        return true
      end
    end
  end
  return false
end

-- pokefirered/data/battle_scripts_1.s:3983
local function intimidate_one(ad, b, foe)
  if not (foe and not ad:isFainted(foe) and (foe.substituteHP or 0) <= 0) then return end
  local fab = ad:abilityOf(foe)
  if fab == "CLEAR_BODY" or fab == "HYPER_CUTTER" or fab == "WHITE_SMOKE" then
    -- src/battle_script_commands.c:9181
    say_id(ad, "STRINGID_PREVENTEDFROMWORKING", {
      def = foe, defAbility = Abilities.id(fab), scrActive = b, buff1 = Abilities.name(ad:abilityOf(b)),
    })
  else
    local side = ad:ownSide(foe)
    if side and (side.expMistTurns or 0) > 0 then
      if not foe._statLoweredMsg then
        foe._statLoweredMsg = true
        say_id(ad, "STRINGID_PKMNPROTECTEDBYMIST", { scrActive = foe })
      end
    elseif (foe.stages.attack or 0) > -6 then
      foe.stages.attack = foe.stages.attack - 1
      ad:playAnim("general", "STATS_CHANGE", foe, foe, Secondary.statAnimArg("attack", -1))
      say_id(ad, "STRINGID_PKMNCUTSATTACKWITH", { scrActive = b, scrActiveAbility = ab_id(ad, b), def = foe })
    end
  end
end

function Abilities.runIntimidate(ad)
  for _, b in ipairs(ad:activeBattlers()) do
    if b.expIntimidatePending and ad:abilityOf(b) == "INTIMIDATE" then
      b.expIntimidatePending = nil
      if ad._st and ad._st.double then
        -- pokefirered/src/battle_script_commands.c:9174
        for _, foe in ipairs(ad:foesOf(b)) do intimidate_one(ad, b, foe) end
      else
        intimidate_one(ad, b, ad:foeOf(b))
      end
      return true
    end
  end
  return false
end

-- pokefirered/src/battle_util.c:2231
function Abilities.runTrace(ad)
  for _, b in ipairs(ad:activeBattlers()) do
    if b.expTracePending and ad:abilityOf(b) == "TRACE" then
      local foe = ad:foeOf(b)
      local st = ad._st
      if st and st.double then
        -- pokefirered/src/battle_util.c:2243
        local State = require("src.core.game3.battle.state")
        local side = (b.id % 2 == 0) and 1 or 0
        local t1, t2 = State.battler(st, side), State.battler(st, side + 2)
        local ok1 = t1 and ad:abilityOf(t1) and ad:hp(t1) > 0
        local ok2 = t2 and ad:abilityOf(t2) and ad:hp(t2) > 0
        if ok1 and ok2 then
          foe = State.battler(st, ad:roll(0, 1) * 2 + side)
        elseif ok1 then
          foe = t1
        elseif ok2 then
          foe = t2
        else
          foe = nil
        end
      end
      local fab = foe and ad:abilityOf(foe)
      if fab and ad:hp(foe) > 0 then
        b.expTracePending = nil
        b.expTracedAbility = fab
        -- src/battle_util.c:2281
        say_id(ad, "STRINGID_PKMNTRACED", {
          scrActive = b, buff1 = State.prefixedName(st, foe), buff2 = Abilities.name(fab),
        })
        return true
      end
    end
  end
  return false
end

-- pokefirered/src/battle_util.c:1816
function Abilities.endTurn(ad, b)
  if not b or ad:hp(b) <= 0 then return false end
  local ab = ad:abilityOf(b)
  if ab == "RAIN_DISH" then
    if weather_active(ad) == "RAIN" and ad:maxHp(b) > ad:hp(b) then
      local amt = math.floor(ad:maxHp(b) / 16)
      if amt == 0 then amt = 1 end
      say_id(ad, "STRINGID_PKMNSXRESTOREDHPALITTLE2", { atk = b, atkAbility = Abilities.id(ab) })
      ad:heal(b, amt)
      return true
    end
  elseif ab == "SHED_SKIN" then
    local s = ad:status(b)
    if s and ad:roll(0, 2) % 3 == 0 then
      local word = STATUS_WORD[s]
      ad:clearStatus(b)
      b.expNightmare = nil
      say_id(ad, "STRINGID_PKMNSXCUREDYPROBLEM", {
        scrActive = b, scrActiveAbility = Abilities.id(ab), buff1 = RomText.plain(word),
      })
      return true
    end
  elseif ab == "SPEED_BOOST" then
    if (b.stages.speed or 0) < 6 and (b.isFirstTurn or 0) ~= 2 then
      b.stages.speed = (b.stages.speed or 0) + 1
      ad:playAnim("general", "STATS_CHANGE", b, b, Secondary.statAnimArg("speed", 1))
      say_id(ad, "STRINGID_PKMNRAISEDSPEED", { scrActive = b, scrActiveAbility = Abilities.id(ab) })
      return true
    end
  elseif ab == "TRUANT" then
    b.expTruantCounter = ((b.expTruantCounter or 0) == 0) and 1 or 0
  end
  return false
end

-- pokefirered/src/battle_util.c:1337
function Abilities.truantLoafs(ad, b)
  return ad:abilityOf(b) == "TRUANT" and (b.expTruantCounter or 0) ~= 0
end

-- pokefirered/src/battle_util.c:1874
function Abilities.soundproofBlocks(M)
  local ad, target = M.adapter, M.target
  if not target or target == M.user then return false end
  if ad:abilityOf(target) ~= "SOUNDPROOF" or not SOUND_MOVES[M.mnum or -1] then return false end
  if M.user.expLockedMove then M.noPP = true end
  M:attackString()
  M:ppReduce()
  say_id(ad, "STRINGID_PKMNSXBLOCKSY", { def = target, defAbility = ab_id(ad, target), currentMove = M.moveName })
  M.anim.statusOnly = true
  M.anim.missed = true
  M.noEffect = true
  return true
end

-- pokefirered/src/battle_util.c:1891
function Abilities.absorb(M)
  local ad, user, target = M.adapter, M.user, M.target
  if M.absorbChecked or not target or target == user then return false end
  M.absorbChecked = true
  local ab = ad:abilityOf(target)
  local mt = tonumber(M.moveType or (M.move and M.move.type)) or 0
  local power = tonumber(M.move and M.move.power) or 0
  local kind
  if ab == "VOLT_ABSORB" and mt == Types.ID.ELECTRIC and power ~= 0 then kind = "hp"
  elseif ab == "WATER_ABSORB" and mt == Types.ID.WATER and power ~= 0 then kind = "hp"
  elseif ab == "FLASH_FIRE" and mt == Types.ID.FIRE and ad:status(target) ~= "FRZ" then kind = "fire" end
  if not kind then return false end
  M:attackString()
  M.absorbed = true
  M.noEffect = true
  M.anim.missed = true
  if kind == "fire" then
    if not target.expFlashFire then
      target.expFlashFire = true
      say_id(ad, "STRINGID_PKMNRAISEDFIREPOWERWITH", { def = target, defAbility = Abilities.id(ab) })
    else
      say_id(ad, "STRINGID_PKMNSXMADEYINEFFECTIVE", {
        def = target, defAbility = Abilities.id(ab), currentMove = M.moveName,
      })
    end
    return true
  end
  if ad:hp(target) >= ad:maxHp(target) then
    say_id(ad, "STRINGID_PKMNSXMADEYUSELESS", { def = target, defAbility = Abilities.id(ab), currentMove = M.moveName })
  else
    local amt = math.floor(ad:maxHp(target) / 4)
    if amt == 0 then amt = 1 end
    ad:heal(target, amt)
    say_id(ad, "STRINGID_PKMNRESTOREDHPUSING", { def = target, defAbility = Abilities.id(ab) })
  end
  return true
end

-- src/battle_message.c:1076
local STATUS_BY_ABILITY = {
  PAR = "STRINGID_PKMNWASPARALYZEDBY",
  PSN = "STRINGID_PKMNPOISONEDBY",
  BRN = "STRINGID_PKMNBURNEDBY",
  SLP = "STRINGID_PKMNMADESLEEP",
}

-- pokefirered/src/battle_script_commands.c:2110
function Abilities.applyStatus(ad, holder, victim, status, primary, M)
  if not victim or ad:hp(victim) <= 0 then return false end
  if (victim.substituteHP or 0) > 0 and victim ~= (M and M.user) then return false end
  local vab = ad:abilityOf(victim)
  local function prevents()
    if M then
      say_id(ad, "STRINGID_PKMNSXPREVENTSYSZ", {
        atk = M.user, atkAbility = ab_id(ad, M.user), def = M.target, defAbility = ab_id(ad, M.target),
      })
    end
    return false
  end
  local function no_effect()
    say_id(ad, "STRINGID_PKMNSXHADNOEFFECTONY", { scrActive = holder, scrActiveAbility = ab_id(ad, holder), eff = victim })
    return false
  end
  if status == "SLP" then
    if ad:status(victim) then return false end
    if vab ~= "SOUNDPROOF" and ad:uproarActive() then return false end
    if vab == "VITAL_SPIRIT" or vab == "INSOMNIA" then return false end
  elseif status == "PSN" or status == "TOX" then
    if vab == "IMMUNITY" and primary then return prevents() end
    if (is_type(victim, Types.ID.POISON) or is_type(victim, Types.ID.STEEL)) and primary then return no_effect() end
    if is_type(victim, Types.ID.POISON) or is_type(victim, Types.ID.STEEL) then return false end
    if ad:status(victim) or vab == "IMMUNITY" then return false end
  elseif status == "BRN" then
    if vab == "WATER_VEIL" and primary then return prevents() end
    if is_type(victim, Types.ID.FIRE) and primary then return no_effect() end
    if is_type(victim, Types.ID.FIRE) or vab == "WATER_VEIL" or ad:status(victim) then return false end
  elseif status == "PAR" then
    if vab == "LIMBER" then
      if primary then return prevents() end
      return false
    end
    if ad:status(victim) then return false end
  else
    return false
  end
  ad:applyStatus(victim, status, holder, { force = true, ignoreSafeguard = true })
  ad:statusAnim(victim, status)
  if status ~= "SLP" then ad._syncEffect = { status = status } end
  if status == "TOX" then
    say_id(ad, "STRINGID_PKMNBADLYPOISONED", { eff = victim })
  else
    say_id(ad, STATUS_BY_ABILITY[status], { scrActive = holder, scrActiveAbility = ab_id(ad, holder), eff = victim })
  end
  return true
end

local function contact(M)
  local f = M.move and M.move.flags
  return f ~= nil and (tonumber(f) or 0) % 2 == 1
end

-- pokefirered/src/battle_util.c:1964
function Abilities.onDamage(M)
  local ad, user, target = M.adapter, M.user, M.target
  if not target or target == user or M.noEffect or not M.targetDamaged then return false end
  local ab = ad:abilityOf(target)
  local mt = tonumber(M.moveType or (M.move and M.move.type)) or 0
  if ab == "COLOR_CHANGE" then
    if M.mnum ~= 165 and (tonumber(M.move.power) or 0) ~= 0 and not is_type(target, mt) and ad:hp(target) > 0 then
      set_type(target, mt)
      say_id(ad, "STRINGID_PKMNCHANGEDTYPEWITH", { def = target, defAbility = Abilities.id(ab), buff1 = Types.name(mt) })
      return true
    end
    return false
  end
  if ad:hp(user) <= 0 or not contact(M) then return false end
  if ab == "ROUGH_SKIN" then
    local amt = math.floor(ad:maxHp(user) / 16)
    if amt == 0 then amt = 1 end
    ad:applyHpLoss(user, amt)
    say_id(ad, "STRINGID_PKMNHURTSWITH", { def = target, defAbility = Abilities.id(ab), atk = user })
    M:tryFaintUser()
    return true
  elseif ab == "EFFECT_SPORE" then
    if ad:roll(0, 9) % 10 == 0 then
      local r
      repeat r = ad:roll(0, 3) % 4 until r ~= 0
      local status = ({ "SLP", "PSN", "PAR" })[r]
      Abilities.applyStatus(ad, target, user, status, false, M)
      return true
    end
  elseif ab == "POISON_POINT" or ab == "STATIC" or ab == "FLAME_BODY" then
    if ad:roll(0, 2) % 3 == 0 then
      local status = (ab == "POISON_POINT" and "PSN") or (ab == "STATIC" and "PAR") or "BRN"
      Abilities.applyStatus(ad, target, user, status, false, M)
      return true
    end
  elseif ab == "CUTE_CHARM" then
    if ad:hp(target) > 0 and ad:roll(0, 2) % 3 == 0 and ad:abilityOf(user) ~= "OBLIVIOUS" then
      local ug, tg = gender_of(user), gender_of(target)
      if ug ~= tg and not user.expInfatuated and ug ~= "U" and tg ~= "U" then
        user.expInfatuated = true
        user.expInfatuatedBy = target.side
        user.expInfatuatedWith = target
        ad:playAnim("status", "INFATUATION", user, user)
        say_id(ad, "STRINGID_PKMNSXINFATUATEDY", { def = target, defAbility = Abilities.id(ab), atk = user })
        return true
      end
    end
  end
  return false
end

-- pokefirered/src/battle_util.c:2087
function Abilities.immunityCure(ad)
  local any = false
  for _, b in ipairs(ad:activeBattlers()) do
    local ab = ad:abilityOf(b)
    local s = ad:status(b)
    local word, kind
    if ab == "IMMUNITY" and (s == "PSN" or s == "TOX") then word, kind = "gText_Poison", 1
    elseif ab == "OWN_TEMPO" and (b.confusionTurns or 0) > 0 then word, kind = "gText_Confusion", 2
    elseif ab == "LIMBER" and s == "PAR" then word, kind = "gText_Paralysis", 1
    elseif (ab == "INSOMNIA" or ab == "VITAL_SPIRIT") and s == "SLP" then
      b.expNightmare = nil
      word, kind = "gText_Sleep", 1
    elseif ab == "WATER_VEIL" and s == "BRN" then word, kind = "gText_Burn", 1
    elseif ab == "MAGMA_ARMOR" and s == "FRZ" then word, kind = "gText_Ice", 1
    elseif ab == "OBLIVIOUS" and b.expInfatuated then word, kind = "gText_Love", 3 end
    if kind then
      if kind == 1 then ad:clearStatus(b)
      elseif kind == 2 then b.confusionTurns = nil
      else b.expInfatuated, b.expInfatuatedWith, b.expInfatuatedBy = nil, nil, nil end
      say_id(ad, "STRINGID_PKMNSXCUREDYPROBLEM", {
        scrActive = b, scrActiveAbility = Abilities.id(ab), buff1 = RomText.plain(word),
      })
      any = true
    end
  end
  return any
end

-- pokefirered/src/battle_util.c:2185
function Abilities.synchronize(M, holder, victim)
  local ad = M.adapter
  local pend = ad._syncEffect
  if not pend or not holder or ad:abilityOf(holder) ~= "SYNCHRONIZE" then return false end
  ad._syncEffect = nil
  local status = pend.status
  if status == "TOX" then status = "PSN" end
  Abilities.applyStatus(ad, holder, victim, status, true, M)
  return true
end

-- pokefirered/src/battle_main.c:3002
function Abilities.escapeBlocker(ad, b)
  if ad._st and ad._st.double then
    for _, foe in ipairs(ad:foesOf(b)) do
      if not ad:isFainted(foe) then
        local fab = ad:abilityOf(foe)
        if fab == "SHADOW_TAG" then return foe, fab end
        if fab == "ARENA_TRAP" and ad:abilityOf(b) ~= "LEVITATE" and not is_type(b, Types.ID.FLYING) then
          return foe, fab
        end
      end
    end
    -- pokefirered/src/battle_main.c:3036
    if is_type(b, Types.ID.STEEL) then
      for _, o in ipairs(ad:activeBattlers()) do
        if o ~= b and not ad:isFainted(o) and ad:abilityOf(o) == "MAGNET_PULL" then return o, "MAGNET_PULL" end
      end
    end
    return nil
  end
  local foe = ad:foeOf(b)
  if not foe or ad:isFainted(foe) then return nil end
  local fab = ad:abilityOf(foe)
  if fab == "SHADOW_TAG" then return foe, fab end
  if fab == "ARENA_TRAP" and ad:abilityOf(b) ~= "LEVITATE" and not is_type(b, Types.ID.FLYING) then
    return foe, fab
  end
  if fab == "MAGNET_PULL" and is_type(b, Types.ID.STEEL) then return foe, fab end
  return nil
end

-- pokefirered/src/battle_script_commands.c:9197
function Abilities.switchOut(ad, b)
  if b and ad:abilityOf(b) == "NATURAL_CURE" and ad:status(b) then
    ad:clearStatus(b)
    local State = require("src.core.game3.battle.state")
    local pm = State.partyMon(b)
    if pm then pm.status = nil end
    return true
  end
  return false
end

return Abilities
