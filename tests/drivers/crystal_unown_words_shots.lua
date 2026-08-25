-- The Ruins of Alph wall words and word rooms, driven in a real game.
--
--   POKEPORT_IDENTITY=unit-e-unown POKEPORT_GAME=crystal \
--     POKEPORT_VERSION=crystal POKEPORT_SHOT_DIR=/tmp/unit-e \
--     POKEPORT_DRIVER=tests/drivers/crystal_unown_words_shots.lua love .


local U = require("tests.drivers.util")

local GameVersion = require("src.core.GameVersion")
local Mon = require("src.battle.gen2.Mon")
local UnownWords = require("src.world.gen2.UnownWords")

-- maps/RuinsOfAlphKabutoChamber.asm:272 `bg_event 4, 0, BGEVENT_UP`
local CHAMBERS = {
  { map = "RUINS_OF_ALPH_KABUTO_CHAMBER", word = "ESCAPE" },
  { map = "RUINS_OF_ALPH_AERODACTYL_CHAMBER", word = "LIGHT" },
  { map = "RUINS_OF_ALPH_OMANYTE_CHAMBER", word = "WATER" },
  { map = "RUINS_OF_ALPH_HO_OH_CHAMBER", word = "HO-OH" },
}

local WORD_ROOMS = {
  { map = "RUINS_OF_ALPH_KABUTO_WORD_ROOM", x = 9, y = 6 },
  { map = "RUINS_OF_ALPH_AERODACTYL_WORD_ROOM", x = 9, y = 6 },
  { map = "RUINS_OF_ALPH_OMANYTE_WORD_ROOM", x = 9, y = 6 },
  { map = "RUINS_OF_ALPH_HO_OH_WORD_ROOM", x = 9, y = 6 },
}

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-unown-words"
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

  local function top() return game.stack:top() end
  local function wordScreen()
    local state = top()
    return (state and getmetatable(state) == UnownWords) and state or nil
  end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "crystal world did not boot")
  say("version=" .. GameVersion.get() .. " engine=" .. GameVersion.engine())

  local save = game.save
  save.player = save.player or {}
  save.player.name = save.player.name or "CHRIS"
  save.player.id = save.player.id or 30000
  save.party = { Mon.new(game.data, "TYPHLOSION", 40) }

  for index, chamber in ipairs(CHAMBERS) do
    say("A" .. index .. " " .. chamber.map)
    world:setMap(chamber.map, 4, 1, "up")
    U.wait(30)
    U.shot(game, ("%s/a%d-%s-chamber.png"):format(
      out, index, chamber.word:lower()))
    local screen
    for _ = 1, 300 do
      screen = wordScreen()
      if screen then break end
      if not world:busy() then tap("a", 2) else tap("a", 2) end
    end
    ok(screen ~= nil, chamber.map .. " reached DisplayUnownWords")
    if screen then
      U.wait(20)
      ok(screen.wall and screen.wall.word == chamber.word,
        ("   showing %s (got %s)"):format(chamber.word,
          tostring(screen.wall and screen.wall.word)))
      ok(#screen.squares == #chamber.word,
        ("   %d letter squares"):format(#screen.squares))
      U.shot(game, ("%s/a%d-%s-word.png"):format(
        out, index, chamber.word:lower()))
      tap("a", 10)
      ok(wordScreen() == nil, "   A closes the box")
      U.wait(20)
    end
  end

  for index, room in ipairs(WORD_ROOMS) do
    say("B" .. index .. " " .. room.map)
    world:setMap(room.map, room.x, room.y, "up")
    U.wait(40)
    ok(world.map and world.map.id == room.map, "   stood in " .. room.map)
    U.shot(game, ("%s/b%d-%s.png"):format(out, index,
      room.map:lower():gsub("ruins_of_alph_", "")))
  end

  say(fails == 0 and "ALL OK" or (fails .. " FAILURES"))
  U.wait(10)
  love.event.quit(fails == 0 and 0 or 1)
end
