-- pokecrystal engine/battle/core.asm:6983
-- pokecrystal engine/battle/core.asm:8294
local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-ditto-exp-2192"
  os.execute('mkdir -p "' .. out .. '" 2>/dev/null')
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[ditto-exp] " .. (cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "the crystal world did not boot")

  local ditto = Mon.new(game.data, "DITTO", 9)
  assert(ditto, "could not build a DITTO")
  ditto.experience = 729
  ditto.moves = { { id = "TRANSFORM", pp = 10, maxPp = 10 } }
  game.save.party = { ditto }
  game.save.inventory = { POKE_BALL = 5 }

  local wild = Mon.new(game.data, "PIDGEY", 3)
  assert(wild, "could not build a wild PIDGEY")
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  assert(world:startBattle({ wild = wild }), "startBattle failed")

  local screen
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  assert(screen and screen.battle, "battle screen never came up")

  local function toMenu()
    for _ = 1, 900 do
      if screen.phase == "menu" then return true end
      U.tap(game, "a")
      U.wait(2)
    end
    return false
  end

  local function attack()
    U.tap(game, "a")
    U.wait(4)
    U.tap(game, "a")
    U.wait(4)
  end

  ok(toMenu(), "reached the battle menu")
  attack()
  for _ = 1, 200 do
    if screen.battle.player.species == "PIDGEY" then break end
    U.wait(1)
  end
  ok(screen.battle.player.species == "PIDGEY", "the DITTO transformed")

  ok(toMenu(), "reached the menu for the KO turn")
  screen.battle.enemy.hp = 1
  attack()

  local shots = {
    { "2192_01_faint_text_pic_stays_pidgey.png", "fainted" },
    { "2192_02_exp_message.png", "EXP" },
  }
  local at = 1
  for _ = 1, 900 do
    local want = shots[at]
    local message = screen.message or ""
    if want and message:find(want[2], 1, true) then
      U.wait(90)
      if want[2] == "fainted" then
        ok(screen:activeMon("player").species == "PIDGEY",
          "the pic is still the copy while the faint line is up")
      end
      U.shot(game, out .. "/" .. want[1])
      at = at + 1
    end
    if game.stack:top() ~= screen then break end
    U.tap(game, "a")
    U.wait(2)
  end

  local mon = game.save.party[1]
  local summary = SummaryMenu.new(game, {
    party = game.save.party, index = 1, save = game.save,
    page = SummaryMenu.BLUE_PAGE,
  })
  game.stack:push(summary)
  U.wait(6)
  U.shot(game, out .. "/2192_03_summary_stats_ditto_l9.png")
  game.stack:pop()

  ok(mon.species == "DITTO", "the party slot is a DITTO again")
  ok(mon.experience == 752, "729 + 23 EXP banked (got "
    .. tostring(mon.experience) .. ")")
  ok(mon.level == 9, "still level 9 on MEDIUM_FAST (got "
    .. tostring(mon.level) .. ")")
  ok(mon.maxHp == Mon.stats(game.data.pokemon.DITTO.baseStats, mon.dvs, 9,
    mon.statExp).hp, "maxHP off DITTO's base stats (got "
    .. tostring(mon.maxHp) .. ")")

  print("[ditto-exp] " .. (fails == 0 and "PASS all claims" or
    (fails .. " claims failed")) .. " -- shots in " .. out)
  love.event.quit(fails == 0 and 0 or 1)
end
