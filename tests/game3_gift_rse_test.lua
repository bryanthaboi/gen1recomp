#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

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

do
  local ItemsData = require("src.core.game3.items_data")
  if not pcall(ItemsData.ensureLoaded) then
    ItemsData.installPack({ count = 6, items = {
      [13] = { name = "POTION", pocket = "ITEMS", fieldUse = "heal" },
      [275] = { name = "EON TICKET", pocket = "KEY_ITEMS", fieldUse = "key" },
      [370] = { name = "MYSTIC TICKET", pocket = "KEY_ITEMS", fieldUse = "key" },
      [371] = { name = "AURORA TICKET", pocket = "KEY_ITEMS", fieldUse = "key" },
      [376] = { name = "OLD SEA MAP", pocket = "KEY_ITEMS", fieldUse = "key" },
    } })
  end
end

local MysteryGift = require("src.core.game3.mystery_gift")
local Bag = require("src.core.game3.bag")
local Json = require("src.link.Json")
local C = require("src.core.game3.constants").of("emerald")
local FR = require("src.core.game3.constants").of("firered")

local function F(name) return C:require("flags", name) end
local function V(name) return C:require("vars", name) end
local function I(name) return C:require("items", name) end

local function newSession(version)
  return { version = version or "emerald", store = { flags = {}, vars = {} }, bag = Bag.new(), party = {},
    modData = {} }
end

local function builtin(family, key)
  for _, entry in ipairs(require("tests.fixtures.game3_gift_cards").cards(family)) do
    if entry.key == key then return entry end
  end
  return nil
end

local function cardOf(key)
  return MysteryGift.normalizeCard(builtin("rse", key).card, "emerald")
end

print("[test] 1. The session picks its family")
eq(MysteryGift.familyOf(newSession("emerald")), "rse", "an Emerald session is rse")
eq(MysteryGift.familyOf(newSession("firered")), "frlg", "a FireRed session is frlg")
eq(MysteryGift.familyOf(newSession("leafgreen")), "frlg", "a LeafGreen session is frlg")

print("[test] 2. Mystery Gift enablement reads the Emerald flag")
do
  local s = newSession()
  check(not MysteryGift.isEnabled(s), "a fresh Emerald save has Mystery Gift off")
  MysteryGift.enable(s)
  check(MysteryGift.getFlag(s, F("FLAG_SYS_MYSTERY_GIFT_ENABLE")), "enable sets FLAG_SYS_MYSTERY_GIFT_ENABLE")
  check(not MysteryGift.getFlag(s, FR:require("flags", "FLAG_SYS_MYSTERY_GIFT_ENABLED")),
    "and never the FRLG id")
  local fr = newSession("firered")
  MysteryGift.enable(fr)
  check(MysteryGift.getFlag(fr, FR:require("flags", "FLAG_SYS_MYSTERY_GIFT_ENABLED")), "FRLG keeps its own flag")
end

print("[test] 3. Emerald presets resolve through the Emerald constants")
do
  local aurora = cardOf("rse_aurora_ticket")
  check(aurora ~= nil, "the AURORA TICKET card normalizes")
  eq(aurora.gift.item, I("ITEM_AURORA_TICKET"), "its item")
  eq(aurora.gift.setFlags[1], F("FLAG_ENABLE_SHIP_BIRTH_ISLAND"), "setflag FLAG_ENABLE_SHIP_BIRTH_ISLAND")
  eq(aurora.gift.setFlags[2], F("FLAG_RECEIVED_AURORA_TICKET"), "setflag FLAG_RECEIVED_AURORA_TICKET")
  eq(aurora.gift.haveFlags[2], F("FLAG_BATTLED_DEOXYS"), "vgoto_if_set FLAG_BATTLED_DEOXYS")
  local sea = cardOf("rse_old_sea_map")
  eq(sea.gift.item, I("ITEM_OLD_SEA_MAP"), "OLD SEA MAP item")
  eq(sea.gift.setFlags[1], F("FLAG_ENABLE_SHIP_FARAWAY_ISLAND"), "the Faraway Island ship flag")
  eq(sea.gift.haveFlags[2], F("FLAG_CAUGHT_MEW"), "vgoto_if_set FLAG_CAUGHT_MEW")
  local mystic = cardOf("rse_mystic_ticket")
  eq(mystic.gift.setFlags[1], F("FLAG_ENABLE_SHIP_NAVEL_ROCK"), "the Navel Rock ship flag")
  eq(mystic.gift.haveFlags[2], F("FLAG_CAUGHT_LUGIA"), "vgoto_if_set FLAG_CAUGHT_LUGIA")
  local pichu = cardOf("rse_surf_pichu")
  eq(pichu.gift.slotVar, V("VAR_GIFT_PICHU_SLOT"), "the pichu slot var")
  eq(pichu.gift.moves[3], C:require("moves", "MOVE_SURF"), "MOVE_SURF in slot 3")
  eq(pichu.gift.doneFlag, F("FLAG_MYSTERY_GIFT_DONE"), "FLAG_MYSTERY_GIFT_DONE")
  eq(MysteryGift.normalizeCard({ flagId = 1000, idNumber = 1, gift = { kind = "item", item = "ITEM_NOPE" } }, "emerald"),
    nil, "an unknown constant name drops the card")
  for _, entry in ipairs(require("tests.fixtures.game3_gift_cards").cards("rse")) do
    local c = MysteryGift.normalizeCard(entry.card, "emerald")
    check(c ~= nil and MysteryGift.validateCard(c), "rse preset " .. entry.key .. " is a valid Wonder Card")
  end
