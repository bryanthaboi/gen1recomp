local Strings = require("src.core.Strings")
local Std = require("src.core.game3.scripting.stdscripts")
local Mail = require("src.core.game3.mail")

local Trade = {}

local VAR_0x8004 = 0x8004 -- pokefirered/include/constants/vars.h:319
local VAR_0x8005 = 0x8005 -- pokefirered/include/constants/vars.h:320

local SPECIES_NONE = 0 -- pokefirered/include/constants/species.h:4
local SPECIES_EGG = 412 -- pokefirered/include/constants/species.h:421
local METLOC_IN_GAME_TRADE = 0xFE -- pokefirered/include/constants/region_map_sections.h:218
local TRADED_FRIENDSHIP = 70 -- pokefirered/src/trade_scene.c:1075

-- pokefirered/src/trade_scene.c:2778
local FADE_FRAMES = 16

-- pokefirered/src/data/ingame_trades.h:1 sInGameTrades, FIRERED branch
local TRADES = {
  [0] = {
    nickname = "MIMIEN", species = 122, ivs = { 20, 15, 17, 24, 23, 22 },
    abilityNum = 0, otId = 1985, personality = 0x00009cae, heldItem = 0,
    otName = "REYLEY", otGender = 0, requestedSpecies = 63,
  },
  [1] = {
    nickname = "ZYNX", species = 124, ivs = { 18, 17, 18, 22, 25, 21 },
    abilityNum = 0, otId = 36728, personality = 0x498a2e1d, heldItem = 131,
    otName = "DONTAE", otGender = 0, requestedSpecies = 61, mailNum = 0,
  },
  [2] = {
    nickname = "MS. NIDO", species = 29, ivs = { 22, 18, 25, 19, 15, 22 },
    abilityNum = 0, otId = 63184, personality = 0x4c970b89, heldItem = 103,
    otName = "SAIGE", otGender = 1, requestedSpecies = 32,
  },
  [3] = {
    nickname = "CH'DING", species = 83, ivs = { 20, 25, 21, 24, 15, 20 },
    abilityNum = 0, otId = 8810, personality = 0x151943d7, heldItem = 225,
    otName = "ELYSSA", otGender = 0, requestedSpecies = 21,
  },
  [4] = {
    nickname = "NINA", species = 30, ivs = { 22, 25, 18, 19, 22, 15 },
    abilityNum = 0, otId = 13637, personality = 0x00eeca15, heldItem = 0,
    otName = "TURNER", otGender = 0, requestedSpecies = 33,
  },
  [5] = {
    nickname = "MARC", species = 108, ivs = { 24, 19, 21, 15, 23, 21 },
    abilityNum = 0, otId = 1239, personality = 0x451308ab, heldItem = 0,
    otName = "HADEN", otGender = 0, requestedSpecies = 55,
  },
  [6] = {
    nickname = "ESPHERE", species = 101, ivs = { 19, 16, 18, 25, 25, 19 },
    abilityNum = 1, otId = 50298, personality = 0x06341016, heldItem = 0,
    otName = "CLIFTON", otGender = 0, requestedSpecies = 26,
  },
  [7] = {
    nickname = "TANGENY", species = 114, ivs = { 22, 17, 25, 16, 23, 20 },
    abilityNum = 0, otId = 60042, personality = 0x5c77ecfa, heldItem = 108,
    otName = "NORMA", otGender = 1, requestedSpecies = 48,
  },
  [8] = {
    nickname = "SEELOR", species = 86, ivs = { 24, 15, 22, 16, 23, 22 },
    abilityNum = 0, otId = 9853, personality = 0x482cac89, heldItem = 0,
    otName = "GARETT", otGender = 0, requestedSpecies = 77,
  },
}
Trade.TRADES = TRADES
Trade.COUNT = 9

-- pokefirered/src/data/ingame_trades.h:184 sInGameTradeMailMessages
local TRADE_MAIL_MESSAGES = {
  [0] = { 3613, 4128, 5147, 10876, 3072, 4102, 5183, 4143, 4137 },
}
Trade.MAIL_MESSAGES = TRADE_MAIL_MESSAGES

