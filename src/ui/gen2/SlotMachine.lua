-- Gold's slot machine (engine/games/slot_machine.asm _SlotMachine), reached by
-- the `special SlotMachine` every Game Corner machine's tile script calls.
--
-- The machine is not a coin flip with a spinning picture over it.  Every spin
-- rolls a BIAS symbol out of a weighted table (Slots_InitBias), and each reel's
-- stop is then MANIPULATED toward that symbol -- or, when the spin is unbiased,
-- deliberately away from every symbol -- for up to four slots past where the
-- player's A press landed.  Reel 3 additionally has three near-miss theatres
-- (the slow advance, the Golem drops and the Chansey egg) that only ever run
-- when the first two reels already show matching SEVENs, which is what makes
-- the machine feel like it nearly paid 300 far more often than it can.
--
-- Everything that decides an outcome is a pure function here, taking a
-- `random(n) -> 0..n-1` the way src/battle/gen2 does, so a test can drive
-- thousands of seeded spins and assert the distribution.  The screen half is
-- the only part that touches love.
--
-- Layout is transcribed from the ASM's own coordinates, never laid out by eye:
--
--   .PrintCoinsAndPayout  hlcoord 5, 1 and hlcoord 11, 1, each PrintNum with
--                         PRINTNUM_LEADINGZEROS | 2 bytes, 4 digits
--   Slots_Lights*OnOff    hlcoord 3, 2 / 3, 4 / 3, 6 / 3, 8 / 3, 10, and
--                         Slots_TurnLightsOnOrOff writes the second tile of
--                         each light at +SCREEN_WIDTH/2+3 (column 16, same
--                         row) and the pair below it one row down
--   Slots_InitReelTiles   REEL_X_COORD 6, 10 and 14 * TILE_WIDTH -- so the
--                         three reels sit in tile columns 6-7, 10-11, 14-15
--   Slots_UpdateReelPositionAndOAM
--                         wCurReelYCoord starts at 10 * TILE_WIDTH and steps
--                         up two tiles per symbol.  OAM y is 16px above the
--                         screen, so the bottom symbol covers tile rows 8-9,
--                         the middle 6-7, the top 4-5, and a fourth symbol
--                         peeks in at rows 2-3
--   Slots_AskBet          menu_coords 14, 10, 19, 17 with STATICMENU_CURSOR and
--                         no STATICMENU_NO_TOP_SPACING, so GetMenuTextStartCoord
--                         puts " 3" at (16,12) with the cursor in column 15 and
--                         the three labels two rows apart
--   Slots_PayoutText      .Text_PrintPayout lays the matched symbol's four
--                         tiles at (2,13),(3,13),(2,14),(3,14) and the ▼ at
--                         (18,17)
--
-- Reel art (gfx/slots/slots_1..3.2bpp.lz + slots.tilemap) is extracted into
-- assets/generated/slots/ when the Gold/Silver manifest carries Slots*LZ.
-- Until those files exist, drawReels falls back to labelled cells.

local Chrome = require("src.ui.gen2.Chrome")
local CoinCase = require("src.core.gen2.CoinCase")
local Sound = require("src.core.Sound")

local SlotMachine = {}
SlotMachine.__index = SlotMachine
SlotMachine.isOpaque = true

-- ------------------------------------------------------------------ symbols
--
-- The wSlotMatched constants are a `const_def 0, 4` block, so they step by four
-- and double as the index into every table that is `srl a`'d first (the payout
-- table, the payout strings).  Keeping the cart's values rather than 1..6 means
-- those halvings stay literal.
SlotMachine.SEVEN    = 0x00
SlotMachine.POKEBALL = 0x04
SlotMachine.CHERRY   = 0x08
SlotMachine.PIKACHU  = 0x0c
SlotMachine.SQUIRTLE = 0x10
SlotMachine.STARYU   = 0x14

-- SLOTS_NO_MATCH and SLOTS_NO_BIAS are both -1 ($ff in the byte).  They are
-- different things sharing a value, so they get different names here.
SlotMachine.NO_MATCH = -1
SlotMachine.NO_BIAS = -1

SlotMachine.NAMES = {
  [0x00] = "SEVEN", [0x04] = "POKEBALL", [0x08] = "CHERRY",
  [0x0c] = "PIKACHU", [0x10] = "SQUIRTLE", [0x14] = "STARYU",
}

-- What a symbol cell shows while the cart's own 2x2 reel tiles are unextracted.
SlotMachine.LABELS = {
  [0x00] = "7", [0x04] = "()", [0x08] = "CH",
  [0x0c] = "PI", [0x10] = "SQ", [0x14] = "ST",
}

-- Slots_GetPayout .PayoutTable, indexed by wSlotMatched srl'd once.  The payout
-- does NOT scale with the bet in Gen 2 -- the bet buys extra LINES, not a
-- multiplier, which is the single biggest difference from Red's slots.
SlotMachine.PAYOUTS = {
  [0x00] = 300, -- SLOTS_SEVEN
  [0x04] = 50,  -- SLOTS_POKEBALL
  [0x08] = 6,   -- SLOTS_CHERRY
  [0x0c] = 8,   -- SLOTS_PIKACHU
  [0x10] = 10,  -- SLOTS_SQUIRTLE
  [0x14] = 15,  -- SLOTS_STARYU
}

function SlotMachine.payout(matched)
  if not matched or matched == SlotMachine.NO_MATCH then return 0 end
  return SlotMachine.PAYOUTS[matched] or 0
end

-- ------------------------------------------------------------------- reels
--
-- Reel1Tilemap / Reel2Tilemap / Reel3Tilemap.  REEL_SIZE is 15; the first three
-- entries are repeated at the end so Slots_GetCurrentReelState can read three
-- consecutive bytes without wrapping, which is also why the `and $f` mask below
-- is harmless for a slot the reel can actually spin to.
SlotMachine.REEL_SIZE = 15

local SEVEN, POKEBALL = 0x00, 0x04
local CHERRY, PIKACHU, SQUIRTLE, STARYU = 0x08, 0x0c, 0x10, 0x14

SlotMachine.REELS = {
  -- Reel1Tilemap: three SEVENs' worth of structure -- SEVEN at 0 and 5, and a
  -- POKEBALL where the third SEVEN would be, at 10.
  { SEVEN, CHERRY, STARYU, PIKACHU, SQUIRTLE,
    SEVEN, CHERRY, STARYU, PIKACHU, SQUIRTLE,
    POKEBALL, CHERRY, STARYU, PIKACHU, SQUIRTLE,
    SEVEN, CHERRY, STARYU },
  -- Reel2Tilemap: one SEVEN, at 0, and POKEBALLs at 5 and 10.
  { SEVEN, PIKACHU, CHERRY, SQUIRTLE, STARYU,
    POKEBALL, PIKACHU, CHERRY, SQUIRTLE, STARYU,
    POKEBALL, PIKACHU, CHERRY, SQUIRTLE, STARYU,
    SEVEN, PIKACHU, CHERRY },
  -- Reel3Tilemap: one SEVEN at 0 and one POKEBALL at 10.
  { SEVEN, PIKACHU, CHERRY, SQUIRTLE, STARYU,
    PIKACHU, CHERRY, SQUIRTLE, STARYU, PIKACHU,
    POKEBALL, CHERRY, SQUIRTLE, STARYU, PIKACHU,
    SEVEN, PIKACHU, CHERRY },
}

-- Slots_GetCurrentReelState, byte for byte:
--
--   ld a, [REEL_POSITION] / and a / jr nz, .okay / ld a, $f
--   .okay: dec a / and $f
--
-- so slot 0 reads as if it were 15.  The mask is $f (16) while the strip is 15
-- long, which is only harmless because entries 16-18 repeat entries 1-3: a
-- position of 16 reads the same window a position of 1 does.  A SEARCH that
-- walks the position past 16 (Slots_GetNumberOfGolems does) reads a window that
-- is one slot off, and the cart depends on whatever falls out of that.
--
-- Returns bottom, middle, top -- index 0 is the BOTTOM row, which is what
-- .CheckBottomRow reading wReel1Stopped + 0 establishes.
function SlotMachine.window(strip, position)
  local a = position
  if a == 0 then a = 0x0f end
  a = (a - 1) % 16
  return strip[a + 1], strip[a + 2], strip[a + 3]
end

