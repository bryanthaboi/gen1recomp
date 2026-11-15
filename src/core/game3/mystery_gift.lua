
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
-- pokefirered/include/constants/flags.h:704
local FLAG_RECEIVED_AURORA_TICKET = 0x2A7
local FLAG_RECEIVED_MYSTIC_TICKET = 0x2A8
-- pokefirered/include/constants/flags.h:767
local FLAG_FOUGHT_DEOXYS = 0x2E4
-- pokefirered/include/constants/flags.h:781
local FLAG_FOUGHT_LUGIA = 0x2F2
local FLAG_FOUGHT_HO_OH = 0x2F3

local function versionOf(session)
  local ok, row = pcall(function() return require("src.core.game3.profile").forSession(session) end)
  return ok and type(row) == "table" and row.id or "firered"
end
MysteryGift.versionOf = versionOf

function MysteryGift.familyOf(session)
  return require("src.core.game3.link.family").of(versionOf(session))
end

local function consts(session)
  return require("src.core.game3.constants").of(versionOf(session))
end

MysteryGift.FAMILY = {
  frlg = {
    -- pokefirered/src/event_data.c:127
    enableFlag = "FLAG_SYS_MYSTERY_GIFT_ENABLED",
    -- pokefirered/src/wonder_news.c:74
    newsEnableFlag = "FLAG_SYS_MYSTERY_GIFT_ENABLED",
    -- pokefirered/src/event_data.c:152
    giftVars = { "VAR_EVENT_PICHU_SLOT", "VAR_MYSTERY_GIFT_1", "VAR_MYSTERY_GIFT_2", "VAR_MYSTERY_GIFT_3",
      "VAR_MYSTERY_GIFT_4", "VAR_MYSTERY_GIFT_5", "VAR_MYSTERY_GIFT_6", "VAR_MYSTERY_GIFT_7",
      "VAR_ALTERING_CAVE_WILD_SET" },
  },
  rse = {
    -- pokeemerald/src/event_data.c:107
    enableFlag = "FLAG_SYS_MYSTERY_GIFT_ENABLE",
    -- pokeemerald/src/wonder_news.c:77
    newsEnableFlag = "FLAG_SYS_MYSTERY_EVENT_ENABLE",
    -- pokeemerald/src/event_data.c:132
    giftVars = { "VAR_GIFT_PICHU_SLOT", "VAR_GIFT_UNUSED_1", "VAR_GIFT_UNUSED_2", "VAR_GIFT_UNUSED_3",
      "VAR_GIFT_UNUSED_4", "VAR_GIFT_UNUSED_5", "VAR_GIFT_UNUSED_6", "VAR_GIFT_UNUSED_7" },
  },
}

local function familyRow(session)
  return MysteryGift.FAMILY[MysteryGift.familyOf(session)] or MysteryGift.FAMILY.frlg
end

local function flagNamed(session, name)
  return consts(session):require("flags", name)
end

local function varNamed(session, name)
  return consts(session):require("vars", name)
end

local function wonderNewsStepVar(session)
  return varNamed(session, "VAR_WONDER_NEWS_STEP_COUNTER")
end

local RESOLVE_KINDS = { flags = true, vars = true, items = true, species = true, moves = true }

function MysteryGift.resolveId(version, kind, value)
  local n = tonumber(value)
  if n then return n end
  if type(value) ~= "string" or not RESOLVE_KINDS[kind] or not value:match("^[A-Z][A-Z0-9_]*$") then return nil end
  local ok, id = pcall(function()
    return require("src.core.game3.constants").of(version or versionOf(nil)):id(kind, value)
  end)
  return ok and tonumber(id) or nil
end
-- pokefirered/include/constants/vars.h:235
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

