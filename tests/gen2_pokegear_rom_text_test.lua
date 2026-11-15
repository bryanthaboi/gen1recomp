-- engine/pokegear/radio.asm:101
--   luajit tests/gen2_pokegear_rom_text_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 pokegear rom text")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local CommonText = require("src.core.gen2.CommonText")
local Pokegear = require("src.ui.gen2.Pokegear")
local Fixture = require("tests.fixture_data.gen2_rom_text_s7_d")

local function plain(body)
  return (CommonText.plain(body):gsub("^\n", ""))
end

local function rolls(...)
  local list = { ... }
  local index = 0
  return function()
    index = index % #list + 1
    return list[index]
  end
end

local function radioLog(station, text, lines, extra)
  local data = { landmarks = {}, mapLandmark = {}, grass = {}, species = {},
    caught = function() return false end, dex = {}, classes = {}, hidden = {},
    weekday = 2, luckyNumber = 42, text = text }
  for k, v in pairs(extra or {}) do data[k] = v end
  local radio = Pokegear.Radio.new({ data = data, rng = rolls(0) })
  radio:tune(station)
  for _ = 1, (lines + 2) * 200 do
    if #radio.log >= lines then break end
    radio:step()
  end
  return radio.log
end

-- engine/pokegear/radio.asm:276
do
  local text = Fixture.text({ OPT_IntroText1 = "\nCACHE INTRO{DONE}" })
  local log = radioLog("OAKS_POKEMON_TALK", text, 3)
  eq(log[1], "CACHE INTRO", "Oak's talk opens on the cache's OPT_IntroText1")
  eq(log[2], plain(text.OPT_IntroText2), "then OPT_IntroText2")
  local ok = pcall(radioLog, "OAKS_POKEMON_TALK",
    Fixture.without("OPT_IntroText1"), 1)
  eq(ok, false, "a cache without OPT_IntroText1 is an error")
end

-- engine/pokegear/radio.asm:1327
do
  local gold = radioLog("ROCKET_RADIO", Fixture.text(), 9)
  eq(gold[9], "Where is our Boss?", "Gold's RocketRadioText9")
  local crystal = radioLog("ROCKET_RADIO", Fixture.text(nil, "crystal"), 9)
  eq(crystal[9], "Where is our boss?", "Crystal's own RocketRadioText9")
end

-- ../pokecrystal/engine/pokegear/radio.asm:460
do
  local seen = {}
  for roll = 0, 15 do
    local data = { landmarks = {}, mapLandmark = {}, grass = {},
      text = Fixture.text(nil, "crystal") }
    local radio = Pokegear.Radio.new({ data = data, rng = rolls(roll) })
    radio.vars.segmentCounter = 5
    radio.cur = "OAKS_POKEMON_TALK_9"
    radio:step()
    seen[radio.log[1]] = true
  end
  eq(seen["groovy!"], true, "Crystal's adjective table carries OPT_GroovyText")
  eq(seen["now!"], nil, "and not Gold's OPT_NowText")
end

-- engine/pokegear/radio.asm:996
do
  local log = radioLog("LUCKY_CHANNEL", Fixture.text({
    LC_Text8 = "\nNUMERO {STRBUF}!{DONE}" }), 8)
  eq(log[8], "NUMERO 00042!", "LC_Text8 carries the five-digit number")
end

-- home/text.asm:952
do
  local log = radioLog("POKEMON_MUSIC", Fixture.text({
    ["TextCommand_DAY.Tues"] = "MAR", ["TextCommand_DAY.Day"] = "DI" }), 4)
  eq(log[4], "Today's MARDI,", "the weekday is TextCommand_DAY's own")
  local framed = radioLog("POKEMON_MUSIC", Fixture.text({
    BenFernText1 = "\nHOY {DAY}!{DONE}" }), 4)
  eq(framed[4], "HOY TUESDAY!", "the sentence around it is BenFernText1's")
end

-- engine/pokegear/radio.asm:551, :563
do
  local radio = Pokegear.Radio.new({ data = { text = Fixture.text({
    ["OaksPKMNTalk11.pokemon_string"] = "PKA",
    ["OaksPKMNTalk12.pokemon_channel_string"] = "PKB" }) } })
  radio.cur, radio.delay, radio.top = "OAKS_POKEMON_TALK_11", 1, "POKéMON"
  radio:step()
  eq(radio.top, "POKéMON PKA", "the jingle's second stamp is pokemon_string")
  radio.delay = 1
  radio:step()
  eq(radio.bottom, "PKB", "and its third is pokemon_channel_string")
