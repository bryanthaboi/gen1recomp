#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["src.core.game3.rom_text"] = { plain = function(key) return key end, box = function(key) return key end }

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

local function mon(species, level, personality, extra)
  local m = {
    species = species,
    level = level,
    hp = 30,
    maxHp = 30,
    moves = { 33 },
    pp = { 35 },
    maxPp = { 35 },
    personality = personality or (species * 7),
    nickname = "",
    friendship = 120,
    otName = "RED",
    otId = 0x1234,
  }
  for k, v in pairs(extra or {}) do m[k] = v end
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
local Std = require("src.core.game3.scripting.stdscripts")
local Link = require("src.core.game3.link")
local LT = require("src.core.game3.link.trade")
local Union = require("src.core.game3.link.union_room")
local Status = require("src.core.game3.link.status")
local Trade = require("src.core.game3.scripting.natives_trade")
local TradeScene = require("src.core.game3.trade_scene")
local Game3Link = require("src.link.Game3Link")
local Flags = require("src.core.game3.scripting.flags")

local peer

local function openLink()
  Link.reset()
  LT.reset()
  local host, other = Game3Link.loopback({ game = game })
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

print("[test] 1. the trade specials answer to their pret index")
local EXPECTED = {
  TryTradeLinkup = 0x1D,
  EnterTradeSeat = 0x21,
  StartWiredCableClubTrade = 0x22,
  ShowWirelessCommunicationScreen = 0x16E,
}
for name, id in pairs(EXPECTED) do
  eq(NativesLink.SPECIAL[name], id, "NativesLink.SPECIAL." .. name)
  check(Natives.ALLOW["special:" .. id] ~= nil, name .. " is bound in Natives.ALLOW")
  eq(Std.SPECIAL_NAME_BY_ID[id], name,
    string.format("special 0x%X answers to its pret name", id))
end
-- pokefirered/include/link.h:73
eq(LT.LINKCMD.READY_TO_TRADE, 0xAABB, "LINKCMD_READY_TO_TRADE")
eq(LT.LINKCMD.INIT_BLOCK, 0xBBBB, "LINKCMD_INIT_BLOCK")
eq(LT.LINKCMD.START_TRADE, 0xCCDD, "LINKCMD_START_TRADE")
eq(LT.LINKCMD.CONFIRM_FINISH_TRADE, 0xDCBA, "LINKCMD_CONFIRM_FINISH_TRADE")
eq(LT.LINKCMD.SET_MONS_TO_TRADE, 0xDDDD, "LINKCMD_SET_MONS_TO_TRADE")
-- pokefirered/src/cable_club.c:527 gLinkType = LINKTYPE_TRADE_SETUP
eq(LT.LINKUP.linkType, 0x1133, "TryTradeLinkup asks for LINKTYPE_TRADE_SETUP")
eq(LT.LINKUP.min, 2, "and for exactly two players")

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
peerSend({
  type = LT.MSG.PARTY,
  name = "BLUE",
  trainerId = 0x2222,
  gender = 0,
  version = 4,
  progressFlags = 0,
  party = {
    { species = 7, level = 11, hp = 25, personality = 49, isEgg = false },
    { species = 25, level = 9, hp = 22, personality = 175, isEgg = false },
  },
})
LT.update(0)
eq(LT.peer and LT.peer.name, "BLUE", "the other player introduced itself")
eq(#LT.peerParty, 2, "and its party is on this screen")
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
local keepPeerParty = LT.peerParty
-- pokefirered/src/trade.c:1955 the partner cannot trade an illegitimate DEOXYS or MEW
peerSend({ type = LT.MSG.PARTY, name = "BLUE", trainerId = 0x2222, gender = 0,
  version = 0, progressFlags = 1,
  party = { { species = 410, level = 30, personality = 5, fatefulEncounter = false } } })
LT.pump()
eq(LT.checkValidityOfTradeMons(1, 1), LT.PARTNER_MON_INVALID,
  "an illegitimate DEOXYS on the other machine is PARTNER_MON_INVALID")
LT.peerParty = keepPeerParty

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

print("[test] 6. the swap only happens once both mons are in hand")
peerSend({
  type = LT.MSG.MON,
  name = "BLUE",
  trainerId = 0x2222,
  mon = mon(7, 11, 49, { otName = "BLUE", otId = 0x2222, friendship = 40 }),
})
LT.update(0)
eq(LT.state, "scene", "the trade cinema starts")
eq(TradeScene.isLink(), true, "on its link arm")
eq(session.party[1].species, 1, "the party is untouched while the cinema plays")
local guard, confirms = 0, 0
while guard < 4000 and LT.state ~= "done" do
  pumpPeer(function(msg)
    -- pokefirered/src/trade_scene.c:2344 LINKCMD_CONFIRM_FINISH_TRADE
    if msg.cmd == LT.LINKCMD.CONFIRM_FINISH_TRADE then
      confirms = confirms + 1
      peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.CONFIRM_FINISH_TRADE })
    end
  end)
  LT.update(0)
  guard = guard + 1
