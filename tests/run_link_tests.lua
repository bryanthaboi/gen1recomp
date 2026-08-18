-- Link play tests: the loopback transport, the trade session state
-- machine (with a trade evolution), and a lockstep link battle driven
-- over the loopback.  Runs headlessly under plain luajit:
--   luajit tests/run_link_tests.lua
-- Real networking uses lua-enet (bundled with LÖVE); when enet is
-- importable (inside LÖVE) an actual host/join pairing over UDP
-- localhost is exercised too, otherwise that section is skipped.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
math.randomseed(4242)

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

local Data = require("src.core.Data")
Data:load()
local Pokemon = require("src.pokemon.Pokemon")
local Protocol = require("src.link.Protocol")

-- ---------------------------------------------------------------- json
local Json = require("src.link.Json")
local msg = { type = "party", n = 3, ok = true, list = { 1, 2, 3 },
              name = "RED\"s" }
local rt = Json.decode(Json.encode(msg))
eq(rt.type, "party", "json round trip type")
eq(rt.n, 3, "json round trip number")
eq(#rt.list, 3, "json round trip array")
eq(rt.name, 'RED"s', "json round trip escaping")

-- ---------------------------------------------------------------- pack/unpack
local kadabra = Pokemon.new(Data, "KADABRA", 30)
local packed = Protocol.packMon(kadabra)
local unpacked = Protocol.unpackMon(Data, packed)
eq(unpacked.species, "KADABRA", "mon survives the wire")
eq(unpacked.level, 30, "level survives")
eq(unpacked.stats.hp, kadabra.stats.hp, "stats recomputed identically")
-- tampering is clamped
packed.level = 3000
packed.dvs.attack = 99
local clamped = Protocol.unpackMon(Data, packed)
eq(clamped.level, 100, "tampered level clamped")
eq(clamped.dvs.attack, 15, "tampered DV clamped")

-- OT identity survives the wire (#215): pokered's trade sends each mon's OT
-- ID (party_struct MON_OTID) and OT name (wPartyMonOT); the receiver keeps
-- them verbatim so a traded mon shows its original trainer, not the receiver.
local otMon = Pokemon.new(Data, "KADABRA", 30)
otMon.ot = "CULLEN"
otMon.otId = 16012
local otRt = Protocol.unpackMon(Data, Protocol.packMon(otMon))
eq(otRt.ot, "CULLEN", "OT name survives the wire")
eq(otRt.otId, 16012, "OT ID survives the wire")
-- a tampered OT ID is clamped into the 16-bit range like every other field
local otPack = Protocol.packMon(otMon)
otPack.otId = 999999
eq(Protocol.unpackMon(Data, otPack).otId, 65535, "over-range OT ID clamped")
otPack.otId = -5
eq(Protocol.unpackMon(Data, otPack).otId, 0, "under-range OT ID clamped")
-- an old peer that never sends OT leaves it nil (no worse than legacy; the
-- load-time stampOT backfill then fills the receiver's own, as before)
local legacy = Protocol.packMon(Pokemon.new(Data, "PIDGEY", 10))
check(Protocol.unpackMon(Data, legacy).ot == nil, "missing OT stays nil (legacy peer)")

-- ---------------------------------------------------------------- transport
local Net = require("src.link.Net")

-- loopback pair: the offline transport the tests (and headless luajit,
-- which has no enet) run the protocol over
local lbA, lbB = Net.loopbackPair()
check(lbA.paired and lbB.paired, "loopback pair starts paired")
lbA:send({ type = "hello", name = "RED", mode = "trade" })
lbB:send({ type = "hello", name = "BLUE", mode = "trade" })
lbA:update()
lbB:update()
local gotA, gotB = lbA:poll()[1], lbB:poll()[1]
eq(gotA and gotA.name, "BLUE", "loopback A received B's hello")
eq(gotB and gotB.name, "RED", "loopback B received A's hello")
check(#lbA:poll() == 0, "poll drains the inbox")
lbB:close()
lbB:send({ type = "bye" })
lbA:update()
check(#lbA:poll() == 0, "a closed end sends nothing")

-- real enet pairing over UDP localhost (only when lua-enet is present,
-- i.e. inside LÖVE; plain luajit skips this section)
if Net.available() then
  local host = Net.new()
  check(host:host(7807), "host opens a UDP port")
  check(host.address ~= nil and host.address:match(":7807$") ~= nil,
        "host advertises an address: " .. tostring(host.address))
  local guest = Net.new()
  check(guest:join("127.0.0.1:7807"), "guest dials the address")
  local spins = 0
  while not (host.paired and guest.paired) and spins < 500000 do
    host:update()
    guest:update()
    spins = spins + 1
  end
  check(host.paired and guest.paired, "both sides paired over enet")

  host:send({ type = "hello", name = "RED", mode = "trade" })
  guest:send({ type = "hello", name = "BLUE", mode = "trade" })
  local got = { host = nil, guest = nil }
  spins = 0
  while (not got.host or not got.guest) and spins < 500000 do
    host:update()
    guest:update()
    for _, m in ipairs(host:poll()) do got.host = m end
    for _, m in ipairs(guest:poll()) do got.guest = m end
    spins = spins + 1
  end
  eq(got.host and got.host.name, "BLUE", "host received guest hello")
  eq(got.guest and got.guest.name, "RED", "guest received host hello")

  -- disconnect is noticed
  guest:close()
  spins = 0
  while not host.closed and spins < 500000 do
    host:update()
    spins = spins + 1
  end
  check(host.closed, "host notices the guest leaving")
  host:close()

  -- joining a dead address errors out (short timeout for the test)
  local reject = Net.new()
  reject.joinTimeout = 0.5
  reject:join("127.0.0.1:7809")
  local t0 = os.clock()
  while not reject.error and os.clock() - t0 < 30 do
    reject:update()
  end
  check(reject.error ~= nil, "unanswered join reports an error")
  reject:close()
else
  print("skip real enet pairing (lua-enet not available under this interpreter)")
end

-- ---------------------------------------------------------------- relay (TCP) transport
-- Pure framing logic needs no socket at all: Net:drainLines()/handleTCPLine
-- operate directly on rxBuf, so this much runs even under plain luajit.
do
  local n = Net.new()
  local encoded = Json.encode({ type = "hosted", code = "ABCDEF" })
  n.rxBuf = encoded .. "\n"
  n:drainLines()
  eq(n.code, "ABCDEF", "relay framing: a complete hosted line sets net.code")
  check(n.rxBuf == "", "relay framing: a complete line is fully consumed")

  local n2 = Net.new()
  n2.rxBuf = encoded:sub(1, 5) -- the line straddles two reads
  n2:drainLines()
  check(n2.code == nil, "relay framing: a partial line doesn't parse yet")
  n2.rxBuf = n2.rxBuf .. encoded:sub(6) .. "\n"
  n2:drainLines()
  eq(n2.code, "ABCDEF", "relay framing: completing the line resolves it")

  local n3 = Net.new()
  n3.rxBuf = Json.encode({ type = "join_error", reason = "not_found" }) .. "\n"
  n3:drainLines()
  check(n3.error ~= nil and n3.closed, "relay framing: join_error sets error and closes")

  local n4 = Net.new()
  n4.rxBuf = Json.encode({ type = "paired" }) .. "\n"
  n4:drainLines()
  check(n4.paired, "relay framing: paired flips net.paired")

  local n5 = Net.new()
  n5.paired = true
  n5.rxBuf = Json.encode({ type = "peer_gone" }) .. "\n"
  n5:drainLines()
  check(n5.closed, "relay framing: peer_gone closes the connection")

  local n6 = Net.new()
  n6.rxBuf = Json.encode({ type = "hello", name = "RED" }) .. "\n"
  n6:drainLines()
  eq(#n6.inbox, 1, "relay framing: an unrecognized control type lands in the inbox")
  eq(n6.inbox[1] and n6.inbox[1].name, "RED", "relay framing: ...with its payload intact")
end

-- real pokeserver over TCP localhost (only when luasocket is present, i.e.
-- inside LOVE or a luajit with luasocket installed, AND node is on PATH to
-- spawn the real relay; otherwise this section is skipped, same spirit as
-- the enet gate above)
local hasSocket = pcall(require, "socket")
local nodeCheck = os.execute("command -v node >/dev/null 2>&1")
local hasNode = nodeCheck == true or nodeCheck == 0
if not hasSocket then
  print("skip real relay pairing (luasocket not available under this interpreter)")
elseif not hasNode then
  print("skip real relay pairing (node not on PATH to spawn pokeserver)")
else
  local PORT = 17778
  local pidFile = os.tmpname()
  os.execute(("(cd ../pokeserver && PORT=%d HTTP_PORT=%d node server.js >/tmp/pokeserver_test.log 2>&1 & echo $! > %q)")
             :format(PORT, PORT + 1, pidFile))

  local function busyWait(seconds)
    local t0 = os.clock()
    while os.clock() - t0 < seconds do end
  end

  local function tcpConnectable(host, port)
    local socket = require("socket")
    local tcp = socket.tcp()
    tcp:settimeout(0.2)
    local ok = tcp:connect(host, port)
    tcp:close()
    return ok ~= nil
  end

  local ready = false
  for _ = 1, 50 do
    ready = tcpConnectable("127.0.0.1", PORT)
    if ready then break end
    busyWait(0.1)
  end

  if not ready then
    print("skip real relay pairing (couldn't reach the spawned pokeserver)")
  else
    local host = Net.new()
    check(host:hostOnline("127.0.0.1:" .. PORT), "relay: hostOnline connects: " .. tostring(host.error))
    local deadline = os.clock() + 3
    while not host.code and os.clock() < deadline do host:update() end
    check(host.code ~= nil, "relay: a real server assigns a room code")

    local guest = Net.new()
    check(guest:joinOnline("127.0.0.1:" .. PORT, host.code or ""),
          "relay: joinOnline connects: " .. tostring(guest.error))
    deadline = os.clock() + 3
    while (not host.paired or not guest.paired) and os.clock() < deadline do
      host:update()
      guest:update()
    end
    check(host.paired and guest.paired, "relay: both sides pair over a real TCP server")

    host:send({ type = "hello", name = "RED" })
    local relayed = nil
    deadline = os.clock() + 3
    while not relayed and os.clock() < deadline do
      host:update()
      guest:update()
      for _, m in ipairs(guest:poll()) do
        if m.type == "hello" then relayed = m end
      end
    end
    eq(relayed and relayed.name, "RED", "relay: a message round-trips through the real server")

    host:close()
    guest:close()
  end

  local pidHandle = io.open(pidFile, "r")
  if pidHandle then
    local pid = pidHandle:read("*l")
    pidHandle:close()
    if pid and pid ~= "" then os.execute("kill " .. pid .. " >/dev/null 2>&1") end
  end
  os.remove(pidFile)
end

-- ---------------------------------------------------------------- trade session
local partyA = { Pokemon.new(Data, "KADABRA", 30), Pokemon.new(Data, "PIDGEY", 10) }
local partyB = { Pokemon.new(Data, "MACHOKE", 32) }
-- distinct original trainers so a preserved OT is unmistakable after the swap
-- (#215): A's KADABRA belongs to CULLEN/16012, B's MACHOKE to RED/60368
partyA[1].ot = "CULLEN"; partyA[1].otId = 16012
partyB[1].ot = "RED"; partyB[1].otId = 60368
local tA = Protocol.TradeSession.new(Data, partyA)
local tB = Protocol.TradeSession.new(Data, partyB)
tA:handle({ type = "party", mons = Protocol.packParty(partyB) })
tB:handle({ type = "party", mons = Protocol.packParty(partyA) })
eq(tA.stage, "picking", "trade session enters picking")
local pickA = tA:pick(1) -- gives KADABRA
local pickB = tB:pick(1) -- gives MACHOKE
tA:handle(pickB)
tB:handle(pickA)
eq(tA.stage, "confirming", "both picks -> confirming")
local cA = tA:confirm(true)
local cB = tB:confirm(true)
tA:handle(cB)
tB:handle(cA)
eq(tA.stage, "done", "trade completes")
local gotMon, evoTo = tA:apply(nil)
eq(gotMon.species, "MACHOKE", "A received Machoke")
eq(evoTo, "MACHAMP", "trade evolution triggers (Machoke -> Machamp)")
-- the received mon keeps its SENDER's OT, not the receiver's (#215)
eq(gotMon.ot, "RED", "A's received Machoke keeps sender B's OT name")
eq(gotMon.otId, 60368, "A's received Machoke keeps sender B's OT ID")
local gotMon2, evoTo2 = tB:apply(nil)
eq(gotMon2.species, "KADABRA", "B received Kadabra")
eq(evoTo2, "ALAKAZAM", "Kadabra -> Alakazam on trade")
eq(gotMon2.ot, "CULLEN", "B's received Kadabra keeps sender A's OT name")
eq(gotMon2.otId, 16012, "B's received Kadabra keeps sender A's OT ID")

-- declined trades cancel
local tC = Protocol.TradeSession.new(Data, partyA)
tC:handle({ type = "party", mons = Protocol.packParty(partyB) })
tC:pick(1)
tC:handle({ type = "pick", index = 1 })
tC:confirm(true)
tC:handle({ type = "confirm", ok = false })
eq(tC.stage, "cancelled", "declined trade cancels")

-- ---------------------------------------------------------------- link battle (lockstep)
-- Both sides run the full engine locally on a shared seed; this drives
-- two simulations over a loopback and checks they agree.
local Input = require("src.core.Input")
Input:init()
require("src.render.Font").load(Data)

local function makeFakeGame(leadSpecies)
  local save = require("src.core.SaveData").newGame()
  table.insert(save.party, Pokemon.new(Data, leadSpecies, 50))
  local stack = { list = {} }
  function stack:push(s, ...)
    table.insert(self.list, s)
    if s.enter then s:enter(...) end
  end
  function stack:pop() table.remove(self.list) end
  function stack:top() return self.list[#self.list] end
  function stack:update(dt)
    local t = self:top()
    if t and t.update then t:update(dt) end
  end
  return { data = Data, input = Input, stack = stack, save = save }
end

local LinkBattle = require("src.link.LinkBattle")
local gameA = makeFakeGame("CHARIZARD")
local gameB = makeFakeGame("BLASTOISE")
gameB.save.player.name = "BLUE"
-- each side's send lands in the other's inbox (json re-encoded like
-- the real wire) through Net's own loopback transport
local netA, netB = Net.loopbackPair()

local packedA = Protocol.packParty(gameA.save.party)
local packedB = Protocol.packParty(gameB.save.party)
local seed = 987654321

local battleA = LinkBattle.newHost(gameA, netA, {
  myParty = packedA, theirParty = packedB, theirName = "BLUE", seed = seed,
})
local battleB = LinkBattle.newGuest(gameB, netB, {
  myParty = packedB, theirParty = packedA, theirName = "RED", seed = seed,
})
local resA, resB = nil, nil
battleA.onFinish = function(r) resA = r end
battleB.onFinish = function(r) resB = r end
gameA.stack:push(battleA)
gameB.stack:push(battleB)
eq(battleA.kind, "link", "host battle is a link battle")
eq(battleA.enemy.mon.species, "BLASTOISE", "guest party became the host's enemy side")
eq(battleB.enemy.mon.species, "CHARIZARD", "host party became the guest's enemy side")

-- drive both sides with mashed A (FIGHT -> first move) until done
local guard = 0
while (resA == nil or resB == nil) and guard < 60000 do
  guard = guard + 1
  Input.pressed = { a = true }
  gameA.stack:update(1 / 60)
  gameB.stack:update(1 / 60)
end
check(resA ~= nil and resB ~= nil,
      ("lockstep battle completes on both sides (%s / %s)"):format(
        tostring(resA), tostring(resB)))
check((resA == "win" and resB == "lose") or (resA == "lose" and resB == "win")
      or (resA == "draw" and resB == "draw"),
      "the two simulations agree on the outcome")
-- mirrored final state: my mon's HP on A equals A's mon HP as seen by B
eq(battleA.player.mon.hp, battleB.enemy.mon.hp, "host mon HP identical on both sides")
eq(battleA.enemy.mon.hp, battleB.player.mon.hp, "guest mon HP identical on both sides")
local leftoverMismatch = false
for turn, h in pairs(battleA.localHashes) do
  if battleB.localHashes[turn] and battleB.localHashes[turn] ~= h then
    leftoverMismatch = true
  end
end
check(not leftoverMismatch, "no desync detected across the whole battle")
eq(gameA.save.money, 3000, "no prize money in link battles")
eq(gameA.save.party[1].hp, gameA.save.party[1].stats.hp,
   "the real party is untouched (battle used clamped copies)")

-- ---------------------------------------------------------------- forced-level ("auto 50") matches
-- online matches/tournaments may force every participant's real level to a
-- fixed value for the match (opts.forceLevel), regardless of their save's
-- actual level -- this checks both sides normalize identically and stats
-- recompute for the forced level rather than clamping the original level's
local gameG = makeFakeGame("PIKACHU")
gameG.save.party[1] = Pokemon.new(Data, "PIKACHU", 12)
local gameH = makeFakeGame("GEODUDE")
gameH.save.party[1] = Pokemon.new(Data, "GEODUDE", 100)
gameH.save.player.name = "BLUE"
local netG, netH = Net.loopbackPair()
local packedG = Protocol.packParty(gameG.save.party)
local packedH = Protocol.packParty(gameH.save.party)
local seedGH = 13579

local battleG = LinkBattle.newHost(gameG, netG, {
  myParty = packedG, theirParty = packedH, theirName = "BLUE", seed = seedGH,
  forceLevel = 50,
})
local battleH = LinkBattle.newGuest(gameH, netH, {
  myParty = packedH, theirParty = packedG, theirName = "RED", seed = seedGH,
  forceLevel = 50,
})
eq(battleG.player.mon.level, 50, "forced level overrides a low real level (12 -> 50)")
eq(battleG.enemy.mon.level, 50, "...and a high real level (100 -> 50) the same way")
eq(battleH.player.mon.level, 50, "the guest's own mon is forced too")
eq(battleH.enemy.mon.level, 50, "the guest sees the host's mon forced too")
local expectedStats = require("src.pokemon.Stats").calc(
  Data.pokemon["PIKACHU"], 50, battleG.player.mon.dvs, battleG.player.mon.statExp)
eq(battleG.player.mon.stats.hp, expectedStats.hp,
   "forced-level stats are recomputed for level 50, not clamped from level 12")
eq(gameG.save.party[1].level, 12, "the real save data keeps its actual level")
eq(gameH.save.party[1].level, 100, "...on both sides")

-- ---------------------------------------------------------------- "ANY" level ruling (#204)
-- The link "level ruling" picker cycles a string sentinel "ANY" meaning
-- "use each mon's real level" (Gen1 link cable always used the real level).
-- LinkState/Tournament.levelForWire turns that sentinel into nil on the wire;
-- a broken `x and nil or y` idiom used to let the literal "ANY" through into
-- opts.forceLevel, and Protocol.unpackMon then called math.floor("ANY") ->
-- "bad argument #1 to 'floor' (number expected, got string)", crashing the
-- host the instant parties were unpacked in newHost (see the #204 report's
-- traceback: unpackMon <- unpackParty <- newHost <- LinkState.update).
-- unpackMon now coerces forceLevel with tonumber, so any non-numeric level
-- string means "no forced level" and the mon keeps its packed real level.
local anyPk = Protocol.packMon(Pokemon.new(Data, "PIKACHU", 12))
local okAny, monAny = pcall(Protocol.unpackMon, Data, anyPk, { forceLevel = "ANY" })
check(okAny, "unpackMon does not crash on the ANY sentinel string")
eq(okAny and monAny and monAny.level, 12, "ANY forceLevel keeps the mon's real level (12)")
local okStr, monStr = pcall(Protocol.unpackMon, Data, anyPk, { forceLevel = "50" })
eq(okStr and monStr and monStr.level, 50, "a numeric-string forceLevel is still honored (50)")
local okNil, monNil = pcall(Protocol.unpackMon, Data, anyPk, { forceLevel = nil })
eq(okNil and monNil and monNil.level, 12, "no forceLevel keeps the real level (12)")

-- end-to-end host path from the crash report: newHost -> unpackParty ->
-- unpackMon, with the exact bad value the bug emitted (forceLevel = "ANY").
local gameI = makeFakeGame("PIKACHU")
gameI.save.party[1] = Pokemon.new(Data, "PIKACHU", 12)
local gameJ = makeFakeGame("GEODUDE")
gameJ.save.party[1] = Pokemon.new(Data, "GEODUDE", 100)
gameJ.save.player.name = "BLUE"
local netI, netJ = Net.loopbackPair()
local packedI = Protocol.packParty(gameI.save.party)
local packedJ = Protocol.packParty(gameJ.save.party)
local seedIJ = 24680
local okHost, battleI = pcall(LinkBattle.newHost, gameI, netI, {
  myParty = packedI, theirParty = packedJ, theirName = "BLUE", seed = seedIJ,
  forceLevel = "ANY",
})
local okGuest, battleJ = pcall(LinkBattle.newGuest, gameJ, netJ, {
  myParty = packedJ, theirParty = packedI, theirName = "RED", seed = seedIJ,
  forceLevel = "ANY",
})
check(okHost and battleI ~= nil, "newHost does not crash with the ANY ruling")
check(okGuest and battleJ ~= nil, "newGuest does not crash with the ANY ruling")
eq(okHost and battleI and battleI.player.mon.level, 12,
   "ANY ruling: the host keeps its mon's real level (12, not forced)")
eq(okHost and battleI and battleI.enemy.mon.level, 100,
   "ANY ruling: the enemy mon keeps its real level (100, not forced)")

-- ---------------------------------------------------------------- tournament shot clock
-- opts.turnLimit only applies to tournament matches; the guest mashes
-- through its own menu every frame while the host never presses anything,
-- so the host's clock is the only one that can expire.
local gameC = makeFakeGame("PIKACHU")
local gameD = makeFakeGame("SNORLAX")
gameD.save.player.name = "YELLOW"
local netC, netD = Net.loopbackPair()
local packedC = Protocol.packParty(gameC.save.party)
local packedD = Protocol.packParty(gameD.save.party)
local battleC = LinkBattle.newHost(gameC, netC, {
  myParty = packedC, theirParty = packedD, theirName = "YELLOW", seed = 42,
  turnLimit = 0.05,
})
local battleD = LinkBattle.newGuest(gameD, netD, {
  myParty = packedD, theirParty = packedC, theirName = "RED", seed = 42,
  turnLimit = 0.05,
})
local resC, resD = nil, nil
battleC.onFinish = function(r) resC = r end
battleD.onFinish = function(r) resD = r end
gameC.stack:push(battleC)
gameD.stack:push(battleD)

-- both sides need "a" to get through the intro's messages/animations
-- (send-out poofs, cries...) before the host's own menu even shows; only
-- once the host's decision point is actually up does withholding input
-- from it mean anything
local guardIntro = 0
while battleC.phase ~= "menu" and guardIntro < 6000 do
  guardIntro = guardIntro + 1
  Input.pressed = { a = true }
  gameC.stack:update(1 / 60)
  gameD.stack:update(1 / 60)
end
check(battleC.phase == "menu", "shot clock: host reaches its own decision point")

local guard2 = 0
while resD == nil and guard2 < 6000 do
  guard2 = guard2 + 1
  Input.pressed = { a = true }
  gameD.stack:update(1 / 60) -- guest mashes through its menu
  Input.pressed = {}
  gameC.stack:update(1 / 60) -- host presses nothing; its clock ticks down
end
check(resD == "win", "shot clock: the timed-out player's opponent wins immediately")

-- the timed-out host still has to dismiss its own "time's up" message to
-- reach finish() -- exactly like a slow-but-present player would; this
-- isn't the clock's business, just the ordinary message queue
local guard3 = 0
while resC == nil and guard3 < 6000 do
  guard3 = guard3 + 1
  Input.pressed = { a = true }
  gameC.stack:update(1 / 60)
end
check(resC == "lose", "shot clock: the timed-out host is recorded as the loser")

-- ---------------------------------------------------------------- tournament spectator replay
-- A spectator (LinkBattle.newSpectator) reconstructs the same lockstep
-- battle from a copy of the wire traffic tagged by side -- exactly what
-- pokeserver's tournament fan-out gives it. Feed it directly here rather
-- than standing up a real relay: wrap the host/guest loopback sends so
-- every message they exchange also lands, tagged, in a fake spectator net.
local gameE = makeFakeGame("CHARIZARD")
local gameF = makeFakeGame("BLASTOISE")
gameF.save.player.name = "BLUE"
local gameSpec = makeFakeGame("RATTATA")
local netE, netF = Net.loopbackPair()
local packedE = Protocol.packParty(gameE.save.party)
local packedF = Protocol.packParty(gameF.save.party)
local specSeed = 13579

local specInbox = {}
local origSendE, origSendF = netE.send, netF.send
netE.send = function(self, msg)
  origSendE(self, msg)
  table.insert(specInbox, { type = "spectate", side = "host", msg = msg })
end
netF.send = function(self, msg)
  origSendF(self, msg)
  table.insert(specInbox, { type = "spectate", side = "guest", msg = msg })
end
local specNet = {
  closed = false,
  update = function() end,
  poll = function()
    local msgs = specInbox
    specInbox = {}
    return msgs
  end,
}

local battleE = LinkBattle.newHost(gameE, netE, {
  myParty = packedE, theirParty = packedF, theirName = "BLUE", seed = specSeed,
})
local battleF = LinkBattle.newGuest(gameF, netF, {
  myParty = packedF, theirParty = packedE, theirName = "RED", seed = specSeed,
})
local battleSpec = LinkBattle.newSpectator(gameSpec, specNet, {
  hostParty = packedE, guestParty = packedF, hostName = "RED", guestName = "BLUE",
  seed = specSeed,
})
check(battleSpec ~= nil, "spectator battle constructs")
eq(battleSpec.spectating, true, "spectator battle is marked as such (not a reportable match)")

local resE, resF = nil, nil
battleE.onFinish = function(r) resE = r end
battleF.onFinish = function(r) resF = r end
gameE.stack:push(battleE)
gameF.stack:push(battleF)
gameSpec.stack:push(battleSpec)

local guard3 = 0
while (resE == nil or resF == nil) and guard3 < 60000 do
  guard3 = guard3 + 1
  Input.pressed = { a = true }
  gameE.stack:update(1 / 60)
  gameF.stack:update(1 / 60)
  gameSpec.stack:update(1 / 60)
end
check(resE ~= nil and resF ~= nil, "spectator test: the underlying match completes")
eq(battleSpec.player.mon.hp, battleE.player.mon.hp,
   "spectator's host-side HP matches the host's own view")
eq(battleSpec.enemy.mon.hp, battleF.player.mon.hp,
   "spectator's guest-side HP matches the guest's own view")

-- ---------------------------------------------------------------- fx clock
-- A link battle skips BattleState:update on two hot paths -- waiting for the
-- peer's action, and draining a resolved turn -- and the presentational
-- clock (BGP flash sequences, pic slide/hide programs, the send-out grow-in)
-- only advances inside it.  Frozen, a flash stopped on its inverted BGP step
-- and repainted the UI in inverted shades, and a pic caught mid-slide stayed
-- off screen, both for as long as the opponent took to choose.  These assert
-- the clock keeps running on every path a link battle can sit in.
local fxGame = makeFakeGame("CHARIZARD")
local fxNetA = select(1, Net.loopbackPair())
local fxBattle = LinkBattle.newHost(fxGame, fxNetA, {
  myParty = Protocol.packParty(fxGame.save.party),
  theirParty = Protocol.packParty(makeFakeGame("BLASTOISE").save.party),
  theirName = "BLUE", seed = 99 })
fxGame.stack:push(fxBattle)

local function fxAdvances(phase, afterQueue)
  fxBattle.phase = phase
  fxBattle.afterQueue = afterQueue
  -- a three-step flash sequence, exactly as an SE_* flash row starts one
  fxBattle.fx = fxBattle.fx or {}
  fxBattle.fx.bgpSeq = { steps = { { map = {}, frames = 2 },
                                   { map = {}, frames = 2 },
                                   { map = {}, frames = 2 } },
                         idx = 1, left = 2 }
  local startFrame = fxBattle.frame
  for _ = 1, 4 do fxBattle:update(1 / 60) end
  local seq = fxBattle.fx.bgpSeq
  return fxBattle.frame > startFrame and (seq == nil or seq.idx > 1)
end

check(fxAdvances("waitRemote", nil),
      "the fx clock keeps running while waiting for the peer's action")
check(fxAdvances("messages", "linkNext"),
      "the fx clock keeps running while a resolved turn drains")

-- ---------------------------------------------------------------- desync fuzz
-- The lockstep battle above holds A through one Charizard/Blastoise duel,
-- which is one path.  This walks the rest -- random parties, switches,
-- faints, locked actions -- with the two sides deliberately configured as
-- DIFFERENT clients (options, game speed, relay lag), which is the shape
-- every desync players reported actually had.
local fuzzOk, fuzzErr = pcall(dofile, "tests/link_desync_fuzz.lua")
check(fuzzOk, "lockstep desync fuzz" .. (fuzzOk and "" or (": " .. tostring(fuzzErr))))

-- ---------------------------------------------------------------- hostile wire
-- Every message type crossed with every wrong Lua type, through the real
-- Session choke point and into the real consumers.  The regression net for
-- the remote-crash payloads; self-contained like the fuzz above.
local hostileOk, hostileErr = pcall(dofile, "tests/link_hostile.lua")
check(hostileOk, "hostile wire suite"
      .. (hostileOk and "" or (": " .. tostring(hostileErr))))

-- ---------------------------------------------------------------- mod link compat
-- Self-contained like the tests/mod_*.lua suites: own bootstrap and
-- assert-based checks, so it lands here as a single pass/fail line.
local modOk, modErr = pcall(dofile, "tests/mod_link_tests.lua")
check(modOk, "mod link compat suite" .. (modOk and "" or (": " .. tostring(modErr))))

print(("\n%s"):format(failures == 0 and "ALL LINK TESTS PASSED" or failures .. " FAILURES"))
os.exit(failures == 0 and 0 or 1)
