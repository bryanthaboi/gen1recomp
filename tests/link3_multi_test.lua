#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local H = require("tests.link3_harness")
local Cache = require("tests.game3_cache")

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

if not Cache.root("meta.json") then
  print("[skip] Gen 3 multi battle runs the real battle engine on ROM data: " .. tostring(Cache.reason))
  os.exit(0)
end
H.mountCache()

local quietPrint = print
local function silent(fn)
  print = function() end
  local ok, a, b, c = pcall(fn)
  print = quietPrint
  if not ok then error(a, 0) end
  return a, b, c
end

local Pokemon = require("src.core.game3.pokemon")

local function mon(species, level, extra)
  local m = {
    species = species, level = level, moves = extra and extra.moves or Pokemon.movesAtLevel(species, level),
    personality = extra and extra.personality or 0,
    ivs = { hp = 20, atk = 20, def = 20, spe = 20, spa = 20, spd = 20 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    item = extra and extra.item or 0,
  }
  return H.legal(m)
end

local NAMES = { [0] = "RED", [1] = "LEAF", [2] = "BLUE", [3] = "GREEN" }

local function session(seat)
  return { name = NAMES[seat], trainerId = 0x1000 + seat, gender = seat % 2, party = {}, bag = {} }
end

local function makePolicy(opts)
  opts = opts or {}
  return function(w, st)
    local sel = w.Battle._dblSel
    if not (sel and sel.active) then return end
    local id = sel.active
    if opts.run and opts.run(w, st, id) then
      w.Ui._pendingCommand = { kind = "run", user = "player", battler = id }
      return
    end
    if opts.switch then
      local slot = opts.switch(w, st, id)
      if slot then
        w.Ui._pendingCommand = { kind = "switch", user = "player", battler = id, slot = slot }
        return
      end
    end
    local b = w.State.battler(st, id)
    local mon0 = b and b.mon or {}
    local slot = 1
    for i = 1, 4 do
      if mon0.moves and mon0.moves[i] and (tonumber(mon0.pp and mon0.pp[i]) or 0) > 0 then
        slot = i
        if (st.turn + id) % 2 == 0 then break end
      end
    end
    local targets = {}
    for _, t in ipairs({ 1, 3 }) do
      if w.State.isPresent(st, t) then targets[#targets + 1] = t end
    end
    local target = targets[(st.turn % math.max(1, #targets)) + 1] or 1
    w.Ui._pendingCommand = w.Commands.playerAction(st, 1, slot, id, target)
  end
end

local function runMatch(opts)
  local relay = H.relay({ seed = opts.seed, seats = 4, lag = opts.lag or {}, roomSeed = opts.seed })
  local ws = {}
  silent(function()
    for seat = 0, 3 do ws[seat] = H.newWorld("seat" .. seat, session(seat)) end
    for seat = 0, 3 do
      H.attachSeat(ws[seat], relay, seat, { mode = "multi", myParty = H.pack(opts.parties[seat]),
        profile = { rule = {} }, autoFight = opts.auto })
    end
  end)
  local spectator
  if opts.watch then
    spectator = H.newWorld("spectator", { name = "WATCH", trainerId = 1, gender = 0, party = {}, bag = {} })
    silent(function() H.attachSpectator(spectator, relay, { mode = "multi", profile = { rule = {} } }) end)
  end
  local policies = {}
  for seat = 0, 3 do policies[seat] = (opts.policies and opts.policies[seat]) or makePolicy() end
  local frames = 0
  silent(function()
    while frames < 40000 do
      frames = frames + 1
      for seat = 0, 3 do
        for _ = 1, (opts.steps and opts.steps[seat]) or 1 do H.step(ws[seat], policies[seat]) end
      end
      if spectator then H.step(spectator, nil) end
      if opts.onFrame then opts.onFrame(ws, relay, frames) end
      relay:tick()
      local done = true
      for seat = 0, 3 do if not ws[seat].result then done = false end end
      if spectator and not spectator.result then done = false end
      if done then break end
    end
  end)
  return ws, spectator, relay, frames
end

local function hashesOf(w)
  return H.run(w, function()
    local out = {}
    for turn, value in pairs(w.LB._myHashes or {}) do out[turn] = value end
    return out
  end)
end

local function sameHashes(a, b)
  local n = 0
  for turn, value in pairs(a) do
    if b[turn] ~= nil then
      n = n + 1
      if b[turn] ~= value then return false, n, turn end
    end
  end
  return true, n
end

local MIRROR = { win = "lose", lose = "win", draw = "draw" }

local function verify(label, ws, spectator, relay)
  for seat = 0, 3 do
    check(ws[seat].result ~= nil, label .. ": seat " .. seat .. " finished (" .. tostring(ws[seat].result) .. ")")
    eq(H.run(ws[seat], function() return ws[seat].LB.endReason end), nil, label .. ": seat " .. seat .. " saw no desync")
    eq(#ws[seat].reports, 1, label .. ": seat " .. seat .. " reported once")
  end
  eq(ws[2].result, ws[0].result, label .. ": partners 0 and 2 share a result")
  eq(ws[3].result, ws[1].result, label .. ": partners 1 and 3 share a result")
  eq(MIRROR[ws[0].result], ws[1].result, label .. ": the sides mirror")
  local h0 = hashesOf(ws[0])
  for seat = 1, 3 do
    local ok, n, turn = sameHashes(h0, hashesOf(ws[seat]))
    check(ok and n >= 2, label .. ": seat " .. seat .. " digested every turn like seat 0 (" .. tostring(n) .. " turns"
      .. (turn and (", split at " .. turn) or "") .. ")")
  end
  if spectator then
    local okS, nS = sameHashes(h0, hashesOf(spectator))
    check(okS and nS >= 1, label .. ": the spectator simulated the same turns (" .. tostring(nS) .. ")")
    eq(spectator.result, "ended", label .. ": the spectator watched to the end")
    eq(#spectator.reports, 0, label .. ": the spectator never reports")
  end
  local kinds, outcomes = {}, {}
  for _, row in ipairs(relay.log) do
    kinds[row.msg.type] = (kinds[row.msg.type] or 0) + 1
    if row.msg.type == "game3_battle_action" then
      check(row.msg.actions == nil and row.msg.kind ~= "list", label .. ": seat " .. tostring(row.seat)
        .. " sent a single action for turn " .. tostring(row.msg.turn))
      if row.msg.actions ~= nil then break end
    end
    if row.msg.type == "game3_battle_outcome" then outcomes[row.seat] = row.msg.outcome end
  end
  eq((kinds.game3_battle_setup or 0), 4, label .. ": four setups crossed the relay")
  eq((kinds.game3_battle_outcome or 0), 4, label .. ": every seat sent one game3_battle_outcome")
  check((kinds.game3_battle_hash or 0) >= 8, label .. ": hashes crossed the relay (" .. tostring(kinds.game3_battle_hash) .. ")")
end

local PARTIES = {
  [0] = { mon(6, 50), mon(25, 50), mon(131, 50) },
  [1] = { mon(9, 50), mon(3, 50), mon(143, 50) },
  [2] = { mon(65, 50), mon(68, 50), mon(94, 50) },
  [3] = { mon(59, 50), mon(130, 50), mon(26, 50) },
}

print("[test] 1. four seats over the relay, one battler each, side A vs side B, with a spectator")
do
  local ws, spectator, relay = runMatch({ seed = 0x4D17, parties = PARTIES, watch = true })
  verify("multi", ws, spectator, relay)
end

print("[test] 2. each machine sees its own mons on its side of the field")
do
  local relay = H.relay({ seed = 0x51, seats = 4, roomSeed = 0x51 })
  local ws = {}
  silent(function()
    for seat = 0, 3 do ws[seat] = H.newWorld("layout" .. seat, session(seat)) end
    for seat = 0, 3 do
      H.attachSeat(ws[seat], relay, seat, { mode = "multi", myParty = H.pack(PARTIES[seat]), profile = { rule = {} } })
    end
    for _ = 1, 30 do
      for seat = 0, 3 do H.step(ws[seat], nil) end
      relay:tick()
    end
  end)
  local function species(list)
    local out = {}
    for i, m in ipairs(list or {}) do out[i] = tonumber(m.species) end
    return table.concat(out, ",")
  end
  local function speciesOf(seats)
    local out = {}
    for _, seat in ipairs(seats) do
      for _, m in ipairs(PARTIES[seat]) do out[#out + 1] = tonumber(m.species) end
    end
    return table.concat(out, ",")
  end
  for seat = 0, 3 do
    local st = H.run(ws[seat], function() return ws[seat].Battle.getState() end)
    check(st ~= nil and st.multi == true, "layout: seat " .. seat .. " runs a multi battle")
    if st then
      local mySide = seat % 2
      local SIDE = { [0] = { 0, 2 }, [1] = { 3, 1 } }
      eq(species(st.playerParty), speciesOf(SIDE[mySide]), "layout: seat " .. seat .. " player party = its side's two trainers, left flank first")
      eq(species(st.foeParty), speciesOf(SIDE[1 - mySide]), "layout: seat " .. seat .. " foe party = the other side, left flank first")
      local own = (seat == 0 or seat == 3) and 0 or 2
      eq(st.linkOwn, own, "layout: seat " .. seat .. " controls battler " .. own)
      eq(st.linkNames[1], NAMES[SIDE[1 - mySide][1]], "layout: seat " .. seat .. " sees the left-flank opponent at battler 1")
      eq(st.linkNames[3], NAMES[SIDE[1 - mySide][2]], "layout: seat " .. seat .. " sees the right-flank opponent at battler 3")
      local byId = {}
      for i, id in ipairs(H.run(ws[seat], function() return ws[seat].State.battlerOrder(st) end)) do
        byId[i] = st.linkSeatOf[id]
      end
      eq(table.concat(byId, ","), "0,1,2,3", "layout: seat " .. seat .. " walks battlers in cart battler id order")
      local b = H.run(ws[seat], function() return ws[seat].State.battler(st, own) end)
      eq(tonumber(b and b.mon and b.mon.species), tonumber(PARTIES[seat][1].species), "layout: seat " .. seat .. " leads with its own first mon")
      eq(st.linkNames[own], NAMES[seat], "layout: seat " .. seat .. " own battler named for its trainer")
      eq(st.linkNames[(own + 2) % 4], NAMES[(seat + 2) % 4], "layout: seat " .. seat .. " partner battler named for the partner")
      eq(st.linkMaster, seat % 2 == 0, "layout: seat " .. seat .. " perspective follows its side")
      local partnerSlot = (own == 0) and 4 or 1
      local err = H.run(ws[seat], function() return ws[seat].Commands.switchError(st, partnerSlot, false, own) end)
      check(type(err) == "string" and err:find(NAMES[(seat + 2) % 4], 1, true) ~= nil,
        "layout: seat " .. seat .. " can't switch to the ally's mon (" .. tostring(err) .. ")")
      local ownBench = (own == 0) and 2 or 5
      local okErr = H.run(ws[seat], function() return ws[seat].Commands.switchError(st, ownBench, false, own) end)
      eq(okErr, nil, "layout: seat " .. seat .. " may switch to its own bench mon")
      local cands = H.run(ws[seat], function()
        return require("src.core.game3.battle.engine").replacementCandidates(st, own)
      end)
      local allOwn = #cands > 0
      for _, c in ipairs(cands) do if st.partyOwner.player[c] ~= own then allOwn = false end end
      check(allOwn, "layout: seat " .. seat .. " replacement candidates are its own mons only")
      local order = H.run(ws[seat], function() return ws[seat].Ui.battlePartyOrder(st) end)
      local view = {}
      for i, pi in ipairs(order) do view[i] = st.partyOwner.player[pi] end
      eq(table.concat(view, ","), table.concat({ own, (own + 2) % 4, own, own, (own + 2) % 4, (own + 2) % 4 }, ","),
        "layout: seat " .. seat .. " party menu = own lead, ally lead, own bench, ally bench")
      local intro = H.run(ws[seat], function()
        local log = ws[seat].Ui.log() or {}
        return table.concat(log, " / ")
      end)
      local pics = H.run(ws[seat], function()
        return require("src.core.game3.battle.intro_seq").multiTrainerPics(st, 0)
      end)
      local LBw = ws[seat].LB
      local function front(s0) return (s0 % 2 == 1) and LBw.TRAINER_PIC_LEAF or LBw.TRAINER_PIC_RED end
      local partner = (seat + 2) % 4
      check(pics ~= nil, "pics: seat " .. seat .. " builds the multi trainer pics")
      if pics then
        eq(pics.gender, seat % 2, "pics: seat " .. seat .. " own back pic uses its own gender")
        eq(pics.partnerGender, partner % 2, "pics: seat " .. seat .. " partner back pic uses seat " .. partner .. "'s link gender")
        eq(pics.x, (own == 2) and 90 or 32, "pics: seat " .. seat .. " own back pic on its flank")
        eq(pics.partnerX, (own == 2) and 32 or 90, "pics: seat " .. seat .. " partner back pic on the other flank")
        eq(pics.enemyPic, front(SIDE[1 - mySide][1]), "pics: seat " .. seat .. " left opponent front pic by link gender")
        eq(pics.enemyPic2, front(SIDE[1 - mySide][2]), "pics: seat " .. seat .. " right opponent front pic by link gender")
      end
      local opp1 = (seat % 2 == 0) and seat + 1 or seat - 1
      local opp2 = (opp1 + 2) % 4
      check(intro:find(NAMES[opp1] .. " and " .. NAMES[opp2], 1, true) ~= nil,
        "layout: seat " .. seat .. " is challenged by both link opponents (" .. intro:sub(1, 80) .. ")")
    end
  end
end

print("[test] 3. a switch to an own bench mon crosses to all four machines")
do
  local switched = {}
  local policies = {}
  for seat = 0, 3 do
    policies[seat] = makePolicy({
      switch = function(w, st, id)
        if seat == 2 and st.turn == 1 and not switched[seat] then
          switched[seat] = true
          return 5
        end
        return nil
      end,
    })
  end
  local ws, _, relay = runMatch({ seed = 0x5117C, parties = PARTIES, policies = policies })
  verify("switch", ws, nil, relay)
  local sawSwitch = false
  for _, row in ipairs(relay.log) do
    if row.seat == 2 and row.msg.type == "game3_battle_action" and row.msg.kind == "switch" then sawSwitch = true end
  end
  check(sawSwitch, "switch: seat 2's switch went out as its own action")
end

print("[test] 4. a partner running ends the battle as a loss for that side")
do
  local policies = {}
  for seat = 0, 3 do
    policies[seat] = makePolicy({
      run = function(w, st, id) return seat == 3 and st.turn >= 1 end,
    })
  end
  local ws = runMatch({ seed = 0x7777, parties = PARTIES, policies = policies })
  eq(ws[0].result, "win", "run: seat 0 wins when the other side runs")
  eq(ws[2].result, "win", "run: seat 2 wins too")
  eq(ws[1].result, "lose", "run: seat 1 loses with its runaway partner")
  eq(ws[3].result, "lose", "run: seat 3 loses")
end

print("[test] 5. lag and uneven frame rates across four seats stay in lockstep")
do
  local ws, spectator, relay = runMatch({ seed = 0x2BAD, parties = {
    [0] = { mon(149, 55), mon(26, 50) },
    [1] = { mon(248, 55) },
    [2] = { mon(94, 50), mon(65, 50), mon(3, 50) },
    [3] = { mon(143, 50), mon(59, 50) },
  }, watch = true, lag = { [0] = 2, [1] = 0, [2] = 3, [3] = 1, spectator = 2 }, steps = { [0] = 1, [1] = 3, [2] = 2, [3] = 1 } })
  verify("lag", ws, spectator, relay)
end

print("[test] 6. a seat that sends a four-mon party is refused")
do
  local extra = H.pack({ mon(3, 50) })[1]
  local relay = H.relay({ seed = 0x99, seats = 4, roomSeed = 0x99, tamper = function(fromSeat, _, msg)
    if fromSeat == 3 and msg.type == "game3_battle_setup" and type(msg.party) == "table" then
      msg.party[#msg.party + 1] = extra
    end
    return msg
  end })
  local ws = {}
  silent(function()
    for seat = 0, 3 do ws[seat] = H.newWorld("refuse" .. seat, session(seat)) end
    for seat = 0, 3 do
      H.attachSeat(ws[seat], relay, seat, { mode = "multi", myParty = H.pack(PARTIES[seat]), profile = { rule = {} } })
    end
    for _ = 1, 60 do
      for seat = 0, 3 do H.step(ws[seat], nil) end
      relay:tick()
    end
  end)
  for seat = 0, 2 do
    eq(ws[seat].result, "error", "refuse: seat " .. seat .. " refuses seat 3's four-mon party")
    eq(H.run(ws[seat], function() return ws[seat].LB.endReason end), "bad party", "refuse: seat " .. seat .. " names the reason")
  end
  local forfeits = 0
  for _, row in ipairs(relay.log) do if row.msg.type == "forfeit" then forfeits = forfeits + 1 end end
  check(forfeits >= 3, "refuse: every refusing seat sent forfeit (" .. forfeits .. ")")
end

print("[test] 7. a seat whose replacement never arrives is caught instead of stalling the room")
do
  local relay = H.relay({ seed = 0x5EED, seats = 4, roomSeed = 0x5EED, tamper = function(fromSeat, _, msg)
    if fromSeat == 2 and msg.type == "game3_battle_switch" then msg.type = "game3_link_card" end
    return msg
  end })
  local parties = {
    [0] = { mon(6, 50), mon(25, 50) },
    [1] = { mon(9, 50), mon(3, 50) },
    [2] = { mon(129, 5), mon(94, 50) },
    [3] = { mon(59, 50), mon(26, 50) },
  }
  local ws = {}
  silent(function()
    for seat = 0, 3 do ws[seat] = H.newWorld("skip" .. seat, session(seat)) end
    for seat = 0, 3 do
      H.attachSeat(ws[seat], relay, seat, { mode = "multi", myParty = H.pack(parties[seat]), profile = { rule = {} } })
    end
    local policy = makePolicy()
    for _ = 1, 20000 do
      for seat = 0, 3 do H.step(ws[seat], policy) end
      relay:tick()
      if ws[0].result and ws[1].result and ws[2].result and ws[3].result then break end
    end
  end)
  for seat = 0, 3 do
    eq(ws[seat].result, "draw", "skip: seat " .. seat .. " ends drawn")
    eq(H.run(ws[seat], function() return ws[seat].LB.endReason end), "desync", "skip: seat " .. seat .. " ends as a desync")
  end
  local log0 = H.run(ws[0], function() return table.concat(ws[0].LB.log, "\n") end)
  check(log0:find("component=switch", 1, true) ~= nil, "skip: seat 0 named the missing switch (" .. log0:gsub("\n", " | ") .. ")")
end

print("[test] 8. layout helpers")
do
  local w = H.newWorld("helpers", session(0))
  H.run(w, function()
    local LB = w.LB
    eq(LB.localBattler(1, 1), 2, "helpers: seat 1 sees itself as battler 2 (player right)")
    eq(LB.localBattler(1, 3), 0, "helpers: seat 1 sees its partner seat 3 as battler 0 (player left)")
    eq(LB.localBattler(1, 0), 1, "helpers: seat 1 sees seat 0 as battler 1 (opponent left)")
    eq(LB.localBattler(3, 3), 0, "helpers: seat 3 sees itself as battler 0 (player left)")
    eq(LB.localBattler(2, 2), 2, "helpers: seat 2 sees itself as battler 2 (player right)")
    eq(LB.localBattler(0, 3), 1, "helpers: seat 0 sees seat 3 as battler 1 (opponent left)")
    eq(LB.localBattler(0, 1), 3, "helpers: seat 0 sees seat 1 as battler 3 (opponent right)")
    eq(LB.localBattler(nil, 3), 1, "helpers: a spectator watches from seat 0's side")
    eq(LB.oppositeSeat(2), 3, "helpers: seat 2 faces seat 3")
    local layout, pp, fp = LB.multiLayout(3, { [0] = { "a" }, [1] = { "b", "c" }, [2] = { "d" }, [3] = { "e", "f", "g" } },
      { [0] = "RED", [1] = "LEAF", [2] = "BLUE", [3] = "GREEN" }, { [0] = 0, [1] = 1, [2] = 0, [3] = 1 })
    eq(table.concat(pp, ""), "efgbc", "helpers: seat 3's side party is seat 3 then seat 1")
    eq(table.concat(fp, ""), "ad", "helpers: seat 3's foe party is seat 0 then seat 2")
    eq(table.concat(layout.owners.player, ","), "0,0,0,2,2", "helpers: owners follow the local battler ids")
    eq(layout.own, 0, "helpers: seat 3 owns battler 0")
    eq(layout.names[1], "RED", "helpers: seat 3's battler 1 is seat 0")
    eq(layout.genders[3], 0, "helpers: seat 3's battler 3 is seat 2's gender")
    eq(layout.seatOf[2], 1, "helpers: seat 3's battler 2 is seat 1")
    eq(layout.localOf[1], 2, "helpers: seat 3 finds seat 1 at battler 2")
    eq(table.concat(layout.order, ","), "1,2,3,0", "helpers: seat 3 walks cart battler ids 0-3 as local 1,2,3,0")
    local IntroSeq = require("src.core.game3.battle.intro_seq")
    local G = { [0] = 0, [1] = 1, [2] = 1, [3] = 0 }
    local SIDE = { [0] = { 0, 2 }, [1] = { 3, 1 } }
    local function front(s0) return (G[s0] == 1) and LB.TRAINER_PIC_LEAF or LB.TRAINER_PIC_RED end
    for seat = 0, 3 do
      local lay = LB.multiLayout(seat, { [0] = {}, [1] = {}, [2] = {}, [3] = {} }, NAMES, G)
      local pics = IntroSeq.multiTrainerPics({ multi = true, linkOwn = lay.own, linkGenders = lay.genders }, 0)
      local partner = (seat + 2) % 4
      local foes = SIDE[1 - seat % 2]
      eq(pics.gender, G[seat], "helpers: seat " .. seat .. " own back pic gender with mixed genders")
      eq(pics.partnerGender, G[partner], "helpers: seat " .. seat .. " partner back pic is seat " .. partner .. "'s gender")
      eq(pics.enemyPic, front(foes[1]), "helpers: seat " .. seat .. " left opponent pic is seat " .. foes[1] .. "'s")
      eq(pics.enemyPic2, front(foes[2]), "helpers: seat " .. seat .. " right opponent pic is seat " .. foes[2] .. "'s")
    end
    local ok, why = LB.unpackMultiParty(H.pack({ mon(1, 5), mon(4, 5), mon(7, 5), mon(25, 5) }))
    check(ok == nil and why == "bad party", "helpers: four mons are refused (" .. tostring(why) .. ")")
    LB.mode = LB.MODE_OF.multi
    LB._myPacked = H.pack({ mon(1, 5), mon(4, 5), mon(7, 5), mon(25, 5) })
    eq(#LB.myPacked(), 3, "helpers: this seat sends only its first three")
    LB.reset()
  end)
end

if failed == 0 then
  print("[pass] link3 multi")
  os.exit(0)
end
print("[fail] link3 multi: " .. failed)
os.exit(1)
