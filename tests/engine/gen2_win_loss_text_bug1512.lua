-- engine/battle/core.asm:2310-2323 (WinTrainerBattle), :2763-2782 (LostBattle),
-- home/trainers.asm:120 and :230 (PrintWinLossText)

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")
local World = require("src.world.gen2.World")

local LEVEL = 10

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 100, pp = 35, effect = "EFFECT_NORMAL_HIT" },
}

local POKEMON = {
  growthRates = {
    GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
      linear = 0, constant = 0 },
  },
  RATTATA = {
    id = "RATTATA", index = 19, name = "RATTATA",
    baseStats = { hp = 30, attack = 56, defense = 35, speed = 72,
      specialAttack = 25, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 51,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = { NORMAL = { id = "NORMAL", index = 0,
    category = "physical" } }, matchups = {} },
  items = {},
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local function mon()
  local m = Mon.new(DATA, "RATTATA", LEVEL, { dvs = perfect })
  m.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  return m
end

local function newSave()
  return { player = { name = "GOLD", money = 1000, id = 4242 },
    mom = { savedMoney = 0 }, party = {} }
end

local function newBattle(trainer, battleType)
  local save = newSave()
  local battle = Battle.new({ data = DATA, party = { mon() },
    trainer = trainer, battleType = battleType, save = save,
    random = function(n) return 99 % math.max(1, n or 1) end })
  return battle, save
end

local function trainerRecord(extra)
  local record = { name = "SAGE CHOW", baseMoney = 3, party = { mon() } }
  for key, value in pairs(extra or {}) do record[key] = value end
  return record
end

local function kinds(events)
  local out = {}
  for i, event in ipairs(events or {}) do out[i] = event.kind end
  return table.concat(out, ",")
end

local function indexOf(events, kind)
  for i, event in ipairs(events or {}) do
    if event.kind == kind then return i, event end
  end
  return nil
end

-- The win arm: defeated line, frontpic slide-in, the trainer's own line, money.
do
  local battle = newBattle(trainerRecord({ winText = "Th-Thank you!" }))
  battle.enemy.hp = 0
  T.check(battle:resolveFaints(), "the last enemy mon ends the battle")
  local events = battle:takeEvents()
  local defeated = indexOf(events, "faint")
  local ret = indexOf(events, "trainer-return")
  local win, winEvent = indexOf(events, "win-text")
  local money = indexOf(events, "money")
  T.check(ret and win and money, "all three win rows are queued: " ..
    kinds(events))
  T.check(defeated < ret, "the last faint event precedes the pic's return")
  T.check(ret < win, "the frontpic slides back in before the line")
  T.check(win < money, "and PrintWinLossText runs before the payout")
  T.eq(winEvent.text, "Th-Thank you!", "the struct's win text is printed")
end

-- The pic comes back whether or not there is a line: the DEBUG_BATTLE_F skip
-- sits in front of PrintWinLossText alone.
do
  local battle = newBattle(trainerRecord())
  battle.enemy.hp = 0
  battle:resolveFaints()
  local events = battle:takeEvents()
  T.check(indexOf(events, "trainer-return"), "the slide-in is unconditional")
  T.eq(indexOf(events, "win-text"), nil, "with no line to print")
end

-- A wild battle has no trainer and no line.
do
  local save = newSave()
  local wild = mon()
  local battle = Battle.new({ data = DATA, party = { mon() }, wild = wild,
    save = save, random = function(n) return 99 % math.max(1, n or 1) end })
  battle.enemy.hp = 0
  battle:resolveFaints()
  local events = battle:takeEvents()
  T.eq(indexOf(events, "trainer-return"), nil, "no frontpic to slide back in")
  T.eq(indexOf(events, "win-text"), nil, "and nothing to print")
end

-- The loss arm: only BATTLETYPE_CANLOSE reaches PrintWinLossText.
do
  local battle = newBattle(trainerRecord({ winText = "Th-Thank you!",
    lossText = "...Too weak..." }), Battle.BATTLETYPE_CANLOSE)
  battle.player.hp = 0
  T.check(battle:resolveFaints(), "the whiteout ends the battle")
  local events = battle:takeEvents()
  local _, lossEvent = indexOf(events, "win-text")
  T.check(lossEvent, "the loss line is printed: " .. kinds(events))
  T.eq(lossEvent.text, "...Too weak...", "wLossTextPointer, not the win one")
end

do
  local battle = newBattle(trainerRecord({ lossText = "...Too weak..." }))
  battle.player.hp = 0
  battle:resolveFaints()
  local events = battle:takeEvents()
  T.eq(indexOf(events, "win-text"), nil, "an ordinary loss whites out instead")
end

-- wWinTextPointer / wLossTextPointer: the map object's struct, or whatever
-- `winlosstext` overwrote the pair with.
do
  local world = { text = { ["3:4000"] = "Th-Thank you!",
    ["3:4100"] = "...Too weak...", ["3:4200"] = "Scripted win." } }
  world.vm = { trainerObject = { winText = "3:4000", lossText = "3:4100" } }
  local win, loss = World.trainerWinLossText(world)
  T.eq(win, "Th-Thank you!", "the struct's win text is decoded")
  T.eq(loss, "...Too weak...", "and its loss text with it")

  world.vm.winLossArmed = true
  world.vm.winTextOverride = "3:4200"
  win, loss = World.trainerWinLossText(world)
  T.eq(win, "Scripted win.", "`winlosstext` overwrites the pointer")
  -- winlosstext writes BOTH pointers; its 0 loss argument destroyed the
  -- struct's value (engine/overworld/scripting.asm:651)
  T.eq(loss, nil, "and a 0 loss argument zeroes the loss pointer with it")

  world.vm.trainerObject = nil
  world.vm.winTextOverride = nil
  world.vm.winLossArmed = nil
  win, loss = World.trainerWinLossText(world)
  T.eq(win, nil, "a battle with no trainer object has no line")
  T.eq(loss, nil, "on either side")

  world.vm = nil
  T.eq(World.trainerWinLossText(world), nil, "and neither has one with no VM")
end

-- The screen side: the slide-in owns the frames the way SlideBattlePicOut
-- does, and the line pages like the map text it is.
local BattleState = require("src.ui.gen2.BattleState")

local function newScreen(battle, queue, image)
  return setmetatable({
    battle = battle, queue = queue, picHidden = {}, evolvable = {},
    phase = "resolving", messageTimer = 0, enemyTrainerImage = image,
  }, { __index = BattleState })
end

do
  local battle = newBattle(trainerRecord({ winText = "Th-Thank you!" }))
  local screen = newScreen(battle, { { kind = "trainer-return" },
    { kind = "win-text", text = "Th-Thank you!" } }, {})
  screen:advanceQueue()
  T.eq(screen.winSlide, 0, "the slide starts on the frame the event runs")
  T.check(screen.winSliding, "and owns the screen while it runs")
  T.check(screen.showEnemyTrainer, "the beaten trainer is back on the field")
  T.eq(screen.picHidden.enemy, false, "in the box the fainted mon left empty")
  T.eq(#screen.queue, 1, "the line is still waiting behind it")
end

do
  local battle = newBattle(trainerRecord())
  local screen = newScreen(battle, { { kind = "trainer-return" },
    { kind = "win-text", text = "Th-Thank you!\fReally." } }, nil)
  screen:advanceQueue()
  T.eq(screen.winSlide, nil, "no cached pic, no slide")
  T.eq(screen.message, "Th-Thank you!", "the line runs straight away")
  T.check(screen.messagePages, "with its `para` page held back")
  T.check(screen:nextPage(), "which the queue waits for")
  T.eq(screen.message, "Really.", "before the second page shows")
end

T.finish("gen2 win loss text bug 1512")
