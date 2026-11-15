local MysteryGift = require("src.core.game3.mystery_gift")

local M = {}

local FLAG_MYSTERY_GIFT_DONE = 0x3D8
local FLAG_ENABLE_SHIP_NAVEL_ROCK = 0x84A
local FLAG_ENABLE_SHIP_BIRTH_ISLAND = 0x84B
local FLAG_RECEIVED_AURORA_TICKET = 0x2A7
local FLAG_RECEIVED_MYSTIC_TICKET = 0x2A8
local FLAG_FOUGHT_DEOXYS = 0x2E4
local FLAG_FOUGHT_LUGIA = 0x2F2
local FLAG_FOUGHT_HO_OH = 0x2F3
local VAR_ALTERING_CAVE_WILD_SET = 0x4024
local VAR_EVENT_PICHU_SLOT = 0x40B5

local function bodyOf(...)
  return { ... }
end

local rseBuiltins

-- pokefirered/data/mystery_event_msg.s:1
function M.cards(family)
  family = family or MysteryGift.familyOf(nil)
  if family == "rse" then return rseBuiltins() end
  return {
    {
      key = "mystic_ticket",
      label = "MYSTIC TICKET",
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 1,
        idNumber = 1,
        iconSpecies = 0,
        type = MysteryGift.CARD_TYPE_GIFT,
        bgType = 2,
        sendType = MysteryGift.SEND_TYPE_DISALLOWED,
        maxStamps = 0,
        titleText = "MYSTIC TICKET",
        subtitleText = "MYSTERY GIFT",
        -- pokefirered/data/mystery_event_msg.s:303 sText_MysticTicket2
        bodyText = bodyOf(
          "Thank you for using the MYSTERY",
          "GIFT System.",
          "There is a ticket here for you.",
          "It is for use at VERMILION CITY port."),
        footerLine1Text = "Speak to the deliveryman",
        footerLine2Text = "at a POKéMON CENTER.",
        versions = { "firered", "leafgreen" },
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
      label = "AURORA TICKET",
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET,
        idNumber = 2,
        iconSpecies = 0,
        type = MysteryGift.CARD_TYPE_GIFT,
        bgType = 3,
        sendType = MysteryGift.SEND_TYPE_DISALLOWED,
        maxStamps = 0,
        titleText = "AURORA TICKET",
        subtitleText = "MYSTERY GIFT",
        -- pokefirered/data/mystery_event_msg.s:244 sText_AuroraTicket1
        bodyText = bodyOf(
          "Thank you for using the MYSTERY",
          "GIFT System.",
          "There is a ticket here for you.",
          "It is for use at VERMILION CITY port."),
        footerLine1Text = "Speak to the deliveryman",
        footerLine2Text = "at a POKéMON CENTER.",
        versions = { "firered", "leafgreen" },
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
      label = "SURFING PICHU EGG",
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 3,
        idNumber = 3,
        iconSpecies = 172,
        type = MysteryGift.CARD_TYPE_GIFT,
        bgType = 1,
        sendType = MysteryGift.SEND_TYPE_DISALLOWED,
        maxStamps = 0,
        titleText = "POKéMON EGG",
        subtitleText = "MYSTERY GIFT",
        -- pokefirered/data/mystery_event_msg.s:100 sText_MysteryGiftEgg
        bodyText = bodyOf(
          "From the POKéMON CENTER we",
          "have a gift, a POKéMON EGG!",
          "Please raise it with love and",
          "kindness."),
        footerLine1Text = "Speak to the deliveryman",
        footerLine2Text = "at a POKéMON CENTER.",
        versions = { "firered", "leafgreen" },
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
      label = "STAMP CARD",
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 4,
        idNumber = 4,
        iconSpecies = 0,
        type = MysteryGift.CARD_TYPE_STAMP,
        bgType = 4,
        sendType = MysteryGift.SEND_TYPE_ALLOWED,
        maxStamps = MysteryGift.MAX_STAMP_CARD_STAMPS,
        titleText = "STAMP CARD",
        subtitleText = "MYSTERY GIFT",
        -- pokefirered/data/mystery_event_msg.s:34 sText_MysteryGiftStampCard
        bodyText = bodyOf(
          "Thank you for using the STAMP CARD",
          "System.",
          "Trade with other TRAINERS to fill",
          "your STAMP CARD."),
        footerLine1Text = "Speak to the deliveryman",
        footerLine2Text = "at a POKéMON CENTER.",
        versions = { "firered", "leafgreen" },
        gift = { kind = "none" },
      },
    },
    {
      key = "battle_card",
      label = "BATTLE COUNT CARD",
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 5,
        idNumber = 5,
        iconSpecies = 0,
        type = MysteryGift.CARD_TYPE_LINK_STAT,
        bgType = 5,
        sendType = MysteryGift.SEND_TYPE_ALLOWED,
        maxStamps = 0,
        titleText = "BATTLE COUNT CARD",
        subtitleText = "MYSTERY GIFT",
        -- pokefirered/data/mystery_event_msg.s:187 sText_MysteryGiftBattleCountCard
        bodyText = bodyOf(
          "Your BATTLE COUNT CARD keeps",
          "track of your battle record against",
          "TRAINERS with the same CARD.",
          "Look for them and battle!"),
        footerLine1Text = "Speak to the deliveryman",
        footerLine2Text = "at a POKéMON CENTER.",
        versions = { "firered", "leafgreen" },
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
      label = "ALTERING CAVE",
      card = {
        flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 6,
        idNumber = 6,
        iconSpecies = 0,
        type = MysteryGift.CARD_TYPE_GIFT,
        bgType = 6,
        sendType = MysteryGift.SEND_TYPE_DISALLOWED,
        maxStamps = 0,
        titleText = "ALTERING CAVE",
        subtitleText = "MYSTERY GIFT",
        bodyText = bodyOf(
          "The POKéMON living in ALTERING",
          "CAVE have changed.",
          "Go and see what turns up",
          "on SIX ISLAND."),
        footerLine1Text = "Speak to the deliveryman",
        footerLine2Text = "at a POKéMON CENTER.",
        versions = { "firered", "leafgreen" },
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

local function rseCard(key, label, t)
  t.iconSpecies = t.iconSpecies or 0
  t.type = t.type or MysteryGift.CARD_TYPE_GIFT
  t.sendType = t.sendType or MysteryGift.SEND_TYPE_DISALLOWED
  t.maxStamps = t.maxStamps or 0
  t.titleText = t.titleText or label
  t.subtitleText = t.subtitleText or "MYSTERY GIFT"
  t.footerLine1Text = t.footerLine1Text or "Speak to the deliveryman"
  t.footerLine2Text = t.footerLine2Text or "at a POKéMON CENTER."
  t.versions = t.versions or { "emerald" }
  return { key = key, family = "rse", label = label, card = t }
end

function rseBuiltins()
  local C = require("src.core.game3.constants").of("emerald")
  local function f(name) return C:require("flags", name) end
  local function v(name) return C:require("vars", name) end
  local function i(name) return C:require("items", name) end
  local ticketBody = function()
    return bodyOf(
      "Thank you for using the MYSTERY",
      "GIFT System.",
      "There is a ticket here for you.",
      "It is for use at LILYCOVE CITY port.")
  end
  return {
    rseCard("rse_eon_ticket", "EON TICKET", {
      flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 3, idNumber = 101, bgType = 1, bodyText = ticketBody(),
      -- pokeemerald/data/scripts/cable_club.inc:33
      gift = { kind = "item", item = i("ITEM_EON_TICKET"), quantity = 1,
        setFlags = { f("FLAG_ENABLE_SHIP_SOUTHERN_ISLAND") },
        haveFlags = { f("FLAG_ENABLE_SHIP_SOUTHERN_ISLAND") } },
    }),
    rseCard("rse_aurora_ticket", "AURORA TICKET", {
      flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET, idNumber = 102, bgType = 3, bodyText = ticketBody(),
      -- pokeemerald/data/scripts/gift_aurora_ticket.inc:5
      gift = { kind = "item", item = i("ITEM_AURORA_TICKET"), quantity = 1,
        setFlags = { f("FLAG_ENABLE_SHIP_BIRTH_ISLAND"), f("FLAG_RECEIVED_AURORA_TICKET") },
        haveFlags = { f("FLAG_RECEIVED_AURORA_TICKET"), f("FLAG_BATTLED_DEOXYS") } },
    }),
    rseCard("rse_mystic_ticket", "MYSTIC TICKET", {
      flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 1, idNumber = 103, bgType = 2, bodyText = ticketBody(),
      -- pokeemerald/data/scripts/gift_mystic_ticket.inc:5
      gift = { kind = "item", item = i("ITEM_MYSTIC_TICKET"), quantity = 1,
        setFlags = { f("FLAG_ENABLE_SHIP_NAVEL_ROCK"), f("FLAG_RECEIVED_MYSTIC_TICKET") },
        haveFlags = { f("FLAG_RECEIVED_MYSTIC_TICKET"), f("FLAG_CAUGHT_LUGIA"), f("FLAG_CAUGHT_HO_OH") } },
    }),
    rseCard("rse_old_sea_map", "OLD SEA MAP", {
      flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 2, idNumber = 104, bgType = 6,
      bodyText = bodyOf(
        "Thank you for using the MYSTERY",
        "GIFT System.",
        "We received this OLD SEA MAP",
        "addressed to you."),
      -- pokeemerald/data/scripts/gift_old_sea_map.inc:5
      gift = { kind = "item", item = i("ITEM_OLD_SEA_MAP"), quantity = 1,
        setFlags = { f("FLAG_ENABLE_SHIP_FARAWAY_ISLAND"), f("FLAG_RECEIVED_OLD_SEA_MAP") },
        haveFlags = { f("FLAG_RECEIVED_OLD_SEA_MAP"), f("FLAG_CAUGHT_MEW") } },
    }),
    rseCard("rse_surf_pichu", "SURFING PICHU EGG", {
      flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 4, idNumber = 105, iconSpecies = 172, bgType = 1,
      titleText = "POKéMON EGG",
      bodyText = bodyOf(
        "From the POKéMON CENTER we",
        "have a gift, a POKéMON EGG!",
        "Please raise it with love and",
        "kindness."),
      -- pokeemerald/data/scripts/gift_pichu.inc:1
      gift = { kind = "egg", script = "surfPichu", species = C:require("species", "SPECIES_PICHU"),
        moves = { [3] = C:require("moves", "MOVE_SURF") },
        slotVar = v("VAR_GIFT_PICHU_SLOT"), doneFlag = f("FLAG_MYSTERY_GIFT_DONE") },
    }),
    rseCard("rse_stamp_card", "STAMP CARD", {
      flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 5, idNumber = 106, type = MysteryGift.CARD_TYPE_STAMP,
      bgType = 4, sendType = MysteryGift.SEND_TYPE_ALLOWED, maxStamps = MysteryGift.MAX_STAMP_CARD_STAMPS,
      bodyText = bodyOf(
        "Thank you for using the STAMP CARD",
        "System.",
        "Trade with other TRAINERS to fill",
        "your STAMP CARD."),
      -- pokeemerald/data/scripts/gift_stamp_card.inc:1
      gift = { kind = "none", script = "stampCard" },
    }),
    rseCard("rse_battle_card", "BATTLE COUNT CARD", {
      flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 6, idNumber = 107, type = MysteryGift.CARD_TYPE_LINK_STAT,
      bgType = 5, sendType = MysteryGift.SEND_TYPE_ALLOWED,
      bodyText = bodyOf(
        "Your BATTLE COUNT CARD keeps",
        "track of your battle record against",
        "TRAINERS with the same CARD.",
        "Look for them and battle!"),
      -- pokeemerald/data/scripts/gift_battle_card.inc:1
      gift = { kind = "item", script = "battleCard", item = i("ITEM_POTION"), quantity = 1,
        doneFlag = f("FLAG_MYSTERY_GIFT_DONE"),
        requireStat = MysteryGift.CARD_STAT_BATTLES_WON, requireValue = 3 },
    }),
    rseCard("rse_altering_cave", "ALTERING CAVE", {
      flagId = MysteryGift.WONDER_CARD_FLAG_OFFSET + 7, idNumber = 108, bgType = 6,
      bodyText = bodyOf(
        "The POKéMON living in ALTERING",
        "CAVE have changed.",
        "Go and see what turns up",
        "on ROUTE 103."),
      -- pokeemerald/data/scripts/gift_altering_cave.inc:1
      gift = { kind = "var", script = "alteringCave", slotVar = v("VAR_ALTERING_CAVE_WILD_SET"), varAdd = 1,
        varWrap = 10 },
    }),
  }
end

return M
