local Pokemon = require("src.pokemon.Pokemon")
local Stats = require("src.pokemon.Stats")
local Growth = require("src.pokemon.Growth")

local MonOps = {}

function MonOps.create(data, species, level, gen)
  level = math.max(1, math.min(100, math.floor(tonumber(level) or 5)))
  if gen == 3 then
    local PokemonG3 = require("src.core.game3.pokemon")
    local SummaryData = require("src.core.game3.summary_data")
    pcall(PokemonG3.install, nil)

    local spId = tonumber(species) or (PokemonG3.speciesFromName and PokemonG3.speciesFromName(tostring(species))) or 1
    local name = (PokemonG3.name and PokemonG3.name(spId)) or tostring(species)

    local personality = (love and love.math and love.math.random and love.math.random(0, 0xFFFFFFFF))
      or (math.floor(math.random() * 0x100000000) % 0x100000000)

    local ivs = {}
    for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
      ivs[k] = (love and love.math and love.math.random and love.math.random(0, 31)) or math.random(0, 31)
    end

    local meta = PokemonG3.speciesMeta and PokemonG3.speciesMeta(spId)
    local friendship = (meta and meta.friendship) or 70
    local growthRate = (meta and tonumber(meta.growthRate)) or 0
    local ability = PokemonG3.abilityId and PokemonG3.abilityId(spId, personality) or 0
    local gender = PokemonG3.gender and PokemonG3.gender(spId, personality) or "U"

    local moves, pp, maxPp = {}, {}, {}
    if PokemonG3.movesAtLevel then
      moves, pp, maxPp = PokemonG3.movesAtLevel(spId, level)
    end

    local monMoves = {}
    for slot = 1, 4 do
      local mvId = moves[slot]
      if mvId and mvId > 0 then
        local mvName = PokemonG3.moveName(mvId)
        monMoves[slot] = {
          id = mvId,
          moveId = mvId,
          pp = pp[slot] or 10,
          maxPp = maxPp[slot] or 10,
        }
      end
    end

    local mon = {
      species = spId,
      speciesId = spId,
      name = name,
      nickname = "",
      level = level,
      growthRate = growthRate,
      exp = SummaryData.expForLevel(growthRate, level),
      moves = monMoves,
      personality = personality,
      nature = PokemonG3.natureId and PokemonG3.natureId(personality) or 0,
      ivs = ivs,
      dvs = {
        attack = math.floor(ivs.atk / 2),
        defense = math.floor(ivs.def / 2),
        speed = math.floor(ivs.spe / 2),
        special = math.floor(ivs.spa / 2),
        hp = math.floor(ivs.hp / 2),
      },
      evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
      ability = ability,
      gender = gender,
      happiness = friendship,
      friendship = friendship,
      pokeball = 4, -- pokefirered/src/pokemon.c:1820
    }

    require("src.core.game3.save_mon").normalize(mon)
    mon.stats = {
      hp = mon.maxHp,
      attack = mon.attack,
      defense = mon.defense,
      speed = mon.speed,
      spAtk = mon.spAtk,
      spDef = mon.spDef,
      specialAttack = mon.spAtk,
      specialDefense = mon.spDef,
    }
    return mon
  elseif gen == 2 then
    local Mon = require("src.battle.gen2.Mon")
    local mon = Mon.new(data, species, level)
    assert(mon, "unknown species " .. tostring(species))
    return mon
  end
  return Pokemon.new(data, species, level)
end

function MonOps.recalc(data, mon, gen)
  if type(mon) ~= "table" then return end
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil)
    or (mon.ivs ~= nil) or (mon.evs ~= nil and mon.evs.spa ~= nil)
  if isG3 then
    local okP, PokemonG3 = pcall(require, "src.core.game3.pokemon")
    if okP and PokemonG3 then
      require("src.core.game3.save_mon").normalize(mon)
      mon.hp = math.max(0, math.min(mon.hp or mon.maxHp, mon.maxHp))
    end
    return
  end
  if gen == 2 or (mon.stats and mon.stats.specialAttack) or mon.experience then
    require("src.battle.gen2.Mon").refreshStats(mon, data)
    return
  end
  local def = data and data.pokemon and data.pokemon[mon.species]
  assert(def, "unknown species")
  mon.stats = Stats.calc(def, mon.level, mon.dvs, mon.statExp)
  mon.hp = math.max(0, math.min(mon.hp or mon.stats.hp, mon.stats.hp))
end

function MonOps.setLevel(data, mon, level, gen)
  if type(mon) ~= "table" then return end
  level = math.max(1, math.min(100, math.floor(level)))
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil) or (mon.ivs ~= nil)
  mon.level = level

  if isG3 then
    local SummaryData = require("src.core.game3.summary_data")
    local gr = require("src.core.game3.pokemon").growthRate(require("src.core.game3.pokemon").speciesOf(mon)) or mon.growthRate or 0
    if not gr then
      local okP, PokemonG3 = pcall(require, "src.core.game3.pokemon")
      local spId = tonumber(mon.speciesId) or tonumber(mon.species)
        or (okP and PokemonG3 and PokemonG3.speciesOf and PokemonG3.speciesOf(mon))
      local meta = okP and PokemonG3 and spId and PokemonG3.speciesMeta and PokemonG3.speciesMeta(spId)
      gr = (meta and tonumber(meta.growthRate))
        or (data and data.pokemon and (data.pokemon[mon.species] or (spId and data.pokemon[spId])) and (data.pokemon[mon.species] or data.pokemon[spId]).growthRate)
        or 0
    end
    mon.growthRate = gr
    mon.exp = SummaryData.expForLevel(gr, level)
    mon.experience = mon.exp
    MonOps.recalc(data, mon, gen)
    return
  end

  local def = data and data.pokemon and data.pokemon[mon.species]
  if gen == 2 or mon.experience ~= nil then
    local Mon = require("src.battle.gen2.Mon")
    local growth = Mon.growthFor(data, def and def.growthRate)
    mon.experience = Mon.experienceForLevel(growth, level)
    Mon.refreshStats(mon, data)
    return
  end
  mon.exp = Growth.expForLevel(def and def.growthRate or 0, level)
  MonOps.recalc(data, mon, gen)
