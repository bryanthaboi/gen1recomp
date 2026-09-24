#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
local Cache = require("tests.game3_cache")
if not Cache.mount("meta.json") then
  print("[skip] link trade: " .. tostring(Cache.reason))
  os.exit(0)
end
require("tests.fixture_data.game3_items").install()
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

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

local TRADE_CENTER = "FR_TRADE_CENTER"
local COUNTER_MAP = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local UNION_MAP = "FR_UNION_ROOM"

local MAPS = {
  [COUNTER_MAP] = {
    warps = { { x = 9, y = 1, destMap = TRADE_CENTER, destWarp = 1 } },
  },
  [TRADE_CENTER] = {
    warps = { { x = 5, y = 8, mapGroup = 0x7F, mapNum = 0x7F, destWarp = 128 } },
  },
  [UNION_MAP] = {
    warps = { { x = 7, y = 11, mapGroup = 0x7F, mapNum = 0x7F, destWarp = 128 } },
  },
}

local function mon(species, level, _, extra)
  local holder = { name = "RED", trainerId = 0x1234, party = {} }
  require("src.core.game3.party").giveMon(holder, species, level)
  local m = holder.party[1]
  m.friendship, m.happiness = 120, 120
  for k, v in pairs(extra or {}) do m[k] = v end
  if m.otName then m.ot = m.otName end
  return m
end

local store = { flags = {}, vars = {} }
local session = {
  store = store,
  map = TRADE_CENTER,
  x = 5,
  y = 8,
  name = "RED",
  gender = 0,
  trainerId = 0x1234,
  party = { mon(1, 10), mon(4, 12) },
  bag = { pockets = { items = {} } },
}
local game = { data = { maps = MAPS }, session = session }

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
  _mod = nil,
}
package.loaded["src.core.game3.player"] = { cellX = 5, cellY = 8, facing = "up" }
local questEvents = {}
package.loaded["src.core.game3.quest_log_recorder"] = {
  event = function(s, key, args) questEvents[#questEvents + 1] = { s = s, key = key, args = args } end,
}
package.loaded["src.core.game3.map"] = { load = function() end, current = TRADE_CENTER }
package.loaded["src.core.game3.objects"] = {
  addObject = function() return true end,
  removeObject = function() return true end,
  refreshGraphics = function() return 0 end,
}

local ctx = { specialVars = {}, stringVars = {} }
local adapters = { log = function() end, playSe = function() end }
package.loaded["src.core.game3.scripting.space"] = {
  store = store,
  mapId = TRADE_CENTER,
  vm = { ctx = ctx, adapters = adapters },
}

local Natives = require("src.core.game3.scripting.natives")
local NativesLink = require("src.core.game3.scripting.natives_link")
local Link = require("src.core.game3.link")
local LT = require("src.core.game3.link.trade")
local Union = require("src.core.game3.link.union_room")
local Trade = require("src.core.game3.scripting.natives_trade")
local TradeScene = require("src.core.game3.trade_scene")
local FakeRelay = require("tests.g3link_fake_relay")

local peer

local function openLink()
  Link.reset()
  LT.reset()
  LT.loopbackCommit = false
  local host, other = FakeRelay.pair({ game = game })
  host:update(0)
  other:update(0)
  Link.attach(host)
  peer = other
  return host
end

local function pumpPeer(handler)
  if not peer then return end
  peer:update(0)
  local msg = peer:take(LT.MSG.CMD)
  while msg do
    if handler then handler(msg) end
    msg = peer:take(LT.MSG.CMD)
  end
end

local function peerSend(message)
  if peer then peer:send(message) end
end

local Protocol = require("src.link.Protocol")
local Wire = require("src.link.Wire")

local function packedParty(list)
  local idx = {}
  for i = 1, #list do idx[i] = i end
  return Protocol.packParty3(list, idx)
end

local function peerParty(list, extra)
  local msg = { type = LT.MSG.PARTY, party = packedParty(list), name = "BLUE",
    trainerId = 0x2222, gender = 0, version = 4, progressFlags = 0 }
  for k, v in pairs(extra or {}) do msg[k] = v end
  peerSend(msg)
end

local function peerMon(block, m, extra)
  local msg = { type = LT.MSG.MON, name = "BLUE", trainerId = 0x2222, mon = Protocol.packMon3(m) }
  for k, v in pairs(extra or {}) do msg[k] = v end
  peerSend(msg)
  local theirs = Wire.sanitize(msg).mon
  peerSend({ type = LT.MSG.CONFIRM, digest = Protocol.tradeDigest(block.mon, theirs) })
end

local function runTrade()
  local before, guard, confirms = LT.completed, 0, 0
  while guard < 4000 and LT.completed == before do
    pumpPeer(function(msg)
      -- pokefirered/src/trade_scene.c:2344
      if msg.cmd == LT.LINKCMD.CONFIRM_FINISH_TRADE then
        confirms = confirms + 1
        peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.CONFIRM_FINISH_TRADE })
      end
    end)
    LT.update(0)
    guard = guard + 1
  end
  return LT.completed > before, confirms
