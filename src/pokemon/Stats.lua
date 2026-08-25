-- Gen 1 stat calculation (home/move_mon.asm CalcStat):
--   stat = floor(((base + DV) * 2 + floor(ceil(sqrt(statExp)) / 4)) * level / 100) + 5
--   HP adds level + 10 instead of 5.
-- The HP DV is derived from the low bits of the other four DVs.

local Stats = {}

local ORDER = { "hp", "attack", "defense", "speed", "special" }
Stats.ORDER = ORDER

function Stats.randomDVs(rng)
  rng = rng or love.math.random
  local dvs = {
    attack = rng(0, 15),
    defense = rng(0, 15),
    speed = rng(0, 15),
    special = rng(0, 15),
  }
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4 +
           (dvs.speed % 2) * 2 + (dvs.special % 2)
  return dvs
end

local function calcOne(base, dv, statExp, level, isHP)
  -- CalcStat .statExpLoop finds the smallest b with b*b >= statExp
  -- (a ceiling sqrt), capped at 255, and quarters it
  local ev = math.floor(math.min(255, math.ceil(math.sqrt(statExp or 0))) / 4)
  local v = math.floor(((base + dv) * 2 + ev) * level / 100)
  if isHP then
    return v + level + 10
  end
  return v + 5
end

function Stats.calc(speciesDef, level, dvs, statExp)
  statExp = statExp or {}
  local out = {}
  for _, key in ipairs(ORDER) do
    out[key] = calcOne(speciesDef.baseStats[key], dvs[key] or 0,
                       statExp[key], level, key == "hp")
  end
  return out
end

-- Give a mon a stat block when it has none.  A real Gen 1 box_struct is a
-- byte-for-byte PREFIX of party_struct that stops before MON_LEVEL and
-- MON_STATS (macros/ram.asm box_struct / party_struct), so mons decoded out
-- of an imported .sav arrive without one (src/save_convert/GenSave.lua
-- decodeMon, isParty = false).  The original derives them on demand at
-- exactly two moments: when a box or daycare mon's status screen opens
-- (engine/pokemon/status_screen.asm:66-76, "mon is in a box or daycare" ->
-- CalcStats) and when one is moved back into the party
-- (engine/pokemon/add_mon.asm _MoveMon tail).  The stored current HP is
-- kept (box_struct does hold it) but clamped to the recalculated maximum.
-- A complete stat block is returned untouched; an incomplete one is rebuilt,
-- because CalcStats writes all NUM_STATS stats or none
-- (home/move_mon.asm:33-48).  #233, #304, #1517
local function statsComplete(stats)
  for _, key in ipairs(ORDER) do
    if type(stats[key]) ~= "number" then return false end
  end
  return true
end

function Stats.ensure(speciesDef, mon)
  if type(mon) ~= "table" then return mon end
  if type(mon.stats) == "table" and statsComplete(mon.stats) then return mon end
  if type(speciesDef) ~= "table" or type(speciesDef.baseStats) ~= "table" then
    return mon
  end
  mon.stats = Stats.calc(speciesDef, mon.level or 1, mon.dvs or {}, mon.statExp)
  mon.hp = math.max(0, math.min(tonumber(mon.hp) or mon.stats.hp, mon.stats.hp))
  return mon
end

-- Battle stat stage multipliers (data/battle/stat_modifiers.asm): stages
-- -6..+6 map to N/D pairs 25/100 .. 400/100.
local STAGE_MULT = {
  [-6] = { 25, 100 }, [-5] = { 28, 100 }, [-4] = { 33, 100 }, [-3] = { 40, 100 },
  [-2] = { 50, 100 }, [-1] = { 66, 100 }, [0] = { 100, 100 }, [1] = { 150, 100 },
  [2] = { 200, 100 }, [3] = { 250, 100 }, [4] = { 300, 100 }, [5] = { 350, 100 },
  [6] = { 400, 100 },
}

function Stats.applyStage(value, stage)
  local m = STAGE_MULT[math.max(-6, math.min(6, stage or 0))]
  local v = math.floor(value * m[1] / m[2])
  return math.max(1, math.min(999, v))
end

-- Gen 2 shiny formula applied to Gen 1 DVs (the RBY "virtual shiny"):
-- Defense/Speed/Special DV == 10 and Attack DV is even-high
-- (2, 3, 6, 7, 10, 11, 14, or 15).  Used by shiny-indicator mods.
local SHINY_ATK = {
  [2] = true, [3] = true, [6] = true, [7] = true,
  [10] = true, [11] = true, [14] = true, [15] = true,
}

function Stats.isShiny(dvs)
  if type(dvs) ~= "table" then return false end
  return (dvs.defense or 0) == 10
     and (dvs.speed or 0) == 10
     and (dvs.special or 0) == 10
     and SHINY_ATK[dvs.attack or 0] == true
end

return Stats
