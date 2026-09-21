
local Strings = require("src.core.Strings")
local Std = require("src.core.game3.scripting.stdscripts")

local Queries = {}

local PARTY_SIZE = 6 -- pokefirered/include/constants/global.h:78
local SPECIES_EGG = 412 -- pokefirered/include/constants/species.h:421
local SPECIES_DODRIO = 85 -- pokefirered/include/constants/species.h:89
local ITEM_ENIGMA_BERRY = 175 -- pokefirered/include/constants/items.h:179
local FIRST_BERRY_INDEX = 133 -- pokefirered/include/constants/items.h:181
local LAST_BERRY_INDEX = 175 -- pokefirered/include/constants/items.h:182
local ITEM_BERRY_POUCH = 365 -- pokefirered/include/constants/items.h:437
local KANTO_DEX_COUNT = 151 -- pokefirered/include/constants/pokedex.h:424
local JOHTO_DEX_COUNT = 251 -- pokefirered/include/constants/pokedex.h:425
local NATIONAL_DEX_COUNT = 386 -- pokefirered/include/constants/pokedex.h:426
local FLAG_SHOWN_BOX_WAS_FULL_MESSAGE = 0x843 -- pokefirered/include/constants/flags.h:1401
local VAR_STARTER_MON = 0x4031 -- pokefirered/include/constants/vars.h:98

-- pokefirered/src/field_specials.c:1519
local STARTER_SPECIES = { [0] = 1, 7, 4 }

-- pokefirered/src/field_specials.c:362
local SLOT_MACHINE_IDS = {
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
  1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 5,
}

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function sessionOf()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function scriptStore()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local session = sessionOf()
  return (Space and Space.store) or (session and session.store) or nil
end

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(), ctx, id)) or 0
end

local function varSet(ctx, id, value)
  flagsMod().setVar(scriptStore(), ctx, id, tonumber(value) or 0)
end

-- pokefirered/src/scrcmd.c:99
local function setResult(ctx, value)
  varSet(ctx, 0x800D, value)
end

local function boolResult(ctx, cond)
  local v = cond and 1 or 0
  setResult(ctx, v)
  return false, v
end

-- pokefirered/src/scrcmd.c:109
local function boolReturn(cond)
  return false, cond and 1 or 0
end

local function partyOf()
  local session = sessionOf()
  return (session and session.party) or {}
end

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId)) or 0
end

local function isEgg(mon)
  if not mon then return false end
  if mon.isEgg or mon.egg then return true end
  return speciesOf(mon) == SPECIES_EGG
end

-- pokefirered/src/pokemon.c:3742
local function playerPartyCount()
  local party = partyOf()
  local n = 0
  while n < PARTY_SIZE and speciesOf(party[n + 1]) ~= 0 do
    n = n + 1
  end
  return n
end

-- pokefirered/src/pokemon.c:3245
local function speciesOrEgg(mon)
  if isEgg(mon) then return SPECIES_EGG end
  return speciesOf(mon)
end

local function dexOf()
  local session = sessionOf()
  return session and session.dex
end

local function nameOfPlayer()
  local session = sessionOf()
  return tostring((session and (session.name or session.playerName)) or "")
end

local function setStringVar(ctx, adapters, index, text)
  if adapters and adapters.setStringVar then adapters.setStringVar(index, text) end
  if ctx and ctx.stringVars then ctx.stringVars[index] = text end
end

-- pokefirered/src/pokemon.c:5174
local function speciesFromNational(nat)
  local Pokemon = require("src.core.game3.pokemon")
  local ok, sp = pcall(Pokemon.speciesFromNational, nat)
  return (ok and tonumber(sp)) or nat
end

-- pokefirered/src/field_specials.c:1671
local function nicknameOf(mon)
  if not mon then return "" end
  if mon.nickname and mon.nickname ~= "" then return tostring(mon.nickname) end
  local Pokemon = require("src.core.game3.pokemon")
  pcall(function()
    if not Pokemon._names then Pokemon.install(nil) end
  end)
  return (Pokemon.name and Pokemon.name(speciesOf(mon))) or ""
end

local function itemName(itemId)
  local ok, Items = pcall(require, "src.core.game3.items")
  if ok and Items and Items.displayName then
    return tostring(Items.displayName(itemId) or "")
  end
  return ""
end

local function heldItemOf(mon)
  return tonumber(mon and (mon.heldItem or mon.item or mon.holdItem)) or 0
