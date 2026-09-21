#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Slots = require("src.core.game3.slot_machine")
local Rng = require("src.core.game3.rng")
local Opcodes = require("src.core.game3.scripting.opcodes")

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

local PRET = "../pokefirered/src/slot_machine.c"
local PRET_SPECIALS = "../pokefirered/src/field_specials.c"

local function slurp(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local d = f:read("*a")
  f:close()
  return d
end

local ICON_NAMES = {
  ICON_7 = Slots.ICON.SEVEN,
  ICON_ROCKET = Slots.ICON.ROCKET,
  ICON_PIKACHU = Slots.ICON.PIKACHU,
  ICON_PSYDUCK = Slots.ICON.PSYDUCK,
  ICON_CHERRIES = Slots.ICON.CHERRIES,
  ICON_MAGNEMITE = Slots.ICON.MAGNEMITE,
  ICON_SHELLDER = Slots.ICON.SHELLDER,
}

local PAYOUT_NAMES = {
  PAYOUT_NONE = 0,
  PAYOUT_CHERRIES2 = 1,
  PAYOUT_CHERRIES3 = 2,
  PAYOUT_MAGSHELL = 3,
  PAYOUT_PIKAPSY = 4,
  PAYOUT_ROCKET = 5,
  PAYOUT_7 = 6,
}

local function body_after(src, decl)
  local i = src:find(decl, 1, true)
  if not i then return nil end
  local open = src:find("{", i, true)
  if not open then return nil end
  local depth, j = 0, open
  while j <= #src do
    local c = src:sub(j, j)
    if c == "{" then depth = depth + 1 end
    if c == "}" then
      depth = depth - 1
      if depth == 0 then return src:sub(open + 1, j - 1) end
    end
    j = j + 1
  end
  return nil
end

local src = slurp(PRET)
local specials = slurp(PRET_SPECIALS)
if not src or not specials then
  print("[skip] pret sources not found at " .. PRET .. " (nothing to compare against)")
  os.exit(0)
end

print("[test] 1. Reel strips match pret symbol for symbol")
do
  local body = body_after(src, "static const u8 sReelIconAnimByReelAndPos[NUM_REELS][REEL_LENGTH]")
  check(body ~= nil, "sReelIconAnimByReelAndPos found in pret")
  local reel, pos = 0, 0
  local seen = 0
  for token in body:gmatch("[%w_}{]+") do
    if token == "{" then
      pos = 0
    elseif token == "}" then
      if pos > 0 then
        eq(pos, Slots.REEL_LENGTH, "reel " .. reel .. " has REEL_LENGTH icons")
        reel = reel + 1
      end
    elseif ICON_NAMES[token] ~= nil then
      eq(Slots.iconAt(reel, pos), ICON_NAMES[token],
        string.format("reel %d pos %d is %s", reel, pos, token))
      pos = pos + 1
      seen = seen + 1
    end
  end
  eq(seen, 63, "every reel icon compared")
end

print("[test] 2. Payout table pays exactly pret's amounts")
do
  local body = body_after(src, "static const u16 sPayoutTable[]")
  check(body ~= nil, "sPayoutTable found in pret")
  local n = 0
  for name, value in body:gmatch("%[(PAYOUT_[%w_]+)%]%s*=%s*(%d+)") do
    local rank = PAYOUT_NAMES[name]
    eq(Slots.payoutFor(rank), tonumber(value), "payout for " .. name)
    n = n + 1
  end
  eq(n, Slots.NUM_PAYOUT_TYPES, "every payout rank compared")
end

print("[test] 3. Row attributes and the pay lines each bet opens")
do
  local body = body_after(src, "static const u8 sRowAttributes[NUM_MATCH_LINES][4]")
  check(body ~= nil, "sRowAttributes found in pret")
  local line = 0
  for row in body:gmatch("{([^}]+)}") do
    local cols = {}
    for v in row:gmatch("0x%x+") do cols[#cols + 1] = tonumber(v) end
    eq(#cols, 4, "line " .. line .. " has four attributes")
    for i = 1, 4 do
      eq(Slots.ROW_ATTRIBUTES[line][i - 1], cols[i],
        string.format("line %d attribute %d", line, i - 1))
    end
    line = line + 1
  end
  eq(line, Slots.NUM_MATCH_LINES, "five match lines")

  local function lineSet(bet)
    local t = {}
    for _, id in ipairs(Slots.linesForBet(bet)) do t[id] = true end
    return t
  end
  local b1, b2, b3 = lineSet(1), lineSet(2), lineSet(3)
  eq(#Slots.linesForBet(1), 1, "bet 1 opens one line")
  check(b1[2], "bet 1 opens the middle row only")
  eq(#Slots.linesForBet(2), 3, "bet 2 opens three lines")
  check(b2[1] and b2[2] and b2[3], "bet 2 opens the three horizontal rows")
  check(not b2[0] and not b2[4], "bet 2 leaves both diagonals dark")
  eq(#Slots.linesForBet(3), 5, "bet 3 opens all five lines")
  check(b3[0] and b3[4], "bet 3 lights both diagonals")
end

print("[test] 4. CalcPayout pays pret's amount for each combination")
-- pokefirered/src/slot_machine.c:1712
local function positionFor(reel, icon, row)
  for pos = 0, Slots.REEL_LENGTH - 1 do
    if Slots.iconAt(reel, (pos + 1 + row) % Slots.REEL_LENGTH) == icon then return pos end
  end
  return nil
end

local function payoutOf(bet, icons, row)
  local st = Slots.newState(0)
  st.bet = bet
  for reel = 0, 2 do
    local p = positionFor(reel, icons[reel + 1], row)
    if p == nil then return nil end
    st.reelPositions[reel] = p
  end
  local rank = Slots.calcPayout(st)
  return rank, st.payout
end

do
  local I = Slots.ICON
  -- pokefirered/src/slot_machine.c:253
  local rank, coins = payoutOf(1, { I.SEVEN, I.SEVEN, I.SEVEN }, 1)
  eq(rank, Slots.PAYOUT.SEVEN, "three sevens on the middle row is PAYOUT_7")
  eq(coins, 300, "three sevens pay 300")

  rank, coins = payoutOf(1, { I.ROCKET, I.ROCKET, I.ROCKET }, 1)
  eq(rank, Slots.PAYOUT.ROCKET, "three rockets is PAYOUT_ROCKET")
  eq(coins, 100, "three rockets pay 100")

  rank, coins = payoutOf(1, { I.PIKACHU, I.PIKACHU, I.PIKACHU }, 1)
  eq(rank, Slots.PAYOUT.PIKAPSY, "three Pikachu is PAYOUT_PIKAPSY")
  eq(coins, 15, "three Pikachu pay 15")

  rank, coins = payoutOf(1, { I.MAGNEMITE, I.MAGNEMITE, I.MAGNEMITE }, 1)
  eq(rank, Slots.PAYOUT.MAGSHELL, "three Magnemite is PAYOUT_MAGSHELL")
  eq(coins, 8, "three Magnemite pay 8")

  rank, coins = payoutOf(1, { I.MAGNEMITE, I.MAGNEMITE, I.SHELLDER }, 1)
  eq(rank, Slots.PAYOUT.NONE, "Magnemite and Shellder do not match each other")
  eq(coins, 0, "a mixed line pays nothing")

  rank, coins = payoutOf(1, { I.CHERRIES, I.SEVEN, I.SEVEN }, 1)
  eq(rank, Slots.PAYOUT.CHERRIES2, "one cherry on reel 1 is PAYOUT_CHERRIES2")
  eq(coins, 2, "one cherry pays 2")

  rank, coins = payoutOf(1, { I.CHERRIES, I.CHERRIES, I.SEVEN }, 1)
  eq(rank, Slots.PAYOUT.CHERRIES3, "cherries on reels 1 and 2 is PAYOUT_CHERRIES3")
  eq(coins, 6, "two cherries pay 6")

  rank, coins = payoutOf(1, { I.SEVEN, I.SEVEN, I.SEVEN }, 0)
  eq(rank, Slots.PAYOUT.NONE, "a bet of 1 does not pay the top row")
  eq(coins, 0, "an unlit line pays nothing")

  rank, coins = payoutOf(2, { I.SEVEN, I.SEVEN, I.SEVEN }, 0)
  eq(rank, Slots.PAYOUT.SEVEN, "a bet of 2 pays the top row")
  check(coins >= 300, "the top row pays the same 300, got " .. tostring(coins))
end

print("[test] 5. Bias chance table and CalcSlotBias pick the machine's class")
do
  local body = body_after(src, "static const u16 sReelBiasChances[][NUM_PAYOUT_TYPES]")
  check(body ~= nil, "sReelBiasChances found in pret")
  local chances = {}
  local idx = 0
  for row in body:gmatch("{([^}]+)}") do
    local t = {}
    for name, value in row:gmatch("%[(PAYOUT_[%w_]+)%]%s*=%s*(0x%x+)") do
      t[PAYOUT_NAMES[name]] = tonumber(value)
    end
    chances[idx] = t
    idx = idx + 1
  end
  eq(idx, Slots.NUM_MACHINE_CLASSES, "six machine classes in pret")
  for machine = 0, idx - 1 do
    for rank = 0, Slots.NUM_PAYOUT_TYPES - 1 do
      eq(Slots.BIAS_CHANCES[machine][rank], chances[machine][rank],
        string.format("machine %d chance for rank %d", machine, rank))
    end
  end

  -- pokefirered/src/slot_machine.c:1680
  local mismatches, sevens = 0, 0
  for machine = 0, idx - 1 do
    for seed = 1, 400 do
      Rng.SeedRng(seed * 31 + machine)
      local st = Slots.newState(machine)
      local got = Slots.calcBias(st)
      Rng.SeedRng(seed * 31 + machine)
      local rval = math.floor(Rng.Random() / 4)
      local expect = Slots.NUM_PAYOUT_TYPES - 1
      for i = 0, Slots.NUM_PAYOUT_TYPES - 2 do
        if rval < chances[machine][i] then expect = i break end
      end
      if got ~= expect then mismatches = mismatches + 1 end
      if got == Slots.PAYOUT.SEVEN then sevens = sevens + 1 end
    end
  end
  eq(mismatches, 0, "CalcSlotBias follows pret's threshold table on every machine")
  check(sevens > 0, "the 7 bias is reachable, hit " .. sevens .. " times")
end

print("[test] 6. The bias reaches the reels")
local function playOnce(st)
  st.bet = 3
  st.payout = 0
  Slots.startReels(st)
  for reel = 0, Slots.NUM_REELS - 1 do
    for _ = 1, 5 + (Rng.Random() % 40) do Slots.spinStep(st) end
    Slots.stopCurrentReel(st, reel, reel)
    local guard = 0
    while Slots.isReelSpinning(st, reel) and guard < 400 do
      Slots.spinStep(st)
      guard = guard + 1
    end
    check(guard < 400, "reel " .. reel .. " settled on its stop position")
  end
  return Slots.calcPayout(st), st.payout
end

do
  Rng.SeedRng(0x51075)
  local st = Slots.newState(0)
  local wins, coins, jackpots = {}, {}, 0
  for bias = 0, 6 do wins[bias], coins[bias] = 0, 0 end
  for play = 1, 700 do
    local bias = play % 7
    st.machineBias = bias
    local rank, paid = playOnce(st)
    if rank ~= Slots.PAYOUT.NONE then wins[bias] = wins[bias] + 1 end
    coins[bias] = coins[bias] + paid
    if rank == Slots.PAYOUT.SEVEN then jackpots = jackpots + 1 end
  end
  eq(wins[0], 0, "a PAYOUT_NONE bias never lands a paying line")
  eq(coins[0], 0, "a PAYOUT_NONE bias pays nothing")
  for bias = 1, 6 do
    check(wins[bias] > 0,
      string.format("bias %d lands paying lines (%d in 100 plays)", bias, wins[bias]))
  end
  check(jackpots > 0, "a biased machine can land the 300 coin jackpot")
end

print("[test] 7. A stop never moves the reel more than pret's five positions")
do
  Rng.SeedRng(0xBEEF)
  local st = Slots.newState(3)
  for _ = 1, 200 do
    Slots.calcBias(st)
    Slots.startReels(st)
    for reel = 0, Slots.NUM_REELS - 1 do
      for _ = 1, 3 + (Rng.Random() % 30) do Slots.spinStep(st) end
      local before = Slots.nextReelPosition(st, reel)
      Slots.stopCurrentReel(st, reel, reel)
      local delta = (before - st.destReelPos[reel]) % Slots.REEL_LENGTH
      check(delta <= 4, "stop offset " .. delta .. " is inside pret's five position window")
      local guard = 0
      while Slots.isReelSpinning(st, reel) and guard < 400 do
        Slots.spinStep(st)
        guard = guard + 1
      end
    end
    Slots.calcPayout(st)
  end
end

print("[test] 8. Machine ids map to pret's luck classes")
do
  local body = body_after(specials, "static const u8 sSlotMachineIndices[]")
  check(body ~= nil, "sSlotMachineIndices found in pret")
  local n = 0
  for value in body:gmatch("%d+") do
    eq(Slots.MACHINE_CLASS_BY_ID[n], tonumber(value), "machine id " .. n .. " luck class")
    n = n + 1
  end
  eq(n, Slots.NUM_MACHINE_IDS, "every Game Corner machine id mapped")
  for id = 0, n - 1 do
    local class = Slots.MACHINE_CLASS_BY_ID[id]
    check(class >= 0 and class < Slots.NUM_MACHINE_CLASSES,
      "machine id " .. id .. " maps into the bias table")
  end
  -- pokefirered/src/slot_machine.c:871
  eq(Slots.newState(99).machineIdx, 0, "an out of range machine id clamps to 0")
end

print("[test] 9. StopReel1 reads the bytes below the strip at a negative index")
do
  -- pokefirered/src/slot_machine.c:261
  if not src then
    print("[skip] no pret checkout at " .. PRET)
  else
    local bias = src:find("static const u16 sReelBiasChances", 1, true)
    local strip = src:find("static const u8 sReelIconAnimByReelAndPos", 1, true)
    check(bias ~= nil and strip ~= nil and bias < strip,
      "pret declares the bias table right before the reel strips")
    if bias and strip then
      local between = src:sub(src:find("};", bias, true) + 2, strip - 1)
      check(between:gsub("%s", "") == "", "nothing is declared between the two tables")
    end
  end
  -- pokefirered/src/slot_machine.c:1361
  local tail = Slots.BIAS_CHANCES[Slots.NUM_MACHINE_CLASSES - 1]
  local last = tail[Slots.NUM_PAYOUT_TYPES - 1]
  local prev = tail[Slots.NUM_PAYOUT_TYPES - 2]
  eq(Slots.iconAt(0, -1), math.floor(last / 256), "one byte below the strip")
  eq(Slots.iconAt(0, -2), last % 256, "two bytes below the strip")
  eq(Slots.iconAt(0, -3), math.floor(prev / 256), "three bytes below the strip")
  eq(Slots.iconAt(0, -4), prev % 256, "four bytes below the strip")
  check(not Slots.testIconAttribute(1, Slots.iconAt(0, -1)), "the byte below is not a cherry")
  check(not Slots.testIconAttribute(1, Slots.iconAt(0, -2)), "the second byte below is not a cherry")
  check(not Slots.testIconAttribute(1, Slots.iconAt(0, -3)), "the third byte below is not a cherry")
  eq(Slots.iconAt(1, -3), Slots.iconAt(0, 18), "a negative index on reel 2 falls into reel 1")
end

print("[test] 10. playslotmachine is opcode 0x89")
do
  local row = Opcodes.TABLE and Opcodes.TABLE[0x89] or nil
  check(row ~= nil, "opcode 0x89 is decoded")
  if row then
    eq(row.name, "playslotmachine", "opcode 0x89 is playslotmachine")
    eq(row.size, 3, "playslotmachine is three bytes")
  end
end

print("[test] 11. Betting moves coins through Bag.Coins")
do
  local Bag = require("src.core.game3.bag")
  local session = { coins = 10 }
  local st = Slots.newState(0)
  check(Slots.betOne(st, session), "a bet of one coin is accepted")
  eq(st.bet, 1, "bet is 1")
  eq(Bag.Coins.get(session), 9, "one coin left the purse")
  check(Slots.betMax(st, session), "R fills the bet to three")
  eq(st.bet, Slots.MAX_BET, "bet is 3")
  eq(Bag.Coins.get(session), 7, "two more coins left the purse")
  Slots.refundBet(st, session)
  eq(Bag.Coins.get(session), 10, "quitting refunds the whole bet")
  eq(st.bet, 0, "the refunded bet is cleared")

  local poor = { coins = 2 }
  local st2 = Slots.newState(0)
  check(Slots.betMax(st2, poor), "R with two coins is accepted")
  eq(st2.bet, 2, "the bet is what the player could afford")
  eq(Bag.Coins.get(poor), 0, "the purse is empty")
  check(not Slots.betOne(st2, poor), "an empty purse cannot bet")

  local winner = { coins = 0 }
  local st3 = Slots.newState(0)
  st3.payout = 3
  check(Slots.payCoin(st3, winner), "the payout pays one coin at a time")
  eq(Bag.Coins.get(winner), 1, "one coin arrived")
  eq(st3.payout, 2, "the payout counted down")
  check(Slots.payAll(st3, winner), "START pays the rest at once")
  eq(Bag.Coins.get(winner), 3, "every coin arrived")
  eq(st3.payout, 0, "the payout is empty")
  check(not Slots.payAll(st3, winner), "an empty payout pays nothing")
end

print("[test] 12. The playslotmachine opcode opens the machine and blocks the script")
do
  local Flags = require("src.core.game3.scripting.flags")
  local Vm = require("src.core.game3.scripting.vm")
  local Adapters = require("src.core.game3.scripting.adapters")
  local SlotUi = require("src.ui.game3.slot_machine")
  local VAR_RESULT = 0x800D

  local store = Flags.newStore()
  local vm = Vm.new({
    store = store,
    scripts = {
      t = {
        { op = "setvar", [1] = VAR_RESULT, [2] = 4 },
        { op = "playslotmachine", [1] = VAR_RESULT },
        { op = "setvar", [1] = 0x4001, [2] = 7 },
        { op = "end" },
      },
    },
    adapters = Adapters.host(nil, nil, nil),
  })
  vm:start("t")
  check(SlotUi.isOpen(), "playslotmachine opened the slot machine screen")
  eq(SlotUi.state and SlotUi.state.machineIdx, 4, "the operand var chose the machine class")
  eq(vm.ctx.status, "waiting", "the script is blocked on the screen")
  eq(Flags.getVar(store, vm.ctx, 0x4001), 0, "the script has not run past the machine")
  vm:tick()
  check(SlotUi.isOpen(), "the script stays blocked while the machine is open")
  SlotUi.close()
  vm:tick()
  eq(Flags.getVar(store, vm.ctx, 0x4001), 7, "closing the machine resumes the script")
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
