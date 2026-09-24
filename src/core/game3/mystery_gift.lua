
local Strings = require("src.core.Strings")

local MysteryGift = {}

-- pokefirered/include/constants/mystery_gift.h:17
MysteryGift.CARD_TYPE_GIFT = 0
MysteryGift.CARD_TYPE_STAMP = 1
MysteryGift.CARD_TYPE_LINK_STAT = 2
MysteryGift.CARD_TYPE_COUNT = 3

-- pokefirered/include/constants/mystery_gift.h:23
MysteryGift.SEND_TYPE_DISALLOWED = 0
MysteryGift.SEND_TYPE_ALLOWED = 1
MysteryGift.SEND_TYPE_ALLOWED_ALWAYS = 2

-- pokefirered/include/constants/mystery_gift.h:11
MysteryGift.CARD_STAT_BATTLES_WON = 0
MysteryGift.CARD_STAT_BATTLES_LOST = 1
MysteryGift.CARD_STAT_NUM_TRADES = 2
MysteryGift.CARD_STAT_NUM_STAMPS = 3
MysteryGift.CARD_STAT_MAX_STAMPS = 4

-- pokefirered/include/constants/mystery_gift.h:5
MysteryGift.GET_NUM_STAMPS = 0
MysteryGift.GET_MAX_STAMPS = 1
MysteryGift.GET_CARD_BATTLES_WON = 2
MysteryGift.GET_CARD_BATTLES_LOST = 3
MysteryGift.GET_CARD_NUM_TRADES = 4

-- pokefirered/include/constants/mystery_gift.h:41
MysteryGift.NUM_WONDER_BGS = 8
MysteryGift.MAX_WONDER_CARD_STAT = 999
MysteryGift.WONDER_CARD_FLAG_OFFSET = 1000

-- pokefirered/include/constants/mystery_gift.h:47
MysteryGift.NEWS_REWARD_NONE = 0
MysteryGift.NEWS_REWARD_RECV_SMALL = 1
MysteryGift.NEWS_REWARD_RECV_BIG = 2
MysteryGift.NEWS_REWARD_WAITING = 3
MysteryGift.NEWS_REWARD_SENT_SMALL = 4
MysteryGift.NEWS_REWARD_SENT_BIG = 5
MysteryGift.NEWS_REWARD_AT_MAX = 6

-- pokefirered/include/wonder_news.h:6
MysteryGift.WONDER_NEWS_NONE = 0
MysteryGift.WONDER_NEWS_RECV_FRIEND = 1
MysteryGift.WONDER_NEWS_RECV_WIRELESS = 2
MysteryGift.WONDER_NEWS_SENT = 3

-- pokefirered/src/wonder_news.c:9
local MAX_SENT_REWARD = 4
-- pokefirered/src/wonder_news.c:13
local MAX_REWARD = 5
-- pokefirered/src/wonder_news.c:60
local NEWS_STEP_LIMIT = 500

-- pokefirered/include/constants/global.h:68
local NUM_QUESTIONNAIRE_WORDS = 4
local WONDER_CARD_TEXT_LENGTH = 40
local WONDER_NEWS_TEXT_LENGTH = 40
local WONDER_CARD_BODY_TEXT_LINES = 4
local WONDER_NEWS_BODY_TEXT_LINES = 10
MysteryGift.MAX_STAMP_CARD_STAMPS = 7

-- pokefirered/src/mystery_gift.c:30 sReceivedGiftFlags
-- pokefirered/include/constants/flags.h:704 FLAG_RECEIVED_AURORA_TICKET .. FLAG_WONDER_CARD_UNUSED_17
MysteryGift.RECEIVED_GIFT_FLAG_FIRST = 0x2A7
MysteryGift.NUM_WONDER_CARD_FLAGS = 20

-- pokefirered/include/constants/flags.h:1391
local FLAG_SYS_MYSTERY_GIFT_ENABLED = 0x839
-- pokefirered/include/constants/flags.h:1013
local FLAG_MYSTERY_GIFT_DONE = 0x3D8
-- pokefirered/include/constants/flags.h:1408
local FLAG_ENABLE_SHIP_NAVEL_ROCK = 0x84A
local FLAG_ENABLE_SHIP_BIRTH_ISLAND = 0x84B
-- pokefirered/include/constants/flags.h:704
local FLAG_RECEIVED_AURORA_TICKET = 0x2A7
local FLAG_RECEIVED_MYSTIC_TICKET = 0x2A8
-- pokefirered/include/constants/flags.h:767
local FLAG_FOUGHT_DEOXYS = 0x2E4
-- pokefirered/include/constants/flags.h:781
local FLAG_FOUGHT_LUGIA = 0x2F2
local FLAG_FOUGHT_HO_OH = 0x2F3

-- pokefirered/include/constants/vars.h:87
local VAR_WONDER_NEWS_STEP_COUNTER = 0x4028
-- pokefirered/include/constants/vars.h:71
local VAR_ALTERING_CAVE_WILD_SET = 0x4024
-- pokefirered/include/constants/vars.h:234
local VAR_EVENT_PICHU_SLOT = 0x40B5
local VAR_MYSTERY_GIFT_1 = 0x40B6

-- pokefirered/include/constants/items.h:442
MysteryGift.ITEM_MYSTIC_TICKET = 370
MysteryGift.ITEM_AURORA_TICKET = 371
-- pokefirered/include/constants/items.h:181
local FIRST_BERRY_INDEX = 133
local ITEM_RAZZ_BERRY = 148

-- pokefirered/include/constants/region_map_sections.h:219
local METLOC_FATEFUL_ENCOUNTER = 0xFF
-- pokefirered/include/constants/global.h:78
local PARTY_SIZE = 6
-- pokefirered/include/constants/species.h:4
local NUM_SPECIES = 412

MysteryGift.DELIVER_NOTHING = 0
MysteryGift.DELIVER_GIVEN = 1
MysteryGift.DELIVER_NO_ROOM = 2
MysteryGift.DELIVER_PARTY_FULL = 3
MysteryGift.DELIVER_ALREADY = 4

-- pokefirered/src/util.c:77 gCrc16Table
local CRC_TABLE = {}
do
  local bit = require("bit")
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
      if c % 2 == 1 then
        c = bit.bxor(bit.rshift(c, 1), 0x8408)
      else
        c = bit.rshift(c, 1)
      end
    end
    CRC_TABLE[i] = c
  end
end

-- pokefirered/src/util.c:250 CalcCRC16WithTable
function MysteryGift.crc16(bytes)
  if type(bytes) ~= "string" then return 0 end
  local bit = require("bit")
  local crc = 0x1121
  for i = 1, #bytes do
    local byte = bit.rshift(crc, 8)
    crc = bit.bxor(crc, bytes:byte(i))
    crc = bit.band(bit.bxor(byte, CRC_TABLE[bit.band(crc, 0xFF)]), 0xFFFF)
  end
  return bit.band(bit.bnot(crc), 0xFFFF)
end

local function clampText(text, limit)
  if type(text) ~= "string" then return "" end
  if #text <= limit then return text end
  local count, i = 0, 1
  while i <= #text do
    local c = text:byte(i)
    local len = (c >= 0xF0 and 4) or (c >= 0xE0 and 3) or (c >= 0xC0 and 2) or 1
    count = count + 1
    if count > limit then return text:sub(1, i - 1) end
    i = i + len
  end
  return text
end

