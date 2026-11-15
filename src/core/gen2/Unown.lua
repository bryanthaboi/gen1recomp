-- Unown: the letter a set of DVs spells, which letters the Ruins of Alph have
-- unlocked, and the #DEX's own catching-order list of them.
--
-- Sources, all of them small and all of them in different files on the cart:
--
--   GetUnownLetter          engine/gfx/load_pics.asm -- the DVs -> 1..26 map
--   CheckUnownLetter        engine/battle/core.asm   -- is that form unlocked
--   UnlockedUnownLetterSets data/wild/unlocked_unowns.asm -- the four sets
--   UpdateUnownDex          engine/pokedex/unown_dex.asm  -- wUnownDex
--   PrintUnownWord          engine/pokedex/unown_dex.asm  -- the word per form
--   CountUnown              engine/events/specials.asm    -- how many so far
--
-- They live together here because every one of them is about the FORM rather
-- than the species, and the port's save keys its #DEX by species (a single
-- UNOWN flag).  The form list is a second, parallel record: `save.unownDex`,
-- a list of letter numbers in the order they were first caught, exactly the
-- shape of wUnownDex.
--
-- Letters are NUMBERS here, 1 = A .. 26 = Z, because that is what the cart
-- stores and what UnownWords / UnownPicPointers index by.  `Unown.name` is
-- the only place a number becomes a character.

local Runtime = require("src.mods.Runtime")

local EngineFlags = require("src.core.gen2.EngineFlags")
local Unown = EngineFlags.expose({}, { "ENGINE_UNOWN_DEX" })

-- constants/pokemon_constants.asm: NUM_UNOWN EQU 26.
Unown.NUM_UNOWN = 26
Unown.SPECIES = "UNOWN"

Unown.ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

-- 1 -> "A".  Anything off the end answers nil rather than an empty string, so
-- a caller that got its number from bad data notices.
function Unown.name(letter)
  if type(letter) ~= "number" then return nil end
  if letter < 1 or letter > Unown.NUM_UNOWN then return nil end
  return Unown.ALPHABET:sub(letter, letter)
end

-- "A" -> 1, and a number passes straight through.  Handy for tests and for the
-- pic table, whose keys in pokemon.lua are the letters themselves.
function Unown.index(letter)
  if type(letter) == "number" then return letter end
  if type(letter) ~= "string" or #letter ~= 1 then return nil end
  local at = Unown.ALPHABET:find(letter:upper(), 1, true)
  return at
end

-- ------------------------------------------------------------ the letter
--
-- GetUnownLetter takes the MIDDLE two bits of each of the four DVs and packs
-- them in the order atk, def, spd, spc:
--
--   ; atk  def  spd  spc
--   ; .ww..xx.  .yy..zz.
--
-- The asm reads the two packed DV bytes, so its masks are $60 / $06 on each --
-- bits 1 and 2 of every nibble.  With the DVs already unpacked into fields the
-- same two bits are `(dv >> 1) % 4`, which is what the shifts add up to.
--
-- Then `ld a, $ff / NUM_UNOWN + 1` is 10, Divide gives 0..25, and `inc a`
-- makes it 1..26.  The divisor is integer-truncated on the cart ($ff / 26 is
-- 9), so it is 10 and not 255/26: a value of 250..255 still lands on Z.
local function middleBits(dv)
  return math.floor((dv or 0) / 2) % 4
end

-- No DVs means the caller has a mon this module cannot read, which is a bug in
-- the caller rather than a letter A: Mon.new always rolls DVs (opts.dvs or
-- Mon.randomDVs, src/battle/gen2/Mon.lua:198) and a catch appends that same
-- record by reference, so every real party or box Unown has them.  Answering 1
-- here is how a missing plumbing hop reads as a legitimate Unown A.
function Unown.letterFromDVs(dvs)
  if not dvs then return nil end
  local packed = middleBits(dvs.attack) * 64
    + middleBits(dvs.defense) * 16
    + middleBits(dvs.speed) * 4
    + middleBits(dvs.special)
  return math.floor(packed / 10) + 1
end

-- ------------------------------------------------------- the unlocked sets
--
-- data/wild/unlocked_unowns.asm.  Each solved puzzle sets one ENGINE_* flag and
-- that flag unlocks one contiguous run of letters; the runs are uneven because
-- they were cut to the four chamber puzzles, not to equal thirds.
--
-- ENGINE_UNOWN_DEX, the flag RuinsOfAlphResearchCenterGetUnownDexScript sets.
-- It is what gates the #DEX's UNOWN MODE (Pokedex_CheckUnlockedUnownMode reads
-- it as wStatusFlags bit STATUSFLAGS_UNOWN_DEX_F), and it is a different thing
-- from having caught an Unown.

Unown.UNLOCK_SETS = {
  { name = "ENGINE_UNLOCKED_UNOWNS_A_TO_K", first = 1, last = 11 },
  { name = "ENGINE_UNLOCKED_UNOWNS_L_TO_R", first = 12, last = 18 },
  { name = "ENGINE_UNLOCKED_UNOWNS_S_TO_W", first = 19, last = 23 },
  { name = "ENGINE_UNLOCKED_UNOWNS_X_TO_Z", first = 24, last = 26 },
}

