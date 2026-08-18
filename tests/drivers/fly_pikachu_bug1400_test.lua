-- Driver: Fly / Teleport must take Pikachu with it (#1400).  _LeaveMapAnim
-- drops the companion sprite before the bird flaps (home/pikachu.asm:1) and
-- EnterMapAnim only puts it back once the swoop or the spin has landed, so
-- Pikachu is invisible for the whole sequence and never stands on the landing
-- cell ahead of the player.
--
--   POKEPORT_DRIVER=tests/drivers/fly_pikachu_bug1400_test.lua \
--     POKEPORT_VERSION=yellow POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
--
-- Never add POKEPORT_SPEED; the run needs an imported Yellow cache.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local GameVersion = require("src.core.GameVersion")
  local PF = require("src.world.PikachuFollower")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  check("running as Yellow (needs POKEPORT_VERSION=yellow)",
        GameVersion.isYellow())

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  -- DisablePikachuOverworldSpriteDrawing is what keeps it in the ball
  -- (pokeyellow scripts/OaksLab.asm); out of the ball is what follows (#1009)
  game.save.pikachuInBall = false
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 20) }
  game.save.onBike = false

  local function drawn()
    local ow = game.overworld
    local npc = ow and PF.current(ow)
    if not npc then return false end
    for _, e in ipairs(ow.entities or {}) do
      if e == npc then return true end
    end
    return false
  end

  U.teleport(game, "ROUTE_17", 4, 10, "down")
  U.wait(30)
  local ow = game.stack:top()
  check("Pikachu is out and drawn before the flight", drawn())
  U.shot(game, DIR .. "/bug1400_0_before.png")

  ow:flyTo("PALLET_TOWN")
  U.wait(12) -- mid in-place flap
  check("hidden during the departure flap", not drawn())
  U.shot(game, DIR .. "/bug1400_1_flap.png")

  U.wait(60) -- the bird's path out
  check("still hidden while the bird flies off", not drawn())

  local guard = 0
  while ow.map.id == "ROUTE_17" and guard < 900 do
    guard = guard + 1
    coroutine.yield()
  end
  guard = 0
  while not ow.flyArrive and guard < 900 do
    guard = guard + 1
    coroutine.yield()
  end
  U.wait(12) -- mid swoop, the frame the old bug showed Pikachu already landed
  check("hidden through the arrival swoop", not drawn())
  U.shot(game, DIR .. "/bug1400_2_arrive.png")

  guard = 0
  while ow.flyArrive and guard < 900 do
    guard = guard + 1
    coroutine.yield()
  end
  U.wait(10)
  check("back out once the bird has landed", drawn())
  do
    local npc = PF.current(ow)
    local p = ow.player
    check("and it comes back on the player's own cell",
          npc and p and npc.cellX == p.cellX and npc.cellY == p.cellY)
  end
  U.shot(game, DIR .. "/bug1400_3_landed.png")

  -- Dig / Teleport / Escape Rope take the same _LeaveMapAnim path
  game.save.lastHeal = { map = "VIRIDIAN_CITY", x = 23, y = 26 }
  ow:beginTeleportOut()
  U.wait(20)
  check("hidden during the teleport-out spin", not drawn())
  U.shot(game, DIR .. "/bug1400_4_spin_out.png")

  guard = 0
  while (ow.teleportOut or ow.player.spinning or ow.transitioning)
        and guard < 900 do
    guard = guard + 1
    coroutine.yield()
  end
  U.wait(10)
  check("back out once the arrival spin has landed", drawn())
  U.shot(game, DIR .. "/bug1400_5_spin_in.png")

  U.log("Watch the shots in order: Pikachu stands beside the player before")
  U.log("the flight, is nowhere on screen for the flap, the fade and the")
  U.log("swoop, and only reappears under him once the bird sets him down.")
  U.log("A Pikachu standing on the landing cell during the swoop is the bug.")
  U.log("The pad is yours -- fly around and watch the departures.")

  while true do coroutine.yield() end
end
