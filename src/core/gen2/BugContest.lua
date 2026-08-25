-- The Bug Catching Contest (engine/events/bug_contest/).
--
-- A MODE, not a menu.  For its duration the party is masked down to the lead
-- mon, the pack is replaced by twenty PARK BALLs, a twenty minute clock runs
-- off the RTC, wild encounters come from the contest's OWN table rather than
-- from National Park's grass, and only ONE caught mon is kept at a time.  When
-- it is over the judge scores that mon against five rolled contestants, and
-- the placing decides whether the player walks out with a SUN STONE.
--
-- The pieces, and the file each is transcribed from:
--
--   ContestScore                 bug_contest/judging.asm   the player's score
--   ComputeAIContestantScores    bug_contest/judging.asm   the five AI rolls
--   DetermineContestWinners      bug_contest/judging.asm   the podium
--   BugContest_GetPlayersResult  bug_contest/judging.asm   the placing, 0..3
--   BugContestantPointers        data/events/bug_contest_winners.asm
--   BugCatchingContestantEventFlagTable  data/events/bug_contest_flags.asm
--   ContestMons                  data/wild/bug_contest_mons.asm
--   ChooseWildEncounter_BugContest  engine/overworld/events.asm
--   TryWildEncounter_BugContest     engine/overworld/events.asm
--   ContestDropOffMons / ContestReturnMons  bug_contest/contest_2.asm
--   BugContest_SetCaughtContestMon          bug_contest/caught_mon.asm
--   GiveParkBalls                bug_contest/contest.asm
--   StartBugContestTimer / CheckBugContestTimer  engine/overworld/time.asm
--
-- NOTHING here draws.  src/ui/gen2/ContestMenu.lua is the STOCK-versus-THIS
-- comparison screen, and it asks this module every question it needs answered,
-- so the rules can be tested with no love at all.
--
-- The DRIVER is the extracted script bytecode: Route35NationalParkGate's
-- officer calls ContestDropOffMons, GiveParkBalls and
-- SelectRandomBugContestContestants, and BugContestResultsScript calls
-- BugContestJudging, ContestReturnMons and CheckPartyFullAfterContest.  Each of
-- those specials is one call into this module -- see the module map at the
-- bottom of the file.
--
-- This file also carries the RTC delta helpers from engine/overworld/time.asm.
-- They live here because the contest timer is the port's only SECOND
-- resolution consumer of them; src/core/gen2/Apricorns.lua reuses the same two
-- functions at day resolution for Kurt's wait.  Both belong in a
-- src/core/gen2/Time.lua the day one exists.

local Runtime = require("src.mods.Runtime")

local BugContest = {}

-- ---------------------------------------------------------------- constants
--
-- constants/script_constants.asm.
BugContest.BALLS = 20            -- BUG_CONTEST_BALLS
BugContest.MINUTES = 20          -- BUG_CONTEST_MINUTES
BugContest.SECONDS = 0           -- BUG_CONTEST_SECONDS
BugContest.PLAYER = 1            -- BUG_CONTEST_PLAYER
BugContest.NUM_CONTESTANTS = 10  -- NUM_BUG_CONTESTANTS, not counting the player
BugContest.CONTESTANT_SIZE = 4   -- BUG_CONTESTANT_SIZE: id, mon, score hi, lo
-- SelectRandomBugContestContestants sets five of the ten flags.
BugContest.CONTESTANTS_PICKED = 5

-- The three-way answer CheckPartyFullAfterContest leaves in wScriptVar, which
-- BugContestResults_DidNotLeaveMons branches on.
BugContest.CAUGHT_MON = 0
BugContest.BOXED_MON = 1
BugContest.NO_CATCH = 2

-- constants/engine_flags.asm, by index: the two ENGINE_* ids the gate scripts
-- set and clear around a contest.  ENGINE_BUG_CONTEST_TIMER is what makes
-- CheckTimeEvents poll the clock instead of the daily reset;
-- ENGINE_DAILY_BUG_CONTEST is a wDailyFlags1 bit, so it clears itself overnight
-- and that is what makes the contest a once-a-day thing.
BugContest.ENGINE_BUG_CONTEST_TIMER = 16
BugContest.ENGINE_DAILY_BUG_CONTEST = 80

-- Route35OfficerScriptContest turns you away on SUNDAY, MONDAY, WEDNESDAY and
-- FRIDAY, so the contest runs Tuesday, Thursday and Saturday.  Weekday numbers
-- are GetWeekday's, which is wCurDay mod 7 with SUNDAY == 0
-- (constants/ram_constants.asm).
BugContest.SUNDAY, BugContest.MONDAY, BugContest.TUESDAY = 0, 1, 2
BugContest.WEDNESDAY, BugContest.THURSDAY = 3, 4
BugContest.FRIDAY, BugContest.SATURDAY = 5, 6
BugContest.CONTEST_DAYS = { [2] = true, [4] = true, [6] = true }

