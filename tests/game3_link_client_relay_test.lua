#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_items").install()

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

local okR, Relay = pcall(require, "tests.support.fake_relay")
if not okR then
  print("[skip] tests/support/fake_relay.lua is not in this tree: " .. tostring(Relay))
  os.exit(0)
end

local function newClientModule()
  package.loaded["src.online.Client"] = nil
  local Client = require("src.online.Client")
  Client.reset()
  return Client
end

local PROFILE = {
  engine = 3, version = "firered", engineVersion = "0.0.0-dev", apiVersion = "2",
  fingerprint = "g3fingerprint", rulesetId = "g3_link", kind = "vanilla", rule = {},
}

local relay = Relay.new()
local seatA = relay:seat("a0000001", "RED")
local seatB = relay:seat("b0000002", "BLUE")

local ClientB = newClientModule()
ClientB.configure({ relayAddress = "fake:1", connect = function() return seatB.transport end })
local ClientA = newClientModule()
ClientA.configure({ relayAddress = "fake:1", connect = function() return seatA.transport end })

local function step(n)
  for _ = 1, n or 3 do
    relay:pump()
    ClientA.update(0)
    ClientB.update(0)
  end
end

ClientA.connect({ name = "RED", profiles = { PROFILE } })
ClientB.connect({ name = "BLUE", profiles = { PROFILE } })
step()
eq(ClientA.state(), "online", "A is online on the fake relay")
eq(ClientB.state(), "online", "B is online on the fake relay")

local session = { name = "RED", trainerId = 0x1234, gender = 0, party = {} }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}
local RelayTransport = require("src.core.game3.link.relay_transport")
local Game3Link = require("src.link.Game3Link")
local game = { data = {}, save = { player = { name = "RED" }, options = {} } }

print("[test] 1. two AUTO queues pair into a relay room born battling")
ClientA.queueDirect({ activity = "trade", ruleset = "g3_link", auto = true, profile = PROFILE,
  avatar = { name = "RED", trainerId = 1, gender = 0, version = "firered" }, preview = { 1 } })
step()
ClientB.queueDirect({ activity = "trade", ruleset = "g3_link", auto = true, profile = PROFILE,
  avatar = { name = "BLUE", trainerId = 2, gender = 0, version = "leafgreen" }, preview = { 4 } })
step()
local roomA = ClientA.room()
check(roomA ~= nil, "A has a room")
eq(roomA and roomA.stage, "battling", "born battling")
check(roomA and roomA.match ~= nil, "with a match token")
eq(ClientA.seat(), 0, "A queued first: seat 0")
eq(ClientB.seat(), 1, "B: seat 1")

print("[test] 2. Game3Link handshakes over the real Client room sessions")
local tA = RelayTransport.new(ClientA.roomSession(), { client = ClientA })
local tB = RelayTransport.new(ClientB.roomSession(), { client = ClientB })
eq(tA:seat(), 0, "transport A is seat 0")
eq(tB:seat(), 1, "transport B is seat 1")
eq(tA:seed(), roomA.seed, "the relay seed")
local lA = Game3Link.attach(tA, { game = game })
local lB = Game3Link.attach(tB, { game = game, hello = Game3Link.hello(game,
  Game3Link.LINKTYPE.TRADE, { name = "BLUE", trainerId = 2, gender = 0 }) })
for _ = 1, 4 do
  step(1)
  lA:update(0)
  lB:update(0)
end
check(lA:isReady(), "A reached ready")
check(lB:isReady(), "B reached ready")
eq(lA:peerName(), "BLUE", "A names BLUE")
eq(lB:peerName(), "RED", "B names RED")
eq(lA.peerHellos[1] and lA.peerHellos[1].seat, 1, "the hello arrived tagged with seat 1")

print("[test] 3. messages cross the relay seat-tagged, the relay barrier commits")
lA:send({ type = "game3_trade_cmd", cmd = 0xAABB, cursor = 2 })
step(1)
lB:update(0)
local cmd = lB:take("game3_trade_cmd")
eq(cmd and cmd.cursor, 2, "B received the trade command")
eq(cmd and cmd.seat, 0, "from seat 0")
lA:send({ type = "game3_trade_confirm", digest = "0123456789abcdef" })
lB:send({ type = "game3_trade_confirm", digest = "0123456789abcdef" })
step(2)
lA:update(0)
local commit = lA:take("trade_commit")
check(commit ~= nil, "A receives the relay's trade_commit")
eq(commit and commit.seat, -1, "relay-authored")