end

local function bagOf()
  local session = sessionOf()
  return session and session.bag
end

local function bagHas(itemId, qty)
  local bag = bagOf()
  if not bag then return false end
  local ok, Bag = pcall(require, "src.core.game3.bag")
  if not (ok and Bag and Bag.has) then return false end
  return Bag.has(bag, itemId, qty or 1) and true or false
end

Queries.HANDLERS = {
  -- pokefirered/src/prof_pc.c:23
  [Std.SPECIAL.GetPokedexCount] = function(ctx)
    local Dex = require("src.core.game3.dex")
    local PokedexData = require("src.core.game3.pokedex_data")
    local dex = dexOf()
    local mode = (varGet(ctx, 0x8004) == 0) and "kanto" or "national"
    varSet(ctx, 0x8005, Dex.countSeen(dex, mode))
    varSet(ctx, 0x8006, Dex.countCaught(dex, mode))
    local enabled = PokedexData.isNationalUnlocked(sessionOf(), dex) and 1 or 0
    return false, enabled
  end,
  -- pokefirered/src/field_specials.c:1537
  [Std.SPECIAL.SetSeenMon] = function(ctx)
    local Dex = require("src.core.game3.dex")
    local dex = dexOf()
    local species = varGet(ctx, 0x8004)
    if dex and species > 0 then Dex.setSeen(dex, species) end
    return false
  end,
  -- pokefirered/src/field_specials.c:158
  [Std.SPECIAL.SetHiddenItemFlag] = function(ctx)
    local store = scriptStore()
    if store then flagsMod().setFlag(store, ctx, varGet(ctx, 0x8004), true) end
    return false
  end,
  -- pokefirered/src/pokemon.c:3742
  [Std.SPECIAL.CalculatePlayerPartyCount] = function(ctx)
    local n = playerPartyCount()
    return false, n
  end,
  -- pokefirered/src/pokemon_storage_system_menu.c:141
  [Std.SPECIAL.CountPartyNonEggMons] = function(ctx)
    local party = partyOf()
    local count = 0
    for i = 1, PARTY_SIZE do
      local mon = party[i]
      if speciesOf(mon) ~= 0 and not isEgg(mon) then count = count + 1 end
    end
    return false, count
  end,
  -- pokefirered/src/pokemon_storage_system_menu.c:155
  [Std.SPECIAL.CountPartyAliveNonEggMons_IgnoreVar0x8004Slot] = function(ctx)
    local party = partyOf()
    local skip = varGet(ctx, 0x8004) + 1
    local count = 0
    for i = 1, PARTY_SIZE do
      local mon = party[i]
      if i ~= skip and speciesOf(mon) ~= 0 and not isEgg(mon)
        and (tonumber(mon.hp) or 0) ~= 0 then
        count = count + 1
      end
    end
    return false, count
  end,
  -- pokefirered/src/field_specials.c:1767
  [Std.SPECIAL.DoesPlayerPartyContainSpecies] = function(ctx)
    local party = partyOf()
    local want = varGet(ctx, 0x8004)
    for i = 1, playerPartyCount() do
      if speciesOrEgg(party[i]) == want then return boolReturn(true) end
    end
    return boolReturn(false)
  end,
  -- pokefirered/src/field_specials.c:2494
  [Std.SPECIAL.PlayerPartyContainsSpeciesWithPlayerID] = function(ctx)
    local session = sessionOf()
    local party = partyOf()
    local want = varGet(ctx, 0x8004)
    local playerId = tonumber(session and session.trainerId) or 0
    for i = 1, playerPartyCount() do
      local mon = party[i]
      local otId = tonumber(mon and (mon.otId or mon.ot_id)) or playerId
      if speciesOrEgg(mon) == want and otId == playerId then
        return boolReturn(true)
      end
    end
    return boolReturn(false)
  end,
  -- pokefirered/src/field_specials.c:524
  [Std.SPECIAL.GetPartyMonSpecies] = function(ctx)
    local mon = partyOf()[varGet(ctx, 0x8004) + 1]
    local species = speciesOrEgg(mon)
    return false, species
  end,
  -- pokefirered/src/party_menu_specials.c:102
  [Std.SPECIAL.IsSelectedMonEgg] = function(ctx)
    local mon = partyOf()[varGet(ctx, 0x8004) + 1]
    return boolResult(ctx, isEgg(mon))
  end,
  -- pokefirered/src/field_specials.c:529
  [Std.SPECIAL.IsMonOTNameNotPlayers] = function(ctx, adapters)
    local mon = partyOf()[varGet(ctx, 0x8004) + 1]
    local player = nameOfPlayer()
    local otName = tostring((mon and (mon.otName or mon.ot_name)) or player)
    setStringVar(ctx, adapters, 1, otName)
    return boolReturn(otName ~= player)
  end,
  -- pokefirered/src/field_specials.c:1619
  [Std.SPECIAL.NameRaterWasNicknameChanged] = function(ctx, adapters)
    local mon = partyOf()[varGet(ctx, 0x8004) + 1]
    local nick = nicknameOf(mon)
    setStringVar(ctx, adapters, 1, nick)
    local before = tostring((ctx and ctx.stringVars and ctx.stringVars[3]) or "")
    return boolReturn(before ~= nick)
  end,
  -- pokefirered/src/daycare.c:1216
  [Std.SPECIAL.GetSelectedMonNicknameAndSpecies] = function(ctx, adapters)
    -- pokefirered/src/party_menu.c:1200
    local mon = partyOf()[varGet(ctx, 0x8004) + 1]
    local species = speciesOf(mon)
    setStringVar(ctx, adapters, 1, nicknameOf(mon))
    return false, species
  end,
  -- pokefirered/src/money.c:63
  [Std.SPECIAL.IsEnoughForCostInVar0x8005] = function(ctx)
    local session = sessionOf()
    local money = tonumber(session and session.money) or 0
    return boolReturn(money >= varGet(ctx, 0x8005))
  end,
  -- pokefirered/src/money.c:68
  [Std.SPECIAL.SubtractMoneyFromVar0x8005] = function(ctx)
    local session = sessionOf()
    if session then
      local money = tonumber(session.money) or 0
      session.money = math.max(0, money - varGet(ctx, 0x8005))
    end
    return false
  end,
  -- pokefirered/src/pokedex.c:110
  [Std.SPECIAL.HasAllKantoMons] = function(ctx)
    local Dex = require("src.core.game3.dex")
    local dex = dexOf()
    for i = 1, KANTO_DEX_COUNT - 1 do
      if not Dex.isCaught(dex, i) then return boolReturn(false) end
    end
    return boolReturn(true)
  end,
  -- pokefirered/src/pokedex.c:123
  [Std.SPECIAL.HasAllMons] = function(ctx)
    local Dex = require("src.core.game3.dex")
    local dex = dexOf()
    local function caughtNational(nat)
      return Dex.isCaught(dex, speciesFromNational(nat))
    end
    for i = 1, KANTO_DEX_COUNT - 1 do
      if not caughtNational(i) then return boolReturn(false) end
    end
    for i = KANTO_DEX_COUNT + 1, JOHTO_DEX_COUNT - 3 do
      if not caughtNational(i) then return boolReturn(false) end
    end
    for i = JOHTO_DEX_COUNT + 1, NATIONAL_DEX_COUNT - 2 do
      if not caughtNational(i) then return boolReturn(false) end
    end
    return boolReturn(true)
  end,
  -- pokefirered/src/field_specials.c:1525
  [Std.SPECIAL.GetStarterSpecies] = function(ctx)
    local idx = varGet(ctx, VAR_STARTER_MON)
    if idx > 2 then idx = 0 end
    return false, STARTER_SPECIES[idx] or STARTER_SPECIES[0]
  end,
  -- pokefirered/src/field_specials.c:387
  [Std.SPECIAL.GetRandomSlotMachineId] = function(ctx)
    local Rng = require("src.core.game3.rng")
    local pick = SLOT_MACHINE_IDS[(Rng.Random() % #SLOT_MACHINE_IDS) + 1]
    return false, pick
  end,
  -- pokefirered/src/field_specials.c:137
  [Std.SPECIAL.BufferBigGuyOrBigGirlString] = function(ctx, adapters)
    local session = sessionOf()
    local female = (tonumber(session and session.gender) or 0) ~= 0
    setStringVar(ctx, adapters, 1, female and Strings("Big girl") or Strings("Big guy"))
    return false
  end,
  -- pokefirered/src/field_player_avatar.c:1082
  [Std.SPECIAL.GetPlayerFacingDirection] = function(ctx)
    local P = package.loaded["src.core.game3.player"]
    local dirs = { down = 1, up = 2, left = 3, right = 4 }
    local facing = dirs[P and P.facing] or varGet(ctx, 0x800C)
    return false, facing
  end,
  -- pokefirered/src/seagallop.c:496
  [Std.SPECIAL.IsPlayerLeftOfVermilionSailor] = function(ctx)
    local session = sessionOf()
    local onMap = session and session.map == "FR_VERMILION_CITY"
    local x = tonumber(session and session.x) or 0
    return boolReturn(onMap and x < 24)
  end,
  -- pokefirered/src/field_specials.c:2470
  [Std.SPECIAL.IsPlayerNotInTrainerTowerLobby] = function()
    local session = sessionOf()
    return boolReturn((session and session.map) ~= "FR_TRAINER_TOWER_LOBBY")
  end,
  -- pokefirered/src/union_room.c:3606
  [Std.SPECIAL.BufferUnionRoomPlayerName] = function()
    return boolReturn(false)
  end,
  -- pokefirered/src/field_specials.c:2458
  [Std.SPECIAL.IsBadEggInParty] = function()
    local party = partyOf()
    for i = 1, playerPartyCount() do
      if party[i] and party[i].isBadEgg == true then return boolReturn(true) end
    end
    return boolReturn(false)
  end,
  -- pokefirered/src/field_specials.c:432
  [Std.SPECIAL.IsThereRoomInAnyBoxForMorePokemon] = function()
    local session = sessionOf()
    local Storage = require("src.core.game3.storage")
    local storage = session and session.storage
    if not (storage and storage.boxes) then return boolReturn(true) end
    for b = 1, Storage.TOTAL_BOXES_COUNT do
      for s = 1, Storage.IN_BOX_COUNT do
        if Storage.getBoxMon(storage, b, s) == nil then return boolReturn(true) end
      end
    end
    return boolReturn(false)
  end,
  -- pokefirered/src/dodrio_berry_picking.c:2911
  [Std.SPECIAL.IsDodrioInParty] = function(ctx)
    local party = partyOf()
    for i = 1, PARTY_SIZE do
      local mon = party[i]
      if speciesOf(mon) ~= 0 and speciesOrEgg(mon) == SPECIES_DODRIO then
        return boolResult(ctx, true)
      end
    end
    return boolResult(ctx, false)
  end,
  -- pokefirered/src/item.c:142
  [Std.SPECIAL.HasAtLeastOneBerry] = function(ctx)
    if not bagHas(ITEM_BERRY_POUCH, 1) then return boolResult(ctx, false) end
    for itemId = FIRST_BERRY_INDEX, LAST_BERRY_INDEX do
      if bagHas(itemId, 1) then return boolResult(ctx, true) end
    end
    return boolResult(ctx, false)
  end,
  -- pokefirered/src/script_pokemon_util.c:119
  [Std.SPECIAL.DoesPartyHaveEnigmaBerry] = function(ctx, adapters)
    local party = partyOf()
    for i = 1, PARTY_SIZE do
      if heldItemOf(party[i]) == ITEM_ENIGMA_BERRY then
        setStringVar(ctx, adapters, 1, itemName(ITEM_ENIGMA_BERRY))
        return boolReturn(true)
      end
    end
    return boolReturn(false)
  end,
  -- pokefirered/src/field_specials.c:1985
  [Std.SPECIAL.ShouldShowBoxWasFullMessage] = function(ctx)
    local store = scriptStore()
    local Flags = flagsMod()
    if Flags.getFlag(store, ctx, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE) then
      return boolReturn(false)
    end
    local session = sessionOf()
    local storage = session and session.storage
    local current = (tonumber(storage and storage.currentBox) or 1) - 1
    if current == varGet(ctx, 0x4037) then return boolReturn(false) end
    if store then Flags.setFlag(store, ctx, FLAG_SHOWN_BOX_WAS_FULL_MESSAGE, true) end
    return boolReturn(true)
  end,
  -- pokefirered/src/field_specials.c:1980
  [Std.SPECIAL.GetPCBoxToSendMon] = function()
    return false, Queries.pcBoxToSendMon or 0
  end,
}

-- pokefirered/src/field_specials.c:1975
Queries.pcBoxToSendMon = 0

function Queries.setPCBoxToSendMon(boxId)
  Queries.pcBoxToSendMon = tonumber(boxId) or 0
end

return Queries
