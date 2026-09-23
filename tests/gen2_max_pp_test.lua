-- engine/items/item_effects.asm:2752, :2801, :2836

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 max pp")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Boxes = require("src.core.gen2.Boxes")
local Breeding = require("src.core.gen2.Breeding")
local ItemEffects = require("src.core.gen2.ItemEffects")
local Mon = require("src.battle.gen2.Mon")
local World = require("src.world.gen2.World")

local MOVES = {
  WATER_GUN = { id = "WATER_GUN", name = "WATER GUN", pp = 25 },
  RAGE = { id = "RAGE", name = "RAGE", pp = 20 },
  LEER = { id = "LEER", name = "LEER", pp = 30 },
  SCRATCH = { id = "SCRATCH", name = "SCRATCH", pp = 35 },
  MEAN_LOOK = { id = "MEAN_LOOK", name = "MEAN LOOK", pp = 5 },
  GROWL = { id = "GROWL", name = "GROWL", pp = 40 },
  SKETCH = { id = "SKETCH", name = "SKETCH", pp = 1 },
}

local POKEMON = {
  growthRates = {
    GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
      linear = 0, constant = 0 },
  },
  TOTODILE = {
    id = "TOTODILE", index = 158, dex = 158, name = "TOTODILE",
    baseStats = { hp = 50, attack = 65, defense = 64, speed = 43,
      specialAttack = 44, specialDefense = 48 },
    types = { "WATER", "WATER" }, growthRate = "GROWTH_MEDIUM_FAST",
    genderRatio = 31, eggGroups = { "EGG_MONSTER", "EGG_WATER_1" },
    evolutions = {}, levelMoves = { { level = 1, move = "SCRATCH" } },
    tmhm = {},
  },
}

local DATA = { pokemon = POKEMON, moves = MOVES, items = {} }

local function broken()
  return {
    { id = "LEER", pp = 30, maxPp = 30 },
    { id = "SCRATCH", pp = 35, maxPp = 35 },
    { id = "RAGE", pp = 9 },
    { id = "WATER_GUN", pp = 1 },
  }
end

local function toto(moves)
  local mon = Mon.new(DATA, "TOTODILE", 16, {
    dvs = { attack = 10, defense = 10, speed = 10, special = 10 },
    moves = moves or broken(),
  })
  mon.hp = 1
  return mon
end

do
  eq(Mon.maxPpOf({ id = "WATER_GUN", pp = 1 }, DATA), 25,
    "a record with no maxPp reads the move's base PP")
  eq(Mon.maxPpOf({ id = "WATER_GUN", pp = 1, maxPp = 1 }, DATA), 25,
    "a stored max below base cannot lower it")
  eq(Mon.maxPpOf({ id = "WATER_GUN", pp = 3, maxPp = 30 }, DATA), 30,
    "a stored max one PP Up above base keeps that PP Up")
  eq(Mon.maxPpOf({ id = "WATER_GUN", pp = 3, maxPp = 31 }, DATA), 25,
    "a stored max ComputeMaxPP cannot produce infers no PP Up")
  eq(Mon.maxPpOf({ id = "GROWL", pp = 0, ppUps = 3 }, DATA), 61,
    "three PP Ups on a 40 PP move cap at 61")
  eq(Mon.maxPpOf({ id = "GROWL", pp = 0, ppUps = 9 }, DATA), 61,
    "the PP Up count is two bits")
  eq(Mon.maxPpOf({ id = "MEAN_LOOK", pp = 4, maxPp = 4 }, DATA), 5,
    "MEAN LOOK 4/4 reads 5")
  eq(Mon.maxPpOf({ id = "SKETCH", pp = 1, ppUps = 3 }, DATA), 1,
    "a 1 PP move gains nothing per PP Up")
  eq(Mon.ppUpsOf({ id = "WATER_GUN", maxPp = 40 }, DATA), 3,
    "ppUpsOf infers three from a stored 40 on a 25 PP move")
end

do
  local mon = toto()
  local save = { party = { mon } }
  World.healParty({ game = { save = save, data = DATA } })
  eq(mon.moves[3].pp, 20, "HealParty refills RAGE to 20, not 9")
  eq(mon.moves[4].pp, 25, "HealParty refills WATER GUN to 25, not 1")
  eq(mon.moves[4].maxPp, 25, "and writes the derived max back")
  eq(mon.hp, mon.maxHp, "HP is still refilled")
end

