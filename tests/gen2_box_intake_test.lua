-- Everything that lands a mon in a box lands it healed (#1696).
--
--   luajit tests/gen2_box_intake_test.lua
--
-- ROM-free.  box_struct ends at Level and has no Status, no HP and no MaxHP
-- at all -- those three belong to party_struct alone (macros/ram.asm:7-40) --
-- so a boxed mon has nowhere to keep damage, and every screen that reads one
-- goes through CalcTempmonStats, whose .not_egg arm copies MON_MAXHP over
-- MON_HP and whose .zero_status arm blanks MON_STATUS before anything is
-- drawn (engine/pokemon/tempmon.asm:39-83).  The four intakes are the catch
-- that overflows to the PC (`.SendToPC` / SendMonIntoBox,
-- engine/items/item_effects.asm:604, engine/pokemon/move_mon.asm:942-1065),
-- the PC's own deposit, MOVE <PK><MN> W/O MAIL, and the bug contest's
-- full-party arm (engine/pokemon/caught_nickname.asm:72-90).
--
-- The asymmetry at the bottom is real cart behaviour and is the near-miss to
-- watch: a catch that fits in the PARTY goes through TryAddMonToParty
-- (item_effects.asm:551-556) and KEEPS its damage, so a fix that heals every
-- capture is as wrong as one that heals none.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 box intake")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local BoxMenu = require("src.ui.gen2.BoxMenu")
local Boxes = require("src.core.gen2.Boxes")
local BugContest = require("src.core.gen2.BugContest")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")

-- A mon hurt and statused exactly the way a ball lands on one.
local function hurt(species)
  return { species = species, nickname = species, name = species, level = 5,
    hp = 1, maxHp = 20, status = "sleep", statusTurns = 3,
    moves = { { id = "TACKLE", pp = 2, maxPp = 35 } } }
end

local function healthy(species)
  return { species = species, nickname = species, name = species, level = 5,
    hp = 20, maxHp = 20,
    moves = { { id = "TACKLE", pp = 35, maxPp = 35 } } }
end

local function newSave(party)
  return { party = party or {}, boxes = {}, boxNames = {}, currentBox = 1 }
end

-- ---- Boxes.enterBox, the shared seam --------------------------------------
do
  local mon = hurt("PIDGEY")
  Boxes.enterBox(mon)
  eq(mon.hp, 20, "a mon entering a box is at full HP")
  eq(mon.status, nil, "with no status byte to carry it")
  eq(mon.statusTurns, nil, "and no sleep counter either")
  eq(mon.moves[1].pp, 35, "RestorePPOfDepositedPokemon refilled its PP")

  -- .not_egg is skipped for an EGG: CalcTempmonStats writes 0 over MON_HP
  -- instead, which is what keeps a stored egg from reading as hatchable.
  local egg = hurt("TOGEPI")
  egg.isEgg = true
  Boxes.enterBox(egg)
  eq(egg.hp, 0, "an EGG stays at 0 HP")
  eq(egg.status, nil, "and still loses the status byte")

  -- A mon with no maxHp recorded must not come out with hp nil, which would
  -- read as fainted everywhere downstream.
  local odd = { species = "MISSINGNO", hp = 4 }
  Boxes.enterBox(odd)
  eq(odd.hp, 4, "a mon with no maxHp keeps the HP it had")
  eq(Boxes.enterBox(nil), nil, "and nil is handed straight back")
end

-- ---- the PC's own deposit -------------------------------------------------
--
-- Read while the mon is STILL IN THE BOX: this is what the PC's STATS screen
-- shows, and healing only on the way back out looks right in the party while
-- the storage screen still reports 1 HP and SLP.
do
  local save = newSave({ healthy("CYNDAQUIL"), hurt("PIDGEY"),
    healthy("GEODUDE") })
  local ok = Boxes.deposit(save, 2, 1)
  check(ok, "the hurt mon deposits")
  local boxed = Boxes.box(save, 1)[1]
  eq(boxed.species, "PIDGEY", "and it is the one in the box")
  eq(boxed.hp, 20, "sitting there at full HP")
  eq(boxed.status, nil, "with the status gone")
  eq(boxed.moves[1].pp, 35, "and its PP back")

  -- ...and the withdraw arm still hands back the same whole mon.
  local took
  ok, took = Boxes.withdraw(save, 1, 1)
  check(ok, "withdrawing it works")
  eq(took.hp, 20, "and it is still whole on the way out")
end

-- ---- MOVE <PK><MN> W/O MAIL ----------------------------------------------
do
  local function newInput()
    local input = { pressed = {} }
    function input:press(...)
      for _, button in ipairs({ ... }) do self.pressed[button] = true end
    end
    function input:wasPressed(button)
      if self.pressed[button] then
        self.pressed[button] = nil
        return true
      end
      return false
    end
    function input:isDown() return false end
    return input
  end

  local function press(screen, input, ...)
    for _, button in ipairs({ ... }) do
      input:press(button)
      screen:update(0)
    end
  end

  local function openMove(save)
    local input = newInput()
    local game = {
      input = input, save = save, data = { audio = {}, pokemon = {} },
      stack = { _items = {},
        push = function(self, s) self._items[#self._items + 1] = s end,
        pop = function(self) return table.remove(self._items) end,
        top = function(self) return self._items[#self._items] end,
      },
    }
    return BoxMenu.new(game, { save = save, mode = "move",
      onClose = function() end }), input
  end

  -- party -> box: .CopyToBox writes a box_struct, so the damage cannot follow.
  local save = newSave({ hurt("PIDGEY"), healthy("CYNDAQUIL"),
    healthy("GEODUDE") })
  local menu, input = openMove(save)
  press(menu, input, "left")
  eq(menu.boxIndex, 0, "the move screen walks left to the PARTY")
  press(menu, input, "a", "a")
  eq(menu.phase, "insert", "MOVE opens the insert cursor")
  press(menu, input, "right", "a")
  eq(#save.party, 2, "the hurt mon left the party")
  local boxed = Boxes.box(save, 1)[1]
  eq(boxed and boxed.nickname, "PIDGEY", "and landed in BOX1")
  eq(boxed and boxed.hp, 20, "at full HP")
  eq(boxed and boxed.status, nil, "with no status")
  eq(boxed and boxed.moves[1].pp, 35, "and full PP")

  -- party -> party is the same screen's reorder, and party_struct HAS the
  -- three fields, so this arm must leave the damage exactly where it was.
  save = newSave({ hurt("PIDGEY"), healthy("CYNDAQUIL"), healthy("GEODUDE") })
  menu, input = openMove(save)
  press(menu, input, "left")
  eq(menu.boxIndex, 0, "back on the party")
  press(menu, input, "a", "a", "down", "down", "a")
  eq(#save.party, 3, "the party still has three")
  local moved
  for _, mon in ipairs(save.party) do
    if mon.nickname == "PIDGEY" then moved = mon end
  end
  eq(moved and moved.hp, 1, "a party-to-party move keeps the damage")
  eq(moved and moved.status, "sleep", "and keeps the status")
end

-- ---- the bug contest's full-party arm -------------------------------------
do
  local save = newSave({ healthy("A"), healthy("B"), healthy("C"),
    healthy("D"), healthy("E"), healthy("F") })
  save.currentBox = 2
  save.playerName = "GOLD"
  BugContest.start(save)
  BugContest.switchCaught(save, hurt("SCYTHER"))
  local result = BugContest.collectCaughtMon(save, 6)
  eq(result, BugContest.BOXED_MON, "a full party sends the contest catch to a box")
  local boxed = Boxes.box(save, 2)[1]
  eq(boxed and boxed.nickname, "SCYTHER", "it is in the current box")
  eq(boxed and boxed.hp, 20, "at full HP")
  eq(boxed and boxed.status, nil, "with no status")
  eq(boxed and boxed.moves[1].pp, 35, "and its PP restored")
end

-- ---- the catch that overflows to the PC -----------------------------------
--
-- The whole chain, through the real BattleState: a ball that lands while the
-- party is full runs `.SendToPC`, and what the PC's STATS screen then reads
-- is the box_struct SendMonIntoBox wrote.
do
  local TYPES = { NORMAL = { id = "NORMAL", index = 0,
    category = "physical" } }
  local MOVES = { TACKLE = { id = "TACKLE", name = "TACKLE", power = 35,
    type = "NORMAL", accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" } }
  local POKEMON = {
    growthRates = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1,
      squared = 0, linear = 0, constant = 0 } },
    CYNDAQUIL = {
      id = "CYNDAQUIL", index = 155, name = "CYNDAQUIL",
      baseStats = { hp = 39, attack = 52, defense = 43, speed = 65,
        specialAttack = 60, specialDefense = 50 },
      types = { "NORMAL", "NORMAL" }, catchRate = 45, baseExp = 65,
      growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 31,
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
    pokemon = POKEMON, moves = MOVES,
    type_chart = { types = TYPES, matchups = {} },
    items = { POKE_BALL = { id = "POKE_BALL", name = "POKe BALL",
      pocket = "BALL" } },
  }
  local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
  perfect.hp = Mon.hpDV(perfect)

  -- partySize 6 fills the party so the catch overflows; 5 leaves it room.
  local function catch(partySize)
    Input:init()
    local party = {}
    for i = 1, partySize do
      local mon = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
      mon.nickname = "MON" .. i
      mon.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
      party[i] = mon
    end
    local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
    wild.moves = { { id = "TACKLE", pp = 4, maxPp = 35 } }
    -- one HP and asleep: what a ball usually lands on
    wild.hp = 1
    wild.status = "sleep"
    wild.statusTurns = 3
    local save = { party = party, inventory = { POKE_BALL = 1 },
      currentBox = 3, boxes = {}, boxNames = {} }
    local game = {
      data = DATA, save = save, input = Input, options = {},
      stack = { push = function() end, pop = function() end,
        top = function() return nil end },
    }
    -- random 0: the catch roll always lands.
    local battle = Battle.new({ data = DATA, party = party, wild = wild,
      save = save, random = function() return 0 end })
    local screen = BattleState.new(game, { battle = battle, save = save })
    screen:useItem("POKE_BALL")
    return battle, save, wild
  end

  local battle, save, wild = catch(6)
  eq(battle.outcome, "caught", "the ball lands on a full party")
  eq(#save.party, 6, "the party did not grow")
  local boxed = Boxes.box(save, 3)[1]
  eq(boxed, wild, "SendMonIntoBox put the catch in slot 1 of the current box")
  eq(boxed and boxed.hp, boxed and boxed.maxHp,
    "and the PC holds it at full HP")
  eq(boxed and boxed.status, nil, "with no status on the STATS screen")
  eq(boxed and boxed.statusTurns, nil, "and no sleep counter behind it")
  eq(boxed and boxed.moves[1].pp, 35, "PP refilled with the rest")

  -- The other half of the cart's asymmetry.
  battle, save, wild = catch(5)
  eq(battle.outcome, "caught", "the ball lands with room in the party")
  eq(save.party[6], wild, "and TryAddMonToParty keeps it in the party")
  eq(wild.hp, 1, "at the 1 HP it was caught on")
  eq(wild.status, "sleep", "still asleep")
  eq(wild.moves[1].pp, 4, "and with the PP it had left")
  eq(Boxes.count(save, 3), 0, "nothing went to the PC")
end

S.finish()
