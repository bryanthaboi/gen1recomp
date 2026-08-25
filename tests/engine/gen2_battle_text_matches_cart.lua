-- Five Gen 2 battle messages printed something the cart does not say.  Each
-- case below drives a real turn and compares the emitted line against the
-- label in pokegold's data/text/battle.asm:
--
--   SuperEffectiveText                    :603
--   NotVeryEffectiveText                  :608
--   BattleText_TheresNoPPLeftForThisMove  :315
--   PlayerHitTimesText / EnemyHitTimesText:749, :755
--   StartPerishText                       :986
--
-- The marker is the one src/import/RomExtractorGen2.lua decodes the cart's own
-- $4e (`line`) into, so a line written here reads exactly as an extracted one
-- would.  The tail case pins the other half of that: printMessage draws at
-- most TEXT_ROWS rows and cuts the rest, so a line has to fit two of them.
--
--   luajit tests/engine/gen2_battle_text_matches_cart.lua
--
-- ROM-free: the fixtures below are the extractor's shapes.

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

local check = T.check

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  GROUND = { id = "GROUND", index = 4, category = "physical" },
  ROCK = { id = "ROCK", index = 5, category = "physical" },
  FIRE = { id = "FIRE", index = 20, category = "special" },
  WATER = { id = "WATER", index = 21, category = "special" },
}

local MATCHUPS = {
  { attacker = "NORMAL", defender = "ROCK", multiplier = 5 },
  { attacker = "WATER", defender = "FIRE", multiplier = 20 },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  WATER_GUN = { id = "WATER_GUN", name = "WATER GUN", power = 40,
    type = "WATER", accuracy = 100, pp = 25, effect = "EFFECT_NORMAL_HIT" },
  DOUBLESLAP = { id = "DOUBLESLAP", name = "DOUBLESLAP", power = 15,
    type = "NORMAL", accuracy = 100, pp = 10, effect = "EFFECT_MULTI_HIT" },
  PERISH_SONG = { id = "PERISH_SONG", name = "PERISH SONG", power = 0,
    type = "NORMAL", accuracy = 100, pp = 5, effect = "EFFECT_PERISH_SONG" },
}

local GROWTH = {
  GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15,
    linear = 100, constant = 140 },
}

local function species(id, index, types)
  return { id = id, index = index, name = id,
    baseStats = { hp = 50, attack = 60, defense = 50, speed = 50,
      specialAttack = 50, specialDefense = 50 },
    types = types, catchRate = 255, baseExp = 60,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} }
end

local POKEMON = {
  growthRates = GROWTH,
  CYNDAQUIL = species("CYNDAQUIL", 155, { "FIRE", "FIRE" }),
  GEODUDE = species("GEODUDE", 74, { "ROCK", "GROUND" }),
}

local DATA = { pokemon = POKEMON, moves = MOVES,
  type_chart = { types = TYPES, matchups = MATCHUPS }, items = {} }

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

-- The smallest roll that is neither a critical hit nor a miss.
local function detRandom(n)
  if (n or 1) <= 1 then return 0 end
  return 1
end