end

function MonOps.clearMove(mon, slot)
  for _, key in ipairs({ "moves", "pp", "maxPp", "moveIds", "ppBonuses", "ppBonus", "ppUp" }) do
    if type(mon[key]) == "table" then mon[key][slot] = nil end
  end
  if type(mon.ppBonusesPacked) == "number" then
    local bit = require("bit")
    mon.ppBonusesPacked = bit.band(mon.ppBonusesPacked, bit.bnot(bit.lshift(3, (slot - 1) * 2)))
  end
end

function MonOps.setMove(data, mon, slot, moveId)
  assert(slot >= 1 and slot <= 4)
  local mdef = data and data.moves and data.moves[moveId]
  local numMove = tonumber(moveId)
  if not mdef and numMove then
    local okP, PokemonG3 = pcall(require, "src.core.game3.pokemon")
    if okP and PokemonG3 then
      local mName = PokemonG3.moveName(numMove)
      local bMove = PokemonG3.battleMove(numMove)
      mdef = {
        id = mName,
        moveId = numMove,
        name = mName,
        pp = (bMove and tonumber(bMove.pp)) or 10,
        maxPp = (bMove and tonumber(bMove.pp)) or 10,
      }
    end
  end
  assert(type(mdef) == "table", "unknown move: " .. tostring(moveId))
  mon.moves = mon.moves or {}
  local basePp = mdef.pp or 10
  if mon.speciesId ~= nil or mon.personality ~= nil then
    local nativeId = assert(tonumber(mdef.moveId or numMove), "unknown native move")
    MonOps.clearMove(mon, slot)
    mon.moves[slot] = nativeId
    mon.pp, mon.maxPp = mon.pp or {}, mon.maxPp or {}
    mon.pp[slot], mon.maxPp[slot] = basePp, basePp
    return
  end
  local currentUps = (mon.moves[slot] and mon.moves[slot].ppUps) or 0
  mon.moves[slot] = {
    id = mdef.id or mdef.name or tostring(moveId),
    moveId = mdef.moveId or numMove,
    pp = basePp + currentUps * math.floor(basePp / 5),
    ppUps = currentUps > 0 and currentUps or nil,
    maxPp = basePp,
  }
end

-- HP DV is derived from the low bits of the other four (Stats.randomDVs).
function MonOps.syncHpDv(dvs)
  if not dvs then return end
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4
         + (dvs.speed % 2) * 2 + (dvs.special % 2)
  return dvs
end

function MonOps.setDv(data, mon, key, value, gen)
  if type(mon) ~= "table" then return end
  mon.dvs = mon.dvs or { attack = 15, defense = 15, speed = 15, special = 15, hp = 15 }
  mon.dvs[key] = math.max(0, math.min(15, math.floor(value)))
  if key ~= "hp" then
    MonOps.syncHpDv(mon.dvs)
  end

  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil) or (mon.ivs ~= nil)
  if isG3 then
    mon.ivs = mon.ivs or {}
    mon.ivs.hp = math.min(31, (mon.dvs.hp or 0) * 2 + 1)
    mon.ivs.atk = math.min(31, (mon.dvs.attack or 0) * 2 + 1)
    mon.ivs.def = math.min(31, (mon.dvs.defense or 0) * 2 + 1)
    mon.ivs.spe = math.min(31, (mon.dvs.speed or 0) * 2 + 1)
    mon.ivs.spa = math.min(31, (mon.dvs.special or 0) * 2 + 1)
    mon.ivs.spd = math.min(31, (mon.dvs.special or 0) * 2 + 1)
  elseif gen == 2 or (mon.stats and mon.stats.specialAttack) then
    local Mon = require("src.battle.gen2.Mon")
    mon.dvs.hp = Mon.hpDV(mon.dvs)
    local def = data and data.pokemon and data.pokemon[mon.species]
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

function MonOps.setSpecies(data, mon, species, gen)
  if type(mon) ~= "table" then return end
  local isG3 = (gen == 3) or (mon.speciesId ~= nil) or (mon.personality ~= nil)
  if isG3 then
    local PokemonG3 = require("src.core.game3.pokemon")
    pcall(PokemonG3.install, nil)
    local spId = tonumber(species) or (PokemonG3.speciesFromName and PokemonG3.speciesFromName(tostring(species))) or 1
    local name = (PokemonG3.name and PokemonG3.name(spId)) or tostring(species)
    mon.species = spId
    mon.speciesNumbering = PokemonG3.NUMBERING_INTERNAL
    mon.speciesId = spId
    mon.name = name
    local meta = PokemonG3.speciesMeta and PokemonG3.speciesMeta(spId)
    mon.growthRate = (meta and tonumber(meta.growthRate)) or 0
    MonOps.setLevel(data, mon, mon.level or 5, gen)
    return
  end
  assert(data.pokemon[species], "unknown species: " .. tostring(species))
  mon.species = species
  MonOps.setLevel(data, mon, mon.level, gen)
  if gen == 2 or mon.experience ~= nil or (mon.stats and mon.stats.specialAttack) then
    require("src.battle.gen2.Mon").syncIdentity(mon, data)
  end
end

return MonOps
