package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
if not _G.love then _G.love = require("tests.love_stub") end

local Cache = require("tests.game3_cache")
if not Cache.mount("meta.json") then
  print("[skip] online_trade_relay3: " .. tostring(Cache.reason))
  os.exit(0)
end

local okR, FakeRelay = pcall(require, "tests.support.fake_relay")
if not okR then
  print("[skip] online_trade_relay3: no tests/support/fake_relay.lua: " .. tostring(FakeRelay))
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")
local SaveData = require("src.core.SaveData")
local Trade = require("src.online.Trade")
local Fingerprint = require("src.link.Fingerprint")
local Pokemon = require("src.core.game3.pokemon")
local Party = require("src.core.game3.party")
local Schema = require("src.core.game3.save_schema_firered")
local RelayTransport = require("src.core.game3.link.relay_transport")
local Version = require("src.core.Version")
Pokemon.install(nil)

local files = {}
SaveData.portableFs = function()
  return {
    getInfo = function(name) return files[name] and { type = "file" } or nil end,
    read = function(name) return files[name] end,
    write = function(name, body) files[name] = body return true end,
    remove = function(name) files[name] = nil return true end,
    createDirectory = function() return true end,
  }
end

local cache = require("src.core.game3.dataset").cache()
local fingerprint = Fingerprint.compute({ generation = 3,
  gen3Inputs = Fingerprint.gen3Inputs(function(rel) return cache:read(rel) end) }, {}, 3)
local PROFILE = { engine = 3, version = "firered", engineVersion = Version.engine,
  apiVersion = Version.modApi, fingerprint = fingerprint, rulesetId = "g3_link",
  kind = "vanilla", rule = {} }

local function newClient(relay, seat)
  package.loaded["src.online.Client"] = nil
  local Client = require("src.online.Client")
  Client.reset()
  Client.configure({ relayAddress = "fake:1", connect = function() return seat.transport end })
  return Client
end

local function makeSave(version, name, trainerId, mons)
  local session = Schema.newGame({ version = version, name = name, rngSeed = trainerId })
  session.trainerId = trainerId
  session.dex.nationalUnlocked = true
  session.party = {}
  for _, row in ipairs(mons) do
    assert(Party.giveMon(session, row.species, row.level))
    local mon = session.party[#session.party]
    for k, v in pairs(row.extra or {}) do mon[k] = v end
  end
  return SaveData.decode(SaveData.encode(Schema.toSaveTable(session)))
end

local DATA = { generation = 3, Pokemon = Pokemon, pokemon = Pokemon }

local function handle(version, slotId, save)
  local path = Trade.slotPath(version, slotId)
  files[path] = SaveData.encode(save)
  return { version = version, generation = 3, slotId = slotId, save = save,
           path = path, party = save.party, data = DATA }
end

local function setup(slot)
  local relay = FakeRelay.new()
  local seatA = relay:seat("a0000001", "RED")
  local seatB = relay:seat("b0000002", "LEAF")
  local B = newClient(relay, seatB)
  local A = newClient(relay, seatA)
  local function step(n)
    for _ = 1, n or 1 do
      relay:pump()
      A.update(0)
      B.update(0)
    end
  end
  A.connect({ name = "RED", profiles = { PROFILE } })
  B.connect({ name = "LEAF", profiles = { PROFILE } })
  step(3)
  A.queueDirect({ activity = "trade", ruleset = "g3_link", auto = true, profile = PROFILE,
    avatar = { name = "RED", trainerId = 1, gender = 0, version = "firered" }, preview = { 64 } })
  step(2)
  B.queueDirect({ activity = "trade", ruleset = "g3_link", auto = true, profile = PROFILE,
    avatar = { name = "LEAF", trainerId = 2, gender = 1, version = "leafgreen" }, preview = { 95 } })
  step(3)
  local hA = handle("firered", slot, makeSave("firered", "RED", 11111, {
    { species = 64, level = 30 }, { species = 25, level = 12 } }))
  local hB = handle("leafgreen", slot, makeSave("leafgreen", "LEAF", 22222, {
    { species = 95, level = 25, extra = { item = 199, heldItem = 199 } }, { species = 1, level = 8 } }))
  local rsA, rsB = A.roomSession(), B.roomSession()
  local remoteA = Trade.remote(hA, rsA, { transport = RelayTransport.new(rsA, { client = A }) })
  local remoteB = Trade.remote(hB, rsB, { transport = RelayTransport.new(rsB, { client = B }) })
  return { relay = relay, A = A, B = B, step = step, rA = remoteA, rB = remoteB,
           hA = hA, hB = hB, diskA = files[hA.path], diskB = files[hB.path] }
end

local function run(s, n, until_)
  for _ = 1, n do
    s.step(1)
    s.rA:update()
    s.rB:update()
    if until_ and until_() then return true end
  end
  return until_ == nil or until_()
end

do
  local s = setup("slot1")
  T.eq(s.A.seat(), 0, "the AUTO pair seats FireRed first")
  T.check(s.rA ~= nil and s.rB ~= nil, "both launchers open a Gen 3 remote trade")
  s.rA:start()
  s.rB:start()
  T.check(run(s, 12, function()
    return s.rA:stage() == "picking" and s.rB:stage() == "picking"
  end), "both reach the trade menu over the real Client rooms")
  s.rA:pick(1)
  s.rB:pick(1)
  T.check(run(s, 8, function()
    return s.rA:stage() == "confirming" and s.rB:stage() == "confirming"
  end), "the leader sets the mons to trade")
  s.rA:confirm(true)
  s.rB:confirm(true)
  T.check(run(s, 12, function()
    return s.rA:stage() == "committed" and s.rB:stage() == "committed"
  end), "the relay barrier commits both sides: " .. tostring(s.rA:stage()) .. "/"
    .. tostring(s.rB:stage()))
  T.eq(SaveData.decode(files[s.hA.path]).party[1].species, 208, "FireRed holds Steelix")
  T.eq(SaveData.decode(files[s.hB.path]).party[1].species, 65, "LeafGreen holds Alakazam")
  s.rA:close()
  s.rB:close()
  s.step(3)
  T.eq(s.A.room(), nil, "closing leaves the room")
end

do
  local s = setup("slot2")
  s.rA:start()
  s.rB:start()
  run(s, 12, function() return s.rA:stage() == "picking" and s.rB:stage() == "picking" end)
  s.rA:pick(1)
  s.rB:pick(1)
  run(s, 8, function() return s.rA:stage() == "confirming" and s.rB:stage() == "confirming" end)
  s.rB:confirm(true)
  s.rA:confirm(true)
  run(s, 12, function() return s.rB:stage() == "commit_wait" end)
  T.eq(s.rB:stage(), "commit_wait", "seat 1 has confirmed its digest")
  T.eq(s.rA:stage(), "exchange", "seat 0 has not sent its digest yet")
  s.A.leaveRoom()
  run(s, 10, function() return s.rB:stage() == "cancelled" end)
  T.eq(s.rB:stage(), "cancelled", "seat 0 leaving before its digest aborts the trade")
  T.eq(s.rA:stage(), "cancelled", "and seat 0's own trade is off")
  T.eq(files[s.hA.path], s.diskA, "nothing written on seat 0")
  T.eq(files[s.hB.path], s.diskB, "nothing written on seat 1")
end

T.finish()
