-- Morning Sun / Synthesis / Moonlight: BattleCommand_TimeBasedHealContinue
-- (engine/battle/effect_commands.asm:6374) walks a four-rung .Multipliers
-- table from the half rung -- the wrong wTimeOfDay steps down, sun up, rain
-- and sandstorm down (#1751).  World:startBattle is where the hour comes from.
--
--   luajit tests/gen2_timed_heal_test.lua   -- ROM-free

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 timed heal")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")
local Effects = require("src.battle.gen2.Effects")
local Mon = require("src.battle.gen2.Mon")

-- constants/ram_constants.asm:137-140, wTimeOfDay: MORN_F 0, DAY_F 1, NITE_F 2,
-- DARKNESS_F 3.
local MORN, DAY, NITE, DARK = 0, 1, 2, 3

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
  FLYING = { id = "FLYING", index = 2, category = "physical" },
  GRASS = { id = "GRASS", index = 22, category = "special" },
  WATER = { id = "WATER", index = 21, category = "special" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" },
  -- data/moves/moves.asm: three 5 PP status moves that differ only in effect.
  SYNTHESIS = { id = "SYNTHESIS", name = "SYNTHESIS", power = 0,
    type = "GRASS", accuracy = 100, pp = 5, effect = "EFFECT_SYNTHESIS" },
  MORNING_SUN = { id = "MORNING_SUN", name = "MORNING SUN", power = 0,
    type = "NORMAL", accuracy = 100, pp = 5, effect = "EFFECT_MORNING_SUN" },
  MOONLIGHT = { id = "MOONLIGHT", name = "MOONLIGHT", power = 0,
    type = "NORMAL", accuracy = 100, pp = 5, effect = "EFFECT_MOONLIGHT" },
  SUNNY_DAY = { id = "SUNNY_DAY", name = "SUNNY DAY", power = 0,
    type = "FIRE", accuracy = 100, pp = 5, effect = "EFFECT_SUNNY_DAY" },
  RAIN_DANCE = { id = "RAIN_DANCE", name = "RAIN DANCE", power = 0,
    type = "WATER", accuracy = 100, pp = 5, effect = "EFFECT_RAIN_DANCE" },
}

local GROWTH = {
  GROWTH_MEDIUM_SLOW = { numerator = 6, denominator = 5, squared = -15,
    linear = 100, constant = 140 },
}

