#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_gift_model_test")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local MysteryGift = require("src.core.game3.mystery_gift")
local Schema = require("src.core.game3.save_schema_firered")
local Bag = require("src.core.game3.bag")

local FLAG_ENABLE_SHIP_NAVEL_ROCK = 0x84A
local FLAG_ENABLE_SHIP_BIRTH_ISLAND = 0x84B
local FLAG_RECEIVED_MYSTIC_TICKET = 0x2A8
local FLAG_RECEIVED_AURORA_TICKET = 0x2A7

local function newSession()
  return Schema.newGame({ rngSeed = 0x1234 })
end

local function builtin(key)
  for _, entry in ipairs(MysteryGift.builtins()) do
    if entry.key == key then return entry end
  end
  return nil
end

print("[test] 1. CalcCRC16WithTable")
-- pokefirered/src/util.c:250 CalcCRC16WithTable
eq(MysteryGift.crc16(""), 0xEEDE, "crc16 of an empty record")
check(MysteryGift.crc16("MYSTIC") ~= MysteryGift.crc16("AURORA"), "crc16 separates two records")

print("[test] 2. Card and news round trip through a save")
local session = newSession()
check(MysteryGift.receiveCard(session, builtin("mystic_ticket").card), "the Mystic Ticket card saves")
check(MysteryGift.receiveNews(session, {
  id = 7,
  sendType = MysteryGift.SEND_TYPE_ALLOWED,
  bgType = 1,
  titleText = "BERRY NEWS",
  bodyText = { "A friend sent you news." },
}, MysteryGift.WONDER_NEWS_RECV_FRIEND), "the Wonder News saves")

local restored = Schema.fromSaveTable(Schema.toSaveTable(session))
check(MysteryGift.validateSavedCard(restored), "the saved card survives the save round trip")
check(MysteryGift.validateSavedNews(restored), "the saved news survives the save round trip")
eq(MysteryGift.getCardFlagId(restored), MysteryGift.WONDER_CARD_FLAG_OFFSET + 1,
  "the restored card keeps its flagId")
eq(MysteryGift.getSavedCard(restored).titleText, "MYSTIC TICKET", "the restored card keeps its title")
eq(MysteryGift.getSavedNews(restored).id, 7, "the restored news keeps its id")
check(MysteryGift.isEnabled(restored), "FLAG_SYS_MYSTERY_GIFT_ENABLED survives the round trip")

print("[test] 3. Validation rejects a malformed card")
-- pokefirered/src/mystery_gift.c:191 ValidateWonderCard
local good = builtin("aurora_ticket").card
local function reject(mutate, label)
  local card = MysteryGift.normalizeCard(good)
  mutate(card)
  local s = newSession()
  check(not MysteryGift.saveCard(s, card), label)
  check(not MysteryGift.validateSavedCard(s), label .. " leaves no saved card")
end
reject(function(c) c.flagId = 0 end, "flagId 0 is rejected")
reject(function(c) c.type = MysteryGift.CARD_TYPE_COUNT end, "an out of range card type is rejected")
reject(function(c) c.sendType = 3 end, "an unknown sendType is rejected")
reject(function(c) c.bgType = MysteryGift.NUM_WONDER_BGS end, "an out of range bgType is rejected")
reject(function(c) c.maxStamps = MysteryGift.MAX_STAMP_CARD_STAMPS + 1 end,
  "more stamps than the card can hold is rejected")

local tampered = newSession()
MysteryGift.receiveCard(tampered, good)
check(MysteryGift.validateSavedCard(tampered), "the aurora card validates before tampering")
MysteryGift.getSavedCard(tampered).titleText = "FREE MASTER BALL"
check(not MysteryGift.validateSavedCard(tampered), "an edited card fails its CRC")

print("[test] 4. The tickets set the two ship flags")
-- pokefirered/data/mystery_event_msg.s:266 MysteryEventScript_MysticTicket
local mystic = newSession()
MysteryGift.receiveCard(mystic, builtin("mystic_ticket").card)
check(MysteryGift.isGiftNotReceived(mystic), "the Mystic Ticket gift is pending before delivery")
eq(MysteryGift.deliverGift(mystic), MysteryGift.DELIVER_GIVEN, "the Mystic Ticket is handed over")
check(Bag.has(mystic.bag, MysteryGift.ITEM_MYSTIC_TICKET, 1), "the MYSTIC TICKET is in the bag")
check(MysteryGift.getFlag(mystic, FLAG_ENABLE_SHIP_NAVEL_ROCK), "FLAG_ENABLE_SHIP_NAVEL_ROCK is set")
check(MysteryGift.getFlag(mystic, FLAG_RECEIVED_MYSTIC_TICKET), "FLAG_RECEIVED_MYSTIC_TICKET is set")
check(not MysteryGift.getFlag(mystic, FLAG_ENABLE_SHIP_BIRTH_ISLAND),
  "the Mystic Ticket leaves Birth Island alone")
