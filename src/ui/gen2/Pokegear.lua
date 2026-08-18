-- The POKeGEAR (engine/pokegear/pokegear.asm): Gen 2's clock, town map, radio
-- and phone in one device.
--
-- Transcribed rather than laid out by eye.  A Pokegear card is not a layout at
-- all -- it is a tilemap.  InitPokegearTilemap fills the screen with $4f, runs
-- the card's own entry, and then Pokegear_FinishTilemap lays the card strip
-- across the top two rows.  Three of the four cards are stored as RLE
-- tilemaps in the ROM (Pokegear_LoadTilemapRLE, whose comment has its own
-- format backwards: the first byte is the tile and the second the count) and
-- the MAP card is the painted region map, JohtoMap / KantoMap.
--
-- Both sheets live in one 96-tile block: Pokegear_LoadGFX puts TownMapGFX at
-- vTiles2 $00 and PokegearGFX at $30, so a tilemap byte under $30 is town map
-- art and anything above it is gear chrome.  Colour is by tile id rather than
-- by rectangle -- TownMapPals walks the tilemap and reads a nybble per tile
-- out of its PalMap, with $60 and up falling back to palette 0.
--
-- Card strip (Pokegear_FinishTilemap): the two rows are cleared to $4f, then
-- each owned card's 2x2 icon is laid as n, n+1 / n+$10, n+$11 -- MAP at (2,0)
-- from $40, PHONE at (4,0) from $44, RADIO at (6,0) from $42, and the gear
-- itself at (0,0) from $46.

local Chrome = require("src.ui.gen2.Chrome")
local Clock = require("src.core.gen2.Clock")
local Font = require("src.render.Font")
local Palettes = require("src.world.gen2.Palettes")
local Phone = require("src.core.gen2.Phone")
local SpriteRenderer = require("src.render.SpriteRenderer")
local TileSheet = require("src.ui.gen2.TileSheet")

local Pokegear = {}
Pokegear.__index = Pokegear
Pokegear.isOpaque = true

local SCREEN_W, SCREEN_H = 20, 18
local BLANK_TILE = 0x4f

-- POKEGEARCARD_* order (constants/pokegear_constants.asm: CLOCK, MAP, PHONE,
-- RADIO), with the icon each one contributes to the strip.  The order is load
-- bearing twice over: paging steps this list, and every joypad routine walks
-- the cards in exactly this sequence (PokegearClock_Joypad right -> MAP else
-- PHONE else RADIO, PokegearRadio_Joypad left -> PHONE else MAP else CLOCK),
-- while AnimatePokegearModeIndicatorArrow indexes its $00/$10/$20/$30 x offsets
-- by wPokegearCard.  Listing RADIO before PHONE made the arrow jump column 2 ->
-- 6 -> 4.
local CARDS = {
  { id = "clock", label = "CLOCK", icon = 0x46, iconX = 0 },
  { id = "map", label = "MAP", flag = "map", icon = 0x40, iconX = 2 },
  { id = "phone", label = "PHONE", flag = "phone", icon = 0x44, iconX = 4 },
  { id = "radio", label = "RADIO", flag = "radio", icon = 0x42, iconX = 6 },
}

-- _FlyMap draws the SAME town map, but it is not the MAP card: it is its own
-- screen (LoadTownMapGFX / FlyMap / TownMapBubble), with no card strip and no
-- ENGINE_MAP_CARD gate, which is why FLY works before the Guide Gent hands the
-- card over.  One row, so `#self.cards` stays 1 and nothing pages.
local FLY_MAP_CARD = { id = "map", label = "FLY" }

-- ---------------------------------------------------------------- the radio
--
-- engine/pokegear/radio.asm is not a text table: it is a jumptable of code.
-- Every station is a little state machine whose segments each print ONE line
-- and name the segment that prints the next, so the only way to get the shows
-- right is to port the shows.  What follows transcribes RadioJumptable row by
-- row; the segment names are the constants/radio_constants.asm ones so a row
-- here can be read against the routine it came from.
--
-- Three pieces of RAM drive all of it (ram/wram.asm):
--   wCurRadioLine        which segment runs this frame
--   wNextRadioLine       which segment RADIO_SCROLL hands control to
--   wRadioTextDelay      frames left before RADIO_SCROLL proceeds
--   wNumRadioLinesPrinted 0, 1 or 2 -- how much of the box is filled yet
-- and the display is the bottom text box's two lines, which
-- CopyBottomLineToTopLine scrolls up as each new line lands.

-- Channel ids.  The first ten are stations (NUM_RADIO_CHANNELS); everything
-- above is an internal segment.  The numbers matter in exactly one place --
-- PlayRadioShow's `cp POKE_FLUTE_RADIO` Rocket override -- so they are kept.
local RADIO_ID = {
  OAKS_POKEMON_TALK = 0x00, POKEDEX_SHOW = 0x01, POKEMON_MUSIC = 0x02,
  LUCKY_CHANNEL = 0x03, PLACES_AND_PEOPLE = 0x04, LETS_ALL_SING = 0x05,
  ROCKET_RADIO = 0x06, POKE_FLUTE_RADIO = 0x07, UNOWN_RADIO = 0x08,
  EVOLUTION_RADIO = 0x09,
}

-- data/radio/channel_music.asm, in the port's own song labels: the port names
-- songs the pokegold way (Music_*), not by the MUSIC_* constant.
local RADIO_CHANNEL_SONGS = {
  OAKS_POKEMON_TALK = "Music_ProfOaksPokemonTalk", -- MUSIC_POKEMON_TALK
  POKEDEX_SHOW = "Music_PokemonCenter",            -- MUSIC_POKEMON_CENTER
  POKEMON_MUSIC = "Music_TitleScreen",             -- MUSIC_TITLE
  LUCKY_CHANNEL = "Music_GameCorner",              -- MUSIC_GAME_CORNER
  PLACES_AND_PEOPLE = "Music_ViridianCity",        -- MUSIC_VIRIDIAN_CITY
  LETS_ALL_SING = "Music_Bicycle",                 -- MUSIC_BICYCLE
  ROCKET_RADIO = "Music_RocketTheme",              -- MUSIC_ROCKET_OVERTURE
  POKE_FLUTE_RADIO = "Music_PokeFluteChannel",
  UNOWN_RADIO = "Music_RuinsOfAlphRadio",
  EVOLUTION_RADIO = "Music_LakeOfRageRocketRadio",
}

-- The station names LoadStation_* hands the tuner (the *Name labels at the
-- bottom of pokegear.asm).  `#` is the four-tile POKé compression byte, so
-- spelling it out costs the same tiles; `<PKMN>` is NOT -- it is the two-tile
-- <PK><MN> ligature the font already carries, so it stays a ligature.
-- LoadStation_RocketRadio really does reuse LetsAllSingName, and
-- LoadStation_EvolutionRadio really does reuse UnownStationName.
local STATION_NAMES = {
  OAKS_POKEMON_TALK = "OAK's <PK><MN> Talk",
  POKEDEX_SHOW = "POKéDEX Show",
  POKEMON_MUSIC = "POKéMON Music",
  LUCKY_CHANNEL = "Lucky Channel",
  PLACES_AND_PEOPLE = "Places & People",
  LETS_ALL_SING = "Let's All Sing!",
  ROCKET_RADIO = "Let's All Sing!",
  POKE_FLUTE_RADIO = "POKé FLUTE",
  UNOWN_RADIO = "?????",
  EVOLUTION_RADIO = "?????",
}

-- OaksPKMNTalk8.Adverbs, in table order: `maskbits 16` makes every roll valid,
-- which is why there is no retry loop around it.
local OPT_ADVERBS = {
  "sweet and adorably", "wiggly and slickly", "aptly named and",
  "undeniably kind of", "so, so unbearably", "wow, impressively",
  "almost poisonously", "ooh, so sensually", "so mischievously",
  "so very topically", "sure addictively", "looks in water is",
  "evolution must be", "provocatively", "so flipped out and",
  "heart-meltingly",
}

-- OaksPKMNTalk9.Adjectives.
local OPT_ADJECTIVES = {
  "cute.", "weird.", "pleasant.", "bold, sort of.", "frightening.",
  "suave & debonair!", "powerful.", "exciting.", "now!", "inspiring.",
  "friendly.", "hot, hot, hot!", "stimulating.", "guarded.", "lovely.",
  "speedy.",
}

-- PeoplePlaces5.Adjectives and PeoplePlaces7.Adjectives are the same sixteen
-- rows in the same order, so one table serves both.
local PNP_ADJECTIVES = {
  "is cute.", "is sort of lazy.", "is always happy.", "is quite noisy.",
  "is precocious.", "is somewhat bold.", "is too picky!", "is sort of OK.",
  "is just so-so.", "is actually great.", "is just my type.",
  "is so cool, no?", "is inspiring!", "is kind of weird.",
  "is right for me?", "is definitely odd!",
}

-- RocketRadioText1..10.  The text_pause bytes inside 7-10 only stall the
-- printer, so the port carries the words either side of them as one line.
local ROCKET_LINES = {
  "… …Ahem, we are", "TEAM ROCKET!", "After three years",
  "of preparation, we", "have risen again", "from the ashes!",
  "GIOVANNI! Can you", "hear? We did it!", "Where is our Boss?",
  "Is he listening?",
}

-- data/radio/oaks_pkmn_talk_routes.asm: the fifteen maps Oak's Pokemon Talk
-- draws its wild mon from.  `and %11111` then `cp 15` is a rejection roll, so
-- a byte above 14 is thrown away rather than folded.
local OPT_ROUTES = {
  "ROUTE_29", "ROUTE_46", "ROUTE_30", "ROUTE_32", "ROUTE_34", "ROUTE_35",
  "ROUTE_37", "ROUTE_38", "ROUTE_39", "ROUTE_42", "ROUTE_43", "ROUTE_44",
  "ROUTE_45", "ROUTE_36", "ROUTE_31",
}

-- data/radio/pnp_places.asm.  Two of the nine are interiors picked purely for
-- the landmark they sit in (the Cerulean police station stands in for
-- CERULEAN CITY, the beta Cinnabar centre for CINNABAR ISLAND).
local PNP_PLACES = {
  "PALLET_TOWN", "ROUTE_22", "PEWTER_CITY", "CERULEAN_POLICE_STATION",
  "ROUTE_12", "ROUTE_11", "ROUTE_16", "ROUTE_14",
  "CINNABAR_POKECENTER_2F_BETA",
}

-- data/radio/pnp_hidden_people.asm is one list with two interior labels, and
-- the fallthrough is load bearing: PnP_HiddenPeople runs into
-- PnP_HiddenPeople_BeatE4, which runs into PnP_HiddenPeople_BeatKanto.  So
-- beating the Elite Four un-hides the E4 themselves, and sweeping Kanto's
-- badges un-hides its gym leaders too.
local PNP_HIDDEN = {
  "WILL", "BRUNO", "KAREN", "KOGA", "CHAMPION",
  -- PnP_HiddenPeople_BeatE4
  "BROCK", "MISTY", "LT_SURGE", "ERIKA", "JANINE", "SABRINA", "BLAINE",
  "BLUE",
  -- PnP_HiddenPeople_BeatKanto
  "RIVAL1", "POKEMON_PROF", "CAL", "RIVAL2", "RED",
}
local PNP_HIDDEN_BEAT_E4 = 6    -- first index of PnP_HiddenPeople_BeatE4
local PNP_HIDDEN_BEAT_KANTO = 14 -- first index of PnP_HiddenPeople_BeatKanto

-- TextCommand_DAY's .Days table, plus its "DAY" suffix.  GetWeekday counts
-- from Sunday = 0, which is NOT os.date's 1-based wday.
local RADIO_DAYS = {
  [0] = "SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY",
  "SATURDAY",
}

-- macros/data.asm: `percent` is `* $ff / 100`, so these are the two literal
-- thresholds PeoplePlaces rolls against.
local PNP_PEOPLE_CHANCE = math.floor(49 * 255 / 100) - 1 -- 49 percent - 1
local PNP_RESTART_CHANCE = math.floor(4 * 255 / 100)     -- 4 percent

-- A landmark name is stored with its town-map line break in it
-- ("BLACKTHORN\nCITY").  GetLandmarkName hands that to the radio verbatim,
-- break byte and all, which on hardware throws the rest of the sentence onto
-- the box's second line; the port spends the break as a space instead so the
-- sentence stays one radio line.
local function flatName(name)
  return (tostring(name or ""):gsub("\n", " "))
end

-- An hlcoord is a column of TILES, and the port stores its strings as UTF-8,
-- so "é" is two bytes and one tile.  Counting lead bytes gets the column
-- arithmetic right; it is only ever used on plain text, never on the <PK><MN>
-- ligature markers Font.split expands.
local function tileWidth(text)
  local width = 0
  for _ in tostring(text or ""):gmatch("[^\128-\191]") do width = width + 1 end
  return width
end

