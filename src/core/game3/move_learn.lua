-- pokefirered/src/pokemon.c:5741 GetMoveRelearnerMoves

local Pokemon = require("src.core.game3.pokemon")

local MoveLearn = {}

-- pokefirered/include/constants/pokemon.h:209
local MAX_LEVEL_UP_MOVES = 20
-- pokefirered/include/constants/global.h:77
local MAX_MON_MOVES = 4
-- pokefirered/include/constants/species.h:421
local SPECIES_EGG = 412

MoveLearn.MAX_LEVEL_UP_MOVES = MAX_LEVEL_UP_MOVES

local function learned_moves(mon)
  local out = {}
  for i = 1, MAX_MON_MOVES do
    out[i] = tonumber(Pokemon.moveIdAt(mon, i)) or 0
  end
  return out
end

local function contains(list, n, value)
  for i = 1, n do
    if list[i] == value then return true end
  end
  return false
end

--- pokefirered/src/pokemon.c:5741
function MoveLearn.relearnableMoves(mon)
  local moves = {}
  if not mon then return moves end
  local species = Pokemon.speciesOf(mon)
  if not species or species == SPECIES_EGG then return moves end
  local level = tonumber(mon.level) or 0
  local known = learned_moves(mon)
  local set = Pokemon.learnset(species)
  local count = 0
  for i = 1, MAX_LEVEL_UP_MOVES do
    local entry = set[i]
    if not entry then break end
    local lv = tonumber(entry[1] or entry.level) or 0
    local mv = tonumber(entry[2] or entry.move) or 0
    if mv > 0 and lv <= level then
      if not contains(known, MAX_MON_MOVES, mv) and not contains(moves, count, mv) then
        count = count + 1
        moves[count] = mv
      end
    end
  end
  return moves
end

--- pokefirered/src/pokemon.c:5791
function MoveLearn.countRelearnableMoves(mon)
  if not mon then return 0 end
  if Pokemon.isEgg(mon) then return 0 end
  return #MoveLearn.relearnableMoves(mon)
end

local SLOT_ARRAYS = { "moves", "pp", "maxPp", "moveIds", "ppBonuses", "ppBonus", "ppUp" }

local function packed_bonus(mon, slot)
  if type(mon.ppBonusesPacked) ~= "number" then return nil end
  return bit.band(bit.rshift(mon.ppBonusesPacked, (slot - 1) * 2), 3)
end

local function set_packed_bonus(mon, slot, value)
  if type(mon.ppBonusesPacked) ~= "number" then return end
  local shift = (slot - 1) * 2
  local packed = bit.band(mon.ppBonusesPacked, bit.bnot(bit.lshift(3, shift)))
  mon.ppBonusesPacked = bit.bor(packed, bit.lshift(bit.band(value or 0, 3), shift))
end

-- pokefirered/src/party_menu_specials.c:70 ShiftMoveSlot
local function shift_slot(mon, slotTo, slotFrom)
  for _, key in ipairs(SLOT_ARRAYS) do
    local t = mon[key]
    if type(t) == "table" then t[slotTo], t[slotFrom] = t[slotFrom], t[slotTo] end
  end
  local a, b = packed_bonus(mon, slotTo), packed_bonus(mon, slotFrom)
  if a or b then
    set_packed_bonus(mon, slotTo, b)
    set_packed_bonus(mon, slotFrom, a)
  end
end

--- pokefirered/src/party_menu_specials.c:92 MoveDeleterForgetMove
function MoveLearn.forgetMove(mon, slot)
  slot = tonumber(slot)
  if not mon or not slot or slot < 0 or slot >= MAX_MON_MOVES then return false end
  local i = slot + 1
  if not Pokemon.moveIdAt(mon, i) then return false end
  for _, key in ipairs(SLOT_ARRAYS) do
    local t = mon[key]
    if type(t) == "table" then t[i] = nil end
  end
  -- pokefirered/src/pokemon.c:3904 RemoveMonPPBonus
  set_packed_bonus(mon, i, 0)
  for j = i, MAX_MON_MOVES - 1 do
    shift_slot(mon, j, j + 1)
  end
  return true
end

-- pokefirered/include/constants/party_menu.h:28
MoveLearn.TUTOR_MOVE_COUNT = 15
-- pokefirered/include/constants/party_menu.h:30
MoveLearn.TUTOR_MOVE_FRENZY_PLANT = 15
MoveLearn.TUTOR_MOVE_BLAST_BURN = 16
MoveLearn.TUTOR_MOVE_HYDRO_CANNON = 17

-- pokefirered/src/party_menu.c:91
MoveLearn.CAN_LEARN_MOVE = 0
MoveLearn.CANNOT_LEARN_MOVE = 1
MoveLearn.ALREADY_KNOWS_MOVE = 2
MoveLearn.CANNOT_LEARN_MOVE_IS_EGG = 3

-- pokefirered/src/field_specials.c:2213 sCapeBrinkCompatibleSpecies
local CAPE_BRINK = {
  [0] = { species = 3, tutor = MoveLearn.TUTOR_MOVE_FRENZY_PLANT, move = 338, flag = 0x2DE },
  [1] = { species = 6, tutor = MoveLearn.TUTOR_MOVE_BLAST_BURN, move = 307, flag = 0x2DF },
  [2] = { species = 9, tutor = MoveLearn.TUTOR_MOVE_HYDRO_CANNON, move = 308, flag = 0x2E0 },
}

