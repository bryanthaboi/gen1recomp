-- Post-battle evolution (pret TryEvolvePokemon / EVO_MODE_NORMAL).
-- MVP: ROM EVO_LEVEL (method 4) only. Stones/trade/friendship later.

local Pokemon = require("src.core.game3.pokemon")
local ModRuntime = require("src.mods.Runtime")

local Evolution = {}

-- pret constants/pokemon.h
Evolution.EVO_FRIENDSHIP = 1
Evolution.EVO_FRIENDSHIP_DAY = 2
Evolution.EVO_FRIENDSHIP_NIGHT = 3
Evolution.EVO_LEVEL = 4
Evolution.EVO_TRADE = 5
Evolution.EVO_TRADE_ITEM = 6
Evolution.EVO_ITEM = 7

local EVERSTONE = 197 -- FRLG ITEM_EVERSTONE

local function held_is_everstone(mon)
  local item = mon and (mon.item or mon.heldItem)
  if item == nil then return false end
  if tonumber(item) == EVERSTONE then return true end
  if type(item) == "string" and item:upper():find("EVERSTONE", 1, true) then
    return true
  end
  return false
end

local function is_national_unlocked(session)
  local PokedexData = require("src.core.game3.pokedex_data")
  return PokedexData.isNationalUnlocked(session)
end

local function level_row(mon, evo, session)
  local level = tonumber(mon.level) or 1
  local method = tonumber(evo.method or evo[1]) or 0
  local param = tonumber(evo.param or evo[2]) or 0
  local target = tonumber(evo.target or evo[3]) or 0
  if method == Evolution.EVO_LEVEL and target > 0 and level >= param then
    -- National Dex gating: prevent evolving into non-Kanto species (target > 151) if locked
    if target > 151 and not is_national_unlocked(session) then
      return "stop"
    end
    return "match", target, param
  elseif (method == Evolution.EVO_FRIENDSHIP or method == Evolution.EVO_FRIENDSHIP_DAY or method == Evolution.EVO_FRIENDSHIP_NIGHT) and target > 0 then
    local friendship = tonumber(mon.friendship) or 220
    if friendship >= 220 then
      if target > 151 and not is_national_unlocked(session) then
        return "stop"
      end
      return "match", target, 0
    end
  end
  return nil
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

--- Target species for level-up evolution, or nil.
-- pokefirered/src/pokemon.c:5025
function Evolution.levelTarget(mon, session)
  if not mon then return nil end
  if held_is_everstone(mon) then return nil end
  local species = Pokemon.speciesOf(mon) or tonumber(mon.species or mon.speciesId)
  if not species then return nil end
  local hooked = ModRuntime.wantsHook("evolution.check")
  local R = hooked and package.loaded["src.core.game3.runtime"] or nil
  for _, evo in ipairs(Pokemon.evolutions(species)) do
    local kind, target, param = level_row(mon, evo, session)
    if hooked then
      local view = evo_view(evo)
      local ok = ModRuntime.call("evolution.check", function()
        return kind == "match"
      end, R and R._game or nil, mon, view, { kind = "levelup", session = session })
      if ok then
        if kind == "match" then return target, param end
        if view.speciesId > 0 then return view.speciesId, view.param end
      end
      if kind == "stop" then return nil end
    else
      if kind == "stop" then return nil end
      if kind == "match" then return target, param end
    end
  end
  return nil
end

--- Target species for item/stone evolution, or nil (stones bypass Everstone).
function Evolution.itemTarget(mon, itemId, session)
  if not mon then return nil end
  local species = Pokemon.speciesOf(mon) or tonumber(mon.species or mon.speciesId)
  local ItemsData = require("src.core.game3.items_data")
  local num = ItemsData.toNumericId(itemId) or tonumber(itemId)
  if not species or not num then return nil end
  for _, evo in ipairs(Pokemon.evolutions(species)) do
    local method = tonumber(evo.method or evo[1]) or 0
    local param = tonumber(evo.param or evo[2]) or 0
    local target = tonumber(evo.target or evo[3]) or 0
    if (method == Evolution.EVO_ITEM or method == Evolution.EVO_TRADE_ITEM) and param == num and target > 0 then
      -- National Dex gating: prevent evolving into non-Kanto species (target > 151) if locked
      if target > 151 and not is_national_unlocked(session) then
        return nil
      end
      return target
    end
  end
  return nil
end

--- Rename mon on evolution matching retail FRLG EvolutionRenameMon rules.
function Evolution.renameMon(mon, preSpecies, postSpecies)
  if not mon then return end
  local preName = Pokemon.name(preSpecies) or ""
  local newName = Pokemon.name(postSpecies) or "POKéMON"
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

  -- 5. Shedinja Creation (Nincada -> Ninjask)
  local isNincada = (preSpecies == 290 or preSpecies == 301)
  local isNinjask = (newSpecies == 291 or newSpecies == 302)
  local shedId = (newSpecies == 302) and 303 or 292
  if isNincada and isNinjask and session then
    local party = session.party or (session.save and session.save.party)
    if party and #party < 6 then
      local hasPokeBall = false
      local BagMod = package.loaded["src.core.game3.bag"] or require("src.core.game3.bag")
      local b = bag or session.bag
      if b then
        if BagMod.has and BagMod.has(b, 4, 1) then
          hasPokeBall = true
          BagMod.remove(b, 4, 1)
        elseif type(b.has) == "function" and b:has(4, 1) then
          hasPokeBall = true
          if type(b.remove) == "function" then b:remove(4, 1) end
        end
      end
      if hasPokeBall then
        -- Deep clone Nincada before Ninjask learns new moves
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
        shedinja.name = Pokemon.name(shedId) or "SHEDINJA"
        shedinja.nickname = Pokemon.name(shedId) or "SHEDINJA"
        shedinja.heldItem = 0
        shedinja.item = 0
        shedinja.status = 0
        shedinja.pokeball = 4
        shedinja.ability = 25 -- ABILITY_WONDER_GUARD
        shedinja.maxHp = 1
        shedinja.hp = 1
        party[#party + 1] = shedinja
        if session.dex then
          local Dex = require("src.core.game3.dex")
          Dex.setSeen(session.dex, shedId)
          Dex.setCaught(session.dex, shedId)
        end
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
