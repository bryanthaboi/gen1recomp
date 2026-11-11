local Merge = require("src.mods.Merge")
local Gen2ItemEffects = require("src.core.gen2.ItemEffects")
local Schemas = require("src.mods.Schemas")
local Ids = require("src.mods.UnifiedIds")
local GameVersion = require("src.core.GameVersion")
local Effects = require("src.mods.UnifiedEffects")
local TextIR = require("src.core.game3.scripting.text_ir")

local UnifiedContent = {}
local DELETE = Merge.DELETE
local copy = Merge.deepCopy
local CORE = { pokemon = true, moves = true, items = true,
  trainers = true, encounters = true }
local VERBS = { "register", "override", "patch", "remove" }
local PASSTHROUGH = { text = true, rom_text = true, field = true,
  decorations = true, landmarks = true, battle_anims = true, constants = true,
  icons = true, map_scripts = true, palettes = true, sprites = true,
  balls = true, maps = true, marts = true, spawns = true, fly_points = true }
local UNSUPPORTED = "unsupported: "

local function refuse(reason) error(UNSUPPORTED .. reason, 0) end
local function expect(ok, reason)
  if not ok then error("invalid content: " .. reason, 0) end
end
local function record(value)
  expect(type(value) == "table" and value ~= DELETE, "expected record")
end
local function integer(value, low, high)
  return type(value) == "number" and value == value and value % 1 == 0
    and value ~= math.huge and value ~= -math.huge
    and value >= low and value <= (high or math.huge)
end
local function identifier(value)
  return type(value) == "string" and value ~= ""
end
local function finite(value, seen)
  if type(value) == "number" then
    expect(value == value and value ~= math.huge and value ~= -math.huge, "non-finite number")
  elseif type(value) == "table" and value ~= DELETE then
    seen = seen or {}
    expect(not seen[value], "cyclic content")
    seen[value] = true
    for key, sub in pairs(value) do finite(key, seen); finite(sub, seen) end
    seen[value] = nil
  end
end
local function keys(value, allowed)
  record(value)
  for key in pairs(value) do
    expect(allowed[key] == true, "unknown field " .. tostring(key))
  end
end
local function fields(names)
  local out = {}
  for name in names:gmatch("%S+") do out[name] = true end
  return out
