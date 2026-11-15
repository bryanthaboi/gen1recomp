-- pokecrystal/engine/pokegear/radio.asm:1461
local Save = require("src.core.gen2.Save")
local BugContest = require("src.core.gen2.BugContest")
local EngineFlags = require("src.core.gen2.EngineFlags")

local Buena = {}

function Buena.metadata(data)
  return data and data.gen2EventTables and data.gen2EventTables.buenaPassword
end

function Buena.captured(save, data)
  local state = save and save.crystal and save.crystal.buenaPassword
  local packed = state and state.word
  if type(packed) ~= "number" or packed % 1 ~= 0 or packed < 0 or packed > 255 then return nil end
  local group, index = math.floor(packed / 16), packed % 16
  local metadata = Buena.metadata(data)
  local category = metadata and metadata.categories and metadata.categories[group + 1]
  if not category or index >= 3 or not category.words[index + 1] then return nil end
  return category, index, packed
end

function Buena.word(data, category, index)
  local id = category and category.words and category.words[index + 1]
  if not id then return nil end
  if category.kind == "string" then return id end
  local definitions = category.kind == "mon" and data.pokemon
    or category.kind == "item" and data.items or data.moves
  local definition = definitions and definitions[id]
  return definition and definition.name or id
end

function Buena.broadcast(save, data, sample)
  if not save or save.version ~= "crystal" then return nil end
  local metadata = Buena.metadata(data)
  if not metadata or not metadata.categories then return nil end
  local flags = save.engineFlags or {}
  save.engineFlags = flags
  local listened = EngineFlags.id("ENGINE_BUENAS_PASSWORD")
  local category, index = Buena.captured(save, data)
  local state = save.crystal and save.crystal.buenaPassword
  local imported = flags[listened] == nil and state and type(state.day) == "number"
    and state.day % 1 == 0 and state.day >= 0 and state.day < BugContest.DAY_WRAP
  if (flags[listened] ~= true and not imported) or not category then
    local group = sample(function(byte)
      local value = byte % 16
      if value < 11 then return value end
    end)
    if group == nil then return nil end
    index = sample(function(byte)
      local value = byte % 4
      if value < 3 then return value end
    end)
    if index == nil then return nil end
    category = metadata.categories[group + 1]
    if not category or not category.words[index + 1] then return nil end
    state = Save.crystalState(save).buenaPassword
    state.word = group * 16 + index
    state.day = BugContest.now().day
  end
  flags[listened] = true
  return Buena.word(data, category, index)
end

-- pokecrystal/engine/pokegear/radio.asm:1612
function Buena.clearListening(save)
  if not save or save.version ~= "crystal" then return end
  local id = EngineFlags.id("ENGINE_BUENAS_PASSWORD")
  if save.engineFlags then save.engineFlags[id] = nil end
  local state = save.crystal and save.crystal.buenaPassword
  if state then state.day = nil end
end

-- pokecrystal/engine/overworld/time.asm:103
function Buena.dailyReset(save)
  if not save or save.version ~= "crystal" then return end
  Buena.clearListening(save)
  local id = EngineFlags.id("ENGINE_BUENAS_PASSWORD_2")
  if save.engineFlags then save.engineFlags[id] = nil end
end

return Buena
