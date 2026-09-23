-- FRLG experience award (pret Cmd_getexp + gExperienceTables).
-- Yields / growth rates come from ROM species meta (pokemon/meta.lua).
-- Level thresholds come from SummaryData (= pret experience_tables.h).

local Pokemon = require("src.core.game3.pokemon")
local SummaryData = require("src.core.game3.summary_data")
local ModRuntime = require("src.mods.Runtime")

local Experience = {}

Experience.MAX_LEVEL = 100

function Experience.expYield(species)
  species = tonumber(species) or (species and species.species) or 0
  local meta = Pokemon.speciesMeta(species)
  return (meta and tonumber(meta.expYield)) or 0
end

--- pret GROWTH_* index for this mon/species (ROM BaseStats.growthRate).
function Experience.growthRate(monOrSpecies)
  if type(monOrSpecies) == "table" then
    local gr = tonumber(monOrSpecies.growthRate)
    if gr then return gr % 6 end
    local sp = tonumber(monOrSpecies.species or monOrSpecies.speciesId)
    local meta = sp and Pokemon.speciesMeta(sp)
    return (meta and tonumber(meta.growthRate) or 0) % 6
  end
  local meta = Pokemon.speciesMeta(tonumber(monOrSpecies))
  return (meta and tonumber(meta.growthRate) or 0) % 6
end

function Experience.expForLevel(monOrGrowth, level)
  local growth = type(monOrGrowth) == "table" and Experience.growthRate(monOrGrowth) or (tonumber(monOrGrowth) or 0) % 6
  return SummaryData.expForLevel(growth, level)
end

--- Highest level whose threshold <= exp (pret GetLevelFromMonExp).
function Experience.levelForExp(monOrGrowth, exp)
  local growth = type(monOrGrowth) == "table" and Experience.growthRate(monOrGrowth) or (tonumber(monOrGrowth) or 0) % 6
  exp = math.max(0, tonumber(exp) or 0)
  local lv = 1
  while lv < Experience.MAX_LEVEL do
    local nextThresh = SummaryData.expForLevel(growth, lv + 1)
    if exp < nextThresh then break end
    lv = lv + 1
  end
  return lv
end

function Experience.progress(mon)
  return SummaryData.expProgress(mon, Experience.growthRate(mon))
end

--- Ensure mon.exp matches its growth curve at current level (new gifts / bad saves).
function Experience.syncExpToLevel(mon)
  if type(mon) ~= "table" then return mon end
  local growth = Experience.growthRate(mon)
  mon.growthRate = growth
  local level = math.max(1, math.min(Experience.MAX_LEVEL, tonumber(mon.level) or 1))
  mon.level = level
  local atLevel = SummaryData.expForLevel(growth, level)
  local nextLevel = level >= Experience.MAX_LEVEL and atLevel or SummaryData.expForLevel(growth, level + 1)
  local exp = tonumber(mon.exp)
  if exp == nil or exp < atLevel or (level < Experience.MAX_LEVEL and exp >= nextLevel) then
    mon.exp = atLevel
  end
  return mon
end

--- pret: calculatedExp = expYield * foeLevel / 7
-- then SAFE_DIV by participants (halved when any Exp.Share holder — deferred).
-- Per-recipient boosts: Lucky Egg ×1.5, trainer ×1.5, traded ×1.5 (floored *150/100).
function Experience.gainFor(foeSpecies, foeLevel, opts)
  opts = opts or {}
  local yield = Experience.expYield(foeSpecies)
  foeLevel = math.max(1, tonumber(foeLevel) or 1)
  local participants = math.max(1, tonumber(opts.participants) or 1)
  local calculated = math.floor(yield * foeLevel / 7)
  local amount = math.floor(calculated / participants)
  if amount < 1 then amount = 1 end
  -- Exp.Share party pass deferred: opts.expShareShare would add half-pool share
  if opts.luckyEgg then
    amount = math.floor(amount * 150 / 100)
  end
  if opts.trainer then
    amount = math.floor(amount * 150 / 100)
  end
  if opts.traded then
    amount = math.floor(amount * 150 / 100)
  end
  if amount < 1 then amount = 1 end
  return amount
