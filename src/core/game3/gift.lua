local ModRuntime = require("src.mods.Runtime")

local Gift = {}

Gift.NICKNAME_LENGTH = 10
-- pokefirered/src/daycare.c:1095
Gift.EGG_LEVEL = 5

function Gift.beforeGive(ctx, species, level, opts)
  opts = opts or {}
  if not ModRuntime.wants("pokemon.before_give") then return species, level, nil end
  local Pokemon = require("src.core.game3.pokemon")
  local isEgg = opts.isEgg == true
  local gift = {
    ctx = ctx,
    species = Pokemon.keyName(species) or species,
    speciesId = species,
    level = level,
    isEgg = isEgg,
  }
  ModRuntime.emit("pokemon.before_give", gift)
  local id = type(gift.species) == "number" and gift.species
    or Pokemon.speciesFromName(gift.species)
  if tonumber(id) and tonumber(id) >= 1 then species = tonumber(id) end
  if isEgg then return species, level, nil end
  if tonumber(gift.level) then
    level = math.max(1, math.min(100, math.floor(tonumber(gift.level))))
  end
  local nick = require("src.core.TextClip").clip(gift.nickname, Gift.NICKNAME_LENGTH)
  return species, level, nick ~= "" and nick or nil
end

return Gift
