local Pokemon = require("src.core.game3.pokemon")

local M = {}

function M.normalize(mon)
  if type(mon) ~= "table" then return mon end
  local species = Pokemon.speciesOf(mon)
  if not species and tonumber(mon.speciesId) then
    species = Pokemon.speciesOf({ species = mon.speciesId, speciesNumbering = mon.speciesNumbering })
  end
  if not species or not Pokemon.isInternalSpecies(species) then return mon end
  mon.species, mon.speciesId = species, species
  mon.speciesNumbering = Pokemon.NUMBERING_INTERNAL
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

function M.each(save, fn)
  for _, mon in pairs(save.party or {}) do fn(mon) end
  for _, box in pairs(save.storage and save.storage.boxes or {}) do
    for _, mon in pairs(type(box) == "table" and box.mons or {}) do fn(mon) end
  end
end

return M
