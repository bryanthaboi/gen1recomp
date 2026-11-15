-- The side tables a script command NAMES rather than carries: the in-game
-- trades, the elevator floor lists, and the five decoration descriptions.
--   GOLD_CACHE="$HOME/Library/Application Support/LOVE/gold-dev/gold" \
--     luajit tests/gen2_events_test.lua
--
-- All three were unreachable until the extractor followed the pointer each
-- command holds, so this suite is in two halves: the model, which runs
-- ROM-free against fixtures transcribed from pokegold, and a cache-gated block
-- that asserts data/generated/events.lua really carries what those fixtures
-- claim.  A re-import that reads a row wrong fails in the second half.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 events")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local NpcTrade = require("src.core.gen2.NpcTrade")
local ElevatorMenu = require("src.ui.gen2.ElevatorMenu")
local TradeMenu = require("src.ui.gen2.TradeMenu")
local TradeAnim = require("src.core.gen2.TradeAnim")
local TradeAnimView = require("src.ui.gen2.TradeAnim")
local Mon = require("src.battle.gen2.Mon")

-- ---- fixtures -------------------------------------------------------------
--
-- data/events/npc_trades.asm row 0, the Violet City collector:
--   npctrade TRADE_DIALOGSET_COLLECTOR, DROWZEE, MACHOP, "MUSCLE", $37, $66,
--            GOLD_BERRY, 37460, "MIKE", TRADE_GENDER_EITHER
local MIKE = {
  id = 0, dialog = "TRADE_DIALOGSET_COLLECTOR",
  give = "DROWZEE", get = "MACHOP", nickname = "MUSCLE",
  dvs = { 0x37, 0x66 }, item = 174, otId = 37460, otName = "MIKE",
  gender = "TRADE_GENDER_EITHER",
}
-- Row 3 is the one trade that wants a particular gender.
local EMY = {
  id = 3, dialog = "TRADE_DIALOGSET_NEWBIE",
  give = "DRAGONAIR", get = "RHYDON", nickname = "DON",
  dvs = { 0x77, 0x66 }, item = 0, otId = 283, otName = "EMY",
  gender = "TRADE_GENDER_FEMALE",
}

local GROWTH = { GROWTH_MEDIUM_FAST =
  { numerator = 1, denominator = 1, squared = 0, linear = 0, constant = 0 } }
local POKEMON = { growthRates = GROWTH }
local function species(id, genderRatio)
  POKEMON[id] = {
    id = id, name = id,
    baseStats = { hp = 45, attack = 49, defense = 49, speed = 45,
      specialAttack = 65, specialDefense = 65 },
    types = { "NORMAL", "NORMAL" },
    growthRate = "GROWTH_MEDIUM_FAST",
    genderRatio = genderRatio or 127,
    levelMoves = { { level = 1, move = "TACKLE" } },
  }
  return POKEMON[id]
end
species("DROWZEE")
species("MACHOP")
species("DRAGONAIR")
species("RHYDON")
-- NPCTRADE_ITEM is an item id BYTE in the table, while a held item is a KEY of
-- data/generated/items.lua everywhere else in the port, so the fixture carries
-- the item table the byte is named through.
local ITEMS = {
  GOLD_BERRY = { id = "GOLD_BERRY", index = 174, name = "GOLD BERRY",
    heldEffect = "HELD_RESTORE_HP", heldParameter = 30 },
}
local DATA = { pokemon = POKEMON, moves = {}, items = ITEMS }

-- ---- the DV bytes ---------------------------------------------------------
--
-- NPCTRADE_DVS is a `dw` of two RAW bytes, `dn attack, defense` then
-- `dn speed, special` -- not a number.  Reading it as one would give MUSCLE a
-- different mon than every other player's.
do
  local dvs = NpcTrade.dvs(MIKE)
  eq(dvs.attack, 3, "$37 high nibble is the Attack DV")
  eq(dvs.defense, 7, "and its low nibble the Defense DV")
  eq(dvs.speed, 6, "$66 high nibble is Speed")
  eq(dvs.special, 6, "and its low nibble Special")
  -- Mon.hpDV is the low bit of each of the four, in that order.
  eq(dvs.hp, Mon.hpDV(dvs), "the HP DV is derived, not stored")