end
local function equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not equal(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function list(value, convert, wrappers)
  if value == DELETE then return DELETE end
  record(value)
  if Merge.isWrapper(value) then
    expect(wrappers, "list extensions require patch")
    keys(value, { __append = true, __prepend = true })
    local out = {}
    for _, key in ipairs({ "__prepend", "__append" }) do
      if value[key] ~= nil then out[key] = list(value[key], convert, false) end
    end
    return out
  end
  local n = #value
  for key in pairs(value) do
    expect(integer(key, 1, n), "expected contiguous list")
  end
  local out = {}
  for i = 1, n do
    expect(value[i] ~= nil, "expected contiguous list")
    out[i] = convert(value[i], i)
    expect(out[i] ~= nil, "unrepresentable list row")
  end
  return out
end

local function ids(value, wrappers)
  return list(value, function(id)
    expect(identifier(id), "expected string id")
    return id
  end, wrappers)
end

local function effective(old, value)
  if value == DELETE then return nil end
  if type(value) == "table" then
    return Merge.deepMerge(copy(old or {}), value)
  end
  return value
end

local function canonicalName(name)
  return Schemas.ALIASES[name] or name
end

local fieldsFor

function UnifiedContent.supports(name, generation, version)
  local field
  if type(name) == "string" and name:find(".", 1, true) then
    name, field = name:match("^([^.]*)%.(.*)$")
  end
  name = canonicalName(name)
  local spec = Schemas.REGISTRIES[name]
  if not spec then return false, UNSUPPORTED .. "unknown registry" end
  if generation ~= 1 and generation ~= 2 and generation ~= 3 then
    return false, UNSUPPORTED .. "unknown generation"
  end
  if version ~= nil and (not GameVersion.VERSIONS[version]
      or GameVersion.generation(version) ~= generation) then
    return false, UNSUPPORTED .. "version does not match generation"
  end
  if Schemas.gatedFor(name, generation, version) then
    return false, UNSUPPORTED .. name .. " has no native target"
  end
  if not CORE[name] and Schemas.hasShape(spec, generation) then
    if not PASSTHROUGH[name] then
      return false, UNSUPPORTED .. name .. " has no canonical record adapter"
    end
  end
  if field ~= nil and not fieldsFor(name, generation)[field] then
    return false, UNSUPPORTED .. name .. "." .. field
  end
  return true
end

local STAT_FIELDS = fields("hp attack defense speed special specialAttack specialDefense")
local MON_FIELDS = fields("id name dex index types baseStats catchRate baseExp growthRate "
  .. "level1Moves learnset evolutions tmhm spriteFront spriteBack frontSize dexEntry "
  .. "eggMoves genderRatio eggCycles itemCommon itemRare trueColor native")
local MOVE_FIELDS = fields("id name index type power accuracy pp effect category priority "
  .. "secondaryChance description native")
local ITEM_FIELDS = fields("id name index price machine effect ball tossable needsTarget "
  .. "pocket description native")
local TRAINER_FIELDS = fields("id name index pic trueColor baseMoney battleTheme parties partyNames native")
local PARTY_MON_FIELDS = fields("level species item moves native")
local EVO_FIELDS = fields("method species level item time comparison param")
local SLOT_FIELDS = fields("species level minLevel maxLevel chance timeGroup day nite fallback")
local AREA_FIELDS = fields("rate slots times map native")
local ENCOUNTER_FIELDS = fields("id grass water rocks fishing swarmGrass swarmWater "
  .. "treeSet rockSet mapGroup mapNum kind entries native")
local EXTRA_ENCOUNTERS = fields("fishGroups timeFishGroups treeSets treeMonsAsleep "
  .. "bugContest roamMaps roamMons")
local MAP_KINDS = { "grass", "water", "swarmGrass", "swarmWater", "trees", "rocks" }
local MON_BATTLE_FIELDS = fields("battleScaleFront battleScaleBack battleTheme")

local function coreFields(name, allowed, generation)
  if generation ~= 1 then
    if name ~= "pokemon" then return allowed end
    local out = copy(allowed)
    for key in pairs(MON_BATTLE_FIELDS) do out[key] = true end
    return out
  end
  local out = copy(allowed)
  local nativeSchema = Schemas.shapeFor(name, Schemas.REGISTRIES[name], generation)
  for key in pairs(nativeSchema.fields or {}) do
    if key ~= "_modEffectId" then out[key] = true end
  end
  return out
end

local CORE_FIELDS = { pokemon = MON_FIELDS, moves = MOVE_FIELDS, items = ITEM_FIELDS,
  trainers = TRAINER_FIELDS, encounters = ENCOUNTER_FIELDS }

fieldsFor = function(name, generation)
  if CORE_FIELDS[name] then return coreFields(name, CORE_FIELDS[name], generation) end
  return Schemas.shapeFor(name, Schemas.REGISTRIES[name], generation).fields or {}
end

local function project(value, allowed)
  local out, extra = {}, {}
  for key, sub in pairs(value) do
    if allowed[key] and key ~= "native" then out[key] = copy(sub)
    else extra[key] = copy(sub) end
  end
  if next(extra) then out.native = extra end
  return out
end

local function nativeExtension(value, old, allowed)
  if value.native == nil then return end
  local expected = old and project(old, allowed).native
  if not equal(value.native, expected or {}) then
    refuse("native extensions are read-only")
  end
end

local function evolutionRead(row, generation)
  local out = copy(row)
  out.species, out.into = row.species or row.into, nil
  local method = row.method
  if generation == 2 then
    method = ({ EVOLVE_LEVEL = "LEVEL", EVOLVE_ITEM = "ITEM",
      EVOLVE_TRADE = "TRADE", EVOLVE_HAPPINESS = "FRIENDSHIP",
      EVOLVE_STAT = "LEVEL" })[method] or method
  elseif generation == 3 then
    method = type(method) == "string" and method:gsub("^EVO_", "") or method
    if method == "FRIENDSHIP_DAY" then method, out.time = "FRIENDSHIP", "MORNDAY"
    elseif method == "FRIENDSHIP_NIGHT" then method, out.time = "FRIENDSHIP", "NITE"
    elseif method == "TRADE_ITEM" then method = "TRADE"
    elseif method == "LEVEL_ATK_GT_DEF" then method, out.comparison = "LEVEL", "ATK_GT_DEF"
    elseif method == "LEVEL_ATK_LT_DEF" then method, out.comparison = "LEVEL", "ATK_LT_DEF"
    elseif method == "LEVEL_ATK_EQ_DEF" then method, out.comparison = "LEVEL", "ATK_EQ_DEF" end
    if out.param == 0 then out.param = nil end
  end
  out.method = method
  return out
end

local function evolutionWrite(row, generation)
  keys(row, EVO_FIELDS)
  expect(identifier(row.species), "evolution species is required")
  expect(identifier(row.method), "evolution method is required")
  if row.level ~= nil then expect(integer(row.level, 1, 100), "invalid evolution level") end
  if row.item ~= nil then expect(identifier(row.item), "invalid evolution item") end
  if row.param ~= nil then expect(integer(row.param, 0), "invalid evolution parameter") end
  local out, method = copy(row), row.method
  if generation == 1 then
    if row.time ~= nil or row.comparison ~= nil or row.param ~= nil then
      refuse("evolution condition has no Gen 1 representation")
    end
    return out
  end
  if row.time ~= nil then
    expect(row.time == "ANYTIME" or row.time == "MORNDAY" or row.time == "NITE",
      "invalid evolution time")
    if method ~= "FRIENDSHIP" then refuse("time requires FRIENDSHIP") end
  end
  if row.comparison ~= nil then
    expect(row.comparison == "ATK_GT_DEF" or row.comparison == "ATK_LT_DEF"
      or row.comparison == "ATK_EQ_DEF", "invalid evolution comparison")
    if method ~= "LEVEL" then refuse("comparison requires LEVEL") end
  end
  if method == "LEVEL" then
    expect(row.level ~= nil, "LEVEL requires level")
    expect(row.item == nil and row.time == nil and row.param == nil, "invalid LEVEL condition")
  elseif method == "ITEM" then
    expect(row.item ~= nil, "ITEM requires item")
    expect(row.level == nil and row.param == nil, "invalid ITEM condition")
  elseif method == "TRADE" or method == "FRIENDSHIP" then
    expect(row.level == nil and row.param == nil, "invalid evolution condition")
    if method == "FRIENDSHIP" then expect(row.item == nil, "invalid FRIENDSHIP item") end
  end
  local native = method == "LEVEL" or method == "ITEM" or method == "TRADE" or method == "FRIENDSHIP"
    or (generation == 3 and ({ LEVEL_SILCOON = true, LEVEL_CASCOON = true,
      LEVEL_NINJASK = true, LEVEL_SHEDINJA = true, BEAUTY = true })[method] or false)
  if not native then
    if generation == 2 then out.species, out.into = nil, row.species end
    return out
  end
  if generation == 2 then
    out.species, out.into = nil, row.species
    out.method = ({ LEVEL = "EVOLVE_LEVEL", ITEM = "EVOLVE_ITEM",
      TRADE = "EVOLVE_TRADE", FRIENDSHIP = "EVOLVE_HAPPINESS" })[method]
    if row.comparison then out.method = "EVOLVE_STAT" end
  else
    if method == "FRIENDSHIP" and row.time and row.time ~= "ANYTIME" then
      method = row.time == "NITE" and "FRIENDSHIP_NIGHT" or "FRIENDSHIP_DAY"
    elseif method == "TRADE" and row.item then method = "TRADE_ITEM"
    elseif method == "LEVEL" and row.comparison then method = "LEVEL_" .. row.comparison end
    out.time, out.comparison = nil, nil
    out.method = "EVO_" .. method
  end
  return out
end

local function effectRead(value, generation, context)
  return Effects.read(value, generation, context)
end
local activeLoader
local function registeredEffect(id)
  local registry = activeLoader and activeLoader.content and activeLoader.content.move_effects
  return registry ~= nil and registry:get(id) ~= nil
end
local function effectWrite(value, generation, context)
  if value == DELETE then return DELETE end
  expect(identifier(value), "move effect must be a string id")
  local native, chance, reason = Effects.write(value, generation, context, registeredEffect)
  if native == nil then refuse(reason or chance or ("move effect " .. value)) end
  return native, chance
end

local function monRead(value, generation)
  local out = project(value, coreFields("pokemon", MON_FIELDS, generation))
  if generation ~= 1 then
    if out.baseStats then out.baseStats.special = value.baseStats.specialAttack end
    out.level1Moves, out.learnset = {}, {}
    for _, row in ipairs((generation == 2 and value.levelMoves or value.learnset) or {}) do
      if row.level == 1 then out.level1Moves[#out.level1Moves + 1] = row.move
      else out.learnset[#out.learnset + 1] = copy(row) end
    end
  end
  if generation == 2 then
    out.frontSize = value.picSize
    out.eggCycles = value.eggSteps
    out.itemRare, out.itemCommon = (value.items or {})[1], (value.items or {})[2]
  end
  if value.evolutions then
    out.evolutions = {}
    for i, row in ipairs(value.evolutions) do out.evolutions[i] = evolutionRead(row, generation) end
  end
  if generation == 3 and type(out.types) == "table" then
    for i, id in ipairs(out.types) do out.types[i] = Ids.canonical(id, "type", 3) end
  end
  return out
end

local function monWrite(value, old, generation, patch)
  local allowed = coreFields("pokemon", MON_FIELDS, generation)
  keys(value, allowed)
  nativeExtension(value, old, allowed)
  local out = copy(value)
  out.native = nil
  if not patch and generation ~= 3 and value.frontSize == nil then
    out.frontSize = 7
  end
  if value.baseStats ~= nil and value.baseStats ~= DELETE then
    keys(value.baseStats, STAT_FIELDS)
    for _, stat in pairs(value.baseStats) do
      expect(stat == DELETE or integer(stat, 1, 255), "invalid base stat")
    end
    if generation == 1 then
      local stats = effective(old and monRead(old, generation).baseStats, value.baseStats)
      local a = value.baseStats.specialAttack or value.baseStats.special or stats.special
      local b = value.baseStats.specialDefense or value.baseStats.special or stats.special
      expect(a == b, "conflicting Gen 1 special stats")
      local special = value.baseStats.special or a or b
      for _, key in ipairs({ "special", "specialAttack", "specialDefense" }) do
        if value.baseStats[key] ~= nil and value.baseStats[key] ~= special then
          expect(false, "conflicting Gen 1 special stats")
        end
      end
      out.baseStats.specialAttack, out.baseStats.specialDefense = nil, nil
      if value.baseStats.special ~= nil or value.baseStats.specialAttack ~= nil
          or value.baseStats.specialDefense ~= nil then
        out.baseStats.special = special
      end
    else
      local stats = value.baseStats
      if stats.special ~= nil then
        expect(stats.specialAttack == nil or stats.specialAttack == stats.special,
          "conflicting special and specialAttack")
        out.baseStats.specialAttack = stats.specialAttack or stats.special
        out.baseStats.specialDefense = stats.specialDefense or stats.special
      end
      out.baseStats.special = nil
    end
  end
  if value.level1Moves ~= nil then out.level1Moves = ids(value.level1Moves, patch) end
  if value.learnset ~= nil then
    out.learnset = list(value.learnset, function(row)
      keys(row, { level = true, move = true })
      expect(integer(row.level, 1, 100) and identifier(row.move), "invalid learnset row")
      return copy(row)
    end, patch)
  end
  if generation ~= 1 and (value.level1Moves ~= nil or value.learnset ~= nil) then
    local previous = old and monRead(old, generation) or {}
    local function merged(key)
      local rows = out[key]
      if rows == DELETE then return {} end
      if rows == nil then return copy(previous[key] or {}) end
      if Merge.isWrapper(rows) then return effective(previous[key], rows) end
      return rows
    end
    local combined = {}
    for _, move in ipairs(merged("level1Moves")) do
      combined[#combined + 1] = { level = 1, move = move }
    end
    for _, row in ipairs(merged("learnset")) do combined[#combined + 1] = copy(row) end
    out.level1Moves, out.learnset = nil, nil
    if generation == 2 then out.levelMoves = combined else out.learnset = combined end
  elseif generation == 1 then
    if out.level1Moves == DELETE then out.level1Moves = {} end
    if out.learnset == DELETE then out.learnset = {} end
  end
  if value.evolutions ~= nil then
    out.evolutions = list(value.evolutions, function(row)
      return evolutionWrite(row, generation)
    end, patch)
  end
  for _, key in ipairs({ "types", "tmhm", "eggMoves" }) do
    if value[key] ~= nil then out[key] = ids(value[key], patch) end
  end
  if generation == 2 then
    if out.frontSize ~= nil then out.picSize, out.frontSize = out.frontSize, nil end
    if value.eggCycles ~= nil then out.eggSteps, out.eggCycles = value.eggCycles, nil end
    if value.itemCommon ~= nil or value.itemRare ~= nil then
      local pair = copy(old and old.items or {})
      if value.itemRare ~= nil then pair[1] = value.itemRare end
      if value.itemCommon ~= nil then pair[2] = value.itemCommon end
      expect(identifier(pair[1]) and identifier(pair[2]), "Gen 2 requires both wild held items")
      out.items, out.itemCommon, out.itemRare = pair, nil, nil
    end
  elseif generation == 1 then
    for _, key in ipairs({ "eggMoves", "genderRatio", "eggCycles", "itemCommon", "itemRare" }) do
      if value[key] ~= nil then refuse(key .. " has no Gen 1 representation") end
    end
  else
    for _, key in ipairs({ "frontSize", "battleScaleFront", "battleScaleBack", "battleTheme" }) do
      if value[key] ~= nil then refuse(key .. " has no Gen 3 representation") end
    end
  end
  if generation == 3 and value.trueColor ~= nil and value.trueColor ~= (old or {}).trueColor then
    refuse("trueColor has no Gen 3 representation")
  end
  return out
end

local function partyMonRead(mon, generation)
  local out = project(mon, PARTY_MON_FIELDS)
  if generation == 3 then out.item = mon.heldItem end
  return out
end
local function trainerRead(value, generation)
  local out = project(value, coreFields("trainers", TRAINER_FIELDS, generation))
  out.parties, out.partyNames = {}, copy(value.partyNames or {})
  if generation == 1 then
    for i, party in ipairs(value.parties or {}) do
      out.parties[i] = {}
      for j, mon in ipairs(party) do out.parties[i][j] = partyMonRead(mon, generation) end
    end
  elseif generation == 2 then
    for i, trainer in ipairs(value.trainers or {}) do
      out.parties[i], out.partyNames[i] = {}, trainer.name
      for j, mon in ipairs(trainer.party or {}) do out.parties[i][j] = partyMonRead(mon, generation) end
    end
  else
    local party = {}
    for i, mon in ipairs(value.party or {}) do party[i] = partyMonRead(mon, generation) end
    out.parties[1], out.partyNames[1] = party, value.name
  end
  return out
end

local function trainerWrite(value, old, generation, patch)
  local allowed = coreFields("trainers", TRAINER_FIELDS, generation)
  keys(value, allowed)
  nativeExtension(value, old, allowed)
  local out = copy(value)
  out.native = nil
  if value.partyNames ~= nil and value.partyNames ~= DELETE then
    record(value.partyNames)
    if Merge.isWrapper(value.partyNames) then
      out.partyNames = list(value.partyNames, function(name)
        expect(type(name) == "string", "invalid party name")
        return name
      end, patch)
    else
      for i, name in pairs(value.partyNames) do
        expect(integer(i, 1) and type(name) == "string", "invalid party name")
      end
    end
  end
  if generation == 1 and value.parties == nil then
    if Merge.isWrapper(out.partyNames) then
      out.partyNames = effective(old and old.partyNames, out.partyNames)
    end
    return out
  end
  if value.parties == nil and value.partyNames == nil then return out end
  local previous = old and trainerRead(old, generation).parties or {}
  local source = value.parties or previous
  if generation ~= 1 and Merge.isWrapper(source) then source = effective(previous, source) end
  local parties = list(source, function(row, i)
    return list(row, function(mon, j)
      keys(mon, PARTY_MON_FIELDS)
      expect(integer(mon.level, 1, 100) and identifier(mon.species), "invalid trainer Pokemon")
      if mon.item ~= nil then expect(identifier(mon.item), "invalid held item") end
      local before = previous[i] and previous[i][j]
      if mon.native and not equal(mon.native, before and before.native or {}) then
        refuse("native Pokemon extensions are read-only")
      end
      local native = copy(mon)
      native.native = nil
      if mon.moves then native.moves = ids(mon.moves, false) end
      if generation == 1 and mon.item then refuse("trainer held items have no Gen 1 representation") end
      if generation == 3 then native.heldItem, native.item = mon.item, nil end
      return native
    end, false)
  end, patch)
  local names = value.partyNames
  if names == DELETE then names = {}
  elseif names == nil then names = old and trainerRead(old, generation).partyNames or {}
  elseif Merge.isWrapper(names) then
    names = effective(old and trainerRead(old, generation).partyNames, names)
  end
  if generation == 1 then
    out.parties = parties == DELETE and {} or parties
    if Merge.isWrapper(out.partyNames) then out.partyNames = names end
  elseif generation == 2 then
    out.parties, out.partyNames = nil, nil
    if parties == DELETE then parties = {} end
    out.trainers = list(parties, function(row, i)
      local trainer = copy(old and old.trainers and old.trainers[i] or {})
      trainer.name, trainer.party = names[i] or "", row
      local hasMoves, hasItem = false, false
      for _, mon in ipairs(row) do
        hasMoves, hasItem = hasMoves or mon.moves ~= nil, hasItem or mon.item ~= nil
      end
      trainer.trainerType = hasMoves and (hasItem and "TRAINERTYPE_ITEM_MOVES" or "TRAINERTYPE_MOVES")
        or (hasItem and "TRAINERTYPE_ITEM" or "TRAINERTYPE_NORMAL")
      return trainer
    end, patch)
  else
    out.partyNames = nil
    if parties == DELETE then out.party, out.parties = {}, nil
    else
      if Merge.isWrapper(parties) or #parties ~= 1 then
        refuse("Gen 3 trainers require exactly one party")
      end
      out.party, out.parties = parties[1], nil
      if names[1] then
        expect(out.name == nil or out.name == names[1], "conflicting trainer names")
        out.name = names[1]
      end
    end
  end
  return out
end

local function slotRead(slot)
  local out = {}
  out.species = copy(slot.species or slot[1])
  if out.species == 0 then out.species, out.fallback = nil, true end
  out.minLevel = copy(slot.minLevel or slot.min or slot.level or slot[2])
  out.maxLevel = copy(slot.maxLevel or slot.max or slot.level or slot[2] or out.minLevel)
  out.level = copy(slot.level or out.minLevel)
  out.chance, out.timeGroup = copy(slot.chance), copy(slot.timeGroup)
  if slot.day then out.day = slotRead(slot.day) end
  if slot.nite then out.nite = slotRead(slot.nite) end
  return out
end

local function slotWrite(slot, generation, variant)
  keys(slot, SLOT_FIELDS)
  slot = copy(slot)
  if slot.level ~= nil then
    expect(integer(slot.level, 0, 255), "invalid encounter level")
    slot.minLevel = slot.minLevel or slot.level
    slot.maxLevel = slot.maxLevel or slot.level
    expect(slot.minLevel == slot.level, "conflicting encounter level")
  end
  expect(integer(slot.minLevel, 0, 255) and integer(slot.maxLevel, slot.minLevel, 255),
    "invalid encounter level range")
  expect(identifier(slot.species) or slot.fallback == true
    or variant == "treeSets", "encounter species is required")
  if slot.fallback ~= nil then expect(type(slot.fallback) == "boolean", "invalid encounter fallback") end
  local out = { species = slot.species }
  if slot.fallback then
    if generation ~= 2 or (variant ~= "fishGroups" and variant ~= "timeFishGroups") then
      refuse("encounter fallback requires Gen 2 fishing")
    end
    expect(slot.species == nil, "fallback cannot name species")
    out.species = 0
  end
  if generation == 3 then out.minLevel, out.maxLevel = slot.minLevel, slot.maxLevel
  elseif variant == "bugContest" then out.min, out.max = slot.minLevel, slot.maxLevel
  else
    if slot.minLevel ~= slot.maxLevel then refuse("encounter level ranges require Gen 3 or bugContest") end
    out.level = slot.minLevel
  end
  if slot.chance ~= nil then
    expect(integer(slot.chance, 0, 255), "invalid encounter chance")
    if not variant then refuse("weighted encounter slots are not writable here") end
    out.chance = slot.chance
  end
  if slot.timeGroup ~= nil or slot.day ~= nil or slot.nite ~= nil then
    if variant ~= "fishGroups" then refuse("time-dependent fishing requires fishGroups") end
    if slot.timeGroup ~= nil then expect(integer(slot.timeGroup, 0, 255), "invalid fishing time group") end
    out.timeGroup = slot.timeGroup
    if slot.day then out.day = slotWrite(slot.day, generation, "timeFishGroups") end
    if slot.nite then out.nite = slotWrite(slot.nite, generation, "timeFishGroups") end
  end
  return out
end

local function areaRead(area, generation, grass)
  local out = { rate = copy(area.rate), map = copy(area.map) }
  if generation == 2 and grass then
    out.times = {}
    for _, time in ipairs({ "MORN", "DAY", "NITE" }) do
      local rows = {}
      for i, slot in ipairs((area.slots or {})[time] or {}) do rows[i] = slotRead(slot) end
      out.times[time] = { rate = copy((area.rates or {})[time]), slots = rows }
    end
    out.rate, out.slots = out.times.DAY.rate, copy(out.times.DAY.slots)
  else
    out.slots = {}
    for i, slot in ipairs(area.slots or area.mons or area) do out.slots[i] = slotRead(slot) end
  end
  return out
end

local function areaWrite(area, generation, grass, patch, old)
  if area == DELETE then return DELETE end
  keys(area, AREA_FIELDS)
  if area.native ~= nil then refuse("native encounter extensions are read-only") end
  local out = { rate = area.rate, map = area.map }
  if area.rate ~= nil then expect(area.rate == DELETE or integer(area.rate, 0, 255), "invalid encounter rate") end
  local function rows(value)
    return list(value, function(slot) return slotWrite(slot, generation) end, patch)
  end
  if generation == 2 and grass then
    out.rates, out.slots, out.rate = {}, {}, nil
    if area.times then
      keys(area.times, { MORN = true, DAY = true, NITE = true })
      for time, row in pairs(area.times) do
        keys(row, { rate = true, slots = true })
        if row.rate ~= nil then
          expect(row.rate == DELETE or integer(row.rate, 0, 255), "invalid encounter rate")
          out.rates[time] = row.rate
        end
        if row.slots ~= nil then out.slots[time] = rows(row.slots) end
      end
    end
    local previous = old and areaRead(old, generation, grass) or {}
    for _, time in ipairs({ "MORN", "DAY", "NITE" }) do
      if area.rate ~= nil and (not area.times or not equal(area.rate, previous.rate)) then
        out.rates[time] = area.rate
      end
      if area.slots ~= nil and (not area.times or not equal(area.slots, previous.slots)) then
        out.slots[time] = rows(area.slots)
      end
    end
  else
    if area.times ~= nil then refuse("time-specific encounters have no native representation") end
    if area.slots ~= nil then out.slots = rows(area.slots) end
  end
  return out
end

local function extraEntries(value, kind, writing, patch)
  local function slot(row)
    if writing then return slotWrite(row, 2, kind) end
    return slotRead(row)
  end
  if kind == "bugContest" then return list(value, slot, patch) end
  if kind == "roamMaps" or kind == "treeMonsAsleep" then return copy(value) end
  if kind == "roamMons" then
    return list(value, function(row)
      if not writing then
        local out = copy(row)
        out.minLevel, out.maxLevel = row.level, row.level
        return out
      end
      keys(row, fields("species level minLevel maxLevel mapGroup mapNumber map"))
      local out = copy(row)
      if row.level ~= nil then
        expect(integer(row.level, 1, 100), "invalid roaming level")
        out.minLevel, out.maxLevel = row.minLevel or row.level, row.maxLevel or row.level
        expect(out.minLevel == row.level, "conflicting roaming level")
      end
      if out.minLevel ~= nil or out.maxLevel ~= nil then
        expect(integer(out.minLevel, 1, 100) and out.minLevel == out.maxLevel,
          "roaming Pokemon require one level")
        out.level, out.minLevel, out.maxLevel = out.minLevel, nil, nil
      end
      return out
    end, patch)
  end
  record(value)
  local out = {}
  for id, row in pairs(value) do
    if row == DELETE then out[id] = DELETE
    else
      record(row)
      if kind == "fishGroups" then
        keys(row, fields("id index chance old good super"))
        out[id] = { id = row.id, index = row.index, chance = row.chance }
        for _, rod in ipairs({ "old", "good", "super" }) do
          if row[rod] ~= nil then out[id][rod] = list(row[rod], slot, patch) end
        end
      elseif kind == "timeFishGroups" then
        keys(row, { day = true, nite = true })
        out[id] = {}
        for _, time in ipairs({ "day", "nite" }) do
          if row[time] ~= nil then out[id][time] = slot(row[time]) end
        end
      elseif kind == "treeSets" then
        keys(row, { common = true, rare = true })
        out[id] = {}
        for _, group in ipairs({ "common", "rare" }) do
          if row[group] ~= nil then out[id][group] = list(row[group], slot, patch) end
        end
      end
    end
  end
  return out
end

local function encounterRead(id, native, generation)
  if generation == 2 then
    if EXTRA_ENCOUNTERS[id] then
      local value = native:get(id)
      if value == nil then return nil end
      return { id = id, kind = id, entries = extraEntries(value, id, false, false) }
    end
    local out, found = { id = id }, false
    for _, kind in ipairs(MAP_KINDS) do
      local value = (native:get(kind) or {})[id]
      if value ~= nil then
        found = true
        if kind == "trees" then out.treeSet = copy(value)
        elseif kind == "rocks" then out.rockSet = copy(value)
        else out[kind] = areaRead(value, generation, kind == "grass" or kind == "swarmGrass") end
      end
    end
    if found then return out end
    return nil
  end
  local value = native:get(id)
  if value == nil then return nil end
  local out = project(value, ENCOUNTER_FIELDS)
  out.id = id
  if generation == 3 then out.grass = nil end
  for _, kind in ipairs({ "grass", "water", "rocks", "fishing" }) do
    local source = kind == "grass" and (value.land or value.grass) or value[kind]
    if source then out[kind] = areaRead(source, generation, false) end
  end
  return out
end

local function rejectUnknown(value, shape, path)
  if value == DELETE then return end
  if shape.kind == "opt" then return rejectUnknown(value, shape.inner, path) end
  if type(value) ~= "table" then return end
  if shape.kind == "rec" or shape.kind == "partial" then
    for key, sub in pairs(value) do
      if not shape.fields[key] then refuse(path .. "." .. tostring(key)) end
      rejectUnknown(sub, shape.fields[key], path .. "." .. tostring(key))
    end
  elseif shape.kind == "list" then
    list(value, function(row)
      rejectUnknown(row, shape.inner, path)
      return row
    end, true)
  elseif shape.kind == "map" then
    for key, row in pairs(value) do rejectUnknown(row, shape.value, path .. "." .. tostring(key)) end
  elseif shape.kind == "union" then
    local lastError
    for _, alt in ipairs(shape.alts) do
      if Schemas.check({ value = alt }, path, "value", value, "patch") then
        local ok, reason = pcall(rejectUnknown, value, alt, path)
        if ok then return end
        lastError = reason
      end
    end
    if lastError then error(lastError, 0) end
  end
end

local function validate(name, id, value, mode, generation)
  local spec = Schemas.shapeFor(name, Schemas.REGISTRIES[name], generation)
  if mode ~= "remove" and value ~= DELETE then
    if spec.fields then
      record(value)
      for key, row in pairs(value) do
        if not spec.fields[key] then refuse(name .. "." .. tostring(key)) end
        rejectUnknown(row, spec.fields[key], name .. "." .. tostring(key))
      end
    elseif spec.value then rejectUnknown(value, spec.value, name)
    elseif spec.keys or spec.keyValue then
      local shape = (spec.keys or {})[id] or spec.keyValue
      if shape then rejectUnknown(value, shape, name) end
    end
  end
  local ok, reason = Schemas.check(spec, name, id, value, mode)
  expect(ok, reason or "schema mismatch")
end

local function readCore(name, value, generation)
  if value == nil then return nil end
  if name == "pokemon" then return monRead(value, generation) end
  if name == "trainers" then return trainerRead(value, generation) end
  if name == "moves" then
    local out = project(value, coreFields(name, MOVE_FIELDS, generation))
    out.effect = effectRead(value.effect, generation, value)
    if generation == 3 then out.type = Ids.canonical(out.type, "type", 3) end
    if generation == 2 then out.secondaryChance = value.effectChance end
    if out.category == nil then
      local physical = fields("NORMAL FIGHTING FLYING POISON GROUND ROCK BUG GHOST STEEL")
      out.category = (value.power or 0) == 0 and "status"
        or physical[value.type] and "physical" or "special"
    end
    return out
  end
  if name == "items" then
    local out = project(value, coreFields(name, ITEM_FIELDS, generation))
    if generation == 2 then out.tossable = value.canToss end
    return out
  end
  return copy(value)
end

local function writeCore(name, value, old, generation, patch)
  if value == DELETE then return DELETE end
  if name == "pokemon" then return monWrite(value, old, generation, patch) end
  if name == "trainers" then return trainerWrite(value, old, generation, patch) end
  local allowed = coreFields(name, name == "moves" and MOVE_FIELDS or ITEM_FIELDS, generation)
  keys(value, allowed)
  nativeExtension(value, old, allowed)
  local out = copy(value)
  out.native = nil
  if name == "moves" then
    local chance = value.secondaryChance
    local changed = false
    if value.effect ~= nil then
      if old and value.effect == effectRead(old.effect, generation, old) then out.effect = old.effect
      else
        local defaultChance
        out.effect, defaultChance = effectWrite(value.effect, generation, old)
        changed = true
        if generation ~= 1 and type(value.effect) == "string"
            and not value.effect:match("^native:") then out._modEffectId = value.effect end
        if chance == nil and generation ~= 1 then chance = defaultChance end
      end
    end
    if chance ~= nil then
      if generation == 1 then refuse("secondaryChance has no Gen 1 representation") end
      expect(chance == DELETE or integer(chance, 0, 100), "invalid secondaryChance")
      if generation == 2 then
        out.effectChance, out.secondaryChance = chance, nil
        if chance == DELETE then out.effectChanceRaw = DELETE
        elseif not changed and old and chance == old.effectChance then
          out.effectChanceRaw = old.effectChanceRaw
        else out.effectChanceRaw = math.floor(chance * 255 / 100) end
      else out.secondaryChance = chance end
    end
    if (generation == 2 or generation == 3) and value.category ~= nil then
      local combined = effective(old, out)
      combined.category = nil
      local expected = readCore("moves", combined, generation).category
      if value.category ~= expected then refuse("move category is determined by type and power") end
      out.category = nil
    end
    if generation == 2 and value.priority ~= nil then
      refuse("Gen 2 priority uses native move dispatch")
    end
  elseif generation == 2 and value.tossable ~= nil then
    expect(type(value.tossable) == "boolean" or value.tossable == DELETE, "invalid tossable")
    out.canToss, out.tossable = value.tossable, nil
  end
  return out
end

local GEN3_DELETES = fields("pokemon.genderRatio pokemon.eggCycles pokemon.friendship "
  .. "pokemon.eggGroups pokemon.itemCommon pokemon.itemRare pokemon.abilities "
  .. "pokemon.tmhm pokemon.eggMoves pokemon.dexEntry "
  .. "pokemon.dexEntry.heightM pokemon.dexEntry.weightKg "
  .. "moves.effect moves.secondaryChance moves.target moves.priority moves.flags "
  .. "items.pocket items.fieldUse items.holdEffect items.holdEffectParam "
  .. "items.importance items.registrability items.battleUsage items.secondaryId items.description")

local function checkDeletes(value, shape, path, generation)
  if not shape then return end
  if value == DELETE then
    if shape.kind ~= "opt" then refuse("cannot delete required field " .. path) end
    if generation == 3 and not GEN3_DELETES[path] then
      refuse("native field deletion " .. path)
    end
    return
  end
  if shape.kind == "opt" then return checkDeletes(value, shape.inner, path, generation) end
  if type(value) ~= "table" then return end
  if shape.kind == "rec" or shape.kind == "partial" then
    for key, sub in pairs(value) do
      checkDeletes(sub, shape.fields[key], path .. "." .. tostring(key), generation)
    end
  elseif shape.kind == "map" then
    for key, sub in pairs(value) do
      if sub ~= DELETE then checkDeletes(sub, shape.value, path .. "." .. tostring(key), generation) end
    end
  end
end

local function textDialect(version)
  if version == "ruby" or version == "sapphire" then return "rs" end
  return GameVersion.layout(version) or TextIR.DEFAULT_DIALECT
end

local function textSource(value, generation, version)
  if generation ~= 3 then
    expect(type(value) == "string", "text must be a source string")
    if value:find("[\r\252]") then refuse("unrepresentable text control") end
    return (value:gsub("\\([nplf])", { n = "\n", p = "\f", l = "\v", f = "\f" }))
  end
  local dialect = TextIR.dialect(textDialect(version))
  local ir = value
  if type(value) == "string" then
    if value:find("[\r\252]") then refuse("unrepresentable text control") end
    ir = TextIR.fromAscii((value:gsub("\v", "\\l")), { dialect = dialect })
  end
  local ended = false
  local rows = list(ir, function(seg)
    record(seg)
    expect(not ended, "text after end of string")
    local row = copy(seg)
    if row.t == "eos" then
      keys(row, { t = true })
      ended = true
    elseif row.t == "text" then
      keys(row, { t = true, s = true })
      expect(type(row.s) == "string", "invalid text segment")
      local parsed = TextIR.fromAscii(row.s, { dialect = dialect })
      if row.s ~= "" and (#parsed ~= 2 or parsed[1].t ~= "text" or parsed[1].s ~= row.s) then
        refuse("literal text has no lossless source representation")
      end
    elseif row.t == "ph" or row.t == "bph" then
      keys(row, { t = true, code = true, name = true })
      local name = row.name or (row.t == "ph" and dialect.PH_NAMES[row.code]
        or dialect.B_TXT[row.code])
      if not identifier(name) or (generation == 3 and row.t == "ph" and not dialect.PH_CODE[name]) then
        refuse("unknown text placeholder")
      end
      row = { t = "tag", tag = "{" .. name .. "}" }
    elseif row.t == "tag" then
      keys(row, { t = true, tag = true })
      expect(type(row.tag) == "string", "invalid text tag")
      if not TextIR.TAG_NAMES[row.tag:match("^{(.+)}$")] then refuse("text printer control") end
    elseif row.t == "strvar" then
      keys(row, { t = true, n = true })
      expect(integer(row.n, 1, 3), "invalid text string variable")
    elseif row.t == "player" or row.t == "rival" or row.t == "nl"
        or row.t == "para" or row.t == "scroll" then
      keys(row, { t = true })
    else refuse("text control " .. tostring(row.t)) end
    return row
  end, false)
  local source = TextIR.toSource(rows, { dialect = dialect },
    { named = true, nl = "\n", para = "\f", scroll = "\v" })
  return (source:gsub("%%%%", "%%"))
end

local function textWrite(value, generation, version)
  if value == DELETE then return DELETE end
  expect(type(value) == "string", "text must be a source string")
  local source = textSource(value, generation, version)
  if generation == 3 then
    return TextIR.fromAscii((source:gsub("\v", "\\l")), { dialect = textDialect(version) })
  end
  return (source:gsub("\\([npl])", { n = "\n", p = "\f", l = "\v" }))
end

local function emptyLists(value, shape)
  if type(value) ~= "table" or value == DELETE or not shape then return nil end
  if shape.kind == "opt" then return emptyLists(value, shape.inner) end
  if shape.kind == "list" then
    if next(value) == nil then return DELETE end
    return nil
  end
  local out = {}
  if shape.kind == "rec" or shape.kind == "partial" then
    for key, sub in pairs(value) do
      local clear = emptyLists(sub, shape.fields[key])
      if clear then out[key] = clear end
    end
  elseif shape.kind == "map" then
    for key, sub in pairs(value) do
      local clear = emptyLists(sub, shape.value)
      if clear then out[key] = clear end
    end
  end
  if next(out) then return out end
end

local function clearingPatch(name, id, value, generation)
  if type(value) ~= "table" or value == DELETE then return nil end
  local spec = Schemas.shapeFor(name, Schemas.REGISTRIES[name], generation)
  local shape = spec.value or (spec.keys and spec.keys[id]) or spec.keyValue
  if spec.fields then shape = { kind = "rec", fields = spec.fields } end
  return emptyLists(value, shape)
end

local function preserveExtensions(payload, canonical, name, generation)
  if type(payload) ~= "table" or payload == DELETE then return end
  local function restore(target, extension, excluded)
    for key, value in pairs(extension or {}) do
      if target[key] == nil and not (excluded or {})[key] then target[key] = copy(value) end
    end
  end
  restore(payload, canonical.native)
  if name ~= "trainers" or type(canonical.parties) ~= "table"
      or canonical.parties == DELETE then return end
  local function rows(parties, target)
    for i, row in ipairs(parties) do
      local nativeRow = target and target[i]
      if nativeRow then
        if generation == 2 then restore(nativeRow, row.native, { trainerType = true }) end
        local mons = generation == 1 and nativeRow or generation == 2 and nativeRow.party or target
        for j, mon in ipairs(row) do
          if mons and mons[j] then restore(mons[j], mon.native, { heldItem = true }) end
        end
      end
    end
  end
  local target = generation == 1 and payload.parties or generation == 2 and payload.trainers or payload.party
  if not target or target == DELETE then return end
  if Merge.isWrapper(canonical.parties) then
    for key, parties in pairs(canonical.parties) do rows(parties, target[key]) end
  else rows(canonical.parties, target) end
end

local function nativeTable(base, ...)
  if type(base) ~= "table" then return nil end
  for i = 1, select("#", ...) do
    local value = base[(select(i, ...))]
    if type(value) == "table" then return value end
  end
  return nil
end

local function gen3Index(loader, name, id, value, old)
  local registry = loader.content and loader.content[name]
  expect(registry ~= nil, "missing native registry")
  if old and value.index ~= nil and value.index ~= old.index then
    refuse("changing a Gen 3 native index")
  end
  local used = {}
  local function reserve(index, owner)
    if integer(index, 1, 65535) then
      if owner == id then used[index] = used[index] or id
      else used[index] = owner or true end
    end
  end
  local base = registry.base and registry.base()
  if base then
    local rows = {}
    if name == "pokemon" then
      local native = Schemas.gen3View.monTables(base)
      for _, key in ipairs({ "names", "stats", "meta", "types", "abilities",
          "learnsets", "eggMoves", "evolutions" }) do rows[#rows + 1] = native[key] or {} end
      rows[#rows + 1] = native.tmhm and native.tmhm.learnsets or {}
      rows[#rows + 1] = native.national and native.national.toNational or {}
    elseif name == "moves" then
      local moves = Schemas.gen3View.moveRows(base)
      local pokemon = loader.content and loader.content.pokemon
      local pokemonBase = pokemon and pokemon.base and pokemon.base()
        or Schemas.liveModuleFor("gen3Pokemon", loader.version)
      local native = Schemas.gen3View.monTables(pokemonBase)
      local names = nativeTable(base, "_moveNames", "moveNames", "names") or native.moveNames
      rows = { moves or {}, names or {}, native.moveNames or {}, native.battleMoves or {},
        nativeTable(base, "_linkRows") or {} }
    else
      local items = Schemas.gen3View.itemRows(base)
      local pack = nativeTable(base, "_pack")
      rows = { items or {}, nativeTable(pack, "items") or {}, nativeTable(base, "items") or {} }
    end
    for _, row in ipairs(rows) do for index in pairs(row) do reserve(index) end end
    local original = registry.spec and registry.spec.baseAt and registry.spec.baseAt(base, id)
    if original and original.index then used[original.index] = id end
  end
  for other, row in registry:each() do
    if type(row) == "table" then reserve(row.index, other) end
  end
  for other, ops in pairs(registry.ops or {}) do
    for _, op in ipairs(ops) do
      if type(op.value) == "table" then reserve(op.value.index, other) end
    end
  end
  if name == "pokemon" then used[412] = true end
  local index = value.index or (old and old.index)
  if index == nil then
    for candidate = 1, 65535 do
      if not used[candidate] then index = candidate; break end
    end
  end
  expect(integer(index, 1, 65535), "no valid Gen 3 native index")
  expect(used[index] == nil or used[index] == id, "Gen 3 native index collision")
  value.index = index
end

local function gen3References(loader, name, payload, currentId)
  local function reference(registryName, id)
    local registry = loader.content and loader.content[registryName]
    local base = registry and registry.base and registry.base()
    local staged = registry and registry:get(id)
    local num = staged and staged.index
    if registryName == name and id == currentId then num = payload.index end
    if not num and base and staged ~= nil then
      if registryName == "pokemon" then num = Schemas.gen3View.speciesNum(base, id)
      elseif registryName == "moves" then num = Schemas.gen3View.moveNum(base, id)
      elseif registryName == "items" then num = Schemas.gen3View.itemNum(base, id) end
    end
    if not identifier(id) or not integer(num, 1, 65535)
        or (registryName == "pokemon" and num == 412) then
      refuse("unmapped Gen 3 " .. registryName .. " id " .. tostring(id))
    end
    return num
  end
  if payload == DELETE then return end
  if name == "pokemon" or name == "moves" then
    local validTypes = {}
    for _, id in pairs(Schemas.gen3View.TYPES) do validTypes[id] = true end
    validTypes.PSYCHIC_TYPE, validTypes.CURSE_TYPE = true, true
    local chart = loader.content and loader.content.type_chart
    setmetatable(validTypes, { __index = function(_, id)
      return type(id) == "string" and not id:find(">", 1, true)
        and chart ~= nil and chart:get(id) ~= nil
    end })
    if name == "moves" and payload.type and payload.type ~= DELETE and not validTypes[payload.type] then refuse("unknown Gen 3 type") end
    if payload.types and payload.types ~= DELETE then
      list(payload.types, function(id)
        if not validTypes[id] then refuse("unknown Gen 3 type") end
        return id
      end, true)
    end
    if payload.growthRate and payload.growthRate ~= DELETE then
      local found = false
      for _, id in pairs(Schemas.gen3View.GROWTH) do if id == payload.growthRate then found = true end end
      local curves = loader.content and loader.content.growth_rates
      if curves and curves:get(payload.growthRate) ~= nil then found = true end
      if not found then refuse("unknown Gen 3 growth rate") end
    end
  end
  local function scan(value)
    if type(value) ~= "table" or value == DELETE then return end
    for key, sub in pairs(value) do
      if (key == "species" or key == "move" or key == "item" or key == "heldItem"
          or key == "itemCommon" or key == "itemRare") and sub ~= DELETE then
        reference((key == "species" and "pokemon") or (key == "move" and "moves") or "items", sub)
      elseif (key == "moves" or key == "tmhm" or key == "eggMoves") and sub ~= DELETE then
        list(sub, function(id) reference("moves", id); return id end, true)
      else scan(sub) end
    end
  end
  scan(payload)
  if name == "trainers" and payload.items then
    payload.items = list(payload.items, function(id) return reference("items", id) end, true)
  end
end

local function accessor(loader, name, native, generation, version, mod)
  local available, reason = UnifiedContent.supports(name, generation, version)
  if not native then available, reason = false, UNSUPPORTED .. "missing registry accessor" end
  local out = { available = available }
  out.supports = function() return available, reason end
  local function containsSpecies(id)
    local registry = loader.content and loader.content.pokemon
    local base = registry and registry.base and registry.base()
    if base and base[id] ~= nil then return true end
    if registry and ((registry.ops and registry.ops[id] ~= nil)
        or (registry.seen and registry.seen[id])) then return true end
    local pokemon = name == "pokemon" and native or registry
    return pokemon ~= nil and pokemon:get(id) ~= nil
  end
  local function nativeId(id)
    if name == "pokemon" then return Ids.native(id, "species", generation, containsSpecies) end
    return id
  end
  local function get(id)
    if not available then return nil, reason end
    expect(identifier(id), "registry id is required")
    id = nativeId(id)
    if name == "encounters" then
      return Ids.record(encounterRead(id, native, generation), generation, false)
    end
    if name == "text" or name == "rom_text" then
      local value = native:get(id)
      if value == nil then return nil end
      return textSource(value, generation, version)
    end
    return Ids.record(readCore(name, native:get(id), generation), generation, false,
      nil, name == "pokemon")
  end
  out.get = function(_, id) return get(id) end
  out.has = function(_, id) return get(id) ~= nil end
  out.each = function()
    if not available then return function() end end
    local set = {}
    if name == "encounters" and generation == 2 then
      for _, kind in ipairs(MAP_KINDS) do
        for id in pairs(native:get(kind) or {}) do if identifier(id) then set[id] = true end end
      end
      for id in pairs(EXTRA_ENCOUNTERS) do if native:get(id) ~= nil then set[id] = true end end
    else
      for nativeId in native:each() do
        if identifier(nativeId) then
          local id = nativeId
          if name == "pokemon" then id = Ids.canonical(id, "species", generation) end
          set[id] = true
        end
      end
    end
    local all = {}
    for id in pairs(set) do all[#all + 1] = id end
    table.sort(all)
    local i = 0
    return function()
      while i < #all do
        i = i + 1
        local value = get(all[i])
        if value ~= nil then return all[i], value end
      end
    end
  end

  local function mutate(mode, id, value)
    if not available then return nil, reason end
    expect(identifier(id), "registry id is required")
    finite(value)
    if generation == 3 and name == "trainers" then
      local number = tonumber(id)
      if not integer(number, 0, 65535) or tostring(number) ~= id then
        refuse("Gen 3 trainer ids must be decimal strings")
      end
    end
    local registry = loader.content and loader.content[name]
    if registry and registry.frozen then error(name .. ": content is frozen after load", 0) end
    id = nativeId(id)
    value = Ids.record(value, generation, true, containsSpecies, name == "pokemon")
    local old = native:get(id)
    local patch = mode == "patch"
    if name == "encounters" and generation == 2 then
      old = encounterRead(id, native, generation)
    end
    if mode == "register" and old ~= nil
        and Schemas.REGISTRIES[name].semantics == "record" then
      error(name .. " already registered: " .. id, 0)
    end
    if generation == 3 and CORE[name] and type(value) == "table" and value ~= DELETE
        and old and value.index ~= nil and value.index ~= old.index then
      refuse("changing a Gen 3 native index")
    end
    if name == "encounters" then
      local prepared = {}
      local function prepare(kind, target, payload)
        validate(name, target, payload, kind, generation)
        if generation == 3 and payload ~= nil then gen3References(loader, name, payload) end
        if kind == "patch" then
          local clear = clearingPatch(name, target, payload, generation)
          if clear then
            validate(name, target, clear, "patch", generation)
            prepared[#prepared + 1] = { "patch", target, clear }
          end
        end
        prepared[#prepared + 1] = { kind, target, payload }
      end
      if generation == 2 then
        if EXTRA_ENCOUNTERS[id] then
          if mode == "remove" then prepare("remove", id)
          elseif value == DELETE then prepare("patch", id, DELETE)
          else
            keys(value, ENCOUNTER_FIELDS)
            expect(value.kind == id and value.entries ~= nil, "auxiliary encounters require kind and entries")
            for key in pairs(value) do
              expect(key == "id" or key == "kind" or key == "entries", "invalid auxiliary encounter field")
            end
            prepare(mode, id, extraEntries(value.entries, id, true, patch))
          end
        else
          if mode ~= "remove" and value ~= DELETE then keys(value, ENCOUNTER_FIELDS) end
          local replacing = mode ~= "patch" or value == DELETE
          local allowed = fields("id grass water swarmGrass swarmWater treeSet rockSet")
          if type(value) == "table" and value ~= DELETE then keys(value, allowed) end
          for _, kind in ipairs(MAP_KINDS) do
            local key = kind == "trees" and "treeSet" or kind == "rocks" and "rockSet" or kind
            local part = type(value) == "table" and value ~= DELETE and value[key] or nil
            if mode == "remove" or value == DELETE or (replacing and part == nil) then
              if (native:get(kind) or {})[id] ~= nil then prepare("patch", kind, { [id] = DELETE }) end
            elseif part ~= nil then
              local converted
              if kind == "trees" or kind == "rocks" then
                expect(part == DELETE or identifier(part), "invalid encounter set id")
                converted = part
              else converted = areaWrite(part, generation, kind == "grass" or kind == "swarmGrass", patch,
                (native:get(kind) or {})[id]) end
              if replacing and (native:get(kind) or {})[id] ~= nil then
                prepare("patch", kind, { [id] = DELETE })
              end
              if not patch and converted ~= DELETE and kind ~= "trees" and kind ~= "rocks" then
                validate(name, kind, { [id] = converted }, "override", generation)
              end
              prepare("patch", kind, { [id] = converted })
            end
          end
        end
      elseif mode == "remove" then prepare(mode, id)
      elseif value == DELETE then prepare(mode, id, value)
      else
        keys(value, ENCOUNTER_FIELDS)
        nativeExtension(value, old, ENCOUNTER_FIELDS)
        local payload = {}
        for key, part in pairs(value) do
          if key ~= "native" then
            if key == "id" or key == "mapGroup" or key == "mapNum" then payload[key] = copy(part)
            elseif key == "grass" or key == "water" or (generation == 3 and (key == "rocks" or key == "fishing")) then
              local target = key
              if generation == 3 and key == "grass" then target = old and old.grass and not old.land and "grass" or "land" end
              payload[target] = areaWrite(part, generation, false, patch)
            else refuse("encounter field " .. key) end
          end
        end
        prepare(mode, id, payload)
      end
      for _, op in ipairs(prepared) do native[op[1]](native, op[2], op[3]) end
      return get(id)
    end
    if mode == "remove" then native:remove(id); return nil end
    local payload = CORE[name] and writeCore(name, value, old, generation, patch) or copy(value)
    if name == "text" or name == "rom_text" then payload = textWrite(value, generation, version) end
    if CORE[name] and type(payload) == "table" and payload ~= DELETE then
      if not patch then payload.id = payload.id or id end
      if generation == 3 and (name == "pokemon" or name == "moves" or name == "items") then
        gen3Index(loader, name, id, payload, old)
      elseif generation == 2 then
        payload = Schemas.gen2Index(registry, id, payload)
      end
      local spec = Schemas.shapeFor(name, Schemas.REGISTRIES[name], generation)
      checkDeletes(payload, { kind = "rec", fields = spec.fields }, name, generation)
    end
    local schemaPayload = copy(payload)
    if generation == 2 and name == "moves" then
      if payload.effectChance ~= nil and payload.effectChance ~= DELETE then
        expect(integer(payload.effectChance, 0, 100), "invalid secondaryChance")
      end
      schemaPayload.effectChance, schemaPayload.effectChanceRaw = nil, nil
      if payload.description ~= nil then
        expect(payload.description == DELETE or type(payload.description) == "string", "invalid description")
        schemaPayload.description = nil
      end
    elseif generation == 2 and name == "items" then
      schemaPayload.canToss = nil
      for _, key in ipairs({ "pocket", "description" }) do
        if payload[key] ~= nil then
          expect(payload[key] == DELETE or type(payload[key]) == "string", "invalid " .. key)
          schemaPayload[key] = nil
        end
      end
    end
    validate(name, id, schemaPayload, mode, generation)
    if generation == 3 and CORE[name] then gen3References(loader, name, payload, id) end
    if CORE[name] and value ~= DELETE then preserveExtensions(payload, value, name, generation) end
    local nativeSpec = Schemas.shapeFor(name, Schemas.REGISTRIES[name], generation)
    local valid, detail = Schemas.check(nativeSpec, name, id, payload, mode)
    expect(valid, detail or "schema mismatch")
    if patch and value ~= DELETE and (name == "pokemon" or name == "trainers" or name == "moves") then
      local source = copy(value)
      if generation == 2 and payload.index ~= nil then source.index = payload.index end
      local function stripMetadata(row)
        if type(row) ~= "table" or row == DELETE then return end
        row.native = nil
        for _, sub in pairs(row) do stripMetadata(sub) end
      end
      stripMetadata(source)
      loader:_journal(name)
      local owner = mod.manifest and mod.manifest.id or mod.id
      registry:patchTransformed(id, source, owner, function(current, canonical)
        canonical = Ids.record(canonical, generation, true, containsSpecies, name == "pokemon")
        local converted = writeCore(name, canonical, current, generation, true)
        local clear = clearingPatch(name, id, converted, generation)
        local result = copy(current or {})
        if clear then result = Merge.deepMerge(result, clear, registry.spec.semantics) end
        return Merge.deepMerge(result, converted, registry.spec.semantics)
      end)
      return get(id)
    end
    if CORE[name] and patch then
      local clear = clearingPatch(name, id, payload, generation)
      if clear then
        local clearValid, clearDetail = Schemas.check(nativeSpec, name, id, clear, "patch")
        expect(clearValid, clearDetail or "invalid list replacement")
        native:patch(id, clear)
      end
    end
    if generation == 2 and name == "item_effects" and type(payload) == "table" then
      Gen2ItemEffects.markUnified(payload.use)
    end
    native[mode](native, id, payload)
    return get(id)
  end
  for _, mode in ipairs(VERBS) do
    if not native or native[mode] ~= nil then
      out[mode] = function(_, id, value)
        local previousLoader = activeLoader
        activeLoader = loader
        local ok, result, detail = pcall(mutate, mode, id, value)
        activeLoader = previousLoader
        if ok then return result, detail end
        if type(result) == "string" and result:sub(1, #UNSUPPORTED) == UNSUPPORTED then
          return nil, result
        end
        error(result, 0)
      end
    end
  end
  return out
end

function UnifiedContent.new(loader, mod, nativeContent)
  local out, made = {}, {}
  for name in pairs(Schemas.REGISTRIES) do
    made[name] = accessor(loader, name, nativeContent[name], loader.generation, loader.version, mod)
    out[name] = made[name]
  end
  for alias, canonical in pairs(Schemas.ALIASES) do out[alias] = made[canonical] end
  return out
end

function UnifiedContent.wrapDataset(view, mod)
  if view == nil then return nil end
  return { version = view.version, generation = view.generation,
    content = UnifiedContent.new(view, mod, view.content), assets = view.assets }
end

return UnifiedContent
