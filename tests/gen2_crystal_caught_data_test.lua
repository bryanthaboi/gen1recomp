-- Crystal MON_CAUGHTDATA: the two packed bytes, who stamps them, and the two
-- readers that key off them (the level-up happiness pick and the fields that
-- have to survive an evolution and a Day-Care round trip).
--   luajit tests/gen2_crystal_caught_data_test.lua
--
-- Gold has no such word in its party struct, so every assertion below comes in
-- a Crystal half and a Gold half: Gold must come out with the three fields
-- still nil.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 crystal caught data")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local Mon = require("src.battle.gen2.Mon")
local Catching = require("src.battle.gen2.Catching")
local Evolution = require("src.core.gen2.Evolution")
local Breeding = require("src.core.gen2.Breeding")
local Happiness = require("src.core.gen2.Happiness")
local Save = require("src.core.gen2.Save")

local priorVersion = GameVersion.get()

-- ---- fixtures -------------------------------------------------------------

-- GROWTH_MEDIUM_FAST is plain n^3 (data/growth_rates.asm).
local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local function species(id, index, evolutions)
  return {
    id = id, index = index, name = id,
    baseStats = { hp = 45, attack = 49, defense = 49, speed = 45,
      specialAttack = 65, specialDefense = 65 },
    types = { "NORMAL", "NORMAL" },
    growthRate = "GROWTH_MEDIUM_FAST",
    genderRatio = 127,
    eggGroups = { "EGG_GROUND", "EGG_GROUND" },
    eggSteps = 20,
    evolutions = evolutions or {},
    levelMoves = { { level = 1, move = "TACKLE" } },
  }
end

local DATA = {
  moves = { TACKLE = { id = "TACKLE", pp = 35 } },
  pokemon = {
    growthRates = GROWTH,
    CATERPIE = species("CATERPIE", 10,
      { { method = "EVOLVE_LEVEL", level = 7, into = "METAPOD" } }),
    METAPOD = species("METAPOD", 11),
  },
  -- data/generated/landmarks.lua's shape, two rows deep enough for the
  -- National Park override to resolve by name.
  gen2Landmarks = {
    landmarks = {
      LANDMARK_NATIONAL_PARK = { id = "LANDMARK_NATIONAL_PARK", index = 19 },
      LANDMARK_NEW_BARK_TOWN = { id = "LANDMARK_NEW_BARK_TOWN", index = 1 },
    },
  },
}

local function newMon(level, opts)
  return Mon.new(DATA, "CATERPIE", level or 5, opts)
end

-- ---- the constants --------------------------------------------------------

eq(Mon.CAUGHT_TIME_MASK, 0xc0, "CAUGHT_TIME_MASK")
eq(Mon.CAUGHT_LEVEL_MASK, 0x3f, "CAUGHT_LEVEL_MASK")
eq(Mon.CAUGHT_GENDER_MASK, 0x80, "CAUGHT_GENDER_MASK")
eq(Mon.CAUGHT_LOCATION_MASK, 0x7f, "CAUGHT_LOCATION_MASK")
eq(Mon.CAUGHT_EGG_LEVEL, 1, "CAUGHT_EGG_LEVEL")
eq(Mon.LANDMARK_EVENT, 0x7f, "LANDMARK_EVENT")
eq(Mon.LANDMARK_GIFT, 0x7e, "LANDMARK_GIFT")

-- ---- the two bytes --------------------------------------------------------

-- `ld a, [wTimeOfDay] / inc a / rrca / rrca`: MORN 0 stores as 1, and 0 is
-- left free to mean unknown.
eq(Mon.caughtTimeOf(0), 1, "MORN stamps 1")
eq(Mon.caughtTimeOf(1), 2, "DAY stamps 2")
eq(Mon.caughtTimeOf(2), 3, "NITE stamps 3")
eq(Mon.caughtTimeOf("MORN"), 1, "the name reads the same as the id")
eq(Mon.caughtTimeOf(nil), 0, "and nothing at all is unknown")
eq(Mon.caughtTimeOf("BRUNCH"), 0, "as is a time of day that is not one")

local stamped = Mon.setCaughtData({ level = 12 },
  { timeOfDay = 2, landmark = 1, playerGender = "male" })