-- Slots_UpdateReelPositionAndOAM's tail: inc a / and $f / cp REEL_SIZE / xor a.
function SlotMachine.advance(position)
  local a = (position + 1) % 16
  if a == SlotMachine.REEL_SIZE then a = 0 end
  return a
end

-- ------------------------------------------------------------------- lines
--
-- Slots_CheckMatchedAllThreeReels' jumptable is indexed by `wSlotBet and 3`,
-- and .three FALLS THROUGH into .two, which falls through into .one.  ASM
-- fallthrough is not a branch: a bet of 3 runs all five checks on the same
-- frame, a bet of 2 runs three, a bet of 1 runs one.
--
-- Every check that hits calls .StoreResult, which OVERWRITES wSlotMatched, so
-- the LAST line checked is the one that pays.  In fallthrough order that is
-- upward diagonal, downward diagonal, bottom, top, middle -- meaning the middle
-- row wins any tie and only ONE line is ever paid.
--
-- Each row is { reel1 index, reel2 index, reel3 index }, 1 = bottom.
local UP_DIAG   = { 1, 2, 3 }
local DOWN_DIAG = { 3, 2, 1 }
local BOTTOM    = { 1, 1, 1 }
local TOP       = { 3, 3, 3 }
local MIDDLE    = { 2, 2, 2 }

SlotMachine.LINES = {
  [0] = {},
  [1] = { MIDDLE },
  [2] = { BOTTOM, TOP, MIDDLE },
  [3] = { UP_DIAG, DOWN_DIAG, BOTTOM, TOP, MIDDLE },
}

local function betLines(bet)
  return SlotMachine.LINES[(bet or 0) % 4] or {}
end

-- Slots_CheckMatchedAllThreeReels.  r1/r2/r3 are three-entry windows.
-- Returns the matched symbol, or NO_MATCH.
function SlotMachine.matchAll(bet, r1, r2, r3)
  local matched = SlotMachine.NO_MATCH
  for _, line in ipairs(betLines(bet)) do
    local a = r1[line[1]]
    if a == r3[line[3]] and a == r2[line[2]] then matched = a end
  end
  return matched
end

-- Slots_CheckMatchedFirstTwoReels.  Same jumptable, same fallthrough, but the
-- comparisons are DIFFERENT rows: with only two reels down there is no third
-- column to close a diagonal, so both diagonals and the middle row all test
-- reel 2's middle symbol.
--
--   .CheckBottomRow     r1 bottom vs r2 bottom
--   .CheckUpwardsDiag   r1 bottom vs r2 middle
--   .CheckMiddleRow     r1 middle vs r2 middle
--   .CheckDownwardsDiag r1 top    vs r2 middle
--   .CheckTopRow        r1 top    vs r2 top
--
-- Returns the building symbol (or NO_MATCH) and whether it is a SEVEN, which is
-- wFirstTwoReelsMatchingSevens -- the flag every reel-3 theatre gates on.
local TWO_LINES = {
  [0] = {},
  [1] = { { 2, 2 } },
  [2] = { { 1, 1 }, { 3, 3 }, { 2, 2 } },
  [3] = { { 1, 2 }, { 3, 2 }, { 1, 1 }, { 3, 3 }, { 2, 2 } },
}

function SlotMachine.matchFirstTwo(bet, r1, r2)
  local building = SlotMachine.NO_MATCH
  local matchingSevens = false
  for _, line in ipairs(TWO_LINES[(bet or 0) % 4] or {}) do
    if r1[line[1]] == r2[line[2]] then
      building = r1[line[1]]
      if building == SlotMachine.SEVEN then
        matchingSevens = true
      end
    end
  end
  return building, matchingSevens
end

-- ------------------------------------------------------------------- bias
--
-- Slots_InitBias.  `percent` is EQUS "* $ff / 100" (macros/data.asm) with
-- rgbasm's integer division, so "19 percent" is 48 and not 48.45 -- the tables
-- below are the bytes the assembler emits, not the percentages they read as.
--
-- The scan is `ld a, [hli] / cp c / jr nc, .done`: the first row whose
-- threshold is >= the random byte wins, so the thresholds are cumulative and
-- the last row is 100 percent = 255.
SlotMachine.BIAS_NORMAL = {
  { 1,   SEVEN },     --   1 percent - 1
  { 3,   POKEBALL },  --   1 percent + 1
  { 10,  STARYU },    --   4 percent
  { 20,  SQUIRTLE },  --   8 percent
  { 40,  PIKACHU },   --  16 percent
  { 48,  CHERRY },    --  19 percent
  { 255, SlotMachine.NO_BIAS },
}

-- The luckier table, picked when wScriptVar is non-zero on entry: the Game
-- Corner's scripts pass one machine per room in as the lucky one.
SlotMachine.BIAS_LUCKY = {
  { 2,   SEVEN },     --   1 percent
  { 3,   POKEBALL },  --   1 percent + 1
  { 8,   STARYU },    --   3 percent + 1
  { 16,  SQUIRTLE },  --   6 percent + 1
  { 30,  PIKACHU },   --  12 percent
  { 80,  CHERRY },    --  31 percent + 1
  { 255, SlotMachine.NO_BIAS },
}

-- `ld a, [wSlotBias] / and a / ret z` at the top of Slots_InitBias: a spin that
-- is ALREADY biased to SEVEN (value 0) keeps that bias without rerolling.  That
-- one instruction is the whole seven streak -- see keepSevenBias below for what
-- ends it.
function SlotMachine.initBias(currentBias, lucky, random)
  if currentBias == SlotMachine.SEVEN then return SlotMachine.SEVEN end
  local table_ = lucky and SlotMachine.BIAS_LUCKY or SlotMachine.BIAS_NORMAL
  local roll = random(256)
  for _, row in ipairs(table_) do
    if row[1] >= roll then return row[2] end
  end
  return SlotMachine.NO_BIAS
end

-- .InitGFX's tail rolls wKeepSevenBiasChance once for the whole session:
-- `call Random / and %00101010 / ret nz` leaves it FALSE 87.5% of the time.
-- Lua 5.1 has no bitwise operators, so a mask is spelled out as the bits it
-- names -- %00101010 is $2a, bits 1, 3 and 5.
local function maskIsZero(value, bits)
  for _, bit in ipairs(bits) do
    if math.floor(value / bit) % 2 == 1 then return false end
  end
  return true
end

function SlotMachine.rollKeepSevenChance(random)
  return maskIsZero(random(256), { 2, 8, 32 })
end

-- .LinedUpSevens, after the 300-coin fanfare.  A SEVEN payout usually DROPS the
-- seven bias; the chance it survives into the next spin is what makes a streak.
--
-- Oddly, the rarer session flag (wKeepSevenBiasChance = TRUE, 12.5% of visits)
-- is the one with the WORSE streak odds, 12.5% against 25% -- the ASM's own
-- comment flags this as probably-inverted, and it is transcribed as written.
function SlotMachine.keepSevenBias(keepSevenChance, random)
  -- keepSevenChance: and %0011100 ($1c, three bits) -> 1 in 8
  -- otherwise:       and %0010100 ($14, two bits)   -> 1 in 4
  local mask = keepSevenChance and { 4, 8, 16 } or { 4, 16 }
  return maskIsZero(random(256), mask)
end