check(not MysteryGift.isGiftNotReceived(mystic), "the card reads as collected afterwards")
eq(MysteryGift.deliverGift(mystic), MysteryGift.DELIVER_ALREADY, "a second visit hands over nothing")

-- pokefirered/data/mystery_event_msg.s:208 MysteryEventScript_AuroraTicket
local aurora = newSession()
MysteryGift.receiveCard(aurora, builtin("aurora_ticket").card)
eq(MysteryGift.deliverGift(aurora), MysteryGift.DELIVER_GIVEN, "the Aurora Ticket is handed over")
check(Bag.has(aurora.bag, MysteryGift.ITEM_AURORA_TICKET, 1), "the AURORA TICKET is in the bag")
check(MysteryGift.getFlag(aurora, FLAG_ENABLE_SHIP_BIRTH_ISLAND), "FLAG_ENABLE_SHIP_BIRTH_ISLAND is set")
check(MysteryGift.getFlag(aurora, FLAG_RECEIVED_AURORA_TICKET), "FLAG_RECEIVED_AURORA_TICKET is set")

-- pokefirered/data/mystery_event_msg.s:271 vgoto_if_set FLAG_FOUGHT_LUGIA
local fought = newSession()
MysteryGift.receiveCard(fought, builtin("mystic_ticket").card)
MysteryGift.setFlag(fought, 0x2F2, true)
eq(MysteryGift.deliverGift(fought), MysteryGift.DELIVER_ALREADY,
  "a player who already fought LUGIA gets no second ticket")
check(not Bag.has(fought.bag, MysteryGift.ITEM_MYSTIC_TICKET, 1), "and no ticket reaches the bag")

