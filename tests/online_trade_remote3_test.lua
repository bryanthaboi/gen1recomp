package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
if not _G.love then _G.love = require("tests.love_stub") end

local Cache = require("tests.game3_cache")
if not Cache.mount("meta.json") then
  print("[skip] online_trade_remote3: " .. tostring(Cache.reason))
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")
local SaveData = require("src.core.SaveData")
local Trade = require("src.online.Trade")
local Pokemon = require("src.core.game3.pokemon")
local Party = require("src.core.game3.party")
local Schema = require("src.core.game3.save_schema_firered")
local Relay = require("tests.online_trade_fakerelay")
Pokemon.install(nil)
T.check(Pokemon._names ~= nil, "FireRed species tables load from the cache")

local files = {}
local fs = {
  getInfo = function(name) return files[name] and { type = "file" } or nil end,
  read = function(name) return files[name] end,
  write = function(name, body) files[name] = body return true end,
  remove = function(name) files[name] = nil return true end,
  createDirectory = function() return true end,
}
SaveData.portableFs = function() return fs end

local DATA = { generation = 3, Pokemon = Pokemon, pokemon = Pokemon }

local function makeSave(version, name, trainerId, mons)
  local session = Schema.newGame({ version = version, name = name, rngSeed = trainerId })
  session.trainerId = trainerId
  session.dex.nationalUnlocked = true
  session.party = {}
  for _, row in ipairs(mons) do
    assert(Party.giveMon(session, row.species, row.level, row.nickname))
    local mon = session.party[#session.party]
    for k, v in pairs(row.extra or {}) do mon[k] = v end
  end
  return SaveData.decode(SaveData.encode(Schema.toSaveTable(session)))
end

local function handle(version, slotId, save)
  local path = Trade.slotPath(version, slotId)
  files[path] = SaveData.encode(save)
  return {
    version = version, generation = 3, slotId = slotId, save = save,
    path = path, party = save.party, data = DATA,
  }
end

local function onDisk(h)
  return SaveData.decode(files[h.path] or "")
end

local function pair(opts)
  opts = opts or {}
  local fr = makeSave("firered", "RED", 11111, {
    { species = 64, level = 30, nickname = "ABRA CAD" },
    { species = 25, level = 12 },
  })
  local lg = makeSave("leafgreen", "LEAF", 22222, {
    { species = 95, level = 25, extra = { item = 199, heldItem = 199 } },
    { species = 1, level = 8 },
  })
  local relay = Relay.new({ tamper = opts.tamper, rewrite = opts.rewrite })
  local rsA, rsB = relay:join(0, "RED"), relay:join(1, "LEAF")
  local hA = handle("firered", opts.slot or "slot1", fr)
  local hB = handle("leafgreen", opts.slot or "slot1", lg)
  local A = assert(Trade.remote(hA, rsA, { transport = relay:transport(rsA), peerName = "LEAF" }))
  local B = assert(Trade.remote(hB, rsB, { transport = relay:transport(rsB), peerName = "RED" }))
  return { relay = relay, rsA = rsA, rsB = rsB, A = A, B = B, hA = hA, hB = hB,
           diskA = files[hA.path], diskB = files[hB.path] }
end

local function pump(p, n)
  for _ = 1, n or 1 do
    p.A:update()
    p.B:update()
  end
end

local function toConfirming(p)
  p.A:start()
  p.B:start()
  pump(p, 3)
  T.eq(p.A:stage(), "picking", "seat 0 reaches the trade menu")
  T.eq(p.B:stage(), "picking", "seat 1 reaches the trade menu")
  T.eq(#p.A.session.theirParty, 2, "each side unpacked the other's party")
  T.eq(p.A.session.theirParty[1].species, 95, "as real mons")
  T.check(p.A:canPick(1), "a legit pick is allowed")
  T.check(p.A:pick(1), "seat 0 offers its first mon")
  T.check(p.B:pick(1), "seat 1 offers its first mon")
  pump(p, 2)
  T.eq(p.A:stage(), "confirming", "the leader set the mons to trade")
  T.eq(p.B:stage(), "confirming", "the follower heard it")
  T.eq(p.A.session.theirPick, 1, "seat 0 knows what it gets")
  T.eq(p.B.session.theirPick, 1, "seat 1 knows what it gets")
end

do
  local p = pair()
  toConfirming(p)
  p.A:confirm(true)
  p.B:confirm(true)
  pump(p, 1)
  T.eq(p.B:stage(), "commit_wait", "seat 1 sent its digest and waits")
  T.eq(p.A:stage(), "exchange", "seat 0 is still exchanging")
  p.A:update()
  T.eq(p.A:stage(), "commit_wait", "seat 0 sent its digest")
  T.eq(p.relay.commits, 1, "the relay committed once")
  T.eq(files[p.hA.path], p.diskA, "nothing is written before trade_commit reaches seat 0")
  T.eq(files[p.hB.path], p.diskB, "nor seat 1")
  pump(p, 2)
  T.eq(p.A:stage(), "committed", "seat 0 committed")
  T.eq(p.B:stage(), "committed", "seat 1 committed")
  T.eq(p.A:commit(), true, "commit reports the cached result")
  local frNow, lgNow = onDisk(p.hA), onDisk(p.hB)
  T.eq(frNow and frNow.party[1].species, 208, "FireRed's file holds the Onix, now Steelix")
  T.eq(frNow and frNow.party[1].item, 0, "the Metal Coat was used up")
  T.eq(lgNow and lgNow.party[1].species, 65, "LeafGreen's file holds the Kadabra, now Alakazam")
  T.eq(lgNow and lgNow.party[1].nickname, "ABRA CAD", "keeping its nickname")
  T.eq(lgNow and lgNow.party[1].otName, "RED", "and its OT")
  T.eq(frNow and frNow.party[2].species, 25, "untraded mons stay")
  T.check(pcall(Schema.fromSaveTable, frNow), "the FireRed file loads back")
  T.check(pcall(Schema.fromSaveTable, lgNow), "the LeafGreen file loads back")
  pump(p, 1)
  T.check(p.A.peerFinished and p.B.peerFinished, "both sent CONFIRM_FINISH_TRADE after committing")
  p.A:close()
  p.B:close()
  T.check(p.rsA.left and p.rsB.left, "closing leaves the room")
end

do
  local p = pair({ slot = "slot2" })
  toConfirming(p)
  p.A:confirm(true)
  p.B:confirm(true)
  pump(p, 1)
  T.eq(p.B:stage(), "commit_wait", "seat 1 confirmed its digest")
  p.rsA.close()
  pump(p, 2)
  T.eq(p.relay.aborts, 1, "the relay aborts when seat 0 leaves before confirming")
  T.eq(p.B:stage(), "cancelled", "seat 1 calls the trade off")
  T.eq(p.B.session.error, "left", "because the other trainer left")
  T.eq(p.A:stage(), "cancelled", "and seat 0 is out too")
  T.eq(files[p.hA.path], p.diskA, "a drop before commit writes nothing on seat 0")
  T.eq(files[p.hB.path], p.diskB, "or on seat 1")
end

do
  local p = pair({ slot = "slot3" })
  toConfirming(p)
  p.A:confirm(true)
  p.B:confirm(true)
  pump(p, 1)
  p.rsB.online = false
  p.A:update()
  T.eq(p.relay.commits, 1, "both digests reached the relay")
  p.A:update()
  T.eq(p.A:stage(), "committed", "seat 0 commits while seat 1 is dropped")
  for _ = 1, 3 do p.B:update() end
  T.eq(p.B:stage(), "commit_wait", "a reconnecting seat 1 keeps waiting")
  T.eq(files[p.hB.path], p.diskB, "and has written nothing yet")
  p.rsB.online = true
  p.B:update()
  T.eq(p.B:stage(), "committed", "the replayed commit lands after the reconnect")
  T.eq(onDisk(p.hA).party[1].species, 208, "seat 0's file is written")
  T.eq(onDisk(p.hB).party[1].species, 65, "and seat 1's")
end

do
  local p = pair({ slot = "slot4" })
  toConfirming(p)
  p.A:confirm(true)
  p.B:confirm(true)
  pump(p, 1)
  p.A:update()
  p.rsA.close()
  p.B:update()
  T.eq(p.B:stage(), "committed", "a commit already sent survives the other side leaving")
  T.eq(onDisk(p.hB).party[1].species, 65, "so seat 1 is written")
  p.A:update()
  T.eq(p.A:stage(), "committed", "and seat 0, who left after the relay committed, writes too")
  T.eq(onDisk(p.hA).party[1].species, 208, "both files are written")
end

do
  local p = pair({ slot = "slot5", tamper = function(seat, digest)
    if seat == 1 then return ("0"):rep(16) end
    return digest
  end })
  toConfirming(p)
  p.A:confirm(true)
  p.B:confirm(true)
  pump(p, 3)
  T.eq(p.relay.aborts, 1, "mismatched digests abort")
  T.eq(p.A:stage(), "cancelled", "seat 0 cancels")
  T.eq(p.A.session.error, "digest", "naming the digest")
  T.eq(p.B:stage(), "cancelled", "seat 1 cancels")
  T.eq(files[p.hA.path], p.diskA, "nothing written on seat 0")
  T.eq(files[p.hB.path], p.diskB, "nothing written on seat 1")
end

do
  local p = pair({ slot = "slot6" })
  toConfirming(p)
  p.A:confirm(true)
  p.B:confirm(false)
  pump(p, 2)
  T.eq(p.A:stage(), "picking", "a no at the confirm returns both to the menu")
  T.eq(p.B:stage(), "picking", "on both sides")
  T.eq(p.A.session.myPick, nil, "with the picks cleared")
  T.eq(files[p.hA.path], p.diskA, "and nothing written")
  p.relay:_relayed({ type = "trade_abort", n = 9, why = "timeout" })
  pump(p, 1)
  T.eq(p.A:stage(), "picking", "a stale abort from an older barrier is ignored")
end

do
  local p = pair({ slot = "slot7" })
  p.A:start()
  p.B:start()
  pump(p, 3)
  p.relay:deliver(1, { type = "game3_trade_party", party = { { species = 25, level = 5 } },
    name = "EVIL", trainerId = 1, gender = 0, version = 4, progressFlags = 0 })
  p.A:update()
  T.eq(p.A:stage(), "cancelled", "a hostile party is refused whole")
  T.check(p.A.session.error ~= nil, "with a reason: " .. tostring(p.A.session.error))
  T.eq(files[p.hA.path], p.diskA, "and nothing written")
  p.B:update()
  T.eq(p.B:stage(), "cancelled", "the peer is told BOTH_CANCEL_TRADE")
  T.eq(p.B.session.error, "both_canceled", "and exits too")
end

local Protocol = require("src.link.Protocol")

local function repick(p, a, b)
  T.check(p.A:pick(a), "seat 0 picks again")
  T.check(p.B:pick(b), "seat 1 picks again")
  pump(p, 2)
  T.eq(p.A:stage(), "confirming", "the second pick reaches the confirm")
  p.A:confirm(true)
  p.B:confirm(true)
  pump(p, 6)
end

do
  local swap = true
  local p
  p = pair({ slot = "slot8", rewrite = function(from, msg)
    if swap and from == 1 and msg.type == "game3_trade_mon" then
      local out = {}
      for k, v in pairs(msg) do out[k] = v end
      out.mon = Protocol.packMon3(p.hB.party[2])
      return out
    end
  end })
  toConfirming(p)
  p.A:confirm(true)
  p.B:confirm(true)
  pump(p, 1)
  T.eq(p.B:stage(), "commit_wait", "seat 1 confirmed round 1 with the mon it really sent")
  pump(p, 2)
  T.eq(p.A.lastRefusal, "not the POKéMON that was shown",
    "a block that isn't the previewed mon is refused (trade.c:1951 runs on what was shown)")
  T.eq(p.A:stage(), "picking", "seat 0 goes back to the menu")
  T.eq(p.B:stage(), "picking", "seat 1 withdraws from commit_wait")
  T.eq(p.relay.commits, 0, "the relay never committed")
  T.eq(files[p.hA.path], p.diskA, "and nothing is written")
  swap = false
  repick(p, 2, 1)
  T.check(p.relay.dropped >= 1, "the withdrawn side's confirm hit the still-open round")
  T.eq(p.relay.aborts, 1, "which settles as one stale abort")
  T.eq(p.A:stage(), "committed", "the stale round's abort doesn't cancel the second trade")
  T.eq(p.B:stage(), "committed", "on either side")
  T.eq(p.relay.commits, 1, "the relay commits the next round")
  T.eq(onDisk(p.hB).party[1].species, 25, "seat 1 holds the Pikachu it was shown")
  T.eq(onDisk(p.hA).party[2].species, 208, "seat 0 holds the Onix, now Steelix")
end

do
  local p = pair({ slot = "slot9" })
  toConfirming(p)
  p.A:confirm(true)
  p.B:confirm(true)
  pump(p, 1)
  p.B.phase, p.B._staleRound = "commit_wait", 1
  p.B.digest = p.B.digest or ("ab"):rep(8)
  p.relay:_relayed({ type = "trade_abort", n = 2, why = "digest" })
  p.B:update()
  T.eq(p.B:stage(), "cancelled", "an abort past the stale round still cancels")
end

do
  local p = pair({ slot = "slot10" })
  toConfirming(p)
  local realPrepare = Trade.prepare
  Trade.prepare = function(plan)
    if plan.sides[1].handle == p.hB then return false, "that save didn't validate" end
    return realPrepare(plan)
  end
  p.A:confirm(true)
  p.B:confirm(true)
  pump(p, 4)
  Trade.prepare = realPrepare
  T.eq(p.B.lastRefusal, "that save didn't validate", "a save that won't build is caught before the confirm")
  T.eq(p.B:stage(), "picking", "seat 1 backs out to the menu")
  T.eq(p.A:stage(), "picking", "and seat 0 with it")
  T.eq(p.relay.commits, 0, "so the relay never commits")
  T.eq(files[p.hA.path], p.diskA, "and seat 0 writes nothing")
  T.eq(files[p.hB.path], p.diskB, "nor seat 1")
end

do
  local LT = require("src.core.game3.link.trade")
  local p = pair({ slot = "slot11" })
  toConfirming(p)
  p.A:confirm(true)
  p.B:confirm(true)
  pump(p, 1)
  T.eq(p.B:stage(), "commit_wait", "seat 1 confirmed")
  local jPath = Trade.journalPath(p.hB.path)
  local j = files[jPath] and SaveData.decode(files[jPath]) or nil
  local e = j and j.entries and j.entries[#j.entries] or {}
  T.eq(e.room, p.relay.room, "its journal names the relay room")
  T.eq(e.digest, p.B.digest, "and the confirmed digest")
  T.eq(e.sent and e.sent.personality, p.hB.party[1].personality,
    "it holds the packed mon sent, as the in-game resolver reads it")
  T.eq(e.mon and e.mon.species, 64, "and the packed mon received")
  T.eq(e.name, "RED", "with the partner's name for the quest log")
  p.rsB.online = false
  p.A:update()
  p.A:update()
  T.eq(p.A:stage(), "committed", "seat 0 commits")
  p.B:close()
  T.eq(onDisk(p.hB).party[1].species, 95, "seat 1 lost the link before trade_commit")
  local realWith = Trade.withDataset
  Trade.withDataset = function(_, fn)
    local ok, result = pcall(fn, DATA)
    if not ok then return nil, tostring(result) end
    return result
  end
  LT.outcomeClient = p.relay:outcomeClient()
  local done = false
  for _ = 1, 60 do
    if Trade.pumpPending(1000) == true then done = true break end
  end
  LT.outcomeClient = nil
  Trade.withDataset = realWith
  T.check(done, "the next launcher start settles the journal")
  local lgNow = onDisk(p.hB)
  T.eq(lgNow and lgNow.party[1].species, 65, "the Kadabra arrives, now Alakazam")
  T.eq(lgNow and lgNow.party[1].otName, "RED", "keeping its OT")
  T.check(pcall(Schema.fromSaveTable, lgNow), "the LeafGreen file loads back")
  T.eq(files[jPath], nil, "and the journal is gone")
end

T.finish()
