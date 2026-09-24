package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local Protocol2 = require("src.online.Protocol2")
local Wire = require("src.link.Wire")
local FakeRelay = require("tests.support.fake_relay")

local failures = 0
local function check(cond, msg)
  if cond then
    print("ok   " .. msg)
  else
    failures = failures + 1
    print("FAIL " .. msg)
  end
end
local function eq(got, want, msg)
  check(got == want, ("%s (got %s, want %s)"):format(msg, tostring(got), tostring(want)))
end

local savedGetTime = love.timer.getTime
local CLOCK = 0
love.timer.getTime = function() return CLOCK end

local function newClient()
  package.loaded["src.online.Client"] = nil
  local Client = require("src.online.Client")
  Client.reset()
  return Client
end

local function pid(n) return ("%08x"):format(n) end

local PROFILE3 = {
  engine = 3, version = "firered", engineVersion = "0.0.0-dev", apiVersion = "2",
  fingerprint = "g3fingerprint", rulesetId = "g3_single", kind = "vanilla",
  rule = { partySize = 3 },
}

local function profile3(rulesetId, version)
  local p = FakeRelay.copy(PROFILE3)
  p.rulesetId = rulesetId or p.rulesetId
  p.version = version or p.version
  return p
end

local function avatar(name, trainerId, gender)
  return { name = name, trainerId = trainerId, gender = gender or 0, version = "firered" }
end

