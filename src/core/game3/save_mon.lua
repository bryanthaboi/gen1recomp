local Pokemon = require("src.core.game3.pokemon")

local M = {}

-- src/pokemon.c:2196
local function levelFromExp(growthRate, exp)
  local SummaryData = require("src.core.game3.summary_data")
  local level = 1
  while level <= 100 and SummaryData.expForLevel(growthRate, level) <= exp do level = level + 1 end
  return math.max(1, level - 1)
end

local function finishCartMon(mon, species)
  local growthRate = Pokemon.growthRate(species)
  mon.growthRate = growthRate
  if mon.level == nil then mon.level = levelFromExp(growthRate, tonumber(mon.exp) or 0) end
  if not mon.isEgg then
    mon.name = Pokemon.name(species)
    if mon.nickname == mon.name then mon.nickname = "" end
  end
  mon.gender = Pokemon.gender(species, mon.personality)
  local pair = Pokemon.abilities(species)
  local ability = pair[(tonumber(mon.abilityNum) or 0) + 1]
  if not ability or ability == 0 then ability = pair[1] end
  mon.ability, mon.abilityId = ability, ability
  mon.maxPp = {}
  local bonuses = tonumber(mon.ppBonusesPacked) or 0
  for slot, move in ipairs(mon.moves or {}) do
    local base = Pokemon.movePp(move)
    -- src/pokemon.c:3898
    mon.maxPp[slot] = base + math.floor(base * 20 * (math.floor(bonuses / 4 ^ (slot - 1)) % 4) / 100)
  end
  mon.cartImport = nil
end

function M.normalize(mon)
  if type(mon) ~= "table" then return mon end
  local species = Pokemon.speciesOf(mon)
  if not species and tonumber(mon.speciesId) then
    species = Pokemon.speciesOf({ species = mon.speciesId, speciesNumbering = mon.speciesNumbering })
  end
  if not species or not Pokemon.isInternalSpecies(species) then return mon end
  mon.species, mon.speciesId = species, species
  mon.speciesNumbering = Pokemon.NUMBERING_INTERNAL
  if mon.cartImport then finishCartMon(mon, species) end
  local hp = tonumber(mon.hp)
  Pokemon.applyStats(mon)
  if hp then mon.hp = math.max(0, math.min(hp, mon.maxHp)) end
  mon.stats = mon.stats or {}
  for key, value in pairs({ hp = mon.maxHp, attack = mon.attack, defense = mon.defense,
      speed = mon.speed, spAtk = mon.spAtk, spDef = mon.spDef,
      specialAttack = mon.spAtk, specialDefense = mon.spDef }) do
    mon.stats[key] = value
  end
  for slot = 1, 4 do
    local move = mon.moves and mon.moves[slot]
    if type(move) == "table" then
      local id = tonumber(move.moveId or move.id or move.move)
      if not id and type(move.id) == "string" then
        for n = 1, 354 do
          if Pokemon.moveName(n) == move.id then id = n; break end
        end
      end
      if id then
        move.id, move.moveId = id, id
        mon.pp, mon.maxPp = mon.pp or {}, mon.maxPp or {}
        mon.pp[slot] = move.pp or mon.pp[slot] or Pokemon.movePp(id)
        mon.maxPp[slot] = move.maxPp or mon.maxPp[slot] or Pokemon.movePp(id)
      end
    end
  end
  return mon
end

-- src/heal_location.c:30
local function healIdFor(w)
  local Field = require("src.core.game3.field")
  if not Field.flyDestinationsMounted() then return nil end
  for _, dest in pairs(Field._flyBaked or {}) do
    if dest.healLocation and dest.map == w.map then return dest.healLocation end
  end
  return false
end

function M.finishCartImport(save)
  local ci = type(save.modData) == "table" and save.modData.cartImport
  if type(ci) ~= "table" or not Pokemon.isInternalSpecies(1) then return end
  save.dex = save.dex or {}
  local dex = save.dex
  dex.seen, dex.owned, dex.caught = dex.seen or {}, dex.owned or {}, dex.caught or {}
  for _, nat in ipairs(ci.dexSeen or {}) do
    local sp = Pokemon.speciesFromNational(nat)
    if sp then dex.seen[sp] = true end
  end
  for _, nat in ipairs(ci.dexOwned or {}) do
    local sp = Pokemon.speciesFromNational(nat)
    if sp then dex.owned[sp], dex.caught[sp] = true, true end
  end
  ci.dexSeen, ci.dexOwned = nil, nil
  local dc = save.modData.firered_daycare
  if type(dc) == "table" then
    for _, mon in pairs(type(dc.daycare) == "table" and dc.daycare or {}) do
      if type(mon) == "table" and mon.cartImport then M.normalize(mon) end
    end
    if type(dc.route5Daycare) == "table" and type(dc.route5Daycare.mon) == "table" then
      M.normalize(dc.route5Daycare.mon)
    end
  end
  if type(ci.lastHealLocation) == "table" then
    -- src/heal_location.c:79
    local id = healIdFor(ci.lastHealLocation)
    if id then require("src.core.game3.heal_locations").applyToSession(save, id) end
    if id ~= nil then ci.lastHealLocation = nil end
  else
    ci.lastHealLocation = nil
  end
  if ci.lastHealLocation == nil then save.modData.cartImport = nil end
end

function M.each(save, fn)
  M.finishCartImport(save)
  for _, mon in pairs(save.party or {}) do fn(mon) end
  for _, box in pairs(save.storage and save.storage.boxes or {}) do
    for _, mon in pairs(type(box) == "table" and box.mons or {}) do fn(mon) end
  end
end

return M