-- ------------------------------------------------------------- reel stops
--
-- Each ReelAction_StopReel* runs once per SLOT (Slots_SpinReel only calls the
-- action jumptable when the spin distance's low nibble is zero), and either
-- stops the reel there or lets it turn one more slot and asks again.  Running
-- that decision to a fixed point up front gives exactly the slot the cart
-- reaches, so the screen spins toward a known stop instead of carrying the
-- whole ReelAction jumptable.
--
-- REEL_MANIP_COUNTER starts at 4 for every reel (SlotsAction_BetAndStart).
SlotMachine.MANIP_COUNTER = 4

-- The loop is bounded on the cart by the reel coming back around; the guard
-- here is a full strip plus the manipulation budget, and reaching it stops the
-- reel the way Slots_StopReel would.
local SEARCH_LIMIT = SlotMachine.REEL_SIZE * 4

-- ReelAction_StopReel1: with no bias, stop where the player pressed.  With a
-- bias, walk up to four slots looking for the biased symbol ANYWHERE in reel
-- one's three-symbol window -- even on a line the current bet does not buy.
function SlotMachine.stopReel1(position, bias)
  local strip = SlotMachine.REELS[1]
  local manip = SlotMachine.MANIP_COUNTER
  for _ = 1, SEARCH_LIMIT do
    if bias == SlotMachine.NO_BIAS or manip == 0 then return position end
    manip = manip - 1
    local a, b, c = SlotMachine.window(strip, position)
    if a == bias or b == bias or c == bias then return position end
    position = SlotMachine.advance(position)
  end
  return position
end

-- ReelAction_StopReel2: stop early once reels one and two are already building
-- the biased symbol on a line this bet buys, otherwise burn the four slots.
function SlotMachine.stopReel2(position, bias, bet, stopped1)
  local strip = SlotMachine.REELS[2]
  local manip = SlotMachine.MANIP_COUNTER
  for _ = 1, SEARCH_LIMIT do
    local window = { SlotMachine.window(strip, position) }
    local building = SlotMachine.matchFirstTwo(bet, stopped1, window)
    if building ~= SlotMachine.NO_MATCH and building == bias then
      return position
    end
    if bias == SlotMachine.NO_BIAS or manip == 0 then return position end
    manip = manip - 1
    position = SlotMachine.advance(position)
  end
  return position
end

-- ReelAction_StopReel3, and the one place the "no bias means no win" rule is
-- actually enforced:
--
--   * a line that matches the bias stops the reel dead
--   * a line that matches ANYTHING ELSE keeps the reel turning, manip counter
--     or not (`ret z` returns without stopping, it does not fall through)
--   * no line at all stops the reel, unless a bias is still being hunted and
--     the four-slot budget has not run out
function SlotMachine.stopReel3(position, bias, bet, stopped1, stopped2)
  local strip = SlotMachine.REELS[3]
  local manip = SlotMachine.MANIP_COUNTER
  for _ = 1, SEARCH_LIMIT do
    local window = { SlotMachine.window(strip, position) }
    local matched = SlotMachine.matchAll(bet, stopped1, stopped2, window)
    if matched ~= SlotMachine.NO_MATCH then
      if matched == bias then return position end
      if manip > 0 then manip = manip - 1 end
    else
      if bias == SlotMachine.NO_BIAS or manip == 0 then return position end
      manip = manip - 1
    end
    position = SlotMachine.advance(position)
  end
  return position
end

-- ---------------------------------------------------- reel 2's skip-to-seven
--
-- Slots_StopReel2's alternative: with a bet of 2 or more, a SEVEN visible
-- anywhere in reel one, and a spin that is either unbiased or biased to SEVEN,
-- there is a 31.25% chance (`cp 31 percent + 1 / jr nc` = 80/256) that reel two
-- ignores the player entirely, pauses, and then fast-spins until the two reels
-- line up SEVENs.
--
-- It is almost always a tease: lining up two SEVENs is what UNLOCKS the reel-3
-- theatres below, and those only pay when the bias was SEVEN to begin with.
function SlotMachine.reel2SkipsToSeven(bet, bias, stopped1, random)
  if (bet or 0) < 2 then return false end
  if bias ~= SlotMachine.SEVEN and bias ~= SlotMachine.NO_BIAS then
    return false
  end
  -- .CheckReel1ForASeven returns z only when one of the three is SLOTS_SEVEN,
  -- which is zero -- so the test really is "any zero in the window".
  if not (stopped1[1] == SlotMachine.SEVEN or stopped1[2] == SlotMachine.SEVEN
      or stopped1[3] == SlotMachine.SEVEN) then
    return false
  end
  return random(256) < 80
end

-- ReelAction_FastSpinReel2UntilLinedUp7s: keep turning until the two reels show
-- matching SEVENs on a line this bet buys.
function SlotMachine.spinReel2ToSevens(position, bet, stopped1)
  local strip = SlotMachine.REELS[2]
  local pos = SlotMachine.advance(position)
  for _ = 1, SEARCH_LIMIT do
    local window = { SlotMachine.window(strip, pos) }
    local building, sevens = SlotMachine.matchFirstTwo(bet, stopped1, window)
    if building ~= SlotMachine.NO_MATCH and sevens then return pos end
    pos = SlotMachine.advance(pos)
  end
  return pos
end

-- ------------------------------------------------------- reel 3's theatre
--
-- Slots_StopReel3's action roll, which only happens when the first two reels
-- already show matching SEVENs.  The ASM's `.biased` label is misleading: it is
-- reached when the bias is NOT SEVEN (including no bias at all), and the
-- fallthrough above it is the bias-to-SEVEN case.  The ASM's own comment block
-- confirms which set of odds belongs to which.
SlotMachine.REEL3_STOP  = "stop"
SlotMachine.REEL3_SLOW  = "slowAdvance"
SlotMachine.REEL3_GOLEM = "golem"
SlotMachine.REEL3_EGG   = "chansey"

function SlotMachine.reel3Action(matchingSevens, bias, random)
  if not matchingSevens then return SlotMachine.REEL3_STOP end
  local r = random(256)
  if bias == SlotMachine.SEVEN then
    -- cp 71 percent - 1 (180) / cp 47 percent + 1 (120) / cp 24 percent - 1 (60)
    if r >= 180 then return SlotMachine.REEL3_STOP end        -- 29.7%
    if r >= 120 then return SlotMachine.REEL3_SLOW end        -- 23.4%
    if r >= 60 then return SlotMachine.REEL3_GOLEM end        -- 23.4%
    return SlotMachine.REEL3_EGG                              -- 23.4%
  end
  -- cp 63 percent (160) / cp 31 percent + 1 (80).  Chansey is unreachable here,
  -- which is why the egg is the rarest thing on the machine.
  if r >= 160 then return SlotMachine.REEL3_STOP end          -- 37.5%
  if r >= 80 then return SlotMachine.REEL3_SLOW end           -- 31.25%
  return SlotMachine.REEL3_GOLEM                              -- 31.25%
end

-- The predicate every theatre spins toward, from ReelAction_WaitSlowAdvanceReel3
-- .check1 / .check2: biased to SEVEN means "keep going until SEVENs line up",
-- anything else means "keep going until NOTHING lines up".
local function theatreSatisfied(bias, matched)
  if bias == SlotMachine.SEVEN then return matched == SlotMachine.SEVEN end
  return matched == SlotMachine.NO_MATCH
end

function SlotMachine.slowAdvance(position, bias, bet, stopped1, stopped2)
  local strip = SlotMachine.REELS[3]
  for _ = 1, SEARCH_LIMIT do
    local window = { SlotMachine.window(strip, position) }
    local matched = SlotMachine.matchAll(bet, stopped1, stopped2, window)
    if theatreSatisfied(bias, matched) then return position end
    position = SlotMachine.advance(position)
  end
  return position
end

-- Slots_GetNumberOfGolems.  Two different searches, and only one of them is
-- honest:
--
--   biased to SEVEN  the position is stepped ONE slot per Golem until SEVENs
--                    line up, and the count returned is exactly that many
--                    steps -- so the reel really does land where the search
--                    looked (1 to 14 Golems)
--   anything else    the search steps by a growing stride (a random 4..7, then
--                    5, 6, ...) while the returned count is the FINAL stride,
--                    and each Golem only advances the reel one slot.  The reel
--                    therefore lands somewhere the search never checked, and
--                    ReelAction_WaitGolem `.two` stops it there regardless.
--                    That mismatch is the cart's, not a shortcut here.
--
-- Returns the Golem count; the reel ends up `count` slots on from where it was.
function SlotMachine.golemCount(position, bias, bet, stopped1, stopped2, random)
  local strip = SlotMachine.REELS[3]
  if bias == SlotMachine.SEVEN then
    local walk, count = position, 0
    for _ = 1, SEARCH_LIMIT do
      walk = walk + 1
      count = count + 1
      local window = { SlotMachine.window(strip, walk) }
      local matched = SlotMachine.matchAll(bet, stopped1, stopped2, window)
      if matched == SlotMachine.SEVEN then return count end
    end
    return count
  end
  -- `call Random / and $7 / cp $8 / 2 / jr c` rerolls until the low three bits
  -- are 4..7.
  local stride = random(8)
  while stride < 4 do stride = random(8) end
  local walk = position
  for _ = 1, SEARCH_LIMIT do
    walk = walk + stride
    stride = stride + 1
    local window = { SlotMachine.window(strip, walk) }
    local matched = SlotMachine.matchAll(bet, stopped1, stopped2, window)
    if matched == SlotMachine.NO_MATCH then return stride end
  end
  return stride
end

-- ReelAction_DropReel: Chansey's egg drops the reel 17 slots at a time and
-- re-checks, over and over, until SEVENs are lined up.  17 slots is two slots
-- of net movement per egg on a 15-slot reel, which is why the egg keeps
-- falling for so long.
SlotMachine.EGG_DROP = 17

function SlotMachine.eggDrops(position, bet, stopped1, stopped2)
  local strip = SlotMachine.REELS[3]
  local drops = 0
  for _ = 1, SEARCH_LIMIT do
    for _ = 1, SlotMachine.EGG_DROP do
      position = SlotMachine.advance(position)
    end
    drops = drops + 1
    local window = { SlotMachine.window(strip, position) }
    local matched = SlotMachine.matchAll(bet, stopped1, stopped2, window)
    -- `.check_match: jr nc, .EggAgain / and a / jr nz, .EggAgain` -- it takes a
    -- match AND that match being SEVEN to settle.
    if matched == SlotMachine.SEVEN then return position, drops end
  end
  return position, drops
end

-- ------------------------------------------------------------- whole spin
--
-- One spin resolved end to end, for the tests and for anything that wants the
-- machine's numbers without its animation.  `stops` is where the player's three
-- A presses landed (0-based slot per reel, the way REEL_POSITION reads).
--
-- Returns { matched, payout, bias, positions, reel3Action }.
function SlotMachine.spin(opts)
  local random = opts.random
  local bet = opts.bet or 1
  local bias = SlotMachine.initBias(opts.bias or SlotMachine.NO_BIAS,
    opts.lucky, random)
  local stops = opts.stops or { 0, 0, 0 }

  local p1 = SlotMachine.stopReel1(stops[1], bias)
  local r1 = { SlotMachine.window(SlotMachine.REELS[1], p1) }

  local p2
  if SlotMachine.reel2SkipsToSeven(bet, bias, r1, random) then
    p2 = SlotMachine.spinReel2ToSevens(stops[2], bet, r1)
  else
    p2 = SlotMachine.stopReel2(stops[2], bias, bet, r1)
  end
  local r2 = { SlotMachine.window(SlotMachine.REELS[2], p2) }
  local _, matchingSevens = SlotMachine.matchFirstTwo(bet, r1, r2)

  local action = SlotMachine.reel3Action(matchingSevens, bias, random)
  local p3 = stops[3]
  if action == SlotMachine.REEL3_STOP then
    p3 = SlotMachine.stopReel3(p3, bias, bet, r1, r2)
  elseif action == SlotMachine.REEL3_SLOW then
    p3 = SlotMachine.slowAdvance(p3, bias, bet, r1, r2)
  elseif action == SlotMachine.REEL3_GOLEM then
    local count = SlotMachine.golemCount(p3, bias, bet, r1, r2, random)
    for _ = 1, count do p3 = SlotMachine.advance(p3) end
  else
    p3 = SlotMachine.eggDrops(p3, bet, r1, r2)
  end
  local r3 = { SlotMachine.window(SlotMachine.REELS[3], p3) }

  local matched = SlotMachine.matchAll(bet, r1, r2, r3)
  return {
    matched = matched,
    payout = SlotMachine.payout(matched),
    bias = bias,
    reel3Action = action,
    positions = { p1, p2, p3 },
    windows = { r1, r2, r3 },
  }
end

-- ------------------------------------------------------------------ layout
local COINS_X, COINS_Y = 5, 1
local PAYOUT_X, PAYOUT_Y = 11, 1
-- REEL_X_COORD / TILE_WIDTH (5, 9, 13) for the 3 reel apertures (columns 5-6, 9-10, 13-14)
local REEL_X = { 5, 9, 13 }
-- Slots_UpdateReelPositionAndOAM's y ladder, converted from OAM space (which
-- sits 16px above the screen) to tile rows: bottom, middle, top, and the
-- fourth symbol that only half shows.
local REEL_ROW = { 8, 6, 4, 2 }
-- Slots_Lights3OnOff / 2 / 1: the row each bet's pair of lights is drawn on,
-- and the two columns Slots_TurnLightsOnOrOff writes.
local LIGHT_ROWS = { [3] = { 2, 10 }, [2] = { 4, 8 }, [1] = { 6 } }
local LIGHT_COLS = { 3, 16 }
-- Slots_AskBet's MenuHeader through GetMenuTextStartCoord.
local BET_BOX_X, BET_BOX_Y, BET_BOX_W, BET_BOX_H = 14, 10, 6, 8
local BET_LABEL_X, BET_LABEL_Y, BET_SPACING = 16, 12, 2
-- .Text_PrintPayout's four ldcoord_a writes.
local PAYOUT_SYMBOL_X, PAYOUT_SYMBOL_Y = 2, 13
-- Textbox(0, TEXTBOX_Y) -- the standard speech box every PrintText here uses.
local TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W, TEXT_BOX_H = 0, 12, 20, 6
local TEXT_X, TEXT_Y, TEXT_LINE = 1, 14, 2

