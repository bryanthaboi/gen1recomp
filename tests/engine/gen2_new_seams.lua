-- The events and hooks that are NEW IN GEN 2 -- the only names in the mod API
-- with no Gen 1 analogue, and therefore the only places a new name is
-- justified (docs/mod-api-gen2-compat.md, "New in Gen 2").
--
-- gate_gen2_mod_api.lua holds the SHARED names to having a call site in both
-- generations; by construction that gate cannot cover these, because a Gen 1
-- site is exactly what they do not have.  This file is the other half: for
-- each new name, drive the real Gen 2 module through a live bus and assert the
-- payload the call site documents.  It runs ROM-free -- every module below
-- takes its data by argument -- so it lives in the engine tier.
--
-- The discipline each case follows is the one gate_events/gate_hooks enforce
-- generally: subscribe, drive, assert the payload, unsubscribe, and assert the
-- mod-free path answers exactly what it answered before.

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.gen2_engine_flags").bind("gold")

local T = require("tests.modkit")
local Events = require("src.mods.Events")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")

local Apricorns = require("src.core.gen2.Apricorns")
local Breeding = require("src.core.gen2.Breeding")
local BugContest = require("src.core.gen2.BugContest")
local Clock = require("src.core.gen2.Clock")
local Happiness = require("src.core.gen2.Happiness")
local Mail = require("src.core.gen2.Mail")
local Mon = require("src.battle.gen2.Mon")
local Phone = require("src.core.gen2.Phone")
require("tests.fixtures.gen2_phone_events").install()
local PhoneRing = require("src.core.gen2.PhoneRing")
local Pokerus = require("src.core.gen2.Pokerus")
local Roamers = require("src.core.gen2.Roamers")
local Unown = require("src.core.gen2.Unown")

-- ------- the bus, installed the way Loader:load installs it

local events, hooks = Events.new(), Hooks.new()
local savedEvents, savedHooks = Runtime.events, Runtime.hooks
Runtime.install(events, hooks, {})

