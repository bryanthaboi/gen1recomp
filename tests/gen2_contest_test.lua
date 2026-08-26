-- The Bug Catching Contest and Kurt's apricorns.
--   GOLD_CACHE="..." luajit tests/gen2_contest_test.lua
--
-- Both systems are pure rules over a save table, so every assertion below runs
-- with no cache, no love and no stack.  The rolls are injected byte by byte
-- (`call Random` yields one byte, so a seed here is a literal list of the
-- bytes the ASM would have read) and the clock is injected as a cart-shaped
-- { day, hour, minute, second }, which is the only way to test a day-long wait
-- and a player winding the clock backwards.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 contest")
local check, eq = S.check, S.eq
local seq = S.rng.seq

love = require("tests.love_stub")

local BugContest = require("src.core.gen2.BugContest")
local Apricorns = require("src.core.gen2.Apricorns")

-- ---- constants ------------------------------------------------------------
eq(BugContest.BALLS, 20, "BUG_CONTEST_BALLS is 20")
eq(BugContest.MINUTES, 20, "BUG_CONTEST_MINUTES is 20")
eq(BugContest.SECONDS, 0, "BUG_CONTEST_SECONDS is 0")
eq(BugContest.PLAYER, 1, "BUG_CONTEST_PLAYER is 1")
eq(BugContest.NUM_CONTESTANTS, 10, "ten contestants, not counting the player")
eq(BugContest.CONTESTANT_SIZE, 4, "BUG_CONTESTANT_SIZE is 4")
eq(BugContest.CONTESTANTS_PICKED, 5, "five of the ten are picked")
eq(BugContest.BALL, "PARK_BALL", "the park's only ball")
eq(BugContest.PRIZES[1], "SUN_STONE", "first place is the SUN STONE")
eq(BugContest.PRIZES[2], "EVERSTONE", "second is the EVERSTONE")
eq(BugContest.PRIZES[3], "GOLD_BERRY", "third is the GOLD BERRY")
eq(BugContest.CONSOLATION_PRIZE, "BERRY", "and everyone else gets a BERRY")
eq(BugContest.prizeFor(0), "BERRY", "placing nowhere is the consolation prize")
eq(BugContest.prizeFor(1), "SUN_STONE", "placing first is the SUN STONE")

-- Route35OfficerScriptContest turns you away on Sunday, Monday, Wednesday and
-- Friday.
local DAYS = { "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY",
               "FRIDAY", "SATURDAY" }
local WANT_CONTEST = { false, false, true, false, true, false, true }
for index = 1, 7 do
  eq(BugContest.isContestDay({ day = index - 1 }), WANT_CONTEST[index],
    DAYS[index] .. " is " .. (WANT_CONTEST[index] and "" or "not ")
      .. "a contest day")
end
-- GetWeekday is wCurDay mod 7, so day 9 is the same weekday as day 2.
eq(BugContest.weekday({ day = 9 }), 2, "day 9 is a TUESDAY, like day 2")
check(BugContest.isContestDay({ day = 9 }), "and so it is a contest day")

-- ---- ContestScore ---------------------------------------------------------
--
-- Hand computed against engine/events/bug_contest/judging.asm ContestScore.
local function mon(fields)
  local out = {
    species = "SCYTHER", level = 13,
    maxHp = 45, hp = 45,
    stats = { hp = 45, attack = 40, defense = 35, speed = 50,
              specialAttack = 25, specialDefense = 30 },
    dvs = { attack = 15, defense = 0, speed = 2, special = 8 },
  }
  for key, value in pairs(fields or {}) do out[key] = value end
  return out
end

-- 4 * 45 max HP            = 180
-- 40 + 35 + 50 + 25 + 30   = 180  the five stats
-- DV bit 1s: atk 15 -> 1, def 0 -> 0, spd 2 -> 1, spc 8 -> 0
--   8 * 1 + 16 * 0 + 1 * 1 + 4 * 0 = 9
-- floor(45 / 8)            = 5
-- no held item             = 0
eq(BugContest.score(mon()), 374, "the hand computed base score")

-- The item term is a flat +1, whatever the item is.
eq(BugContest.score(mon({ item = "BERRY" })), 375, "a held item is worth one")

-- Every DV bit weight, one at a time, against a mon whose DVs are otherwise 0.
local BARE = { attack = 0, defense = 0, speed = 0, special = 0 }
local function dvOnly(key, value)
  local dvs = {}
  for k, v in pairs(BARE) do dvs[k] = v end
  dvs[key] = value
  return BugContest.score(mon({ dvs = dvs })) - BugContest.score(mon({ dvs = BARE }))
end
eq(dvOnly("defense", 2), 16, "bit 1 of the Defense DV is worth 16")
eq(dvOnly("attack", 2), 8, "bit 1 of the Attack DV is worth 8")
eq(dvOnly("special", 2), 4, "bit 1 of the Special DV is worth 4")
eq(dvOnly("speed", 2), 1, "bit 1 of the Speed DV is worth 1")
-- Bit 0 and bits 2-3 are not read at all: `and %0010` masks everything else
-- off, so a DV of 1 scores like a DV of 0 and a DV of 13 (%1101) does too.
eq(dvOnly("attack", 1), 0, "bit 0 of a DV is not read")
eq(dvOnly("attack", 13), 0, "and neither are bits 2 and 3")
eq(dvOnly("attack", 15), 8, "only bit 1 counts, so 15 scores like 2")

-- Every term is an EIGHT BIT read out of a big-endian party struct, so a max
-- HP of 300 contributes 4 * (300 - 256), not 1200.
eq(BugContest.score(mon({ maxHp = 300, hp = 0, dvs = BARE })),
  4 * 44 + 180, "max HP is read one byte at a time")
-- Remaining HP is shifted right three times, so 45 and 47 tally the same 5.
eq(BugContest.score(mon({ hp = 47 })), BugContest.score(mon({ hp = 45 })),
  "remaining HP is divided by eight")

-- `ld a, [wContestMonSpecies] / and a / jr z, .done`
eq(BugContest.score(nil), 0, "no mon scores nothing")
eq(BugContest.score({ maxHp = 200 }), 0, "and neither does an empty slot")

