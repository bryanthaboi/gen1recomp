-- pokecrystal/engine/pokegear/radio.asm:1425
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness").suite("Crystal Buena radio #2639")
local EngineFlagsFixture = require("tests.fixture_data.gen2_engine_flags")
EngineFlagsFixture.bind("crystal")
local Gear = require("src.ui.gen2.Pokegear")
local Buena = require("src.core.gen2.Buena")
local MapRadio = require("src.ui.gen2.MapRadio")
local Music = require("src.core.Music")
local World = require("src.world.gen2.World")
local Specials = require("src.script.gen2.Specials")
local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")
local Apricorns = require("src.core.gen2.Apricorns")
local Fixture = require("tests.fixtures.gen2_buena")
local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}; for k, x in pairs(v) do out[k] = copy(x) end; return out
end
local originalPlay, originalStop = Music.play, Music.stop
local played, stopped = {}, 0
Music.play = function(_, song) played[#played + 1] = song end
Music.stop = function() stopped = stopped + 1 end
local function gear(version, hour, landmark, save, rng, data)
  save = save or { version = version, pokegearFlags = { radio = true }, engineFlags = {} }
  data = data or copy(Fixture)
  for k, v in pairs(require("tests.fixture_data.gen2_rom_text_s7_d").text(nil, version)) do
    if data.text[k] == nil then data.text[k] = v end
  end
  if version ~= "crystal" then data.gen2EventTables = {} end
  local game = { save = save, data = data }
  local g = Gear.new(game, { clock = { hour = hour, weekday = 2 },
    landmarks = require("tests.fixture_data.gen2_landmarks_s7_d").anchored(
      { landmarks = { HERE = { index = landmark or 1 } } }, version),
    currentLandmark = "HERE", radioRng = rng or function() return 0 end })
  g.tuningKnob = 40; g:tuneRadio()
  return g, save, data
end
local function reach(g, segment)
  for _ = 1, 5000 do
    if g.radio.cur == segment then return end
    g:tickRadio()
  end
  error("unreached Buena segment " .. segment)
end
local function segment(g, name)
  g.radio.cur = name; g:tickRadio()
end
for _, hour in ipairs({ 18, 21, 23 }) do
  local g, save = gear("crystal", hour)
  T.eq(g:currentStation().station, "BUENAS_PASSWORD", "10.5 station at " .. hour)
  T.eq(g:currentStation().name, "BUENA'S PASSWORD", "ROM station name")
  T.eq(#g:stations(), 9, "Crystal has the source ninth dial row")
  T.eq(g.radio.stationName, "", "initial source station-name blank")
  for _ = 1, 410 do g:tickRadio() end
  T.eq(g.radioSong, "Music_BuenasPassword", "existing ROM music at " .. hour)
  T.eq(g.radio.stationName, "BUENA'S PASSWORD", "show writes ROM station name")
  T.same({ unpack(g.radio.log, 1, 4) }, {
    "BUENA: BUENA here!", "Today's password!", "Let me think… It's", "CYNDAQUIL!",
  }, "four actual timed intro/password lines")
  T.eq(save.crystal.buenaPassword.word, 0, "group-zero choice-zero packed word")
  T.check(save.engineFlags[95], "broadcast sets listened only at password segment")
  T.eq(save.crystal.buenaPassword.balance, nil, "radio awards no points")
end
for _, version in ipairs({ "gold", "silver" }) do
  local g = gear(version, 21)
  T.eq(#g:stations(), 8, version .. " source dial count retained")
  T.eq(g:currentStation().station, nil, version .. " has no Buena signal")
  T.eq(g.radio, nil, version .. " has no Buena show")
  g.tuningKnob = 16; g:tuneRadio(); g:tickRadio()
  T.eq(g.radioSong, "Music_ProfOaksPokemonTalk", version .. " ordinary station control")
end
local crystalLandmarks = require("tests.fixture_data.gen2_landmarks_s7_d").table("crystal").landmarks
T.eq(gear("crystal", 21, crystalLandmarks.LANDMARK_PALLET_TOWN.index):currentStation().station,
  nil, "Kanto has no Buena signal")
T.eq(gear("crystal", 21, crystalLandmarks.LANDMARK_FAST_SHIP.index):currentStation().station,
  "BUENAS_PASSWORD", "Fast Ship has Buena")
do
  local save = { version = "crystal", engineFlags = { [95] = true, [96] = true },
    crystal = { buenaPassword = { word = 0x52, day = 57, balance = 17 } } }
  local calls = 0
  local g, _, data = gear("crystal", 21, nil, save, function() calls = calls + 1; return 0 end)
  for _ = 1, 1500 do g:tickRadio() end
  T.eq(calls, 0, "valid imported listened word survives host-day mismatch and show loops")
  T.eq(save.crystal.buenaPassword.word, 0x52, "imported packed word preserved")
  T.eq(save.crystal.buenaPassword.day, 57, "imported listened day preserved")
  T.check(g.radio.log[4] == "DROWZEE!", "broadcast resolves imported category/word")
  g:tuneRadio(); for _ = 1, 410 do g:tickRadio() end
  T.eq(calls, 0, "retuning never rerolls valid listening state")
  local world = World.new({ save = save, data = data })
  local vm = Vm.new({}, {}, Events.new(), { specials = {
    save = function() return save end, data = function() return data end,
    pushScreen = function(_, opts)
      T.same(opts.words, { "HOOTHOOT", "SPINARAK", "DROWZEE" }, "NPC shares ROM-fed category")
      T.eq(opts.width, 10, "NPC reads ROM width")
      opts.onDone(2); return true
    end,
  }, readVar = function(id) return world:readVar(id) end,
  writeVar = function(id, v) world:writeVar(id, v) end })
  local oldRandom = Specials.random
  Specials.random = function() error("NPC generated a password") end
  local co = coroutine.create(function() Specials.HANDLERS.BuenasPassword(vm) end); vm.co = co
  local ok, err = coroutine.resume(co); assert(ok, err); Specials.random = oldRandom
  T.eq(vm.scriptVar, 1, "actual NPC accepts captured third choice")
  T.eq(save.crystal.buenaPassword.balance, 17, "menu preserves points")
  g.clock.hour = 0
  reach(g, "BUENAS_PASSWORD_7"); g:tickRadio()
  T.eq(g.radio.log[#g.radio.log], "RADIO TOWER!", "midnight segment7 prints pending source line")
  T.eq(g.radio.next, "BUENAS_PASSWORD_8", "midnight segment7 enters outro")
  T.eq(save.engineFlags[95], nil, "midnight clears listened flag")
  T.eq(save.crystal.buenaPassword.day, nil, "midnight clears export day projection")
  T.check(save.engineFlags[96], "midnight preserves separate played flag")
  local start = #g.radio.log
  reach(g, "BUENAS_PASSWORD_21")
  local actual = { unpack(g.radio.log, start + 1) }
  T.same(actual, { "…", "BUENA: Oh my…", "It's midnight! I", "have to shut down!",
    "Thanks for tuning", "in to the end! But", "don't stay up too", "late! Presented to",
    "you by DJ BUENA!", "I'm outta here!", "…", "…", "" }, "all source midnight/outro segments")
  T.eq(g.radioSong, false, "off-air clears song")
  T.eq(g.radio.stationName, "", "off-air clears station name")
  T.eq(g.radioMusicPlaying, "enterMap", "off-air retains source exit-map behavior")
  local stopCount = stopped
  for _ = 1, 500 do g:tickRadio() end
  T.eq(stopped, stopCount, "off-air music stop happens once")
  T.eq(calls, 0, "off-air polling never generates passwords")
  Apricorns.dailyReset(save)
  T.eq(save.engineFlags[96], nil, "daily reset clears played separately")
  T.eq(save.crystal.buenaPassword.word, 0x52, "daily reset preserves stored packed word")
  T.eq(save.crystal.buenaPassword.balance, 17, "daily reset preserves points")
  g.clock.hour = 18; reach(g, "BUENAS_PASSWORD_4"); g:tickRadio()
  T.eq(calls, 2, "off-air polling starts next broadcast without retuning")
  T.eq(save.crystal.buenaPassword.word, 0, "new broadcast writes newly generated word")
  T.check(save.engineFlags[95], "new broadcast sets listening flag again")
end
for _, pending in ipairs({ 3, 4 }) do
  local g, save = gear("crystal", 23)
  reach(g, "BUENAS_PASSWORD_" .. pending)
  g.clock.hour = 0; g:tickRadio()
  T.eq(g.radio.next, pending == 3 and "BUENAS_PASSWORD_8" or "BUENAS_PASSWORD_9",
    "midnight source checkpoint " .. pending)
  T.eq(save.crystal, nil, "midnight intro never generates a word")
end
do
  local s = { version = "crystal", engineFlags = {},
    crystal = { buenaPassword = { word = 0, day = 0, balance = 17 } } }
  local g = gear("crystal", 21, nil, s, function() error("zero imported word rerolled") end)
  for _ = 1, 410 do g:tickRadio() end
  T.eq(s.crystal.buenaPassword.word, 0, "imported word zero is valid")
  T.eq(s.crystal.buenaPassword.day, 0, "imported day zero is valid")
  T.check(s.engineFlags[95], "decoded day-only listening state promotes canonical engine flag")
  s.engineFlags[95] = false
  g.radioRng = function() return 1 end
  g:tuneRadio(); for _ = 1, 410 do g:tickRadio() end
  T.eq(s.crystal.buenaPassword.word, 0x11, "explicit cleared engine flag overrides stale day")
  T.eq(s.crystal.buenaPassword.balance, 17, "broadcast regeneration preserves points")
  Buena.clearListening(s, Fixture)
  s.crystal.buenaPassword.word = 0x53
  T.eq(Buena.captured(s, Fixture), nil, "invalid captured low nibble is rejected")
  s.crystal.buenaPassword.word = 0xb0
  T.eq(Buena.captured(s, Fixture), nil, "invalid captured category is rejected")
end
do
  local g, save = gear("crystal", 17)
  g:tickRadio()
  T.eq(g.radio.next, "BUENAS_PASSWORD_21", "initial off-air skips outro")
  T.eq(g.radioSong, false, "initial off-air stops music")
  T.eq(save.crystal, nil, "initial off-air does not create a password")
  g.clock.hour = 18; reach(g, "BUENAS_PASSWORD_4"); g:tickRadio()
  T.check(save.engineFlags[95], "hour changes dynamically inside cached radioData")
end
do
  local rolls, count = { 15, 11, 10, 3, 2 }, 0
  local g, save = gear("crystal", 21, nil, nil, function() count = count + 1; return rolls[count] end)
  reach(g, "BUENAS_PASSWORD_4"); g:tickRadio()
  T.eq(count, 5, "source rejects category11/15 and option3")
  T.eq(save.crystal.buenaPassword.word, 0xa2, "source high/low nibble packing")
  T.eq(g.radio.log[4], "Lucky Channel!", "raw ROM string category resolves")
  local stuck, state = gear("crystal", 21, nil, nil, function() return 255 end)
  reach(stuck, "BUENAS_PASSWORD_4"); stuck:tickRadio()
  T.eq(stuck.radio.cur, "BUENAS_PASSWORD_4", "bounded RNG exhaustion retries segment")
  T.eq(state.crystal, nil, "RNG exhaustion does not commit a partial password")
  T.eq(state.engineFlags[95], nil, "RNG exhaustion leaves listening clear")
end
do
  local data = copy(Fixture); data.gen2EventTables.buenaPassword.stationName = "ROM STATION"
  data.gen2EventTables.buenaPassword.categories[1].words[1] = "OTHER_MON"
  data.pokemon = { OTHER_MON = { name = "ROM MON" } }
  data.text._BuenaRadioText1 = "\nROM INTRO{DONE}"
  local g = gear("crystal", 21, nil, nil, nil, data)
  for _ = 1, 410 do g:tickRadio() end
  T.eq(g.radio.stationName, "ROM STATION", "station consumes extracted name")
  T.eq(g.radio.log[1], "ROM INTRO", "show consumes extracted text")
  T.eq(g.radio.log[4], "ROM MON!", "shared resolver consumes extracted IDs and display names")
  local printed
  g.styled = function() return false end
  for index, card in ipairs(g.cards) do if card.id == "radio" then g.cardIndex = index end end
  T.check(not pcall(g.draw, g), "a cache without pokegear art is an error")
  segment(g, "BUENAS_PASSWORD_20")
  g.text = function(_, body, x, y) if x == 2 and y == 9 then printed = body end end
  g.drawTilemap, g.drawStrip, g.drawTuningKnob, g.textbox = function() end, function() end,
    function() end, function() end
  g:drawRadio()
  T.eq(printed, "", "styled radio clears off-air name")
  segment(g, "BUENAS_PASSWORD"); g:drawRadio()
  T.eq(printed, "ROM STATION", "styled radio displays imported on-air name")
  local rows = {}; local registry = { register = function(_, id, row) rows[id] = row end }
  T.eq(MapRadio.registerInto(registry, data), 11, "Crystal adds one Pokegear-only registry station")
  T.eq(rows.BUENAS_PASSWORD.name, "ROM STATION", "registry uses ROM station name")
  T.eq(rows.BUENAS_PASSWORD.channel, nil, "Buena adds no wall-radio index")
  rows = {}; T.eq(MapRadio.registerInto(registry, {}), 10, "Gold/Silver registry counts unchanged")
  T.eq(rows.BUENAS_PASSWORD, nil, "Gold/Silver registry has no Buena")
  local missing = copy(data); missing.gen2EventTables = {}
  T.eq(Buena.broadcast({ version = "crystal" }, missing, function() error("no data") end), nil,
    "missing metadata has no handwritten fallback")
end
do
  local g = gear("crystal", 21)
  g.radio.data.rocketsInRadioTower = true; g:tickRadio()
  T.eq(g.radio.music, "Music_RocketTheme", "Crystal Buena obeys source Rocket takeover")
  T.eq(g.radio.cur, "RADIO_SCROLL", "Rocket show runs actual segment")
  local s = { version = "silver", engineFlags = { [95] = true, [96] = true },
    crystal = { buenaPassword = { word = 0x52, day = 57, balance = 17 } } }
  EngineFlagsFixture.bind("gold")
  Apricorns.dailyReset(s)
  T.check(s.engineFlags[95] and s.engineFlags[96], "narrow Buena reset does not clear Gold/Silver flags")
  T.eq(s.crystal.buenaPassword.day, 57, "Gold/Silver unrelated state untouched")
  EngineFlagsFixture.bind("crystal")
  local reset = { version = "crystal", engineFlags = { [95] = true, [96] = true },
    crystal = { buenaPassword = { word = 0x52, day = 57, balance = 17 } } }
  Buena.dailyReset(reset)
  T.eq(reset.engineFlags[96], nil, "reset clears Crystal's ENGINE_BUENAS_PASSWORD_2")
  T.eq(reset.engineFlags[95], nil, "and ENGINE_BUENAS_PASSWORD")
  T.eq(reset.crystal.buenaPassword.day, nil, "reset clears listening day")
end
Music.play, Music.stop = originalPlay, originalStop
do
  local Sdk = require("tests.modkit.sdk")
  local Runtime = require("src.mods.Runtime")
  local run = Sdk.loadMods({ "mods/buena_callback_probe" }, {
    generation = 1, data = {}, fs = Sdk.memfs({
      ["mods/buena_callback_probe/manifest.json"] =
        '{"id":"buena_callback_probe","name":"buena_callback_probe","version":"1.0.0","entry":"main.lua","api":2,"games":["all"]}',
      ["mods/buena_callback_probe/main.lua"] = 'local mod=...;mod.exports.loaded=true',
    }),
  })
  T.eq(#run.errors, 0, "Gen1 mod context loads without errors")
  Runtime.currentMod = "buena_callback_probe"
  local rows = {}
  local registry = { register = function(_, id, row) rows[id] = row end }
  local ok, count = pcall(MapRadio.registerInto, registry, Fixture)
  T.check(ok, "engine-owned radio callback needs no late Gen2 require: " .. tostring(count))
  T.eq(ok and count, 11, "Crystal metadata registry remains complete under mod context")
  rows = {}
  local goldOk, goldCount = pcall(MapRadio.registerInto, registry, {})
  T.check(goldOk, "Gold registry callback works under Gen1 mod context")
  T.eq(goldOk and goldCount, 10, "Gold registry count remains unchanged")
  T.eq(rows.BUENAS_PASSWORD, nil, "Gold registry keeps Buena absent")
  local s = { version = "crystal", engineFlags = { [95] = true, [96] = true },
    crystal = { buenaPassword = { word = 0x52, day = 57, balance = 17 } } }
  local resetOk, resetError = pcall(Apricorns.dailyReset, s)
  T.check(resetOk, "engine-owned reset callback needs no late Gen2 require: " .. tostring(resetError))
  T.eq(s.engineFlags[96], nil, "Crystal callback clears played flag")
  T.eq(s.crystal.buenaPassword.day, nil, "Crystal callback clears listening day")
  local directOk, directError = pcall(require, "src.core.gen2.Buena")
  T.eq(directOk, false, "direct mod require remains refused even for loaded Buena")
  T.check(tostring(directError):find("Gen 2 engine module", 1, true), "unchanged guard reports direct cross-generation access")
  Runtime.currentMod = nil
  run.release()
end
T.finish()