end

print("[test] 2. the trade menu exchanges both parties before anything is chosen")
openLink()
session.party = { mon(1, 10), mon(4, 12) }
LT.startMenu()
peer:update(0)
local sentParty = peer:take(LT.MSG.PARTY)
check(sentParty ~= nil, "this machine sent its party to the other one")
eq(sentParty and sentParty.name, "RED", "with the player's name on it")
eq(sentParty and #sentParty.party, 2, "two mons")
eq(sentParty and sentParty.party[1].species, 1, "the lead is BULBASAUR")
-- pokefirered/src/trade.c:1435 Trade_Memcpy
eq(sentParty and sentParty.party[1].maxHp, nil, "packed with packMon3: no stats go on the wire")
eq(sentParty and sentParty.party[1].moves and sentParty.party[1].moves[1]
  and sentParty.party[1].moves[1].id, session.party[1].moves[1],
  "and its moves for the selected-mon screen and summary")
local blueSquirtle = mon(7, 11, nil, { otName = "BLUE", otId = 0x2222, friendship = 40 })
peerParty({ mon(25, 9), blueSquirtle })
LT.update(0)
eq(LT.peer and LT.peer.name, "BLUE", "the other player introduced itself")
eq(#LT.peerParty, 2, "and its party is on this screen")
check((LT.peerParty[1].maxHp or 0) > 0, "with stats recomputed by the strict unpack")
eq(LT.state, "menu", "the trade menu is up")

print("[test] 3. the offer both machines have to agree on")
eq(LT.isLeader(), true, "this machine is the link leader")
check(LT.offer(1), "the player offers the mon in slot 1")
eq(LT.playerSelectStatus, LT.STATUS.READY, "which is STATUS_READY for the leader itself")
eq(LT.cursor, 0, "at cursor 0")
eq(LT.state, "ready_wait", "and the leader waits for the other machine")
LT.update(0)
eq(LT.state, "ready_wait", "one ready side is not a trade")
-- pokefirered/src/trade.c:1811 SetReadyToTrade
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 1 })
LT.update(0)
eq(LT.partnerCursor, 1, "the other machine named its own mon")
eq(LT.state, "confirm", "so both selections are locked in")
local sawSetMons = false
pumpPeer(function(msg)
  if msg.cmd == LT.LINKCMD.SET_MONS_TO_TRADE then sawSetMons = true end
end)
check(sawSetMons, "the leader told the other machine which two mons are on the table")

print("[test] 4. CheckValidityOfTradeMons before the block exchange")
eq(LT.checkValidityOfTradeMons(1, 2), LT.BOTH_MONS_VALID, "two ordinary mons are valid")
local keepParty = session.party
session.party = { mon(1, 10) }
eq(LT.checkValidityOfTradeMons(1, 2), LT.PLAYER_MON_INVALID,
  "trading away the only mon left is PLAYER_MON_INVALID")
session.party = keepParty
local keepPeerParty, keepPeerPacked = LT.peerParty, LT._peerPacked
-- pokefirered/src/trade.c:1955 the partner cannot trade an illegitimate DEOXYS or MEW
peerParty({ mon(410, 30, nil, { fatefulEncounter = false }) }, { version = 0, progressFlags = 1 })
LT.pump()
eq(LT.checkValidityOfTradeMons(1, 1), LT.PARTNER_MON_INVALID,
  "an illegitimate DEOXYS on the other machine is PARTNER_MON_INVALID")
LT.peerParty, LT._peerPacked = keepPeerParty, keepPeerPacked

