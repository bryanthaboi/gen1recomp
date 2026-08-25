-- A script-gifted mon registers in the #DEX.  GiveShuckle
-- (engine/events/shuckle.asm:14) hands its mon to TryAddMonToParty, whose
-- PARTYMON arm falls into .registerpokedex / SetSeenAndCaughtMon
-- (engine/pokemon/move_mon.asm:179-197), so Mania's SHUCKIE arrives already
-- ticked off.  #1719.  ROM-free:
--   luajit tests/gen2_dex_gift_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 dex gift")
local check, eq, same = S.check, S.eq, S.same

love = require("tests.love_stub")

local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")
local Specials = require("src.script.gen2.Specials")
local Breeding = require("src.core.gen2.Breeding")
local Save = require("src.core.gen2.Save")

-- constants/pokemon_constants.asm: SHUCKLE is 213.
local SHUCKLE_INDEX = 213

-- Just enough of data.pokemon / data.moves for Mon.new to build a SHUCKLE,
-- plus one other species so the "index, not name" mistake has something to
-- collide with.
local function fixture()
  return {
    pokemon = {
      SHUCKLE = { name = "SHUCKLE", index = SHUCKLE_INDEX,
        growthRate = "MEDIUM_FAST",
        types = { "BUG", "ROCK" },
        baseStats = { hp = 20, attack = 10, defense = 230, speed = 5,
          specialAttack = 10, specialDefense = 230 },
        levelMoves = { { level = 1, move = "CONSTRICT" } } },
      TOTODILE = { name = "TOTODILE", index = 158,
        growthRate = "MEDIUM_SLOW",
        types = { "WATER", "WATER" },
        baseStats = { hp = 50, attack = 65, defense = 64, speed = 43,
          specialAttack = 44, specialDefense = 48 },
        levelMoves = { { level = 1, move = "SCRATCH" } } },
    },
    moves = {
      CONSTRICT = { name = "CONSTRICT", pp = 35 },
      SCRATCH = { name = "SCRATCH", pp = 35 },
    },
    items = {},
  }
end

-- The three hooks GiveShuckle reads out of World:specialHooks: the party it
-- appends to, the save it flags the dex on, and the data Mon.new builds from.
local function giftVm(record)
  record.party = record.party or {}
  return Vm.new({}, {}, Events.new(), { specials = {
    party = function() return record.party end,
    save = function() return record end,
    data = fixture,
  } })
end

-- ---- the gift itself ------------------------------------------------------
local giftedDex
do
  local record = { party = {} }
  Specials.HANDLERS.GiveShuckle(giftVm(record))

  eq(#record.party, 1, "Mania's SHUCKIE joins the party")
  local mon = record.party[1]
  eq(mon.nickname, "SHUCKIE", "under its own nickname")

  local dex = record.pokedex or {}
  eq((dex.seen or {})[mon.species], true, "and it is SEEN in the #DEX")
  eq((dex.caught or {})[mon.species], true,
    "and CAUGHT: SetSeenAndCaughtMon sets both flags, not just the one")
  eq((dex.caught or {})[SHUCKLE_INDEX], nil,
    "keyed by the species name PokedexMenu:rebuild looks up, not by dex number")
  local summary = Save.summary(record)
  eq(summary and summary.caught, 1,
    "so the CONTINUE panel's own count agrees (Save.lua:910-913)")
  giftedDex = record.pokedex
end

-- The handler must leave wScriptVar TRUE, because ManiasHouse.asm branches on
-- it to pick the "took it" text over the "your party is full" one.
do
  local record = { party = {} }
  local vm = giftVm(record)
  Specials.HANDLERS.GiveShuckle(vm)
  eq(vm.scriptVar, 1, "GiveShuckle answers TRUE when it hands one over")
end

-- ---- a dex that already has entries in it ---------------------------------
do
  local record = { party = {},
    pokedex = { seen = { TOTODILE = true }, caught = { TOTODILE = true } } }
  Specials.HANDLERS.GiveShuckle(giftVm(record))
  eq(record.pokedex.caught.TOTODILE, true, "the starter's entry survives")
  eq(record.pokedex.caught.SHUCKLE, true, "and SHUCKIE joins it")
  eq(Save.summary(record).caught, 2, "two owned species, counted once each")
end

-- The shape a loaded save actually has, rather than a hand-built one:
-- Save.normalize seeds pokedex.seen/caught, so the handler is writing into
-- tables that already exist.
do
  local record = Save.normalize({ party = {} }) or { party = {} }
  record.party = record.party or {}
  Specials.HANDLERS.GiveShuckle(giftVm(record))
  eq(record.pokedex.caught.SHUCKLE, true, "a normalized save takes the flag too")
end

-- ---- the arms that must NOT flag the dex ----------------------------------
-- .full returns before _AddPartyMon runs, so nothing reaches .registerpokedex
-- and the player who never received the mon has no entry for it.
do
  local full = {}
  for i = 1, Breeding.PARTY_SIZE do full[i] = { species = "TOTODILE", level = i } end
  local record = { party = full }
  local vm = giftVm(record)
  Specials.HANDLERS.GiveShuckle(vm)
  eq(vm.scriptVar, 0, "a full party refuses the gift")
  eq(#record.party, Breeding.PARTY_SIZE, "and nothing is appended")
  eq(record.pokedex, nil, "a refused gift leaves no #DEX entry behind")
end

-- Mon.new failing (no such species in the cache) is the other early out.
do
  local record = { party = {} }
  local vm = Vm.new({}, {}, Events.new(), { specials = {
    party = function() return record.party end,
    save = function() return record end,
    data = function() return { pokemon = {}, moves = {} } end,
  } })
  Specials.HANDLERS.GiveShuckle(vm)
  eq(vm.scriptVar, 0, "a mon that cannot be built is refused")
  eq(record.pokedex, nil, "and still flags nothing")
end

-- ---- parity with the engine's other SetSeenAndCaughtMon ports -------------
-- Breeding.markPokedex is the shared port of the same routine the hatch, the
-- NPC trade and the givepoke opcode all run.  A gift that flags the dex its
-- own way instead of matching that state is drift, and drift is what leaves
-- one screen showing the entry and another not.
do
  local sibling = { party = {} }
  check(Breeding.markPokedex(sibling, "SHUCKLE"),
    "the shared SetSeenAndCaughtMon port still takes a species")
  same(giftedDex, sibling.pokedex,
    "GiveShuckle leaves the identical #DEX state the shared port does")
end

S.finish()