-- --------------------------------------------------------- the show machine
--
-- Radio is deliberately free of love, of Game and of drawing: it is the
-- jumptable and its four bytes of RAM, stepped one frame at a time, so a test
-- can seed `rng` and assert the exact line sequence a station produces.
--
-- `data` is the cache read the shows need, gathered by Pokegear:radioData():
--   landmarks[index]  = { name }          GetLandmarkName
--   mapLandmark[map]  = landmark index    GetWorldMapLocation
--   grass[map]        = { [0]=morn, [1]=day, [2]=nite } lists of species
--   species[index]    = name              GetPokemonName
--   dex[name]         = { kind, lines }   the Pokedex entry, split at <NEXT>
--   classes[index]    = { name, trainer } GetTrainerClassName / GetTrainerName
--   hidden[index]     = true              the resolved PnP_HiddenPeople list
--   caught(name)      -> boolean          CheckCaughtMon
--   weekday           = 0..6              GetWeekday
--   luckyNumber       = wLuckyIDNumber
local Radio = {}
Radio.__index = Radio

-- PlaceRadioString and PrintRadioLine both set wRadioTextDelay to 100; the
-- Pokemon Channel jingle's last hop uses 10.
local RADIO_LINE_FRAMES = 100
local RADIO_JINGLE_FRAMES = 10

local RadioJumptable = {}

function Radio.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Radio)
  self.data = opts.data or {}
  -- `call Random` yields one byte.  Without a supplied source the port falls
  -- back to math.random, which is fine for play and useless for a test.
  self.rng = opts.rng or function() return math.random(0, 255) end
  -- wCurRadioLine / wNextRadioLine / wRadioTextDelay / wNumRadioLinesPrinted.
  self.cur = nil
  self.next = nil
  self.delay = 0
  self.printed = 0
  -- The bottom text box's two lines.
  self.top, self.bottom = "", ""
  -- Every line this station has printed, oldest first: the scroll throws the
  -- top one away, and a test wants the whole sequence.
  self.log = {}
  -- wCurPartySpecies, wStringBuffer1/2 and wOaksPKMNTalkSegmentCounter, which
  -- survive across segments because the shows read them a segment later.
  self.vars = {}
  -- The label RadioMusicRestartDE was last asked for, so the caller can play
  -- it without the machine knowing what an audio system is.
  self.music = nil
  return self
end

-- `call Random`: one byte, 0..255.
function Radio:random()
  return math.floor(self.rng() or 0) % 256
end

-- Half the shows sample by rejection: roll a byte, throw it away if it is out
-- of range, roll again.  On hardware those loops are unbounded because
-- `call Random` never repeats itself; the port cannot promise that of an
-- injected roll source, so every sampler is capped.  A sampler that runs out
-- of tries leaves its segment without printing, and the next frame retries the
-- whole segment -- which is what the cart would do with a stuck RNG anyway.
local RADIO_SAMPLE_TRIES = 512

function Radio:sample(pick)
  for _ = 1, RADIO_SAMPLE_TRIES do
    local value = pick(self:random())
    if value ~= nil then return value end
  end
  return nil
end

-- LoadStation_*: every one of them parks the station id in wCurRadioLine and
-- zeroes wNumRadioLinesPrinted, which is what makes StartRadioStation fire
-- once and once only.
function Radio:tune(station)
  self.cur = station
  self.next = nil
  self.delay = 0
  self.printed = 0
  self.top, self.bottom = "", ""
  self.log = {}
  self.vars = {}
  self.music = nil
end

-- StartRadioStation: on the first frame of a station only, clear the box and
-- start RadioChannelSongs[wCurRadioLine].
function Radio:startStation()
  if self.printed ~= 0 then return end
  self.top, self.bottom = "", ""
  self.music = RADIO_CHANNEL_SONGS[self.cur]
end