-- The four puzzles, in UNOWNPUZZLE_* order (constants/script_constants.asm),
-- with the flag each chamber's .PuzzleComplete arm sets.  `setval
-- UNOWNPUZZLE_KABUTO / special UnownPuzzle` is how the screen is told which
-- picture to slice, so the id the script passes indexes this list from 0.
Unown.PUZZLES = {
  [0] = { id = "KABUTO", flag = "ENGINE_UNLOCKED_UNOWNS_A_TO_K",
          event = "EVENT_SOLVED_KABUTO_PUZZLE" },
  [1] = { id = "OMANYTE", flag = "ENGINE_UNLOCKED_UNOWNS_L_TO_R",
          event = "EVENT_SOLVED_OMANYTE_PUZZLE" },
  [2] = { id = "AERODACTYL", flag = "ENGINE_UNLOCKED_UNOWNS_S_TO_W",
          event = "EVENT_SOLVED_AERODACTYL_PUZZLE" },
  [3] = { id = "HO_OH", flag = "ENGINE_UNLOCKED_UNOWNS_X_TO_Z",
          event = "EVENT_SOLVED_HO_OH_PUZZLE" },
}

-- CheckUnownLetter: walk the four sets, skip a set whose bit is clear, and
-- answer true as soon as the letter turns up in one that is set.  Returns
-- carry on the cart, which is "NOT unlocked", so the sense is flipped here to
-- read the way the call sites want it.
function Unown.letterUnlocked(letter, engineFlags)
  local index = Unown.index(letter)
  if not index then return false end
  for _, set in ipairs(Unown.UNLOCK_SETS) do
    if engineFlags and engineFlags[EngineFlags.id(set.name)] then
      if index >= set.first and index <= set.last then return true end
    end
  end
  return false
end

-- ChooseWildEncounter's `ld a, [wUnlockedUnowns] / and a / jr z,
-- .nowildbattle`: with no puzzle solved at all an Unown slot is not an
-- encounter, it is no encounter.  The whole byte is tested, so the four unused
-- bits would count too; nothing ever sets them.
function Unown.anyUnlocked(engineFlags)
  if not engineFlags then return false end
  for _, set in ipairs(Unown.UNLOCK_SETS) do
    if engineFlags[EngineFlags.id(set.name)] then return true end
  end
  return false
end

-- Every letter currently reachable, in order.  The puzzle screen has nothing
-- to say about this; it is here because the researcher's dialogue and the
-- encounter roll both want the same list.
function Unown.unlockedLetters(engineFlags)
  local out = {}
  for _, set in ipairs(Unown.UNLOCK_SETS) do
    if engineFlags and engineFlags[EngineFlags.id(set.name)] then
      for letter = set.first, set.last do out[#out + 1] = letter end
    end
  end
  table.sort(out)
  return out
end

-- LoadEnemyMon's .GenerateDVs loop: roll DVs, take the letter, and roll again
-- while the letter is locked.  The cart's loop is unbounded, and the comment
-- above it says so ("If combined with forced shiny battletype, causes an
-- infinite loop") -- here the retries are capped and the fallback picks an
-- unlocked letter directly, so a caller that hands in a degenerate RNG gets a
-- legal mon instead of a hang.
--
-- `randomDVs` is src/battle/gen2/Mon.randomDVs, passed in rather than required
-- so this module stays free of the party builder.
local DV_RETRIES = 256

function Unown.wildDVs(engineFlags, randomDVs)
  local dvs = randomDVs()
  if not Unown.anyUnlocked(engineFlags) then return dvs end
  local tries = 0
  while not Unown.letterUnlocked(Unown.letterFromDVs(dvs), engineFlags) do
    tries = tries + 1
    if tries >= DV_RETRIES then
      return Unown.dvsForLetter(Unown.unlockedLetters(engineFlags)[1] or 1)
    end
    dvs = randomDVs()
  end
  return dvs
end

-- The inverse of GetUnownLetter, for the fallback above and for a test that
-- wants a mon of a named form.  Letter n covers packed values 10*(n-1) ..
-- 10*(n-1)+9, so the lowest one in the band is the tidy representative; the
-- two middle bits of each DV are set from it and the outer bits left at zero.
function Unown.dvsForLetter(letter)
  local index = Unown.index(letter) or 1
  local packed = (index - 1) * 10
  local function dv(shift)
    return (math.floor(packed / shift) % 4) * 2
  end
  return {
    attack = dv(64),
    defense = dv(16),
    speed = dv(4),
    special = dv(1),
  }
end

-- ------------------------------------------------------------- the #DEX
--
-- wUnownDex is 26 bytes of letter numbers in the order they were first caught,
-- zero-terminated.  UpdateUnownDex walks it: a letter already in the list
-- returns at once, and the first zero is where a new one lands.
function Unown.dex(save)
  if not save then return {} end
  save.unownDex = save.unownDex or {}
  return save.unownDex
end

function Unown.updateDex(save, letter)
  local index = Unown.index(letter)
  if not (save and index) then return false end
  local list = Unown.dex(save)
  for _, seen in ipairs(list) do
    if seen == index then return false end
  end
  if #list >= Unown.NUM_UNOWN then return false end
  list[#list + 1] = index
  -- unown.unlocked, a Gen 2 invention: Gen 1 has one sprite per species and no
  -- form list at all, so there is no name to share and pokemon.caught would be
  -- the wrong one (this fires for a box deposit too, and not for the second
  -- Unown of a letter already listed).  UpdateUnownDex's early return IS the
  -- gate: the event marks the moment a FORM becomes something the #DEX's UNOWN
  -- MODE and the ALPH RUINS STAMP machine can show, which happens exactly once
  -- per letter.
  --
  --   letter  1..26, the same number wUnownDex stores (A is 1)
  --   name    "A".."Z", for a mod that would rather print than index
  --   word    data/pokemon/unown_words.asm's word for the form
  --   count   how many forms are listed now, which is also VAR_UNOWNCOUNT
  if Runtime.wants("unown.unlocked") then
    Runtime.emit("unown.unlocked", {
      letter = index, name = Unown.name(index), word = Unown.word(index),
      count = #list,
    })
  end
  return true
end

function Unown.caught(save, letter)
  local index = Unown.index(letter)
  if not index then return false end
  for _, seen in ipairs(Unown.dex(save)) do
    if seen == index then return true end
  end
  return false
end

-- The two places the cart calls `predef GetUnownLetter / callfar UpdateUnownDex`
-- are AddPartyMon's `.registerunowndex` and SendMonIntoBox (both
-- engine/pokemon/move_mon.asm), i.e. every route a caught Unown can take.  The
-- port's equivalents are the battle's catch handler and `givepoke`, and both
-- call this rather than reaching into the list themselves.
--
-- Anything that is not an Unown falls straight through, so a call site does not
-- have to check the species first.
function Unown.registerCatch(save, mon)
  local letter = Unown.monLetter(mon)
  if not (save and letter) then return false end
  return Unown.updateDex(save, letter)
end

-- CountUnown: `ld b, 0 / loop / ret z` -- the count of non-zero entries, which
-- with the list above is just its length.  This is also VAR_UNOWNCOUNT
-- (engine/overworld/variables.asm .UnownCaught).
function Unown.count(save)
  return #Unown.dex(save)
end

-- ------------------------------------------------------------- the words
--
-- data/pokemon/unown_words.asm.  Each form has one word, printed under its
-- picture on the #DEX's UNOWN MODE page by PrintUnownWord at hlcoord 4, 15.
-- X really is "XXXXX" on the cart.
Unown.WORDS = {
  "ANGRY", "BEAR", "CHASE", "DIRECT", "ENGAGE", "FIND", "GIVE", "HELP",
  "INCREASE", "JOIN", "KEEP", "LAUGH", "MAKE", "NUZZLE", "OBSERVE", "PERFORM",
  "QUICKEN", "REASSURE", "SEARCH", "TELL", "UNDO", "VANISH", "WANT", "XXXXX",
  "YIELD", "ZOOM",
}

function Unown.word(letter)
  local index = Unown.index(letter)
  return index and Unown.WORDS[index] or nil
end

-- The letter a party/box mon is, or nil for anything that is not an Unown.
-- Reads the stored form first: a mon built before this existed still has DVs,
-- and the two always agree because the stored value comes from the DVs.
function Unown.monLetter(mon)
  if not mon or mon.species ~= Unown.SPECIES then return nil end
  if mon.unownLetter then return Unown.index(mon.unownLetter) end
  return Unown.letterFromDVs(mon.dvs)
end

-- pokemon.lua's UNOWN entry carries `letters.A .. letters.Z`, each with its own
-- spriteFront / spriteBack: the pics come out of UnownPicPointers, not the
-- species' own row (pokegold engine/gfx/load_pics.asm GetFrontpic swaps the
-- pointer table for UnownPicPointers and indexes it by wUnownLetter).  A cache
-- built before that landed has no `letters` table, and every caller here
-- degrades to the species' own pics -- which ARE letter A's, since that is
-- what GetUnownLetter defaults to.
function Unown.forms(pokemon)
  local def = pokemon and pokemon[Unown.SPECIES]
  return def and def.letters or nil
end

function Unown.formSprite(pokemon, letter, back)
  local def = pokemon and pokemon[Unown.SPECIES]
  if not def then return nil end
  -- A caller that cannot name the letter answers nil, never letter A.  Every
  -- screen here is handed the mon and reads Unown.monLetter off it; a site that
  -- resolved the pic from the SPECIES instead (as SummaryMenu:picFor once did)
  -- has no letter to give, and coercing that to 1 is exactly what made a caught
  -- Unown D show up in the party as an A with nothing logged.
  local index = Unown.index(letter)
  if not index then return nil end
  local name = Unown.name(index)
  local form = def.letters and name and def.letters[name]
  if form then
    return back and form.spriteBack or form.spriteFront
  end
  return back and def.spriteBack or def.spriteFront
end

return Unown
