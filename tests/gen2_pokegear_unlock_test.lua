-- The Pokegear and Pokedex unlock chain: `setflag` to the START menu and the
-- card strip.
--
--   GOLD_CACHE="$HOME/Library/Application Support/LOVE/gold-dev/gold" \
--     luajit tests/gen2_pokegear_unlock_test.lua
--
-- On the cart every unlock in this family is ONE engine flag
-- (constants/engine_flags.asm const order over data/events/engine_flags.asm):
-- ENGINE_RADIO_CARD 0, ENGINE_MAP_CARD 1, ENGINE_PHONE_CARD 2,
-- ENGINE_EXPN_CARD 3 and ENGINE_POKEGEAR 4 are wPokegearFlags bits, and
-- ENGINE_POKEDEX 11 is wStatusFlags' STATUSFLAGS_POKEDEX_F.  The menus read
-- the same bits the scripts set: start_menu.asm's .SetUpMenuItems bit-tests
-- wStatusFlags and wPokegearFlags, and the Pokegear's card strip is
-- wPokegearFlags again.  So the round trip under test is
--   script `setflag` -> Vm -> World:setEngineFlag -> save.engineFlags ->
--   StartMenu:availability / Pokegear:flags
-- with nothing hand-seeded in between.  The first half runs fixture rows that
-- mirror the granting scripts; the cache-gated half runs the real extracted
-- scripts themselves.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 pokegear unlock")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

-- No font is loaded (logic assertions only), so quiet the per-glyph warns.
require("src.core.Logger").warn = function() end

local Pokegear = require("src.ui.gen2.Pokegear")
local Save = require("src.core.gen2.Save")
local Strings = require("src.core.Strings")
local StartMenu = require("src.ui.gen2.StartMenu")
local Vm = require("src.script.gen2.Vm")
local World = require("src.world.gen2.World")

-- ---- plumbing --------------------------------------------------------------

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