-- BugContestResults_FirstPlace / _SecondPlace / _ThirdPlace, and the
-- consolation BERRY every entrant who placed nowhere gets.
BugContest.PRIZES = { "SUN_STONE", "EVERSTONE", "GOLD_BERRY" }
BugContest.CONSOLATION_PRIZE = "BERRY"

-- The one ball that works inside the park.  BattleMenu_Pack's `.contest`
-- branch does not open the pack at all: it loads PARK_BALL into wCurItem and
-- runs the item effect, so there is no way to throw anything else.
BugContest.BALL = "PARK_BALL"

-- ------------------------------------------------------------- the RTC
--
-- wCurDay counts 0..139 (_CalcDaysSince wraps by adding 20 * 7), hours by
-- MAX_HOUR, minutes and seconds by 60.
BugContest.DAY_WRAP = 20 * 7
BugContest.HOUR_WRAP = 24 -- MAX_HOUR, constants/misc_constants.asm

-- The host clock in the cart's shape.  `stamp` is optional and is an os.time()
-- value, so a test can pin the clock without touching the real one.
function BugContest.now(stamp)
  local t = os.date("*t", stamp)
  -- Days since the epoch in LOCAL time, folded into wCurDay's range.  The
  -- absolute value is meaningless (the cart's own wCurDay is only ever read
  -- through a difference or a mod 7), so any monotone daily counter serves,
  -- and folding it here is what makes a save survive a year of real time.
  local midday = os.time({ year = t.year, month = t.month, day = t.day,
                           hour = 12, min = 0, sec = 0 })
  local day = math.floor(midday / 86400) % BugContest.DAY_WRAP
  return { day = day, hour = t.hour, minute = t.min, second = t.sec }
end

-- GetWeekday: wCurDay mod 7, SUNDAY == 0.
function BugContest.weekday(now)
  return ((now or BugContest.now()).day or 0) % 7
end

function BugContest.isContestDay(now)
  return BugContest.CONTEST_DAYS[BugContest.weekday(now)] == true
end

local function borrowed(value, wrap)
  -- One `sub`/`sbc` step: the wrapped difference, plus the borrow that has to
  -- carry into the next unit up.
  if value < 0 then return value + wrap, 1 end
  return value, 0
end

-- CalcSecsMinsHoursDaysSince.  Two things about this routine matter and both
-- are easy to lose in a port:
--
--   * it ADVANCES the stored stamp to `now` in place (`ld [hl], c ; current
--     seconds`, and again for minutes, hours and days).  So the deltas are
--     "since the LAST poll", not "since the timer started", and two polls a
--     minute apart subtract one minute each rather than one and then two.
--   * every unit wraps rather than going negative.  A clock moved BACKWARDS
--     therefore reads as a very large jump forward, which is exactly what
--     makes a rewound clock end the contest and roll the daily flags.
--
-- `depth` picks how far down the struct the cart went: CalcDaysSince stops at
-- days, CalcMinsHoursDaysSince at minutes, CalcSecsMinsHoursDaysSince runs the
-- lot.  Unread units are left alone in the stamp, the same way the shorter
-- entry points never touch them.
function BugContest.elapsedSince(stamp, now, depth)
  now = now or BugContest.now()
  depth = depth or "second"
  local out = { days = 0, hours = 0, minutes = 0, seconds = 0 }
  local carry = 0
  if depth == "second" then
    local value
    value, carry = borrowed((now.second or 0) - (stamp.second or 0), 60)
    stamp.second = now.second or 0
    out.seconds = value
  end
  if depth == "second" or depth == "minute" then
    local value
    value, carry = borrowed((now.minute or 0) - (stamp.minute or 0) - carry, 60)
    stamp.minute = now.minute or 0
    out.minutes = value
  end
  if depth ~= "day" then
    local value
    value, carry = borrowed((now.hour or 0) - (stamp.hour or 0) - carry,
      BugContest.HOUR_WRAP)
    stamp.hour = now.hour or 0
    out.hours = value
  end
  local days
  days, carry = borrowed((now.day or 0) - (stamp.day or 0) - carry,
    BugContest.DAY_WRAP)
  stamp.day = now.day or 0
  out.days = days
  return out
end

