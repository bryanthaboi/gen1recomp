-- Pokerus: the infection roll after a won battle, the spread through the party,
-- the daily countdown that leaves the immune marker behind, and the doubled
-- stat exp an infected (or cured) mon earns.
--   GOLD_CACHE="$HOME/Library/Application Support/LOVE/gold-dev/gold" \
--     luajit tests/gen2_pokerus_test.lua
--
-- Every roll is pinned: Pokerus.give takes the same "one function, one byte"
-- roller BugContest does, so the sequences below are the exact `call Random`
-- results engine/events/pokerus/pokerus.asm would have read, in order.  The
-- numbers in the comments are traceable to that file so a failure names the
-- branch it disagrees with.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 pokerus")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")
local Pokerus = require("src.core.gen2.Pokerus")
local Gen2Save = require("src.core.gen2.Save")

-- ---- fixtures -------------------------------------------------------------

local function base(hp, attack, defense, speed, spa, spd)
  return { hp = hp, attack = attack, defense = defense, speed = speed,
    specialAttack = spa, specialDefense = spd }
end

-- GROWTH_MEDIUM_FAST is plain n^3 (data/growth_rates.asm).
local GROWTH = {
  MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0, linear = 0,
    constant = 0 },
}

local POKEMON = {
  growthRates = GROWTH,
  CYNDAQUIL = {
    name = "CYNDAQUIL", index = 155, growthRate = "MEDIUM_FAST",
    genderRatio = 0x1f, types = { "FIRE" }, baseExp = 65,
    baseStats = base(39, 52, 43, 65, 60, 50),
    levelMoves = { { level = 1, move = "TACKLE" } },
  },
  -- data/pokemon/base_stats/pidgey.asm: 40/45/40/56/35/35, base exp 55.
  PIDGEY = {
    name = "PIDGEY", index = 16, growthRate = "MEDIUM_FAST",
    genderRatio = 0x7f, types = { "NORMAL", "FLYING" }, baseExp = 55,
    baseStats = base(40, 45, 40, 56, 35, 35),
    levelMoves = { { level = 1, move = "TACKLE" } },
  },
}

local MOVES = {
  TACKLE = { name = "TACKLE", type = "NORMAL", power = 35, accuracy = 95,
    pp = 35, category = "physical" },
}

local DATA = { pokemon = POKEMON, moves = MOVES,
  text = require("tests.fixture_data.gen2_rom_text_s7_a").text() }

-- A roller that hands back a fixed sequence, so every branch below is chosen
-- rather than sampled.  Running off the end is a test bug, not a pass.
local function rolls(...)
  local queue = { ... }
  local at = 0
  return function()
    at = at + 1
    assert(queue[at], "pokerus roller ran past its pinned sequence")
    return queue[at]
  end
end

local function mon(pokerus)
  local m = Mon.new(DATA, "PIDGEY", 5, { dvs = { attack = 0, defense = 0,
    speed = 0, special = 0 } })
  m.pokerus = pokerus or 0
  return m
end

-- ---- reading the byte -----------------------------------------------------

eq(Pokerus.strain(mon(0x34)), 3, "the high nybble is the strain")
eq(Pokerus.days(mon(0x34)), 4, "the low nybble is the days left")
check(Pokerus.isInfected(mon(0x34)), "a counter above zero is an infection")
check(not Pokerus.isImmune(mon(0x34)), "and is not yet the immune marker")
check(not Pokerus.isInfected(mon(0x30)), "a spent counter is not an infection")
check(Pokerus.isImmune(mon(0x30)), "but the strain left behind is immunity")
check(not Pokerus.isInfected(mon(0)), "an untouched byte is neither")
check(not Pokerus.isImmune(mon(0)), "an untouched byte is not immune")

-- GiveExperiencePoints tests the WHOLE byte, so a cured mon still doubles.
check(Pokerus.doublesStatExp(mon(0x34)), "an infected mon doubles stat exp")
check(Pokerus.doublesStatExp(mon(0x30)), "and so does a cured one")
check(not Pokerus.doublesStatExp(mon(0)), "a clean mon does not")

-- _CheckPokerus: the low nybble only.
check(Pokerus.inParty({ mon(0), mon(0x34) }), "one infected slot is enough")
check(not Pokerus.inParty({ mon(0), mon(0x30) }),
  "a party of cured mons answers no")
check(not Pokerus.inParty({}), "and an empty party answers no")

-- A garbage byte is folded rather than trusted, so no reader ever sees a
-- strain or a day count no cartridge could produce.
eq(Pokerus.byteOf({ pokerus = -4 }), 0, "a negative byte reads as zero")
eq(Pokerus.byteOf({ pokerus = 300 }), 44, "and an oversized one wraps")