print("[test] 5. both confirmations, then the mons go over the cable")
check(LT.confirm(true), "the player answers YES to IS THIS TRADE OKAY?")
eq(LT.lastResult, LT.BOTH_MONS_VALID, "with both mons valid")
eq(LT.playerConfirmStatus, LT.STATUS.READY, "LINKCMD_INIT_BLOCK for the leader itself")
eq(LT.state, "confirm_wait", "and it waits again")
eq(session.party[1].species, 1, "nothing has moved yet")
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.INIT_BLOCK })
LT.update(0)
eq(LT.state, "exchange", "both confirmations start the trade")
local sawStart = false
pumpPeer(function(msg)
  if msg.cmd == LT.LINKCMD.START_TRADE then sawStart = true end
end)
check(sawStart, "the leader sent LINKCMD_START_TRADE")
peer:update(0)
local block = peer:take(LT.MSG.MON)
check(block ~= nil, "this machine put its mon on the cable")
eq(block and block.mon.species, 1, "the mon it offered")
eq(session.party[1].species, 1, "and the party still holds it until the other one arrives")
eq(#session.party, 2, "with nothing lost")

print("[test] 6. the swap only happens after the commit, once both mons are in hand")
local saves = 0
function game:saveGame() saves = saves + 1 end
peerSend({ type = LT.MSG.MON, name = "BLUE", trainerId = 0x2222,
  mon = Protocol.packMon3(blueSquirtle) })
LT.update(0)
eq(LT.state, "commit_wait", "both blocks in hand: the confirm went out and it waits for the commit")
peer:update(0)
local sentConfirm = peer:take(LT.MSG.CONFIRM)
check(sentConfirm and type(sentConfirm.digest) == "string" and #sentConfirm.digest == 16,
  "game3_trade_confirm carries a 16 hex digest")
eq(TradeScene.isOpen(), false, "no cinema before the commit")
peerSend({ type = LT.MSG.CONFIRM, digest = sentConfirm and sentConfirm.digest })
LT.update(0)
eq(LT.state, "scene", "the commit starts the trade cinema")
eq(TradeScene.isLink(), true, "on its link arm")
eq(session.party[1].species, 1, "the party is untouched while the cinema plays")
local finished, confirms = runTrade()
check(finished, "and it runs to the end of the link tail")
eq(saves, 1, "the save was written once, after the commit")
eq(LT.state, "menu", "then the TRADE CENTER returns to the trade menu")
eq(confirms, 1, "each machine confirms the finished trade exactly once")
eq(session.party[1].species, 7, "SQUIRTLE is in the party now")
eq(session.party[1].otName, "BLUE", "with the other player as its OT")
eq(#session.party, 2, "and the party is still two mons")
-- pokefirered/src/trade_scene.c:1075 TradeMons
eq(session.party[1].friendship, 70, "friendship reset to 70 by TradeMons")
check(session.dex and session.dex.owned and session.dex.owned[7] == true,
  "and the received mon is entered in the POKeDEX")
-- pokefirered/src/trade_scene.c:2606
eq(session.gameStats and session.gameStats[21], 1, "GAME_STAT_POKEMON_TRADES counts the trade")
-- pokefirered/src/trade_scene.c:2605
local ql = questEvents[#questEvents]
eq(ql and ql.key, "TradedMon1ForPersonsMon2", "the quest log records QL_EVENT_LINK_TRADED")
eq(ql and ql.args.S1, "BLUE", "naming the partner")
eq(ql and ql.s, session, "on this player's session")

print("[test] 7. a cancel from the other machine leaves the party alone")
openLink()
session.party = { mon(1, 10), mon(4, 12) }
LT.startMenu()
peer:update(0)
peer:take(LT.MSG.PARTY)
peerParty({ mon(7, 11) })
LT.update(0)
LT.offer(1)
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.REQUEST_CANCEL })
LT.update(0)
eq(LT.state, "canceled", "the trade was canceled")
eq(LT.lastResult, "partner_canceled", "because the other player pressed CANCEL")
eq(session.party[1].species, 1, "the party never changed")
local sawPartnerCancel = false
pumpPeer(function(msg)
  if msg.cmd == LT.LINKCMD.PARTNER_CANCEL_TRADE then sawPartnerCancel = true end
end)
check(sawPartnerCancel, "and the other machine was told so")

print("[test] 8. a cable pulled mid-trade loses nothing")
openLink()
session.party = { mon(1, 10), mon(4, 12) }
LT.startMenu()
peer:update(0)
peer:take(LT.MSG.PARTY)
local pulledSquirtle = mon(7, 11)
peerParty({ pulledSquirtle })
LT.update(0)
LT.offer(1)
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 0 })
LT.update(0)
LT.confirm(true)
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.INIT_BLOCK })
LT.update(0)
eq(LT.state, "exchange", "the trade reached the block exchange")
peer:update(0)
local pulledBlock = peer:take(LT.MSG.MON)
peerSend({ type = LT.MSG.MON, name = "BLUE", trainerId = 0x2222,
  mon = Protocol.packMon3(pulledSquirtle) })