local POKEMON = {
  growthRates = GROWTH,
  CHIKORITA = {
    id = "CHIKORITA", index = 152, name = "CHIKORITA",
    baseStats = { hp = 45, attack = 49, defense = 65, speed = 45,
      specialAttack = 49, specialDefense = 65 },
    types = { "GRASS", "GRASS" }, catchRate = 45, baseExp = 64,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "FLYING" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_SLOW", genderRatio = 127,
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

local function zeroRandom() return 0 end

local function newBattle(opts)
  opts = opts or {}
  local player = Mon.new(DATA, "CHIKORITA", 20, { dvs = perfect })
  player.moves = {
    { id = "SYNTHESIS", pp = 5, maxPp = 5 },
    { id = "MORNING_SUN", pp = 5, maxPp = 5 },
    { id = "MOONLIGHT", pp = 5, maxPp = 5 },
    { id = "SUNNY_DAY", pp = 5, maxPp = 5 },
  }
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local battle = Battle.new({
    data = DATA,
    party = { player },
    wild = wild,
    random = zeroRandom,
    timeOfDay = opts.timeOfDay,
  })
  battle:takeEvents()
  return battle, player, wild
end

-- ------------------------------------------------------------- the ladder

local frac = Effects.timeBasedHealFraction
check(type(frac) == "function",
  "Effects models the whole command, not just the weather half")

-- .Multipliers itself (effect_commands.asm:6450-6454).
local RUNGS = { 1 / 8, 1 / 4, 1 / 2, 1 }
eq(Effects.HEAL_MULTIPLIERS[1], RUNGS[1], "rung 0 is an eighth")
eq(Effects.HEAL_MULTIPLIERS[2], RUNGS[2], "rung 1 is a quarter")
eq(Effects.HEAL_MULTIPLIERS[3], RUNGS[3], "rung 2 is a half, the default")
eq(Effects.HEAL_MULTIPLIERS[4], RUNGS[4], "rung 3 is the whole bar")

-- The `ld b, MORN_F / DAY_F / NITE_F` each of the three entry points loads
-- (effect_commands.asm:6362-6371).
eq(Effects.SUN_HEAL.EFFECT_MORNING_SUN, MORN, "Morning Sun wants MORN")
eq(Effects.SUN_HEAL.EFFECT_SYNTHESIS, DAY, "Synthesis wants DAY")
eq(Effects.SUN_HEAL.EFFECT_MOONLIGHT, NITE, "Moonlight wants NITE")

-- The six cells that matter, read as Synthesis: its own hour on the top row,
-- any other hour on the bottom.
eq(frac(nil, DAY, DAY), 1 / 2, "right hour, clear sky: a half")
eq(frac("sun", DAY, DAY), 1, "right hour in sun: the whole bar")
eq(frac("rain", DAY, DAY), 1 / 4, "right hour in rain: a quarter")
eq(frac(nil, DAY, NITE), 1 / 4, "wrong hour, clear sky: a quarter")
eq(frac("sun", DAY, NITE), 1 / 2, "wrong hour in sun: a half")
eq(frac("rain", DAY, NITE), 1 / 8, "wrong hour in rain: an eighth")

-- Sandstorm takes the same `dec c / dec c` arm rain does.
eq(frac("sandstorm", DAY, DAY), 1 / 4, "sandstorm is rain's rung")
eq(frac("sandstorm", DAY, NITE), 1 / 8, "at either hour")

-- Every hour that is not the move's own is the wrong one, DARKNESS included.
eq(frac(nil, DAY, MORN), 1 / 4, "morning is the wrong hour for Synthesis")
eq(frac(nil, DAY, DARK), 1 / 4, "and so is DARKNESS")
eq(frac(nil, MORN, MORN), 1 / 2, "Morning Sun at dawn is the top row")
eq(frac(nil, MORN, DAY), 1 / 4, "Morning Sun in the afternoon is not")
eq(frac(nil, NITE, NITE), 1 / 2, "Moonlight at night is the top row")
eq(frac(nil, NITE, DAY), 1 / 4, "Moonlight at noon is not")

-- wTimeOfDay by name, the spelling World keeps.
eq(frac(nil, DAY, "DAY"), 1 / 2, "the DAY spelling reads as DAY_F")
eq(frac(nil, DAY, "NITE"), 1 / 4, "and NITE as NITE_F")
eq(frac(nil, NITE, "NITE"), 1 / 2, "Moonlight likewise")

-- `ld a, [wLinkMode] / and a / jr nz, .Weather` (effect_commands.asm:6396-6399):
-- a battle with no clock skips the time term rather than failing the hour.
eq(frac(nil, DAY, nil), 1 / 2, "no clock, no time term")
eq(frac("sun", DAY, nil), 1, "the weather half still walks")

-- Gen 3's 2/3 is not on this ladder anywhere.
do
  local offLadder = {}
  for _, weather in ipairs({ "none", "sun", "rain", "sandstorm" }) do
    for _, wants in ipairs({ MORN, DAY, NITE }) do
      for hour = MORN, DARK do
        local got = frac(weather ~= "none" and weather or nil, wants, hour)
        local onLadder = false
        for _, rung in ipairs(RUNGS) do
          if got == rung then onLadder = true end
        end
        if not onLadder then
          offLadder[#offLadder + 1] = ("%s/%d/%d=%s")
            :format(weather, wants, hour, tostring(got))
        end
      end
    end
  end
  eq(#offLadder, 0,
    "every cell lands on a .Multipliers rung: " .. table.concat(offLadder, " "))
end
check(Effects.weatherHealFraction == nil
  or math.abs(Effects.weatherHealFraction("sun") - 2 / 3) > 0.0001,
  "and nothing still answers Gen 3's two thirds in sun")

-- ------------------------------------------------------- through a battle

-- wTimeOfDay reaches the handler (effect_commands.asm:6401-6404).
do
  local battle = newBattle({ timeOfDay = NITE })
  eq(battle.timeOfDay, NITE, "Battle.new carries wTimeOfDay")
end

local function healedBy(move, timeOfDay, weather)
  local battle, player = newBattle({ timeOfDay = timeOfDay })
  battle.weather = weather
  battle.weatherTurns = weather and 5 or nil
  player.hp = math.floor(player.maxHp / 2)
  local before = player.hp
  battle:useMove(player, battle.enemy, move)
  return player.hp - before, player.maxHp, battle:takeEvents()
end

do
  local healed, maxHp = healedBy("SYNTHESIS", NITE)
  eq(healed, math.floor(maxHp / 4), "Synthesis at night restores a quarter")
  check(healed ~= math.floor(maxHp / 2),
    "which is not the flat half the unfixed move gave")
end

do
  local healed, maxHp, events = healedBy("SYNTHESIS", DAY)
  eq(healed, math.floor(maxHp / 2), "Synthesis in the day restores a half")
  local said = false
  for _, event in ipairs(events) do
    if event.text and event.text:find("regained health!", 1, true) then
      said = true
    end
  end
  check(said, "and still says so")
end

-- Sun on the top rung is GetMaxHP, not a bigger fraction, so the bar fills
-- from wherever it started rather than from half.
do
  local battle, player = newBattle({ timeOfDay = DAY })
  battle.weather, battle.weatherTurns = "sun", 5
  player.hp = 1
  battle:useMove(player, battle.enemy, "SYNTHESIS")
  eq(player.hp, player.maxHp,
    "Synthesis in the day under Sunny Day fills the bar from 1 HP")

  battle, player = newBattle({ timeOfDay = DAY })
  battle.weather, battle.weatherTurns = "sun", 5
  player.hp = math.floor(player.maxHp / 2)
  battle:useMove(player, battle.enemy, "SYNTHESIS")
  eq(player.hp, player.maxHp, "and from half")
end

do
  local healed, maxHp = healedBy("SYNTHESIS", NITE, "rain")
  eq(healed, math.floor(maxHp / 8), "Synthesis at night in rain is an eighth")
end

do
  local healed, maxHp = healedBy("MOONLIGHT", NITE)
  eq(healed, math.floor(maxHp / 2), "Moonlight at night restores a half")
  healed = healedBy("MOONLIGHT", DAY)
  eq(healed, math.floor(maxHp / 4), "and a quarter at noon")
  healed = healedBy("MORNING_SUN", MORN)
  eq(healed, math.floor(maxHp / 2), "Morning Sun at dawn restores a half")
  healed = healedBy("MORNING_SUN", NITE)
  eq(healed, math.floor(maxHp / 4), "and a quarter at night")
end

-- At NITE only Moonlight is on its top rung.
do
  local night = {}
  for _, move in ipairs({ "MORNING_SUN", "SYNTHESIS", "MOONLIGHT" }) do
    night[move] = healedBy(move, NITE)
  end
  check(night.MOONLIGHT > night.SYNTHESIS,
    "Moonlight beats Synthesis at night")
  eq(night.MORNING_SUN, night.SYNTHESIS,
    "and the two daytime moves tie below it")
end

-- effect_commands.asm:6443-6448: a full-HP user gets HPIsFullText and no heal,
-- whatever the clock says.
do
  local battle, player = newBattle({ timeOfDay = NITE })
  battle:useMove(player, battle.enemy, "SYNTHESIS")
  eq(player.hp, player.maxHp, "a full-HP user is not healed")
  local said = false
  for _, event in ipairs(battle:takeEvents()) do
    if event.text and event.text:find("HP is full", 1, true) then said = true end
  end
  check(said, "and hears HPIsFullText instead")
end

-- ------------------------------------------------- the overworld's clock

-- World:timeOfDayId is wTimeOfDay off the RTC hour
-- (engine/tilesets/timeofday_pals.asm:5-11), and startBattle hands it over.
do
  local World = require("src.world.gen2.World")
  local Screens = require("src.ui.Screens")

  local pushed
  local realPush = Screens.push
  Screens.push = function(_, id, opts)
    if id == "Gen2BattleState" then pushed = opts end
  end

  local ok, err = pcall(function()
    for _, hour in ipairs({ { "MORN", MORN }, { "DAY", DAY },
        { "NITE", NITE }, { "DARK", DARK } }) do
      local mon = Mon.new(DATA, "CHIKORITA", 20, { dvs = perfect })
      local game = {
        data = DATA,
        save = { version = "gold", player = { name = "GOLD", id = 1234 },
          party = { mon }, inventory = {}, boxes = {} },
      }
      game.stack = { pop = function() end }
      local world = World.new(game)
      world.tod = hour[1]
      -- No map, so DoBattleTransition has nothing to wipe and the battle
      -- screen comes straight in (World:pushBattleTransition).
      world.map = nil
      pushed = nil
      world:startBattle({ wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect }) })
      eq(pushed and pushed.battle and pushed.battle.timeOfDay, hour[2],
        "a battle started at " .. hour[1] .. " carries that wTimeOfDay")
    end
  end)

  Screens.push = realPush
  check(ok, "the World seam ran: " .. tostring(err))
end

S.finish()
