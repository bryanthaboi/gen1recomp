-- #1556, the two battle jingles: _NewDexDataText's sound_slot_machine_start
-- (data/text/common_3.asm:285) on a first catch, and _LearnedMoveText's
-- sound_dex_fanfare_50_79 (data/text/common_3.asm:119) on a level-up move.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1556_battle.lua \
--     perl -e 'alarm 420; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--   POKEPORT_SHOT_DIR=/tmp/gold-bug1556-battle   (default)
--
-- Both ride the message queue's `sfx` + `waitSfx` keys, which the "Gotcha!"
-- line and the "grew to level" line already used -- the two lines next door
-- to them did not.  So the ear is comparing neighbours: the catch jingle must
-- be followed by a SECOND, different one over the #DEX line, and the level-up
-- fanfare by a second over "learned".
local U = require("tests.drivers.util")

local Bag = require("src.inventory.Bag")
local PackMenu = require("src.ui.gen2.PackMenu")
local Mon = require("src.battle.gen2.Mon")
local Sound = require("src.core.Sound")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1556-battle"

  local heard = {}
  local realPlay = Sound.play
  Sound.play = function(data, name)
    heard[#heard + 1] = name
    return realPlay(data, name)
  end
  local function reset() heard = {} end
  -- A throw, its wobbles and a level-up all animate for a while; a report taken
  -- before the jingle lands reads as silence.
  local function awaitSfx(name, frames, want)
    want = want or 1
    for i = 1, (frames or 200) do
      local seen = 0
      for _, n in ipairs(heard) do if n == name then seen = seen + 1 end end
      if seen >= want then return true end
      if i % 5 == 0 then U.tap(game, "a") else U.wait(2) end
    end
    return false
  end
  local function report(label, want)
    U.log(label, #heard > 0 and table.concat(heard, ", ") or "(silence)")
    U.log("   want:", want)
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")
  local save, data = game.save, game.data

  local function battleScreen()
    local top = game.stack:top()
    return (top and top.battle) and top or nil
  end

  local function tapUntil(predicate, tries, btn)
    for _ = 1, tries or 400 do
      if predicate() then return true end
      U.tap(game, btn or "a")
      U.wait(2)
    end
    return predicate()
  end

  -- ---- 1. a first catch: "Gotcha!" then the #DEX line ---------------------
  save.party = { Mon.new(data, "CYNDAQUIL", 20) }
  save.inventory, save.bagOrder = {}, {}
  Bag.add(save, "MASTER_BALL", 1, data)
  save.pokedexReceived = true
  save.pokedex = { seen = {}, caught = {} }

  local wild = Mon.new(data, "PIDGEY", 3)
  assert(wild, "the cache carries no PIDGEY")
  assert(world:startBattle({ wild = wild }), "the wild battle refused to start")
  assert(tapUntil(function()
    local screen = battleScreen()
    return screen ~= nil and screen.phase == "menu"
  end), "the battle never reached BattleMenu")
  local screen = battleScreen()

  -- BattleMenuHeader's 2x2 grid: 1 FIGHT / 2 PkMn, 3 PACK / 4 RUN.
  if screen.menuIndex % 2 == 0 then U.tap(game, "left") U.wait(3) end
  if screen.menuIndex <= 2 then U.tap(game, "down") U.wait(3) end
  U.tap(game, "a")
  U.wait(6)
  local pack = game.stack:top()
  assert(pack and pack.rows, "the battle PACK did not open")
  -- The PACK restores its own cursor pocket; the BALL pocket is where a
  -- MASTER BALL lives (engine/items/pack.asm's ItemAttributes pocket byte).
  for _ = 1, #PackMenu.POCKETS do
    if pack:pocket().id == "BALL" then break end
    U.tap(game, "right")
    U.wait(3)
  end
  assert(pack:pocket().id == "BALL", "could not reach the BALL pocket")
  local ballRow
  for index, row in ipairs(pack.rows) do
    if row.id == "MASTER_BALL" then ballRow = index end
  end
  assert(ballRow, "the battle PACK does not show the MASTER BALL")
  for _ = 2, ballRow do U.tap(game, "down") U.wait(2) end
  reset()
  U.tap(game, "a")
  awaitSfx("Sfx_CaughtMon", 400)
  awaitSfx("Sfx_SlotMachineStart", 300)
  U.wait(30)
  report("01 catch:",
         "Sfx_CaughtMon, then Sfx_SlotMachineStart over the #DEX line")
  U.shot(game, out .. "/01-caught.png")
  for _ = 1, 6 do U.tap(game, "a") U.wait(20) end
  U.shot(game, out .. "/02-dex-line.png")
  for _ = 1, 30 do
    if not battleScreen() then break end
    U.tap(game, "a")
    U.wait(10)
  end

  -- ---- 2. a level-up that teaches a move ---------------------------------
  local SPECIES = "CYNDAQUIL"
  local def = data.pokemon and data.pokemon[SPECIES]
  local target
  for _, entry in ipairs((def and def.levelMoves) or {}) do
    if entry.level and entry.level > 6 and not target then target = entry.level end
  end
  if not target then
    U.log("SKIP 02 -- no level-up move row for " .. SPECIES)
  else
    local hero = Mon.new(data, SPECIES, target - 1)
    local growth = Mon.growthFor(data, def.growthRate)
    hero.experience = Mon.experienceForLevel(growth, target) - 1
    -- Only three moves, so LearnMove takes the free slot rather than ForgetMove
    -- (engine/pokemon/learn.asm:23-29).
    while hero.moves and #hero.moves > 3 do table.remove(hero.moves) end
    save.party = { hero }
    save.inventory = {}
    U.log(("levelling %s %d -> %d for its %s row")
      :format(SPECIES, hero.level, target, tostring(target)))

    local prey = Mon.new(data, "PIDGEY", 2)
    prey.hp = 1
    assert(world:startBattle({ wild = prey }), "the second battle refused")
    assert(tapUntil(function()
      local s = battleScreen()
      return s ~= nil and s.phase == "menu"
    end), "the second battle never reached BattleMenu")
    screen = battleScreen()
    if screen.menuIndex % 2 == 0 then U.tap(game, "left") U.wait(3) end
    if screen.menuIndex > 2 then U.tap(game, "up") U.wait(3) end
    reset()
    U.tap(game, "a")      -- FIGHT
    U.wait(6)
    U.tap(game, "a")      -- the first move
    awaitSfx("Sfx_DexFanfare5079", 400, 2)
    U.wait(60)
    report("02 level-up move:",
           "Sfx_DexFanfare5079 twice: \"grew to level\" and \"learned\"")
    U.shot(game, out .. "/03-level-up.png")
    for _ = 1, 8 do U.tap(game, "a") U.wait(30) end
    U.shot(game, out .. "/04-learned.png")
  end

  Sound.play = realPlay
  U.log("done -- the controls are yours")
end
