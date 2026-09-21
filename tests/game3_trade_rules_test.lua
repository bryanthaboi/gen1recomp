#!/usr/bin/env luajit
-- pokefirered/src/trade_scene.c:1235 TradeBufferOTnameAndNicknames, link branch

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local store = { flags = {}, vars = {} }
local session = {
  store = store, map = "FR_ROUTE2_HOUSE", party = {},
  name = "RED", trainerId = 4242, gender = "male", vars = {}, flags = {},
  dex = { seen = {}, owned = {} },
}
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("meta.json")
if not cacheRoot then
  print("[skip] no current FireRed cache: " .. tostring(Cache.reason))
end

local TradeScene = require("src.core.game3.trade_scene")
local Trade = require("src.core.game3.scripting.natives_trade")
local Pokemon = require("src.core.game3.pokemon")
local Party = require("src.core.game3.party")
local Mail = require("src.core.game3.mail")

local ART = { gba = true }

local function run(offer, received, opts, limit)
  local order, counts, texts = {}, {}, {}
  local frames = 0
  TradeScene.play(offer, received, nil, opts)
  local seen = TradeScene.phase()
  order[#order + 1] = seen
  counts[seen] = 0
  while frames < (limit or 20000) do
    frames = frames + 1
    local st = TradeScene.state()
    local over = TradeScene.step()
    counts[seen] = (counts[seen] or 0) + 1
    if st and st.text and st.text ~= "" then texts[seen] = st.text end
    if over then break end
    local now = TradeScene.phase()
    if now ~= seen then
      seen = now
      order[#order + 1] = seen
      counts[seen] = 0
    end
  end
  return order, counts, frames, texts
end

local OFFER = { species = 63, nickname = "ABRA", level = 12, otName = "RED", otId = 4242 }
local RECEIVED = { species = 122, nickname = "MIMIEN", otName = "TRIS", otId = 31337, level = 12 }
local PEER = { name = "TRIS", id = 31337 }

print("[test] 1. the link arm runs pret's link branches")
local swapAt, evolveAt
local order, counts, total, texts = run(OFFER, RECEIVED, {
  art = ART, peer = PEER,
  onSwap = function() swapAt = TradeScene.phase() end,
  onEvolve = function() evolveAt = TradeScene.phase() end,
})
local at = {}
for i, name in ipairs(order) do at[name] = i end

-- pokefirered/src/trade_scene.c:1770 STATE_END_LINK_TRADE returns TRUE for a link trade
local LINK_TAIL = {
  "check_ribbons", "end_link_trade", "link_wait_peer", "try_evolution", "wait_evolution",
  "link_standby", "link_save", "link_save_delay", "link_close_delay",
  "fade_out_end", "wait_fade_out_end",
}
local base = at.check_ribbons
check(base ~= nil, "the link cinema reached check_ribbons")
for i, name in ipairs(LINK_TAIL) do
  eq(order[(base or 0) + i - 1], name, "link phase " .. i .. " of the tail is " .. name)
end
eq(order[#order], "wait_fade_out_end", "the link cinema ends on wait_fade_out_end")

-- pokefirered/src/trade_scene.c:2533 CB2_UpdateLinkTrade calls TradeMons at the return
eq(swapAt, "end_link_trade", "a link trade swaps the party at end_link_trade")
-- pokefirered/src/trade_scene.c:2322 CB2_TryLinkTradeEvolution
eq(evolveAt, "try_evolution", "the trade evolution still runs at try_evolution")

-- pokefirered/src/trade_scene.c:2649 case 40 then case 41
eq(counts.link_save_delay, 52, "link_save_delay holds pret's 52 frames")
-- pokefirered/src/trade_scene.c:2698 case 5
eq(counts.link_close_delay, 61, "link_close_delay holds pret's 61 frames")

-- pokefirered/src/trade_scene.c:1238 StringCopy(gStringVar1, gLinkPlayers[mpId ^ 1].name)
check(texts.send_msg and texts.send_msg:find("TRIS", 1, true) ~= nil,
  "the send-off names the peer: " .. tostring(texts.send_msg))
check(texts.new_mon_msg and texts.new_mon_msg:find("TRIS", 1, true) ~= nil,
  "the reveal names the peer: " .. tostring(texts.new_mon_msg))
-- pokefirered/src/trade_scene.c:2572 gText_CommunicationStandby5
check(texts.link_standby and texts.link_standby:find("standby", 1, true) ~= nil,
  "the standby window is drawn: " .. tostring(texts.link_standby))
-- pokefirered/src/trade_scene.c:2594 gText_SavingDontTurnOffThePower2
check(texts.link_save and texts.link_save:find("SAVING", 1, true) ~= nil,
  "the saving window is drawn: " .. tostring(texts.link_save))
check(total > 0, "the link cinema ran " .. total .. " frames")

print("[test] 2. the link gates park the scene until the transport answers")
TradeScene.play(OFFER, RECEIVED, nil, { art = ART, peer = PEER, awaitPeer = true, awaitSave = true })
local parked = 0
while parked < 20000 do
  parked = parked + 1
  if TradeScene.step() then break end
  local ph = TradeScene.phase()
  if ph == "link_wait_peer" and parked > 1 then break end
end
eq(TradeScene.phase(), "link_wait_peer", "the scene waits for the peer's finish confirmation")
check(TradeScene.isLink(), "the scene reports itself as a link trade")
TradeScene.peerConfirmed()
local guard = 0
while guard < 20000 do
  guard = guard + 1
  if TradeScene.step() then break end
  if TradeScene.phase() == "link_standby" and guard > 1 then break end
end
eq(TradeScene.phase(), "link_standby", "the scene waits on the link task at link_standby")
TradeScene.linkTaskDone()
guard = 0
while guard < 20000 do
  guard = guard + 1
  if TradeScene.step() then break end
  if TradeScene.phase() == "link_save" and guard > 1 then break end
end
eq(TradeScene.phase(), "link_save", "the scene waits on the save at link_save")
TradeScene.saveDone()
guard = 0
while guard < 20000 do
  guard = guard + 1
  if TradeScene.step() then break end
end
check(not TradeScene.isOpen(), "the scene finished once the transport answered, frames=" .. guard)

print("[test] 3. the in-game arm keeps pret's own ordering")
swapAt, evolveAt = nil, nil
local igOrder = run(OFFER, RECEIVED, {
  art = ART,
  onSwap = function() swapAt = TradeScene.phase() end,
  onEvolve = function() evolveAt = TradeScene.phase() end,
})
local igAt = {}
for i, name in ipairs(igOrder) do igAt[name] = i end
-- pokefirered/src/trade_scene.c:1776 TradeMons runs in STATE_TRY_EVOLUTION for an in-game trade
eq(swapAt, "try_evolution", "an in-game trade swaps the party at try_evolution")
eq(evolveAt, "try_evolution", "and evolves in the same state")
for _, name in ipairs({
  "link_wait_peer", "link_standby", "link_save", "link_save_delay", "link_close_delay",
}) do
  eq(igAt[name], nil, "the in-game arm has no " .. name)
end

-- pokefirered/src/trade.c:1293 CB_FadeToStartTrade
local fadeOrder, fadeCounts = run(OFFER, RECEIVED, { art = ART, peer = PEER, fadeIn = true })
eq(fadeOrder[1], "fade_to_black", "a link entry can lead in with pret's fade to black")
eq(fadeOrder[2], "wait_fade_to_black", "and waits for it")
eq(fadeCounts.wait_fade_to_black, 16, "the lead-in fade is pret's 16 frames")
eq(fadeOrder[3], "start", "then the cinema starts")
eq(order[1], "start", "a caller that faded for itself gets no lead-in")

print("[test] 4. OT identity, the outsider rule and the met stamps")
-- pokefirered/src/pokemon.c:5974 IsOtherTrainer
check(not Pokemon.isOtherTrainer(4242, "RED", session), "the player's own mon is not an outsider")
check(Pokemon.isOtherTrainer(1985, "RED", session), "a different trainer id is an outsider")
check(Pokemon.isOtherTrainer(4242, "BLUE", session), "the same id with another name is an outsider")
-- pokefirered/src/pokemon.c:5985
check(not Pokemon.isOtherTrainer(4242, "RED", { trainerId = 4242, name = "REDX" }),
  "pret stops at the OT name terminator, so a prefix still counts as the owner")
check(Pokemon.isOtherTrainer(4242, "REDX", { trainerId = 4242, name = "RED" }),
  "a longer OT name than the player's is an outsider")
check(not Pokemon.isTradedMon({ species = 25 }, session), "a mon with no OT id is not traded")
check(Pokemon.isTradedMon({ species = 122, otId = 1985, otName = "REYLEY" }, session),
  "a mon from REYLEY is a traded mon")

session.party = {}
local ok1 = Party.giveMon(session, 25, 9, "PIKA")
check(ok1, "the player's own mon was created")
local mine = session.party[1]
-- pokefirered/src/pokemon.c:1819
eq(mine.metGame, Party.VERSION_FIRE_RED, "a mon created on this cart is stamped FIRE RED")
-- pokefirered/src/pokemon.c:1822
eq(mine.otGender, 0, "a male player's mon is stamped OT gender 0")
eq(mine.metLevel, 9, "the met level is the level it was created at")
check(not Pokemon.isTradedMon(mine, session), "the player's own new mon obeys")
local girl = { party = {}, name = "LEAF", trainerId = 7, gender = "female" }
Party.giveMon(girl, 25, 5)
eq(girl.party[1].otGender, 1, "a female player's mon is stamped OT gender 1")

if not cacheRoot then
  print("[skip] the in-game trade mon needs an imported cache")
else
  -- pokefirered/src/trade_scene.c:2461 METLOC_IN_GAME_TRADE
  session.party = { { species = 63, nickname = "ABRA", level = 17, otName = "RED", otId = 4242 } }
  local traded = Trade.createTradeMon(0, Trade.levelOfSlot(0))
  check(traded ~= nil, "the in-game trade mon was built")
  if traded then
    eq(traded.otName, "REYLEY", "the received mon keeps REYLEY as its OT name")
    eq(traded.otId, 1985, "the received mon keeps REYLEY's trainer id")
    eq(traded.otGender, 0, "the received mon keeps REYLEY's OT gender")
    eq(traded.metLocation, 0xFE, "the received mon is stamped METLOC_IN_GAME_TRADE")
    eq(traded.metLevel, 17, "the met level is the level the player's mon was at")
    check(Pokemon.isTradedMon(traded, session), "the received mon is an outsider that can disobey")
    local sent = Trade.tradeMons(session, 0, traded)
    check(sent ~= nil, "the swap ran")
    eq(session.party[1], traded, "the received mon took the slot")
    eq(session.party[1].otName, "REYLEY", "and still carries REYLEY after the swap")
    eq(session.party[1].otId, 1985, "and still carries REYLEY's id after the swap")
    -- pokefirered/src/trade_scene.c:1075
    eq(session.party[1].friendship, 70, "a traded mon starts back at friendship 70")
  end
end

print("[test] 5. the traded-mon experience bonus")
if not cacheRoot then
  print("[skip] the exp bonus needs an imported cache")
else
  local Experience = require("src.core.game3.battle.experience")
  local plain = Experience.gainFor(19, 10, { participants = 1 })
  local boosted = Experience.gainFor(19, 10, { participants = 1, traded = true })
  check(plain > 0, "the plain award is " .. plain)
  -- pokefirered/src/battle_script_commands.c:3239
  eq(boosted, math.floor(plain * 150 / 100), "a traded mon gets pret's 1.5x once")
  local both = Experience.gainFor(19, 10, { participants = 1, traded = true, luckyEgg = true })
  eq(both, math.floor(math.floor(plain * 150 / 100) * 150 / 100),
    "the Lucky Egg and the trade bonus stack the way pret floors them")
  local st = { playerTrainerId = 4242, playerOtName = "RED" }
  local opts = Experience.recipientOpts(st, { species = 122, otId = 1985, otName = "REYLEY" })
  check(opts.traded == true, "a traded mon is flagged for the bonus by the battle layer")
  local ownOpts = Experience.recipientOpts(st, { species = 25, otId = 4242, otName = "RED" })
  check(ownOpts.traded ~= true, "the player's own mon is not flagged")
end

print("[test] 6. mail rides across opaquely")
Trade.clearPartnerMail()
local letter = Mail.clear(nil)
letter.playerName = "DONTAE"
letter.trainerId = 36728
letter.species = 124
letter.itemId = 131
letter.words[1] = 3613
check(Trade.setPartnerMail(0, letter), "the transport handed the peer's letter over")
session.party = { { species = 63, nickname = "ABRA", level = 12 } }
session.mail = nil
local arriving = {
  species = 124, nickname = "ZYNX", level = 12, otName = "DONTAE", otId = 36728,
  item = 131, heldItem = 131, mail = 0,
}
-- pokefirered/src/trade_scene.c:1078
Trade.tradeMons(session, 0, arriving)
local mailId = tonumber(session.party[1].mail)
check(mailId ~= nil and mailId ~= Mail.MAIL_NONE, "the received mon still holds mail, id=" .. tostring(mailId))
local stored = mailId and Mail.slot(session, mailId)
eq(stored and stored.playerName, "DONTAE", "the letter kept its author")
eq(stored and stored.words[1], 3613, "the letter kept its easy-chat words")

print("[test] 7. the refusals pret prints before the scene starts")
-- pokefirered/src/trade.c:2745 CanTradeSelectedMon
local party = {
  { species = 63, nickname = "ABRA", level = 12 },
  { species = 25, nickname = "PIKA", level = 9 },
}
eq(Trade.canTradeSelectedMon(party, 0, { nationalDex = true }), Trade.CAN_TRADE_MON,
  "two mons, either may go")
eq(Trade.canTradeSelectedMon({ party[1] }, 0, { nationalDex = true }), Trade.CANT_TRADE_LAST_MON,
  "the last mon cannot be traded")
-- pokefirered/src/trade.c:2801 eggs do not count towards the mons left behind
eq(Trade.canTradeSelectedMon({
  party[1], { species = 25, isEgg = true, level = 5 },
}, 0, { nationalDex = true }), Trade.CANT_TRADE_LAST_MON,
  "an egg does not count as the mon you leave behind")
-- pokefirered/src/trade.c:2769 the retail build answers CANT_TRADE_NATIONAL for an egg
eq(Trade.canTradeSelectedMon({
  { species = 25, isEgg = true, level = 5 }, party[2],
}, 0, { nationalDex = false }), Trade.CANT_TRADE_NATIONAL,
  "without the National Dex an egg answers the cart's national refusal")
eq(Trade.canTradeSelectedMon({
  { species = 252, nickname = "TREECKO", level = 5 }, party[2],
}, 0, { nationalDex = false }), Trade.CANT_TRADE_NATIONAL,
  "without the National Dex a non-Kanto mon cannot be traded")
-- pokefirered/src/trade.c:2789
eq(Trade.canTradeSelectedMon({
  { species = 25, isEgg = true, level = 5 }, party[2],
}, 0, { nationalDex = true, partner = { version = 4, progressFlags = 0 } }),
  Trade.CANT_TRADE_PARTNER_EGG_YET,
  "a partner without the National Dex refuses an egg")
eq(Trade.canTradeSelectedMon({
  { species = 252, nickname = "TREECKO", level = 5 }, party[2],
}, 0, { nationalDex = true, partner = { version = 4, progressFlags = 0 } }),
  Trade.CANT_TRADE_INVALID_MON,
  "a partner without the National Dex refuses a non-Kanto mon")
eq(Trade.canTradeSelectedMon({
  { species = 252, nickname = "TREECKO", level = 5 }, party[2],
}, 0, { nationalDex = true, partner = { version = 2, progressFlags = 0 } }),
  Trade.CAN_TRADE_MON,
  "a Ruby partner is not asked for its National Dex")
-- pokefirered/src/trade.c:2795
eq(Trade.canTradeSelectedMon({
  { species = 410, nickname = "DEOXYS", level = 30, fatefulEncounter = false }, party[2],
}, 0, { nationalDex = true }), Trade.CANT_TRADE_INVALID_MON,
  "an illegal DEOXYS cannot be traded")
eq(Trade.canTradeSelectedMon({
  { species = 151, nickname = "MEW", level = 30, fatefulEncounter = false }, party[2],
}, 0, { nationalDex = true }), Trade.CANT_TRADE_INVALID_MON,
  "an illegal MEW cannot be traded")
eq(Trade.canTradeSelectedMon({
  { species = 151, nickname = "MEW", level = 30 }, party[2],
}, 0, { nationalDex = true }), Trade.CAN_TRADE_MON,
  "a legitimate MEW may be traded")

-- pokefirered/src/field_specials.c:2458 IsBadEggInParty
check(not Trade.hasBadEgg(party), "a clean party has no bad egg")
check(Trade.hasBadEgg({ party[1], { species = 0, isBadEgg = true } }),
  "a bad egg in the party is found")

check(Trade.refusalText(Trade.CANT_TRADE_LAST_MON):find("only", 1, true) ~= nil,
  "the last-mon refusal is pret's text: " .. Trade.refusalText(Trade.CANT_TRADE_LAST_MON))
check(Trade.refusalText(Trade.CANT_TRADE_EGG_YET):find("EGG", 1, true) ~= nil,
  "the egg refusal is pret's text: " .. Trade.refusalText(Trade.CANT_TRADE_EGG_YET))
check(Trade.refusalText(Trade.CANT_TRADE_NATIONAL):find("can't be traded", 1, true) ~= nil,
  "the national refusal is pret's text: " .. Trade.refusalText(Trade.CANT_TRADE_NATIONAL))
eq(Trade.refusalText(Trade.CAN_TRADE_MON), nil, "a tradeable mon has no refusal text")
check(Trade.badEggText():find("can't be taken", 1, true) ~= nil,
  "the bad-egg abort is pret's cable club text: " .. Trade.badEggText())

finish()
