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

local FakeRelay = require("tests.g3link_fake_relay")
local RelayTransport = require("src.core.game3.link.relay_transport")
local Game3Link = require("src.link.Game3Link")
local Versions = require("src.import.gba.versions")

local session = { name = "RED", trainerId = 0x1234, gender = 0 }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = nil,
}

print("[test] 1. the transport is relay-backed and never pumps the Client")
local room = FakeRelay.room({ seats = 2, names = { "RED", "BLUE" } })
local rs0 = room:session(0)
local t0 = RelayTransport.new(rs0, { client = room:client(0) })
eq(t0.relay, true, "t.relay is true")
eq(t0.target, room.id, "t.target is the room id")
eq(t0.code, nil, "t.code is nil (no codes)")
t0:update()
t0:update()
eq(rs0.updateCalls, nil, "t:update never calls roomSession:update (no double pump)")
eq(t0:seat(), 0, "seat() reads the room session seat")
eq(t0:seats(), 2, "seats() reads the room session seat count")
eq(#t0:players(), 2, "players() lists every seat")
eq(t0:role(), "host", "role() is host for seat 0")
eq(t0:seed(), room.seed, "seed() is the relay-dealt seed")
eq(t0:match(), room.match, "match() is the relay match token")
eq(t0:peerOnline(1), true, "peerOnline(1) reads the room")

print("[test] 2. send strips seat, poll and take tag the sender seat")
local t1 = RelayTransport.new(room:session(1), { client = room:client(1) })
t0:send({ type = "game3_link_card", seat = 3, card = { name = "RED" } })
local got = t1:poll()
eq(#got, 1, "the peer receives one message")
eq(got[1] and got[1].seat, 0, "tagged with the sender seat from the envelope, not the spoofed one")
room:relay({ type = "trade_commit", n = 1, digests = { "a", "b" } })
local commit = t1:take("trade_commit")
eq(commit and commit.seat, -1, "relay-authored messages carry seat -1")
room.inbox[1][#room.inbox[1] + 1] = { type = "spectate", side = "guest", msg = { type = "game3_battle_action", turn = 1 } }
local unwrapped = t1:poll()[1]
eq(unwrapped and unwrapped.type, "game3_battle_action", "a legacy spectate envelope is unwrapped")
eq(unwrapped and unwrapped.seat, 1, "and the side becomes a seat")

print("[test] 3. close ends the link only, leave leaves the room")
t0:close()
eq(t0.closed, true, "close marks the link closed")
eq(rs0.left, false, "the room session is untouched")
eq(#room.players, 2, "both seats are still in the room")
t0:leave()
eq(rs0.closeCalls, 1, "leave closes the room session once")
eq(#room.players, 1, "and the seat leaves the room")
t0:leave()
eq(rs0.closeCalls, 1, "a second leave is a no-op")

print("[test] 4. the link closes when the room goes away, the Client fails, or a seat leaves")
local r2 = FakeRelay.room({ seats = 2 })
local c2 = r2:client(0)
local ta = RelayTransport.new(r2:session(0), { client = c2 })
r2:setOnline(1, false)
ta:update()
eq(ta.closed, false, "a peer going online:false alone never closes (resume grace)")
r2:drop(1)
ta:update()
eq(ta.closed, true, "a seat listed at match start that left the room closes the link")

local r3 = FakeRelay.room({ seats = 2 })
local tb = RelayTransport.new(r3:session(0), { client = r3:client(0) })
r3:setState(0, "error")
tb:update()
eq(tb.closed, true, "Client error closes the link")
check(tb.error ~= nil, "and reports the error")

local r4 = FakeRelay.room({ seats = 2 })
local tc = RelayTransport.new(r4:session(0), { client = r4:client(0) })
r4:setState(0, "offline")
tc:update()
eq(tc.closed, true, "Client offline closes the link")
eq(tc.error, nil, "without an error")

local r5 = FakeRelay.room({ seats = 2 })
local c5 = r5:client(0)
local td = RelayTransport.new(r5:session(0), { client = c5 })
local realRoom = c5.room
c5.room = function()
  local t = realRoom()
  t.room = "r0000000000000bad"
  return t
end
td:update()
eq(td.closed, true, "a different Client room closes the link")

print("[test] 5. Game3Link pairs two seats over the relay")
local game = { data = {}, save = { player = { name = "SAVE" }, options = {} } }
local host, guest, pairRoom = FakeRelay.pair({ game = game })
eq(host.myHello.game3.seat, 0, "the host hello carries seat 0")
eq(guest.myHello.game3.seat, 1, "the guest hello carries seat 1")
eq(host.role, "host", "seat 0 is the host role")
eq(guest.role, "guest", "seat 1 is the guest role")
host:update(0)
guest:update(0)
check(host:isReady(), "the host reached ready")
check(guest:isReady(), "the guest reached ready")
eq(host.myHello.game3.cacheVersion, Versions.CACHE_VERSION, "the hello carries the cache version")
eq(host.myHello.name, "RED", "the hello name comes from the live session")
eq(host.myHello.ruleset, "gen1_faithful", "Handshake.hello reads game.save.options through the view")
local rows = host:players()
eq(#rows, 2, "players() has one row per seat")
eq(rows[1].seat, 0, "sorted by seat")
eq(rows[1].isLocal, true, "the local row is seat 0 on the host")
eq(rows[2].role, "guest", "the peer row is the guest")
eq(guest:peerName(), "RED", "the guest names the host")

print("[test] 6. a relay drop is a peer drop, never a room leave by the survivor")
pairRoom:drop(1)
host:update(0)
check(not host:isOpen(), "the survivor's link closed")
eq(host.reason, "peer_dropped", "reported as a peer drop")
eq(pairRoom:session(0).closeCalls, nil, "the survivor did not leave the room on its own")

print("[test] 7. four seats handshake only after every other hello")
local quad, links = FakeRelay.links({ seats = 4, game = game })
links[1]:update(0)
local early = FakeRelay.room({ seats = 4 })
local lone = Game3Link.attach(FakeRelay.transport(early, 0), { game = game, seat = 0, seats = 4 })
local peer1 = Game3Link.attach(FakeRelay.transport(early, 1), { game = game, seat = 1, seats = 4 })
lone:update(0)
check(not lone:isReady(), "one hello of three is not enough")
for _, lk in ipairs(links) do lk:update(0) end
for i, lk in ipairs(links) do
  check(lk:isReady(), "seat " .. (i - 1) .. " reached ready")
end
local four = links[3]:players()
eq(#four, 4, "players() has four rows")
eq(four[3].isLocal, true, "seat 2 is the local row on seat 2")
eq(four[3].role, "seat2", "seat 2 has its seat role")
eq(links[3].peerHello and links[3].peerHello.game3.seat, 0, "peerHello is seat 0's")
eq(peer1.seat, 1, "a guest seat stays 1")

print("[test] 8. a refused hello on any seat refuses the link")
local mixed, mlinks = FakeRelay.links({ seats = 2, game = game })
mixed.inbox[0] = {}
local stale = Game3Link.hello(game, Game3Link.LINKTYPE.BATTLE)
stale.game3.cacheVersion = Versions.CACHE_VERSION + 1
stale.seat = 1
mixed.inbox[0][1] = stale
mlinks[1]:update(0)
check(not mlinks[1]:isOpen(), "a peer on another cache is refused")
eq(mlinks[1].reason, "cache_version_mismatch", "and says why")

print("[test] 9. Game3Link.hello takes a prebuilt player for the launcher")
local h = Game3Link.hello(game, Game3Link.LINKTYPE.TRADE, { name = "LAUNCH", trainerId = 77, gender = 1 })
eq(h.name, "LAUNCH", "the override name wins")
eq(h.game3.trainerId, 77, "the override trainer id wins")
eq(h.game3.gender, 1, "the override gender wins")
local r9 = FakeRelay.room({ seats = 2 })
local prebuilt = Game3Link.attach(FakeRelay.transport(r9, 1), { hello = h, seat = 1, seats = 2 })
eq(prebuilt.myHello.name, "LAUNCH", "attach sends the prebuilt hello")
eq(prebuilt.myHello.game3.seat, 1, "stamped with the seat")
eq(h.game3.seat, nil, "without touching the caller's table")

print("[test] 10. loopback stays for tests")
local lh, lg = Game3Link.loopback({ game = game })
lh:update(0)
lg:update(0)
check(lh:isReady() and lg:isReady(), "the loopback pair still handshakes")

print("[test] 11. the cable club has no LAN any more")
package.loaded["src.core.game3.scripting.space"] = { store = { flags = {}, vars = {} } }
local Link = require("src.core.game3.link")
eq(Link.dial, nil, "Link.dial is gone")
local none, why = Link.open({ address = "203.0.113.1:1" })
eq(none, nil, "Link.open with an address and no transport opens nothing")
eq(why, "no_transport", "and says why")
eq(Link.beginConnect({}), false, "beginConnect never opens an IP screen")
local LinkMenu = require("src.ui.game3.link_menu")
eq(LinkMenu.showConnect, nil, "the HOST/JOIN IP screen is gone")

print("[test] 12. Link.openRelay adopts the Client room and closeLink leaves it")
local Client = FakeRelay.client({ state = "online" })
package.loaded["src.online.Client"] = Client
local r12 = FakeRelay.room({ seats = 2 })
Client.bindRoom(r12, 1)
local rs12 = r12:session(1)
local opened = Link.openRelay({ game = game })
check(opened ~= nil, "openRelay attached a link")
eq(Link.link, opened, "it is the live cable club link")
eq(opened.seat, 1, "seated from the room session")
eq(opened._transport.relay, true, "over the relay transport")
Link.closeLink("done")
eq(opened.closed, true, "closeLink closed the link")
eq(rs12.closeCalls, 1, "and then left the room")
eq(#r12.players, 1, "the seat is gone from the room")
Link.reset()

if failed == 0 then
  print("[pass] relay transport")
  os.exit(0)
end
print("[fail] relay transport: " .. failed)
os.exit(1)
