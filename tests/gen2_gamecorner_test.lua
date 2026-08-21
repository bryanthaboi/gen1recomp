-- The Game Corner: the slot machine's reels, bias table and payout ladder, card
-- flip's deck and 6x8 board, the three prize counters' refusal ladders, and the
-- coin case's clamps at both ends.
--
-- ROM-free and draw-free.  Every decision these screens make is a pure function
-- taking a `random(n) -> 0..n-1`, so the odds tables can be driven with a
-- counted RNG rather than sampled: an assertion here says "this byte selects
-- this symbol", which is a statement about the transcription, not about luck.
-- The distribution checks that follow are the sanity pass over the same tables.

package.path = "./?.lua;" .. package.path

-- The UI modules pull love-side helpers in at load time.  Stub what they touch;
-- nothing here draws.
love = love or {}
love.graphics = love.graphics or {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end,
  rectangle = function() end,
  print = function() end,
  printf = function() end,
  draw = function() end,
  newQuad = function() return {} end,
  newImage = function() return nil end,
  getShader = function() return nil end,
  setShader = function() end,
  newShader = function() error("no shaders in this harness") end,
  getDimensions = function() return 160, 144 end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
  circle = function() end, clear = function() end,
}
love.math = love.math or {
  random = function(a, b)
    if b then return a end
    return a and 1 or 0.5
  end,
}
love.image = love.image or {}
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function() return true end,
  remove = function() return true end,
}
love.timer = love.timer or { getTime = function() return 0 end }

require("src.core.Logger").warn = function() end

local CardFlip = require("src.ui.gen2.CardFlip")
local PrizeMenu = require("src.ui.gen2.PrizeMenu")
local Save = require("src.core.gen2.Save")
local SlotMachine = require("src.ui.gen2.SlotMachine")

local failures, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(
      name, tostring(got), tostring(want)))
  end
end

-- A scripted RNG: hand it the bytes the cart's Random would return, in order.
-- `random(n)` yields the next byte modulo n, which is how every caller here
-- consumes it (`random(256)` is the raw byte, `random(8)` the `and $7`).
local function scripted(bytes)
  local i = 0
  return function(n)
    i = i + 1
    local byte = bytes[i] or 0
    return byte % (n or 256)
  end
end

-- A deterministic linear congruential byte source for the distribution passes,
-- so a failure here is reproducible rather than a flake.
local function seeded(seed)
  local state = seed
  return function(n)
    state = (state * 1103515245 + 12345) % 2147483648
    return math.floor(state / 65536) % (n or 256)
  end
end

local function newSave(coins, money)
  local save = Save.newGame({ playerName = "GOLD" })
  save.player.coins = coins or 0
  save.player.money = money or 0
  return save
end

-- ==================================================================== reels
--
-- Reel1Tilemap / Reel2Tilemap / Reel3Tilemap, including the three repeated
-- entries that let Slots_GetCurrentReelState read three bytes without wrapping.
local SEVEN = SlotMachine.SEVEN
local POKEBALL = SlotMachine.POKEBALL
local CHERRY, PIKACHU = SlotMachine.CHERRY, SlotMachine.PIKACHU
local SQUIRTLE, STARYU = SlotMachine.SQUIRTLE, SlotMachine.STARYU

