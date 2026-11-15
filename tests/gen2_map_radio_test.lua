-- The wall radios: `special MapRadio` -> src/ui/gen2/MapRadio.lua, a port of
-- engine/pokegear/pokegear.asm PlayRadio.
--
--   luajit tests/gen2_map_radio_test.lua
--
-- PlayRadio's contract, row by row: resolve the MAPRADIO_* index through
-- PlayRadioStationPointers (index 0, the Pokemon Channel, resolves by region
-- and time of day), wait 100 frames with only the station name up, then run
-- one show frame per loop until A or B, and leave the channel song playing as
-- the map music on the way out (ExitPokegearRadio_HandleMusic /
-- RadioMusicRestartDE).  Every interaction builds a fresh machine, which is
-- what makes the radio replayable: back out, talk again, it plays again.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 map radio")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

local MapRadio = require("src.ui.gen2.MapRadio")
local Music = require("src.core.Music")
local Save = require("src.core.gen2.Save")

-- `call Random`, scripted: hand back the listed bytes in order, cycling.
local function rolls(...)
  local list = { ... }
  local index = 0
  return function()
    index = index % #list + 1
    return list[index]
  end
end

local function newInput()
  local input = { pressed = {} }
  function input:press(...)
    for _, b in ipairs({ ... }) do self.pressed[b] = true end
  end
  function input:wasPressed(b)
    if self.pressed[b] then self.pressed[b] = nil return true end
    return false
  end
  function input:isDown() return false end
  return input
end

local LANDMARKS = require("tests.fixture_data.gen2_landmarks_s7_d").anchored({ landmarks = {
  LANDMARK_NEW_BARK_TOWN = { index = 2 },
  LANDMARK_VERMILION_CITY = { index = 50 },
} })

local function newGame(save)
  return {
    input = newInput(),
    save = save,
    options = Save.defaultOptions(),
    data = { audio = {}, pokemon = {}, items = {},
      gen2Landmarks = LANDMARKS,
      text = require("tests.fixture_data.gen2_rom_text_s7_d").text() },
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end,
    },
  }
end

-- Enough of the show tables for LETS_ALL_SING (the Ben/Fern chatter needs
-- only a weekday) -- the full fixtures live in gen2_menus_test.lua, which
-- owns the line-by-line show assertions.
local RADIO_DATA = {
  landmarks = {}, mapLandmark = {}, grass = {}, species = {},
  caught = function() return false end,
  dex = {}, classes = {}, hidden = {},
  weekday = 2, luckyNumber = 42, inJohto = true,
  text = require("tests.fixture_data.gen2_rom_text_s7_d").text(),
}

-- ---- the blocking loop -----------------------------------------------------

do
  local save = Save.newGame()
  local game = newGame(save)
  game.world = { map = { def = { music = "Music_NewBarkTown" } } }
  local done = false
  local mr = MapRadio.new(game, {
    channel = 7, radioData = RADIO_DATA, radioRng = rolls(0),
    save = save, onDone = function() done = true end,
  })
  game.stack:push(mr)
  eq(mr.station, "LETS_ALL_SING", "MAPRADIO index 7 is Let's All Sing")
  eq(mr:name(), game.data.text.LetsAllSingName,
    "the quoted name is the cache's LetsAllSingName")
  eq(mr.radioMusicPlaying, "enterMap",
    ".PlayStation parks ENTER_MAP_MUSIC before the show starts")

  -- `ld c, 100 / call DelayFrames`: no lines and no buttons for 100 frames.
  game.input:press("a")
  for _ = 1, 100 do mr:update(0) end
  eq(#mr.radio.log, 0, "nothing prints during the delay")
  eq(game.stack:top(), mr, "and A during the delay does not close it")
  game.input.pressed = {}

  -- The loop's first frame: StartPokemonMusicChannel reads the weekday's low
  -- bit and RadioMusicRestartDE lands the song (an even weekday marches).
  mr:update(0)
  eq(mr.radio.music, "Music_PokemonMarch",
    "the sing show starts the weekday's song")
  eq(mr.radioMusicPlaying, "Music_PokemonMarch",
    "and RadioMusicRestartDE parks it for the exit handler")

  -- Left running, the DJ chatter scrolls through the box.
  for _ = 1, 700 do mr:update(0) end
  check(#mr.radio.log >= 1, "the show prints once the delay is spent")

  -- A stops the loop: pop, resume, and the song stays as the map music.
  Music.setMapSong("Music_NewBarkTown")
  game.input:press("a")
  mr:update(0)
  eq(game.stack:top(), nil, "A closes the radio")
  eq(done, true, "and resumes the parked script")
  eq(Music.mapSong(), "Music_PokemonMarch",
    "with the playing song left as the map music (wMapMusic)")

  -- Replay: the next interaction builds a fresh machine and plays again.
  local again = MapRadio.new(game, {
    channel = 7, radioData = RADIO_DATA, radioRng = rolls(0), save = save,
  })
  game.stack:push(again)
  for _ = 1, 101 do again:update(0) end
  eq(again.radio.music, "Music_PokemonMarch", "a second listen plays again")
  for _ = 1, 400 do again:update(0) end
  check(#again.radio.log >= 1, "and prints again")
  game.input:press("b")
  again:update(0)
  eq(game.stack:top(), nil, "B closes it too")
end

-- ---- LoadStation_PokemonChannel --------------------------------------------

-- Index 0 is not a station: it resolves by region, and in Johto by time of
-- day -- the morning airs the Pokedex Show, the rest of the day Oak.
do
  local save = Save.newGame()
  local function stationFor(landmark, daytime)
    local game = newGame(save)
    game.world = { daytime = daytime,
      map = { def = { music = "Music_NewBarkTown" } } }
    local mr = MapRadio.new(game, {
      channel = 0, radioData = RADIO_DATA, radioRng = rolls(0),
      save = save, currentLandmark = landmark,
    })
    return mr.station
  end
  eq(stationFor("LANDMARK_NEW_BARK_TOWN", "MORN"), "POKEDEX_SHOW",
    "Johto mornings air the Pokedex Show")
  eq(stationFor("LANDMARK_NEW_BARK_TOWN", "DAY"), "OAKS_POKEMON_TALK",
    "and the day belongs to Oak")
  eq(stationFor("LANDMARK_VERMILION_CITY", "DAY"), "PLACES_AND_PEOPLE",
    "from Kanto the same dial carries Places & People")
end

-- ---- the fixed stations ----------------------------------------------------

do
  local save = Save.newGame()
  local game = newGame(save)
  game.data.gen2RadioChannels = {
    LUCKY_CHANNEL = { channel = 4, name = "CANAL CHANCE" },
  }
  local mr = MapRadio.new(game, {
    channel = 4, radioData = RADIO_DATA, radioRng = rolls(0), save = save,
  })
  eq(mr.station, "LUCKY_CHANNEL",
    "Radio2Script's MAPRADIO_LUCKY_CHANNEL is index 4")
  eq(mr:name(), "CANAL CHANCE",
    "the wall radio consumes the registry-patched station name")
end

S.finish()
