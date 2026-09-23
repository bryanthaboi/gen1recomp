-- Post-battle evolution (pret TryEvolvePokemon / EVO_MODE_NORMAL).

local Pokemon = require("src.core.game3.pokemon")
local ModRuntime = require("src.mods.Runtime")

local Evolution = {}

-- pokefirered/include/constants/pokemon.h:266
Evolution.EVO_FRIENDSHIP = 1
Evolution.EVO_FRIENDSHIP_DAY = 2
Evolution.EVO_FRIENDSHIP_NIGHT = 3
Evolution.EVO_LEVEL = 4
Evolution.EVO_TRADE = 5
Evolution.EVO_TRADE_ITEM = 6
Evolution.EVO_ITEM = 7
Evolution.EVO_LEVEL_ATK_GT_DEF = 8
Evolution.EVO_LEVEL_ATK_EQ_DEF = 9
Evolution.EVO_LEVEL_ATK_LT_DEF = 10
Evolution.EVO_LEVEL_SILCOON = 11
Evolution.EVO_LEVEL_CASCOON = 12
Evolution.EVO_LEVEL_NINJASK = 13
Evolution.EVO_LEVEL_SHEDINJA = 14
Evolution.EVO_BEAUTY = 15

-- pokefirered/include/constants/pokemon.h:284
Evolution.EVO_MODE_NORMAL = 0
Evolution.EVO_MODE_TRADE = 1
Evolution.EVO_MODE_ITEM_USE = 2
Evolution.EVO_MODE_ITEM_CHECK = 3

Evolution.KANTO_SPECIES_END = 151 -- pokefirered/include/constants/species.h:157

local HOLD_EFFECT_PREVENT_EVOLVE = 38 -- pokefirered/include/constants/hold_effects.h:42
local ITEM_EVERSTONE = 195 -- pokefirered/include/constants/items.h:206

local function row_method(evo) return tonumber(evo.method or evo[1]) or 0 end
local function row_param(evo) return tonumber(evo.param or evo[2]) or 0 end
local function row_target(evo) return tonumber(evo.target or evo[3]) or 0 end

local function numeric_item(raw)
  if raw == nil then return 0 end
  local num = tonumber(raw)
  if num then return num end
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  if ok and ItemsData and ItemsData.toNumericId then
    local ok2, n = pcall(ItemsData.toNumericId, raw)
    if ok2 and tonumber(n) then return tonumber(n) end
  end
  return 0
end

local function held_item_id(mon)
  return numeric_item(mon and (mon.item or mon.heldItem))
end

-- pokefirered/src/pokemon.c:5038
local function hold_effect_of(item)
  if item == 0 then return 0 end
  local ok, ItemsData = pcall(require, "src.core.game3.items_data")
  if ok and ItemsData and ItemsData.info then
    local ok2, info = pcall(ItemsData.info, item)
    if ok2 and info and tonumber(info.holdEffect) then return tonumber(info.holdEffect) end
  end
  if item == ITEM_EVERSTONE then return HOLD_EFFECT_PREVENT_EVOLVE end
  return 0
end

local function is_national_unlocked(session)
  local PokedexData = require("src.core.game3.pokedex_data")
  return PokedexData.isNationalUnlocked(session)
end

--- pokefirered/src/party_menu.c:5320
function Evolution.nationalAllows(target, session)
  target = tonumber(target) or 0
  if target <= Evolution.KANTO_SPECIES_END then return true end
  return is_national_unlocked(session) and true or false
end

local function normal_context(mon)
  return {
    level = tonumber(mon.level) or 1,
    friendship = Pokemon.friendshipOf(mon),
    beauty = tonumber(mon.beauty) or 0,
    upper = math.floor((tonumber(mon.personality) or 0) / 65536) % 65536,
    atk = tonumber(mon.attack or mon.atk) or 0,
    def = tonumber(mon.defense or mon.def) or 0,
  }
end

-- pokefirered/src/pokemon.c:5053
local function row_matches_normal(evo, c)
  local m, param = row_method(evo), row_param(evo)
  if m == Evolution.EVO_FRIENDSHIP then
    return c.friendship >= 220
  elseif m == Evolution.EVO_LEVEL then
    return param <= c.level
  elseif m == Evolution.EVO_LEVEL_ATK_GT_DEF then
    return param <= c.level and c.atk > c.def
  elseif m == Evolution.EVO_LEVEL_ATK_EQ_DEF then
    return param <= c.level and c.atk == c.def
  elseif m == Evolution.EVO_LEVEL_ATK_LT_DEF then
    return param <= c.level and c.atk < c.def
  elseif m == Evolution.EVO_LEVEL_SILCOON then
    return param <= c.level and (c.upper % 10) <= 4
  elseif m == Evolution.EVO_LEVEL_CASCOON then
    return param <= c.level and (c.upper % 10) > 4
  elseif m == Evolution.EVO_LEVEL_NINJASK then
    return param <= c.level
  elseif m == Evolution.EVO_BEAUTY then
    return param <= c.beauty
  end
  -- pokefirered/src/pokemon.c:5061, :5107
  return false
