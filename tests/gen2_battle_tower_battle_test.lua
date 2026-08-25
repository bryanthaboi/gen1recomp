-- The Battle Tower BATTLE: the roster tables, the opponent draw and the two
-- specials maps/BattleTowerBattleRoom.asm's loop is built out of.
--
--   luajit tests/gen2_battle_tower_battle_test.lua
--
-- ROM-free.  The extractor half runs against a synthetic cartridge whose
-- tables are laid out byte for byte the way data/battle_tower/ assembles
-- them, and the rest against a fixture roster taken from
-- ../pokecrystal/data/battle_tower/parties.asm group 1.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle tower battle")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local BattleTower = require("src.core.gen2.BattleTower")
local Mon = require("src.battle.gen2.Mon")
local RomExtractorGen2 = require("src.import.RomExtractorGen2")
local Save = require("src.core.gen2.Save")
local Specials = require("src.script.gen2.Specials")

-- ---------------------------------------------------------------- fixtures

-- ../pokecrystal/data/pokemon/base_stats/*.asm, the five species group 1 of
-- BattleTowerMons opens with.
local POKEMON = {
  JOLTEON = { name = "JOLTEON", index = 135, types = { "ELECTRIC" },
    growthRate = "MEDIUM_FAST", levelMoves = {},
    baseStats = { hp = 65, attack = 65, defense = 60, speed = 130,
      specialAttack = 110, specialDefense = 95 } },
  ESPEON = { name = "ESPEON", index = 196, types = { "PSYCHIC_TYPE" },
    growthRate = "MEDIUM_FAST", levelMoves = {},
    baseStats = { hp = 65, attack = 65, defense = 60, speed = 110,
      specialAttack = 130, specialDefense = 95 } },
  UMBREON = { name = "UMBREON", index = 197, types = { "DARK" },
    growthRate = "MEDIUM_FAST", levelMoves = {},
    baseStats = { hp = 95, attack = 65, defense = 110, speed = 65,
      specialAttack = 60, specialDefense = 130 } },
  WOBBUFFET = { name = "WOBBUFFET", index = 202, types = { "PSYCHIC_TYPE" },
    growthRate = "MEDIUM_FAST", levelMoves = {},
    baseStats = { hp = 190, attack = 33, defense = 58, speed = 33,
      specialAttack = 33, specialDefense = 58 } },
  KANGASKHAN = { name = "KANGASKHAN", index = 115, types = { "NORMAL" },
    growthRate = "MEDIUM_FAST", levelMoves = {},
    baseStats = { hp = 105, attack = 95, defense = 80, speed = 90,
      specialAttack = 40, specialDefense = 80 } },
}

local MOVES = {
  THUNDERBOLT = { pp = 15 }, HYPER_BEAM = { pp = 5 }, SHADOW_BALL = { pp = 15 },
  ROAR = { pp = 20 }, MUD_SLAP = { pp = 10 }, PSYCHIC_M = { pp = 10 },
  PSYCH_UP = { pp = 10 }, TOXIC = { pp = 10 }, IRON_TAIL = { pp = 15 },
  COUNTER = { pp = 20 }, MIRROR_COAT = { pp = 20 }, SAFEGUARD = { pp = 25 },
  DESTINY_BOND = { pp = 5 }, REVERSAL = { pp = 15 }, EARTHQUAKE = { pp = 10 },
  ATTRACT = { pp = 15 },
}

-- ../pokecrystal/data/battle_tower/parties.asm:4-140, transcribed field for
-- field: the DVs, the stat exp words, the PP bytes and the stats the cart
-- copies straight into wOTPartyMon.
local function row(species, item, moves, pp, dvs, statExp, stats)
  return {
    species = species, item = item, moves = moves, pp = pp,
    level = 10, happiness = 100, experience = 1000, otId = 0,
    dvs = { attack = dvs[1], defense = dvs[2], speed = dvs[3],
      special = dvs[4] },
    statExp = { hp = statExp[1], attack = statExp[2], defense = statExp[3],
      speed = statExp[4], special = statExp[5] },
    hp = stats[1], maxHp = stats[1],
    stats = { hp = stats[1], attack = stats[2], defense = stats[3],
      speed = stats[4], specialAttack = stats[5], specialDefense = stats[6] },
  }
end

local GROUP1 = {
  row("JOLTEON", "MIRACLEBERRY",
    { "THUNDERBOLT", "HYPER_BEAM", "SHADOW_BALL", "ROAR" }, { 15, 5, 15, 20 },
    { 13, 13, 11, 13 }, { 50000, 40000, 40000, 35000, 40000 },
    { 41, 25, 24, 37, 34, 31 }),
  row("ESPEON", "LEFTOVERS",
    { "MUD_SLAP", "PSYCHIC_M", "PSYCH_UP", "TOXIC" }, { 10, 10, 10, 10 },
    { 14, 13, 15, 11 }, { 40000, 50000, 35000, 40000, 40000 },
    { 39, 26, 24, 35, 38, 31 }),
  row("UMBREON", "GOLD_BERRY",
    { "SHADOW_BALL", "IRON_TAIL", "PSYCH_UP", "TOXIC" }, { 15, 15, 10, 10 },
    { 13, 11, 14, 15 }, { 40000, 40000, 45000, 50000, 40000 },
    { 46, 25, 34, 26, 25, 39 }),
  row("WOBBUFFET", "FOCUS_BAND",
    { "COUNTER", "MIRROR_COAT", "SAFEGUARD", "DESTINY_BOND" },
    { 20, 20, 25, 5 }, { 7, 15, 13, 7 },
    { 50000, 50000, 50000, 50000, 50000 }, { 66, 18, 25, 19, 18, 23 }),
  -- MIRACLEBERRY again, which is the item collision the draw refuses.
  row("KANGASKHAN", "MIRACLEBERRY",
    { "REVERSAL", "HYPER_BEAM", "EARTHQUAKE", "ATTRACT" }, { 15, 5, 10, 15 },
    { 14, 15, 12, 15 }, { 40000, 30000, 40000, 30000, 30000 },
    { 47, 31, 29, 29, 20, 28 }),
}

-- ../pokecrystal/data/battle_tower/classes.asm:11-17
local ROSTER = {
  partyLength = 3,
  levelGroups = 2,
  uniqueMon = #GROUP1,
  uniqueTrainers = 4,
  sampleTrainers = 4,
  trainers = {
    { index = 0, name = "HANSON", class = 37, classId = "FISHER" },
    { index = 1, name = "SAWYER", class = 30, classId = "POKEMANIAC" },
    { index = 2, name = "MASUDA", class = 43, classId = "GUITARIST" },
    { index = 3, name = "NICKEL", class = 20, classId = "SCIENTIST" },
  },
  groups = { GROUP1, GROUP1 },
  classSprites = {
    FISHER = "SPRITE_FISHER", POKEMANIAC = "SPRITE_SUPER_NERD",
    GUITARIST = "SPRITE_ROCKER", SCIENTIST = "SPRITE_SCIENTIST",
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  trainers = {
    battleTower = ROSTER,
    classes = {
      FISHER = { index = 37, name = "FISHER", baseMoney = 40,
        attributes = { 0, 0, 40, 1, 0, 0, 0 }, items = {} },
      POKEMANIAC = { index = 30, name = "POKEMANIAC", baseMoney = 60,
        attributes = { 0, 0, 60, 1, 0, 0, 0 }, items = {} },
      GUITARIST = { index = 43, name = "GUITARIST", baseMoney = 36,
        attributes = { 0, 0, 36, 1, 0, 0, 0 }, items = {} },
      SCIENTIST = { index = 20, name = "SCIENTIST", baseMoney = 44,
        attributes = { 0, 0, 44, 1, 0, 0, 0 }, items = {} },
    },
  },
}

local function crystalSave(levelGroup)
  local save = Save.normalize({ version = "crystal", generation = 2 })
  save.battleTower.levelGroup = levelGroup or 1
  save.party = {}
  return save
end

-- A roll that walks a canned list, so every draw below is pinned.  Same
-- 1..n convention Specials.random uses.
local function rolls(list)
  local at = 0
  return function(n)
    at = at + 1
    local value = list[at] or 1
    if value > n then value = ((value - 1) % n) + 1 end
    return value
  end
end

local function fakeVm(save, hooks)
  local vm = {
    scriptVar = 0,
    mem = {},
    stringBuffer = "",
    specials = hooks or {},
  }
  vm.specials.save = vm.specials.save or function() return save end
  vm.specials.data = vm.specials.data or function() return DATA end
  vm.specials.party = vm.specials.party or function() return save.party end
  function vm:setStringBuffer(value) self.stringBuffer = value or "" end
  function vm:showRaw() end
  return vm
end

-- =========================================== the extractor's roster decode
--
-- A synthetic cartridge: BattleTowerTrainers, BattleTowerMons and
-- BTTrainerClassSprites laid out exactly as data/battle_tower/classes.asm,
-- parties.asm and data/trainers/sprites.asm assemble, plus the two
-- `maskbits N / cp N / jr nc` pairs load_trainer.asm samples with.
do
  local NAME_LENGTH, MON_NAME_LENGTH = 11, 11
  local NICKNAMED = 48 + MON_NAME_LENGTH
  local TRAINERS_AT, MONS_AT = 0x4100, 0x4100 + 3 * NAME_LENGTH
  local SPRITES_AT, TR_SAMPLE_AT, MON_SAMPLE_AT = 0x5000, 0x5100, 0x5200
  local bytes = {}
  local function put(offset, list)
    for index, value in ipairs(list) do bytes[offset + index] = value end
  end
  local function name(text, width)
    local out = {}
    for index = 1, width do
      out[index] = (index <= #text) and text:byte(index) or 0x50
    end
    return out
  end
  -- charmap rows for the letters the three names use.
  local charmap, letters = {}, "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  for index = 1, #letters do
    charmap[tostring(0x80 + index - 1)] = letters:sub(index, index)
  end
  local function encode(text, width)
    local out = {}
    for index = 1, width do
      if index <= #text then
        out[index] = 0x80 + (text:byte(index) - 65)
      else
        out[index] = 0x50
      end
    end
    return out
  end
  -- Three rows, the third exactly NAME_LENGTH - 1 long so the unterminated
  -- name the `dname` macro leaves (classes.asm:16 ZABOROWSKI) is covered.
  local rows = { { "ABLE", 1 }, { "BAKER", 2 }, { "CDEFGHIJKL", 3 } }
  for index, entry in ipairs(rows) do
    local at = TRAINERS_AT + (index - 1) * NAME_LENGTH
    put(at, encode(entry[1], NAME_LENGTH - 1))
    bytes[at + NAME_LENGTH] = entry[2]
  end
  -- One level group of two mons.  Only the fields the reader names are set;
  -- everything else stays 0, which is what ByteFill leaves.
  local function monBytes(species, item, moves, pp, dv1, dv2, level, stats)
    local raw = {}
    for index = 1, NICKNAMED do raw[index] = 0 end
    raw[1] = species
    raw[2] = item
    for slot = 1, 4 do raw[2 + slot] = moves[slot] or 0 end
    raw[9], raw[10], raw[11] = 0, 0x03, 0xe8
    raw[12], raw[13] = 0xc3, 0x50
    raw[22], raw[23] = dv1, dv2
    for slot = 1, 4 do raw[23 + slot] = pp[slot] or 0 end
    raw[28] = 100
    raw[32] = level
    raw[35], raw[36] = 0, stats[1]
    raw[37], raw[38] = 0, stats[1]
    raw[39], raw[40] = 0, stats[2]
    raw[41], raw[42] = 0, stats[3]
    raw[43], raw[44] = 0, stats[4]
    raw[45], raw[46] = 0, stats[5]
    raw[47], raw[48] = 0, stats[6]
    return raw
  end
  put(MONS_AT, monBytes(135, 109, { 85, 63, 247, 46 }, { 15, 5, 15, 20 },
    0xdd, 0xbd, 10, { 41, 25, 24, 37, 34, 31 }))
  put(MONS_AT + NICKNAMED, monBytes(196, 78, { 189, 94, 0, 0 }, { 10, 10, 0, 0 },
    0xed, 0xfb, 10, { 39, 26, 24, 35, 38, 31 }))
  put(SPRITES_AT, { 7, 9, 11 })
  -- `and $03 / cp 3 / jr nc, .resample` and `and $01 / cp 2 / jr nc`.
  put(TR_SAMPLE_AT, { 0xcd, 0x8c, 0x2f, 0xf0, 0xe1, 0x80, 0x47,
    0xe6, 0x03, 0xfe, 0x03, 0x30, 0xf3 })
  put(MON_SAMPLE_AT, { 0xcd, 0x8c, 0x2f, 0xf0, 0xe1, 0x80, 0x47,
    0xe6, 0x01, 0xfe, 0x02, 0x30, 0xf3 })

  local rom = {}
  for index = 1, 0x8000 do rom[index] = string.char(bytes[index] or 0) end
  local manifest = {
    romSha1 = "",
    charmap = charmap,
    constants = {
      trainerClassOrder = { "TRAINER_NONE", "FALKNER", "WHITNEY", "BUGSY",
        "MYSTICALMAN" },
      spriteOrder = { "SPRITE_A", "SPRITE_B", "SPRITE_C", "SPRITE_D",
        "SPRITE_E", "SPRITE_F", "SPRITE_G", "SPRITE_H", "SPRITE_I",
        "SPRITE_J", "SPRITE_K" },
      moveOrder = {}, itemOrder = {}, speciesOrder = {},
    },
    symbols = {
      BattleTowerTrainers = { 1, TRAINERS_AT },
      BattleTowerMons = { 1, MONS_AT },
      BTTrainerClassSprites = { 1, SPRITES_AT },
      ["LoadOpponentTrainerAndPokemon.resample"] = { 1, TR_SAMPLE_AT },
      ["LoadRandomBattleTowerMon.resample"] = { 1, MON_SAMPLE_AT },
    },
  }
  manifest.constants.speciesOrder[135] = "JOLTEON"
  manifest.constants.speciesOrder[196] = "ESPEON"
  manifest.constants.itemOrder[109] = "MIRACLEBERRY"
  manifest.constants.itemOrder[78] = "LEFTOVERS"
  manifest.constants.moveOrder[85] = "THUNDERBOLT"
  manifest.constants.moveOrder[63] = "HYPER_BEAM"
  manifest.constants.moveOrder[247] = "SHADOW_BALL"
  manifest.constants.moveOrder[46] = "ROAR"
  manifest.constants.moveOrder[189] = "MUD_SLAP"
  manifest.constants.moveOrder[94] = "PSYCHIC_M"

  local ex = RomExtractorGen2.new(table.concat(rom), manifest, nil)
  local read = ex:readBattleTowerRoster(manifest.constants, charmap)
  check(read ~= nil, "the roster reads out of the cartridge")
  eq(read.uniqueTrainers, 3, "the trainer count is the gap to BattleTowerMons")
  eq(read.uniqueMon, 2, "NUM_UNIQUE_MON comes off the mon resample loop")
  eq(read.sampleTrainers, 3,
    "and the trainer ceiling off its own, which Crystal 1.0 gets wrong")
  eq(read.trainers[1].name, "ABLE", "a terminated name stops at '@'")
  eq(read.trainers[3].name, "CDEFGHIJKL",
    "and a full-width one runs to NAME_LENGTH - 1 with no terminator")
  eq(read.trainers[2].classId, "WHITNEY", "the class byte resolves to a name")
  eq(read.classSprites.FALKNER, "SPRITE_G", "class 1 takes the first sprite")
  eq(read.classSprites.BUGSY, "SPRITE_K", "class 3 the third")
  eq(read.classSprites.MYSTICALMAN, nil,
    "and MYSTICALMAN is off the end of BTTrainerClassSprites")
  eq(#read.groups, 10, "ten level groups are always read")
  local first = read.groups[1][1]
  eq(first.species, "JOLTEON", "group 1 mon 1 species")
  eq(first.item, "MIRACLEBERRY", "its held item")
  eq(first.level, 10, "its level")
  eq(first.happiness, 100, "its happiness")
  eq(first.experience, 1000, "its three exp bytes, big-endian")
  eq(first.statExp.hp, 50000, "its HP stat exp word")
  eq(first.dvs.attack, 13, "attack DV out of the high nibble")
  eq(first.dvs.defense, 13, "defense DV out of the low nibble")
  eq(first.dvs.speed, 11, "speed DV")
  eq(first.dvs.special, 13, "special DV")
  eq(#first.moves, 4, "four moves")
  eq(first.moves[3], "SHADOW_BALL", "move three")
  eq(first.pp[2], 5, "and its PP byte")
  eq(first.maxHp, 41, "the stored max HP")
  eq(first.stats.speed, 37, "and the stored Speed")
  local second = read.groups[1][2]
  eq(#second.moves, 2, "a row with two NO_MOVE slots keeps two moves")
  eq(#second.pp, 2, "and two PP bytes")
end

-- =========================== Mon.stats agrees with the cart's stored stats
--
-- ../pokecrystal/engine/pokemon/move_mon.asm CalcMonStats is what produced the
-- bytes in parties.asm, so the port's own formula has to land on them.
do
  for _, mon in ipairs(GROUP1) do
    local dvs = { attack = mon.dvs.attack, defense = mon.dvs.defense,
      speed = mon.dvs.speed, special = mon.dvs.special }
    local stats = Mon.stats(POKEMON[mon.species].baseStats, dvs, mon.level,
      mon.statExp)
    eq(stats.hp, mon.stats.hp, mon.species .. " HP matches the ROM")
    eq(stats.attack, mon.stats.attack, mon.species .. " Attack matches")
    eq(stats.defense, mon.stats.defense, mon.species .. " Defense matches")
    eq(stats.speed, mon.stats.speed, mon.species .. " Speed matches")
    eq(stats.specialAttack, mon.stats.specialAttack,
      mon.species .. " Sp.Atk matches")
    eq(stats.specialDefense, mon.stats.specialDefense,
      mon.species .. " Sp.Def matches")
  end
end

-- ================================================ roster lookup and gating
do
  eq(BattleTower.roster(DATA), ROSTER, "the roster comes off trainers.lua")
  eq(BattleTower.roster({ trainers = {} }), nil,
    "a Gold cache has no battleTower block")
  eq(BattleTower.roster({ trainers = { battleTower = { trainers = {} } } }), nil,
    "and half a block is not one either")

  local save = crystalSave(0)
  eq(BattleTower.opponentGroup(save, ROSTER), 1,
    "a level group of 0 cannot index before the table")
  save.battleTower.levelGroup = 9
  eq(BattleTower.opponentGroup(save, ROSTER), 2,
    "nor past the last group the roster carries")
  save.battleTower.levelGroup = 2
  eq(BattleTower.opponentGroup(save, ROSTER), 2, "a real group is kept")
end

-- ============================================== the trainer draw and sBTTrainers
do
  local save = crystalSave()
  local trainer = BattleTower.chooseTrainer(save, ROSTER, rolls({ 2 }))
  eq(trainer.name, "SAWYER", "the second row is drawn")
  eq(save.battleTower.trainers[1], 1,
    "and recorded in sBTTrainers[sNrOfBeatenBattleTowerTrainers]")

  -- ../pokecrystal/engine/events/battle_tower/load_trainer.asm:44-51: the
  -- streak list is what the reroll refuses.
  save.battleTower.streak = 1
  local again = BattleTower.chooseTrainer(save, ROSTER, rolls({ 2 }))
  check(again.name ~= "SAWYER", "a trainer already in the streak is refused")
  eq(save.battleTower.trainers[2], again.index,
    "and the new one lands in the next slot")

  -- :29-37, Crystal 1.0's ceiling: with sampleTrainers 2 only the first two
  -- rows can ever come out, however the roll lands.
  local capped = { partyLength = 3, levelGroups = 1, uniqueMon = #GROUP1,
    uniqueTrainers = 4, sampleTrainers = 2, trainers = ROSTER.trainers,
    groups = { GROUP1 }, classSprites = ROSTER.classSprites }
  local seen = {}
  for roll = 1, 8 do
    local fresh = crystalSave()
    seen[BattleTower.chooseTrainer(fresh, capped, rolls({ roll })).index] = true
  end
  eq(seen[2], nil, "row 2 is past the 1.0 ceiling and never drawn")
  eq(seen[3], nil, "nor row 3")
  check(seen[0] and seen[1], "the first two rows both are")
end

-- ================================================== the three-mon team draw
do
  local save = crystalSave()
  local team = BattleTower.chooseTeam(save, ROSTER, 1, rolls({ 1, 1, 1 }))
  eq(#team, 3, "three mons come out")
  eq(team[1].species, "JOLTEON", "the first roll takes the first row")
  -- :131-136, the species and item collisions: JOLTEON is out, and so is
  -- KANGASKHAN, which holds JOLTEON's MIRACLEBERRY.
  eq(team[2].species, "ESPEON",
    "the second roll skips the species already picked")
  eq(team[3].species, "UMBREON", "and so does the third")
  local held = {}
  for _, mon in ipairs(team) do
    eq(held[mon.item], nil, mon.species .. " brings an unheld item")
    held[mon.item] = true
  end

  -- :149-166 and :195-206: the last two teams' species are refused too.
  eq(save.battleTower.prevTeams.prev[1], "JOLTEON",
    "the drawn team becomes sBTMonPrevTrainer")
  eq(#save.battleTower.prevTeams.prevPrev, 0,
    "with nothing displaced into sBTMonPrevPrevTrainer yet")
  local second = BattleTower.chooseTeam(save, ROSTER, 1, rolls({ 1, 1, 1 }))
  eq(second[1].species, "WOBBUFFET", "the next team skips the previous one")
  eq(second[2].species, "KANGASKHAN", "and keeps skipping it")
  eq(save.battleTower.prevTeams.prevPrev[1], "JOLTEON",
    "and the old team shifts down to sBTMonPrevPrevTrainer")

  -- Five rows cannot field three fresh species twice running, which is
  -- exactly where the cart's `jr z, .FindARandomBattleTowerMon` would spin
  -- forever: the port takes the unfiltered draw instead and still hands back
  -- a full team.  Twenty-one rows never reach it.
  eq(#second, 3, "an exhausted pool still fields three rather than hanging")
  eq(second[3].species, "JOLTEON", "the third falls back to a plain roll")
end

-- ============================================== the party the battle fights
do
  local party = BattleTower.battleParty(DATA, { GROUP1[1], GROUP1[3] })
  eq(#party, 2, "one battle mon per roster row")
  local jolteon = party[1]
  eq(jolteon.species, "JOLTEON", "species")
  eq(jolteon.name, "JOLTEON", "and the species name, not the ROM nickname")
  eq(jolteon.nickname, nil, "which is why no nickname is carried")
  eq(jolteon.level, 10, "level")
  eq(jolteon.item, "MIRACLEBERRY", "held item")
  eq(jolteon.happiness, 100, "happiness")
  eq(jolteon.maxHp, 41, "max HP off the stored bytes")
  eq(jolteon.hp, 41, "at full")
  eq(jolteon.stats.speed, 37, "stored Speed")
  eq(jolteon.stats.specialDefense, 31, "stored Sp.Def")
  eq(jolteon.dvs.attack, 13, "the row's own DVs, not a roll")
  eq(#jolteon.moves, 4, "four moves")
  eq(jolteon.moves[2].id, "HYPER_BEAM", "move two")
  eq(jolteon.moves[2].pp, 5, "with the row's PP")
  eq(jolteon.moves[2].maxPp, 5, "and the move's own maximum")
  eq(party[2].species, "UMBREON", "and the second row follows")
  -- Mon.new mutates the dvs table it is handed, so a second build has to see
  -- the roster row untouched.
  local again = BattleTower.battleParty(DATA, { GROUP1[1] })
  eq(again[1].stats.attack, 25, "a second build reads the same row")
  eq(GROUP1[1].dvs.hp, nil, "and leaves the roster row alone")
end

-- ============================== LoadOpponentTrainerAndPokemonWithOTSprite
do
  local painted = {}
  local save = crystalSave()
  local vm = fakeVm(save, {
    setObjectSprite = function(object, sprite)
      painted[#painted + 1] = { object = object, sprite = sprite }
    end,
  })
  vm.scriptVar = 2
  Specials.random = rolls({ 1, 1, 1, 1 })
  Specials.ALL.LoadOpponentTrainerAndPokemonWithOTSprite(vm)
  eq(vm.scriptVar, 2, "wScriptVar still names the object, unwritten")
  check(vm.btOpponent ~= nil, "the opponent is drawn onto the VM")
  eq(vm.btOpponent.name, "HANSON", "the trainer's own name")
  eq(vm.btOpponent.classId, "FISHER", "its class")
  eq(#vm.btOpponent.rows, 3, "with three mons")
  eq(#painted, 1, "the map object is repainted once")
  eq(painted[1].object, 2, "the object wScriptVar named")
  eq(painted[1].sprite, "SPRITE_FISHER",
    "with BTTrainerClassSprites[class - 1]")
  eq(save.battleTower.streak, 0, "the draw does not step the streak")

  -- A save is all it needs; a world with no sprite hook still draws.
  local bare = crystalSave()
  local plain = fakeVm(bare, {})
  Specials.random = rolls({ 1, 1, 1, 1 })
  Specials.ALL.LoadOpponentTrainerAndPokemonWithOTSprite(plain)
  check(plain.btOpponent ~= nil, "and the draw survives a missing hook")

  -- A cache with no roster leaves nothing behind rather than half an opponent.
  local goldVm = fakeVm(crystalSave(), { data = function() return {} end })
  Specials.ALL.LoadOpponentTrainerAndPokemonWithOTSprite(goldVm)
  eq(goldVm.btOpponent, nil, "a cache with no roster draws nobody")
end

-- ============================================================ BattleTowerBattle
local function towerBattle(save, outcome, extra)
  local log = { heals = 0, started = nil }
  local hooks = {
    healParty = function() log.heals = log.heals + 1 end,
    startTowerBattle = function(spec, done)
      log.started = spec
      log.healsAtStart = log.heals
      done(outcome)
      return true
    end,
  }
  for key, value in pairs(extra or {}) do hooks[key] = value end
  local vm = fakeVm(save, hooks)
  Specials.random = rolls({ 1, 1, 1, 1 })
  Specials.ALL.LoadOpponentTrainerAndPokemonWithOTSprite(vm)
  Specials.ALL.BattleTowerBattle(vm)
  return vm, log
end

do
  local save = crystalSave()
  local vm, log = towerBattle(save, "win")
  -- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:236-237
  eq(vm.scriptVar, 0, "a win leaves wBattleResult 0 in wScriptVar")
  eq(log.heals, 2, ":228 and :235, HealParty on both sides of the battle")
  eq(log.healsAtStart, 1, "the first one before the send-out")
  check(log.started ~= nil, "the battle was started")
  eq(log.started.name, "FISHER HANSON", "named class-then-trainer")
  eq(log.started.trainerName, "HANSON", "with the bare name kept")
  eq(log.started.classId, "FISHER", "and the class key the pic reads")
  eq(log.started.class, 37, "and its constant")
  eq(log.started.baseMoney, 40, "the class's own payout multiplier")
  eq(#log.started.party, 3, "three mons walk in")
  eq(log.started.party[1].species, "JOLTEON", "the drawn team, built")
  eq(log.started.party[1].maxHp, 41, "with the roster's stats")

  -- :549-570 CopyBTTrainer, which is what steps the counter.
  eq(save.battleTower.streak, 1, "the streak steps once")
  eq(save.battleTower.challenge, BattleTower.CHALLENGE_IN_PROGRESS,
    "and the challenge is now in progress")
  -- :240-250, the byte maps/BattleTowerBattleRoom.asm:38 reads back.
  eq(vm.mem[BattleTower.WRAM_NR_BEATEN], 1,
    "wNrOfBeatenBattleTowerTrainers holds the new count")
  eq(vm.stringBuffer, "2", "and wStringBuffer3 the NEXT opponent's number")
  eq(vm.btBattleEnded, 1, "wBattleTowerBattleEnded ends the loop")
  eq(vm.btOpponent, nil, "and the drawn opponent is spent")
end

do
  local save = crystalSave()
  save.battleTower.streak = 6
  local vm = towerBattle(save, "win")
  eq(save.battleTower.streak, 7, "the seventh win reaches BATTLETOWER_STREAK_LENGTH")
  eq(vm.mem[BattleTower.WRAM_NR_BEATEN], 7,
    "which is what the room script's `ifequal 7` reads")
end

do
  local save = crystalSave()
  local vm, log = towerBattle(save, "lose")
  eq(vm.scriptVar, 1, "a loss leaves wBattleResult 1")
  eq(log.heals, 2, "and still heals on both sides")
  eq(vm.mem[BattleTower.WRAM_NR_BEATEN], nil,
    ":238-239 skips the counter copy when the battle was lost")
  eq(vm.stringBuffer, "", "and prints no next-opponent number")
  eq(save.battleTower.streak, 1,
    "the counter still stepped, because ReadBTTrainerParty ran")
end

do
  -- No hook at all: the challenge has to END rather than loop on an opponent
  -- that never appears.
  local save = crystalSave()
  local vm = fakeVm(save, {})
  Specials.random = rolls({ 1, 1, 1, 1 })
  Specials.ALL.BattleTowerBattle(vm)
  eq(vm.scriptVar, 1, "an unwired world reports a loss")
  eq(vm.btBattleEnded, 1, "and ends the tower loop")

  local goldVm = fakeVm(crystalSave(), { data = function() return {} end })
  Specials.ALL.BattleTowerBattle(goldVm)
  eq(goldVm.scriptVar, 1, "so does a cache with no roster")
end

do
  -- The special draws its own opponent when the room script never loaded one.
  local save = crystalSave()
  local log
  local vm = fakeVm(save, {
    healParty = function() end,
    startTowerBattle = function(spec, done) log = spec; done("win"); return true end,
  })
  Specials.random = rolls({ 1, 1, 1, 1 })
  Specials.ALL.BattleTowerBattle(vm)
  check(log ~= nil and #log.party == 3,
    "BattleTowerBattle alone still fields an opponent")
end

-- ============================================ InitBattleTowerChallengeRAM
do
  local save = crystalSave()
  local vm = fakeVm(save, { pushScreen = function() return false end })
  vm.mem[BattleTower.WRAM_NR_BEATEN] = 4
  Specials.ALL.BattleTowerRoomMenu(vm)
  eq(vm.mem[BattleTower.WRAM_NR_BEATEN], 0,
    ":193 zeroes wNrOfBeatenBattleTowerTrainers with the rest")
  eq(vm.btBattleEnded, 0, "and wBattleTowerBattleEnded with it")
end

Specials.random = math.random

S.finish()