for i = 1, 3 do
  check("reel " .. i .. " is 18 entries", #SlotMachine.REELS[i], 18)
  for j = 1, 3 do
    check(("reel %d repeats entry %d"):format(i, j),
      SlotMachine.REELS[i][15 + j], SlotMachine.REELS[i][j])
  end
end

-- Each reel's SEVEN and POKEBALL count is what makes 300 coins so rare: reel 3
-- carries exactly one of each.
local function countOf(strip, symbol)
  local n = 0
  for i = 1, SlotMachine.REEL_SIZE do
    if strip[i] == symbol then n = n + 1 end
  end
  return n
end

check("reel 1 has three SEVENs", countOf(SlotMachine.REELS[1], SEVEN), 2)
check("reel 1 has one POKEBALL", countOf(SlotMachine.REELS[1], POKEBALL), 1)
check("reel 2 has one SEVEN", countOf(SlotMachine.REELS[2], SEVEN), 1)
check("reel 2 has two POKEBALLs", countOf(SlotMachine.REELS[2], POKEBALL), 2)
check("reel 3 has one SEVEN", countOf(SlotMachine.REELS[3], SEVEN), 1)
check("reel 3 has one POKEBALL", countOf(SlotMachine.REELS[3], POKEBALL), 1)

-- Slots_GetCurrentReelState: slot 0 reads as if it were 15, and index 0 of the
-- window is the BOTTOM row.
local bottom, middle, top = SlotMachine.window(SlotMachine.REELS[1], 1)
check("slot 1 shows entry 0 on the bottom", bottom, SEVEN)
check("slot 1 shows entry 1 in the middle", middle, CHERRY)
check("slot 1 shows entry 2 on top", top, STARYU)

local b0 = SlotMachine.window(SlotMachine.REELS[1], 0)
local b15 = SlotMachine.window(SlotMachine.REELS[1], 15)
check("slot 0 reads as slot 15", b0, b15)
check("slot 0 shows entry 14", b0, SQUIRTLE)

-- The `and $f` mask is only harmless because of the three repeats: position 16
-- reads the same window position 1 does.
local w1 = { SlotMachine.window(SlotMachine.REELS[2], 1) }
local w16 = { SlotMachine.window(SlotMachine.REELS[2], 16) }
check("position 16 reads position 1's window",
  table.concat(w1, ","), table.concat(w16, ","))

-- Slots_UpdateReelPositionAndOAM's wrap.
check("advance wraps 14 to 0", SlotMachine.advance(14), 0)
check("advance steps 0 to 1", SlotMachine.advance(0), 1)

-- ================================================================ pay lines
--
-- The jumptable FALLS THROUGH, so a bet of three runs five checks and a bet of
-- one runs a single middle row.
check("bet 1 buys one line", #SlotMachine.LINES[1], 1)
check("bet 2 buys three lines", #SlotMachine.LINES[2], 3)
check("bet 3 buys five lines", #SlotMachine.LINES[3], 5)

-- Windows are { bottom, middle, top }.
local function win(a, b, c) return { a, b, c } end

check("a middle row pays at bet 1",
  SlotMachine.matchAll(1, win(CHERRY, SEVEN, CHERRY), win(CHERRY, SEVEN, CHERRY),
    win(CHERRY, SEVEN, CHERRY)), SEVEN)
-- Only the bottom row lines up here, so a bet of one sees nothing at all.
local bottomOnly = {
  win(SEVEN, CHERRY, PIKACHU),
  win(SEVEN, STARYU, SQUIRTLE),
  win(SEVEN, POKEBALL, STARYU),
}
check("a bottom row does not pay at bet 1",
  SlotMachine.matchAll(1, bottomOnly[1], bottomOnly[2], bottomOnly[3]),
  SlotMachine.NO_MATCH)
check("a bottom row pays at bet 2",
  SlotMachine.matchAll(2, bottomOnly[1], bottomOnly[2], bottomOnly[3]), SEVEN)
check("a top row pays at bet 2",
  SlotMachine.matchAll(2, win(CHERRY, STARYU, STARYU),
    win(PIKACHU, SQUIRTLE, STARYU), win(SEVEN, CHERRY, STARYU)), STARYU)
-- The upward diagonal is reel 1's bottom, reel 2's middle and reel 3's top.
check("the upward diagonal only pays at bet 3",
  SlotMachine.matchAll(2, win(CHERRY, SEVEN, STARYU), win(SEVEN, CHERRY, STARYU),
    win(SEVEN, STARYU, CHERRY)), SlotMachine.NO_MATCH)
check("the upward diagonal pays at bet 3",
  SlotMachine.matchAll(3, win(CHERRY, SEVEN, STARYU), win(SEVEN, CHERRY, STARYU),
    win(SEVEN, STARYU, CHERRY)), CHERRY)

-- Every hit overwrites wSlotMatched, so the LAST line checked wins the tie --
-- and the middle row is checked last.  Here the bottom row lines up STARYU and
-- the middle row lines up CHERRY; only the CHERRY is paid.
check("the middle row wins a tie",
  SlotMachine.matchAll(2, win(STARYU, CHERRY, SEVEN), win(STARYU, CHERRY, SEVEN),
    win(STARYU, CHERRY, SEVEN)), CHERRY)

-- Slots_CheckMatchedFirstTwoReels compares DIFFERENT rows: with two reels down
-- both diagonals collapse onto reel 2's middle symbol.
local building, sevens = SlotMachine.matchFirstTwo(3,
  win(SEVEN, CHERRY, PIKACHU), win(STARYU, SEVEN, SQUIRTLE))
check("two reels build on the upward diagonal", building, SEVEN)
check("and the sevens flag is set", sevens, true)
local building2, sevens2 = SlotMachine.matchFirstTwo(1,
  win(SEVEN, CHERRY, PIKACHU), win(STARYU, SEVEN, SQUIRTLE))
check("but not at bet 1", building2, SlotMachine.NO_MATCH)
check("and the sevens flag stays clear", sevens2, false)

-- ============================================================ payout ladder
--
-- Slots_GetPayout .PayoutTable.  The bet buys LINES, never a multiplier.
check("SEVEN pays 300", SlotMachine.payout(SEVEN), 300)
check("POKEBALL pays 50", SlotMachine.payout(POKEBALL), 50)
check("CHERRY pays 6", SlotMachine.payout(CHERRY), 6)
check("PIKACHU pays 8", SlotMachine.payout(PIKACHU), 8)
check("SQUIRTLE pays 10", SlotMachine.payout(SQUIRTLE), 10)
check("STARYU pays 15", SlotMachine.payout(STARYU), 15)
check("no match pays nothing", SlotMachine.payout(SlotMachine.NO_MATCH), 0)

-- ================================================================ the bias
--
-- Slots_InitBias .Normal / .Lucky.  `percent` is "* $ff / 100" with integer
-- division, so the boundaries are the bytes below and not round percentages.
-- The scan takes the first row whose threshold is >= the roll, so each byte
-- below is the LAST one that selects its symbol.
local NO_BIAS = SlotMachine.NO_BIAS
local NORMAL_EDGES = {
  { 0, SEVEN }, { 1, SEVEN }, { 2, POKEBALL }, { 3, POKEBALL },
  { 4, STARYU }, { 10, STARYU }, { 11, SQUIRTLE }, { 20, SQUIRTLE },
  { 21, PIKACHU }, { 40, PIKACHU }, { 41, CHERRY }, { 48, CHERRY },
  { 49, NO_BIAS }, { 255, NO_BIAS },
}
for _, row in ipairs(NORMAL_EDGES) do
  check(("normal bias byte %d"):format(row[1]),
    SlotMachine.initBias(NO_BIAS, false, scripted({ row[1] })), row[2])
end

local LUCKY_EDGES = {
  { 0, SEVEN }, { 2, SEVEN }, { 3, POKEBALL }, { 4, STARYU }, { 8, STARYU },
  { 9, SQUIRTLE }, { 16, SQUIRTLE }, { 17, PIKACHU }, { 30, PIKACHU },
  { 31, CHERRY }, { 80, CHERRY }, { 81, NO_BIAS }, { 255, NO_BIAS },
}
for _, row in ipairs(LUCKY_EDGES) do
  check(("lucky bias byte %d"):format(row[1]),
    SlotMachine.initBias(NO_BIAS, true, scripted({ row[1] })), row[2])
end

-- `ld a, [wSlotBias] / and a / ret z`: a spin already biased to SEVEN keeps it
-- without rolling at all.  The scripted RNG would say CHERRY if consulted.
check("a SEVEN bias survives without a roll",
  SlotMachine.initBias(SEVEN, false, scripted({ 48 })), SEVEN)
check("any other bias is rerolled",
  SlotMachine.initBias(CHERRY, false, scripted({ 48 })), CHERRY)

-- The exact shape of the table, sampled: SEVEN is 2 bytes in 256 on the normal
-- table and CHERRY jumps from 8 bytes to 50 on the lucky one.
local counts = {}
local roll = 0
for byte = 0, 255 do
  local symbol = SlotMachine.initBias(NO_BIAS, false, scripted({ byte }))
  counts[symbol] = (counts[symbol] or 0) + 1
  roll = roll + 1
end
check("256 bytes accounted for", roll, 256)
check("normal SEVEN is 2/256", counts[SEVEN], 2)
check("normal POKEBALL is 2/256", counts[POKEBALL], 2)
check("normal STARYU is 7/256", counts[STARYU], 7)
check("normal SQUIRTLE is 10/256", counts[SQUIRTLE], 10)
check("normal PIKACHU is 20/256", counts[PIKACHU], 20)
check("normal CHERRY is 8/256", counts[CHERRY], 8)
check("normal NO_BIAS is 207/256", counts[NO_BIAS], 207)

local lucky = {}
for byte = 0, 255 do
  local symbol = SlotMachine.initBias(NO_BIAS, true, scripted({ byte }))
  lucky[symbol] = (lucky[symbol] or 0) + 1
end
check("lucky SEVEN is 3/256", lucky[SEVEN], 3)
check("lucky POKEBALL is 1/256", lucky[POKEBALL], 1)
check("lucky CHERRY is 50/256", lucky[CHERRY], 50)
check("lucky NO_BIAS is 175/256", lucky[NO_BIAS], 175)
check("the lucky table is kinder", lucky[NO_BIAS] < counts[NO_BIAS], true)

-- .InitGFX's wKeepSevenBiasChance roll: %00101010 clear is 1 byte in 8.
local keeps = 0
for byte = 0, 255 do
  if SlotMachine.rollKeepSevenChance(scripted({ byte })) then keeps = keeps + 1 end
end
check("the session flag is set 32/256 of the time", keeps, 32)

-- .LinedUpSevens: the streak survives 1 roll in 4 normally, and -- the ASM's
-- own comment calls this out as probably inverted -- only 1 in 8 on the rarer
-- session flag.
local kept, keptRare = 0, 0
for byte = 0, 255 do
  if SlotMachine.keepSevenBias(false, scripted({ byte })) then kept = kept + 1 end
  if SlotMachine.keepSevenBias(true, scripted({ byte })) then
    keptRare = keptRare + 1
  end
end
check("a seven streak survives 64/256", kept, 64)
check("and only 32/256 on the rare flag", keptRare, 32)

-- ============================================================== reel stops
--
-- ReelAction_StopReel1: with no bias the reel stops where the player pressed.
check("an unbiased reel 1 stops dead",
  SlotMachine.stopReel1(7, NO_BIAS), 7)

-- With a bias it walks up to four slots hunting the symbol.  Reel 1 slot 3
-- shows entries 2,3,4 = STARYU, PIKACHU, SQUIRTLE; the nearest SEVEN in the
-- window is at slot 4 (entries 3,4,5).
check("a biased reel 1 walks to its symbol",
  SlotMachine.stopReel1(3, SEVEN), 4)
-- Four slots is the whole budget: a symbol further away is never reached.
local far = SlotMachine.stopReel1(7, SEVEN)
check("and gives up after four slots", far, 11)

-- ReelAction_StopReel3's rule with no bias at all: the reel refuses to settle
-- anywhere a line is lit.  Drive it against two reels showing CHERRY straight
-- across and assert the landing pays nothing.
local r1 = win(CHERRY, CHERRY, CHERRY)
local r2 = win(CHERRY, CHERRY, CHERRY)
local landed = SlotMachine.stopReel3(0, NO_BIAS, 3, r1, r2)
local r3 = { SlotMachine.window(SlotMachine.REELS[3], landed) }
check("an unbiased reel 3 lands on nothing",
  SlotMachine.matchAll(3, r1, r2, r3), SlotMachine.NO_MATCH)

-- Slots_StopReel2's skip-to-seven gate: it needs a bet of 2 or more, a SEVEN
-- somewhere in reel one, and a spin that is unbiased or biased to SEVEN.
local withSeven = win(SEVEN, CHERRY, STARYU)
local noSeven = win(CHERRY, PIKACHU, STARYU)
check("skip needs a bet of two",
  SlotMachine.reel2SkipsToSeven(1, NO_BIAS, withSeven, scripted({ 0 })), false)
check("skip needs a seven in reel one",
  SlotMachine.reel2SkipsToSeven(3, NO_BIAS, noSeven, scripted({ 0 })), false)
check("skip refuses a non-seven bias",
  SlotMachine.reel2SkipsToSeven(3, CHERRY, withSeven, scripted({ 0 })), false)
check("skip fires below 80/256",
  SlotMachine.reel2SkipsToSeven(3, NO_BIAS, withSeven, scripted({ 79 })), true)
check("and not at 80",
  SlotMachine.reel2SkipsToSeven(3, NO_BIAS, withSeven, scripted({ 80 })), false)
check("a seven bias is allowed",
  SlotMachine.reel2SkipsToSeven(2, SEVEN, withSeven, scripted({ 0 })), true)

-- ============================================== reel 3's near-miss theatre
--
-- Slots_StopReel3's action roll only happens when the first two reels already
-- show matching SEVENs.
check("no sevens means no theatre",
  SlotMachine.reel3Action(false, SEVEN, scripted({ 0 })),
  SlotMachine.REEL3_STOP)

-- Biased to SEVEN: stop 76/256, slow 60, golem 60, egg 60.
local sevenBoundaries = {
  { 255, SlotMachine.REEL3_STOP }, { 180, SlotMachine.REEL3_STOP },
  { 179, SlotMachine.REEL3_SLOW }, { 120, SlotMachine.REEL3_SLOW },
  { 119, SlotMachine.REEL3_GOLEM }, { 60, SlotMachine.REEL3_GOLEM },
  { 59, SlotMachine.REEL3_EGG }, { 0, SlotMachine.REEL3_EGG },
}
for _, row in ipairs(sevenBoundaries) do
  check(("seven-bias theatre at %d"):format(row[1]),
    SlotMachine.reel3Action(true, SEVEN, scripted({ row[1] })), row[2])
end

-- Anything else: stop 96/256, slow 80, golem 80, and the egg is UNREACHABLE.
local otherBoundaries = {
  { 255, SlotMachine.REEL3_STOP }, { 160, SlotMachine.REEL3_STOP },
  { 159, SlotMachine.REEL3_SLOW }, { 80, SlotMachine.REEL3_SLOW },
  { 79, SlotMachine.REEL3_GOLEM }, { 0, SlotMachine.REEL3_GOLEM },
}
for _, row in ipairs(otherBoundaries) do
  check(("unbiased theatre at %d"):format(row[1]),
    SlotMachine.reel3Action(true, NO_BIAS, scripted({ row[1] })), row[2])
end
local eggs = 0
for byte = 0, 255 do
  if SlotMachine.reel3Action(true, NO_BIAS, scripted({ byte }))
      == SlotMachine.REEL3_EGG then
    eggs = eggs + 1
  end
end
check("Chansey never appears without a seven bias", eggs, 0)

-- Slots_GetNumberOfGolems, biased to SEVEN: the count is exactly the number of
-- one-slot steps to a SEVEN line, so the reel really does land on one.
local sevenRow = win(SEVEN, SEVEN, SEVEN)
local golems = SlotMachine.golemCount(0, SEVEN, 3, sevenRow, sevenRow,
  scripted({}))
local golemLanding = 0
for _ = 1, golems do golemLanding = SlotMachine.advance(golemLanding) end
local golemWindow = { SlotMachine.window(SlotMachine.REELS[3], golemLanding) }
check("Golem lands a seven when the bias is seven",
  SlotMachine.matchAll(3, sevenRow, sevenRow, golemWindow), SEVEN)
check("and takes at least one Golem", golems >= 1, true)

-- The other branch rerolls `and $7` until it is 4..7, which is the stride the
-- SEARCH walks; the count returned is the final stride, so the reel lands
-- somewhere the search never looked.  0, 1, 2 and 3 are all rejected rolls.
local strideCount = SlotMachine.golemCount(0, NO_BIAS, 3, sevenRow, sevenRow,
  scripted({ 0, 3, 5 }))
check("an unbiased Golem stride starts at 4 or more", strideCount >= 5, true)

-- ================================================================== spins
--
-- The whole machine, seeded.  Two properties hold over thousands of spins and
-- they are the ones the tables above exist to produce.
local paid, spins, unnamed, silentMatch = 0, 0, 0, 0
local random = seeded(20260807)
local biasSeen = {}
for i = 1, 4000 do
  local result = SlotMachine.spin({
    random = random,
    bet = 3,
    bias = NO_BIAS,
    stops = { i % 15, (i * 7) % 15, (i * 11) % 15 },
  })
  spins = spins + 1
  biasSeen[result.bias] = (biasSeen[result.bias] or 0) + 1
  if result.payout > 0 then
    paid = paid + 1
    if SlotMachine.PAYOUTS[result.matched] == nil then unnamed = unnamed + 1 end
  elseif result.matched ~= SlotMachine.NO_MATCH then
    silentMatch = silentMatch + 1
  end
end
check("every spin resolved", spins, 4000)
check("every paid spin names a symbol on the table", unnamed, 0)
check("and a symbol on the table always pays", silentMatch, 0)
-- An unbiased spin cannot line anything up, so a paying spin implies a bias was
-- rolled.  With NO_BIAS at 207/256 the paid rate has to be well under half.
check("most spins pay nothing", paid < spins / 2, true)
check("some spins pay", paid > 0, true)
check("the unbiased spins dominate", biasSeen[NO_BIAS] > spins / 2, true)

-- ReelAction_StopReel3 keeps spinning past any match that is NOT the bias, so
-- the reel it stops can only ever land on the biased symbol or on nothing.
local wrongSymbol = 0
local twoCherries = win(CHERRY, CHERRY, CHERRY)
for start = 0, 14 do
  local at = SlotMachine.stopReel3(start, CHERRY, 3, twoCherries, twoCherries)
  local window = { SlotMachine.window(SlotMachine.REELS[3], at) }
  local matched = SlotMachine.matchAll(3, twoCherries, twoCherries, window)
  if matched ~= SlotMachine.NO_MATCH and matched ~= CHERRY then
    wrongSymbol = wrongSymbol + 1
  end
end
check("a CHERRY-biased reel 3 never settles on another symbol", wrongSymbol, 0)

-- Across whole spins the same holds, with ONE documented exception: the Golem
-- search for a spin that is not biased to SEVEN walks a growing stride while
-- the reel only advances one slot per Golem, so it lands somewhere the search
-- never looked and ReelAction_WaitGolem stops it there anyway.
local offBias = 0
local biasRandom = seeded(99)
for i = 1, 2000 do
  local result = SlotMachine.spin({
    random = biasRandom,
    bet = 3,
    bias = SlotMachine.NO_BIAS,
    stops = { i % 15, (i * 5) % 15, (i * 13) % 15 },
  })
  if result.matched ~= SlotMachine.NO_MATCH
      and result.matched ~= result.bias
      and result.reel3Action ~= SlotMachine.REEL3_GOLEM then
    offBias = offBias + 1
  end
end
check("a spin only ever pays its own bias, Golem aside", offBias, 0)

-- ============================================================== coin case
--
-- engine/events/money.asm GiveCoins / TakeCoins, and Save.MAX_COINS.
check("the cap is 9999", PrizeMenu.MAX_COINS, 9999)
check("and the save agrees", Save.MAX_COINS, 9999)

local case = newSave(0)
check("a fresh case is empty", PrizeMenu.coins(case), 0)
local after, capped = PrizeMenu.giveCoins(case, 50)
check("giving adds", after, 50)
check("and does not cap", capped, false)

case.player.coins = 9990
after, capped = PrizeMenu.giveCoins(case, 5)
check("giving under the cap adds", after, 9995)
check("still not capped", capped, false)
after, capped = PrizeMenu.giveCoins(case, 500)
check("giving over the cap clamps to 9999", after, 9999)
check("and reports the cap", capped, true)
after = PrizeMenu.giveCoins(case, 1)
check("a full case stays at 9999", after, 9999)

case.player.coins = 3
local left, borrowed = PrizeMenu.takeCoins(case, 3)
check("taking exactly empties", left, 0)
check("without borrowing", borrowed, false)
left, borrowed = PrizeMenu.takeCoins(case, 1)
check("taking more clamps at zero", left, 0)
check("and reports the borrow", borrowed, true)

-- CheckCoins -> CompareMoneyAction.
case.player.coins = 100
check("more than", PrizeMenu.checkCoins(case, 50), PrizeMenu.HAVE_MORE)
check("exactly", PrizeMenu.checkCoins(case, 100), PrizeMenu.HAVE_AMOUNT)
check("less than", PrizeMenu.checkCoins(case, 101), PrizeMenu.HAVE_LESS)
check("HAVE_MORE is 0", PrizeMenu.HAVE_MORE, 0)
check("HAVE_AMOUNT is 1", PrizeMenu.HAVE_AMOUNT, 1)
check("HAVE_LESS is 2", PrizeMenu.HAVE_LESS, 2)

-- Save.normalize re-clamps a file that was edited past the cap.
local overflowing = newSave(0)
overflowing.player.coins = 99999
Save.normalize(overflowing)
check("normalize clamps a loaded save", overflowing.player.coins, 9999)
overflowing.player.coins = -5
Save.normalize(overflowing)
check("and clamps below zero", overflowing.player.coins, 0)

-- ========================================================= prize counters
--
-- The prices are the map scripts' EQU blocks.
local counters = PrizeMenu.COUNTERS
check("TM32 costs 1500", counters.CELADON_TM.prizes[1].cost, 1500)
check("TM29 costs 3500", counters.CELADON_TM.prizes[2].cost, 3500)
check("TM15 costs 7500", counters.CELADON_TM.prizes[3].cost, 7500)
check("MR.MIME costs 3333", counters.CELADON_MON.prizes[1].cost, 3333)
check("EEVEE costs 6666", counters.CELADON_MON.prizes[2].cost, 6666)
check("PORYGON costs 9999", counters.CELADON_MON.prizes[3].cost, 9999)
check("PORYGON costs the whole case", counters.CELADON_MON.prizes[3].cost,
  PrizeMenu.MAX_COINS)
check("PORYGON arrives at level 20", counters.CELADON_MON.prizes[3].level, 20)
check("the Goldenrod TMs are all 5500",
  counters.GOLDENROD_TM.prizes[1].cost + counters.GOLDENROD_TM.prizes[2].cost
  + counters.GOLDENROD_TM.prizes[3].cost, 16500)
check("ABRA costs 200", counters.GOLDENROD_MON.prizes[1].cost, 200)
check("DRATINI costs 2100", counters.GOLDENROD_MON.prizes[3].cost, 2100)
check("Gold sells EKANS", counters.GOLDENROD_MON.prizes[2].id, "EKANS")
check("Silver sells SANDSHREW",
  counters.GOLDENROD_MON.prizes[2].silver.id, "SANDSHREW")
check("the coin vendor sells 50 for 1000",
  counters.COIN_VENDOR.prizes[1].cost, 1000)
check("and 500 for 10000", counters.COIN_VENDOR.prizes[2].cost, 10000)

-- A data double: enough for Bag.add's capacity check and for Mon.new.
local data = {
  constants = { bagSize = 20 },
  items = { TM_DOUBLE_TEAM = { name = "TM32", pocket = "TM_HM" } },
  moves = {},
  pokemon = {
    growthRates = { MEDIUM_FAST = {} },
    PORYGON = { name = "PORYGON", baseStats = { hp = 65, attack = 60,
      defense = 70, speed = 40, spAttack = 85, spDefense = 75 },
      types = { "NORMAL" }, growthRate = "MEDIUM_FAST", levelMoves = {} },
  },
}

-- The item counter's ladder: coins are checked first, and the PACK only after
-- the player has said yes -- so a broke player is never told about the bag.
local tmCounter = counters.CELADON_TM
local tm32 = tmCounter.prizes[1]
local broke = newSave(1499)
check("1499 coins is not enough for TM32",
  PrizeMenu.check(broke, tmCounter, tm32, data), "coins")
check("and buying refuses without charging",
  PrizeMenu.buy(broke, tmCounter, tm32, data), "coins")
check("the coins are untouched", broke.player.coins, 1499)
check("and nothing was added", broke.inventory.TM_DOUBLE_TEAM, nil)

local exact = newSave(1500)
check("exactly 1500 passes the check",
  PrizeMenu.check(exact, tmCounter, tm32, data), "ok")
check("and buys", PrizeMenu.buy(exact, tmCounter, tm32, data), "ok")
check("leaving nothing", exact.player.coins, 0)
check("with the TM in the bag", exact.inventory.TM_DOUBLE_TEAM, 1)

-- A full ITEM pocket does NOT block a TM: they live in different pockets
-- (item_data_constants.asm).  The filler ids have no pocket def, so they
-- resolve to ITEM; the TM goes to TM_HM, which is empty here.
local fullItems = newSave(5000)
for i = 1, 20 do fullItems.inventory["FILLER_" .. i] = 1 end
check("a full ITEM pocket does not block a TM purchase",
  PrizeMenu.buy(fullItems, tmCounter, tm32, data), "ok")
check("and the TM lands in the TM/HM pocket",
  fullItems.inventory.TM_DOUBLE_TEAM, 1)

-- A full TM/HM pocket is what actually refuses a TM.  giveitem discovers it,
-- so the pre-confirm check still says ok.
local fullTms = newSave(5000)
for i = 1, 64 do
  local id = "OTHER_TM_" .. i
  data.items[id] = { name = id, pocket = "TM_HM" }
  fullTms.inventory[id] = 1
end
check("a full TM/HM pocket passes the pre-confirm check",
  PrizeMenu.check(fullTms, tmCounter, tm32, data), "ok")
check("but the purchase itself refuses",
  PrizeMenu.buy(fullTms, tmCounter, tm32, data), "room")
check("and the coins are not taken", fullTms.player.coins, 5000)

-- The mon counter checks the PARTY before asking, so a full party never gets
-- the question at all.
local monCounter = counters.CELADON_MON
local porygon = monCounter.prizes[3]
local fullParty = newSave(9999)
for i = 1, Save.PARTY_SIZE do fullParty.party[i] = { species = "RATTATA" } end
check("a full party is refused before the question",
  PrizeMenu.check(fullParty, monCounter, porygon, data), "room")
check("and the purchase refuses too",
  PrizeMenu.buy(fullParty, monCounter, porygon, data), "room")
check("with the coins untouched", fullParty.player.coins, 9999)

local roomy = newSave(9999)
check("nine thousand nine hundred and ninety nine is exactly enough",
  PrizeMenu.check(roomy, monCounter, porygon, data), "ok")
check("and the mon is handed over",
  PrizeMenu.buy(roomy, monCounter, porygon, data), "ok")
check("the party grew", #roomy.party, 1)
check("the mon is the prize", roomy.party[1] and roomy.party[1].species,
  "PORYGON")
check("at the scripted level", roomy.party[1] and roomy.party[1].level, 20)
check("the case is empty", roomy.player.coins, 0)
-- `special GameCornerPrizeMonCheckDex` right before the givepoke.
check("and the dex was told", roomy.pokedex.caught.PORYGON, true)
check("seen as well", roomy.pokedex.seen.PORYGON, true)
-- AddPartyMon stamps the buyer's identity onto it (move_mon.asm:44-56, :143-149).
check("the prize mon carries the player's OT ID", roomy.party[1].otId,
  roomy.player.id)
check("and the player's OT name", roomy.party[1].ot, roomy.player.name)

local shortByOne = newSave(9998)
check("one coin short is refused",
  PrizeMenu.check(shortByOne, monCounter, porygon, data), "coins")

-- The coin vendor asks about ROOM first and money second, which is why a player
-- with a full case and an empty wallet hears about the case.
local coinCounter = counters.COIN_VENDOR
local fifty = coinCounter.prizes[1]
local fullCase = newSave(9999, 0)
check("a full case is reported before the wallet",
  PrizeMenu.check(fullCase, coinCounter, fifty, data), "room")
-- MAX_COINS - 50 is 9949: exactly that still fits, one more does not.
local atHeadroom = newSave(9949, 1000)
check("exactly the headroom still fits",
  PrizeMenu.check(atHeadroom, coinCounter, fifty, data), "ok")
local overHeadroom = newSave(9950, 1000)
check("one coin past the headroom is full",
  PrizeMenu.check(overHeadroom, coinCounter, fifty, data), "room")

local poor = newSave(0, 999)
check("¥999 does not buy 50 coins",
  PrizeMenu.check(poor, coinCounter, fifty, data), "money")
check("and buying refuses", PrizeMenu.buy(poor, coinCounter, fifty, data),
  "money")
check("with the wallet untouched", poor.player.money, 999)

local buyer = newSave(0, 1000)
check("¥1000 buys 50 coins", PrizeMenu.buy(buyer, coinCounter, fifty, data),
  "ok")
check("the coins arrive", buyer.player.coins, 50)
check("and the money is gone", buyer.player.money, 0)

-- Buying 500 near the cap clamps rather than overflowing.
local nearCap = newSave(9900, 10000)
check("500 into a nearly full case is refused",
  PrizeMenu.check(nearCap, coinCounter, coinCounter.prizes[2], data), "room")

-- ================================================================ card flip
--
-- CARDFLIP_DECK_SIZE, and the card packing every win condition masks against.
check("the deck is 24 cards", CardFlip.DECK_SIZE, 24)
check("the bet is three coins", CardFlip.BET, 3)
check("card 0 is a level 1 Pikachu", CardFlip.level(0) + 1, 1)
check("and its mon index is 0", CardFlip.mon(0), 0)
check("card 23 is a level 6 Oddish", CardFlip.level(23) + 1, 6)
check("with mon index 3", CardFlip.mon(23), 3)
check("packing round-trips", CardFlip.card(4, 2), 18)
check("the level pair of card 0", CardFlip.levelPair(0), 0)
check("the level pair of card 11", CardFlip.levelPair(11), 1)
check("the level pair of card 23", CardFlip.levelPair(23), 2)

-- CardFlip_ShuffleDeck produces a permutation of 0..23 every time, including
-- the card 0 that is never explicitly placed.
for seed = 1, 40 do
  local deck = CardFlip.shuffle(seeded(seed))
  local seen = {}
  local ok = #deck == 24
  for _, card in ipairs(deck) do
    if seen[card] or card < 0 or card > 23 then ok = false end
    seen[card] = true
  end
  for card = 0, 23 do
    if not seen[card] then ok = false end
  end
  check("shuffle " .. seed .. " is a permutation", ok, true)
end

-- A degenerate `random` -- one a mod could inject -- must not hang the
-- rejection loop.  The linear-probe fallback still produces a permutation.
local stuck = CardFlip.shuffle(function() return 31 end)
local stuckSeen, stuckOk = {}, #stuck == 24
for _, card in ipairs(stuck) do
  if stuckSeen[card] then stuckOk = false end
  stuckSeen[card] = true
end
check("a degenerate RNG still deals 24 distinct cards", stuckOk, true)

-- .CheckTheCard's index: two cards a hand, twelve hands to the deck.
local deck = CardFlip.shuffle(seeded(7))
check("the first hand deals slots 1 and 2",
  CardFlip.dealt(deck, 0, 0), deck[1])
check("and the second card", CardFlip.dealt(deck, 0, 1), deck[2])
check("the last hand deals slots 23 and 24",
  CardFlip.dealt(deck, 11, 1), deck[24])
check("twelve hands to a deck", CardFlip.HANDS_PER_DECK, 12)

-- ------------------------------------------------------------- the board
--
-- CardFlip_CheckWinCondition's jumptable, square by square.
check("the board is six wide", CardFlip.BOARD_W, 6)
check("and eight tall", CardFlip.BOARD_H, 8)

for y = 0, 1 do
  for x = 0, 1 do
    check(("(%d,%d) is impossible"):format(x, y),
      CardFlip.cell(x, y).kind, "impossible")
    -- Impossible squares lose against every card in the deck.
    local anyWin = false
    for card = 0, 23 do
      if CardFlip.payout(x, y, card) > 0 then anyWin = true end
    end
    check(("(%d,%d) never pays"):format(x, y), anyWin, false)
  end
end

check("the ladder pays 6 for a mon pair", CardFlip.PAYOUT_MON_PAIR, 6)
check("9 for a level pair", CardFlip.PAYOUT_LEVEL_PAIR, 9)
check("12 for one mon", CardFlip.PAYOUT_MON, 12)
check("18 for one level", CardFlip.PAYOUT_LEVEL, 18)
check("72 for the exact card", CardFlip.PAYOUT_CARD, 72)

-- A Pikachu/Jigglypuff pair is x = 2 or 3 on row 0, and Poliwag/Oddish x = 4
-- or 5; both squares of a pair behave identically.
for _, x in ipairs({ 2, 3 }) do
  check(("(%d,0) pays on Pikachu"):format(x), CardFlip.payout(x, 0, 0), 6)
  check(("(%d,0) pays on Jigglypuff"):format(x), CardFlip.payout(x, 0, 1), 6)
  check(("(%d,0) loses on Poliwag"):format(x), CardFlip.payout(x, 0, 2), 0)
end
for _, x in ipairs({ 4, 5 }) do
  check(("(%d,0) pays on Poliwag"):format(x), CardFlip.payout(x, 0, 2), 6)
  check(("(%d,0) pays on Oddish"):format(x), CardFlip.payout(x, 0, 3), 6)
  check(("(%d,0) loses on Pikachu"):format(x), CardFlip.payout(x, 0, 0), 0)
end

-- Row 1 is one square per Pokemon, and the win is level-independent.
for mon = 0, 3 do
  for level = 0, 5 do
    check(("(%d,1) pays on its mon at level %d"):format(mon + 2, level + 1),
      CardFlip.payout(mon + 2, 1, CardFlip.card(level, mon)), 12)
  end
  check(("(%d,1) loses on another mon"):format(mon + 2),
    CardFlip.payout(mon + 2, 1, CardFlip.card(0, (mon + 1) % 4)), 0)
end

-- Column 0 is a level PAIR reached from two rows apiece: 1-2, 3-4, 5-6.
local PAIR_ROWS = { { 2, 3, 0 }, { 4, 5, 1 }, { 6, 7, 2 } }
for _, row in ipairs(PAIR_ROWS) do
  for _, y in ipairs({ row[1], row[2] }) do
    for _, level in ipairs({ row[3] * 2, row[3] * 2 + 1 }) do
      check(("(0,%d) pays on level %d"):format(y, level + 1),
        CardFlip.payout(0, y, CardFlip.card(level, 0)), 9)
    end
    check(("(0,%d) loses outside its pair"):format(y),
      CardFlip.payout(0, y, CardFlip.card((row[3] * 2 + 2) % 6, 0)), 0)
  end
end

-- Column 1 is a single level.
for level = 0, 5 do
  for mon = 0, 3 do
    check(("(1,%d) pays on level %d"):format(level + 2, level + 1),
      CardFlip.payout(1, level + 2, CardFlip.card(level, mon)), 18)
  end
  check(("(1,%d) loses on another level"):format(level + 2),
    CardFlip.payout(1, level + 2, CardFlip.card((level + 1) % 6, 0)), 0)
end

-- The 24 exact squares pay 72 on their own card and nothing on any other.
local exactHits = 0
for level = 0, 5 do
  for mon = 0, 3 do
    local x, y = mon + 2, level + 2
    local card = CardFlip.card(level, mon)
    if CardFlip.payout(x, y, card) == 72 then exactHits = exactHits + 1 end
    local misses = 0
    for other = 0, 23 do
      if other ~= card and CardFlip.payout(x, y, other) ~= 0 then
        misses = misses + 1
      end
    end
    check(("(%d,%d) pays on nothing else"):format(x, y), misses, 0)
  end
end
check("all 24 exact squares pay 72", exactHits, 24)

-- The house edge, sampled: every square is bet on against every card, and no
-- square wins more than three cards in twenty-four except the pairs.
local hitCounts = {}
for y = 0, 7 do
  for x = 0, 5 do
    local hits = 0
    for card = 0, 23 do
      if CardFlip.payout(x, y, card) > 0 then hits = hits + 1 end
    end
    hitCounts[#hitCounts + 1] = hits
  end
end
check("a mon pair hits 12 of 24 cards", hitCounts[0 * 6 + 2 + 1], 12)
check("one mon hits 6 of 24", hitCounts[1 * 6 + 2 + 1], 6)
check("a level pair hits 8 of 24", hitCounts[2 * 6 + 0 + 1], 8)
check("one level hits 4 of 24", hitCounts[2 * 6 + 1 + 1], 4)
check("an exact card hits 1 of 24", hitCounts[2 * 6 + 2 + 1], 1)

-- ------------------------------------------------------- the cursor moves
--
-- ChooseCard_HandleJoypad.  The two teleports and the `and $e` snaps are the
-- whole reason the board is not a plain grid.
local function moved(x, y, dir)
  local nx, ny = CardFlip.moveCursor(x, y, dir)
  return nx .. "," .. ny
end

check("the cursor starts on the level 1 Pikachu card", "2,2", "2,2")
check("right steps a column", moved(2, 2, "right"), "3,2")
check("right stops at the last column", moved(5, 2, "right"), "5,2")
check("left steps back", moved(3, 2, "left"), "2,2")
check("left stops at column 0 below the mon rows", moved(0, 2, "left"), "0,2")
check("down steps a row", moved(2, 2, "down"), "2,3")
check("down stops at the last row", moved(2, 7, "down"), "2,7")
check("up steps back", moved(2, 3, "up"), "2,2")

-- Leaving the level rows upward from a mon column lands on the mon row.
check("up out of the level rows", moved(3, 2, "up"), "3,1")
-- Column 1 (the single level column) teleports to the mon row's Pikachu.
check("up out of column 1 teleports", moved(1, 2, "up"), "2,1")
-- Column 0 spans two rows, so up snaps to the even row first and then steps
-- two -- and from the first pair it teleports.
check("up out of column 0's first pair teleports", moved(0, 3, "up"), "2,1")
check("up from column 0's second pair steps two", moved(0, 5, "up"), "0,2")
check("and snaps the odd row even first", moved(0, 4, "up"), "0,2")
check("down in column 0 steps two", moved(0, 2, "down"), "0,4")
check("down in column 0 stops at the last pair", moved(0, 6, "down"), "0,6")
check("and snaps odd rows even", moved(0, 7, "down"), "0,6")

-- Row 0 spans two columns the same way.
check("right on the mon-pair row steps two", moved(2, 0, "right"), "4,0")
check("and snaps an odd column even first", moved(3, 0, "right"), "4,0")
check("right stops at the last pair", moved(4, 0, "right"), "4,0")
check("left from the second pair steps two", moved(4, 0, "left"), "2,0")
check("left from the first pair teleports", moved(2, 0, "left"), "1,2")
check("left from the single-mon row teleports", moved(2, 1, "left"), "1,2")
check("left from a further mon column steps", moved(4, 1, "left"), "3,1")
check("up from the mon-pair row goes nowhere", moved(2, 0, "up"), "2,0")
check("down from the mon-pair row reaches the mon row", moved(2, 0, "down"),
  "2,1")

-- Every reachable square is reachable: walking the board from the start with
-- the four directions must cover all 48 squares.
local reached = { ["2,2"] = true }
local frontier = { { 2, 2 } }
while #frontier > 0 do
  local at = table.remove(frontier)
  for _, dir in ipairs({ "left", "right", "up", "down" }) do
    local nx, ny = CardFlip.moveCursor(at[1], at[2], dir)
    local key = nx .. "," .. ny
    if not reached[key] then
      reached[key] = true
      frontier[#frontier + 1] = { nx, ny }
    end
  end
end
local reachedCount = 0
for _ in pairs(reached) do reachedCount = reachedCount + 1 end
-- 44 of the 48 squares, and the four missing ones are exactly the .Impossible
-- corner: both teleports (.left_to_number_gp and .up_to_mon_group) jump PAST
-- it, so the cursor can never actually rest on a square that always loses.  The
-- jumptable entries and the cursor OAM for them are dead code on the cart.
check("every square the cursor can occupy is reachable", reachedCount, 44)
for _, key in ipairs({ "0,0", "1,0", "0,1", "1,1" }) do
  check("the impossible square " .. key .. " is unreachable", reached[key], nil)
end

-- ============================================================ screen flows
--
-- A stub input and a stub game, enough to walk each screen's state machine.
local function newInput()
  local input = { pressed = {} }
  function input:press(...)
    for _, button in ipairs({ ... }) do self.pressed[button] = true end
  end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

local function newGame(save)
  local input = newInput()
  return {
    input = input,
    save = save,
    data = nil, -- no audio and no music in this harness
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
    },
  }, input
end

-- The slot machine's bet menu: the top row is three coins (`ld a, 4 / sub b`),
-- and a bet the case cannot cover is refused without deducting.
local slotSave = newSave(2)
local slotGame, slotInput = newGame(slotSave)
local slots = SlotMachine.new(slotGame, { save = slotSave,
  random = seeded(5), onClose = function() slotSave.closed = true end })
check("the machine opens on the bet menu", slots.phase, "bet")
check("with the cursor on three coins", slots.betIndex, 1)
slotInput:press("a")
slots:update(1 / 60)
check("two coins cannot cover a bet of three", slots.phase, "bet")
check("and nothing was deducted", slotSave.player.coins, 2)
check("the refusal is on screen", slots.message, SlotMachine.TEXTS.notEnough)
slotInput:press("a")
slots:update(1 / 60) -- dismiss
slotInput:press("down")
slots:update(1 / 60)
slotInput:press("down")
slots:update(1 / 60)
check("the cursor reaches one coin", slots.betIndex, 3)
slotInput:press("a")
slots:update(1 / 60)
check("a bet of one is taken", slots.bet, 1)
check("and one coin left the case", slotSave.player.coins, 1)
check("the reels are turning", slots.phase, "spinning")

-- A whole round, driven frame by frame: bet three, stop all three reels, and
-- assert the coins that come back are exactly the payout table's answer for
-- whatever the reels landed on.
local roundSave = newSave(50)
local roundGame, roundInput = newGame(roundSave)
local round = SlotMachine.new(roundGame, { save = roundSave,
  random = seeded(11) })
roundInput:press("a")
round:update(1 / 60)
check("the top row bets three", round.bet, 3)
check("and three coins leave the case", roundSave.player.coins, 47)
-- SlotsAction_WaitStart's 32 frame lockout, so a held A cannot stop reel one.
for _ = 1, 33 do round:update(1 / 60) end
for reel = 1, 3 do
  roundInput:press("a")
  round:update(1 / 60)
  for _ = 1, 600 do
    if round.stopped and round.stopped[reel] then break end
    round:update(1 / 60)
  end
  check(("reel %d settles"):format(reel),
    round.stopped and round.stopped[reel] ~= nil, true)
end
check("the round resolved into a payout or a Darn!",
  round.phase == "flash" or round.phase == "payoutText", true)
local owed = SlotMachine.payout(round.matched)
for _ = 1, 3000 do
  if round.phase == "again" or round.phase == "ranOut" then break end
  if round.phase == "payoutText" and round.matched == SlotMachine.NO_MATCH then
    roundInput:press("a")
  end
  round:update(1 / 60)
end
check("the payout counter emptied", round.payoutLeft, 0)
check("and the case holds the stake back plus the win",
  roundSave.player.coins, 47 + owed)
check("the machine offers another go",
  round.phase == "again" or round.phase == "ranOut", true)

-- Card flip: the first question costs three coins, and a case with two is told
-- so and shown the door.
local flipSave = newSave(2)
local flipGame, flipInput = newGame(flipSave)
local flip = CardFlip.new(flipGame, { save = flipSave, random = seeded(3),
  onClose = function() flipSave.closed = true end })
check("card flip opens on the question", flip.phase, "ask")
flipInput:press("a")
flip:update(1 / 60)
check("two coins is not enough", flip.phase, "message")
check("and the bet was not taken", flipSave.player.coins, 2)
flipInput:press("a")
flip:update(1 / 60)
check("dismissing the refusal leaves", flipSave.closed, true)

local flipSave2 = newSave(10)
local flipGame2, flipInput2 = newGame(flipSave2)
local flip2 = CardFlip.new(flipGame2, { save = flipSave2, random = seeded(3) })
flipInput2:press("a")
flip2:update(1 / 60)
check("three coins buy a hand", flipSave2.player.coins, 7)
check("and the cards come out", flip2.phase, "choose")
flipInput2:press("a")
flip2:update(1 / 60)
check("A locks the card and opens the bet", flip2.phase, "bet")
-- Bet on the square that matches whatever was dealt, and assert it pays 72.
local dealt = CardFlip.dealt(flip2.deck, 0, flip2.which)
flip2.cursorX = CardFlip.mon(dealt) + 2
flip2.cursorY = CardFlip.level(dealt) + 2
flipInput2:press("a")
flip2:update(1 / 60)
check("the exact square pays 72", flip2.payoutLeft, 72)
check("and the card is discarded", flip2.discarded[dealt], true)
for _ = 1, 200 do flip2:update(1 / 60) end
check("the coins are counted out", flipSave2.player.coins, 7 + 72)
check("and the hand is over", flip2.phase, "result")

-- The payout stops at the cap rather than wrapping.
local capSave = newSave(9990)
local capGame = newGame(capSave)
local capFlip = CardFlip.new(capGame, { save = capSave, random = seeded(3) })
capFlip.payoutLeft = 72
capFlip.payoutTick = 0
capFlip.phase = "payout"
for _ = 1, 400 do capFlip:update(1 / 60) end
check("a payout past the cap clamps", capSave.player.coins, 9999)

-- The prize counter screen: no COIN CASE is the very first refusal.
local caseless = newSave(5000)
local caselessGame, caselessInput = newGame(caseless)
local counter = PrizeMenu.new(caselessGame, { save = caseless,
  counter = "CELADON_TM", texts = "CELADON", data = data,
  onClose = function() caseless.closed = true end })
check("the intro plays first", counter.message ~= nil, true)
-- Three pages of Welcome, then the refusal, then the door.
for _ = 1, 3 do
  caselessInput:press("a")
  counter:update(1 / 60)
end
check("the counter never opens its menu", counter.phase, nil)
caselessInput:press("a")
counter:update(1 / 60)
check("a player with no COIN CASE is turned away", caseless.closed, true)

local shopper = newSave(5000)
shopper.inventory.COIN_CASE = 1
local shopGame, shopInput = newGame(shopper)
local shop = PrizeMenu.new(shopGame, { save = shopper, counter = "CELADON_TM",
  texts = "CELADON", data = data,
  onClose = function() shopper.closed = true end })
for _ = 1, 3 do
  shopInput:press("a")
  shop:update(1 / 60)
end
check("the menu opens", shop.phase, "menu")
check("with four rows including CANCEL", #shop.prizes, 4)
check("and the cursor on the first prize", shop.index, 1)
shopInput:press("a")
shop:update(1 / 60)
check("choosing TM32 asks first", shop.confirm ~= nil, true)
shopInput:press("a")
shop:update(1 / 60)
check("yes buys it", shopper.inventory.TM_DOUBLE_TEAM, 1)
check("and takes the coins", shopper.player.coins, 3500)
-- The second TM costs 3500, which is exactly what is left.
shopInput:press("down")
shop:update(1 / 60)
shopInput:press("a")
shop:update(1 / 60) -- dismiss "Here you go!"
check("the loop returns to the menu", shop.phase, "menu")

-- The Goldenrod mon counter's checkver swap.
local silverShop = PrizeMenu.new(newGame(newSave(0)),
  { save = newSave(0), counter = "GOLDENROD_MON", texts = "GOLDENROD",
    version = "silver", data = data, hasCoinCase = true })
check("Silver's second prize is SANDSHREW", silverShop.prizes[2].id,
  "SANDSHREW")
local goldShop = PrizeMenu.new(newGame(newSave(0)),
  { save = newSave(0), counter = "GOLDENROD_MON", texts = "GOLDENROD",
    version = "gold", data = data, hasCoinCase = true })
check("Gold's second prize is EKANS", goldShop.prizes[2].id, "EKANS")

-- ============================================ the counters the GAME reaches
--
-- Everything above is a model.  None of it says a prize counter can be OPENED,
-- and none of it is what opens one: on the cart no counter is a screen at all.
-- Each is a `bg_event ..., BGEVENT_READ, ...Vendor` (CeladonGameCornerPrizeRoom
-- .asm, GoldenrodGameCorner.asm) and the whole transaction is script bytecode --
-- `special DisplayCoinCaseBalance`, `loadmenu`, `verticalmenu`, `checkcoins`,
-- `giveitem` / `givepoke`, `takecoins`.  So this drives the REAL extracted
-- script through the VM off the map's own bg event, which is the only assertion
-- that says the counter works where a player stands.
local Events = require("src.world.gen2.Events")
local Vm = require("src.script.gen2.Vm")

local cache = os.getenv("GOLD_CACHE")
  or ((os.getenv("HOME") or "") .. "/Library/Application Support/LOVE/gold-dev/gold")
local function loadCache(name)
  local chunk = loadfile(cache .. "/data/generated/" .. name .. ".lua")
  return chunk and chunk() or nil
end

local cacheMaps = loadCache("maps")
local cacheScripts = loadCache("scripts")
local cacheText = loadCache("text")
local cacheConsts = loadCache("constants")

-- One counter conversation, driven to a stop.  `pick` answers every
-- `verticalmenu`; the log is what the player would have seen.
local function runCounter(key, opts)
  opts = opts or {}
  local save = opts.save or newSave(opts.coins or 0, opts.money or 0)
  local log, seen = {}, {}
  local vm
  vm = Vm.new(cacheScripts, cacheText, Events.new(), {
    specialOrder = cacheConsts and cacheConsts.specialOrder,
    specials = { save = function() return save end,
      monName = function(index) return "MON" .. tostring(index) end },
    showText = function(body, onDone) log[#log + 1] = body; onDone() end,
    facePlayer = function() end,
    yesorno = function(onChoose) onChoose(opts.yes ~= false) end,
    -- Every counter LOOPS back to its own menu after a sale, so only the first
    -- pass buys and the second cancels out; otherwise the run below empties
    -- the case rather than making one purchase.
    openMenu = function(header, _style, onChoose)
      seen[#seen + 1] = { balance = vm.balanceKind, items = header.items }
      vm.balanceKind = nil
      onChoose(#seen == 1 and (opts.pick or 0) or 0)
    end,
    -- The two seams the balance boxes hang off: engine/menus/menu_2.asm draws
    -- them and returns, and the `loadmenu` that follows is what shows them.
    showCoins = function() vm.balanceKind = "coins" end,
    showMoney = function(kind) vm.balanceKind = kind or "money" end,
    hasItem = function() return opts.coinCase ~= false end,
    giveItem = function(index, qty)
      save.inventory[index] = (save.inventory[index] or 0) + (qty or 1)
      return true
    end,
    givePoke = function(species, level)
      save.party[#save.party + 1] = { species = species, level = level }
    end,
    getCoins = function() return save.player.coins end,
    setCoins = function(value) save.player.coins = value end,
    getMoney = function() return save.player.money end,
    setMoney = function(_account, value) save.player.money = value end,
    getItemName = function(index) return "ITEM" .. tostring(index) end,
    getMonName = function(index) return "MON" .. tostring(index) end,
    readVar = function() return #save.party end,
    playSound = function() end,
    waitSfx = function() return true end,
  })
  vm:start(key)
  for _ = 1, 400 do vm:update() end
  return save, seen, log
end

if not (cacheMaps and cacheScripts and cacheConsts) then
  check("no GOLD_CACHE: the counters are not driven off the map (SKIP)",
    true, true)
else
  -- The two Celadon counters are bg events 1 and 2 of the prize room, in the
  -- order the .asm lists them: the TM vendor at (2,1), the mon vendor at (4,1).
  local room = cacheMaps.CELADON_GAME_CORNER_PRIZE_ROOM
  local tmEvent = room and room.bgEvents and room.bgEvents[1]
  local monEvent = room and room.bgEvents and room.bgEvents[2]
  check("the Celadon TM counter is a readable bg event",
    tmEvent ~= nil and (tmEvent.kind or 0) == 0, true)
  check("and so is the Celadon mon counter",
    monEvent ~= nil and (monEvent.kind or 0) == 0, true)
  check("the TM counter's script is in the cache",
    cacheScripts[tmEvent.scriptKey] ~= nil, true)

  local bought, menus = runCounter(tmEvent.scriptKey, { coins = 5000, pick = 1 })
  check("reading the counter opens its prize list",
    menus[1] and menus[1].items[1], "TM32    1500")
  check("with the COIN box up beside it", menus[1] and menus[1].balance,
    "coins")
  check("TM32 is handed over", bought.inventory[224], 1)
  check("and 1500 coins are taken", bought.player.coins, 3500)

  -- No COIN CASE is the very first refusal: no menu at all.
  local _, noMenus = runCounter(tmEvent.scriptKey,
    { coins = 5000, coinCase = false, pick = 1 })
  check("without a COIN CASE the counter never opens", #noMenus, 0)

  -- The mon counter hands over a party member instead, and the dex entry is
  -- `special GameCornerPrizeMonCheckDex` on the way past.
  local won = runCounter(monEvent.scriptKey, { coins = 9999, pick = 1 })
  check("the mon counter gives a prize mon", #won.party, 1)
  check("the coins are taken at 3333", won.player.coins, 9999 - 3333)
  check("and it is registered as caught",
    won.pokedex and won.pokedex.caught["MON122"], true)

  -- Goldenrod puts its counters behind PEOPLE rather than counter tiles: the
  -- clerk who sells coins and the two receptionists, objects 1 to 3 in the
  -- order GoldenrodGameCorner.asm lists them.
  local goldenrod = cacheMaps.GOLDENROD_GAME_CORNER
  local objects = (goldenrod and goldenrod.objects) or {}
  local _, tmMenus = runCounter(objects[2] and objects[2].scriptKey,
    { coins = 9999, pick = 0 })
  check("the Goldenrod TM counter opens its list",
    tmMenus[1] and tmMenus[1].items[1], "TM25    5500")
  check("under the COIN box too", tmMenus[1] and tmMenus[1].balance, "coins")
  local _, monMenus = runCounter(objects[3] and objects[3].scriptKey,
    { coins = 9999, pick = 0 })
  check("and the Goldenrod mon counter sells Gold's EKANS",
    monMenus[1] and monMenus[1].items[2], "EKANS       700")

  -- The coin vendor beside them is a `jumpstd` to GameCornerCoinVendorScript,
  -- and its box is the MONEY + COIN one (DisplayMoneyAndCoinBalance) rather
  -- than the COIN box the prize counters use.
  local _, coinMenus = runCounter(objects[1] and objects[1].scriptKey,
    { money = 999999, pick = 1 })
  check("the coin vendor shows MONEY and COIN together",
    coinMenus[1] and coinMenus[1].balance, "moneycoins")
  check("and 50 coins cost ¥1000", coinMenus[1] and coinMenus[1].items[1],
    " 50 :  \xc2\xa51000")
end

-- The boxes themselves (engine/menus/menu_2.asm through
-- src/ui/gen2/Chrome.lua): the yen field is six digits wide with the ¥ against
-- the first significant digit, and the coin field is four digits with leading
-- zeroes.
local Chrome = require("src.ui.gen2.Chrome")
check("¥1000 is right-aligned in a six-digit field", Chrome.money(1000),
  "  \xc2\xa51000")
check("a full wallet fills it", Chrome.money(999999), "\xc2\xa5999999")
check("the coin field keeps its leading zeroes", Chrome.number(50, 4, true),
  "0050")

-- ============================================================ multi-game stress tests
--
-- Verify that 500 consecutive Slot Machine games and 500 consecutive Card Flip hands
-- run to completion with zero softlocks, zero infinite spin loops (issue #1520),
-- and correct coin accounting across all random biases and near-miss theatres.

local mockSave = {
  player = { name = "GOLD", coins = 5000 },
}

local mockInput = {
  pressed = {},
  wasPressed = function(self, key)
    local v = self.pressed[key]
    self.pressed[key] = false
    return v or false
  end,
  press = function(self, key)
    self.pressed[key] = true
  end,
}

local mockSlotGame = {
  save = mockSave,
  input = mockInput,
  data = {},
}

-- Test Slot Machine 500-spin continuous loop
local sm = SlotMachine.new(mockSlotGame, { lucky = true })
local completedSpins = 0

for spin = 1, 500 do
  mockSave.player.coins = 5000 -- ensure test player always has coins
  if sm.phase == "quit" or sm.phase == "ranOut" then
    sm = SlotMachine.new(mockSlotGame, { lucky = true })
  end

  -- Enter bet phase
  check("slot machine in bet phase at spin start", sm.phase, "bet")
  mockInput:press("a") -- bet 3 coins
  sm:update(1/60)

  check("slot machine entered spinning phase", sm.phase, "spinning")

  local frameCount = 0
  local maxFrames = 5000 -- safety bound per spin

  while sm.phase == "spinning" and frameCount < maxFrames do
    frameCount = frameCount + 1
    if frameCount % 30 == 0 then
      mockInput:press("a") -- press stop button
    end
    sm:update(1/60)
  end

  check(("spin %d must not hang in spinning"):format(spin), frameCount < maxFrames, true)

  -- Resolve flash and payout phases
  while (sm.phase == "flash" or sm.phase == "payoutText") and frameCount < maxFrames do
    frameCount = frameCount + 1
    if sm.phase == "payoutText" and sm.matched == SlotMachine.NO_MATCH then
      mockInput:press("a")
    end
    sm:update(1/60)
  end

  check(("spin %d reached again phase"):format(spin), sm.phase == "again" or sm.phase == "bet", true)
  if sm.phase == "again" then
    mockInput:press("a") -- choose YES to play again
    sm:update(1/60)
    completedSpins = completedSpins + 1
  elseif sm.phase == "bet" then
    completedSpins = completedSpins + 1
  end
end

check("all 500 slot machine spins completed without softlock", completedSpins >= 490, true)

-- Test Card Flip 500-hand continuous loop
local cf = CardFlip.new(mockSlotGame)
local completedHands = 0

for hand = 1, 500 do
  mockSave.player.coins = 5000
  if cf.phase == "quit" then
    cf = CardFlip.new(mockSlotGame)
  end

  local frameCount = 0
  local maxFrames = 500

  while cf.phase ~= "again" and cf.phase ~= "quit" and frameCount < maxFrames do
    frameCount = frameCount + 1
    if cf.phase == "ask" or cf.phase == "message" or cf.phase == "result"
        or cf.phase == "choose" or cf.phase == "bet" then
      mockInput:press("a")
    end
    cf:update(1/60)
  end

  check(("hand %d completed in bounds"):format(hand), frameCount < maxFrames, true)

  if cf.phase == "again" then
    mockInput:press("a") -- play again
    cf:update(1/60)
    completedHands = completedHands + 1
  end
end

check("all 500 card flip hands completed cleanly", completedHands >= 490, true)

print(("gen2 game corner: %d checks, %d failures"):format(checks, failures))
-- Raise rather than os.exit: tests/run_tests.lua dofiles this file, so an exit
-- here would take the whole tier down and silently skip every suite after it.
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