end

-- engine/pokegear/pokegear.asm:305, :1235
do
  local function clockRuns(version)
    local gear = Pokegear.new({ data = { text = Fixture.text({
      ["Pokegear_UpdateClock.GearTodayText"] = "<{DAY}>" }, version) } },
      { save = {}, clock = { hour = 9, minute = 0, weekday = 3 } })
    local drawn = {}
    gear.drawTilemap, gear.drawStrip, gear.cursor = function() end, function() end, function() end
    gear.textbox, gear.printBoxText = function() end, function() end
    gear.text = function(_, body, x, y) drawn[#drawn + 1] = { body, x, y } end
    gear:drawClock()
    return drawn, gear
  end
  local gold = clockRuns()
  eq(gold[1][1] .. "@" .. gold[1][2], "SWITCH@13", "Gold's SWITCH sits at hlcoord 13")
  eq(gold[2][1], "<TUESDAY>", "the day goes through _GearTodayText")
  local crystal = clockRuns("crystal")
  eq(crystal[1][1] .. "@" .. crystal[1][2], " SWITCH@12", "Crystal's at hlcoord 12")

  local _, gear = clockRuns()
  local rows = {}
  gear.text = function(_, body, x, y) rows[#rows + 1] = body .. "@" .. x .. "," .. y end
  gear.phoneSubmenu = "callDeleteCancel"
  gear:drawPhoneSubmenu()
  eq(table.concat(rows, " "), "CALL@11,6 DELETE@11,8 CANCEL@11,10",
    "the phone submenu is CallDeleteCancelStrings")
  rows = {}
  gear.textData = Fixture.text({
    ["PokegearPhoneContactSubmenu.CallCancelStrings#1"] = "APPEL\nRETOUR" })
  gear.phoneSubmenu = "callCancel"
  gear:drawPhoneSubmenu()
  eq(table.concat(rows, " "), "APPEL@11,8 RETOUR@11,10",
    "and the two-row one CallCancelStrings")
  gear.textData = Fixture.without("PokegearPhoneContactSubmenu.CallCancelStrings#1")
  check(not pcall(gear.drawPhoneSubmenu, gear), "a cache without the menu is an error")
end

-- engine/pokegear/pokegear.asm:1699
do
  local text = Fixture.text({ PokemonMusicName = "CACHE MUSIC" })
  local gear = Pokegear.new({ data = { text = text } }, { save = {} })
  eq(gear:stationName("POKEMON_MUSIC"), "CACHE MUSIC",
    "the tuner names a station from the cache")
  eq(gear:stationName("ROCKET_RADIO"), plain(text.LetsAllSingName),
    "Rocket Radio borrows LetsAllSingName")
  gear.textData = Fixture.without("PokemonMusicName")
  eq(pcall(gear.stationName, gear, "POKEMON_MUSIC"), false,
    "a cache without the station label is an error")
end

-- data/text/common_3.asm:43
do
  local gear = Pokegear.new({ data = { text = Fixture.text() } }, { save = {} })
  eq(gear:phoneText("AskWhoCall"), "Whom do you want\nto call?",
    "the phone prompt keeps the cache's own line break")
  eq(gear:phoneText("OutOfArea"), plain(Fixture.text()._PhoneOutOfAreaText),
    "and every phone line is the cache's")
  gear.textData = Fixture.without("_PokegearAskWhoCallText")
  eq(pcall(gear.phoneText, gear, "AskWhoCall"), false,
    "a cache without the label is an error")
end

-- engine/rtc/print_hours_mins.asm:65, engine/pokegear/pokegear.asm:2132
do
  local text = Fixture.text({ String_PM = "PMX", ["TownMapBubble.Where"] = "OU?" })
  local gear = Pokegear.new({ data = { text = text } },
    { save = {}, clock = { hour = 15, minute = 4, weekday = 2 } })
  local drawn = {}
  gear.drawTilemap, gear.drawStrip, gear.cursor = function() end, function() end, function() end
  gear.textbox, gear.printBoxText = function() end, function() end
  gear.tile, gear.drawPlate = function() end, function() end
  gear.text = function(_, body, x, y) drawn[x .. ":" .. y] = body end
  gear:drawClock()
  eq(drawn["12:8"], "PMX", "the clock card prints String_PM")
  gear:drawFlyBubble()
  eq(drawn["2:0"], "OU?", "the fly bubble prints TownMapBubble.Where")
  gear.textData = Fixture.without("String_PM")
  check(not pcall(gear.drawClock, gear), "a cache without String_PM is an error")
end

S.finish()
