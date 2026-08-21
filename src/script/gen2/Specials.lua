-- The `special` command's handlers (data/events/special_pointers.asm).
--
-- Lifted out of src/script/gen2/Vm.lua because the two are different kinds of
-- code: the VM is one interpreter with a shared control flow, and this is 112
-- INDEPENDENT routines that happen to share a dispatch table.  Growing them
-- inside runList's else-chain would have buried the interpreter.
--
-- Dispatch is by NAME.  The script byte is an index into SpecialsPointers,
-- which the extractor turns into constants.specialOrder, and Vm:specialName
-- resolves the one into the other; keying on the label rather than on the
-- number means a repointed table cannot silently call the wrong routine, and
-- it means a test can assert the mapping against the cache.  This cache's
-- order has 112 rows -- the asm file's 113 `add_special` matches include the
-- MACRO line itself.
--
-- Three kinds of entry live here:
--
--   HANDLERS  the routine, ported.  Most read or write wScriptVar, so each
--             takes the Vm and leaves its answer in `vm.scriptVar`, exactly
--             as the asm leaves it in wScriptVar.
--   STUBS     deliberately out of scope, with the reason written down and a
--             SANE return rather than a fall-through.  Everything link cable,
--             Mystery Gift and the printer is here: those need a second
--             console or a Game Boy Printer, and a script that asks and gets
--             no answer at all takes the wrong branch.
--   ALL       the merge, which is what Vm.SPECIALS is.  The two sets are
--             disjoint by construction and tests/gen2_vm_test.lua asserts it.
--
-- Everything a handler needs from the game is one call into `vm.specials`, the
-- hook table src/world/gen2/World.lua builds in World:specialHooks.  A handler
-- with no hooks at all still runs and still leaves the right wScriptVar: that
-- is what makes the whole table testable headless.
--
-- BLOCKING.  A handler runs INSIDE the VM's coroutine (runList calls
-- Vm:runSpecial), so it may yield, and Specials.block below is how it parks on
-- a screen: the async work is started first and the coroutine only yields if
-- the callback has not already fired, which is what lets the same handler work
-- against a real pushed screen and against a test stub that answers on the
-- spot.  The parked yield carries a kind Vm:resume does not recognise, and
-- that is deliberate: it means "nothing to do, wait", and the screen's own
-- callback is the only thing that can start the script again.

-- Two cart tables this file USES but must not re-transcribe.  Each already has
-- exactly one home, and a second copy here is how the pair drift apart:
--   Happiness  data/events/happiness_changes.asm, plus ChangeHappiness's tier
--              pick, its two carry clamps and its `cp EGG / ret z`.
--   Roamers    InitRoamMons' three wRoamMon structs, plus the roam walk that
--              indexes them BY SLOT.
--   BugContest data/wild/bug_contest_mons.asm, ContestScore's tally, the ten
--              contestants and the podium, plus the twenty minute clock.
--   Apricorns  data/items/apricorn_balls.asm and FindApricornsInBag's walk of
--              it, plus the fruit trees and the daily rollover Kurt waits on.
local Apricorns = require("src.core.gen2.Apricorns")
local BugContest = require("src.core.gen2.BugContest")
local Happiness = require("src.core.gen2.Happiness")
local Phone = require("src.core.gen2.Phone")
local Pokerus = require("src.core.gen2.Pokerus")
local Strings = require("src.core.Strings")
local Roamers = require("src.core.gen2.Roamers")
local Unown = require("src.core.gen2.Unown")

local Specials = {}

-- constants/script_constants.asm
local TRUE, FALSE = 1, 0

-- constants/pokemon_constants.asm, for the handlers that name a species.
local MAGIKARP = "MAGIKARP"
local SHUCKLE = "SHUCKLE"

-- constants/misc_constants.asm GBCHECK_*: what GameboyCheck answers.
local GBCHECK_GB, GBCHECK_SGB, GBCHECK_CGB = 0, 1, 2

-- data/events/magikarp_lengths.asm is one table, but the ARITHMETIC around it
-- (CalcMagikarpLength) is what actually produces a length, so both are below.

-- Rolls.  Kept on the module rather than taken from the VM so a test can pin
-- every weighted table below without reaching into love.math, and so the two
-- calling conventions in this codebase (`random(n) -> 1..n` here,
-- `random(n) -> 0..n-1` in src/battle/gen2) cannot get crossed.
Specials.random = math.random

--------------------------------------------------------------------------
-- Plumbing
--------------------------------------------------------------------------

local function hooks(vm)
  return (vm and vm.specials) or {}
end

-- Park the coroutine on `start`, which must call its `done` exactly once.
--
-- The order matters.  `start` runs FIRST, while the coroutine is still on the
-- stack, so a hook that answers synchronously (no love, no stack, a test stub)
-- sets `finished` before the yield is ever reached and the handler simply
-- carries on -- resuming a coroutine that is not suspended would be an error.
-- A hook that answers later leaves the coroutine parked on a yield nothing in
-- Vm:resume claims, and its own callback is what resumes it.
function Specials.block(vm, start)
  local finished, answer = false, nil
  start(function(value)
    answer = value
    finished = true
    if vm.co and coroutine.status(vm.co) == "suspended" then
      vm:resume(value)
    end
  end)
  if finished then return answer end
  return coroutine.yield({ kind = "specialwait" })
end

-- Print a page whose very next act is this handler's OWN `yesorno`.
--
-- Vm's one-command lookahead (Vm:textStays) is what keeps a text box standing
-- under a YES/NO prompt, but it reads the SCRIPT LIST: inside a hand-ported
-- special the row being run is the `special` itself, so nextOp is whatever
-- follows it (`waitbutton` for MomScript) and the lookahead is structurally
-- blind to a prompt this file raises.  Answering it for the length of one page
-- is what the cart does anyway -- `PrintText / call YesNoBox` with nothing in
-- between, and each of these texts ends in `done`, so DoneText returns with no
-- PromptButton (home/text.asm:484) and YesNoBox goes straight up over the box
-- nothing closed.  Without this the box pops on a press the cart never asks
-- for and the question is re-printed underneath the prompt.
local function showRawHeld(vm, body)
  local nextOp = vm.nextOp
  vm.nextOp = "yesorno"
  vm:showRaw(body)
  vm.nextOp = nextOp
end

-- The party, as the handlers see it.  wPartyMon* is one array on the cart and
-- one Lua list here, and every routine below that walks it walks this.
local function party(vm)
  local h = hooks(vm)
  return (h.party and h.party()) or {}
end

local function save(vm)
  local h = hooks(vm)
  return h.save and h.save() or nil
end

local function data(vm)
  local h = hooks(vm)
  return h.data and h.data() or nil
end

-- wScriptVar, spelled the way the asm spells it so a handler reads as its
-- source: `ld a, TRUE / ld [wScriptVar], a`.
local function answer(vm, value)
  vm.scriptVar = value or 0
end

-- Every routine that ends `call GetPokemonName / jp
-- CopyPokemonName_Buffer1_Buffer3` puts a name where the next writetext's
-- {STRBUF} will find it.
local function nameMon(vm, species)
  local h = hooks(vm)
  local name = h.monName and h.monName(species)
  if not name and type(species) == "string" then name = species end
  if name then vm:setStringBuffer(name) end
end

-- SelectMonFromParty: the carry flag is "the player pressed B".  `onDone` gets
-- (index, mon) or (nil, nil), and the handler blocks on it.
local function selectMon(vm, prompt)
  local h = hooks(vm)
  if not h.selectPartyMon then return nil, nil end
  local picked = Specials.block(vm, function(done)
    h.selectPartyMon(prompt, function(index, mon)
      done({ index = index, mon = mon })
    end)
  end)
  picked = picked or {}
  return picked.index, picked.mon
end

--------------------------------------------------------------------------
-- Magikarp lengths (engine/events/magikarp.asm)
--------------------------------------------------------------------------

-- MagikarpLengths (data/events/magikarp_lengths.asm): fourteen `dwb` triplets
-- of "threshold word, divisor byte".  Not extracted -- nothing in the ROM's
-- script bytecode points at it -- so it is transcribed here beside the
-- arithmetic that reads it, in the file's own order.
Specials.MAGIKARP_LENGTHS = {
  { 110, 1 },   -- not used unless the .BCLessThanDE bug is fixed
  { 310, 2 },
  { 710, 4 },
  { 2710, 20 },
  { 7710, 50 },
  { 17710, 100 },
  { 32710, 150 },
  { 47710, 150 },
  { 57710, 100 },
  { 62710, 50 },
  { 64710, 20 },
  { 65210, 5 },
  { 65410, 2 },
  { 65510, 1 },  -- not used
}

-- `rrc` on one byte: an 8-bit rotate right, the bit that falls off coming back
-- in at the top.
local function rrc(byte)
  byte = (byte or 0) % 256
  return math.floor(byte / 2) + (byte % 2) * 128
end

local function xorByte(a, b)
  a, b = (a or 0) % 256, (b or 0) % 256
  local out, bit = 0, 1
  for _ = 1, 8 do
    if (a % 2) ~= (b % 2) then out = out + bit end
    a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
  end
  return out
end

-- CalcMagikarpLength (engine/events/magikarp.asm), transcribed rather than
-- approximated, bug and all: the whole Lake of Rage guru sub-plot is this one
-- number, and the bug is what makes long Magikarp rare.
--
--   bc = rrc(id_hi) ++ rrc(id_lo)  XOR  rrc(rrc(dv_hi)) ++ rrc(rrc(dv_lo))
--
-- Then, walking MagikarpLengths with an index that starts at 2:
--   * bc < 10 is a special case: the length is bc + 190 mm
--   * otherwise the first row whose threshold's HIGH BYTE exceeds bc's high
--     byte wins.  That is .BCLessThanDE's bug -- `ret c / ret nc` makes the
--     low-byte comparison behind it dead code, so only b and d are compared --
--     and it is why `bc - de` underflows and the length lands where it does.
--   * the length is 100 * index + low_byte_of((bc - de) / divisor)
--   * falling off the end of the table is (bc - 65510) + 1600
--
-- Both truncations are the cart's: Divide leaves a 32-bit quotient and the
-- routine reads only hQuotient + 3, its LOW BYTE.
function Specials.magikarpLength(otId, dvWord)
  otId = (otId or 0) % 65536
  dvWord = (dvWord or 0) % 65536
  local b = xorByte(rrc(math.floor(otId / 256)),
    rrc(rrc(math.floor(dvWord / 256))))
  local c = xorByte(rrc(otId % 256), rrc(rrc(dvWord % 256)))
  local bc = b * 256 + c

  local mm
  if b == 0 and c < 10 then
    mm = bc + 190
  else
    local index = 2
    local de = 0
    for _, row in ipairs(Specials.MAGIKARP_LENGTHS) do
      de = row[1]
      if b < math.floor(de / 256) then
        local dividend = (bc - de) % 65536
        mm = 100 * index + (math.floor(dividend / row[2]) % 256)
        break
      end
      index = index + 1
    end
    if not mm then mm = ((bc - de) % 65536) + 1600 end
  end
  mm = mm % 65536

  -- `hl = de * 10`, then a 254-step division: inches = mm * 10 / 254, i.e.
  -- mm / 25.4.  `a` is one byte, so a length past 2550 inches wraps -- which
  -- no reachable length does.
  local inches = math.floor(mm * 10 / 254) % 256
  return math.floor(inches / 12), inches % 12, mm
end

-- PrintMagikarpLength: PRINTNUM_LEFTALIGN over one byte each, with the ′ and ″
-- glyphs (font codes $6e / $6f) between them.  Written as the plain ASCII pair
-- because Font.split has no charmap entry for the two prime marks.
local function magikarpLengthText(feet, inches)
  return string.format("%d'%d\"", feet or 0, inches or 0)
end
Specials.magikarpLengthText = magikarpLengthText

-- The DV word CalcMagikarpLength is handed, out of the port's DV table:
-- (attack << 12) | (defense << 8) | (speed << 4) | special, which is the
-- MON_DVS pair's own layout.
function Specials.dvWord(dvs)
  if type(dvs) == "number" then return dvs % 65536 end
  if type(dvs) ~= "table" then return 0 end
  return ((dvs.attack or 0) % 16) * 4096
    + ((dvs.defense or 0) % 16) * 256
    + ((dvs.speed or 0) % 16) * 16
    + ((dvs.special or 0) % 16)
end

--------------------------------------------------------------------------
-- The handlers
--------------------------------------------------------------------------

local H = {}

-- ---- 0 WarpToSpawnPoint ---------------------------------------------------
-- The whiteout warp, and the few scripted trips home that borrow it.
H.WarpToSpawnPoint = function(vm)
  if vm.warpToSpawnFn then vm.warpToSpawnFn() end
end

-- ---- 20-24 the Bug Catching Contest ---------------------------------------
--
-- Every rule below lives in src/core/gen2/BugContest.lua and NOT here.  These
-- five handlers plus BugContestJudging are the gate scripts' half of the
-- system: Route35NationalParkGate's officer runs ContestDropOffMons,
-- GiveParkBalls and SelectRandomBugContestContestants on the way in, and
-- BugContestResultsScript runs BugContestJudging, ContestReturnMons and
-- CheckPartyFullAfterContest on the way out.  Keeping the state on the SAVE
-- (save.bugContest) rather than on the Vm is required, not tidiness: the cart's
-- masked party and its park balls are in SRAM and survive a save mid-contest.

-- The party as save.bugContest reads it.  The hooks hand back the same table
-- the save holds, so this only fills in a save that has no `party` key at all
-- (a headless test that passed nothing but a hook).
local function contestSave(vm)
  local record = save(vm)
  if not record then
    -- A VM built with no `save` hook at all (a headless test) still has a
    -- party, and the mask has to go somewhere: the VM stands in for the save,
    -- which is enough for every rule and nothing like enough to survive a
    -- reload -- exactly what a cartridge with no SRAM would do.
    vm.contestSave = vm.contestSave or { party = party(vm) }
    return vm.contestSave
  end
  if record.party == nil then record.party = party(vm) end
  return record
end

