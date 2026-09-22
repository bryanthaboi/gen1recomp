-- Gen 1 module facades for a FireRed boot: the Gen 1 API backed by src/core/game3.
-- Contract mirrors src/mods/Gen2Compat.lua; docs/mod-api-gen3-compat.md.

local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")

local Gen3Compat = {}

local rawRequire = require

local resolveGame = nil
local lastGame = nil

local built = {}
local claimants = {}
local warned = {}

local function warnOnce(key, fmt, ...)
  if warned[key] then return end
  warned[key] = true
  Logger.warn(fmt, ...)
end

local function who(name)
  local ids = claimants[name]
  if not ids or #ids == 0 then return "a gen3 mod" end
  return table.concat(ids, ", ")
end

local function live()
  local g = resolveGame and resolveGame() or nil
  return g or lastGame
end

local function unbacked(module, member, why)
  return function()
    warnOnce(module .. "." .. member,
      "[%s] %s.%s has no Gen 3 backing: %s", who(module), module, member, why)
    return nil
  end
end

local function g3(name)
  local ok, module = pcall(rawRequire, "src.core.game3." .. name)
  if ok then return module end
  return nil
end

local function ui3(name)
  local ok, module = pcall(rawRequire, "src.ui.game3." .. name)
  if ok then return module end
  return nil
end

local function session()
  local R = package.loaded["src.core.game3.runtime"]
  local s = R and R.getSession and R.getSession()
  if s then return s end
  local g = live()
  return g and g.session or nil
end

local function space()
  return package.loaded["src.core.game3.scripting.space"]
end

local function flagStore()
  local S = space()
  return S and S.store or nil
end

local function inField()
  local g = live()
  if g and g.phase ~= nil and g.phase ~= "field" then return false end
  return session() ~= nil
end

local COVERAGE = {}

Gen3Compat.COVERAGE_VERSION = 1
Gen3Compat.STATUS = { BACKED = "backed", WARNED = "warned", ABSENT = "absent" }

