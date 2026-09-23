-- engine/link/link.asm:1970 CheckTimeCapsuleCompatibility
-- engine/link/link.asm:640 Link_PrepPartyData_Gen1, :930 Link_ConvertPartyStruct1to2

local Mon = require("src.battle.gen2.Mon")
local Mail = require("src.core.gen2.Mail")
local Stats = require("src.pokemon.Stats")
local Growth = require("src.pokemon.Growth")

local Convert = {}

Convert.STATUS_1TO2 = {
  SLP = "sleep", PSN = "poison", BRN = "burn",
  PAR = "paralyze", FRZ = "freeze",
}

-- engine/link/link.asm:980
Convert.STATUS_2TO1 = {
  sleep = "SLP", poison = "PSN", toxic = "PSN", burn = "BRN",
  paralyze = "PAR", freeze = "FRZ",
}

-- engine/link/time_capsule.asm:41
Convert.TYPE_EXEMPT = { MAGNEMITE = true, MAGNETON = true }

Convert.DEFAULT_HAPPINESS = 70 -- engine/link/link.asm:1067

local function displayName(registry, id)
  local def = registry and registry[id]
  local name = def and def.name
  if type(name) == "string" and name ~= "" then return name end
  return tostring(id):gsub("_", " ")
end

local function baseStatsOf(def)
  return (def and def.baseStats) or {}
end

local function copyStatExp(statExp)
  statExp = statExp or {}
  local special = statExp.special
  if special == nil then
    special = statExp.specialAttack or statExp.specialDefense
  end
  return {
    hp = statExp.hp or 0,
    attack = statExp.attack or 0,
    defense = statExp.defense or 0,
    speed = statExp.speed or 0,
    special = special or 0,
  }
end

local function copyDVs(dvs)
  dvs = dvs or {}
  local special = dvs.special
  if special == nil then
    special = dvs.specialAttack or dvs.specialDefense
  end
  local out = {
    attack = dvs.attack or 0,
    defense = dvs.defense or 0,
    speed = dvs.speed or 0,
    special = special or 0,
  }
  out.hp = Mon.hpDV(out)
  return out
end

local function scaleHp(hp, oldMax, newMax)
  hp = tonumber(hp)
  if hp == nil then return newMax end
  if not oldMax or oldMax <= 0 then return newMax end
  if hp <= 0 then return 0 end
  if hp >= oldMax then return newMax end
  local scaled = math.floor(hp * newMax / oldMax + 0.5)
  return math.max(1, math.min(newMax, scaled))
end

local function ppBonus(base, ups)
  return (base or 0) + (ups or 0) * math.floor((base or 0) / 5)
end