-- PrintRadioLine.  The first line lands on the box's top row, the second on
-- its bottom row (`bccoord 1, 16`), and every line after that on the bottom
-- row with RADIO_SCROLL having moved the previous one up first.
function Radio:printLine(text, nextLine)
  self.next = nextLine
  -- wRadioText itself: the buffer keeps the last line composed into it, which
  -- is what OaksPKMNTalk4's .overflow branch reprints.
  self.text = text
  if self.printed < 2 then
    self.printed = self.printed + 1
    if self.printed == 1 then self.top = text else self.bottom = text end
  else
    self.bottom = text
  end
  self.log[#self.log + 1] = text
  self.cur = "RADIO_SCROLL"
  self.delay = RADIO_LINE_FRAMES
end

-- NextRadioLine is PrintRadioLine with a CopyRadioTextToRAM in front of it.
-- The copy is invisible here (the port passes the composed line straight in),
-- but the two are kept apart because several segments compose the text a
-- segment early and then reach PrintRadioLine directly.
Radio.nextLine = Radio.printLine

-- PlaceRadioString: no scroll, no line counter -- it stamps a string into the
-- box where it stands and waits 100 frames.  Only the Pokemon Channel jingle
-- uses it, which is why the jingle does not scroll.
function Radio:placeString(nextLine)
  self.cur = nextLine
  self.delay = RADIO_LINE_FRAMES
end

-- One frame of PlayRadioShow.
function Radio:step()
  -- Team Rocket broadcasts on every station: a station id below
  -- POKE_FLUTE_RADIO, in Johto, with the tower occupied, is overwritten.  The
  -- comparison is against the id, so mid-show segments (all $0a and up) never
  -- trigger it -- the takeover can only happen between shows.
  local id = RADIO_ID[self.cur]
  if id and id < RADIO_ID.POKE_FLUTE_RADIO
    and self.data.rocketsInRadioTower and self.data.inJohto then
    self.cur = "ROCKET_RADIO"
  end
  local segment = RadioJumptable[self.cur]
  if segment then segment(self) end
end

-- RadioScroll: burn the delay, then hand over to wNextRadioLine.  The
-- `cp 1` skips the copy for the very first line, which is still sitting on
-- the top row and has nothing under it to scroll up.
RadioJumptable["RADIO_SCROLL"] = function(R)
  if R.delay ~= 0 then
    R.delay = R.delay - 1
    return
  end
  R.cur = R.next
  if R.printed ~= 1 then R.top = R.bottom end
  R.bottom = ""
end

-- ----------------------------------------------------- Oak's Pokemon Talk
--
-- Five wild-mon segments (wOaksPKMNTalkSegmentCounter) and then the Pokemon
-- Channel jingle, which resets the counter and drops back into the fourth
-- segment for another five.

RadioJumptable["OAKS_POKEMON_TALK"] = function(R)
  R.vars.segmentCounter = 5
  R:startStation()
  R:nextLine("MARY: PROF.OAK'S", "OAKS_POKEMON_TALK_2")
end

RadioJumptable["OAKS_POKEMON_TALK_2"] = function(R)
  R:nextLine("POKéMON TALK!", "OAKS_POKEMON_TALK_3")
end

RadioJumptable["OAKS_POKEMON_TALK_3"] = function(R)
  R:nextLine("With me, MARY!", "OAKS_POKEMON_TALK_4")
end

-- OaksPKMNTalk4: roll a route, roll a time of day, roll one of the middle
-- three grass slots, and name the mon and the route it walks.
RadioJumptable["OAKS_POKEMON_TALK_4"] = function(R)
  -- .sample: `and %11111` then `cp 15`, so a byte above the table's length is
  -- rerolled rather than wrapped.
  local map = R:sample(function(roll)
    roll = roll % 32
    if roll < #OPT_ROUTES then return OPT_ROUTES[roll + 1] end
    return nil
  end)
  if not map then return end
  local slots = R.data.grass and R.data.grass[map]
  if not slots then
    -- .overflow: a map with no row in JohtoGrassWildMons restarts the show
    -- from its intro, reprinting whatever wRadioText still holds.
    return R:printLine(R.text or "", "OAKS_POKEMON_TALK")
  end
  -- .loop2: `maskbits NUM_DAYTIMES` then reject DARKNESS_F, so 0, 1 or 2.
  local daytime = R:sample(function(roll)
    roll = roll % 4
    return roll ~= 3 and roll or nil
  end)
  -- .loop3: `maskbits NUM_GRASSMON` then reject below 2 and 5 or above, which
  -- leaves the middle three of the seven slots.
  local slot = R:sample(function(roll)
    roll = roll % 8
    return (roll >= 2 and roll < 5) and roll or nil
  end)
  if not (daytime and slot) then return end
  local list = slots[daytime] or slots[0] or {}
  local species = list[slot + 1]
  R.vars.species = species
  R.vars.landmark = R.data.mapLandmark and R.data.mapLandmark[map]
  -- _OPT_OakText1 is "OAK: @" plus the mon name, with no punctuation: the
  -- sentence is finished by the next two segments.
  R:printLine("OAK: " .. tostring(species or ""), "OAKS_POKEMON_TALK_5")
end

RadioJumptable["OAKS_POKEMON_TALK_5"] = function(R)
  R:nextLine("may be seen around", "OAKS_POKEMON_TALK_6")
end

RadioJumptable["OAKS_POKEMON_TALK_6"] = function(R)
  -- _OPT_OakText3 is the landmark name with a full stop welded on.
  local entry = R.data.landmarks and R.data.landmarks[R.vars.landmark]
  R:nextLine(flatName(entry and entry.name) .. ".", "OAKS_POKEMON_TALK_7")
end

RadioJumptable["OAKS_POKEMON_TALK_7"] = function(R)
  R:nextLine("MARY: " .. tostring(R.vars.species or "") .. "'s",
    "OAKS_POKEMON_TALK_8")
end

RadioJumptable["OAKS_POKEMON_TALK_8"] = function(R)
  local adverb = OPT_ADVERBS[R:random() % 16 + 1]
  R:nextLine(adverb, "OAKS_POKEMON_TALK_9")
end

-- OaksPKMNTalk9 rolls the adjective FIRST and only then spends the segment
-- counter, so the roll happens on the fifth pass too.
RadioJumptable["OAKS_POKEMON_TALK_9"] = function(R)
  local adjective = OPT_ADJECTIVES[R:random() % 16 + 1]
  R.vars.segmentCounter = (R.vars.segmentCounter or 1) - 1
  local nextLine = "OAKS_POKEMON_TALK_4"
  if R.vars.segmentCounter == 0 then
    R.vars.segmentCounter = 5
    nextLine = "OAKS_POKEMON_TALK_10"
  end
  R:nextLine(adjective, nextLine)
end

-- The Pokemon Channel jingle.  OaksPKMNTalk10 calls PrintText rather than
-- PrintRadioLine, so it bypasses the scroll entirely: the box is redrawn with
-- "POKéMON" on its top row and the three PlaceRadioString hops then stamp the
-- rest in over 100 frames each.
RadioJumptable["OAKS_POKEMON_TALK_10"] = function(R)
  R.music = "Music_PokemonChannel" -- RadioMusicRestartPokemonChannel
  R.top, R.bottom = "POKéMON", ""
  R.log[#R.log + 1] = R.top
  R.cur = "OAKS_POKEMON_TALK_11"
  R.delay = RADIO_LINE_FRAMES
end

-- `hlcoord 9, 14` is the top row, column 9; the box's text starts at column 1,
-- so the stamp lands eight cells in from what is already there.
RadioJumptable["OAKS_POKEMON_TALK_11"] = function(R)
  R.delay = R.delay - 1
  if R.delay ~= 0 then return end
  R.top = R.top .. string.rep(" ", math.max(0, 8 - tileWidth(R.top))) .. "POKéMON"
  R.log[#R.log + 1] = R.top
  R:placeString("OAKS_POKEMON_TALK_12")
end

RadioJumptable["OAKS_POKEMON_TALK_12"] = function(R)
  R.delay = R.delay - 1
  if R.delay ~= 0 then return end
  R.bottom = "POKéMON Channel" -- hlcoord 1, 16
  R.log[#R.log + 1] = R.bottom
  R:placeString("OAKS_POKEMON_TALK_13")
end

-- `hlcoord 12, 16` with a bare "@": nothing is drawn, the hop only buys
-- another 100 frames of the jingle.
RadioJumptable["OAKS_POKEMON_TALK_13"] = function(R)
  R.delay = R.delay - 1
  if R.delay ~= 0 then return end
  R:placeString("OAKS_POKEMON_TALK_14")
end

-- Back to the talk: the music restarts, PrintText with a bare terminator wipes
-- the box, and wNumRadioLinesPrinted goes back to zero so the next two lines
-- fill the box from the top again.
RadioJumptable["OAKS_POKEMON_TALK_14"] = function(R)
  R.delay = R.delay - 1
  if R.delay ~= 0 then return end
  R.music = "Music_ProfOaksPokemonTalk" -- MUSIC_POKEMON_TALK
  R.top, R.bottom = "", ""
  R.next = "OAKS_POKEMON_TALK_4"
  R.printed = 0
  R.cur = "RADIO_SCROLL"
  R.delay = RADIO_JINGLE_FRAMES
end

-- ------------------------------------------------------------ Pokedex Show
--
-- One caught species, then its Pokedex entry read out a line at a time: the
-- kind ("TINY BIRD"), then the six description lines, then a new species.

RadioJumptable["POKEDEX_SHOW"] = function(R)
  R:startStation()
  -- `cp NUM_POKEMON` rejects a byte of 251 or more, then CheckCaughtMon
  -- rejects anything the player has not caught.  The index is still zero-based
  -- there; the `inc c` after the loop is what makes it a species number.  A
  -- Pokedex with nothing in it spins this loop forever on hardware, which is
  -- why the port's sampler is the capped one.
  local species = R:sample(function(roll)
    if roll >= 251 then return nil end
    local name = R.data.species and R.data.species[roll + 1]
    if not name then return nil end
    if R.data.caught and not R.data.caught(name) then return nil end
    return name
  end)
  if not species then return end
  R.vars.species = species
  R:nextLine(species, "POKEDEX_SHOW_2")
end

-- PokedexShow2 prints from the entry's own start, which is the species kind,
-- and then steps the read pointer past the height/weight words.
RadioJumptable["POKEDEX_SHOW_2"] = function(R)
  local entry = R.data.dex and R.data.dex[R.vars.species]
  R:printLine(entry and entry.kind or "", "POKEDEX_SHOW_3")
end

-- PokedexShow3..8 are the same routine six times over: copy the next line of
-- the entry, print it, name the next segment.  The eighth hands back to
-- POKEDEX_SHOW, which rolls a fresh species.
local POKEDEX_SHOW_SEGMENTS = {
  "POKEDEX_SHOW_3", "POKEDEX_SHOW_4", "POKEDEX_SHOW_5", "POKEDEX_SHOW_6",
  "POKEDEX_SHOW_7", "POKEDEX_SHOW_8",
}
for index, segment in ipairs(POKEDEX_SHOW_SEGMENTS) do
  RadioJumptable[segment] = function(R)
    local entry = R.data.dex and R.data.dex[R.vars.species]
    local lines = entry and entry.lines or {}
    R:printLine(lines[index] or "",
      POKEDEX_SHOW_SEGMENTS[index + 1] or "POKEDEX_SHOW")
  end
end

-- --------------------------------------- Pokemon Music / Let's All Sing
--
-- Two stations that meet: BenMonMusic is Johto's, FernMonMusic is Kanto's, and
-- LETS_ALL_SING_2 jumps straight into POKEMON_MUSIC_4 so both DJs read the
-- same three closing lines.

-- StartPokemonMusicChannel picks the song off the weekday's low bit, and
-- BenFernMusic5/6 read the same bit again for the words that go with it.
local function startPokemonMusicChannel(R)
  R.top, R.bottom = "", ""
  local odd = (R.data.weekday or 0) % 2 == 1
  R.music = odd and "Music_PokemonLullaby" or "Music_PokemonMarch"
end

RadioJumptable["POKEMON_MUSIC"] = function(R)
  startPokemonMusicChannel(R)
  R:nextLine("BEN: POKéMON MUSIC", "POKEMON_MUSIC_2")
end

RadioJumptable["POKEMON_MUSIC_2"] = function(R)
  R:nextLine("CHANNEL!", "POKEMON_MUSIC_3")
end

RadioJumptable["POKEMON_MUSIC_3"] = function(R)
  R:nextLine("It's me, DJ BEN!", "POKEMON_MUSIC_4")
end

RadioJumptable["LETS_ALL_SING"] = function(R)
  startPokemonMusicChannel(R)
  R:nextLine("FERN: POKéMUSIC!", "LETS_ALL_SING_2")
end

-- FernMonMusic2 names POKEMON_MUSIC_4, not a LETS_ALL_SING segment: this is
-- the handoff, and from here Kanto's station is running Johto's code.
RadioJumptable["LETS_ALL_SING_2"] = function(R)
  R:nextLine("With DJ FERN!", "POKEMON_MUSIC_4")
end

RadioJumptable["POKEMON_MUSIC_4"] = function(R)
  local day = RADIO_DAYS[(R.data.weekday or 0) % 7] or ""
  R:nextLine("Today's " .. day .. ",", "POKEMON_MUSIC_5")
end

RadioJumptable["POKEMON_MUSIC_5"] = function(R)
  local odd = (R.data.weekday or 0) % 2 == 1
  R:nextLine(odd and "so chill out to" or "so let us jam to",
    "POKEMON_MUSIC_6")
end

RadioJumptable["POKEMON_MUSIC_6"] = function(R)
  local odd = (R.data.weekday or 0) % 2 == 1
  R:nextLine(odd and "POKéMON Lullaby!" or "POKéMON March!", "POKEMON_MUSIC_7")
end

-- BenFernMusic7 is a bare `ret`.  Both music stations really do stop talking
-- here and play out, and nothing ever leaves this segment.
RadioJumptable["POKEMON_MUSIC_7"] = function() end

-- ------------------------------------------------------- Lucky Number Show
--
-- Eleven fixed lines, the week's number read out twice, and a 1-in-256 chance
-- of REED admitting he is bored before he starts over.

local LUCKY_LINES = {
  LUCKY_CHANNEL = { "REED: Yeehaw! How", "LUCKY_NUMBER_SHOW_2" },
  LUCKY_NUMBER_SHOW_2 = { "y'all doin' now?", "LUCKY_NUMBER_SHOW_3" },
  LUCKY_NUMBER_SHOW_3 = { "Whether you're up", "LUCKY_NUMBER_SHOW_4" },
  LUCKY_NUMBER_SHOW_4 = { "or way down low,", "LUCKY_NUMBER_SHOW_5" },
  LUCKY_NUMBER_SHOW_5 = { "don't you miss the", "LUCKY_NUMBER_SHOW_6" },
  LUCKY_NUMBER_SHOW_6 = { "LUCKY NUMBER SHOW!", "LUCKY_NUMBER_SHOW_7" },
  LUCKY_NUMBER_SHOW_7 = { "This week's Lucky", "LUCKY_NUMBER_SHOW_8" },
  LUCKY_NUMBER_SHOW_9 = { "I'll repeat that!", "LUCKY_NUMBER_SHOW_10" },
  -- LC_Text7 and LC_Text8 again: REED reads the number out a second time.
  LUCKY_NUMBER_SHOW_10 = { "This week's Lucky", "LUCKY_NUMBER_SHOW_11" },
  LUCKY_NUMBER_SHOW_12 = { "Match it and go to", "LUCKY_NUMBER_SHOW_13" },
  LUCKY_NUMBER_SHOW_14 = { "…Repeating myself", "LUCKY_NUMBER_SHOW_15" },
  LUCKY_NUMBER_SHOW_15 = { "gets to be a drag…", "LUCKY_CHANNEL" },
}
for segment, row in pairs(LUCKY_LINES) do
  RadioJumptable[segment] = function(R)
    if segment == "LUCKY_CHANNEL" then R:startStation() end
    R:nextLine(row[1], row[2])
  end
end

-- LuckyNumberShow8 prints wLuckyIDNumber with PRINTNUM_LEADINGZEROS over five
-- digits, so a low number reads as "00042".
local function luckyNumberLine(R)
  return ("Number is %05d!"):format(math.floor(R.data.luckyNumber or 0) % 100000)
end

RadioJumptable["LUCKY_NUMBER_SHOW_8"] = function(R)
  R:nextLine(luckyNumberLine(R), "LUCKY_NUMBER_SHOW_9")
end

RadioJumptable["LUCKY_NUMBER_SHOW_11"] = function(R)
  R:nextLine(luckyNumberLine(R), "LUCKY_NUMBER_SHOW_12")
end

-- `call Random / and a`: only a rolled zero takes the drag lines, so REED
-- complains about once every 256 times round.
RadioJumptable["LUCKY_NUMBER_SHOW_13"] = function(R)
  local roll = R:random()
  R:nextLine("the RADIO TOWER!",
    roll ~= 0 and "LUCKY_CHANNEL" or "LUCKY_NUMBER_SHOW_14")
end

-- ------------------------------------------------------- Places and People
--
-- DJ LILY alternates between a trainer ("People") and a landmark ("Places"),
-- with a 4% chance after each of restarting the show from its own intro.

RadioJumptable["PLACES_AND_PEOPLE"] = function(R)
  R:startStation()
  R:nextLine("PLACES AND PEOPLE!", "PLACES_AND_PEOPLE_2")
end

RadioJumptable["PLACES_AND_PEOPLE_2"] = function(R)
  R:nextLine("Brought to you by", "PLACES_AND_PEOPLE_3")
end

-- `cp 49 percent - 1` with `jr c` taking People, so the split is 123/256 to
-- People and the rest to Places.
local function peopleOrPlaces(R)
  return R:random() < PNP_PEOPLE_CHANCE and "PLACES_AND_PEOPLE_4"
    or "PLACES_AND_PEOPLE_6"
end

RadioJumptable["PLACES_AND_PEOPLE_3"] = function(R)
  R:nextLine("me, DJ LILY!", peopleOrPlaces(R))
end

-- PeoplePlaces4: roll a trainer class, reject the ones the hidden list is
-- covering this playthrough, and name its first trainer.
RadioJumptable["PLACES_AND_PEOPLE_4"] = function(R)
  local classes = R.data.classes or {}
  local hidden = R.data.hidden or {}
  -- `maskbits NUM_TRAINER_CLASSES` is a 128 mask, `inc a` makes it one-based,
  -- and `cp NUM_TRAINER_CLASSES + 1` throws away anything past the sixty-six
  -- real classes.  IsInArray against PnP_HiddenPeople is a third rejection,
  -- not a skip: the roll is spent and another one is taken.
  local index = R:sample(function(roll)
    roll = roll % 128 + 1
    if roll > 66 or hidden[roll] or not classes[roll] then return nil end
    return roll
  end)
  local class = index and classes[index]
  if not class then return end
  R.vars.class = class.name
  R.vars.trainer = class.trainer
  R.vars.classIndex = index
  -- _PnP_Text4 is the class name and the trainer name with one space between.
  R:nextLine(tostring(class.name or "") .. " " .. tostring(class.trainer or ""),
    "PLACES_AND_PEOPLE_5")
end

-- PeoplePlaces5 rolls the adjective, then a 4% restart, then the People/Places
-- coin again.  Three rolls, always in that order.
RadioJumptable["PLACES_AND_PEOPLE_5"] = function(R)
  local adjective = PNP_ADJECTIVES[R:random() % 16 + 1]
  local nextLine = "PLACES_AND_PEOPLE"
  if R:random() >= PNP_RESTART_CHANCE then nextLine = peopleOrPlaces(R) end
  R:nextLine(adjective, nextLine)
end

-- PeoplePlaces6: roll one of the nine PnP_Places maps and name its landmark.
RadioJumptable["PLACES_AND_PEOPLE_6"] = function(R)
  -- `cp (PnP_Places.End - PnP_Places) / 2`: a byte past the nine rows is
  -- rerolled, not folded.
  local map = R:sample(function(roll)
    if roll < #PNP_PLACES then return PNP_PLACES[roll + 1] end
    return nil
  end)
  if not map then return end
  local index = R.data.mapLandmark and R.data.mapLandmark[map]
  local entry = R.data.landmarks and R.data.landmarks[index]
  R.vars.landmark = index
  R:nextLine(flatName(entry and entry.name), "PLACES_AND_PEOPLE_7")
end

-- PeoplePlaces7 is PeoplePlaces5 with the same three rolls in the same order.
RadioJumptable["PLACES_AND_PEOPLE_7"] = function(R)
  local adjective = PNP_ADJECTIVES[R:random() % 16 + 1]
  local nextLine = "PLACES_AND_PEOPLE"
  if R:random() >= PNP_RESTART_CHANCE then nextLine = peopleOrPlaces(R) end
  R:printLine(adjective, nextLine)
end

-- ------------------------------------------------------------ Rocket Radio
--
-- Ten fixed lines on a loop.  Nothing rolls, nothing branches.

RadioJumptable["ROCKET_RADIO"] = function(R)
  R:startStation()
  R:nextLine(ROCKET_LINES[1], "ROCKET_RADIO_2")
end
for index = 2, 10 do
  RadioJumptable["ROCKET_RADIO_" .. index] = function(R)
    R:nextLine(ROCKET_LINES[index],
      index < 10 and ("ROCKET_RADIO_" .. (index + 1)) or "ROCKET_RADIO")
  end
end

-- ------------------------------------------------- the three music stations
--
-- PokeFluteRadio, UnownRadio and EvolutionRadio start their song, set
-- wNumRadioLinesPrinted to 1 so StartRadioStation never fires again, and
-- return.  They print nothing at all, ever: the box stays empty.
for _, station in ipairs({ "POKE_FLUTE_RADIO", "UNOWN_RADIO",
  "EVOLUTION_RADIO" }) do
  RadioJumptable[station] = function(R)
    R:startStation()
    R.printed = 1
  end
end

-- ------------------------------------------------------------- the tuner
--
-- RadioChannels (engine/pokegear/pokegear.asm) is the dial: a tuning-knob
-- value and the routine that decides whether anything is on it.  The comment
-- there gives the arithmetic: frequency value = 4 x ingame frequency - 2, so
-- knob 16 is the 04.5 mark.  A knob position whose test fails is not a station
-- at all -- NoRadioStation wipes the name and the box and plays nothing.
--
-- `signal(ctx)` returns the station to load, or nil for dead air.  ctx carries
-- inJohto, timeOfDay, landmark (the player's, not the cursor's), expnCard and
-- rocketSignal.
local RADIO_CHANNELS = {
  -- .PKMNTalkAndPokedexShow: the Pokedex Show airs in the morning and Oak's
  -- Pokemon Talk the rest of the day, off the same frequency.
  { knob = 16, frequency = "04.5", signal = function(ctx)
      if not ctx.inJohto then return nil end
      if (ctx.timeOfDay or 0) == 0 then return "POKEDEX_SHOW" end
      return "OAKS_POKEMON_TALK"
    end },
  { knob = 28, frequency = "07.5", signal = function(ctx)
      return ctx.inJohto and "POKEMON_MUSIC" or nil
    end },
  { knob = 32, frequency = "08.5", signal = function(ctx)
      return ctx.inJohto and "LUCKY_CHANNEL" or nil
    end },
  -- .RuinsOfAlphRadio is a one-landmark station: the static only resolves
  -- standing in the Ruins of Alph themselves.
  { knob = 52, frequency = "13.5", signal = function(ctx)
      return ctx.landmark == "LANDMARK_RUINS_OF_ALPH" and "UNOWN_RADIO" or nil
    end },
  { knob = 64, frequency = "16.5", signal = function(ctx)
      return (not ctx.inJohto) and "PLACES_AND_PEOPLE" or nil
    end },
  { knob = 72, frequency = "18.5", signal = function(ctx)
      return (not ctx.inJohto) and "LETS_ALL_SING" or nil
    end },
  -- .PokeFluteRadio also wants the EXPN card, which is the Kanto radio
  -- upgrade.
  { knob = 78, frequency = "20.0", signal = function(ctx)
      if ctx.inJohto or not ctx.expnCard then return nil end
      return "POKE_FLUTE_RADIO"
    end },
  -- .EvolutionRadio only airs while Team Rocket is still in Mahogany, and only
  -- within earshot of the Lake of Rage.
  { knob = 80, frequency = "20.5", signal = function(ctx)
      if not ctx.rocketSignal then return nil end
      local here = ctx.landmark
      if here == "LANDMARK_MAHOGANY_TOWN" or here == "LANDMARK_ROUTE_43"
        or here == "LANDMARK_LAKE_OF_RAGE" then
        return "EVOLUTION_RADIO"
      end
      return nil
    end },
}

-- PHONE_DISPLAY_HEIGHT.
local PHONE_ROWS = 4

-- data/text/common_3.asm.  Every one of these lives in ROM bank $66, which the
-- importer does not reach yet (it follows map script pointers and nothing on a
-- map points into the phone banks), so they are transcribed here with the
-- "bank:addr" key their extracted form will have -- Pokegear:phoneText prefers
-- the extracted string and only falls back to the transcription.
local PHONE_TEXT = {
  GearEllipse = { key = "66:4066", body = "……" },
  GearOutOfService = { key = "66:4069",
    body = "You're out of the service area." },
  AskWhoCall = { key = "66:4089", body = "Whom do you want to call?" },
  -- _PokegearPressButtonText, the CLOCK card's bottom-box prompt.
  PressButton = { key = "66:40a4", body = "Press any button to exit." },
  AskDelete = { key = "66:40bf", body = "Delete this stored phone number?" },
  WrongNumber = { key = "66:40e1", body = "Huh? Sorry, wrong number!" },
  Click = { key = "66:40fc", body = "Click!" },
  PhoneEllipse = { key = "66:4104", body = "……" },
  OutOfArea = { key = "66:4107", body = "That number is out of the area." },
  JustTalkToThem = { key = "66:4128", body = "Just go talk to that person!" },
}

function Pokegear:wantsFillScale() return true end
function Pokegear:drawsWidescreen() return true end

-- opts: save, landmarks (landmarks.lua), currentLandmark, clock, menuGfx,
-- radioData (a prebuilt Radio data table, for tests), radioRng, onClose(),
-- mapDef (the maps.lua record the player is standing on, for the phone's
-- signal / same-map tests), trainers (trainers.lua, for contact names), text
-- (text.lua) and onCall(descriptor), which hands a placed call out to whoever
-- can run its script
function Pokegear.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, Pokegear)
  self.game = game
  self.save = opts.save or (game and game.save)
  local data = game and game.data or {}
  self.landmarks = opts.landmarks or data.gen2Landmarks
  self.currentLandmark = opts.currentLandmark
  self.clock = opts.clock
  self.onClose = opts.onClose
  self.cards = self:visibleCards()
  self.cardIndex = 1
  self.mode = "strip" -- strip | card
  -- Which RadioChannels row the tuning knob sits on.  The knob itself runs
  -- 0..80 in steps of two; the port steps the row instead, because every
  -- position between two stations is the same dead air.
  self.station = 1
  -- wPokegearPhoneCursorPosition / wPokegearPhoneScrollPosition, both of which
  -- are ZERO based on the cart: the cursor runs 0..PHONE_DISPLAY_HEIGHT - 1
  -- inside the visible window and the scroll runs 0..CONTACT_LIST_SIZE -
  -- PHONE_DISPLAY_HEIGHT.  Neither wraps.
  self.phoneCursor = 0
  self.phoneScroll = 0
  -- wPokegearPhoneSubmenuCursor, and which submenu is open at all.
  self.phoneSubmenu = nil
  self.phoneSubmenuCursor = 0
  self.mapDef = opts.mapDef
  self.trainers = opts.trainers or data.trainers or data.gen2Trainers
  -- text.lua, for the phone strings; `text` is already a method name here.
  self.textData = opts.text
  self.onCall = opts.onCall
  -- The show that the tuned frequency resolved to, and its state machine.
  -- Both are nil while the knob sits on dead air (NoRadioStation).
  self.radioShow = nil
  self.radio = nil
  self.radioDataOverride = opts.radioData
  self.radioRng = opts.radioRng
  self.radioOn = false
  -- TownMap_InitCursorAndPlayerIconPositions seeds both the player icon and
  -- the cursor from the landmark the player is standing in; the d-pad then
  -- walks the CURSOR's landmark index while the icon stays put.
  self.mapCursor = nil
  -- The call the phone card is showing, if any.
  self.call = nil

  -- _FlyMap's own state.  `fly` is FieldMoves.flyPoints' answer: this region's
  -- half of the Flypoints table with every row CheckIfVisitedFlypoint would
  -- reject already dropped, so the cursor's skip loop is just "next row".
  self.fly = opts.fly
  self.onFly = opts.onFly
  if self.fly and #self.fly > 0 then
    self.cards = { FLY_MAP_CARD }
    self.cardIndex = 1
    self.mode = "card"
    -- FlyMap's defaults: the Johto map opens on JOHTO_FLYPOINT (New Bark
    -- Town) and the Kanto one on NUM_FLYPOINTS - 1 (Indigo Plateau), not on
    -- wherever the player is standing.
    self.flyIndex = (self:region() == "kanto") and #self.fly or 1
  end

  -- _CGB_PokegearPals writes wBGPals1 only (engine/gfx/cgb_layouts.asm:157),
  -- so the RED_WALK icon keeps the overworld's own OBJ palette.
  self.sprites = opts.sprites or data.gen2Sprites
  self.palettes = opts.palettes or data.gen2Palettes

  local gfx = (opts.menuGfx or data.gen2MenuGfx or {}).pokegear
  self.gfx = gfx
  if gfx then
    self.sheet = TileSheet.new({
      path = gfx.tiles, wide = gfx.tilesWide or 16, firstTile = 0,
      paletteFor = function(tile) return self:colorsFor(tile) end,
    })
  end
  return self
end

function Pokegear:styled()
  return self.sheet ~= nil and self.sheet:available()
end

-- TownMapPals: a nybble per tile id for $00..$5f, palette 0 above that.
function Pokegear:colorsFor(tile)
  local gfx = self.gfx
  if not (gfx and gfx.palettes) then return nil end
  if tile >= 0x60 then return gfx.palettes[1] end
  return gfx.palettes[(gfx.palMap and gfx.palMap[tile + 1]) or 1]
end

-- Every string on a Pokegear card is a run of font tiles laid straight into
-- the tilemap, so it wears BG palette 0 (PokegearPals' first entry) rather
-- than drawing as black ink over whatever was underneath.
function Pokegear:text(str, tx, ty)
  local pals = self.gfx and self.gfx.palettes
  return Chrome.printThrough(str, tx, ty, pals and pals[1])
end

-- wPokegearFlags' four card bits are ENGINE flags: EngineFlags rows 0-3 are
-- POKEGEAR_RADIO/MAP/PHONE/EXPN_CARD_F (pokegold data/events/engine_flags.asm,
-- constants/engine_flags.asm const order), so the scripts' `setflag` -- the
-- Radio Tower quiz's ENGINE_RADIO_CARD, the Guide Gent's ENGINE_MAP_CARD,
-- Mom's ENGINE_PHONE_CARD and the Lavender tower's ENGINE_EXPN_CARD -- lands
-- each id in save.engineFlags through World:setEngineFlag.  The string-keyed
-- save.pokegearFlags overlay stays readable so a test can seed a card without
-- a world.
local CARD_ENGINE_FLAGS = { radio = 0, map = 1, phone = 2, expn = 3 }

function Pokegear:flags()
  local save = self.save or {}
  local flags = {}
  for key, value in pairs(save.pokegearFlags or {}) do flags[key] = value end
  local engine = save.engineFlags or {}
  for key, id in pairs(CARD_ENGINE_FLAGS) do
    if engine[id] == true then flags[key] = true end
  end
  return flags
end

function Pokegear:visibleCards()
  local flags = self:flags()
  local out = {}
  for _, card in ipairs(CARDS) do
    if not card.flag or flags[card.flag] then out[#out + 1] = card end
  end
  return out
end

function Pokegear:card()
  return self.cards[self.cardIndex]
end

-- PokegearClock_Init / UpdateClock read hHours, hMinutes and GetWeekday right
-- after UpdateTime, so the CLOCK card shows the GAME clock: the RTC through the
-- save's wStartHour / wStartMinute base.  The gear is pushed over a live world,
-- and that world already owns the read (World:hour, plus the POKEPORT_GOLD_HOUR
-- pin a driver sets), so prefer it and fall back to the save's own base when
-- there is no world underneath (the Pokegear opened from a test).
--
-- `weekday` comes back 1-based for the DAYS table; wCurDay counts SUNDAY 0.
function Pokegear:clockParts()
  if self.clock then
    return self.clock.hour or 0, self.clock.minute or 0,
      self.clock.weekday or 1
  end
  local world = self.game and self.game.world
  if world and world.hour then
    return world:hour(), world:minute(), (world:weekday() % 7) + 1
  end
  local save = self.save
  return Clock.hour(save), Clock.minute(save), Clock.weekday(save) + 1
end

-- wPhoneList itself: ten ordered slots, 0 for an empty one.  The empty slots
-- are part of the display (PokegearPhone_UpdateDisplayList draws four rows
-- unconditionally, and slot 0 renders as NonTrainerCallerNames' "----------"),
-- so this does not compact them away.
function Pokegear:phoneList()
  return Phone.contacts(self.save)
end

-- The contact under the cursor, or 0 for an empty slot.  `.a` on the phone
-- card reads wPhoneList + scroll + cursor and returns straight back out when
-- that byte is zero.
function Pokegear:phoneSelection()
  return self:phoneList()[self.phoneScroll + self.phoneCursor + 1] or 0
end

-- What the phone model needs to know about where the player is standing:
-- GetMapPhoneService reads the map header, and both the same-map test and
-- SpecialCallOnlyWhenOutside read the map record too.  The Pokegear is pushed
-- from the start menu with the world still underneath it, so the record is
-- either handed in or read off that world.
function Pokegear:phoneContext()
  local map = self.mapDef
  if not map then
    local world = self.game and self.game.world
    map = world and world.map and world.map.def
  end
  local hour, minute = self:clockParts()
  return { map = map, clock = { hour = hour, minute = minute } }
end

-- A common phone string: the extracted text when bank $66 finally arrives,
-- and the transcription from data/text/common_3.asm until then.
function Pokegear:phoneText(name)
  local entry = PHONE_TEXT[name]
  if not entry then return "" end
  local text = self.textData
    or (self.game and self.game.world and self.game.world.text)
  local extracted = text and text[entry.key]
  if extracted and extracted ~= "" then return extracted end
  return entry.body
end

-- GetCallerClassAndName: a trainer contact is "<name>:" over the class name, a
-- non-trainer is its NonTrainerCallerNames string and nothing under it.
function Pokegear:contactRow(id)
  local name, className = Phone.contactName(id, self.trainers)
  return (name or "----------") .. ":", className
end

function Pokegear:update(_dt)
  -- .Frameset_RedWalk (data/sprite_anims/framesets.asm:81): four 8-frame
  -- beats, so the map card's player icon walks in place.
  self.iconTimer = ((self.iconTimer or 0) + 1) % 32
  local input = self.game and self.game.input
  if not input then return end
  -- The fly picker owns the whole screen: no strip, no card paging, and B
  -- answers -1 rather than backing out to the strip.
  if self.fly then return self:updateFlyMap(input) end
  if self.mode == "strip" then
    local stripCard = self:card()
    if not (stripCard and stripCard.id == "phone") then
      if input:wasPressed("left") then
        self.cardIndex = self.cardIndex > 1 and self.cardIndex - 1 or #self.cards
      elseif input:wasPressed("right") then
        self.cardIndex = self.cardIndex < #self.cards and self.cardIndex + 1 or 1
      elseif input:wasPressed("a") then
        self.mode = "card"
      elseif input:wasPressed("b") then
        if self.onClose then self.onClose() end
      end
      return
    end
    self.mode = "card"
  end
  -- Inside a card.
  local card = self:card()
  -- The phone card owns B while it is showing a call or a submenu: on the cart
  -- those are their own jumptable states (POKEGEARSTATE_PHONE*), and B closes
  -- the state, not the card.
  -- The busy test comes FIRST: wasPressed consumes the press, so asking about
  -- B before knowing whether the phone wants it would eat the button the
  -- submenu is waiting for.
  local phoneBusy = card and card.id == "phone"
    and (self.call ~= nil or self.phoneSubmenu ~= nil)
  -- engine/pokegear/pokegear.asm:799
  if card and card.id == "phone" and not phoneBusy then
    if input:wasPressed("b") then
      if self.onClose then self.onClose() end
      return
    elseif input:wasPressed("left") then
      self:switchCard("map", "clock")
      return
    elseif input:wasPressed("right") then
      self:switchCard("radio")
      return
    end
  end
  if not phoneBusy and input:wasPressed("b") then
    self.mode = "strip"
    self:stopRadio()
    self.call = nil
    self.phoneSubmenu = nil
    return
  end
  if card and card.id == "radio" then
    self:ensureTuned()
    -- AnimateTuningKnob.TuningKnob: up winds the knob towards 80 and down
    -- back towards 0, and it stops dead at either end rather than wrapping.
    -- The port steps RadioChannels rows, so "stops dead" is a clamp.
    if input:wasPressed("up") then
      if self.station < #RADIO_CHANNELS then
        self.station = self.station + 1
        self:tuneRadio()
      end
    elseif input:wasPressed("down") then
      if self.station > 1 then
        self.station = self.station - 1
        self:tuneRadio()
      end
    end
    self:tickRadio()
  elseif card and card.id == "phone" then
    self:updatePhone(input)
  elseif card and card.id == "map" then
    self:moveMapCursor(input)
  end
end

-- --------------------------------------------------------------------- radio
--
-- .InJohto: the S.S. Aqua counts as Johto and so does anything below
-- KANTO_LANDMARK ($2e = 46).  This reads the PLAYER's landmark, never the map
-- cursor's -- the two are separate bytes for exactly this reason.
function Pokegear:region()
  local landmarks = self.landmarks and self.landmarks.landmarks
  local current = landmarks and self.currentLandmark
    and landmarks[self.currentLandmark]
  local index = current and current.index or 0
  -- LANDMARK_FAST_SHIP is $5e = 94, past every Kanto landmark and still Johto.
  if index == 94 then return "johto" end
  if index >= 46 then return "kanto" end
  return "johto"
end

-- The context RadioChannels' per-frequency tests read.
function Pokegear:radioContext()
  local save = self.save or {}
  local flags = self:flags()
  local world = self.game and self.game.world
  return {
    inJohto = self:region() == "johto",
    landmark = self.currentLandmark,
    -- wTimeOfDay: MORN is 0, which is the only value that swaps Oak's
    -- Pokemon Talk out for the Pokedex Show.  Palettes.DAYTIME_ID is 1-based
    -- for Lua's sake, so it comes back down a step here.
    timeOfDay = self.timeOfDay or self:timeOfDayIndex(),
    -- POKEGEAR_EXPN_CARD_F, the Kanto radio upgrade.
    expnCard = flags.expn or false,
    -- STATUSFLAGS_ROCKET_SIGNAL_F, set while Team Rocket holds Mahogany.
    rocketSignal = (save.flags or {}).ROCKET_SIGNAL or false,
  }
end

-- Every RadioChannels row, with the station its test resolves to right now
-- (nil where NoRadioStation would fire).
function Pokegear:stations()
  local ctx = self:radioContext()
  local out = {}
  for index, row in ipairs(RADIO_CHANNELS) do
    local station = row.signal(ctx)
    out[index] = {
      knob = row.knob, frequency = row.frequency, station = station,
      name = station and STATION_NAMES[station] or nil,
    }
  end
  return out
end

function Pokegear:currentStation()
  return self:stations()[self.station]
end

-- UpdateRadioStation: the knob moved, so resolve the frequency, hand the show
-- machine the station it landed on, and let RadioChannelSongs replace the
-- map's music.  Dead air is NoRadioStation: no name, no box, no song.
function Pokegear:tuneRadio()
  local row = self:currentStation()
  local station = row and row.station
  self.radioTuned = true
  self.radioShow = station
  if not station then
    self.radio = nil
    self.radioOn = false
    -- NoRadioStation: MUSIC_NONE now, and ENTER_MAP_MUSIC parked in
    -- wPokegearRadioMusicPlaying so leaving the radio on dead air brings the
    -- map's own theme back (ExitPokegearRadio_HandleMusic).
    self.radioMusicPlaying = "enterMap"
    local data = self.game and self.game.data
    if data then pcall(require("src.core.Music").stop) end
    return
  end
  self.radio = Radio.new({ data = self:radioData(), rng = self.radioRng })
  self.radio:tune(station)
  self.radioOn = true
  self:playRadioMusic()
end

-- PokegearRadio_Init resolves the knob before the card is ever drawn, so a
-- card that arrives already selected (a driver setting cardIndex by hand, or
-- a save resumed on the radio) still knows what it is playing.
function Pokegear:ensureTuned()
  if self.radioTuned then return end
  self:tuneRadio()
end

-- One frame of PlayRadioShow, plus whatever song the show asked for on the
-- way through (RadioMusicRestartDE is a call, not a table lookup, so the
-- Pokemon Channel jingle really does change the music mid-show).
function Pokegear:tickRadio()
  if not self.radio then return end
  self.radio:step()
  self:playRadioMusic()
end

-- What a started song leaves in wPokegearRadioMusicPlaying.  Every station
-- start goes through RadioMusicRestartDE, which parks the SONG there (and in
-- wMapMusic); the one exception is the Pokemon Channel jingle, whose
-- RadioMusicRestartPokemonChannel parks RESTART_MAP_MUSIC instead -- closing
-- the gear mid-jingle gives the map its music back.
function Pokegear.radioPlayingValue(song)
  if song == "Music_PokemonChannel" then return "restartMap" end
  return song
end

function Pokegear:playRadioMusic()
  local song = self.radio and self.radio.music
  if not song or song == self.radioSong then return end
  self.radioSong = song
  self.radioMusicPlaying = Pokegear.radioPlayingValue(song)
  local data = self.game and self.game.data
  if not data then return end
  pcall(require("src.core.Music").play, data, song)
end

-- The cache reads the shows need, gathered once per Pokegear.  Everything
-- here is a lookup the cart does with a farcall (GetLandmarkName,
-- GetWorldMapLocation, GetPokemonName, GetTrainerClassName); the port hands
-- the show machine tables instead so it stays testable.
function Pokegear:radioData()
  if self.radioDataOverride then return self.radioDataOverride end
  if self.radioDataCache then return self.radioDataCache end
  local data = (self.game and self.game.data) or {}
  local save = self.save or {}
  local out = { inJohto = self:region() == "johto" }

  -- Landmarks by index, which is how GetLandmarkName and GetWorldMapLocation
  -- both address them.
  out.landmarks = {}
  for _, entry in pairs((self.landmarks or {}).landmarks or {}) do
    out.landmarks[entry.index or 0] = entry
  end

  -- GetWorldMapLocation is a map -> landmark lookup; the extracted maps carry
  -- the landmark index the cart's table would have returned.
  out.mapLandmark = {}
  local maps = (self.game and self.game.world and self.game.world.maps)
    or data.gen2Maps or {}
  for id, def in pairs(maps) do out.mapLandmark[id] = def.landmark end

  -- JohtoGrassWildMons, keyed by map and then by the time-of-day block Oak's
  -- Pokemon Talk indexes with `AddNTimes 2 * NUM_GRASSMON`.
  out.grass = {}
  for id, row in pairs((data.gen2Encounters or {}).grass or {}) do
    local slots = row.slots or {}
    local block = {}
    for index, key in ipairs({ "MORN", "DAY", "NITE" }) do
      local list = {}
      for slot, entry in ipairs(slots[key] or {}) do list[slot] = entry.species end
      block[index - 1] = list
    end
    out.grass[id] = block
  end

  -- Species by internal index, which is what the Pokedex Show rolls.
  out.species = {}
  for name, def in pairs(data.pokemon or {}) do
    if def.index then out.species[def.index] = name end
  end
  local caught = (save.pokedex or {}).caught or {}
  out.caught = function(name) return caught[name] == true end

  -- Pokedex entries, split the way CopyDexEntryPart1 walks them: the kind
  -- name first, then one line per <NEXT>, with the page break ('@') simply
  -- joining the two pages into one run of six.
  out.dex = {}
  for name, entry in pairs((data.gen2Pokedex or {}).entries or {}) do
    local lines = {}
    for _, page in ipairs({ entry.text, entry.text2 }) do
      for line in (tostring(page or "") .. "<NEXT>"):gmatch("(.-)<NEXT>") do
        if line ~= "" then lines[#lines + 1] = line end
      end
    end
    out.dex[name] = { kind = entry.kind, lines = lines }
  end

  -- TrainerClassNames and the class's first trainer, by class index.
  out.classes = {}
  for _, class in pairs((data.gen2Trainers or {}).classes or {}) do
    if class.index then
      out.classes[class.index] = {
        name = class.name,
        trainer = class.trainers and class.trainers[1]
          and class.trainers[1].name,
      }
    end
  end
  out.hidden = self:hiddenPeople()

  out.weekday = self:radioWeekday()
  -- wLuckyIDNumber, rolled by src/script/gen2/Specials.lua's
  -- ResetLuckyNumberShowFlag (engine/events/lucky_number.asm's
  -- LoadOrRegenerateLuckyIDNumber).  A save that has never visited the Lucky
  -- Number Man in Radio Tower has never rolled one, so 00000 is the honest
  -- reading, not a stand-in for unfinished work.
  out.luckyNumber = save.luckyNumber or 0
  out.rocketsInRadioTower = (save.flags or {}).ROCKETS_IN_RADIO_TOWER or false
  self.radioDataCache = out
  return out
end

-- PnP_HiddenPeople, resolved to class indices against this save's progress.
-- The list is walked from one of three entry points, so the further along the
-- player is, the shorter it gets.
function Pokegear:hiddenPeople()
  local save = self.save or {}
  local first = 1
  if (save.flags or {}).HALL_OF_FAME then
    first = PNP_HIDDEN_BEAT_E4
    local badges = (save.player or {}).kantoBadges or {}
    local count = 0
    for _, has in pairs(badges) do if has then count = count + 1 end end
    if count >= 8 then first = PNP_HIDDEN_BEAT_KANTO end
  end
  local hidden = {}
  for index = first, #PNP_HIDDEN do
    local classIndex = self:trainerClassIndex(PNP_HIDDEN[index])
    if classIndex then hidden[classIndex] = true end
  end
  return hidden
end

function Pokegear:trainerClassIndex(id)
  local classes = (self.game and self.game.data and self.game.data.gen2Trainers
    or {}).classes or {}
  local class = classes[id]
  return class and class.index or nil
end

-- wTimeOfDay, as the cart numbers it: MORN 0, DAY 1, NITE 2, DARK 3.
function Pokegear:timeOfDayIndex()
  local world = self.game and self.game.world
  local daytime = (world and world.daytime)
    or Palettes.clockDaytime(self.clock and self.clock.hour or nil)
  return (Palettes.DAYTIME_ID[daytime] or 2) - 1
end

-- GetWeekday counts from Sunday = 0; clockParts answers in the 1-based DAYS
-- numbering the clock card draws with, so the radio's day is that same read
-- shifted down rather than a second clock.
function Pokegear:radioWeekday()
  local _, _, weekday = self:clockParts()
  return ((weekday or 1) - 1) % 7
end

-- ExitPokegearRadio_HandleMusic (pokegold engine/pokegear/pokegear.asm): what
-- leaving the radio does to the music is decided by wPokegearRadioMusicPlaying,
-- not done unconditionally.  A tuned station's song was written into wMapMusic
-- by RadioMusicRestartDE, so it KEEPS PLAYING and is the map music from then
-- on -- Music.setMapSong makes a battle's restore replay it, and only a map
-- change replaces it.  ENTER_MAP_MUSIC (dead air) and RESTART_MAP_MUSIC (the
-- Pokemon Channel jingle) are the two arms that bring the map theme back.
-- Shared with src/ui/gen2/MapRadio.lua, whose PlayRadio exit runs the same
-- routine.
function Pokegear.exitRadioMusic(game, playing)
  if not playing then return end
  local data = game and game.data
  if not data then return end
  local Music = require("src.core.Music")
  if playing ~= "enterMap" and playing ~= "restartMap" then
    Music.setMapSong(playing)
    return
  end
  local world = game and game.world
  local song = world and world.map and world.map.def and world.map.def.music
  if song then pcall(Music.play, data, song) else pcall(Music.stop) end
end

function Pokegear:stopRadio()
  local playing = self.radioMusicPlaying
  self.radio = nil
  self.radioShow = nil
  self.radioSong = nil
  self.radioTuned = nil
  self.radioMusicPlaying = nil
  self.radioOn = false
  Pokegear.exitRadioMusic(self.game, playing)
end

-- --------------------------------------------------------------------- phone
--
-- The phone card is four jumptable states on the cart, and they are separate
-- states because each one owns the buttons outright:
--
--   PHONEJOYPAD    the list.  PokegearPhone_GetDPad walks the cursor, A opens
--                  the contact submenu.
--   (submenu)      PokegearPhoneContactSubmenu, a blocking loop rather than a
--                  state: CALL / DELETE / CANCEL, with DELETE withheld from a
--                  contact CheckCanDeletePhoneNumber refuses (MOM and ELM).
--   MAKEPHONECALL  PokegearPhone_MakePhoneCall -- two rings, then
--                  MakePhoneCallFromPokegear.
--   FINISHCALL     any button hangs up.

-- PokegearPhoneContactSubmenu's two string tables.  The three-entry menu draws
-- its box at (9,4) and the two-entry one at (9,6), because the box origin is
-- computed from the STRING coordinate by `bccoord -1, -2, 0`; entries are one
-- <NEXT> apart, which is TWO tile rows, and the cursor column steps by the
-- same two rows.
local PHONE_SUBMENUS = {
  callDeleteCancel = { x = 9, y = 4, rows = 3, textX = 11, textY = 6,
    entries = { "CALL", "DELETE", "CANCEL" } },
  callCancel = { x = 9, y = 6, rows = 2, textX = 11, textY = 8,
    entries = { "CALL", "CANCEL" } },
}

Pokegear.PHONE_SUBMENUS = PHONE_SUBMENUS

-- PokegearPhone_GetDPad, then `.a`.  Neither the cursor nor the scroll wraps:
-- the cursor stops at the top and bottom of the four visible rows and hands
-- over to the scroll, which stops at 0 and at CONTACT_LIST_SIZE - 4.
function Pokegear:updatePhone(input)
  -- A placed call owns the buttons: PokegearPhone_FinishPhoneCall takes A or B
  -- and hangs up.
  if self.call then
    if input:wasPressed("a") or input:wasPressed("b") then
      self:hangUp()
    end
    return
  end
  if self.phoneSubmenu then
    self:updatePhoneSubmenu(input)
    return
  end
  if input:wasPressed("a") then
    -- `ld a, [hl] / and a / ret z`: an empty slot is not a contact.
    if self:phoneSelection() ~= 0 then self:openPhoneSubmenu() end
    return
  end
  if input:wasPressed("up") then
    if self.phoneCursor > 0 then
      self.phoneCursor = self.phoneCursor - 1
    elseif self.phoneScroll > 0 then
      self.phoneScroll = self.phoneScroll - 1
    end
  elseif input:wasPressed("down") then
    if self.phoneCursor < PHONE_ROWS - 1 then
      self.phoneCursor = self.phoneCursor + 1
    elseif self.phoneScroll < Phone.CONTACT_LIST_SIZE - PHONE_ROWS then
      self.phoneScroll = self.phoneScroll + 1
    end
  end
end

-- CheckCanDeletePhoneNumber picks which of the two menus opens.
function Pokegear:openPhoneSubmenu()
  local id = self:phoneSelection()
  self.phoneSubmenu = Phone.canDelete(id) and "callDeleteCancel" or "callCancel"
  self.phoneSubmenuCursor = 0
end

function Pokegear:updatePhoneSubmenu(input)
  local menu = PHONE_SUBMENUS[self.phoneSubmenu]
  if not menu then
    self.phoneSubmenu = nil
    return
  end
  -- `.d_up` refuses to move off entry 0 and `.d_down` off the last one; the
  -- cart's own loop simply keeps looping, so this is a clamp, not a wrap.
  if input:wasPressed("up") then
    if self.phoneSubmenuCursor > 0 then
      self.phoneSubmenuCursor = self.phoneSubmenuCursor - 1
    end
    return
  end
  if input:wasPressed("down") then
    if self.phoneSubmenuCursor < menu.rows - 1 then
      self.phoneSubmenuCursor = self.phoneSubmenuCursor + 1
    end
    return
  end
  -- `.a_b`: B always means Cancel, whatever the cursor is on.
  if input:wasPressed("b") then
    self.phoneSubmenu = nil
    return
  end
  if not input:wasPressed("a") then return end
  local choice = menu.entries[self.phoneSubmenuCursor + 1]
  self.phoneSubmenu = nil
  if choice == "CALL" then
    self:callContact(self:phoneSelection())
  elseif choice == "DELETE" then
    -- The cart asks first (PokegearAskDeleteText + YesNoBox).  There is no
    -- yes/no box inside a Pokegear card in this port, so the submenu entry is
    -- the confirmation; the prompt is what the deletion state shows.
    Phone.deleteContactAt(self.save, self.phoneScroll + self.phoneCursor + 1)
  end
end

-- PokegearPhone_MakePhoneCall.  The no-signal branch never reaches
-- MakePhoneCallFromPokegear at all: it plays SFX_NO_SIGNAL and prints
-- _GearOutOfServiceText, which is a DIFFERENT string from the "that number is
-- out of the area" the engine's own out-of-area path prints.
function Pokegear:callContact(id)
  if not id or id == 0 then return end
  local context = self:phoneContext()
  if not Phone.mapHasService(context) then
    self.call = { contact = id, kind = "nosignal",
      text = self:phoneText("GearOutOfService") }
    return
  end
  -- pokegold engine/pokegear/pokegear.asm:883-889: SFX_CALL rings before the call connects.
  local world = self.game and self.game.world
  if world then world:playSfxNamed("Sfx_Call", 106) end
  local call = Phone.call(self.save, id, context)
  local name, className = Phone.contactName(id, self.trainers)
  call.name, call.className = name, className
  if call.kind == "outofarea" then
    call.text = self:phoneText("OutOfArea")
  elseif call.kind == "justtalk" then
    call.text = self:phoneText("JustTalkToThem")
  elseif call.wrongNumber then
    call.text = self:phoneText("WrongNumber")
  else
    -- What the cart shows while a call connects: Phone_TextboxWithName's
    -- "NAME:" and PhoneEllipseText.  The handler below runs the callee script
    -- over it; the ellipsis stays under its pages the way the cart's does.
    call.text = (name or "") .. ": " .. self:phoneText("PhoneEllipse")
  end
  self.call = call
  -- Hand the descriptor out.  Game2:runPokegearCall is the live handler:
  -- the contact's extracted SCRIPT1 runs through the overworld VM and its
  -- pages ride the state stack over this card.  With no handler (a bare
  -- test harness) the card still shows the ring and the caller's name.
  if self.onCall then self.onCall(call) end
end

-- HangUp: the click, the boops, and back to "Whom do you want to call?".
function Pokegear:hangUp()
  -- pokegold engine/phone/phone.asm:517-519: HangUp_Beep plays SFX_HANG_UP.
  if self.call and self.call.kind ~= "nosignal" then
    local world = self.game and self.game.world
    if world then world:playSfxNamed("Sfx_HangUp", 107) end
  end
  self.call = nil
end

-- ----------------------------------------------------------------------- map
--
-- PokegearMap_JohtoMap / PokegearMap_KantoMap.  The cursor is a landmark
-- INDEX, not a position: up steps to the next landmark id and down to the
-- previous one, and the two limit registers d (the last landmark of the
-- region) and e (the first) are what it wraps between.
--
-- LANDMARK_* indices, from constants/landmark_constants.asm:
--   NEW_BARK_TOWN $01   SILVER_CAVE $2d   PALLET_TOWN $2e
--   VICTORY_ROAD  $57   ROUTE_28    $5d   FAST_SHIP   $5e
-- LANDMARK_SPECIAL ($00) and LANDMARK_FAST_SHIP ($5e) sit outside both
-- ranges, so the cursor can never land on either.
local LANDMARK_NEW_BARK_TOWN = 0x01
local LANDMARK_SILVER_CAVE = 0x2d
local LANDMARK_PALLET_TOWN = 0x2e
local LANDMARK_VICTORY_ROAD = 0x57
local LANDMARK_ROUTE_28 = 0x5d

-- Returns d (last) and e (first).  Kanto's pair comes from
-- TownMap_GetKantoLandmarkLimits, which withholds everything west of Victory
-- Road until the Hall of Fame is on the record -- before that the Kanto map
-- only walks the seven landmarks on the road to Indigo Plateau.
function Pokegear:cursorLimits()
  if self:region() ~= "kanto" then
    return LANDMARK_SILVER_CAVE, LANDMARK_NEW_BARK_TOWN
  end
  if ((self.save or {}).flags or {}).HALL_OF_FAME then
    return LANDMARK_ROUTE_28, LANDMARK_PALLET_TOWN
  end
  return LANDMARK_ROUTE_28, LANDMARK_VICTORY_ROAD
end

-- The cursor's landmark index.  Unset, it is the player's own, which is what
-- TownMap_InitCursorAndPlayerIconPositions writes into both bytes.
function Pokegear:mapCursorIndex()
  -- On the fly screen the cursor IS the flypoint row: _FlyMap walks the
  -- Flypoints table and reads the landmark out of it, so the name plate and
  -- the arrow both follow the row rather than a free landmark index.
  local flyRow = self:flyRow()
  if flyRow and flyRow.index then return flyRow.index end
  if self.mapCursor then return self.mapCursor end
  local landmarks = self.landmarks and self.landmarks.landmarks
  local current = landmarks and self.currentLandmark
    and landmarks[self.currentLandmark]
  local _, first = self:cursorLimits()
  return current and current.index or first
end

-- PokegearMap_ContinueMap's .DPad.  Both branches share the increment or
-- decrement that follows them, which is why the wrap writes e - 1 / d + 1
-- rather than e / d.
function Pokegear:moveMapCursor(input)
  local last, first = self:cursorLimits()
  local cursor = self:mapCursorIndex()
  if input:wasPressed("up") then
    -- `cp d / jr c, .wrap_around_up`: below the last landmark the value is
    -- left alone, at or past it the cursor is slammed to e - 1 first.
    if cursor >= last then cursor = first - 1 end
    cursor = cursor + 1
  elseif input:wasPressed("down") then
    -- `cp e / jr nz, .wrap_around_down`: only the first landmark wraps.
    if cursor == first then cursor = last + 1 end
    cursor = cursor - 1
  elseif input:wasPressed("right") then
    -- Left and right do not move the cursor at all on this card: they page
    -- the POKeGEAR.  .right takes the PHONE if it is owned and the RADIO if
    -- it is not; .left always takes the CLOCK.
    self:switchCard("phone", "radio")
    return
  elseif input:wasPressed("left") then
    self:switchCard("clock")
    return
  else
    return
  end
  self.mapCursor = cursor
end

-- ------------------------------------------------------------------ fly map
--
-- _FlyMap's `.loop` (engine/pokegear/pokegear.asm:1978): A takes the flypoint
-- the cursor is on, B answers -1, and .HandleDPad walks the Flypoints table
-- with up/down, wrapping between wStartFlypoint and wEndFlypoint and skipping
-- every row CheckIfVisitedFlypoint rejects.  Left and right do nothing at all
-- here -- there is no card to page to.
function Pokegear:updateFlyMap(input)
  local rows = self.fly or {}
  local count = #rows
  if count == 0 then
    if self.onClose then self.onClose() end
    return
  end
  if input:wasPressed("up") then
    self.flyIndex = ((self.flyIndex or 1) % count) + 1
  elseif input:wasPressed("down") then
    self.flyIndex = ((self.flyIndex or 1) - 2) % count + 1
  elseif input:wasPressed("a") then
    local row = rows[self.flyIndex or 1]
    if row and self.onFly then self.onFly(row.spawn) end
  elseif input:wasPressed("b") then
    if self.onClose then self.onClose() end
  end
end

-- The flypoint under the cursor.
function Pokegear:flyRow()
  if not self.fly then return nil end
  return self.fly[self.flyIndex or 1]
end

-- Pokegear_SwitchPage: take the first of the named cards the player owns.
function Pokegear:switchCard(...)
  for _, id in ipairs({ ... }) do
    for index, card in ipairs(self.cards) do
      if card.id == id then
        self.cardIndex = index
        if id == "radio" then self:tuneRadio() end
        return true
      end
    end
  end
  return false
end

-- The landmark the map card is naming and parking the cursor sprite on:
-- PokegearMap_UpdateCursorPosition reads the CURSOR's landmark, never the
-- player icon's.
function Pokegear:mapLandmark()
  local index = self:mapCursorIndex()
  for _, entry in pairs((self.landmarks or {}).landmarks or {}) do
    if entry.index == index then return entry end
  end
  return nil
end

-- The landmark the player icon sits on, which the d-pad never moves.
function Pokegear:playerLandmark()
  local landmarks = self.landmarks and self.landmarks.landmarks
  return landmarks and self.currentLandmark and landmarks[self.currentLandmark]
    or nil
end

-- ---------------------------------------------------------------- tile layer

-- A card's tilemap uses exactly two "empty" cells and they are NOT the same
-- colour, which is the whole reason the gear reads as a lit panel on black:
--
--   $4f  the ground InitPokegearTilemap ByteFills SCREEN_AREA with.  A solid
--        colour-3 tile, so it is BLACK (Pokegear:groundColor), and it is what
--        every cell outside a card's art stays.
--   $7f  a font-page SPACE.  Every pixel is colour 0, so it is the CREAM
--        plate, and it is what fills the SWITCH box, the day/time window and
--        the map's label strip.  The clock card's own tilemap spells both out:
--        `30 7f 7f 7f 7f 7f 7f 31` is the SWITCH box's top row (rounded
--        corners around six spaces), and the window interior is nothing but
--        $7f between the $16 sides.
--
-- Neither is in the gear's tile sheet -- they are font-page ids -- so both are
-- painted here rather than blitted.  Before this, a $7f drew nothing and the
-- black ground showed through, which took the cream out of the SWITCH box and
-- left the clock window an empty black rectangle.
local SPACE_TILE = 0x7f

function Pokegear:tile(id, tx, ty)
  if id == SPACE_TILE then
    local paper = self:paperColor()
    local G = love.graphics
    G.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
    G.rectangle("fill", tx * 8, ty * 8, 8, 8)
    G.setColor(1, 1, 1, 1)
    return
  end
  if id == BLANK_TILE then
    local ground = self:groundColor()
    local G = love.graphics
    G.setColor(ground[1] / 255, ground[2] / 255, ground[3] / 255, 1)
    G.rectangle("fill", tx * 8, ty * 8, 8, 8)
    G.setColor(1, 1, 1, 1)
    return
  end
  if self.sheet then self.sheet:draw(id, tx, ty) end
end

function Pokegear:drawTilemap(cells)
  if not cells then return end
  for index = 1, SCREEN_W * SCREEN_H do
    local tile = cells[index]
    if tile then
      self:tile(tile, (index - 1) % SCREEN_W,
        math.floor((index - 1) / SCREEN_W))
    end
  end
end

-- Pokegear_FinishTilemap.
-- PokegearSpritesGFX, shared by the mode indicator arrow ($00) and the town
-- map cursor ($04).  Loaded once and remembered as `false` when there is no
-- sheet at all, so a missing asset is not retried every frame.
function Pokegear:loadArrowSheet()
  if self.arrow ~= nil then return end
  self.arrow = false
  local gfx = self.gfx
  if gfx and gfx.sprites then
    self:loadPlayerIcon()
    self.arrow = TileSheet.new({
      path = gfx.sprites, wide = gfx.spritesWide or 2, firstTile = 0,
      -- pokegold data/sprite_anims/oam.asm .OAMData_RedWalk: STILL_CURSOR's
      -- oamset reuses RED_WALK's OAM data, so this wears PAL_OW_RED.
      palette = (self.playerIcon and self.playerIcon.objColors)
        or (gfx.palettes and gfx.palettes[1]),
    })
  end
end

function Pokegear:drawStrip()
  for x = 0, 7 do
    self:tile(BLANK_TILE, x, 0)
    self:tile(BLANK_TILE, x, 1)
  end
  for _, card in ipairs(self.cards) do
    local n, x = card.icon, card.iconX
    self:tile(n, x, 0)
    self:tile(n + 1, x + 1, 0)
    self:tile(n + 0x10, x, 1)
    self:tile(n + 0x11, x + 1, 1)
  end
end

-- The mode indicator arrow.  Two things about it follow from its being an OBJ
-- rather than part of the tilemap, and both were wrong when it was drawn
-- inside drawStrip:
--
--   * It is ABOVE everything.  A card's own art goes down after the strip, so
--     drawing the arrow with the icons put the phone list's window frame over
--     its tip and the list's plate behind its stem.  On hardware an OBJ is
--     composited over the BG whatever the BG is, so this draws LAST, from
--     drawPanel, after whichever card has finished.
--   * It sits directly under the strip.  The icons are rows 0 and 1, so the
--     arrow's top is row 2 -- its tip touches the selected icon's bottom edge,
--     which is the whole point of an indicator.  Four pixels lower and it
--     reads as floating in the card rather than hanging off the icon.
--
-- AnimatePokegearModeIndicatorArrow slides it $10 pixels per card, which is
-- exactly one icon's width, so the x follows the selected card's own column.
--
-- Tiles $00-$03: a 16x16 up-triangle with a short stem, which is why the town
-- map cursor starts at $04 and why PokegearSpritesGFX is two tiles wide.
-- $00/$01 are its top row and $02/$03 its bottom; drawing $00 alone put the
-- triangle's top-left corner on screen and nothing else, which is the thin
-- diagonal sliver that read as a broken cursor.
function Pokegear:drawModeArrow()
  local card = self:card()
  local G = love.graphics
  -- CENTRED on the icon, not hung off its corner.  An icon is two tiles wide
  -- (iconX, iconX + 1) and the arrow is two tiles wide too, so their left
  -- edges are the same column: starting a tile further right put the arrow's
  -- centre over the icon's right-hand edge, which reads as belonging to the
  -- gap between two cards rather than to either one.
  local iconX = (card and card.iconX or 0) * 8
  self:loadArrowSheet()
  if self.arrow and self.arrow:available() then
    G.setColor(1, 1, 1, 1)
    -- The sprite's first two pixel rows are all but empty (the triangle proper
    -- starts on row 2 of tile $00), so the block is lifted half a tile: the
    -- apex then meets the icon's bottom edge and tucks under it instead of
    -- floating in the black gap below the strip.
    local tx, ty = iconX / 8, 1.5
    self.arrow:draw(0, tx, ty)
    self.arrow:draw(1, tx + 1, ty)
    self.arrow:draw(2, tx, ty + 1)
    self.arrow:draw(3, tx + 1, ty + 1)
  else
    Chrome.cursor(math.floor(iconX / 8), 2)
  end
end

-- ---------------------------------------------------------------- the cards

function Pokegear:drawClock()
  local hour, minute, weekday = self:clockParts()
  self:drawTilemap(self.gfx and self.gfx.cards and self.gfx.cards.clock)
  self:drawStrip()
  self:text("SWITCH", 13, 1)
  Chrome.cursor(19, 1)

  -- Pokegear_UpdateClock: ClearBox(3,5) 5x14, the day at (6,6) and
  -- PrintHoursMins at (6,8) -- two digits, ':', two more, then AM/PM at
  -- column 12.
  self:text(Clock.weekdayName(weekday) or "", 6, 6)
  local display = hour % 12
  if display == 0 then display = 12 end
  self:text(Chrome.number(display, 2), 6, 8)
  self:text(":", 8, 8)
  self:text(Chrome.number(minute, 2, true), 9, 8)
  self:text(hour < 12 and "AM" or "PM", 12, 8)

  -- The bottom Textbox is part of the card (lb bc, 4, 18 at (0,12)), and
  -- PokegearClock_Init prints PokegearPressButtonText straight into it
  -- (engine/pokegear/pokegear.asm PokegearClock_Init), the same way
  -- PokegearPhone_Init fills it with PokegearAskWhoCallText -- the box is the
  -- exit prompt, not spare room.  `line` starts the second row two tile rows
  -- below the first (data/text/common_3.asm _PokegearPressButtonText), which is
  -- why this steps 14 -> 16 rather than printing consecutive rows.
  self:textbox(0, 12, 18, 4)
  self:printBoxText(self:phoneText("PressButton"))
end

-- One of these bottom-box strings, laid out the way PrintText lays a two-line
-- text out: `text` on the box's first interior row and `line` two tile rows
-- under it, which is the same (1,14)/(1,16) pair the port's other Gold text
-- boxes use.  The box only has room for those two rows.
function Pokegear:printBoxText(text)
  local lines = Chrome.wrap(text, 18)
  for i = 1, math.min(#lines, 2) do
    Chrome.print(lines[i], 1, 14 + (i - 1) * 2)
  end
end

-- The Pokegear's paper: BG palette 0's colour 0.  _CGB_PokegearPals copies the
-- six PokegearPals entries straight into wBGPals1 (engine/gfx/cgb_layouts.asm
-- _CGB_PokegearPals), and TownMapPals hands every tile id >= $60 -- the whole
-- font page, so every blank $7f and every glyph cell -- palette 0
-- (engine/pokegear/pokegear.asm TownMapPals).  That first entry is
-- `RGB 28, 31, 20` (gfx/pokegear/pokegear.pal), a pale cream, NOT white: a card
-- painted white underneath its strings is what puts a cream bar behind every
-- run printThrough lays down.
function Pokegear:paperColor()
  local pals = self.gfx and self.gfx.palettes
  return (pals and pals[1] and pals[1][1]) or { 255, 255, 255 }
end

-- The colour the gear's own ground reads as.  InitPokegearTilemap ByteFills
-- SCREEN_AREA with $4f, and $4f is not a blank cell: it is a SOLID tile, every
-- pixel colour index 3, so the fill lands as BG palette 0's LAST colour and
-- the gear sits on black.  Reading colour 0 instead put the screen on the
-- cream plate, which is why the card art appeared as a black box floating on
-- pale green rather than as a lit panel on black.
--
-- Colour 0 is still right for a plate of ' ' cells (Pokegear:drawPlate): a
-- space IS a font-page cell on colour 0, which is the contrast the day/time
-- window and the map's KANTO label are drawn against.
function Pokegear:groundColor()
  local pals = self.gfx and self.gfx.palettes
  local pal = pals and pals[1]
  return (pal and pal[#pal]) or { 0, 0, 0 }
end

-- A run of ' ' cells over the map art.  A space is a font-page cell, so it
-- reads as BG palette 0's colour 0 -- the cream plate -- rather than as
-- whatever town-map tile was underneath.
function Pokegear:drawPlate(tx, ty, tw, th)
  local paper = self:paperColor()
  local G = love.graphics
  G.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
  G.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
  G.setColor(1, 1, 1, 1)
end

-- Textbox on this screen.  Its frame is TextBoxBorder's $79-$7e and its
-- interior is ' ' ($7f), all of them font-page tiles, so the WHOLE box -- the
-- ring as much as the middle -- reads as palette 0's colour 0 here
-- (engine/pokegear/pokegear.asm TownMapPals).  Chrome.textbox cannot be used
-- as-is: Font.drawBox hard-fills its rect white, which is right on every other
-- Gold screen (their BG palette 0 colour 0 IS white) and wrong on the gear, so
-- lay the gear's own paper down and draw only the frame glyphs over it.  b/c in
-- the ASM are interior rows/columns, same as Chrome.textbox.
function Pokegear:textbox(tx, ty, interiorW, interiorH)
  local tw, th = interiorW + 2, interiorH + 2
  self:drawPlate(tx, ty, tw, th)
  local B = Font.BORDER
  local G = love.graphics
  G.setColor(0, 0, 0, 1)
  Font.drawCode(B.tl, tx * 8, ty * 8)
  Font.drawCode(B.tr, (tx + tw - 1) * 8, ty * 8)
  Font.drawCode(B.bl, tx * 8, (ty + th - 1) * 8)
  Font.drawCode(B.br, (tx + tw - 1) * 8, (ty + th - 1) * 8)
  for i = 1, tw - 2 do
    Font.drawCode(B.h, (tx + i) * 8, ty * 8)
    Font.drawCode(B.h, (tx + i) * 8, (ty + th - 1) * 8)
  end
  for j = 1, th - 2 do
    Font.drawCode(B.v, tx * 8, (ty + j) * 8)
    Font.drawCode(B.v, (tx + tw - 1) * 8, (ty + j) * 8)
  end
  G.setColor(0, 0, 0, 1)
end

-- TownMapBubble: the plate the fly screen wears instead of the card strip.
-- Three rows from (1,0) to (18,2), "Where?" at (2,0), the flypoint's landmark
-- name at (2,1) and the up/down scroller at (18,1).  The four rounded corners
-- come from FlyMapLabelBorderGFX, a six-tile 1bpp set loaded over vTiles2 tile
-- $30 for this screen only -- the extractor carries the town map's own $30-$33
-- instead, so the plate is drawn square rather than with the wrong art in its
-- corners.
function Pokegear:drawFlyBubble()
  self:drawPlate(1, 0, 18, 3)
  self:text("Where?", 2, 0)
  local row = self:flyRow()
  self:text(flatName(row and row.name), 2, 1)
  Chrome.cursor(18, 1)
end

function Pokegear:drawMap()
  -- The REGION follows the player (`cp KANTO_LANDMARK` in
  -- PokegearMap_CheckRegion); the name box follows the CURSOR, which the
  -- d-pad may have walked somewhere else entirely.
  local region = self:region()
  local current = self:mapLandmark()
  self:drawTilemap(self.gfx and self.gfx.maps and self.gfx.maps[region])
  local G = love.graphics
  if self.fly then
    self:drawFlyBubble()
  else
    self:drawStrip()
    -- The header's own bottom rule: $07 across (1,2), with $06 and $17 as caps.
    self:tile(0x06, 0, 2)
    for x = 1, 18 do self:tile(0x07, x, 2) end
    self:tile(0x17, 19, 2)

    -- PokegearMap_UpdateLandmarkName: ClearBox(8,0) 2 rows by 12 columns --
    -- with ' ', which is a font-page cell and so reads as BG palette 0's
    -- colour 0, the cream plate, rather than the strip's black $4f -- then
    -- $34, the ▲▼ scroller, at (8,0).  The name itself is placed at (9,0) by
    -- TownMap_ConvertLineBreakCharacters, and the word break it rewrites is
    -- <LF>, which steps one row rather than <NEXT>'s two.
    G.setColor(1, 1, 1, 1)
    self:drawPlate(8, 0, 12, 2)
    self:tile(0x34, 8, 0)
    local name = current and current.name or ""
    local row = 0
    for line in (tostring(name) .. "\n"):gmatch("(.-)\n") do
      if row < 2 then self:text(line, 9, row) end
      row = row + 1
    end
  end

  -- Two OBJs, not one.  PokegearMap_InitPlayerIcon parks RED_WALK on the
  -- PLAYER's landmark and PokegearMap_InitCursor parks the POKEGEAR_ARROW
  -- (sprite tile $04) on the CURSOR's, and only the second one moves.  The
  -- landmark macro stores x + 8 / y + 16, which is OAM space; the extractor
  -- already took the offsets back off, so these coordinates are screen ones.
  local player = self:playerLandmark()
  if player and player.x and player.y then
    if not self:drawPlayerIcon(player.x, player.y) then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", player.x - 2, player.y - 2, 5, 5)
      G.setColor(1, 1, 1, 1)
      G.rectangle("fill", player.x - 1, player.y - 1, 3, 3)
    end
  end
  if current and current.x and current.y then
    self:mapCursorSprite(current.x, current.y)
  end
end

-- ChrisSpriteGFX, the sheet Pokegear_LoadGFX copies into vTiles0 $10 and $14
-- (engine/pokegear/pokegear.asm:135-144).  `false` means no gen2 sprites.
function Pokegear:loadPlayerIcon()
  if self.playerIcon ~= nil then return end
  self.playerIcon = false
  local def = self.sprites and self.sprites.SPRITE_CHRIS
  if not (def and def.image) then return end
  local ok, icon = pcall(SpriteRenderer.new, def, "player")
  if not (ok and icon) then return end
  local world = self.game and self.game.world
  local daytime = (world and world.daytime)
    or Palettes.clockDaytime(self.clock and self.clock.hour or nil)
  local colors = self.palettes
    and Palettes.spritePalette(self.palettes, daytime, def)
  if colors then
    icon:setObjPalette(colors,
      ("gen2:%s:%d"):format(tostring(daytime), def.paletteId or 0))
  end
  self.playerIcon = icon
end

function Pokegear:drawPlayerIcon(x, y)
  self:loadPlayerIcon()
  if not self.playerIcon then return false end
  -- .Frameset_RedWalk beats (data/sprite_anims/framesets.asm:82-85): stand,
  -- walk, stand, walk B_OAM_XFLIP, as FacingStepDown0-3 in facings.asm.
  local beat = math.floor((self.iconTimer or 0) / 8)
  -- .OAMData_RedWalk (data/sprite_anims/oam.asm:314-319) hangs its four tiles
  -- at -8,-8; camY of -4 undoes the world's sprite lift.
  love.graphics.setColor(1, 1, 1, 1)
  self.playerIcon:draw(x - 8, y - 8, 0, -4, "down",
    beat % 2, beat == 3)
  return true
end

-- The cursor arrow.  It is the same PokegearSpritesGFX sheet the mode
-- indicator uses, at tile $04; without the sheet the port falls back to
-- Chrome's own cursor glyph so the card is still navigable.
function Pokegear:mapCursorSprite(x, y)
  self:loadArrowSheet()
  local G = love.graphics
  if self.arrow and self.arrow:available() then
    G.setColor(1, 1, 1, 1)
    -- Tiles $04-$07 are one 16x16 OBJ, and .OAMData_RedWalk (the STILL_CURSOR
    -- oamset, data/sprite_anims/oam.asm:57) centres it on the landmark.
    local tx, ty = (x - 8) / 8, (y - 8) / 8
    self.arrow:draw(0x04, tx, ty)
    self.arrow:draw(0x05, tx + 1, ty)
    self.arrow:draw(0x06, tx, ty + 1)
    self.arrow:draw(0x07, tx + 1, ty + 1)
    return
  end
  Chrome.cursor(math.floor(x / 8), math.floor(y / 8))
end

-- PokegearRadio_Init's tile $08 at `depixel 4, 10, 4, 4`, three rows deep
-- (data/sprite_anims/oam.asm:588), x = knob (pokegear.asm:1355).
function Pokegear:drawTuningKnob()
  self:loadArrowSheet()
  if not (self.arrow and self.arrow:available()) then return end
  local row = self:currentStation()
  local tx = (72 + (row and row.knob or 0)) / 8
  self.arrow:draw(0x08, tx, 1)
  self.arrow:draw(0x08, tx, 2)
  self.arrow:draw(0x08, tx, 3)
end

function Pokegear:drawRadio()
  self:ensureTuned()
  self:drawTilemap(self.gfx and self.gfx.cards and self.gfx.cards.radio)
  self:drawStrip()
  self:drawTuningKnob()
  local station = self:currentStation()
  -- UpdateRadioStation prints the tuned channel's name at (2,9).  Dead air
  -- prints nothing: NoRadioStation clears the box and leaves it clear.
  self:text(station and station.name or "", 2, 9)
  -- The show owns the bottom text box's two lines.  PrintRadioLine fills them
  -- from the top the first time round and CopyBottomLineToTopLine scrolls
  -- afterwards, so `top` is always the line before `bottom`.
  self:textbox(0, 12, 18, 4)
  local radio = self.radio
  if not (station and station.station and radio) then return end
  if radio.top ~= "" then Chrome.print(radio.top, 1, 14) end
  if radio.bottom ~= "" then Chrome.print(radio.bottom, 1, 16) end
end

function Pokegear:drawPhone()
  self:drawTilemap(self.gfx and self.gfx.cards and self.gfx.cards.phone)
  self:drawStrip()
  -- .PlacePhoneBars: the signal meter at (17,1)/(18,1)/(17,2), and the fourth
  -- tile at (18,2) ONLY when GetMapPhoneService comes back zero -- the missing
  -- corner is how the card says "no signal here".
  self:tile(0x3c, 17, 1)
  self:tile(0x3d, 18, 1)
  self:tile(0x3e, 17, 2)
  if Phone.mapHasService(self:phoneContext()) then
    self:tile(0x3f, 18, 2)
  end

  self:textbox(0, 12, 18, 4)
  -- A call in progress replaces the prompt with what the caller is saying;
  -- otherwise the box holds PokegearAskWhoCallText the whole time.
  if self.call then
    Chrome.printWrapped(self.call.text or self:phoneText("GearEllipse"),
      1, 14, 18, 3)
  else
    self:printBoxText(self:phoneText("AskWhoCall"))
  end
  -- PokegearPhone_UpdateDisplayList: every one of the four visible slots is
  -- drawn, empty or not, from (2,4) two rows apart.  GetCallerClassAndName
  -- puts the name (with its trailing colon) on that row and the trainer class
  -- one row down and three columns in; a non-trainer has no second line.
  local list = self:phoneList()
  for row = 1, PHONE_ROWS do
    local id = list[row + self.phoneScroll] or 0
    local ty = 4 + (row - 1) * 2
    local label, className = self:contactRow(id)
    self:text(label, 2, ty)
    if className then self:text(className, 5, ty + 1) end
  end
  -- PokegearPhone_UpdateCursor draws the cursor at (1, 4 + 2 * cursor).
  Chrome.cursor(1, 4 + self.phoneCursor * 2)
  self:drawPhoneSubmenu()
end

-- PokegearPhoneContactSubmenu's box and its entries, laid where the ASM's
-- coordinates put them rather than by eye.
function Pokegear:drawPhoneSubmenu()
  local menu = PHONE_SUBMENUS[self.phoneSubmenu or ""]
  if not menu then return end
  -- `ld a, [de] / sla a` -> b is twice the entry count, and Textbox's b/c are
  -- interior rows/columns, so the box is (rows * 2 + 2) tall and 10 wide.
  self:textbox(menu.x, menu.y, 8, menu.rows * 2)
  for index, label in ipairs(menu.entries) do
    local ty = menu.textY + (index - 1) * 2
    self:text(label, menu.textX, ty)
  end
  Chrome.cursor(menu.textX - 1, menu.textY + self.phoneSubmenuCursor * 2)
end

-- ------------------------------------------------------------------ fallback

function Pokegear:drawPlain()
  Chrome.clear()
  if self.fly then
    -- No town-map art in this cache, so the bubble's "Where?" and the rows it
    -- scrolls between are the whole screen.
    Chrome.box(0, 0, 20, 4)
    Chrome.print("Where?", 2, 1)
    Chrome.box(0, 4, 20, 14)
    local rows = self.fly
    local top = math.max(1, math.min((self.flyIndex or 1) - 3, #rows - 5))
    for slot = 0, 5 do
      local index = top + slot
      local row = rows[index]
      if row then
        local ty = 5 + slot * 2
        if index == (self.flyIndex or 1) then Chrome.cursor(1, ty) end
        Chrome.print(flatName(row.name), 2, ty)
      end
    end
    return
  end
  Chrome.box(0, 0, 20, 4)
  local card = self:card()
  Chrome.print(card and card.label or "", 2, 1)
  if #self.cards > 1 then Chrome.cursor(17, 1) end
  local id = card and card.id
  if id == "clock" then
    local hour, minute, weekday = self:clockParts()
    Chrome.box(1, 5, 18, 7)
    Chrome.print(Clock.weekdayName(weekday) or "DAY", 3, 7)
    local display = hour % 12
    if display == 0 then display = 12 end
    Chrome.print(("%s:%s %s"):format(
      Chrome.number(display, 2), Chrome.number(minute, 2, true),
      hour < 12 and "AM" or "PM"), 5, 9)
    Chrome.print(Clock.daytimeLabel(hour), 5, 11)
  elseif id == "radio" then
    -- Without the gear sheet there is no dial art, so the frequencies go down
    -- the screen as a list.  A frequency whose test failed still gets a row:
    -- the knob really does stop there, it just finds nothing.
    Chrome.box(0, 4, 20, 14)
    for i, row in ipairs(self:stations()) do
      local ty = 5 + (i - 1) * 2
      if ty < 17 then
        if i == self.station then Chrome.cursor(1, ty) end
        Chrome.print(row.frequency .. " " .. (row.name or ""), 2, ty)
      end
    end
  elseif id == "phone" then
    -- No card art, so no signal meter and no tilemap: the list and the call
    -- box are the whole card, at the same coordinates the styled one uses so
    -- the two read the same way.
    Chrome.box(0, 3, 20, 9)
    local list = self:phoneList()
    for row = 1, PHONE_ROWS do
      local ty = 4 + (row - 1) * 2
      local label, className = self:contactRow(list[row + self.phoneScroll] or 0)
      Chrome.print(label, 2, ty)
      if className then Chrome.print(className, 5, ty + 1) end
    end
    Chrome.cursor(1, 4 + self.phoneCursor * 2)
    Chrome.textbox(0, 12, 18, 4)
    Chrome.printWrapped(self.call and (self.call.text or "")
      or self:phoneText("AskWhoCall"), 1, 14, 18, 3)
    self:drawPhoneSubmenu()
  else
    Chrome.box(0, 4, 20, 14)
    Chrome.print("NO CARD DATA", 2, 6)
  end
end

function Pokegear:drawPanel()
  if not self:styled() then
    self:drawPlain()
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local G = love.graphics
  -- InitPokegearTilemap ByteFills the whole SCREEN_AREA with $4f before the
  -- card's tilemap goes down (engine/pokegear/pokegear.asm InitPokegearTilemap),
  -- and every cell the card leaves blank is a font-page tile on palette 0, so
  -- the ground under a card is the gear's paper, not white.  See
  -- Pokegear:paperColor.
  local ground = self:groundColor()
  G.setColor(ground[1] / 255, ground[2] / 255, ground[3] / 255, 1)
  G.rectangle("fill", 0, 0, SCREEN_W * 8, SCREEN_H * 8)
  local id = self:card() and self:card().id
  if id == "map" then
    self:drawMap()
  elseif id == "radio" then
    self:drawRadio()
  elseif id == "phone" then
    self:drawPhone()
  else
    self:drawClock()
  end
  -- Last: the arrow is an OBJ and composites over whatever the card drew.
  self:drawModeArrow()
  G.setColor(1, 1, 1, 1)
end

function Pokegear:draw()
  self:drawPanel()
end

function Pokegear:drawWidescreen(winW, winH)
  local G = love.graphics
  -- The surround takes the gear's own ground, so the panel does not read as a
  -- black card sitting inside a cream frame.  It follows groundColor for the
  -- same reason drawPanel does: $4f is what the screen is filled with.
  local ground = self:groundColor()
  G.setColor(ground[1] / 255, ground[2] / 255, ground[3] / 255, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  local ox, oy = Chrome.fitOrigin(winW, winH, scale)
  G.push()
  G.translate(ox, oy)
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

-- The gate World:openFlyMap reads before it pushes this screen instead of
-- falling back to its yes/no chain.
Pokegear.FLY_MAP = true

Pokegear.CARDS = CARDS
-- Exported for tests and drivers: the dial, the show machine, and the tables
-- the shows read out of.
Pokegear.RADIO_CHANNELS = RADIO_CHANNELS
Pokegear.STATION_NAMES = STATION_NAMES
Pokegear.Radio = Radio
Pokegear.OPT_ADVERBS = OPT_ADVERBS
Pokegear.OPT_ADJECTIVES = OPT_ADJECTIVES
Pokegear.PNP_ADJECTIVES = PNP_ADJECTIVES
Pokegear.ROCKET_LINES = ROCKET_LINES
Pokegear.OPT_ROUTES = OPT_ROUTES
Pokegear.PNP_PLACES = PNP_PLACES

return Pokegear