end

print("[test] 4. The AURORA TICKET card delivers with Emerald flags")
do
  local s = newSession()
  check(MysteryGift.receiveCard(s, cardOf("rse_aurora_ticket")), "the card saves")
  check(MysteryGift.isEnabled(s), "receiving it enables Mystery Gift")
  eq(MysteryGift.receivedGiftFlag(1000, s), F("FLAG_RECEIVED_AURORA_TICKET"), "sReceivedGiftFlags[0] on Emerald")
  eq(MysteryGift.receivedGiftFlag(1002, s), F("FLAG_RECEIVED_OLD_SEA_MAP"), "sReceivedGiftFlags[2] on Emerald")
  check(MysteryGift.isGiftNotReceived(s), "the gift starts uncollected")
  eq(MysteryGift.ramScriptId(s), "aurora", "the card runs the ROM AURORA TICKET ramscript")
  eq(MysteryGift.deliverGift(s), MysteryGift.DELIVER_GIVEN, "the fallback delivery hands it over")
  eq(Bag.get(s.bag, I("ITEM_AURORA_TICKET")), 1, "one AURORA TICKET")
  check(MysteryGift.getFlag(s, F("FLAG_ENABLE_SHIP_BIRTH_ISLAND")), "FLAG_ENABLE_SHIP_BIRTH_ISLAND is set")
  check(MysteryGift.getFlag(s, F("FLAG_RECEIVED_AURORA_TICKET")), "FLAG_RECEIVED_AURORA_TICKET is set")
  check(not MysteryGift.getFlag(s, FR:require("flags", "FLAG_ENABLE_SHIP_BIRTH_ISLAND")), "the FRLG ship flag id is untouched")
  check(not MysteryGift.getFlag(s, FR:require("flags", "FLAG_RECEIVED_AURORA_TICKET")), "the FRLG received flag id is untouched")
  eq(MysteryGift.deliverGift(s), MysteryGift.DELIVER_ALREADY, "a second visit hands over nothing")
  eq(MysteryGift.deliveryTextKey(s, MysteryGift.DELIVER_ALREADY), "sText_AuroraTicketThankYou", "and thanks the player")
end

print("[test] 5. A relay card with numeric Emerald ids maps to its ramscript")
do
  local s = newSession()
  local raw = { flagId = 1002, idNumber = 10, type = 0, bgType = 6, sendType = 0,
    gift = { kind = "item", item = 376, quantity = 1, setFlags = { F("FLAG_ENABLE_SHIP_FARAWAY_ISLAND"), 0x13C },
      haveFlags = { 0x13C, F("FLAG_CAUGHT_MEW") } } }
  check(MysteryGift.receiveCard(s, raw), "the card saves")
  eq(MysteryGift.ramScriptId(s), "oldSeaMap", "an OLD SEA MAP item card runs the OLD SEA MAP ramscript")
  eq(MysteryGift.deliveryTextKey(s, MysteryGift.DELIVER_NO_ROOM), "sText_MysteryGiftOldSeaMapBagFull",
    "its full-bag text")
  eq(MysteryGift.ramScriptId(newSession("firered"), MysteryGift.normalizeCard(raw, "firered")), nil,
    "FRLG never uses Emerald ramscripts")