-- ------------------------------------------------------------------- text
--
-- data/text/common_2.asm and common_3.asm.  None of these are in the cache's
-- text.lua: no script bytecode points at them, so the extractor -- which walks
-- reachable script pointers -- never reaches them.
local TEXTS = {
  betHowMany = { "Bet how many", "coins?" },      -- _SlotsBetHowManyCoinsText
  start = { "Start!" },                            -- _SlotsStartText
  notEnough = { "Not enough", "coins." },          -- _SlotsNotEnoughCoinsText
  ranOut = { "Darn… Ran out of", "coins…" },       -- _SlotsRanOutOfCoinsText
  playAgain = { "Play again?" },                   -- _SlotsPlayAgainText
  darn = { "Darn!" },                              -- _SlotsDarnText
}
SlotMachine.TEXTS = TEXTS

-- _SlotsLinedUpText: "lined up!" / "Won @<wStringBuffer2> coins!", with the
-- matched symbol's 2x2 tiles printed to its left by .Text_PrintPayout.
local function linedUpLines(payout)
  return { "    lined up!", ("Won %d coins!"):format(payout) }
end

-- Slots_PlaySFX's labels, spelled the pokegold way (Sound.GEN2_ALIASES is what
-- maps the shared UI's own names onto these, never the other way round).
local SFX_START = "Sfx_SlotMachineStart"
local SFX_STOP = "Sfx_StopSlot"
local SFX_PAY_DAY = "Sfx_PayDay"
local SFX_COIN = "Sfx_GetCoinFromSlots"
local SFX_QUIT = "Sfx_QuitSlots"
local SFX_SEVENS = "Sfx_2ndPlace"
local SFX_POKEBALLS = "Sfx_3rdPlace"
local SFX_SMALL_WIN = "Sfx_Present"

-- ------------------------------------------------------------------ screen
function SlotMachine:wantsFillScale() return true end
function SlotMachine:drawsWidescreen() return true end

-- opts: save, lucky (wScriptVar on entry), random(n), onClose()
function SlotMachine.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, SlotMachine)
  self.game = game
  self.save = opts.save or (game and game.save)
  self.lucky = opts.lucky or false
  self.onClose = opts.onClose
  self.random = opts.random or function(n)
    if love and love.math and love.math.random then
      return love.math.random(n) - 1
    end
    return math.random(n) - 1
  end
  -- .InitGFX's tail, rolled once for the whole visit to the machine.
  self.keepSevenChance = SlotMachine.rollKeepSevenChance(self.random)
  self.bias = SlotMachine.NO_BIAS
  self.payoutLeft = 0
  self.positions = { 0, 0, 0 }
  self.distance = { 0, 0, 0 }
  self.rate = { 0, 0, 0 }
  self.stops = { nil, nil, nil }
  self:playMusic()
  self:enterInit()
  return self
end

function SlotMachine:playMusic()
  local data = self.game and self.game.data
  if not data then return end
  require("src.core.Music").play(data, "Music_GameCorner")
end

function SlotMachine:sfx(name)
  local data = self.game and self.game.data
  if data then Sound.play(data, name) end
end

function SlotMachine:coins()
  return CoinCase.coins(self.save)