print("[test] 4. closing the link keeps the room; leaving it drops the peer's link")
lA:close("done")
step(1)
check(ClientA.room() ~= nil, "A's link closed but A is still seated")
lA:leave()
step(2)
eq(ClientA.room(), nil, "A left the room")
lB:update(0)
lB:update(0)
check(not lB:isOpen(), "B's link closed")
check(lB.reason == "peer_left" or lB.reason == "peer_dropped", "because the peer left")

print("[test] 5. an invite from the launcher lands in the Union Room")
local store = { flags = {}, vars = {} }
session.store = store
session.map = "FR_UNION_ROOM"
local ctx = { specialVars = {}, stringVars = {} }
package.loaded["src.core.game3.runtime"]._game = { data = { maps = {} }, session = session,
  input = { wasPressed = function() return false end }, save = game.save }
local romBundleEarly = require("tests.game3_cache").bundle()
package.loaded["src.core.game3.scripting.space"] = {
  store = store, mapId = "FR_UNION_ROOM", vm = { ctx = ctx, adapters = { log = function() end } },
  ensureBundle = function() return romBundleEarly end,
}
require("src.core.game3.link.union_room")._avatars = require("tests.g3link_fake_relay").avatars()
package.loaded["src.core.game3.objects"] = {
  addObject = function() return true end, removeObject = function() return true end,
  refreshGraphics = function() return 0 end,
}
package.loaded["src.core.game3.player"] = { cellX = 7, cellY = 11, facing = "down" }
package.loaded["src.online.ArenaData"] = {
  liveProfile3 = function(_, rulesetId)
    local p = {}
    for k, v in pairs(PROFILE) do p[k] = v end
    p.rulesetId = rulesetId
    return p
  end,
}
package.loaded["src.online.Client"] = ClientA
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
local Link = require("src.core.game3.link")
local Union = require("src.core.game3.link.union_room")
check(Link.adapterConnected(), "A's adapter reads connected")
Union.run(ctx)
eq(Union.relay, true, "the Union Room runs over the relay")
step()
check(ClientA.plaza() ~= nil, "A is in the union plaza")
seatB.presence.where = "launcher"
ClientB.invite("a0000001", "chat", {}, PROFILE)
step()
Union.update(1 / 60)
Union.pollIncoming()
eq(Union.state, "player_contacted_you", "B's invite reaches the Union Room")
eq(Union._requestName, "BLUE", "from BLUE")
Union.answerRequest(true)
step()
for _ = 1, 3 do
  Link.update(1 / 60)
  step(1)
end
eq(Union.state, "in_activity", "the chat began over the relay")
eq(Link.link, nil, "the chat talks to the room session, no Game3Link handshake")
eq(ClientA.seat(), 1, "the invited player sits in seat 1")
local Chat = require("src.core.game3.link.chat")
check(Chat.isActive(), "chat is live")
local rsB = ClientB.roomSession()
step(1)
local join = rsB:take("game3_union_hello")
eq(join and join.name, "RED", "A announced itself to the chat")
rsB:send({ type = "game3_union_hello", name = "BLUE", gender = 0, trainerId = 2, activity = 0x45 })
rsB:send({ type = "game3_chat_line", name = "BLUE", text = "HI RED" })
step(2)
Link.update(1 / 60)
eq(#Chat.lines, 2, "BLUE joined and spoke")
check(Chat.lines[2] and Chat.lines[2].text:find("HI RED", 1, true) ~= nil, "BLUE's line is in the log")
eq(Chat.lines[2] and Chat.lines[2].seat, 0, "in BLUE's seat colour")
Chat.stop("left")
for _ = 1, 3 do
  Link.update(1 / 60)
  step(1)
end
eq(Union.state, "main", "back in the Union Room")
eq(ClientA.room(), nil, "the private room was left")
local bye = rsB:take("game3_chat_bye")
check(bye ~= nil, "BLUE saw A leave the chat")
Union.stop("test")
step()
eq(ClientA.plaza(), nil, "leaving the Union Room leaves the plaza")

Link.reset()
if failed == 0 then
  print("[pass] link over the Client")
  os.exit(0)
end
print("[fail] link over the Client: " .. failed)
os.exit(1)