-- ------------------------------------------------------------- the state
--
-- Everything the contest owns lives under save.bugContest, spelled after the
-- WRAM it stands in for:
--
--   active      ENGINE_BUG_CONTEST_TIMER (wStatusFlags2 bit 0)
--   balls       wParkBallsRemaining
--   minutes     wBugContestMinsRemaining
--   seconds     wBugContestSecsRemaining
--   startTime   wBugContestStartTime, { day, hour, minute, second }
--   caught      wContestMon, one party-shaped mon or nil
--   stash       the party tail ContestDropOffMons masks off
--   contestants { [1..10] = true } for a SET flag, i.e. NOT in this contest
--   results     wBugContestResults, { first, second, third }
--   place       what BugContestJudging left in wScriptVar, 0..3
function BugContest.state(save)
  if type(save) ~= "table" then return nil end
  save.bugContest = save.bugContest or {}
  return save.bugContest
end

function BugContest.isActive(save)
  local state = BugContest.state(save)
  return (state and state.active) == true
end

-- ------------------------------------------------------- the encounter table
--
-- data/wild/bug_contest_mons.asm, transcribed.  `chance` is the row's slice of
-- 100, NOT a cumulative total: ChooseWildEncounter_BugContest subtracts each
-- row from the roll until it borrows.  The ten real rows already add to 100, so
-- the trailing VENOMOTH row -- whose chance byte is -1, i.e. "always" -- is
-- unreachable.  It is kept because dropping it would be editing the cart's
-- table, and because it is the row a modified chance list would fall through
-- to.
BugContest.MONS = {
  { chance = 20, species = "CATERPIE",   min = 7,  max = 18 },
  { chance = 20, species = "WEEDLE",     min = 7,  max = 18 },
  { chance = 10, species = "METAPOD",    min = 9,  max = 18 },
  { chance = 10, species = "KAKUNA",     min = 9,  max = 18 },
  { chance = 5,  species = "BUTTERFREE", min = 12, max = 15 },
  { chance = 5,  species = "BEEDRILL",   min = 12, max = 15 },
  { chance = 10, species = "VENONAT",    min = 10, max = 16 },
  { chance = 10, species = "PARAS",      min = 10, max = 17 },
  { chance = 5,  species = "SCYTHER",    min = 13, max = 14 },
  { chance = 5,  species = "PINSIR",     min = 13, max = 14 },
  { chance = 255, species = "VENOMOTH",  min = 30, max = 40 },
}

-- The extractor writes the same eleven rows as encounters.bugContest, which is
-- its own table in the cache and not a grass row: the park's grass entry is
-- what the map rolls off OUTSIDE the twenty minutes.  This reader prefers the
-- cache, so the transcription above is the pinned fallback rather than a
-- second source of truth that can drift.
function BugContest.contestMons(data)
  local extracted = data and data.encounters and data.encounters.bugContest
  if type(extracted) == "table" and #extracted > 0 then return extracted end
  return BugContest.MONS
end

-- `call Random` gives one byte.  Kept on the module, not taken from the VM, so
-- every roll below can be pinned by a test; the convention is the ASM's, a
-- function of no arguments returning 0..255.
function BugContest.random()
  if love and love.math and love.math.random then
    return love.math.random(0, 255)
  end
  return math.random(0, 255)
end

local function byte(random)
  return (random or BugContest.random)()
end

-- TryWildEncounter_BugContest: 40 percent in super-tall grass, 20 percent in
-- ordinary grass, and `percent` is `* $ff / 100` so those are 102 and 51 out of
-- 256, not 40 and 20 out of 100.
BugContest.ENCOUNTER_RATE_SUPER_TALL = math.floor(40 * 0xff / 100)
BugContest.ENCOUNTER_RATE_GRASS = math.floor(20 * 0xff / 100)

function BugContest.encounterRate(superTallGrass)
  if superTallGrass then return BugContest.ENCOUNTER_RATE_SUPER_TALL end
  return BugContest.ENCOUNTER_RATE_GRASS
end

function BugContest.triggers(superTallGrass, random)
  return byte(random) < BugContest.encounterRate(superTallGrass)
end

-- ChooseWildEncounter_BugContest.  The roll is rejected until it is under
-- 200 and then halved, which is a uniform 0..99 with no modulo bias, and the
-- level is `min + Random % (max - min + 1)` unless min and max are equal.
function BugContest.chooseWild(data, random)
  local rows = BugContest.contestMons(data)
  local roll
  repeat
    roll = byte(random)
  until roll < 200
  roll = math.floor(roll / 2)

  local row
  for index = 1, #rows do
    row = rows[index]
    local chance = row.chance or 0
    if roll < chance then break end
    roll = roll - chance
  end
  if not row then return nil end

  local level = row.min or 1
  local span = (row.max or level) - level
  if span ~= 0 then
    -- SimpleDivide's remainder over (max - min + 1), added to min.
    level = level + (byte(random) % (span + 1))
  end
  return { species = row.species, level = level }
end