print("[test] 5. An event mon carries the card's personality and OT")
local eventCard = MysteryGift.normalizeCard(builtin("surf_pichu").card)
eventCard.gift.personality = 0x12345678
eventCard.gift.otName = "GF"
eventCard.gift.otId = 30518
local egg = newSession()
MysteryGift.receiveCard(egg, eventCard)
eq(MysteryGift.deliverGift(egg), MysteryGift.DELIVER_GIVEN, "the event egg is handed over")
local mon = egg.party[#egg.party]
local partyAfterGift = #egg.party
check(mon ~= nil, "the event mon reached the party")
eq(mon and mon.personality, 0x12345678, "the mon carries the card's personality")
eq(mon and mon.otName, "GF", "the mon carries the card's OT name")
eq(mon and mon.otId, 30518, "the mon carries the card's OT id")
eq(mon and mon.species, 172, "the mon is the card's species")
check(mon and mon.isEgg, "the Surfing Pichu card gives an egg")
-- pokefirered/data/mystery_event_msg.s:72 setmonmetlocation METLOC_FATEFUL_ENCOUNTER
eq(mon and mon.metLocation, 0xFF, "the mon is met at METLOC_FATEFUL_ENCOUNTER")
check(mon and mon.modernFatefulEncounter, "the mon is a modern fateful encounter")
-- pokefirered/data/mystery_event_msg.s:81 setmonmove slot, 2, MOVE_SURF
eq(mon and mon.moves and mon.moves[3], 57, "the egg knows SURF in the third slot")
-- pokefirered/data/mystery_event_msg.s:42 vgoto_if_unset FLAG_MYSTERY_GIFT_DONE
eq(MysteryGift.deliverGift(egg), MysteryGift.DELIVER_ALREADY,
  "FLAG_MYSTERY_GIFT_DONE stops a second egg")
eq(#egg.party, partyAfterGift, "the party did not grow a second time")

local full = newSession()
MysteryGift.receiveCard(full, eventCard)
for _ = 1, 6 do full.party[#full.party + 1] = { species = 1, level = 5 } end
eq(MysteryGift.deliverGift(full), MysteryGift.DELIVER_PARTY_FULL,
  "a full party is told to come back later")

print("[test] 6. Stamp card and battle card stats")
-- pokefirered/src/mystery_gift.c:307 MysteryGift_TrySaveStamp
local stampSession = newSession()
MysteryGift.receiveCard(stampSession, builtin("stamp_card").card)
eq(MysteryGift.getCardStat(stampSession, MysteryGift.CARD_STAT_MAX_STAMPS),
  MysteryGift.MAX_STAMP_CARD_STAMPS, "the stamp card reports its maximum")
check(MysteryGift.trySaveStamp(stampSession, { species = 25, id = 3 }), "a new stamp is accepted")
check(not MysteryGift.trySaveStamp(stampSession, { species = 25, id = 3 }), "the same stamp is refused")
check(not MysteryGift.trySaveStamp(stampSession, { species = 0, id = 4 }), "a speciesless stamp is refused")
eq(MysteryGift.getCardStat(stampSession, MysteryGift.CARD_STAT_NUM_STAMPS), 1, "one stamp is counted")
-- pokefirered/src/field_specials.c:1955 GetMysteryGiftCardStat
eq(MysteryGift.getCardStatForScript(stampSession, MysteryGift.GET_NUM_STAMPS), 1,
  "GET_NUM_STAMPS reaches the same count")

-- pokefirered/src/mystery_gift.c:561 MysteryGift_TryIncrementStat
local battle = newSession()
MysteryGift.receiveCard(battle, builtin("battle_card").card)
MysteryGift.tryIncrementStat(battle, MysteryGift.CARD_STAT_BATTLES_WON, 111)
eq(MysteryGift.getCardStat(battle, MysteryGift.CARD_STAT_BATTLES_WON), 0,
  "stats do not move until the card enables them")
check(MysteryGift.tryEnableStatsByFlagId(battle, MysteryGift.getCardFlagId(battle)),
  "the battle card enables stats by its own flagId")
MysteryGift.tryIncrementStat(battle, MysteryGift.CARD_STAT_BATTLES_WON, 111)
MysteryGift.tryIncrementStat(battle, MysteryGift.CARD_STAT_BATTLES_WON, 111)
eq(MysteryGift.getCardStat(battle, MysteryGift.CARD_STAT_BATTLES_WON), 1,
  "the same trainer only counts once")
-- pokefirered/data/mystery_event_msg.s:166 three wins before the prize
eq(MysteryGift.deliverGift(battle), MysteryGift.DELIVER_NOTHING,
  "the battle card gives no prize below three wins")
MysteryGift.tryIncrementStat(battle, MysteryGift.CARD_STAT_BATTLES_WON, 222)
MysteryGift.tryIncrementStat(battle, MysteryGift.CARD_STAT_BATTLES_WON, 333)
eq(MysteryGift.getCardStat(battle, MysteryGift.CARD_STAT_BATTLES_WON), 3, "three trainers, three wins")
eq(MysteryGift.deliverGift(battle), MysteryGift.DELIVER_GIVEN, "three wins pay the prize")
MysteryGift.disableStats()

print("[test] 7. Wonder News rewards")
-- pokefirered/src/wonder_news.c:68 WonderNews_GetRewardInfo
local newsSession = newSession()
local newsRecord = {
  id = 3,
  sendType = MysteryGift.SEND_TYPE_ALLOWED,
  bgType = 0,
  titleText = "NEWS",
  bodyText = { "Hello." },
}
check(MysteryGift.saveNews(newsSession, newsRecord), "the news saves")
local rewardType, item = MysteryGift.getNewsRewardInfo(newsSession)
eq(rewardType, MysteryGift.NEWS_REWARD_NONE, "no reward while Mystery Gift is disabled")
MysteryGift.enable(newsSession)
MysteryGift.setNewsReward(newsSession, MysteryGift.WONDER_NEWS_RECV_FRIEND)
rewardType, item = MysteryGift.getNewsRewardInfo(newsSession)
eq(rewardType, MysteryGift.NEWS_REWARD_RECV_SMALL, "news from a friend is a small reward")
check(item ~= nil and item >= 133 and item <= 162, "the reward is a berry, got " .. tostring(item))
rewardType = MysteryGift.getNewsRewardInfo(newsSession)
eq(rewardType, MysteryGift.NEWS_REWARD_WAITING, "the reward is spent after one visit")
check(not MysteryGift.isNewsSameAsSaved(newsSession, { id = 4, titleText = "NEWS" }),
  "a different news record does not match the saved one")
check(MysteryGift.isNewsSameAsSaved(newsSession, newsRecord), "the same news record matches")

print("[test] 8. The drop-in card file")
local parsed = MysteryGift.parse([[
# a dropped in Wonder Card
[card]
flagId = 1003
type = 0
bgType = 1
sendType = 0
maxStamps = 0
iconSpecies = 25
title = SURPRISE
subtitle = FROM A FRIEND
body = Line one.
body = Line two.
gift.kind = item
gift.item = 13
gift.quantity = 2
gift.setflag = 0x84A

[news]
id = 12
sendType = 1
bgType = 0
title = NEWS FILE
body = Something happened.
]])
check(parsed ~= nil, "the drop-in file parses")
eq(parsed and parsed.card and parsed.card.flagId, 1003, "the parsed card keeps its flagId")
eq(parsed and parsed.card and parsed.card.titleText, "SURPRISE", "the parsed card keeps its title")
eq(parsed and parsed.card and parsed.card.bodyText[2], "Line two.", "the parsed card keeps its body lines")
eq(parsed and parsed.card and parsed.card.gift.item, 13, "the parsed card keeps its gift item")
eq(parsed and parsed.card and parsed.card.gift.setFlags[1], 0x84A, "the parsed card keeps its gift flag")
eq(parsed and parsed.news and parsed.news.id, 12, "the parsed news keeps its id")
local dropped = newSession()
check(MysteryGift.receiveCard(dropped, parsed.card), "the parsed card saves")
eq(MysteryGift.deliverGift(dropped), MysteryGift.DELIVER_GIVEN, "the parsed card hands its item over")
eq(Bag.get(dropped.bag, 13), 2, "both POTIONs arrived")
local bad, err = MysteryGift.parse("[card]\nflagId = 0\ntype = 0\n")
check(bad == nil, "a card with no flagId is refused by the parser")
check(err ~= nil, "the parser says why, got " .. tostring(err))

print("[test] 9. The script specials")
local fakeRuntime = { getSession = function() return nil end }
package.loaded["src.core.game3.runtime"] = fakeRuntime
local Natives = require("src.core.game3.scripting.natives")
local specials = require("src.core.game3.scripting.natives_gift").SPECIAL_IDS
local scriptSession = newSession()
fakeRuntime.getSession = function() return scriptSession end
local ctx = { specialVars = {}, stringVars = {} }
local _, value, known = Natives.special(ctx, specials.ValidateSavedWonderCard, {})
check(known, "ValidateSavedWonderCard is a known special")
eq(value, 0, "no card saved reads as FALSE")
MysteryGift.receiveCard(scriptSession, builtin("stamp_card").card)
MysteryGift.trySaveStamp(scriptSession, { species = 25, id = 3 })
_, value = Natives.special(ctx, specials.ValidateSavedWonderCard, {})
eq(value, 1, "a saved card reads as TRUE")
ctx.specialVars[0x800D] = MysteryGift.GET_NUM_STAMPS
_, value = Natives.special(ctx, specials.GetMysteryGiftCardStat, {})
eq(value, 1, "GetMysteryGiftCardStat returns the stamp count")
ctx.specialVars[0x800D] = MysteryGift.GET_MAX_STAMPS
_, value = Natives.special(ctx, specials.GetMysteryGiftCardStat, {})
eq(value, MysteryGift.MAX_STAMP_CARD_STAMPS, "GetMysteryGiftCardStat returns the stamp maximum")

MysteryGift.enable(scriptSession)
MysteryGift.saveNews(scriptSession, newsRecord)
MysteryGift.setNewsReward(scriptSession, MysteryGift.WONDER_NEWS_RECV_WIRELESS)
_, value = Natives.special(ctx, specials.WonderNews_GetRewardInfo, {})
eq(value, MysteryGift.NEWS_REWARD_RECV_BIG, "WonderNews_GetRewardInfo returns the reward type")
check((ctx.specialVars[0x800D] or 0) >= 133, "and leaves the berry in VAR_RESULT, got "
  .. tostring(ctx.specialVars[0x800D]))

print("[test] 10. ClearMysteryGift")
-- pokefirered/src/mystery_gift.c:55
MysteryGift.clear(scriptSession)
check(not MysteryGift.validateSavedCard(scriptSession), "the card is gone")
check(not MysteryGift.validateSavedNews(scriptSession), "the news is gone")
eq(MysteryGift.getCardStat(scriptSession, MysteryGift.CARD_STAT_NUM_STAMPS), 0, "the stamps are gone")

if failed == 0 then
  print("PASS game3_gift_model")
  os.exit(0)
else
  print("FAIL game3_gift_model failures=" .. failed)
  os.exit(1)
end