end

local function get_mon_stats(mon)
  return {
    maxHp = tonumber(mon and (mon.maxHp or mon.maxhp)) or 1,
    atk = tonumber(mon and (mon.attack or mon.atk)) or 1,
    def = tonumber(mon and (mon.defense or mon.def)) or 1,
    spa = tonumber(mon and (mon.spAtk or mon.spa or mon.spatk)) or 1,
    spd = tonumber(mon and (mon.spDef or mon.spd or mon.spdef)) or 1,
    spe = tonumber(mon and (mon.speed or mon.spe)) or 1,
  }
end

local function apply_level_stats(mon, newLevel)
  local oldMax = tonumber(mon.maxHp) or 1
  local oldHp = tonumber(mon.hp) or oldMax
  mon.level = newLevel
  Pokemon.applyStats(mon)
  local newMax = tonumber(mon.maxHp) or oldMax
  mon.hp = math.min(newMax, oldHp + math.max(0, newMax - oldMax))
end

--- Add XP to mon using its ROM growth curve. Mutates mon.
-- Returns {
--   gained, fromLevel, toLevel, fromExp, toExp,
--   levels = {N,...},  -- each level reached
--   steps = {{level, fromRatio, toRatio, fillToOne}, ...} for bar anim
-- }
function Experience.apply(mon, amount)
  amount = math.max(0, math.floor(tonumber(amount) or 0))
  Experience.syncExpToLevel(mon)
  local growth = Experience.growthRate(mon)
  local fromLevel = tonumber(mon.level) or 1
  local fromExp = tonumber(mon.exp) or Experience.expForLevel(growth, fromLevel)
  local cap = SummaryData.expForLevel(growth, Experience.MAX_LEVEL)

  if fromLevel >= Experience.MAX_LEVEL or amount <= 0 then
    return {
      gained = 0,
      fromLevel = fromLevel,
      toLevel = fromLevel,
      fromExp = fromExp,
      toExp = fromExp,
      levels = {},
      steps = {},
    }
  end

  local rawGained = amount
  local newExp = math.min(cap, fromExp + amount)
  local applied = newExp - fromExp
  mon.exp = newExp

  local toLevel = Experience.levelForExp(growth, newExp)
  local levels, steps = {}, {}

  -- Bar steps: from current ratio → (fill to 1 per level-up) → final ratio
  local curLevel = fromLevel
  local curExp = fromExp
  while curLevel < toLevel do
    local nextThresh = SummaryData.expForLevel(growth, curLevel + 1)
    local curThresh = SummaryData.expForLevel(growth, curLevel)
    local span = math.max(1, nextThresh - curThresh)
    local fromRatio = math.max(0, math.min(1, (curExp - curThresh) / span))
    local oldStats = get_mon_stats(mon)
    steps[#steps + 1] = {
      level = curLevel,
      fromRatio = fromRatio,
      toRatio = 1,
      grewTo = curLevel + 1,
    }
    curLevel = curLevel + 1
    curExp = nextThresh
    levels[#levels + 1] = curLevel
    apply_level_stats(mon, curLevel)
    -- pokefirered/src/battle_script_commands.c:3298
    if ModRuntime.wants("pokemon.level_up") then
      local G3 = require("src.mods.Gen3Compat")
      local learnable, learnableIds = {}, {}
      for _, mv in ipairs(Pokemon.movesLearnedAt(tonumber(mon.species or mon.speciesId), curLevel)) do
        learnable[#learnable + 1] = G3.moveName(mv)
        learnableIds[#learnableIds + 1] = mv
      end
      ModRuntime.emit("pokemon.level_up", {
        mon = mon, level = curLevel, prevLevel = curLevel - 1,
        learnable = learnable, learnableIds = learnableIds,
      })
    end
    local newStats = get_mon_stats(mon)
    steps[#steps].hp = tonumber(mon.hp)
    steps[#steps].maxHp = tonumber(mon.maxHp)
    steps[#steps].oldStats = oldStats
    steps[#steps].newStats = newStats
  end

  -- Remainder into final level
  do
    local curThresh = SummaryData.expForLevel(growth, toLevel)
    local nextThresh = toLevel >= Experience.MAX_LEVEL and curThresh
      or SummaryData.expForLevel(growth, toLevel + 1)
    local span = math.max(1, nextThresh - curThresh)
    local fromRatio = (curLevel == fromLevel)
      and math.max(0, math.min(1, (fromExp - curThresh) / span))
      or 0
    local toRatio = toLevel >= Experience.MAX_LEVEL and 1
      or math.max(0, math.min(1, (newExp - curThresh) / span))
    if toRatio > fromRatio + 0.0001 or (#steps == 0 and applied > 0) then
      steps[#steps + 1] = {
        level = toLevel,
        fromRatio = fromRatio,
        toRatio = toRatio,
        grewTo = nil,
      }
    end
  end

  if toLevel > fromLevel then
    -- stats already applied per level; ensure final
    apply_level_stats(mon, toLevel)
  end

  return {
    gained = applied,
    rawGained = rawGained,
    fromLevel = fromLevel,
    toLevel = toLevel,
    fromExp = fromExp,
    toExp = newExp,
    levels = levels,
    steps = steps,
  }
end

-- pokefirered/src/battle_script_commands.c:3232
function Experience.recipientOpts(st, mon)
  local HeldItems = require("src.core.game3.battle.held_items")
  local Engine = require("src.core.game3.battle.engine")
  return {
    luckyEgg = HeldItems.effectOf(mon and (mon.item or mon.heldItem)) == HeldItems.HOLD.LUCKY_EGG,
    traded = Engine.isTradedMon(st, mon),
  }
end

--- Award XP for a defeated foe to participant party mons.
-- opts: trainer, participants (count), getOpts(mon, partyIndex) → luckyEgg/traded
-- Returns list of { mon, partyIndex, battler?, result }
-- pokefirered/src/battle_script_commands.c:3113
function Experience.awardFoe(st, foeBattler, opts)
  opts = opts or {}
  if not st or not foeBattler then return {} end
  local HeldItems = require("src.core.game3.battle.held_items")
  local foeMon = foeBattler.mon
  local foeSpecies = foeBattler.species or (foeMon and (foeMon.species or foeMon.speciesId))
  local foeLevel = (foeMon and foeMon.level) or foeBattler.level or 1
  local isTrainer = opts.trainer
  if isTrainer == nil then isTrainer = not st.wild end

  local sentIn = {}
  if opts.partyIndices then
    for _, pi in ipairs(opts.partyIndices) do sentIn[pi] = true end
  elseif foeBattler.participants and next(foeBattler.participants) then
    -- pokefirered/src/battle_script_commands.c:3123
    for pi in pairs(foeBattler.participants) do sentIn[pi] = true end
  elseif st.player and st.player.mon and (tonumber(st.player.mon.hp) or 0) > 0 then
    sentIn[st.player.partyIndex or 1] = true
  end
  local b0 = st.player
  local b2 = st.double and st.battlers and st.battlers[2] or nil
  local absent = st.absent or {}
  local function on_field(pi)
    if b0 and b0.partyIndex == pi and not absent[0] then return b0 end
    if b2 and b2.partyIndex == pi and not absent[2] then return b2 end
    return nil
  end
  -- pokefirered/src/battle_script_commands.c:3248
  local function getter_id(pi)
    if not st.double then return 0 end
    if b2 and b2.partyIndex == pi and not absent[2] then return 2 end
    if not absent[0] then return 0 end
    return 2
  end
  local party = st.playerParty or {}
  local function alive(mon)
    return mon and (tonumber(mon.species or mon.speciesId) or 0) ~= 0 and (tonumber(mon.hp) or 0) > 0
  end
  local function has_share(mon)
    return HeldItems.effectOf(mon and (mon.item or mon.heldItem)) == HeldItems.HOLD.EXP_SHARE
  end
  local viaSentIn, viaExpShare = 0, 0
  for i = 1, 6 do
    local mon = party[i]
    if alive(mon) then
      if sentIn[i] then viaSentIn = viaSentIn + 1 end
      if has_share(mon) then viaExpShare = viaExpShare + 1 end
    end
  end
  local calculated = math.floor(Experience.expYield(foeSpecies) * math.max(1, tonumber(foeLevel) or 1) / 7)
  local exp, shareExp
  if viaExpShare > 0 then
    exp = (viaSentIn > 0) and math.floor(math.floor(calculated / 2) / viaSentIn) or 0
    if exp == 0 then exp = 1 end
    shareExp = math.floor(math.floor(calculated / 2) / viaExpShare)
    if shareExp == 0 then shareExp = 1 end
  else
    exp = (viaSentIn > 0) and math.floor(calculated / viaSentIn) or 0
    if exp == 0 then exp = 1 end
    shareExp = 0
  end

  local friendshipCtx = { mapSec = Pokemon.currentMapSec(st.session) }

  local out = {}
  for pi = 1, 6 do
    local mon = party[pi]
    local share = mon and has_share(mon)
    if mon and (sentIn[pi] or share) and (tonumber(mon.level) or 1) < Experience.MAX_LEVEL and alive(mon) then
      local per = opts.getOpts and opts.getOpts(mon, pi) or Experience.recipientOpts(st, mon)
      local function vanilla_amount()
        local amount = sentIn[pi] and exp or 0
        if share then amount = amount + shareExp end
        if per.luckyEgg then amount = math.floor(amount * 150 / 100) end
        if isTrainer then amount = math.floor(amount * 150 / 100) end
        if per.traded then amount = math.floor(amount * 150 / 100) end
        return amount
      end
      local amount
      -- pokefirered/src/battle_script_commands.c:3230
      if ModRuntime.wantsHook("exp.gain") then
        local G3 = require("src.mods.Gen3Compat")
        amount = ModRuntime.call("exp.gain", function() return vanilla_amount() end, {
          defeatedDef = G3.speciesView(foeSpecies), level = foeLevel, isTrainer = isTrainer,
          participants = viaSentIn, traded = per.traded, luckyEgg = per.luckyEgg,
          expShare = share and true or false, mon = mon, index = pi,
          battle = st, loser = foeBattler,
        })
        amount = math.max(0, math.floor(tonumber(amount) or 0))
      else
        amount = vanilla_amount()
      end
      -- pokefirered/src/battle_script_commands.c:3271
      Pokemon.gainEVs(mon, foeSpecies)
      local result = Experience.apply(mon, amount)
      -- pokefirered/src/battle_script_commands.c:3314
      for _ = 1, #result.levels do
        Pokemon.adjustFriendship(mon, Pokemon.FRIENDSHIP_EVENT_GROW_LEVEL, friendshipCtx)
      end
      local fieldB
      if st.double then
        fieldB = on_field(pi)
        if fieldB then
          fieldB.mon = mon
          fieldB.fainted = (tonumber(mon.hp) or 0) <= 0
        end
      elseif st.player and st.player.partyIndex == pi then
        st.player.mon = mon
        st.player.fainted = (tonumber(mon.hp) or 0) <= 0
        fieldB = st.player
      end
      -- pokefirered/src/battle_script_commands.c:3278
      if ModRuntime.wants("battle.exp_gained") then
        ModRuntime.emit("battle.exp_gained", {
          battle = st, mon = mon, gained = result.gained, levels = result.levels,
          index = pi, battler = fieldB, battlerId = getter_id(pi),
        })
      end
      out[#out + 1] = {
        mon = mon,
        partyIndex = pi,
        battler = fieldB,
        expGetterBattlerId = getter_id(pi),
        amount = amount,
        boosted = per.traded and true or false,
        result = result,
      }
    end
  end
  return out
end

return Experience