-- ---- the daily tick -------------------------------------------------------

do
  local party = { mon(0x34), mon(0x31), mon(0x30), mon(0) }
  local cured = Pokerus.applyTick(party, 2)
  eq(party[1].pokerus, 0x32, "two days off a four-day infection leaves two")
  eq(party[2].pokerus, 0x30, "a counter that runs out keeps its strain")
  eq(party[3].pokerus, 0x30, "an already-cured mon is skipped, not re-cured")
  eq(party[4].pokerus, 0, "a clean mon is left alone")
  eq(#cured, 1, "one mon cured on this tick")
  eq(cured[1], 2, "and it is the slot whose counter ran out")
end

do
  -- The clamp is `jr nc, .ok / xor a`: a tick bigger than the counter cannot
  -- borrow into the strain nybble.
  local party = { mon(0x81) }
  Pokerus.applyTick(party, 200)
  eq(party[1].pokerus, 0x80, "a huge tick clamps at zero without touching the strain")
end

do
  local save = { party = { mon(0x34) } }
  check(not Pokerus.checkTick(save, { day = 5 }),
    "the first poll only stamps the day")
  eq(save.pokerusStartDay, 5, "and the stamp is today")
  eq(save.party[1].pokerus, 0x34, "so nothing ticked")
  check(not Pokerus.checkTick(save, { day = 5 }),
    "a second poll on the same day still ticks nothing")
  check(Pokerus.checkTick(save, { day = 7 }), "two days later it ticks")
  eq(save.party[1].pokerus, 0x32, "by the days SINCE THE LAST POLL")
  eq(save.pokerusStartDay, 7, "and the stamp advances to today")
  check(not Pokerus.checkTick(save, { day = 7 }),
    "so the same two days are never counted twice")
end

-- ---- catching it de novo --------------------------------------------------

do
  local party = { mon(0) }
  eq(Pokerus.give(party, { random = rolls(0, 0, 0, 0x34) }), nil,
    "a save that has not reached Goldenrod cannot catch it")
  eq(party[1].pokerus, 0, "and nothing was written")
end

do
  -- hRandomAdd zero, hRandomSub under 3, slot 0, then the strain/duration byte:
  -- $34 has a non-zero high nybble, so strain = ($34 & 7) + 1 = 5 and the
  -- counter is (5 & 3) + 1 = 2.
  local party = { mon(0) }
  eq(Pokerus.give(party, { reachedGoldenrod = true,
    random = rolls(0, 0, 0, 0x34) }), 1, "the rolled slot is the one infected")
  eq(party[1].pokerus, 0x52, "strain 5, two days")
end

do
  -- 3 in 65536: either byte out of range and the routine returns.
  local party = { mon(0) }
  eq(Pokerus.give(party, { reachedGoldenrod = true, random = rolls(1) }), nil,
    "a non-zero hRandomAdd ends it")
  eq(Pokerus.give(party, { reachedGoldenrod = true, random = rolls(0, 3) }), nil,
    "and so does hRandomSub at 3")
  eq(party[1].pokerus, 0, "neither wrote anything")
end

do
  -- `.randomMonSelectLoop` masks the roll to 0..7 and rerolls until it lands
  -- inside the party.
  local party = { mon(0), mon(0) }
  eq(Pokerus.give(party, { reachedGoldenrod = true,
    random = rolls(0, 0, 5, 1, 0x34) }), 2, "a slot past the party is rerolled")
  eq(party[1].pokerus, 0, "the first slot is untouched")
  eq(party[2].pokerus, 0x52, "the second caught it")
end

do
  -- `.randomPokerusLoop` rerolls a zero byte, because zero would mean no
  -- strain and no days.
  local party = { mon(0) }
  Pokerus.give(party, { reachedGoldenrod = true,
    random = rolls(0, 0, 0, 0, 0x11) })
  eq(party[1].pokerus, 0x23, "a zero sample is rerolled: strain 2, three days")
end

do
  -- The strain-zero quirk: a sample whose HIGH nybble is zero takes the
  -- `jr z, .load_pkrs` arm with a = 0, so the mon gets $01 and cures back to
  -- $00 -- which leaves it able to catch Pokerus again.
  local party = { mon(0) }
  Pokerus.give(party, { reachedGoldenrod = true,
    random = rolls(0, 0, 0, 0x08) })
  eq(party[1].pokerus, 0x01, "strain zero, one day")
  Pokerus.applyTick(party, 1)
  eq(party[1].pokerus, 0, "and it cures to nothing at all")
end

do
  -- `and $f0 / ret nz`: the immune marker blocks a second infection.
  local party = { mon(0x30) }
  eq(Pokerus.give(party, { reachedGoldenrod = true,
    random = rolls(0, 0, 0, 0x34) }), nil, "a cured mon cannot catch it again")
  eq(party[1].pokerus, 0x30, "its byte is unchanged")
end

-- ---- spreading it ---------------------------------------------------------

do
  -- An active infection anywhere in the party turns the whole routine into a
  -- spread roll, so a second strain can never be contracted.
  local party = { mon(0x34), mon(0), mon(0) }
  eq(Pokerus.give(party, { reachedGoldenrod = true, random = rolls(85) }), nil,
    "33 percent is 85 out of 256, and 85 itself misses")
  eq(party[2].pokerus, 0, "nothing spread")
end

do
  -- 200 is at or over 128, so the walk goes FORWARDS from the carrier.
  local party = { mon(0x34), mon(0), mon(0) }
  eq(Pokerus.give(party, { random = rolls(0, 200) }), 2,
    "the next slot catches it")
  eq(party[2].pokerus, 0x34, "same strain, a counter of (3 & 3) + 1 days")
  eq(party[3].pokerus, 0, "and the walk stopped there")
end

do
  -- The last slot has nothing after it, so `cp 2 / jr c` sends it backwards
  -- without spending a second Random.
  local party = { mon(0), mon(0), mon(0x34) }
  eq(Pokerus.give(party, { random = rolls(0) }), 2,
    "a carrier in the last slot walks backwards")
  eq(party[2].pokerus, 0x34, "infecting the slot before it")
end

do
  local party = { mon(0x34) }
  eq(Pokerus.give(party, { random = rolls(0) }), nil,
    "a party of one has nowhere to spread")
end

do
  -- `and $3 / ret z` on a neighbour's byte: meant as "stop at a cured mon",
  -- and $30 is exactly that.
  local party = { mon(0x34), mon(0x30), mon(0) }
  eq(Pokerus.give(party, { random = rolls(0, 200) }), nil,
    "the walk stops dead at a cured mon")
  eq(party[3].pokerus, 0, "so the slot past it stays clean")
end

do
  -- Register c is reloaded from each neighbour walked over, so the strain that
  -- lands two slots away is the LAST one seen, not the carrier's.
  local party = { mon(0x34), mon(0x51), mon(0) }
  eq(Pokerus.give(party, { random = rolls(0, 200) }), 3,
    "an infected neighbour is walked past")
  eq(party[3].pokerus, 0x52, "carrying ITS strain, not the first carrier's")
end

-- ---- stat exp -------------------------------------------------------------

do
  local m = Mon.new(DATA, "CYNDAQUIL", 10)
  check(m.statExp ~= nil, "a fresh mon carries the five stat exp words")
  eq(m.statExp.special, 0, "all starting at zero")
  eq(m.pokerus, 0, "and a clean Pokerus byte")

  -- PIDGEY's base stats, one participant, no Pokerus.  The loop runs
  -- NUM_EXP_STATS = 5 times over a six-entry base stat block, so the Special
  -- word takes Special ATTACK and Special Defense is never read.
  Mon.gainStatExp(m, POKEMON.PIDGEY, 1, false)
  eq(m.statExp.hp, 40, "HP stat exp is the loser's base HP")
  eq(m.statExp.attack, 45, "Attack likewise")
  eq(m.statExp.defense, 40, "Defense likewise")
  eq(m.statExp.speed, 56, "Speed likewise")
  eq(m.statExp.special, 35, "and Special takes the loser's Special ATTACK")

  Mon.gainStatExp(m, POKEMON.PIDGEY, 1, true)
  eq(m.statExp.hp, 40 + 80, "Pokerus adds the same value a second time")
  eq(m.statExp.special, 35 + 70, "for every word, Special included")

  -- .EvenlyDivideExpAmongParticipants divides the base stats in place, so the
  -- share is the same one the exp points are divided by.
  local shared = Mon.new(DATA, "CYNDAQUIL", 10)
  Mon.gainStatExp(shared, POKEMON.PIDGEY, 2, false)
  eq(shared.statExp.attack, 22, "two participants split the base stat, floored")
  eq(shared.statExp.special, 17, "and the halving floors each word separately")

  -- .stat_exp_maxed_out
  local full = Mon.new(DATA, "CYNDAQUIL", 10)
  full.statExp.hp = 65530
  Mon.gainStatExp(full, POKEMON.PIDGEY, 1, true)
  eq(full.statExp.hp, 65535, "a word that would overflow stops at $ffff")
end

do
  -- One Special stat exp word feeds BOTH special stats, the way one Special DV
  -- feeds both.
  local dvs = { attack = 15, defense = 15, speed = 15, special = 15 }
  local plain = Mon.stats(POKEMON.CYNDAQUIL.baseStats, dvs, 50)
  local trained = Mon.stats(POKEMON.CYNDAQUIL.baseStats, dvs, 50,
    { special = 65535 })
  check(trained.specialAttack > plain.specialAttack,
    "Special stat exp raises Special Attack")
  eq(trained.specialDefense - plain.specialDefense,
    trained.specialAttack - plain.specialAttack,
    "and raises Special Defense by exactly as much")
end

-- ---- the battle call site -------------------------------------------------

do
  -- Battle:awardExperience is where GiveExperiencePoints lives, so the doubling
  -- is asserted through it rather than through the helper alone.
  local clean = Mon.new(DATA, "CYNDAQUIL", 30)
  local infected = Mon.new(DATA, "CYNDAQUIL", 30)
  infected.pokerus = 0x34
  local loser = Mon.new(DATA, "PIDGEY", 5)

  local function award(party)
    local battle = setmetatable({
      data = DATA, party = party, participants = { [1] = true },
      events = {}, trainer = nil,
    }, Battle)
    battle:awardExperience(loser)
    return battle
  end

  award({ clean })
  award({ infected })
  eq(clean.statExp.attack, 45, "a clean participant gains the base stat once")
  eq(infected.statExp.attack, 90, "an infected one gains it twice")
  eq(clean.experience > 0, true, "and both still gained experience points")
  eq(infected.experience, clean.experience,
    "Pokerus doubles stat exp only, never exp points")
end

-- ---- the save side --------------------------------------------------------

do
  local save = Gen2Save.normalize({
    party = { { species = "PIDGEY", pokerus = 300 },
              { species = "PIDGEY", pokerus = -1 },
              { species = "PIDGEY" } },
    boxes = { { { species = "PIDGEY", pokerus = 3.7 } } },
  })
  eq(save.party[1].pokerus, 44, "an oversized byte is folded on load")
  eq(save.party[2].pokerus, 0, "a negative one becomes zero")
  eq(save.party[3].pokerus, nil, "a slot without one is left alone")
  eq(save.boxes[1][1].pokerus, 3, "and box mons are normalized too")
end

-- ---- call sites -----------------------------------------------------------

-- The two hooks a headless test cannot construct: World needs a map, a stack
-- and a VM, BattleState needs love.  A call site that is not spelled out in the
-- file is not there at all, which is the failure this item is about.
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
  check(world:find("Pokerus.checkTick(save)", 1, true) ~= nil,
    "CheckTimeEvents' .do_daily arm runs the Pokerus tick")

  local battle = sourceOf("src/ui/gen2/BattleState.lua")
  check(battle ~= nil, "BattleState's source is readable")
  for _, wanted in ipairs({
      "function BattleState:givePokerus",
      "Pokerus.giveAfterBattle(self.save, party)",
      "self:givePokerus()",
    }) do
    check(battle:find(wanted, 1, true) ~= nil, "BattleState has " .. wanted)
  end

  local engine = sourceOf("src/battle/gen2/Battle.lua")
  check(engine ~= nil, "the battle engine's source is readable")
  check(engine:find("Mon.gainStatExp(mon, def, count, Pokerus.doublesStatExp(mon), halved)",
    1, true) ~= nil, "awardExperience gives stat exp through Pokerus")

  local specials = sourceOf("src/script/gen2/Specials.lua")
  check(specials ~= nil, "the specials' source is readable")
  check(specials:find("Pokerus.inParty(party(vm))", 1, true) ~= nil,
    "the CheckPokerus special reads the low nybble through the model")
end

-- ---- against a real cache -------------------------------------------------

-- ExitBattle's roll only ever runs off real base stats, so when a Gold cache is
-- present the stat exp half is re-asked against them.
local cache = os.getenv("GOLD_CACHE")
if cache then
  local path = cache .. "/data/generated/pokemon.lua"
  local f = io.open(path, "r")
  if f then
    f:close()
    local cached = assert(loadfile(path))()
    local pidgey = cached.PIDGEY
    if pidgey and pidgey.baseStats then
      local data = { pokemon = cached, moves = {} }
      local real = Mon.new(data, "CYNDAQUIL", 20)
      if real then
        real.pokerus = 0x34
        Mon.gainStatExp(real, pidgey, 1, Pokerus.doublesStatExp(real))
        eq(real.statExp.attack, (pidgey.baseStats.attack or 0) * 2,
          "a real base stat doubles for an infected mon")
        eq(real.statExp.special, (pidgey.baseStats.specialAttack or 0) * 2,
          "and the Special word comes from the real Special Attack")
      end
    end
  end
end

S.finish()
