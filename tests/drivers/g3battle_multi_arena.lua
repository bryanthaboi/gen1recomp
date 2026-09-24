local U = require("tests.drivers.util")
local H = require("tests.link3_harness")

local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3battle_multi"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS g3battle_multi_arena")
    love.event.quit(0)
  else
    print("FAIL g3battle_multi_arena failures=" .. failures)
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

local NAMES = { [0] = "RED", [1] = "LEAF", [2] = "BLUE", [3] = "GREEN" }
local TRAINER_IDS = { [0] = 0x1234, [1] = 0x2468, [2] = 0x1357, [3] = 0x8642 }

local function profile()
  return { engine = 3, version = "firered", kind = "vanilla", rulesetId = "g3_multi", rule = { partySize = 3 } }
end

local function players()
  local out = {}
  for seat = 0, 3 do out[#out + 1] = { id = string.format("%08x", seat + 1), name = NAMES[seat], seat = seat } end
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
  local State = require("src.core.game3.battle.state")
  local Engine = require("src.core.game3.battle.engine")
  local LB = require("src.core.game3.link.battle")

  local parties = {
    [0] = { mon(6, 50, { 53, 17 }), mon(25, 50, { 85, 98 }), mon(131, 50, { 57, 58 }) },
    [1] = { mon(9, 50, { 57, 44 }), mon(3, 50, { 76, 22 }), mon(143, 50, { 34, 29 }) },
    [2] = { mon(65, 50, { 94, 93 }), mon(68, 50, { 2, 67 }), mon(94, 50, { 85, 95 }) },
    [3] = { mon(59, 50, { 53, 44 }), mon(130, 50, { 57, 44 }), mon(26, 50, { 85, 98 }) },
  }
  local packed = {}
  for seat = 0, 3 do packed[seat] = H.pack(parties[seat]) end
  local SEED = 0x3C3C5A5A

  local returned
  game.returnToLauncher = function(o) returned = o or {} end

  local function canon(st, id)
    return st.linkSeatOf[id]
  end

  local function scriptedPeers(relay, mySeat)
    local peers, sent, switched, outcomes = {}, {}, {}, {}
    for seat = 0, 3 do
      if seat ~= mySeat then peers[seat] = relay:session(seat) end
    end
    local seatSent = {}
    return function()
      for seat, s in pairs(peers) do
        for _, msg in ipairs(s:poll()) do
          if msg.seat == mySeat then
            if msg.type == "game3_hello" then
              local hello = LB.copy(msg)
              hello.seat = nil
              hello.name = NAMES[seat]
              hello.game3.trainerId, hello.game3.gender, hello.game3.seat = TRAINER_IDS[seat], seat % 2, seat
              s:send(hello)
            elseif msg.type == "game3_battle_linkup" then
              s:send({ type = "game3_battle_linkup", linkType = msg.linkType, players = 4 })
            elseif msg.type == "game3_battle_seat" and not seatSent[seat] then
              seatSent[seat] = true
              s:send({ type = "game3_battle_seat" })
            elseif msg.type == "game3_battle_setup" then
              s:send({ type = "game3_battle_setup", mode = "multi", unionRoom = false, name = NAMES[seat],
                trainerId = TRAINER_IDS[seat], gender = seat % 2, party = packed[seat] })
            elseif msg.type == "game3_battle_hash" then
              s:send({ type = "game3_battle_hash", turn = msg.turn, value = msg.value, parts = msg.parts })
            elseif msg.type == "game3_battle_outcome" and not outcomes[seat] then
              outcomes[seat] = true
              local out = msg.outcome
              if seat % 2 ~= mySeat % 2 then out = ({ [1] = 2, [2] = 1, [3] = 3, [128] = 1 })[msg.outcome] or 3 end
              s:send({ type = "game3_battle_outcome", outcome = out, turn = msg.turn })
            end
          end
        end
      end
      local st = Battle.getState()
      if Battle.isActive() and st and st.multi then
        if Battle._phase == "linkwait" and Battle._linkMulti then
          for id = 0, 3 do
            local seat = st.linkSeatOf[id]
            local key = tostring(seat) .. ":" .. tostring(st.turn)
            if peers[seat] and not sent[key] and State.isPresent(st, id) then
              sent[key] = true
              local b = State.battler(st, id)
              local slot = 1
              for i = 1, 4 do
                if b.mon.moves[i] and (tonumber(b.mon.pp and b.mon.pp[i]) or 0) > 0 then slot = i break end
              end
              local target = State.isPresent(st, State.OPPOSITE(id)) and State.OPPOSITE(id)
                or State.PARTNER(State.OPPOSITE(id))
              peers[seat]:send({ type = "game3_battle_action", turn = st.turn, kind = "move", slot = slot,
                target = canon(st, target) })
            end
          end
        end
        local pending = Battle._linkSwitch
        if Battle._phase == "linkswitch" and pending and pending.battler ~= nil then
          local seat = st.linkSeatOf[pending.battler]
          local key = tostring(seat) .. ":" .. tostring(st.turn) .. ":" .. tostring(pending.battler)
          if peers[seat] and not switched[key] then
            switched[key] = true
            local cands = Engine.replacementCandidates(st, pending.battler)
            if cands[1] then peers[seat]:send({ type = "game3_battle_switch", slot = cands[1] }) end
          end
        end
      end
      relay:tick()
    end
  end

  local function runArena(mySeat, shots)
    returned = nil
    local relay = H.relay({ seed = SEED, seats = 4, roomSeed = 10 + mySeat })
    local session = relay:session(mySeat)
    local peerStep = scriptedPeers(relay, mySeat)
    local outcome
    local digests
    game:enterArena({
      profile = profile(), role = ({ [0] = "host", [1] = "guest", [2] = "seat2", [3] = "seat3" })[mySeat],
      seat = mySeat, seats = 4, seed = SEED, match = "m" .. mySeat, room = relay.room, players = players(),
      myParty = packed[mySeat], session = session, client = relay:client(), mode = "multi",
      onDone = function(r)
        outcome = r
        digests = {}
        for turn, value in pairs(LB._myHashes or {}) do digests[turn] = value end
      end,
    })
    if game.session then
      game.session.name, game.session.gender = NAMES[mySeat], mySeat % 2
    end
    local taken, info = {}, {}
    local lastAction = -1
    local partyOpened = false
    for _ = 1, 40000 do
      if returned then break end
      peerStep()
      local st = Battle.getState()
      if Battle.isActive() and st and st.multi then
        info.own = st.linkOwn
        local PartyMenu = package.loaded["src.ui.game3.party_menu"]
        local partyOpen = PartyMenu and PartyMenu.isOpen and PartyMenu.isOpen()
        local menuUp = Battle._phase == "command" and BattleUi._mode == "menu" and not partyOpen
        local Message = package.loaded["src.ui.game3.message"]
        local page = (Message and Message.isOpen and Message.isOpen() and Message.isWaiting and Message.isWaiting()
          and tostring(Message.currentPage() or "")) or ""
        page = page:gsub("\n", " ")
        if shots.result and not taken.result and (page:find("defeated", 1, true) or page:find("lost to", 1, true)
            or page:find("lost against", 1, true) or page:find("draw", 1, true)) then
          taken.result = true
          info.resultText = page
          U.still(game, DIR .. "/" .. shots.result)
        elseif shots.intro and not taken.intro and page:find("want to battle", 1, true) then
          taken.intro = true
          info.introText = page
          local tp = require("src.core.game3.battle.anim").stage().trainer.player
          info.backs = { own = tp.gender, partner = tp.gender2 }
          U.wait(20)
          U.still(game, DIR .. "/" .. shots.intro)
        elseif shots.sendout and not taken.sendout and page:find("Go! ", 1, true) then
          taken.sendout = true
          info.sendoutText = page
          U.wait(10)
          U.still(game, DIR .. "/" .. shots.sendout)
        elseif shots.start and not taken.start and menuUp then
          taken.start = true
          U.wait(8)
          U.still(game, DIR .. "/" .. shots.start)
        elseif shots.party and not taken.party and menuUp and not partyOpened then
          partyOpened = true
          U.tap(game, "down")
          U.wait(4)
          U.tap(game, "a")
          U.wait(4)
        elseif shots.party and not taken.party and partyOpen then
          U.wait(40)
          info.order = BattleUi.battlePartyOrder(st)
          info.allies = BattleUi.allySlots(st, info.order)
          U.still(game, DIR .. "/" .. shots.party)
          taken.party = true
          U.tap(game, "b")
          U.wait(20)
          if PartyMenu.isOpen() then U.tap(game, "b") U.wait(10) end
        elseif not partyOpen and Battle._phase == "command"
            and (BattleUi._mode == "menu" or BattleUi._mode == "moves" or BattleUi._mode == "target")
            and U.frame() - lastAction > 6 and (taken.party or not shots.party) then
          lastAction = U.frame()
          if BattleUi._mode == "menu" and (tonumber(BattleUi._menuIndex) or 1) ~= 1 then
            U.tap(game, "up")
            U.wait(2)
            U.tap(game, "left")
          else
            U.tap(game, "a")
          end
        elseif partyOpen and taken.party and PartyMenu.mode == "battle_faint" then
          local order = BattleUi.battlePartyOrder(st)
          local pick
          for view, pi in ipairs(order) do
            local m = st.playerParty[pi]
            if not pick and st.partyOwner.player[pi] == st.linkOwn and m and (tonumber(m.hp) or 0) > 0 then pick = view end
          end
          if pick then PartyMenu.cursor = pick end
          U.tap(game, "a")
          U.wait(8)
          U.tap(game, "a")
          U.wait(8)
        elseif partyOpen and taken.party then
          U.tap(game, "b")
          U.wait(4)
        else
          U.wait(1)
        end
      else
        U.wait(1)
      end
    end
    return outcome, digests, taken, info, relay
  end

  local r0, d0, shots0, info0, relay0 = runArena(0, {
    intro = "g3battle_multi_seat0_intro_two_trainers.png",
    sendout = "g3battle_multi_seat0_partner_sendout.png",
    start = "g3battle_multi_seat0_battle_start.png",
    party = "g3battle_multi_seat0_party_menu.png",
    result = "g3battle_multi_seat0_result.png",
  })
  result(shots0.result, "seat 0 multi result was captured (" .. tostring(info0.resultText) .. ")")
  result(shots0.intro and (info0.introText or ""):find("LEAF and GREEN", 1, true) ~= nil,
    "seat 0 intro names both link opponents (" .. tostring(info0.introText) .. ")")
  result(shots0.sendout and (info0.sendoutText or ""):find("BLUE sent out", 1, true) ~= nil,
    "seat 0 intro has the partner send out first (" .. tostring(info0.sendoutText) .. ")")
  result(r0 == "win" or r0 == "lose" or r0 == "draw", "seat 0 multi battle finished (" .. tostring(r0) .. ")")
  result(returned and returned.tab == "online", "seat 0 returned to the launcher's online tab")
  result(shots0.start and shots0.party, "seat 0 multi battle start and party menu were captured")
  result(info0.own == 0, "seat 0 controls battler 0")
  local own0 = {}
  for view, allied in pairs(info0.allies or {}) do if allied then own0[#own0 + 1] = view end end
  table.sort(own0)
  result(table.concat(own0, ",") == "2,5,6", "seat 0 party menu tints the ally's boxes 2, 5 and 6 (" .. table.concat(own0, ",") .. ")")
  local n0 = 0
  for _ in pairs(d0 or {}) do n0 = n0 + 1 end
  result(n0 >= 1, "seat 0 digested " .. n0 .. " turns")
  local actions = {}
  for _, row in ipairs(relay0.log) do
    if row.msg.type == "game3_battle_action" and row.seat == 0 then
      actions[#actions + 1] = row.msg
    end
  end
  local single = #actions > 0
  for _, a in ipairs(actions) do if a.actions ~= nil or a.kind == "list" then single = false end end
  result(single, "seat 0 sent one action per turn for its own battler (" .. #actions .. ")")

  local r2, d2, shots2, info2 = runArena(2, {
    intro = "g3battle_multi_seat2_intro_two_trainers.png",
    start = "g3battle_multi_seat2_battle_start.png",
    party = "g3battle_multi_seat2_party_menu.png",
  })
  result(r2 == "win" or r2 == "lose" or r2 == "draw", "seat 2 multi battle finished (" .. tostring(r2) .. ")")
  result(shots2.start and shots2.party, "seat 2 multi battle start and party menu were captured")
  result(info2.own == 2, "seat 2 controls battler 2")

  local r1, _, shots1, info1 = runArena(1, {
    intro = "g3battle_multi_seat1_intro_two_trainers.png",
    sendout = "g3battle_multi_seat1_partner_sendout.png",
    start = "g3battle_multi_seat1_battle_start.png",
    party = "g3battle_multi_seat1_party_menu.png",
  })
  result(shots1.intro and (info1.introText or ""):find("RED and BLUE", 1, true) ~= nil,
    "seat 1 intro names seat 0 then seat 2 (" .. tostring(info1.introText) .. ")")
  result(shots1.sendout and (info1.sendoutText or ""):find("GREEN sent out", 1, true) ~= nil,
    "seat 1 intro has its partner seat 3 send out first (" .. tostring(info1.sendoutText) .. ")")
  result(r1 == "win" or r1 == "lose" or r1 == "draw", "seat 1 multi battle finished (" .. tostring(r1) .. ")")
  result(shots1.start and shots1.party, "seat 1 multi battle start and party menu were captured")
  result(info1.own == 2, "seat 1 controls battler 2 (player right)")
  local b1 = info1.backs or {}
  result(b1.own == 1 and b1.partner == 1,
    "seat 1 draws LEAF's and partner GREEN's female back pics (" .. tostring(b1.own) .. "," .. tostring(b1.partner) .. ")")
  local b0 = info0.backs or {}
  result(b0.own == 0 and b0.partner == 0,
    "seat 0 draws RED's and partner BLUE's male back pics (" .. tostring(b0.own) .. "," .. tostring(b0.partner) .. ")")
  local own1 = {}
  for view, allied in pairs(info1.allies or {}) do if allied then own1[#own1 + 1] = view end end
  table.sort(own1)
  result(table.concat(own1, ",") == "2,5,6", "seat 1 party menu tints the ally's boxes 2, 5 and 6 (" .. table.concat(own1, ",") .. ")")
  local relayS = H.relay({ seed = SEED, seats = 4, roomSeed = 30 })
  local feeds = {}
  for seat = 0, 3 do feeds[seat] = relayS:session(seat) end
  for _, row in ipairs(relay0.log) do
    if row.seat ~= nil and feeds[row.seat] and row.msg.type ~= "game3_bye" then feeds[row.seat]:send(row.msg) end
  end
  local watcher = relayS:session(nil)
  returned = nil
  local rS
  game:enterArena({
    profile = profile(), role = "spectator", seats = 4, seed = SEED, match = "ms", room = relayS.room,
    players = players(), session = watcher, client = relayS:client(), mode = "multi",
    onDone = function(r) rS = r end,
  })
  local takenS = {}
  for _ = 1, 40000 do
    if returned then break end
    relayS:tick()
    local st = Battle.getState()
    local Message = package.loaded["src.ui.game3.message"]
    local page = (Battle.isActive() and st and Message and Message.isOpen and Message.isOpen() and Message.isWaiting
      and Message.isWaiting() and tostring(Message.currentPage() or "")) or ""
    page = page:gsub("\n", " ")
    if not takenS.intro and page:find("want to battle", 1, true) then
      takenS.intro = true
      U.still(game, DIR .. "/g3battle_multi_spectator_intro.png")
    elseif not takenS.mid and st and (st.turn or 0) >= 2 and page:find(" used ", 1, true) then
      takenS.mid = true
      U.still(game, DIR .. "/g3battle_multi_spectator_mid_turn.png")
    elseif not takenS.result and (page:find("defeated", 1, true) or page:find("lost to", 1, true)
        or page:find("lost against", 1, true) or page:find("draw", 1, true)) then
      takenS.result = true
      U.still(game, DIR .. "/g3battle_multi_spectator_result.png")
    end
    U.wait(1)
  end
  result(rS == "ended", "the spectator watched the whole multi battle (" .. tostring(rS) .. ")")
  result(takenS.intro and takenS.mid and takenS.result, "spectator intro, mid-turn and result were captured")
  local spoke = false
  for _, row in ipairs(relayS.log) do if row.seat == nil then spoke = true end end
  result(not spoke, "the spectator never sent a message")
  result(game.phase == "arena" and game.arena == nil, "the arena state was torn down")
  finish()
end
