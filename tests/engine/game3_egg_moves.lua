-- FRLG egg moves (gEggMoves), end to end: the ROM stream the extractor
-- decodes, the cache file it writes and the accessor a mod reads.
--
-- Why this exists: the Gen 3 pack used to carry no egg moves at all, so a
-- mod asking for a species' egg-move list got nothing back and a hidden-mon
-- generator fell through to whatever else it had -- the TM/HM pool.  The
-- extractor now reads gEggMoves and nothing else, and these checks pin that.
--
--   luajit tests/engine/game3_egg_moves.lua [path/to/firered.gba]
--
-- The real-ROM block needs the supported USA 1.0 dump; without it the
-- synthetic checks below still cover the decode, the writer and the accessor.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Versions = require("src.import.gba.versions")
local PokemonExtract = require("src.import.gba.pokemon_extract")
local Pokemon = require("src.core.game3.pokemon")

local BASE = Versions.EGG_MOVES
local OFF = Versions.EGG_MOVES_SPECIES_OFFSET
local TERM = Versions.EGG_MOVES_TERMINATOR
local NUM = Versions.NUM_SPECIES

eq(BASE, 0x25EF0C, "gEggMoves is pinned to the FireRed USA 1.0 offset")
eq(OFF, 20000, "species headers carry EGG_MOVES_SPECIES_OFFSET")
eq(TERM, 0xFFFF, "EGG_MOVES_TERMINATOR is 0xFFFF")
check(Versions.CACHE_VERSION >= 99,
  "the cache version is bumped past the packs that had no egg_moves.lua")
check(PokemonExtract.FORMAT_VERSION >= 4, "the pokemon pack format version is bumped")

-- ------------------------------------------------------------------ decode
-- A ROM whose gEggMoves stream is `words` and which reads 0 everywhere else:
-- a decode that wandered past the table would pick up those zeros instead of
-- inventing moves out of neighbouring data.
local function romOf(words)
  local at = {}
  for i, word in ipairs(words) do
    local off = BASE + (i - 1) * 2
    at[off] = word % 256
    at[off + 1] = math.floor(word / 256)
  end
  return {
    size = Versions.ROM_SIZE,
    get = function(_, off) return at[off] or 0 end,
    u16 = function(self, off) return self:get(off) + self:get(off + 1) * 256 end,
  }
end

local function decode(words)
  return PokemonExtract.eggMovesFromRom(romOf(words), NUM)
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

do -- two runs, each closed by its own terminator
  local eggMoves = decode({ OFF + 4, 57, 10, TERM, OFF + 16, 33, TERM })
  eq(count(eggMoves), 2, "two species runs decode to two species")
  eq(table.concat(eggMoves[4], ","), "57,10", "a run keeps its moves in ROM order")
  eq(table.concat(eggMoves[16], ","), "33", "and the second run keeps its own")
end

