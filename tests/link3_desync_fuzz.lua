package.path = "./?.lua;./?/init.lua;" .. package.path

local H = require("tests.link3_harness")
local Cache = require("tests.game3_cache")

if not Cache.root("meta.json") then
  print("[skip] Gen 3 link desync fuzz runs the real battle engine on ROM data: " .. tostring(Cache.reason))
  os.exit(0)
end
H.mountCache()

require("src.core.Logger").warn = function() end
local quietPrint = print
local function silent(fn)
  print = function() end
  local ok, a, b, c = pcall(fn)
  print = quietPrint
  if not ok then error(a, 0) end
  return a, b, c
end

local function makeRandom(seed)
  local s = seed % 2147483647
  if s <= 0 then s = s + 2147483646 end
  return function(a, b)
    s = (s * 16807) % 2147483647
    if b == nil then a, b = 1, a end
    return a + (s % (b - a + 1))
  end
end

local ITEM_NAMES = {
  "LEFTOVERS", "KINGS_ROCK", "QUICK_CLAW", "FOCUS_BAND", "BRIGHT_POWDER", "SCOPE_LENS",
  "SHELL_BELL", "LUM_BERRY", "SITRUS_BERRY", "CHESTO_BERRY", "WHITE_HERB", "MENTAL_HERB",
  "CHOICE_BAND", "ORAN_BERRY", "PERSIM_BERRY", "CHARCOAL", "MYSTIC_WATER", "SHARP_BEAK",
}
local ITEMS = {}
do
  local ItemsData = require("src.core.game3.items_data")
  pcall(ItemsData.ensureLoaded)
  for _, name in ipairs(ITEM_NAMES) do
    local ok, id = pcall(ItemsData.toNumericId, name)
    if ok and tonumber(id) and tonumber(id) > 0 then ITEMS[#ITEMS + 1] = tonumber(id) end
  end
end

local Pokemon = require("src.core.game3.pokemon")

local function randomMon(rnd)
  for _ = 1, 50 do
    local species = rnd(1, 411)
    if (species < 252 or species > 276) and Pokemon.isInternalSpecies(species) then
      local level = rnd(25, 60)
      local pool = Pokemon.movesAtLevel(species, level) or {}
      local learn = {}
      for _, row in ipairs(Pokemon.learnset(species) or {}) do
        local lv, mv = tonumber(row[1] or row.level), tonumber(row[2] or row.move)
        if lv and mv and lv <= level then learn[#learn + 1] = mv end
      end
      local moves, seen = {}, {}
      for _ = 1, 4 do
        local src = (#learn > 0 and rnd(1, 3) == 1) and learn or pool
        local mv = src[rnd(1, math.max(1, #src))]
        if mv and not seen[mv] then
          seen[mv] = true
          moves[#moves + 1] = mv
        end
      end
      if #moves > 0 then
        local evs, left = {}, 510
        for _, key in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
          local v = math.min(left, rnd(0, 255))
          evs[key] = v
          left = left - v
        end
        local mon = {
          species = species, level = level, moves = moves,
          personality = rnd(0, 65535) * 65536 + rnd(0, 65535),
          ivs = { hp = rnd(0, 31), atk = rnd(0, 31), def = rnd(0, 31), spe = rnd(0, 31), spa = rnd(0, 31), spd = rnd(0, 31) },
          evs = evs,
          item = (#ITEMS > 0 and rnd(1, 100) <= 60) and ITEMS[rnd(1, #ITEMS)] or 0,
          friendship = rnd(0, 255),
        }
        return H.legal(mon)
      end
    end
  end
  return H.legal({ species = 6, level = 50, moves = { 53 } })
end

local function randomParty(rnd, n)
  local out = {}
  for i = 1, n do out[i] = randomMon(rnd) end
  return out
end

local function usableSlots(st, b)
  local out = {}
  local mon = b and b.mon or {}
  for i = 1, 4 do
    if mon.moves and mon.moves[i] and mon.moves[i] ~= 0 and (tonumber(mon.pp and mon.pp[i]) or 0) > 0 then
      out[#out + 1] = i
    end
  end
  return out
end

local function makePolicy(rnd, runChance)
  return function(w, st)
    if st.double then
      local sel = w.Battle._dblSel
      if not (sel and sel.active) then return end
      local id = sel.active
      local b = w.State.battler(st, id)
      if rnd(1, 1000) <= runChance then
        w.Ui._pendingCommand = { kind = "run", user = "player", battler = id }
        return
      end
      if rnd(1, 100) <= 8 then
        for _ = 1, 4 do
          local slot = rnd(1, #st.playerParty)
          if not w.Commands.switchError(st, slot, false, id) then
            w.Ui._pendingCommand = { kind = "switch", user = "player", battler = id, slot = slot }
            return
          end
        end
      end
      local slots = usableSlots(st, b)
      local slot = slots[rnd(1, math.max(1, #slots))] or 1
      local targets = {}
      for _, t in ipairs({ 1, 3, (id + 2) % 4 }) do
        if w.State.isPresent(st, t) then targets[#targets + 1] = t end
      end
      w.Ui._pendingCommand = w.Commands.playerAction(st, 1, slot, id, targets[rnd(1, math.max(1, #targets))] or 1)
      return
    end
    if rnd(1, 1000) <= runChance then
      w.Ui._pendingCommand = { kind = "run", user = "player" }
      return
    end
    if rnd(1, 100) <= 8 then
      for _ = 1, 4 do
        local slot = rnd(1, #st.playerParty)
        if slot ~= st.player.partyIndex and not w.Commands.switchError(st, slot) then
          w.Ui._pendingCommand = { kind = "switch", user = "player", slot = slot }
          return
        end
      end
    end
    local slots = usableSlots(st, st.player)
    w.Ui._pendingCommand = w.Commands.playerAction(st, 1, slots[rnd(1, math.max(1, #slots))] or 1)
  end
end

local MODES = { "clean", "clean", "clean", "seed", "rng", "hp", "party" }
local MIRROR = { win = "lose", lose = "win", draw = "draw" }

local function hashes(w)
  return H.run(w, function()
    local out = {}
    for turn, value in pairs(w.LB._myHashes or {}) do out[turn] = value end
    return out
  end)
end

local function firstSplit(a, b)
  local found
  for turn, value in pairs(a) do
    if b[turn] and b[turn] ~= value and (not found or turn < found) then found = turn end
  end
  return found
end

local function runOne(seed)
  local rnd = makeRandom((seed * 69621 + 7) % 2147483647)
  for _ = 1, 5 do rnd(1, 2) end
  local mode = MODES[rnd(1, #MODES)]
  local battleMode = rnd(1, 3) == 1 and "double" or "single"
  local lagA, lagB = rnd(0, 3), rnd(0, 3)
  local stepsA, stepsB = rnd(1, 3), rnd(1, 3)
  local auto = rnd(1, 5) == 1
  local watch = rnd(1, 2) == 1
  local injectTurn = rnd(2, 4)
  local sizeA = battleMode == "double" and rnd(2, 4) or rnd(1, 4)
  local sizeB = battleMode == "double" and rnd(2, 4) or rnd(1, 4)
  local partyA = randomParty(rnd, sizeA)
  local partyB = randomParty(rnd, sizeB)
  local tamper
  if mode == "party" then
    tamper = function(fromSeat, toSeat, msg)
      if fromSeat == 0 and toSeat == 1 and msg.type == "game3_battle_setup" and type(msg.party) == "table" then
        local m = msg.party[1]
        for _, mv in ipairs(m and m.moves or {}) do
          if (tonumber(mv.pp) or 0) > 0 then
            mv.pp = mv.pp - 1
            break
          end
        end
      end
      return msg
    end
  end
  local relay = H.relay({ seed = rnd(1, 2147483000), seats = 2, roomSeed = seed,
    lag = { [0] = lagA, [1] = lagB, spectator = rnd(0, 3) }, tamper = tamper })
  local w0 = H.newWorld("seat0", { name = "GOLD", trainerId = rnd(0, 65535), gender = 0, party = {}, bag = {} })
  local w1 = H.newWorld("seat1", { name = "SILVER", trainerId = rnd(0, 65535), gender = 1, party = {}, bag = {} })
  local ws = watch and H.newWorld("spectator", { name = "WATCH", trainerId = 1, gender = 0, party = {}, bag = {} }) or nil
  local policyA = makePolicy(makeRandom(seed * 7 + 1), mode == "clean" and 4 or 0)
  local policyB = makePolicy(makeRandom(seed * 7 + 2), mode == "clean" and 4 or 0)
  silent(function()
    H.attachSeat(w0, relay, 0, { mode = battleMode, myParty = H.pack(partyA), profile = { rule = {} }, autoFight = auto })
    H.attachSeat(w1, relay, 1, { mode = battleMode, myParty = H.pack(partyB), profile = { rule = {} }, autoFight = auto,
      seedOverride = mode == "seed" and (relay.seed + 1) or nil })
    if ws then H.attachSpectator(ws, relay, { mode = battleMode, profile = { rule = {} } }) end
  end)
  local trace = os.getenv("LINK3_FUZZ_TRACE") == "1"
  for _, w in ipairs({ w0, w1 }) do
    H.run(w, function()
      w.LB.keepRaw = true
      if trace then
        w.acts = {}
        local send = w.LB.sendAction
        w.LB.sendAction = function(turn, act)
          w.acts[#w.acts + 1] = ("send t%s %s slot=%s move=%s"):format(tostring(turn), tostring(act and act.kind), tostring(act and act.slot), tostring(act and act.move))
          return send(turn, act)
        end
        local Engine = require("src.core.game3.battle.engine")
        local resolve = Engine.resolveMove
        Engine.resolveMove = function(user, target, moveId, slot, ...)
          local st = w.Battle.getState()
          w.acts[#w.acts + 1] = ("resolve t%s user=%s move=%s slot=%s"):format(tostring(st and st.turn), tostring(type(user) == "table" and user.id or user), tostring(moveId), tostring(slot))
          return resolve(user, target, moveId, slot, ...)
        end
        local plan = Engine.planTurnFromActions
        Engine.planTurnFromActions = function(st, ad, p, e)
          w.acts[#w.acts + 1] = ("plan t%s p=%s/%s/%s e=%s/%s/%s"):format(tostring(st.turn), tostring(p and p.kind), tostring(p and p.slot), tostring(p and p.move), tostring(e and e.kind), tostring(e and e.slot), tostring(e and e.move))
          return plan(st, ad, p, e)
        end
        w.draws = {}
        local make = w.LB.makeRng
        w.LB.makeRng = function(s, counter)
          local fn = make(s, counter)
          return function(lo, hi)
            local v = fn(lo, hi)
            local tb = debug.traceback("", 2):gsub("\n%s*", " < "):sub(1, 400)
            w.draws[#w.draws + 1] = tostring(lo) .. "," .. tostring(hi) .. "=" .. tostring(v) .. tb
            return v
          end
        end
      end
    end)
  end
  local injected, injectedAt = false, nil
  local guard = 0
  local label = ("seed %d [%s %s lag %d/%d steps %d/%d%s%s]"):format(seed, mode, battleMode, lagA, lagB,
    stepsA, stepsB, auto and " auto" or "", ws and " watched" or "")
  silent(function()
    while guard < 30000 do
      guard = guard + 1
      for _ = 1, stepsA do H.step(w0, policyA) end
      for _ = 1, stepsB do H.step(w1, policyB) end
      if ws then H.step(ws, nil) end
      relay:tick()
      if (mode == "rng" or mode == "hp") and not injected then
        H.run(w1, function()
          local st = w1.Battle.getState()
          if st and w1.Battle.isActive() and st.turn >= injectTurn and w1.Battle._phase == "command" then
            injected = true
            injectedAt = st.turn
            if mode == "rng" then
              st.rng(0, 1)
            else
              local foe = st.enemy and st.enemy.mon
              if foe and (tonumber(foe.hp) or 0) > 1 then foe.hp = foe.hp - 1 else st.player.mon.hp = math.max(1, st.player.mon.hp - 1) end
            end
          end
        end)
      end
      if w0.result and w1.result and (not ws or ws.result) then break end
    end
  end)
  local turns = H.run(w0, function() local st = w0.Battle.getState() return st and st.turn or 0 end)
  if not (w0.result and w1.result) then
    local detail = ""
    if os.getenv("LINK3_FUZZ_LOG") == "1" then
      for _, w in ipairs({ w0, w1 }) do
        H.run(w, function()
          local st = w.Battle.getState()
          detail = detail .. ("\n    %s phase=%s lb=%s turn=%s sw=%s ui=%s"):format(w.name, tostring(w.Battle._phase),
            tostring(w.LB.state), tostring(st and st.turn), tostring(w.Battle._linkSwitch and w.Battle._linkSwitch.side),
            tostring(w.Ui._mode))
          local log = w.Ui.log() or {}
          for i = math.max(1, #log - 12), #log do
            detail = detail .. "\n    " .. w.name .. " | " .. tostring(log[i]):gsub("\n", " ")
          end
        end)
      end
    end
    return label .. ": did not finish (" .. tostring(w0.result) .. "/" .. tostring(w1.result) .. ") at turn " .. tostring(turns) .. detail, turns
  end
  if ws and not ws.result then return label .. ": the spectator never finished", turns end
  local r0 = H.run(w0, function() return w0.LB.endReason end)
  local r1 = H.run(w1, function() return w1.LB.endReason end)
  local h0, h1 = hashes(w0), hashes(w1)
  if mode == "clean" then
    local split = firstSplit(h0, h1)
    if split then
      local a = H.run(w0, function() return w0.LB._raw and w0.LB._raw[split] end) or {}
      local b = H.run(w1, function() return w1.LB._raw and w1.LB._raw[split] end) or {}
      local detail = ""
      for _, part in ipairs({ "actives", "volatile", "bench", "field" }) do
        if a[part] ~= b[part] then
          detail = ("\n  %s:\n    seat0 %s\n    seat1 %s"):format(part, tostring(a[part]), tostring(b[part]))
          break
        end
      end
      if trace then
        for i = 1, math.max(#(w0.draws or {}), #(w1.draws or {})) do
          local da, db = w0.draws[i], w1.draws[i]
          local ka = da and da:match("^[^<]*")
          local kb = db and db:match("^[^<]*")
          if ka ~= kb or (da and db and da:match("< ([^<]*) <") ~= db:match("< ([^<]*) <")) then
            detail = detail .. ("\n  draw %d\n    seat0 %s\n    seat1 %s"):format(i, tostring(da), tostring(db))
            break
          end
        end
      end
      if trace then
        for _, w in ipairs({ w0, w1 }) do
          for i = math.max(1, #w.acts - 14), #w.acts do detail = detail .. "\n    " .. w.name .. " # " .. w.acts[i] end
        end
      end
      if os.getenv("LINK3_FUZZ_LOG") == "1" then
        for _, w in ipairs({ w0, w1 }) do
          H.run(w, function()
            local log = w.Ui.log() or {}
            for i = math.max(1, #log - 40), #log do
              detail = detail .. "\n    " .. w.name .. " | " .. tostring(log[i]):gsub("\n", " ")
            end
          end)
        end
      end
      return label .. ": turn " .. split .. " hash split" .. detail, turns
    end
    if r0 == "desync" or r1 == "desync" then return label .. ": a clean run desynced (" .. tostring(r0) .. "/" .. tostring(r1) .. ")", turns end
    if MIRROR[w0.result] ~= w1.result then
      local detail = ""
      if os.getenv("LINK3_FUZZ_LOG") == "1" then
        for _, w in ipairs({ w0, w1 }) do
          H.run(w, function()
            local log = w.Ui.log() or {}
            for i = math.max(1, #log - 30), #log do
              detail = detail .. "\n    " .. w.name .. " | " .. tostring(log[i]):gsub("\n", " ")
            end
          end)
        end
      end
      return label .. ": results disagree (" .. tostring(w0.result) .. " vs " .. tostring(w1.result) .. ")" .. detail, turns
    end
    if MIRROR[w0.reports[1]] ~= w1.reports[1] or #w0.reports ~= 1 or #w1.reports ~= 1 then
      return label .. ": reports disagree", turns
    end
    if ws then
      if ws.result ~= "ended" then return label .. ": the spectator ended " .. tostring(ws.result), turns end
      local split2 = firstSplit(h0, hashes(ws))
      if split2 then return label .. ": the spectator split from seat 0 at turn " .. split2, turns end
    end
    return nil, turns
  end
  if (mode == "seed" or mode == "party") and turns <= 1 then return nil, turns end
  if (mode == "seed" or mode == "party") and not firstSplit(h0, h1) and MIRROR[w0.result] == w1.result then return nil, turns end
  if w0.result ~= "draw" or w1.result ~= "draw" then
    if (mode == "rng" or mode == "hp") and not injected then return nil, turns end
    return label .. ": a " .. mode .. " mismatch was not caught (" .. tostring(w0.result) .. "/" .. tostring(w1.result) .. ")", turns
  end
  if r0 ~= "desync" and r1 ~= "desync" then
    return label .. ": the draw was not a desync (" .. tostring(r0) .. "/" .. tostring(r1) .. ")", turns
  end
  if (mode == "rng" or mode == "hp") and turns > (injectedAt or injectTurn) + 2 then
    return label .. ": caught late at turn " .. turns .. " (injected at " .. tostring(injectedAt) .. ")", turns
  end
  if ws and ws.result ~= "ended" and ws.result ~= "error" then
    return label .. ": the spectator ended " .. tostring(ws.result), turns
  end
  return nil, turns
end

local function runMulti(seed)
  local rnd = makeRandom((seed * 48271 + 12345) % 2147483647)
  for _ = 1, 5 do rnd(1, 2) end
  local mode = MODES[rnd(1, #MODES)]
  local lag, steps = { spectator = rnd(0, 3) }, {}
  for seat = 0, 3 do
    lag[seat] = rnd(0, 3)
    steps[seat] = rnd(1, 3)
  end
  local auto = rnd(1, 5) == 1
  local watch = rnd(1, 2) == 1
  local injectTurn = rnd(2, 4)
  local odd = rnd(0, 3)
  local parties = {}
  for seat = 0, 3 do parties[seat] = randomParty(rnd, rnd(1, 3)) end
  local tamper
  if mode == "party" then
    tamper = function(fromSeat, toSeat, msg)
      if fromSeat == odd and toSeat == (odd + 1) % 4 and msg.type == "game3_battle_setup" and type(msg.party) == "table" then
        local m = msg.party[1]
        for _, mv in ipairs(m and m.moves or {}) do
          if (tonumber(mv.pp) or 0) > 0 then
            mv.pp = mv.pp - 1
            break
          end
        end
      end
      return msg
    end
  end
  local relay = H.relay({ seed = rnd(1, 2147483000), seats = 4, roomSeed = seed + 100000, lag = lag, tamper = tamper })
  local names = { [0] = "GOLD", [1] = "SILVER", [2] = "CRYS", [3] = "EMER" }
  local ws = {}
  for seat = 0, 3 do
    ws[seat] = H.newWorld("multi" .. seat, { name = names[seat], trainerId = rnd(0, 65535), gender = seat % 2,
      party = {}, bag = {} })
  end
  local wsp = watch and H.newWorld("multiwatch", { name = "WATCH", trainerId = 1, gender = 0, party = {}, bag = {} }) or nil
  local policies = {}
  for seat = 0, 3 do policies[seat] = makePolicy(makeRandom(seed * 11 + seat + 1), mode == "clean" and 3 or 0) end
  silent(function()
    for seat = 0, 3 do
      H.attachSeat(ws[seat], relay, seat, { mode = "multi", myParty = H.pack(parties[seat]), profile = { rule = {} },
        autoFight = auto, seedOverride = (mode == "seed" and seat == odd) and (relay.seed + 1) or nil })
      H.run(ws[seat], function() ws[seat].LB.keepRaw = true end)
    end
    if wsp then H.attachSpectator(wsp, relay, { mode = "multi", profile = { rule = {} } }) end
  end)
  local label = ("multi seed %d [%s lag %d/%d/%d/%d%s%s odd %d]"):format(seed, mode, lag[0], lag[1], lag[2], lag[3],
    auto and " auto" or "", wsp and " watched" or "", odd)
  local injected, guard, injectedAt = false, 0, nil
  local function allDone()
    for seat = 0, 3 do if not ws[seat].result then return false end end
    return not wsp or wsp.result ~= nil
  end
  silent(function()
    while guard < 40000 do
      guard = guard + 1
      for seat = 0, 3 do
        for _ = 1, steps[seat] do H.step(ws[seat], policies[seat]) end
      end
      if wsp then H.step(wsp, nil) end
      relay:tick()
      if (mode == "rng" or mode == "hp") and not injected then
        local w = ws[odd]
        H.run(w, function()
          local st = w.Battle.getState()
          if st and w.Battle.isActive() and st.turn >= injectTurn and w.Battle._phase == "command" then
            injected = true
            injectedAt = st.turn
            if mode == "rng" then
              st.rng(0, 1)
            else
              local foe = w.State.battler(st, 1)
              local mine = w.State.battler(st, st.linkOwn or 0)
              if foe and (tonumber(foe.mon.hp) or 0) > 1 then foe.mon.hp = foe.mon.hp - 1
              elseif mine then mine.mon.hp = math.max(1, mine.mon.hp - 1) end
            end
          end
        end)
      end
      if allDone() then break end
    end
  end)
  local turns = H.run(ws[0], function() local st = ws[0].Battle.getState() return st and st.turn or 0 end)
  for seat = 0, 3 do
    if not ws[seat].result then
      local detail = ""
      if os.getenv("LINK3_FUZZ_LOG") == "1" then
        for s = 0, 3 do
          H.run(ws[s], function()
            local st = ws[s].Battle.getState()
            detail = detail .. ("\n    seat%d phase=%s lb=%s turn=%s sw=%s result=%s"):format(s, tostring(ws[s].Battle._phase),
              tostring(ws[s].LB.state), tostring(st and st.turn), tostring(ws[s].Battle._linkSwitch and ws[s].Battle._linkSwitch.battler),
              tostring(ws[s].result))
            local log = ws[s].Ui.log() or {}
            for i = math.max(1, #log - 6), #log do detail = detail .. "\n    seat" .. s .. " | " .. tostring(log[i]):gsub("\n", " ") end
          end)
        end
      end
      return label .. ": seat " .. seat .. " did not finish at turn " .. tostring(turns) .. detail, turns
    end
  end
  if wsp and not wsp.result then return label .. ": the spectator never finished", turns end
  local reasons, h = {}, {}
  for seat = 0, 3 do
    reasons[seat] = H.run(ws[seat], function() return ws[seat].LB.endReason end)
    h[seat] = hashes(ws[seat])
  end
  if mode == "clean" then
    for seat = 1, 3 do
      local split = firstSplit(h[0], h[seat])
      if split then
        local a = H.run(ws[0], function() return ws[0].LB._raw and ws[0].LB._raw[split] end) or {}
        local b = H.run(ws[seat], function() return ws[seat].LB._raw and ws[seat].LB._raw[split] end) or {}
        local detail = ""
        for _, part in ipairs({ "actives", "volatile", "bench", "field" }) do
          if a[part] ~= b[part] then
            detail = ("\n  %s:\n    seat0 %s\n    seat%d %s"):format(part, tostring(a[part]), seat, tostring(b[part]))
            break
          end
        end
        return label .. ": seat " .. seat .. " split from seat 0 at turn " .. split .. detail, turns
      end
    end
    for seat = 0, 3 do
      if reasons[seat] == "desync" then return label .. ": a clean run desynced at seat " .. seat, turns end
    end
    if ws[2].result ~= ws[0].result or ws[3].result ~= ws[1].result or MIRROR[ws[0].result] ~= ws[1].result then
      return label .. (": results disagree (%s/%s/%s/%s)"):format(tostring(ws[0].result), tostring(ws[1].result),
        tostring(ws[2].result), tostring(ws[3].result)), turns
    end
    for seat = 0, 3 do
      if #ws[seat].reports ~= 1 then return label .. ": seat " .. seat .. " reported " .. #ws[seat].reports .. " times", turns end
    end
    if wsp then
      if wsp.result ~= "ended" then return label .. ": the spectator ended " .. tostring(wsp.result), turns end
      local split = firstSplit(h[0], hashes(wsp))
      if split then return label .. ": the spectator split from seat 0 at turn " .. split, turns end
      if #wsp.reports ~= 0 then return label .. ": the spectator reported", turns end
    end
    return nil, turns
  end
  if (mode == "rng" or mode == "hp") and not injected then return nil, turns end
  if (mode == "seed" or mode == "party") and turns <= 1 then return nil, turns end
  if (mode == "seed" or mode == "party") and not (firstSplit(h[0], h[1]) or firstSplit(h[0], h[2]) or firstSplit(h[0], h[3]))
      and ws[2].result == ws[0].result and MIRROR[ws[0].result] == ws[1].result then
    return nil, turns
  end
  for seat = 0, 3 do
    if ws[seat].result ~= "draw" then
      return label .. (": a %s mismatch was not caught at seat %d (%s)"):format(mode, seat, tostring(ws[seat].result)), turns
    end
    if reasons[seat] ~= "desync" then
      return label .. (": seat %d drew without a desync (%s)"):format(seat, tostring(reasons[seat])), turns
    end
  end
  if (mode == "rng" or mode == "hp") and turns > (injectedAt or injectTurn) + 2 then
    return label .. ": caught late at turn " .. turns .. " (injected at " .. tostring(injectedAt) .. ")", turns
  end
  if wsp and wsp.result ~= "ended" and wsp.result ~= "error" then
    return label .. ": the spectator ended " .. tostring(wsp.result), turns
  end
  return nil, turns
end

local RUNS = tonumber(arg and arg[1]) or 40
local FIRST = tonumber(arg and arg[2]) or 1
local WHICH = (arg and arg[3]) or os.getenv("LINK3_FUZZ_MODE") or "all"

local failures, turns, multiRuns, multiTurns = 0, 0, 0, 0
for seed = FIRST, FIRST + RUNS - 1 do
  if WHICH ~= "multi" then
    local ok, why, t = pcall(runOne, seed)
    turns = turns + (tonumber(t) or 0)
    if not ok then
      failures = failures + 1
      print("FAIL gen3 desync fuzz seed " .. seed .. ": " .. tostring(why))
    elseif why then
      failures = failures + 1
      print("FAIL gen3 desync fuzz " .. why)
    end
  end
  if WHICH == "multi" or (WHICH == "all" and seed % 2 == 0) then
    multiRuns = multiRuns + 1
    local ok, why, t = pcall(runMulti, seed)
    multiTurns = multiTurns + (tonumber(t) or 0)
    if not ok then
      failures = failures + 1
      print("FAIL gen3 desync fuzz multi seed " .. seed .. ": " .. tostring(why))
    elseif why then
      failures = failures + 1
      print("FAIL gen3 desync fuzz " .. why)
    end
  end
end
print(("gen3 link desync fuzz: %d runs, %d turns, %d multi runs, %d multi turns, %d failures"):format(
  WHICH == "multi" and 0 or RUNS, turns, multiRuns, multiTurns, failures))
os.exit(failures == 0 and 0 or 1)
