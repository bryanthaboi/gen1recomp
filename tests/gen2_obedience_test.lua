-- Traded-mon obedience: BattleCommand_CheckObedience
-- (engine/battle/effect_commands.asm:642).
--
--   luajit tests/gen2_obedience_test.lua
--
-- ROM-free.  An outsider mon (OT id differs from wPlayerID) above the
-- badge-gated cap -- 10 bare, 30 with HIVEBADGE, 50 with FOGBADGE, 70 with
-- STORMBADGE, unlimited with RISINGBADGE -- rolls to obey, and past the
-- rolls either uses another move, naps, hits itself or loafs.  A native mon
-- never disobeys at any level; the Violet City ROCKY (OT 48926) is the
-- walkthrough's own warning case.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 obedience")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  ROCK = { id = "ROCK", index = 5, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  ROCK_THROW = { id = "ROCK_THROW", name = "ROCK THROW", power = 50,
    type = "ROCK", accuracy = 100, pp = 15, effect = "EFFECT_NORMAL_HIT" },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local POKEMON = {
  growthRates = GROWTH,
  ONIX = {
    id = "ONIX", index = 95, name = "ONIX",
    baseStats = { hp = 35, attack = 45, defense = 160, speed = 70,
      specialAttack = 30, specialDefense = 45 },
    types = { "ROCK", "ROCK" }, catchRate = 45, baseExp = 108,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = {} },
  items = {},
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local PLAYER_ID = 1234
local ROCKY_OT = 48926

local function rolls(queue, fill)
  local at = 0
  return function(n)
    at = at + 1
    local value = queue[at]
    if value == nil then value = fill or 0 end
    return value % math.max(1, n or 1)
  end
end

local function newBattle(opts)
  opts = opts or {}
  local mon = Mon.new(DATA, "ONIX", opts.level or 30, { dvs = perfect,
    nickname = "ROCKY" })
  mon.otId = opts.otId
  mon.moves = {
    { id = "ROCK_THROW", pp = 15, maxPp = 15 },
    { id = "TACKLE", pp = opts.tacklePp or 35, maxPp = 35 },
  }
  local wild = Mon.new(DATA, "PIDGEY", 10, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({ data = DATA, party = { mon }, wild = wild,
    save = { player = { id = PLAYER_ID, badges = opts.badges or {} } },
    random = opts.random })
  return battle, mon, wild
end

-- Any event carrying the line: the move-use line rides a `move` event and
-- the nap a `status` event, so the kind is not filtered.
local function findText(events, text)
  for _, event in ipairs(events or {}) do
    if event.text == text then return true end
  end
  return false
end

-- ---- who is an outsider ---------------------------------------------------
do
  local battle, mon = newBattle({ otId = PLAYER_ID })
  eq(battle:isOutsider(mon), false, "the player's own OT id is native")
  battle, mon = newBattle({ otId = ROCKY_OT })
  eq(battle:isOutsider(mon), true, "KYLE's 48926 is an outsider")
  battle, mon = newBattle({})
  eq(battle:isOutsider(mon), false,
    "no recorded OT (the port's own catches) is the player's own")
end

-- ---- the badge ladder -----------------------------------------------------
do
  local battle = newBattle({})
  eq(battle:obedienceLevel(), 10, "no badges: level 10")
  battle = newBattle({ badges = { HIVE = true } })
  eq(battle:obedienceLevel(), 30, "HIVEBADGE: 30")
  battle = newBattle({ badges = { HIVE = true, FOG = true } })
  eq(battle:obedienceLevel(), 50, "FOGBADGE: 50")
  battle = newBattle({ badges = { STORM = true } })
  eq(battle:obedienceLevel(), 70, "STORMBADGE: 70")
  battle = newBattle({ badges = { RISING = true } })
  eq(battle:obedienceLevel(), Mon.MAX_LEVEL + 1,
    "RISINGBADGE: nothing ever disobeys")
end

-- ---- who never disobeys ---------------------------------------------------
do
  -- A native mon at any level, whatever the rolls come up.
  local battle = newBattle({ otId = PLAYER_ID, level = 80,
    random = rolls({}, 255) })
  eq(battle:checkObedience("ROCK_THROW"), false,
    "a native mon never checks at all")

  -- An outsider at or under the cap.
  battle = newBattle({ otId = ROCKY_OT, level = 30,
    badges = { HIVE = true }, random = rolls({}, 255) })
  eq(battle:checkObedience("ROCK_THROW"), false,
    "an outsider AT the cap obeys without rolling")

  -- An outsider above the cap whose first roll lands under it.
  battle = newBattle({ otId = ROCKY_OT, level = 30,
    random = rolls({ 5 }) })
  eq(battle:checkObedience("ROCK_THROW"), false,
    "a first roll under the cap obeys")
end

-- ---- the disobedience ladder ----------------------------------------------
-- Level 30, no badges: cap 10, limit 40, margin 20.
do
  -- Second roll under the cap: use ANOTHER move instead.
  local battle, mon, wild = newBattle({ otId = ROCKY_OT, level = 30,
    random = rolls({ 39, 5, 0 }, 1) })
  local hpBefore = wild.hp
  eq(battle:checkObedience("ROCK_THROW"), true, "the mon went its own way")
  -- UsedMoveText breaks after the user's name by construction: _UsedMove1Text
  -- is `text_start` + `line "used @"` (data/text/common_2.asm:339).
  check(findText(battle.events, "ROCKY\nused TACKLE!"),
    "and used the OTHER move")
  check(wild.hp < hpBefore, "which really landed")
  eq(mon.moves[2].pp, 34, "spending the substituted move's PP")

  -- With no alternative the use-instead arm falls through to loafing.
  battle, mon = newBattle({ otId = ROCKY_OT, level = 30, tacklePp = 0,
    random = rolls({ 39, 5, 45, 0 }) })
  eq(battle:checkObedience("ROCK_THROW"), true, "still disobeys")
  check(findText(battle.events, "ROCKY is loafing around."),
    "but can only loaf")

  -- Nap: the margin roll under level - cap.
  battle, mon = newBattle({ otId = ROCKY_OT, level = 30,
    random = rolls({ 39, 39, 5, 2 }) })
  eq(battle:checkObedience("ROCK_THROW"), true, "napped instead")
  eq(mon.status, "sleep", "BeganToNap writes sleep straight in")
  eq(mon.statusTurns, 3, "1-7 turns, written straight into the status byte")
  check(findText(battle.events, "ROCKY began to nap!"), "with its own line")

  -- Self-hit: the margin roll in the second band.
  battle, mon = newBattle({ otId = ROCKY_OT, level = 30,
    random = rolls({ 39, 39, 25 }) })
  local before = mon.hp
  eq(battle:checkObedience("ROCK_THROW"), true, "won't obey")
  check(findText(battle.events, "ROCKY won't obey!"), "says so")
  check(findText(battle.events, "It hurt itself in its confusion!"),
    "and hits itself (HitConfusion)")
  check(mon.hp < before, "for real damage")

  -- Loafing: past both margin bands, one of the four lines.
  battle, mon = newBattle({ otId = ROCKY_OT, level = 30,
    random = rolls({ 39, 39, 45, 2 }) })
  eq(battle:checkObedience("ROCK_THROW"), true, "loafed")
  check(findText(battle.events, "ROCKY turned away!"),
    "line 2 of the four-way pick")
end

-- ---- through the real turn ------------------------------------------------
do
  -- The disobedient turn is spent: the enemy still moves, ROCK THROW's PP
  -- is untouched, and nothing hit the enemy.  The queue's first roll feeds
  -- the wild AI's own move pick, which runs before the player's half.
  local battle, mon, wild = newBattle({ otId = ROCKY_OT, level = 30,
    random = rolls({ 0, 39, 39, 45, 2 }, 1) })
  local hpBefore = wild.hp
  local events = battle:takeTurn({ kind = "move", move = "ROCK_THROW" })
  check(findText(events, "ROCKY turned away!"), "the turn opens on the loaf")
  eq(mon.moves[1].pp, 15, "no PP left the disobeyed move")
  eq(wild.hp, hpBefore, "and the enemy was never touched")
  check(findText(events, "Wild PIDGEY\nused TACKLE!")
    or findText(events, "PIDGEY\nused TACKLE!"),
    "while the enemy's half of the turn still ran")

  -- The second half of a charge move is exempt (CheckUserIsCharging): a
  -- stored charge always lands.
  battle, mon = newBattle({ otId = ROCKY_OT, level = 30,
    random = rolls({}, 255) })
  battle:volatile(mon).chargeMove = "ROCK_THROW"
  eq(battle:checkObedience("ROCK_THROW"), false,
    "a charging mon is not checked")
end

S.finish()