LT.update(0)
eq(LT.state, "commit_wait", "both blocks crossed and the confirm went out")
check(pulledBlock ~= nil, "the offered mon went over the cable")
saves = 0
peer:close("cable_pulled")
LT.update(0)
eq(LT.state, "off", "the session closed when the cable was pulled before the commit")
eq(LT.lastResult, "peer_dropped", "as a dropped peer")
eq(session.party[1].species, 1, "the offered mon is still in the party")
eq(#session.party, 2, "and the party is whole")
eq(saves, 0, "and nothing was saved")
eq(TradeScene.isOpen(), false, "with no cinema left on screen")

print("[test] 9. the mons the trade menu refuses")
openLink()
-- pokefirered/src/trade.c:2767 the retail build answers CANT_TRADE_NATIONAL for an EGG
session.party = { mon(1, 10), mon(4, 12, 99, { isEgg = true }) }
LT.startMenu()
peerParty({ mon(7, 11) })
LT.pump()
local ok, code = LT.offer(2)
eq(ok, false, "an EGG is refused")
eq(code, Trade.CANT_TRADE_NATIONAL,
  "with the retail CANT_TRADE_NATIONAL answer, not the egg string")
session.party = { mon(1, 10), mon(4, 12, 99, { isEgg = true }) }
local ok2, code2 = LT.offer(1)
eq(ok2, false, "the last mon that is not an EGG is refused too")
eq(code2, Trade.CANT_TRADE_LAST_MON, "as CANT_TRADE_LAST_MON")
check(Trade.refusalText(code2) ~= nil, "and the refusal has a message")
-- pokefirered/data/scripts/cable_club.inc:414 CheckPartyTradeRequirements
session.party = { mon(1, 10), mon(4, 12, 99, { heldItem = 175 }) }
local yieldB, berry = Natives.special(ctx, 0x153, adapters)
eq(yieldB, false, "DoesPartyHaveEnigmaBerry does not yield")
eq(berry, 1, "the counter refuses a party carrying an ENIGMA BERRY")
session.party = { mon(1, 10), mon(4, 12, 99, { isBadEgg = true }) }
check(Trade.hasBadEgg(session.party), "and a BAD EGG party is refused at the counter")

print("[test] 10. the union room trading board trade")
openLink()
Union.reset()
session.party = { mon(1, 10), mon(67, 30, 4242) }
session.gameStats = {}
local record = Union.trade()
eq(record.species, 0, "the trading board starts with no registered mon")
-- pokefirered/src/union_room.c:4600 RegisterTradeMonAndGetIsEgg
local isEgg = LT.registerTradeMonAndGetIsEgg(2)
eq(isEgg, false, "registering MACHOKE is not an egg registration")
eq(Union.trade().playerSpecies, 67, "the board shows the registered species")
eq(Union.trade().playerLevel, 30, "and its level")
-- pokefirered/src/union_room.c:4618 GetPartyPositionOfRegisteredMon
eq(LT.partyPositionOfRegisteredMon(Union.trade(), true), 1,
  "the registered mon is found in party slot 2")
check(LT.startUnionRoomTrade(), "the board trade starts")
eq(LT.unionRoom, true, "as a union room trade")
eq(LT.cursor, 1, "offering the registered mon")
eq(session.gameStats[50], 1, "and GAME_STAT_NUM_UNION_ROOM_BATTLES went up, as in pret")
peer:update(0)
local urBlock = peer:take(LT.MSG.MON)
eq(urBlock and urBlock.mon.species, 67, "the registered mon went over the wire")
peerMon(urBlock, mon(25, 9, nil, { otName = "BLUE", otId = 0x2222 }))
LT.update(0)
LT.update(0)
eq(LT.state, "scene", "the union room trade goes through the same commit to the same cinema")
check(runTrade(), "and finishes")
eq(LT.state, "done", "a union room trade does not reopen the trade menu")
eq(session.party[2].species, 25, "PIKACHU came back for MACHOKE")
-- pokefirered/src/trade_scene.c:2601
eq(session.gameStats[21], nil, "a union room trade leaves GAME_STAT_POKEMON_TRADES alone")
eq(questEvents[#questEvents] and questEvents[#questEvents].key, "TradedMon1ForTrainersMon2",
  "and logs QL_EVENT_LINK_TRADED_UNION")
-- pokefirered/src/union_room.c:1746 ResetUnionRoomTrade
eq(Union.trade().playerSpecies, 0, "and the trading board registration was cleared")

print("[test] 11. trade evolution on the mon that just arrived, saved after it evolved")
openLink()
session.party = { mon(1, 10), mon(4, 12) }
session.dex = { seen = {}, owned = {} }
LT.startMenu()
peer:update(0)
peer:take(LT.MSG.PARTY)
local blueMachoke = mon(67, 30, nil, { otName = "BLUE", otId = 0x2222 })
peerParty({ blueMachoke }, { progressFlags = 1 })
LT.update(0)
LT.offer(1)
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 0 })
LT.update(0)
LT.confirm(true)
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.INIT_BLOCK })
LT.update(0)
peer:update(0)
local evoBlock = peer:take(LT.MSG.MON)
peerMon(evoBlock, blueMachoke)
local savedSpecies
function game:saveGame() savedSpecies = session.party[1].species end
check(runTrade(), "the trade ran to its end")
-- pokefirered/src/trade_scene.c:2322
eq(session.party[1].species, 68, "the MACHOKE that arrived evolved into MACHAMP")
-- pokefirered/src/trade_scene.c:2595
eq(savedSpecies, 68, "and the link save came after the evolution")
game.saveGame = nil

