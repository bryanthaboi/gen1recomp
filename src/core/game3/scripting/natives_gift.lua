local RomText = require("src.core.game3.rom_text")
local MysteryGift = require("src.core.game3.mystery_gift")

local Gift = {}

-- pokefirered/data/specials.inc:395
local SPECIAL_ValidateSavedWonderCard = 0x180
-- pokefirered/data/specials.inc:401
local SPECIAL_GetMysteryGiftCardStat = 0x186
-- pokefirered/data/specials.inc:404
local SPECIAL_WonderNews_GetRewardInfo = 0x189

local VAR_RESULT = 0x800D -- pokefirered/include/constants/vars.h:328

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function sessionOf()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end
Gift.session = sessionOf

local function scriptStore()
  return MysteryGift.scriptStore(sessionOf())
end

local function varGet(ctx, id)
  return tonumber(flagsMod().getVar(scriptStore(), ctx, id)) or 0
end

local function varSet(ctx, id, value)
  flagsMod().setVar(scriptStore(), ctx, id, tonumber(value) or 0)
end

-- pokefirered/data/mystery_event_msg.s:244
function Gift.deliveryText(session, code)
  local card = MysteryGift.getSavedCard(session)
  local mystic = card and card.gift and card.gift.item == MysteryGift.ITEM_MYSTIC_TICKET
  local ctx = { playerName = type(session) == "table" and (session.name or session.playerName) or nil }
  if code == MysteryGift.DELIVER_NO_ROOM then
    -- pokefirered/data/mystery_event_msg.s:260 sText_AuroraTicketNoPlace, :319 sText_MysticTicketNoPlace
    return RomText.ascii(mystic and "sText_MysticTicketNoPlace" or "sText_AuroraTicketNoPlace", ctx)
  end
  if code == MysteryGift.DELIVER_PARTY_FULL then
    -- pokefirered/data/mystery_event_msg.s:108 sText_FullParty
    return RomText.ascii("sText_FullParty", ctx)
  end
  local got = mystic and "sText_MysticTicketGot" or "sText_AuroraTicketGot"
  if code == MysteryGift.DELIVER_ALREADY or code == MysteryGift.DELIVER_NOTHING then
    -- pokefirered/data/mystery_event_msg.s:256 sText_AuroraTicketGot, :315 sText_MysticTicketGot
    return RomText.ascii(got, ctx)
  end
  local lines = {}
  for _, line in ipairs((card and card.bodyText) or {}) do
    if line ~= "" then lines[#lines + 1] = line end
  end
  if #lines == 0 then
    return RomText.ascii(got, ctx)
  end
  -- pokefirered/data/mystery_event_msg.s:303 sText_MysticTicket2
  local pages = {}
  for i = 1, #lines, 2 do
    pages[#pages + 1] = lines[i + 1] and (lines[i] .. "\n" .. lines[i + 1]) or lines[i]
  end
  return table.concat(pages, "\\p")
end

local function textBox(ascii, adapters)
  local TextIR = require("src.core.game3.scripting.text_ir")
  local view = {}
  if adapters then
    view.playerName = type(adapters.playerName) == "function"
      and adapters.playerName() or adapters.playerName
  end
  return TextIR.toTextBox(TextIR.fromAscii(ascii), view)
end
Gift.textBox = textBox

-- pokefirered/include/constants/songs.h:264
local MUS_LEVEL_UP = 257
local MUS_OBTAIN_ITEM = 258
local MUS_OBTAIN_KEY_ITEM = 318

function Gift.obtainedLine(session, code)
  if code ~= MysteryGift.DELIVER_GIVEN then return nil end
  local card = MysteryGift.getSavedCard(session)
  local gift = card and card.gift or {}
  local Strings = require("src.core.Strings")
  local player = type(session) == "table" and (session.name or session.playerName) or ""
  if gift.kind == "mon" then
    local Pokemon = require("src.core.game3.pokemon")
    local ok, name = pcall(Pokemon.name, tonumber(gift.species))
    -- pokefirered/data/maps/CeladonCity_Condominiums_RoofRoom/scripts.inc:21
    return Strings("%s obtained %s!", player, ok and name or ""), MUS_LEVEL_UP
  elseif gift.kind == "egg" then
    -- pokefirered/data/mystery_event_msg.s:55
    return Strings("%s received an EGG!", player), MUS_OBTAIN_ITEM
  elseif gift.kind == "item" then
    local Items = require("src.core.game3.items_data")
    local id = tonumber(gift.item)
    local key = Items.pocketOf(id) == "KEY_ITEMS"
    return Strings("%s obtained the %s!", player, Items.displayName(id)), key and MUS_OBTAIN_KEY_ITEM or MUS_OBTAIN_ITEM
  end
  return nil
end

-- pokefirered/src/scrcmd.c:275 ScrCmd_trywondercardscript
function Gift.runWonderCardScript(ctx, adapters)
  local session = sessionOf()
  if not MysteryGift.validateSavedCard(session) then return false, false end
  local code = MysteryGift.deliverGift(session)
  Gift.lastDelivery = code
  local text = textBox(Gift.deliveryText(session, code), adapters)
  local line, song = Gift.obtainedLine(session, code)
  Gift.lastObtained = line
  if not (adapters and (adapters.openMessageAsync or adapters.openMessage)) then
    return false, true
  end
  local Natives = require("src.core.game3.scripting.natives")
  local function show(msg, after)
    if adapters.openMessageAsync then
      adapters.openMessageAsync(msg, after)
    else
      adapters.openMessage(msg)
      after()
    end
  end
  local yield = Natives.yieldHost(ctx, adapters, function(done)
    show(text, function()
      if not line then return done() end
      local Audio = require("src.core.game3.audio")
      Audio.playFanfare(song)
      show(textBox(line, adapters), function()
        if adapters.waitFanfare then return adapters.waitFanfare(done) end
        Audio.waitFanfare(done)
      end)
    end)
  end)
  return yield, true
end

Gift.HANDLERS = {
  -- pokefirered/src/mystery_gift.c:180 ValidateSavedWonderCard
  [SPECIAL_ValidateSavedWonderCard] = function()
    return false, MysteryGift.validateSavedCard(sessionOf()) and 1 or 0
  end,
  -- pokefirered/src/field_specials.c:1955 GetMysteryGiftCardStat
  [SPECIAL_GetMysteryGiftCardStat] = function(ctx)
    return false, MysteryGift.getCardStatForScript(sessionOf(), varGet(ctx, VAR_RESULT))
  end,
  -- pokefirered/src/wonder_news.c:68 WonderNews_GetRewardInfo
  [SPECIAL_WonderNews_GetRewardInfo] = function(ctx)
    local rewardType, item = MysteryGift.getNewsRewardInfo(sessionOf())
    if item then varSet(ctx, VAR_RESULT, item) end
    return false, rewardType
  end,
}

Gift.SPECIAL_IDS = {
  ValidateSavedWonderCard = SPECIAL_ValidateSavedWonderCard,
  GetMysteryGiftCardStat = SPECIAL_GetMysteryGiftCardStat,
  WonderNews_GetRewardInfo = SPECIAL_WonderNews_GetRewardInfo,
}

return Gift