end

local function evo_view(evo)
  local G3 = require("src.mods.Gen3Compat")
  local okS, Schemas = pcall(require, "src.mods.Schemas")
  local methods = okS and Schemas.gen3View and Schemas.gen3View.EVOLUTIONS or {}
  local method = tonumber(evo.method or evo[1]) or 0
  local param = tonumber(evo.param or evo[2]) or 0
  local target = tonumber(evo.target or evo[3]) or 0
  return {
    method = methods[method] or method, methodId = method, param = param,
    level = param, species = G3.speciesName(target), speciesId = target,
  }
end

local function scan_normal(mon, species, hook)
  local c = normal_context(mon)
  local target, param = 0, 0
  for _, evo in ipairs(Pokemon.evolutions(species)) do
    local matched = row_matches_normal(evo, c)
    if hook then
      local view = evo_view(evo)
      local ok = ModRuntime.call("evolution.check", function()
        return matched
      end, hook.game, mon, view, { kind = "levelup", session = hook.session })
      if ok then
        if matched then
          target, param = row_target(evo), row_param(evo)
        elseif view.speciesId > 0 then
          target, param = view.speciesId, view.param
        end
      end
    elseif matched then
      target, param = row_target(evo), row_param(evo)
    end
  end
  return target, param
end

-- pokefirered/src/pokemon.c:5114
local function scan_trade(mon, species)
  local heldItem = held_item_id(mon)
  local target, param = 0, 0
  for _, evo in ipairs(Pokemon.evolutions(species)) do
    local m = row_method(evo)
    if m == Evolution.EVO_TRADE then
      target, param = row_target(evo), row_param(evo)
    elseif m == Evolution.EVO_TRADE_ITEM and row_param(evo) == heldItem then
      target, param = row_target(evo), row_param(evo)
    end
  end
  return target, param
end

-- pokefirered/src/pokemon.c:5139
local function scan_item(mon, species, evolutionItem)
  local num = numeric_item(evolutionItem)
  if num == 0 then return 0, 0 end
  for _, evo in ipairs(Pokemon.evolutions(species)) do
    if row_method(evo) == Evolution.EVO_ITEM and row_param(evo) == num then
      return row_target(evo), row_param(evo)
    end
  end
  return 0, 0
end

-- pokefirered/src/pokemon.c:5025 GetEvolutionTargetSpecies
function Evolution.targetSpecies(mon, mode, evolutionItem, hook)
  if not mon then return 0, 0 end
  local species = Pokemon.speciesOf(mon) or tonumber(mon.species or mon.speciesId)
  if not species then return 0, 0 end
  mode = tonumber(mode) or Evolution.EVO_MODE_NORMAL
  if hold_effect_of(held_item_id(mon)) == HOLD_EFFECT_PREVENT_EVOLVE
    and mode ~= Evolution.EVO_MODE_ITEM_CHECK then
    return 0, 0
  end
  if mode == Evolution.EVO_MODE_NORMAL then
    return scan_normal(mon, species, hook)
  elseif mode == Evolution.EVO_MODE_TRADE then
    return scan_trade(mon, species)
  end
  return scan_item(mon, species, evolutionItem)
end

-- pokefirered/src/pokemon.c:5049, src/evolution_scene.c:641
function Evolution.levelTarget(mon, session)
  if not mon then return nil end
  local hook = nil
  if ModRuntime.wantsHook("evolution.check") then
    local R = package.loaded["src.core.game3.runtime"]
    hook = { game = R and R._game or nil, session = session }
  end
  local target, param = Evolution.targetSpecies(mon, Evolution.EVO_MODE_NORMAL, nil, hook)
  if target == 0 then return nil end
  if not Evolution.nationalAllows(target, session) then return nil end
  return target, param
end

-- pokefirered/src/pokemon.c:5139, src/party_menu.c:5318 MonCanEvolve
function Evolution.itemTarget(mon, itemId, session)
  if not mon then return nil end
  local target = Evolution.targetSpecies(mon, Evolution.EVO_MODE_ITEM_USE, itemId)
  if target == 0 then return nil end
  if not Evolution.nationalAllows(target, session) then return nil end
  return target
end

-- pokefirered/src/party_menu.c:872
function Evolution.itemCheck(mon, itemId)
  if not mon then return nil end
  local target = Evolution.targetSpecies(mon, Evolution.EVO_MODE_ITEM_CHECK, itemId)
  if target == 0 then return nil end
  return target
end

-- pokefirered/src/pokemon.c:5114
function Evolution.tradeTarget(mon, session)
  if not mon then return nil end
  local target = Evolution.targetSpecies(mon, Evolution.EVO_MODE_TRADE)
  if target == 0 then return nil end
  if Evolution.nationalAllows(target, session) then
    local species = Pokemon.speciesOf(mon) or tonumber(mon.species or mon.speciesId)
    local heldItem = held_item_id(mon)
    for _, evo in ipairs(Pokemon.evolutions(species or 0)) do
      if row_method(evo) == Evolution.EVO_TRADE_ITEM and row_param(evo) == heldItem
        and row_target(evo) == target then
        mon.item = 0
        mon.heldItem = 0
      end
    end
    return target
  end
  return nil