eq(stamped.caughtTime, 3, "NITE")
eq(stamped.caughtLevel, 12, "the level the catch happened at")
eq(stamped.caughtLocation, 1, "GetWorldMapLocation's landmark")
eq(stamped.caughtByGender, "boy", "and wPlayerGender bit 0 clear")

local byte0, byte1 = Mon.packCaughtData(stamped)
eq(byte0, 3 * 0x40 + 12, "byte 0 is ((tod + 1) << 6) | level")
eq(byte1, 1, "byte 1 is (female << 7) | landmark")

local female = Mon.setCaughtData({},
  { timeOfDay = 0, level = 7, landmark = 19, playerGender = "female" })
eq(female.caughtByGender, "girl", "PLAYERGENDER_FEMALE_F reads as girl")
byte0, byte1 = Mon.packCaughtData(female)
eq(byte0, 0x40 + 7, "MORN and level 7")
eq(byte1, 0x80 + 19, "the gender bit rides byte 1, not byte 0")

-- CAUGHT_LEVEL_MASK is six bits, so the packed level of a high-level catch
-- wraps exactly as `or b` leaves it on the cart.
byte0 = Mon.packCaughtData(Mon.setCaughtData({},
  { timeOfDay = 1, level = 70, landmark = 1 }))
eq(byte0 % 0x40, 70 % 0x40, "level 70 packs into six bits")

local round = Mon.unpackCaughtData(Mon.packCaughtData(female))
eq(round.caughtTime, 1, "unpack recovers the time")
eq(round.caughtLevel, 7, "the level")
eq(round.caughtLocation, 19, "the location")
eq(round.caughtByGender, "girl", "and the gender bit")

local blank = Mon.unpackCaughtData(0, 0)
eq(blank.caughtTime, 0, "an all-zero word is an unknown time")
eq(blank.caughtLevel, 0, "an unknown level")
eq(blank.caughtLocation, 0, "and an unknown location")

-- SetGiftMonCaughtData folds CAUGHT_BY_* through `rrc b`, which is why
-- CAUGHT_BY_BOY lands on LANDMARK_EVENT instead of on a gender bit.
local gift = Mon.setGiftCaughtData({}, "girl")
eq(gift.caughtTime, 0, "a gift mon has no caught time")
eq(gift.caughtLevel, 0, "and no caught level")
eq(gift.caughtLocation, Mon.LANDMARK_GIFT, "LANDMARK_GIFT")
eq(gift.caughtByGender, "girl", "with the gender bit set")
eq(Mon.setGiftCaughtData({}, "boy").caughtLocation, Mon.LANDMARK_EVENT,
  "CAUGHT_BY_BOY rotates into bit 0 and makes it LANDMARK_EVENT")
eq(Mon.setGiftCaughtData({}, "unknown").caughtLocation, Mon.LANDMARK_GIFT,
  "CAUGHT_BY_UNKNOWN leaves LANDMARK_GIFT alone")

-- ---- who stamps -----------------------------------------------------------

GameVersion.set("gold")
check(not Mon.hasCaughtData(), "Gold's struct has no MON_CAUGHTDATA")
local goldMon = newMon(5)
eq(goldMon.caughtLevel, 5, "Gold still gets the caught level it always had")
eq(goldMon.caughtTime, nil, "but no caught time")
eq(goldMon.caughtLocation, nil, "no caught location")
eq(goldMon.caughtByGender, nil, "and no OT gender")
Catching.stampCaughtData(goldMon,
  { data = DATA, timeOfDay = 1, map = { id = "ROUTE_29", landmark = 1 } })
eq(goldMon.caughtTime, nil, "and SetCaughtData is a no-op on Gold")

GameVersion.set("crystal")
check(Mon.hasCaughtData(), "the crystal lineage carries it")

local caught = newMon(4)
Catching.stampCaughtData(caught, {
  data = DATA, timeOfDay = 1, playerGender = "female",
  map = { id = "ROUTE_29", landmark = 1 },
})
eq(caught.caughtTime, 2, "a Crystal catch stamps the time")
eq(caught.caughtLevel, 4, "the level")
eq(caught.caughtLocation, 1, "the map's landmark")
eq(caught.caughtByGender, "girl", "and the player's gender")