-- One turn of the player's move, returning every message line it printed.
local function linesFrom(playerSpecies, playerMoves, wildSpecies, moveId)
  local player = Mon.new(DATA, playerSpecies, 20, { dvs = perfect })
  player.moves = playerMoves
  local wild = Mon.new(DATA, wildSpecies, 20, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    random = detRandom })
  local said = {}
  for _, event in ipairs(battle:takeTurn({ kind = "move", move = moveId })) do
    if event.kind == "message" and event.text then
      said[#said + 1] = event.text
    end
  end
  return said
end

local function saw(said, text)
  for _, line in ipairs(said) do
    if line == text then return true end
  end
  return false
end

local function shown(said)
  return "printed: " .. table.concat(said, " | ")
end

-- ---- the two effectiveness lines ------------------------------------------
-- Both break across the box's two lines on the cart, and "super-" is
-- hyphenated to make the break.  The not-very line ends on the single
-- ellipsis glyph the Gold charmap carries at $75, not on three periods.
do
  local said = linesFrom("CYNDAQUIL",
    { { id = "TACKLE", pp = 35, maxPp = 35 } }, "GEODUDE", "TACKLE")
  check(saw(said, "It's not very\neffective…"),
    "NotVeryEffectiveText prints as the cart writes it. " .. shown(said))

  said = linesFrom("GEODUDE",
    { { id = "WATER_GUN", pp = 25, maxPp = 25 } }, "CYNDAQUIL", "WATER_GUN")
  check(saw(said, "It's super-\neffective!"),
    "SuperEffectiveText keeps its hyphen and its break. " .. shown(said))
end

-- ---- a move at zero PP ----------------------------------------------------
do
  -- a second move with PP left, so the turn refuses the empty one rather
  -- than falling through to Struggle
  local said = linesFrom("CYNDAQUIL",
    { { id = "TACKLE", pp = 0, maxPp = 35 },
      { id = "WATER_GUN", pp = 25, maxPp = 25 } }, "GEODUDE", "TACKLE")
  check(saw(said, "There's no PP left\nfor this move!"),
    "the empty-PP refusal is the cart's sentence. " .. shown(said))
end

-- ---- the multi-hit tally --------------------------------------------------
-- "Hit @ times!" has no singular form on the cart, which is why the "(s)"
-- this used to print is not a hedge the game ever makes.  Gen 1 says it the
-- same way (src/battle/EffectRegistry.lua, _HitXTimesText).
do
  local said = linesFrom("CYNDAQUIL",
    { { id = "DOUBLESLAP", pp = 10, maxPp = 10 } }, "GEODUDE", "DOUBLESLAP")
  local tally
  for _, line in ipairs(said) do
    if line:match("^Hit %d+ times!$") then tally = line end
  end
  check(tally ~= nil,
    "the multi-hit tally reads \"Hit N times!\". " .. shown(said))
  check(not table.concat(said, " "):find("time(s)", 1, true),
    "and no line hedges the plural with a parenthetical. " .. shown(said))
end

-- ---- Perish Song ----------------------------------------------------------
-- What shipped here was a sentence no cart prints.  StartPerishText names
-- both sides and counts in digits.
do
  local said = linesFrom("CYNDAQUIL",
    { { id = "PERISH_SONG", pp = 5, maxPp = 5 } }, "GEODUDE", "PERISH_SONG")
  check(saw(said, "Both POKéMON will\nfaint in 3 turns!"),
    "Perish Song prints StartPerishText. " .. shown(said))
end

-- ---- and every one of them fits the box -----------------------------------
-- printMessage draws Chrome.wrap(self.message, TEXT_WIDTH) and stops at
-- TEXT_ROWS (home/text.asm:143, :397), so a third row is cut rather than
-- spilled.  A cart line that needs one, such as SpikesText's `cont` row
-- carrying <TARGET>, cannot be told on this path at all: engine messages set
-- self.message directly (src/ui/gen2/BattleState.lua) instead of going
-- through showPages, so nothing paginates them.  Hence Spikes is left alone
-- above, and every line that IS changed is checked to fit here.
do
  local Chrome = require("src.ui.gen2.Chrome")
  -- TEXT_WIDTH and TEXT_ROWS are file-locals in BattleState, so their values
  -- are repeated rather than required.
  local BOX_WIDTH, BOX_ROWS = 18, 2
  for _, line in ipairs({
    "It's super-\neffective!",
    "It's not very\neffective…",
    "There's no PP left\nfor this move!",
    "Hit 3 times!",
    "Both POKéMON will\nfaint in 3 turns!",
  }) do
    local rows = #Chrome.wrap(line, BOX_WIDTH)
    check(rows <= BOX_ROWS,
      ("\"%s\" wraps to %d rows, and the box draws %d")
        :format((line:gsub("\n", "\\n")), rows, BOX_ROWS))
  end
end

T.finish("gen2 battle text matches the cart")