local function copyFlagList(list, version, bad)
  local out = {}
  for _, id in ipairs(type(list) == "table" and list or {}) do
    local n = MysteryGift.resolveId(version, "flags", id)
    if n then out[#out + 1] = n elseif id ~= nil then bad.any = true end
  end
  return out
end

MysteryGift.VERSIONS = { "firered", "leafgreen", "ruby", "sapphire", "emerald" }
MysteryGift.FAMILY_VERSIONS = { frlg = { "firered", "leafgreen" }, rse = { "emerald" }, rs = { "ruby", "sapphire" } }

local function copyVersions(list)
  if type(list) ~= "table" then return nil end
  local known, out = {}, {}
  for _, v in ipairs(MysteryGift.VERSIONS) do known[v] = true end
  for _, v in ipairs(list) do
    if known[v] then out[#out + 1] = v end
  end
  return out
end

function MysteryGift.offeredIn(list, version)
  if type(list) ~= "table" or version == nil then return true end
  for _, v in ipairs(list) do
    if v == version then return true end
  end
  return false
end

local function resolved(version, kind, value, bad)
  if value == nil then return nil end
  local n = MysteryGift.resolveId(version, kind, value)
  if n == nil then bad.any = true end
  return n
end

-- pokefirered/include/global.h:655 struct WonderCard
function MysteryGift.normalizeCard(card, version)
  if type(card) ~= "table" then return nil end
  local gift = type(card.gift) == "table" and card.gift or {}
  local bad = {}
  local moves = {}
  for slot, move in pairs(type(gift.moves) == "table" and gift.moves or {}) do
    local s, m = tonumber(slot), resolved(version, "moves", move, bad)
    if s and m then moves[s] = m end
  end
  local out = {
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
      item = resolved(version, "items", gift.item, bad),
      quantity = tonumber(gift.quantity) or 1,
      species = resolved(version, "species", gift.species, bad),
      level = tonumber(gift.level) or 5,
      nickname = type(gift.nickname) == "string" and gift.nickname or nil,
      moves = moves,
      personality = tonumber(gift.personality),
      otName = type(gift.otName) == "string" and gift.otName or nil,
      otId = tonumber(gift.otId),
      heldItem = resolved(version, "items", gift.heldItem, bad),
      setFlags = copyFlagList(gift.setFlags, version, bad),
      haveFlags = copyFlagList(gift.haveFlags, version, bad),
      doneFlag = resolved(version, "flags", gift.doneFlag, bad),
      slotVar = resolved(version, "vars", gift.slotVar, bad),
      varAdd = tonumber(gift.varAdd),
      varWrap = tonumber(gift.varWrap),
      requireStat = tonumber(gift.requireStat),
      requireValue = tonumber(gift.requireValue),
      script = type(gift.script) == "string" and gift.script:match("^[%w_]+$") and gift.script or nil,
      metLocation = tonumber(gift.metLocation),
      metLevel = tonumber(gift.metLevel),
      metGame = tonumber(gift.metGame),
      ball = tonumber(gift.ball),
      language = tonumber(gift.language),
      otNames = type(gift.otNames) == "table" and copyList(gift.otNames, math.min(#gift.otNames, 6), 7) or nil,
      otIdMax = tonumber(gift.otIdMax),
      secretIdRandom = gift.secretIdRandom == true or nil,
      otGender = tonumber(gift.otGender),
      shiny = (gift.shiny == "never" or gift.shiny == "always" or gift.shiny == "random") and gift.shiny or nil,
      nationalRibbon = gift.nationalRibbon == true or nil,
      movesOnly = gift.movesOnly == true or nil,
    },
    versions = copyVersions(card.versions),
  }
  if gift.fateful == false then out.gift.fateful = false end
  if bad.any then return nil, "unresolved" end
  return out
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
  if gift.script then parts[#parts + 1] = "R" .. tostring(gift.script) end
  for _, k in ipairs({ "metLocation", "metLevel", "metGame", "ball", "language", "otIdMax", "secretIdRandom",
    "otGender", "shiny", "nationalRibbon", "movesOnly" }) do
    if gift[k] ~= nil then parts[#parts + 1] = k .. "=" .. tostring(gift[k]) end
  end
  if gift.fateful == false then parts[#parts + 1] = "fateful=false" end
  for _, n in ipairs(type(gift.otNames) == "table" and gift.otNames or {}) do parts[#parts + 1] = "O" .. n end
  for _, slot in ipairs(moveKeys) do
    parts[#parts + 1] = tostring(slot) .. "=" .. tostring(gift.moves[slot])
  end
  for _, id in ipairs(gift.setFlags or {}) do parts[#parts + 1] = "S" .. tostring(id) end
  for _, id in ipairs(gift.haveFlags or {}) do parts[#parts + 1] = "H" .. tostring(id) end
  if gift.heldItem then parts[#parts + 1] = "I" .. tostring(gift.heldItem) end
  for _, v in ipairs(type(card.versions) == "table" and card.versions or {}) do parts[#parts + 1] = "V" .. tostring(v) end
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

-- pokeemerald/src/mystery_gift.c:54 GetQuestionnaireWordsPtr
function MysteryGift.questionnaireWords(session)
  local rec = MysteryGift.ensure(session)
  local words = type(rec.questionnaireWords) == "table" and rec.questionnaireWords or {}
  for i = 1, NUM_QUESTIONNAIRE_WORDS do
    local w = tonumber(words[i]) or 0
    -- pokeemerald/src/easy_chat.c:5857 InitQuestionnaireWords
    words[i] = w == 0 and 0xFFFF or w
  end
  rec.questionnaireWords = words
  return words
end

-- pokeemerald/src/easy_chat.c:2988 DidPlayerInputMysteryGiftPhrase
MysteryGift.MYSTERY_GIFT_PHRASE = { 521, 5131, 4144, 4138 }

function MysteryGift.isMysteryGiftPhrase(words)
  for i = 1, NUM_QUESTIONNAIRE_WORDS do
    if tonumber(type(words) == "table" and words[i]) ~= MysteryGift.MYSTERY_GIFT_PHRASE[i] then return false end
  end
  return true
end

local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

local function scriptStore(session)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local rt = package.loaded["src.core.game3.runtime"]
  local live = rt and rt.getSession and rt.getSession() or nil
  if Space and type(Space.store) == "table" and live ~= nil and session == live then return Space.store end
  if type(session) == "table" and type(session.store) == "table" then return session.store end
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
  return getFlag(session, flagNamed(session, familyRow(session).enableFlag))
end

-- pokefirered/src/event_data.c:122 EnableMysteryGift
function MysteryGift.enable(session)
  setFlag(session, flagNamed(session, familyRow(session).enableFlag), true)
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
  local first = flagNamed(session, "FLAG_MYSTERY_GIFT_DONE")
  for id = first, first + 15 do
    setFlag(session, id, false)
  end
end

-- pokefirered/src/event_data.c:152 ClearMysteryGiftVars
local function clearMysteryGiftVars(session)
  for _, name in ipairs(familyRow(session).giftVars) do
    setVar(session, varNamed(session, name), 0)
  end
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
function MysteryGift.receivedGiftFlag(flagId, session)
  flagId = num(flagId)
  if not isFlagIdInValidRange(flagId) then return nil end
  local first = flagNamed(session, "FLAG_RECEIVED_AURORA_TICKET")
  return first + (flagId - MysteryGift.WONDER_CARD_FLAG_OFFSET)
end

local function tracksById(card)
  local gift = type(card) == "table" and type(card.gift) == "table" and card.gift or {}
  return (gift.kind == "mon" or gift.kind == "egg") and not gift.doneFlag
end

local function deliveredIds(session)
  local rec = MysteryGift.ensure(session)
  rec.deliveredIds = type(rec.deliveredIds) == "table" and rec.deliveredIds or {}
  return rec.deliveredIds
end

function MysteryGift.wasDelivered(session, card)
  local id = num(type(card) == "table" and card.idNumber)
  for _, v in ipairs(deliveredIds(session)) do
    if num(v) == id then return true end
  end
  return false
end

-- pokefirered/src/mystery_gift.c:248 IsSavedWonderCardGiftNotReceived
function MysteryGift.isGiftNotReceived(session)
  if MysteryGift.validateSavedCard(session) and tracksById(MysteryGift.ensure(session).card) then
    return not MysteryGift.wasDelivered(session, MysteryGift.ensure(session).card)
  end
  local flagId = MysteryGift.getCardFlagId(session)
  local giftFlag = MysteryGift.receivedGiftFlag(flagId, session)
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
  setVar(session, wonderNewsStepVar(session), 0)
end

-- pokefirered/src/wonder_news.c:53 WonderNews_IncrementStepCounter
function MysteryGift.incrementNewsStepCounter(session)
  local data = MysteryGift.getSavedNewsMetadata(session)
  if num(data.rewardCounter) >= MAX_REWARD then
    local steps = getVar(session, wonderNewsStepVar(session)) + 1
    if steps >= NEWS_STEP_LIMIT then
      data.rewardCounter = 0
      steps = 0
    end
    setVar(session, wonderNewsStepVar(session), steps)
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
  if not getFlag(session, flagNamed(session, familyRow(session).newsEnableFlag))
    or not MysteryGift.validateSavedNews(session) then
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

-- pokefirered/src/mystery_gift_client.c:210 CLI_SAVE_NEWS
function MysteryGift.saveNewsIfNew(session, news)
  if MysteryGift.isNewsSameAsSaved(session, news) then return false, "had" end
  if not MysteryGift.saveNews(session, news) then return false, "invalid" end
  return true
end

-- pokefirered/src/mystery_gift_client.c:213
function MysteryGift.receiveNews(session, news, newsType)
  local ok, why = MysteryGift.saveNewsIfNew(session, news)
  if not ok then return false, why end
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
  local Rng = require("src.core.game3.rng")
  local otName = gift.otName
  if type(gift.otNames) == "table" and #gift.otNames > 0 then
    otName = gift.otNames[(Rng.Random() % #gift.otNames) + 1]
  end
  if otName then
    mon.ot = otName
    mon.otName = otName
  end
  if gift.otIdMax then
    mon.otId = (Rng.Random() % num(gift.otIdMax)) + 1
    mon.otSecretId = 0
  elseif gift.otId then
    mon.otId = num(gift.otId) % 65536
    mon.otSecretId = math.floor(num(gift.otId) / 65536) % 65536
  end
  if gift.secretIdRandom then mon.otSecretId = Rng.Random() end
  if gift.otGender == 2 then mon.otGender = Rng.Random() % 2
  elseif gift.otGender then mon.otGender = gift.otGender end
  local personality = gift.personality and num(gift.personality) or mon.personality
  -- pokefirered/src/pokemon.c:6062 IsShinyOtIdPersonality
  local function shiny(p)
    local bit = require("bit")
    local tid, sid = num(mon.otId) % 65536, num(mon.otSecretId) % 65536
    return bit.bxor(bit.bxor(tid, sid), bit.bxor(math.floor(p / 65536), p % 65536)) < 8
  end
  if not gift.personality and gift.shiny == "never" then
    while shiny(personality) do personality = Rng.Random32() % 0x100000000 end
  elseif not gift.personality and gift.shiny == "always" and not shiny(personality) then
    local bit = require("bit")
    local hi = math.floor(personality / 65536)
    local lo = bit.band(bit.bxor(bit.bxor(num(mon.otId) % 65536, num(mon.otSecretId) % 65536), hi), 0xFFF8)
      + personality % 8
    personality = hi * 65536 + lo
  end
  if personality ~= mon.personality then
    mon.personality = personality
    if Pokemon.natureId then mon.nature = Pokemon.natureId(mon.personality) end
    if Pokemon.abilityId then
      mon.ability = Pokemon.abilityId(species, mon.personality)
      mon.abilityId = mon.ability
    end
    if Pokemon.gender then mon.gender = Pokemon.gender(species, mon.personality) end
    if Pokemon.applyStats then Pokemon.applyStats(mon) end
  end
  if gift.heldItem and num(gift.heldItem) > 0 then
    mon.item, mon.heldItem = num(gift.heldItem), num(gift.heldItem)
  end
  -- pokefirered/src/scrcmd.c:2244 ScrCmd_setmonmodernfatefulencounter
  mon.modernFatefulEncounter = gift.fateful ~= false
  if gift.nationalRibbon then
    require("src.core.game3.rse.ribbons").set(mon, "national", 1)
  end
  -- pokefirered/data/mystery_event_msg.s:72 setmonmetlocation METLOC_FATEFUL_ENCOUNTER
  mon.metLocation = gift.metLocation or METLOC_FATEFUL_ENCOUNTER
  if gift.metLevel then mon.metLevel = gift.metLevel end
  if gift.metGame then mon.metGame = gift.metGame end
  if gift.ball then mon.pokeball = gift.ball end
  if gift.language then mon.language = gift.language end
  mon.moves = mon.moves or {}
  mon.pp = mon.pp or {}
  mon.maxPp = mon.maxPp or {}
  if gift.movesOnly then mon.moves, mon.pp, mon.maxPp = {}, {}, {} end
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
  local byId = tracksById(card)
  local receivedFlag = not byId and MysteryGift.receivedGiftFlag(card.flagId, session) or nil

  -- pokefirered/src/mystery_gift.c:248 IsSavedWonderCardGiftNotReceived
  if receivedFlag and getFlag(session, receivedFlag) then
    return MysteryGift.DELIVER_ALREADY
  end
  if byId and MysteryGift.wasDelivered(session, card) then return MysteryGift.DELIVER_ALREADY end
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
    local id = num(gift.slotVar, varNamed(session, "VAR_ALTERING_CAVE_WILD_SET"))
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
  if byId then table.insert(deliveredIds(session), num(card.idNumber)) end
  return MysteryGift.DELIVER_GIVEN
end

-- pokefirered/src/mystery_gift_client.c:208
function MysteryGift.receiveCard(session, card)
  if not MysteryGift.saveCard(session, card) then return false end
  MysteryGift.enable(session)
  MysteryGift.runReceiveScript(session)
  return true
end

MysteryGift.RSE_TICKET_SCRIPTS = {
  -- pokeemerald/data/scripts/gift_aurora_ticket.inc:1
  ITEM_AURORA_TICKET = "aurora",
  -- pokeemerald/data/scripts/gift_mystic_ticket.inc:1
  ITEM_MYSTIC_TICKET = "mystic",
  -- pokeemerald/data/scripts/gift_old_sea_map.inc:1
  ITEM_OLD_SEA_MAP = "oldSeaMap",
  -- pokeemerald/data/scripts/cable_club.inc:33
  ITEM_EON_TICKET = "eon",
}

function MysteryGift.ramScriptId(session, card)
  card = card or MysteryGift.getSavedCard(session)
  if type(card) ~= "table" or MysteryGift.familyOf(session) ~= "rse" then return nil end
  local gift = type(card.gift) == "table" and card.gift or {}
  if gift.script then return gift.script end
  if gift.kind ~= "item" then return nil end
  local C = consts(session)
  for name, id in pairs(MysteryGift.RSE_TICKET_SCRIPTS) do
    if C:id("items", name) == num(gift.item) then return id end
  end
  return nil
end

-- pokeemerald/src/field_specials.c:3630 ShouldDistributeEonTicket
function MysteryGift.runReceiveScript(session)
  if MysteryGift.ramScriptId(session) ~= "eon" then return false end
  local Bag = require("src.core.game3.bag")
  local C = consts(session)
  if type(session) == "table" and session.bag and Bag.has(session.bag, C:require("items", "ITEM_EON_TICKET"), 1) then
    return false
  end
  if getFlag(session, C:require("flags", "FLAG_ENABLE_SHIP_SOUTHERN_ISLAND")) then return false end
  setVar(session, C:require("vars", "VAR_DISTRIBUTE_EON_TICKET"), 1)
  return true
end

local TEXT_KEYS = {
  frlg = {
    -- pokefirered/data/mystery_event_msg.s:260
    noRoom = { default = "sText_AuroraTicketNoPlace", ITEM_MYSTIC_TICKET = "sText_MysticTicketNoPlace" },
    -- pokefirered/data/mystery_event_msg.s:256
    done = { default = "sText_AuroraTicketGot", ITEM_MYSTIC_TICKET = "sText_MysticTicketGot" },
    -- pokefirered/data/mystery_event_msg.s:108
    partyFull = "sText_FullParty",
  },
  rse = {
    -- pokeemerald/data/scripts/gift_aurora_ticket.inc:24
    noRoom = { default = "sText_AuroraTicketBagFull", ITEM_MYSTIC_TICKET = "sText_MysticTicketBagFull",
      ITEM_OLD_SEA_MAP = "sText_MysteryGiftOldSeaMapBagFull" },
    -- pokeemerald/data/scripts/gift_aurora_ticket.inc:31
    done = { default = "sText_AuroraTicketThankYou", ITEM_MYSTIC_TICKET = "sText_MysticTicketThankYou",
      ITEM_OLD_SEA_MAP = "sText_MysteryGiftOldSeaMapThankYou" },
    -- pokeemerald/data/scripts/gift_pichu.inc:24
    partyFull = "sText_FullParty",
    -- pokeemerald/data/scripts/gift_pichu.inc:13
    egg = "sText_MysteryGiftEgg",
    -- pokeemerald/data/scripts/gift_altering_cave.inc:9
    var = "sText_MysteryGiftAlteringCave",
    -- pokeemerald/data/scripts/gift_battle_card.inc:9
    statWon = "sText_MysteryGiftBattleCountCard_WonPrize",
    -- pokeemerald/data/scripts/gift_battle_card.inc:20
    statInfo = "sText_MysteryGiftBattleCountCard",
    -- pokeemerald/data/scripts/gift_stamp_card.inc:11
    stamp = "sText_MysteryGiftStampCard",
  },
}
MysteryGift.TEXT_KEYS = TEXT_KEYS

local function byItem(session, map, item)
  local C = consts(session)
  for name, key in pairs(map) do
    if name ~= "default" and C:id("items", name) == num(item) then return key end
  end
  return map.default
end

function MysteryGift.deliveryTextKey(session, code, card)
  card = card or MysteryGift.getSavedCard(session)
  local keys = TEXT_KEYS[MysteryGift.familyOf(session)] or TEXT_KEYS.frlg
  local gift = type(card) == "table" and type(card.gift) == "table" and card.gift or {}
  if code == MysteryGift.DELIVER_NO_ROOM then return byItem(session, keys.noRoom, gift.item) end
  if code == MysteryGift.DELIVER_PARTY_FULL then return keys.partyFull end
  if code == MysteryGift.DELIVER_GIVEN then
    if gift.requireStat and keys.statWon then return keys.statWon end
    if gift.kind == "egg" and keys.egg then return keys.egg end
    if gift.kind == "var" and keys.var then return keys.var end
    return nil
  end
  if gift.requireStat and keys.statInfo then return keys.statInfo end
  if type(card) == "table" and num(card.type) == MysteryGift.CARD_TYPE_STAMP and keys.stamp then return keys.stamp end
  return byItem(session, keys.done, gift.item)
end

function MysteryGift.fallbackTextKey(session, card)
  card = card or MysteryGift.getSavedCard(session)
  local keys = TEXT_KEYS[MysteryGift.familyOf(session)] or TEXT_KEYS.frlg
  local gift = type(card) == "table" and type(card.gift) == "table" and card.gift or {}
  return byItem(session, keys.done, gift.item)
end

function MysteryGift.cardHaveFlags(family)
  if family == "rse" then
    local C = require("src.core.game3.constants").of("emerald")
    local function f(name) return C:require("flags", name) end
    return {
      -- pokeemerald/data/scripts/gift_aurora_ticket.inc:5
      rse_aurora_ticket = { f("FLAG_RECEIVED_AURORA_TICKET"), f("FLAG_BATTLED_DEOXYS") },
      -- pokeemerald/data/scripts/gift_mystic_ticket.inc:5
      rse_mystic_ticket = { f("FLAG_RECEIVED_MYSTIC_TICKET"), f("FLAG_CAUGHT_LUGIA"), f("FLAG_CAUGHT_HO_OH") },
      -- pokeemerald/data/scripts/gift_old_sea_map.inc:5
      rse_old_sea_map = { f("FLAG_RECEIVED_OLD_SEA_MAP"), f("FLAG_CAUGHT_MEW") },
    }
  end
  return {
    -- pokefirered/data/mystery_event_msg.s:270
    mystic_ticket = { FLAG_RECEIVED_MYSTIC_TICKET, FLAG_FOUGHT_LUGIA, FLAG_FOUGHT_HO_OH },
    -- pokefirered/data/mystery_event_msg.s:212
    aurora_ticket = { FLAG_RECEIVED_AURORA_TICKET, FLAG_FOUGHT_DEOXYS },
  }
end

MysteryGift.UI_TEXT = {
  rse = {
    -- pokeemerald/src/mystery_gift_menu.c:493
    gText_MysteryGift2 = "gText_MysteryGift",
    -- pokeemerald/src/union_room.c:2275
    gText_UR_SearchingForWirelessSystemWait = "sText_SearchingForWirelessSystemWait",
    -- pokeemerald/src/union_room.c:2393
    gText_UR_WirelessSearchCanceled = "sText_WirelessSearchCanceled",
    -- pokeemerald/src/union_room.c:2402
    gTexts_UR_NoWonderShared = "sNoWonderSharedTexts",
  },
}

function MysteryGift.uiTextKey(key, session)
  local map = MysteryGift.UI_TEXT[MysteryGift.familyOf(session)]
  return map and map[key] or key
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

local function rowFamily(raw)
  return type(raw) == "table" and type(raw.family) == "string" and raw.family or "frlg"
end

local function familyVersion(family)
  if family == MysteryGift.familyOf(nil) then return versionOf(nil) end
  return MysteryGift.FAMILY_VERSIONS[family] and MysteryGift.FAMILY_VERSIONS[family][1] or "firered"
end

-- pokeruby/src/mystery_event_script.c:46 CheckCompatibility
function MysteryGift.eventHeaderOk(bytes, version)
  local Event = require("src.core.game3.rs.mystery_event")
  if type(bytes) ~= "string" or #bytes < 17 or #bytes > Event.MAX_BYTES or bytes:byte(1) ~= 1 then return false end
  local bit = require("bit")
  local function u16(at) return bytes:byte(at) + bytes:byte(at + 1) * 256 end
  local function u32(at) return u16(at) + u16(at + 2) * 65536 end
  local mask = ({ ruby = 0x80, sapphire = 0x100 })[version] or 0x180
  return bit.band(u16(6), 2) ~= 0 and bit.band(u32(8), 2) ~= 0 and bit.band(u16(12), 4) ~= 0
    and bit.band(u32(14), mask) ~= 0
end

local EVENT_OP_SIZE = { [0] = 1, 17, 1, 6, 2, 5, 12, 5, 3, 1, 2, 5, 5, 5, 1, 13, 13 }

-- pokeruby/src/mystery_event_script.c:356 MEScrCmd_setrecordmixinggift
function MysteryGift.eventRecordMixingItem(bytes)
  if type(bytes) ~= "string" then return nil end
  local pos = 1
  while pos <= #bytes do
    local op = bytes:byte(pos)
    local size = EVENT_OP_SIZE[op]
    if not size or op == 2 then return nil end
    if op == 11 and pos + 4 <= #bytes then
      local unk, qty = bytes:byte(pos + 1), bytes:byte(pos + 2)
      local item = bytes:byte(pos + 3) + bytes:byte(pos + 4) * 256
      if unk ~= 0 and qty ~= 0 and item ~= 0 then return item end
    end
    pos = pos + size
  end
  return nil
end

local function parseEvents(data, version)
  local out = {}
  if type(data.events) ~= "table" then return out end
  local Base64 = require("src.core.Base64")
  for _, raw in ipairs(data.events) do
    local ok, bytes = pcall(Base64.decode, type(raw) == "table" and raw.payload or nil)
    if ok and rowFamily(raw) == "rs" and MysteryGift.offeredIn(copyVersions(raw.versions), version)
      and MysteryGift.eventHeaderOk(bytes, version) then
      out[#out + 1] = {
        key = type(raw.key) == "string" and raw.key or tostring(#out + 1),
        label = clampText(raw.title, WONDER_CARD_TEXT_LENGTH),
        bytes = bytes,
      }
    end
  end
  return out
end

function MysteryGift.parseFeed(payload, family, gameVersion)
  family = family or MysteryGift.familyOf(nil)
  local version = familyVersion(family)
  local Json = require("src.link.Json")
  local data = Json.decode(payload)
  if type(data) ~= "table" or data.v ~= MysteryGift.FEED_VERSION then return nil, "bad_feed" end
  if type(data.cards) ~= "table" or type(data.news) ~= "table" then return nil, "bad_feed" end
  local out = { issued = num(data.issued), cards = {}, news = {} }
  if family == "rs" then out.events = parseEvents(data, gameVersion) end
  for _, raw in ipairs(data.cards) do
    local card = rowFamily(raw) == family and MysteryGift.normalizeCard(raw, gameVersion or version) or nil
    if card and validateCard(card) and isFlagIdInValidRange(card.flagId) and card.idNumber ~= 0
      and MysteryGift.offeredIn(card.versions, gameVersion) then
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

function MysteryGift.verifyFeed(feed, family, gameVersion)
  if type(feed) ~= "table" or type(feed.payload) ~= "string" or type(feed.sig) ~= "string" then
    return nil, "bad_feed"
  end
  local Ed25519 = require("src.core.crypto.ed25519")
  if not Ed25519.verify(MysteryGift.GIFT_PUBKEY, feed.payload, feed.sig) then
    return nil, "bad_signature"
  end
  return MysteryGift.parseFeed(feed.payload, family, gameVersion)
end

function MysteryGift.feedPath(family, gameVersion)
  local q = {}
  if family ~= "frlg" then q[#q + 1] = "family=" .. tostring(family) end
  if gameVersion then q[#q + 1] = "version=" .. tostring(gameVersion) end
  if #q == 0 then return MysteryGift.FEED_PATH end
  return MysteryGift.FEED_PATH .. "?" .. table.concat(q, "&")
end

function MysteryGift.fetchOnline(opts)
  opts = opts or {}
  local family = opts.family or MysteryGift.familyOf(opts.session)
  local gameVersion = opts.version
  if gameVersion == nil then
    gameVersion = versionOf(opts.session)
    if not MysteryGift.offeredIn(MysteryGift.FAMILY_VERSIONS[family], gameVersion) then gameVersion = nil end
  end
  local client = opts.client
  if not client then
    local okS, SyncClient = pcall(require, "src.sync.SyncClient")
    if not okS then return { status = "error", reason = "offline" } end
    local okN, made = pcall(SyncClient.new, { transport = opts.transport })
    if not okN then return { status = "error", reason = "offline" } end
    client = made
  end
  local okR, handle = pcall(client.send, client, "GET", MysteryGift.feedPath(family, gameVersion), nil,
    { noAuth = true, maxSeconds = MysteryGift.FETCH_SECONDS })
  if not okR or handle == nil then
    return { status = "error", reason = "offline", client = client, family = family, version = gameVersion }
  end
  return { status = "pending", client = client, handle = handle, family = family, version = gameVersion }
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
  local list, why = MysteryGift.verifyFeed(res.data, job.family, job.version)
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
  local session = { store = store, modData = save.modData,
    version = type(save.version) == "string" and save.version or nil, bag = save.bag }
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