-- The Pokecenter 2F substitution: wBackupMapGroup / wBackupMapNumber, so the
-- cable-club floor never lands on LANDMARK_SPECIAL.
eq(Catching.caughtLandmark({
  map = { id = "POKECENTER_2F", landmark = 0 },
  backupMap = { id = "VIOLET_CITY", landmark = 6 },
}), 6, "POKECENTER_2F reads the map it was entered from")
eq(Catching.caughtLandmark({ map = { id = "POKECENTER_2F", landmark = 0 } }), 0,
  "with no backup map recorded it stays unknown")
eq(Catching.caughtLandmark({ map = { id = "ROUTE_29", landmark = 1 } }), 1,
  "every other map is a plain GetWorldMapLocation")
eq(Catching.caughtLandmark({}), 0, "and no map at all is unknown")

-- BugContest_SetCaughtContestMon overwrites the location afterwards, keeping
-- the gender bit.
eq(Catching.caughtLandmark({ data = DATA, bugContest = true,
  map = { id = "NATIONAL_PARK_BUG_CONTEST", landmark = 0 } }), 19,
  "the Bug Contest catch is LANDMARK_NATIONAL_PARK")
eq(Catching.caughtLandmark({ bugContest = true }),
  Catching.LANDMARK_NATIONAL_PARK,
  "and the same index without a landmarks table to look it up in")

local contest = Catching.stampCaughtData(newMon(6), {
  data = DATA, bugContest = true, timeOfDay = 1, playerGender = "female",
  map = { id = "NATIONAL_PARK_BUG_CONTEST", landmark = 0 },
})
eq(contest.caughtLocation, 19, "the contest mon is stamped National Park")
eq(contest.caughtByGender, "girl", "and keeps CAUGHT_GENDER_MASK")

-- ---- survival across an evolution -----------------------------------------

check(Evolution.MON_FIELDS.caughtTime, "MON_FIELDS names caughtTime")
check(Evolution.MON_FIELDS.caughtLocation, "and caughtLocation")
check(Evolution.MON_FIELDS.caughtByGender, "and caughtByGender")

local evolved = Evolution.apply(DATA, caught,
  { method = "EVOLVE_LEVEL", level = 7, into = "METAPOD" })
eq(evolved.species, "METAPOD", "it evolved")
eq(evolved.caughtTime, 2, "the caught time survived")
eq(evolved.caughtLevel, 4, "the caught level survived")
eq(evolved.caughtLocation, 1, "the caught location survived")
eq(evolved.caughtByGender, "girl", "and so did the OT gender")

-- ---- survival across the Day-Care, and the egg marker ---------------------

local function newSave(party)
  local save = { version = "crystal", party = party or {},
    player = { name = "CHRIS", id = 1, gender = "female", money = 5000 },
    pokedex = { seen = {}, caught = {} } }
  return save
end

local deposited = newMon(5)
Catching.stampCaughtData(deposited, {
  data = DATA, timeOfDay = 2, playerGender = "female",
  map = { id = "ROUTE_34", landmark = 3 },
})
local save = newSave({})
local dc = Breeding.dayCare(save)
dc.man.mon = deposited
dc.man.level = 5
local ok, withdrawn = Breeding.withdraw(DATA, save, "man")
check(ok ~= false, "the mon came back out of the Day-Care")
withdrawn = save.party[1]
eq(withdrawn.caughtTime, 3, "RetrieveBreedmon carried the caught time")
eq(withdrawn.caughtLevel, 5, "the caught level")
eq(withdrawn.caughtLocation, 3, "the caught location")
eq(withdrawn.caughtByGender, "girl", "and the OT gender")

local egg = newMon(5)
egg.isEgg = true
egg.eggSteps = 0
egg.level = 5
save = newSave({ egg })
local hatched = Breeding.hatch(DATA, save, 1, nil,
  { timeOfDay = 0, landmark = 3 })
check(hatched ~= nil, "the egg hatched")
eq(hatched.caughtLevel, Mon.CAUGHT_EGG_LEVEL,
  "SetEggMonCaughtData stamps CAUGHT_EGG_LEVEL, not the hatch level")