end
eq(LT.state, "done", "and it runs to the end of the link tail")
eq(confirms, 1, "each machine confirms the finished trade exactly once")
eq(session.party[1].species, 7, "SQUIRTLE is in the party now")
eq(session.party[1].otName, "BLUE", "with the other player as its OT")
eq(#session.party, 2, "and the party is still two mons")
-- pokefirered/src/trade_scene.c:1075 TradeMons
eq(session.party[1].friendship, 70, "friendship reset to 70 by TradeMons")
check(session.dex and session.dex.owned and session.dex.owned[7] == true,
  "and the received mon is entered in the POKeDEX")

print("[test] 7. a cancel from the other machine leaves the party alone")
openLink()
session.party = { mon(1, 10), mon(4, 12) }
LT.startMenu()
peer:update(0)
peer:take(LT.MSG.PARTY)
peerSend({
  type = LT.MSG.PARTY, name = "BLUE", trainerId = 0x2222, version = 4, progressFlags = 0,
  party = { { species = 7, level = 11, personality = 49 } },
})
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
peerSend({
  type = LT.MSG.PARTY, name = "BLUE", trainerId = 0x2222, version = 4, progressFlags = 0,
  party = { { species = 7, level = 11, personality = 49 } },
})
LT.update(0)
LT.offer(1)
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 0 })
LT.update(0)
LT.confirm(true)
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.INIT_BLOCK })
LT.update(0)
eq(LT.state, "exchange", "the trade reached the block exchange")
peer:close("cable_pulled")
LT.update(0)
eq(LT.state, "off", "the session closed when the cable was pulled")
eq(LT.lastResult, "peer_dropped", "as a dropped peer")
eq(session.party[1].species, 1, "the offered mon is still in the party")
eq(#session.party, 2, "and the party is whole")
eq(TradeScene.isOpen(), false, "with no cinema left on screen")

print("[test] 9. the mons the trade menu refuses")
openLink()
-- pokefirered/src/trade.c:2767 the retail build answers CANT_TRADE_NATIONAL for an EGG
session.party = { mon(1, 10), mon(4, 12, 99, { isEgg = true }) }
LT.startMenu()
peerSend({ type = LT.MSG.PARTY, name = "BLUE", trainerId = 0x2222, gender = 0,
  version = 4, progressFlags = 0, party = { mon(7, 11) } })
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
peerSend({
  type = LT.MSG.MON,
  name = "BLUE",
  trainerId = 0x2222,
  mon = mon(25, 9, 175, { otName = "BLUE", otId = 0x2222 }),
})
LT.update(0)
eq(LT.state, "scene", "the union room trade plays the same cinema")
guard = 0
while guard < 4000 and LT.state ~= "done" do
  pumpPeer(function(msg)
    if msg.cmd == LT.LINKCMD.CONFIRM_FINISH_TRADE then
      peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.CONFIRM_FINISH_TRADE })
    end
  end)
  LT.update(0)
  guard = guard + 1
