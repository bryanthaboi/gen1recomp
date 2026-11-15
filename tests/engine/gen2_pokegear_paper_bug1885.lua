-- engine/pokegear/pokegear.asm (#1885)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check
love = love or require("tests.love_stub")

local Chrome = require("src.ui.gen2.Chrome")
local Pokegear = require("src.ui.gen2.Pokegear")

local CREAM = { 224, 248, 160 }
local PALS = { { CREAM, { 168, 168, 168 }, { 84, 84, 84 }, { 0, 0, 0 } } }

local runs, cursors, plain

local function spy(fn)
  runs, cursors, plain = {}, {}, 0
  local print_, through, cursor, cursorThrough =
    Chrome.print, Chrome.printThrough, Chrome.cursor, Chrome.cursorThrough
  Chrome.print = function() plain = plain + 1 end
  Chrome.printThrough = function(text, tx, ty, palette)
    runs[#runs + 1] = { text = text, tx = tx, ty = ty, palette = palette }
  end
  Chrome.cursor = function() plain = plain + 1 end
  Chrome.cursorThrough = function(tx, ty, palette)
    cursors[#cursors + 1] = { tx = tx, ty = ty, palette = palette }
  end
  local ok, err = pcall(fn)
  Chrome.print, Chrome.printThrough = print_, through
  Chrome.cursor, Chrome.cursorThrough = cursor, cursorThrough
  if not ok then error(err, 0) end
end

local function newGear()
  local gear = setmetatable({}, { __index = Pokegear })
  gear.pals = function() return PALS end
  gear.paperColor = function() return CREAM end
  return gear
end

local gear = newGear()
spy(function() gear:printBoxText("Press any button to exit.") end)
check(#runs == 2, "the exit prompt is two runs")
check(runs[1] and runs[1].text == "Press any button", "the first line as printed")
check(runs[1] and runs[1].tx == 1 and runs[1].ty == 14, "at (1,14)")
check(runs[2] and runs[2].ty == 16, "and the second two rows under it")
check(runs[1] and runs[1].palette == PALS[1], "both on the gear's cream paper")
check(runs[2] and runs[2].palette == PALS[1], "not Chrome's white box palette")
check(plain == 0, "and nothing goes through the white printer")

local clock = newGear()
clock.textData = require("tests.fixture_data.gen2_rom_text_s7_d").text()
clock.clockParts = function() return 15, 47, 5 end
clock.drawTilemap = function() end
clock.drawStrip = function() end
clock.textbox = function() end
clock.phoneText = function() return "Press any button to exit." end
spy(function() clock:drawClock() end)
check(runs[1] and runs[1].text == "SWITCH" and runs[1].tx == 13,
  "Gold's InitPokegearTilemap.switch is placed at column 13")
check(#cursors == 1 and cursors[1].tx == 19 and cursors[1].ty == 1,
  "its arrow sits at (19,1)")
check(cursors[1] and cursors[1].palette == PALS[1],
  "and wears the cream paper too")
check(plain == 0, "no white cell anywhere on the clock card")

local radio = newGear()
radio.ensureTuned = function() end
radio.drawTilemap = function() end
radio.drawStrip = function() end
radio.drawTuningKnob = function() end
radio.textbox = function() end
radio.currentStation = function()
  return { name = "OAK's PKMN Talk", station = "OAKS_POKEMON_TALK" }
end
radio.radio = { top = "... ...Ahem, we are", bottom = "TEAM ROCKET!" }
spy(function() radio:drawRadio() end)
check(runs[2] and runs[2].text == "... ...Ahem, we are" and runs[2].ty == 14,
  "the show's top line lands on row 14")
check(runs[3] and runs[3].text == "TEAM ROCKET!" and runs[3].ty == 16,
  "and the bottom line on row 16")
check(runs[2] and runs[2].palette == PALS[1], "on cream, like the station name")
check(plain == 0, "with no white bar behind the speech")

T.finish("gen2 pokegear paper bug 1885")