print("[test] 14. the letter the traded mon is holding rides with it")
local Mail = require("src.core.game3.mail")
openLink()
Trade.clearPartnerMail()
session.mail = nil
session.party = { mon(1, 10), mon(4, 12) }
-- pokefirered/include/mail.h:21 ITEM_ORANGE_MAIL
local ORANGE_MAIL = 121
local RETRO_MAIL = 122
-- pokefirered/src/mail_data.c:41 GiveMailToMon
local sentMailId = Mail.giveMailToMon(session, session.party[1], ORANGE_MAIL)
check(sentMailId ~= Mail.MAIL_NONE, "the offered mon is carrying ORANGE MAIL")
LT.startMenu()
peer:update(0)
peer:take(LT.MSG.PARTY)
local mailSquirtle = mon(7, 11, nil, { otName = "BLUE", otId = 0x2222, item = RETRO_MAIL,
  heldItem = RETRO_MAIL })
peerParty({ mailSquirtle })
LT.update(0)
LT.offer(1)
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 0 })
LT.update(0)
LT.confirm(true)
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.INIT_BLOCK })
LT.update(0)
peer:update(0)
-- pokefirered/src/union_room.c:1733 the mail goes out beside the mon
local sentBlock = peer:take(LT.MSG.MON)
check(sentBlock ~= nil, "the offered mon went over the cable")
check(sentBlock and type(sentBlock.mail) == "table", "with its letter beside it")
eq(sentBlock and sentBlock.mail and sentBlock.mail.itemId, ORANGE_MAIL,
  "the same ORANGE MAIL record")
eq(sentBlock and sentBlock.mail and sentBlock.mail.playerName, "RED", "signed by this player")
peerMon(sentBlock, mailSquirtle, {
  mail = {
    itemId = RETRO_MAIL, playerName = "BLUE", trainerId = 0x2222, species = 7, design = 1,
    words = { 1, 2, 3, 4, 5, 6, 7, 8, 9 },
  },
})
LT.update(0)
LT.update(0)
eq(LT.state, "scene", "the cinema starts once both letters are in hand and the trade committed")
-- pokefirered/src/trade_scene.c:2488 gLinkPartnerMail[0] = mail
check(Trade.PARTNER_MAIL[0] ~= nil, "the partner's letter is parked in gLinkPartnerMail")
check(runTrade(), "the trade ran to its end")
eq(session.party[1].species, 7, "the received mon is in the party")
-- pokefirered/src/trade_scene.c:1078 GiveMailToMon2
check(Mail.monHasMail(session.party[1]), "still holding the letter it came with")
local landed = Mail.get(session, session.party[1].mail)
eq(landed and landed.playerName, "BLUE", "written by the other player")
eq(landed and landed.itemId, RETRO_MAIL, "on the RETRO MAIL it was sent on")
eq(landed and landed.words and landed.words[1], 1, "with the words it was written with")
-- pokefirered/src/trade_scene.c:1066 ClearMailStruct
local orangeLeft = 0
for _, record in ipairs(Mail.pool(session)) do
  if (tonumber(record.itemId) or 0) == ORANGE_MAIL then orangeLeft = orangeLeft + 1 end
end
eq(orangeLeft, 0, "the letter the sent mon carried left this save with it")
eq(session.party[1].mail, sentMailId,
  "and the arriving letter took the slot it freed, as GiveMailToMon does")