end

-- ---- CheckTradeGender -----------------------------------------------------
--
-- TRADE_GENDER_EITHER takes anything; the other two run GetGender on the mon
-- the player picked.  A genderless species satisfies neither -- both arms of
-- CheckTradeGender fall to .not_matching.
do
  check(NpcTrade.genderOk(MIKE, { gender = "male" }), "EITHER takes a male")
  check(NpcTrade.genderOk(MIKE, { gender = "female" }), "and a female")
  check(NpcTrade.genderOk(MIKE, { gender = "unknown" }),
    "and a genderless mon")
  check(NpcTrade.genderOk(EMY, { gender = "female" }),
    "TRADE_GENDER_FEMALE takes a female")
  check(not NpcTrade.genderOk(EMY, { gender = "male" }), "and refuses a male")
  check(not NpcTrade.genderOk(EMY, { gender = "unknown" }),
    "and refuses a genderless one")
end

-- ---- the refusal ladder ---------------------------------------------------
--
-- Species first, then gender, and BOTH are TRADE_DIALOG_WRONG: the NPC never
-- says which of the two was the problem.
do
  eq(NpcTrade.check(MIKE, { species = "DROWZEE", gender = "male" }), nil,
    "the right mon goes through")
  eq(NpcTrade.check(MIKE, { species = "MACHOP", gender = "male" }),
    NpcTrade.DIALOG_WRONG, "the wrong species is WRONG")
  eq(NpcTrade.check(EMY, { species = "DRAGONAIR", gender = "male" }),
    NpcTrade.DIALOG_WRONG, "and so is the wrong gender")
  eq(NpcTrade.check(MIKE, nil), NpcTrade.DIALOG_CANCEL,
    "backing out of the party list is CANCEL, not WRONG")
end

-- ---- wTradeFlags ----------------------------------------------------------
--
-- Checked BEFORE the intro line, which is why a completed trade never asks
-- again -- it only says TRADE_DIALOG_AFTER.
do
  local save = { party = {} }
  check(not NpcTrade.done(save, 0), "a fresh save has traded nothing")
  NpcTrade.markDone(save, 0)
  check(NpcTrade.done(save, 0), "and the flag sticks")
  check(not NpcTrade.done(save, 1), "one trade at a time")
end