end

-- ---------------------------------------------------------------- phases
--
-- SlotsAction_Init: clear the match flags, then straight into the bet menu.
function SlotMachine:enterInit()
  self.matched = SlotMachine.NO_MATCH
  self.matchingSevens = false
  self.phase = "bet"
  self.betIndex = 1 -- `db 1 ; default option`, which is the " 3" row
  self.message = nil
end

-- Slots_AskBet: `ld a, 4 / sub b` turns the cursor row into the bet, so the
-- top row is three coins and the bottom is one.
local BET_ROWS = { " 3", " 2", " 1" }

function SlotMachine:updateBet(input)
  if self.message then
    if input:wasPressed("a") or input:wasPressed("b") then self.message = nil end
    return
  end
  if input:wasPressed("up") then
    self.betIndex = self.betIndex > 1 and self.betIndex - 1 or #BET_ROWS
    return
  elseif input:wasPressed("down") then
    self.betIndex = self.betIndex < #BET_ROWS and self.betIndex + 1 or 1
    return
  elseif input:wasPressed("b") then
    -- VerticalMenu returning carry is what SlotsAction_BetAndStart reads as
    -- SLOTS_QUIT.
    self:quit()
    return
  elseif input:wasPressed("a") then
    local bet = 4 - self.betIndex
    if self:coins() < bet then
      self.message = TEXTS.notEnough
      return
    end
    self.bet = bet
    CoinCase.takeCoins(self.save, bet)
    self:sfx(SFX_PAY_DAY)
    self:startSpin()
  end
end

-- SlotsAction_BetAndStart's tail: the bias for THIS spin, all three reels at
-- REEL_ACTION_NORMAL_RATE, and 32 frames of wSlotsDelay before A does anything.
function SlotMachine:startSpin()
  self.bias = SlotMachine.initBias(self.bias, self.lucky, self.random)
  self.phase = "spinning"
  self.reel = 1
  self.delay = 32
  self.message = TEXTS.start
  self.stopped = nil
  self.matched = SlotMachine.NO_MATCH
  self.matchingSevens = false
  self.reel3Action = nil
  self.golemAnim = nil
  self.chanseyAnim = nil
  self.reel2Pause = nil
  for i = 1, 3 do
    self.rate[i] = 4 -- ReelAction_NormalRate
    self.stops[i] = nil
    self.distance[i] = 0
  end
  self:sfx(SFX_START)
end

-- Slots_SpinReel, per reel per frame: the action jumptable runs only on a slot
-- boundary, and the position advances whenever 16 pixels are traversed.
function SlotMachine:spinReels()
  for i = 1, 3 do
    local rate = self.rate[i]
    if rate > 0 then
      self.distance[i] = (self.distance[i] or 0) + rate
      while self.distance[i] >= 16 do
        self.distance[i] = self.distance[i] - 16
        self.positions[i] = SlotMachine.advance(self.positions[i])
        -- A reel with a resting slot chosen stops the moment it reaches it.
        if self.stops[i] and self.positions[i] == self.stops[i] then
          self.rate[i] = 0
          self.distance[i] = 0
          self.stopped = self.stopped or {}
          self.stopped[i] = { SlotMachine.window(SlotMachine.REELS[i],
            self.positions[i]) }
          self:sfx(SFX_STOP)
          self:reelStopped(i)
          break
        end
      end
    end
  end
end

-- The three symbols reel `i` is currently showing.  Named apart from
-- SlotMachine.window so the instance method cannot shadow the pure one.
function SlotMachine:reelWindow(i)
  return { SlotMachine.window(SlotMachine.REELS[i], self.positions[i]) }
end

-- SlotsAction_WaitReel1 / 2 / 3: A picks the slot, and the reel then turns to
-- wherever the manipulation put it.
function SlotMachine:pressStop()
  local i = self.reel
  if self.stops[i] then return end
  local here = self.positions[i]
  if i == 1 then
    self.stops[1] = SlotMachine.stopReel1(here, self.bias)
  elseif i == 2 then
    local r1 = self.stopped[1]
    local hereWindow = { SlotMachine.window(SlotMachine.REELS[2], here) }
    local _, hereSevens = SlotMachine.matchFirstTwo(self.bet, r1, hereWindow)
    local doSkip = SlotMachine.reel2SkipsToSeven(self.bet, self.bias, r1, self.random)
    if hereSevens and not doSkip then
      self.stops[2] = here
    elseif doSkip then
      -- ReelAction_SetUpReel2SkipTo7 pauses the reel for 32 frames and then
      -- fast-spins it at double rate; the pause is the tell.
      self.stops[2] = SlotMachine.spinReel2ToSevens(here, self.bet, r1)
      self.reel2Pause = 32
      self.rate[2] = 0 -- paused during the 32-frame tell
    else
      self.stops[2] = SlotMachine.stopReel2(here, self.bias, self.bet, r1)
    end
  else
    local r1, r2 = self.stopped[1], self.stopped[2]
    local _, sevens = SlotMachine.matchFirstTwo(self.bet, r1, r2)
    self.matchingSevens = sevens
    local action = SlotMachine.reel3Action(sevens, self.bias, self.random)
    self.reel3Action = action
    if action == SlotMachine.REEL3_STOP or action == "stop" then
      self.stops[3] = SlotMachine.stopReel3(here, self.bias, self.bet, r1, r2)
    elseif action == SlotMachine.REEL3_SLOW or action == "slowAdvance" then
      self.stops[3] = SlotMachine.slowAdvance(here, self.bias, self.bet, r1, r2)
      self.rate[3] = 1 -- ReelAction_QuarterRate slow crawl
    elseif action == SlotMachine.REEL3_GOLEM or action == "golem" then
      local count = SlotMachine.golemCount(here, self.bias, self.bet, r1, r2,
        self.random)
      if count == 0 then count = 3 end
      local target = here
      for _ = 1, count do target = SlotMachine.advance(target) end
      self.stops[3] = target
      self.golems = count
      self.golemAnim = {
        count = count,
        state = "falling",
        var1 = 48,
        x = 100,
        y = 44 - 112,
        animFrame = 0,
        animTimer = 0,
      }
      self.rate[3] = 0 -- reel 3 stepped by each golem impact
    else
      local target = SlotMachine.eggDrops(here, self.bet, r1, r2)
      self.stops[3] = target
      self.chanseyAnim = {
        state = "walking",
        xcoord = 0,
        x = -24,
        y = 44,
        animTimer = 0,
        animPose = 0,
      }
      self.rate[3] = 0 -- paused until Chansey drops egg
    end
  end
  -- A reel already sitting on its resting slot has nowhere to turn.
  -- Only trigger immediate halt if no active pause tell or special animation is running.
  if not self.reel2Pause and not self.golemAnim and not self.chanseyAnim then
    if self.stops[i] == self.positions[i] then
      self.rate[i] = 0
      self.distance[i] = 0
      self.stopped = self.stopped or {}
      self.stopped[i] = self:reelWindow(i)
      self:sfx(SFX_STOP)
      self:reelStopped(i)
    end
  end
end

function SlotMachine:reelStopped(i)
  if i < 3 then
    self.reel = i + 1
    return
  end
  self.golemAnim = nil
  self.chanseyAnim = nil
  self.reel2Pause = nil
  -- SlotsAction_FlashIfWin: a win flashes the object palette for 16 frames
  -- before the payout is counted out; a loss skips straight past it.
  local r1, r2, r3 = self.stopped[1], self.stopped[2], self.stopped[3]
  self.matched = SlotMachine.matchAll(self.bet, r1, r2, r3)
  if self.matched == SlotMachine.NO_MATCH then
    self.phase = "payoutText"
    self.message = TEXTS.darn
    return
  end
  self.phase = "flash"
  self.flash = 16
end

-- SlotsAction_GiveEarnedCoins / SlotsAction_PayoutTextAndAnim: the payout
-- counter is filled from the table, the fanfare plays, and then the coins tick
-- across one per two frames.
function SlotMachine:beginPayout()
  self.payoutLeft = SlotMachine.payout(self.matched)
  self.payoutTick = 0
  self.phase = "payoutText"
  self.message = linedUpLines(self.payoutLeft)
  if self.matched == SlotMachine.SEVEN then
    self:sfx(SFX_SEVENS)
    -- .LinedUpSevens decides here whether the seven streak survives.
    if not SlotMachine.keepSevenBias(self.keepSevenChance, self.random) then
      self.bias = SlotMachine.NO_BIAS
    end
  elseif self.matched == SlotMachine.POKEBALL then
    self:sfx(SFX_POKEBALLS)
  else
    self:sfx(SFX_SMALL_WIN)
  end
