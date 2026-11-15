-- The wall radios (engine/pokegear/pokegear.asm PlayRadio).  A house radio's
-- bg event runs `jumpstd Radio1Script` -- `setval MAPRADIO_*` then `special
-- MapRadio` (engine/events/std_scripts.asm, engine/events/specials.asm) --
-- and PlayRadio owns the joypad from there: it resolves the MAPRADIO_* index
-- through PlayRadioStationPointers, prints the station's name in quotes in
-- the caller's text box, waits 100 frames, then runs one PlayRadioShow frame
-- per loop until A or B.  The show is the SAME state machine the Pokegear's
-- radio card runs (src/ui/gen2/Pokegear.lua's Radio), and the exit music is
-- the same ExitPokegearRadio_HandleMusic: the channel song the show started
-- stays playing as the map music.
--
-- Pushed by src/script/gen2/Specials.lua H.MapRadio while the script VM is
-- parked on the special; `onDone` resumes it, and `closetext` follows.

local Chrome = require("src.ui.gen2.Chrome")
local Buena = require("src.core.gen2.Buena")
local Nests = require("src.core.gen2.Nests")
local Pokegear = require("src.ui.gen2.Pokegear")
local Runtime = require("src.mods.Runtime")

local MapRadio = {}
MapRadio.__index = MapRadio
-- The map stays on screen under the text box, exactly as the cart leaves it.
MapRadio.isOpaque = false

-- PlayRadioStationPointers, in MAPRADIO_* order (constants/
-- radio_constants.asm).  Index 0, LoadStation_PokemonChannel, resolves by
-- region and time of day below rather than to a fixed station.
local STATIONS = {
  [1] = "OAKS_POKEMON_TALK",
  [2] = "POKEDEX_SHOW",
  [3] = "POKEMON_MUSIC",
  [4] = "LUCKY_CHANNEL",
  [5] = "UNOWN_RADIO",
  [6] = "PLACES_AND_PEOPLE",
  [7] = "LETS_ALL_SING",
  [8] = "ROCKET_RADIO",
}

local POKEGEAR_ONLY_STATIONS = { "POKE_FLUTE_RADIO", "EVOLUTION_RADIO" }

-- The same eight as the `radio_channels` registry sees them (src/mods/
-- Schemas.lua), one of the Gen 2-only six: Red has no radio, so the name is
-- gated under Gen 1 and routed to data.gen2RadioChannels under Gen 2.  Id =
-- the station the dial lands on, which is the LoadStation_* id
-- src/ui/gen2/Pokegear.lua's show state machine is keyed by; `channel` is its
-- MAPRADIO_* position, the byte a wall radio's `setval` passes the special.
-- Position 0 is deliberately unregistered: it is not a station, it resolves by
-- region and time of day in resolveStation below.
--
-- src/mods/Builtins.lua seeds these engine-owned, so a mod's register of
-- ROCKET_RADIO collides and has to say override.
local function seededName(data, station)
  local label = Pokegear.STATION_LABELS[station]
  local text = data and data.text
  if not (label and type(text) == "table" and text[label]) then return nil end
  return Pokegear.stationNameFrom(data, station)
end

function MapRadio.registerInto(registry, data, owner)
  local count = 0
  for channel, station in pairs(STATIONS) do
    registry:register(station, { channel = channel,
                                 name = seededName(data, station) }, owner)
    count = count + 1
  end
  -- Two Pokegear-only signals have no MAPRADIO_* index.  They still belong in
  -- the same registry because the tuner resolves their display names by id;
  -- leaving `channel` absent keeps wall-radio lookup unambiguous.
  for _, station in ipairs(POKEGEAR_ONLY_STATIONS) do
    registry:register(station, { name = seededName(data, station) }, owner)
    count = count + 1
  end
  local metadata = Buena.metadata(data)
  if metadata then
    registry:register("BUENAS_PASSWORD", { name = metadata.stationName }, owner)
    count = count + 1
  end
  return count
end

-- The merged record for a dial position, or nil.  Read through data rather
-- than through STATIONS so a registered station is on the dial for real; the
-- module's own table is the fallback for a boot with no loader.
function MapRadio.channelRecord(data, channel)
  local rows = data and data.gen2RadioChannels
  if type(rows) == "table" then
    for station, record in pairs(rows) do
      if type(record) == "table" and record.channel == channel then
        return record, station
      end
    end
    return nil
  end
  local station = STATIONS[channel]
  if not station then return nil end
  return { channel = channel, name = Pokegear.stationNameFrom(data, station) }, station
end

-- The player's landmark, the way Game2:currentLandmark reads it: the map
-- header's landmark byte resolved through the `landmarks` registry
-- (src/core/gen2/Nests.lua).  IsInJohto and the Rocket takeover both branch
-- on it.
local function landmarkOf(game)
  local world = game and game.world
  local map = world and world.map and world.map.def
  return Nests.landmarkId(game and game.data, map and map.landmark)
end

-- opts: channel (the MAPRADIO_* index setval left in wScriptVar), onDone(),
-- and for tests: save, currentLandmark, radioData, radioRng.
function MapRadio.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, MapRadio)
  self.game = game
  self.onDone = opts.onDone
  -- The Pokegear owns the radio data assembly (Pokegear:radioData) and the
  -- region/time reads; a gear instance that is never drawn keeps one copy of
  -- that wiring.
  self.gear = Pokegear.new(game, {
    save = opts.save or (game and game.save),
    currentLandmark = opts.currentLandmark or landmarkOf(game),
    radioData = opts.radioData,
    radioRng = opts.radioRng,
  })
  self.station, self.stationName = self:resolveStation(opts.channel or 0)
  self.radio = Pokegear.Radio.new({
    data = self.gear:radioData(), rng = opts.radioRng,
  })
  self.radio:tune(self.station)
  -- radio.channel, a Gen 2 invention: Gen 1 has no radio, so there is no name
  -- to share.  Raised on the tune rather than per show line, because the
  -- station is what a mod reasons about -- the show under it is the same state
  -- machine the Pokegear's radio card runs and reports its song through
  -- music.started like everything else.
  --
  --   station  the LoadStation_* id the dial landed on
  --   channel  the MAPRADIO_* index the script's setval passed in; 0 is the
  --            Pokemon Channel position, which resolves by region and hour
  --   name     the station's display name, the one quoted in the text box
  --   source   "map_radio" -- the wall radio, as against the Pokegear card
  if Runtime.wants("radio.channel") then
    Runtime.emit("radio.channel", {
      station = self.station, channel = opts.channel or 0,
      name = self:name(),
      source = "map_radio",
    })
  end
  -- .PlayStation parks ENTER_MAP_MUSIC before the show's own
  -- RadioMusicRestartDE lands the channel song, so backing out before the
  -- show starts still restores the map theme.
  self.radioMusicPlaying = "enterMap"
  self.radioSong = nil
  -- `ld c, 100 / call DelayFrames`: the name sits alone in the box before
  -- the show's first line, and no button is read during the delay.
  self.hold = 100
  return self
