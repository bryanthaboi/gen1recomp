local Pokemon = require("src.pokemon.Pokemon")
local Stats = require("src.pokemon.Stats")
local Growth = require("src.pokemon.Growth")

local MonOps = {}

function MonOps.create(data, species, level, gen)
  if gen == 2 then
    local Mon = require("src.battle.gen2.Mon")
    local mon = Mon.new(data, species, level)
    assert(mon, "unknown species " .. tostring(species))
    return mon
  end
  return Pokemon.new(data, species, level)
end

function MonOps.recalc(data, mon, gen)
  if gen == 2 or (mon.stats and mon.stats.specialAttack) or mon.experience then
    require("src.battle.gen2.Mon").refreshStats(mon, data)
    return
  end
  local def = data.pokemon[mon.species]
  assert(def, "unknown species")
  mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
  mon.hp = math.max(0, math.min(mon.hp or mon.stats.hp, mon.stats.hp))
end

function MonOps.setLevel(data, mon, level, gen)
  level = math.max(1, math.min(100, math.floor(level)))
  local def = data.pokemon[mon.species]
  mon.level = level
  if gen == 2 or mon.experience ~= nil then
    local Mon = require("src.battle.gen2.Mon")
    local growth = Mon.growthFor(data, def.growthRate)
    mon.experience = Mon.experienceForLevel(growth, level)
    Mon.refreshStats(mon, data)
    return
  end
  mon.exp = Growth.expForLevel(def.growthRate, level)
  MonOps.recalc(data, mon, gen)
end

function MonOps.setMove(data, mon, slot, moveId)
  assert(slot >= 1 and slot <= 4)
  local mdef = data.moves[moveId]
  assert(type(mdef) == "table", "unknown move")
  mon.moves = mon.moves or {}
  mon.moves[slot] = {
    id = moveId,
    pp = mdef.pp + ((mon.moves[slot] and mon.moves[slot].ppUps) or 0) * math.floor(mdef.pp / 5),
    ppUps = mon.moves[slot] and mon.moves[slot].ppUps or nil,
    maxPp = mdef.pp,
  }
end

-- HP DV is derived from the low bits of the other four (Stats.randomDVs).
function MonOps.syncHpDv(dvs)
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4
         + (dvs.speed % 2) * 2 + (dvs.special % 2)
  return dvs
end

function MonOps.setDv(data, mon, key, value, gen)
  mon.dvs[key] = math.max(0, math.min(15, math.floor(value)))
  if key ~= "hp" then
    MonOps.syncHpDv(mon.dvs)
  end
  if gen == 2 or (mon.stats and mon.stats.specialAttack) then
    local Mon = require("src.battle.gen2.Mon")
    mon.dvs.hp = Mon.hpDV(mon.dvs)
    local def = data.pokemon[mon.species]
    if def then
      mon.gender = Mon.gender(def, mon.dvs, { species = mon.species, level = mon.level })
      mon.shiny = Mon.isShiny(mon.dvs, { species = mon.species, def = def, level = mon.level })
      local Unown = require("src.core.gen2.Unown")
      if mon.species == Unown.SPECIES then
        mon.unownLetter = Unown.letterFromDVs(mon.dvs)
      end
    end
  end
  MonOps.recalc(data, mon, gen)
end

-- Keep level; resync exp to the species growth curve (species changes).
-- Gold also copies def.name onto mon.name: the party list and SUMMARY print
-- that field when nickname is nil, so leaving the previous species' name
-- made a swapped mon still read as ABRA (or whoever was added first).
function MonOps.setSpecies(data, mon, species, gen)
  assert(data.pokemon[species], "unknown species")
  mon.species = species
  MonOps.setLevel(data, mon, mon.level, gen)
  if gen == 2 or mon.experience ~= nil or (mon.stats and mon.stats.specialAttack) then
    require("src.battle.gen2.Mon").syncIdentity(mon, data)
  end
end

return MonOps