local function num(value, default)
  return tonumber(value) or default or 0
end

local function copyList(list, count, limit)
  local out = {}
  for i = 1, count do
    out[i] = clampText(type(list) == "table" and list[i] or "", limit)
  end
  return out
end

local function copyFlagList(list)
  local out = {}
  for _, id in ipairs(type(list) == "table" and list or {}) do
    local n = tonumber(id)
    if n then out[#out + 1] = n end
  end
  return out
end

-- pokefirered/include/global.h:655 struct WonderCard
function MysteryGift.normalizeCard(card)
  if type(card) ~= "table" then return nil end
  local gift = type(card.gift) == "table" and card.gift or {}
  local moves = {}
  for slot, move in pairs(type(gift.moves) == "table" and gift.moves or {}) do
    local s, m = tonumber(slot), tonumber(move)
    if s and m then moves[s] = m end
  end
  return {
    flagId = num(card.flagId),
    iconSpecies = num(card.iconSpecies),
    idNumber = num(card.idNumber),
    type = num(card.type),
    bgType = num(card.bgType),
    sendType = num(card.sendType),
    maxStamps = num(card.maxStamps),
    titleText = clampText(card.titleText, WONDER_CARD_TEXT_LENGTH),
    subtitleText = clampText(card.subtitleText, WONDER_CARD_TEXT_LENGTH),
    bodyText = copyList(card.bodyText, WONDER_CARD_BODY_TEXT_LINES, WONDER_CARD_TEXT_LENGTH),
    footerLine1Text = clampText(card.footerLine1Text, WONDER_CARD_TEXT_LENGTH),
    footerLine2Text = clampText(card.footerLine2Text, WONDER_CARD_TEXT_LENGTH),
    gift = {
      kind = type(gift.kind) == "string" and gift.kind or "none",
      item = tonumber(gift.item),
      quantity = tonumber(gift.quantity) or 1,
      species = tonumber(gift.species),
      level = tonumber(gift.level) or 5,
      nickname = type(gift.nickname) == "string" and gift.nickname or nil,
      moves = moves,
      personality = tonumber(gift.personality),
      otName = type(gift.otName) == "string" and gift.otName or nil,
      otId = tonumber(gift.otId),
      heldItem = tonumber(gift.heldItem),
      setFlags = copyFlagList(gift.setFlags),
      haveFlags = copyFlagList(gift.haveFlags),
      doneFlag = tonumber(gift.doneFlag),
      slotVar = tonumber(gift.slotVar),
      varAdd = tonumber(gift.varAdd),
      varWrap = tonumber(gift.varWrap),
      requireStat = tonumber(gift.requireStat),
      requireValue = tonumber(gift.requireValue),
    },
  }
end

-- pokefirered/include/global.h:646 struct WonderNews
function MysteryGift.normalizeNews(news)
  if type(news) ~= "table" then return nil end
  return {
    id = num(news.id),
    sendType = num(news.sendType),
    bgType = num(news.bgType),
    titleText = clampText(news.titleText, WONDER_NEWS_TEXT_LENGTH),
    bodyText = copyList(news.bodyText, WONDER_NEWS_BODY_TEXT_LINES, WONDER_NEWS_TEXT_LENGTH),
  }
end

local function cardBytes(card)
  if type(card) ~= "table" then return "" end
  local gift = type(card.gift) == "table" and card.gift or {}
  local moveKeys = {}
  for slot in pairs(type(gift.moves) == "table" and gift.moves or {}) do
    moveKeys[#moveKeys + 1] = slot
  end
  table.sort(moveKeys)
  local parts = {
    tostring(num(card.flagId)), tostring(num(card.iconSpecies)),
    tostring(num(card.idNumber)), tostring(num(card.type)),
    tostring(num(card.bgType)), tostring(num(card.sendType)),
    tostring(num(card.maxStamps)),
    tostring(card.titleText or ""), tostring(card.subtitleText or ""),
    table.concat(copyList(card.bodyText, WONDER_CARD_BODY_TEXT_LINES, WONDER_CARD_TEXT_LENGTH), "\1"),
    tostring(card.footerLine1Text or ""), tostring(card.footerLine2Text or ""),
    tostring(gift.kind or "none"), tostring(gift.item or 0), tostring(gift.quantity or 0),
    tostring(gift.species or 0), tostring(gift.level or 0), tostring(gift.nickname or ""),
    tostring(gift.personality or 0), tostring(gift.otName or ""), tostring(gift.otId or 0),
    tostring(gift.doneFlag or 0), tostring(gift.slotVar or 0),
    tostring(gift.varAdd or 0), tostring(gift.varWrap or 0),
    tostring(gift.requireStat or 0), tostring(gift.requireValue or 0),
  }
  for _, slot in ipairs(moveKeys) do
    parts[#parts + 1] = tostring(slot) .. "=" .. tostring(gift.moves[slot])
  end
  for _, id in ipairs(gift.setFlags or {}) do parts[#parts + 1] = "S" .. tostring(id) end
  for _, id in ipairs(gift.haveFlags or {}) do parts[#parts + 1] = "H" .. tostring(id) end
  if gift.heldItem then parts[#parts + 1] = "I" .. tostring(gift.heldItem) end
  return table.concat(parts, "\2")
end

local function newsBytes(news)
  if type(news) ~= "table" then return "" end
  return table.concat({
    tostring(num(news.id)), tostring(num(news.sendType)), tostring(num(news.bgType)),
    tostring(news.titleText or ""),
    table.concat(copyList(news.bodyText, WONDER_NEWS_BODY_TEXT_LINES, WONDER_NEWS_TEXT_LENGTH), "\1"),
  }, "\2")
end

local function emptyStamps()
  local species, ids = {}, {}
  for i = 1, MysteryGift.MAX_STAMP_CARD_STAMPS do
    species[i] = 0
    ids[i] = 0
  end
  return { species = species, ids = ids }
end

-- pokefirered/include/global.h:671 struct WonderCardMetadata
local function newCardMetadata()
  return {
    battlesWon = 0,
    battlesLost = 0,
    numTrades = 0,
    iconSpecies = 0,
    stampData = emptyStamps(),
  }
end

-- pokefirered/include/global.h:638 struct WonderNewsMetadata
local function newNewsMetadata()
  return { newsType = 0, sentRewardCounter = 0, rewardCounter = 0, berry = 0 }
end

-- pokefirered/include/global.h:680 struct MysteryGiftSave
local function newSave()
  local words = {}
  for i = 1, NUM_QUESTIONNAIRE_WORDS do words[i] = 0 end
  return {
    newsCrc = 0,
    news = nil,
    cardCrc = 0,
    card = nil,
    cardMetadataCrc = 0,
    cardMetadata = newCardMetadata(),
    questionnaireWords = words,
    newsMetadata = newNewsMetadata(),
    trainerIds = { {}, {} },
  }
end

MysteryGift.SAVE_KEY = "mysteryGift"

-- pokefirered/include/global.h:680 struct MysteryGiftSave
function MysteryGift.ensure(session)
  if type(session) ~= "table" then return newSave() end
  local rec = type(session.mysteryGift) == "table" and session.mysteryGift or nil
  if not rec then
    session.modData = type(session.modData) == "table" and session.modData or {}
    rec = session.modData[MysteryGift.SAVE_KEY]
    if type(rec) ~= "table" then
      rec = newSave()
      session.modData[MysteryGift.SAVE_KEY] = rec
    end
  end
  rec.cardMetadata = type(rec.cardMetadata) == "table" and rec.cardMetadata or newCardMetadata()
  rec.cardMetadata.stampData = type(rec.cardMetadata.stampData) == "table"
    and rec.cardMetadata.stampData or emptyStamps()
  rec.newsMetadata = type(rec.newsMetadata) == "table" and rec.newsMetadata or newNewsMetadata()
  rec.trainerIds = type(rec.trainerIds) == "table" and rec.trainerIds or { {}, {} }
  rec.trainerIds[1] = type(rec.trainerIds[1]) == "table" and rec.trainerIds[1] or {}
  rec.trainerIds[2] = type(rec.trainerIds[2]) == "table" and rec.trainerIds[2] or {}
  return rec
end

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function scriptStore(session)
  if type(session) == "table" and type(session.store) == "table" then return session.store end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store then return Space.store end
  if type(session) == "table" then
    session.flags = type(session.flags) == "table" and session.flags or {}
    session.vars = type(session.vars) == "table" and session.vars or {}
    return { flags = session.flags, vars = session.vars }
  end
  return nil
end
MysteryGift.scriptStore = scriptStore

local function getFlag(session, id)
  return flagsMod().getFlag(scriptStore(session), nil, id) and true or false
end

local function setFlag(session, id, on)
  flagsMod().setFlag(scriptStore(session), nil, id, on ~= false)
end

local function getVar(session, id)
  return tonumber(flagsMod().getVar(scriptStore(session), nil, id)) or 0
end

local function setVar(session, id, value)
  flagsMod().setVar(scriptStore(session), nil, id, value)
end

MysteryGift.getFlag = getFlag
MysteryGift.setFlag = setFlag

-- pokefirered/src/event_data.c:127 IsMysteryGiftEnabled
function MysteryGift.isEnabled(session)
  return getFlag(session, FLAG_SYS_MYSTERY_GIFT_ENABLED)
end

-- pokefirered/src/event_data.c:122 EnableMysteryGift
function MysteryGift.enable(session)
  setFlag(session, FLAG_SYS_MYSTERY_GIFT_ENABLED, true)
end

-- pokefirered/src/mystery_gift.c:62 GetSavedWonderNews
function MysteryGift.getSavedNews(session)
  return MysteryGift.ensure(session).news
end

-- pokefirered/src/mystery_gift.c:67 GetSavedWonderCard
function MysteryGift.getSavedCard(session)
  return MysteryGift.ensure(session).card
end

-- pokefirered/src/mystery_gift.c:72 GetSavedWonderCardMetadata
function MysteryGift.getSavedCardMetadata(session)
  return MysteryGift.ensure(session).cardMetadata
end

-- pokefirered/src/mystery_gift.c:77 GetSavedWonderNewsMetadata
function MysteryGift.getSavedNewsMetadata(session)
  return MysteryGift.ensure(session).newsMetadata
end

-- pokefirered/src/mystery_gift.c:113 ValidateWonderNews
local function validateNews(news)
  if type(news) ~= "table" then return false end
  if num(news.id) == 0 then return false end
  return true
end
MysteryGift.validateNews = validateNews

-- pokefirered/src/mystery_gift.c:191 ValidateWonderCard
local function validateCard(card)
  if type(card) ~= "table" then return false end
  if num(card.flagId) == 0 then return false end
  if num(card.type) >= MysteryGift.CARD_TYPE_COUNT then return false end
  local send = num(card.sendType)
  if not (send == MysteryGift.SEND_TYPE_DISALLOWED
    or send == MysteryGift.SEND_TYPE_ALLOWED
    or send == MysteryGift.SEND_TYPE_ALLOWED_ALWAYS) then
    return false
  end
  if num(card.bgType) >= MysteryGift.NUM_WONDER_BGS then return false end
  if num(card.maxStamps) > MysteryGift.MAX_STAMP_CARD_STAMPS then return false end
  return true
end
MysteryGift.validateCard = validateCard

-- pokefirered/src/mystery_gift.c:128 ClearSavedWonderNews
local function clearSavedNews(session)
  local rec = MysteryGift.ensure(session)
  rec.news = nil
  rec.newsCrc = 0
end

-- pokefirered/src/mystery_gift.c:216 ClearSavedWonderCard
local function clearSavedCard(session)
  local rec = MysteryGift.ensure(session)
  rec.card = nil
  rec.cardCrc = 0
end

-- pokefirered/src/mystery_gift.c:222 ClearSavedWonderCardMetadata
local function clearSavedCardMetadata(session)
  local rec = MysteryGift.ensure(session)
  rec.cardMetadata = newCardMetadata()
  rec.cardMetadataCrc = 0
end

-- pokefirered/src/mystery_gift.c:592 ClearSavedTrainerIds
local function clearSavedTrainerIds(session)
  MysteryGift.ensure(session).trainerIds = { {}, {} }
end

-- pokefirered/src/event_data.c:132 ClearMysteryGiftFlags
local function clearMysteryGiftFlags(session)
  for id = FLAG_MYSTERY_GIFT_DONE, FLAG_MYSTERY_GIFT_DONE + 15 do
    setFlag(session, id, false)
  end
end

-- pokefirered/src/event_data.c:152 ClearMysteryGiftVars
local function clearMysteryGiftVars(session)
  setVar(session, VAR_EVENT_PICHU_SLOT, 0)
  for i = 0, 6 do
    setVar(session, VAR_MYSTERY_GIFT_1 + i, 0)
  end
  setVar(session, VAR_ALTERING_CAVE_WILD_SET, 0)
end

-- pokefirered/src/mystery_gift.c:134 ClearSavedWonderNewsMetadata
local function clearSavedNewsMetadata(session)
  MysteryGift.ensure(session).newsMetadata = newNewsMetadata()
  MysteryGift.resetNews(session)
end

-- pokefirered/src/mystery_gift.c:155 ClearSavedWonderCardAndRelated
function MysteryGift.clearCardAndRelated(session)
  clearSavedCard(session)
  clearSavedCardMetadata(session)
  clearSavedTrainerIds(session)
  clearMysteryGiftFlags(session)
  clearMysteryGiftVars(session)
end

-- pokefirered/src/mystery_gift.c:88 ClearSavedWonderNewsAndRelated
function MysteryGift.clearNewsAndRelated(session)
  clearSavedNews(session)
end

-- pokefirered/src/mystery_gift.c:55 ClearMysteryGift
function MysteryGift.clear(session)
  local rec = MysteryGift.ensure(session)
  local fresh = newSave()
  for key in pairs(rec) do rec[key] = nil end
  for key, value in pairs(fresh) do rec[key] = value end
  clearSavedNewsMetadata(session)
end

-- pokefirered/src/mystery_gift.c:166 SaveWonderCard
function MysteryGift.saveCard(session, card)
  local normalized = MysteryGift.normalizeCard(card)
  if not validateCard(normalized) then return false end
  MysteryGift.clearCardAndRelated(session)
  local rec = MysteryGift.ensure(session)
  rec.card = normalized
  rec.cardCrc = MysteryGift.crc16(cardBytes(normalized))
  rec.cardMetadata.iconSpecies = normalized.iconSpecies
  return true
end

-- pokefirered/src/mystery_gift.c:180 ValidateSavedWonderCard
function MysteryGift.validateSavedCard(session)
  local rec = MysteryGift.ensure(session)
  if not rec.card then return false end
  if num(rec.cardCrc) ~= MysteryGift.crc16(cardBytes(rec.card)) then return false end
  if not validateCard(rec.card) then return false end
  return true
end

-- pokefirered/src/mystery_gift.c:93 SaveWonderNews
function MysteryGift.saveNews(session, news)
  local normalized = MysteryGift.normalizeNews(news)
  if not validateNews(normalized) then return false end
  clearSavedNews(session)
  local rec = MysteryGift.ensure(session)
  rec.news = normalized
  rec.newsCrc = MysteryGift.crc16(newsBytes(normalized))
  return true
end

-- pokefirered/src/mystery_gift.c:104 ValidateSavedWonderNews
function MysteryGift.validateSavedNews(session)
  local rec = MysteryGift.ensure(session)
  if not rec.news then return false end
  if num(rec.newsCrc) ~= MysteryGift.crc16(newsBytes(rec.news)) then return false end
  if not validateNews(rec.news) then return false end
  return true
end

-- pokefirered/src/mystery_gift.c:140 IsWonderNewsSameAsSaved
function MysteryGift.isNewsSameAsSaved(session, news)
  if not MysteryGift.validateSavedNews(session) then return false end
  local other = MysteryGift.normalizeNews(news)
  if not other then return false end
  return newsBytes(MysteryGift.ensure(session).news) == newsBytes(other)
end

-- pokefirered/src/mystery_gift.c:120 IsSendingSavedWonderNewsAllowed
function MysteryGift.isSendingNewsAllowed(session)
  local news = MysteryGift.ensure(session).news
  if not news then return false end
  return num(news.sendType) ~= MysteryGift.SEND_TYPE_DISALLOWED
end

-- pokefirered/src/mystery_gift.c:208 IsSendingSavedWonderCardAllowed
function MysteryGift.isSendingCardAllowed(session)
  local card = MysteryGift.ensure(session).card
  if not card then return false end
  return num(card.sendType) ~= MysteryGift.SEND_TYPE_DISALLOWED
end

-- pokefirered/src/mystery_gift.c:235 DisableWonderCardSending
function MysteryGift.disableCardSending(card)
  if type(card) == "table" and num(card.sendType) == MysteryGift.SEND_TYPE_ALLOWED then
    card.sendType = MysteryGift.SEND_TYPE_DISALLOWED
  end
end

-- pokefirered/src/mystery_gift.c:228 GetWonderCardFlagId
function MysteryGift.getCardFlagId(session)
  if MysteryGift.validateSavedCard(session) then
    return num(MysteryGift.ensure(session).card.flagId)
  end
  return 0
end

-- pokefirered/src/mystery_gift.c:241 IsWonderCardFlagIDInValidRange
local function isFlagIdInValidRange(flagId)
  return flagId >= MysteryGift.WONDER_CARD_FLAG_OFFSET
    and flagId < MysteryGift.WONDER_CARD_FLAG_OFFSET + MysteryGift.NUM_WONDER_CARD_FLAGS
end

-- pokefirered/src/mystery_gift.c:30 sReceivedGiftFlags
function MysteryGift.receivedGiftFlag(flagId)
  flagId = num(flagId)
  if not isFlagIdInValidRange(flagId) then return nil end
  return MysteryGift.RECEIVED_GIFT_FLAG_FIRST + (flagId - MysteryGift.WONDER_CARD_FLAG_OFFSET)
end

-- pokefirered/src/mystery_gift.c:248 IsSavedWonderCardGiftNotReceived
function MysteryGift.isGiftNotReceived(session)
  local flagId = MysteryGift.getCardFlagId(session)
  local giftFlag = MysteryGift.receivedGiftFlag(flagId)
  if not giftFlag then return false end
  if getFlag(session, giftFlag) then return false end
  return true
end

-- pokefirered/src/mystery_gift.c:260 GetNumStampsInMetadata
local function numStampsInMetadata(metadata, size)
  local stamps = type(metadata) == "table" and metadata.stampData or nil
  if type(stamps) ~= "table" then return 0 end
  local count = 0
  for i = 1, num(size) do
    if num(stamps.ids[i]) ~= 0 and num(stamps.species[i]) ~= 0 then
      count = count + 1
    end
  end
  return count
end

-- pokefirered/src/mystery_gift.c:272 IsStampInMetadata
local function isStampInMetadata(metadata, stamp, maxStamps)
  local stamps = type(metadata) == "table" and metadata.stampData or nil
  if type(stamps) ~= "table" then return false end
  for i = 1, num(maxStamps) do
    if num(stamps.ids[i]) == num(stamp and stamp.id) then return true end
    if num(stamps.species[i]) == num(stamp and stamp.species) then return true end
  end
  return false
end

-- pokefirered/src/mystery_gift.c:285 ValidateStamp
local function validateStamp(stamp)
  if type(stamp) ~= "table" then return false end
  if num(stamp.id) == 0 then return false end
  if num(stamp.species) == 0 then return false end
  if num(stamp.species) >= NUM_SPECIES then return false end
  return true
end

-- pokefirered/src/mystery_gift.c:296 GetNumStampsInSavedCard
local function numStampsInSavedCard(session)
  if not MysteryGift.validateSavedCard(session) then return 0 end
  local rec = MysteryGift.ensure(session)
  if num(rec.card.type) ~= MysteryGift.CARD_TYPE_STAMP then return 0 end
  return numStampsInMetadata(rec.cardMetadata, rec.card.maxStamps)
end

-- pokefirered/src/mystery_gift.c:307 MysteryGift_TrySaveStamp
function MysteryGift.trySaveStamp(session, stamp)
  local rec = MysteryGift.ensure(session)
  local card = rec.card
  local maxStamps = num(card and card.maxStamps)
  if not validateStamp(stamp) then return false end
  if isStampInMetadata(rec.cardMetadata, stamp, maxStamps) then return false end
  local stamps = rec.cardMetadata.stampData
  for i = 1, maxStamps do
    if num(stamps.ids[i]) == 0 and num(stamps.species[i]) == 0 then
      stamps.ids[i] = num(stamp.id)
      stamps.species[i] = num(stamp.species)
      return true
    end
  end
  return false
end

-- pokefirered/src/mystery_gift.c:490 MysteryGift_GetCardStat
function MysteryGift.getCardStat(session, stat)
  local rec = MysteryGift.ensure(session)
  local card = rec.card
  local cardType = num(card and card.type)
  stat = num(stat)
  if stat == MysteryGift.CARD_STAT_BATTLES_WON then
    if cardType == MysteryGift.CARD_TYPE_LINK_STAT then return num(rec.cardMetadata.battlesWon) end
  elseif stat == MysteryGift.CARD_STAT_BATTLES_LOST then
    if cardType == MysteryGift.CARD_TYPE_LINK_STAT then return num(rec.cardMetadata.battlesLost) end
  elseif stat == MysteryGift.CARD_STAT_NUM_TRADES then
    if cardType == MysteryGift.CARD_TYPE_LINK_STAT then return num(rec.cardMetadata.numTrades) end
  elseif stat == MysteryGift.CARD_STAT_NUM_STAMPS then
    if cardType == MysteryGift.CARD_TYPE_STAMP then return numStampsInSavedCard(session) end
  elseif stat == MysteryGift.CARD_STAT_MAX_STAMPS then
    if cardType == MysteryGift.CARD_TYPE_STAMP then return num(card.maxStamps) end
  end
  return 0
end

-- pokefirered/src/field_specials.c:1955 GetMysteryGiftCardStat
function MysteryGift.getCardStatForScript(session, selector)
  selector = num(selector)
  if selector == MysteryGift.GET_NUM_STAMPS then
    return MysteryGift.getCardStat(session, MysteryGift.CARD_STAT_NUM_STAMPS)
  elseif selector == MysteryGift.GET_MAX_STAMPS then
    return MysteryGift.getCardStat(session, MysteryGift.CARD_STAT_MAX_STAMPS)
  elseif selector == MysteryGift.GET_CARD_BATTLES_WON then
    return MysteryGift.getCardStat(session, MysteryGift.CARD_STAT_BATTLES_WON)
  elseif selector == MysteryGift.GET_CARD_BATTLES_LOST then
    return MysteryGift.getCardStat(session, MysteryGift.CARD_STAT_BATTLES_LOST)
  elseif selector == MysteryGift.GET_CARD_NUM_TRADES then
    return MysteryGift.getCardStat(session, MysteryGift.CARD_STAT_NUM_TRADES)
  end
  return 0
end

MysteryGift._statsEnabled = false

-- pokefirered/src/mystery_gift.c:543 MysteryGift_DisableStats
function MysteryGift.disableStats()
  MysteryGift._statsEnabled = false
end

-- pokefirered/src/mystery_gift.c:548 MysteryGift_TryEnableStatsByFlagId
function MysteryGift.tryEnableStatsByFlagId(session, flagId)
  MysteryGift._statsEnabled = false
  flagId = num(flagId)
  if flagId == 0 then return false end
  if not MysteryGift.validateSavedCard(session) then return false end
  if num(MysteryGift.ensure(session).card.flagId) ~= flagId then return false end
  MysteryGift._statsEnabled = true
  return true
end

-- pokefirered/src/mystery_gift.c:458 IncrementCardStat
local function incrementCardStat(session, statType)
  local rec = MysteryGift.ensure(session)
  if num(rec.card and rec.card.type) ~= MysteryGift.CARD_TYPE_LINK_STAT then return end
  local key
  if statType == MysteryGift.CARD_STAT_BATTLES_WON then key = "battlesWon"
  elseif statType == MysteryGift.CARD_STAT_BATTLES_LOST then key = "battlesLost"
  elseif statType == MysteryGift.CARD_STAT_NUM_TRADES then key = "numTrades" end
  if not key then return end
  local value = num(rec.cardMetadata[key]) + 1
  if value > MysteryGift.MAX_WONDER_CARD_STAT then value = MysteryGift.MAX_WONDER_CARD_STAT end
  rec.cardMetadata[key] = value
end

-- pokefirered/src/mystery_gift.c:599 RecordTrainerId
local function recordTrainerId(trainerId, ids, size)
  trainerId = num(trainerId)
  for i = 1, size do ids[i] = num(ids[i]) end
  local found = nil
  for i = 1, size do
    if ids[i] == trainerId then found = i break end
  end
  if not found then
    for j = size, 2, -1 do ids[j] = ids[j - 1] end
    ids[1] = trainerId
    return true
  end
  for j = found, 2, -1 do ids[j] = ids[j - 1] end
  ids[1] = trainerId
  return false
end

-- pokefirered/src/mystery_gift.c:630 IncrementCardStatForNewTrainer
local function incrementCardStatForNewTrainer(session, stat, trainerId, ids)
  if recordTrainerId(trainerId, ids, 5) then
    incrementCardStat(session, stat)
  end
end

-- pokefirered/src/mystery_gift.c:561 MysteryGift_TryIncrementStat
function MysteryGift.tryIncrementStat(session, stat, trainerId)
  if not MysteryGift._statsEnabled then return end
  local rec = MysteryGift.ensure(session)
  if stat == MysteryGift.CARD_STAT_NUM_TRADES then
    incrementCardStatForNewTrainer(session, stat, trainerId, rec.trainerIds[2])
  elseif stat == MysteryGift.CARD_STAT_BATTLES_WON or stat == MysteryGift.CARD_STAT_BATTLES_LOST then
    incrementCardStatForNewTrainer(session, stat, trainerId, rec.trainerIds[1])
  end
end

-- pokefirered/src/wonder_news.c:21 WonderNews_SetReward
function MysteryGift.setNewsReward(session, newsType)
  local data = MysteryGift.getSavedNewsMetadata(session)
  local Rng = require("src.core.game3.rng")
  data.newsType = num(newsType)
  if data.newsType == MysteryGift.WONDER_NEWS_RECV_FRIEND
    or data.newsType == MysteryGift.WONDER_NEWS_RECV_WIRELESS then
    data.berry = (Rng.Random() % 15) + (ITEM_RAZZ_BERRY - FIRST_BERRY_INDEX + 1)
  elseif data.newsType == MysteryGift.WONDER_NEWS_SENT then
    data.berry = (Rng.Random() % 15) + 1
  end
end

-- pokefirered/src/wonder_news.c:42 WonderNews_Reset
function MysteryGift.resetNews(session)
  local data = MysteryGift.getSavedNewsMetadata(session)
  data.newsType = MysteryGift.WONDER_NEWS_NONE
  data.sentRewardCounter = 0
  data.rewardCounter = 0
  data.berry = 0
  setVar(session, VAR_WONDER_NEWS_STEP_COUNTER, 0)
end

-- pokefirered/src/wonder_news.c:53 WonderNews_IncrementStepCounter
function MysteryGift.incrementNewsStepCounter(session)
  local data = MysteryGift.getSavedNewsMetadata(session)
  if num(data.rewardCounter) >= MAX_REWARD then
    local steps = getVar(session, VAR_WONDER_NEWS_STEP_COUNTER) + 1
    if steps >= NEWS_STEP_LIMIT then
      data.rewardCounter = 0
      steps = 0
    end
    setVar(session, VAR_WONDER_NEWS_STEP_COUNTER, steps)
  end
end

-- pokefirered/src/wonder_news.c:133 GetRewardType
local function newsRewardType(data)
  if num(data.rewardCounter) == MAX_REWARD then return MysteryGift.NEWS_REWARD_AT_MAX end
  local newsType = num(data.newsType)
  if newsType == MysteryGift.WONDER_NEWS_NONE then return MysteryGift.NEWS_REWARD_WAITING end
  if newsType == MysteryGift.WONDER_NEWS_RECV_FRIEND then return MysteryGift.NEWS_REWARD_RECV_SMALL end
  if newsType == MysteryGift.WONDER_NEWS_RECV_WIRELESS then return MysteryGift.NEWS_REWARD_RECV_BIG end
  if newsType == MysteryGift.WONDER_NEWS_SENT then
    if num(data.sentRewardCounter) < MAX_SENT_REWARD - 1 then
      return MysteryGift.NEWS_REWARD_SENT_SMALL
    end
    return MysteryGift.NEWS_REWARD_SENT_BIG
  end
  return MysteryGift.NEWS_REWARD_NONE
end

-- pokefirered/src/wonder_news.c:102 GetRewardItem
local function newsRewardItem(data)
  data.newsType = MysteryGift.WONDER_NEWS_NONE
  local itemId = num(data.berry) + FIRST_BERRY_INDEX - 1
  data.berry = 0
  data.rewardCounter = num(data.rewardCounter) + 1
  if num(data.rewardCounter) > MAX_REWARD then data.rewardCounter = MAX_REWARD end
  return itemId
end

-- pokefirered/src/wonder_news.c:68 WonderNews_GetRewardInfo
function MysteryGift.getNewsRewardInfo(session)
  local data = MysteryGift.getSavedNewsMetadata(session)
  if not MysteryGift.isEnabled(session) or not MysteryGift.validateSavedNews(session) then
    return MysteryGift.NEWS_REWARD_NONE, nil
  end
  local rewardType = newsRewardType(data)
  local item = nil
  if rewardType == MysteryGift.NEWS_REWARD_RECV_SMALL
    or rewardType == MysteryGift.NEWS_REWARD_RECV_BIG then
    item = newsRewardItem(data)
  elseif rewardType == MysteryGift.NEWS_REWARD_SENT_SMALL then
    item = newsRewardItem(data)
    data.sentRewardCounter = num(data.sentRewardCounter) + 1
    if num(data.sentRewardCounter) > MAX_SENT_REWARD then
      data.sentRewardCounter = MAX_SENT_REWARD
    end
  elseif rewardType == MysteryGift.NEWS_REWARD_SENT_BIG then
    item = newsRewardItem(data)
    data.sentRewardCounter = 0
  end
  return rewardType, item
end

-- pokefirered/src/mystery_gift_client.c:213
function MysteryGift.receiveNews(session, news, newsType)
  if not MysteryGift.saveNews(session, news) then return false end
  MysteryGift.setNewsReward(session, newsType or MysteryGift.WONDER_NEWS_RECV_WIRELESS)
  return true
end

-- pokefirered/data/mystery_event_msg.s:69 SurfPichu_GiveEgg
local function createEventMon(session, gift)
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  if not Pokemon._names then pcall(Pokemon.install, nil) end
  local species = num(gift.species)
  local level = num(gift.level, 5)
  -- src/mystery_gift.c:191-210
  local known = type(Pokemon._names) == "table" and Pokemon._names[species] ~= nil
  if not known then return nil, "invalid gift species" end
  if level < 1 or level > 100 then return nil, "invalid gift level" end
  local isEgg = gift.kind == "egg"
  local ok, code, mon
  if isEgg then
    ok, code, mon = Party.giveEgg(session, species)
  else
    ok, code, mon = Party.giveMon(session, species, level, gift.nickname)
  end
  if not (ok and mon) then return nil, code end
  if gift.personality then
    mon.personality = num(gift.personality)
    if Pokemon.natureId then mon.nature = Pokemon.natureId(mon.personality) end
    if Pokemon.abilityId then
      mon.ability = Pokemon.abilityId(species, mon.personality)
      mon.abilityId = mon.ability
    end
    if Pokemon.gender then mon.gender = Pokemon.gender(species, mon.personality) end
    if Pokemon.applyStats then Pokemon.applyStats(mon) end
  end
  if gift.otName then
    mon.ot = gift.otName
    mon.otName = gift.otName
  end
  if gift.otId then
    -- pokefirered/src/pokemon.c:6062 IsShinyOtIdPersonality
    mon.otId = num(gift.otId) % 65536
    mon.otSecretId = math.floor(num(gift.otId) / 65536) % 65536
  end
  if gift.heldItem and num(gift.heldItem) > 0 then
    mon.item, mon.heldItem = num(gift.heldItem), num(gift.heldItem)
  end
  -- pokefirered/src/scrcmd.c:2244 ScrCmd_setmonmodernfatefulencounter
  mon.modernFatefulEncounter = true
  -- pokefirered/data/mystery_event_msg.s:72 setmonmetlocation METLOC_FATEFUL_ENCOUNTER
  mon.metLocation = METLOC_FATEFUL_ENCOUNTER
  mon.moves = mon.moves or {}
  mon.pp = mon.pp or {}
  mon.maxPp = mon.maxPp or {}
  for slot, move in pairs(gift.moves or {}) do
    mon.moves[slot] = move
    local pp = Pokemon.movePp and Pokemon.movePp(move) or nil
    mon.pp[slot] = pp or mon.pp[slot] or 5
    mon.maxPp[slot] = pp or mon.maxPp[slot] or 5
  end
  return mon, code
end
MysteryGift.createEventMon = createEventMon

-- src/mystery_event_script.c:92-95
local meScriptStatus = 0
function MysteryGift.setStatus(v)
  meScriptStatus = tonumber(v) or 0
  return meScriptStatus
end
function MysteryGift.getStatus()
  return meScriptStatus
end

-- pokefirered/data/mystery_event_msg.s:208 MysteryEventScript_AuroraTicket
function MysteryGift.deliverGift(session, card)
  card = card or MysteryGift.getSavedCard(session)
  if type(card) ~= "table" then return MysteryGift.DELIVER_NOTHING end
  local gift = type(card.gift) == "table" and card.gift or {}
  local receivedFlag = MysteryGift.receivedGiftFlag(card.flagId)

  -- pokefirered/src/mystery_gift.c:248 IsSavedWonderCardGiftNotReceived
  if receivedFlag and getFlag(session, receivedFlag) then
    return MysteryGift.DELIVER_ALREADY
  end
  if gift.doneFlag and getFlag(session, gift.doneFlag) then
    return MysteryGift.DELIVER_ALREADY
  end
  for _, flag in ipairs(gift.haveFlags or {}) do
    if getFlag(session, flag) then return MysteryGift.DELIVER_ALREADY end
  end
  -- pokefirered/data/mystery_event_msg.s:166 specialvar GetMysteryGiftCardStat
  if gift.requireStat
    and MysteryGift.getCardStat(session, gift.requireStat) ~= num(gift.requireValue) then
    return MysteryGift.DELIVER_NOTHING
  end

  if gift.kind == "item" then
    local Bag = require("src.core.game3.bag")
    session.bag = session.bag or Bag.new()
    local itemId = num(gift.item)
    local qty = num(gift.quantity, 1)
    -- pokefirered/data/mystery_event_msg.s:214 checkitem
    if Bag.has(session.bag, itemId, 1) then return MysteryGift.DELIVER_ALREADY end
    -- pokefirered/data/mystery_event_msg.s:219 checkitemspace
    if not Bag.canAdd(session.bag, itemId, qty) then return MysteryGift.DELIVER_NO_ROOM end
    if not Bag.add(session.bag, itemId, qty) then return MysteryGift.DELIVER_NO_ROOM end
  elseif gift.kind == "mon" or gift.kind == "egg" then
    -- pokefirered/data/mystery_event_msg.s:46 CalculatePlayerPartyCount
    session.party = session.party or {}
    if #session.party >= PARTY_SIZE then return MysteryGift.DELIVER_PARTY_FULL end
    if gift.slotVar then setVar(session, gift.slotVar, #session.party) end
    local mon = createEventMon(session, gift)
    if not mon then return MysteryGift.DELIVER_PARTY_FULL end
  elseif gift.kind == "var" then
    -- pokefirered/data/mystery_event_msg.s:325 MysteryEventScript_AlteringCave
    local id = num(gift.slotVar, VAR_ALTERING_CAVE_WILD_SET)
    local value = getVar(session, id) + num(gift.varAdd, 1)
    if gift.varWrap and value == num(gift.varWrap) then value = 0 end
    setVar(session, id, value)
  elseif gift.kind == "none" then
    return MysteryGift.DELIVER_NOTHING
  end

  -- pokefirered/data/mystery_event_msg.s:222 setflag
  for _, flag in ipairs(gift.setFlags or {}) do
    setFlag(session, flag, true)
  end
  if gift.doneFlag then setFlag(session, gift.doneFlag, true) end
  if receivedFlag then setFlag(session, receivedFlag, true) end
  return MysteryGift.DELIVER_GIVEN
end

-- pokefirered/src/mystery_gift_client.c:208
function MysteryGift.receiveCard(session, card)
  if not MysteryGift.saveCard(session, card) then return false end
  MysteryGift.enable(session)
  return true
end

local function bodyOf(...)
  return { ... }
end

-- pokefirered/data/mystery_event_msg.s:1
function MysteryGift.builtins()
  return {
    {
      key = "mystic_ticket",
      label = Strings("MYSTIC TICKET"),
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 1,
        idNumber = 1,
        iconSpecies = 0,
        type = MysteryGift.CARD_TYPE_GIFT,
        bgType = 2,
        sendType = MysteryGift.SEND_TYPE_DISALLOWED,
        maxStamps = 0,
        titleText = Strings("MYSTIC TICKET"),
        subtitleText = Strings("MYSTERY GIFT"),
        -- pokefirered/data/mystery_event_msg.s:303 sText_MysticTicket2
        bodyText = bodyOf(
          Strings("Thank you for using the MYSTERY"),
          Strings("GIFT System."),
          Strings("There is a ticket here for you."),
          Strings("It is for use at VERMILION CITY port.")),
        footerLine1Text = Strings("Speak to the deliveryman"),
        footerLine2Text = Strings("at a POKéMON CENTER."),
        gift = {
          kind = "item",
          item = MysteryGift.ITEM_MYSTIC_TICKET,
          quantity = 1,
          -- pokefirered/data/mystery_event_msg.s:281
          setFlags = { FLAG_ENABLE_SHIP_NAVEL_ROCK, FLAG_RECEIVED_MYSTIC_TICKET },
          -- pokefirered/data/mystery_event_msg.s:270
          haveFlags = { FLAG_RECEIVED_MYSTIC_TICKET, FLAG_FOUGHT_LUGIA, FLAG_FOUGHT_HO_OH },
        },
      },
    },
    {
      key = "aurora_ticket",
      label = Strings("AURORA TICKET"),
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET,
        idNumber = 2,
        iconSpecies = 0,
        type = MysteryGift.CARD_TYPE_GIFT,
        bgType = 3,
        sendType = MysteryGift.SEND_TYPE_DISALLOWED,
        maxStamps = 0,
        titleText = Strings("AURORA TICKET"),
        subtitleText = Strings("MYSTERY GIFT"),
        -- pokefirered/data/mystery_event_msg.s:244 sText_AuroraTicket1
        bodyText = bodyOf(
          Strings("Thank you for using the MYSTERY"),
          Strings("GIFT System."),
          Strings("There is a ticket here for you."),
          Strings("It is for use at VERMILION CITY port.")),
        footerLine1Text = Strings("Speak to the deliveryman"),
        footerLine2Text = Strings("at a POKéMON CENTER."),
        gift = {
          kind = "item",
          item = MysteryGift.ITEM_AURORA_TICKET,
          quantity = 1,
          -- pokefirered/data/mystery_event_msg.s:222
          setFlags = { FLAG_ENABLE_SHIP_BIRTH_ISLAND, FLAG_RECEIVED_AURORA_TICKET },
          -- pokefirered/data/mystery_event_msg.s:212
          haveFlags = { FLAG_RECEIVED_AURORA_TICKET, FLAG_FOUGHT_DEOXYS },
        },
      },
    },
    {
      key = "surf_pichu",
      -- pokefirered/data/mystery_event_msg.s:40 MysteryEventScript_SurfPichu
      label = Strings("SURFING PICHU EGG"),
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 3,
        idNumber = 3,
        iconSpecies = 172,
        type = MysteryGift.CARD_TYPE_GIFT,
        bgType = 1,
        sendType = MysteryGift.SEND_TYPE_DISALLOWED,
        maxStamps = 0,
        titleText = Strings("POKéMON EGG"),
        subtitleText = Strings("MYSTERY GIFT"),
        -- pokefirered/data/mystery_event_msg.s:100 sText_MysteryGiftEgg
        bodyText = bodyOf(
          Strings("From the POKéMON CENTER we"),
          Strings("have a gift, a POKéMON EGG!"),
          Strings("Please raise it with love and"),
          Strings("kindness.")),
        footerLine1Text = Strings("Speak to the deliveryman"),
        footerLine2Text = Strings("at a POKéMON CENTER."),
        gift = {
          kind = "egg",
          species = 172,
          -- pokefirered/data/mystery_event_msg.s:81 setmonmove slot, 2, MOVE_SURF
          moves = { [3] = 57 },
          slotVar = VAR_EVENT_PICHU_SLOT,
          -- pokefirered/data/mystery_event_msg.s:42
          doneFlag = FLAG_MYSTERY_GIFT_DONE,
        },
      },
    },
    {
      key = "stamp_card",
      label = Strings("STAMP CARD"),
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 4,
        idNumber = 4,
        iconSpecies = 0,
        type = MysteryGift.CARD_TYPE_STAMP,
        bgType = 4,
        sendType = MysteryGift.SEND_TYPE_ALLOWED,
        maxStamps = MysteryGift.MAX_STAMP_CARD_STAMPS,
        titleText = Strings("STAMP CARD"),
        subtitleText = Strings("MYSTERY GIFT"),
        -- pokefirered/data/mystery_event_msg.s:34 sText_MysteryGiftStampCard
        bodyText = bodyOf(
          Strings("Thank you for using the STAMP CARD"),
          Strings("System."),
          Strings("Trade with other TRAINERS to fill"),
          Strings("your STAMP CARD.")),
        footerLine1Text = Strings("Speak to the deliveryman"),
        footerLine2Text = Strings("at a POKéMON CENTER."),
        gift = { kind = "none" },
      },
    },
    {
      key = "battle_card",
      label = Strings("BATTLE COUNT CARD"),
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 5,
        idNumber = 5,
        iconSpecies = 0,
        type = MysteryGift.CARD_TYPE_LINK_STAT,
        bgType = 5,
        sendType = MysteryGift.SEND_TYPE_ALLOWED,
        maxStamps = 0,
        titleText = Strings("BATTLE COUNT CARD"),
        subtitleText = Strings("MYSTERY GIFT"),
        -- pokefirered/data/mystery_event_msg.s:187 sText_MysteryGiftBattleCountCard
        bodyText = bodyOf(
          Strings("Your BATTLE COUNT CARD keeps"),
          Strings("track of your battle record against"),
          Strings("TRAINERS with the same CARD."),
          Strings("Look for them and battle!")),
        footerLine1Text = Strings("Speak to the deliveryman"),
        footerLine2Text = Strings("at a POKéMON CENTER."),
        -- pokefirered/data/mystery_event_msg.s:173 giveitem ITEM_POTION
        gift = {
          kind = "item",
          item = 13,
          quantity = 1,
          doneFlag = FLAG_MYSTERY_GIFT_DONE,
          -- pokefirered/include/constants/mystery_gift.h:33 REQUIRED_CARD_BATTLES
          requireStat = MysteryGift.CARD_STAT_BATTLES_WON,
          requireValue = 3,
        },
      },
    },
    {
      key = "altering_cave",
      label = Strings("ALTERING CAVE"),
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 6,
        idNumber = 6,
        iconSpecies = 0,
        type = MysteryGift.CARD_TYPE_GIFT,
        bgType = 6,
        sendType = MysteryGift.SEND_TYPE_DISALLOWED,
        maxStamps = 0,
        titleText = Strings("ALTERING CAVE"),
        subtitleText = Strings("MYSTERY GIFT"),
        bodyText = bodyOf(
          Strings("The POKéMON living in ALTERING"),
          Strings("CAVE have changed."),
          Strings("Go and see what turns up"),
          Strings("on SIX ISLAND.")),
        footerLine1Text = Strings("Speak to the deliveryman"),
        footerLine2Text = Strings("at a POKéMON CENTER."),
        -- pokefirered/data/mystery_event_msg.s:325
        gift = {
          kind = "var",
          slotVar = VAR_ALTERING_CAVE_WILD_SET,
          varAdd = 1,
          varWrap = 10,
        },
      },
    },
  }
end

MysteryGift.GIFT_PUBKEY = "2cecc61cc4d4ea70fc6802a66643e659a0f2c344eec6391ccf20b434ab280ffd"
MysteryGift.FEED_PATH = "/gifts/gen3"
MysteryGift.FEED_VERSION = 1
MysteryGift.FETCH_SECONDS = 10

local function readClaims(session)
  local rec = MysteryGift.ensure(session)
  rec.claims = type(rec.claims) == "table" and rec.claims or {}
  rec.claims.cards = type(rec.claims.cards) == "table" and rec.claims.cards or {}
  rec.claims.news = type(rec.claims.news) == "table" and rec.claims.news or {}
  return rec.claims, rec
end

local function listHas(list, id)
  for _, v in ipairs(list) do
    if num(v) == id then return true end
  end
  return false
end

function MysteryGift.hasClaimedCard(session, card)
  local id = num(type(card) == "table" and card.idNumber or card)
  if id == 0 then return false end
  local claims, rec = readClaims(session)
  if listHas(claims.cards, id) then return true end
  return rec.card ~= nil and num(rec.card.idNumber) == id
end

function MysteryGift.hasClaimedNews(session, news)
  local id = num(type(news) == "table" and news.id or news)
  if id == 0 then return false end
  local claims, rec = readClaims(session)
  if listHas(claims.news, id) then return true end
  return rec.news ~= nil and num(rec.news.id) == id
end

function MysteryGift.claimCard(session, card)
  local id = num(type(card) == "table" and card.idNumber or card)
  if id == 0 then return false end
  local claims = readClaims(session)
  if not listHas(claims.cards, id) then claims.cards[#claims.cards + 1] = id end
  return true
end

function MysteryGift.claimNews(session, news)
  local id = num(type(news) == "table" and news.id or news)
  if id == 0 then return false end
  local claims = readClaims(session)
  if not listHas(claims.news, id) then claims.news[#claims.news + 1] = id end
  return true
end

function MysteryGift.parseFeed(payload)
  local Json = require("src.link.Json")
  local data = Json.decode(payload)
  if type(data) ~= "table" or data.v ~= MysteryGift.FEED_VERSION then return nil, "bad_feed" end
  if type(data.cards) ~= "table" or type(data.news) ~= "table" then return nil, "bad_feed" end
  local out = { issued = num(data.issued), cards = {}, news = {} }
  for _, raw in ipairs(data.cards) do
    local card = MysteryGift.normalizeCard(raw)
    if card and validateCard(card) and isFlagIdInValidRange(card.flagId) and card.idNumber ~= 0 then
      out.cards[#out.cards + 1] = {
        key = type(raw.key) == "string" and raw.key or tostring(card.idNumber),
        label = card.titleText,
        card = card,
      }
    end
  end
  for _, raw in ipairs(data.news) do
    local news = MysteryGift.normalizeNews(raw)
    if news and validateNews(news) then
      out.news[#out.news + 1] = {
        key = type(raw.key) == "string" and raw.key or tostring(news.id),
        label = news.titleText,
        news = news,
      }
    end
  end
  return out
end

function MysteryGift.verifyFeed(feed)
  if type(feed) ~= "table" or type(feed.payload) ~= "string" or type(feed.sig) ~= "string" then
    return nil, "bad_feed"
  end
  local Ed25519 = require("src.core.crypto.ed25519")
  if not Ed25519.verify(MysteryGift.GIFT_PUBKEY, feed.payload, feed.sig) then
    return nil, "bad_signature"
  end
  return MysteryGift.parseFeed(feed.payload)
end

function MysteryGift.fetchOnline(opts)
  opts = opts or {}
  local client = opts.client
  if not client then
    local okS, SyncClient = pcall(require, "src.sync.SyncClient")
    if not okS then return { status = "error", reason = "offline" } end
    local okN, made = pcall(SyncClient.new, { transport = opts.transport })
    if not okN then return { status = "error", reason = "offline" } end
    client = made
  end
  local okR, handle = pcall(client.send, client, "GET", MysteryGift.FEED_PATH, nil,
    { noAuth = true, maxSeconds = MysteryGift.FETCH_SECONDS })
  if not okR or handle == nil then
    return { status = "error", reason = "offline", client = client }
  end
  return { status = "pending", client = client, handle = handle }
end

function MysteryGift.pollOnline(job)
  if type(job) ~= "table" then return "error", "offline" end
  if job.status == "ok" then return "ok", job.result end
  if job.status == "error" then return "error", job.reason end
  local ok, res = pcall(job.client.poll, job.client, job.handle)
  if not ok or type(res) ~= "table" then res = { status = "error" } end
  if res.status == "pending" then return "pending" end
  pcall(job.client.release, job.client, job.handle)
  job.handle = nil
  if res.status ~= "ok" then
    job.status = "error"
    job.reason = (num(res.code) >= 400) and "server" or "offline"
    return "error", job.reason
  end
  local list, why = MysteryGift.verifyFeed(res.data)
  if not list then
    job.status, job.reason = "error", why
    return "error", why
  end
  job.status, job.result = "ok", list
  return "ok", list
end

function MysteryGift.cancelOnline(job)
  if type(job) ~= "table" or job.handle == nil then return end
  local transport = job.client and job.client.transport
  if transport and transport.cancel then pcall(transport.cancel, transport, job.handle) end
  pcall(job.client.release, job.client, job.handle)
  job.handle = nil
  job.status, job.reason = "error", "canceled"
end

-- pokefirered/src/main_menu.c:236 IsMysteryGiftEnabled
function MysteryGift.sessionFromSave(save)
  save = type(save) == "table" and save or {}
  local Flags = flagsMod()
  local store = Flags.newStore()
  Flags.loadInto(store, { flags = save.flags, vars = save.vars })
  save.modData = type(save.modData) == "table" and save.modData or {}
  local session = { store = store, modData = save.modData }
  MysteryGift.ensure(session)
  return session
end

-- pokefirered/src/mystery_gift_menu.c:855 SaveOnMysteryGiftMenu
function MysteryGift.applyToSave(session, save)
  if type(session) ~= "table" or type(save) ~= "table" then return false end
  local Flags = flagsMod()
  local snap = Flags.serialize(session.store or { flags = {}, vars = {} })
  save.flags = snap.flags
  save.vars = snap.vars
  save.modData = type(save.modData) == "table" and save.modData or {}
  save.modData[MysteryGift.SAVE_KEY] = MysteryGift.ensure(session)
  return true
end

return MysteryGift
