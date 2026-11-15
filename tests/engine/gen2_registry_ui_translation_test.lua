-- Runtime coverage for the registry-adjacent Gen 2 labels.  The Python
-- harvest test proves the keys enter a translation scaffold; this suite proves
-- that loading such a catalog changes what the actual screens draw.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
require("tests.fixture_data.gen2_engine_flags").bind("gold")

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local Chrome = require("src.ui.gen2.Chrome")
local MainMenu = require("src.ui.gen2.MainMenu")
local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local Pokegear = require("src.ui.gen2.Pokegear")
local Strings = require("src.core.Strings")

Strings.load({ strings = {
  AM = "MATIN", PM = "SOIR", DAY = "JOUR",

  ["Press any button to exit."] = "Appuyez pour sortir.",
} })

-- ../pokecrystal/engine/menus/main_menu.asm:286, engine/rtc/timeset.asm:688
do
  local oldPrint, oldTextbox = Chrome.print, Chrome.textbox
  local drawn = {}
  Chrome.print = function(text, x, y) drawn[x .. ":" .. y] = text end
  Chrome.textbox = function() end
  local menu = MainMenu.new({ data = { text = require("tests.fixture_data.gen2_rom_text_s7_c")
    .text({ ["PrintDayOfWeek.Day"] = "JOUR", ["GetTimeOfDayString.day_string"] = "JOUR" }) } },
    { hasSave = false, save = false, clock = { hour = 13, minute = 5, weekday = 99 } })
  menu:drawClockBox()
  T.eq(drawn["1:15"], "JOUR", "the main-menu DAY fallback is PrintDayOfWeek.Day")
  T.eq(drawn["4:16"], "JOUR 1:05",
    "the main-menu daytime word (DAY, not PM) is GetTimeOfDayString's")
  Chrome.print, Chrome.textbox = oldPrint, oldTextbox
end

-- engine/rtc/print_hours_mins.asm:64
do
  local text = require("tests.fixture_data.gen2_rom_text_s7_d").text({
    String_AM = "MATIN", _PokegearPressButtonText = "Appuyez pour sortir.{DONE}",
  })
  local gear = Pokegear.new({ data = { text = text } }, {
    save = {}, clock = { hour = 1, minute = 2, weekday = 99 },
  })
  local drawn = {}
  gear.drawTilemap = function() end
  gear.drawStrip = function() end
  gear.cursor = function() end
  gear.textbox = function() end
  gear.printBoxText = function() end
  gear.text = function(_, text, x, y) drawn[x .. ":" .. y] = text end
  gear:drawClock()
  T.eq(drawn["12:8"], "MATIN", "the Pokegear AM half is translated")
  T.eq(gear:phoneText("PressButton"), "Appuyez pour sortir.",
    "a complete built-in Pokegear prompt is translated")
end

-- DexEntryScreen's action strip is one ROM string rather than four invented
-- fragments.
do
  local save = { pokedex = { seen = { BULBASAUR = true }, caught = {} } }
  local game = { save = save, data = {
    pokemon = { BULBASAUR = { name = "BULBIZARRE" } },
    text = { ["Pokedex_GetArea.String_SNest"] = " (NID)",
      ["Pokedex_DrawDexEntryScreenBG.MenuItems#1"] = " PAGE ZONE CRI IMPR",
      ["Pokedex_DrawDexEntryScreenBG.Height"] = "HT  ?<ROCKET>??<DEXEND>",
      ["Pokedex_DrawDexEntryScreenBG.Weight"] = "PDS   ???liv" },
    gen2Pokedex = { entries = {
      BULBASAUR = { dex = 1, kind = "GRAINE", height = 204, weight = 150 },
    }, newOrder = { "BULBASAUR" } },
  } }
  local dex = PokedexMenu.new(game, {})
  local drawn = {}
  dex.text = function(_, text, x, y) drawn[x .. ":" .. y] = text end
  dex.fill = function() end
  dex.border = function() end
  dex.tile = function() end
  dex.blank = function() end
  dex.drawPic = function() end
  dex.drawFootprint = function() end
  dex.cursorVisible = function() return false end
  dex:drawEntryBody(dex:current(), game.data.gen2Pokedex.entries.BULBASAUR)
  T.eq(drawn["1:17"], " PAGE ZONE CRI IMPR",
    "the Pokedex action strip is .MenuItems")
  T.eq(drawn["9:9"], "PDS   ???liv", "the Pokedex weight line is .Weight")

  local title
  dex.drawAreaHeader = function(_, text) title = text end
  dex.areaBlink = 0
  dex:drawArea()
  T.eq(title, "BULBIZARRE (NID)",
    "the Pokedex nest title is the name then Pokedex_GetArea.String_SNest")
  game.data.text["Pokedex_GetArea.String_SNest"] = nil
  T.check(not pcall(dex.drawArea, dex),
    "a cache without Pokedex_GetArea.String_SNest is an error")
end

Strings.load(nil)
T.finish()
