-- The two chamber walls the FIELD MOVES open, driven through the production
-- call sites rather than by calling the routines directly.
--
-- ../pokecrystal/engine/events/overworld.asm:280-291 FlashFunction.CheckUseFlash
-- (badge FIRST, then SpecialAerodactylChamber) and :808-813 EscapeRopeOrDig's
-- `.escaperope` arm.
--
--   POKEPORT_GAME=crystal POKEPORT_VERSION=crystal \
--     POKEPORT_DRIVER=tests/drivers/gate_chamber_fieldmoves.lua love .
local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")
local UnownWords = require("src.world.gen2.UnownWords")

return function(game)
  local fails = 0
  local function say(line) print("[driver] " .. line); io.stdout:flush() end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "OK   " or "FAIL ") .. line)
  end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "crystal world did not boot")

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  local function clearText()
    for _ = 1, 200 do
      if not world:busy() then return true end
      tap("a", 3)
    end
    return false
  end

  local function enter(mapId)
    while game.stack:top() do game.stack:pop() end
    assert(world:setMap(mapId, 3, 7, "up"), "no " .. mapId .. " in this cache")
    for _ = 1, 240 do
      if not world:busy() then break end
      U.wait(2)
    end
    U.wait(10)
  end

  -- ---- the escape rope, in the Kabuto chamber ------------------------------
  say("--- KABUTO, through World:useEscapeRope()")
  enter(UnownWords.CHAMBER_MAPS.KABUTO)
  ok(not UnownWords.wallOpened(world.events, "KABUTO"),
    "the Kabuto wall flag starts clear")
  game.save.inventory = { ESCAPE_ROPE = 1 }
  -- wDigWarpNumber / wBackupMapGroup: the cave's own entrance, which
  -- ../pokecrystal/engine/events/overworld.asm:795-798 copies into wNextWarp.
  world.backupWarp = { map = "RUINS_OF_ALPH_OUTSIDE", warp = 1 }
  clearText()
  local rope = world:useEscapeRope("ESCAPE_ROPE")
  say("escape rope result: " .. tostring(rope))
  ok(rope == "escape_rope", "the rope was used")
  ok(UnownWords.wallOpened(world.events, "KABUTO"),
    "and SpecialKabutoChamber set the wall flag")

  -- The rope must not open a wall anywhere else.
  world.queuedFieldMove = nil
  enter("RUINS_OF_ALPH_OUTSIDE")
  clearText()
  local before = UnownWords.wallOpened(world.events, "OMANYTE")
  game.save.inventory = { ESCAPE_ROPE = 1 }
  world:useEscapeRope("ESCAPE_ROPE")
  ok(UnownWords.wallOpened(world.events, "OMANYTE") == before,
    "a rope used outside a chamber opens nothing")

  -- ---- FLASH, in the Aerodactyl chamber ------------------------------------
  say("--- AERODACTYL, through World:useFieldMove(\"FLASH\")")
  enter(UnownWords.CHAMBER_MAPS.AERODACTYL)
  ok(world.map.id == UnownWords.CHAMBER_MAPS.AERODACTYL, "in the chamber")
  ok(not UnownWords.wallOpened(world.events, "AERODACTYL"),
    "the wall flag starts clear")

  local flash = game.data.moves.FLASH
  game.save.party = { Mon.new(game.data, "TYPHLOSION", 40,
    { moves = { { id = "FLASH", pp = flash.pp, maxPp = flash.pp } } }) }

  -- :281-283, the ZEPHYRBADGE gate that runs BEFORE the special.
  game.save.player = game.save.player or {}
  game.save.player.badges = {}
  local refused = world:useFieldMove("FLASH", game.save.party[1])
  ok(refused and refused.ok ~= true, "no ZEPHYRBADGE: FLASH is refused")
  ok(refused and refused.badge == "ZEPHYR", "on the badge, not on the map")
  ok(not UnownWords.wallOpened(world.events, "AERODACTYL"),
    "and the badgeless press did NOT open the wall")

  -- The refusal opened a text box; the world is busy until it is dismissed.
  clearText()
  game.save.player.badges = { ZEPHYR = true }
  local used = world:useFieldMove("FLASH", game.save.party[1])
  say("flash result: ok=" .. tostring(used and used.ok)
    .. " action=" .. tostring(used and used.action))
  ok(used and used.ok == true,
    "with the badge FLASH is allowed in a chamber that is not a dark cave")
  ok(UnownWords.wallOpened(world.events, "AERODACTYL"),
    "and SpecialAerodactylChamber set the wall flag")

  enter(UnownWords.CHAMBER_MAPS.AERODACTYL)
  U.wait(40)
  local _, block = world:blockIndexAt(3, 5)
  say("aerodactyl block under the wall: " .. tostring(block))
  U.shot(game, (os.getenv("POKEPORT_SHOT_DIR") or "/tmp")
    .. "/01-aerodactyl-flash-open.png")

  say(fails == 0 and "PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
