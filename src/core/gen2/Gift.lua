local Runtime = require("src.mods.Runtime")
local Mon = require("src.battle.gen2.Mon")

local Gift = {}

Gift.NICKNAME_LENGTH = 10

function Gift.beforeGive(data, ctx, species, level, opts)
  opts = opts or {}
  local preset = opts.nickname
  if not Runtime.wants("pokemon.before_give") then return species, level, preset, preset ~= nil end
  local isEgg = opts.isEgg == true
  local gift = { ctx = ctx, species = species, level = level, isEgg = isEgg, nickname = preset }
  Runtime.emit("pokemon.before_give", gift)
  local pokemon = data and data.pokemon or {}
  if type(gift.species) == "string" and type(pokemon[gift.species]) == "table" then
    species = gift.species
  end
  local lv = tonumber(gift.level)
  if lv and lv == lv then level = math.max(1, math.min(Mon.MAX_LEVEL or 100, math.floor(lv))) end
  if isEgg then return species, level, preset, preset ~= nil end
  if type(gift.nickname) ~= "string" then return species, level, nil, false end
  local nick = require("src.core.TextClip").clip(gift.nickname, Gift.NICKNAME_LENGTH,
    require("src.render.Font").split)
  return species, level, nick ~= "" and nick or nil, true
end

-- ../pokecrystal/engine/pokemon/move_mon.asm:1121
function Gift.egg(data, save, species, level)
  local def = data and data.pokemon and data.pokemon[species]
  local mon = def and Mon.new(data, species, level)
  if not mon then return nil end
  mon.isEgg = true
  -- ../pokecrystal/engine/pokemon/move_mon.asm:1193
  mon.nickname = require("src.core.gen2.Breeding").EGG_NAME
  mon.eggSteps = def.eggSteps or 0
  mon.hp = 0
  Mon.stampOT(save, mon)
  return mon
end

function Gift.giveEgg(data, ctx, save, egg)
  local species, level = Gift.beforeGive(data, ctx, egg.species, egg.level, { isEgg = true })
  if species == egg.species and level == egg.level then return egg end
  local def = data and data.pokemon and data.pokemon[species]
  if not def then return egg end
  local same = species == egg.species
  local old = egg.dvs
  local dvs = old and { attack = old.attack, defense = old.defense, speed = old.speed,
    special = old.special } or nil
  local moves
  if same and type(egg.moves) == "table" then
    moves = {}
    for i, m in ipairs(egg.moves) do
      moves[i] = type(m) == "table" and { id = m.id, pp = m.pp, maxPp = m.maxPp, ppUps = m.ppUps } or m
    end
  end
  -- ../pokecrystal/engine/events/daycare.asm:621
  local mon = Mon.new(data, species, level, {
    dvs = dvs, moves = moves, hp = 0, nickname = egg.nickname,
    happiness = egg.happiness, item = egg.item,
  })
  if not mon then return egg end
  mon.isEgg = true
  -- ../pokecrystal/engine/events/daycare.asm:712
  mon.eggSteps = same and egg.eggSteps or def.eggSteps or 0
  mon.ot, mon.otName, mon.otId = egg.ot, egg.otName, egg.otId
  Mon.stampOT(save, mon)
  return mon
end

return Gift