-- pokefirered/src/trade.c:144 gLinkPartnerMail
Trade.PARTNER_MAIL = {}

-- pokefirered/src/trade_scene.c:2488 gLinkPartnerMail[0] = mail
function Trade.setPartnerMail(mailNum, record)
  local id = tonumber(mailNum)
  if not id then return false end
  Trade.PARTNER_MAIL[id] = record
  return true
end

function Trade.clearPartnerMail()
  Trade.PARTNER_MAIL = {}
end

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

local function setStringVar(ctx, adapters, index, text)
  if adapters and adapters.setStringVar then adapters.setStringVar(index, text) end
  if ctx and ctx.stringVars then ctx.stringVars[index] = text end
end

local function pokemonMod()
  local Pokemon = require("src.core.game3.pokemon")
  if not Pokemon._names then pcall(Pokemon.install, nil) end
  return Pokemon
end

local function speciesName(species)
  local Pokemon = pokemonMod()
  return (Pokemon.name and Pokemon.name(species)) or ""
end

local function nicknameOf(mon)
  if not mon then return "" end
  if mon.nickname and mon.nickname ~= "" then return tostring(mon.nickname) end
  return speciesName(speciesOf(mon))
end

-- pokefirered/include/constants/trade.h:24
Trade.CAN_TRADE_MON = 0
Trade.CANT_TRADE_LAST_MON = 1
Trade.CANT_TRADE_NATIONAL = 2
Trade.CANT_TRADE_EGG_YET = 3
Trade.CANT_TRADE_INVALID_MON = 4
Trade.CANT_TRADE_PARTNER_EGG_YET = 5

-- pokefirered/include/constants/species.h:157 KANTO_SPECIES_END
local KANTO_SPECIES_END = 151
local SPECIES_MEW = 151 -- pokefirered/include/constants/species.h:155
local SPECIES_DEOXYS = 410 -- pokefirered/include/constants/species.h:419
local VERSION_RUBY = 2 -- pokefirered/include/constants/global.h:9
local VERSION_SAPPHIRE = 3 -- pokefirered/include/constants/global.h:10

-- pokefirered/src/pokemon.c:3049 MON_DATA_SPECIES_OR_EGG
local function speciesOrEgg(mon)
  if not mon then return SPECIES_NONE end
  if isEgg(mon) then return SPECIES_EGG end
  return speciesOf(mon)
end

local function nationalUnlocked(session)
  local ok, PokedexData = pcall(require, "src.core.game3.pokedex_data")
  if not (ok and PokedexData and PokedexData.isNationalUnlocked) then return false end
  session = session or sessionOf()
  local okC, unlocked = pcall(PokedexData.isNationalUnlocked, session, session and session.dex)
  return okC and unlocked == true
end

-- pokefirered/src/field_specials.c:2458 IsBadEggInParty
function Trade.hasBadEgg(party)
  party = party or partyOf()
  for i = 1, 6 do
    if party[i] and party[i].isBadEgg == true then return true end
  end
  return false
end