end
eq(session.party[2].species, 25, "PIKACHU came back for MACHOKE")
-- pokefirered/src/union_room.c:1746 ResetUnionRoomTrade
eq(Union.trade().playerSpecies, 0, "and the trading board registration was cleared")

print("[test] 11. trade evolution on the mon that just arrived")
local Cache = require("tests.game3_cache")
local root = Cache.mount("meta.json")
if not root then
  print("[skip] trade evolution: " .. tostring(Cache.reason))
else
  local Pokemon = require("src.core.game3.pokemon")
  Pokemon.install(nil)
  if #(Pokemon.evolutions(67) or {}) == 0 then
    print("[skip] trade evolution: the mounted cache at " .. tostring(root) ..
      " carries no evolution rows")
  else
    openLink()
    session.party = { mon(1, 10), mon(4, 12) }
    session.dex = { seen = {}, owned = {} }
    LT.startMenu()
    peer:update(0)
    peer:take(LT.MSG.PARTY)
    peerSend({
      type = LT.MSG.PARTY, name = "BLUE", trainerId = 0x2222, version = 4, progressFlags = 1,
      party = { { species = 67, level = 30, personality = 4242 } },
    })
    LT.update(0)
    LT.offer(1)
    peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 0 })
    LT.update(0)
    LT.confirm(true)
    peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.INIT_BLOCK })
    LT.update(0)
    peer:take(LT.MSG.MON)
    peerSend({
      type = LT.MSG.MON,
      name = "BLUE",
      trainerId = 0x2222,
      mon = mon(67, 30, 4242, { otName = "BLUE", otId = 0x2222 }),
    })
    LT.update(0)
    guard = 0
    while guard < 4000 and LT.state ~= "done" do
      pumpPeer(function(msg)
        if msg.cmd == LT.LINKCMD.CONFIRM_FINISH_TRADE then
          peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.CONFIRM_FINISH_TRADE })
        end
      end)
      LT.update(0)
      guard = guard + 1
    end
    -- pokefirered/src/trade_scene.c:2322 CB2_TryLinkTradeEvolution
    eq(session.party[1].species, 68, "the MACHOKE that arrived evolved into MACHAMP")
  end
end

print("[test] 12. the wireless communication status screen counts")
Link.reset()
LT.reset()
Union.reset()
local G = Status.GROUPTYPE
local counts = Status.counts({
  { activity = Union.ACTIVITY.TRADE },
  { activity = Union.ACTIVITY.BATTLE_SINGLE },
  { activity = Union.ACTIVITY.BATTLE_MULTI },
  { activity = Union.ACTIVITY.NONE + Union.IN_UNION_ROOM },
})
eq(counts[G.TRADE], 2, "a trading group is two people")
eq(counts[G.BATTLE], 6, "a single and a multi battle are six")
eq(counts[G.UNION], 1, "one player idling in the UNION ROOM")
eq(counts[G.TOTAL], 9, "and the total is trade plus battle plus union")
-- pokefirered/src/wireless_communication_status_screen.c:505 the retail total drops the rest
local wonder = Status.counts({ { activity = Union.ACTIVITY.WONDER_CARD } })
eq(wonder[G.TOTAL], 0,
  "the retail total leaves WONDER CARD players out, as the cart does")