local function outTypes(seat)
  local out = {}
  for _, m in ipairs(seat.transport.outbox) do out[#out + 1] = m.type end
  return out
end

local World = {}
World.__index = World

local function newWorld(opts)
  local w = setmetatable({ relay = FakeRelay.new({ clock = function() return CLOCK end,
                                                    minProtocol = opts and opts.minProtocol,
                                                    epoch = opts and opts.epoch }),
                           clients = {} }, World)
  return w
end

function World:add(n, name, profiles, presence)
  local id = pid(n)
  local seat = self.relay:seat(id, name)
  local C = newClient()
  C.configure({ relayAddress = "fake:3", connect = function() return seat.transport end })
  C.connect({ name = name, profiles = profiles or { PROFILE3 }, presence = presence })
  self.clients[#self.clients + 1] = C
  return C, seat
end

function World:pump(rounds)
  for _ = 1, rounds or 3 do
    self.relay:pump()
    for _, C in ipairs(self.clients) do C.update(0) end
  end
end

do
  eq(Wire.roomId("R0123456789ABCDEF"), "r0123456789abcdef", "a room id normalizes to lower case")
  eq(Wire.roomId("ABC234"), nil, "a code is no room id")
  eq(Wire.roomId("r0123456789abcdeg"), nil, "a non-hex room id is refused")
  eq(Wire.tourId("t0000000000000001"), "t0000000000000001", "a tournament id validates")
  eq(Wire.inviteId("i00000000000000ff"), "i00000000000000ff", "an invite id validates")
  eq(Wire.inviteToken(("ab"):rep(16)), ("ab"):rep(16), "an invite token validates")
  eq(Wire.inviteToken("abc"), nil, "a short invite token is refused")
  eq(Wire.playerId("0000abcd"), "0000abcd", "a player id validates")
  eq(Wire.playerId("RED"), nil, "a name is no player id")
  eq(Wire.pin("0000"), "0000", "0000 is a valid PIN")
  eq(Wire.pin("12a4"), nil, "a PIN is four digits")
  eq(Wire.pin(1234), nil, "a numeric PIN is refused")
  eq(Wire.code("trn234"), "TRN234", "Wire.code survives for private tournaments")

  local mon = Wire.mon3({ species = 25, level = 12, personality = 4000000000,
                          moves = { { id = 85, pp = 15, ppUps = 9 }, "junk" },
                          ivs = { hp = 31, atk = 40 }, gender = "X", extra = "drop" })
  eq(mon.species, 25, "mon3 keeps the species")
  eq(mon.personality, 4000000000, "mon3 keeps a 32-bit personality")
  eq(mon.item, 0, "mon3 always carries item")
  eq(mon.nickname, "", "mon3 defaults the nickname")
  eq(mon.status, "", "mon3 defaults the status")
  eq(mon.gender, "U", "an unknown gender reads as U")
  eq(#mon.moves, 1, "non-table moves are dropped")
  eq(mon.moves[1].ppUps, 3, "ppUps clamp to 3")
  eq(mon.ivs.atk, 40, "ivs are left for the strict unpacker to judge")
  eq(mon.ivs.spd, 0, "every iv key is present")
  eq(mon.extra, nil, "unknown mon fields are dropped")
  eq(mon.isEgg, false, "isEgg defaults to false")
  local party = Wire.party3({ mon, mon, mon, mon, mon, mon, mon })
  eq(#party, 6, "a Gen 3 party is capped at six")

  local av = Wire.avatar({ name = "LEAF", trainerId = 99999, gender = 3, version = "leafgreen" })
  eq(av.trainerId, 65535, "an avatar trainer id clamps to 16 bits")
  eq(av.gender, 1, "an avatar gender clamps to 0/1")
  eq(Wire.member({ id = "nothex", name = "X" }), nil, "a member needs a player id")

  local hello = Wire.sanitize({ type = "game3_hello", name = "RED", generation = 3,
                                seat = 1, game3 = { linkType = 0x2233, trainerId = 12345,
                                                    gender = 1, seat = 1 } })
  eq(hello.game3.linkType, 0x2233, "game3_hello keeps its game3 block")
  eq(hello.seat, 1, "game3_hello keeps the transport seat")
  eq(Wire.sanitize({ type = "game3_made_up", x = 1 }), nil,
     "an unknown game3_* type is dropped, never passed through")
  local chat = Wire.sanitize({ type = "game3_chat_line", name = "LONGNAMEX",
                               text = "abcdefghijklmnopqrstuvwxyz" })
  eq(#chat.text, 15, "a chat line is clipped to 15")
  eq(#chat.name, 7, "a chat name is clipped to 7")
  local setup = Wire.sanitize({ type = "game3_battle_setup", mode = "single",
                                party = { { species = 6, level = 50, moves = {} } } })
  eq(setup.party[1].species, 6, "game3_battle_setup carries mon3")
  eq(setup.party[1].item, 0, "and the mon3 item is present")
  local act = Wire.sanitize({ type = "game3_battle_action", turn = 3, kind = "list",
                              actions = { { kind = "move", slot = 1 },
                                          { kind = "move", slot = 2 },
                                          { kind = "move", slot = 3 } } })
  eq(#act.actions, 2, "a doubles action list is capped at two")
  local commit = Wire.sanitize({ type = "trade_commit", n = 2, seat = -1, relay = true,
                                 digests = { ("a"):rep(16), ("b"):rep(16), ("c"):rep(16) } })
  eq(#commit.digests, 2, "trade_commit carries two digests")
  eq(commit.seat, -1, "a relay-authored inner keeps seat -1")
  eq(commit.relay, true, "and its relay flag")
  eq(Wire.sanitize({ type = "game3_trade_confirm", digest = "xyz" }).digest, nil,
     "a malformed digest is dropped")
  local leader = Wire.sanitize({ type = "game3_mg_leader", seat = 2, prev = 0, epoch = 2 })
  eq(leader.seat, 2, "game3_mg_leader keeps the new leader's seat")
  local ms = Wire.sanitize({ type = "match_start", room = "r0000000000000001", match = "m",
                             role = "seat2", seat = 2, seats = 4, engine = 3,
                             parties = { { { species = 1 } }, {}, { { species = 4 } } } })
  eq(ms.parties[1][1].species, 1, "match_start parties hold mon3 per seat")
  eq(#ms.parties[2], 0, "an empty seat party stays empty")
  eq(ms.parties[3][1].item, 0, "and every seat's party is mon3-shaped")
  local entry = Wire.sanitize({ type = "lobby_list", entries = { {
    id = "p1", room = "r000000000000000a", code = "ABC234", locked = true, auto = true,
    seats = 4, engine = 3, where = "union", status = "recruiting" } } }).entries[1]
  eq(entry.code, nil, "a lobby entry never keeps a code")
  eq(entry.locked, true, "a lobby entry keeps its lock")
  eq(entry.engine, 3, "and its engine")
  eq(Wire.profile({ engine = 5 }).engine, 3, "the profile engine clamps to 1..3")
end

do
  for _, t in ipairs({ "set_profiles", "presence", "invite_token", "invite",
                       "invite_reply", "plaza_join", "plaza_leave", "group_open",
                       "group_list", "group_join", "group_accept", "group_leave",
                       "group_start", "direct_queue", "direct_list", "direct_leave" }) do
    check(Protocol2.CLIENT_TYPES[t], "CLIENT_TYPES has " .. t)
  end
  for _, t in ipairs({ "upgrade_required", "invite_token", "invite_sent", "invite_in",
                       "invite_closed", "plaza_state", "plaza_delta", "plaza_counts",
                       "group_state", "group_request", "group_list", "group_closed",
                       "direct_state", "direct_list" }) do
    check(Protocol2.SERVER_TYPES[t], "SERVER_TYPES has " .. t)
  end
  local reasons = { "lobby_disabled", "resume_unknown", "resume_expired", "already_in_room",
    "not_found", "full", "spectators_full", "bad_profile", "bad_party", "profile_mismatch",
    "party_ineligible", "spectate_late", "tour_not_found", "tour_started", "tour_full",
    "not_creator", "bad_room", "bad_pin", "pin_required", "pin_locked", "bad_seats",
    "bad_stage", "invite_expired", "tour_private", "group_not_found", "group_full",
    "group_below_min", "not_leader", "already_in_group", "bad_activity", "already_queued",
    "rate_limited" }
  for _, r in ipairs(reasons) do
    check(not Protocol2.joinErrorText({ reason = r }):find("Couldn't join", 1, true),
          "join_error " .. r .. " has its own text")
  end
  check(Protocol2.joinErrorText({ reason = "bad_pin", triesLeft = 2 }):find("2", 1, true) ~= nil,
        "bad_pin text says how many tries are left")
  check(Protocol2.joinErrorText({ reason = "pin_locked", retryAt = 1790000300000 }, 1790000000000)
          :find("5 min", 1, true) ~= nil,
        "pin_locked text says when to retry")
  check(Protocol2.joinErrorText({ reason = "pin_locked", retryAt = 1790000000000 }, 1790000300000)
          :find("min", 1, true) == nil,
        "a past retryAt adds nothing")
  local whys = { "accepted", "declined", "timeout", "busy", "offline", "self", "target_left",
    "sender_left", "rate_limited", "profile_mismatch", "bad_activity", "crossed", "no_room",
    "no_group", "group_full" }
  for _, w in ipairs(whys) do
    check(not Protocol2.inviteClosedText({ why = w }):find("invite closed", 1, true),
          "invite_closed " .. w .. " has its own text")
  end
  eq(select(2, Protocol2.validate({ type = "invite_in", id = "i0000000000000001",
                                    activity = "trade" })),
     "invite_in without a sender", "invite_in needs a sender")
  eq(select(2, Protocol2.validate({ type = "plaza_state", kind = "union" })),
     "plaza_state without members", "plaza_state needs members")
  eq(select(2, Protocol2.validate({ type = "match_start", role = "host", match = "m" })),
     "match_start without a room id", "match_start needs a room id")
  local q = Protocol2.directQueue({ activity = "battle_double", auto = true, pin = "1234",
                                    profile = PROFILE3, preview = { 1, 4, 7 } })
  eq(q.ruleset, "g3_double", "direct_queue fills the ruleset from the activity")
  eq(q.pin, "1234", "direct_queue carries a SET PIN")
  eq(#q.preview, 3, "and the preview species")
  eq(Protocol2.presence({ board = false }).board, false, "presence can clear the board")
  eq(Protocol2.seatRole(2), "seat2", "seat 2 reads as seat2")
  eq(Protocol2.roleSeat("guest"), 1, "guest reads as seat 1")
  eq(Protocol2.ACTIVITY_RULESET.battle_multi, "g3_multi", "multi rides g3_multi")
  eq(Protocol2.GROUP_CAPACITY.minigame_pick[1], 3, "Dodrio needs three")
end

do
  local w = newWorld({ minProtocol = 4 })
  local C, seat = w:add(1, "OLD")
  local upgrades = 0
  C.on("upgrade_required", function() upgrades = upgrades + 1 end)
  w:pump()
  eq(C.state(), "error", "upgrade_required lands the client in error")
  check(C.upgradeRequired() ~= nil, "and the payload is kept")
  check(tostring(C.error()):find("too old", 1, true) ~= nil, "the error is the upgrade text")
  eq(upgrades, 1, "the upgrade_required event fires once")
  local hellos = #w.relay:sent(seat, "lobby_hello")
  CLOCK = CLOCK + 60
  w:pump()
  eq(C.state(), "error", "an upgrade_required client never reconnects")
  eq(#w.relay:sent(seat, "lobby_hello"), hellos, "and never says hello again")
  C.disconnect()
  eq(C.upgradeRequired(), C.upgradeRequired(), "disconnect keeps the accessor callable")
end

do
  local w = newWorld()
  local Host, hs = w:add(0x10, "HOST")
  local Joiner = w:add(0x11, "JOIN")
  local Other = w:add(0x12, "OTHER")
  w:pump()
  eq(Host.state(), "online", "the host is online on protocol 3")
  eq(w.relay:sent(hs, "lobby_hello")[1].protocol, 3, "lobby_hello says protocol 3")
  local made = Host.createRoom({ intent = "battle", profile = PROFILE3, private = true,
                                 pin = "4321" })
  w:pump()
  check(made.done and Wire.roomId(made.id) ~= nil, "a private room is created with an id")
  eq(Host.room().locked, true, "the private room is locked")
  local roomId = made.id

  local noPin = Joiner.joinRoom(roomId, "player", PROFILE3)
  w:pump()
  eq(noPin.reason, "pin_required", "a locked room asks for a PIN")
  local wrong = Joiner.joinRoom(roomId, "player", PROFILE3, "0000")
  w:pump()
  eq(wrong.reason, "bad_pin", "a wrong PIN is refused")
  eq(wrong.triesLeft, 4, "and says how many tries are left")
  local last
  for _ = 1, 4 do
    last = Joiner.joinRoom(roomId, "player", PROFILE3, "1111")
    w:pump()
  end
  eq(last.reason, "pin_locked", "the fifth wrong PIN locks the joiner out")
  check(last.retryAt ~= nil, "with a retry time")
  local locked = Joiner.joinRoom(roomId, "player", PROFILE3, "4321")
  w:pump()
  eq(locked.reason, "pin_locked", "even the right PIN waits out the lock")

  local starts = {}
  Host.on("match_start", function(p) starts.host = p end)
  Other.on("match_start", function(p) starts.other = p end)
  local ok = Other.joinRoom(roomId, "player", PROFILE3, "4321")
  w:pump()
  check(ok.done and ok.error == nil, "the right PIN seats another joiner")
  eq(Other.room().stage, "battling", "an engine 3 room starts when the last seat fills")
  eq(starts.other and starts.other.seat, 1, "the joiner is seat 1")
  eq(starts.other and starts.other.role, "guest", "with the guest role")
  eq(starts.host and starts.host.seat, 0, "the host is seat 0")
  eq(starts.host and starts.host.engine, 3, "match_start says engine 3")
  eq(Other.roomSession().paired, true, "a full room reads as paired")
end

do
  local w = newWorld()
  local A = w:add(0x20, "AAA", { profile3("g3_link") })
  local B = w:add(0x21, "BBB", { profile3("g3_link") })
  w:pump()
  local inbound, closedA, closedB = nil, {}, {}
  B.on("invite_in", function(m) inbound = m end)
  A.on("invite_closed", function(m) closedA[#closedA + 1] = m end)
  B.on("invite_closed", function(m) closedB[#closedB + 1] = m end)

  local h = A.invite(pid(0x21), "trade", {}, profile3("g3_link"))
  eq(h.state, "sending", "a fresh invite is sending")
  w:pump()
  eq(h.state, "sent", "invite_sent marks it sent")
  check(Wire.inviteId(h.id) ~= nil, "and gives it an id")
  eq(#A.outgoing(), 1, "the outgoing list holds it")
  check(inbound ~= nil and inbound.activity == "trade", "the target gets invite_in")
  eq(inbound and inbound.from.id, pid(0x20), "naming the sender")
  eq(#B.invites(), 1, "the target's invite list holds it")
  local starts = {}
  A.on("match_start", function(p) starts.a = p end)
  B.on("match_start", function(p) starts.b = p end)
  check(B.replyInvite(inbound.id, true), "the target accepts")
  eq(#B.invites(), 0, "a replied invite leaves the list")
  w:pump()
  eq(h.state, "accepted", "the sender's handle is accepted")
  check(Wire.roomId(h.room) ~= nil, "with the new room")
  eq(#A.outgoing(), 0, "and leaves the outgoing list")
  eq(A.room() and A.room().origin, "invite", "both land in an invite room")
  eq(A.room() and A.room().listed, false, "which is unlisted")
  eq(A.room() and A.room().intent, "trade", "with the trade intent")
  eq(starts.a and starts.a.seat, 0, "the sender is seat 0")
  eq(starts.b and starts.b.seat, 1, "the target is seat 1")
  eq(closedA[#closedA].why, "accepted", "invite_closed accepted reaches the sender")
  eq(closedB[#closedB].why, "accepted", "and the target")
  A.leaveRoom(); B.leaveRoom()
  w:pump()

  local h2 = A.invite(pid(0x21), "chat", {}, profile3("g3_link"))
  w:pump()
  B.replyInvite(B.invites()[1].id, false)
  w:pump()
  eq(h2.state, "closed", "a declined invite closes")
  eq(h2.why, "declined", "with why declined")
  eq(A.room(), nil, "and no room")

  local selfH = A.invite(pid(0x20), "battle_single", {}, profile3("g3_single"))
  w:pump()
  eq(selfH.state, "closed", "inviting yourself is refused")
  eq(selfH.why, "self", "with why self")
  local ghost = A.invite(pid(0x99), "battle_single", {}, profile3("g3_single"))
  w:pump()
  eq(ghost.why, "offline", "an unknown target is offline")
  eq(#A.outgoing(), 0, "refused invites leave the outgoing list")

  local ha = A.invite(pid(0x21), "battle_single", {}, profile3("g3_single"))
  w:pump()
  local hb = B.invite(pid(0x20), "battle_single", {}, profile3("g3_single"))
  w:pump()
  eq(ha.state, "accepted", "crossed invites accept the earlier one")
  eq(hb.state, "accepted", "the later one reads as accepted too")
  eq(hb.why, "crossed", "with why crossed")
  eq(#B.invites(), 0, "the crossed incoming invite is gone")
  check(A.room() ~= nil and B.room() ~= nil and A.room().room == B.room().room,
        "and both share one room")
  A.leaveRoom(); B.leaveRoom()
  w:pump()

  local h3 = A.invite(pid(0x21), "card", {}, profile3("g3_link"))
  w:pump()
  eq(#B.invites(), 1, "a pending invite waits")
  CLOCK = CLOCK + 30
  w:pump()
  eq(#B.invites(), 0, "an expired invite is pruned")
  eq(h3.state, "sent", "the sender waits for the relay's timeout")
end

do
  local w = newWorld()
  local A = w:add(0x30, "ANN")
  local B = w:add(0x31, "BEN")
  local Mon = w:add(0x32, "MON")
  w:pump()
  local plazaEvents = 0
  A.on("plaza", function() plazaEvents = plazaEvents + 1 end)
  A.joinPlaza("union", PROFILE3, avatar("ANN", 100, 1))
  w:pump()
  local p = A.plaza()
  check(p ~= nil and p.kind == "union", "plaza_state lands")
  eq(p and p.you, 1, "the first member takes slot 1")
  eq(p and #p.members, 1, "and is alone")
  B.joinPlaza("union", PROFILE3, avatar("BEN", 201, 0))
  w:pump()
  eq(#A.plaza().members, 2, "plaza_delta adds the joiner")
  eq(A.plaza().members[2].slot, 2, "members sort by slot")
  eq(A.plaza().members[2].avatar.trainerId, 201, "and carry their avatar")
  eq(B.plaza().you, 2, "the joiner gets the next slot")
  B.setPresence({ board = { species = 25, level = 10, wantType = 12 } })
  w:pump()
  eq(A.plaza().members[2].board and A.plaza().members[2].board.species, 25,
     "a trading board change reaches the plaza")
  B.setPresence({ board = false })
  w:pump()
  eq(A.plaza().members[2].board, nil, "clearing the board clears it")
  Mon.joinPlaza("wireless")
  w:pump()
  w.relay:tick()
  w:pump()
  eq(Mon.plazaCounts() and Mon.plazaCounts().union, 2, "the wireless monitor counts the plaza")
  eq(Mon.plazaCounts() and Mon.plazaCounts().total, 2, "and the total")
  B.leavePlaza("union")
  w:pump()
  eq(#A.plaza().members, 1, "plaza_delta removes a leaver")
  eq(B.plaza(), nil, "the leaver's plaza is gone")
  check(plazaEvents >= 4, "every plaza change emits a plaza event")
  local wrong = B.joinPlaza("union", { engine = 1, fingerprint = "x" }, avatar("BEN", 1))
  local errs = {}
  B.on("error", function(e) errs[#errs + 1] = e end)
  w:pump()
  check(wrong and errs[1] and errs[1].reason == "bad_profile",
        "the union plaza refuses a non-engine-3 profile")
end

do
  local w = newWorld()
  local L = w:add(0x40, "LEAD", { profile3("g3_link") })
  local M = w:add(0x41, "MEMB", { profile3("g3_link") })
  w:pump()
  L.openGroup("minigame_jump", nil, avatar("LEAD", 7))
  w:pump()
  local g = L.group()
  eq(g and g.leader, pid(0x40), "group_open makes a group")
  eq(g and g.min, 2, "with the cart's minimum")
  eq(g and g.max, 5, "and maximum")
  local errs = {}
  L.on("error", function(e) errs[#errs + 1] = e end)
  L.startGroup()
  w:pump()
  eq(errs[1] and errs[1].reason, "group_below_min", "a lone leader cannot start")
  M.groupList("minigame_jump")
  w:pump()
  eq(#M.groups("minigame_jump"), 1, "the watcher sees the group")
  local req
  L.on("group_request", function(m) req = m end)
  M.joinGroup(pid(0x40), nil, avatar("MEMB", 8))
  w:pump()
  eq(req and req.from, pid(0x41), "the leader gets group_request")
  eq(#L.group().pending, 1, "the joiner is pending")
  L.acceptGroup(pid(0x41), true)
  w:pump()
  eq(#L.group().members, 2, "accepting seats the joiner")
  eq(M.group() and #M.group().members, 2, "the member sees the group state")
  local P = w:add(0x42, "PEND", { profile3("g3_link") })
  w:pump()
  P.joinGroup(pid(0x40), nil, avatar("PEND", 9))
  w:pump()
  eq(#L.group().pending, 1, "a second joiner waits unanswered")
  local closedP = {}
  P.on("group_closed", function(m) closedP[#closedP + 1] = m end)
  local closed
  M.on("group_closed", function(m) closed = m end)
  local startM
  M.on("match_start", function(p) startM = p end)
  L.startGroup()
  w:pump()
  eq(closed and closed.why, "started", "group_closed says started")
  eq(#closedP, 1, "the pending joiner gets one group_closed")
  eq(closedP[1] and closedP[1].why, "full", "saying full, not started")
  eq(P.group(), nil, "and its group is cleared")
  eq(P.room(), nil, "without a seat in the room")
  eq(M.group(), nil, "the member's group is cleared")
  eq(L.group(), nil, "and the leader's")
  eq(M.room() and M.room().origin, "group", "a group room is born")
  eq(M.room() and M.room().intent, "minigame", "with the minigame intent")
  eq(M.room() and M.room().leader, 0, "the leader seat is 0")
  eq(M.room() and M.room().stage, "battling", "born battling")
  eq(startM and startM.seat, 1, "the member is seat 1")
  eq(startM and startM.seats, 2, "of two")
end

do
  local w = newWorld()
  local A = w:add(0x50, "AUTOA")
  local B = w:add(0x51, "AUTOB")
  local C = w:add(0x52, "PINHOST")
  local D = w:add(0x53, "CHOOSER")
  w:pump()
  local directA
  A.on("direct", function(m) directA = m end)
  A.queueDirect({ activity = "battle_single", auto = true, avatar = avatar("AUTOA", 1),
                  preview = { 1, 4 } })
  w:pump()
  eq(directA and directA.queued, true, "AUTO queues")
  CLOCK = CLOCK + 1
  local sa, sb
  A.on("match_start", function(p) sa = p end)
  B.on("match_start", function(p) sb = p end)
  B.queueDirect({ activity = "battle_single", auto = true, avatar = avatar("AUTOB", 2) })
  w:pump()
  eq(directA and directA.why, "paired", "the earlier AUTO player is paired")
  eq(A.direct() and A.direct().queued, false, "and no longer queued")
  eq(sa and sa.seat, 0, "the earlier-queued player is seat 0")
  eq(sb and sb.seat, 1, "the later one seat 1")
  eq(A.room() and A.room().origin, "direct", "in a direct room")
  eq(A.room() and A.room().stage, "battling", "born battling")

  C.queueDirect({ activity = "trade", auto = true, pin = "7777",
                  profile = profile3("g3_link"), avatar = avatar("PINHOST", 3) })
  w:pump()
  check(C.direct() and Wire.roomId(C.direct().hosting) ~= nil, "SET PIN hosts a room")
  eq(C.room() and C.room().locked, true, "which is locked")
  D.directList("trade", profile3("g3_link"))
  w:pump()
  local entries = D.directEntries("trade")
  eq(#entries, 1, "CHOOSE lists the hosted room")
  eq(entries[1] and entries[1].kind, "room", "as a room entry")
  eq(entries[1] and entries[1].locked, true, "with its lock")
  eq(entries[1] and entries[1].auto, true, "and its AUTO opt-in")
  local sd
  D.on("match_start", function(p) sd = p end)
  D.queueDirect({ activity = "trade", auto = true, profile = profile3("g3_link"),
                  avatar = avatar("CHOOSER", 4) })
  w:pump()
  eq(sd and sd.seat, 1, "AUTO pairs into a PIN host that opted in, PIN bypassed")
  eq(D.room() and D.room().room, C.room() and C.room().room, "both share the host's room")
  D.leaveDirect()
  w:pump()
  eq(D.direct() and D.direct().why, "left", "direct_leave answers direct_state left")
end

do
  local w = newWorld()
  local cs, seats = {}, {}
  for i = 1, 4 do
    cs[i], seats[i] = w:add(0x60 + i, "MULTI" .. i, { profile3("g3_multi") })
  end
  local Spec = w:add(0x6f, "WATCHER", { profile3("g3_multi") })
  w:pump()
  for i = 1, 4 do
    cs[i].queueDirect({ activity = "battle_multi", auto = true, avatar = avatar("M" .. i, i) })
    CLOCK = CLOCK + 1
    w:pump()
  end
  eq(cs[1].room() and cs[1].room().seats, 4, "four AUTO players form a multi room")
  eq(cs[3].seat(), 2, "the third queued is seat 2")
  eq(cs[3].role(), "seat2", "with the seat2 role")
  local rs3 = cs[3].roomSession()
  eq(rs3:seats(), 4, "the room session knows four seats")
  eq(rs3.paired, true, "and is paired once all four sit")
  local token
  cs[1].on("invite_token", function(m) token = m.token end)
  check(cs[1].inviteToken(), "a seated player mints an invite token")
  w:pump()
  check(Wire.inviteToken(token) ~= nil, "the token comes back")
  local watched = Spec.joinRoomByInvite(token, "spectator")
  w:pump()
  check(watched.done and watched.error == nil, "a spectator joins the unlisted room by token")
  eq(Spec.role(), "spectator", "as a spectator")
  local rsSpec = Spec.roomSession()
  rsSpec:poll()
  for i = 1, 4 do cs[i].roomSession():poll() end

  rs3:send({ type = "game3_battle_action", turn = 1, kind = "move", slot = 2 })
  w:pump()
  for _, i in ipairs({ 1, 2, 4 }) do
    local got = cs[i].roomSession():poll()
    eq(#got, 1, ("seat %d gets seat 2's action"):format(i - 1))
    eq(got[1] and got[1].seat, 2, ("tagged with seat 2 at seat %d"):format(i - 1))
  end
  eq(#rs3:poll(), 0, "the sender never gets its own message")
  local sg = rsSpec:poll()
  eq(#sg, 1, "the spectator gets it too")
  eq(sg[1] and sg[1].type, "game3_battle_action", "bare, without a spectate wrapper")
  eq(sg[1] and sg[1].seat, 2, "and tagged with the sender's seat")
  cs[1].roomSession():send({ type = "game3_battle_action", turn = 1, kind = "move",
                             slot = 1, seat = 3, relay = true })
  w:pump()
  local spoof = cs[2].roomSession():take("game3_battle_action")
  eq(spoof and spoof.seat, 0, "the envelope seat wins over a spoofed inner seat")
  eq(spoof and spoof.relay, nil, "and a spoofed relay flag is stripped")
  cs[1].roomSession():send({ type = "trade_commit", n = 1, digests = {} })
  w:pump()
  eq(cs[2].roomSession():take("trade_commit"), nil,
     "a client-authored trade_commit never reaches a peer")
  eq(cs[2].roomSession():peerOnline(3), true, "peerOnline reads the seat's online flag")
end

do
  local w = newWorld()
  local A, sa = w:add(0x70, "TRA", { profile3("g3_link") })
  local B = w:add(0x71, "TRB", { profile3("g3_link") })
  w:pump()
  A.invite(pid(0x71), "trade", {}, profile3("g3_link"))
  w:pump()
  B.replyInvite(B.invites()[1].id, true)
  w:pump()
  local ra, rb = A.roomSession(), B.roomSession()
  check(ra ~= nil and rb ~= nil, "both traders hold a room session")
  ra:poll(); rb:poll()
  local commitsA, commitsB = {}, {}
  A.on("trade_commit", function(m) commitsA[#commitsA + 1] = m end)
  B.on("trade_commit", function(m) commitsB[#commitsB + 1] = m end)
  local digest = ("0123456789abcdef")
  ra:send({ type = "game3_trade_confirm", digest = digest })
  w:pump()
  w.relay:drop(sa)
  A.update(0)
  eq(A.state(), "reconnecting", "the first confirmer drops")
  rb:send({ type = "game3_trade_confirm", digest = digest })
  w:pump()
  local gotB = rb:take("trade_commit")
  check(gotB ~= nil, "the connected seat gets trade_commit through its inbox")
  eq(gotB and gotB.seat, -1, "tagged as relay-authored")
  eq(gotB and gotB.relay, true, "with the relay flag")
  eq(gotB and gotB.digests[1], digest, "carrying both digests")
  eq(#commitsB, 1, "and the trade_commit event fires")
  eq(#commitsA, 0, "the dropped seat has not seen it yet")

  w.relay:reconnect(sa)
  CLOCK = CLOCK + 2
  A.update(0)
  w:pump()
  eq(A.state(), "online", "the dropped seat resumes")
  check(A.roomSession() == ra, "its room session survives the resume")
  local replayed = ra:take("trade_commit")
  check(replayed ~= nil, "resume replays trade_commit to the dropped seat")
  eq(replayed and replayed.n, 1, "the first barrier")
  eq(replayed and replayed.seat, -1, "tagged relay-authored")
  eq(#commitsA, 1, "and fires the event once")
  eq(ra:take("game3_trade_confirm") and true or false, true,
     "the peer's confirm is replayed too")

  ra:send({ type = "game3_trade_confirm", digest = ("1"):rep(16) })
  rb:send({ type = "game3_trade_confirm", digest = ("2"):rep(16) })
  local aborts = {}
  A.on("trade_abort", function(m) aborts[#aborts + 1] = m end)
  w:pump()
  eq(aborts[1] and aborts[1].why, "digest", "differing digests abort")
  eq(aborts[1] and aborts[1].n, 2, "on the second barrier")
end

do
  local w = newWorld()
  local A, sa = w:add(0x80, "REJOIN", { PROFILE3 },
                      { where = "launcher", status = "idle", version = "firered" })
  w:pump()
  A.setProfiles({ PROFILE3, profile3("g3_link") })
  A.setPresence({ status = "busy" })
  A.joinPlaza("union", PROFILE3, avatar("REJOIN", 5))
  A.queueDirect({ activity = "battle_double", auto = true, profile = profile3("g3_double") })
  A.openGroup("minigame_crush", profile3("g3_link"), avatar("REJOIN", 5))
  A.groupList("minigame_pick", profile3("g3_link"))
  w:pump()
  local hello = w.relay:sent(sa, "lobby_hello")[1]
  eq(hello.presence and hello.presence.version, "firered", "the hello carries presence")

  w.relay:drop(sa)
  A.update(0)
  w.relay:reconnect(sa)
  CLOCK = CLOCK + 2
  A.update(0)
  local plazaStates = 0
  A.on("plaza", function(p) if p then plazaStates = plazaStates + 1 end end)
  w:pump()
  eq(A.state(), "online", "a resumed session is online")
  eq(plazaStates, 1, "the relay re-sends plaza_state on resume")
  local resent = 0
  for _, t in ipairs(outTypes(sa)) do
    if t == "plaza_join" or t == "direct_queue" or t == "group_open" then resent = resent + 1 end
  end
  eq(resent, 0, "a resumed session re-sends nothing")

  w.relay:drop(sa)
  w.relay:forget(sa)
  A.update(0)
  w.relay:reconnect(sa)
  CLOCK = CLOCK + 4
  A.update(0)
  w.relay:pump()
  A.update(0)
  local before = #w.relay.log
  w.relay:pump()
  A.update(0)
  w.relay:pump()
  local order = {}
  for i = before + 1, #w.relay.log do
    local m = w.relay.log[i]
    if m.from == sa.id then order[#order + 1] = m.msg.type end
  end
  local want = { "lobby_hello", "set_profiles", "presence", "plaza_join", "direct_queue",
                 "group_open", "group_list" }
  local seq = table.concat(order, ",")
  eq(seq, table.concat(want, ","), "a fresh welcome re-sends the session state in order")
  local presence = w.relay:sent(sa, "presence")
  eq(presence[#presence].status, "busy", "the re-sent presence is the latest")
  local sp = w.relay:sent(sa, "set_profiles")
  eq(#sp[#sp].profiles, 2, "the re-sent profiles are the latest")

  A.leavePlaza("union")
  A.leaveDirect()
  A.leaveGroup()
  A.groupList(nil)
  w:pump()
  w.relay:drop(sa)
  w.relay:forget(sa)
  A.update(0)
  w.relay:reconnect(sa)
  CLOCK = CLOCK + 8
  A.update(0)
  local mark = #w.relay.log
  w:pump(4)
  local again = {}
  for i = mark + 1, #w.relay.log do
    local m = w.relay.log[i]
    if m.from == sa.id then again[#again + 1] = m.msg.type end
  end
  eq(table.concat(again, ","), "resume,lobby_hello,set_profiles,presence",
     "left plazas, queues and groups are not re-joined")
end

do
  local w = newWorld()
  local L = w:add(0x90, "MGL", { profile3("g3_link") })
  local M = w:add(0x91, "MGM", { profile3("g3_link") })
  local N = w:add(0x92, "MGN", { profile3("g3_link") })
  w:pump()
  L.openGroup("minigame_crush", nil, avatar("MGL", 1))
  w:pump()
  M.joinGroup(pid(0x90), nil, avatar("MGM", 2))
  N.joinGroup(pid(0x90), nil, avatar("MGN", 3))
  w:pump()
  L.acceptGroup(pid(0x91), true)
  L.acceptGroup(pid(0x92), true)
  w:pump()
  L.startGroup()
  w:pump()
  local roomId = M.room() and M.room().room
  eq(M.room() and M.room().seats, 3, "a three-member Berry Crush room")
  local rm = M.roomSession()
  rm:poll()
  N.roomSession():poll()
  M.roomSession():send({ type = "game3_mg_state", f = 3, e = 1, s = { x = 1 } })
  w:pump()
  eq(N.roomSession():take("game3_mg_state"), nil, "a non-leader's mg_state is dropped")
  w.relay:drop(w.relay.sessions[pid(0x90)])
  w.relay:migrateLeader(roomId)
  w:pump()
  local lead = rm:take("game3_mg_leader")
  eq(lead and lead.seat, 1, "game3_mg_leader names the new leader seat")
  eq(lead and lead.prev, 0, "and the previous one")
  eq(lead and lead.relay, true, "and is relay-authored")
  eq(M.room().leader, 1, "the room state follows the new leader")
end

do
  local w = newWorld()
  local L = w:add(0x94, "MGL", { profile3("g3_link") })
  local M = w:add(0x95, "MGM", { profile3("g3_link") })
  w:pump()
  L.openGroup("minigame_jump", nil, avatar("MGL", 1))
  w:pump()
  M.joinGroup(pid(0x94), nil, avatar("MGM", 2))
  w:pump()
  L.acceptGroup(pid(0x95), true)
  w:pump()
  L.startGroup()
  w:pump()
  eq(L.room() and L.room().intent, "minigame", "a minigame room")
  eq(L.room() and L.room().players[1].seat, 0, "the leader holds seat 0")
  L.leaveRoom()
  w:pump()
  local sa = w.relay.sessions[pid(0x94)]
  eq(#w.relay:sent(sa, "room_close"), 0, "seat 0 leaving a minigame room sends no room_close")
  eq(#w.relay:sent(sa, "room_leave"), 1, "only a plain room_leave")
end

do
  local EPOCH = 1790000000000
  local w = newWorld({ epoch = EPOCH })
  local A = w:add(0xa0, "AAA", { profile3("g3_link") })
  local B = w:add(0xa1, "BBB", { profile3("g3_link") })
  w:pump()
  check((B.serverTime() or 0) >= EPOCH, "lobby_welcome.serverTime keeps epoch milliseconds")
  local h = A.invite(pid(0xa1), "trade", {}, profile3("g3_link"))
  w:pump()
  local held = B.invites()[1]
  eq(#B.invites(), 1, "an epoch-stamped invite_in is not pruned on arrival")
  check(held and (held.expiresAt or 0) > EPOCH, "expiresAt keeps epoch milliseconds")
  check(B.replyInvite(held and held.id, true), "and can be answered")
  w:pump()
  eq(h.state, "accepted", "the sender sees it accepted")
end

do
  local w = newWorld()
  local A = w:add(0xb0, "AAA", { profile3("g3_link") })
  local sa = w.relay.sessions[pid(0xb0)]
  w:pump()
  A.createRoom({ intent = "trade", profile = profile3("g3_link") })
  w:pump()
  local old = A.room() and A.room().room
  check(Wire.roomId(old) ~= nil, "a room to leave")
  A.leaveRoom()
  local stale = { type = "room_state", room = old, intent = "trade", engine = 3, seats = 2,
                  players = { { id = pid(0xb0), name = "AAA", seat = 0 } }, stage = "waiting" }
  w.relay:to(sa, stale)
  w.relay:to(sa, { type = "match_start", room = old, seat = 0, seats = 2, role = "host",
                   engine = 3, seed = 7 })
  local started = false
  A.on("match_start", function() started = true end)
  A.update(0)
  eq(A.room(), nil, "a room_state for the room just left is dropped")
  eq(started, false, "and so is its match_start")
  local p = A.createRoom({ intent = "trade", profile = profile3("g3_link") })
  w.relay:to(sa, stale)
  A.update(0)
  eq(p.done, false, "a stale room_state does not answer the next create")
  w:pump()
  check(p.done and A.room() and A.room().room ~= old, "the new room lands")
  A.leaveRoom()
  local rejoin = A.joinRoom(old, "player", profile3("g3_link"))
  w.relay:to(sa, stale)
  A.update(0)
  eq(A.room() and A.room().room, old, "an explicit rejoin of the left room is still applied")
  eq(rejoin.done, true, "and answers that join")
end

do
  local m = Wire.member({ id = pid(1), group = { leader = pid(1), members = { pid(1), pid(2) },
                                                  activity = "chat" } })
  eq(m and m.group and m.group.leader, pid(1), "plaza members keep group.leader")
  eq(m and m.group and #m.group.members, 2, "and group.members")
  eq(m and m.group and m.group.activity, "chat", "and group.activity")
  local inv = Wire.sanitize({ type = "invite", to = pid(2), activity = "chat",
                              detail = { join = true } })
  eq(inv and inv.detail.join, true, "invites keep detail.join")
  local line = Wire.sanitize({ type = "game3_chat_line", name = "\195\137LODIE12",
                               text = "HI\238\131\144\195\169\226\128\166ABCDEFGHIJKLMNOP" })
  eq(line and line.text, "HI\238\131\144\195\169\226\128\166ABCDEFGHIJ",
     "a chat line clips to 15 characters, not 15 bytes")
  eq(line and line.name, "\195\137LODIE1", "a chat name clips to 7 characters")
  local ready = Wire.sanitize({ type = "game3_mg_ready", species = 25, partySlot = 0,
                                name = "RED", trainerId = 12345, gender = 1 })
  eq(ready and ready.name, "RED", "game3_mg_ready keeps the OT name")
  eq(ready and ready.trainerId, 12345, "and the trainer id")
  eq(ready and ready.gender, 1, "and the gender")
end

do
  local Session = require("src.link.Session")
  local queue = {
    { type = "forfeit", seat = 2, reason = "gave up", match = "r0123456789abcdef-m1" },
    { type = "bye", seat = 3, relay = false },
  }
  local transport = { closed = false }
  function transport.update() end
  function transport.poll()
    local out = queue
    queue = {}
    return out
  end
  function transport.send() end
  function transport.close() end
  local s = Session.new(transport, { role = "host", kind = "game3" })
  s:update()
  local f = s:take("forfeit")
  eq(f and f.seat, 2, "an engine 3 forfeit keeps its sender seat through the session's sanitize")
  eq(f and f.reason, "gave up", "and its reason")
  eq(f and f.match, "r0123456789abcdef-m1", "and its match")
  local b = s:take("bye")
  eq(b and b.seat, 3, "an engine 3 bye keeps its sender seat")
  eq(Wire.sanitize({ type = "forfeit", seat = 9 }).seat, 4, "a forfeit seat clamps to the wire range")
end

do
  local w = newWorld()
  local A, sa = w:add(0xB0, "BOARD", { profile3("g3_link") })
  local B = w:add(0xB1, "WATCH", { profile3("g3_link") })
  w:pump()
  A.setPresence({ board = { species = 1, level = 5, wantType = 3 } })
  w:pump()
  eq(sa.presence.board, nil, "the relay ignores a board sent before plaza_join")
  A.joinPlaza("union", profile3("g3_link"), avatar("BOARD", 1))
  B.joinPlaza("union", profile3("g3_link"), avatar("WATCH", 2))
  w:pump()
  A.setPresence({ board = { species = 25, level = 12, wantType = 10 } })
  w:pump()
  eq(sa.presence.board and sa.presence.board.species, 25, "the relay holds the board once in the plaza")
  w.relay:drop(sa)
  w.relay:forget(sa)
  A.update(0)
  w.relay:reconnect(sa)
  CLOCK = CLOCK + 4
  A.update(0)
  w:pump(6)
  eq(A.state(), "online", "a forgotten session comes back on a fresh welcome")
  eq(A.plaza() ~= nil, true, "and re-joins the union plaza")
  local order = {}
  for _, m in ipairs(w.relay:sent(sa)) do
    if m.type == "plaza_join" or (m.type == "presence" and type(m.board) == "table") then
      order[#order + 1] = m.type
    end
  end
  eq(order[#order], "presence", "the board presence goes out after the fresh plaza_join")
  eq(sa.presence.board and sa.presence.board.species, 25,
     "so the relay holds the trading board again after a fresh welcome")
  local seen
  for _, m in ipairs(B.plaza() and B.plaza().members or {}) do
    if m.id == pid(0xB0) then seen = m.board end
  end
  eq(seen and seen.species, 25, "and the other plaza member sees it")
end

do
  local w = newWorld()
  local H, sh = w:add(0xC0, "HOST", { profile3("g3_link") })
  local G, sg = w:add(0xC1, "GUEST", { profile3("g3_link") })
  w:pump()
  H.createRoom({ intent = "trade", profile = profile3("g3_link") })
  w:pump()
  local roomId = H.room() and H.room().room
  G.joinRoom(roomId, "player", profile3("g3_link"))
  w:pump()
  local hrs, grs = H.roomSession(), G.roomSession()
  eq(grs and grs:seat(), 1, "the guest holds seat 1 of the trade room")
  local digest = ("ab"):rep(8)
  hrs:send({ type = "game3_trade_confirm", digest = digest })
  grs:send({ type = "game3_trade_confirm", digest = digest })
  w.relay:pump()
  H.update(0)
  local hostCommit
  for _, m in ipairs(hrs:poll()) do
    if m.type == "trade_commit" then hostCommit = m end
  end
  eq(hostCommit and hostCommit.n, 1, "the host gets trade_commit")
  hrs:close()
  w.relay:pump()
  eq(#w.relay:sent(sh, "room_close"), 0, "the host leaving a trade room sends no room_close")
  eq(#w.relay:sent(sh, "room_leave"), 1, "only a plain room_leave")
  eq(w.relay.rooms[roomId] ~= nil, true, "so the room and its log outlive the host")
  G.update(0)
  local guestCommit
  for _, m in ipairs(grs:poll()) do
    if m.type == "trade_commit" then guestCommit = m end
  end
  eq(guestCommit and guestCommit.n, 1, "the guest still gets trade_commit")
  w.relay:drop(sg)
  G.update(0)
  w.relay:reconnect(sg)
  CLOCK = CLOCK + 4
  G.update(0)
  w:pump(4)
  eq(G.room() and G.room().room, roomId, "a resuming guest still finds the room")
end

do
  local t = FakeRelay.transport()
  local C = newClient()
  C.configure({ relayAddress = "fake:1", connect = function() return t end })
  C.connect({ name = "X", profiles = { PROFILE3 } })
  t.inbox[#t.inbox + 1] = { type = "lobby_welcome", session = "s-b", resumed = false,
    you = { id = pid(0xD1), name = "X", verified = true }, serverTime = 1790000000000,
    heartbeatMs = 10000 }
  C.update(0)
  local room = "r00000000000000d0"
  t.inbox[#t.inbox + 1] = { type = "room_state", room = room, intent = "trade", engine = 3,
    profile = profile3("g3_link"), seats = 2, stage = "battling", host = pid(0xD0),
    match = room .. "-m1", origin = "invite",
    players = { { id = pid(0xD0), name = "H", seat = 0 }, { id = pid(0xD1), name = "X", seat = 1 } } }
  C.update(0)
  local rs = C.roomSession()
  t.inbox[#t.inbox + 1] = { type = "room_msg", seq = 3, seat = 0,
    msg = { type = "game3_trade_cmd", cmd = 1 } }
  t.inbox[#t.inbox + 1] = { type = "room_msg", seq = 4, seat = -1, relay = true,
    msg = { type = "trade_commit", n = 1, digests = { ("cd"):rep(8), ("cd"):rep(8) } } }
  t.inbox[#t.inbox + 1] = { type = "room_closed", reason = "closed", room = room }
  C.update(0)
  eq(C.room(), nil, "room_closed clears the room")
  eq(rs.closed, true, "and closes the room session")
  eq(rs:hasPending(), true, "a relay trade_commit sharing the pump stays pending on it")
  local got = rs:take("trade_commit")
  eq(got and got.n, 1, "and is still delivered")
  eq(got and got.seat, -1, "as a relay message")
  eq(rs:take("game3_trade_cmd"), nil, "peer traffic of the closed room is not kept")
  eq(rs:hasPending(), false, "the leftover drains once")
end

love.timer.getTime = savedGetTime

if failures > 0 then
  print(("\n%d online client gen 3 check(s) failed"):format(failures))
  os.exit(1)
end
print("\nonline client gen 3 tests passed")
return failures
