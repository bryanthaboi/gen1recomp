-- data/specials.inc, src/berry_powder.c, src/pokemon_jump.c, src/dodrio_berry_picking.c, src/berry_crush.c, src/battle_tower.c, src/field_specials.c

local Strings = require("src.core.Strings")
local Std = require("src.core.game3.scripting.stdscripts")

local Wireless = {}

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328
local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_OBJ_GFX_ID_0 = 0x4010 -- pokefirered/include/constants/vars.h:28
local OBJ_EVENT_GFX_YOUNGSTER = 18 -- pokefirered/include/constants/event_objects.h:24
local PARTY_SIZE = 6 -- pokefirered/include/constants/pokemon.h
local MAX_BERRY_POWDER = 99999 -- pokefirered/src/berry_powder.c:12

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function sessionOf(ctx)
  local rt = package.loaded["src.core.game3.runtime"]
  return (rt and rt.getSession and rt.getSession())
    or (ctx and ctx.session)
    or nil
end

local function scriptStore(ctx)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local session = sessionOf(ctx)
  return (Space and Space.store)
    or (session and (session.store or session))
    or (ctx and (ctx.store or ctx.session or (ctx.vars and ctx)))
    or nil
end

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(ctx), ctx, id)) or 0
end

local function varSet(ctx, id, value)
  flagsMod().setVar(scriptStore(ctx), ctx, id, tonumber(value) or 0)
end

local function setResult(ctx, value)
  varSet(ctx, VAR_RESULT, value)
end

local function setStringVar(ctx, adapters, index, text)
  if adapters and adapters.setStringVar then pcall(adapters.setStringVar, index, text) end
  if ctx and ctx.stringVars then ctx.stringVars[index] = text end
end

-- pokefirered/src/battle_tower.c:1354
local function visitingEReaderTrainer(session)
  local trainer = session and session.ereaderTrainer
  if type(trainer) ~= "table" then return nil end
  if type(trainer.party) ~= "table" or type(trainer.party[1]) ~= "table" then
    return nil
  end
  return trainer
end

-- pokefirered/src/battle_tower.c:830
local function convertSpeech(words)
  if type(words) ~= "table" then return "" end
  local okE, EasyChatData = pcall(require, "src.core.game3.easy_chat_data")
  if not (okE and EasyChatData and EasyChatData.formatPhrase) then return "" end
  local ok, text = pcall(EasyChatData.formatPhrase, words, 3, 2)
  if ok and type(text) == "string" then return text end
  return ""
end

Wireless.HANDLERS = {
  -- pokefirered/src/party_menu.c:5818, data/scripts/cable_club.inc:1181
  [Std.SPECIAL.ChooseMonForWirelessMinigame] = function(ctx)
    varSet(ctx, VAR_0x8004, PARTY_SIZE)
    return false
  end,

  -- pokefirered/src/pokemon_jump.c:2687, data/scripts/cable_club.inc:1177, pokemon_jump.c:766
  [Std.SPECIAL.IsPokemonJumpSpeciesInParty] = function(ctx)
    setResult(ctx, 0)
    return false, 0
  end,

  -- pokefirered/src/pokemon_jump.c:4487, data/scripts/cable_club.inc:1278
  [Std.SPECIAL.ShowPokemonJumpRecords] = function()
    return false
  end,

  -- pokefirered/src/dodrio_berry_picking.c:2929, data/scripts/cable_club.inc:1286
  [Std.SPECIAL.ShowDodrioBerryPickingRecords] = function()
    return false
  end,

  -- pokefirered/src/berry_crush.c:3189, data/maps/CeruleanCity_House5/scripts.inc:169
  [Std.SPECIAL.ShowBerryCrushRankings] = function()
    return false
  end,

  -- pokefirered/src/berry_powder.c:113
  [Std.SPECIAL.DisplayBerryPowderVendorMenu] = function(ctx)
    if ctx then ctx.berryPowderVendorOpen = true end
    local session = sessionOf(ctx)
    if session then session.berryPowderVendorOpen = true end
    return false
  end,

  -- pokefirered/src/berry_powder.c:128
  [Std.SPECIAL.RemoveBerryPowderVendorMenu] = function(ctx)
    if ctx then ctx.berryPowderVendorOpen = false end
    local session = sessionOf(ctx)
    if session then session.berryPowderVendorOpen = false end
    return false
  end,

  -- pokefirered/src/berry_powder.c:108
  [Std.SPECIAL.PrintPlayerBerryPowderAmount] = function()
    return false
  end,

  -- pokefirered/src/berry_powder.c:40
  [Std.SPECIAL.Script_HasEnoughBerryPowder] = function(ctx)
    local session = sessionOf(ctx)
    local powder = math.floor(tonumber(session and session.berryPowder) or 0)
    local cost = varGet(ctx, VAR_0x8004)
    local enough = (powder >= cost) and 1 or 0
    setResult(ctx, enough)
    return false, enough
  end,

  -- pokefirered/src/berry_powder.c:77
  [Std.SPECIAL.Script_TakeBerryPowder] = function(ctx)
    local session = sessionOf(ctx)
    local powder = math.floor(tonumber(session and session.berryPowder) or 0)
    local cost = varGet(ctx, VAR_0x8004)
    local took = 0
    if session and powder >= cost then
      powder = math.min(powder - cost, MAX_BERRY_POWDER)
      session.berryPowder = powder
      took = 1
    end
    setResult(ctx, took)
    return false, took
  end,

  -- pokefirered/src/field_specials.c:331, battle_tower.c:1343, data/maps/SevenIsland_House_Room1/scripts.inc:88, text.inc:19
  [Std.SPECIAL.BufferEReaderTrainerName] = function(ctx, adapters)
    local trainer = visitingEReaderTrainer(sessionOf(ctx))
    local name = trainer and trainer.name
    if type(name) ~= "string" or name == "" then name = Strings("TRAINER") end
    setStringVar(ctx, adapters, 1, name)
    return false
  end,

  -- pokefirered/src/battle_tower.c:1401, data/maps/SevenIsland_House_Room2/scripts.inc:18
  [Std.SPECIAL.BufferEReaderTrainerGreeting] = function(ctx, adapters)
    local trainer = visitingEReaderTrainer(sessionOf(ctx))
    local greeting = trainer and trainer.greeting
    local text
    if type(greeting) == "string" and greeting ~= "" then
      text = greeting
    elseif type(greeting) == "table" then
      text = convertSpeech(greeting)
    end
    if not text or text == "" then text = Strings("OK, LET'S BATTLE!") end
    setStringVar(ctx, adapters, 4, text)
    return false
  end,

  -- pokefirered/src/battle_tower.c:397, data/maps/SevenIsland_House_Room2/scripts.inc:7
  [Std.SPECIAL.SetEReaderTrainerGfxId] = function(ctx)
    varSet(ctx, VAR_OBJ_GFX_ID_0, OBJ_EVENT_GFX_YOUNGSTER)
    return false
  end,
}

return Wireless