end

-- SlotsAction_PayoutAnim: `ld a, [hl] / inc [hl] / and $1` -- one coin every
-- other frame, and the coin case clamp is checked BEFORE the increment, so a
-- full case eats the rest of the payout.
function SlotMachine:updatePayoutAnim()
  self.payoutTick = (self.payoutTick or 0) + 1
  if self.payoutTick % 2 == 1 then return end
  if self.payoutLeft <= 0 then
    self.phase = "again"
    return
  end
  self.payoutLeft = self.payoutLeft - 1
  CoinCase.giveCoins(self.save, 1)
  if self.payoutTick % 8 == 0 then self:sfx(SFX_COIN) end
end

-- Slots_AskPlayAgain: no coins left is not a question, it is the exit.
function SlotMachine:enterAgain()
  if self:coins() <= 0 then
    self.phase = "ranOut"
    self.message = TEXTS.ranOut
    self.ranOutDelay = 60 -- `ld c, 60 / call DelayFrames`
    return
  end
  self.phase = "again"
  self.againChoice = 1
  self.message = TEXTS.playAgain
end

function SlotMachine:quit()
  self.phase = "quit"
  self:sfx(SFX_QUIT)
  local data = self.game and self.game.data
  if data then require("src.core.Music").restoreMap(data) end
  if self.onClose then self.onClose() end
end

function SlotMachine:update(_dt)
  local input = self.game and self.game.input
  if not input then return end
  local phase = self.phase

  if phase == "bet" then
    self:updateBet(input)
    return
  end

  if phase == "spinning" then
    -- SlotsAction_WaitStart clears hJoypadSum first, so a press held from the
    -- bet menu cannot stop reel one.
    if (self.delay or 0) > 0 then
      self.delay = self.delay - 1
      self:spinReels()
      return
    end
    if self.reel2Pause and self.reel2Pause > 0 then
      self.reel2Pause = self.reel2Pause - 1
      if self.reel2Pause <= 0 then
        self.reel2Pause = nil
        self.rate[2] = 8 -- resume fast-spin after the 32-frame tell
      end
    end

    if self.golemAnim then
      local g = self.golemAnim
      -- Cycle animation frames every 8 ticks (~7.5 fps) matching the original pacing
      g.animTimer = (g.animTimer or 0) + 1
      if g.animTimer >= 8 then
        g.animTimer = 0
        g.animFrame = ((g.animFrame or 0) + 1) % 4
      end

      if g.state == "falling" then
        if g.var1 > 32 then
          g.var1 = g.var1 - 1
          local angle = (g.var1 * math.pi) / 32
          local yOffset = math.floor(112 * math.sin(angle) + 0.5)
          g.y = 44 + yOffset
          g.x = 100
        else
          -- Landed on Reel 3!
          g.y = 44
          g.x = 100
          g.state = "rolling"
          g.xoffset = 0
          g.animTimer = 0
          g.animFrame = 0
          self:sfx("Sfx_PlacePuzzlePieceDown")
          -- Advance reel 3 by 1 slot per Golem impact
          self.positions[3] = SlotMachine.advance(self.positions[3])
          self.distance[3] = 0
        end
      elseif g.state == "rolling" then
        g.xoffset = (g.xoffset or 0) + 1
        g.x = 100 - g.xoffset

        if g.xoffset >= 88 then
          -- Rolled past reel 1 (100 - 88 = 12px) off the screen -> restart or end
          g.count = g.count - 1
          if g.count > 0 then
            g.state = "falling"
            g.var1 = 48
            g.x = 100
            g.y = 44 - 112
          else
            -- All Golems finished; halt reel 3 at target
            self.golemAnim = nil
            self.rate[3] = 0
            self.distance[3] = 0
            self.stopped = self.stopped or {}
            self.stopped[3] = self:reelWindow(3)
            self:sfx(SFX_STOP)
            self:reelStopped(3)
          end
        end
      end
    end

    if self.chanseyAnim then
      local c = self.chanseyAnim
      if c.state == "walking" then
        c.xcoord = (c.xcoord or 0) + 1
        c.x = c.xcoord - 24
        c.y = 44

        -- Cycle walking poses 0->1->2->3 (maps to Chansey 1->2->3->4) every 6 frames
        c.animTimer = (c.animTimer or 0) + 1
        if c.animTimer >= 6 then
          c.animTimer = 0
          c.animPose = ((c.animPose or 0) + 1) % 4
        end

        if c.xcoord % 16 == 0 then self:sfx("Sfx_JumpOverLedge") end

        if c.x >= 88 then
          -- Reached reel 3! Switch to tell pause (pose 4 = arm raised)
          c.x = 88
          c.state = "egg_pause"
          c.delay = 14
          c.animPose = 3
        end
      elseif c.state == "egg_pause" then
        c.delay = (c.delay or 14) - 1
        if c.delay <= 0 then
          -- Switch to Chansey 5 (egg drop pose) and spawn egg
          c.animPose = 4
          c.state = "egg_drop"
          c.eggTimer = 0
          c.eggStartX = c.x + 14
          c.eggStartY = c.y + 8
          c.eggX = c.eggStartX
          c.eggY = c.eggStartY
          c.eggVisible = true
          self:sfx("Sfx_Present")
        end
      elseif c.state == "egg_drop" then
        c.eggTimer = (c.eggTimer or 0) + 1
        local t = c.eggTimer / 16
        if t > 1 then t = 1 end
        c.eggX = c.eggStartX + t * (108 - c.eggStartX)
        c.eggY = c.eggStartY + t * (56 - c.eggStartY) - math.sin(t * math.pi) * 8

        if c.eggTimer >= 16 then
          -- Egg landed on Reel 3!
          c.eggVisible = false
          c.state = "spinning"
          self:sfx("Sfx_PlacePuzzlePieceDown")
          self.rate[3] = 16 -- fast drop reel 3 to jackpot
        end
      end
    end

    self.message = nil
    if input:wasPressed("a") then
      if not self.stops[self.reel] and not self.reel2Pause and not self.golemAnim and not self.chanseyAnim then
        self:pressStop()
      end
    end
    self:spinReels()
    return
  end

  if phase == "flash" then
    self.flash = self.flash - 1
    if self.flash <= 0 then self:beginPayout() end
    return
  end

  if phase == "payoutText" then
    if self.matched == SlotMachine.NO_MATCH then
      if input:wasPressed("a") or input:wasPressed("b") then
        self:enterAgain()
      end
      return
    end
    self:updatePayoutAnim()
    if self.phase == "again" then self:enterAgain() end
    return
  end

  if phase == "again" then
    if input:wasPressed("up") or input:wasPressed("down") then
      self.againChoice = self.againChoice == 1 and 2 or 1
      return
    end
    if input:wasPressed("b") then
      self:quit()
      return
    end
    if input:wasPressed("a") then
      if self.againChoice == 1 then self:enterInit() else self:quit() end
    end
    return
  end

  if phase == "ranOut" then
    self.ranOutDelay = self.ranOutDelay - 1
    if self.ranOutDelay <= 0 then self:quit() end
    return
  end
end

-- ------------------------------------------------------------------- draw
--
-- Authentic Color Game Boy palettes and tile graphics matching pret/pokegold
local TileSheet = require("src.ui.gen2.TileSheet")
local GbcPalette = require("src.render.GbcPalette")