-- pokefirered/src/trade.c:2745 CanTradeSelectedMon
function Trade.canTradeSelectedMon(party, monIdx, opts)
  party = party or partyOf()
  opts = opts or {}
  local idx = (tonumber(monIdx) or 0) + 1
  local count = tonumber(opts.partyCount) or #party
  local species2, species = {}, {}
  for i = 1, count do
    species2[i] = speciesOrEgg(party[i])
    species[i] = speciesOf(party[i])
  end

  local national = opts.nationalDex
  if national == nil then national = nationalUnlocked(opts.session) end
  if not national then
    -- pokefirered/src/trade.c:2767
    if species2[idx] and species2[idx] > KANTO_SPECIES_END then
      return Trade.CANT_TRADE_NATIONAL
    end
    -- pokefirered/src/trade.c:2775
    if species2[idx] == SPECIES_NONE then return Trade.CANT_TRADE_EGG_YET end
  end

  -- pokefirered/src/trade.c:2780
  local partner = opts.partner
  if partner then
    local version = tonumber(partner.version) or 0
    version = version % 0x100
    if version ~= VERSION_RUBY and version ~= VERSION_SAPPHIRE then
      local flags = tonumber(partner.progressFlags) or 0
      if flags % 16 == 0 then
        if species2[idx] == SPECIES_EGG then return Trade.CANT_TRADE_PARTNER_EGG_YET end
        if species2[idx] and species2[idx] > KANTO_SPECIES_END then
          return Trade.CANT_TRADE_INVALID_MON
        end
      end
    end
  end

  -- pokefirered/src/trade.c:2795
  if species[idx] == SPECIES_DEOXYS or species[idx] == SPECIES_MEW then
    if party[idx] and party[idx].fatefulEncounter == false then
      return Trade.CANT_TRADE_INVALID_MON
    end
  end

  -- pokefirered/src/trade.c:2803
  for i = 1, count do
    if species2[i] == SPECIES_EGG then species2[i] = SPECIES_NONE end
  end
  local left = 0
  for i = 1, count do
    if i ~= idx then left = left + (species2[i] or 0) end
  end
  if left ~= 0 then return Trade.CAN_TRADE_MON end
  return Trade.CANT_TRADE_LAST_MON
end

-- pokefirered/src/trade.c:546 sMessages
function Trade.refusalText(code)
  if code == Trade.CANT_TRADE_LAST_MON then
    -- pokefirered/src/strings.c:301 gText_OnlyPkmnForBattle
    return Strings("That's your only\nPOKéMON for battle.")
  end
  if code == Trade.CANT_TRADE_EGG_YET or code == Trade.CANT_TRADE_PARTNER_EGG_YET then
    -- pokefirered/src/strings.c:303 gText_EggCantBeTradedNow
    return Strings("An EGG can't be traded now.")
  end
  if code == Trade.CANT_TRADE_NATIONAL or code == Trade.CANT_TRADE_INVALID_MON then
    -- pokefirered/src/strings.c:302 gText_PkmnCantBeTradedNow
    return Strings("That POKéMON can't be traded\nnow.")
  end
  return nil
end

-- pokefirered/data/scripts/cable_club.inc:1440 CableClub_Text_YouHaveAMonThatCantBeTaken
function Trade.badEggText()
  return Strings("You have at least one POKéMON\nthat can't be taken.")
end

-- pokefirered/src/strings.c:304 gText_OtherTrainersPkmnCantBeTraded
function Trade.peerMonRefusalText()
  return Strings("The other TRAINER's POKéMON\ncan't be traded now.")
end

-- pokefirered/src/trade_scene.c:2500 GetInGameTradeMail
function Trade.tradeMail(entry)
  local words = entry and TRADE_MAIL_MESSAGES[tonumber(entry.mailNum) or -1]
  if not words then return nil end
  local record = Mail.clear(nil)
  for i = 1, Mail.MAIL_WORDS_COUNT do
    record.words[i] = words[i] or Mail.EC_WORD_UNDEFINED
  end
  record.playerName = Strings(entry.otName)
  record.trainerId = entry.otId
  record.species = entry.species
  record.itemId = entry.heldItem
  record.design = Mail.designOf(entry.heldItem)
  return record
end