eq(hatched.caughtTime, 1, "with the hatch site's time of day")
eq(hatched.caughtLocation, 3, "and its landmark")
eq(hatched.caughtByGender, "girl", "off save.player.gender")
eq(Mon.packCaughtData(hatched) % 0x40, Mon.CAUGHT_EGG_LEVEL,
  "so byte 0's level field reads 1")

GameVersion.set("gold")
local goldEgg = newMon(5)
goldEgg.isEgg = true
goldEgg.eggSteps = 0
local goldSave = newSave({ goldEgg })
goldSave.version = "gold"
goldSave.player.gender = nil
local goldHatch = Breeding.hatch(DATA, goldSave, 1)
eq(goldHatch.caughtLevel, 5, "a Gold hatchling keeps the egg's own level")
eq(goldHatch.caughtTime, nil, "and grows no caught-data keys")
eq(goldHatch.caughtLocation, nil, "none of them")
eq(goldHatch.caughtByGender, nil, "at all")
GameVersion.set("crystal")

-- ---- HAPPINESS_GAINLEVELATHOME --------------------------------------------

eq(Happiness.EVENT.GAINLEVELATHOME, 19, "the enum's 19th row")
eq(Happiness.NUM_EVENTS, 19, "and Crystal's table is one longer than Gold's")
eq(#Happiness.CHANGES, 19, "every row is present")
eq(Happiness.delta("GAINLEVELATHOME", 0), 10, "+10 under 100")
eq(Happiness.delta("GAINLEVELATHOME", 100), 6, "+6 under 200")
eq(Happiness.delta("GAINLEVELATHOME", 200), 4, "+4 above it")
check(Happiness.delta("GAINLEVELATHOME", 0) > Happiness.delta("GAINLEVEL", 0),
  "and it is worth more than a plain level")

local home = { happiness = 70, caughtLocation = 3 }
eq(Happiness.levelUpEvent(home, 3), "GAINLEVELATHOME",
  "levelling where it was caught")
eq(Happiness.levelUpEvent(home, 4), "GAINLEVEL", "and anywhere else")
eq(Happiness.levelUpEvent({ caughtLocation = 3 }, nil), "GAINLEVEL",
  "an unknown current landmark cannot match")
eq(Happiness.levelUpEvent({}, 0), "GAINLEVEL",
  "and a mon with no caught data at all never reads ATHOME")
eq(Happiness.levelUpEvent({ caughtLocation = 0 }, 0), "GAINLEVELATHOME",
  "though a Crystal mon stamped LANDMARK_SPECIAL does, as the cart's cp does")
-- CAUGHT_LOCATION_MASK: the comparison is against the low seven bits, so the
-- gender bit riding the same byte cannot break the match.
eq(Happiness.levelUpEvent({ caughtLocation = 0x80 + 3 }, 3), "GAINLEVELATHOME",
  "the gender bit is masked out of the comparison")

eq(Happiness.levelUp(home, 3), 80, "levelUp applies the +10")
eq(Happiness.levelUp(home, 9), 85, "and the +5 away from home")

-- ---- the save layer -------------------------------------------------------

eq(Save.defaultPlayerName("gold"), "GOLD", "PlayerNameArray's first row")
eq(Save.defaultPlayerName("silver"), "SILVER", "on Silver")
eq(Save.defaultPlayerName("crystal"), "CHRIS", "and MalePlayerNameArray's")

local normalized = Save.normalize({ version = "crystal", player = {} })
eq(normalized.player.gender, "male", "normalize defaults wPlayerGender to 0")
eq(Save.normalize({ version = "crystal",
  player = { gender = "female" } }).player.gender, "female",
  "and leaves a recorded gender alone")

-- A Gold save that never catches anything grows no new keys.
GameVersion.set("gold")
local goldParty = { newMon(5) }
local goldFile = Save.normalize({ version = "gold", party = goldParty })
eq(goldFile.party[1].caughtTime, nil, "no caughtTime on a Gold record")
eq(goldFile.party[1].caughtLocation, nil, "no caughtLocation")
eq(goldFile.party[1].caughtByGender, nil, "no caughtByGender")

GameVersion.set(priorVersion)

S.finish()