-- Collect every payload `name` raises while `body` runs, then unsubscribe --
-- so the next case starts from the mod-free state and Runtime.wants goes back
-- to false, which is what the guarded call sites key off.
local function capture(name, body)
  local seen = {}
  local unsubscribe = events:on(name, function(payload)
    seen[#seen + 1] = payload
  end, 0, "gen2_new_seams")
  body()
  unsubscribe()
  return seen
end

local function withHook(name, wrapper, body)
  local remove = hooks:wrap(name, wrapper, 0, "gen2_new_seams")
  local ok, err = pcall(body)
  remove()
  if not ok then error(err, 0) end
end

-- ------- a Gen 2 shaped dataset, small enough to read

local DATA = {
  pokemon = {
    growthRates = {
      MEDIUM_FAST = { numerator = 1, denominator = 1 },
    },
    SEEDMON = {
      id = "SEEDMON", name = "SEEDMON", index = 1, dex = 1,
      types = { "GRASS" },
      baseStats = { hp = 45, attack = 49, defense = 49, speed = 45,
                    specialAttack = 65, specialDefense = 65 },
      catchRate = 45, baseExp = 64, growthRate = "MEDIUM_FAST",
      levelMoves = { { level = 1, move = "SEED_TACKLE" } },
      evolutions = {},
      eggGroups = { "MONSTER" }, eggSteps = 20, genderRatio = 0x1f,
      spriteFront = "a.png", spriteBack = "b.png", picSize = 5,
    },
  },
  moves = { SEED_TACKLE = { id = "SEED_TACKLE", pp = 35 } },
}

-- ------- happiness.changed

do
  local mon = { species = "SEEDMON", happiness = Happiness.BASE, hp = 20 }
  local seen = capture("happiness.changed", function()
    Happiness.change(mon, "GAINLEVEL")
  end)
  T.eq(#seen, 1, "happiness.changed fires once per ChangeHappiness")
  T.eq(seen[1].mon, mon, "happiness.changed carries the mon")
  T.eq(seen[1].event, "GAINLEVEL", "happiness.changed carries the event name")
  T.eq(seen[1].reason, "event", "a ChangeHappiness reports reason 'event'")
  T.eq(seen[1].from, Happiness.BASE, "happiness.changed carries the old value")
  T.eq(seen[1].to, Happiness.BASE + 5, "happiness.changed carries the new value")
  T.eq(seen[1].delta, 5, "happiness.changed's delta is what was applied")

  -- the clamp is part of the delta: a mon on $ff gaining 5 gained nothing
  local capped = { species = "SEEDMON", happiness = Happiness.MAX }
  local clamped = capture("happiness.changed", function()
    Happiness.change(capped, "GAINLEVEL")
  end)
  T.eq(clamped[1].delta, 0, "happiness.changed reports the clamped delta")

  local save = { party = { { species = "SEEDMON", happiness = 10 } },
                 happinessStepCount = 1 }
  local stepped = capture("happiness.changed", function()
    Happiness.stepCycle(save)
  end)
  T.eq(#stepped, 1, "StepHappiness raises happiness.changed per mon it moved")
  T.eq(stepped[1].reason, "step", "the walk reports reason 'step'")
  T.eq(stepped[1].event, nil, "the walk has no HAPPINESS_* event")

  -- the mod-free path is unchanged
  local plain = { species = "SEEDMON", happiness = Happiness.BASE }
  T.eq(Happiness.change(plain, "GAINLEVEL"), Happiness.BASE + 5,
    "ChangeHappiness answers the same with nobody subscribed")
end

-- ------- breeding.compatibility, breeding.egg_created, egg.hatched

do
  local man = { species = "SEEDMON", dvs = { attack = 2, defense = 2,
                speed = 3, special = 4 }, otId = 1 }
  local lady = { species = "SEEDMON", dvs = { attack = 5, defense = 6,
                 speed = 7, special = 8 }, otId = 2 }

  -- vanilla: two same-gender SEEDMON with no Ditto never breed
  T.eq(Breeding.compatibility(DATA, man, lady), 0,
    "breeding.compatibility answers the vanilla 0 with nobody subscribed")

  local ctxSeen
  withHook("breeding.compatibility", function(nextFn, ctx)
    ctxSeen = ctx
    nextFn()
    return 128
  end, function()
    T.eq(Breeding.compatibility(DATA, man, lady, { dayCare = true }), 128,
      "breeding.compatibility replaces the answer")
  end)
  T.eq(ctxSeen.mon1, man, "breeding.compatibility's ctx carries the first mon")
  T.eq(ctxSeen.mon2, lady, "breeding.compatibility's ctx carries the second")
  T.eq(ctxSeen.data, DATA, "breeding.compatibility's ctx carries the data")
  T.eq(ctxSeen.dayCare, true, "breeding.compatibility knows the yard called it")

  -- and the value is clamped to the byte wBreedingCompatibility is
  withHook("breeding.compatibility", function() return 9999 end, function()
    T.eq(Breeding.compatibility(DATA, man, lady), 255,
      "breeding.compatibility clamps to the compatibility byte")
  end)

  -- egg_created rides the same forced compatibility: initBreeding refuses 0
  local save = { dayCare = { man = { mon = man }, lady = { mon = lady },
                             compatible = false },
                 player = { name = "GOLD", id = 7 } }
  local created
  withHook("breeding.compatibility", function() return 128 end, function()
    created = capture("breeding.egg_created", function()
      Breeding.initBreeding(DATA, save, { rng = function() return 200 end })
    end)
  end)
  T.eq(#created, 1, "breeding.egg_created fires when the pair becomes compatible")
  T.eq(created[1].compatibility, 128,
    "breeding.egg_created carries the compatibility that let it run")
  T.eq(created[1].stepsToEgg, save.dayCare.stepsToEgg,
    "breeding.egg_created carries wStepsToEgg")
  T.check(created[1].mother ~= nil and created[1].father ~= nil,
    "breeding.egg_created names both parents")
  T.check(created[1].mother ~= created[1].father,
    "breeding.egg_created's parents are the two different records")

  -- egg.hatched, off a real egg in a party slot
  local egg = Mon.new(DATA, "SEEDMON", Breeding.EGG_LEVEL, { hp = 0 })
  egg.isEgg = true
  egg.eggSteps = 0
  local file = { party = { egg } }
  local hatched = capture("egg.hatched", function()
    Breeding.hatch(DATA, file, 1, "SPROUT")
  end)
  T.eq(#hatched, 1, "egg.hatched fires once per hatched slot")
  T.eq(hatched[1].slot, 1, "egg.hatched carries the party slot")
  T.eq(hatched[1].species, "SEEDMON", "egg.hatched carries the species")
  T.eq(hatched[1].nickname, "SPROUT", "egg.hatched carries the chosen nickname")
  T.eq(hatched[1].egg, egg, "egg.hatched carries the egg it replaced")
  T.eq(hatched[1].mon, file.party[1],
    "egg.hatched carries the hatchling now in the party")
  T.eq(hatched[1].mon.isEgg, nil, "the hatchling is no longer an egg")
end

-- ------- phone.call_received and phone.contact_list

do
  local call = { kind = "call", contact = 1, direction = "incoming",
                 scriptKey = "41:4000" }
  local seen = capture("phone.call_received", function()
    PhoneRing.script(call, "JOEY", "YOUNGSTER")
  end)
  T.eq(#seen, 1, "phone.call_received fires once per ring")
  T.eq(seen[1].call, call, "phone.call_received carries the descriptor")
  T.eq(seen[1].contact, 1, "phone.call_received carries the contact id")
  T.eq(seen[1].name, "JOEY", "phone.call_received carries the caller name")
  T.eq(seen[1].className, "YOUNGSTER", "phone.call_received carries the class")
  T.eq(seen[1].scriptKey, "41:4000", "phone.call_received carries the script key")

  local save = {}
  Phone.addContact(save, Phone.CONTACTS[1] and 1 or 1)
  local vanilla = Phone.contacts(save)
  T.eq(#vanilla, Phone.CONTACT_LIST_SIZE,
    "the phone book is ten slots with nobody subscribed")

  withHook("phone.contact_list", function(nextFn, file, list)
    T.eq(file, save, "phone.contact_list is handed the save")
    T.eq(#list, Phone.CONTACT_LIST_SIZE,
      "phone.contact_list is handed all ten slots")
    local out = nextFn()
    out[10] = 1
    return out
  end, function()
    local hooked = Phone.contacts(save)
    T.eq(#hooked, Phone.CONTACT_LIST_SIZE,
      "phone.contact_list keeps the slot count")
    T.eq(hooked[10], 1, "phone.contact_list can fill an empty slot")
  end)

  -- a chain that returns the wrong shape is ignored rather than trusted
  withHook("phone.contact_list", function() return { 1, 2 } end, function()
    T.eq(#Phone.contacts(save), Phone.CONTACT_LIST_SIZE,
      "a short phone.contact_list answer is refused")
  end)
  -- and an id the contact table does not know is blanked, not carried
  withHook("phone.contact_list", function(nextFn)
    local out = nextFn()
    out[1] = 9999
    return out
  end, function()
    T.eq(Phone.contacts(save)[1], 0,
      "phone.contact_list blanks an unknown contact id")
  end)
end

-- ------- clock.day_changed

do
  local save = {}
  local seen = capture("clock.day_changed", function()
    -- the first read after a boot has nothing to compare against
    Clock.weekday(save)
    -- Mom's wheel moving the day is a change; setWeekday reports it
    Clock.setWeekday(save, (Clock.weekday(save) + 3) % Clock.DAYS)
  end)
  T.eq(#seen, 1, "clock.day_changed does not fire on the first read")
  T.eq(seen[1].reason, "set", "re-anchoring the day reports reason 'set'")
  T.eq(seen[1].day, Clock.weekday(save), "clock.day_changed carries the new day")
  T.check(seen[1].previous ~= seen[1].day,
    "clock.day_changed carries a different previous day")

  local quiet = capture("clock.day_changed", function()
    Clock.weekday(save)
    Clock.weekday(save)
    Clock.weekday(save)
  end)
  T.eq(#quiet, 0, "a day that has not moved raises nothing")
end

-- ------- pokerus.infected

do
  -- .TrySpreadPokerus: slot 1 already carries the virus, slot 2 is clean, and
  -- the rolls below pass the spread gate and walk forward.
  local party = {
    { species = "SEEDMON", pokerus = 0x11 },
    { species = "SEEDMON", pokerus = 0 },
  }
  local rolls = { 0, 255 }
  local index = 0
  local function random()
    index = index + 1
    return rolls[index] or 0
  end
  local seen = capture("pokerus.infected", function()
    Pokerus.give(party, { random = random })
  end)
  T.eq(#seen, 1, "pokerus.infected fires once per newly infected slot")
  T.eq(seen[1].slot, 2, "pokerus.infected carries the party slot")
  T.eq(seen[1].mon, party[2], "pokerus.infected carries the mon")
  T.eq(seen[1].source, "spread", "a spread reports source 'spread'")
  T.eq(seen[1].strain, Pokerus.strain(party[2]),
    "pokerus.infected carries the strain nybble")
  T.eq(seen[1].days, Pokerus.days(party[2]),
    "pokerus.infected carries the day counter")
  T.check(Pokerus.isInfected(party[2]), "and the byte really was written")
end

-- ------- roamer.moved and roamer.encountered

do
  local save = {}
  local roamEncounters = require("tests.fixtures.gen2_roamers").encounters("gold")
  Roamers.init(save, { encounters = roamEncounters })
  local seen = capture("roamer.moved", function()
    Roamers.jumpAll(save, "ROUTE_29", function(n) return n - 1 end,
      roamEncounters)
  end)
  T.check(#seen > 0, "roamer.moved fires when JumpRoamMons scatters the beasts")
  for _, payload in ipairs(seen) do
    T.eq(payload.reason, "jump", "a teleport reports reason 'jump'")
    T.check(payload.from ~= payload.to,
      "roamer.moved only reports a beast that changed route")
    T.eq(payload.slot.map, payload.to, "roamer.moved's `to` is where it stands")
  end

  -- CheckEncounterRoamMon: a byte under 100 whose low two bits pick slot 1
  local beast = Roamers.slot(save, 1)
  beast.map = "ROUTE_42"
  local met = capture("roamer.encountered", function()
    local hit = Roamers.checkEncounter(save, "ROUTE_42", false,
      function() return 1 end)
    T.check(hit ~= nil, "the roll met the roamer")
  end)
  T.eq(#met, 1, "roamer.encountered fires once per meeting")
  T.eq(met[1].index, 1, "roamer.encountered carries the roamer slot")
  T.eq(met[1].species, beast.species, "roamer.encountered carries the species")
  T.eq(met[1].mapId, "ROUTE_42", "roamer.encountered carries the map")
end

-- ------- apricorn.converted

do
  local save = { inventory = { RED_APRICORN = 1 }, events = {}, engineFlags = {} }
  T.check(Apricorns.give(save, "RED_APRICORN"), "Kurt takes the apricorn")
  -- .GiveLevelBall only fires once the daily flag has rolled over
  save.engineFlags[Apricorns.ENGINE_KURT_MAKING_BALLS] = false
  local seen = capture("apricorn.converted", function()
    local ball = Apricorns.collect(save)
    T.check(ball ~= nil, "the ball is ready to collect")
  end)
  T.eq(#seen, 1, "apricorn.converted fires once per ball handed over")
  T.eq(seen[1].apricorn, "RED_APRICORN",
    "apricorn.converted carries the apricorn that went in")
  T.eq(seen[1].ball, Apricorns.ballFor("RED_APRICORN"),
    "apricorn.converted carries the ball that came out")
  T.check(seen[1].event ~= nil,
    "apricorn.converted names the EVENT_GAVE_KURT_* flag it cleared")
end

-- ------- bug_contest.scored

do
  local save = {}
  local state = BugContest.state(save)
  state.caught = { species = "SEEDMON", hp = 20, maxHp = 20,
                   stats = { attack = 10, defense = 10, speed = 10,
                             specialAttack = 10, specialDefense = 10 },
                   dvs = { attack = 2, defense = 2, speed = 2, special = 2 } }
  local seen = capture("bug_contest.scored", function()
    BugContest.runJudging(save, function() return 0 end)
  end)
  T.eq(#seen, 1, "bug_contest.scored fires once per judging")
  T.eq(seen[1].mon, state.caught, "bug_contest.scored carries the player's mon")
  T.eq(seen[1].score, BugContest.score(state.caught),
    "bug_contest.scored carries the score DetermineContestWinners used")
  T.eq(seen[1].place, state.place, "bug_contest.scored carries the placing")
  T.check(seen[1].results ~= nil and seen[1].results.first ~= nil,
    "bug_contest.scored carries the podium")
end

-- ------- unown.unlocked

do
  local save = {}
  local seen = capture("unown.unlocked", function()
    Unown.updateDex(save, 1)
    -- the same letter a second time is UpdateUnownDex's early return
    Unown.updateDex(save, 1)
    Unown.updateDex(save, 2)
  end)
  T.eq(#seen, 2, "unown.unlocked fires once per NEW form, not per catch")
  T.eq(seen[1].letter, 1, "unown.unlocked carries the letter number")
  T.eq(seen[1].name, "A", "unown.unlocked carries the letter name")
  T.eq(seen[1].word, Unown.word(1), "unown.unlocked carries the form's word")
  T.eq(seen[2].count, 2, "unown.unlocked carries the running count")
end

-- ------- mail.written and mail.read

do
  local save = { player = { name = "GOLD", id = 7 },
                 party = { { species = "SEEDMON" } } }
  local written = capture("mail.written", function()
    Mail.compose(save, 1, "HI THERE", save.party[1], "LOVELY_MAIL")
  end)
  T.eq(#written, 1, "mail.written fires when the compose screen closes")
  T.eq(written[1].slot, 1, "mail.written carries the party slot")
  T.eq(written[1].source, "compose", "the compose screen reports 'compose'")
  T.eq(written[1].author, "GOLD", "mail.written carries the author")
  T.eq(written[1].message, "HI THERE", "mail.written carries the message")
  T.eq(written[1].mon, save.party[1], "mail.written carries the mon it rides")

  local given = capture("mail.written", function()
    Mail.give(save, "LOVELY_MAIL", "FROM A FRIEND")
  end)
  T.eq(#given, 1, "GivePokeMail raises mail.written too")
  T.eq(given[1].source, "script", "a scripted letter reports 'script'")

  local entry = Mail.get(save, 1)
  local read = capture("mail.read", function()
    -- the reader redraws the page every frame; that is one opened letter
    Mail.lines(entry)
    Mail.lines(entry)
    Mail.lines(entry)
  end)
  T.eq(#read, 1, "mail.read is one event per opened letter, not per frame")
  T.eq(read[1].entry, entry, "mail.read carries the struct being read")
  T.eq(read[1].message, entry.message, "mail.read carries the message")
  T.check(read[1].top ~= nil and read[1].bottom ~= nil,
    "mail.read carries the two rows MailGFX_PlaceMessage draws")

  local reopened = capture("mail.read", function()
    -- picking the letter again out of the record re-arms the latch
    local again = Mail.get(save, 1)
    Mail.lines(again)
    Mail.lines(again)
  end)
  T.eq(#reopened, 1, "opening the same letter a second time is a second event")
end

-- ------- radio.channel
--
-- src/ui/gen2/MapRadio.lua is a LOVE state and its constructor reaches through
-- the Pokegear, so the seam is asserted here through the bus rather than by
-- building a screen: what this pins is that the name is on the wire and that a
-- listener sees the four fields the call site documents.

do
  local seen = capture("radio.channel", function()
    Runtime.emit("radio.channel", { station = "OAKS_POKEMON_TALK", channel = 1,
      name = "OAK'S #MON TALK", source = "map_radio" })
  end)
  T.eq(#seen, 1, "radio.channel reaches a listener")
  T.eq(seen[1].source, "map_radio", "radio.channel names the wall radio")
  T.eq(seen[1].station, "OAKS_POKEMON_TALK", "radio.channel carries the station")
end

-- ------- shiny.roll and gender.roll

do
  local shinyDvs = { attack = 2, defense = 10, speed = 10, special = 10 }
  local plainDvs = { attack = 0, defense = 0, speed = 0, special = 0 }
  T.eq(Mon.isShiny(shinyDvs), true, "the vanilla shiny pattern still reads true")
  T.eq(Mon.isShiny(plainDvs), false, "and a plain DV set still reads false")

  local ctxSeen
  withHook("shiny.roll", function(nextFn, ctx)
    ctxSeen = ctx
    nextFn()
    return true
  end, function()
    local mon = Mon.new(DATA, "SEEDMON", 5, { dvs = plainDvs })
    T.eq(mon.shiny, true, "shiny.roll can force a shiny")
  end)
  T.eq(ctxSeen.species, "SEEDMON", "shiny.roll's ctx carries the species")
  T.eq(ctxSeen.level, 5, "shiny.roll's ctx carries the level")
  T.check(ctxSeen.dvs ~= nil, "shiny.roll's ctx carries the DVs")

  -- a forced-shiny battle overrides the roll rather than hooking it
  withHook("shiny.roll", function() return false end, function()
    local forced = Mon.new(DATA, "SEEDMON", 5,
      { dvs = plainDvs, shiny = true })
    T.eq(forced.shiny, true, "opts.shiny still wins over shiny.roll")
  end)

  -- Mon.syncIdentity (wired into refreshStats, which SummaryMenu.new calls
  -- on every menu open) used to recompute mon.shiny from DVs unconditionally,
  -- so opening the summary screen on a forced shiny -- one whose DVs do not
  -- happen to match the natural pattern -- un-shinied it the moment the menu
  -- opened.  shiny is monotonic once true: a natural roll or a forced one
  -- both stay shiny through any later refresh, the way opts.shiny already
  -- wins at construction.
  do
    local forced = Mon.new(DATA, "SEEDMON", 5, { dvs = plainDvs, shiny = true })
    T.eq(forced.shiny, true, "still shiny straight out of Mon.new")
    Mon.syncIdentity(forced, DATA)
    T.eq(forced.shiny, true, "syncIdentity does not clobber a forced shiny")
    Mon.refreshStats(forced, DATA)
    T.eq(forced.shiny, true,
      "refreshStats (SummaryMenu.new's call) does not either")

    -- the natural cases are unaffected: DVs that read shiny stay shiny,
    -- DVs that do not stay plain
    local natural = Mon.new(DATA, "SEEDMON", 5, { dvs = shinyDvs })
    Mon.syncIdentity(natural, DATA)
    T.eq(natural.shiny, true, "a naturally shiny mon still reads shiny")
    local plain = Mon.new(DATA, "SEEDMON", 5, { dvs = plainDvs })
    Mon.syncIdentity(plain, DATA)
    T.eq(plain.shiny, false, "a plain mon is not promoted to shiny")
  end

  local genderCtx
  withHook("gender.roll", function(nextFn, ctx)
    genderCtx = ctx
    nextFn()
    return "female"
  end, function()
    local mon = Mon.new(DATA, "SEEDMON", 5,
      { dvs = { attack = 15, defense = 0, speed = 0, special = 0 } })
    T.eq(mon.gender, "female", "gender.roll can replace the answer")
  end)
  T.eq(genderCtx.ratio, DATA.pokemon.SEEDMON.genderRatio,
    "gender.roll's ctx carries the species' ratio byte")
  T.eq(genderCtx.species, "SEEDMON", "gender.roll's ctx carries the species")

  -- anything that is not one of the three genders falls back to vanilla
  withHook("gender.roll", function() return "enby" end, function()
    T.eq(Mon.gender(DATA.pokemon.SEEDMON,
      { attack = 15, defense = 0, speed = 0, special = 0 }), "male",
      "an unknown gender.roll answer falls back to the DV read")
  end)
end

-- ------- held_item.trigger
--
-- Driven through Battle:heldEffect directly: it is the one function every
-- held-item site on Gold reads its (effect, parameter) pair out of, which is
-- the property that makes one hook cover all eight triggers.

do
  local Battle = require("src.battle.gen2.Battle")
  local battle = setmetatable({
    data = { items = { KINGS_ROCK = { id = "KINGS_ROCK", name = "KING'S ROCK",
                                      heldEffect = "HELD_FLINCH",
                                      heldParameter = 30 } } },
  }, Battle)
  local mon = { species = "SEEDMON", item = "KINGS_ROCK" }

  local effect, parameter = battle:heldEffect(mon, "flinch")
  T.eq(effect, "HELD_FLINCH", "the vanilla held effect comes off the item")
  T.eq(parameter, 30, "and so does its parameter")

  local ctxSeen
  withHook("held_item.trigger", function(nextFn, ctx)
    ctxSeen = ctx
    return nextFn()
  end, function()
    local e, p = battle:heldEffect(mon, "flinch")
    T.eq(e, "HELD_FLINCH", "held_item.trigger's vanilla answers the item")
    T.eq(p, 30, "held_item.trigger's vanilla answers the parameter")
  end)
  T.eq(ctxSeen.trigger, "flinch", "held_item.trigger names which site called")
  T.eq(ctxSeen.mon, mon, "held_item.trigger carries the holder")
  T.eq(ctxSeen.item, "KINGS_ROCK", "held_item.trigger carries the item id")
  T.eq(ctxSeen.effect, "HELD_FLINCH", "held_item.trigger carries the effect")
  T.eq(ctxSeen.parameter, 30, "held_item.trigger carries the parameter")
  T.eq(ctxSeen.battle, battle, "held_item.trigger carries the battle")

  -- suppression: nil is "this item does nothing at this trigger"
  withHook("held_item.trigger", function() return nil end, function()
    T.eq(battle:heldEffect(mon, "flinch"), nil,
      "held_item.trigger can switch an item off")
  end)

  -- substitution: another HELD_* name, keeping the item's own parameter
  withHook("held_item.trigger", function() return "HELD_QUICK_CLAW" end,
    function()
      local e, p = battle:heldEffect(mon, "priority")
      T.eq(e, "HELD_QUICK_CLAW", "held_item.trigger can substitute an effect")
      T.eq(p, 30, "and the item's own parameter survives the substitution")
    end)

  -- the residual arm reads through the same seam
  local leftovers = { species = "SEEDMON", item = "LEFTOVERS", hp = 10,
                      maxHp = 20, stats = { hp = 20 } }
  battle.data.items.LEFTOVERS = { id = "LEFTOVERS", name = "LEFTOVERS",
                                  heldEffect = "HELD_LEFTOVERS" }
  local residual
  withHook("held_item.trigger", function(nextFn, ctx)
    residual = ctx.trigger
    return nextFn()
  end, function()
    battle:heldEffect(leftovers, "residual")
  end)
  T.eq(residual, "residual",
    "the end-of-turn arm reaches held_item.trigger as 'residual'")
end

-- ------- intro.boot.*: the GS boot cinema
--
-- Red boots into IntroMovie and has no copyright card, no GAME FREAK splash
-- and no attract movie, so these four cards are the rare case where a NEW name
-- is the honest one -- there is no Gen 1 moment to share with.  (The Oak
-- speech next door is the opposite case and reuses intro.oak_speech.* verbatim;
-- gate_gen2_mod_api.lua holds that half.)  One name per card, raised the frame
-- the card comes up, plus the one card end that carries a fact nothing
-- downstream does: whether the movie was watched or skipped.
--
-- The screens take their data by argument and draw nothing here, so the whole
-- chain runs ROM-free.

do
  local CopyrightSplash = require("src.ui.gen2.CopyrightSplash")
  local GameFreakPresents = require("src.ui.gen2.GameFreakPresents")
  local GoldSilverIntro = require("src.ui.gen2.GoldSilverIntro")
  local TitleState = require("src.ui.gen2.TitleState")

  local game = { data = {}, save = { player = {} } }

  local seen = capture("intro.boot.copyright", function()
    CopyrightSplash.new(game, {}):enter()
  end)
  T.eq(#seen, 1, "the copyright card raises intro.boot.copyright once")
  T.check(seen[1].screen ~= nil and seen[1].game == game,
    "intro.boot.copyright carries { screen, game }")

  seen = capture("intro.boot.gamefreak", function()
    GameFreakPresents.new(game,
      { oakSpeech = require("tests.fixtures.gen2_oak_speech").data() }):enter()
  end)
  T.eq(#seen, 1, "the GAME FREAK splash raises intro.boot.gamefreak once")
  T.check(seen[1].screen ~= nil and seen[1].game == game,
    "intro.boot.gamefreak carries { screen, game }")

  local movie
  seen = capture("intro.boot.movie", function()
    movie = GoldSilverIntro.new(game, {})
    movie:enter()
  end)
  T.eq(#seen, 1, "the attract movie raises intro.boot.movie once")
  T.check(seen[1].screen == movie and seen[1].game == game,
    "intro.boot.movie carries { screen, game }")

  -- GoldSilverIntro.PlayFrame's PAD_BUTTONS exit.
  seen = capture("intro.boot.movie_ended", function() movie:skip() end)
  T.eq(#seen, 1, "a skipped movie raises intro.boot.movie_ended once")
  T.eq(seen[1].skipped, true, "and reports skipped = true")
  T.check(type(seen[1].frames) == "number",
    "intro.boot.movie_ended carries the frame count it reached")

  -- IntroScene17's `ld c, 64` tail, i.e. the movie run to its end.
  seen = capture("intro.boot.movie_ended", function()
    local watched = GoldSilverIntro.new(game, {})
    watched:enter()
    watched:finish()
  end)
  T.eq(seen[1].skipped, false, "a movie watched through reports skipped = false")

  seen = capture("intro.boot.title", function()
    TitleState.new(game, { title = require("tests.fixture_data.gen2_title_s7_c").gold }):enter()
  end)
  T.eq(#seen, 1, "the title screen raises intro.boot.title once")
  T.check(seen[1].screen ~= nil and seen[1].game == game,
    "intro.boot.title carries { screen, game }")
end

-- ------- the mod-free state is restored

-- ------- battle.enemy_switch_or_item
--
-- AI_SwitchOrTryItem's whole choke point (src/battle/gen2/Battle.lua), the
-- companion to battle.enemy_action: enemy_action rewrites which MOVE the foe
-- picks, this one decides whether the foe spends the turn on a rotation or an
-- item instead of moving at all.  Vanilla answers a boolean; a mod may answer
-- a { kind = "switch", index } or a { kind = "item", item } action.

do
  local Battle = require("src.battle.gen2.Battle")
  local Mon = require("src.battle.gen2.Mon")
  local data = {
    pokemon = DATA.pokemon,
    moves = DATA.moves,
    items = { POTION = { id = "POTION", name = "POTION" } },
    text = require("tests.gen2_battle_text_fixture")(), type_chart = { battleRules = require("tests.gen2_battle_rules_fixture")(), types = {}, matchups = {} },
  }
  local function fighter(level)
    local mon = Mon.new(data, "SEEDMON", level,
      { dvs = { attack = 15, defense = 15, speed = 15, special = 15 } })
    mon.moves = { { id = "SEED_TACKLE", pp = 35, maxPp = 35 } }
    return mon
  end
  local roster = { fighter(10), fighter(12) }
  local battle = Battle.new({
    data = data,
    random = function() return 0 end,
    party = { fighter(10) },
    trainer = { name = "FOE", party = roster, items = { "POTION" } },
  })

  -- No TRNATTR_AI flags: vanilla never rotates and never drinks.
  T.eq(battle:enemyTrySwitchOrItem(), false,
    "battle.enemy_switch_or_item's vanilla refuses a flagless trainer")

  local ctxSeen
  withHook("battle.enemy_switch_or_item", function(nextFn, b)
    ctxSeen = b
    return nextFn(b)
  end, function()
    T.eq(battle:enemyTrySwitchOrItem(), false,
      "battle.enemy_switch_or_item passes vanilla's answer through")
  end)
  T.eq(ctxSeen, battle, "battle.enemy_switch_or_item is handed the battle")

  withHook("battle.enemy_switch_or_item", function()
    return { kind = "switch", index = 2 }
  end, function()
    T.eq(battle:enemyTrySwitchOrItem(), true,
      "battle.enemy_switch_or_item can rotate the foe")
    T.eq(battle.enemyIndex, 2, "...to the slot the action names")
    T.eq(battle.enemy, roster[2], "...and the battler follows")
  end)

  battle.enemy.hp = 1
  withHook("battle.enemy_switch_or_item", function()
    return { kind = "item", item = "POTION" }
  end, function()
    T.eq(battle:enemyTrySwitchOrItem(), true,
      "battle.enemy_switch_or_item can spend the turn on an item")
  end)
  T.check(battle.enemy.hp > 1, "...and the item's effect lands")
  T.eq(#battle.trainer.items, 0, "...consuming it from the roster")

  withHook("battle.enemy_switch_or_item", function() return nil end, function()
    T.eq(battle:enemyTrySwitchOrItem(), false,
      "battle.enemy_switch_or_item can refuse both")
  end)
end

for _, name in ipairs({ "intro.boot.copyright", "intro.boot.gamefreak",
                        "intro.boot.movie", "intro.boot.movie_ended",
                        "intro.boot.title",
                        "happiness.changed", "breeding.egg_created",
                        "egg.hatched", "phone.call_received",
                        "clock.day_changed", "pokerus.infected",
                        "roamer.moved", "roamer.encountered",
                        "apricorn.converted", "bug_contest.scored",
                        "unown.unlocked", "radio.channel", "mail.written",
                        "mail.read" }) do
  T.eq(Runtime.wants(name), false,
    "every case unsubscribed: " .. name)
end
-- Hooks:wrap's remover empties the chain but leaves the (empty) table, the
-- same residue gate_events.lua documents for the event bus, so the check is on
-- the chain's contents rather than on wantsHook.
for _, name in ipairs({ "held_item.trigger", "breeding.compatibility",
                        "phone.contact_list", "shiny.roll", "gender.roll",
                        "battle.enemy_switch_or_item" }) do
  T.eq(#(hooks.chains[name] or {}), 0, "every hook case unwrapped: " .. name)
end

Runtime.events, Runtime.hooks = savedEvents, savedHooks
Runtime.errors = nil

T.finish("gen2_new_seams")