local function newGame(save)
  return {
    input = newInput(),
    save = save,
    options = save and save.options or Save.defaultOptions(),
    data = { audio = {}, pokemon = {}, items = {} },
    stack = { _items = {},
      push = function(self, s) self._items[#self._items + 1] = s end,
      pop = function(self) return table.remove(self._items) end,
      top = function(self) return self._items[#self._items] end,
    },
  }
end

-- A real World:setEngineFlag / World:engineFlag over a real save, without the
-- rest of the world: the same slice gen2_badges_test.lua drives.
local function newWorld(save)
  return setmetatable({ game = { save = save } }, { __index = World })
end

-- wEventFlags for the Vm: setevent / checkevent land here.
local function newEvents()
  return { flags = {},
    set = function(self, id, v) self.flags[id] = v or nil end,
    get = function(self, id) return self.flags[id] == true end,
  }
end

-- Run a script list to completion, spending pause/showemote waits.  yesorno
-- answers come from `answers` in order and default to YES past the end: the
-- confirm loops (Mom's clock wheel re-asks until the player agrees) terminate
-- on YES, so an unscripted question is confirmed rather than looping forever.
local function runScript(scripts, key, world, opts)
  opts = opts or {}
  local answers = opts.answers or {}
  local asked = 0
  local vm = Vm.new(scripts, opts.text or {}, opts.events or newEvents(), {
    setEngineFlag = function(flag, v) world:setEngineFlag(flag, v) end,
    getEngineFlag = function(flag) return world:engineFlag(flag) end,
    yesorno = function(done)
      asked = asked + 1
      local answer = answers[asked]
      if answer == nil then answer = true end
      done(answer == true)
    end,
    specialOrder = opts.specialOrder,
    -- The world half of the special handlers, as ONE sub-table: pushScreen
    -- rides here, the same seam World:specialHooks fills.
    specials = opts.specials,
  })
  check(vm:start(key), "script " .. tostring(key) .. " started")
  for _ = 1, 5000 do
    if not vm:running() then break end
    vm:update()
  end
  eq(vm:running(), false, "script " .. tostring(key) .. " ran to completion")
  return vm, asked
end

local function menuIds(menu)
  local out = {}
  for _, item in ipairs(menu.items) do out[#out + 1] = item.value end
  return table.concat(out, ",")
end

local function cardIds(gear)
  local out = {}
  for _, card in ipairs(gear.cards) do out[#out + 1] = card.id end
  return table.concat(out, ",")
end

-- ---- the locked state ------------------------------------------------------

do
  local save = Save.newGame()
  save.party = { { species = "CYNDAQUIL" } }
  local menu = StartMenu.new(newGame(save), { save = save })
  eq(menuIds(menu), "pokemon,pack,status,save,option,quit",
    "no engine flags: no POKeDEX and no POKeGEAR row")
  local gear = Pokegear.new(newGame(save), { save = save })
  eq(cardIds(gear), "clock", "and the gear alone is just the clock card")
end

-- ---- fixture rows: the same setflag ids the granting scripts carry ---------

-- Mom (maps/PlayersHouse1F.asm): `setflag ENGINE_POKEGEAR` then
-- `setflag ENGINE_PHONE_CARD` on the way out the door.
do
  local save = Save.newGame()
  save.party = { { species = "CYNDAQUIL" } }
  local world = newWorld(save)
  runScript({ mom = {
    { op = "setflag", flag = 4 },
    { op = "setflag", flag = 2 },
    { op = "end" },
  } }, "mom", world)
  eq(save.engineFlags[4], true, "ENGINE_POKEGEAR landed in save.engineFlags")
  local menu = StartMenu.new(newGame(save), { save = save })
  eq(menuIds(menu), "pokemon,pack,pokegear,status,save,option,quit",
    "the POKeGEAR row unlocks from the flag alone")
  local gear = Pokegear.new(newGame(save), { save = save })
  eq(cardIds(gear), "clock,phone", "and the PHONE card is on the strip")
end

-- Oak (maps/MrPokemonsHouse.asm): `setflag ENGINE_POKEDEX`.
do
  local save = Save.newGame()
  save.party = { { species = "CYNDAQUIL" } }
  local world = newWorld(save)
  runScript({ oak = {
    { op = "setflag", flag = 11 },
    { op = "end" },
  } }, "oak", world)
  local menu = StartMenu.new(newGame(save), { save = save })
  eq(menuIds(menu), "pokedex,pokemon,pack,status,save,option,quit",
    "ENGINE_POKEDEX puts POKeDEX at the top of the menu")
end

-- The Guide Gent (maps/CherrygroveCity.asm `setflag ENGINE_MAP_CARD`), the
-- Radio Tower quiz lady (maps/RadioTower1F.asm `setflag ENGINE_RADIO_CARD`)
-- and the Lavender tower director (maps/LavRadioTower1F.asm
-- `setflag ENGINE_EXPN_CARD`).
do
  local save = Save.newGame()
  local world = newWorld(save)
  runScript({ cards = {
    { op = "setflag", flag = 1 },
    { op = "setflag", flag = 0 },
    { op = "setflag", flag = 3 },
    { op = "end" },
  } }, "cards", world)
  local gear = Pokegear.new(newGame(save), { save = save })
  eq(cardIds(gear), "clock,map,radio",
    "MAP and RADIO cards unlock; PHONE stays locked without flag 2")
  -- POKEGEAR_EXPN_CARD_F is not a card of its own -- it is the Kanto radio
  -- upgrade the Poke Flute channel checks.
  eq(gear:radioContext().expnCard, true, "EXPN reaches the radio context")
end

-- With every card granted the strip has to read in POKEGEARCARD_* order
-- (constants/pokegear_constants.asm: CLOCK 0, MAP 1, PHONE 2, RADIO 3).  The
-- order is what paging walks, and AnimatePokegearModeIndicatorArrow indexes its
-- $00/$10/$20/$30 x offsets by wPokegearCard, so a strip out of card order
-- makes the mode arrow skip an icon and then jump backwards.
do
  local save = Save.newGame()
  local world = newWorld(save)
  runScript({ cards = {
    { op = "setflag", flag = 0 },
    { op = "setflag", flag = 1 },
    { op = "setflag", flag = 2 },
    { op = "end" },
  } }, "cards", world)
  local gear = Pokegear.new(newGame(save), { save = save })
  eq(cardIds(gear), "clock,map,phone,radio", "the strip is in card order")
  local columns = {}
  for _, card in ipairs(gear.cards) do
    columns[#columns + 1] = tostring(card.iconX)
  end
  eq(table.concat(columns, ","), "0,2,4,6",
    "and paging steps the arrow left to right, one icon at a time")
end

-- The overlay stays: a test or driver may still seed save.pokegearFlags and
-- the older proxy fields directly.
do
  local save = Save.newGame()
  save.pokegearFlags = { phone = true }
  save.pokedexReceived = true
  save.pokegearReceived = true
  save.party = { { species = "TOTODILE" } }
  local gear = Pokegear.new(newGame(save), { save = save })
  eq(cardIds(gear), "clock,phone", "seeded pokegearFlags still read")
  local menu = StartMenu.new(newGame(save), { save = save })
  eq(menuIds(menu), "pokedex,pokemon,pack,pokegear,status,save,option,quit",
    "and the proxy fields still unlock the menu rows")
end

-- ---- the EXPN gate and the two landmark stations ---------------------------

-- RadioChannels (engine/pokegear/pokegear.asm): knob 78 (20.0) is the Poke
-- Flute channel, Kanto plus EXPN only; knob 52 (13.5) resolves ????? only at
-- the Ruins of Alph.  Both were unreachable while the flags never arrived.
local LANDMARKS = { landmarks = {
  LANDMARK_NEW_BARK_TOWN = { index = 2 },
  LANDMARK_RUINS_OF_ALPH = { index = 10 },
  LANDMARK_VERMILION_CITY = { index = 50 },
} }

local function stationAt(save, landmark, knob)
  local gear = Pokegear.new(newGame(save), {
    save = save, landmarks = LANDMARKS, currentLandmark = landmark,
  })
  for _, row in ipairs(gear:stations()) do
    if row.knob == knob then return row end
  end
  return nil
end

do
  local save = Save.newGame()
  local world = newWorld(save)
  world:setEngineFlag(0, true)
  local locked = stationAt(save, "LANDMARK_VERMILION_CITY", 78)
  eq(locked and locked.station, nil, "20.0 is dead air without the EXPN flag")
  world:setEngineFlag(3, true)
  local flute = stationAt(save, "LANDMARK_VERMILION_CITY", 78)
  eq(flute and flute.station, "POKE_FLUTE_RADIO",
    "ENGINE_EXPN_CARD opens the Poke Flute channel in Kanto")
  eq(flute and flute.name, "POKé FLUTE", "with its own station name")
  local ruins = stationAt(save, "LANDMARK_RUINS_OF_ALPH", 52)
  eq(ruins and ruins.station, "UNOWN_RADIO",
    "and 13.5 resolves the ????? station at the Ruins of Alph")
  local away = stationAt(save, "LANDMARK_NEW_BARK_TOWN", 52)
  eq(away and away.station, nil, "which is dead air anywhere else")
end

-- Station presentation is the radio_channels registry's concern; the show id
-- and dial mechanics stay unchanged.  Fixed show prose resolves through the
-- strings catalog only when the machine prints it.
do
  local save = Save.newGame()
  local world = newWorld(save)
  world:setEngineFlag(3, true)
  local game = newGame(save)
  game.data.gen2RadioChannels = {
    POKE_FLUTE_RADIO = { channel = 7, name = "FLÛTE RADIO" },
  }
  local gear = Pokegear.new(game, { save = save, landmarks = LANDMARKS,
    currentLandmark = "LANDMARK_VERMILION_CITY" })
  eq(gear:stations()[7].name, "FLÛTE RADIO",
    "the Pokegear consumes a registry-patched station name")

  Strings.load({ strings = {
    ["MARY: PROF.OAK'S"] = "MARIE : PROF.CHEN",
    -- Registry-authored display values are complete content, not source keys.
    ["FLÛTE RADIO"] = "THIS MUST NOT BE USED",
  } })
  eq(gear:stations()[7].name, "FLÛTE RADIO",
    "a mod-authored station name is not translated a second time")

  Strings.load({ strings = {
    CLOCK = "HORLOGE", MAP = "CARTE", PHONE = "TÉLÉPHONE",
    RADIO = "RADIO FR", FLY = "VOL", AM = "MATIN", PM = "SOIR",
    ["Whom do you want to call?"] = "Qui voulez-vous appeler ?",
  } })
  eq(gear:cardLabel(Pokegear.CARDS[1]), "HORLOGE", "CLOCK is localizable")
  eq(gear:cardLabel(Pokegear.CARDS[2]), "CARTE", "MAP is localizable")
  eq(gear:cardLabel(Pokegear.CARDS[3]), "TÉLÉPHONE", "PHONE is localizable")
  eq(gear:cardLabel(Pokegear.CARDS[4]), "RADIO FR", "RADIO is localizable")
  local flyGear = Pokegear.new(game, {
    save = save, landmarks = LANDMARKS,
    currentLandmark = "LANDMARK_VERMILION_CITY",
    fly = { { name = "VERMILION", landmark = "LANDMARK_VERMILION_CITY" } },
  })
  eq(flyGear:cardLabel(), "VOL", "FLY is localizable")
  eq(gear:phoneText("AskWhoCall"), "Qui voulez-vous appeler ?",
    "the complete built-in phone prompt is localizable")

  Strings.load({ strings = {
    ["MARY: PROF.OAK'S"] = "MARIE : PROF.CHEN",
  } })
  local radio = Pokegear.Radio.new()
  radio:tune("OAKS_POKEMON_TALK")
  radio:step()
  eq(radio.top, "MARIE : PROF.CHEN",
    "radio show prose resolves through the strings catalog")
  Strings.load(nil)
end

-- ---- ExitPokegearRadio_HandleMusic -----------------------------------------

-- RadioMusicRestartDE writes the tuned song into wMapMusic, so closing the
-- gear on a station leaves the song playing AS the map music; NoRadioStation's
-- ENTER_MAP_MUSIC brings the map theme back instead.
local Music = require("src.core.Music")

do
  local save = Save.newGame()
  local world = newWorld(save)
  world:setEngineFlag(0, true)
  world:setEngineFlag(3, true)
  local game = newGame(save)
  game.world = { map = { def = { music = "Music_VermilionCity" } } }
  local gear = Pokegear.new(game, {
    save = save, landmarks = LANDMARKS,
    currentLandmark = "LANDMARK_VERMILION_CITY",
  })
  gear.tuningKnob = 78
  gear:tuneRadio()
  eq(gear.radioShow, "POKE_FLUTE_RADIO", "the tuner resolved the channel")
  gear:tickRadio()
  eq(gear.radioSong, "Music_PokeFluteChannel", "the station started its song")
  eq(gear.radioMusicPlaying, "Music_PokeFluteChannel",
    "and parked it in wPokegearRadioMusicPlaying")
  Music.setMapSong("Music_VermilionCity")
  gear:stopRadio()
  eq(Music.mapSong(), "Music_PokeFluteChannel",
    "closing the radio makes the tuned song the map music (wMapMusic)")
  eq(gear.radioMusicPlaying, nil, "and zeroes the handoff byte")

  -- Dead air: knob 16 asks for Johto, and this gear is in Kanto.
  Music.setMapSong("Music_VermilionCity")
  gear.tuningKnob = 16
  gear:tuneRadio()
  eq(gear.radioShow, nil, "04.5 is dead air in Kanto")
  eq(gear.radioMusicPlaying, "enterMap", "NoRadioStation parks ENTER_MAP_MUSIC")
  gear:stopRadio()
  eq(Music.mapSong(), "Music_VermilionCity",
    "and closing on dead air leaves the map song alone")
end

-- The Pokemon Channel jingle is the one RESTART_MAP_MUSIC writer.
eq(Pokegear.radioPlayingValue("Music_PokemonChannel"), "restartMap",
  "RadioMusicRestartPokemonChannel restores the map theme on exit")
eq(Pokegear.radioPlayingValue("Music_PokeFluteChannel"),
  "Music_PokeFluteChannel", "RadioMusicRestartDE hands the song itself over")

-- ---- the cache half: the real granting scripts -----------------------------

local cacheDir = os.getenv("GOLD_CACHE")
if not cacheDir then
  cacheDir = (os.getenv("HOME") or "") ..
    "/Library/Application Support/LOVE/gold-dev/gold"
end
local scriptsFile = loadfile(cacheDir .. "/data/generated/scripts.lua")
if not scriptsFile then
  check(true, "cache absent (SKIP)")
  S.finish()
  return
end
local scripts = scriptsFile()
local constants = assert(
  loadfile(cacheDir .. "/data/generated/constants.lua"))()

-- Mom's send-off (maps/PlayersHouse1F.asm): flags 4 and 2 in one script.
do
  local save = Save.newGame()
  save.party = { { species = "CYNDAQUIL" } }
  local world = newWorld(save)
  runScript(scripts, "60:564f", world)
  eq(save.engineFlags[4], true, "Mom set ENGINE_POKEGEAR")
  eq(save.engineFlags[2], true, "and ENGINE_PHONE_CARD")
  local menu = StartMenu.new(newGame(save), { save = save })
  check(menuIds(menu):find("pokegear", 1, true) ~= nil,
    "so the real script unlocks the POKeGEAR row")
  eq(cardIds(Pokegear.new(newGame(save), { save = save })), "clock,phone",
    "and the PHONE card")
end

-- Oak's dex handover (maps/MrPokemonsHouse.asm): flag 11.
do
  local save = Save.newGame()
  save.party = { { species = "CYNDAQUIL" } }
  local world = newWorld(save)
  runScript(scripts, "62:46c1", world)
  eq(save.engineFlags[11], true, "Oak set ENGINE_POKEDEX")
  local menu = StartMenu.new(newGame(save), { save = save })
  eq(menu.items[1] and menu.items[1].value, "pokedex",
    "so the real script puts POKeDEX first")
end

-- The Guide Gent's tour (maps/CherrygroveCity.asm): flag 1.
do
  local save = Save.newGame()
  local world = newWorld(save)
  runScript(scripts, "48:43ea", world)
  eq(save.engineFlags[1], true, "the Guide Gent set ENGINE_MAP_CARD")
  eq(cardIds(Pokegear.new(newGame(save), { save = save })), "clock,map",
    "so the real script unlocks the MAP card")
end

-- The Radio Tower quiz (maps/RadioTower1F.asm): five questions whose right
-- answers are YES/YES/NO/YES/NO, after a YES to sit the quiz at all.
do
  local save = Save.newGame()
  local world = newWorld(save)
  local _, asked = runScript(scripts, "43:4d7d", world, {
    answers = { true, true, true, false, true, false },
  })
  eq(asked, 6, "the quiz asked its six questions")
  eq(save.engineFlags[0], true, "a perfect run set ENGINE_RADIO_CARD")
  eq(cardIds(Pokegear.new(newGame(save), { save = save })), "clock,radio",
    "so the real quiz unlocks the RADIO card")

  -- One wrong answer and the card is withheld.
  local save2 = Save.newGame()
  runScript(scripts, "43:4d7d", newWorld(save2), {
    answers = { true, true, true, true },
  })
  eq(save2.engineFlags[0], nil, "a wrong answer grants nothing")
end

-- The Lavender tower director (maps/LavRadioTower1F.asm): flag 3.
do
  local save = Save.newGame()
  local world = newWorld(save)
  runScript(scripts, "5d:47b3", world)
  eq(save.engineFlags[3], true, "the director set ENGINE_EXPN_CARD")
  local gear = Pokegear.new(newGame(save), {
    save = save, landmarks = LANDMARKS,
    currentLandmark = "LANDMARK_VERMILION_CITY",
  })
  eq(gear:radioContext().expnCard, true,
    "so the real script arms the Poke Flute channel gate")
end

-- ---- the wall radios reach the new special ---------------------------------

-- std_scripts.asm Radio1Script is `setval MAPRADIO_POKEMON_CHANNEL` +
-- `special MapRadio`; the id must resolve to a HANDLER now, not a stub.
do
  local Specials = require("src.script.gen2.Specials")
  eq(constants.specialOrder[41], "MapRadio", "special id 40 is MapRadio")
  check(Specials.HANDLERS.MapRadio ~= nil, "MapRadio is implemented")
  eq(Specials.STUB_REASONS.MapRadio, nil, "and no longer a stub")

  local save = Save.newGame()
  local world = newWorld(save)
  local pushed = nil
  local vm = Vm.new(scripts, {}, newEvents(), {
    setEngineFlag = function(flag, v) world:setEngineFlag(flag, v) end,
    getEngineFlag = function(flag) return world:engineFlag(flag) end,
    specialOrder = constants.specialOrder,
    specials = {
      pushScreen = function(id, opts)
        pushed = { id = id, opts = opts }
        -- A pushed screen answers later; here the "screen" closes at once.
        if opts and opts.onDone then opts.onDone() end
        return true
      end,
    },
  })
  check(vm:start("40:4132"), "Radio1Script's body started")
  for _ = 1, 200 do
    if not vm:running() then break end
    vm:update()
  end
  eq(vm:running(), false, "and ran through the special to its end")
  eq(pushed and pushed.id, "Gen2MapRadio",
    "special 40 pushed the wall-radio screen")
  eq(pushed and pushed.opts and pushed.opts.channel, 0,
    "with setval's MAPRADIO_POKEMON_CHANNEL")

  -- Radio2Script (the Lucky Channel houses): channel 4.
  pushed = nil
  check(vm:start("40:413a"), "Radio2Script's body started")
  for _ = 1, 200 do
    if not vm:running() then break end
    vm:update()
  end
  eq(pushed and pushed.opts and pushed.opts.channel, 4,
    "Radio2Script tunes MAPRADIO_LUCKY_CHANNEL")
end

S.finish()