end

--- Rename mon on evolution matching retail FRLG EvolutionRenameMon rules.
function Evolution.renameMon(mon, preSpecies, postSpecies)
  if not mon then return end
  local preName = Pokemon.name(preSpecies) or ""
  local newName = Pokemon.name(postSpecies)
  local function trim(s)
    if type(s) ~= "string" then return "" end
    return (s:gsub("%z+", ""):match("^%s*(.-)%s*$")) or ""
  end
  local nick = trim(mon.nickname)
  local pName = trim(preName)
  if nick == "" or nick:upper() == pName:upper() then
    mon.nickname = newName
    mon.name = newName
  else
    mon.name = nick
  end
end

--- Apply species change + stats. Point of no return.
function Evolution.apply(mon, newSpecies, session, bag, via)
  newSpecies = tonumber(newSpecies)
  if not mon or not newSpecies then return false end
  local preSpecies = Pokemon.speciesOf(mon) or tonumber(mon.species or mon.speciesId) or 1
  local oldMax = tonumber(mon.maxHp) or 1
  local oldHp = tonumber(mon.hp) or oldMax

  -- 1. Mutate species
  mon.species = newSpecies
  mon.speciesId = newSpecies
  Pokemon.tagNumbering(mon, Pokemon.NUMBERING_INTERNAL)

  -- 2. Nickname update
  Evolution.renameMon(mon, preSpecies, newSpecies)

  -- 3. Recalculate stats & handle HP delta
  Pokemon.applyStats(mon)
  local newMax = tonumber(mon.maxHp) or oldMax
  if oldHp > 0 then
    mon.hp = math.min(newMax, oldHp + math.max(0, newMax - oldMax))
  else
    mon.hp = 0 -- preserve fainted status
  end

  -- 4. Pokedex registration
  if session and session.dex then
    local Dex = require("src.core.game3.dex")
    Dex.setSeen(session.dex, newSpecies)
    Dex.setCaught(session.dex, newSpecies)
  end

  -- 5. pokefirered/src/evolution_scene.c:550 CreateShedinja
  local preRows = Pokemon.evolutions(preSpecies)
  local shedId = (preRows[1] and row_method(preRows[1]) == Evolution.EVO_LEVEL_NINJASK
    and preRows[2] and row_target(preRows[2])) or 0
  if shedId > 0 and session then
    session.party = session.party or (session.save and session.save.party) or {}
    local party = session.party
    if #party < 6 then
      local shedinja = {}
      for k, v in pairs(mon) do
        if type(v) == "table" then
          local t = {}
          for k2, v2 in pairs(v) do t[k2] = v2 end
          shedinja[k] = t
        else
          shedinja[k] = v
        end
      end
      shedinja.species = shedId
      shedinja.speciesId = shedId
      Pokemon.tagNumbering(shedinja, Pokemon.NUMBERING_INTERNAL)
      shedinja.name = Pokemon.name(shedId)
      shedinja.nickname = Pokemon.name(shedId)
      shedinja.heldItem = 0
      shedinja.item = 0
      shedinja.status = 0
      shedinja.markings = nil
      shedinja.mail = nil
      if Pokemon.abilityId then
        shedinja.ability = Pokemon.abilityId(shedId, shedinja.personality)
        shedinja.abilityId = shedinja.ability
      end
      shedinja.hp = nil
      Pokemon.applyStats(shedinja)
      shedinja.hp = 1
      party[#party + 1] = shedinja
      if session.dex then
        local Dex = require("src.core.game3.dex")
        Dex.setSeen(session.dex, shedId)
        Dex.setCaught(session.dex, shedId)
      end
    end
  end

  if ModRuntime.wants("pokemon.evolved") then
    ModRuntime.emit("pokemon.evolved", {
      mon = mon,
      fromSpecies = Pokemon.keyName(preSpecies) or preSpecies,
      toSpecies = Pokemon.keyName(newSpecies) or newSpecies,
      fromSpeciesId = preSpecies,
      toSpeciesId = newSpecies,
      via = via or "level",
    })
  end

  return true
end

--- Scan party (or indices) for pending level evolutions.
-- leveledSet: optional {[partyIndex]=true} from battle.
-- Returns { {mon, partyIndex, fromSpecies, toSpecies}, ... }
function Evolution.pending(party, leveledSet, session)
  local out = {}
  if type(party) ~= "table" then return out end
  for i, mon in ipairs(party) do
    if mon and (not leveledSet or leveledSet[i]) then
      local target = Evolution.levelTarget(mon, session)
      if target then
        out[#out + 1] = {
          mon = mon,
          partyIndex = i,
          fromSpecies = tonumber(mon.species or mon.speciesId),
          toSpecies = target,
        }
      end
    end
  end
  return out
end

return Evolution