-- ---- the contestant table -------------------------------------------------
eq(#BugContest.CONTESTANTS, 10, "ten contestant rows")
-- BugContestantPointers slot 1 is Bug Catcher Don and slot 10 is Schoolboy
-- Kipp; slot 0's duplicate Don is deliberately not in the Lua table.
eq(BugContest.CONTESTANTS[1].name, "DON", "slot 1 is DON")
eq(BugContest.CONTESTANTS[10].name, "KIPP", "slot 10 is KIPP")
eq(BugContest.contestantId(1), 2, "slot 1 answers to winner ID 2")
eq(BugContest.contestantId(10), 11, "slot 10 answers to winner ID 11")
eq(BugContest.contestantSlot(2), 1, "and back again")
for slot, row in ipairs(BugContest.CONTESTANTS) do
  eq(#row.mons, 3, ("contestant %d lists three mons"):format(slot))
end
-- Cooltrainer Nick's rows are NOT in score order on the cart: his "third"
-- Pinsir outscores his "first" Scyther.  Transcribed, not sorted.
eq(BugContest.CONTESTANTS[3].mons[1].score, 357, "Nick's first row is 357")
eq(BugContest.CONTESTANTS[3].mons[3].score, 368, "and his third row is 368")

eq(BugContest.contestantName(nil, 1, "GOLD"), "GOLD", "ID 1 is the player")
eq(BugContest.contestantName(nil, 4), "COOLTRAINERM NICK",
  "and a contestant falls back to the transcribed class and name")

-- ---- ComputeAIContestantScores' roll --------------------------------------
--
-- Two bytes per contestant: `and 3` with a reroll on 3 picks the mon, `and 7`
-- bumps the score.  Slot 3 is Cooltrainer Nick.
local rolled = BugContest.rollContestant(3, seq(3, 5, 10))
eq(rolled.id, 4, "the roll reports Nick's winner ID")
eq(rolled.species, "BUTTERFREE", "5 & 3 is 1, so his second row")
eq(rolled.score, 351, "349 plus 10 & 7")

-- A byte of 3 is thrown away rather than folded, which is what keeps the three
-- rows equally likely.
eq(BugContest.rollContestant(3, seq(3, 3, 3, 0, 0)).species, "SCYTHER",
  "three rerolls land on the first row")
eq(BugContest.rollContestant(3, seq(2, 0)).species, "PINSIR",
  "and 2 is the third row")
eq(BugContest.rollContestant(3, seq(0, 7)).score, 357 + 7,
  "the bump is masked to three bits")
eq(BugContest.rollContestant(3, seq(0, 255)).score, 357 + 7,
  "so 255 bumps by seven, not by 255")

-- ---- DetermineContestWinners ----------------------------------------------
local function entry(id, score) return { id = id, species = "PARAS", score = score } end

local podium = {}
BugContest.placeEntry(podium, entry(2, 100))
BugContest.placeEntry(podium, entry(3, 300))
BugContest.placeEntry(podium, entry(4, 200))
eq(podium.first.score, 300, "the podium sorts descending")
eq(podium.second.score, 200, "second")
eq(podium.third.score, 100, "third")

-- A fourth entry below third does not displace anything.
BugContest.placeEntry(podium, entry(5, 50))
eq(podium.third.score, 100, "a worse score never reaches the podium")

-- CompareBytes only sets carry on a STRICTLY smaller score, so an equal score
-- takes the place and pushes the sitting entry down.  The player is scored
-- last, which is what makes this the tie-break rule that matters.
podium = {}
BugContest.placeEntry(podium, entry(2, 300))
BugContest.placeEntry(podium, entry(BugContest.PLAYER, 300))
eq(podium.first.id, BugContest.PLAYER, "a tie goes to whoever is placed later")
eq(podium.second.id, 2, "and the incumbent drops to second")

-- ---- BugContest_GetPlayersResult ------------------------------------------
eq(BugContest.playerPlace(podium), 1, "the player took first")
eq(BugContest.playerPlace({ first = entry(2, 9), second = entry(BugContest.PLAYER, 8) }),
  2, "second")
eq(BugContest.playerPlace({ first = entry(2, 9), third = entry(BugContest.PLAYER, 1) }),
  3, "third")
eq(BugContest.playerPlace({ first = entry(2, 9) }), 0,
  "and placing nowhere is 0, the consolation branch")

-- ---- BugContest_JudgeContestants ------------------------------------------
--
-- A SET flag kept that trainer off the map, so the five picked contestants are
-- the five who do NOT score.  Leaving only slot 1 in the running makes the
-- whole judging deterministic from four bytes.
local save = { party = {}, boxes = {}, inventory = {}, events = {} }
local state = BugContest.state(save)
state.contestants = {}
for slot = 2, 10 do state.contestants[slot] = true end

-- Slot 1 is Bug Catcher Don: 0 & 3 picks his KAKUNA at 300, +0.
local results = BugContest.judge(state, mon(), 374, seq(0, 0))
eq(results.first.id, BugContest.PLAYER, "374 beats Don's 300")
eq(results.second.id, 2, "and Don is second")
eq(results.third, nil, "with nobody third")
eq(BugContest.playerPlace(results), 1, "so the player wins the SUN STONE")

-- The same field, with a player score one under Don's.
results = BugContest.judge(state, mon(), 299, seq(0, 0))
eq(results.first.id, 2, "299 loses to Don's 300")
eq(BugContest.playerPlace(results), 2, "and takes the EVERSTONE instead")

-- All ten present, all rolling their first row with no bump: the top three are
-- Nick 357, Barry 366 and Cindy 341 -- so the leader board is Barry, Nick,
-- Cindy and a player on 374 still wins.
state.contestants = {}
local zeros = {}
for _ = 1, 40 do zeros[#zeros + 1] = 0 end
results = BugContest.judge(state, mon(), 374, seq(unpack(zeros)))
eq(results.first.id, BugContest.PLAYER, "374 is above every listed first row")
eq(results.second.id, BugContest.contestantId(6), "Camper Barry's 366 is next")
eq(results.third.id, BugContest.contestantId(3), "then Cooltrainer Nick's 357")

-- runJudging is the whole special: it scores wContestMon, judges, and leaves
-- the placing where BugContestJudging's `ld a, b / ld [wScriptVar], a` does.
state.contestants = {}
for slot = 2, 10 do state.contestants[slot] = true end
state.caught = mon()
eq(BugContest.runJudging(save, seq(0, 0)), 1, "runJudging answers the placing")
eq(state.playerScore, 374, "and records the score the judge used")
eq(state.results.first.id, BugContest.PLAYER, "and the podium it built")

-- Catching nothing scores 0.  With only one contestant in the field that is
-- still good enough for second, and that is NOT a bug in the port:
-- ClearContestResults zeroes all three podium slots, and CompareBytes only
-- rejects a STRICTLY smaller score, so a zero ties an empty slot and takes it.
state.caught = nil
eq(BugContest.runJudging(save, seq(0, 0)), 2,
  "a zero score still fills an empty podium slot, as the cleared struct does")

-- With a real field of five it places nowhere, which is the branch that hands
-- out the consolation BERRY.
state.contestants = { [1] = true, [2] = true, [3] = true, [4] = true,
                      [5] = true }
eq(BugContest.runJudging(save, seq(unpack(zeros))), 0,
  "against a full field an empty stock places nowhere")
for slot = 2, 10 do state.contestants[slot] = true end
state.contestants[1] = nil

-- ---- SelectRandomBugContestContestants ------------------------------------
--
-- `cp $ff / 10 * 10` rejects 250 and up, then SimpleDivide by 25 lands on
-- 0..9.  Five distinct slots, rerolling a duplicate rather than reshuffling.
local picked = BugContest.pickContestants(save, seq(0, 25, 50, 75, 100))
local count = 0
for slot in pairs(picked) do count = count + 1 end
eq(count, 5, "five contestants are picked")
for slot = 1, 5 do
  check(picked[slot], ("slot %d was picked"):format(slot))
end
check(not picked[6], "and slot 6 was not")

-- A byte of 250 or over is thrown away, and a duplicate slot is rerolled.
picked = BugContest.pickContestants(save, seq(250, 255, 0, 0, 25, 50, 75, 100))
count = 0
for _ in pairs(picked) do count = count + 1 end
eq(count, 5, "out-of-range bytes and duplicates are both rerolled")
check(picked[1] and picked[2] and picked[3] and picked[4] and picked[5],
  "and the five that stuck are the five distinct slots")

-- The five picked are the five that do NOT score.
local judged = BugContest.judge({ contestants = picked }, nil, 0,
  seq(unpack(zeros)))
check(judged.first.id >= BugContest.contestantId(6),
  "only the unpicked contestants turn up to be judged")

-- ---- the contestant flag table --------------------------------------------
--
-- data/events/bug_contest_flags.asm, which is what turns a pick into a sprite
-- that is not on the map.
local Events = require("src.world.gen2.Events")

eq(#BugContest.FLAGS, 10, "one flag per contestant, not counting the player")
for slot = 1, 10 do
  eq(BugContest.FLAGS[slot], 1813 + slot,
    ("slot %d is EVENT_BUG_CATCHING_CONTESTANT_%dA"):format(slot, slot))
end

eq(BugContest.contestantFlags(nil), BugContest.FLAGS,
  "no event tables at all falls back to the transcription")
eq(BugContest.contestantFlags({}), BugContest.FLAGS,
  "and so does a cache that predates the extractor writing it")
eq(BugContest.contestantFlags({ bugContestFlags = { 1, 2, 3 } }),
  BugContest.FLAGS, "a short table is a misread, not a source")
local extractedFlags = { 900, 901, 902, 903, 904, 905, 906, 907, 908, 909 }
eq(BugContest.contestantFlags({ bugContestFlags = extractedFlags }),
  extractedFlags, "a full one is preferred over the transcription")

do
  -- `.loop1` RESETS all ten before the five are set, so the flags the caller
  -- writes are ALL ten and not just the picks.
  local events = Events.new()
  local chosen = { [2] = true, [4] = true, [6] = true, [8] = true,
                   [10] = true }
  BugContest.applyContestantFlags(events, chosen, nil)
  for slot = 1, 10 do
    local flag = BugContest.FLAGS[slot]
    if chosen[slot] then
      check(events:get(flag), ("slot %d is flagged out of the park"):format(slot))
      check(not events:objectVisible(flag),
        ("and object %d is hidden"):format(slot))
    else
      check(not events:get(flag), ("slot %d stays in"):format(slot))
      check(events:objectVisible(flag),
        ("and object %d is drawn"):format(slot))
    end
  end

  -- A second contest must not inherit the first one's absentees: without the
  -- reset the two picks would union and the park would keep emptying.
  BugContest.applyContestantFlags(events, { [1] = true, [3] = true,
    [5] = true, [7] = true, [9] = true }, nil)
  local hidden = 0
  for slot = 1, 10 do
    if events:get(BugContest.FLAGS[slot]) then hidden = hidden + 1 end
  end
  eq(hidden, 5, "the second contest hides five, not ten")
  check(events:get(BugContest.FLAGS[1]), "the new picks are out")
  check(not events:get(BugContest.FLAGS[2]), "and the old ones are back")

  -- The extracted table is the one written when it is there.
  local other = Events.new()
  BugContest.applyContestantFlags(other, { [1] = true },
    { bugContestFlags = extractedFlags })
  check(other:get(900), "an extracted flag number is the one that is set")
  check(not other:get(BugContest.FLAGS[1]),
    "and the transcribed number is left alone")

  -- A caller with no flag store at all still picks; it just cannot hide
  -- anybody.
  eq(BugContest.applyContestantFlags(nil, chosen, nil), nil,
    "no wEventFlags is not an error")
end

-- ---- ContestMons and the contest's own encounter table ---------------------
local rows = BugContest.contestMons(nil)
eq(#rows, 11, "eleven rows, including the unreachable VENOMOTH")
local total = 0
for index = 1, 10 do total = total + rows[index].chance end
eq(total, 100, "the ten reachable rows add to exactly 100")
eq(rows[11].species, "VENOMOTH", "so the -1 fallthrough row is VENOMOTH")

-- ChooseWildEncounter_BugContest: reject a byte of 200 or more, halve it into
-- 0..99, then subtract each row's slice until it borrows.
local wild = BugContest.chooseWild(nil, seq(200, 0, 5))
eq(wild.species, "CATERPIE", "roll 0 lands in the first slice")
eq(wild.level, 7 + 5 % 12, "min 7 plus the level roll over the 12-wide span")

-- 180 halves to 90, which is inside SCYTHER's 90..94 slice.
wild = BugContest.chooseWild(nil, seq(180, 1))
eq(wild.species, "SCYTHER", "roll 90 lands on SCYTHER")
eq(wild.level, 14, "13 plus 1 & 1, over a span of two")

-- A row whose min and max match skips the level roll entirely, so no second
-- byte is consumed; check the boundary rows instead.
wild = BugContest.chooseWild(nil, seq(198, 0))
eq(wild.species, "PINSIR", "roll 99 is the last reachable slice")

-- TryWildEncounter_BugContest.  `40 percent` is `40 * $ff / 100`, so the
-- thresholds are 102 and 51 out of 256 and not 40 and 20 out of 100.
eq(BugContest.ENCOUNTER_RATE_SUPER_TALL, 102, "40 percent is 102")
eq(BugContest.ENCOUNTER_RATE_GRASS, 51, "20 percent is 51")
eq(BugContest.encounterRate(true), 102, "super tall grass is the higher rate")
eq(BugContest.encounterRate(false), 51, "ordinary grass the lower one")
check(BugContest.triggers(true, seq(101)), "a roll under the rate bites")
check(not BugContest.triggers(true, seq(102)), "a roll at the rate does not")
check(not BugContest.triggers(false, seq(51)), "and 51 is over the grass rate")

-- ---- ContestDropOffMons / ContestReturnMons -------------------------------
local function party(...)
  local list = {}
  for _, species in ipairs({ ... }) do
    list[#list + 1] = { species = species, hp = 20, maxHp = 20 }
  end
  return list
end

save = { party = party("CYNDAQUIL", "PIDGEY", "GEODUDE"), boxes = {},
         inventory = {}, events = {} }
eq(BugContest.dropOffMons(save), 0, "dropping the party off succeeds")
eq(#save.party, 1, "only the lead mon is left")
eq(save.party[1].species, "CYNDAQUIL", "and it is the lead")
eq(#BugContest.state(save).stash, 2, "the tail is stashed on the SAVE")

-- A caught mon lands in slot 2 while the tail is away, and ContestReturnMons
-- recomputes the count by walking to the terminator -- so the tail goes back
-- BEHIND it rather than over it.
save.party[2] = { species = "SCYTHER", hp = 1, maxHp = 40 }
BugContest.returnMons(save)
eq(#save.party, 4, "the party comes back with the catch in it")
eq(save.party[2].species, "SCYTHER", "the catch keeps slot 2")
eq(save.party[3].species, "PIDGEY", "and the tail lands behind it")
eq(BugContest.state(save).stash, nil, "the stash is spent")

-- `.fainted`: a lead mon on 0 HP answers TRUE, and the officer says so.
save = { party = party("CYNDAQUIL"), boxes = {}, inventory = {}, events = {} }
save.party[1].hp = 0
eq(BugContest.dropOffMons(save), 1, "a fainted lead mon refuses")
eq(#save.party, 1, "and nothing is masked off")

-- ---- GiveParkBalls, the timer and the park balls --------------------------
save = { party = party("CYNDAQUIL"), boxes = {}, inventory = {}, events = {} }
local START = { day = 10, hour = 12, minute = 0, second = 0 }
state = BugContest.start(save, START)
check(state.active, "the contest is running")
eq(state.balls, 20, "with twenty PARK BALLs")
eq(state.minutes, 20, "and twenty minutes")
eq(state.seconds, 0, "on the dot")
eq(state.caught, nil, "and nothing caught yet")
check(BugContest.isActive(save), "isActive follows the timer flag")

-- CheckBugContestTimer subtracts the time since the LAST poll, because
-- CalcSecsMinsHoursDaysSince advances the stored stamp as it reads it.
check(not BugContest.tickTimer(save, { day = 10, hour = 12, minute = 5, second = 30 }),
  "five and a half minutes in, the contest runs on")
eq(state.minutes, 14, "14 minutes left")
eq(state.seconds, 30, "and 30 seconds")
check(not BugContest.tickTimer(save, { day = 10, hour = 12, minute = 10, second = 0 }),
  "another four and a half minutes")
eq(state.minutes, 10, "10 minutes left")
eq(state.seconds, 0, "flat")

-- Landing on exactly 0:00 does NOT end it: `sbc` leaves no borrow, so the
-- routine returns with the carry clear and the NEXT poll is the one that ends
-- the contest.
check(not BugContest.tickTimer(save, { day = 10, hour = 12, minute = 20, second = 0 }),
  "hitting 0:00 exactly is still not over")
eq(state.minutes, 0, "the clock reads 0")
eq(state.seconds, 0, "00")
check(BugContest.tickTimer(save, { day = 10, hour = 12, minute = 20, second = 1 }),
  "one more second ends it")

-- Ending zeroes both halves of the clock.
local left, secs = BugContest.timeLeft(save)
eq(left, 0, "no minutes left")
eq(secs, 0, "no seconds either")

-- Any whole hour or day of elapsed time ends it outright, and so does a clock
-- wound BACKWARDS: _CalcDaysSince and its siblings wrap a negative difference
-- into a large positive one instead of clamping it, so a rewound clock reads
-- as an enormous jump forward.
save = { party = party("CYNDAQUIL"), boxes = {}, inventory = {}, events = {} }
BugContest.start(save, START)
check(BugContest.tickTimer(save, { day = 10, hour = 13, minute = 0, second = 0 }),
  "an hour later the contest is over")

save = { party = party("CYNDAQUIL"), boxes = {}, inventory = {}, events = {} }
BugContest.start(save, START)
check(BugContest.tickTimer(save, { day = 11, hour = 12, minute = 0, second = 0 }),
  "and so is a day later")

save = { party = party("CYNDAQUIL"), boxes = {}, inventory = {}, events = {} }
BugContest.start(save, START)
check(BugContest.tickTimer(save, { day = 10, hour = 11, minute = 59, second = 0 }),
  "winding the clock back one minute ends the contest, as it does on the cart")

-- A stopped contest polls to nothing.
BugContest.stop(save)
check(not BugContest.isActive(save), "clearflag ENGINE_BUG_CONTEST_TIMER")
check(not BugContest.tickTimer(save, { day = 12, hour = 0, minute = 0, second = 0 }),
  "and a stopped clock never ends again")

-- ---- the park balls -------------------------------------------------------
save = { party = party("CYNDAQUIL"), boxes = {}, inventory = {}, events = {} }
state = BugContest.start(save, START)
eq(BugContest.ballsLeft(save), 20, "twenty to start")
check(not BugContest.isOver(save), "and the contest is not over")

-- A Park Ball is never in the bag: PokeBallEffect's `.used_park_ball` does
-- `dec [hl]` on wParkBallsRemaining instead of tossing an item.
local kind = BugContest.catch(save, mon({ species = "CATERPIE" }))
eq(kind, BugContest.KEEP_FIRST, "the first catch is kept with no question")
eq(BugContest.ballsLeft(save), 19, "and cost one ball")
eq(save.inventory.PARK_BALL, nil, "the bag never held a PARK BALL")
eq(BugContest.caughtMon(save).species, "CATERPIE", "the catch is in stock")

-- A second catch asks instead of replacing.
local ask, stock, fresh = BugContest.catch(save, mon({ species = "SCYTHER" }))
eq(ask, BugContest.ASK_SWITCH, "the second catch asks")
eq(stock.species, "CATERPIE", "handing back the stock mon")
eq(fresh.species, "SCYTHER", "and the new one")
eq(BugContest.caughtMon(save).species, "CATERPIE",
  "and declining -- which is what B does -- keeps the stock mon")
eq(BugContest.ballsLeft(save), 18, "the asking still cost a ball")

BugContest.switchCaught(save, fresh)
eq(BugContest.caughtMon(save).species, "SCYTHER", "saying YES swaps it in")

-- CheckContestBattleOver: an empty ball count is what ends the contest early.
state.balls = 1
BugContest.useBall(save)
eq(BugContest.ballsLeft(save), 0, "the last ball is spent")
check(BugContest.isOver(save), "which ends the contest")
BugContest.useBall(save)
eq(BugContest.ballsLeft(save), 0, "and the count never goes negative")

-- ---- CheckPartyFullAfterContest -------------------------------------------
save = { party = party("CYNDAQUIL"), boxes = {}, boxNames = {}, currentBox = 1,
         inventory = {}, events = {} }
BugContest.start(save, START)
BugContest.catch(save, mon({ species = "PINSIR" }))
local answer, kept = BugContest.collectCaughtMon(save)
eq(answer, BugContest.CAUGHT_MON, "a party with room takes the catch")
eq(kept.species, "PINSIR", "and it is the mon that was caught")
eq(save.party[2].species, "PINSIR", "which joins the party")
eq(BugContest.caughtMon(save), nil, "and wContestMon is cleared")

eq(BugContest.collectCaughtMon(save), BugContest.NO_CATCH,
  "catching nothing answers BUGCONTEST_NO_CATCH")

-- A full party sends it to the current box instead.
save = { party = party("A", "B", "C", "D", "E", "F"), boxes = {},
         boxNames = {}, currentBox = 3, inventory = {}, events = {} }
BugContest.start(save, START)
BugContest.catch(save, mon({ species = "PINSIR" }))
answer = BugContest.collectCaughtMon(save)
eq(answer, BugContest.BOXED_MON, "a full party boxes the catch")
eq(#save.party, 6, "the party is untouched")
local Boxes = require("src.core.gen2.Boxes")
eq(Boxes.box(save, 3)[1].species, "PINSIR", "and it landed in the current box")

--------------------------------------------------------------------------
-- Kurt and the apricorns
--------------------------------------------------------------------------

-- ---- every apricorn to ball mapping ---------------------------------------
local WANT = {
  { "RED_APRICORN", "LEVEL_BALL" },
  { "BLU_APRICORN", "LURE_BALL" },
  { "YLW_APRICORN", "MOON_BALL" },
  { "GRN_APRICORN", "FRIEND_BALL" },
  { "WHT_APRICORN", "FAST_BALL" },
  { "BLK_APRICORN", "HEAVY_BALL" },
  { "PNK_APRICORN", "LOVE_BALL" },
}
eq(#Apricorns.BALLS, 7, "seven apricorns")
for index, row in ipairs(WANT) do
  eq(Apricorns.ballFor(row[1]), row[2], row[1] .. " becomes a " .. row[2])
  eq(Apricorns.apricornFor(row[2]), row[1], "and back again")
  eq(Apricorns.BALLS[index].apricorn, row[1],
    ("row %d is in ApricornBalls order"):format(index))
end
eq(Apricorns.ballFor("BERRY"), nil, "a berry is not an apricorn")
check(Apricorns.isApricorn("PNK_APRICORN"), "the pink one is")
check(not Apricorns.isApricorn("POKE_BALL"), "a POKE BALL is not")

-- ---- FindApricornsInBag ---------------------------------------------------
--
-- The list is always in ApricornBalls order, never pack order, and always ends
-- in the CANCEL row that wKurtApricornCount counts.
local bag = { PNK_APRICORN = 1, RED_APRICORN = 3, GRN_APRICORN = 1 }
local list = Apricorns.bagList(bag)
eq(#list, 3, "three apricorns in the bag")
eq(list[1], "RED_APRICORN", "red first, whatever order the pack is in")
eq(list[2], "GRN_APRICORN", "then green")
eq(list[3], "PNK_APRICORN", "then pink")
eq(list.cancel, 4, "and CANCEL is the fourth row")
check(not list.empty, "the list is not empty")

local none = Apricorns.bagList({})
check(none.empty, "an apricorn-free bag is the `scf` case")
eq(none.cancel, 1, "whose only row is CANCEL")

eq(Apricorns.select(bag, 2), "GRN_APRICORN", "picking row 2 gives the green one")
eq(Apricorns.select(bag, 4), nil, "picking CANCEL gives FALSE")
eq(Apricorns.select({}, 1), nil, "and an empty bag always gives FALSE")

-- ---- the handover ---------------------------------------------------------
save = { inventory = { RED_APRICORN = 2, BLU_APRICORN = 1 }, events = {},
         engineFlags = {} }
local ok, ball = Apricorns.give(save, "RED_APRICORN")
check(ok, "Kurt takes the red apricorn")
eq(ball, "LEVEL_BALL", "and promises a LEVEL BALL")
-- SelectApricornForKurt's TossItem takes exactly one, and the map script never
-- takes any -- so a port that does both would eat two.
eq(save.inventory.RED_APRICORN, 1, "exactly one apricorn leaves the bag")
eq(save.inventory.BLU_APRICORN, 1, "the others are untouched")
-- 600, not the 237 counting the `const` lines gives: `const_next 600` sits two
-- lines above the block in constants/event_flags.asm, and the extracted Kurt1
-- script's red arm is `setevent 600`.  save.events is wEventFlags as bytes.
eq(Apricorns.BALLS[1].event, 600, "EVENT_GAVE_KURT_RED_APRICORN is 600")
check(Apricorns.event(save, 600), "EVENT_GAVE_KURT_RED_APRICORN is set")
eq(save.events[75], 1, "as bit 0 of wEventFlags byte 75, the way SRAM holds it")
check(not Apricorns.event(save, 601), "and its neighbour is untouched")
check(Apricorns.isWorking(save), "and ENGINE_KURT_MAKING_BALLS with it")

eq(Apricorns.pending(save), "RED_APRICORN", "he is holding the red one")
eq(Apricorns.readyBall(save), nil, "and while he works there is no ball")

check(not Apricorns.give(save, "YLW_APRICORN"),
  "an apricorn the bag does not hold cannot be handed over")
check(not Apricorns.give(save, "BERRY"), "and neither can a berry")

-- ---- the day-long wait ----------------------------------------------------
--
-- Nothing about Kurt runs a timer.  ENGINE_KURT_MAKING_BALLS is wDailyFlags1
-- bit 0, and CheckDailyResetTimer clearing both daily-flag bytes is the ONLY
-- thing that ever finishes his work.
local DAY10 = { day = 10, hour = 9, minute = 0, second = 0 }
Apricorns.startDailyResetTimer(save, DAY10)
eq(save.dailyReset.remaining, 1, "the daily timer counts one day")
eq(save.dailyReset.day, 10, "from today")

check(not Apricorns.checkDailyResetTimer(save,
  { day = 10, hour = 23, minute = 59, second = 59 }),
  "the same calendar day never rolls over, however late it gets")
check(Apricorns.isWorking(save), "so Kurt is still working")
eq(Apricorns.readyBall(save), nil, "and the ball is not ready")

check(Apricorns.checkDailyResetTimer(save, { day = 11, hour = 0, minute = 1 }),
  "one minute past midnight the next day IS the rollover")
check(not Apricorns.isWorking(save), "which clears ENGINE_KURT_MAKING_BALLS")
eq(Apricorns.readyBall(save), "LEVEL_BALL", "and the LEVEL BALL is ready")
eq(save.dailyReset.remaining, 1, "the timer restarts for the next day")
eq(save.dailyReset.day, 11, "from the new day")

-- The rollover wipes every wDailyFlags1/2 bit, not just Kurt's.
save.engineFlags[Apricorns.ENGINE_ALL_FRUIT_TREES] = true
save.engineFlags[80] = true                      -- ENGINE_DAILY_BUG_CONTEST
save.engineFlags[BugContest.ENGINE_BUG_CONTEST_TIMER] = true
save.engineFlags[26] = true                      -- ENGINE_ZEPHYRBADGE
check(Apricorns.checkDailyResetTimer(save, { day = 12, hour = 0, minute = 0 }),
  "the next day rolls over too")
eq(save.engineFlags[Apricorns.ENGINE_ALL_FRUIT_TREES], nil,
  "the fruit trees refill")
eq(save.engineFlags[80], nil, "the contest can be entered again")
check(save.engineFlags[BugContest.ENGINE_BUG_CONTEST_TIMER],
  "but ENGINE_BUG_CONTEST_TIMER lives in wStatusFlags2 and survives")
check(save.engineFlags[26], "and a badge is not a daily flag either")

-- Collecting the ball is what clears the colour's event, and only after the
-- ball is actually in hand: `verbosegiveitem / iffalse .NoRoomForBall`.
local got, spent = Apricorns.collect(save)
eq(got, "LEVEL_BALL", "the ball comes back")
eq(spent, "RED_APRICORN", "for the apricorn that made it")
check(not save.events[237], "and the event is cleared")
eq(Apricorns.pending(save), nil, "so Kurt is holding nothing")
eq(Apricorns.collect(save), nil, "and has nothing more to hand over")

-- ---- the clock wound backwards --------------------------------------------
--
-- _CalcDaysSince wraps a negative difference by adding 20 * 7, so setting the
-- system clock back a day reads as 139 days FORWARD and rolls the daily flags
-- immediately.  The cart does nothing about this and neither does the port;
-- the test exists so the behaviour is a decision rather than an accident.
save = { inventory = { BLK_APRICORN = 1 }, events = {}, engineFlags = {} }
Apricorns.give(save, "BLK_APRICORN")
Apricorns.startDailyResetTimer(save, { day = 10, hour = 12 })
check(Apricorns.isWorking(save), "Kurt starts on the heavy ball")
check(Apricorns.checkDailyResetTimer(save, { day = 9, hour = 12 }),
  "winding the clock back a day rolls the daily flags anyway")
eq(Apricorns.readyBall(save), "HEAVY_BALL",
  "so the HEAVY BALL is ready early, exactly as it is on the cart")
eq(save.dailyReset.day, 9, "and the timer restarts from the new day")

-- A save with no timer at all starts one rather than rolling over on the spot.
save = { inventory = {}, events = {}, engineFlags = {} }
check(not Apricorns.checkDailyResetTimer(save, { day = 5 }),
  "a fresh save arms the daily timer instead of firing it")
eq(save.dailyReset.day, 5, "from the day it first ran")

-- UpdateTimeRemaining's -1 sentinel: an elapsed span too large for its unit
-- expires the counter outright.
local remaining, expired = Apricorns.updateTimeRemaining(5, -1)
eq(remaining, 0, "an out-of-range elapsed span zeroes the counter")
check(expired, "and expires it")
remaining, expired = Apricorns.updateTimeRemaining(3, 1)
eq(remaining, 2, "an ordinary day decrements it")
check(not expired, "without expiring it")

-- ---- the fruit trees ------------------------------------------------------
eq(Apricorns.NUM_FRUIT_TREES, 30, "thirty fruit trees")
-- FRUITTREE_* opens `const_def 1`, so the ids are 1-based and a 1-based Lua
-- list lines up with them: tree 1 is Route 29's BERRY and tree 30 is Fuchsia's
-- BURNT BERRY.  A 0-based table would shift every row and drop the last.
eq(Apricorns.treeFruit(1), "BERRY", "tree 1 is FRUITTREE_ROUTE_29")
eq(Apricorns.treeFruit(30), "BURNT_BERRY", "tree 30 is FRUITTREE_FUCHSIA_CITY")
eq(Apricorns.treeFruit(0), nil, "there is no tree 0")
eq(Apricorns.treeFruit(31), nil, "and no tree 31")
-- The seven apricorn trees, which is why they live in this module.
eq(Apricorns.treeFruit(17), "RED_APRICORN", "Route 37's first tree")
eq(Apricorns.treeFruit(18), "BLU_APRICORN", "its second")
eq(Apricorns.treeFruit(19), "BLK_APRICORN", "its third")
eq(Apricorns.treeFruit(20), "WHT_APRICORN", "Azalea Town's")
eq(Apricorns.treeFruit(21), "PNK_APRICORN", "Route 42's first")
eq(Apricorns.treeFruit(22), "GRN_APRICORN", "its second")
eq(Apricorns.treeFruit(23), "YLW_APRICORN", "its third")
local apricornTrees = 0
for _, item in ipairs(Apricorns.FRUIT_TREES) do
  if Apricorns.isApricorn(item) then apricornTrees = apricornTrees + 1 end
end
eq(apricornTrees, 7, "seven of the thirty trees grow apricorns")

save = { inventory = {}, events = {}, engineFlags = {} }
check(Apricorns.tryResetFruitTrees(save), "the first visit of the day refills")
check(not Apricorns.tryResetFruitTrees(save), "the second does not")
check(not Apricorns.treePicked(save, 20), "Azalea's tree has fruit")
eq(Apricorns.pickTree(save, 20), "WHT_APRICORN", "which is a white apricorn")
check(Apricorns.treePicked(save, 20), "and now it is picked")
eq(Apricorns.pickTree(save, 20), nil, "so it gives nothing twice")
eq(Apricorns.pickTree(save, 99), nil, "and a tree that does not exist gives nothing")
Apricorns.dailyReset(save)
check(Apricorns.tryResetFruitTrees(save), "the rollover lets them refill again")
check(not Apricorns.treePicked(save, 20), "and Azalea's tree bears fruit again")

--------------------------------------------------------------------------
-- The screen
--------------------------------------------------------------------------
--
-- Every Gold screen is reached through a src/ui/Screens.lua id, so ContestMenu
-- names the id it must be registered under and this asserts the registration
-- resolves to this module once src/ui/Screens.lua carries it.  The check is
-- written to pass either way, because Screens.lua belongs to another file's
-- owner: what it must never do is resolve the id to something else.
local Screens = require("src.ui.Screens")
eq(BugContest.SCREEN_ID, "Gen2ContestMenu", "the screen id the module claims")
local registered = false
for _, id in ipairs(Screens.GEN2_IDS) do
  if id == BugContest.SCREEN_ID then registered = true end
end
if registered then
  eq(Screens.get({}, BugContest.SCREEN_ID),
    require("src.ui.gen2.ContestMenu"),
    "and the id resolves to src/ui/gen2/ContestMenu.lua")
else
  check(true, "the id is not registered in src/ui/Screens.lua yet")
end

local ContestMenu = require("src.ui.gen2.ContestMenu")
eq(ContestMenu.TEXT.stock, " STOCK <PK><MN> ",
  "the STOCK label keeps its spaces, which is what erases the border under it")
eq(ContestMenu.TEXT.this, " THIS <PK><MN> ", "and so does THIS")
eq(ContestMenu.TEXT.askSwitch, "Switch #MON?", "_ContestAskSwitchText")

-- The screen decides nothing: yes swaps the stock mon, no and B both keep it.
local function fakeInput(pressed)
  return { wasPressed = function(_, key) return pressed == key end }
end

save = { party = {}, boxes = {}, inventory = {}, events = {} }
BugContest.start(save, START)
BugContest.catch(save, mon({ species = "CATERPIE" }))
local _, stockMon, freshMon = BugContest.catch(save, mon({ species = "PINSIR" }))

local answered
local screen = ContestMenu.new({ save = save }, {
  save = save, stock = stockMon, caught = freshMon,
  onClose = function(keptMon) answered = keptMon end,
})
eq(screen.choice, 1, "PlaceYesNoBox opens on YES")
screen.game.input = fakeInput("b")
screen:update(0)
eq(answered.species, "CATERPIE", "B is the NO arm and keeps the stock mon")
eq(BugContest.caughtMon(save).species, "CATERPIE", "so the state is unchanged")

answered = nil
screen = ContestMenu.new({ save = save }, {
  save = save, stock = stockMon, caught = freshMon,
  onClose = function(keptMon) answered = keptMon end,
})
screen.game.input = fakeInput("a")
screen:update(0)
eq(answered.species, "PINSIR", "A on YES swaps the new mon in")
eq(BugContest.caughtMon(save).species, "PINSIR", "and the state follows")

answered = nil
screen = ContestMenu.new({ save = save }, {
  save = save, stock = freshMon, caught = stockMon,
  onClose = function(keptMon) answered = keptMon end,
})
screen.game.input = fakeInput("down")
screen:update(0)
eq(screen.choice, 2, "down moves the cursor to NO")
screen.game.input = fakeInput("a")
screen:update(0)
eq(answered.species, "PINSIR", "and A on NO keeps the stock mon")

-- ---------------------------------------------------------------------------
-- The call sites (the half that was missing)
-- ---------------------------------------------------------------------------
--
-- Every rule above was already ported and tested, and NOTHING started a
-- contest: BugContestJudging was a stub and no wild roll, no clock and no park
-- ball ever reached this module.  This section drives the six specials the gate
-- scripts call, and then reads the two files whose call sites cannot be
-- constructed headless (World needs a map and a stack, BattleState needs love)
-- and asserts the wiring is spelled out in them.

local Specials = require("src.script.gen2.Specials")

-- A Vm as far as a special can tell: the hook table, wScriptVar, and the two
-- methods a handler may call to talk to the player.  `events` and
-- `eventTables` are on the VM itself rather than in the hook table, which is
-- where Vm.new puts them and therefore where a handler has to look; the
-- rebuild counter stands in for World's deferred reloadSprites.
local function fakeVm(record, sfx)
  local vm = { scriptVar = 0, texts = {}, rebuilds = 0 }
  vm.events = Events.new()
  vm.eventTables = {}
  vm.onFlagsChanged = function() vm.rebuilds = vm.rebuilds + 1 end
  vm.specials = {
    save = function() return record end,
    party = function() return record.party end,
    monName = function(species) return species end,
    playSfxNamed = function(name) sfx[#sfx + 1] = name end,
  }
  function vm:showRaw(body) self.texts[#self.texts + 1] = body end
  function vm:setStringBuffer(value) self.stringBuffer = value end
  return vm
end

-- CheckPartyFullAfterContest asks GiveANickname_YesNo, so it yields the way
-- every prompting special does: run it on a coroutine and feed the answer back.
-- `yes` is what the YES/NO box returns; `typed` is what the keyboard hands over
-- (nil means the player backed out of it).
local function runContestCollect(vm, record, yes, typed)
  vm.specials.renameMon = function(_mon, done) done(typed) end
  vm.co = coroutine.create(function()
    Specials.HANDLERS.CheckPartyFullAfterContest(vm)
  end)
  local ok, req = coroutine.resume(vm.co)
  while ok and coroutine.status(vm.co) ~= "dead" do
    local answer = nil
    if req and req.kind == "yesorno" then answer = yes end
    ok, req = coroutine.resume(vm.co, answer)
  end
  if not ok then error(req) end
end

check(Specials.STUBS.BugContestJudging == nil,
  "BugContestJudging is no longer a stub")
eq(type(Specials.HANDLERS.BugContestJudging), "function",
  "it is a handler now")
for _, name in ipairs({ "ContestDropOffMons", "ContestReturnMons",
    "GiveParkBalls", "CheckPartyFullAfterContest",
    "SelectRandomBugContestContestants" }) do
  eq(type(Specials.HANDLERS[name]), "function", name .. " is ported")
end

do
  local sfx = {}
  local record = {
    player = { name = "GOLD" },
    party = { mon({ species = "CHIKORITA" }), mon({ species = "MAGIKARP" }),
              mon({ species = "SHUCKLE" }) },
    boxes = {}, inventory = {}, events = {},
  }
  local vm = fakeVm(record, sfx)

  -- Route35NationalParkGate_OkayToProceed, in its order.
  Specials.HANDLERS.ContestDropOffMons(vm)
  eq(vm.scriptVar, 0, "a healthy lead mon is accepted")
  eq(#record.party, 1, "and the tail is masked away")
  eq(#(BugContest.state(record).stash or {}), 2,
    "onto the SAVE, so a reload mid-contest still has it")

  Specials.HANDLERS.GiveParkBalls(vm)
  check(BugContest.isActive(record), "GiveParkBalls starts the contest")
  eq(BugContest.ballsLeft(record), 20, "with twenty park balls")
  eq(select(1, BugContest.timeLeft(record)), 20, "and twenty minutes")

  Specials.HANDLERS.SelectRandomBugContestContestants(vm)
  local picked, slots = 0, 0
  for slot, set in pairs(BugContest.state(record).contestants or {}) do
    if set == true then picked = picked + 1 end
    if type(slot) == "number" and slot >= 1 and slot <= 10 then
      slots = slots + 1
    end
  end
  eq(picked, 5, "five of the ten contestant flags are set")
  eq(slots, 5, "and the table is keyed by SLOT, which is what judging reads")

  -- The pick reaches wEventFlags, which is the only thing that takes those
  -- five sprites off NationalParkBugContest.  Five hidden and five drawn: a
  -- handler that only stored the pick on the save left all ten standing there.
  local hidden, drawn = 0, 0
  for slot = 1, BugContest.NUM_CONTESTANTS do
    local flag = BugContest.FLAGS[slot]
    if vm.events:objectVisible(flag) then drawn = drawn + 1
    else hidden = hidden + 1 end
    eq(vm.events:get(flag),
      BugContest.state(record).contestants[slot] == true,
      ("slot %d's flag matches its pick"):format(slot))
  end
  eq(hidden, 5, "five contestants are flagged out of the park")
  eq(drawn, 5, "and the other five are still drawn")
  eq(vm.rebuilds, 1, "and the map is told once that the flags moved")

  -- The catch, as the battle screen makes it: held, not added.
  BugContest.catch(record, mon({ species = "SCYTHER", maxHp = 255,
    stats = { hp = 255, attack = 255, defense = 255, speed = 255,
              specialAttack = 255, specialDefense = 255 } }))
  eq(#record.party, 1, "a contest catch does not join the party")
  eq(BugContest.ballsLeft(record), 19, "and it costs a park ball")

  -- BugContestResultsScript, in its order.
  Specials.HANDLERS.BugContestJudging(vm)
  eq(vm.scriptVar, 1, "an unbeatable score places FIRST")
  eq(#vm.texts, 6, "three winners, each with its own score page")
  check(vm.texts[5]:find("GOLD", 1, true) ~= nil,
    "and the winner named on the first-place page is the player")
  eq(sfx[#sfx], "Sfx_1stPlace", "the first-place jingle plays last")

  BugContest.stop(record)
  check(not BugContest.isActive(record), "clearflag stops the clock")
  Specials.HANDLERS.ContestReturnMons(vm)
  eq(#record.party, 3, "the party comes back")
  eq(record.party[2].species, "MAGIKARP", "in its old order")

  local textsBefore = #vm.texts
  runContestCollect(vm, record, true, "BUZZ")
  eq(vm.scriptVar, BugContest.CAUGHT_MON,
    "BUGCONTEST_CAUGHT_MON is 0, and the gate's ifequal reads it")
  eq(#record.party, 4, "the held mon joins the party last")
  eq(record.party[4].species, "SCYTHER", "and it is the mon that was caught")
  -- GiveANickname_YesNo (engine/pokemon/caught_nickname.asm) is the last thing
  -- the contest asks, and it asks on the party arm as well as the box one.
  eq(#vm.texts, textsBefore + 1, "the nickname prompt is printed")
  check(vm.texts[#vm.texts]:find("nickname", 1, true) ~= nil,
    "and it is _CaughtAskNicknameText")
  eq(vm.stringBuffer, "SCYTHER",
    "GetPokemonName fills {STRBUF} with the species before the prompt")
  eq(record.party[4].nickname, "BUZZ", "a typed name is kept")
end

-- NO, and a keyboard the player backed out of, both leave the species name.
do
  local record = { party = {}, boxes = {}, inventory = {}, events = {} }
  local vm = fakeVm(record, {})
  BugContest.start(record)
  BugContest.catch(record, mon({ species = "WEEDLE" }))
  runContestCollect(vm, record, false, "IGNORED")
  eq(record.party[1].nickname, nil, "answering NO skips the keyboard")

  local record2 = { party = {}, boxes = {}, inventory = {}, events = {} }
  local vm2 = fakeVm(record2, {})
  BugContest.start(record2)
  BugContest.catch(record2, mon({ species = "PARAS" }))
  runContestCollect(vm2, record2, true, nil)
  eq(record2.party[1].nickname, nil,
    "and an empty entry keeps the species name, the way InitNickname does")
end

-- A full party sends the catch to the box, which is the branch that prints
-- ContestResults_PartyFullText.
do
  local record = { party = {}, boxes = {}, inventory = {}, events = {} }
  for _ = 1, 6 do record.party[#record.party + 1] = mon() end
  local vm = fakeVm(record, {})
  BugContest.start(record)
  BugContest.catch(record, mon({ species = "PINSIR" }))
  runContestCollect(vm, record, true, "PINCH")
  eq(vm.scriptVar, BugContest.BOXED_MON, "a full party boxes it")
  eq(#record.party, 6, "and the party is untouched")
  local boxed = require("src.core.gen2.Boxes").box(record, record.currentBox or 1)
  eq(boxed and boxed[#boxed] and boxed[#boxed].nickname, "PINCH",
    "the box arm asks for a nickname too")
  local texts = #vm.texts
  runContestCollect(vm, record, true, "NOPE")
  eq(vm.scriptVar, BugContest.NO_CATCH,
    "and with nothing held the answer is BUGCONTEST_NO_CATCH")
  eq(#vm.texts, texts, "which asks nothing")
end

-- TryWildEncounter_BugContest reads CheckSuperTallGrassTile, which is the LONG
-- grass pair alone -- the ordinary tall grass takes the 20 percent rate.
local Permissions = require("src.world.gen2.Permissions")
check(Permissions.isSuperTallGrass(0x14), "COLL_LONG_GRASS is super tall")
check(Permissions.isSuperTallGrass(0x1c), "and so is its unused alias")
check(not Permissions.isSuperTallGrass(0x18),
  "COLL_TALL_GRASS is not, so it rolls at 20 percent")
check(not Permissions.isSuperTallGrass(nil), "and no tile at all is not")

-- ---- SelectApricornForKurt ------------------------------------------------
--
-- The special is the whole of Kurt's port that is not in maps/KurtsHouse.asm:
-- the menu, the item id it leaves in wScriptVar for the `ifequal BLU_APRICORN`
-- ladder, and the TossItem the script never does.
check(Specials.STUBS.SelectApricornForKurt == nil,
  "SelectApricornForKurt is no longer a stub")
eq(type(Specials.HANDLERS.SelectApricornForKurt), "function",
  "it is a handler now")

-- The item indices Kurt's ladder compares against, out of the extracted
-- items.lua -- and they are the same six the extracted script's own `ifequal`
-- rows carry, in .Blu .Ylw .Grn .Wht .Blk .Pnk order.
local APRICORN_ITEM = {
  RED_APRICORN = 85, BLU_APRICORN = 89, YLW_APRICORN = 92, GRN_APRICORN = 93,
  WHT_APRICORN = 97, BLK_APRICORN = 99, PNK_APRICORN = 101,
}

-- A Vm whose menu answers on the spot, which is the synchronous arm of
-- Specials.block; `pick` is the row the player lands on.
local function kurtVm(record, pick)
  local vm = { scriptVar = 0xff, menus = {} }
  vm.specials = {
    save = function() return record end,
    itemName = function(id) return (id:gsub("_APRICORN", " APRICORN")) end,
    itemIndex = function(id) return APRICORN_ITEM[id] end,
    scriptMenu = function(header, onChoose)
      vm.menus[#vm.menus + 1] = header
      onChoose(pick)
    end,
  }
  return vm
end

do
  local record = { inventory = { PNK_APRICORN = 1, RED_APRICORN = 2,
    GRN_APRICORN = 1 }, events = {}, engineFlags = {} }
  local vm = kurtVm(record, 2)
  Specials.HANDLERS.SelectApricornForKurt(vm)
  local header = vm.menus[1]
  check(header ~= nil, "the menu opens")
  eq(#header.items, 4, "three apricorns and the CANCEL row")
  eq(header.items[1], "RED APRICORN", "in ApricornBalls order, not pack order")
  eq(header.items[2], "GRN APRICORN", "green second")
  eq(header.items[4], "CANCEL", "and CANCEL last, the way .Name draws it")
  eq(header.right, 14, "menu_coords 0, 0, 14, 17")
  eq(header.bottom, 17, "bottom included")
  eq(vm.scriptVar, 93, "wScriptVar is GRN_APRICORN's ITEM id, not its row")
  eq(record.inventory.GRN_APRICORN, nil, "TossItem takes the one it had")
  eq(record.inventory.RED_APRICORN, 2, "and leaves the rest of the pack alone")

  -- `jr c, .nope`: B, or the CANCEL row, is FALSE and costs nothing.
  vm = kurtVm(record, 0)
  Specials.HANDLERS.SelectApricornForKurt(vm)
  eq(vm.scriptVar, 0, "backing out is FALSE")
  eq(record.inventory.RED_APRICORN, 2, "and no apricorn is taken")

  vm = kurtVm(record, 3)
  Specials.HANDLERS.SelectApricornForKurt(vm)
  eq(vm.scriptVar, 0, "so is the CANCEL row itself")
  eq(record.inventory.PNK_APRICORN, 1, "with the pink one still in the pack")

  -- FindApricornsInBag's `scf`: no menu at all, and the script's `ifequal
  -- FALSE` sends Kurt to .Cancel.
  local empty = { inventory = { BERRY = 5 }, events = {}, engineFlags = {} }
  vm = kurtVm(empty, 1)
  Specials.HANDLERS.SelectApricornForKurt(vm)
  eq(vm.scriptVar, 0, "an apricorn-free pack never opens the menu")
  eq(#vm.menus, 0, "no menu was asked for")
  eq(empty.inventory.BERRY, 5, "and nothing was tossed")

  -- No item table to resolve against is not a licence to guess: an answer the
  -- ladder cannot match would fall through to .Red.
  local bag = { inventory = { BLU_APRICORN = 1 }, events = {},
    engineFlags = {} }
  vm = kurtVm(bag, 1)
  vm.specials.itemIndex = function() return nil end
  Specials.HANDLERS.SelectApricornForKurt(vm)
  eq(vm.scriptVar, 0, "an unresolvable item is FALSE")
  eq(bag.inventory.BLU_APRICORN, 1, "and the apricorn stays in the pack")
end

-- ---- the fruit trees ------------------------------------------------------
--
-- FruitTreeItems is thirty entries with seven apricorns in it, and the ids are
-- 1-based (`const_def 1`).
eq(Apricorns.NUM_FRUIT_TREES, 30, "thirty fruit trees")
eq(Apricorns.treeFruit(1), "BERRY", "FRUITTREE_ROUTE_29 is a BERRY")
eq(Apricorns.treeFruit(0x11), "RED_APRICORN",
  "FRUITTREE_ROUTE_37_1 is the RED APRICORN")
eq(Apricorns.treeFruit(0x17), "YLW_APRICORN",
  "FRUITTREE_ROUTE_42_3 is the YELLOW one")

do
  local record = { inventory = {}, events = {}, engineFlags = {} }
  check(Apricorns.tryResetFruitTrees(record),
    "the first tree examined refills them all")
  check(not Apricorns.tryResetFruitTrees(record),
    "and ENGINE_ALL_FRUIT_TREES stops it happening twice in a day")
  eq(Apricorns.pickTree(record, 0x11), "RED_APRICORN", "picking gives fruit")
  check(Apricorns.treePicked(record, 0x11), "which sets the tree's flag")
  eq(Apricorns.pickTree(record, 0x11), nil, "so it cannot be picked again")
  check(not Apricorns.treePicked(record, 0x12), "the next tree is untouched")

  Apricorns.startDailyResetTimer(record, { day = 3 })
  check(Apricorns.checkDailyResetTimer(record, { day = 4 }),
    "the daily rollover comes")
  check(Apricorns.tryResetFruitTrees(record),
    "and the next tree examined refills the lot")
  check(not Apricorns.treePicked(record, 0x11),
    "so route 37's red apricorn is back")
end

-- The two call sites a headless test cannot construct.  Reading the source is
-- the honest check here: World needs a map, a stack and a VM, and BattleState
-- needs love -- but a call site that is not spelled out in the file is not
-- there at all, which is exactly the failure this whole item is about.
local function sourceOf(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

do
  local world = sourceOf("src/world/gen2/World.lua")
  check(world ~= nil, "World's source is readable")
  for _, wanted in ipairs({
      "function World:tryContestEncounter",
      "self:tryContestEncounter(collision)",
      "function World:checkTimeEvents",
      "self:checkTimeEvents()",
      "function World:bugContestOver",
      "function World:bugContestBattleOver",
      "self:bugContestBattleOver()",
      "BugContestResultsWarpScript",
      "FieldMoves.BUG_CONTEST_FLAG",
      -- Kurt's menu and the item pair the ladder needs.
      "scriptMenu = function(header, onChoose)",
      "itemIndex = function(id)",
      -- FruitTreeScript's four hooks, all four now over Apricorns.
      "function World:fruitTreeItem",
      "Apricorns.treeFruit(treeId)",
      "function World:fruitTreeReset",
      "Apricorns.tryResetFruitTrees(save)",
      "Apricorns.treePicked(save, treeId)",
      "Apricorns.pickTree(save, treeId)",
      "fruitTreeReset = function() return self:fruitTreeReset() end,",
      "Apricorns.checkDailyResetTimer(save)",
    }) do
    check(world:find(wanted, 1, true) ~= nil, "World has " .. wanted)
  end

  -- TryResetFruitTrees runs inside the VM's transcribed FruitTreeScript, above
  -- the CheckFruitTree it gates.
  local vmSource = sourceOf("src/script/gen2/Vm.lua")
  check(vmSource ~= nil, "the VM's source is readable")
  for _, wanted in ipairs({
      "fruitTreeResetFn = hooks.fruitTreeReset,",
      "if self.fruitTreeResetFn then self.fruitTreeResetFn() end",
    }) do
    check(vmSource:find(wanted, 1, true) ~= nil, "the VM has " .. wanted)
  end

  local battle = sourceOf("src/ui/gen2/BattleState.lua")
  check(battle ~= nil, "BattleState's source is readable")
  for _, wanted in ipairs({
      "function BattleState:throwParkBall",
      "self:throwParkBall()",
      "function BattleState:contestCatch",
      "self:contestCatch(enemy)",
      "BugContest.useBall(save)",
      "BugContest.isOver(save)",
      '"Gen2ContestMenu"',
    }) do
    check(battle:find(wanted, 1, true) ~= nil, "BattleState has " .. wanted)
  end
end

-- ---- the cache against the transcriptions ---------------------------------
--
-- The same two tables by two routes: BugContest.MONS and BugContest.FLAGS were
-- transcribed from pokegold, the rows below were followed out of the ROM.  Any
-- drift means one of them is wrong, which is the same pin
-- tests/gen2_world_test.lua holds CmdQueue.STONE_TABLES to.
do
  local cache = os.getenv("GOLD_CACHE")
  if not cache then
    local home = os.getenv("HOME") or ""
    cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local function loadLua(rel)
    local path = cache .. "/" .. rel
    local chunk = loadfile(path)
    return chunk and chunk() or nil
  end

  local encounters = loadLua("data/generated/encounters.lua")
  if not encounters then
    check(true, "gold cache absent : transcriptions only (SKIP the pins)")
  else
    local extracted = encounters.bugContest
    if type(extracted) ~= "table" or #extracted == 0 then
      check(true, "cache predates ContestMons extraction (SKIP)")
    else
      eq(#extracted, #BugContest.MONS, "the same eleven rows")
      for index, hand in ipairs(BugContest.MONS) do
        local row = extracted[index] or {}
        eq(row.species, hand.species, ("row %d species"):format(index))
        eq(row.chance, hand.chance, ("row %d chance"):format(index))
        eq(row.min, hand.min, ("row %d min level"):format(index))
        eq(row.max, hand.max, ("row %d max level"):format(index))
      end
      -- And the reader really does take the cache over the transcription.
      eq(BugContest.contestMons({ encounters = encounters }), extracted,
        "contestMons prefers the extracted table")
      -- Rolled through the cache rather than the transcription, the slices
      -- still land where ChooseWildEncounter_BugContest puts them.
      local rolled = BugContest.chooseWild({ encounters = encounters },
        seq(180, 1))
      eq(rolled.species, "SCYTHER", "roll 90 off the cache is still SCYTHER")
      eq(rolled.level, 14, "at level 14")
    end
  end

  local eventTables = loadLua("data/generated/events.lua")
  local flags = eventTables and eventTables.bugContestFlags
  if type(flags) ~= "table" or #flags == 0 then
    check(true, "cache predates bug_contest_flags extraction (SKIP)")
  else
    eq(#flags, BugContest.NUM_CONTESTANTS, "ten contestant flags")
    for slot, hand in ipairs(BugContest.FLAGS) do
      eq(flags[slot], hand, ("slot %d flag number"):format(slot))
    end
    eq(BugContest.contestantFlags(eventTables), flags,
      "contestantFlags prefers the extracted table")

    -- The strongest form of the pin: the table's ten words ARE the ten
    -- object_event flags on NationalParkBugContest, in map order.  A stride or
    -- an endianness that was off by anything would miss this.
    local maps = loadLua("data/generated/maps.lua")
    local park = maps and maps.NATIONAL_PARK_BUG_CONTEST
    if not park then
      check(true, "cache has no NATIONAL_PARK_BUG_CONTEST (SKIP)")
    else
      for slot = 1, BugContest.NUM_CONTESTANTS do
        local object = (park.objects or {})[slot] or {}
        eq(object.eventFlag, flags[slot],
          ("contest object %d answers to slot %d's flag"):format(slot, slot))
      end
    end
  end
end

S.finish()