local function entry(list, kind, text, extra)
  local row = extra or {}
  row.kind = kind
  row.text = text
  list[#list + 1] = row
  return row
end

local function newReport()
  return { lost = {}, changed = {} }
end

local function levelOf(mon)
  return math.max(1, math.min(100, math.floor(tonumber(mon.level) or 1)))
end

-- engine/link/link.asm:930 Link_ConvertPartyStruct1to2

function Convert.toGen2(mon, gen1Data, gen2Data)
  if type(mon) ~= "table" then return nil, "not_a_mon" end
  local def2 = gen2Data and gen2Data.pokemon and gen2Data.pokemon[mon.species]
  if not def2 then return nil, "species_unknown" end
  local def1 = gen1Data and gen1Data.pokemon and gen1Data.pokemon[mon.species]

  local report = newReport()
  local level = levelOf(mon)
  local dvs = copyDVs(mon.dvs)
  local statExp = copyStatExp(mon.statExp)
  local stats = Mon.stats(baseStatsOf(def2), dvs, level, statExp)

  local oldStats = mon.stats
  if not (oldStats and oldStats.hp) then
    oldStats = Stats.calc(def1 or { baseStats = baseStatsOf(def2) }, level,
      dvs, statExp)
  end
  local oldSpecial = oldStats.special
  if oldSpecial and (oldSpecial ~= stats.specialAttack
    or oldSpecial ~= stats.specialDefense) then
    -- engine/link/link.asm:1042
    entry(report.changed, "special_split",
      ("SPECIAL SPLIT %d -> %d/%d"):format(oldSpecial, stats.specialAttack,
        stats.specialDefense),
      { from = oldSpecial, specialAttack = stats.specialAttack,
        specialDefense = stats.specialDefense })
  end

  local hp = scaleHp(mon.hp, oldStats.hp, stats.hp)
  if oldStats.hp ~= stats.hp then
    entry(report.changed, "hp",
      ("HP %d/%d -> %d/%d"):format(math.min(tonumber(mon.hp) or 0,
        oldStats.hp), oldStats.hp, hp, stats.hp),
      { from = mon.hp, fromMax = oldStats.hp, to = hp, toMax = stats.hp })
  end

  local growth = Mon.growthFor(gen2Data, def2.growthRate)
  local experience = Mon.experienceForLevel(growth, level)
  if tonumber(mon.exp) and math.floor(mon.exp) ~= experience then
    entry(report.changed, "experience",
      ("EXP %d -> %d"):format(math.floor(mon.exp), experience),
      { from = math.floor(mon.exp), to = experience })
  end

  local moves = {}
  for _, mv in ipairs(mon.moves or {}) do
    local mdef = gen2Data.moves and gen2Data.moves[mv.id]
    local base = (mdef and mdef.pp) or 0
    local maxPp = ppBonus(base, mv.ppUps)
    moves[#moves + 1] = {
      id = mv.id,
      pp = math.max(0, math.min(tonumber(mv.pp) or maxPp, maxPp)),
      maxPp = maxPp,
    }
  end

  local status = mon.status and Convert.STATUS_1TO2[mon.status] or nil
  if mon.status and status ~= mon.status then
    entry(report.changed, "status",
      ("STATUS %s -> %s"):format(tostring(mon.status), tostring(status)),
      { from = mon.status, to = status })
  end

  local out = {
    species = mon.species,
    name = def2.name or mon.species,
    nickname = mon.nickname,
    level = level,
    experience = experience,
    dvs = dvs,
    statExp = statExp,
    stats = stats,
    hp = hp,
    maxHp = stats.hp,
    types = def2.types,
    moves = moves,
    item = nil,
    status = status,
    -- engine/link/link.asm:1067
    happiness = Convert.DEFAULT_HAPPINESS,
    pokerus = 0,
    caughtLevel = level,
    isEgg = false,
    ot = mon.ot,
    otName = mon.ot,
    otId = mon.otId,
    traded = mon.traded,
  }
  out.shiny = Mon.isShiny(dvs,
    { species = mon.species, def = def2, level = level })
  out.gender = Mon.gender(def2, dvs, { species = mon.species, level = level })

  entry(report.changed, "happiness",
    ("FRIENDSHIP SET TO %d"):format(Convert.DEFAULT_HAPPINESS),
    { to = Convert.DEFAULT_HAPPINESS })
  entry(report.changed, "caught_level",
    ("MET AT LEVEL %d"):format(level), { to = level })

  return out, report
end

-- engine/link/link.asm:1985 species, :1999 mail, :2016 move
function Convert.refusalFor(mon, gen2Data, gen1Data)
  if type(mon) ~= "table" then return "not_a_mon", {} end
  if mon.isEgg then return "is_egg", {} end
  local species1 = gen1Data and gen1Data.pokemon and gen1Data.pokemon[mon.species]
  if not species1 then
    return "species_too_new", { species = mon.species }
  end
  if mon.mail ~= nil or Mail.monHoldsMail(mon) then
    return "has_mail", { item = mon.item }
  end
  for _, mv in ipairs(mon.moves or {}) do
    if not (gen1Data.moves and gen1Data.moves[mv.id]) then
      return "move_too_new", { move = mv.id }
    end
  end
  return nil
end

function Convert.toGen1(mon, gen2Data, gen1Data)
  local reason, info = Convert.refusalFor(mon, gen2Data, gen1Data)
  if reason then return nil, reason, info end

  local def1 = gen1Data.pokemon[mon.species]
  local def2 = gen2Data and gen2Data.pokemon and gen2Data.pokemon[mon.species]
  local report = newReport()
  local level = levelOf(mon)
  local dvs = copyDVs(mon.dvs)
  local statExp = copyStatExp(mon.statExp)

  -- engine/link/link.asm:784, data/pokemon/gen1_base_special.asm:3
  local stats = Stats.calc(def1, level, dvs, statExp)

  local oldMax = tonumber(mon.maxHp)
  if not oldMax then
    local old = mon.stats
      or Mon.stats(baseStatsOf(def2), dvs, level, statExp)
    oldMax = old.hp
  end
  local oldSpA = mon.stats and mon.stats.specialAttack
  local oldSpD = mon.stats and mon.stats.specialDefense
  if oldSpA or oldSpD then
    entry(report.changed, "special_fold",
      ("SPECIAL FOLDED %s/%s -> %d"):format(tostring(oldSpA or "?"),
        tostring(oldSpD or "?"), stats.special),
      { specialAttack = oldSpA, specialDefense = oldSpD, to = stats.special })
  end

  local hp = scaleHp(mon.hp, oldMax, stats.hp)
  if oldMax ~= stats.hp then
    entry(report.changed, "hp",
      ("HP %d/%d -> %d/%d"):format(math.min(tonumber(mon.hp) or 0, oldMax),
        oldMax, hp, stats.hp),
      { from = mon.hp, fromMax = oldMax, to = hp, toMax = stats.hp })
  end

  local exp = Growth.expForLevel(def1.growthRate, level, gen1Data.growth_rates)
  if tonumber(mon.experience) and math.floor(mon.experience) ~= exp then
    entry(report.changed, "experience",
      ("EXP %d -> %d"):format(math.floor(mon.experience), exp),
      { from = math.floor(mon.experience), to = exp })
  end

  local moves = {}
  for _, mv in ipairs(mon.moves or {}) do
    local ups = Mon.ppUpsOf(mv, gen2Data)
    local base1 = (gen1Data.moves[mv.id] and gen1Data.moves[mv.id].pp) or 0
    local maxPp = ppBonus(base1, ups)
    moves[#moves + 1] = {
      id = mv.id,
      pp = math.max(0, math.min(tonumber(mv.pp) or maxPp, maxPp)),
      ppUps = ups,
    }
  end

  local status = mon.status and Convert.STATUS_2TO1[mon.status] or nil
  if mon.status and status ~= mon.status then
    entry(report.changed, "status",
      ("STATUS %s -> %s"):format(tostring(mon.status), tostring(status)),
      { from = mon.status, to = status })
  end

  if mon.item then
    -- engine/link/link.asm:756, :1078 TimeCapsule_ReplaceTeruSama
    entry(report.lost, "item",
      ("HELD ITEM LOST: %s"):format(displayName(gen2Data and gen2Data.items,
        mon.item)), { item = mon.item })
  end
  if tonumber(mon.happiness) then
    entry(report.lost, "happiness", "FRIENDSHIP LOST",
      { from = math.floor(mon.happiness) })
  end
  if tonumber(mon.pokerus) and mon.pokerus ~= 0 then
    entry(report.lost, "pokerus", "POKERUS LOST", { from = mon.pokerus })
  end
  if tonumber(mon.caughtLevel) then
    entry(report.lost, "caught_level", "MET DATA LOST",
      { from = math.floor(mon.caughtLevel) })
  end

  local out = {
    species = mon.species,
    level = level,
    exp = exp,
    dvs = dvs,
    statExp = statExp,
    stats = stats,
    hp = hp,
    catchRate = def1.catchRate,
    status = status,
    moves = moves,
    nickname = mon.nickname,
    ot = mon.ot or mon.otName,
    otId = mon.otId,
    traded = mon.traded,
  }
  return out, report
end

-- engine/link/time_capsule.asm:3 ValidateOTTrademon, :41 the type carve-out

function Convert.validateArrival(mon, destData)
  if type(mon) ~= "table" then return false, "not_a_mon" end
  local def = destData and destData.pokemon and destData.pokemon[mon.species]
  if not def then return false, "species_unknown" end
  -- engine/link/time_capsule.asm:27
  local level = tonumber(mon.level)
  if not level or level < 1 or level > 100 then return false, "level" end
  if Convert.TYPE_EXEMPT[mon.species] then return true end
  local claimed = mon.types
  if type(claimed) ~= "table" then return true end
  local want = def.types or {}
  local w1, w2 = want[1], want[2] or want[1]
  local c1, c2 = claimed[1], claimed[2] or claimed[1]
  if c1 ~= w1 or c2 ~= w2 then return false, "types" end
  return true
end

local REFUSAL_TEXT = {
  is_egg = function() return "EGGS CANNOT TRAVEL" end,
  has_mail = function() return "MON IS HOLDING MAIL" end,
  not_a_mon = function() return "NO MON" end,
  species_unknown = function(_, info)
    return ("SPECIES UNKNOWN: %s"):format(tostring(info.species or "?"))
  end,
  species_too_new = function(_, info)
    return ("SPECIES NOT IN GEN 1: %s"):format(
      tostring(info.species or "?"):gsub("_", " "))
  end,
  move_too_new = function(_, info)
    return ("MOVE ILLEGAL IN GEN 1: %s"):format(
      tostring(info.move or "?"):gsub("_", " "))
  end,
}

local function previewLines(mon, report, reason, info)
  local lines = {}
  if reason then
    local fn = REFUSAL_TEXT[reason]
    lines[1] = fn and fn(mon, info or {}) or reason:upper()
    return lines, false
  end
  for _, row in ipairs(report.lost) do lines[#lines + 1] = row.text end
  for _, row in ipairs(report.changed) do lines[#lines + 1] = row.text end
  if #lines == 0 then lines[1] = "NOTHING IS LOST" end
  return lines, true
end

local function convertOne(mon, toGen, fromData, toData)
  if toGen == 1 then
    local out, second, info = Convert.toGen1(mon, fromData, toData)
    if out then return out, second end
    return nil, second, info or {}
  end
  local out, second = Convert.toGen2(mon, fromData, toData)
  if out then return out, second end
  return nil, second, { species = mon and mon.species }
end

function Convert.preview(mon, fromGen, toGen, fromData, toData)
  local out, second, info = convertOne(mon, toGen, fromData, toData)
  if out then return previewLines(mon, second) end
  return previewLines(mon, nil, second, info)
end

-- engine/link/link.asm:2048 refuses the whole party; per-slot here instead
local function mapParty(party, toGen, fromData, toData)
  local converted, results = {}, {}
  for i, mon in ipairs(party or {}) do
    local out, second, info = convertOne(mon, toGen, fromData, toData)
    if out then
      converted[#converted + 1] = out
      results[i] = { index = i, ok = true, mon = out, report = second,
                     species = mon.species,
                     preview = previewLines(mon, second) }
    else
      results[i] = { index = i, ok = false, reason = second, info = info,
                     species = mon.species,
                     preview = previewLines(mon, nil, second, info) }
    end
  end
  return converted, results
end

function Convert.partyToGen1(party, gen2Data, gen1Data)
  return mapParty(party, 1, gen2Data, gen1Data)
end

function Convert.partyToGen2(party, gen1Data, gen2Data)
  return mapParty(party, 2, gen1Data, gen2Data)
end

function Convert.refusals(results)
  local out = {}
  for _, row in ipairs(results or {}) do
    if not row.ok then out[#out + 1] = row end
  end
  return out
end

return Convert
