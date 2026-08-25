-- The four Ruins of Alph secret chambers, opened in a real game.
--
--   POKEPORT_IDENTITY=f3-crystal POKEPORT_GAME=crystal \
--     POKEPORT_VERSION=crystal POKEPORT_SHOT_DIR=/tmp/f3 \
--     POKEPORT_DRIVER=tests/drivers/crystal_unown_chambers.lua love .

local U = require("tests.drivers.util")

local GameVersion = require("src.core.GameVersion")
local Mon = require("src.battle.gen2.Mon")
local UnownWords = require("src.world.gen2.UnownWords")

-- ../pokecrystal/maps/RuinsOfAlphOmanyteChamber.asm:25 closed, :42 open;
-- ../pokecrystal/engine/overworld/scripting.asm:2147 halves them to block 2,0.
local WALL_BLOCK = 3
local WALL_SHUT, WALL_OPEN = 0x2e, 0x30

local CHAMBERS = {
  {
    key = "OMANYTE", word = "WATER",
    -- ../pokecrystal/engine/events/unown_walls.asm:25 CheckItem, :38 MON_ITEM
    shut = function(game)
      game.save.inventory = { FIRE_STONE = 1 }
      game.save.party = { Mon.new(game.data, "TYPHLOSION", 40,
        { item = "FIRE_STONE" }) }
    end,
    arm = function(game)
      game.save.inventory = {}
      game.save.party = {
        Mon.new(game.data, "TYPHLOSION", 40),
        Mon.new(game.data, "LANTURN", 30, { item = "WATER_STONE" }),
      }
    end,
    armed = "a WATER STONE held by the last party mon",
  },
  {
    key = "HO_OH", word = "HO-OH",
    -- ../pokecrystal/engine/events/unown_walls.asm:2 wPartySpecies[0].
    shut = function(game)
      game.save.inventory = {}
      game.save.party = {
        Mon.new(game.data, "TYPHLOSION", 40),
        Mon.new(game.data, "HO_OH", 70),
      }
    end,
    arm = function(game)
      game.save.party = {
        Mon.new(game.data, "HO_OH", 70),
        Mon.new(game.data, "TYPHLOSION", 40),
      }
    end,
    armed = "HO-OH moved into the FIRST party slot",
  },
  {
    key = "KABUTO", word = "ESCAPE",
    shut = function(game)
      game.save.inventory = { ESCAPE_ROPE = 1 }
      game.save.party = { Mon.new(game.data, "TYPHLOSION", 40) }
    end,
    -- ../pokecrystal/engine/events/overworld.asm:809 farcall
    -- SpecialKabutoChamber, off EscapeRopeOrDig's rope arm.
    arm = function(_, world)
      UnownWords.kabutoChamber(world.events, world.map and world.map.id)
    end,
    armed = "SpecialKabutoChamber, as the escape rope calls it",
  },
  {
    key = "AERODACTYL", word = "LIGHT",
    shut = function(game)
      game.save.inventory = {}
      game.save.party = { Mon.new(game.data, "TYPHLOSION", 40) }
    end,
    -- ../pokecrystal/engine/events/overworld.asm:285 farcall
    -- SpecialAerodactylChamber, inside FlashFunction.CheckUseFlash.
    arm = function(_, world)
      UnownWords.aerodactylChamber(world.events, world.map and world.map.id)
    end,
    armed = "SpecialAerodactylChamber, as FLASH calls it",
  },
}

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-unown-chambers"
  local fails = 0

  local function say(line) print("[driver] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "OK   " or "FAIL ") .. line)
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  local function wordScreen()
    local state = game.stack:top()
    return (state and getmetatable(state) == UnownWords) and state or nil
  end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "crystal world did not boot")
  say("version=" .. GameVersion.get() .. " engine=" .. GameVersion.engine())

  game.save.player = game.save.player or {}
  game.save.player.name = game.save.player.name or "CHRIS"
  game.save.player.id = game.save.player.id or 30000

  local function enter(mapId)
    world:setMap("RUINS_OF_ALPH_OUTSIDE", 8, 15, "down")
    U.wait(20)
    world.mapScenes[mapId] = 0
    world:setMap(mapId, 3, 1, "up")
    for _ = 1, 400 do
      U.wait(2)
      if not world:busy() and not world.pendingSceneScript then break end
    end
    U.wait(30)
  end

  local function blockNow()
    local blocks = world.map and world.map.def and world.map.def.blocks
    return blocks and blocks[WALL_BLOCK]
  end

  for index, chamber in ipairs(CHAMBERS) do
    local mapId = UnownWords.CHAMBER_MAPS[chamber.key]
    local flag = UnownWords.WALL_OPENED[chamber.key]
    say(("%d %s (flag %d)"):format(index, mapId, flag))
    world.events:set(flag, false)

    chamber.shut(game, world)
    enter(mapId)
    ok(world.map and world.map.id == mapId, "   stood in the chamber")
    ok(not world.events:get(flag), "   the wall flag is still clear")
    ok(blockNow() == WALL_SHUT,
      ("   and the hidden-doors callback drew the closed wall (%s)")
        :format(tostring(blockNow())))
    U.shot(game, ("%s/%d-%s-shut.png"):format(out, index,
      chamber.key:lower()))

    chamber.arm(game, world)
    say("   armed: " .. chamber.armed)
    world.mapScenes[mapId] = 0
    enter(mapId)
    ok(world.events:get(flag), "   the wall flag is set now")
    ok(blockNow() == WALL_OPEN,
      ("   and the wall-open script rewrote the block (%s)")
        :format(tostring(blockNow())))
    U.shot(game, ("%s/%d-%s-open.png"):format(out, index,
      chamber.key:lower()))

    -- ../pokecrystal/maps/RuinsOfAlphOmanyteChamber.asm:82
    -- RuinsOfAlphOmanyteChamberWallPatternLeft
    local screen
    for _ = 1, 200 do
      screen = wordScreen()
      if screen then break end
      tap("a", 2)
    end
    ok(screen ~= nil, "   the wall pattern reached DisplayUnownWords")
    if screen then
      U.wait(20)
      ok(screen.wall and screen.wall.word == chamber.word,
        ("   showing %s (got %s)"):format(chamber.word,
          tostring(screen.wall and screen.wall.word)))
      U.shot(game, ("%s/%d-%s-word.png"):format(out, index,
        chamber.key:lower()))
      tap("a", 10)
      U.wait(20)
    end
  end

  say(fails == 0 and "ALL OK" or (fails .. " FAILURES"))
  U.wait(10)
  love.event.quit(fails == 0 and 0 or 1)
end
