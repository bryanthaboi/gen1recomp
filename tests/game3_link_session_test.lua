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

local COUNTER_MAP = "FR_TEST_CABLE_COUNTER"
local LINK_ROOM_MAP = "FR_TEST_LINK_ROOM"
local LOBBY_MAP = "FR_TEST_LOBBY"

local MAPS = {
  [COUNTER_MAP] = {
    warps = {
      { x = 1, y = 6, destMap = LOBBY_MAP, destWarp = 1 },
      { x = 9, y = 1, destMap = LINK_ROOM_MAP, destWarp = 1 },
    },
  },
  [LINK_ROOM_MAP] = {
    warps = {
      { x = 5, y = 8, mapGroup = 0x7F, mapNum = 0x7F, destWarp = 128 },
    },
  },
  [LOBBY_MAP] = { warps = { { x = 7, y = 8, destMap = COUNTER_MAP, destWarp = 1 } } },
}

local store = { flags = {}, vars = {} }
local session = {
  store = store,
  map = COUNTER_MAP,
  x = 9,
  y = 1,
  party = {},
  bag = { pockets = { items = { { id = 4, qty = 3 } } } },
}
local game = { data = { maps = MAPS }, session = session,
  saveGame = function() return true end }

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
  _mod = nil,
}

local Player = { cellX = 9, cellY = 1, facing = "up" }
package.loaded["src.core.game3.player"] = Player