local function words(s)
  local out = {}
  for w in tostring(s or ""):gmatch("%S+") do out[#out + 1] = w end
  return out
end

-- ------- ids

local MAP_PREFIX = "FR_"

function Gen3Compat.gen1MapId(id)
  if type(id) ~= "string" then return id end
  if id:sub(1, #MAP_PREFIX) == MAP_PREFIX then return id:sub(#MAP_PREFIX + 1) end
  return id
end

function Gen3Compat.gen3MapId(id)
  if type(id) ~= "string" then return id end
  local g = live()
  local maps = g and g.data and g.data.maps
  if maps then
    if maps[id] then return id end
    if maps[MAP_PREFIX .. id] then return MAP_PREFIX .. id end
    return nil
  end
  if id:sub(1, #MAP_PREFIX) == MAP_PREFIX then return id end
  return MAP_PREFIX .. id
end

local function canonicalName(display)
  if type(display) ~= "string" then return nil end
  local s = display:upper()
  s = s:gsub("♂", "_M"):gsub("♀", "_F")
  s = s:gsub("[%.']", ""):gsub("[%s%-]+", "_")
  s = s:gsub("[^%w_]", ""):gsub("_+", "_"):gsub("^_", ""):gsub("_$", "")
  return s
end

function Gen3Compat.speciesId(ref)
  if type(ref) == "number" then return ref end
  if type(ref) ~= "string" then return nil end
  local n = tonumber(ref)
  if n then return n end
  local P = g3("pokemon")
  return P and P.speciesFromName and P.speciesFromName(ref) or nil
end

function Gen3Compat.speciesName(sp)
  if type(sp) == "string" and not tonumber(sp) then return sp end
  sp = tonumber(sp)
  if not sp then return nil end
  local P = g3("pokemon")
  if P and P.keyName then
    local key = P.keyName(sp)
    if key then return key end
  end
  if not (P and P.name) then return nil end
  return canonicalName(P.name(sp))
end

function Gen3Compat.itemId(ref)
  if type(ref) == "number" then return ref end
  local D = g3("items_data")
  local num = D and D.toNumericId and D.toNumericId(ref)
  if num then return num end
  if type(ref) == "string" and D and D.toNumericId then
    return D.toNumericId((ref:gsub("_", " ")))
  end
  return nil
end

function Gen3Compat.moveId(ref)
  if type(ref) == "number" then return ref end
  if type(ref) ~= "string" then return nil end
  local n = tonumber(ref)
  if n then return n end
  local M = g3("battle.moves")
  if not M then return nil end
  local norm = M.normalizeId and M.normalizeId(ref) or ref
  local num = M.numForName and M.numForName(norm) or nil
  if num then return num end
  local okS, Schemas = pcall(rawRequire, "src.mods.Schemas")
  if okS and Schemas and Schemas.gen3View then
    local n = Schemas.gen3View.moveNum(M, ref)
    if type(n) == "number" then return n end
  end
  return nil
end

local function schemaId(display)
  if type(display) ~= "string" or display == "" then return nil end
  local okS, Schemas = pcall(rawRequire, "src.mods.Schemas")
  if okS and Schemas and Schemas.gen3View then
    return Schemas.gen3View.idOf(display)
  end
  return canonicalName(display)
end

function Gen3Compat.moveName(ref)
  if type(ref) == "table" then ref = ref.numId or ref.id or ref.move end
  if type(ref) == "string" and not tonumber(ref) then return ref end
  local num = tonumber(ref)
  if not num or num < 1 then return nil end
  local P = g3("pokemon")
  local name = P and P.moveName and P.moveName(num)
  if type(name) ~= "string" or name == "" or name:match("^MOVE ") then
    local M = g3("battle.moves")
    name = M and M.BY_NUM and M.BY_NUM[num] or nil
  end
  return schemaId(name) or tostring(num)
end

function Gen3Compat.itemName(ref)
  if ref == nil or ref == 0 then return nil end
  if type(ref) == "string" and not tonumber(ref) then return ref end
  local num = tonumber(ref)
  if not num or num < 1 then return nil end
  local D = g3("items_data")
  local name = D and D.displayName and D.displayName(num)
  return schemaId(name) or tostring(num)
end

local function typeName(t)
  local okS, Schemas = pcall(rawRequire, "src.mods.Schemas")
  local types = okS and Schemas and Schemas.gen3View and Schemas.gen3View.TYPES
  local n = tonumber(t)
  return (types and n and types[n]) or t
end

function Gen3Compat.moveView(ref)
  local M = g3("battle.moves")
  if not M then return nil end
  local def = type(ref) == "table" and ref.effect ~= nil and ref or M.get(ref)
  if not def then return nil end
  local num = tonumber(def.numId) or Gen3Compat.moveId(type(ref) == "table" and def.id or ref)
  return {
    id = Gen3Compat.moveName(num) or def.id, index = num, num = num,
    name = M.displayName and M.displayName(num or def.id) or def.id,
    type = typeName(def.type), gen3Type = tonumber(def.type),
    power = def.power, accuracy = def.accuracy, pp = def.pp,
    priority = def.priority, category = def.category, effect = def.effect,
    target = def.target, secondaryChance = def.secondaryChance,
  }
end

function Gen3Compat.speciesView(sp)
  sp = Gen3Compat.speciesId(sp)
  if not sp then return nil end
  local P = g3("pokemon")
  local meta = P and P.speciesMeta and P.speciesMeta(sp) or {}
  return {
    id = Gen3Compat.speciesName(sp), index = sp,
    catchRate = tonumber(meta.catchRate), expYield = tonumber(meta.expYield),
    growthRate = tonumber(meta.growthRate),
  }
end

local function nameList(list, toName)
  if type(list) ~= "table" then return list end
  local out = {}
  for _, v in ipairs(list) do
    local name = (tonumber(v) or 0) ~= 0 and toName(v) or nil
    if name then out[#out + 1] = name end
  end
  return out
end

function Gen3Compat.partyNames(party)
  local out = {}
  for i, mon in ipairs(party or {}) do
    local row = {}
    for k, v in pairs(mon) do row[k] = v end
    local sp = tonumber(mon.species or mon.speciesId)
    row.species = Gen3Compat.speciesName(sp) or mon.species
    row.speciesId = sp
    if type(mon.moves) == "table" then
      row.moves = nameList(mon.moves, Gen3Compat.moveName)
      row.moveIds = {}
      for j, v in ipairs(mon.moves) do row.moveIds[j] = v end
    end
    if mon.heldItem ~= nil then
      row.heldItem = Gen3Compat.itemName(mon.heldItem)
      row.heldItemId = tonumber(mon.heldItem)
    end
    out[i] = row
  end
  return out
end

function Gen3Compat.partyNums(party)
  local out = {}
  for i, mon in ipairs(party or {}) do
    local row = {}
    for k, v in pairs(mon) do row[k] = v end
    row.species = Gen3Compat.speciesId(mon.species) or tonumber(mon.speciesId) or 0
    row.speciesId = nil
    if type(mon.moves) == "table" then
      local list = {}
      for j, v in ipairs(mon.moves) do list[j] = Gen3Compat.moveId(v) or 0 end
      row.moves = list
    end
    row.moveIds = nil
    if mon.heldItem ~= nil then
      row.heldItem = Gen3Compat.itemId(mon.heldItem)
    end
    row.heldItemId = nil
    out[i] = row
  end
  return out
end

-- ------- live views over the session

local function flagId(name)
  if type(name) == "number" then return name end
  if type(name) ~= "string" then return nil end
  local n = tonumber(name)
  if n then return n end
  local Flags = g3("scripting.flags")
  return Flags and Flags.IDS and Flags.IDS[name] or nil
end

local function varId(name)
  if type(name) == "number" then return name end
  if type(name) ~= "string" then return nil end
  local n = tonumber(name)
  if n then return n end
  local Flags = g3("scripting.flags")
  return Flags and Flags.VAR_IDS and Flags.VAR_IDS[name] or nil
end

function Gen3Compat.getFlag(name)
  local id = flagId(name)
  if not id then return nil end
  local Flags = g3("scripting.flags")
  local store = flagStore()
  if store and Flags then
    return Flags.getFlag(store, nil, id) and true or nil
  end
  local s = session()
  local flags = s and s.flags
  if not flags then return nil end
  return (flags[id] or flags[tostring(id)]) and true or nil
end

function Gen3Compat.setFlag(name, value)
  local id = flagId(name)
  if not id then return nil, "unknown FireRed flag: " .. tostring(name) end
  local Flags = g3("scripting.flags")
  local store = flagStore()
  if store and Flags then
    Flags.setFlag(store, nil, id, value and true or false)
    local Objects = package.loaded["src.core.game3.objects"]
    if Objects and Objects.syncFlagVisibility then
      Objects.syncFlagVisibility(id, value and true or false)
    end
    return true
  end
  local s = session()
  if not s then return nil, "no session" end
  s.flags = s.flags or {}
  s.flags[tostring(id)] = value and true or nil
  return true
end

function Gen3Compat.getVar(name)
  local id = varId(name)
  if not id then return nil end
  local Flags = g3("scripting.flags")
  local S = space()
  if S and S.store and Flags then
    return Flags.getVar(S.store, S.vm and S.vm.ctx, id)
  end
  local s = session()
  local vars = s and s.vars
  return vars and tonumber(vars[id] or vars[tostring(id)]) or 0
end

function Gen3Compat.setVar(name, value)
  local id = varId(name)
  if not id then return nil, "unknown FireRed var: " .. tostring(name) end
  local Flags = g3("scripting.flags")
  local S = space()
  if S and S.store and Flags then
    Flags.setVar(S.store, S.vm and S.vm.ctx, id, value)
    return true
  end
  local s = session()
  if not s then return nil, "no session" end
  s.vars = s.vars or {}
  s.vars[tostring(id)] = tonumber(value) or 0
  return true
end

local FLAGS_VIEW = setmetatable({}, {
  __index = function(_, key) return Gen3Compat.getFlag(key) end,
  __newindex = function(_, key, value)
    local ok, err = Gen3Compat.setFlag(key, value)
    if not ok then
      warnOnce("save.flags." .. tostring(key),
        "[%s] save.flags.%s: %s", who("src.core.Game"), tostring(key),
        tostring(err))
    end
  end,
})

local VARS_VIEW = setmetatable({}, {
  __index = function(_, key) return Gen3Compat.getVar(key) end,
  __newindex = function(_, key, value) Gen3Compat.setVar(key, value) end,
})

local INVENTORY_VIEW = setmetatable({}, {
  __index = function(_, key)
    local s = session()
    local Bag = g3("bag")
    if not (s and s.bag and Bag) then return nil end
    local id = Gen3Compat.itemId(key) or key
    local n = Bag.get(s.bag, id)
    if not n or n <= 0 then return nil end
    return n
  end,
  __newindex = function(_, key, value)
    local s = session()
    local Bag = g3("bag")
    if not (s and s.bag and Bag) then return end
    local id = Gen3Compat.itemId(key)
    if not id then
      warnOnce("save.inventory." .. tostring(key),
        "[%s] save.inventory.%s: no FireRed item of that name",
        who("src.core.Game"), tostring(key))
      return
    end
    Bag.set(s.bag, id, tonumber(value) or 0)
  end,
})

local function dexSide(field)
  return setmetatable({}, {
    __index = function(_, key)
      local s = session()
      local dex = s and s.dex and s.dex[field]
      local sp = Gen3Compat.speciesId(key)
      if not (dex and sp) then return nil end
      return (dex[sp] or dex[tostring(sp)]) and true or nil
    end,
    __newindex = function(_, key, value)
      local s = session()
      local sp = Gen3Compat.speciesId(key)
      if not (s and sp) then return end
      s.dex = s.dex or {}
      s.dex[field] = s.dex[field] or {}
      s.dex[field][sp] = value and true or nil
    end,
  })
end

local POKEDEX_VIEW = { seen = dexSide("seen"), caught = dexSide("owned") }

local PLAYER_VIEW = setmetatable({}, {
  __index = function(_, key)
    local s = session()
    if not s then return nil end
    if key == "name" then return s.name end
    if key == "rival" then return s.rivalName end
    if key == "money" then return s.money end
    if key == "map" then return Gen3Compat.gen1MapId(s.map) end
    if key == "gen3Map" then return s.map end
    if key == "x" or key == "y" or key == "facing" then
      local P = package.loaded["src.core.game3.player"]
      if P and inField() then
        if key == "x" then return P.cellX end
        if key == "y" then return P.cellY end
        return P.facing
      end
      return s[key]
    end
    return nil
  end,
  __newindex = function(_, key, value)
    local s = session()
    if not s then return end
    if key == "name" then s.name = value
    elseif key == "rival" then s.rivalName = value
    elseif key == "money" then s.money = value
    else
      warnOnce("save.player.write." .. tostring(key),
        "[%s] save.player.%s is read-only on FireRed; move the player with "
        .. "mod.world:warpTo", who("src.core.Game"), tostring(key))
    end
  end,
})

local SAVE_ABSENT = {
  boxes = "FireRed's PC is session.storage (14 boxes of 30 sparse slots); "
    .. "require src.pokemon.Boxes, which is served",
  box = "FireRed has no Gen 1 save.box",
  objectToggles = "an object's visibility IS its hide flag on FireRed",
  defeatedTrainers = "trainer defeats are flags 0x500 + trainer id",
  hiddenTaken = "hidden items are flags on FireRed",
}

local SAVE_VIEW = setmetatable({}, {
  __index = function(_, key)
    local s = session()
    if not s then return nil end
    if key == "flags" then return FLAGS_VIEW end
    if key == "vars" then return VARS_VIEW end
    if key == "inventory" then return INVENTORY_VIEW end
    if key == "player" then return PLAYER_VIEW end
    if key == "pokedex" then return POKEDEX_VIEW end
    if key == "gen3" then return s end
    local why = SAVE_ABSENT[key]
    if why then
      warnOnce("save.absent." .. key, "[%s] save.%s has no Gen 3 backing: %s",
        who("src.core.Game"), key, why)
      return nil
    end
    return s[key]
  end,
  __newindex = function(_, key, value)
    local s = session()
    if not s then return end
    if key == "flags" or key == "vars" or key == "inventory"
        or key == "player" or key == "pokedex" then
      warnOnce("save.replace." .. key,
        "[%s] save.%s cannot be replaced wholesale on FireRed; write its keys",
        who("src.core.Game"), key)
      return
    end
    s[key] = value
  end,
})

Gen3Compat.saveView = SAVE_VIEW

-- ------- data views

local recordCache = setmetatable({}, { __mode = "k" })

local function pokemonRecord(ref)
  local P = g3("pokemon")
  local sp = Gen3Compat.speciesId(ref)
  if not (P and sp) then return nil end
  local names = P._names
  if not names and P.install then pcall(P.install, P._cache) names = P._names end
  if not (names and names[sp]) then return nil end
  local byModule = recordCache[P]
  if not byModule or byModule.names ~= names then
    byModule = { names = names, rows = {} }
    recordCache[P] = byModule
  end
  local hit = byModule.rows[sp]
  if hit then return hit end
  local base = P.stats and P.stats(sp) or {}
  local meta = P.speciesMeta and P.speciesMeta(sp) or {}
  local root = "data/generated/gba/pokemon/"
  hit = {
    id = (P.keyName and P.keyName(sp)) or canonicalName(names[sp]),
    index = sp,
    gen3Species = sp,
    name = names[sp],
    types = P.types and P.types(sp) or nil,
    baseStats = { hp = base.hp, attack = base.atk, defense = base.def,
      speed = base.spe, specialAttack = base.spa, specialDefense = base.spd },
    catchRate = tonumber(meta.catchRate),
    growthRate = P.growthRate and P.growthRate(sp) or nil,
    abilities = P.abilities and P.abilities(sp) or nil,
    learnset = P.learnset and P.learnset(sp) or nil,
    evolutions = P.evolutions and P.evolutions(sp) or nil,
    dexEntry = P.dexEntry and P.dexEntry(sp) or nil,
    national = P.national and P.national(sp) or nil,
    spriteFront = root .. "front/" .. sp .. ".rgba",
    spriteBack = root .. "back/" .. sp .. ".rgba",
    trueColor = true,
  }
  byModule.rows[sp] = hit
  return hit
end

Gen3Compat.pokemonRecord = pokemonRecord

local function moveRecord(ref)
  local M = g3("battle.moves")
  local num = Gen3Compat.moveId(ref)
  if not (M and num and M.get) then return nil end
  local row = M.get(num)
  if not row then return nil end
  local out = {}
  for k, v in pairs(row) do out[k] = v end
  out.index = num
  out.name = out.name or (M.displayName and M.displayName(num))
  return out
end

Gen3Compat.moveRecord = moveRecord

local function itemRecord(ref)
  local D = g3("items_data")
  local num = Gen3Compat.itemId(ref)
  if not (D and num) then return nil end
  return D.info(num)
end

Gen3Compat.itemRecord = itemRecord

local function registryOverride(name, id)
  local g = live()
  local content = g and g.mods and g.mods.content
  local reg = content and content[name]
  if reg and reg.ops and type(id) == "string" and reg.ops[id] then
    return reg:get(id)
  end
  return nil
end

local function namedView(registry, record)
  return setmetatable({}, {
    __index = function(_, key)
      local over = registryOverride(registry, key)
      if over ~= nil then return over end
      return record(key)
    end,
    __newindex = function(_, key)
      warnOnce("data." .. registry .. ".write",
        "[%s] game.data.%s.%s: FireRed's %s are numeric ROM tables; change "
        .. "them through mod.content.%s", who("src.core.Game"), registry,
        tostring(key), registry, registry)
    end,
  })
end

local POKEMON_VIEW = namedView("pokemon", pokemonRecord)
local MOVES_VIEW = namedView("moves", moveRecord)
local ITEMS_VIEW = namedView("items", itemRecord)

local DATA_RENAMES = {
  encounters = "gen3Encounters", trainers = "gen3Trainers",
  text = "gen3Text", map_scripts = "gen3Scripts", scripts = "gen3Scripts",
}

local DATA_UNBACKED = {
  sprites = "FireRed's overworld sprites are baked by the extractor, not a "
    .. "data.sprites registry",
  field = "FireRed's field rules are src/core/game3/collision.lua and the "
    .. "ROM's metatile behaviours, not a data.field record",
  constants = "no Gen 1 rule table exists on FireRed",
  text_pointers = "the extractor's Gen 1 pointer table has no FireRed "
    .. "counterpart",
  trainer_headers = "the extractor's Gen 1 header table has no FireRed "
    .. "counterpart",
  palettes = "FireRed palettes are baked into the extracted RGBA art",
  icons = "FireRed icons are src/core/game3/pokemon.lua Pokemon.icon",
  battle_anims = "FireRed's battle animations are the pret script VM under "
    .. "src/core/game3/battle/anim_*",
  type_chart = "FireRed's type chart is src/core/game3/battle/types.lua",
}

local dataProxies = setmetatable({}, { __mode = "kv" })

local function mapsView(data)
  return setmetatable({}, {
    __index = function(_, key)
      local maps = data.maps
      if not maps then return nil end
      local hit = maps[key]
      if hit ~= nil then return hit end
      if type(key) == "string" then return maps[MAP_PREFIX .. key] end
      return nil
    end,
    __newindex = function(_, key, value)
      if data.maps then data.maps[Gen3Compat.gen3MapId(key) or key] = value end
    end,
  })
end

local function dataProxy(data)
  if not data then return nil end
  local hit = dataProxies[data]
  if hit then return hit end
  local maps = mapsView(data)
  hit = setmetatable({}, {
    __index = function(_, key)
      if key == "pokemon" then return POKEMON_VIEW end
      if key == "moves" then return MOVES_VIEW end
      if key == "items" then return ITEMS_VIEW end
      if key == "maps" then return maps end
      local renamed = DATA_RENAMES[key]
      if renamed then return data[renamed] end
      local why = DATA_UNBACKED[key]
      if why then
        warnOnce("data." .. key, "[%s] game.data.%s is Gen 1 only: %s",
          who("src.core.Game"), key, why)
        return nil
      end
      return data[key]
    end,
    __newindex = function(_, key, value) data[DATA_RENAMES[key] or key] = value end,
  })
  dataProxies[data] = hit
  return hit
end

Gen3Compat.dataView = dataProxy

-- ------- src.core.Game

local GAME_UNBACKED = {
  renderer = "FireRed composites through src/core/game3/display.lua at "
    .. "240x160 and never inits the Renderer singleton",
  load = "calling it would re-run FireRed's whole boot on top of a running "
    .. "game",
  bootConfig = "FireRed's new-game inputs are Schema.newGame's opts",
  makeTitleState = "src/ui/game3/boot.lua owns the title; nothing returns a "
    .. "state to push",
  step = "FireRed's logic tick is Game3:fixedUpdate; the input.step hook is "
    .. "the replacement",
  restoreSave = "FireRed continues through the boot menu "
    .. "(Game3:_handleBootAction), not a save table handed in",
  linkNet = "FireRed has no link play",
  linkSession = "FireRed has no link play",
}

local GAME_STACK_STATICS = {
  "worldBgBattleDim", "worldBgBattleInStack", "fillScaleInStack",
  "wideBattleInStack", "uiAnchorsHeldInStack", "drawBaseInStack", "dynamicUI",
}

local function buildGame()
  local proxy = {}
  local statics = nil

  local function gen1Static(key)
    if statics == nil then
      local ok, module = pcall(rawRequire, "src.core.Game")
      statics = ok and module or false
    end
    return statics and statics[key] or nil
  end

  local translate = {}

  function translate.overworld()
    if not inField() then return nil end
    return Gen3Compat.resolve("src.world.OverworldController")
  end
  function translate.data(g) return dataProxy(g.data) end
  function translate.save()
    if not session() then return nil end
    return SAVE_VIEW
  end
  function translate.stack()
    warnOnce("game.stack",
      "[%s] Game.stack on FireRed is src/ui/game3/stack.lua: push(id, module, "
      .. "opts) / pop(id) / top(), not a StateStack of state objects",
      who("src.core.Game"))
    return ui3("stack")
  end
  function translate.fixedStep() return rawRequire("src.core.FixedStep") end
  function translate.generation() return 3 end

  function translate.writeOptions()
    return function()
      local g = live()
      if g and g.writeOptions then return g:writeOptions() end
    end
  end

  function translate.logicSpeed()
    return function()
      local g = live()
      if not g or not g.logicSpeed then return 1 end
      return g:logicSpeed()
    end
  end

  function translate.applyOptions()
    return function(opts)
      local g = live()
      if not g or not g.applyOptions then return end
      if opts == proxy then opts = nil end
      return g:applyOptions(opts or g.options)
    end
  end

  function translate.saveGame()
    return function()
      local g = live()
      if g and g.saveGame then return g:saveGame() end
    end
  end

  function translate.writeSave() return translate.saveGame() end

  function translate.restartWithMods()
    return function() return rawRequire("src.core.HostShell").restart() end
  end

  function translate.recoverInput()
    return function()
      local g = live()
      if not g then return end
      local Input = rawRequire("src.core.Input")
      Input:reset()
      if Input.reconcile then Input:reconcile() end
      local okT, Touch = pcall(rawRequire, "src.core.TouchControls")
      if okT and Touch and Touch.reset then Touch:reset() end
      if g.mods and g.mods.releaseModInput then g.mods:releaseModInput() end
    end
  end

  function translate.zoomStep()
    return function(delta)
      local g = live()
      if g and g.zoomStep then g:zoomStep(delta) end
    end
  end

  local LIVE_FREE = { writeOptions = true, logicSpeed = true, fixedStep = true,
                      restartWithMods = true, generation = true }

  setmetatable(proxy, {
    __index = function(_, key)
      local why = GAME_UNBACKED[key]
      if why then
        warnOnce("game." .. key, "[%s] Game.%s has no Gen 3 backing: %s",
          who("src.core.Game"), key, why)
        return nil
      end
      local made = translate[key]
      if made then
        local g = live()
        if not g and not LIVE_FREE[key] then return nil end
        return made(g)
      end
      for _, name in ipairs(GAME_STACK_STATICS) do
        if name == key then return gen1Static(key) end
      end
      local g = live()
      if not g then return nil end
      local value = g[key]
      if value == nil then
        warnOnce("game.unknown." .. tostring(key),
          "[%s] Game.%s is not on the FireRed service owner; it reads nil "
          .. "because Game3 has no member of that name",
          who("src.core.Game"), tostring(key))
        return nil
      end
      if type(value) == "function" then
        return function(first, ...)
          if first == proxy then return value(g, ...) end
          return value(first, ...)
        end
      end
      return value
    end,
    __newindex = function(_, key, value)
      local g = live()
      if not g then return end
      if key == "overworld" or key == "save" or key == "data" then
        warnOnce("game.write." .. key,
          "[%s] Game.%s cannot be replaced on FireRed", who("src.core.Game"), key)
        return
      end
      g[key] = value
    end,
  })
  return proxy
end

COVERAGE["src.core.Game"] = {
  kind = "facade", target = "src.core.Game3",
  backed = "overworld data data.pokemon data.moves data.items data.maps "
    .. "data.encounters data.trainers data.text data.map_scripts data.tilesets "
    .. "save save.flags save.vars save.party save.money save.inventory "
    .. "save.player save.player.map save.player.x save.player.y "
    .. "save.player.facing save.player.rival save.pokedex save.options "
    .. "save.modData mods modStatus input touchControls options phase "
    .. "fixedStep generation writeOptions logicSpeed applyOptions saveGame "
    .. "writeSave restartWithMods recoverInput zoomStep returnToTitle update "
    .. "draw keypressed keyreleased gamepadpressed gamepadreleased "
    .. "gamepadaxis joystickpressed joystickreleased joystickaxis joystickhat "
    .. "joystickremoved focus visible onResume touchpressed touchmoved "
    .. "touchreleased mousepressed mousemoved mousereleased wheelmoved "
    .. "worldBgBattleDim worldBgBattleInStack fillScaleInStack "
    .. "wideBattleInStack uiAnchorsHeldInStack drawBaseInStack dynamicUI",
  warned = "stack renderer load bootConfig makeTitleState step restoreSave "
    .. "linkNet linkSession data.sprites data.field data.constants "
    .. "data.text_pointers data.trainer_headers data.palettes data.icons "
    .. "data.battle_anims data.type_chart save.boxes save.box "
    .. "save.objectToggles save.defeatedTrainers save.hiddenTaken",
  absent = "saveReport save.meta",
  notes = {
    identity = "the proxy never compares equal to the Game3 instance in the "
      .. "game.ready payload; mod.game is the raw Game3",
    iteration = "pairs/next/rawget see an EMPTY table on the proxy and on "
      .. "every save / data view below it",
    save = "a LIVE view over the FireRed session (Runtime.getSession), not "
      .. "Game3.save, which is a snapshot rebuilt at each save",
    ["save.flags"] = "keyed by FireRed flag NAME (FLAG_SYS_POKEMON_GET, or "
      .. "the name without FLAG_) or number; a Gen 1 name such as "
      .. "EVENT_GOT_STARTER reads nil because FireRed has no such flag",
    ["save.inventory"] = "item name or FireRed item id -> count; answered "
      .. "through src/core/game3/bag.lua, so a write lands in the right pocket",
    ["save.player.map"] = "the Gen 1 spelling (FR_ prefix stripped); "
      .. "save.player.gen3Map is the raw id",
    ["save.pokedex"] = "seen / caught keyed by species name or FireRed "
      .. "species number",
    ["data.pokemon"] = "a NAME-keyed view assembled from the numeric FireRed "
      .. "tables; spriteFront/spriteBack name the cache .rgba, and a "
      .. "registry override wins",
    ["data.maps"] = "keyed by the FR_ id; a Gen 1 spelling without the "
      .. "prefix also resolves",
    stack = "src/ui/game3/stack.lua, a module-level id stack, warned once",
    applyOptions = "Game3:applyOptions(opts) takes the table directly, the "
      .. "same contract as Gen 1",
  },
}

-- ------- src.world.Map

local MapView = {}

local function collision()
  return package.loaded["src.core.game3.collision"]
end

function MapView.__index(self, key)
  local method = rawget(MapView, key)
  if method ~= nil then return method end
  local raw = rawget(self, "gen3Id")
  local g = live()
  local def = g and g.data and g.data.maps and g.data.maps[raw]
  if key == "def" then return def end
  if key == "tileset" then return def and def.tileset end
  if key == "widthCells" then return def and def.width end
  if key == "heightCells" then return def and def.height end
  if key == "warps" then return def and def.warps end
  if key == "connections" then return def and def.connections end
  return nil
end

local function isActiveMap(self)
  local M = package.loaded["src.core.game3.map"]
  return M and M.current == rawget(self, "gen3Id")
end

function MapView:inBounds(cx, cy)
  local C = collision()
  if not (C and isActiveMap(self)) then return false end
  return C.inBounds(cx, cy) and true or false
end

function MapView:isWalkableCell(cx, cy)
  local C = collision()
  if not (C and isActiveMap(self)) then return false end
  return C.isWalkable(cx, cy) and true or false
end

function MapView:isWaterCell(cx, cy)
  local C = collision()
  if not (C and isActiveMap(self)) then return false end
  return C.isWater(cx, cy) and true or false
end

function MapView:isGrassCell(cx, cy)
  local C = collision()
  if not (C and isActiveMap(self)) then return false end
  return C.isGrass(cx, cy) and true or false
end

function MapView:warpAtCell(cx, cy)
  local C = collision()
  if not (C and isActiveMap(self)) then return nil end
  return C.warpAt(cx, cy)
end

function MapView:cellBehavior(cx, cy)
  local C = collision()
  if not (C and isActiveMap(self)) then return nil end
  return C.behavior(cx, cy)
end

function MapView:isOutdoor()
  local def = self.def
  local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
  return type(pair) == "string" and pair:find("outdoor", 1, true) ~= nil
end
MapView.isOutside = MapView.isOutdoor

function MapView.new()
  warnOnce("map.new",
    "[%s] src.world.Map.new: FireRed maps are loaded by "
    .. "src/core/game3/map.lua Map.load; take the live one from "
    .. "OverworldController.map", who("src.world.Map"))
  return nil
end

local function mapView(rawId)
  if not rawId then return nil end
  return setmetatable({ id = Gen3Compat.gen1MapId(rawId), gen3Id = rawId },
    MapView)
end

Gen3Compat.mapView = mapView

local function buildMap() return MapView end

COVERAGE["src.world.Map"] = {
  kind = "facade", target = "src.core.game3.map",
  backed = "id gen3Id def tileset widthCells heightCells warps connections "
    .. "inBounds isWalkableCell isWaterCell isGrassCell warpAtCell "
    .. "cellBehavior isOutdoor isOutside",
  warned = "new",
  absent = "cellTile isCounterCell blockAt setBlock tileAt isDoorTileCell "
    .. "isWarpTileCell signAtCell connection isPushable defCellTile "
    .. "defIsWalkableCell defIsWaterCell defPassable DELTA isFlyTown "
    .. "ghostBattles warpPadOrHoleAt walkable doorTiles warpTiles waterTiles "
    .. "renderer signAt warpAt",
  notes = {
    id = "the Gen 1 spelling (FR_OAKS_LAB -> OAKS_LAB); gen3Id is the raw id",
    inBounds = "cell queries answer only for the ACTIVE map: FireRed binds one "
      .. "collision grid at a time (src/core/game3/collision.lua)",
    blockAt = "FireRed has 16px metatiles and no 32px blocks",
  },
}

-- ------- src.world.NPC

local function buildNpc()
  local NPC = {}
  NPC.new = unbacked("src.world.NPC", "new",
    "FireRed event objects are plain records built by "
    .. "src/core/game3/objects.lua from the map's object templates; "
    .. "mod.world:npc hands out a handle onto a live one")
  function NPC.facePlayer(npc)
    local Objects = package.loaded["src.core.game3.objects"]
    if not (Objects and type(npc) == "table" and npc.localId) then return nil end
    return Objects.facePlayer(npc.localId, live())
  end
  function NPC.pose(npc)
    if type(npc) ~= "table" then return nil end
    return npc.facing, npc.moving
  end
  return NPC
end

COVERAGE["src.world.NPC"] = {
  kind = "facade", target = "src.core.game3.objects",
  backed = "facePlayer pose",
  warned = "new",
  absent = "update walkPhase draw hopStep MOVE __index",
  notes = {
    instance = "a live FireRed object carries localId cellX cellY px py "
      .. "facing moving progress frozen passable sprite def; it has no "
      .. "metatable, so getmetatable(npc) == NPC is false",
    new = "no constructor: FireRed object templates come from the extracted "
      .. "map events",
  },
}

-- ------- src.world.Collision

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function buildCollision()
  local Collision = { DELTA = DELTA }

  function Collision.target(cx, cy, dir)
    local d = DELTA[dir]
    if not d then return cx, cy end
    return cx + d[1], cy + d[2]
  end

  function Collision.occupied(entities, cx, cy, ignore)
    for _, e in ipairs(entities or {}) do
      if e ~= ignore and not e.passable then
        if (e.cellX == cx and e.cellY == cy)
            or (e.targetX == cx and e.targetY == cy) then
          return e
        end
      end
    end
    return nil
  end

  function Collision.load(_data)
    warnOnce("collision.load",
      "[%s] Collision.load: FireRed has no data.field.tilePairs; passability "
      .. "is the ROM's metatile behaviour (src/core/game3/collision.lua)",
      who("src.world.Collision"))
    return nil
  end

  local function passthrough(allowed) return allowed end

  function Collision.canMove(map, entities, mover, dir)
    local tx, ty = Collision.target(mover.cellX, mover.cellY, dir)
    local C = collision()
    local allowed, why = true, nil
    if not C then
      allowed, why = false, "bounds"
    else
      -- pokefirered/src/event_object_movement.c:4830 GetCollisionAtCoords
      local ok, reason = C.canEnter(live(), tx, ty,
        { fromX = mover.cellX, fromY = mover.cellY, dir = dir,
          surfing = mover.surfing and true or false })
      if not ok then
        allowed = false
        why = (reason == "bounds" or reason == "entity") and reason or "tile"
      elseif Collision.occupied(entities, tx, ty, mover) then
        allowed, why = false, "entity"
      end
    end
    if Runtime.wantsHook("movement.collision") then
      local ctx = { map = map, mover = mover, dir = dir,
                    fromX = mover.cellX, fromY = mover.cellY,
                    toX = tx, toY = ty, reason = why }
      allowed = Runtime.call("movement.collision", passthrough, allowed, ctx)
      why = ctx.reason
    end
    if allowed then return true end
    return false, why
  end

  return Collision
end

COVERAGE["src.world.Collision"] = {
  kind = "facade", target = "src.core.game3.collision",
  backed = "DELTA target occupied canMove",
  warned = "load",
  absent = "",
  notes = {
    canMove = "the verdict src/core/game3/collision.lua Collision.canEnter "
      .. "gives the active map, so `map` is ignored and only the loaded grid "
      .. "answers",
    target = "returns (cx, cy) unchanged for an unknown dir where Gen 1 errors",
  },
}

-- ------- src.world.FieldDefaults

local WORLD_CONSTANTS = {
  stepFrames = 16,
  turnFrames = 4,
  runStepFrames = 8,
  bikeStepFrames = 4,
}

local function buildFieldDefaults()
  local FieldDefaults = { CONSTANTS = { world = WORLD_CONSTANTS } }

  function FieldDefaults.field(_data, key)
    warnOnce("fieldDefaults.field." .. tostring(key),
      "[%s] src.world.FieldDefaults.field(%s): FireRed has no data.field",
      who("src.world.FieldDefaults"), tostring(key))
    return nil
  end

  function FieldDefaults.fieldValue(_data, key, ...)
    local path = tostring(key)
    for i = 1, select("#", ...) do path = path .. "." .. tostring((select(i, ...))) end
    warnOnce("fieldDefaults.fieldValue." .. path,
      "[%s] src.world.FieldDefaults: FireRed has no data.field %s",
      who("src.world.FieldDefaults"), path)
    return nil
  end

  function FieldDefaults.constant(_data, key)
    if key == "world" then return WORLD_CONSTANTS end
    warnOnce("fieldDefaults.constant." .. tostring(key),
      "[%s] FieldDefaults.constant(%s): the Gen 1 default is Kanto Red's rule "
      .. "and FireRed does not carry it", who("src.world.FieldDefaults"),
      tostring(key))
    return nil
  end

  function FieldDefaults.world(_data, key)
    local value = WORLD_CONSTANTS[key]
    if value ~= nil then return value end
    warnOnce("fieldDefaults.world." .. tostring(key),
      "[%s] FieldDefaults.world(%s): FireRed's step events do not read a "
      .. "shared constant table", who("src.world.FieldDefaults"), tostring(key))
    return nil
  end

  FieldDefaults.seed = unbacked("src.world.FieldDefaults", "seed",
    "seeding Kanto Red's FIELD into a FireRed dataset would put Gen 1 map ids "
    .. "into data.field")

  return FieldDefaults
end

COVERAGE["src.world.FieldDefaults"] = {
  kind = "facade",
  backed = "CONSTANTS CONSTANTS.world constant world",
  warned = "field fieldValue seed",
  absent = "FIELD CONSTANTS.encounterBuckets CONSTANTS.hmBadges",
  notes = {
    ["CONSTANTS.world"] = "stepFrames 16, turnFrames 4, runStepFrames 8, "
      .. "bikeStepFrames 4, the frame counts src/core/game3/player.lua uses",
  },
}

-- ------- src.pokemon.Boxes

local function sessionOf(save)
  if save == nil or save == SAVE_VIEW then return session() end
  if type(save) == "table" and save.storage ~= nil then return save end
  return session()
end

local function buildBoxes()
  local Storage = g3("storage")
  local Boxes = {
    COUNT = Storage and Storage.TOTAL_BOXES_COUNT or 14,
    CAPACITY = Storage and Storage.IN_BOX_COUNT or 30,
  }

  function Boxes.ensure(save)
    local s = sessionOf(save)
    if not (s and Storage) then return {} end
    local storage = Storage.ensure(s)
    local out = {}
    for i = 1, Boxes.COUNT do
      out[i] = storage.boxes[i] and storage.boxes[i].mons or {}
    end
    return out
  end

  function Boxes.active(save)
    local s = sessionOf(save)
    if not (s and Storage) then return nil end
    local storage = Storage.ensure(s)
    local box = storage.boxes[storage.currentBox or 1]
    return box and box.mons or nil
  end

  function Boxes.deposit(save, mon)
    local s = sessionOf(save)
    if not (s and Storage and mon) then return nil end
    local ok, boxId = Storage.depositCaught(s, mon)
    if not ok then return nil end
    return boxId
  end

  function Boxes.count(save, index)
    local s = sessionOf(save)
    if not (s and Storage) then return 0 end
    local storage = Storage.ensure(s)
    return Storage.countBoxMons(storage, index or storage.currentBox or 1)
  end

  function Boxes.isFull(save)
    local s = sessionOf(save)
    if not (s and Storage) then return true end
    return Storage.findOpenSlot(Storage.ensure(s)) == nil
  end

  function Boxes.setCurrent(save, index)
    local s = sessionOf(save)
    if not (s and Storage) then return nil end
    local storage = Storage.ensure(s)
    storage.currentBox = math.max(1, math.min(Boxes.COUNT, tonumber(index) or 1))
    return storage.currentBox
  end

  return Boxes
end

COVERAGE["src.pokemon.Boxes"] = {
  kind = "facade", target = "src.core.game3.storage",
  backed = "COUNT CAPACITY ensure active deposit count isFull setCurrent",
  warned = "",
  absent = "withdraw release move name rename box",
  notes = {
    COUNT = "14 boxes on FireRed",
    CAPACITY = "30 slots per box on FireRed",
    ensure = "each box is session.storage.boxes[i].mons, a SPARSE 30-slot "
      .. "table: iterate 1..CAPACITY and skip nil, never trust #box",
    deposit = "Storage.depositCaught: first open slot from the current box, "
      .. "and depositing heals the mon as the Gen 3 PC does",
  },
}

-- ------- src.world.OverworldController

local overworld

local function defaultUpdate() end
local function defaultInteract()
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.interact then return Field.interact(live()) end
  return false
end
local function defaultTalkTo() return false end

local OW = "src.world.OverworldController"

local function objectsList()
  local Objects = package.loaded["src.core.game3.objects"]
  local out = {}
  if not (Objects and Objects._order and Objects._byId) then return out end
  for _, lid in ipairs(Objects._order) do
    local eo = Objects._byId[lid]
    if eo and eo.visible and not eo.hidden then out[#out + 1] = eo end
  end
  return out
end

local function playerModule()
  return package.loaded["src.core.game3.player"]
end

local function localIdOf(entity)
  local P = playerModule()
  local Objects = package.loaded["src.core.game3.objects"]
  if entity == nil then return nil end
  if entity == P then return Objects and Objects.PLAYER_LOCAL_ID or 0xFF end
  if type(entity) == "table" and entity.localId then return entity.localId end
  return nil
end

function Gen3Compat.worldBusy()
  local Field = package.loaded["src.core.game3.field"]
  if not (Field and Field.running) then return true, "no overworld" end
  if Field.locked then return true, "world is busy" end
  local R = package.loaded["src.core.game3.runtime"]
  if R and R.uiBusy then
    local ok, busy = pcall(R.uiBusy)
    if ok and busy then return true, "world is busy" end
  end
  local S = space()
  if S and S.vm and S.vm.isRunning and S.vm:isRunning() then
    return true, "a script is running"
  end
  local B = package.loaded["src.core.game3.battle.init"]
    or package.loaded["src.core.game3.battle"]
  if B and B.isActive and B.isActive() then return true, "a battle is running" end
  local W = package.loaded["src.core.game3.warp"]
  if W and W.isBusy and W.isBusy() then return true, "the world is mid-warp" end
  local P = playerModule()
  if P and P.moving then return true, "world is busy" end
  return false
end

local function buildOverworld()
  local ow = {
    update = defaultUpdate,
    interact = defaultInteract,
    talkTo = defaultTalkTo,
  }

  local function ready(member)
    if inField() then return true end
    warnOnce(OW .. "." .. member .. ".nofield",
      "[%s] %s.%s: no FireRed field is up yet; the honest replacement is the "
      .. "game.ready / map.entered event", who(OW), OW, member)
    return false
  end

  function ow.npcAtCell(cx, cy)
    if not ready("npcAtCell") then return nil end
    local Objects = package.loaded["src.core.game3.objects"]
    return Objects and Objects.at(cx, cy) or nil
  end

  function ow.npcByIndex(index)
    if not ready("npcByIndex") then return nil end
    local Objects = package.loaded["src.core.game3.objects"]
    if type(index) ~= "number" or not Objects then return nil end
    local eo = Objects._byId and Objects._byId[index]
    return eo
  end

  function ow.setMap(mapId, x, y, facing, _opts)
    if not ready("setMap") then return nil end
    local raw = Gen3Compat.gen3MapId(mapId)
    if not raw then return nil, "unknown map: " .. tostring(mapId) end
    local M = g3("map")
    return M and M.load(nil, live(), raw, { x = x, y = y,
      facing = facing or "down", depth1Connections = true }) or nil
  end

  function ow.reloadMap(mapId, _reason)
    if not ready("reloadMap") then return nil end
    local M = g3("map")
    local P = playerModule()
    if not (M and M.current and P) then return nil end
    local raw = mapId and Gen3Compat.gen3MapId(mapId) or M.current
    if raw ~= M.current then return true end
    M.load(nil, live(), raw, { x = P.cellX, y = P.cellY, facing = P.facing,
      depth1Connections = true })
    Runtime.emit("map.reloaded", { mapId = raw, reason = "invalidate" })
    return true
  end

  function ow.startWarpTo(mapId, x, y, facing, onDone, opts)
    if not ready("startWarpTo") then return nil end
    local raw = Gen3Compat.gen3MapId(mapId)
    if not raw then return nil, "unknown map: " .. tostring(mapId) end
    if onDone then
      warnOnce("ow.startWarpTo.onDone",
        "[%s] OverworldState.startWarpTo drops onDone on FireRed "
        .. "(src/core/game3/warp.lua Warp.request has no completion callback)",
        who(OW))
    end
    local W = g3("warp")
    local P = playerModule()
    return W and W.request(nil, live(), raw, x, y,
      facing or (P and P.facing) or "down",
      { teleport = opts and opts.arrive == "teleport" or nil }) or nil
  end

  function ow.canCollisionWarp()
    local W = package.loaded["src.core.game3.warp"]
    return not (W and W.isBusy and W.isBusy())
  end

  function ow.healPoint()
    local s = session()
    if not s then return nil end
    return { map = Gen3Compat.gen1MapId(s.healMap), gen3Map = s.healMap,
             x = s.healX, y = s.healY }
  end

  function ow.warpToHealPoint(onDone)
    if not ready("warpToHealPoint") then return nil end
    local Field = g3("field")
    if not Field then return nil end
    Field.respawnAtHeal()
    if onDone then onDone() end
    return true
  end

  function ow.stepForwardOrCrossEdge(dir)
    if not ready("stepForwardOrCrossEdge") then return nil end
    local P = playerModule()
    return P and P.tryMove(dir, live(), false) or nil
  end

  function ow.checkLedgeHop(dir)
    local C = collision()
    local P = playerModule()
    if not (C and P and inField()) then return false end
    return C.ledgeLanding(live(), P.cellX, P.cellY, dir) ~= nil
  end

  function ow.checkEdgeExit(dir)
    local C = collision()
    local P = playerModule()
    if not (C and P and inField()) then return false end
    return C.tryConnection(live(), P.cellX, P.cellY, dir, false) and true or false
  end
  ow.crossConnection = function(dir) return ow.checkEdgeExit(dir) end

  function ow.scriptMove(entity, dir, tiles, onDone, _opts)
    if not ready("scriptMove") then return nil, "no overworld" end
    local Objects = package.loaded["src.core.game3.objects"]
    if not Objects then return nil, "no overworld" end
    if not DELTA[dir] then return nil, "unknown direction: " .. tostring(dir) end
    local lid = localIdOf(entity)
    if not lid then
      return nil, "no FireRed localId for that entity: only the player and a "
        .. "live map object can be moved"
    end
    local actions = {}
    for _ = 1, math.max(0, tiles or 1) do
      actions[#actions + 1] = { kind = "step", dir = dir }
    end
    Objects.startTrack(lid, actions, onDone)
    return true
  end

  function ow.timeOfDay()
    warnOnce("ow.timeOfDay",
      "[%s] OverworldState.timeOfDay: FireRed has no clock and no time of "
      .. "day", who(OW))
    return nil
  end

  function ow.replaceBlock(bx, by, block)
    if not ready("replaceBlock") then return nil end
    local Field = g3("field")
    if not Field then return nil end
    warnOnce("ow.replaceBlock",
      "[%s] OverworldState.replaceBlock on FireRed sets one 16px METATILE at "
      .. "(x, y) in metatile coordinates; FireRed has no 32px blocks", who(OW))
    Field.setMetatile(bx, by, block)
    local M = package.loaded["src.core.game3.map"]
    Runtime.emit("world.block_replaced",
      { mapId = M and M.current, bx = bx, by = by, block = block })
    return true
  end

  function ow.partyKnows(moveId)
    local s = session()
    local P = g3("pokemon")
    local num = Gen3Compat.moveId(moveId)
    if not (s and P and num) then return false end
    for _, mon in ipairs(s.party or {}) do
      if P.knowsMove(mon, num) then return true end
    end
    return false
  end

  function ow.openPC(onDone)
    if not ready("openPC") then return nil end
    local Hud = ui3("hud")
    if not Hud then return nil end
    if onDone then
      warnOnce("ow.openPC.onDone",
        "[%s] OverworldState.openPC drops onDone on FireRed: the PC closes "
        .. "itself with no callback", who(OW))
    end
    Hud.openPc(live(), session())
    return true
  end

  function ow.nurseHeal(onDone)
    local s = session()
    local Party = g3("party")
    if not (s and Party) then return nil end
    Party.healAll(s.party)
    if onDone then onDone() end
    return true
  end

  function ow.showMapText(key, _npc, onDone)
    if not ready("showMapText") then return nil end
    local S = space()
    local g = live()
    local body = (S and S.bundle and S.bundle.text and S.bundle.text[key])
      or (g and g.data and g.data.gen3Text and g.data.gen3Text[key])
    if body == nil then
      warnOnce("ow.showMapText." .. tostring(key),
        "[%s] OverworldState.showMapText(%s): FireRed text keys are the "
        .. "extracted script labels; a Gen 1 TEXT_* constant resolves to "
        .. "nothing", who(OW), tostring(key))
      return nil
    end
    local Message = ui3("message")
    if not Message then return nil end
    Message.show(body, function()
      Message.close()
      if onDone then onDone() end
    end)
    return true
  end

  local queueApi
  function ow.queueScript(rows, extra)
    local g = live()
    if not g then return nil, "no overworld" end
    if not queueApi or queueApi.game ~= g then
      queueApi = rawRequire("src.world.game3.WorldAPI").new(g, OW)
    end
    return queueApi:queueScript(rows, extra)
  end

  local SEAMS = { update = true, interact = true, talkTo = true }
  for key, fn in pairs(ow) do
    if type(fn) == "function" and not SEAMS[key] then
      ow[key] = function(first, ...)
        if first == overworld then return fn(...) end
        return fn(first, ...)
      end
    end
  end

  local LIVE_FIELD = { map = true, player = true, npcs = true, entities = true }

  setmetatable(ow, {
    __index = function(_, key)
      if not LIVE_FIELD[key] then
        if key == "isOverworld" then return true end
        return nil
      end
      if not inField() then return nil end
      if key == "map" then
        local M = package.loaded["src.core.game3.map"]
        return mapView(M and M.current or (session() and session().map))
      end
      if key == "player" then return playerModule() end
      local list = objectsList()
      if key == "entities" then
        local P = playerModule()
        if P then list[#list + 1] = P end
      end
      return list
    end,
    __newindex = function(t, key, value)
      if LIVE_FIELD[key] then
        warnOnce("ow.write." .. key,
          "[%s] OverworldState.%s is owned by src/core/game3 and cannot be "
          .. "replaced; move the player with warpTo", who(OW), key)
        return
      end
      rawset(t, key, value)
    end,
  })

  overworld = ow
  return ow
end

function Gen3Compat.worldTick(dt)
  if not overworld or overworld.update == defaultUpdate then return end
  overworld.update(overworld, dt)
end

function Gen3Compat.interactWrapper()
  if not overworld or overworld.interact == defaultInteract then return nil end
  return overworld.interact
end

function Gen3Compat.talkToWrapper()
  if not overworld or overworld.talkTo == defaultTalkTo then return nil end
  return overworld.talkTo
end

COVERAGE[OW] = {
  kind = "facade", target = "src.core.game3.field",
  backed = "map player npcs entities isOverworld npcAtCell npcByIndex setMap "
    .. "reloadMap startWarpTo canCollisionWarp healPoint warpToHealPoint "
    .. "stepForwardOrCrossEdge checkLedgeHop checkEdgeExit crossConnection "
    .. "scriptMove partyKnows openPC nurseHeal showMapText queueScript "
    .. "update interact talkTo",
  warned = "timeOfDay replaceBlock startWarpTo openPC",
  absent = "pushableAtCell pooledNPC computeNeighbors rebuildNeighbors "
    .. "takeWarp refreshStandingOnWarp dirHeld handleInput connectionLanding "
    .. "checkBoulderPush checkForcedMovement updateScriptMoves setDark "
    .. "bikeAllowed addRuntimeObject removeRuntimeObject tryHiddenObject "
    .. "hasHiddenItemLeft facingIsShoreOrWater facingIsLandDismount trySurf "
    .. "tryCut goFishing flyTo trainerDefeated engageTrainer "
    .. "checkTrainerSight startTrainerApproach applyFieldPoison neighbors "
    .. "ghosts npcPool camera runner tod dark draw",
  notes = {
    map = "a view with the Gen 1 id (FR_ stripped) plus gen3Id; the cell "
      .. "queries answer against the active collision grid",
    player = "src/core/game3/player.lua itself: cellX cellY px py facing "
      .. "moving surfing biking carry, and writes land on the live avatar",
    npcs = "a fresh array per read of the visible FireRed event objects",
    update = "a replacement runs each field tick via Gen3Compat.worldTick",
    interact = "a replacement owns the A press; the original is Field.interact",
    talkTo = "a replacement returning true consumes a scripted NPC talk",
    startWarpTo = "Warp.request with the FireRed fade; onDone is dropped",
    replaceBlock = "sets one 16px metatile (Field.setMetatile), not a 32px "
      .. "Gen 1 block",
    npcByIndex = "keyed by the FireRed localId the map's object template "
      .. "carries",
    timeOfDay = "FireRed has no clock",
    flyTo = "the FireRed fly map is src/ui/game3/region_map.lua; no seam",
  },
}

-- ------- src.world.PikachuFollower

local function buildFollower()
  local F = {}
  local why = "FireRed has no walking follower"
  F.setShouldSpawn = unbacked("src.world.PikachuFollower", "setShouldSpawn", why)
  F.onMapEntered = unbacked("src.world.PikachuFollower", "onMapEntered", why)
  F.update = unbacked("src.world.PikachuFollower", "update", why)
  F.talk = function() return false end
  F.current = function() return nil end
  F.starterInParty = function() return false end
  F.setVisible = unbacked("src.world.PikachuFollower", "setVisible", why)
  return F
end

COVERAGE["src.world.PikachuFollower"] = {
  kind = "facade",
  backed = "current starterInParty talk",
  warned = "setShouldSpawn onMapEntered update setVisible",
  absent = "shouldSpawn rebase at SPRITE onStep bumpHappiness modifyHappiness "
    .. "picLift hopToCounter updateHop",
  notes = {
    current = "always nil: FireRed has no follower",
    talk = "returns false and never calls done",
  },
}

-- ------- UI facades

local PATCHED_NIL = {}

local function passThroughProxy(target, overrides, absent, moduleName)
  local patched = {}
  return setmetatable({}, {
    __index = function(_, key)
      local mine = patched[key]
      if mine == PATCHED_NIL then return nil end
      if mine ~= nil then return mine end
      local made = overrides[key]
      if made ~= nil then return made end
      local why = absent[key]
      if why then
        warnOnce(moduleName .. "." .. key,
          "[%s] %s.%s has no Gen 3 backing: %s",
          who(moduleName), moduleName, key, why)
        return nil
      end
      return target[key]
    end,
    __newindex = function(_, key, value)
      patched[key] = (value == nil) and PATCHED_NIL or value
      target[key] = value
    end,
  })
end

local UI_ABSENT = "FireRed's screens are module singletons under src/ui/game3 "
  .. "drawn at 240x160; there is no Gen 1 state object to reach into"

local function buildPartyMenu()
  local PM = ui3("party_menu") or {}
  local overrides, absent = {}, {}
  local showOrig, closeOrig = PM.show, PM.close
  for _, name in ipairs({ "drawIcon", "frameFor", "mirrorsIcon", "iconFrames",
                          "sgbPalettes", "animateTo", "entryY" }) do
    absent[name] = UI_ABSENT
  end

  function overrides.new(_game, opts)
    opts = opts or {}
    local s = session()
    if not (s and showOrig) then return nil end
    local handle = {}
    function handle.close() if closeOrig then closeOrig() end end
    handle.party = opts.party or s.party
    showOrig(handle.party, s.move_overlay, {
      session = s,
      mode = "list",
      onSelect = opts.onSwitch and function(slot)
        local mon = slot and handle.party[slot]
        if mon then opts.onSwitch(mon, handle) end
      end or nil,
      onClose = opts.onCancel,
    })
    return handle
  end

  function overrides.close() if closeOrig then return closeOrig() end end

  return passThroughProxy(PM, overrides, absent, "src.ui.PartyMenu")
end

COVERAGE["src.ui.PartyMenu"] = {
  kind = "facade", target = "src.ui.game3.party_menu",
  backed = "new close show isOpen update draw handleInput",
  warned = "",
  absent = "drawIcon frameFor mirrorsIcon iconFrames sgbPalettes animateTo "
    .. "entryY bottomMessage index submenu",
  notes = {
    new = "opens the FireRed party screen over session.party and returns a "
      .. "handle { party, close }, not a state object; onSwitch(mon, handle) "
      .. "and onCancel are honoured, the rest of opts is not",
  },
}

local function buildStartMenu()
  local SM = ui3("start_menu") or {}
  local overrides = {}
  function overrides.new(_game)
    local Hud = ui3("hud")
    if not (Hud and inField()) then return nil end
    if not (SM.isOpen and SM.isOpen()) then Hud.openStartMenu(live(), session()) end
    return SM
  end
  return passThroughProxy(SM, overrides, {}, "src.ui.StartMenu")
end

COVERAGE["src.ui.StartMenu"] = {
  kind = "facade", target = "src.ui.game3.start_menu",
  backed = "new show close isOpen draw ENTRIES",
  warned = "",
  absent = "items ITEMS lastIndex",
  notes = {
    new = "Hud.openStartMenu, which closes any other field menu first; "
      .. "returns the FireRed start menu module",
    ENTRIES = "the assembled list, rebuilt on every show(); the hook below "
      .. "hands it back and a table return replaces it",
    ["hook ui.start_menu.items"] = "raised from src/ui/game3/start_menu.lua, "
      .. "same name and arity as Gen 1 and Gold, but a FireRed row is "
      .. "{ id, label } and carries no onSelect to rewire, and a non-table "
      .. "return is dropped without the Logger.error the other two emit",
  },
}

local function buildOptionsMenu()
  local OM = ui3("option_menu") or {}
  local overrides = {}
  local showOrig = OM.show
  function overrides.new(_game, opts)
    opts = opts or {}
    if not showOrig then return nil end
    showOrig({ session = session(), game = live(), onClose = opts.onCancel })
    return OM
  end
  return passThroughProxy(OM, overrides, { sgbPalettes = UI_ABSENT },
    "src.ui.OptionsMenu")
end

COVERAGE["src.ui.OptionsMenu"] = {
  kind = "facade", target = "src.ui.game3.option_menu",
  backed = "new show close isOpen draw handleInput",
  warned = "",
  absent = "sgbPalettes rows index scroll",
  notes = {
    new = "OptionMenu.show with opts.onCancel as onClose",
  },
}

local function buildBoxMenu()
  local PC = ui3("pc_menu") or {}
  local overrides = {}
  function overrides.new(_game)
    local Hud = ui3("hud")
    if not (Hud and inField()) then return nil end
    Hud.openPc(live(), session())
    return PC
  end
  return passThroughProxy(PC, overrides, {}, "src.ui.BoxMenu")
end

COVERAGE["src.ui.BoxMenu"] = {
  kind = "facade", target = "src.ui.game3.pc_menu",
  backed = "new show close isOpen draw handleInput",
  warned = "",
  absent = "items th tx tw scroll clampScroll",
  notes = {
    new = "Hud.openPc: Bill's / the player's PC top menu, the Gen 1 BoxMenu's "
      .. "counterpart",
  },
}

-- ------- src.battle.BattleState

local function battleModule()
  return package.loaded["src.core.game3.battle.init"]
    or package.loaded["src.core.game3.battle"]
end

local function buildBattleState()
  local B = {}
  local MOVED = "FireRed's battle engine is src/core/game3/battle, over pret's "
    .. "battle_main.c; no Gen 1 BattleState object exists"
  local absent = {}
  for _, name in ipairs({
    "newWild", "newTrainer", "makeSafari", "makeGhost", "makeBattler",
    "resolveTurn", "executeAction", "performMove", "computeDamage",
    "catchAttempt", "runRoll", "enter", "exit", "sgbPalettes", "awardExp",
    "throwBall", "storeCaughtMon", "tryRun",
  }) do
    absent[name] = MOVED
  end

  function B.isActive()
    local M = battleModule()
    return M and M.isActive and M.isActive() or false
  end

  function B.current()
    local M = battleModule()
    return M and M.isActive and M.isActive() and M.getState and M.getState() or nil
  end

  function B.say(_self, text)
    local Ui = package.loaded["src.core.game3.battle.ui"]
    if not (Ui and Ui.push and B.isActive()) then return nil end
    Ui.push(tostring(text or ""))
    return true
  end
  B.sayAuto = B.say

  local LIVE = { player = true, enemy = true, turnCount = true, phase = true,
                 result = true, kind = true, wild = true }

  return setmetatable(B, {
    __index = function(_, key)
      if LIVE[key] then
        local st = B.current()
        if not st then return nil end
        if key == "turnCount" then return st.turn end
        if key == "phase" then
          local M = battleModule()
          return M and M._phase
        end
        return st[key]
      end
      local why = absent[key]
      if why then
        warnOnce("battle." .. key, "[%s] BattleState.%s has no Gen 3 backing: %s",
          who("src.battle.BattleState"), key, why)
      end
      return nil
    end,
  })
end

COVERAGE["src.battle.BattleState"] = {
  kind = "facade", target = "src.core.game3.battle",
  backed = "isActive current say sayAuto player enemy turnCount phase result "
    .. "kind wild",
  warned = "",
  absent = "newWild newTrainer makeSafari makeGhost makeBattler resolveTurn "
    .. "executeAction performMove computeDamage catchAttempt runRoll enter "
    .. "exit sgbPalettes awardExp throwBall storeCaughtMon tryRun update draw",
  notes = {
    player = "the live FireRed battler { mon, side, species, type1, type2, "
      .. "ability, stages, status }; mon carries NUMERIC species and moves",
    newWild = "ABSENT: start a wild battle with mod.world:startWildBattle, or "
      .. "rewrite the species through the encounter.species hook",
    say = "queues onto the FireRed battle textbox (battle/ui.lua Ui.push)",
    events = "battle.* events and hooks fire from src/core/game3/battle for every "
      .. "battler, with battlerId 0-3 in doubles; species, moves and items are "
      .. "NAME strings with the FireRed number alongside (speciesId, moveNum, ballId)",
  },
}

-- ------- src.script.ScriptRunner

local SR = "src.script.ScriptRunner"

local function buildScriptRunner()
  local okGen1, Gen1 = pcall(rawRequire, "src.script.ScriptRunner")
  local adapter = {}
  adapter.scanLabels = okGen1 and Gen1.scanLabels or nil

  function adapter.validate(script, lookup)
    if not (okGen1 and Gen1.validate) then return nil end
    return Gen1.validate(script, lookup or function(verb)
      local g = live()
      local commands = g and g.data and g.data.commands
      return commands ~= nil and commands[verb] ~= nil
    end)
  end

  local Handle = {}
  Handle.__index = function(self, key)
    if key == "game" then return live() end
    local S = space()
    local vm = S and S.vm
    if key == "vm" then return vm end
    if key == "ctx" then return vm and vm.ctx end
    return rawget(Handle, key)
  end

  function Handle:isRunning()
    local S = space()
    return S and S.vm and S.vm:isRunning() or false
  end

  function Handle:run(script, extra)
    if extra ~= nil then
      warnOnce("runner.run.extra",
        "[%s] runner:run's `extra` is unserved on FireRed", who(SR))
    end
    local S = space()
    if not (S and S.vm) then return false end
    if type(script) ~= "string" then
      warnOnce("runner.run.rows",
        "[%s] runner:run on FireRed takes an extracted script KEY (g3:...); a "
        .. "Gen 1 row list runs through mod.world:queueScript", who(SR))
      return false
    end
    if S.vm:isRunning() then return false end
    return S.startScript(script) and true or false
  end

  Handle.resume = unbacked(SR, "runner:resume",
    "the FireRed VM is ticked by src/core/game3/field.lua; a second drive "
    .. "double-steps it")
  Handle.update = unbacked(SR, "runner:update",
    "the FireRed VM is ticked by src/core/game3/field.lua every frame")
  Handle.exec = unbacked(SR, "runner:exec",
    "the script.command hook is the supported patch point")
  Handle.yield = unbacked(SR, "runner:yield",
    "FireRed scripts are pret bytecode, not coroutines")
  Handle.makeContext = unbacked(SR, "runner:makeContext",
    "Gen3Compat.scriptCtx(vm) builds the Gen 1-shaped ctx events carry")

  function adapter.new(_game, _overworld)
    return setmetatable({}, Handle)
  end

  return adapter
end

COVERAGE[SR] = {
  kind = "facade", target = "src.core.game3.scripting.vm",
  backed = "scanLabels validate new isRunning run game vm ctx",
  warned = "resume update exec yield makeContext",
  absent = "co waitingFrames parallel waitingCheck overworld __index",
  notes = {
    run = "takes an extracted FireRed script key and starts it on the one "
      .. "Space VM; returns false while another script runs",
    new = "a thin handle onto src/core/game3/scripting/space.lua's VM, which "
      .. "is replaced on every map change, so the handle resolves it per call",
  },
}

-- ------- src.world.WorldAPI

COVERAGE["src.world.WorldAPI"] = {
  kind = "alias", target = "src.world.game3.WorldAPI",
  backed = "new __index overworld current activeBlockAt canReorderParty "
    .. "reorderParty availableFieldActions useFieldAction canFly flyTo "
    .. "mapOverview warpTo toggleObject setFlag getFlag effectiveEncounters "
    .. "replaceBlock npc queueScript startWildBattle invalidateMap",
  warned = "spawnNpc removeNpc",
  absent = "",
  notes = {
    current = "mapId is the raw FR_ id; warpTo accepts either spelling",
    setFlag = "a FireRed flag NAME (with or without FLAG_) or number",
    replaceBlock = "one 16px metatile, not a 32px block",
    queueScript = "the five Gen 2 verbs (start_battle wild, warp, text, "
      .. "setflag, clearflag); anything else is refused by name up front",
  },
}

-- ------- sprites

local spriteOverrides = { front = {}, back = {} }
local imageCache = {}
local wrappedModules = setmetatable({}, { __mode = "k" })
local reloadRegistered = setmetatable({}, { __mode = "k" })

local function isVanillaPic(path)
  return type(path) ~= "string" or path == "" or path:find("%.rgba$") ~= nil
end

local function readImageData(path)
  if not (love and love.image and love.image.newImageData) then return nil end
  local okA, Assets = pcall(rawRequire, "src.render.Assets")
  if okA and Assets and Assets.imageData then
    local ok, data = pcall(Assets.imageData, path)
    if ok and data then return data end
  end
  local ok, data = pcall(love.image.newImageData, path)
  if ok and data then return data end
  return nil
end

local function centredEntry(path)
  local hit = imageCache[path]
  if hit ~= nil then return hit or nil end
  local data = readImageData(path)
  if not (data and love.graphics and love.graphics.newImage) then
    warnOnce("sprite." .. tostring(path),
      "[gen3] sprite override %s could not be loaded", tostring(path))
    imageCache[path] = false
    return nil
  end
  local w, h = data:getDimensions()
  local out = data
  if w ~= 64 or h ~= 64 then
    out = love.image.newImageData(64, 64)
    local cw, ch = math.min(w, 64), math.min(h, 64)
    local sx = math.floor((w - cw) / 2)
    local sy = math.floor((h - ch) / 2)
    local dx = math.floor((64 - cw) / 2)
    local dy = math.floor((64 - ch) / 2)
    out:paste(data, dx, dy, sx, sy, cw, ch)
  end
  local image = love.graphics.newImage(out)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  hit = { image = image, w = 64, h = 64, path = path }
  imageCache[path] = hit
  return hit
end

Gen3Compat.centredSprite = centredEntry

local function samePath(path) return path end

local function hookedEntry(side, species, form, vanilla)
  if not Runtime.wantsHook("pokemon.sprite") then return vanilla end
  local P = g3("pokemon")
  local path = spriteOverrides[side][species]
    or ("data/generated/gba/pokemon/" .. side .. "/" .. species .. ".rgba")
  local g = live()
  local ctx = { data = g and dataProxy(g.data), species = Gen3Compat.speciesName(species),
                gen3Species = species, form = form, side = side, kind = "battle",
                trueColor = true, path = path }
  local hooked = Runtime.call("pokemon.sprite", samePath, path, ctx)
  if type(hooked) ~= "string" or hooked == path or isVanillaPic(hooked) then
    return vanilla
  end
  return centredEntry(hooked) or vanilla
end

local function wrapPics(P)
  if not P or wrappedModules[P] then return end
  wrappedModules[P] = true
  local frontOrig, backOrig = P.frontPic, P.backPic
  if frontOrig then
    P.frontPic = function(species, form)
      local sp = tonumber(species)
      local path = sp and (tonumber(form) or 0) == 0 and spriteOverrides.front[sp]
      local entry = path and centredEntry(path)
      if not entry then entry = frontOrig(species, form) end
      if sp then return hookedEntry("front", sp, form, entry) end
      return entry
    end
    P.frontSprite = P.frontPic
  end
  if backOrig then
    P.backPic = function(species, form)
      local sp = tonumber(species)
      local path = sp and (tonumber(form) or 0) == 0 and spriteOverrides.back[sp]
      local entry = path and centredEntry(path)
      if not entry then entry = backOrig(species, form) end
      if sp then return hookedEntry("back", sp, form, entry) end
      return entry
    end
  end
end

local function seed(P)
  if not P then return end
  P._front = P._front or {}
  P._back = P._back or {}
  for sp, path in pairs(spriteOverrides.front) do
    local entry = centredEntry(path)
    if entry then P._front[sp] = entry end
  end
  for sp, path in pairs(spriteOverrides.back) do
    local entry = centredEntry(path)
    if entry then P._back[sp] = entry end
  end
end

function Gen3Compat.reseedSprites()
  local P = package.loaded["src.core.game3.pokemon"]
  if P then
    wrapPics(P)
    seed(P)
  end
end

local function collectOverrides(game)
  spriteOverrides = { front = {}, back = {} }
  local content = game and game.mods and game.mods.content
  local reg = content and content.pokemon
  if not (reg and reg.ops) then return end
  for id in pairs(reg.ops) do
    local ok, rec = pcall(reg.get, reg, id)
    if ok and type(rec) == "table" then
      local sp = Gen3Compat.speciesId(id)
      if not sp and type(rec.gen3Species) == "number" then sp = rec.gen3Species end
      if sp then
        if not isVanillaPic(rec.spriteFront) then
          spriteOverrides.front[sp] = rec.spriteFront64 or rec.spriteFront
        end
        if not isVanillaPic(rec.spriteBack) then
          spriteOverrides.back[sp] = rec.spriteBack64 or rec.spriteBack
        end
      end
    end
  end
end

function Gen3Compat.spriteOverrides()
  local out = { front = {}, back = {} }
  for side, map in pairs(spriteOverrides) do
    for sp, path in pairs(map) do out[side][sp] = path end
  end
  return out
end

local function reapply(name, target, what)
  local g = live()
  local content = g and g.mods and g.mods.content
  local reg = content and content[name]
  if not (target and reg and reg.ops and next(reg.ops) ~= nil) then return end
  local spec = reg.spec
  if spec and type(spec.write) == "function" then
    local ok, err = pcall(spec.write, target, reg)
    if not ok then
      warnOnce(name .. ".reapply", "[gen3] mod %s data not re-applied after reload: %s",
        what, tostring(err))
    end
  end
  for key in pairs(recordCache) do recordCache[key] = nil end
end

local function reapplyMoves(M)
  reapply("moves", M, "move")
end

-- Pokemon.install() replaces every species table with a fresh copy of the
-- ROM pack, and Runtime runs it on entering FireRed -- after the loader has
-- merged the mods onto the old tables.  Write the moves and pokemon
-- registries again onto the new ones: move names live in that same pack
-- (Pokemon._moveNames), and so does the battle-move copy the moves writer
-- mirrors its rows into.  Moves first, as Loader:_mergeOrder does: the moves
-- writer is what puts a mod's own moves in the move index, and the species
-- writer reads that index to resolve learnsets, egg moves and TM/HM lists.
local function reapplyPokemon(P)
  local g = live()
  local M = g and g.data and g.data.gen3Moves
  if not M then
    local okM, Moves = pcall(rawRequire, "src.core.game3.battle.moves")
    M = okM and type(Moves) == "table" and Moves or nil
  end
  reapplyMoves(M)
  reapply("pokemon", P, "species")
end

function Gen3Compat.applyMerged(game)
  if game then lastGame = game end
  imageCache = {}
  for key in pairs(recordCache) do recordCache[key] = nil end
  local okM, Moves = pcall(rawRequire, "src.core.game3.battle.moves")
  if okM and type(Moves) == "table" and type(Moves.onReload) == "function"
      and not reloadRegistered[Moves] then
    reloadRegistered[Moves] = true
    Moves.onReload(reapplyMoves, "gen3compat")
  end
  collectOverrides(game or live())
  local okP, P = pcall(rawRequire, "src.core.game3.pokemon")
  if not (okP and P) then return end
  wrapPics(P)
  seed(P)
  if type(P.onReload) == "function" and not reloadRegistered[P] then
    reloadRegistered[P] = true
    P.onReload(function()
      for key in pairs(recordCache) do recordCache[key] = nil end
      reapplyPokemon(P)
      wrapPics(P)
      seed(P)
    end, "gen3compat")
  end
end

-- ------- script ctx

function Gen3Compat.scriptCtx(vm)
  local S = space()
  return {
    game = live(),
    save = SAVE_VIEW,
    overworld = inField() and Gen3Compat.resolve(OW) or nil,
    runner = vm or (S and S.vm),
    vm = vm or (S and S.vm),
    generation = 3,
  }
end

-- ------- the table

local ADAPTERS = {
  ["src.core.Game"] = buildGame,
  ["src.world.NPC"] = buildNpc,
  ["src.world.Collision"] = buildCollision,
  ["src.world.FieldDefaults"] = buildFieldDefaults,
  ["src.pokemon.Boxes"] = buildBoxes,
  ["src.world.OverworldController"] = buildOverworld,
  ["src.ui.PartyMenu"] = buildPartyMenu,
  ["src.ui.StartMenu"] = buildStartMenu,
  ["src.ui.OptionsMenu"] = buildOptionsMenu,
  ["src.battle.BattleState"] = buildBattleState,
  ["src.script.ScriptRunner"] = buildScriptRunner,
  ["src.world.PikachuFollower"] = buildFollower,
  ["src.world.Map"] = buildMap,
  ["src.world.WorldAPI"] = "src.world.game3.WorldAPI",
  ["src.ui.BoxMenu"] = buildBoxMenu,
}

Gen3Compat.ADAPTERS = ADAPTERS

function Gen3Compat.endSession()
  resolveGame, lastGame = nil, nil
  built, claimants, warned = {}, {}, {}
end

function Gen3Compat.bind(fn)
  resolveGame = fn
end

function Gen3Compat.serves(name)
  return ADAPTERS[name] ~= nil
end

function Gen3Compat.modules()
  local out = {}
  for name in pairs(ADAPTERS) do out[#out + 1] = name end
  table.sort(out)
  return out
end

function Gen3Compat.coverage(name)
  local row = COVERAGE[name]
  if not row then return nil end
  local members = {}
  for _, status in ipairs({ "backed", "absent", "warned" }) do
    for _, member in ipairs(words(row[status])) do
      members[member] = status
    end
  end
  local notes = {}
  for key, value in pairs(row.notes or {}) do notes[key] = value end
  return { module = name, kind = row.kind, target = row.target,
           members = members, notes = notes }
end

function Gen3Compat.memberStatus(name, member)
  local row = Gen3Compat.coverage(name)
  return row and row.members[member] or nil
end

function Gen3Compat.resolve(name, modId)
  local spec = ADAPTERS[name]
  if not spec then return nil end
  local module = built[name]
  if not module then
    module = type(spec) == "string" and rawRequire(spec) or spec()
    built[name] = module
  end
  if modId then
    local ids = claimants[name]
    if not ids then ids = {} claimants[name] = ids end
    local seen = false
    for _, id in ipairs(ids) do if id == modId then seen = true break end end
    if not seen then ids[#ids + 1] = modId end
  end
  return module
end

return Gen3Compat