-- ContestDropOffMons: the party is not stored anywhere, it is MASKED -- the
-- count is written down to 1 and the second species byte is replaced with the
-- -1 terminator, so only the lead mon exists for the duration of the contest.
--
-- `.fainted`: a lead mon with 0 HP refuses, and answers TRUE so the gate
-- attendant can say so.
H.ContestDropOffMons = function(vm)
  answer(vm, BugContest.dropOffMons(contestSave(vm)))
end

-- ContestReturnMons: the count is RECOMPUTED by walking to the terminator, so
-- a mon caught during the contest is still in slot 2 when the tail goes back
-- behind it.  Restoring after the caught mon rather than over it is that walk.
H.ContestReturnMons = function(vm)
  BugContest.returnMons(contestSave(vm))
end

-- GiveParkBalls: BUG_CONTEST_BALLS is 20, wContestMon is cleared first, and the
-- StartBugContestTimer it farcalls is what puts the twenty minutes on the clock.
Specials.BUG_CONTEST_BALLS = BugContest.BALLS

H.GiveParkBalls = function(vm)
  BugContest.start(contestSave(vm))
end

-- CheckPartyFullAfterContest: the mon caught in the contest goes into the
-- party if there is room and into the current box if there is not.  wScriptVar
-- is the three-way answer BugContestResults_DidNotLeaveMons branches on:
-- BUGCONTEST_CAUGHT_MON 0, BUGCONTEST_BOXED_MON 1, BUGCONTEST_NO_CATCH 2
-- (constants/script_constants.asm).
-- _CaughtAskNicknameText (data/text/common_2.asm:717), engine-printed so
-- the extractor never reaches it.
local CONTEST_NICKNAME_PROMPT =
  Strings.source("Give a nickname to\nthe {STRBUF} you\nreceived?")

-- GiveANickname_YesNo (engine/pokemon/caught_nickname.asm:123)
function Specials.askNickname(vm, mon)
  nameMon(vm, mon.species)
  showRawHeld(vm, Strings(CONTEST_NICKNAME_PROMPT))
  if coroutine.yield({ kind = "yesorno" }) then
    -- InitNickname (engine/pokemon/move_mon.asm:1787)
    local h = hooks(vm)
    local name = h.renameMon and Specials.block(vm, function(done)
      h.renameMon(mon, done, { blank = true })
    end)
    -- _InitString's blank test (home/string.asm:6-30)
    if name and name:gsub(" ", "") ~= "" then mon.nickname = name end
  end
end

H.CheckPartyFullAfterContest = function(vm)
  local Breeding = require("src.core.gen2.Breeding")
  local result, mon =
    BugContest.collectCaughtMon(contestSave(vm), Breeding.PARTY_SIZE)
  -- GiveANickname_YesNo runs on both contest arms, party and box
  if mon and result ~= BugContest.NO_CATCH then
    Specials.askNickname(vm, mon)
  end
  answer(vm, result)
end

-- _BugContestJudging (engine/events/bug_contest/judging.asm): ContestScore over
-- wContestMon, BugContest_JudgeContestants for the podium, then the three text
-- pages -- third, second, first, in that order -- each followed by its score
-- page and its placing jingle.  The placing itself is what
-- BugContest_GetPlayersResult leaves in wScriptVar, and the gate script's three
-- `ifequal`s are the prize branches.
--
-- The pages are authored here rather than read out of text.lua because nothing
-- in the ROM's script bytecode points at ContestJudging_*Text: they hang off
-- engine code, so the extractor never reaches them.
local JUDGING = {
  third = Strings.source("Placing third was\n%s,\fwho caught a\n%s!"),
  second = Strings.source("Placing second was\n%s,\fwho caught a\n%s!"),
  first = Strings.source(
    "This Bug-Catching\nContest winner is\f%s,\nwho caught a\n%s!"),
  score = Strings.source("The score was\n%d points!"),
  winningScore = Strings.source("The winning score\nwas %d points!"),
}

-- SFX_1ST_PLACE / SFX_2ND_PLACE / SFX_3RD_PLACE, by their pokegold labels: the
-- text_asm arm of each page plays one and waits for it.
local PLACE_SFX = { "Sfx_1stPlace", "Sfx_2ndPlace", "Sfx_3rdPlace" }

H.BugContestJudging = function(vm)
  local record = contestSave(vm)
  local place = BugContest.runJudging(record)
  local state = BugContest.state(record) or {}
  local results = state.results or {}
  local h = hooks(vm)
  -- wPlayerName, which LoadContestantName copies straight out for ID 1.
  local playerName = record.player and record.player.name
  -- LoadContestantName reads the winner ID, and GetPokemonName the species the
  -- podium recorded, so a slot nobody filled prints nothing at all.
  local order = {
    { entry = results.third, page = JUDGING.third, score = JUDGING.score,
      sfx = PLACE_SFX[3] },
    { entry = results.second, page = JUDGING.second, score = JUDGING.score,
      sfx = PLACE_SFX[2] },
    { entry = results.first, page = JUDGING.first,
      score = JUDGING.winningScore, sfx = PLACE_SFX[1] },
  }
  for _, row in ipairs(order) do
    local entry = row.entry
    if entry then
      local who = BugContest.contestantName(data(vm), entry.id, playerName)
      local what = (h.monName and h.monName(entry.species)) or entry.species
        or ""
      vm:showRaw(Strings(row.page, who, what))
      if h.playSfxNamed then h.playSfxNamed(row.sfx) end
      vm:showRaw(Strings(row.score, entry.score or 0))
    end
  end
  answer(vm, place)
end

-- ---- 25, 26 the Magikarp guru ---------------------------------------------

-- CheckMagikarpLength's four answers, spelled out at the top of the routine:
--   3  a Magikarp that beats the record
--   2  a Magikarp the record still beats
--   1  B pressed in the party list
--   0  the mon picked is not a Magikarp
H.CheckMagikarpLength = function(vm)
  local _, mon = selectMon(vm, "choose")
  if not mon then
    answer(vm, 1)
    return
  end
  if mon.species ~= MAGIKARP then
    answer(vm, 0)
    nameMon(vm, mon.species)
    return
  end
  local feet, inches =
    Specials.magikarpLength(mon.otId, Specials.dvWord(mon.dvs))
  vm:setStringBuffer(magikarpLengthText(feet, inches))
  local record = save(vm)
  local best = record and record.magikarpRecord
  local total = (feet or 0) * 12 + (inches or 0)
  local bestTotal = best and ((best.feet or 0) * 12 + (best.inches or 0)) or 0
  if total <= bestTotal then
    answer(vm, 2)
    return
  end
  if record then
    record.magikarpRecord = {
      feet = feet, inches = inches,
      name = record.player and record.player.name,
    }
  end
  answer(vm, 3)
end

-- MagikarpHouseSign: the record on the wall, in the string buffer for the
-- writetext that follows.  A house nobody has beaten yet reads 0'00", which is
-- what InitializeMagikarpHouse leaves behind.
H.MagikarpHouseSign = function(vm)
  local record = save(vm)
  local best = record and record.magikarpRecord
  vm:setStringBuffer(magikarpLengthText(best and best.feet, best and best.inches))
end

-- ---- 27-29 the Pokecenter -------------------------------------------------
H.HealParty = function(vm)
  if vm.healPartyFn then vm.healPartyFn() end
end

-- The heal machine's light show, BLOCKING: LoadBallsOntoMachine holds 30
-- frames per party ball and .FlashPalettes8Times ten more per flash, and the
-- nurse's "thank you for waiting" must not come up over the machine still
-- running.  wScriptVar carries the machine's location (`setval HEALMACHINE_*`
-- right before the special): 0 Pokecenter, 1 Elm's lab, 2 Hall of Fame.
H.HealMachineAnim = function(vm)
  if not vm.healAnimFn then return end
  Specials.block(vm, function(done)
    vm.healAnimFn(vm.scriptVar or 0, done)
  end)
end

-- PokemonCenterPC (engine/events/pokecenter_pc.asm): the Pokecenter PC's
-- whose-PC top menu.  The special only opens the screen -- World:openPc
-- pushes src/ui/gen2/CenterPcMenu.lua, which carries the party gate, the
-- BILL's / <PLAYER>'s / PROF.OAK's / HALL OF FAME gating and the shutdown.
-- The asm never writes wScriptVar, so neither does this.
H.PokemonCenterPC = function(vm)
  if vm.openPcFn then vm.openPcFn() end
end

-- PlayersHousePC ends `ld a, c / ld [wScriptVar], a`, and _PlayersHousePC's c
-- is TRUE for exactly one reason: the DECORATION menu moved something.  That
-- is the branch behind it -- PlayersHousePCScript's `iftrue .Warp`, whose
-- `warp NONE, 0, 0` reloads the room so the two decoration callbacks run
-- again.  A decoration placed with no reload would not appear until the next
-- time the map loaded anyway, which is the cart's behaviour and the reason the
-- warp is there.
H.PlayersHousePC = function(vm)
  local h = hooks(vm)
  if not h.playersHousePc then
    -- No bedroom PC on this side (a test harness, or the Pokecenter hook only):
    -- open what there is and answer the way a player who changed nothing does.
    answer(vm, FALSE)
    if vm.openPcFn then vm.openPcFn() end
    return
  end
  local changed = Specials.block(vm, function(done)
    h.playersHousePc(done)
  end)
  answer(vm, changed and TRUE or FALSE)
end