local mapLoads = {}
package.loaded["src.core.game3.map"] = {
  load = function(_mod, _game, mapId, opts)
    mapLoads[#mapLoads + 1] = { map = mapId, x = opts and opts.x, y = opts and opts.y }
  end,
  current = nil,
}

local ctx = { specialVars = {} }
local adapterCalls = { warp = {}, se = {} }
local adapters = {
  log = function() end,
  playSe = function(id) adapterCalls.se[#adapterCalls.se + 1] = id end,
  warp = function(group, num, warpId, x, y, done)
    adapterCalls.warp[#adapterCalls.warp + 1] =
      { group = group, num = num, warpId = warpId, x = x, y = y }
    if done then done() end
  end,
}

local romBundle = require("tests.game3_cache").bundle()
if not romBundle then
  package.loaded["src.core.game3.rom_text"] = {
    plain = function(key) return key end, box = function(key) return key end,
    ascii = function(key) return key end, has = function() return true end,
    ir = function(key) return { { t = "text", s = key } } end,
    key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    count = function() return 0 end, list = function() return {} end,
    lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
  }
end

package.loaded["src.core.game3.scripting.space"] = {
  store = store,
  mapId = COUNTER_MAP,
  vm = { ctx = ctx, adapters = adapters },
  ensureBundle = function() return romBundle end,
}
local Space = package.loaded["src.core.game3.scripting.space"]

local Natives = require("src.core.game3.scripting.natives")
local NativesLink = require("src.core.game3.scripting.natives_link")
local Link = require("src.core.game3.link")
local Game3Link = require("src.link.Game3Link")
local FakeRelay = require("tests.g3link_fake_relay")
local Versions = require("src.import.gba.versions")
local Flags = require("src.core.game3.scripting.flags")
local SaveMenu = require("src.ui.game3.save_menu")

local function result()
  return tonumber(Flags.getVar(store, ctx, Link.VAR_RESULT)) or 0
end

print("[test] 1. ids match the 0-based def_special index of pokefirered/data/specials.inc")
local EXPECTED = {
  SetCableClubWarp = 0x01,
  DoCableClubWarp = 0x02,
  ReturnFromLinkRoom = 0x03,
  CleanupLinkRoomState = 0x04,
  ExitLinkRoom = 0x05,
  CloseLink = 0x1F,
  CableClub_AskSaveTheGame = 0x23,
  Field_AskSaveTheGame = 0x5D,
  LoadPlayerBag = 0x14B,
  IsWirelessAdapterConnected = 0x16A,
}
local Std = require("src.core.game3.scripting.stdscripts")
for name, id in pairs(EXPECTED) do
  eq(NativesLink.SPECIAL[name], id, "NativesLink.SPECIAL." .. name)
  check(Natives.ALLOW["special:" .. id] ~= nil, name .. " is bound in Natives.ALLOW")
  eq(Std.SPECIAL_NAME_BY_ID[id], name, "special 0x" .. string.format("%X", id) ..
    " answers to its pret name")
end
local discovered = {}
for _, n in ipairs(Natives.MODULE_NAMES) do discovered[n] = true end
check(discovered.natives_link, "natives_link is discovered as a natives module")
local known = false
for _, n in ipairs(Natives.KNOWN_MODULES) do
  if n == "natives_link" then known = true end
end
check(known, "natives_link is in the headless KNOWN_MODULES fallback")

print("[test] 2. every link special dispatches instead of logging as unknown")
Natives.resetLog()
local logs = {}
local quiet = { log = function(m) logs[#logs + 1] = m end }
local probeIds = {}
for id in pairs(NativesLink.HANDLERS) do probeIds[#probeIds + 1] = id end
table.sort(probeIds)
for _, id in ipairs(probeIds) do
  if id ~= NativesLink.SPECIAL.Field_AskSaveTheGame
      and id ~= NativesLink.SPECIAL.CableClub_AskSaveTheGame then
    local _, _, isKnown = Natives.special({ specialVars = {} }, id, quiet)
    check(isKnown, string.format("special 0x%X dispatches to a handler", id))
  end
end
eq(#logs, 0, "nothing reached the unknown-special log")

print("[test] 3. IsWirelessAdapterConnected answers FALSE")
Flags.setVar(store, ctx, Link.VAR_RESULT, 9)
local yield, value = Natives.special(ctx, NativesLink.SPECIAL.IsWirelessAdapterConnected, adapters)
eq(yield, false, "IsWirelessAdapterConnected does not yield")
eq(value, 0, "IsWirelessAdapterConnected returns FALSE for specialvar")
eq(result(), 0, "VAR_RESULT is FALSE")

print("[test] 4. SetCableClubWarp records the return warp at a link room door")
session.dynamicWarp = nil
session.warpDestination = nil
Player.cellX, Player.cellY = 9, 1
Space.mapId = COUNTER_MAP
Natives.special(ctx, NativesLink.SPECIAL.SetCableClubWarp, adapters)
eq(session.warpDestination and session.warpDestination.map, LINK_ROOM_MAP,
  "warp destination is the link room behind the door")
check(type(session.dynamicWarp) == "table", "a dynamic return warp was recorded")
eq(session.dynamicWarp and session.dynamicWarp.map, COUNTER_MAP, "it returns to the counter map")
eq(session.dynamicWarp and session.dynamicWarp.warpId, 1, "it names the door warp (0-based)")
eq(session.dynamicWarp and session.dynamicWarp.x, 9, "it remembers the door x")
eq(session.dynamicWarp and session.dynamicWarp.y, 1, "it remembers the door y")

session.dynamicWarp = nil
Player.cellX, Player.cellY = 1, 6
Natives.special(ctx, NativesLink.SPECIAL.SetCableClubWarp, adapters)
eq(session.warpDestination and session.warpDestination.map, LOBBY_MAP,
  "an ordinary door still sets the warp destination")
eq(session.dynamicWarp, nil, "an ordinary door records no dynamic return warp")

print("[test] 5. DoCableClubWarp replays a setwarp destination, not a warp already taken")
Player.cellX, Player.cellY = 9, 1
Space.mapId = COUNTER_MAP
adapterCalls.warp, adapterCalls.se = {}, {}
Natives.special(ctx, NativesLink.SPECIAL.SetCableClubWarp, adapters)
session.warpDestination = { mapGroup = 12, mapNum = 1, warpId = 0xFF, x = 5, y = 8 }
Natives.special(ctx, NativesLink.SPECIAL.DoCableClubWarp, adapters)
eq(#adapterCalls.warp, 1, "the stored destination was warped to")
eq(adapterCalls.warp[1] and adapterCalls.warp[1].group, 12, "with the stored map group")
eq(adapterCalls.warp[1] and adapterCalls.warp[1].y, 8, "with the stored y")
eq(adapterCalls.se[1], 9, "SE_EXIT played")

adapterCalls.warp = {}
Natives.special(ctx, NativesLink.SPECIAL.SetCableClubWarp, adapters)
Space.mapId = LINK_ROOM_MAP
Natives.special(ctx, NativesLink.SPECIAL.DoCableClubWarp, adapters)
eq(#adapterCalls.warp, 0, "a script warp that already changed the map is not repeated")
Space.mapId = COUNTER_MAP

print("[test] 6. Field_AskSaveTheGame gates entry on the save prompt")
Flags.setVar(store, ctx, Link.VAR_RESULT, 7)
local yielded = Natives.special(ctx, NativesLink.SPECIAL.Field_AskSaveTheGame, adapters)
check(yielded, "the script yields while the save prompt is up")
check(SaveMenu.isOpen(), "the save menu opened")
check(ctx.nativePoll and ctx.nativePoll() == false, "the script stays parked while it is open")
SaveMenu.cursor = 2
SaveMenu.confirm()
eq(result(), 0, "answering NO reports FALSE, which aborts the link")
check(ctx.nativePoll and ctx.nativePoll() == true, "the script resumes once it closes")

Flags.setVar(store, ctx, Link.VAR_RESULT, 7)
Natives.special(ctx, NativesLink.SPECIAL.Field_AskSaveTheGame, adapters)
SaveMenu.cursor = 1
SaveMenu.confirm()
SaveMenu.confirm()
SaveMenu.confirm()
eq(result(), 1, "saving reports TRUE, which lets the link continue")
check(not SaveMenu.isOpen(), "the save menu closed")

print("[test] 7. two FireRed peers pair over the relay, anything else is refused")
local host, guest, room = FakeRelay.pair({ game = game })
host:update(0)
guest:update(0)
check(host:isReady(), "the host reached ready")
check(guest:isReady(), "the guest reached ready")
eq(host._transport.relay, true, "over the relay transport")
eq(#host:players(), 2, "the host lists both players")
eq(host.myHello.generation, 3, "the hello announces generation 3")
eq(host.myHello.game3.cacheVersion, Versions.CACHE_VERSION, "the hello carries the cache version")

local r7 = FakeRelay.room({ seats = 2 })
local lone = Game3Link.attach(FakeRelay.transport(r7, 0), { game = game })
local Handshake = require("src.link.Handshake")
r7:session(1):send(Handshake.hello(game, "battle"))
lone:update(0)
check(not lone:isOpen(), "a peer with no FireRed hello is refused")
eq(lone.reason, "peer_is_not_firered", "and says why")

local r7b = FakeRelay.room({ seats = 2 })
local strict = Game3Link.attach(FakeRelay.transport(r7b, 0), { game = game })
local staleHello = Game3Link.hello(game, Game3Link.LINKTYPE.BATTLE)
staleHello.game3.cacheVersion = Versions.CACHE_VERSION + 1
r7b:session(1):send(staleHello)
strict:update(0)
check(not strict:isOpen(), "a peer built on another cache is refused")
eq(strict.reason, "cache_version_mismatch", "and says why")

local Handshake = require("src.link.Handshake")
local realRuleset = Handshake.ruleset
Handshake.ruleset = function() return "gen1_modern" end
local r7c = FakeRelay.room({ seats = 2 })
local mixed = Game3Link.attach(FakeRelay.transport(r7c, 0), { game = game })
local otherHello = Game3Link.hello(game, Game3Link.LINKTYPE.BATTLE)
Handshake.ruleset = realRuleset
eq(otherHello.ruleset, Handshake.DEFAULT_RULESET, "the Gen 1 RULESET option never reaches a FireRed hello")
r7c:session(1):send(otherHello)
mixed:update(0)
check(mixed:isOpen() and mixed:isReady(), "so two players with different Gen 1 rulesets still link")

print("[test] 8. CloseLink tears the session down and the peer hears it")
Link.reset()
Link.attach(host)
eq(Link.link, host, "the cable club session owns the link")
Natives.special(ctx, NativesLink.SPECIAL.CloseLink, adapters)
check(not host:isOpen(), "CloseLink closed the local end")
eq(Link.link, nil, "and cleared the cable club session")
guest:update(0)
check(not guest:isOpen(), "the peer saw the goodbye")
eq(guest.reason, "peer_left", "and reports the peer leaving")
eq(#room.players, 1, "CloseLink also left the relay room")
eq(room.players[1] and room.players[1].seat, 1, "only the peer is still seated")

print("[test] 9. a peer drop in a link room returns the player to the counter")
Link.reset()
local host2, guest2, room2 = FakeRelay.pair({ game = game })
host2:update(0)
guest2:update(0)
Link.attach(host2)
Space.mapId = LINK_ROOM_MAP
session.map = LINK_ROOM_MAP
session.dynamicWarp = { map = COUNTER_MAP, warpId = 1, x = 9, y = 1 }
session.warpDestination = nil
Flags.setVar(store, ctx, Link.VAR_CABLE_CLUB_STATE, Link.USING.UNION_ROOM)
Flags.setVar(store, ctx, Link.VAR_0x8004, Link.USING.UNION_ROOM)
mapLoads = {}
room2:drop(1)
Link.update(0)
check(not host2:isOpen(), "the survivor closed its end")
eq(host2.reason, "peer_dropped", "the drop is reported as a peer drop")
eq(#mapLoads, 1, "the player was warped back")
eq(mapLoads[1] and mapLoads[1].map, COUNTER_MAP, "to the cable club counter map")
eq(mapLoads[1] and mapLoads[1].x, 9, "onto the link room door x")
eq(mapLoads[1] and mapLoads[1].y, 1, "onto the link room door y")
-- pokefirered/data/scripts/cable_club.inc:106 the 2F's OnFrame exit script clears it
check(tonumber(Flags.getVar(store, ctx, Link.VAR_CABLE_CLUB_STATE)) ~= 0,
  "VAR_CABLE_CLUB_STATE stays set for the Pokemon Center's exit script")

print("[test] 10. CleanupLinkRoomState restores the bag and asks for the saved party")
Link.reset()
session.map = LINK_ROOM_MAP
local walkedInWith = session.bag.pockets.items[1].id
Link.loadPlayerBag()
session.bag = { pockets = { items = { { id = 13, qty = 1 } } } }
local asked = 0
local prev = Natives.ALLOW["special:40"]
Natives.ALLOW["special:40"] = function() asked = asked + 1 end
Flags.setVar(store, ctx, Link.VAR_0x8004, Link.USING.SINGLE_BATTLE)
session.dynamicWarp = { map = COUNTER_MAP, warpId = 1, x = 9, y = 1 }
session.warpDestination = nil
Natives.special(ctx, NativesLink.SPECIAL.CleanupLinkRoomState, adapters)
eq(asked, 1, "LoadPlayerParty (special 0x28) was asked for the pre-link party")
eq(session.bag.pockets.items[1].id, walkedInWith, "the bag the player walked in with is back")
eq(session.warpDestination and session.warpDestination.map, COUNTER_MAP,
  "the warp destination became the dynamic return warp")

asked = 0
Link.loadPlayerBag()
Flags.setVar(store, ctx, Link.VAR_0x8004, Link.USING.TRADE_CENTER)
Natives.special(ctx, NativesLink.SPECIAL.CleanupLinkRoomState, adapters)
eq(asked, 0, "a trade room does not restore the battle party")
Natives.ALLOW["special:40"] = prev

print("[test] 11. ExitLinkRoom with no peer left walks the player out on its own")
Link.reset()
Space.mapId = LINK_ROOM_MAP
Flags.setVar(store, ctx, Link.VAR_CABLE_CLUB_STATE, Link.USING.TRADE_CENTER)
Flags.setVar(store, ctx, Link.VAR_0x8004, Link.USING.TRADE_CENTER)
session.dynamicWarp = { map = COUNTER_MAP, warpId = 1, x = 9, y = 1 }
session.warpDestination = nil
mapLoads = {}
Natives.special(ctx, NativesLink.SPECIAL.ExitLinkRoom, adapters)
eq(#mapLoads, 1, "the player left the link room")
eq(mapLoads[1] and mapLoads[1].map, COUNTER_MAP, "back to the counter")
-- pokefirered/data/scripts/cable_club.inc:106 the 2F's OnFrame exit script clears it
check(tonumber(Flags.getVar(store, ctx, Link.VAR_CABLE_CLUB_STATE)) ~= 0,
  "VAR_CABLE_CLUB_STATE stays set for the Pokemon Center's exit script")

print("[test] 12. the real Pokemon Center 2F door is a dynamic warp back to the counter")
local Cache = require("tests.game3_cache")
local root = Cache.mount("meta.json")
if not root then
  print("[skip] cable club door check: " .. tostring(Cache.reason))
else
  local Dataset = require("src.core.game3.dataset")
  local realMaps = Dataset.buildMaps()
  local CENTER = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
  game.data.maps = realMaps
  Space.mapId = CENTER
  session.map = CENTER
  session.dynamicWarp = nil
  session.warpDestination = nil
  local door = nil
  for _, w in ipairs((realMaps[CENTER] and realMaps[CENTER].warps) or {}) do
    if w.destMap == "FR_TRADE_CENTER" then door = w end
  end
  check(door ~= nil, "the 2F trade centre door is in the map header")
  if door then
    Player.cellX, Player.cellY = tonumber(door.x), tonumber(door.y)
    Natives.special(ctx, NativesLink.SPECIAL.SetCableClubWarp, adapters)
    eq(session.warpDestination and session.warpDestination.map, "FR_TRADE_CENTER",
      "SetCableClubWarp aims at the trade centre")
    eq(session.dynamicWarp and session.dynamicWarp.map, CENTER,
      "and records the return warp to the Pokemon Center 2F")
    local mapId, x, y = Link.resolveDest(session.dynamicWarp)
    eq(mapId, CENTER, "the return warp resolves to the counter map")
    eq(x, tonumber(door.x), "at the door x")
    eq(y, tonumber(door.y), "at the door y")
  end
  game.data.maps = MAPS
end

print("[test] the trainer cards the two machines swap, and the special that shows one")
Link.reset()
session.name = "RED"
session.trainerId = 0x1234
local cardHost, cardGuest = FakeRelay.pair({ game = game })
cardHost:update(0)
cardGuest:update(0)
Link.attach(cardHost)
Link.update(0)
cardGuest:update(0)
-- pokefirered/src/union_room.c:1863 CreateTrainerCardInBuffer
local outgoing = cardGuest:take(Link.MSG.CARD)
check(outgoing ~= nil, "this machine's trainer card goes out once the link is ready")
eq(outgoing and outgoing.card and outgoing.card.name, session.name, "with the player's name")
eq(outgoing and outgoing.card and outgoing.card.trainerId, session.trainerId,
  "and the player's trainer id")
cardGuest:send({ type = Link.MSG.CARD, card = { name = "BLUE", trainerId = 0x2222 } })
cardHost:update(0)
Link.update(0)
eq(Link.peerCard and Link.peerCard.name, "BLUE", "and the peer's card arrives the same way")
eq(Link.peerCards[1] and Link.peerCards[1].name, "BLUE", "filed under the sender's seat")
eq(NativesLink.SPECIAL.Script_ShowLinkTrainerCard, 0x2A,
  "Script_ShowLinkTrainerCard is def_special 0x2A")
local cardLogs = {}
local _, _, known = Natives.special({ specialVars = {} }, 0x2A,
  { log = function(m) cardLogs[#cardLogs + 1] = m end })
check(known, "and it dispatches to a handler instead of logging an unknown special")
eq(#cardLogs, 0, "nothing reached the unknown-special log")

print("[test] the counter opens the relay transport, never a LAN socket")
Link.reset()
-- pokefirered/src/link.c:386 OpenLink
local openRoom = FakeRelay.room({ seats = 2 })
local opened = Link.open({ transport = FakeRelay.transport(openRoom, 1), game = game })
check(opened ~= nil, "Link.open adopts a relay transport and attaches it")
eq(Link.link, opened, "and it becomes the live session")
eq(opened.seat, 1, "seated from the transport")
Link.reset()
local bad, why = Link.open({ address = "203.0.113.1:1", game = game })
eq(bad, nil, "an address opens nothing: there is no LAN for Gen 3")
eq(why, "no_transport", "and says why")
eq(Link.dial, nil, "Link.dial is gone")
Link.reset()
eq(Link.beginConnect({}), false,
  "with no link there is no connect screen, so the counter just keeps waiting")

print("[test] ExitLinkRoom counts each seat once and seat-less exits one by one")
local function stubLink(nseats, queue)
  local s = { nseats = nseats, seat = 0, open = true, queue = queue }
  function s:update() end
  function s:isReady() return false end
  function s:isOpen() return self.open end
  function s:send() end
  function s:close() self.open = false end
  function s:take(kind)
    if kind ~= "game3_exit_link_room" then return nil end
    return table.remove(self.queue, 1)
  end
  return s
end
local function queueExit(lk)
  Link.reset()
  Space.mapId = LINK_ROOM_MAP
  session.map = LINK_ROOM_MAP
  session.dynamicWarp = { map = COUNTER_MAP, warpId = 1, x = 9, y = 1 }
  session.warpDestination = nil
  mapLoads = {}
  Link.link = lk
  Link.exitQueued = true
end
local anon = stubLink(3, { {}, {} })
queueExit(anon)
Link.update(0)
eq(#mapLoads, 1, "two seat-less exits fill a 3-seat room")
check(not anon.open, "and the link is closed")
local dup = stubLink(3, { { seat = 1 }, { seat = 1 } })
queueExit(dup)
Link.update(0)
eq(#mapLoads, 0, "the same seat twice is one exit")
dup.queue[1] = { seat = 2 }
Link.update(0)
eq(#mapLoads, 1, "the second seat completes it")

print("[test] a 4-seat link card is the seat's own, never the last one received")
Link.reset()
local shown
package.loaded["src.ui.game3.trainer_card"] = { show = function(o) shown = o.session end }
local hadLove = love
love = { graphics = {} }
Link.link = stubLink(4, {})
Link.peerCards = { [1] = { name = "BLUE" } }
Link.peerCard = { name = "BLUE" }
Flags.setVar(store, ctx, Link.VAR_0x8006, 2)
Link.showLinkTrainerCard(ctx, adapters)
check(shown ~= nil and shown.name ~= "BLUE", "seat 2's card has not arrived: not BLUE's")
Link.link = stubLink(2, {})
Link.peerCards = {}
Link.peerCard = { name = "BLUE" }
Flags.setVar(store, ctx, Link.VAR_0x8006, 1)
Link.showLinkTrainerCard(ctx, adapters)
eq(shown and shown.name, "BLUE", "a 2-seat link still falls back to the peer's card")
love = hadLove
package.loaded["src.ui.game3.trainer_card"] = nil
Link.link = nil

print("[test] upgrade_required shows the Connect text verbatim")
local hadConnect = package.loaded["src.online.Connect"]
package.loaded["src.online.Connect"] = { upgradeText = function() return "Please update." end }
eq(Link.reasonText("upgrade_required"), "Please update.", "the whole upgrade line, period kept")
package.loaded["src.online.Connect"] = { upgradeText = function() return nil end }
check(Link.reasonText("timeout"):find("timeout", 1, true) ~= nil, "other reasons still name the cause")
package.loaded["src.online.Connect"] = hadConnect

Link.reset()
if failed == 0 then
  print("[pass] link session")
  os.exit(0)
end
print("[fail] link session: " .. failed)
os.exit(1)
