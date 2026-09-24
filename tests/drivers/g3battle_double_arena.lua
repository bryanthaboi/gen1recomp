local U = require("tests.drivers.util")
local H = require("tests.link3_harness")

local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3battle_double"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS g3battle_double_arena")
    love.event.quit(0)
  else
    print("FAIL g3battle_double_arena failures=" .. failures)
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
  return { engine = 3, version = "firered", kind = "vanilla", rulesetId = "g3_double", rule = { partySize = 6 } }
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  local Battle = require("src.core.game3.battle")
  local BattleUi = require("src.core.game3.battle.ui")
  local State = require("src.core.game3.battle.state")
  local LB = require("src.core.game3.link.battle")

  local partyA = { mon(6, 50, { 52, 10 }), mon(25, 50, { 84, 98 }) }
  local partyB = { mon(9, 50, { 55, 33 }), mon(3, 50, { 22, 33 }) }
  local packedB = H.pack(partyB)
  local SEED = 0x2B2B4C4C

  local returned
  game.returnToLauncher = function(o) returned = o or {} end

  local relay = H.relay({ seed = SEED, seats = 2, roomSeed = 7 })
  local peer = relay:session(1)
  local session = relay:session(0)
  local peerSeatSent, outcomeSent = false, false
  local answered = {}
  local function peerAction(st, id)
    local b = State.battler(st, id)
    local slot = 1
    if b and b.mon then
      for i = 1, 4 do
        if b.mon.moves[i] and (tonumber(b.mon.pp and b.mon.pp[i]) or 0) > 0 then slot = i break end
      end
    end
    local target = State.isPresent(st, 0) and 1 or 3
    return { kind = "move", slot = slot, target = target }
  end
  local function scriptedPeer()
    for _, msg in ipairs(peer:poll()) do
      if msg.type == "game3_hello" then
        local hello = LB.copy(msg)
        hello.seat = nil
        hello.name = "LEAF"
        hello.game3.trainerId, hello.game3.gender, hello.game3.seat = 0x2468, 1, 1
        peer:send(hello)
      elseif msg.type == "game3_battle_linkup" then
        peer:send({ type = "game3_battle_linkup", linkType = msg.linkType, players = 2 })
      elseif msg.type == "game3_battle_seat" and not peerSeatSent then
        peerSeatSent = true
        peer:send({ type = "game3_battle_seat" })
      elseif msg.type == "game3_battle_setup" then
        peer:send({ type = "game3_battle_setup", mode = "double", unionRoom = false, name = "LEAF",
          trainerId = 0x2468, gender = 1, party = packedB })
      elseif msg.type == "game3_battle_action" and not answered[msg.turn] then
        answered[msg.turn] = true
        local st = Battle.getState()
        peer:send({ type = "game3_battle_action", turn = msg.turn, kind = "list",
          actions = { peerAction(st, 1), peerAction(st, 3) } })
      elseif msg.type == "game3_battle_hash" then
        peer:send({ type = "game3_battle_hash", turn = msg.turn, value = msg.value, parts = msg.parts })
      elseif msg.type == "game3_battle_outcome" and not outcomeSent then
        outcomeSent = true
        local mirror = ({ [1] = 2, [2] = 1, [3] = 3, [128] = 1 })[msg.outcome] or 3
        peer:send({ type = "game3_battle_outcome", outcome = mirror, turn = msg.turn })
      end
    end
    relay:tick()
  end

  local outcome, sawDouble
  game:enterArena({
    profile = profile(), role = "host", seat = 0, seats = 2, seed = SEED, match = "md",
    room = relay.room, players = { { id = "00000001", name = "RED", seat = 0 }, { id = "00000002", name = "LEAF", seat = 1 } },
    myParty = H.pack(partyA), session = session, client = relay:client(), mode = "double",
    onDone = function(r) outcome = r end,
  })
  local taken = {}
  local lastAction = -1
  for _ = 1, 40000 do
    if returned then break end
    scriptedPeer()
    local st = Battle.getState()
    if Battle.isActive() and st then
      if st.double or (State.isPresent(st, 2) and State.isPresent(st, 3)) then sawDouble = true end
      local Message = package.loaded["src.ui.game3.message"]
      local page = (Message and Message.isOpen and Message.isOpen() and Message.isWaiting and Message.isWaiting()
        and tostring(Message.currentPage() or "")) or ""
      page = page:gsub("\n", " ")
      if not taken.intro and page:find("to battle", 1, true) then
        taken.intro = true
        U.still(game, DIR .. "/g3battle_double_intro.png")
      end
      if not taken.start and Battle._phase == "command" and BattleUi._mode == "menu" then
        taken.start = true
        U.still(game, DIR .. "/g3battle_double_battle_start.png")
      end
      if not taken.mid and (st.turn or 0) >= 2 and page:find(" used ", 1, true) then
        taken.mid = true
        U.still(game, DIR .. "/g3battle_double_mid_turn.png")
      end
      if not taken.result and (page:find("lost against", 1, true)
          or page:find("defeated", 1, true) or page:find("draw against", 1, true)) then
        taken.result = true
        U.still(game, DIR .. "/g3battle_double_result.png")
      end
      if Battle._phase == "command" and (BattleUi._mode == "menu" or BattleUi._mode == "moves"
          or BattleUi._mode == "target") and U.frame() - lastAction > 6 then
        lastAction = U.frame()
        if BattleUi._mode == "menu" and (tonumber(BattleUi._menuIndex) or 1) ~= 1 then
          U.tap(game, "up")
          U.wait(2)
          U.tap(game, "left")
        else
          U.tap(game, "a")
        end
      else
        U.wait(1)
      end
    else
      U.wait(1)
    end
  end
  result(sawDouble, "the arena battle ran as a double battle")
  result(outcome == "win" or outcome == "lose" or outcome == "draw", "the double battle finished (" .. tostring(outcome) .. ")")
  result(returned and returned.tab == "online", "returned to the launcher's online tab")
  result(taken.start and taken.mid and taken.result, "battle start, mid-turn and result were captured")
  local lists = 0
  for _, row in ipairs(relay.log) do
    if row.seat == 0 and row.msg.type == "game3_battle_action" and row.msg.kind == "list" then lists = lists + 1 end
  end
  result(lists >= 1, "seat 0 sent both battlers' actions as one list per turn (" .. lists .. ")")
  finish()
end