-- ------------------------------------------------------------ the contestants
--
-- data/events/bug_contest_winners.asm.  Each row is `db class, id` followed by
-- three `dbw mon, score` rows, best first.
--
-- INDEXING, which is where this table bites.  BugContestantPointers has
-- NUM_BUG_CONTESTANTS + 1 entries: slot 0 is a duplicate of Bug Catcher Don
-- that the comment marks "this reverts back to the player" and nothing ever
-- reads.  ComputeAIContestantScores walks e = 0..9 and looks up slot e + 1,
-- and LoadContestantName takes a winner ID and looks up slot ID - 1.  So the
-- ten real contestants are slots 1..10 and their winner IDs are 2..11, with
-- ID 1 reserved for the player (BUG_CONTEST_PLAYER).  A 1-based Lua list lines
-- up with the slot numbers exactly, which is why this one is NOT zero based.
BugContest.CONTESTANTS = {
  { class = "BUG_CATCHER",  trainer = 1, name = "DON",
    mons = { { species = "KAKUNA",     score = 300 },
             { species = "METAPOD",    score = 285 },
             { species = "CATERPIE",   score = 226 } } },
  { class = "BUG_CATCHER",  trainer = 3, name = "ED",
    mons = { { species = "BUTTERFREE", score = 286 },
             { species = "BUTTERFREE", score = 251 },
             { species = "CATERPIE",   score = 237 } } },
  { class = "COOLTRAINERM", trainer = 1, name = "NICK",
    mons = { { species = "SCYTHER",    score = 357 },
             { species = "BUTTERFREE", score = 349 },
             { species = "PINSIR",     score = 368 } } },
  { class = "POKEFANM",     trainer = 1, name = "WILLIAM",
    mons = { { species = "PINSIR",     score = 332 },
             { species = "BUTTERFREE", score = 324 },
             { species = "VENONAT",    score = 321 } } },
  { class = "BUG_CATCHER",  trainer = 5, name = "BENNY",
    mons = { { species = "BUTTERFREE", score = 318 },
             { species = "WEEDLE",     score = 295 },
             { species = "CATERPIE",   score = 285 } } },
  { class = "CAMPER",       trainer = 5, name = "BARRY",
    mons = { { species = "PINSIR",     score = 366 },
             { species = "VENONAT",    score = 329 },
             { species = "KAKUNA",     score = 314 } } },
  { class = "PICNICKER",    trainer = 5, name = "CINDY",
    mons = { { species = "BUTTERFREE", score = 341 },
             { species = "METAPOD",    score = 301 },
             { species = "CATERPIE",   score = 264 } } },
  { class = "BUG_CATCHER",  trainer = 7, name = "JOSH",
    mons = { { species = "SCYTHER",    score = 326 },
             { species = "BUTTERFREE", score = 292 },
             { species = "METAPOD",    score = 282 } } },
  { class = "YOUNGSTER",    trainer = 5, name = "SAMUEL",
    mons = { { species = "WEEDLE",     score = 270 },
             { species = "PINSIR",     score = 282 },
             { species = "CATERPIE",   score = 251 } } },
  { class = "SCHOOLBOY",    trainer = 2, name = "KIPP",
    mons = { { species = "VENONAT",    score = 267 },
             { species = "PARAS",      score = 254 },
             { species = "KAKUNA",     score = 259 } } },
}

-- The winner ID a slot answers to, and back.  BUG_CONTEST_PLAYER is 1.
function BugContest.contestantId(slot) return slot + 1 end
function BugContest.contestantSlot(id) return id - 1 end