print("[test] 15. the seat's own select screen drives the offer and the confirmation")
Link.reset()
LT.reset()
local Menu = require("src.ui.game3.link_trade_menu")
Menu.reset()
openLink()
session.party = { mon(1, 10), mon(4, 12) }
-- pokefirered/src/cable_club.c:958 StartWiredCableClubTrade ends in the trade menu
Natives.special(ctx, NativesLink.SPECIAL.StartWiredCableClubTrade, adapters)
eq(LT.state, "menu", "the wired seat lands in the trade menu")
check(Menu.show(), "and the select screen is up for the player")
local function tick(n)
  for _ = 1, n or 1 do
    LT.update(0)
    Menu.update(0)
  end
end
tick(1)
-- pokefirered/src/trade.c:853
eq(Menu.cb, "loading", "the screen holds on standby until the other party arrives")
eq(Menu.message, "gText_Trade_CommunicationStandby", "with the standby message up")
peerParty({ mon(7, 11), mon(25, 14) }, { version = 0, progressFlags = 1 })
tick(12)
eq(#LT.peerParty, 2, "the other machine's party arrived over the wire")
eq(Menu.cb, "main", "then the grid takes input once the fade is done")
eq(Menu.message, nil, "and the standby message is gone")
eq(Menu.pos, 0, "the cursor starts on this machine's lead")
local press = function(key)
  return { wasPressed = function(_, k) return k == key end }
end
-- pokefirered/src/trade.c:349 sCursorMoveDestinations
Menu.handleInput(press("down"))
eq(Menu.pos, 12, "DOWN from slot 0 skips the empty rows and lands on CANCEL")
Menu.handleInput(press("up"))
eq(Menu.pos, 7, "UP from CANCEL lands on the other machine's second mon")
Menu.handleInput(press("left"))
eq(Menu.pos, 6, "LEFT walks the other machine's row")
Menu.handleInput(press("left"))
eq(Menu.pos, 1, "LEFT again crosses to this machine's second mon")
eq(Menu.cursor, 2, "which is own slot 2")
Menu.handleInput(press("left"))
eq(Menu.pos, 0, "and LEFT reaches the lead")
eq(Menu.cursor, 1, "own slot 1")
-- pokefirered/src/trade.c:1847
Menu.handleInput(press("a"))
eq(Menu.cb, "selected", "A on an own mon opens SUMMARY / TRADE instead of offering it")
check(Menu.submenuVisible, "the SUMMARY / TRADE window is drawn")
eq(LT.state, "menu", "nothing was offered yet")
Menu.handleInput(press("b"))
eq(Menu.cb, "main", "B closes the submenu")
check(not Menu.submenuVisible, "and erases it")
Menu.handleInput(press("a"))
Menu.handleInput(press("down"))
eq(Menu.subCursor, 2, "DOWN moves to TRADE")
-- pokefirered/src/trade.c:1811 SetReadyToTrade
Menu.handleInput(press("a"))
eq(LT.state, "ready_wait", "TRADE offers the mon, with no hand-fed LT.offer call")
eq(LT.cursor, 0, "and the offered slot is the one the cursor was on")
eq(Menu.message, "gText_Trade_CommunicationStandby", "the standby message comes up")
check(not Menu.cursorVisible, "and the cursor is hidden")
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 1 })
tick(1)
eq(LT.state, "confirm", "both machines have picked, so the confirmation comes up")
eq(Menu.cb, "selected_mons", "the chosen mons slide to the middle first")
eq(Menu.message, nil, "the standby message is cleared")
eq(Menu.selected[0].idx, 0, "this machine's pick is its lead")
eq(Menu.selected[1].idx, 1, "the other machine's pick is its second mon")
tick(30)
eq(Menu.cb, "okay_wait", "both selected-mon screens finished drawing")
eq(Menu.bottom, "okay", "and the bottom row asks IS THIS TRADE OKAY?")
check(not Menu.confirming, "the YES / NO is not up yet")
-- pokefirered/src/trade.c:2086
tick(121)
check(Menu.confirming, "the YES / NO comes up 120 frames later")
Menu.handleInput(press("a"))
eq(LT.state, "confirm_wait", "A on YES answers the prompt through LT.confirm")
eq(LT.playerConfirmStatus, LT.STATUS.READY, "with LINKCMD_INIT_BLOCK for the leader itself")
tick(5)
eq(Menu.message, "gText_Trade_CommunicationStandby", "and standby is queued behind the answer")
Menu.reset()
LT.reset()