do
  local keep = toto()
  keep.hp = keep.maxHp
  local mon = toto()
  local save = { party = { keep, mon }, boxes = {}, boxNames = {},
    currentBox = 1 }
  local ok = Boxes.deposit(save, 2, 1, DATA)
  check(ok, "the deposit went through")
  eq(mon.moves[3].pp, 20, "RestorePPOfDepositedPokemon refills RAGE to 20")
  eq(mon.moves[4].pp, 25, "and WATER GUN to 25")

  local caught = toto()
  Boxes.enterBox(caught, DATA)
  eq(caught.moves[4].pp, 25, "enterBox with data refills from the move table")
end

do
  local mon = toto()
  mon.moves[4].pp = 0
  local res = ItemEffects.usePpItem("ETHER", mon, 4, DATA)
  check(res.used, "an ETHER on a spent maxPp-less move is not refused")
  eq(mon.moves[4].pp, 10, "and adds 10")
  res = ItemEffects.usePpItem("MAX_ETHER", mon, 4, DATA)
  check(res.used, "MAX ETHER still has room")
  eq(mon.moves[4].pp, 25, "and fills to 25")

  local full = toto()
  full.moves[3].pp, full.moves[4].pp = 20, 25
  res = ItemEffects.usePpItem("MAX_ELIXER", full, nil, DATA)
  eq(res.used, false, "MAX ELIXER on a full moveset is refused")
end

do
  local mon = toto({ { id = "WATER_GUN", pp = 30, maxPp = 30 } })
  local res = ItemEffects.usePpItem("PP_UP", mon, 1, DATA)
  check(res.used, "PP UP on a move with one inferred PP Up works")
  eq(mon.moves[1].ppUps, 2, "and counts from the inferred one")
  eq(mon.moves[1].maxPp, 35, "to 35")
  local maxed = toto({ { id = "WATER_GUN", pp = 40, maxPp = 40 } })
  res = ItemEffects.usePpItem("PP_UP", maxed, 1, DATA)
  eq(res.used, false, "a stored 40 on a 25 PP move is already maxed")
end

do
  local save = { party = {}, player = { name = "KRIS", id = 1, money = 3000 },
    pokedex = { seen = {}, caught = {} }, events = {} }
  local dc = Breeding.dayCare(save)
  dc.man.mon = toto()
  local ok, back = Breeding.withdraw(DATA, save, "man")
  check(ok, "the Day-Care withdrawal went through")
  eq(back.moves[4].pp, 25, "HealPartyMon refills WATER GUN to 25, not nil")
  eq(back.moves[3].pp, 20, "and RAGE to 20")
end

do
  local party = toto()
  local boxed = toto()
  local daycare = toto()
  local legacy = toto({ { id = "WATER_GUN" }, { id = "RAGE", pp = 50 } })
  local upped = toto({ { id = "WATER_GUN", pp = 12, maxPp = 35 } })
  local save = { party = { party, legacy, upped }, boxes = { { boxed } },
    dayCare = { man = { mon = daycare }, lady = {} } }
  Mon.syncSaveIdentity(save, DATA)
  eq(party.moves[4].maxPp, 25, "the party's WATER GUN gets its max back")
  eq(party.moves[4].pp, 1, "and keeps the PP it had left")
  eq(party.moves[3].maxPp, 20, "RAGE gets 20")
  eq(boxed.moves[4].maxPp, 25, "boxed mons are repaired too")
  eq(daycare.moves[4].maxPp, 25, "and the Day-Care's")
  eq(legacy.moves[1].pp, 25, "a record with no PP at all reads full")
  eq(legacy.moves[2].pp, 20, "and PP past max is clamped")
  eq(upped.moves[1].maxPp, 35, "a real PP Up max survives the repair")
  eq(upped.moves[1].pp, 12, "with its current PP")
end

do
  local BoxMenu = require("src.ui.gen2.BoxMenu")
  local BugContest = require("src.core.gen2.BugContest")
  local game = { data = DATA, input = { wasPressed = function() return false end,
    isDown = function() return false end } }

  local keep = toto()
  keep.hp = keep.maxHp
  local mon = toto()
  local save = { party = { keep, mon }, boxes = {}, boxNames = {},
    currentBox = 1 }
  game.save = save
  local menu = BoxMenu.new(game, { save = save, mode = "deposit",
    onClose = function() end })
  menu.index = 2
  menu:doDeposit()
  eq(Boxes.box(save, 1)[1], mon, "the PC DEPOSIT went through")
  eq(mon.moves[4].pp, 25, "PC DEPOSIT refills WATER GUN to 25")
  eq(mon.moves[3].pp, 20, "and RAGE to 20")

  keep = toto()
  keep.hp = keep.maxHp
  mon = toto()
  save = { party = { keep, mon }, boxes = {}, boxNames = {}, currentBox = 1 }
  game.save = save
  menu = BoxMenu.new(game, { save = save, mode = "move",
    onClose = function() end })
  menu.moveFrom = { box = 0, slot = 2 }
  menu.boxIndex, menu.index = 1, 1
  menu:insertMon()
  eq(Boxes.box(save, 1)[1], mon, "MOVE party -> box went through")
  eq(mon.moves[4].pp, 25, "MOVE into a box refills WATER GUN to 25")

  save = { party = { toto(), toto(), toto(), toto(), toto(), toto() },
    boxes = {}, boxNames = {}, currentBox = 2, playerName = "KRIS" }
  BugContest.start(save)
  local caught = toto()
  BugContest.switchCaught(save, caught)
  local result = BugContest.collectCaughtMon(save, 6, nil, DATA)
  eq(result, BugContest.BOXED_MON, "a full party boxes the contest catch")
  eq(caught.moves[4].pp, 25, "the boxed contest catch has WATER GUN at 25")
  eq(caught.moves[3].pp, 20, "and RAGE at 20")