-- LoadContestantName: the trainer CLASS name, its trailing terminator replaced
-- by a space, then the trainer's own name appended -- "BUG CATCHER DON".  ID 1
-- is the player, whose name is copied straight out of wPlayerName.
--
-- The class and trainer names come from the cache (trainers.lua keys classes
-- by their constant and lists each class's members in order), and fall back to
-- the transcribed row when a class is missing, so a headless test needs no
-- cache at all.
function BugContest.contestantName(data, id, playerName)
  if id == BugContest.PLAYER then return playerName or "<PLAYER>" end
  local row = BugContest.CONTESTANTS[BugContest.contestantSlot(id)]
  if not row then return "" end
  local classes = data and data.trainers and data.trainers.classes
  local class = classes and classes[row.class]
  local className = (class and class.name) or row.class
  local member = class and class.trainers and class.trainers[row.trainer]
  local trainerName = (member and member.name) or row.name
  return className .. " " .. trainerName
end

-- ---------------------------------------------------------------- the score
--
-- ContestScore.  Everything it tallies is an EIGHT BIT read out of the party
-- struct, and the struct is big-endian, so `[wContestMonMaxHP + 1]` is the LOW
-- byte of max HP and not the high one.  The accumulator itself is 16 bit:
-- .AddContestStat adds into hMultiplicand and carries into the byte below it,
-- which the union in ram/hram.asm makes hProduct, and BugContest_JudgeContestants
-- reads that pair back as the score.
--
--   max HP low byte, four times
--   Attack, Defense, Speed, Special Attack, Special Defense, low bytes
--   a DV term (below)
--   current HP low byte, shifted right three times
--   1 if the mon is holding an item
--
-- The DV term is the odd one.  It reads BIT 1 of four of the DVs -- never bit
-- 0, never the whole nibble -- and weights them 16 for Defense, 8 for Attack,
-- 4 for Special and 1 for Speed:
--
--   ld a, [wContestMonDVs + 0] / and %0010 / add a / add a   ; c = 8 * def_bit1
--   swap b / and %0010 / add a / add c                       ; d = 4 * atk_bit1 + c
--   ld a, [wContestMonDVs + 1] / and %0010                   ; c = 2 * spc_bit1
--   swap b / and %0010 / srl a / add c / add c / add d / add d
--
-- which lands on spd_bit1 + 4 * spc_bit1 + 8 * atk_bit1 + 16 * def_bit1.
local function low(value) return math.floor(value or 0) % 256 end

local function bit1(value) return math.floor((value or 0) / 2) % 2 end

function BugContest.score(mon)
  -- `ld a, [wContestMonSpecies] / and a / jr z, .done`: an empty slot scores 0.
  if not (mon and mon.species) then return 0 end
  local stats = mon.stats or {}
  local maxHp = mon.maxHp or stats.hp
  local total = low(maxHp) * 4
  total = total + low(stats.attack) + low(stats.defense) + low(stats.speed)
    + low(stats.specialAttack) + low(stats.specialDefense)
  local dvs = mon.dvs or {}
  total = total + 16 * bit1(dvs.defense) + 8 * bit1(dvs.attack)
    + 4 * bit1(dvs.special) + bit1(dvs.speed)
  total = total + math.floor(low(mon.hp) / 8)
  -- `ld a, [wContestMonItem] / and a / jr z, .done`, the last term either way.
  if mon.item then total = total + 1 end
  return total % 65536
end

-- ---------------------------------------------------------------- the podium
--
-- DetermineContestWinners compares the temp entry against first, then second,
-- then third, with CompareBytes over the two score bytes.  CompareBytes only
-- sets carry when the temp score is STRICTLY LESS, so an equal score DISPLACES
-- the sitting entry and pushes it down a place.  That is not a rounding detail:
-- it is why the player, who is scored last, wins a tie.
local function beats(entry, incumbent)
  return (entry.score or 0) >= ((incumbent and incumbent.score) or 0)
end

local function copyEntry(entry)
  if not entry then return nil end
  return { id = entry.id, species = entry.species, score = entry.score }
end

function BugContest.placeEntry(results, entry)
  if beats(entry, results.first) then
    results.third = copyEntry(results.second)
    results.second = copyEntry(results.first)
    results.first = copyEntry(entry)
  elseif beats(entry, results.second) then
    results.third = copyEntry(results.second)
    results.second = copyEntry(entry)
  elseif beats(entry, results.third) then
    results.third = copyEntry(entry)
  end
  return results
end

-- ComputeAIContestantScores' inner roll, for ONE contestant.  Two `call Random`
-- bytes: the first picks which of the three listed mons this contestant turned
-- up with (masked to 2 bits and REROLLED on 3, so 0, 1 and 2 are equally
-- likely), the second is a 0..7 bump added to that mon's listed score.
function BugContest.rollContestant(slot, random)
  local row = BugContest.CONTESTANTS[slot]
  if not row then return nil end
  local pick
  repeat
    pick = byte(random) % 4
  until pick ~= 3
  local mon = row.mons[pick + 1]
  return {
    id = BugContest.contestantId(slot),
    species = mon.species,
    score = mon.score + (byte(random) % 8),
  }
end

-- BugContest_JudgeContestants.  ClearContestResults wipes the podium,
-- ComputeAIContestantScores walks the ten contestants and skips any whose flag
-- is SET (a set flag is what kept that trainer OFF the contest map, so the five
-- SelectRandomBugContestContestants picked are the five who do NOT score), and
-- only THEN is the player's own entry placed.
--
-- `state.contestants` is that flag table: state.contestants[slot] == true means
-- the flag is set, i.e. absent.  A state with no table at all scores all ten,
-- which is what a save from before the picking ran looks like.
function BugContest.judge(state, playerMon, playerScore, random)
  local absent = (state and state.contestants) or {}
  local results = { first = nil, second = nil, third = nil }
  for slot = 1, BugContest.NUM_CONTESTANTS do
    if not absent[slot] then
      local entry = BugContest.rollContestant(slot, random)
      if entry then BugContest.placeEntry(results, entry) end
    end
  end
  BugContest.placeEntry(results, {
    id = BugContest.PLAYER,
    species = playerMon and playerMon.species or nil,
    score = playerScore or BugContest.score(playerMon),
  })
  return results
end

-- BugContest_GetPlayersResult: walk the podium from THIRD upwards with b
-- counting 3, 2, 1 and stop at the player.  Falling off the end leaves b at 0,
-- and that 0 is what sends the script down the consolation-BERRY branch.
function BugContest.playerPlace(results)
  local order = { results.third, results.second, results.first }
  for index = 1, 3 do
    local entry = order[index]
    if entry and entry.id == BugContest.PLAYER then return 4 - index end
  end
  return 0
end

-- _BugContestJudging end to end: score, judge, and leave the placing where
-- BugContestJudging's `ld a, b / ld [wScriptVar], a` leaves it.  The results
-- are kept on the state so the gate's three text pages can name each winner.
function BugContest.runJudging(save, random)
  local state = BugContest.state(save)
  if not state then return 0 end
  local mon = state.caught
  local score = BugContest.score(mon)
  local results = BugContest.judge(state, mon, score, random)
  state.results = results
  state.playerScore = score
  state.place = BugContest.playerPlace(results)
  -- bug_contest.scored, a Gen 2 invention: Gen 1 has no contest, so there is
  -- no name to share.  Raised once per contest, after the podium is settled
  -- and before the gate prints it, which is the only moment both the player's
  -- number and the three winners exist together.
  --
  --   mon      the mon the player brought out of the park, or nil for none
  --   score    BugContest.score of it, the number DetermineContestWinners used
  --   place    1, 2, 3, or 0 for the consolation BERRY branch
  --   results  the podium, { first, second, third }, each
  --            { id, species, score } with id BugContest.PLAYER for the player
  if Runtime.wants("bug_contest.scored") then
    Runtime.emit("bug_contest.scored", {
      mon = mon, score = score, place = state.place, results = results,
    })
  end
  return state.place
end

-- The prize for a placing, or the consolation BERRY for 0.
function BugContest.prizeFor(place)
  return BugContest.PRIZES[place] or BugContest.CONSOLATION_PRIZE
end

-- ---------------------------------------------------- SelectRandomBugContestContestants
--
-- data/events/bug_contest_flags.asm, transcribed: EVENT_BUG_CATCHING_CONTESTANT_1A
-- through _10A, by NUMBER, because wEventFlags is keyed by number.  These are
-- the ten NationalParkBugContest object_event flags, in slot order, and they
-- are the *A set -- the *B set is the same ten people standing in
-- Route36NationalParkGate before the contest starts and nothing here touches
-- it.
--
-- The extractor now writes the same ten as events.bugContestFlags, so this is
-- the pinned fallback for a cache that predates it rather than a second source
-- of truth; tests/gen2_contest_test.lua compares the two row by row.
BugContest.FLAGS = {
  1814, 1815, 1816, 1817, 1818, 1819, 1820, 1821, 1822, 1823,
}

-- data/generated/events.lua's copy when it is there, the transcription above
-- when it is not.  `tables` is the eventTables the VM carries, not the whole
-- cache: the flag table is a side table a command NAMES, the same as the
-- trades and the floor labels.
function BugContest.contestantFlags(tables)
  local extracted = tables and tables.bugContestFlags
  if type(extracted) == "table" and #extracted == BugContest.NUM_CONTESTANTS then
    return extracted
  end
  return BugContest.FLAGS
end

-- Five flags chosen at uniform random out of ten, rejecting a duplicate rather
-- than reshuffling: `call Random / cp $ff / 10 * 10 / jr nc` throws away any
-- byte 250 or over, divides by 25 to land on 0..9, and rerolls a slot whose
-- flag is already set.  A SET flag hides that contestant's sprite, so these
-- five are the ones NOT in the park -- and, downstream, the five
-- ComputeAIContestantScores skips.
function BugContest.pickContestants(save, random)
  local state = BugContest.state(save)
  if not state then return nil end
  local n = BugContest.NUM_CONTESTANTS
  local limit = math.floor(0xff / n) * n
  local step = math.floor(0xff / n)
  local chosen = {}
  local picked = 0
  while picked < BugContest.CONTESTANTS_PICKED do
    local roll
    repeat
      roll = byte(random)
    until roll < limit
    -- SimpleDivide's quotient, i.e. 0..9, then 1-based for the Lua table.
    local slot = math.floor(roll / step) + 1
    if not chosen[slot] then
      chosen[slot] = true
      picked = picked + 1
    end
  end
  state.contestants = chosen
  return chosen
end

-- The half of SelectRandomBugContestContestants that touches wEventFlags, and
-- the reason it is a separate call: `.loop1` runs EventFlagAction RESET_FLAG
-- over ALL TEN before a single pick is made.  That reset is not tidiness --
-- without it last contest's five are still hidden, and the two contests
-- together would empty the park.  So every slot is written here, true for a
-- picked one and false for the rest, rather than only the five being set.
--
-- `events` is src/world/gen2/Events.lua (wEventFlags); a nil one is a headless
-- caller with no flag store, which changes nothing else about the pick.
function BugContest.applyContestantFlags(events, chosen, tables)
  if not events then return nil end
  local flags = BugContest.contestantFlags(tables)
  chosen = chosen or {}
  for slot = 1, BugContest.NUM_CONTESTANTS do
    local flag = flags[slot]
    if flag then events:set(flag, chosen[slot] == true) end
  end
  return flags
end

-- ------------------------------------------------------- entering and leaving
--
-- ContestDropOffMons.  The party is not stored anywhere on the cart, it is
-- MASKED: wPartyCount is written down to 1 and the second species byte is
-- replaced with the -1 terminator, so for the duration only the lead mon
-- exists.  A Lua list cannot be truncated in place and restored, so the tail
-- moves to state.stash -- which MUST live on the save, because the cart's
-- masked-off party is still sitting in SRAM and survives a save and reload
-- mid-contest.
--
-- Returns FALSE (0) on success and TRUE (1) when the lead mon has fainted,
-- which is the wScriptVar the officer's `iftrue` branches on.
function BugContest.dropOffMons(save)
  local state = BugContest.state(save)
  local party = save and save.party
  if not (state and party) then return 1 end
  local lead = party[1]
  if not lead or (lead.hp or 0) <= 0 then return 1 end
  local stash = {}
  for index = 2, #party do stash[#stash + 1] = party[index] end
  state.stash = stash
  for index = #party, 2, -1 do party[index] = nil end
  return 0
end

-- ContestReturnMons.  The species of the second mon goes back and the party
-- count is RECOMPUTED by walking to the terminator, which is why a mon caught
-- during the contest -- already sitting in slot 2 by the time this runs -- is
-- kept and the tail lands BEHIND it rather than over it.
function BugContest.returnMons(save)
  local state = BugContest.state(save)
  local party = save and save.party
  if not (state and party) then return end
  for _, mon in ipairs(state.stash or {}) do
    party[#party + 1] = mon
  end
  state.stash = nil
end

-- GiveParkBalls, plus the StartBugContestTimer it farcalls.  wContestMon is
-- cleared first, so entering a second contest cannot inherit the last one's
-- catch.
function BugContest.start(save, now)
  local state = BugContest.state(save)
  if not state then return nil end
  state.active = true
  state.caught = nil
  state.balls = BugContest.BALLS
  state.minutes = BugContest.MINUTES
  state.seconds = BugContest.SECONDS
  state.results = nil
  state.place = nil
  state.playerScore = nil
  local stamp = now or BugContest.now()
  state.startTime = { day = stamp.day, hour = stamp.hour,
                      minute = stamp.minute, second = stamp.second }
  return state
end

-- BugContestResultsScript's `clearflag ENGINE_BUG_CONTEST_TIMER`, and the
-- clean-up around it.  The caught mon is deliberately LEFT on the state:
-- CheckPartyFullAfterContest is what consumes it, and it runs after this.
function BugContest.stop(save)
  local state = BugContest.state(save)
  if not state then return end
  state.active = false
  state.minutes = 0
  state.seconds = 0
  state.startTime = nil
end

-- CheckBugContestTimer.  Called from CheckTimeEvents while
-- ENGINE_BUG_CONTEST_TIMER is set, and returning true is what makes the
-- overworld call BugCatchingContestOverScript.
--
-- Any whole day or hour of elapsed time ends it outright.  Otherwise the
-- seconds are subtracted with a wrap, and the BORROW that wrap produces is
-- carried into the minutes by the `sbc` -- the `add 60` that rewraps the
-- seconds always overflows a byte (the largest possible shortfall is 59), so
-- the carry it leaves behind is the borrow, not an accident.  A minute count
-- that goes negative is the timeout.
function BugContest.tickTimer(save, now)
  local state = BugContest.state(save)
  if not (state and state.active and state.startTime) then return false end
  local since = BugContest.elapsedSince(state.startTime, now, "second")
  if since.days ~= 0 or since.hours ~= 0 then
    state.minutes, state.seconds = 0, 0
    return true
  end
  local seconds, borrow = borrowed((state.seconds or 0) - since.seconds, 60)
  state.seconds = seconds
  local minutes = (state.minutes or 0) - since.minutes - borrow
  if minutes < 0 then
    state.minutes, state.seconds = 0, 0
    return true
  end
  state.minutes = minutes
  return false
end

function BugContest.timeLeft(save)
  local state = BugContest.state(save)
  if not state then return 0, 0 end
  return state.minutes or 0, state.seconds or 0
end

-- ------------------------------------------------------------- the park balls
--
-- ContestBattleMenu's third row is "PARKBALL×" followed by
-- wParkBallsRemaining, and PokeBallEffect's `.used_park_ball` does `dec [hl]`
-- instead of tossing an item out of the pack -- so a Park Ball is never in the
-- bag, never taken from it, and never restored.
function BugContest.ballsLeft(save)
  local state = BugContest.state(save)
  return (state and state.balls) or 0
end

function BugContest.useBall(save)
  local state = BugContest.state(save)
  if not state then return 0 end
  state.balls = math.max(0, (state.balls or 0) - 1)
  return state.balls
end

-- CheckContestBattleOver: no balls left is a DRAW and ends the battle, and
-- BugCatchingContestBattleScript's `readmem wParkBallsRemaining / iffalse`
-- then sends the player back to the gate.
function BugContest.isOver(save)
  return BugContest.ballsLeft(save) <= 0
end

-- ----------------------------------------------------------- the caught mon
--
-- BugContest_SetCaughtContestMon.  With no stock mon the catch is kept
-- outright; with one, the player is shown the STOCK versus THIS comparison and
-- asked, and a YES swaps.  PlaceYesNoBox's `ret c` is the NO, so the DEFAULT --
-- cancelling out of the box with B -- keeps the mon already in stock.
BugContest.KEEP_FIRST = "first"   -- .firstcatch, no question asked
BugContest.ASK_SWITCH = "switch"  -- DisplayCaughtContestMonStats, then yes/no

function BugContest.catch(save, mon)
  local state = BugContest.state(save)
  if not state then return nil end
  BugContest.useBall(save)
  if not state.caught then
    state.caught = mon
    return BugContest.KEEP_FIRST
  end
  return BugContest.ASK_SWITCH, state.caught, mon
end

-- The YES arm of that question.
function BugContest.switchCaught(save, mon)
  local state = BugContest.state(save)
  if not state then return nil end
  state.caught = mon
  return mon
end

function BugContest.caughtMon(save)
  local state = BugContest.state(save)
  return state and state.caught or nil
end

-- ------------------------------------------------- CheckPartyFullAfterContest
--
-- The catch joins the party if there is room and goes to the current box if
-- there is not, and the answer is the three-way wScriptVar the gate branches
-- on.  Boxing needs src/core/gen2/Boxes.lua, which is required lazily so this
-- module stays loadable on its own.
function BugContest.collectCaughtMon(save, partySize, boxes)
  local state = BugContest.state(save)
  local mon = state and state.caught
  if not mon then return BugContest.NO_CATCH end
  state.caught = nil
  -- caught_nickname.asm:34-39 copies wPlayerName when the contest mon joins.
  require("src.battle.gen2.Mon").stampOT(save, mon)
  local party = save.party or {}
  save.party = party
  partySize = partySize or 6
  if #party < partySize then
    party[#party + 1] = mon
    return BugContest.CAUGHT_MON, mon
  end
  boxes = boxes or require("src.core.gen2.Boxes")
  local box = boxes.box(save, save.currentBox or 1)
  -- .TryAddToBox copies BOXMON_STRUCT_LENGTH and tails into
  -- RestorePPOfDepositedPokemon (engine/pokemon/caught_nickname.asm:72-90).
  if box then box[#box + 1] = boxes.enterBox(mon) end
  return BugContest.BOXED_MON, mon
end

-- ------------------------------------------------------------- the module map
--
-- What each special in data/events/special_pointers.asm should call, so the
-- half of this system that lives in src/script/gen2/Specials.lua meets this
-- half exactly once:
--
--   ContestDropOffMons               BugContest.dropOffMons(save)   -> scriptVar
--   ContestReturnMons                BugContest.returnMons(save)
--   GiveParkBalls                    BugContest.start(save)
--   BugContestJudging                BugContest.runJudging(save)    -> scriptVar
--   CheckPartyFullAfterContest       BugContest.collectCaughtMon(save)
--                                                                   -> scriptVar
--   SelectRandomBugContestContestants  BugContest.pickContestants(save) and
--                                      BugContest.applyContestantFlags(events,
--                                        chosen, eventTables)
--
-- and outside the specials table:
--
--   CheckTimeEvents                  BugContest.tickTimer(save)     -> ended?
--   ChooseWildEncounter_BugContest   BugContest.chooseWild(data)
--   TryWildEncounter_BugContest      BugContest.triggers(superTall)
--   PokeBallEffect .used_park_ball   BugContest.catch(save, mon)
BugContest.SCREEN_ID = "Gen2ContestMenu"

return BugContest