print("[test] 16. CANCEL asks first, and a crossed cancel comes back to the grid")
Link.reset()
LT.reset()
Menu.reset()
openLink()
session.party = { mon(1, 10), mon(4, 12) }
LT.startMenu()
Menu.show()
peerParty({ mon(7, 11) }, { version = 0, progressFlags = 1 })
tick(12)
Menu.handleInput(press("b"))
eq(Menu.cb, "main", "B on the grid does nothing")
eq(LT.state, "menu", "and cancels nothing")
Menu.handleInput(press("down"))
eq(Menu.pos, 12, "the cursor is on CANCEL")
-- pokefirered/src/trade.c:1867
Menu.handleInput(press("a"))
eq(Menu.cb, "cancel_prompt", "A on CANCEL asks YES / NO")
eq(Menu.bottom, "cancel", "with the bottom row reading CANCEL TRADE?")
Menu.handleInput(press("b"))
eq(Menu.cb, "main", "B answers NO")
eq(Menu.bottom, "choose", "and the bottom row is back to CHOOSE A POKeMON")
Menu.handleInput(press("a"))
Menu.handleInput(press("a"))
eq(LT.state, "ready_wait", "YES cancels through LT.cancelSelect")
eq(LT.playerSelectStatus, LT.STATUS.CANCEL, "as STATUS_CANCEL for the leader")
eq(Menu.message, "gText_WaitingForFriendToFinish", "while waiting for the other player")
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 0 })
tick(1)
eq(LT.state, "canceled", "the other machine had picked a mon")
eq(Menu.cb, "trade_canceled", "so the screen reports it")
eq(Menu.message, "gText_FriendWantsToTrade", "as YOUR FRIEND WANTS TO TRADE")
check(Menu.isOpen(), "and stays open")
Menu.handleInput(press("a"))
eq(LT.state, "menu", "A returns both the link and the screen to the grid")
eq(Menu.cb, "main", "the grid takes input again")
check(Menu.cursorVisible, "with the cursor back")
Menu.reset()
LT.reset()

print("[test] 17. a mon that cannot go is refused after the queued delay")
Link.reset()
LT.reset()
Menu.reset()
openLink()
session.party = { mon(1, 10) }
LT.startMenu()
Menu.show()
peerParty({ mon(7, 11) }, { version = 0, progressFlags = 1 })
tick(12)
Menu.handleInput(press("a"))
Menu.handleInput(press("down"))
Menu.handleInput(press("a"))
eq(LT.state, "menu", "the last mon is not offered")
eq(Menu.cb, "trade_canceled", "the screen waits for A")
eq(Menu.message, nil, "the refusal is queued, not printed yet")
-- pokefirered/src/trade.c:86 QUEUE_DELAY_MSG
tick(4)
eq(Menu.message, "gText_OnlyPkmnForBattle", "then it says it is the only POKeMON for battle")
Menu.handleInput(press("a"))
eq(Menu.cb, "main", "A goes back to the grid")
eq(Menu.message, nil, "and clears the message")
Menu.reset()
LT.reset()

print("[test] 19. held D-pad repeats, held items, the partner summary and the exit fades")
Link.reset()
LT.reset()
Menu.reset()
openLink()
session.party = { mon(1, 10, nil, { item = 13 }), mon(4, 12, nil, { heldItem = 121 }) }
LT.startMenu()
Menu.show()
peerParty({ mon(7, 11, nil, { otName = "BLUE", otId = 0x2222 }) }, { version = 0, progressFlags = 1 })
tick(12)
local held = function(key, fresh)
  return {
    wasPressed = function(_, k) return fresh and k == key end,
    isDown = function(_, k) return k == key end,
  }