local GBC_PALS = {
  bg = {
    [0] = { { 255, 255, 255 }, { 198, 206, 231 }, { 198, 198, 74 }, { 0, 0, 0 } },  -- 0: Base Frame
    [1] = { { 255, 255, 255 }, { 247, 82, 49 },   { 198, 198, 74 }, { 0, 0, 0 } },  -- 1: Vileplume / Active Lights
    [2] = { { 255, 255, 255 }, { 123, 255, 0 },   { 198, 198, 74 }, { 0, 0, 0 } },  -- 2: Bet 3 Indicators
    [3] = { { 255, 255, 255 }, { 255, 123, 255 }, { 198, 198, 74 }, { 0, 0, 0 } },  -- 3: Bet 2 Indicators
    [4] = { { 255, 255, 255 }, { 123, 173, 255 }, { 198, 198, 74 }, { 0, 0, 0 } },  -- 4: Bet 1 Indicators
    [5] = { { 255, 255, 90 },  { 255, 255, 49 },   { 198, 198, 74 }, { 0, 0, 0 } },  -- 5: Yellow Highlights
    [6] = { { 255, 255, 255 }, { 132, 156, 239 }, { 206, 181, 0 },  { 0, 0, 0 } },  -- 6: Textbox frame
    [7] = { { 255, 255, 255 }, { 173, 173, 173 }, { 107, 107, 107 }, { 0, 0, 0 } },  -- 7: Inactive / Gray
  },
  obj = {
    [0] = { { 255, 255, 255 }, { 247, 82, 49 },   { 255, 0, 0 },    { 0, 0, 0 } },  -- 0: Seven (Red)
    [1] = { { 255, 255, 255 }, { 99, 206, 8 },    { 41, 115, 0 },   { 0, 0, 0 } },  -- 1: Pokeball (Green/Red)
    [2] = { { 255, 255, 255 }, { 99, 206, 8 },    { 247, 82, 49 },  { 0, 0, 0 } },  -- 2: Cherry
    [3] = { { 255, 255, 255 }, { 255, 255, 49 },  { 165, 123, 24 }, { 0, 0, 0 } },  -- 3: Pikachu (Yellow)
    [4] = { { 255, 255, 255 }, { 255, 255, 49 },  { 123, 173, 255 }, { 0, 0, 0 } }, -- 4: Squirtle (Blue/Yellow)
    [5] = { { 255, 255, 255 }, { 255, 255, 49 },  { 165, 123, 24 }, { 0, 0, 0 } },  -- 5: Staryu / Golem (Rock)
    [6] = { { 255, 255, 255 }, { 255, 198, 173 }, { 255, 107, 255 }, { 0, 0, 0 } }, -- 6: Chansey (Pink)
    [7] = { { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 },     { 0, 0, 0 } },  -- 7: Flashing
  }
}

local TILEMAP = nil
local function getTilemap()
  if TILEMAP == nil then
    local path = "assets/generated/slots/gold_slots.tilemap"
    local data = love and love.filesystem and love.filesystem.read(path)
    if data and #data > 0 then
      TILEMAP = {}
      for i = 1, #data do
        TILEMAP[i] = string.byte(data, i)
      end
    else
      TILEMAP = false
    end
  end
  return TILEMAP or nil
end

-- Placeholder 2x2 symbol cell used when reel sheets are not in the cache yet.
local function cell(tx, ty, label)
  local G = love.graphics
  G.setColor(0, 0, 0, 1)
  G.rectangle("line", tx * 8, ty * 8, 16, 16)
  Chrome.print(label, tx, ty + 1)
end

function SlotMachine:sheets()
  if self.sheet1 == nil then
    self.sheet1 = TileSheet.new({ path = "assets/generated/slots/gold_slots_1.png", wide = 2, firstTile = 0 })
    self.sheet2 = TileSheet.new({ path = "assets/generated/slots/gold_slots_2.png", wide = 2, firstTile = 0 })
    self.sheet3 = TileSheet.new({ path = "assets/generated/slots/gold_slots_3.png", wide = 3, firstTile = 0 })
  end
  return self.sheet1, self.sheet2, self.sheet3
end

function SlotMachine:drawBackground()
  local s1, s2 = self:sheets()
  local tm = getTilemap()
  if not tm or not s1:available() then
    -- Fallback simple background if assets unavailable
    Chrome.clear()
    return
  end

  local bet = self.bet or 0

  for ty = 0, 11 do
    for tx = 0, 19 do
      local idx = ty * 20 + tx + 1
      local tileId = tm[idx]

      -- Palette attribution matching _CGB_SlotMachine
      local pal = 0
      if (tx <= 2 or tx >= 17) and ty >= 2 and ty <= 11 then
        if ty >= 6 and ty <= 7 then pal = 4
        elseif ty >= 4 and ty <= 9 then pal = 3
        else pal = 2 end
      elseif tx >= 4 and tx <= 15 and ty >= 2 and ty <= 3 then
        pal = 1 -- Vileplume
      elseif (tx == 3 or tx == 16) and ty >= 2 and ty <= 11 then
        local isLit = false
        if ty == 6 or ty == 7 then isLit = (bet >= 1)
        elseif ty == 4 or ty == 5 or ty == 8 or ty == 9 then isLit = (bet >= 2)
        elseif ty == 2 or ty == 3 or ty == 10 or ty == 11 then isLit = (bet >= 3)
        end
        if isLit then
          pal = 1
          -- Use lit lights tile
          if tileId == 0x23 then tileId = 0x14
          elseif tileId == 0x24 then tileId = 0x15 end
        else
          pal = 0
        end
      end

      local colors = GBC_PALS.bg[pal]
      s1.palette = colors
      s2.palette = colors

      if tileId < 0x25 then
        s1:draw(tileId, tx, ty)
      else
        s2:draw(tileId - 0x25, tx, ty)
      end
    end
  end
end

function SlotMachine:drawReels()
  local _, s2 = self:sheets()
  local G = love.graphics

  for i = 1, 3 do
    local strip = SlotMachine.REELS[i]
    local pos = self.positions[i]
    local a = pos
    if a == 0 then a = 0x0f end
    a = (a - 1) % 16
    local rx = REEL_X[i] * 8
    local dy = math.floor(self.distance[i] or 0)

    -- Draw 4 consecutive 2x2 symbols from bottom to top, exactly matching SlotMachine.window
    for row = 0, 3 do
      local sym = strip[a + row + 1]
      if type(sym) ~= "number" then
        cell(REEL_X[i], REEL_ROW[row + 1], "?")
      else
        local py = 64 - (row * 16) + dy
        local pal = GBC_PALS.obj[math.floor(sym / 4)] or GBC_PALS.obj[0]
        s2.palette = pal

        -- 2x2 tiles in 2-wide sheet:
        -- sym + 0 = top-left (col 0, row 0)
        -- sym + 1 = top-right (col 1, row 0)
        -- sym + 2 = bottom-left (col 0, row 1)
        -- sym + 3 = bottom-right (col 1, row 1)
        local t0 = s2:quad(sym + 0)
        local t1 = s2:quad(sym + 1)
        local t2 = s2:quad(sym + 2)
        local t3 = s2:quad(sym + 3)
        local img = s2:image()

        if img and t0 and t1 and t2 and t3 then
          local function drawSym()
            G.draw(img, t0, rx, py)
            G.draw(img, t1, rx + 8, py)
            G.draw(img, t2, rx, py + 8)
            G.draw(img, t3, rx + 8, py + 8)
          end
          if GbcPalette.available() then
            GbcPalette.with(pal, drawSym)
          else
            drawSym()
          end
        else
          -- Fallback label
          cell(REEL_X[i], REEL_ROW[row + 1], SlotMachine.LABELS[sym] or "?")
        end
      end
    end
  end
end

function SlotMachine:actorsImage()
  if self.actorsLoaded == nil then
    local Assets = require("src.render.Assets")
    local ok, img = pcall(Assets.image, "assets/generated/slots/gold_slots_actors.png")
    if not (ok and img) then
      ok, img = pcall(Assets.image, "assets/generated/slots/gold_slots_3.png")
    end
    self.actorsLoaded = (ok and img) or false
    if self.actorsLoaded then
      local G = love.graphics
      -- 24x240 sheet:
      --   Y=0:   Golem 1 (Standing, 24x32)
      --   Y=32:  Golem 2 (Ball, 24x32)
      --   Y=64:  Chansey 1 (Standing / Step 1, 24x32)
      --   Y=96:  Chansey 2 (Step 2, 24x32)
      --   Y=128: Chansey 3 (Step 3, 24x32)
      --   Y=160: Chansey 4 (Arm raised / Step 4, 24x32)
      --   Y=192: Chansey 5 (Egg Drop pose, 24x32)
      --   Y=224: Egg (8x16 at X=0)
      self.quadGolemStand  = G.newQuad(0, 0,   24, 32, 24, 240)
      self.quadGolemBall   = G.newQuad(0, 32,  24, 32, 24, 240)
      self.quadChansey1    = G.newQuad(0, 64,  24, 32, 24, 240)
      self.quadChansey2    = G.newQuad(0, 96,  24, 32, 24, 240)
      self.quadChansey3    = G.newQuad(0, 128, 24, 32, 24, 240)
      self.quadChansey4    = G.newQuad(0, 160, 24, 32, 24, 240)
      self.quadChanseyDrop = G.newQuad(0, 192, 24, 32, 24, 240)
      self.quadEgg         = G.newQuad(0, 224, 8,  16, 24, 240)
    end
  end
  return self.actorsLoaded or nil