-- pokefirered/src/trade_scene.c:2456 CreateInGameTradePokemonInternal
function Trade.createTradeMon(tradeIdx, level)
  local entry = TRADES[tonumber(tradeIdx) or -1]
  if not entry then return nil end
  level = math.max(1, math.min(100, tonumber(level) or 5))

  local Pokemon = pokemonMod()
  local Party = require("src.core.game3.party")
  local nickname, otName = Strings(entry.nickname), Strings(entry.otName)
  local scratch = { party = {}, name = otName, trainerId = entry.otId }
  local ok, _, mon = Party.giveMon(scratch, entry.species, level, nickname)
  if not (ok and mon) then return nil end

  mon.personality = entry.personality
  mon.nature = (Pokemon.natureId and Pokemon.natureId(entry.personality)) or 0
  mon.ivs = {
    hp = entry.ivs[1], atk = entry.ivs[2], def = entry.ivs[3],
    spe = entry.ivs[4], spa = entry.ivs[5], spd = entry.ivs[6],
  }
  mon.nickname = nickname
  mon.name = nickname
  mon.ot = otName
  mon.otName = otName
  mon.otId = entry.otId
  mon.otGender = entry.otGender
  local abilities = (Pokemon.abilities and Pokemon.abilities(entry.species)) or {}
  local ability = abilities[entry.abilityNum + 1] or abilities[1] or 0
  mon.ability = ability
  mon.abilityId = ability
  mon.gender = (Pokemon.gender and Pokemon.gender(entry.species, entry.personality)) or "U"
  mon.metLocation = METLOC_IN_GAME_TRADE
  mon.item = entry.heldItem
  mon.heldItem = entry.heldItem
  -- pokefirered/src/trade_scene.c:2483
  if entry.heldItem ~= 0 and Mail.isMailItem(entry.heldItem) then
    Trade.PARTNER_MAIL[0] = Trade.tradeMail(entry)
    mon.mail = 0
  else
    mon.mail = nil
  end
  mon.hp = nil
  Pokemon.applyStats(mon)
  return mon
end

-- pokefirered/src/trade_scene.c:1054 TradeMons
function Trade.tradeMons(session, playerSlot, offered)
  if not (session and offered) then return nil end
  local party = session.party or {}
  local slot = (tonumber(playerSlot) or 0) + 1
  local sent = party[slot]
  if not sent then return nil end
  -- pokefirered/src/trade_scene.c:1060
  local playerMail = tonumber(sent.mail)
  local partnerMail = tonumber(offered.mail)
  -- pokefirered/src/trade_scene.c:1066
  if playerMail and playerMail ~= Mail.MAIL_NONE then
    local record = Mail.slot(session, playerMail)
    if record then Mail.clear(record) end
  end
  party[slot] = offered
  -- pokefirered/src/trade_scene.c:1075
  if not isEgg(offered) then
    offered.friendship = TRADED_FRIENDSHIP
    offered.happiness = TRADED_FRIENDSHIP
  end
  -- pokefirered/src/trade_scene.c:1078
  if partnerMail and partnerMail ~= Mail.MAIL_NONE then
    local record = Trade.PARTNER_MAIL[partnerMail]
    if record then Mail.giveMailToMon2(session, offered, record) end
  end
  -- pokefirered/src/trade_scene.c:1081 UpdatePokedexForReceivedMon
  session.dex = session.dex or { seen = {}, owned = {} }
  session.dex.seen = session.dex.seen or {}
  session.dex.owned = session.dex.owned or {}
  local species = speciesOf(offered)
  if species ~= SPECIES_NONE then
    session.dex.seen[species] = true
    session.dex.owned[species] = true
  end
  return sent
end

local function evolutionOpen()
  local Scene = package.loaded["src.ui.game3.evolution_scene"]
  return Scene and Scene.isOpen and Scene.isOpen() or false
end

-- pokefirered/src/trade_scene.c:2277
function Trade.tryTradeEvolution(mon, session)
  local Evolution = require("src.core.game3.evolution")
  local target = Evolution.tradeTarget(mon, session)
  if not target then return false end
  local okS, EvolutionScene = pcall(require, "src.ui.game3.evolution_scene")
  if okS and EvolutionScene and EvolutionScene.start and love and love.graphics then
    EvolutionScene.start(mon, target, { canStop = false, session = session, via = "trade" })
    return true
  end
  Evolution.apply(mon, target, session, session and session.bag, "trade")
  return false
end

local function fade(mode)
  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade and Fade.begin then
    pcall(Fade.begin, mode, 1, function() end)
  end
end