end

-- LoadStation_PokemonChannel: in Johto the morning airs the Pokedex Show and
-- the rest of the day Oak's Pokemon Talk; from Kanto the same dial position
-- carries Places & People.  Answers the station and, when the record carries
-- one, its own display name.
function MapRadio:resolveStation(channel)
  if channel ~= 0 then
    local record, station = MapRadio.channelRecord(
      self.game and self.game.data, channel)
    if station then return station, record and record.name end
    return "OAKS_POKEMON_TALK", nil
  end
  if self.gear:region() ~= "johto" then return "PLACES_AND_PEOPLE" end
  if (self.gear:timeOfDayIndex() or 0) == 0 then return "POKEDEX_SHOW" end
  return "OAKS_POKEMON_TALK"
end

-- The name quoted in the text box.  A loaded game resolves it through the
-- same registry as the Pokegear.
function MapRadio:name()
  if self.stationName then return self.stationName end
  return self.gear:stationName(self.station)
end

function MapRadio:close()
  Pokegear.exitRadioMusic(self.game, self.radioMusicPlaying)
  self.radioMusicPlaying = nil
  local stack = self.game and self.game.stack
  if stack then stack:pop() end
  if self.onDone then self.onDone() end
end

function MapRadio:update(_dt)
  if self.hold > 0 then
    self.hold = self.hold - 1
    return
  end
  local input = self.game and self.game.input
  if input and (input:wasPressed("a") or input:wasPressed("b")) then
    self:close()
    return
  end
  self.radio:step()
  local song = self.radio.music
  if song and song ~= self.radioSong then
    self.radioSong = song
    self.radioMusicPlaying = Pokegear.radioPlayingValue(song)
    local data = self.game and self.game.data
    if data then pcall(require("src.core.Music").play, data, song) end
  end
end

function MapRadio:draw()
  -- PlayRadio's own frame: Textbox at (0,12), 4 rows by 18, with the station
  -- name quoted at (2,14) until the show's first line scrolls in.
  Chrome.textbox(0, 12, 18, 4)
  local radio = self.radio
  if radio.top == "" and radio.bottom == "" then
    local name = self:name() or ""
    Chrome.print("“" .. name .. "”", 1, 14)
    return
  end
  if radio.top ~= "" then Chrome.print(radio.top, 1, 14) end
  if radio.bottom ~= "" then Chrome.print(radio.bottom, 1, 16) end
end

MapRadio.STATIONS = STATIONS

return MapRadio