-- ---- DoNPCTrade -----------------------------------------------------------
--
-- The received mon keeps the LEVEL of the one handed over
-- (ComputeNPCTrademonStats runs on the new species' bases at that level) and
-- arrives wearing the row's nickname, DVs, held item, OT name and OT ID.
do
  local save = { party = {
    { species = "PIDGEY", level = 9 },
    { species = "DROWZEE", level = 22, gender = "male" },
  } }
  local given, got = NpcTrade.perform(DATA, save, MIKE, 2)
  eq(given.species, "DROWZEE", "the picked mon is the one handed over")
  eq(#save.party, 2, "the party size does not change")
  eq(save.party[2], got, "and the new mon lands in the last slot")
  eq(got.species, "MACHOP", "it is NPCTRADE_GETMON")
  eq(got.level, 22, "at the level of the mon given away")
  eq(got.nickname, "MUSCLE", "wearing the row's nickname")
  eq(got.otName, "MIKE", "and its OT name")
  eq(got.otId, 37460, "and its OT ID, which the table stores unswapped")
  -- The held item arrives NAMED, not as the table's raw byte: the mon wears it
  -- like any other held item (DoNPCTrade writes it into wPartyMon1Item), and
  -- every consumer in the port keys items.lua by id.  This used to assert 174,
  -- which crashed Bag.add the moment the player took the item off.
  eq(got.item, "GOLD_BERRY", "and its held item, named")
  eq(ITEMS[got.item].heldEffect, "HELD_RESTORE_HP",
    "so the berry's held effect resolves")
  eq(got.dvs.attack, 3, "with the row's DVs, not a roll")
  -- A row whose item is 0 is NO_ITEM, which must not become a held item id 0.
  local save2 = { party = { { species = "DRAGONAIR", level = 30,
    gender = "female" } } }
  local _, rhydon = NpcTrade.perform(DATA, save2, EMY, 1)
  eq(rhydon.item, nil, "an item byte of 0 is no held item")
  eq(#save2.party, 1, "removing then adding leaves the party the same size")
  -- Taking the item off the traded mon puts it in the bag, which is where the
  -- raw byte used to die: Bag.isBadge indexes the id as a string.
  local Bag = require("src.inventory.Bag")
  check(Bag.add({ inventory = {}, bagOrder = {} }, got.item, 1, DATA) == true,
    "and the bag takes it when the player pulls it off")
  -- A cache written before the extractor named the byte still imports: the
  -- resolver falls back to the item table, then to constants.itemOrder.
  eq(NpcTrade.item(DATA, { item = 174 }), "GOLD_BERRY",
    "a raw byte is named through items.lua")
  eq(NpcTrade.item({ constants = { itemOrder = { [174] = "GOLD_BERRY" } } },
    { item = 174 }), "GOLD_BERRY", "or through constants.itemOrder")
  eq(NpcTrade.item(DATA, { item = "GOLD_BERRY" }), "GOLD_BERRY",
    "and a cache that already names it passes straight through")
  eq(NpcTrade.item(DATA, { item = 0 }), nil, "NO_ITEM stays no item")
end

-- ---- the trade conversation -----------------------------------------------
--
-- GetTradeMonNames fills wStringBuffer1 with the mon you HAND OVER plus the
-- row's gender glyph, wStringBuffer2 with the mon you GET, and
-- wMonOrItemNameBuffer with the handed-over mon again without the glyph.  All
-- three decode to the same {STRBUF}, so the buffer list recorded next to the
-- text is what tells them apart.
do
  local body = "Do you have\v{STRBUF}?\fWant to trade it\nfor my {STRBUF}?"
  local filled = TradeMenu.fill(body, MIKE, DATA,
    { "wStringBuffer1", "wStringBuffer2" })
  check(filled:find("have\vDROWZEE", 1, true) ~= nil,
    "wStringBuffer1 is the mon the NPC wants")
  check(filled:find("for my MACHOP", 1, true) ~= nil,
    "and wStringBuffer2 the mon it offers")
  -- Swap the buffers and the two mons swap with them; a filler that ignored
  -- the list would print the same string either way.
  local swapped = TradeMenu.fill(body, MIKE, DATA,
    { "wStringBuffer2", "wStringBuffer1" })
  check(swapped:find("have\vMACHOP", 1, true) ~= nil,
    "the buffer list decides, not the order of appearance")
  -- wStringBuffer1 carries the glyph; wMonOrItemNameBuffer is the same mon
  -- without it.
  eq(TradeMenu.fill("{STRBUF}", EMY, DATA, { "wStringBuffer1" }),
    "DRAGONAIR\xe2\x99\x80", "TRADE_GENDER_FEMALE tags wStringBuffer1 with ♀")
  eq(TradeMenu.fill("{STRBUF}", EMY, DATA, { "wMonOrItemNameBuffer" }),
    "DRAGONAIR", "and wMonOrItemNameBuffer carries no glyph")
  eq(TradeMenu.fill("{STRBUF}", MIKE, DATA, { "wStringBuffer1" }), "DROWZEE",
    "TRADE_GENDER_EITHER adds nothing")
  eq(TradeMenu.fill("{STRBUF}", MIKE, DATA, nil), "DROWZEE",
    "and with no list at all the fallback is wStringBuffer1")

  -- `\f` starts a page, `\v` scrolls (the new page opens with the last line of
  -- the previous one), `\n` is the page's second line.
  local pages = TradeMenu.paginate("one\ntwo\fthree\nfour")
  eq(#pages, 2, "a form feed is a page break")
  eq(pages[1][1], "one", "page 1 line 1")
  eq(pages[1][2], "two", "page 1 line 2")
  eq(pages[2][1], "three", "page 2 line 1")
  local scrolled = TradeMenu.paginate("one\ntwo\vthree")
  eq(#scrolled, 2, "a scroll is also a page")
  eq(scrolled[2][1], "two", "which opens on the previous last line")
  eq(scrolled[2][2], "three", "with the new line under it")
end

-- ---- the trade animation --------------------------------------------------
--
-- engine/movie/trade_animation.asm.  The script is a flat list of waits, so
-- the whole 37 seconds can be walked without a window: the beats have to come
-- in the cart's order, the two scrolls have to close on the frame the ASM's
-- step size says, and the Game Boy pan has to cross the 256-pixel wrap exactly
-- once in each direction.
do
  eq(TradeAnim.SCRIPT[1].id, "givemon_scroll", "it opens on the given mon")
  eq(TradeAnim.SCRIPT[#TradeAnim.SCRIPT].id, "take_care",
    "and closes on TAKE GOOD CARE")

  -- TradeAnim_DoGivemonScroll closes $88 at 4 a frame, so 34 frames.
  eq(TradeAnim.givemonOffset(0), 0x88, "the panel starts a screen out")
  eq(TradeAnim.givemonOffset(1), 0x84, "and closes 4 pixels a frame")
  eq(TradeAnim.givemonOffset(34), 0, "landing home on the beat's last frame")
  local scroll = TradeAnim.SCRIPT[1]
  eq(scroll.frames, 34, "which is how long the beat is")

  -- EnterLinkTube2 and ExitLinkTube, the same $a0 in opposite directions.
  eq(TradeAnim.tubeOffset("tube_in", 0), 0xa0, "the tube starts off screen")
  eq(TradeAnim.tubeOffset("tube_in", 40), 0, "and is home after 40 frames")
  eq(TradeAnim.tubeOffset("tube_out", 0), 0, "leaving, it starts home")
  eq(TradeAnim.tubeOffset("tube_out", 40), 0xa0, "and is gone after 40")

  -- TubeToOT2/3/4 pan 2 a frame through $50 and $a0 to the wrap; the get
  -- direction is TubeToPlayer3/4/5 running it back.
  eq(TradeAnim.pan("send_pan_a", 0), 0, "the send pan starts on our Game Boy")
  eq(TradeAnim.pan("send_pan_a", 40), 0x50, "hits $50 after 40 frames")
  eq(TradeAnim.pan("send_pan_b", 40), 0xa0, "$a0 after 40 more")
  eq(TradeAnim.pan("send_pan_c", 48), 0x100, "and wraps once, in 48")
  eq(TradeAnim.pan("get_pan_a", 0), 0x100, "the get pan starts at the wrap")
  eq(TradeAnim.pan("get_pan_c", 48), 0, "and comes all the way back")
  eq(TradeAnim.pan("bulge", 0), nil, "a beat outside the pans has no position")

  -- TradeAnim_AnimateTrademonInTube: the icon waits out the pan on the cable,
  -- then walks its two legs and is gone.
  eq(select(1, TradeAnim.tubeIcon("send_pan_a", 0)), 80, "the icon starts at")
  eq(select(2, TradeAnim.tubeIcon("send_pan_a", 0)), 28,
    "TubeToOT1's own depixel, on the cable")
  eq(select(1, TradeAnim.tubeIcon("send_wait", 60)), 140,
    ".MoveRight's `cp $94` after 60 frames")
  eq(select(2, TradeAnim.tubeIcon("send_wait", 92)), 60,
    "and .MoveDown's `cp $4c` 32 later")
  eq(TradeAnim.tubeIcon("send_hold", 0), nil,
    ".done_move_down zeroes the struct index")
  eq(select(2, TradeAnim.tubeIcon("get_wait", 32)), 28, ".MoveUp's `cp $2c`")
  eq(select(1, TradeAnim.tubeIcon("get_wait", 92)), 80,
    "then .MoveLeft's `cp $58`")
  eq(select(2, TradeAnim.tubeIcon("get_pan_b", 20)), 28,
    "so the get pan runs with it parked on the cable, not below it")
  eq(TradeAnim.tubeIcon("get_hold", 0), nil, ".WaitTimer2 despawns it")

  -- The clock: beatAt walks the same list startOf indexes.
  local first, offset = TradeAnim.beatAt(0)
  eq(first.id, "givemon_scroll", "frame 0 is the first beat")
  eq(offset, 0, "at its own frame 0")
  local second = TradeAnim.beatAt(34)
  eq(second.id, "givemon_hold", "frame 34 has already stepped past it")
  local beat, into = TradeAnim.beatAt(TradeAnim.startOf("bulge") + 5)
  eq(beat.id, "bulge", "startOf lands inside the beat it names")
  eq(into, 5, "five frames in")
  local last = TradeAnim.beatAt(TradeAnim.TOTAL + 100)
  eq(last.id, "take_care", "overrunning holds the last picture")
  check(TradeAnim.TOTAL > 2000, "the whole thing really is half a minute")

  -- DoNPCTrade's two records: the player's is the mon that LEFT, under the
  -- player's own name, and the OT's is the row's, under the row's trainer.
  local given = { species = "DROWZEE", level = 15, otName = "GOLD",
    otId = 12345 }
  local received = { species = "MACHOP", level = 15, otName = "MIKE",
    otId = MIKE.otId }
  local save = { player = { name = "SILVER", id = 999 } }
  local give, get = TradeAnim.records(DATA, save, MIKE, given, received)
  eq(give.species, "DROWZEE", "the player's trademon is the one handed over")
  eq(give.senderName, "SILVER", "sent under the player's own name")
  eq(give.otName, "GOLD", "keeping the OT it walked in with")
  eq(give.id, 12345, "and that OT's id")
  eq(get.species, "MACHOP", "the OT's trademon is the one received")
  eq(get.senderName, "MIKE", "sent by the row's trainer")
  eq(get.id, MIKE.otId, "with the row's id")
  eq(given.species, "DROWZEE", "and neither record was mutated")

  -- The animation's lines name FOUR different buffers, and getting the order
  -- wrong is the difference between "MACHOP was sent to MIKE" and a line that
  -- says the player sent themselves.
  local names = {
    wPlayerTrademonSpeciesName = "DROWZEE",
    wPlayerTrademonSenderName = "SILVER",
    wOTTrademonSpeciesName = "MACHOP",
    wOTTrademonSenderName = "MIKE",
  }
  eq(TradeAnimView.fill("{STRBUF} was sent to {STRBUF}.", names,
      { "wPlayerTrademonSpeciesName", "wOTTrademonSenderName" }),
    "DROWZEE was sent to MIKE.", "the sent line names mon then trainer")
  eq(TradeAnimView.fill("For {STRBUF}'s {STRBUF},", names,
      { "wPlayerTrademonSenderName", "wPlayerTrademonSpeciesName" }),
    "For SILVER's DROWZEE,", "and the reply names them the other way round")

  local bare = TradeAnimView.new({ data = DATA, save = save }, {
    row = MIKE, given = given, received = received, save = save,
  })
  check(not pcall(bare.lines, bare, "sent_text"),
    "an events.lua without tradeTexts is an error, not a transcription")
  local view = TradeAnimView.new({ data = DATA, save = save }, {
    row = MIKE, given = given, received = received, save = save,
    eventTables = {
      tradeTexts = {
        _MonWasSentToText = "{STRBUF} was\nsent to {STRBUF}.",
        _BidsFarewellToMonText = "{STRBUF} bids\nfarewell to",
        _MonNameBidsFarewellText = "{STRBUF}.",
        _TakeGoodCareOfMonText = "Take good care of\n{STRBUF}.",
      },
      tradeBuffers = {
        _MonWasSentToText = { "wPlayerTrademonSpeciesName",
                              "wOTTrademonSenderName" },
        _BidsFarewellToMonText = { "wOTTrademonSenderName" },
        _MonNameBidsFarewellText = { "wOTTrademonSpeciesName" },
        _TakeGoodCareOfMonText = { "wOTTrademonSpeciesName" },
      },
    },
  })
  local sent = view:lines("sent_text")
  eq(sent[1], "DROWZEE was", "line 1 of the sent text")
  eq(sent[2], "sent to MIKE.", "line 2")
  eq(view:lines("farewell_a")[1], "MIKE bids", "the farewell opens on the OT")
  eq(view:lines("farewell_b")[1], "MACHOP.", "and names the mon on the next")
  eq(view:lines("take_care")[2], "MACHOP.", "TAKE GOOD CARE names it too")
  eq(view:lines("sent_blank"), nil, "the empty page prints nothing at all")
end

-- ---- the elevator ---------------------------------------------------------
--
-- Elevator_MenuHeader is a four-row scrolling menu, so a seven-floor list
-- scrolls.  The window follows the cursor and stops at both ends.
do
  eq(ElevatorMenu.scrollFor(1, 7, 0), 0, "the window opens at the top")
  eq(ElevatorMenu.scrollFor(4, 7, 0), 0, "and holds while the cursor is in it")
  eq(ElevatorMenu.scrollFor(5, 7, 0), 1, "the fifth row scrolls it one")
  eq(ElevatorMenu.scrollFor(7, 7, 1), 3, "the last row scrolls it to the end")
  eq(ElevatorMenu.scrollFor(7, 7, 5), 3, "and never past it")
  eq(ElevatorMenu.scrollFor(2, 7, 3), 1, "going back up drags it with you")
  eq(ElevatorMenu.scrollFor(1, 3, 0), 0, "a list that fits never scrolls")

  local names = { "B4F", "B3F", "B2F", "B1F", "1F" }
  eq(ElevatorMenu.floorName(names, 3), "B1F", "FLOOR_B1F is row 3")
  eq(pcall(ElevatorMenu.floorName, nil, 4), false, "no floorNames is an error")
  eq(pcall(ElevatorMenu.floorName, names, 15), false, "a row past the cache is an error")
end

-- ---- against the cache ----------------------------------------------------

local cacheDir = os.getenv("GOLD_CACHE")
if not cacheDir then
  cacheDir = (os.getenv("HOME") or "") ..
    "/Library/Application Support/LOVE/gold-dev/gold"
end
local eventsFile = loadfile(cacheDir .. "/data/generated/events.lua")
if not eventsFile then
  check(true, "cache absent or predates events.lua (SKIP)")
  S.finish()
  return
end
local events = eventsFile()
local scripts = assert(loadfile(cacheDir .. "/data/generated/scripts.lua"))()

do
  eq(#events.trades, NpcTrade.NUM_NPC_TRADES, "all six in-game trades")
  local mike = NpcTrade.row(events, 0)
  eq(mike.dialog, MIKE.dialog, "trade 0 dialog set")
  eq(mike.give, MIKE.give, "trade 0 wants DROWZEE")
  eq(mike.get, MIKE.get, "and offers MACHOP")
  eq(mike.nickname, MIKE.nickname, "nicknamed MUSCLE")
  eq(mike.otName, MIKE.otName, "OT MIKE")
  eq(mike.otId, MIKE.otId, "OT ID 37460")
  -- Asserted through the resolver rather than on the raw field, so the suite is
  -- green whether this checkout's cache predates the extractor naming the byte
  -- (174) or was re-imported after it ("GOLD_BERRY").
  local cacheItems = loadfile(cacheDir .. "/data/generated/items.lua")
  eq(NpcTrade.item({ items = cacheItems and cacheItems() or ITEMS }, mike),
    "GOLD_BERRY", "holding GOLD_BERRY")
  eq(mike.dvs[1], MIKE.dvs[1], "DV byte 1")
  eq(mike.dvs[2], MIKE.dvs[2], "DV byte 2")
  eq(mike.gender, MIKE.gender, "and taking either gender")
  local emy = NpcTrade.row(events, 3)
  eq(emy.gender, EMY.gender, "trade 3 wants a female DRAGONAIR")
  eq(emy.otId, EMY.otId, "and its OT ID is the four-digit 283")

  -- The 5x3 text table.  Every cell must be a real string: an empty one means
  -- PrintTradeText's dialog-major indexing was read column-major.
  for _, dialog in ipairs({ NpcTrade.DIALOG_INTRO, NpcTrade.DIALOG_CANCEL,
      NpcTrade.DIALOG_WRONG, NpcTrade.DIALOG_COMPLETE,
      NpcTrade.DIALOG_AFTER }) do
    for _, set in ipairs({ "TRADE_DIALOGSET_COLLECTOR",
        "TRADE_DIALOGSET_HAPPY", "TRADE_DIALOGSET_NEWBIE" }) do
      local body = events.tradeTexts[dialog] and events.tradeTexts[dialog][set]
      check(type(body) == "string" and #body > 0,
        ("%s / %s has a line"):format(dialog, set))
      check(not body:find("{BYTE:", 1, true),
        ("%s / %s decoded cleanly"):format(dialog, set))
    end
  end
  check(events.tradeTexts.TRADE_DIALOG_INTRO.TRADE_DIALOGSET_COLLECTOR
    :find("I collect", 1, true) ~= nil, "the collector's intro is his own")
  check(events.tradeTexts.TradedForText:find("{PLAYER} traded", 1, true) ~= nil,
    "TradedForText follows its far pointer")
  -- text_far ends on TX_END ($50) rather than on `done`, so a decoder that
  -- treats every $50 as a skippable `@` runs into the next string.
  check(not events.tradeTexts.TradedForText:find("I collect", 1, true),
    "and stops there rather than running into the next one")

  -- The buffer list next to each line.  Two markers in one line are two
  -- DIFFERENT buffers, and getting the pair backwards swaps the mons in the
  -- intro -- the one line where a player would notice immediately.
  local intro = events.tradeBuffers.TRADE_DIALOG_INTRO.TRADE_DIALOGSET_COLLECTOR
  eq(#intro, 2, "the collector's intro splices two names")
  eq(intro[1], "wStringBuffer1", "the mon he wants first")
  eq(intro[2], "wStringBuffer2", "then the mon he offers")
  eq(events.tradeBuffers.TRADE_DIALOG_AFTER.TRADE_DIALOGSET_COLLECTOR[1],
    "wStringBuffer2", "and afterwards he asks about the one he gave you")
  eq(events.tradeBuffers.TRADE_DIALOG_COMPLETE.TRADE_DIALOGSET_COLLECTOR[1],
    "wStringBuffer1", "while the thank-you names the one he received")
end

do
  eq(#events.floorNames, 16, "all sixteen FLOOR_* labels")
  eq(events.floorNames[4], "B1F", "FLOOR_B1F")
  eq(events.floorNames[5], "1F", "FLOOR_1F")
  eq(events.floorNames[16], "ROOF", "FLOOR_ROOF")

  -- The three elevators, found through their own scripts.  Goldenrod's is the
  -- seven-floor one; every row has to name a real map or the ride goes nowhere.
  local maps = assert(loadfile(cacheDir .. "/data/generated/maps.lua"))()
  local lists = {}
  for key, cmds in pairs(scripts) do
    if type(cmds) == "table" and key ~= "movements" then
      for _, cmd in ipairs(cmds) do
        if cmd.op == "elevator" and cmd.floors then
          lists[#lists + 1] = cmd.floors
        end
      end
    end
  end
  check(#lists >= 2, "at least the two dept-store elevators carry a list")
  local biggest
  for _, list in ipairs(lists) do
    if not biggest or #list > #biggest then biggest = list end
    for _, row in ipairs(list) do
      check(row.destMap ~= nil and maps[row.destMap] ~= nil,
        ("elevator row %s names a real map"):format(tostring(row.floor)))
      check(row.destWarp and row.destWarp > 0,
        "and a warp number inside it")
    end
  end
  eq(#biggest, 7, "Goldenrod's runs B1F to 6F")
  eq(biggest[1].floor, "FLOOR_B1F", "starting at B1F")
  eq(biggest[1].destWarp, 2, "which is its warp 2")
end

do
  -- describedecoration's five arms.  Each names a script that is really in
  -- scripts.lua; the poster's is the bare `end` DecorationDesc_NullPoster,
  -- which is what a room with nothing on the wall shows.
  local decos = events.decorations or {}
  for _, name in ipairs(events.decorationOrder or {}) do
    local arm = decos[name]
    check(type(arm) == "table", ("%s has an arm"):format(name))
    check(scripts[arm.script] ~= nil,
      ("%s names a script in scripts.lua"):format(name))
  end
  eq(scripts[decos.DECODESC_POSTER.script][1].op, "end",
    "an empty poster wall says nothing")
  -- The two ornaments and the console share one script; the giant ornament has
  -- its own.  Both are `jumptext`, so the text must have come along.
  eq(decos.DECODESC_LEFT_DOLL.script, decos.DECODESC_RIGHT_DOLL.script,
    "both small ornaments share .OrnamentConsoleScript")
  eq(decos.DECODESC_CONSOLE.script, decos.DECODESC_LEFT_DOLL.script,
    "and so does the console")
  check(decos.DECODESC_BIG_DOLL.script ~= decos.DECODESC_LEFT_DOLL.script,
    "the giant ornament has .BigDollScript to itself")
  local text = assert(loadfile(cacheDir .. "/data/generated/text.lua"))()
  local body = scripts[decos.DECODESC_BIG_DOLL.script][1]
  eq(body.op, "jumptext", "which is a jumptext")
  check((text[body.text] or ""):find("giant doll", 1, true) ~= nil,
    "and its line came through the far pointer")
end

-- ---- the held-item marker sheet rode out with the icons ---------------------
--
-- GetIconGFX uploads HeldItemIcons as the two tiles straight after each icon's
-- eight (engine/gfx/mon_icons.asm:218-228), so the party list's marker lives or
-- dies on extractIcons writing this one row.  The love-stubbed draw test can
-- only prove the blit against fixtures; nothing else would catch a real import
-- silently dropping the sheet.  Gated like the trade item above: a cache built
-- before the extractor learned the symbol SKIPS rather than fails.
do
  local iconsFile = loadfile(cacheDir .. "/data/generated/icons.lua")
  local icons = iconsFile and iconsFile()
  local entry = icons and icons.heldItem
  if not entry then
    check(true, "cache predates the HeldItemIcons row (SKIP)")
  else
    check(entry.image:find("^assets/generated/icons/gen2/") ~= nil,
      "the marker sheet is written beside the party icons")
    local file = io.open(cacheDir .. "/" .. entry.image, "rb")
    check(file ~= nil, "and the file it names really exists")
    if file then file:close() end
    -- mail.2bpp then item.2bpp, the order they are INCBIN'd at
    -- mon_icons.asm:230-232 and the order PartyMenu.heldMarkerRow indexes.
    eq(entry.mailRow, 0, "mail is the top row")
    eq(entry.itemRow, 1, "and a plain item the bottom one")
  end
end

S.finish()