end

print("[test] 6. The EON TICKET card raises VAR_DISTRIBUTE_EON_TICKET")
do
  local s = newSession()
  check(MysteryGift.receiveCard(s, cardOf("rse_eon_ticket")), "the card saves")
  eq(MysteryGift.scriptStore(s).vars[V("VAR_DISTRIBUTE_EON_TICKET")] or
    require("src.core.game3.scripting.flags").getVar(s.store, nil, V("VAR_DISTRIBUTE_EON_TICKET")), 1,
    "ShouldDistributeEonTicket turns on")
  local done = newSession()
  MysteryGift.setFlag(done, F("FLAG_ENABLE_SHIP_SOUTHERN_ISLAND"), true)
  MysteryGift.receiveCard(done, cardOf("rse_eon_ticket"))
  eq(require("src.core.game3.scripting.flags").getVar(done.store, nil, V("VAR_DISTRIBUTE_EON_TICKET")), 0,
    "not once the Southern Island ship is open")
  eq(MysteryGift.deliverGift(done), MysteryGift.DELIVER_ALREADY, "and the card has nothing left to give")
end

print("[test] 7. Clearing a card clears Emerald's gift flags and vars")
do
  local s = newSession()
  local Flags = require("src.core.game3.scripting.flags")
  MysteryGift.setFlag(s, F("FLAG_MYSTERY_GIFT_DONE"), true)
  MysteryGift.setFlag(s, F("FLAG_MYSTERY_GIFT_15"), true)
  Flags.setVar(s.store, nil, V("VAR_GIFT_PICHU_SLOT"), 3)
  Flags.setVar(s.store, nil, V("VAR_GIFT_UNUSED_7"), 4)
  Flags.setVar(s.store, nil, V("VAR_ALTERING_CAVE_WILD_SET"), 5)
  MysteryGift.clearCardAndRelated(s)
  check(not MysteryGift.getFlag(s, F("FLAG_MYSTERY_GIFT_DONE")), "FLAG_MYSTERY_GIFT_DONE cleared")
  check(not MysteryGift.getFlag(s, F("FLAG_MYSTERY_GIFT_15")), "FLAG_MYSTERY_GIFT_15 cleared")
  eq(Flags.getVar(s.store, nil, V("VAR_GIFT_PICHU_SLOT")), 0, "VAR_GIFT_PICHU_SLOT cleared")
  eq(Flags.getVar(s.store, nil, V("VAR_GIFT_UNUSED_7")), 0, "VAR_GIFT_UNUSED_7 cleared")
  eq(Flags.getVar(s.store, nil, V("VAR_ALTERING_CAVE_WILD_SET")), 5, "Emerald keeps VAR_ALTERING_CAVE_WILD_SET")
end

print("[test] 8. ALTERING CAVE bumps Emerald's var and wraps")
do
  local s = newSession()
  local Flags = require("src.core.game3.scripting.flags")
  MysteryGift.receiveCard(s, cardOf("rse_altering_cave"))
  eq(MysteryGift.deliverGift(s), MysteryGift.DELIVER_GIVEN, "the card runs")
  eq(Flags.getVar(s.store, nil, V("VAR_ALTERING_CAVE_WILD_SET")), 1, "the Emerald var steps to 1")
  eq(Flags.getVar(s.store, nil, FR:require("vars", "VAR_ALTERING_CAVE_WILD_SET")), 0, "the FRLG var id is untouched")
  eq(MysteryGift.deliveryTextKey(s, MysteryGift.DELIVER_GIVEN), "sText_MysteryGiftAlteringCave", "its message")
  local w = newSession()
  Flags.setVar(w.store, nil, V("VAR_ALTERING_CAVE_WILD_SET"), 9)
  MysteryGift.receiveCard(w, cardOf("rse_altering_cave"))
  MysteryGift.deliverGift(w)
  eq(Flags.getVar(w.store, nil, V("VAR_ALTERING_CAVE_WILD_SET")), 0, "NUM_ALTERING_CAVE_TABLES + 1 wraps to 0")
end