end

-- Redraw the top Vileplume row (rows 2..3) and bottom frame brackets (rows 10..11)
-- over the reels with solid backdrop to naturally mask any sprite overhang like the Game Boy hardware does.
function SlotMachine:drawOverlays()
  local s1, s2 = self:sheets()
  local tm = getTilemap()
  if not tm or not s1:available() then return end

  local G = love.graphics
  -- Solid backdrop over header (rows 0..3) and footer (rows 10..11) between columns 4..15
  G.setColor(198 / 255, 198 / 255, 74 / 255, 1)
  G.rectangle("fill", 4 * 8, 2 * 8, 12 * 8, 2 * 8)
  G.rectangle("fill", 4 * 8, 10 * 8, 12 * 8, 2 * 8)
  G.setColor(1, 1, 1, 1)

  for _, ty in ipairs({ 2, 3, 10, 11 }) do
    for tx = 4, 15 do
      local idx = ty * 20 + tx + 1
      local tileId = tm[idx]
      local pal = (ty <= 3) and 1 or 0
      local colors = GBC_PALS.bg[pal]
      s1.palette = colors
      s2.palette = colors

      if tileId < 0x25 then
        s1:draw(tileId, tx, ty)
      else
        s2:draw(tileId - 0x25, tx, ty)
      end
    end
  end

  -- Draw Golem sprite animation
  if self.golemAnim then
    local actors = self:actorsImage()
    local g = self.golemAnim
    if actors then
      local quad = self.quadGolemBall
      local scaleX = 1
      local scaleY = 1
      if g.state == "falling" then
        quad = self.quadGolemBall
      elseif g.state == "rolling" then
        -- Frameset_SlotsGolem: 0=Standing, 1=Ball, 2=StandingYFlip, 3=BallXFlip
        local rotFrame = (g.animFrame or 0) % 4
        if rotFrame == 0 then
          quad = self.quadGolemStand
          scaleX = 1
          scaleY = 1
        elseif rotFrame == 1 then
          quad = self.quadGolemBall
          scaleX = 1
          scaleY = 1
        elseif rotFrame == 2 then
          quad = self.quadGolemStand
          scaleX = 1
          scaleY = -1
        elseif rotFrame == 3 then
          quad = self.quadGolemBall
          scaleX = -1
          scaleY = 1
        end
      end
      G.setColor(1, 1, 1, 1)
      local function drawGolem()
        -- Draw rotated around center (ox=12, oy=16)
        G.draw(actors, quad,
          math.floor(g.x + 12),
          math.floor(g.y + 16),
          0, scaleX, scaleY, 12, 16)
      end
      if GbcPalette.available() then
        GbcPalette.with(GBC_PALS.obj[5], drawGolem)
      else
        drawGolem()
      end
    end
  end

  -- Draw Chansey & Egg sprite animation
  if self.chanseyAnim then
    local actors = self:actorsImage()
    local c = self.chanseyAnim
    if actors then
      local quad = self.quadChansey1
      if c.state == "walking" then
        local walkCycle = { self.quadChansey1, self.quadChansey2, self.quadChansey3, self.quadChansey4 }
        quad = walkCycle[((c.animPose or 0) % 4) + 1] or self.quadChansey1
      elseif c.state == "egg_pause" then
        quad = self.quadChansey4
      elseif c.state == "egg_drop" or c.state == "spinning" then
        quad = self.quadChanseyDrop
      end

      G.setColor(1, 1, 1, 1)
      local function drawChansey()
        G.draw(actors, quad, math.floor(c.x), math.floor(c.y or 44))
        if c.eggVisible and c.eggX and c.eggY then
          G.draw(actors, self.quadEgg, math.floor(c.eggX), math.floor(c.eggY))
        end
      end
      if GbcPalette.available() then
        GbcPalette.with(GBC_PALS.obj[6], drawChansey)
      else
        drawChansey()
      end
    end
  end
end

function SlotMachine:drawMessage()
  if not self.message then return end
  Chrome.textbox(TEXT_BOX_X, TEXT_BOX_Y, TEXT_BOX_W - 2, TEXT_BOX_H - 2)
  for i, line in ipairs(self.message) do
    Chrome.print(line, TEXT_X, TEXT_Y + (i - 1) * TEXT_LINE)
  end
  if self.matched and self.matched ~= SlotMachine.NO_MATCH
      and self.phase == "payoutText" then
    local _, s2 = self:sheets()
    local sym = self.matched
    if type(sym) ~= "number" then
      cell(PAYOUT_SYMBOL_X, PAYOUT_SYMBOL_Y, "?")
    else
      local pal = GBC_PALS.obj[math.floor(sym / 4)] or GBC_PALS.obj[0]
      s2.palette = pal
      local t0 = s2:quad(sym + 0)
      local t1 = s2:quad(sym + 1)
      local t2 = s2:quad(sym + 2)
      local t3 = s2:quad(sym + 3)
      local img = s2:image()
      local G = love.graphics
      local px, py = PAYOUT_SYMBOL_X * 8, PAYOUT_SYMBOL_Y * 8
      if img and t0 and t1 and t2 and t3 then
        local function drawWin()
          G.setColor(1, 1, 1, 1)
          G.draw(img, t0, px, py)
          G.draw(img, t1, px + 8, py)
          G.draw(img, t2, px, py + 8)
          G.draw(img, t3, px + 8, py + 8)
        end
        G.setColor(1, 1, 1, 1)
        if GbcPalette.available() then
          GbcPalette.with(pal, drawWin)
        else
          drawWin()
        end
      else
        cell(PAYOUT_SYMBOL_X, PAYOUT_SYMBOL_Y, SlotMachine.LABELS[sym] or "?")
      end
    end
  end
end

function SlotMachine:drawPanel()
  self:drawBackground()
  self:drawReels()
  self:drawOverlays()

  -- PRINTNUM_LEADINGZEROS | 2 bytes, 4 digits, for both counters.
  Chrome.print(Chrome.number(self:coins(), 4, true), COINS_X, COINS_Y)
  Chrome.print(Chrome.number(self.payoutLeft or 0, 4, true), PAYOUT_X, PAYOUT_Y)

  if self.phase == "bet" then
    -- Left speech textbox for "Bet how many coins?"
    Chrome.textbox(0, 12, 12, 4)
    Chrome.print(TEXTS.betHowMany[1], 1, 14)
    Chrome.print(TEXTS.betHowMany[2], 1, 16)

    -- Right menu for bet choices (14, 10 to 19, 17)
    Chrome.textbox(14, 10, 4, 6)
    for i, label in ipairs(BET_ROWS) do
      local ty = 12 + (i - 1) * 2
      if i == self.betIndex then Chrome.cursor(15, ty) end
      Chrome.print(label, 16, ty)
    end

    if self.message then
      -- If "Not enough coins." message is shown, overlay full speech box
      Chrome.textbox(0, 12, 18, 4)
      for i, line in ipairs(self.message) do
        Chrome.print(line, TEXT_X, TEXT_Y + (i - 1) * TEXT_LINE)
      end
    end
  elseif self.phase == "again" then
    -- Speech box: "Play again?"
    Chrome.textbox(0, 12, 18, 4)
    Chrome.print(TEXTS.playAgain[1], TEXT_X, TEXT_Y)

    -- PlaceYesNoBox at (14, 12): 6x5 box with YES at (16,13), NO at (16,15)
    Chrome.textbox(14, 12, 4, 3)
    Chrome.print("YES", 16, 13)
    Chrome.print("NO", 16, 15)
    Chrome.cursor(15, 13 + (self.againChoice - 1) * 2)
  else
    self:drawMessage()
  end
end

function SlotMachine:draw()
  self:drawPanel()
end

function SlotMachine:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return SlotMachine