-- ToggleDecorationsVisibility / ToggleMaptileDecorations
-- (engine/overworld/decorations.asm), the two PLAYERS_HOUSE_2F map callbacks.
-- Both rebuild the room from the eight wDeco* bytes: the first writes the four
-- object slots (wVariableSprites plus each object's event flag), the second
-- paints the bed, the plant, the poster and the carpet into the block buffer.
--
-- Neither writes wScriptVar, and neither may block: a map callback is a nested
-- script run.  With no hooks they do nothing at all, which is the room a save
-- with no decorations shows.
H.ToggleDecorationsVisibility = function(vm)
  local h = hooks(vm)
  if h.toggleDecorationsVisibility then h.toggleDecorationsVisibility() end
end

H.ToggleMaptileDecorations = function(vm)
  local h = hooks(vm)
  if h.toggleMaptileDecorations then h.toggleMaptileDecorations() end
end

-- ---- 30-32, 68-69 the Day Care --------------------------------------------
--
-- All three doors are the same screen with a different `side`, and the model
-- behind it is src/core/gen2/Breeding.lua.  DayCareManOutside is the only one
-- that writes wScriptVar (TRUE = the party was full, so the egg is kept and
-- the script asks again), which is why the push carries its answer back.
local function dayCare(vm, side)
  local h = hooks(vm)
  if not h.dayCare then
    answer(vm, FALSE)
    return
  end
  local value = Specials.block(vm, function(done)
    h.dayCare(side, done)
  end)
  answer(vm, value or FALSE)
end

H.DayCareMan = function(vm) dayCare(vm, "man") end
H.DayCareLady = function(vm) dayCare(vm, "lady") end
H.DayCareManOutside = function(vm) dayCare(vm, "outside") end

-- DayCareMon1 / DayCareMon2: not the conversation, just the "you left X here"
-- line, the deposited mon's cry, and -- only when the OTHER side is occupied
-- too -- the compatibility line about the pair.  Both texts live in
-- data/text/common_2.asm and are printed by engine/pokemon/breeding.asm
-- rather than by any bytecode, so the extractor seeds its text walker at them
-- by name (RomExtractorGen2's NAMED_TEXT); `line` below prefers the cache's
-- own characters and falls back to the transcription, which is the shape
-- src/ui/gen2/DayCareMenu.lua uses for the same block.
local DAY_CARE_LEFT = {
  man = { label = "_LeftWithDayCareManText",
    body = Strings.source(
      "It's {STRBUF}\nthat was left with\nthe DAY-CARE MAN.") },
  lady = { label = "_LeftWithDayCareLadyText",
    body = Strings.source(
      "It's {STRBUF}\nthat was left with\nthe DAY-CARE LADY.") },
}

-- DayCareMonCompatibilityText's five verdicts, keyed by the string
-- Breeding.compatibilityText hands back (Breeding.COMPATIBILITY_*), in the
-- ASM's own fall-through order.  The name in {STRBUF} is the OTHER parent's:
-- `ld hl, wBreedMon2Nickname / call DayCareMonCompatibilityText` copies it
-- into wStringBuffer1 before the verdict is picked.
local COMPATIBILITY = {
  brimming = { label = "_BreedBrimmingWithEnergyText",
    body = Strings.source("It's brimming with\nenergy.") },
  none = { label = "_BreedNoInterestText",
    body = Strings.source("It has no interest\nin {STRBUF}.") },
  cares = { label = "_BreedAppearsToCareForText",
    body = Strings.source("It appears to care\nfor {STRBUF}.") },
  friendly = { label = "_BreedFriendlyText",
    body = Strings.source("It's friendly with\n{STRBUF}.") },
  interest = { label = "_BreedShowsInterestText",
    body = Strings.source("It shows interest\nin {STRBUF}.") },
}

-- The extracted string for one of the entries above, or its transcription.
local function commonLine(vm, entry)
  if not entry then return "" end
  local CommonText = require("src.core.gen2.CommonText")
  return CommonText.get(vm and vm.text, entry.label) or Strings(entry.body)
end

local function dayCareMon(vm, side)
  local Breeding = require("src.core.gen2.Breeding")
  local record = save(vm)
  local h = hooks(vm)
  local mine = Breeding.side(record, side) or {}
  local other = Breeding.side(record, side == "man" and "lady" or "man") or {}
  local mon = mine.mon
  if not mon then return end
  local function monName(m)
    return m.nickname or m.name or m.species or "#MON"
  end
  vm:setStringBuffer(monName(mon))
  vm:showRaw(commonLine(vm, DAY_CARE_LEFT[side]))
  local index = h.monIndex and h.monIndex(mon.species)
  if index and vm.cryFn then vm.cryFn(index) end
  -- `bit DAYCARE*_HAS_MON_F / jr z, DayCareMonCursor`: with only one mon in
  -- there the routine stops at the blinking cursor and says nothing else.
  if not other.mon then return end
  local value = Breeding.compatibility(data(vm), mon, other.mon)
  vm:setStringBuffer(monName(other.mon))
  vm:showRaw(commonLine(vm, COMPATIBILITY[Breeding.compatibilityText(value)]))
end

H.DayCareMon1 = function(vm) dayCareMon(vm, "man") end
H.DayCareMon2 = function(vm) dayCareMon(vm, "lady") end

-- ---- the Blackthorn move deleter -------------------------------------------
--
-- MoveDeletion (engine/events/move_deleter.asm).  MoveDeletersHouse's own
-- script is `faceplayer / opentext / special MoveDeletion / waitbutton /
-- closetext` (maps/MoveDeletersHouse.asm), so every PrintText below runs
-- inside a textbox the caller already opened and this never opens or closes
-- one itself.  The asm never writes wScriptVar on any path -- there is no
-- `ld [wScriptVar], a` anywhere in the routine -- so this handler leaves
-- vm.scriptVar exactly as `special` found it, the same way the deliberate
-- stubs this replaces used to leave it at a fixed value; nothing reads it
-- after this call because MoveDeleter's own script has no branch behind it.
--
-- data/text/common_3.asm, transcribed the way DAY_CARE_LEFT above transcribes
-- its own common_* text: the extractor does not reach the common banks.
local MOVE_DELETER_TEXT = {
  intro = Strings.source(
    "Um… Oh, yes, I'm\nthe MOVE DELETER.\n\nI can make #MON\n"
    .. "forget moves.\n\nShall I make a\n#MON forget?"),
  declined = Strings.source("No? Come visit me\nagain."),
  whichMon = Strings.source("Which #MON?"),
  egg = Strings.source("An EGG doesn't\nknow any moves!"),
  onlyOneMove = Strings.source("That #MON knows\nonly one move."),
  whichMove = Strings.source("Which move should\nit forget, then?"),
  confirm = Strings.source("Oh, make it forget\n{STRBUF}?"),
  forgot = Strings.source("Done! Your #MON\nforgot the move."),
}

-- ChooseMoveToDelete is its own screen (engine/pokemon/mon_menu.asm), not a
-- textbox, so it goes through World like SelectMonFromParty does.  A mon with
-- one move never reaches it: `.onlyonemove` is checked first, exactly as the
-- asm checks `ld a, [hl] / and a / jr z, .onlyonemove` before the farcall.
local function chooseMoveToDelete(vm, mon)
  local h = hooks(vm)
  if not h.chooseMoveToDelete then return nil end
  return Specials.block(vm, function(done)
    h.chooseMoveToDelete(mon, done)
  end)
end

H.MoveDeletion = function(vm)
  -- engine/events/move_deleter.asm:2-4, PrintText then `call YesNoBox`.
  showRawHeld(vm, Strings(MOVE_DELETER_TEXT.intro))
  local wantsToDelete = coroutine.yield({ kind = "yesorno" })
  if not wantsToDelete then
    vm:showRaw(Strings(MOVE_DELETER_TEXT.declined))
    return
  end

  vm:showRaw(Strings(MOVE_DELETER_TEXT.whichMon))
  local _, mon = selectMon(vm, "choose")
  if not mon then
    vm:showRaw(Strings(MOVE_DELETER_TEXT.declined))
    return
  end

  -- `ld a, [wCurPartySpecies] / cp EGG`: the port marks an egg slot with
  -- `isEgg` instead of overwriting the species (src/core/gen2/Breeding.lua),
  -- so that is the flag this reads.
  if mon.isEgg then
    vm:showRaw(Strings(MOVE_DELETER_TEXT.egg))
    return
  end

  if #(mon.moves or {}) <= 1 then
    vm:showRaw(Strings(MOVE_DELETER_TEXT.onlyOneMove))
    return
  end

  vm:showRaw(Strings(MOVE_DELETER_TEXT.whichMove))
  local index = chooseMoveToDelete(vm, mon)
  if not index then
    vm:showRaw(Strings(MOVE_DELETER_TEXT.declined))
    return
  end

  local entry = mon.moves[index]
  local d = data(vm)
  local def = entry and d and d.moves and d.moves[entry.id]
  vm:setStringBuffer((def and def.name) or (entry and entry.id) or "?")
  -- engine/events/move_deleter.asm:33-35, the same PrintText / YesNoBox pair.
  showRawHeld(vm, Strings(MOVE_DELETER_TEXT.confirm))
  local reallyDelete = coroutine.yield({ kind = "yesorno" })
  if not reallyDelete then
    vm:showRaw(Strings(MOVE_DELETER_TEXT.declined))
    return
  end

  -- .DeleteMove: shifts every later move (and its PP) down one slot and
  -- clears the last one, which is exactly what removing the array entry does
  -- here -- `mon` is the live save.party reference selectMon handed back, not
  -- a copy.
  table.remove(mon.moves, index)

  -- `call WaitSFX / ld de, SFX_MOVE_DELETED / call PlaySFX / call WaitSFX`:
  -- wait out whatever the YES/NO click left playing, then the deletion jingle,
  -- then wait that out too before the last line prints.
  coroutine.yield({ kind = "waitsfx" })
  local h = hooks(vm)
  if h.playSfxNamed then h.playSfxNamed("Sfx_MoveDeleted", 97) end
  coroutine.yield({ kind = "waitsfx" })

  vm:showRaw(Strings(MOVE_DELETER_TEXT.forgot))
end

-- ---- the Goldenrod NAME RATER ----------------------------------------------
--
-- NameRater (engine/events/name_rater.asm).  Like MoveDeletion above, the
-- caller's own script is just `special NameRater` inside an already-open
-- textbox, so every line here PrintTexts into that box and the handler never
-- opens or closes one.  The asm never writes wScriptVar either, so vm.scriptVar
-- is left exactly as `special` found it.
--
-- data/text/common_1.asm, transcribed the way MOVE_DELETER_TEXT transcribes
-- its own bank -- this one IS reached by the extractor, but a map's own
-- `special` byte only points at the routine, not at the text bank behind it.
local NAME_RATER_TEXT = {
  hello = Strings.source(
    "Hello, hello! I'm\nthe NAME RATER.\n\nI rate the names\nof #MON.\n\n"
    .. "Would you like me\nto rate names?"),
  comeAgain = Strings.source("OK, then. Come\nagain sometime."),
  whichMon = Strings.source("Which #MON's\nnickname should I\nrate for you?"),
  egg = Strings.source("Whoa… That's just\nan EGG."),
  perfectName = Strings.source(
    "Hm… {STRBUF}?\nWhat a great name!\nIt's perfect.\n\nTreat {STRBUF}\n"
    .. "with loving care."),
  betterName = Strings.source(
    "Hm… {STRBUF}…\nThat's a fairly\ndecent name.\n\nBut, how about a\n"
    .. "slightly better\nnickname?\n\nWant me to give it\na better name?"),
  whatName = Strings.source("All right. What\nname should we\ngive it, then?"),
  finished = Strings.source("That's a better\nname than before!\n\nWell done!"),
  sameName = Strings.source(
    "It might look the\nsame as before,\n\nbut this new name\n"
    .. "is much better!\n\nWell done!"),
  named = Strings.source("All right. This\n#MON is now\nnamed {STRBUF}."),
}

-- IsNewNameEmpty: the typed name is empty if every character up to the
-- terminator (or MON_NAME_LENGTH - 1) is a space -- a blank keyboard entry
-- reads the same as a cancelled one.
local function isBlankName(name)
  return not name or name:match("^%s*$") ~= nil
end

local function renameMon(vm, mon)
  local h = hooks(vm)
  if not h.renameMon then return nil end
  return Specials.block(vm, function(done)
    h.renameMon(mon, done)
  end)
end

-- CheckIfMonIsYourOT: the OT name AND the OT id both have to match, or the
-- mon reads as traded.  A mon that has never changed hands carries no `ot` /
-- `otId` at all (Mon.new sets neither), which this treats as "yours" the
-- same way H.FindPartyMonThatSpeciesYourTrainerID's `mon.otId == nil` arm
-- does.
local function isTradedMon(vm, mon)
  if not mon then return false end
  local record = save(vm)
  local player = record and record.player
  if not player then return false end
  if mon.ot ~= nil and mon.ot ~= player.name then return true end
  if mon.otId ~= nil and mon.otId ~= player.id then return true end
  return false
end

H.NameRater = function(vm)
  -- engine/events/name_rater.asm:3-5, PrintText then `call YesNoBox`.
  showRawHeld(vm, Strings(NAME_RATER_TEXT.hello))
  local wantsToRate = coroutine.yield({ kind = "yesorno" })
  if not wantsToRate then
    vm:showRaw(Strings(NAME_RATER_TEXT.comeAgain))
    return
  end

  vm:showRaw(Strings(NAME_RATER_TEXT.whichMon))
  local _, mon = selectMon(vm, "choose")
  if not mon then
    vm:showRaw(Strings(NAME_RATER_TEXT.comeAgain))
    return
  end

  -- `cp EGG`, the same isEgg flag MoveDeletion checks above.
  if mon.isEgg then
    vm:showRaw(Strings(NAME_RATER_TEXT.egg))
    return
  end

  -- GetCurNickname puts the current name where {STRBUF} finds it before
  -- either of the two texts below read it.
  local currentName = mon.nickname or mon.name or mon.species or "?"
  vm:setStringBuffer(currentName)

  if isTradedMon(vm, mon) then
    vm:showRaw(Strings(NAME_RATER_TEXT.perfectName))
    return
  end

  -- engine/events/name_rater.asm:21-23, the same PrintText / YesNoBox pair.
  showRawHeld(vm, Strings(NAME_RATER_TEXT.betterName))
  local wantsRename = coroutine.yield({ kind = "yesorno" })
  if not wantsRename then
    vm:showRaw(Strings(NAME_RATER_TEXT.comeAgain))
    return
  end

  vm:showRaw(Strings(NAME_RATER_TEXT.whatName))
  local newName = renameMon(vm, mon)

  -- IsNewNameEmpty and CompareNewToOld both fall into `.samename`: an empty
  -- entry or a re-typed copy of the old name is treated as "unchanged", not
  -- as a second decline.
  local unchanged = isBlankName(newName) or newName == currentName
  local finalName = currentName
  if not unchanged then
    mon.nickname = newName
    finalName = newName
  end

  -- `.samename` re-runs GetCurNickname (now the new name, on the changed
  -- path) before NameRaterNamedText, then falls into whichever of
  -- FinishedText / SameNameText applies.
  vm:setStringBuffer(finalName)
  vm:showRaw(Strings(NAME_RATER_TEXT.named))
  if unchanged then
    vm:showRaw(Strings(NAME_RATER_TEXT.sameName))
  else
    vm:showRaw(Strings(NAME_RATER_TEXT.finished))
  end
end

-- ---- 36 NameRival ---------------------------------------------------------
-- engine/events/specials.asm NameRival: `farcall _NamingScreen` returns only
-- when the keyboard closes, then InitName fills an empty wRivalName with the
-- version default ("SILVER" on Gold).  That default is the FALLBACK, not the
-- seed: before this special runs, wRivalName holds InitializeNPCNames' "???"
-- (engine/menus/intro_menu.asm), which is the name the Cherrygrove theft
-- battle prints.  The script's very next writetext is the
-- officer's "OK! So <RIVAL>" line, so the handler has to PARK on the screen:
-- running on past it printed the old name with the keyboard still up.
H.NameRival = function(vm)
  if not vm.nameRivalFn then return end
  Specials.block(vm, function(done) vm.nameRivalFn(done) end)
end

-- ---- 37, 108-110 the clock ------------------------------------------------

-- SetDayOfWeek (engine/rtc/timeset.asm:382): the "what day is it?" wheel Mom
-- puts up with the POKeGEAR.  It BLOCKS -- the special does not return until
-- the player has picked a day and confirmed it -- which is why the script's
-- `.SetDayOfWeek` label loops back here.  The screen is
-- src/ui/gen2/InitClock.lua's day mode; a run with no screen to push falls back
-- to the host clock's own day, which is what the player would have picked.
H.SetDayOfWeek = function(vm)
  local record = save(vm)
  if not record then return end
  local Clock = require("src.core.gen2.Clock")
  local h = hooks(vm)
  local picked
  if h.setDayOfWeek then
    picked = Specials.block(vm, function(done) h.setDayOfWeek(done) end)
  end
  if type(picked) ~= "number" then
    Clock.setWeekday(record, Clock.hostWeekday())
  end
  record.rtc = record.rtc or {}
  record.rtc.day = tonumber(os.date("%j")) or record.rtc.day
end

-- InitialSetDSTFlag / InitialClearDSTFlag (engine/rtc/timeset.asm): one bit
-- in wDST, asked once during Mom's clock ladder.  Each routine also reprints
-- the clock and puts its OWN confirmation into the open textbox -- the
-- PrintHoursMins time in front of .DSTIsThatOKText / .TimeAskOkayText -- and
-- the `yesorno` right after it in PlayersHouse1F's script reads THAT page; its
-- iffalse loops back to `.SetDayOfWeek`.  A handler that stays silent leaves
-- the confirm prompt hanging on the previous question, which reads as Mom
-- asking about DST over and over.
local function dstConfirmTime(vm)
  -- PrintHoursMins reads hHours / hMinutes, which are the GAME clock -- the
  -- base InitClock and Mom's own wheel just wrote, not the host's.
  local Clock = require("src.core.gen2.Clock")
  local record = save(vm)
  local w = hooks(vm).world
  local hour = (w and w.hour and w:hour()) or Clock.hour(record)
  return string.format("%d:%02d", hour, Clock.minute(record))
end

local DST_CONFIRM = Strings.source("%s DST,\nis that OK?")
local TIME_CONFIRM = Strings.source("%s,\nis that OK?")

H.InitialSetDSTFlag = function(vm)
  local record = save(vm)
  if record then
    record.rtc = record.rtc or {}
    record.rtc.dst = true
  end
  vm:showRaw(Strings(DST_CONFIRM, dstConfirmTime(vm)))
end

H.InitialClearDSTFlag = function(vm)
  local record = save(vm)
  if record then
    record.rtc = record.rtc or {}
    record.rtc.dst = false
  end
  vm:showRaw(Strings(TIME_CONFIRM, dstConfirmTime(vm)))
end

-- MrChrono prints the raw RTC registers into the text box: a debug readout the
-- cart leaves reachable through the Goldenrod clock man.  The numbers are put
-- in the string buffer rather than laid out by hand, since nothing here owns a
-- text box.
H.MrChrono = function(vm)
  local record = save(vm)
  local rtc = (record and record.rtc) or {}
  vm:setStringBuffer(string.format("RT %d  DF %d",
    rtc.day or 0, rtc.dst and 1 or 0))
end

-- ---- 40 the wall radios -----------------------------------------------------
--
-- MapRadio (engine/events/specials.asm): `ld a, [wScriptVar] / ld e, a /
-- farcall PlayRadio`.  The setval before the special left a MAPRADIO_* station
-- index in wScriptVar, and PlayRadio blocks with the joypad until A or B --
-- which is what the six in-house radios and the bedroom set after the starter
-- all are (std_scripts.asm Radio1Script / Radio2Script).  The screen is
-- src/ui/gen2/MapRadio.lua; the push goes through hooks.pushScreen so a test
-- can stub the seam.  Neither the special nor PlayRadio writes wScriptVar
-- back, so vm.scriptVar keeps the station index it arrived with.
H.MapRadio = function(vm)
  local h = hooks(vm)
  if not h.pushScreen then return end
  local channel = vm.scriptVar or 0
  Specials.block(vm, function(done)
    local ok = h.pushScreen("Gen2MapRadio", {
      channel = channel,
      onDone = function() done(true) end,
    })
    if not ok then done(false) end
  end)
end

-- ---- 42-44 the Game Corner ------------------------------------------------
--
-- StartGameCornerGame is CheckCoinsAndCoinCase and then the machine.  The
-- check is transcribed here rather than left to the screen, because its two
-- refusals are TEXT and the script has to see them before the machine opens:
-- no coins at all, or no COIN_CASE to hold them.
local COIN_CASE = 0x36 -- constants/item_constants.asm:62

-- _NoCoinsText / _NoCoinCaseText, data/text/common_1.asm.
local NO_COINS_TEXT = "You have no coins."
local NO_COIN_CASE_TEXT = Strings.source("You don't have a\nCOIN CASE.")

local function gameCornerGame(vm, kind)
  local h = hooks(vm)
  local coins = (h.coins and h.coins()) or 0
  if coins == 0 then
    vm:showRaw(Strings(NO_COINS_TEXT))
    return
  end
  if h.hasItem and not h.hasItem(COIN_CASE) then
    vm:showRaw(Strings(NO_COIN_CASE_TEXT))
    return
  end
  if not h.gameCornerGame then return end
  Specials.block(vm, function(done)
    h.gameCornerGame(kind, done)
  end)
end

H.SlotMachine = function(vm) gameCornerGame(vm, "slots") end
H.CardFlip = function(vm) gameCornerGame(vm, "cardflip") end

-- ---- the Ruins of Alph ----------------------------------------------------
--
-- UnownPuzzle: `call FadeToMenu / farcall _UnownPuzzle / ld a,
-- [wSolvedUnownPuzzle] / ld [wScriptVar], a / call ExitAllMenus`.
--
-- wScriptVar goes IN as well as out: LoadUnownPuzzlePiecesGFX reads it
-- (`maskbits NUM_UNOWN_PUZZLES`) to pick which of the four pictures is being
-- assembled, which is what the chamber's `setval UNOWNPUZZLE_KABUTO` in front
-- of the special is for.  So the id has to be read before the screen opens and
-- the answer written after it closes, and a screen that cannot open answers 0
-- -- the same "backed out" arm a quit takes.
H.UnownPuzzle = function(vm)
  local h = hooks(vm)
  local puzzle = (vm.scriptVar or 0) % 4
  if not h.unownPuzzle then
    vm.scriptVar = 0
    return
  end
  local solved = Specials.block(vm, function(done)
    h.unownPuzzle(puzzle, done)
  end)
  vm.scriptVar = solved and 1 or 0
end

-- CountUnown has no row in SpecialsPointers and therefore no handler here: it
-- is a plain routine, and its one caller is engine/overworld/variables.asm
-- .UnownCaught, which reads the count out of b.  That is VAR_UNOWNCOUNT, and
-- World:readVar answers it from the same list (src/core/gen2/Unown.lua).

-- UnownPrinter (engine/events/print_unown.asm _UnownPrinter), the research
-- centre's ALPH RUINS STAMP machine.  It is one of the printer specials and
-- it is the one that is NOT stubbed, because only half of it needs the
-- peripheral: the viewer -- the sheet of stamps LEFT and RIGHT walk through
-- -- is drawn on the cartridge itself, and only the A press farcalls
-- PrintUnownStamp.  src/ui/gen2/UnownPrinter.lua is that viewer and takes the
-- A press nowhere, which is what a cartridge with nothing in its link port
-- does; PrintDiploma next door has no viewer half at all and stays a stub.
--
-- `ld a, [wUnownDex] / and a / ret z` is the gate: with no Unown caught the
-- special returns before it draws anything.  The routine never writes
-- wScriptVar, so vm.scriptVar is left exactly as `special` found it -- the
-- same contract H.PhotoStudio and H.MoveDeletion keep.
H.UnownPrinter = function(vm)
  local h = hooks(vm)
  local file = save(vm)
  if file and #Unown.dex(file) == 0 then return end
  if not h.showUnownPrinter then return end
  Specials.block(vm, function(done)
    h.showUnownPrinter(function() done(true) end)
  end)
end

-- OverworldTownMap (engine/events/specials.asm): FadeToMenu, run the
-- view-only `_TownMap` loop until B, then ExitAllMenus.  This is used by every
-- COLL_TOWN_MAP wall map and the bedroom decoration, and does not require the
-- player to own the POKeGEAR's MAP card.
H.OverworldTownMap = function(vm)
  local h = hooks(vm)
  if not h.showTownMap then return end
  Specials.block(vm, function(done)
    h.showTownMap(function() done(true) end)
  end)
end

-- GameCornerPrizeMonCheckDex: a prize mon the player has never caught shows
-- its #DEX page as it is handed over.  The catch itself is the prize counter's
-- job (src/ui/gen2/PrizeMenu.lua); this is the entry, and wScriptVar carries
-- the species in and out untouched.
H.GameCornerPrizeMonCheckDex = function(vm)
  local record = save(vm)
  local h = hooks(vm)
  local species = h.monName and h.monName(vm.scriptVar)
  if not (record and species) then return end
  record.pokedex = record.pokedex or { seen = {}, caught = {} }
  if record.pokedex.caught[species] then return end
  record.pokedex.seen[species] = true
  record.pokedex.caught[species] = true
end

-- UnusedSetSeenMon: SetSeenMon on wScriptVar - 1.  Unreferenced in Gold, but
-- one line and correct.
H.UnusedSetSeenMon = function(vm)
  local record = save(vm)
  local h = hooks(vm)
  local species = h.monName and h.monName(vm.scriptVar)
  if not (record and species) then return end
  record.pokedex = record.pokedex or { seen = {}, caught = {} }
  record.pokedex.seen[species] = true
end

-- ---- 45-55 the presentation block -----------------------------------------
--
-- None of these is state.  They are the fade, the palette reload and the
-- sprite refresh a scripted cutscene brackets its set change with, and the
-- port's single map image plus one people list is what stands in for the
-- cart's VRAM shuffling.  Every one is listed rather than folded together so
-- that a reader looking for FadeOutToBlack finds it.
local function fade(vm, kind)
  local h = hooks(vm)
  if h.fade then h.fade(kind) end
end

H.FadeOutToWhite = function(vm) fade(vm, "outWhite") end
H.FadeOutToBlack = function(vm) fade(vm, "outBlack") end
H.FadeInFromWhite = function(vm) fade(vm, "inWhite") end
H.FadeInFromBlack = function(vm) fade(vm, "inBlack") end

-- ClearBGPalettes / ClearBGPalettesBufferScreen / ClearTilemap: the screen is
-- blanked to the background colour under a fade that is already down.  The
-- port fades with a flat sheet, so the sheet IS the cleared screen.
H.ClearBGPalettes = function(vm) fade(vm, "outBlack") end
H.ClearBGPalettesBufferScreen = function(vm) fade(vm, "outBlack") end
H.ClearTilemap = function(vm) fade(vm, "outBlack") end

-- UpdateTimePals: re-resolve the clock's palette without touching anything
-- else, which is exactly what World:applyPalettes plus a re-bake does.
H.UpdateTimePals = function(vm)
  local h = hooks(vm)
  if h.reloadSprites then h.reloadSprites(true) end
end

-- UpdateSprites / ReloadSpritesNoPalettes: respawn the object list.  The
-- second one is the same walk with LoadMapPalettes skipped, which is why a
-- scripted swap of an NPC's sprite does not restart the palette fade.
H.UpdateSprites = function(vm)
  local h = hooks(vm)
  if h.reloadSprites then h.reloadSprites(true) end
end

H.ReloadSpritesNoPalettes = function(vm)
  local h = hooks(vm)
  if h.reloadSprites then h.reloadSprites(false) end
end

-- LoadUsedSpritesGFX: the VRAM pack for whichever sprites this map actually
-- uses.  The port loads a sheet per sprite on demand, so the whole routine is
-- the rebuild that follows it.
H.LoadUsedSpritesGFX = function(vm)
  local h = hooks(vm)
  if h.reloadSprites then h.reloadSprites(false) end
end

-- UpdatePlayerSprite: the player's sheet is a pure function of wPlayerState
-- (data/sprites/player_sprites.asm ChrisStateSprites), which is what makes
-- getting on and off a Lapras a one-byte change rather than an animation.
H.UpdatePlayerSprite = function(vm)
  local h = hooks(vm)
  if h.updatePlayerSprite then h.updatePlayerSprite() end
end

-- ---- 58-62 sound and the water --------------------------------------------

-- WaitSFX: hold until the sound effect that is playing finishes.  The VM has
-- the whole mechanism already (the `waitsfx` opcode), so this is that yield.
H.WaitSFX = function(vm)
  coroutine.yield({ kind = "waitsfx" })
end

H.PlayMapMusic = function(vm)
  local h = hooks(vm)
  if h.playMapMusic then h.playMapMusic() end
end

H.RestartMapMusic = function(vm)
  local h = hooks(vm)
  if h.restartMapMusic then h.restartMapMusic() end
end

-- FadeOutMusic: MUSIC_NONE into wMusicFadeID with a control of 2, i.e. a fast
-- ramp to silence and nothing queued behind it.
H.FadeOutMusic = function(vm)
  local h = hooks(vm)
  if h.fadeOutMusic then h.fadeOutMusic() end
end

-- SurfStartStep: the player goes onto the water.  Script_UsedSurf calls this
-- rather than doing it itself, so the script route and the party-menu route
-- land in the same place.
H.SurfStartStep = function(vm)
  local h = hooks(vm)
  if h.surfStartStep then h.surfStartStep(party(vm)[1]) end
end

-- PlayCurMonCry / PlaySlowCry: the cry of wCurPartySpecies, and the same cry
-- at a lower pitch (the Lake of Rage Gyarados, the Snorlax).  The port has no
-- pitch control on a cry, so the slow one is the ordinary one -- which is a
-- known, deliberate flattening rather than a missing call.
local function currentCry(vm)
  local h = hooks(vm)
  local species = vm.scriptVar
  if species and species ~= 0 and vm.cryFn then
    vm.cryFn(species)
    return
  end
  local mon = party(vm)[1]
  local index = mon and h.monIndex and h.monIndex(mon.species)
  if index and vm.cryFn then vm.cryFn(index) end
end

H.PlayCurMonCry = currentCry
H.PlaySlowCry = currentCry

-- ---- 63-66 the party searches ---------------------------------------------
--
-- Four routines that share FoundOne / FoundNone: wScriptVar goes IN as the
-- thing looked for and comes back TRUE or FALSE.  The port's party is a list
-- of records, so each predicate is one line.
local function findPartyMon(vm, predicate)
  local wanted = vm.scriptVar or 0
  for _, mon in ipairs(party(vm)) do
    if predicate(mon, wanted) then
      answer(vm, TRUE)
      return
    end
  end
  answer(vm, FALSE)
end

H.FindPartyMonAboveLevel = function(vm)
  findPartyMon(vm, function(mon, level) return (mon.level or 0) >= level end)
end

H.FindPartyMonAtLeastThatHappy = function(vm)
  findPartyMon(vm, function(mon, want)
    return (mon.happiness or 0) >= want
  end)
end

H.FindPartyMonThatSpecies = function(vm)
  local h = hooks(vm)
  findPartyMon(vm, function(mon, wanted)
    return h.monIndex and h.monIndex(mon.species) == wanted
  end)
end

-- _FindPartyMonThatSpeciesYourTrainerID additionally requires the mon to be
-- YOURS: it is the check that stops a traded Pokemon from counting, which is
-- the whole point of the routine (the Goldenrod bike shop, the Trainer House).
H.FindPartyMonThatSpeciesYourTrainerID = function(vm)
  local h = hooks(vm)
  local record = save(vm)
  local myId = record and record.player and record.player.id
  findPartyMon(vm, function(mon, wanted)
    if not (h.monIndex and h.monIndex(mon.species) == wanted) then return false end
    return myId == nil or mon.otId == nil or mon.otId == myId
  end)
end

-- UnusedCheckUnusedTwoDayTimer: a timer nothing else in the ROM reads.  Kept
-- so the name resolves, answering the 0 an untouched wUnusedTwoDayTimer holds.
H.UnusedCheckUnusedTwoDayTimer = function(vm)
  answer(vm, 0)
end

-- ---- 70-71 the swarms and the contestants ---------------------------------

-- SelectRandomBugContestContestants: five of the ten contestant flags are set,
-- and a SET flag is what keeps that trainer OFF the contest map -- and, at
-- judging time, out of ComputeAIContestantScores.  The rejection roll is
-- BugContest.pickContestants, which stores the choice as a SET keyed by slot:
-- a list of indices would make `absent[1]` the first PICK rather than the first
-- slot's flag, and every judging would then skip contestant 1.
--
-- The flag table itself is data/events/bug_contest_flags.asm, which the
-- extractor writes as eventTables.bugContestFlags; applyContestantFlags is the
-- `.loop1` that RESETS all ten before the five are set, so a second contest
-- does not inherit the first one's absentees and empty the park.
--
-- `vm.events` and `vm.eventTables` rather than a specials hook: both are
-- already on the VM (Vm.new takes them), setevent and clearevent write through
-- the same object, and onFlagsChanged is the deferred rebuild those two use so
-- a flag written mid-script does not pop an NPC out from under the player.
Specials.NUM_BUG_CONTESTANTS = BugContest.NUM_CONTESTANTS
Specials.BUG_CONTESTANTS_PICKED = BugContest.CONTESTANTS_PICKED

H.SelectRandomBugContestContestants = function(vm)
  local chosen = BugContest.pickContestants(contestSave(vm))
  BugContest.applyContestantFlags(vm.events, chosen, vm.eventTables)
  if vm.events and vm.onFlagsChanged then vm.onFlagsChanged() end
end

-- ActivateFishingSwarm: wFishingSwarmFlag takes wScriptVar, and the routine
-- FALLS THROUGH into SetSwarmFlag -- so the map pair and DAILYFLAGS1_SWARM are
-- both live afterwards.  A port that set only the flag would leave the Qwilfish
-- swarm on for good.
H.ActivateFishingSwarm = function(vm)
  local record = save(vm)
  if not record then return end
  record.dailyFlags = record.dailyFlags or {}
  record.dailyFlags.fishingSwarm = vm.scriptVar or 0
  record.dailyFlags.swarm = true
end

-- ---- 74-77 gifts and health -----------------------------------------------

-- GiveShuckle: a level 15 SHUCKLE holding a BERRY, with Mania's own OT and
-- trainer ID, nicknamed SHUCKIE.  Those four facts are what ReturnShuckie
-- checks before it will take the thing back, so none of them is decoration.
Specials.MANIA_OT_ID = 518
Specials.MANIA_OT = "MANIA"
Specials.SHUCKIE_NICKNAME = "SHUCKIE"
Specials.SHUCKIE_LEVEL = 15

H.GiveShuckle = function(vm)
  local Breeding = require("src.core.gen2.Breeding")
  local Mon = require("src.battle.gen2.Mon")
  local list = party(vm)
  if #list >= Breeding.PARTY_SIZE then
    answer(vm, FALSE)
    return
  end
  local mon = Mon.new(data(vm), SHUCKLE, Specials.SHUCKIE_LEVEL, {
    nickname = Specials.SHUCKIE_NICKNAME,
    item = "BERRY",
  })
  if not mon then
    answer(vm, FALSE)
    return
  end
  mon.ot = Specials.MANIA_OT
  mon.otId = Specials.MANIA_OT_ID
  list[#list + 1] = mon
  answer(vm, TRUE)
end

-- ReturnShuckie: the mon has to BE the Shuckie -- species, Mania's trainer ID
-- and Mania's OT name, all three -- and it has to be conscious.  wScriptVar's
-- five answers are the five arms of the routine.  Ported to match the asm's
-- own numbering (constants/script_constants.asm) rather than Lua's usual
-- "0 is the sane default" habit, since ManiasHouse.asm's `ifequal` chain
-- checks these values by number.
Specials.SHUCKIE_WRONG_MON = 0
Specials.SHUCKIE_REFUSED = 1
Specials.SHUCKIE_RETURNED = 2
Specials.SHUCKIE_HAPPY = 3
Specials.SHUCKIE_FAINTED = 4

-- .HappyToStayWithYou's threshold: 150 happiness or better and Mania lets
-- you keep Shuckie instead of taking it back.
Specials.SHUCKIE_HAPPY_THRESHOLD = 150

H.ReturnShuckie = function(vm)
  local index, mon = selectMon(vm, "choose")
  if not mon then
    answer(vm, Specials.SHUCKIE_REFUSED)
    return
  end
  if mon.species ~= SHUCKLE
      or mon.otId ~= Specials.MANIA_OT_ID
      or mon.ot ~= Specials.MANIA_OT then
    answer(vm, Specials.SHUCKIE_WRONG_MON)
    return
  end
  if (mon.hp or 0) <= 0 then
    answer(vm, Specials.SHUCKIE_FAINTED)
    return
  end
  -- The happiness the mon comes back with is what Mania comments on, so it is
  -- read before the slot might get emptied.
  vm.shuckieHappiness = mon.happiness or 0
  if (mon.happiness or 0) >= Specials.SHUCKIE_HAPPY_THRESHOLD then
    -- Shuckie stays with the player: the party slot is untouched.
    answer(vm, Specials.SHUCKIE_HAPPY)
    return
  end
  table.remove(party(vm), index)
  answer(vm, Specials.SHUCKIE_RETURNED)
end

-- BillsGrandfather: pick a mon and hand him its species.  wScriptVar is the
-- species index he then names, 0 for a B press.
H.BillsGrandfather = function(vm)
  local h = hooks(vm)
  local _, mon = selectMon(vm, "choose")
  if not mon then
    answer(vm, 0)
    return
  end
  local index = h.monIndex and h.monIndex(mon.species)
  answer(vm, index or 0)
  nameMon(vm, index or mon.species)
end

-- CheckPokerus -> _CheckPokerus -> ScriptReturnCarry: 1 when any party member
-- carries the virus.  `and $0f` is the whole test -- an ACTIVE infection only,
-- so a party of cured mons (high nybble set, counter zero) answers FALSE and
-- the nurse says nothing.
H.CheckPokerus = function(vm)
  answer(vm, Pokerus.inParty(party(vm)) and TRUE or FALSE)
end

-- ---- 78-80 the money boxes ------------------------------------------------
--
-- engine/menus/menu_2.asm.  The three are DIFFERENT boxes, not one box with
-- three names -- DisplayMoneyAndCoinBalance prints both fields in a 13x3 box of
-- its own -- so the world hook is told which, and a hook that ignores the
-- argument still gets the money box it got before.
H.DisplayCoinCaseBalance = function(vm)
  if vm.showCoinsFn then vm.showCoinsFn() end
end

H.DisplayMoneyAndCoinBalance = function(vm)
  if vm.showMoneyFn then vm.showMoneyFn("moneycoins") end
end

H.PlaceMoneyTopRight = function(vm)
  if vm.showMoneyFn then vm.showMoneyFn("money") end
end

-- ---- 81-84 the Lucky Number Show ------------------------------------------
--
-- The radio show that gives out the MASTER BALL.  Its whole rule is the number
-- of TRAILING digits a mon's trainer ID shares with the day's five-digit lucky
-- number, over the party AND every box:
--
--   5 digits  first prize   wScriptVar 1
--   3 or 4    second prize  wScriptVar 2
--   2         third prize   wScriptVar 3
--   fewer     nothing       wScriptVar 0
--
-- The BEST match wins, which is why the comparison keeps the LOWER wScriptVar
-- (`cp b / jr c, .nomatch`), and a match found in a BOX rather than in the
-- party changes only which of two lines is printed.
local function trailingDigitsShared(a, b)
  local left = string.format("%05d", (a or 0) % 100000)
  local right = string.format("%05d", (b or 0) % 100000)
  local shared = 0
  for i = 5, 1, -1 do
    if left:sub(i, i) ~= right:sub(i, i) then break end
    shared = shared + 1
  end
  return shared
end
Specials.trailingDigitsShared = trailingDigitsShared

local function luckyPrizeFor(shared)
  if shared >= 5 then return 1 end
  if shared >= 3 then return 2 end
  if shared >= 2 then return 3 end
  return 0
end
Specials.luckyPrizeFor = luckyPrizeFor

-- engine/overworld/time.asm's RestartLuckyNumberCountdown: the days from
-- `weekday` until the NEXT Friday, where Friday itself is a full week away
-- rather than zero (`sub c / jr z, .friday_saturday` before the `add 7`).
-- GetWeekday counts SUNDAY 0 .. SATURDAY 6, same as BugContest.weekday.
local function daysUntilFriday(weekday)
  return ((BugContest.FRIDAY - (weekday or 0) - 1) % 7) + 1
end
Specials.daysUntilFriday = daysUntilFriday

-- save.luckyNumberReset stands in for wLuckyNumberDayTimer: { remaining, day }
-- the same shape Apricorns.startDailyResetTimer uses, just armed for a week
-- instead of a day.  A save that has never armed it (day == nil) reads as
-- already expired, the same way a freshly zeroed SRAM byte does -- which is
-- what makes the FIRST visit to the Lucky Number Man always reset and roll a
-- number rather than reading a stale zero.
local function luckyNumberTimer(record)
  if type(record) ~= "table" then return nil end
  record.luckyNumberReset = record.luckyNumberReset or { remaining = 0 }
  return record.luckyNumberReset
end

-- _CheckLuckyNumberShowFlag: CheckDayDependentEventHL over wLuckyNumberDayTimer.
-- Advances the stored day as it measures (CalcDaysSince's side effect), then
-- clamps the remaining count at zero, same as Apricorns.checkDailyResetTimer's
-- one-day version.
local function checkLuckyNumberTimer(record, now)
  local timer = luckyNumberTimer(record)
  if not timer then return false end
  if timer.day == nil then return true end
  now = now or BugContest.now()
  local stamp = { day = timer.day }
  local since = BugContest.elapsedSince(stamp, now, "day")
  timer.day = stamp.day
  local left = (timer.remaining or 0) - since.days
  if left < 0 then left = 0 end
  timer.remaining = left
  return left <= 0
end

H.CheckForLuckyNumberWinners = function(vm)
  local record = save(vm)
  local number = record and record.luckyNumber
  answer(vm, 0)
  if not number then return end
  local best, bestMon, inBox = 0, nil, false
  local function consider(mon, fromBox)
    local Breeding = require("src.core.gen2.Breeding")
    if Breeding.isEgg(mon) then return end
    local prize = luckyPrizeFor(trailingDigitsShared(mon.otId, number))
    if prize == 0 then return end
    if best == 0 or prize < best then
      best, bestMon, inBox = prize, mon, fromBox
    end
  end
  for _, mon in ipairs(party(vm)) do consider(mon, false) end
  for _, box in pairs((record and record.boxes) or {}) do
    for _, mon in ipairs(box or {}) do consider(mon, true) end
  end
  answer(vm, best)
  if bestMon then
    nameMon(vm, bestMon.species)
    vm.luckyNumberInBox = inBox
  end
end

-- _CheckLuckyNumberShowFlag -> ScriptReturnCarry: TRUE once wLuckyNumberDayTimer
-- has counted down past the coming Friday, i.e. a new week has started since
-- the show was last reset.  This is the WEEKLY gate; RadioTower1FLuckyNumberManScript
-- only calls ResetLuckyNumberShowFlag (which rolls a fresh number and clears
-- the "already won" bit) when this comes back TRUE, so visiting twice in the
-- same week keeps last week's number and last week's win on record.
H.CheckLuckyNumberShowFlag = function(vm)
  answer(vm, checkLuckyNumberTimer(save(vm)) and TRUE or FALSE)
end

-- ResetLuckyNumberShowFlag: RestartLuckyNumberCountdown re-arms the weekly
-- timer for the days until the NEXT Friday, `res LUCKYNUMBERSHOW_GAME_OVER_F`
-- clears the SAME storage `checkflag`/`setflag ENGINE_LUCKY_NUMBER_SHOW` read
-- and write (data/events/engine_flags.asm's `engine_flag wLuckyNumberShowFlag,
-- LUCKYNUMBERSHOW_GAME_OVER_F`), and LoadOrRegenerateLuckyIDNumber rolls a
-- fresh five-digit number.  Because this only ever runs right after
-- CheckLuckyNumberShowFlag has confirmed the week turned over, "reroll every
-- time this fires" is the same as the cart's "reroll when the stored day
-- differs from today".
H.ResetLuckyNumberShowFlag = function(vm)
  local record = save(vm)
  if not record then return end
  local now = BugContest.now()
  local timer = luckyNumberTimer(record)
  timer.remaining = daysUntilFriday(BugContest.weekday(now))
  timer.day = now.day
  local h = hooks(vm)
  if h.setEngineFlag then h.setEngineFlag("ENGINE_LUCKY_NUMBER_SHOW", nil) end
  record.luckyNumber = Specials.random(0, 99999)
end

-- PrintTodaysLuckyNumber: five digits with leading zeros, into the buffer the
-- following writetext reads.
H.PrintTodaysLuckyNumber = function(vm)
  local record = save(vm)
  vm:setStringBuffer(string.format("%05d",
    (record and record.luckyNumber or 0) % 100000))
end

-- ---- 85 Kurt and the apricorns --------------------------------------------

-- The CANCEL row Kurt_SelectApricorn's .Name draws itself (`db "CANCEL@"`)
-- rather than taking from the item names, because item 0 has no name.
local CANCEL = Strings.source("CANCEL")

-- .MenuHeader: MENU_BACKUP_TILES, `menu_coords 0, 0, 14, 17`, .MenuData and a
-- default option of 1; .MenuData's own byte is STATICMENU_CURSOR |
-- STATICMENU_WRAP (constants/menu_constants.asm bits 7 and 5).  The wrap is
-- the one thing src/ui/gen2/ScriptMenu.lua does not honour yet, so the cursor
-- stops at the ends instead of rolling over; everything else is the header.
local KURT_MENU_FLAGS = 0x80 + 0x20

-- SelectApricornForKurt (engine/events/specials.asm) is two routines deep, and
-- the second one is the half a reader of maps/KurtsHouse.asm cannot see:
--
--   farcall Kurt_SelectApricorn / ld a, c / ld [wScriptVar], a / and a / ret z
--   ld [wCurItem], a / ld a, 1 / ld [wItemQuantityChange], a / TossItem
--
-- so wScriptVar is the ITEM id of the apricorn chosen -- .AskApricorn's ladder
-- is `ifequal BLU_APRICORN` and friends, item constants, not menu rows -- and
-- the apricorn leaves the pack HERE, before the script's setevent runs.
--
-- Kurt_SelectApricorn (engine/menus/menu_2.asm) is FindApricornsInBag plus a
-- DoNthMenu over the list it builds, which is why the rows come out in
-- ApricornBalls order rather than pack order and the last row is always
-- CANCEL.  Both refusals -- FindApricornsInBag's `scf` for a pack with no
-- apricorn in it at all, and the `jr c, .nope` for pressing B -- answer
-- `xor a`, which is the FALSE `.Cancel` waits on.
H.SelectApricornForKurt = function(vm)
  local h = hooks(vm)
  local record = save(vm)
  local list = Apricorns.bagList(record and record.inventory)
  if list.empty then return answer(vm, FALSE) end

  local rows = {}
  for index, apricorn in ipairs(list) do
    rows[index] = (h.itemName and h.itemName(apricorn)) or apricorn
  end
  rows[list.cancel] = Strings(CANCEL)

  local choice = Specials.block(vm, function(done)
    if not h.scriptMenu then return done(0) end
    h.scriptMenu({ items = rows, left = 0, top = 0, right = 14, bottom = 17,
      dataFlags = KURT_MENU_FLAGS, cursor = 1 }, done)
  end)

  local apricorn = Apricorns.select(record and record.inventory,
    tonumber(choice))
  if not apricorn then return answer(vm, FALSE) end
  -- No item id, no toss: an answer the `ifequal` ladder cannot match would
  -- fall through to .Red and hand Kurt an apricorn the player never lost.
  local item = h.itemIndex and h.itemIndex(apricorn)
  if not item or item == 0 then return answer(vm, FALSE) end
  answer(vm, item)
  Apricorns.takeApricorn(record, apricorn)
end

-- ---- 88-89 the first party slot -------------------------------------------

-- GetFirstPokemonHappiness: the happiness of the first NON-EGG party member --
-- the loop skips eggs, which is why a party led by an egg still gets an answer
-- from the mon behind it.
H.GetFirstPokemonHappiness = function(vm)
  local Breeding = require("src.core.gen2.Breeding")
  for _, mon in ipairs(party(vm)) do
    if not Breeding.isEgg(mon) then
      answer(vm, mon.happiness or 0)
      nameMon(vm, mon.species)
      return
    end
  end
  answer(vm, 0)
end

-- CheckFirstMonIsEgg: TRUE when slot 1 holds an egg, and the name goes in the
-- buffer either way (`call GetPokemonName` is past the branch).
H.CheckFirstMonIsEgg = function(vm)
  local Breeding = require("src.core.gen2.Breeding")
  local mon = party(vm)[1]
  answer(vm, Breeding.isEgg(mon) and TRUE or FALSE)
  if mon then nameMon(vm, mon.species) end
end

-- ---- 90 the rare-mon phone call -------------------------------------------
--
-- RandomUnseenWildMon: pick one of the three RAREST slots on the caller's map,
-- and if it is not also one of the four commonest AND has never been seen, the
-- caller tells you about it (wScriptVar 0).  Anything else is 1, "nothing to
-- report".
--
-- GetCallerLocation is a phone routine and the phone-call scripts live in an
-- unextracted ROM bank, so the only map this can honestly read is the one the
-- player is standing on.  That is where the caller would be for every scripted
-- use of it that exists today.
H.RandomUnseenWildMon = function(vm)
  local h = hooks(vm)
  answer(vm, TRUE)
  if not h.rareWildMon then return end
  local species = h.rareWildMon()
  if not species then return end
  local record = save(vm)
  local seen = record and record.pokedex and record.pokedex.seen
  if seen and seen[species] then return end
  nameMon(vm, species)
  answer(vm, FALSE)
end

-- ---- 91, 92 the phone chatter name-drops -----------------------------------
--
-- Both open on GetCallerLocation (engine/phone/phone.asm), which reads the
-- contact on the line out of wCurCaller; the port parks that id on
-- vm.curPhoneCaller when a call's script starts (World:receivePhoneCall for
-- an incoming ring, Game2:runPokegearCall for an outgoing one).
-- Neither routine writes wScriptVar: both end on CopyBytes into
-- wStringBuffer4, which is the {STRBUF} the chat line after them reads.

-- trainers.lua and encounters.lua both store species IDS, not dex indexes,
-- so this is nameMon's sibling for a handler already holding the id.
local function nameSpecies(vm, species)
  local defs = data(vm)
  local def = defs and defs.pokemon and defs.pokemon[species]
  vm:setStringBuffer((def and def.name) or species)
end

-- RandomPhoneWildMon (engine/overworld/wildmons.asm): one of the FOUR
-- commonest grass slots (`call Random / and %11`) on the CALLER'S map, read
-- at the current time of day, named into the buffer.  A caller whose map has
-- no grass table leaves the buffer alone, as the cart's unmatched
-- LookUpWildmonsForMapDE walk would read whatever sat past the last row.
H.RandomPhoneWildMon = function(vm)
  local contact = Phone.CONTACTS[vm.curPhoneCaller or -1]
  local w = hooks(vm).world
  local grass = w and w.encounters and w.encounters.grass
  local entry = contact and contact.map and grass and grass[contact.map]
  local slots = entry and entry.slots
  if not slots then return end
  -- wTimeOfDay, not the palette pin (wildmons.asm:861)
  local daytime = (w and (w.tod or w.daytime)) or "DAY"
  if daytime == "DARK" then daytime = "NITE" end
  local slot = (slots[daytime] or slots.DAY or {})[Specials.random(4)]
  if slot and slot.species then nameSpecies(vm, slot.species) end
end

-- RandomPhoneMon: a mon out of the calling trainer's OWN party, uniform over
-- its length (`call Random / maskbits PARTY_LENGTH / cp e / jr nc` rerolls).
-- The cart walks TrainerGroups by the contact row's class and member bytes;
-- trainers.lua is that table, and the contact stores the same pair as the
-- class id and the member's own id string.
H.RandomPhoneMon = function(vm)
  local contact = Phone.CONTACTS[vm.curPhoneCaller or -1]
  if not (contact and contact.class) then return end
  local defs = data(vm)
  local class = defs and defs.trainers and defs.trainers.classes
    and defs.trainers.classes[contact.class]
  local mons
  for _, row in ipairs((class and class.trainers) or {}) do
    if row.id == contact.member then
      mons = row.party
      break
    end
  end
  if not (mons and #mons > 0) then return end
  local mon = mons[Specials.random(#mons)]
  if mon and mon.species then nameSpecies(vm, mon.species) end
end

-- ---- 95 Snorlax -----------------------------------------------------------
--
-- SnorlaxAwake: TRUE only when the POKe FLUTE channel is the music that is
-- playing AND the player is on one of five cells beside the Snorlax.  Both
-- halves matter -- the flute wakes it from next to it, not from across
-- Vermilion.  The coordinates are the routine's own .ProximityCoords.
Specials.SNORLAX_PROXIMITY = {
  { 33, 8 }, { 34, 10 }, { 35, 10 }, { 36, 8 }, { 36, 9 },
}
Specials.POKE_FLUTE_SONG = "Music_PokeFluteChannel"

H.SnorlaxAwake = function(vm)
  local h = hooks(vm)
  answer(vm, FALSE)
  local song = h.currentMusic and h.currentMusic()
  if song ~= Specials.POKE_FLUTE_SONG then return end
  local x, y = 0, 0
  if h.playerCell then x, y = h.playerCell() end
  for _, cell in ipairs(Specials.SNORLAX_PROXIMITY) do
    if cell[1] == x and cell[2] == y then
      answer(vm, TRUE)
      return
    end
  end
end

-- ---- 96-98 the haircut brothers and Daisy ---------------------------------
--
-- One routine (HaircutOrGrooming) with three happiness tables in front of it.
-- Each table is a weighted roll: a random byte walks the rows subtracting each
-- row's weight, and the row it lands on carries the wScriptVar the script
-- branches on (which of three lines the barber says) and the HAPPINESS_* action
-- applied to the mon.
--
-- The three tables are data/events/happiness_probabilities.asm, transcribed
-- because the extractor never reaches them.  Rows are
-- { weight, scriptVar, happinessChange } where `weight` is the macro's own
-- `N percent` (`* $ff / 100`, integer) and -1 is 255, the catch-all last row:
--
--   Older    30%  -> 2,  50%+1 -> 3,  rest -> 4
--   Younger  60%+1 -> 2, 30%   -> 3,  rest -> 4
--   Daisy    always -> 2
--
-- The wScriptVar values really are 2, 3 and 4 -- not 0-based -- because the
-- barber's script branches on them with `ifequal`.
Specials.HAIRCUT_TABLES = {
  older = {
    { 76, 2, "OLDERCUT1" },   -- 30 percent
    { 128, 3, "OLDERCUT2" },  -- 50 percent + 1
    { 255, 4, "OLDERCUT3" },  -- -1
  },
  younger = {
    { 154, 2, "YOUNGCUT1" },  -- 60 percent + 1
    { 76, 3, "YOUNGCUT2" },   -- 30 percent
    { 255, 4, "YOUNGCUT3" },  -- -1
  },
  daisy = {
    { 255, 2, "GROOMING" },
  },
}

-- HappinessChanges (data/events/happiness_changes.asm) is transcribed ONCE, in
-- src/core/gen2/Happiness.lua, alongside the tier pick and the two clamps.
-- The seven rows the barbers and the groomer reach are a window onto that
-- table, not a second copy: the enum is `const_def 1`, so a row that drifted
-- here would move HAPPINESS_GROOMING off the end of the other one and the two
-- callers of the same cart routine would disagree about the same haircut.
Specials.HAPPINESS_CHANGES = {}
for _, action in ipairs({ "OLDERCUT1", "OLDERCUT2", "OLDERCUT3",
    "YOUNGCUT1", "YOUNGCUT2", "YOUNGCUT3", "GROOMING" }) do
  Specials.HAPPINESS_CHANGES[action] =
    Happiness.CHANGES[Happiness.EVENT[action]]
end

-- ChangeHappiness itself, which is Happiness.change: the band pick, the $ff
-- and 0 carry clamps, and the `cp EGG / ret z` that this wrapper used to be
-- missing.  The egg case cannot be reached from here today (haircut below
-- refuses one before it ever gets this far, the way `.egg` does), but the
-- guard belongs to the routine rather than to one of its callers.
function Specials.changeHappiness(mon, action)
  Happiness.change(mon, action)
end

local function haircut(vm, which)
  local _, mon = selectMon(vm, "choose")
  if not mon then
    answer(vm, 0)
    return
  end
  local Breeding = require("src.core.gen2.Breeding")
  -- `cp EGG / jr z, .egg`: an egg cannot be groomed, and `.egg` leaves
  -- wScriptVar at 0 rather than answering one of the three rows.
  if Breeding.isEgg(mon) then
    answer(vm, 0)
    return
  end
  nameMon(vm, mon.nickname or mon.species)
  local rows = Specials.HAIRCUT_TABLES[which] or Specials.HAIRCUT_TABLES.daisy
  -- `call Random / .loop: sub [hl] / jr c, .ok`: subtract each row's weight
  -- from the rolled byte until it borrows.
  local roll = Specials.random(0, 255)
  local row = rows[#rows]
  for _, candidate in ipairs(rows) do
    if roll < candidate[1] then row = candidate break end
    roll = roll - candidate[1]
  end
  answer(vm, row[2])
  Specials.changeHappiness(mon, row[3])
end

H.OlderHaircutBrother = function(vm) haircut(vm, "older") end
H.YoungerHaircutBrother = function(vm) haircut(vm, "younger") end
H.DaisysGrooming = function(vm) haircut(vm, "daisy") end

-- ---- 100 PROF.OAK's PC #DEX rating -----------------------------------------
--
-- ProfOaksPCBoot (engine/events/prof_oaks_pc.asm).  OaksLab's own script is
-- `writetext OakLabDexCheckText / waitbutton / special ProfOaksPCBoot`, so
-- like MoveDeletion and NameRater above every line here prints straight into
-- an already-open box and never opens or closes one.  The asm never writes
-- wScriptVar either (no branch reads it anywhere), so this leaves
-- vm.scriptVar exactly as `special` found it.
--
-- ProfOaksPC, the outer wrapper with the "want your #DEX rated?" yes/no gate
-- and the "link closed" shutdown line, is what the Pokemon Center's OaksPC
-- menu item farcalls; the whose-PC menu runs that flow inside its own screen
-- (src/ui/gen2/CenterPcMenu.lua oakRate) off the exports below.
-- ProfOaksPCBoot is the only label the cache's specialOrder ever names
-- (OaksLab's dex-completeness check goes straight to it, skipping the
-- yes/no), and it is the one this builds.
--
-- data/text/common_2.asm _OakPCText2/_OakPCText3, transcribed the way
-- MOVE_DELETER_TEXT above transcribes its own bank.  The seen/owned counts
-- are formatted straight into the text with %d instead of through {STRBUF}:
-- the cart puts them in two DIFFERENT buffers (wStringBuffer3,
-- wStringBuffer4) in the one textbox, and the VM's {STRBUF} substitution
-- only ever carries one value.
local OAK_PC_TEXT = {
  completion = Strings.source("Current #DEX\ncompletion level:"),
  counts = Strings.source(
    "%d #MON seen\n%d #MON owned\n\nPROF.OAK's\nRating:"),
}

-- OakRatings (data/events/pokedex_ratings.asm).  Each row is (cap, sfx,
-- text); FindOakRating walks the table with `cp c / jr nc, .match` against
-- ascending caps, which is "the first row whose cap covers the caught
-- count" -- exactly what findOakRating below does.  sfx is the Gold sfx
-- table's own label (audio/sfx_pointers.asm dba lines), not a pokered
-- fanfare name.
local OAK_RATINGS = {
  { max = 9, sfx = "Sfx_DexFanfareLessThan20", text = Strings.source(
    "Look for #MON\nin grassy areas!") },
  { max = 19, sfx = "Sfx_DexFanfareLessThan20", text = Strings.source(
    "Good. I see you\nunderstand how to\nuse # BALLS.") },
  { max = 34, sfx = "Sfx_DexFanfare2049", text = Strings.source(
    "You're getting\ngood at this.\n\nBut you have a\nlong way to go.") },
  { max = 49, sfx = "Sfx_DexFanfare2049", text = Strings.source(
    "You need to fill\nup the #DEX.\n\nCatch different\nkinds of #MON!") },
  { max = 64, sfx = "Sfx_DexFanfare5079", text = Strings.source(
    "You're trying--I\ncan see that.\n\nYour #DEX is\ncoming together.") },
  { max = 79, sfx = "Sfx_DexFanfare5079", text = Strings.source(
    "To evolve, some\n#MON grow,\n\nothers use the\neffects of STONES.") },
  { max = 94, sfx = "Sfx_DexFanfare80109", text = Strings.source(
    "Have you gotten a\nfishing ROD? You\n\ncan catch #MON\nby fishing.") },
  { max = 109, sfx = "Sfx_DexFanfare80109", text = Strings.source(
    "Excellent! You\nseem to like col-\nlecting things!") },
  { max = 124, sfx = "Sfx_CaughtMon", text = Strings.source(
    "Some #MON only\nappear during\n\ncertain times of\nthe day.") },
  { max = 139, sfx = "Sfx_CaughtMon", text = Strings.source(
    "Your #DEX is\nfilling up. Keep\nup the good work!") },
  { max = 154, sfx = "Sfx_DexFanfare140169", text = Strings.source(
    "I'm impressed.\nYou're evolving\n\n#MON, not just\ncatching them.") },
  { max = 169, sfx = "Sfx_DexFanfare140169", text = Strings.source(
    "Have you met KURT?\nHis custom #\nBALLS should help.") },
  { max = 184, sfx = "Sfx_DexFanfare170199", text = Strings.source(
    "Wow. You've found\nmore #MON than\n\nthe last #DEX\nresearch project.") },
  { max = 199, sfx = "Sfx_DexFanfare170199", text = Strings.source(
    "Are you trading\nyour #MON?\n\nIt's tough to do\nthis alone!") },
  { max = 214, sfx = "Sfx_DexFanfare200229", text = Strings.source(
    "Wow! You've hit\n200! Your #DEX\nis looking great!") },
  { max = 229, sfx = "Sfx_DexFanfare200229", text = Strings.source(
    "You've found so\nmany #MON!\n\nYou've really\nhelped my studies!") },
  { max = 239, sfx = "Sfx_DexFanfare230Plus", text = Strings.source(
    "Magnificent! You\ncould become a\n\n#MON professor\nright now!") },
  { max = 248, sfx = "Sfx_DexFanfare230Plus", text = Strings.source(
    "Your #DEX is\namazing! You're\n\nready to turn\nprofessional!") },
  -- The top band (251 real species, the table's cap of 255 covers it): this
  -- is the ONLY place the ROM checks "has the player finished the #DEX", and
  -- it does it here rather than handing off to anything.  The actual diploma
  -- is not this special's business -- GameFreakGameDesignerScript in
  -- Celadon Mansion 3F reads VAR_DEXCAUGHT for itself and is what runs
  -- `special Diploma` (H.Diploma below, src/ui/gen2/Diploma.lua) and
  -- then sets EVENT_ENABLE_DIPLOMA_PRINTING for the Graphic Artist's
  -- `special PrintDiploma` (also stubbed: "printer: no Game Boy Printer").
  -- A finished #DEX here just means every rating after this one is this
  -- same line.
  { max = 255, sfx = "Sfx_DexFanfare230Plus", text = Strings.source(
    "Whoa! A perfect\n#DEX! I've\n\ndreamt about this!\nCongratulations!") },
}

-- CountSetBits over wPokedexSeen/wPokedexCaught.  The port's dex is a
-- species-keyed bool map (src/core/gen2/Save.lua), not a bitfield, so this
-- counts `true` entries the same way Save.summary counts wPokedexCaught for
-- the CONTINUE panel.
local function dexCounts(record)
  local dex = record and record.pokedex
  local seen, caught = 0, 0
  for _, has in pairs((dex and dex.seen) or {}) do
    if has then seen = seen + 1 end
  end
  for _, has in pairs((dex and dex.caught) or {}) do
    if has then caught = caught + 1 end
  end
  return seen, caught
end

-- FindOakRating.  NUM_POKEMON is 251, so `caught` never exceeds the table's
-- own top cap of 255 and this never falls off the end.
local function findOakRating(caught)
  for _, row in ipairs(OAK_RATINGS) do
    if caught <= row.max then return row end
  end
  return OAK_RATINGS[#OAK_RATINGS]
end

H.ProfOaksPCBoot = function(vm)
  vm:showRaw(Strings(OAK_PC_TEXT.completion))
  local seen, caught = dexCounts(save(vm))
  vm:showRaw(Strings(OAK_PC_TEXT.counts, seen, caught))
  local rating = findOakRating(caught)
  local h = hooks(vm)
  if h.playSfxNamed then h.playSfxNamed(rating.sfx) end
  vm:showRaw(Strings(rating.text))
  -- `call PlaySFX / call JoyWaitAorB / call WaitSFX`: the fanfare is left
  -- playing under the rating text, and the caller (OaksLab's own script)
  -- waits it out before closing the box.
  coroutine.yield({ kind = "waitsfx" })
end

-- The whose-PC menu's PROF.OAK's PC row (src/ui/gen2/CenterPcMenu.lua) runs
-- ProfOaksPC's rating flow inside a screen rather than a script, so the
-- counts, the rating pick and the two OakPC texts are exported here rather
-- than transcribed a second time.
Specials.dexCounts = dexCounts
Specials.findOakRating = findOakRating
Specials.OAK_PC_TEXT = OAK_PC_TEXT

-- ---- 101-102 the console and the Trainer House ----------------------------

-- GameboyCheck: GBCHECK_GB 0 / GBCHECK_SGB 1 / GBCHECK_CGB 2.  Gold is a Game
-- Boy Color game and the port renders its GBC palettes, so the honest answer
-- follows the COLOR option: the deliberate step down to a grey Game Boy is a
-- real answer to this question, and the Goldenrod console kid's line changes
-- with it, which is the only place it is asked.
H.GameboyCheck = function(vm)
  local GbcPalette = require("src.render.GbcPalette")
  if GbcPalette.mode == "gbc" then
    answer(vm, GBCHECK_CGB)
  elseif GbcPalette.mode == "classic" then
    answer(vm, GBCHECK_GB)
  else
    answer(vm, GBCHECK_SGB)
  end
end

-- TrainerHouse: sMysteryGiftTrainerHouseFlag, the byte a Mystery Gift trade
-- leaves behind so the Viridian Trainer House has somebody to fight.  Mystery
-- Gift is out of scope, so the flag is permanently 0 and the house holds its
-- default opponent -- which is what an unlinked cartridge does.
--
-- The byte has three readers (this, ReadTrainerParty and GetTrainerName) and
-- src/world/gen2/TrainerHouse.lua is the one that owns it, so the answer here
-- cannot drift from the party the battle then loads.  Required inside the
-- handler the way H.GameboyCheck requires GbcPalette: the script layer does
-- not otherwise depend on the world layer.
H.TrainerHouse = function(vm)
  local TrainerHouse = require("src.world.gen2.TrainerHouse")
  answer(vm, TrainerHouse.hasCustomTrainer(save(vm)) and TRUE or FALSE)
end

-- ---- 104 the roamers ------------------------------------------------------
--
-- InitRoamMons (engine/overworld/wildmons.asm): the three legendary beasts are
-- written into the wRoamMon structs on their starting routes.  RoamMon_1 is
-- Raikou on ROUTE 42, 2 Entei on ROUTE 37, 3 Suicune on ROUTE 38, all at level
-- 40, and each HP byte is zeroed under the asm's own comment "generate new
-- stats" -- a roamer has no rolled stats until it is first met.
--
-- The roster and the walk both live in src/core/gen2/Roamers.lua, which is the
-- ONE writer of save.roamers: this file used to carry a second copy of the
-- three rows, and two transcriptions of one table is how a renumbered slot
-- sends Suicune's damage to Raikou's byte.  Specials.ROAMERS is kept as an
-- alias of that table so a reader landing here still sees what the routine
-- writes.
--
-- `force` because the asm stores unconditionally.  Roamers.init's default is
-- the port's own re-entry guard, which is the right default for a caller that
-- is not the cart's own command; the command itself has to be the cart.
Specials.ROAMERS = Roamers.SPECIES

H.InitRoamMons = function(vm)
  local record = save(vm)
  if not record then return end
  Roamers.init(record, { force = true })
end

-- ---- the #DEX-completion diploma -------------------------------------------
--
-- _Diploma (engine/events/diploma.asm): PlaceDiplomaOnScreen then
-- WaitPressAorB_BlinkCursor.  Called by Celadon Mansion 3F's
-- GameFreakGameDesignerScript once VAR_DEXCAUGHT hits 251 (see the OAK_RATINGS
-- comment above); the caller wraps the farcall in FadeToMenu/ExitAllMenus
-- (engine/events/specials.asm Diploma), and _Diploma itself never touches
-- wScriptVar, so this leaves vm.scriptVar untouched the same way H.MoveDeletion
-- and H.NameRater do.  The screen is src/ui/gen2/Diploma.lua; World:showDiploma
-- is the push, kept behind World the way every other screen-opening special is.
H.Diploma = function(vm)
  local h = hooks(vm)
  if not h.showDiploma then return end
  Specials.block(vm, function(done)
    h.showDiploma(function() done(true) end)
  end)
end

-- ---- Mom's savings ----------------------------------------------------------
--
-- BankOfMom (engine/events/mom.asm), reached from PlayersHouse1F's own
-- `MomScript` (`special BankOfMom`, run inside a caller-opened textbox the
-- same way H.MoveDeletion and H.NameRater's callers open theirs).  The asm is
-- a nine-state jumptable; this ports its shape rather than its byte, with two
-- of its own behaviours kept on purpose:
--
--   * StoreMoney/TakeMoney's insufficient-funds arms `ret` WITHOUT advancing
--     wJumptableIndex, so `.loop` re-enters the SAME state and asks again --
--     the `while true do` loops below stand in for that.
--   * GiveMoney does not refuse an over-the-cap deposit, it CLAMPS to
--     MAX_MONEY and reports carry; the caller sees that as "no room" but the
--     clamp already landed, so a deposit that overflows Mom's account still
--     tops her out at 999999 without touching the wallet (`giveMoneyClamped`
--     below is exactly that GiveMoney, not a rejecting one).
--
-- Not ported: the `.nope` arm of IsThisAboutYourMoney calls DSTChecks, which
-- nudges wStartHour/wStartDay to flip Daylight Saving on or off and reprints
-- the clock.  This port has no wStartHour to nudge -- World:hour reads the
-- host clock directly rather than keeping an offset from it (SetDayOfWeek's
-- own comment above says the same for the day wheel) -- so there is nothing
-- for a yes/no here to change, and the conversation falls straight through to
-- MomJustDoWhatYouCanText the way it does once DSTChecks itself returns.
--
-- data/text/common_1.asm, transcribed the way MOVE_DELETER_TEXT above
-- transcribes its own bank, and with the cart's own page structure: `para` is
-- a page break (`\f` -- the box clears and WAITS for A), `cont` is the
-- scrolled third line (`\v`, which also waits).  Folding paras into plain
-- `\n`s let the whole of MomLeavingText1 type itself out as one page with no
-- button waits at all, straight through to the savings prompt.
local MOM_TEXT = {
  leaving1 = Strings.source(
    "Wow, that's a cute\n#MON.\fWhere did you get\nit?\f…\f"
    .. "So, you're leaving\non an adventure…\fOK!\nI'll help too.\f"
    .. "But what can I do\nfor you?\fI know! I'll save\nmoney for you.\f"
    .. "On a long journey,\nmoney's important.\fDo you want me to\n"
    .. "save your money?"),
  leaving2 = Strings.source("OK, I'll take care\nof your money.\f…"),
  leaving3 = Strings.source(
    "Be careful.\f#MON are your\nfriends. You need\vto work as a team.\f"
    .. "Now, go on!"),
  isThisAboutMoney = Strings.source(
    "Hi! Welcome home!\nYou're trying very\vhard, I see.\f"
    .. "I've kept your\nroom tidy.\fOr is this about\nyour money?"),
  whatDoYouWantToDo = Strings.source("What do you want\nto do?"),
  storeMoney = Strings.source("How much do you\nwant to save?"),
  takeMoney = Strings.source("How much do you\nwant to take?"),
  saveMoney = Strings.source("Do you want to\nsave some money?"),
  haventSavedThatMuch = Strings.source("You haven't saved\nthat much."),
  notEnoughRoomInWallet = Strings.source("You can't take\nthat much."),
  insufficientFundsInWallet = Strings.source("You don't have\nthat much."),
  notEnoughRoomInBank = Strings.source("You can't save\nthat much."),
  startSavingMoney = Strings.source(
    "OK, I'll save your\nmoney. Trust me!\f{PLAYER}, stick\nwith it!"),
  storedMoney = Strings.source("Your money's safe\nhere! Get going!"),
  takenMoney = Strings.source("{PLAYER}, don't\ngive up!"),
  justDoWhatYouCan = Strings.source("Just do what\nyou can."),
}

-- constants/script_constants.asm.
local YOUR_MONEY, MOMS_MONEY = 0, 1
local MOM_MAX_MONEY = 999999

-- BankOfMom_MenuHeader: `menu_coords 0, 0, 10, 10`, STATICMENU_CURSOR, four
-- items, cursor starting on GET.  Answers through the same "menu" yield
-- Script_verticalmenu uses, so Gen2ScriptMenu draws it with no new screen.
local BANK_MENU_HEADER = {
  left = 0, top = 0, right = 10, bottom = 10,
  dataFlags = 0x80, -- STATICMENU_CURSOR
  items = { "GET", "SAVE", "CHANGE", "CANCEL" },
  cursor = 1,
}

local function bankMoney(vm, account)
  local h = hooks(vm)
  return (h.money and h.money(account)) or 0
end

local function setBankMoney(vm, account, value)
  local h = hooks(vm)
  if h.setMoney then
    h.setMoney(account, math.max(0, math.min(value, MOM_MAX_MONEY)))
  end
end

-- GiveMoney (engine/events/money.asm): adds, clamps at MAX_MONEY, and reports
-- (via the second return) whether the clamp fired -- the caller's cue to show
-- the "no room" line even though the account already sits at the cap.
local function giveMoneyClamped(vm, account, amount)
  local have = bankMoney(vm, account)
  local total = have + amount
  if total > MOM_MAX_MONEY then
    setBankMoney(vm, account, MOM_MAX_MONEY)
    return MOM_MAX_MONEY, true
  end
  setBankMoney(vm, account, total)
  return total, false
end

-- TakeMoney: subtracts, floors at 0 rather than borrowing.
local function takeMoneyFloored(vm, account, amount)
  local have = bankMoney(vm, account)
  if amount > have then
    setBankMoney(vm, account, 0)
    return 0
  end
  setBankMoney(vm, account, have - amount)
  return have - amount
end

-- Mom_SetUpWithdrawMenu / Mom_SetUpDepositMenu's six-digit keypad
-- (src/ui/gen2/BankOfMom.lua).  `kind` is "deposit" or "withdraw", only for
-- the screen's own label; the amount it hands back is unvalidated, exactly
-- the way wStringBuffer2 is before StoreMoney/TakeMoney check it against the
-- other account.
local function bankOfMomAmount(vm, kind)
  local h = hooks(vm)
  if not h.bankOfMomAmount then return nil end
  local saved, held = bankMoney(vm, MOMS_MONEY), bankMoney(vm, YOUR_MONEY)
  return Specials.block(vm, function(done)
    h.bankOfMomAmount(kind, saved, held, done)
  end)
end

local function transactionSfx(vm)
  coroutine.yield({ kind = "waitsfx" })
  local h = hooks(vm)
  if h.playSfxNamed then h.playSfxNamed("Sfx_Transaction", 22) end
  coroutine.yield({ kind = "waitsfx" })
end

H.BankOfMom = function(vm)
  local record = save(vm)
  if not record then return end
  record.mom = record.mom or {}
  local mom = record.mom

  local function justDoWhatYouCan()
    vm:showRaw(Strings(MOM_TEXT.justDoWhatYouCan))
  end

  -- .CheckIfBankInitialized / .InitializeBank: the very first visit, before
  -- MOM_ACTIVE_F is ever set.  Skips IsThisAboutYourMoney entirely.
  if not mom.active then
    -- engine/events/mom.asm:50-53, PrintText then `call YesNoBox`.
    showRawHeld(vm, Strings(MOM_TEXT.leaving1))
    local wantsToSave = coroutine.yield({ kind = "yesorno" })
    mom.active = true
    if wantsToSave then
      mom.savingMoney = true
      vm:showRaw(Strings(MOM_TEXT.leaving2))
    end
    vm:showRaw(Strings(MOM_TEXT.leaving3))
    return
  end

  -- .IsThisAboutYourMoney
  -- engine/events/mom.asm:71-74, the same PrintText / YesNoBox pair.
  showRawHeld(vm, Strings(MOM_TEXT.isThisAboutMoney))
  local aboutMoney = coroutine.yield({ kind = "yesorno" })
  if not aboutMoney then
    -- .nope: DSTChecks does not apply here; see the header note above.
    justDoWhatYouCan()
    return
  end

  -- .AccessBankOfMom
  vm:showRaw(Strings(MOM_TEXT.whatDoYouWantToDo))
  local choice = coroutine.yield({ kind = "menu", style = "vertical",
    header = BANK_MENU_HEADER })

  if choice == 1 then
    -- .withdraw -> .TakeMoney
    while true do
      vm:showRaw(Strings(MOM_TEXT.takeMoney))
      local amount = bankOfMomAmount(vm, "withdraw")
      if not amount or amount == 0 then justDoWhatYouCan() return end
      if amount > bankMoney(vm, MOMS_MONEY) then
        vm:showRaw(Strings(MOM_TEXT.haventSavedThatMuch))
      else
        local _, overflowed = giveMoneyClamped(vm, YOUR_MONEY, amount)
        if overflowed then
          vm:showRaw(Strings(MOM_TEXT.notEnoughRoomInWallet))
        else
          takeMoneyFloored(vm, MOMS_MONEY, amount)
          transactionSfx(vm)
          vm:showRaw(Strings(MOM_TEXT.takenMoney))
          return
        end
      end
    end
  elseif choice == 2 then
    -- .deposit -> .StoreMoney
    while true do
      vm:showRaw(Strings(MOM_TEXT.storeMoney))
      local amount = bankOfMomAmount(vm, "deposit")
      if not amount or amount == 0 then justDoWhatYouCan() return end
      if amount > bankMoney(vm, YOUR_MONEY) then
        vm:showRaw(Strings(MOM_TEXT.insufficientFundsInWallet))
      else
        local _, overflowed = giveMoneyClamped(vm, MOMS_MONEY, amount)
        if overflowed then
          vm:showRaw(Strings(MOM_TEXT.notEnoughRoomInBank))
        else
          takeMoneyFloored(vm, YOUR_MONEY, amount)
          transactionSfx(vm)
          vm:showRaw(Strings(MOM_TEXT.storedMoney))
          return
        end
      end
    end
  elseif choice == 3 then
    -- .stopsaving -> .StopOrStartSavingMoney
    -- engine/events/mom.asm:255-258, the same PrintText / YesNoBox pair.
    showRawHeld(vm, Strings(MOM_TEXT.saveMoney))
    local wantsToSave = coroutine.yield({ kind = "yesorno" })
    if wantsToSave then
      mom.savingMoney = true
      vm:showRaw(Strings(MOM_TEXT.startSavingMoney))
    else
      mom.savingMoney = false
      justDoWhatYouCan()
    end
  else
    -- .cancel: CANCEL itself, or B.
    justDoWhatYouCan()
  end
end

-- ---- the Magnet Train ------------------------------------------------------
--
-- MagnetTrain (engine/events/magnet_train.asm), the Goldenrod <-> Saffron ride
-- both station officers run once EVENT_RESTORED_POWER_TO_KANTO is set and the
-- PASS is in the bag.  The routine READS wScriptVar and never writes it:
--
--     ld a, [wScriptVar]
--     and a
--     jr nz, .ToGoldenrod
--
-- so the `setval FALSE` in front of the Goldenrod call and the `setval TRUE` in
-- front of the Saffron one are what pick the direction, and vm.scriptVar has to
-- come back out of here exactly as it went in -- the `warpcheck` that follows
-- reads nothing, but a handler that clobbered it would still be lying about
-- what the routine does.
--
-- The ride itself is src/core/gen2/MagnetTrain.lua and its screen is
-- src/ui/gen2/MagnetTrainRide.lua; World:magnetTrain is the push.  With no hook
-- the special is a no-op that leaves the script to warp on its own, which is
-- what a headless run wants.
H.MagnetTrain = function(vm)
  local h = hooks(vm)
  if not h.magnetTrain then return end
  local toGoldenrod = (vm.scriptVar or 0) ~= 0
  Specials.block(vm, function(done)
    h.magnetTrain(toGoldenrod, function() done(true) end)
  end)
end

-- ---- the Cianwood photo studio ---------------------------------------------
--
-- PhotoStudio (engine/events/print_photo.asm).  CianwoodPhotoStudio's own
-- script (CianwoodPhotoStudioFishingGuruScript) is `faceplayer / opentext /
-- writetext .Question / yesorno / iffalse .Refused / writetext .Yes /
-- waitbutton / special PhotoStudio / waitbutton / closetext` -- the yes/no
-- gate and the surrounding textbox both belong to the map script (generic
-- VM opcodes; nothing to hand-port there), and PhotoStudio itself only ever
-- runs after the player has said yes.  Like H.MoveDeletion and H.NameRater,
-- it never writes wScriptVar (no `ld [wScriptVar], a` anywhere in the
-- routine), so this leaves vm.scriptVar exactly as `special` found it.
--
-- data/text/common_1.asm _WhichMonPhotoText/_HoldStillText/
-- _PrestoAllDoneText/_NoPhotoText/_EggPhotoText, transcribed the way
-- MOVE_DELETER_TEXT above transcribes its own bank.
--
-- farcall PrintPartymon (engine/printer/printer.asm) is the actual camera:
-- it draws the portrait card (src/ui/gen2/PhotoStudio.lua transcribes that
-- layout, PrintPartyMonPage1) and then SendScreenToPrinter walks it out the
-- serial port to a physical Game Boy Printer.  There is no peripheral for it
-- to reach here -- the same reason H.UnownPrinter's A press goes nowhere and
-- PrintDiploma stays stubbed below -- so `ldh a, [hPrinter] / and a / jr nz,
-- .cancel` is
-- hardwired to the nz arm below: the portrait shows, then the print always
-- comes back as though the printer errored, which is the honest answer for
-- a cartridge with nothing plugged into its link port.
local PHOTO_STUDIO_TEXT = {
  whichMon = Strings.source("Which #MON\nshould I photo-\ngraph?"),
  holdStill = Strings.source("All righty. Hold\nstill for a bit."),
  noPhoto = Strings.source("Oh, no picture?\nCome again, OK?"),
  eggPhoto = Strings.source("An EGG? My talent\nis worth more…"),
}

local function showPhotoStudio(vm, mon)
  local h = hooks(vm)
  if not h.showPhotoStudio then return end
  Specials.block(vm, function(done)
    h.showPhotoStudio(mon, function() done(true) end)
  end)
end

H.PhotoStudio = function(vm)
  vm:showRaw(Strings(PHOTO_STUDIO_TEXT.whichMon))
  local _, mon = selectMon(vm, "choose")
  if not mon then
    vm:showRaw(Strings(PHOTO_STUDIO_TEXT.noPhoto))
    return
  end

  -- `ld a, [wCurPartySpecies] / cp EGG`: an egg slot is marked with `isEgg`
  -- in this port (src/core/gen2/Breeding.lua), same test H.MoveDeletion and
  -- H.NameRater make.
  if mon.isEgg then
    vm:showRaw(Strings(PHOTO_STUDIO_TEXT.eggPhoto))
    return
  end

  vm:showRaw(Strings(PHOTO_STUDIO_TEXT.holdStill))
  showPhotoStudio(vm, mon)
  -- hPrinter reads as an error unconditionally; see the header comment.
  vm:showRaw(Strings(PHOTO_STUDIO_TEXT.noPhoto))
end

-- ---- 111 the dummy --------------------------------------------------------
-- UnusedDummySpecial is a bare `ret`.  Listed so the name resolves to a
-- handler rather than to the unimplemented ledger.
H.UnusedDummySpecial = function() end

--------------------------------------------------------------------------
-- The deliberate stubs
--------------------------------------------------------------------------
--
-- Each carries the reason it is out of scope and the value it leaves in
-- wScriptVar.  A stub is NOT the same thing as a missing handler: a special
-- that falls through leaves a STALE wScriptVar behind, and the `iffalse` two
-- commands later then takes whatever branch the last special happened to
-- leave -- which is the exact failure this whole module exists to stop.
--
-- `value = nil` means the routine genuinely does not write wScriptVar.
local STUB_ROWS = {
  -- Everything link cable.  Two Game Boys and a cable; the port has link play
  -- for Gen 1 only (src/link/), and none of the Gen 2 cable-club protocol is
  -- ported.  The values are the "no partner turned up" arm of each routine,
  -- which is what an unplugged cartridge sees.
  { "SetBitsForLinkTradeRequest", nil, "link cable: no Gen 2 cable club" },
  { "WaitForLinkedFriend", 0, "link cable: nobody ever connects" },
  { "CheckLinkTimeout_Receptionist", 1, "link cable: always times out" },
  { "TryQuickSave", 0, "link cable: the cable club's own save is not ported" },
  { "CheckBothSelectedSameRoom", 0, "link cable: no second player" },
  { "FailedLinkToPast", 1, "link cable: the Time Capsule is not ported" },
  { "CloseLink", nil, "link cable: nothing to close" },
  { "WaitForOtherPlayerToExit", nil, "link cable: nobody to wait for" },
  { "SetBitsForBattleRequest", nil, "link cable: no Gen 2 cable club" },
  { "SetBitsForTimeCapsuleRequest", nil, "link cable: no Time Capsule" },
  -- maps/PokeCenter2F.asm:200-203: 2 is .MonMoveTooNew; 0 falls through to
  -- WaitForLinkedFriend and lands on .FriendNotReady
  { "CheckTimeCapsuleCompatibility", 0, "link cable: no Gen 1 partner" },
  { "EnterTimeCapsule", nil, "link cable: no Time Capsule" },
  { "TradeCenter", nil, "link cable: no trade room" },
  { "Colosseum", nil, "link cable: no battle room" },
  { "TimeCapsule", nil, "link cable: no Time Capsule" },
  { "CableClubCheckWhichChris", 0, "link cable: only one player exists" },
  { "DisplayLinkRecord", nil, "link cable: no link record is kept" },
  -- Mystery Gift.  Infrared between two carts; nothing in the port has an IR
  -- port, and sMysteryGiftItem is therefore permanently empty.
  { "CheckMysteryGift", 0, "Mystery Gift: no infrared, so no gift is waiting" },
  { "GetMysteryGiftItem", 0, "Mystery Gift: nothing to hand over" },
  { "UnlockMysteryGift", nil, "Mystery Gift: nothing to unlock" },
  -- The Game Boy Printer.  A second peripheral again, and two of the three
  -- specials that want it are not in this table: PhotoStudio ports the
  -- conversation and the portrait screen (H.PhotoStudio above) and
  -- UnownPrinter ports the stamp viewer (H.UnownPrinter above), with only the
  -- print itself stubbed inside each.  PrintDiploma is the one that is
  -- nothing BUT the print -- the diploma's own page is `special Diploma`, a
  -- separate row -- so it is all that is left here.
  { "PrintDiploma", nil, "printer: no Game Boy Printer" },
  -- Screens the port has not built.  Each names what it needs; the value is
  -- the arm a cancel takes, so the script backs out rather than proceeding
  -- through a transaction that never happened.
  { "UnusedMemoryGame", nil, "unused in Gold; needs the memory game screen" },
}

Specials.HANDLERS = H
Specials.STUBS = {}
Specials.STUB_REASONS = {}

for _, row in ipairs(STUB_ROWS) do
  local name, value, reason = row[1], row[2], row[3]
  Specials.STUB_REASONS[name] = reason
  Specials.STUBS[name] = function(vm)
    if value ~= nil then vm.scriptVar = value end
  end
end

-- The dispatch table Vm.SPECIALS is.  Built rather than written out so the two
-- sets cannot drift, and so a name that ends up in both is a hard error here
-- rather than a silent shadow at runtime.
Specials.ALL = {}
for name, fn in pairs(Specials.HANDLERS) do
  Specials.ALL[name] = fn
end
for name, fn in pairs(Specials.STUBS) do
  if Specials.ALL[name] then
    error("gen2 special '" .. name .. "' is both implemented and stubbed", 0)
  end
  Specials.ALL[name] = fn
end

return Specials