print("[test] 9. Emerald's battle card and news rewards")
do
  local s = newSession()
  MysteryGift.receiveCard(s, cardOf("rse_battle_card"))
  eq(MysteryGift.deliverGift(s), MysteryGift.DELIVER_NOTHING, "no prize before three wins")
  eq(MysteryGift.deliveryTextKey(s, MysteryGift.DELIVER_NOTHING), "sText_MysteryGiftBattleCountCard", "the info text")
  eq(MysteryGift.deliveryTextKey(s, MysteryGift.DELIVER_GIVEN), "sText_MysteryGiftBattleCountCard_WonPrize",
    "the prize text")
  MysteryGift.receiveNews(s, { id = 5, titleText = "NEWS", bodyText = {} })
  eq((MysteryGift.getNewsRewardInfo(s)), MysteryGift.NEWS_REWARD_NONE,
    "news rewards wait for FLAG_SYS_MYSTERY_EVENT_ENABLE on Emerald")
  MysteryGift.setFlag(s, F("FLAG_SYS_MYSTERY_EVENT_ENABLE"), true)
  eq((MysteryGift.getNewsRewardInfo(s)), MysteryGift.NEWS_REWARD_RECV_BIG, "and pay out once it is set")
end

print("[test] 10. The feed is fetched and filtered per family")
do
  eq(MysteryGift.feedPath("frlg"), "/gifts/gen3", "FRLG keeps the bare path")
  eq(MysteryGift.feedPath("rse"), "/gifts/gen3?family=rse", "Emerald asks for its family")
  local payload = Json.encode({
    v = 1, issued = 1,
    cards = {
      { family = "frlg", key = "fr", flagId = 1000, idNumber = 2, type = 0, bgType = 3, sendType = 0,
        gift = { kind = "item", item = 371, setFlags = { 0x84B, 0x2A7 } } },
      { family = "rse", key = "em", flagId = 1000, idNumber = 2, type = 0, bgType = 3, sendType = 0,
        gift = { kind = "item", item = "ITEM_AURORA_TICKET", setFlags = { "FLAG_ENABLE_SHIP_BIRTH_ISLAND" } } },
      { key = "legacy", flagId = 1001, idNumber = 1, type = 0, bgType = 2, sendType = 0, gift = { kind = "none" } },
    },
    news = {
      { family = "rse", key = "emnews", id = 3, titleText = "EM" },
      { key = "frnews", id = 4, titleText = "FR" },
    },
  })
  local rse = MysteryGift.parseFeed(payload, "rse")
  eq(rse and #rse.cards, 1, "rse sees one card")
  eq(rse and rse.cards[1].key, "em", "the rse row")
  eq(rse and rse.cards[1].card.gift.setFlags[1], F("FLAG_ENABLE_SHIP_BIRTH_ISLAND"), "names resolve with Emerald ids")
  eq(rse and #rse.news, 2, "rse sees every news, news has no family limit")
  local frlg = MysteryGift.parseFeed(payload, "frlg")
  eq(frlg and #frlg.cards, 2, "frlg sees its row and the unlabeled one")
  eq(frlg and #frlg.news, 2, "frlg sees every news too")

  local begun = {}
  local transport = {
    begin = function(_, req) begun[#begun + 1] = req return #begun end,
    poll = function() return { status = "pending" } end,
    release = function() end,
  }
  local job = MysteryGift.fetchOnline({ transport = transport, session = newSession("emerald") })
  eq(job.family, "rse", "the Emerald job carries its family")
  local emPath = "/gifts/gen3?family=rse&version=emerald"
  check(begun[1] and begun[1].url:sub(-#emPath) == emPath,
    "Emerald fetches ?family=rse and names its game: " .. tostring(begun[1] and begun[1].url))
  MysteryGift.fetchOnline({ transport = transport, session = newSession("firered") })
  check(begun[2] and begun[2].url:sub(-#"/gifts/gen3?version=firered") == "/gifts/gen3?version=firered",
    "FireRed keeps the frlg path and names its game")
  MysteryGift.fetchOnline({ transport = transport, session = newSession("leafgreen") })
  check(begun[3] and begun[3].url:sub(-#"/gifts/gen3?version=leafgreen") == "/gifts/gen3?version=leafgreen",
    "LeafGreen names its own game")
end

print("[test] 11. LINK TOGETHER WITH ALL")
do
  local s = newSession()
  local words = MysteryGift.questionnaireWords(s)
  eq(words[1], 0xFFFF, "questionnaire words start empty")
  check(MysteryGift.isMysteryGiftPhrase({ 521, 5131, 4144, 4138 }), "LINK TOGETHER WITH ALL matches")
  check(not MysteryGift.isMysteryGiftPhrase({ 521, 5131, 4144, 4139 }), "another phrase does not")
  local okT, Types = pcall(require, "src.core.game3.rse.easy_chat_types")
  local okN = okT and pcall(require, "src.core.game3.scripting.natives_event_islands")
  if okN then
    local def = Types.get(Types.ID.QUESTIONNAIRE)
    check(def ~= nil, "the questionnaire easy chat type is registered")
    local Rse = require("src.core.game3.rse.init")
    local ctx = { specialVars = {} }
    local saved = Rse.setSpecialVar
    local got
    Rse.setSpecialVar = function(_, id, v) if id == 0x8004 then got = v end end
    def.commit(ctx, s, { 521, 5131, 4144, 4138 })
    eq(got, 2, "the Mystery Gift phrase answers VAR_0x8004 = 2")
    def.commit(ctx, s, { 1, 2, 3, 4 })
    eq(got, 0, "anything else answers 0")
    Rse.setSpecialVar = saved
    eq(MysteryGift.questionnaireWords(s)[1], 1, "the words are kept in the Mystery Gift save block")
  else
    print("[skip] natives_event_islands did not load headless")
  end
end

print("[test] 12. The Emerald main menu routes MYSTERY GIFT to the gift screen")
do
  local MainMenu = require("src.ui.game3.rse.main_menu_rse")
  local rows = MainMenu.items(MainMenu.TYPE.HAS_MYSTERY_GIFT)
  eq(rows[3], "MYSTERY_GIFT", "the third row is MYSTERY GIFT")
  eq(MainMenu.menuType(true, { mysteryGift = true }, "ok"), MainMenu.TYPE.HAS_MYSTERY_GIFT,
    "FLAG_SYS_MYSTERY_GIFT_ENABLE shows it")
  eq(MainMenu.menuType(true, { mysteryGift = false }, "ok"), MainMenu.TYPE.HAS_SAVED_GAME, "otherwise hidden")
  local store = { flags = {}, vars = {} }
  require("src.core.game3.scripting.flags").setFlag(store, nil, F("FLAG_SYS_MYSTERY_GIFT_ENABLE"), true)
  local okInfo, info = pcall(MainMenu.continueInfoFromSave, { version = "emerald", flags = store.flags, vars = store.vars },
    "emerald")
  if okInfo then
    check(info and info.mysteryGift, "continue info reads the Emerald enable flag")
  else
    print("[skip] continueInfoFromSave needs the cache: " .. tostring(info))
  end

  local saved = { version = "emerald", engine = "game3", flags = {}, vars = {}, modData = {} }
  local writes = 0
  package.loaded["src.core.SaveData"] = {
    load = function() return saved end,
    save = function() writes = writes + 1 return true end,
  }
  local opened, exits = nil, false
  package.loaded["src.ui.game3.mystery_gift"] = {
    new = function(opts) opened = opts return { opts = opts } end,
    update = function() return exits and "exit" or nil end,
    draw = function() end,
    close = function() end,
  }
  local menu = setmetatable({ state = "a_pressed" }, MainMenu)
  menu:_openMysteryGift()
  eq(menu.state, "mystery_gift", "selecting MYSTERY GIFT opens the gift screen")
  check(opened and opened.session and opened.session.version == "emerald", "on the Emerald save's session")
  eq(opened and MysteryGift.familyOf(opened.fetch.session), "rse", "and fetches the rse feed")
  check(opened and opened.onSave(opened.session) and writes == 1, "saving from the gift screen writes the save")
  eq(menu:update({ wasPressed = function() return false end }, 1 / 60), nil, "the gift screen runs")
  exits = true
  eq(menu:update({ wasPressed = function() return false end }, 1 / 60), "title", "leaving returns to the title screen")
  eq(menu.gift, nil, "and frees the gift screen")
end

if failed == 0 then
  print("PASS game3_gift_rse")
else
  print("FAIL game3_gift_rse failures=" .. failed)
  os.exit(1)
end