MoveLearn.CAPE_BRINK = CAPE_BRINK
-- pokefirered/include/constants/flags.h:764
MoveLearn.FLAG_LEARNED_ALL_MOVES_AT_CAPE_BRINK = 0x2E1

local function cache_root()
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.mountExtractRoots then
    Dataset.mountExtractRoots()
  end
  local okE, Extract = pcall(require, "src.import.gba.extract_island1")
  return (okE and Extract and Extract.CACHE_ROOT) or "data/generated/gba"
end

local function read_cache_lua(rel, short)
  local content = nil
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local cache = Dataset.cache()
    if cache and cache.read then
      content = cache:read(rel) or cache:read(short)
    end
  end
  if not content then
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.readActive then
      content = CacheFs.readActive(rel) or CacheFs.readActive(short)
    end
  end
  if not content and love and love.filesystem and love.filesystem.read then
    content = love.filesystem.read(rel) or love.filesystem.read(short)
  end
  if not content then
    local f = io.open(rel, "r")
    if f then
      content = f:read("*a")
      f:close()
    end
  end
  if not content then return nil end
  local chunk = loadstring and loadstring(content, "@" .. rel) or load(content, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, res = pcall(chunk)
  if ok and type(res) == "table" then return res end
  return nil
end

MoveLearn._tutorPack = nil
MoveLearn._tutorLoaded = false

function MoveLearn.resetTutorPack()
  MoveLearn._tutorPack = nil
  MoveLearn._tutorLoaded = false
end

local function tutor_pack()
  if MoveLearn._tutorLoaded then return MoveLearn._tutorPack end
  MoveLearn._tutorLoaded = true
  local root = cache_root() .. "/pokemon"
  MoveLearn._tutorPack = read_cache_lua(root .. "/tutor.lua", "pokemon/tutor.lua")
  return MoveLearn._tutorPack
end

-- pokefirered/src/data/pokemon/tutor_learnsets.h:22 sTutorLearnsets
function MoveLearn.tutorLearnsets()
  local pack = tutor_pack()
  return pack and pack.learnsets or nil
end

-- pokefirered/src/data/pokemon/tutor_learnsets.h:1 sTutorMoves
function MoveLearn.tutorMoves()
  local pack = tutor_pack()
  return pack and pack.moves or nil
end

--- pokefirered/src/party_menu.c:1892 GetTutorMove
function MoveLearn.tutorMove(tutor)
  tutor = tonumber(tutor)
  if not tutor then return nil end
  for _, row in pairs(CAPE_BRINK) do
    if row.tutor == tutor then return row.move end
  end
  if tutor < 0 or tutor >= MoveLearn.TUTOR_MOVE_COUNT then return nil end
  local moves = MoveLearn.tutorMoves()
  return moves and moves[tutor] or nil
end

--- pokefirered/src/party_menu.c:1907 CanLearnTutorMove
function MoveLearn.canLearnTutorMove(species, tutor)
  species = tonumber(species)
  tutor = tonumber(tutor)
  if not species or not tutor then return false end
  for _, row in pairs(CAPE_BRINK) do
    if row.tutor == tutor then return species == row.species end
  end
  if tutor < 0 or tutor >= MoveLearn.TUTOR_MOVE_COUNT then return false end
  local sets = MoveLearn.tutorLearnsets()
  local bits = sets and tonumber(sets[species])
  if not bits then return false end
  return math.floor(bits / (2 ^ tutor)) % 2 == 1
end

--- pokefirered/src/party_menu.c:1867 CanMonLearnTMTutor, item 0
function MoveLearn.canMonLearnTutorMove(mon, tutor)
  if not mon then return MoveLearn.CANNOT_LEARN_MOVE end
  if Pokemon.isEgg(mon) then return MoveLearn.CANNOT_LEARN_MOVE_IS_EGG end
  local species = Pokemon.speciesOf(mon)
  if not MoveLearn.canLearnTutorMove(species, tutor) then return MoveLearn.CANNOT_LEARN_MOVE end
  local move = MoveLearn.tutorMove(tutor)
  if not move then return MoveLearn.CANNOT_LEARN_MOVE end
  if Pokemon.knowsMove(mon, move) then return MoveLearn.ALREADY_KNOWS_MOVE end
  return MoveLearn.CAN_LEARN_MOVE
end

--- pokefirered/src/field_specials.c:510 GetLeadMonIndex
function MoveLearn.leadMonIndex(party)
  if type(party) ~= "table" then return 0 end
  for i = 1, #party do
    local mon = party[i]
    local species = mon and Pokemon.speciesOf(mon)
    if species and species ~= 0 and species ~= SPECIES_EGG and not Pokemon.isEgg(mon) then
      return i - 1
    end
  end
  return 0
end

--- pokefirered/src/field_specials.c:2219 CapeBrinkGetMoveToTeachLeadPokemon
function MoveLearn.capeBrinkRow(mon)
  if not mon then return nil end
  local species = Pokemon.isEgg(mon) and SPECIES_EGG or Pokemon.speciesOf(mon)
  for i = 0, 2 do
    if CAPE_BRINK[i].species == species then
      if (tonumber(Pokemon.friendshipOf(mon)) or 0) ~= 255 then return nil end
      return CAPE_BRINK[i]
    end
  end
  return nil
end

return MoveLearn
