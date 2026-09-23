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

-- pokefirered/src/scrcmd.c:275 ScrCmd_trywondercardscript
function Gift.runWonderCardScript(ctx, adapters)
  local session = sessionOf()
  if not MysteryGift.validateSavedCard(session) then return false, false end
  local code = MysteryGift.deliverGift(session)
  Gift.lastDelivery = code
  local text = textBox(Gift.deliveryText(session, code), adapters)
  if not (adapters and (adapters.openMessageAsync or adapters.openMessage)) then
    return false, true
  end
  local Natives = require("src.core.game3.scripting.natives")
  local yield = Natives.yieldHost(ctx, adapters, function(done)
    if adapters.openMessageAsync then
      adapters.openMessageAsync(text, done)
    else
      adapters.openMessage(text)
      done()
    end
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
