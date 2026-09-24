local U = require("tests.drivers.util")
local H = require("tests.link3_harness")

local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3battle_arena"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS g3battle_arena_loopback")
    love.event.quit(0)
  else
    print("FAIL g3battle_arena_loopback failures=" .. failures)
    love.event.quit(1)
  end
end

local function mon(species, level, moves)
  return H.legal({
    species = species, level = level, moves = moves, personality = 0x51,
    ivs = { hp = 20, atk = 20, def = 20, spe = 20, spa = 20, spd = 20 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }, item = 0,
    nickname = "", friendship = 70,
  })
end

local function profile()
  return { engine = 3, version = "firered", kind = "vanilla", rulesetId = "g3_single", rule = { partySize = 6 } }
end

local function seatMessages(relay, seat)
  local out = {}
  for _, row in ipairs(relay.log) do
    if row.seat == seat then out[#out + 1] = row end
  end
  return out
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local Battle = require("src.core.game3.battle")
  local BattleUi = require("src.core.game3.battle.ui")
  local LB = require("src.core.game3.link.battle")

  local partyA = { mon(6, 50, { 10, 45 }) }
  local partyB = { mon(9, 50, { 33, 39 }) }
  local packedA, packedB = H.pack(partyA), H.pack(partyB)
  local SEED = 0x1D2C3B4A

  local returned
  game.returnToLauncher = function(o) returned = o or {} end

  local function runArena(spec, peerStep, shots)
    returned = nil
    local digests
    local userDone = spec.onDone
    spec.onDone = function(r)
      digests = {}
      for turn, value in pairs(LB._myHashes or {}) do digests[turn] = value end
      if userDone then userDone(r) end
    end
    game:enterArena(spec)
    local taken = {}
    local lastAction = -1
    for _ = 1, 30000 do
      if returned then break end
      if peerStep then peerStep() end
      local st = Battle.getState()
      if Battle.isActive() and st then
        local Message = package.loaded["src.ui.game3.message"]
        local page = (Message and Message.isOpen and Message.isOpen() and Message.isWaiting and Message.isWaiting()
          and tostring(Message.currentPage() or "")) or ""
        page = page:gsub("\n", " ")
        if shots.start and not taken.start and Battle._phase == "command" and BattleUi._mode == "menu" then
          taken.start = true
          U.still(game, DIR .. "/" .. shots.start)
        elseif shots.start and not taken.start and st.spectate and page:find("Go! ", 1, true) then
          taken.start = true
          U.still(game, DIR .. "/" .. shots.start)
        end
        if shots.mid and not taken.mid and (st.turn or 0) >= 2 and page:find(" used ", 1, true) then
          taken.mid = true
          U.still(game, DIR .. "/" .. shots.mid)
        end
        if shots.result and not taken.result and (page:find("lost against", 1, true)
            or page:find("defeated", 1, true) or page:find("draw against", 1, true)) then
          taken.result = true
          U.still(game, DIR .. "/" .. shots.result)
        end
        if not st.spectate and Battle._phase == "command" and (BattleUi._mode == "menu" or BattleUi._mode == "moves")
            and U.frame() - lastAction > 6 then
          lastAction = U.frame()
          U.tap(game, "a")
        else
          U.wait(1)
        end
      else
        U.wait(1)
      end
    end
    return digests, taken
  end

  local relayA = H.relay({ seed = SEED, seats = 2, roomSeed = 1 })
  local peerA = relayA:session(1)
  local sessionA = relayA:session(0)
  local peerSeatSent = false
  local function scriptedPeer()
    for _, msg in ipairs(peerA:poll()) do
      if msg.type == "game3_hello" then
        local hello = LB.copy(msg)
        hello.seat = nil
        hello.name = "LEAF"
        hello.game3.trainerId, hello.game3.gender, hello.game3.seat = 0x2468, 1, 1
        peerA:send(hello)
      elseif msg.type == "game3_battle_linkup" then
        peerA:send({ type = "game3_battle_linkup", linkType = msg.linkType, players = 2 })
      elseif msg.type == "game3_battle_seat" and not peerSeatSent then
        peerSeatSent = true
        peerA:send({ type = "game3_battle_seat" })
      elseif msg.type == "game3_battle_setup" then
        peerA:send({ type = "game3_battle_setup", mode = "single", unionRoom = false, name = "LEAF",
          trainerId = 0x2468, gender = 1, party = packedB })
      elseif msg.type == "game3_battle_action" then
        peerA:send({ type = "game3_battle_action", turn = msg.turn, kind = "move", slot = 1 })
      elseif msg.type == "game3_battle_hash" then
        peerA:send({ type = "game3_battle_hash", turn = msg.turn, value = msg.value, parts = msg.parts })
      elseif msg.type == "game3_battle_outcome" then
        local mirror = ({ [1] = 2, [2] = 1, [3] = 3, [128] = 1 })[msg.outcome] or 3
        peerA:send({ type = "game3_battle_outcome", outcome = mirror, turn = msg.turn })
      end
    end
    relayA:tick()
  end

  local resultA
  local digestsA, shotsA = runArena({
    profile = profile(), role = "host", seat = 0, seats = 2, slotId = nil, seed = SEED, match = "m1",
    room = relayA.room, players = { { id = "00000001", name = "RED", seat = 0 }, { id = "00000002", name = "LEAF", seat = 1 } },
    myParty = packedA, session = sessionA, client = relayA:client(), mode = "single",
    onDone = function(r) resultA = r end,
  }, scriptedPeer, {
    start = "g3battle_arena_seat0_battle_start.png",
    mid = "g3battle_arena_seat0_mid_turn.png",
    result = "g3battle_arena_seat0_result.png",
  })
  result(resultA == "win" or resultA == "lose" or resultA == "draw", "seat 0 arena battle finished (" .. tostring(resultA) .. ")")
  result(returned and returned.tab == "online", "seat 0 returned to the launcher's online tab")
  result(shotsA.start and shotsA.mid and shotsA.result, "seat 0 battle start, mid-turn and result were captured")
  result(game.phase == "arena" and game.arena == nil, "the arena state was torn down")

  local relayB = H.relay({ seed = SEED, seats = 2, roomSeed = 2 })
  local sessionB = relayB:session(1)
  local replay = relayB:session(0)
  for _, row in ipairs(seatMessages(relayA, 0)) do
    if row.msg.type ~= "game3_bye" then replay:send(row.msg) end
  end
  local resultB
  local digestsB, shotsB = runArena({
    profile = profile(), role = "guest", seat = 1, seats = 2, seed = SEED, match = "m2",
    room = relayB.room, players = { { id = "00000001", name = "RED", seat = 0 }, { id = "00000002", name = "LEAF", seat = 1 } },
    myParty = packedB, session = sessionB, client = relayB:client(), mode = "single",
    onDone = function(r) resultB = r end,
  }, function() relayB:tick() end, { result = "g3battle_arena_seat1_result.png" })
  local mirror = { win = "lose", lose = "win", draw = "draw" }
  result(mirror[resultA] == resultB, "seat 1 replaying seat 0's stream finished mirrored (" .. tostring(resultB) .. ")")
  result(shotsB.result, "seat 1 result was captured")
  local same, n = true, 0
  for turn, value in pairs(digestsA or {}) do
    if digestsB and digestsB[turn] then
      n = n + 1
      if digestsB[turn] ~= value then same = false end
    end
  end
  result(same and n >= 1, "every per-turn digest matched between the two seats (" .. n .. " turns)")

  local relayC = H.relay({ seed = SEED, seats = 2, roomSeed = 3 })
  local feed0, feed1 = relayC:session(0), relayC:session(1)
  for _, row in ipairs(seatMessages(relayA, 0)) do
    if row.msg.type ~= "game3_bye" then feed0:send(row.msg) end
  end
  for _, row in ipairs(seatMessages(relayB, 1)) do
    if row.msg.type ~= "game3_bye" then feed1:send(row.msg) end
  end
  local spectator = relayC:session(nil)
  local resultC
  local digestsC, shotsC = runArena({
    profile = profile(), role = "spectator", seats = 2, seed = SEED, match = "m3", room = relayC.room,
    players = { { id = "00000001", name = "RED", seat = 0 }, { id = "00000002", name = "LEAF", seat = 1 } },
    session = spectator, client = relayC:client(), mode = "single",
    onDone = function(r) resultC = r end,
  }, function() relayC:tick() end, {
    start = "g3battle_arena_spectator_battle_start.png",
    result = "g3battle_arena_spectator_result.png",
  })
  result(resultC == "ended", "the spectator watched the whole battle (" .. tostring(resultC) .. ")")
  result(shotsC.start and shotsC.result, "spectator battle start and result were captured")
  local sameC, nC = true, 0
  for turn, value in pairs(digestsA or {}) do
    if digestsC and digestsC[turn] then
      nC = nC + 1
      if digestsC[turn] ~= value then sameC = false end
    end
  end
  result(sameC and nC >= 1, "the spectator's simulation digested the same turns (" .. nC .. ")")
  local sent = false
  for _, row in ipairs(relayC.log) do if row.seat == nil then sent = true end end
  result(not sent, "the spectator never sent a message")
  finish()
end