-- pokefirered/src/trade_scene.c:2774 DoInGameTradeScene
function Trade.sceneTask(ctx, adapters, tradeIdx, playerSlot)
  local TradeScene = require("src.core.game3.trade_scene")
  local entry = TRADES[tonumber(tradeIdx) or -1]
  local frames = 0
  local phase = "fadeout"
  return function()
    if phase == "fadeout" then
      if frames == 0 then
        local okF, Fade = pcall(require, "src.ui.game3.fade")
        if okF and Fade and Fade.MODE then fade(Fade.MODE.TO_BLACK) end
      end
      frames = frames + 1
      -- pokefirered/src/trade_scene.c:2784 Task_InGameTrade
      if frames < FADE_FRAMES then return false end
      phase = "scene"
      local session = sessionOf()
      local offered = Trade._offered
        or Trade.createTradeMon(tradeIdx, Trade.levelOfSlot(playerSlot))
      Trade._offered = nil
      local sent = partyOf()[(tonumber(playerSlot) or 0) + 1]
      if not (offered and sent) then
        if adapters and adapters.log then
          adapters.log("[game3] in-game trade " .. tostring(tradeIdx) .. " had no mon to swap")
        end
        phase = "abort"
        frames = 0
        local okF, Fade = pcall(require, "src.ui.game3.fade")
        if okF and Fade and Fade.MODE then fade(Fade.MODE.FROM_BLACK) end
        return false
      end
      local swapped = false
      TradeScene.play(sent, offered, nil, {
        otName = entry and Strings(entry.otName) or nil,
        -- pokefirered/src/trade_scene.c:1776 TradeMons(gSpecialVar_0x8005, 0)
        onSwap = function()
          if not Trade.tradeMons(session, playerSlot, offered) then return end
          swapped = true
          -- pokefirered/src/trade_scene.c:2445 BufferInGameTradeMonName
          setStringVar(ctx, adapters, 1, nicknameOf(offered))
          setStringVar(ctx, adapters, 2, speciesName(speciesOf(offered)))
        end,
        -- pokefirered/src/trade_scene.c:1778
        onEvolve = function()
          if not swapped then return end
          Trade.tryTradeEvolution(offered, session)
        end,
      })
      return false
    end
    if phase == "abort" then
      frames = frames + 1
      return frames >= FADE_FRAMES
    end
    if phase == "scene" then
      if TradeScene.step() then phase = "evolving" end
      return false
    end
    -- pokefirered/src/trade_scene.c:1777 gCB2_AfterEvolution
    return not evolutionOpen()
  end
end

function Trade.levelOfSlot(playerSlot)
  local mon = partyOf()[(tonumber(playerSlot) or 0) + 1]
  return tonumber(mon and mon.level) or 5
end

Trade.HANDLERS = {
  -- pokefirered/src/trade_scene.c:2434
  [Std.SPECIAL.GetInGameTradeSpeciesInfo] = function(ctx, adapters)
    local entry = TRADES[varGet(ctx, VAR_0x8004)]
    if not entry then return false, SPECIES_NONE end
    setStringVar(ctx, adapters, 1, speciesName(entry.requestedSpecies))
    setStringVar(ctx, adapters, 2, speciesName(entry.species))
    return false, entry.requestedSpecies
  end,
  -- pokefirered/src/trade_scene.c:2514
  [Std.SPECIAL.GetTradeSpecies] = function(ctx)
    local mon = partyOf()[varGet(ctx, VAR_0x8005) + 1]
    if isEgg(mon) then return false, SPECIES_NONE end
    return false, speciesOf(mon)
  end,
  -- pokefirered/src/trade_scene.c:2522
  [Std.SPECIAL.CreateInGameTradePokemon] = function(ctx)
    Trade._offered = Trade.createTradeMon(varGet(ctx, VAR_0x8004), Trade.levelOfSlot(varGet(ctx, VAR_0x8005)))
    return false
  end,
  -- pokefirered/src/trade_scene.c:2774
  [Std.SPECIAL.DoInGameTradeScene] = function(ctx, adapters)
    local Natives = require("src.core.game3.scripting.natives")
    Natives.awaitState(ctx, Trade.sceneTask(ctx, adapters, varGet(ctx, VAR_0x8004),
      varGet(ctx, VAR_0x8005)))
    return false
  end,
}

return Trade