end
-- pokefirered/src/main.c:309
Menu.handleInput(held("right", true))
eq(Menu.pos, 1, "a fresh RIGHT moves once")
for _ = 1, 39 do Menu.handleInput(held("right")) end
eq(Menu.pos, 1, "holding it does nothing for 40 frames")
Menu.handleInput(held("right"))
eq(Menu.pos, 6, "then JOY_REPT fires and the cursor crosses to the other party")
for _ = 1, 4 do Menu.handleInput(held("right")) end
eq(Menu.pos, 6, "the next repeat waits 5 frames")
Menu.handleInput(held("right"))
eq(Menu.pos, 0, "and the next one wraps RIGHT from 6 back to this machine's lead")
Menu.handleInput({ wasPressed = function() return false end, isDown = function() return false end })
-- pokefirered/src/party_menu.c:2785 DrawHeldItemIconsForTrade
eq(Menu.heldItemFrame(session.party[1]), 0, "a held POTION draws the item icon")
eq(Menu.heldItemFrame(session.party[2]), 1, "held MAIL draws the mail icon")
eq(Menu.heldItemFrame(LT.peerParty[1]), nil, "an empty hand draws nothing")
-- pokefirered/src/trade.c:1946
local SummaryMenu = require("src.ui.game3.summary_menu")
local realOpen = SummaryMenu.openMenu
local seen
SummaryMenu.openMenu = function(party, idx, opts) seen = { party = party, idx = idx, opts = opts } end
Menu.handleInput(press("up"))
Menu.handleInput(press("up"))
eq(Menu.pos, 6, "the cursor is on the partner's lead")
Menu.handleInput(press("a"))
tick(10)
SummaryMenu.openMenu = realOpen
check(seen ~= nil, "A on a partner mon opens its summary")
check(seen and seen.opts.enemyParty == true, "as the enemy party (gText_Somewhere, no move swap)")
eq(seen and seen.opts.owner and seen.opts.owner.playerName, "BLUE", "with the partner as the owner")
eq(seen and seen.opts.owner and seen.opts.owner.trainerId, 0x2222, "and the partner's trainer id")
if seen and seen.opts.onClose then seen.opts.onClose() end
tick(10)
eq(Menu.cb, "main", "the grid is back after the summary")
local savedLove = rawget(_G, "love")
love = { graphics = {} }
LT.state = "exit"
LT.lastResult = "both_canceled"
tick(1)
eq(Menu.cb, "exiting", "a double cancel leaves through CB_InitExitCanceledTrade")
check(Menu.isOpen(), "the screen stays up while it fades")
-- pokefirered/src/trade.c:1721
tick(7)
check(Menu.isOpen() and Menu.fade > 0, "fading to black")
tick(2)
check(not Menu.isOpen(), "and closes once the screen is black")
Menu.reset()
Menu.show()
Menu.cb = "idle"
Menu.fade = 0
LT.state = "exchange"
tick(20)
check(Menu.isOpen() and Menu.fade == 0, "the block exchange keeps the screen up")
LT.state = "commit_wait"
tick(20)
check(Menu.isOpen() and Menu.fade == 0, "and so does waiting for trade_commit")
LT.state = "committed"
-- pokefirered/src/trade.c:1293 CB_FadeToStartTrade
tick(15)
eq(Menu.fade, 0, "the leader holds the screen 16 frames before the trade")
check(Menu.isOpen(), "still up")
tick(1)
tick(8)
check(not Menu.isOpen(), "then fades to black and hands off to the trade scene")
love = savedLove
Menu.reset()
LT.reset()

print("[test] 20. a block that is not the mon the other party showed is refused")
openLink()
session.party = { mon(1, 10), mon(4, 12) }
LT.startMenu()
peer:update(0)
peer:take(LT.MSG.PARTY)
peerParty({ mon(7, 11) }, { version = 0, progressFlags = 1 })
LT.update(0)
LT.offer(1)
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 0 })
LT.update(0)
eq(LT.checkValidityOfTradeMons(1, 1), LT.BOTH_MONS_VALID, "the previewed SQUIRTLE passes the validity check")
LT.confirm(true)
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.INIT_BLOCK })
LT.update(0)
eq(LT.state, "exchange", "the block exchange started")
peer:update(0)
peer:take(LT.MSG.MON)
pumpPeer()
-- pokefirered/src/trade.c:1955
peerSend({ type = LT.MSG.MON, name = "BLUE", trainerId = 0x2222,
  mon = Protocol.packMon3(mon(151, 30, nil, { fatefulEncounter = false })) })
LT.update(0)
eq(LT.state, "canceled", "an illegitimate MEW in place of the SQUIRTLE is refused")
eq(LT.lastResult, "bad_mon", "as bad_mon")
eq(LT.lastRefusal, "not the POKéMON that was shown", "because it is not the mon that was shown")
peer:update(0)
eq(peer:take(LT.MSG.CONFIRM), nil, "no confirm went to the relay")
local sawRefuse = false
pumpPeer(function(msg)
  if msg.cmd == LT.LINKCMD.PLAYER_CANCEL_TRADE then sawRefuse = true end
end)
check(sawRefuse, "the other machine was told to cancel")
eq(session.party[1].species, 1, "and the party is untouched")
LT.reset()

Link.reset()
LT.reset()
Union.reset()

if failed == 0 then
  print("[pass] link trade")
  os.exit(0)
end
print("[FAIL] link trade: " .. failed .. " failed")
os.exit(1)