do -- a run with no moves is an empty list, not a missing key
  local eggMoves = decode({ OFF + 5, TERM, OFF + 6, 12, TERM })
  eq(count(eggMoves), 2, "a moveless run still opens a species")
  eq(#eggMoves[5], 0, "but carries no move")
  eq(table.concat(eggMoves[6], ","), "12", "and the next run is unaffected")
end

do -- a species that appears twice keeps both runs' moves
  local eggMoves = decode({ OFF + 4, 57, TERM, OFF + 4, 10, TERM })
  eq(count(eggMoves), 1, "a repeated header is one species")
  eq(table.concat(eggMoves[4], ","), "57,10", "with both runs' moves")
end

do -- a terminator with no run open is the table's end
  eq(count(decode({ TERM, OFF + 4, 57, TERM })), 0,
    "a leading terminator ends the scan before any species")
end

do -- and a word that is neither a header nor a move ends it too
  local eggMoves = decode({ OFF + 4, 57, 0, OFF + 16, 33, TERM })
  eq(table.concat(eggMoves[4] or {}, ","), "57", "moves before the stray word decode")
  eq(eggMoves[16], nil, "and nothing after it is invented")
end

do -- a header past the species count is not a species
  eq(count(decode({ OFF + NUM, 57, TERM })), 0,
    "an out-of-range species header decodes to nothing")
end

-- ------------------------------------------------------------------ writer
do
  local src = PokemonExtract.writeEggMovesLua({
    [16] = { 10, 33 }, [4] = { 57 }, [5] = {},
  })
  local chunk = load(src, "@egg_moves.lua", "t", {})
  check(chunk ~= nil, "the writer emits loadable lua")
  local written = chunk and chunk() or {}
  eq(table.concat(written[16], ","), "10,33", "the writer keeps a list intact")
  eq(table.concat(written[4], ","), "57", "and a one-move list")
  eq(written[5], nil, "an empty list is left out (gEggMoves is sparse)")
  check(src:find("[4] = { 57 },", 1, true) ~= nil, "species keys are emitted")
  local at4 = src:find("[4] = { 57 },", 1, true)
  local at16 = src:find("[16] = { 10, 33 },", 1, true)
  check(at4 and at16 and at4 < at16, "species keys come out in ascending order")
end

-- -------------------------------------------------------------- accessor
do
  -- the cache the runtime installs from, with just the files this touches
  local files = {
    ["data/generated/gba/pokemon/names.lua"] = 'return {\n' ..
      '  [4] = "CHARMANDER",\n  [16] = "PIDGEY",\n}\n',
    ["data/generated/gba/pokemon/egg_moves.lua"] =
      PokemonExtract.writeEggMovesLua({ [4] = { 57 }, [16] = { 10, 33 } }),
  }
  local cache = { read = function(_, rel) return files[rel] end }

  Pokemon.install(cache)
  eq(Pokemon._eggMoves and Pokemon._eggMoves[4][1], 57,
    "install() loads pokemon/egg_moves.lua into _eggMoves")
  eq(table.concat(Pokemon.eggMoves(16), ","), "10,33",
    "eggMoves(species) returns the list")
  eq(Pokemon.eggMoves("PIDGEY") and #Pokemon.eggMoves("PIDGEY"), 2,
    "eggMoves accepts a species name")
  eq(Pokemon.eggMoves({ species = 4 }) and Pokemon.eggMoves({ species = 4 })[1], 57,
    "eggMoves accepts a mon table")
  eq(Pokemon.eggMoves(151), nil,
    "a species with no egg moves returns nil, not an empty list")
  eq(Pokemon.eggMoves("NOT A SPECIES"), nil, "an unknown name returns nil")
  eq(Pokemon.eggMoves(nil), nil, "and so does no argument at all")

  Pokemon.invalidate()
  eq(Pokemon._eggMoves, nil, "invalidate() drops the loaded list")
end

-- pokefirered/src/daycare.c:888 BuildEggMoveset
do
  local Breeding = require("src.core.game3.breeding")

  local EGG_MOVE, TM_MOVE, SHARED_LVL, PLAIN = 57, 92, 22, 150
  local files = {
    ["data/generated/gba/pokemon/names.lua"] = 'return {\n  [4] = "CHARMANDER",\n}\n',
    ["data/generated/gba/pokemon/egg_moves.lua"] =
      PokemonExtract.writeEggMovesLua({ [4] = { EGG_MOVE } }),
    -- pokefirered/src/pokemon.c:5780 GetLevelUpMovesBySpecies
    ["data/generated/gba/pokemon/learnsets.lua"] =
      ("return {\n  [4] = { {1,%d}, {12,%d}, {19,%d} },\n}\n"):format(33, SHARED_LVL, 98),
    -- pokefirered/src/daycare.c:941 ItemIdToBattleMoveId / CanMonLearnTMHM
    ["data/generated/gba/pokemon/tmhm.lua"] =
      ("local M = { machines = {}, learnsets = {} }\nM.machines[5] = %d\n"):format(TM_MOVE)
      .. "M.learnsets[4] = { lo = 32, hi = 0 }\nreturn M\n",
  }
  Pokemon.install({ read = function(_, rel) return files[rel] end })

  eq(Pokemon.moveFromTmItem(289 + 5), TM_MOVE, "TM06 is the move the fixture put there")
  check(Pokemon.canLearnTmIndex(4, 5), "and species 4 may learn it")

  local function child()
    return { species = 4, moves = {}, pp = {}, maxPp = {} }
  end
  local function parent(moves)
    return { species = 4, moves = moves, pp = { 10, 10, 10, 10 }, maxPp = { 10, 10, 10, 10 } }
  end

  local egg = child()
  Breeding.buildEggMoveset(egg, parent({ EGG_MOVE }), parent({ PLAIN }))
  check(Pokemon.knowsMove(egg, EGG_MOVE), "the father's egg move is inherited")

  egg = child()
  Breeding.buildEggMoveset(egg, parent({ TM_MOVE }), parent({ PLAIN }))
  check(Pokemon.knowsMove(egg, TM_MOVE), "so is a TM move the egg can learn")

  egg = child()
  Breeding.buildEggMoveset(egg, parent({ SHARED_LVL }), parent({ SHARED_LVL }))
  check(Pokemon.knowsMove(egg, SHARED_LVL), "so is a level-up move both parents know")

  egg = child()
  Breeding.buildEggMoveset(egg, parent({ SHARED_LVL }), parent({ PLAIN }))
  check(not Pokemon.knowsMove(egg, SHARED_LVL),
    "but not one only the father knows")

  egg = child()
  Breeding.buildEggMoveset(egg, parent({ PLAIN }), parent({ PLAIN }))
  check(not Pokemon.knowsMove(egg, PLAIN),
    "and not a shared move that is not in the egg's level-up set")

  egg = child()
  Breeding.buildEggMoveset(egg, parent({ EGG_MOVE }), parent({ EGG_MOVE }))
  eq(Pokemon.moveSlotCount(egg), 1, "an inherited move is never given twice")

  -- pokefirered/src/daycare.c:925 DeleteFirstMoveAndGiveMoveToMon
  egg = { species = 4, moves = { 1, 2, 3, 4 }, pp = { 5, 5, 5, 5 }, maxPp = { 5, 5, 5, 5 } }
  Breeding.buildEggMoveset(egg, parent({ EGG_MOVE }), parent({ PLAIN }))
  eq(Pokemon.moveSlotCount(egg), 4, "a full moveset stays at four moves")
  eq(egg.moves[1], 2, "the first move is deleted")
  eq(egg.moves[4], EGG_MOVE, "and the egg move takes the last slot")

  Pokemon.invalidate()
end

-- ----------------------------------------------------------------- real ROM
-- Pinned against the supported FireRed USA 1.0 dump; skipped otherwise.
local path = arg and arg[1]
if not path then
  print("SKIP real-ROM egg-move block: pass a FireRed .gba path explicitly")
else
  local FileIO = require("src.import.gba.file_io")
  local imports = FileIO.makeImports(path, "test")
  local rom = assert(require("src.import.gba.rom").open(imports, "firered"))
  local eggMoves = PokemonExtract.eggMovesFromRom(rom, NUM)

  eq(count(eggMoves), 165, "the ROM's gEggMoves names 165 species")
  local moves = 0
  local widest = 0
  for _, list in pairs(eggMoves) do
    moves = moves + #list
    if #list > widest then widest = #list end
  end
  eq(moves, 973, "holding 973 egg moves in total")
  check(widest <= 8, "no species has more than the ROM's 8 egg moves")
  eq(table.concat(eggMoves[1], ","), "113,130,219,204,80,345,320,174",
    "Bulbasaur's egg moves match the ROM")
  eq(table.concat(eggMoves[411], ","), "50,174,95,138",
    "so do Deoxys'")
  local mankey = eggMoves[56] or {}
  check(#mankey == 8, "Mankey has 8 egg moves")
  local toxic = false
  for _, move in ipairs(mankey) do
    if move == 92 then toxic = true end
  end
  check(not toxic, "and Toxic (a TM) is not one of them")

  -- the whole path a mod depends on: ROM → run() → pokemon/egg_moves.lua →
  -- the runtime accessor.  cacheRoot is the runtime's own root so that
  -- Pokemon.install reads exactly the file the extractor just wrote.
  local root = require("src.import.gba.extract_island1").CACHE_ROOT
  local files = {}
  local cache = {
    write = function(_, rel, bytes) files[rel] = bytes; return true end,
    exists = function(_, rel) return files[rel] ~= nil end,
    read = function(_, rel) return files[rel] end,
  }
  local pack = PokemonExtract.run(rom, cache, { cacheRoot = root })
  check(cache:exists(root .. "/pokemon/egg_moves.lua"),
    "run() writes pokemon/egg_moves.lua into the cache")
  eq(count(pack.eggMoves or {}), 165, "and returns the same 165 species")

  Pokemon.install(cache)
  eq(table.concat(Pokemon.eggMoves(1), ","), "113,130,219,204,80,345,320,174",
    "the written cache loads back into the runtime")
  eq(table.concat(Pokemon.eggMoves(56), ","), "157,193,96,68,179,251,279,265",
    "so a mod reading Mankey's egg moves gets the ROM's list")
  eq(Pokemon.eggMoves(151), nil, "and a species without egg moves gets nil")

  imports:_close()
end

T.finish("game3_egg_moves")