local chat = Status.counts({
  { activity = Union.ACTIVITY.CHAT + Union.IN_UNION_ROOM, members = 3 },
})
eq(chat[G.UNION], 3, "a chat group counts its own members")
local rows = Status.rows()
eq(#rows, 4, "the screen has four rows")
eq(rows[1].label, "People trading:", "the first is the trading count")
eq(rows[4].total, true, "and the last is the total")

print("[test] 13. the adapter answer and the screen the monitor opens")
Flags.setVar(store, ctx, Link.VAR_RESULT, 9)
local yieldW, value = Natives.special(ctx, NativesLink.SPECIAL.IsWirelessAdapterConnected, adapters)
eq(yieldW, false, "IsWirelessAdapterConnected does not yield")
eq(value, 0, "with no session it answers FALSE, and the monitor says so")
openLink()
local _, connected = Natives.special(ctx, NativesLink.SPECIAL.IsWirelessAdapterConnected, adapters)
-- pokefirered/data/scripts/cable_club.inc:849 FALSE is what routes the direct corner
eq(connected, 0, "with a live session it still answers FALSE: this port has no adapter")
local LinkMenu = require("src.ui.game3.link_menu")
eq(LinkMenu.isOpen(), false, "the status screen starts closed")
local closed = false
LinkMenu.show({ onClose = function() closed = true end })
eq(LinkMenu.isOpen(), true, "ShowWirelessCommunicationScreen puts it up")
eq(#LinkMenu.rows, 4, "with the four group counts on it")
LinkMenu.update(1 / 60)
eq(LinkMenu.palIdx, 0, "the wave palette does not move on the first frame")
for _ = 1, 6 do LinkMenu.update(1 / 60) end
eq(LinkMenu.palIdx, 1, "and steps once every six frames, as CyclePalette does")
eq(LinkMenu.countText(3), " 3", "counts are right aligned to two places")
LinkMenu.close()
eq(closed, true, "closing it hands the script back")

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
peerSend({
  type = LT.MSG.PARTY, name = "BLUE", trainerId = 0x2222, version = 4, progressFlags = 0,
  party = { { species = 7, level = 11, personality = 49 } },
})
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
peerSend({
  type = LT.MSG.MON, name = "BLUE", trainerId = 0x2222,
  mon = mon(7, 11, 49, { otName = "BLUE", otId = 0x2222, mail = 0, heldItem = RETRO_MAIL }),
  mail = {
    itemId = RETRO_MAIL, playerName = "BLUE", trainerId = 0x2222, species = 7, design = 1,
    words = { 1, 2, 3, 4, 5, 6, 7, 8, 9 },
  },
})
LT.update(0)
eq(LT.state, "scene", "the cinema starts once both letters are in hand")
-- pokefirered/src/trade_scene.c:2488 gLinkPartnerMail[0] = mail
check(Trade.PARTNER_MAIL[0] ~= nil, "the partner's letter is parked in gLinkPartnerMail")
guard = 0
while guard < 4000 and LT.state ~= "done" do
  pumpPeer(function(msg)
    if msg.cmd == LT.LINKCMD.CONFIRM_FINISH_TRADE then
      peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.CONFIRM_FINISH_TRADE })
    end
  end)
  LT.update(0)
  guard = guard + 1
end
eq(LT.state, "done", "the trade ran to its end")
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
peerSend({ type = LT.MSG.PARTY, party = { mon(7, 11), mon(25, 14) }, name = "BLUE",
  trainerId = 0x2222, gender = 0, version = 0, progressFlags = 1 })
LT.update(0)
eq(#LT.peerParty, 2, "the other machine's party arrived over the wire")
local press = function(key)
  return { wasPressed = function(_, k) return k == key end }
end
Menu.handleInput(press("down"))
eq(Menu.cursor, 2, "DOWN walks this machine's party")
Menu.handleInput(press("up"))
eq(Menu.cursor, 1, "UP walks back")
-- pokefirered/src/trade.c:1811 SetReadyToTrade
Menu.handleInput(press("a"))
eq(LT.state, "ready_wait", "A on a mon offers it, with no hand-fed LT.offer call")
eq(LT.cursor, 0, "and the offered slot is the one the cursor was on")
peerSend({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 1 })
LT.update(0)
eq(LT.state, "confirm", "both machines have picked, so the confirmation comes up")
Menu.update(0)
check(Menu.confirming, "the screen shows IS THIS TRADE OKAY?")
Menu.handleInput(press("a"))
eq(LT.state, "confirm_wait", "A on YES answers the prompt through LT.confirm")
eq(LT.playerConfirmStatus, LT.STATUS.READY, "with LINKCMD_INIT_BLOCK for the leader itself")
Menu.reset()
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
