-- #1428: the Gold battle HUD never drew the party ball rows.
--
--   POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1428_test.lua love .
--   POKEPORT_SHOT_DIR=/tmp/gold-bug1428   (default)
--
-- BattleStart_TrainerHuds (engine/battle/trainer_huds.asm:1-9) runs from
-- inside BattleStartMessage, so the rows are on screen UNDER the opening line
-- and nowhere else: the player's six always, the opponent's only outside a
-- wild battle.  EnemySwitch_TrainerHud (:11-15) brings the opponent's row
-- back for the "will you switch?" prompt after one of its mons drops.
--
-- The party is seeded so all four staged tiles are on screen at once
-- (StageBallTilesData, :47-99): healthy, statused, fainted, and the empty
-- slots past the party count.
--
--   trainer  the intro line, both rows, then the shift prompt after the first
--            enemy mon faints -- the opponent's row again, one ball darkened
--   wild     the same intro with only the player's row, per the `dec a / ret z`
--
-- Nothing here is assertable: the fix IS twelve sprites.  The run ends on the
-- trainer battle's own menu with a human holding the controls.
local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")
local Trainers = require("src.world.gen2.Trainers")

local OUT = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1428"

local hostVisible = love.visible
love.visible = function(v) if hostVisible then pcall(hostVisible, v) end end

local function tap(game, button, frames)
  game.input.pressQueue[#game.input.pressQueue + 1] = button
  game.input.state[button] = true
  U.wait(2)
  game.input.state[button] = false
  U.wait(frames or 6)
end

local function openBattle(game, opts)
  assert(game.world:startBattle(opts), "startBattle failed")
  for _ = 1, 900 do
    local top = game.stack:top()
    if top and top.battle then return top end
    U.wait(1)
  end
  error("battle screen never came up")
end

-- Four healthy, one poisoned, one fainted, and one slot left empty: every
-- tile StageBallTilesData can stage, in one row.  The lead is handed a
-- damaging move outright, because slot 1 of its level-up set is LEER.
local function seedParty(game)
  local party = {}
  for i = 1, 5 do
    party[i] = Mon.new(game.data, "CYNDAQUIL", 20 + i)
  end
  party[1].moves = {}
  for i, id in ipairs({ "EMBER", "TACKLE" }) do
    local def = assert(game.data.moves[id], id .. " is not in moves.lua")
    party[1].moves[i] = { id = id, pp = def.pp, maxPp = def.pp }
  end
  party[4].status = "poison"
  party[5].hp = 0
  return party
end

local function rowState(screen)
  local rows = screen.ballRows or {}
  return ("player=%s enemy=%s balls=%s"):format(
    tostring(rows.player), tostring(rows.enemy),
    tostring(screen.hud and screen.hud:image("balls") ~= nil))
end

return function(game)
  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")

  local save = game.save
  save.inventory = {}
  save.party = seedParty(game)

  --------------------------------------------------------------- trainer
  local entry = game.world:trainerParty(36, 1) -- BUG_CATCHER member 1
  assert(entry, "no BUG_CATCHER member 1 in trainers.lua")
  entry.party = Trainers.party(game.data, entry)
  local screen = openBattle(game, { trainer = entry })

  -- The opening line: both rows, both borders, and no names or bars yet.
  -- Not before the intro slide has settled, or the shots catch the pics
  -- mid-transform instead of the HUD.
  U.wait(150)
  for i = 0, 6 do
    U.shot(game, ("%s/trainer-00-intro-%d.png"):format(OUT, i))
    U.log("[driver] intro " .. i .. ": " .. rowState(screen))
    U.wait(6)
  end
  U.log(("[driver] OT party = %d"):format(#(screen.battle.enemyParty or {})))

  -- Page through the pic slide and the send-out: the rows go with the OAM the
  -- send-out animation takes over.
  for i = 0, 7 do
    tap(game, "a", 5)
    U.shot(game, ("%s/trainer-01-sendout-%d.png"):format(OUT, i))
  end
  for _ = 1, 400 do
    if screen.phase == "menu" then break end
    tap(game, "a", 2)
  end
  U.shot(game, OUT .. "/trainer-02-menu.png")
  U.log("[driver] menu: " .. rowState(screen))

  --------------------------------------------------------------- shift prompt
  -- Drop the enemy's lead so HandleEnemySwitch offers the switch: its row is
  -- redrawn for the prompt, with the fainted ball darkened.
  if #(screen.battle.enemyParty or {}) > 1 then
    for _ = 1, 400 do
      if screen.phase == "ask-shift" or screen.phase == "shift-intro" then
        break
      end
      if screen.battle.over then break end
      if screen.phase == "menu" then
        local enemy = screen.battle.enemy
        if enemy then enemy.hp = 1 end
        screen:chooseMenu("fight")
        U.wait(2)
        screen:chooseMove(1)
        U.wait(4)
      else
        tap(game, "a", 6)
      end
    end
    U.log("[driver] shift prompt: phase=" .. tostring(screen.phase))
    for i = 0, 5 do
      U.shot(game, ("%s/trainer-03-shift-%d.png"):format(OUT, i))
      U.log("[driver] shift " .. i .. ": phase=" .. tostring(screen.phase)
        .. " " .. rowState(screen))
      U.wait(6)
    end
    -- NO: the enemy sends its next mon and the row goes with the animation.
    tap(game, "down", 4)
    tap(game, "a", 4)
    for i = 0, 5 do
      U.shot(game, ("%s/trainer-04-after-shift-%d.png"):format(OUT, i))
      tap(game, "a", 5)
    end
  else
    U.log("[driver] this trainer has one mon; no shift prompt to show")
  end

  --------------------------------------------------------------- wild
  -- ShowPlayerMonsRemaining runs for a wild battle too; the `dec a / ret z`
  -- right after it is what keeps the OT row off.
  for _ = 1, 600 do
    if not (game.stack:top() or {}).battle then break end
    tap(game, "a", 2)
  end
  save.party = seedParty(game)
  screen = openBattle(game, { wild = Mon.new(game.data, "PIDGEY", 5) })
  U.wait(150)
  for i = 0, 6 do
    U.shot(game, ("%s/wild-00-intro-%d.png"):format(OUT, i))
    U.log("[driver] wild " .. i .. ": " .. rowState(screen))
    U.wait(6)
  end
  for _ = 1, 400 do
    if screen.phase == "menu" then break end
    tap(game, "a", 2)
  end
  U.shot(game, OUT .. "/wild-01-menu.png")

  U.log("[driver] shots in " .. OUT .. " -- the battle is yours")
end
