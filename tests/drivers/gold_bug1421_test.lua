-- #1421: the Gold battle HUD ran ahead of its own animations.
--
--   POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1421_test.lua love .
--   POKEPORT_SHOT_DIR=/tmp/gold-bug1421   (default)
--
-- Two symptoms, one seam, and neither can be asserted -- both are "what is on
-- screen while an animation runs":
--
--   caught  a wild mon that is NOT in the dex is caught with a MASTER BALL.
--           The caught mark ($5d at (1,1)) must be absent for every frame of
--           the throw and every line after it, because DrawEnemyHUDBorder --
--           the only thing that paints it -- is never called again during a
--           capture (engine/battle/trainer_huds.asm:134-151).  The control
--           run right after it re-enters a battle with the same species now
--           in the dex, where the mark IS there from the first frame.
--
--   status  THUNDER WAVE on the enemy.  PAR may not be on the HUD until the
--           animation and the "is paralyzed!" line are done with, which is
--           where UpdateBattleHuds runs (home/battle.asm:150).
--
-- Every frame of both animations is logged as `live` (the engine's byte, a
-- whole turn ahead) against `hud` (what the HUD is allowed to print), so the
-- lag is a column of text as well as a strip of pictures.  The run ends in a
-- third wild battle with THUNDER WAVE under the cursor: press A, A, A and
-- watch the tag land with its own line.
local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")

local OUT = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1421"
local WILD = "PIDGEY"

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

local function toMenu(game, screen)
  for _ = 1, 400 do
    if screen.phase == "menu" then return true end
    if screen.battle.over then return false end
    tap(game, "a", 2)
  end
  return screen.phase == "menu"
end

local function giveMoves(game, mon, moves)
  mon.moves = {}
  for i, id in ipairs(moves) do
    local def = assert(game.data.moves[id], id .. " is not in moves.lua")
    mon.moves[i] = { id = id, pp = def.pp, maxPp = def.pp }
  end
  return mon
end

-- Shoot and log while the screen is busy: `probe` returns the two values the
-- run is about, and the caller gets them for every frame.
local function watch(game, screen, prefix, label, probe, limit)
  local frames = 0
  while frames < (limit or 240) do
    if frames % 3 == 0 then
      U.shot(game, ("%s-%03d.png"):format(prefix, frames))
      local live, hud = probe()
      U.log(("[driver] %s f%03d live=%s hud=%s")
        :format(label, frames, tostring(live), tostring(hud)))
    end
    if not screen.anim and screen.phase ~= "resolving" then break end
    frames = frames + 1
    U.wait(1)
  end
  return frames
end

return function(game)
  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")

  local save = game.save
  save.pokedex = save.pokedex or { seen = {}, caught = {} }
  save.pokedex.caught[WILD] = nil
  save.inventory = { MASTER_BALL = 5, POKE_BALL = 10 }
  save.boxes = nil
  save.party = { giveMoves(game, Mon.new(game.data, "CYNDAQUIL", 30),
    { "THUNDER_WAVE", "TACKLE" }) }

  ------------------------------------------------------------------ caught
  local screen = openBattle(game, { wild = Mon.new(game.data, WILD, 5) })
  assert(toMenu(game, screen), "never reached the battle menu")
  U.shot(game, OUT .. "/caught-00-menu.png")
  U.log(("[driver] caught: dex before = %s, hud latch = %s")
    :format(tostring(save.pokedex.caught[WILD]), tostring(screen.caughtMark)))

  screen:useItem("MASTER_BALL")
  watch(game, screen, OUT .. "/caught-01-throw", "caught",
    function()
      return save.pokedex.caught[WILD] and true or false, screen.caughtMark
    end, 200)

  -- The lines that follow the throw: "Gotcha!", the dex entry, the nickname
  -- prompt.  The mark may not appear on any of them either.
  for i = 0, 7 do
    U.shot(game, ("%s/caught-02-after-%d.png"):format(OUT, i))
    if screen.phase == "ask-nickname" then tap(game, "b", 4)
    else tap(game, "a", 4) end
    if screen.phase == "done" or not game.stack:top() then break end
  end
  U.log(("[driver] caught: dex after = %s, hud latch = %s")
    :format(tostring(save.pokedex.caught[WILD]), tostring(screen.caughtMark)))

  for _ = 1, 300 do
    if game.world and not (game.stack:top() or {}).battle then break end
    tap(game, "a", 2)
  end

  ------------------------------------------------------------------ control
  -- Same species, now in the dex: the mark IS on the HUD from the first frame
  -- the enemy HUD is drawn, because DrawEnemyHUDBorder runs at battle start.
  save.party = { giveMoves(game, Mon.new(game.data, "CYNDAQUIL", 30),
    { "THUNDER_WAVE", "TACKLE" }) }
  screen = openBattle(game, { wild = Mon.new(game.data, WILD, 5) })
  assert(toMenu(game, screen), "never reached the battle menu")
  U.shot(game, OUT .. "/control-00-mark.png")
  U.log(("[driver] control: dex = %s, hud latch = %s")
    :format(tostring(save.pokedex.caught[WILD]), tostring(screen.caughtMark)))

  ------------------------------------------------------------------ status
  screen:submit({ kind = "move", move = "THUNDER_WAVE" })
  watch(game, screen, OUT .. "/status-01-anim", "status",
    function()
      local enemy = screen.battle.enemy
      return enemy and enemy.status, screen:hudStatus(enemy, "enemy")
    end, 240)
  U.shot(game, OUT .. "/status-02-line.png")
  for i = 0, 4 do
    tap(game, "a", 4)
    U.shot(game, ("%s/status-03-after-%d.png"):format(OUT, i))
  end
  U.log(("[driver] status: live=%s hud=%s"):format(
    tostring(screen.battle.enemy and screen.battle.enemy.status),
    tostring(screen:hudStatus(screen.battle.enemy, "enemy"))))

  U.log("[driver] shots in " .. OUT
    .. " -- the battle is yours: FIGHT, THUNDER WAVE, watch the tag land")
end