end

-- engine/items/item_effects.asm:2381
do
  local Battle = require("src.battle.gen2.Battle")
  local TDATA = {
    moves = {
      TRANSFORM = { id = "TRANSFORM", name = "TRANSFORM", pp = 10 },
      TACKLE = { id = "TACKLE", name = "TACKLE", pp = 35 },
      ROCK_THROW = { id = "ROCK_THROW", name = "ROCK THROW", pp = 15 },
    },
    pokemon = {
      DITTO = { id = "DITTO", name = "DITTO", types = { "NORMAL", "NORMAL" } },
      GEODUDE = { id = "GEODUDE", name = "GEODUDE", types = { "ROCK", "GROUND" } },
    },
    items = {},
  }
  local function transformed(transformPp)
    local ditto = { species = "DITTO", hp = 30, maxHp = 30, stats = {},
      moves = { { id = "TRANSFORM", pp = transformPp or 10, maxPp = 10 } } }
    local geodude = { species = "GEODUDE", hp = 30, maxHp = 30, stats = {},
      moves = { { id = "TACKLE", pp = 35, maxPp = 35 },
                { id = "ROCK_THROW", pp = 15, maxPp = 15 } } }
    local b = setmetatable({ data = TDATA, events = {} }, Battle)
    b.player, b.enemy = ditto, geodude
    Battle.MOVE_EFFECTS.EFFECT_TRANSFORM(b, ditto, geodude)
    return ditto
  end

  local d = transformed()
  d.moves[1].pp = 0
  local r = ItemEffects.usePpItem("ETHER", d, 1, TDATA)
  eq(r.used, false, "ETHER on a transformed mon with a full TRANSFORM is refused")
  eq(d.moves[1].pp, 0, "ETHER leaves the spent TACKLE copy alone")
  eq(d.moves[1].maxPp, 5, "the TACKLE copy keeps its 5 max")

  d = transformed()
  r = ItemEffects.usePpItem("MAX_ETHER", d, 1, TDATA)
  eq(r.used, false, "MAX ETHER is refused while TRANSFORM is full")
  eq(d.moves[1].pp, 5, "the full TACKLE copy stays 5/5")

  d = transformed()
  d.moves[2].pp = 0
  r = ItemEffects.usePpItem("ELIXER", d, nil, TDATA)
  eq(r.used, false, "ELIXER is refused while the party moves are full")
  eq(d.moves[1].pp, 5, "ELIXER leaves TACKLE's copy at 5")
  eq(d.moves[2].pp, 0, "ELIXER leaves ROCK THROW's copy at 0")

  d = transformed(2)
  r = ItemEffects.usePpItem("ETHER", d, 1, TDATA)
  eq(r.used, true, "ETHER lands on the party TRANSFORM")
  eq(d.volatile.preTransform.moves[1].pp, 10, "TRANSFORM refilled to 10")
  eq(d.moves[1].pp, 5, "the TACKLE copy is untouched")
  eq(Mon.partyMoves(d)[1].id, "TRANSFORM", "party move list is Ditto's own")
end

do
  local move = { id = "RAGE", pp = 20, maxPp = 32 }
  Mon.repairMoves({ moves = { move } }, DATA)
  eq(move.ppUps, 3, "repairMoves stamps inferred PP Ups")
  eq(move.maxPp, 32, "and keeps the 32 max")
  local plain = { id = "RAGE", pp = 20, maxPp = 20 }
  Mon.repairMoves({ moves = { plain } }, DATA)
  eq(plain.ppUps, nil, "no PP Ups leaves ppUps unset")
  local growl = { id = "GROWL", pp = 1, maxPp = 54 }
  eq(Mon.ppUpsOf(growl, DATA), 2, "GROWL 54 max infers 2 ups at 7 per up")
end

S.finish()
