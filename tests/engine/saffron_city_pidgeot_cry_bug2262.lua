-- pokered/scripts/SaffronCity.asm:76
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

local function findRow(rows, cmd)
  for i, row in ipairs(rows) do
    if row[1] == cmd then return i end
  end
  return nil
end

local chunk = loadfile("data/scripts/flavor/saffron_city.lua")
T.check(chunk ~= nil, "saffron_city flavor file exists")
local mod = chunk and chunk() or {}
local rows = mod.SAFFRON_CITY and mod.SAFFRON_CITY.talk
  and mod.SAFFRON_CITY.talk.TEXT_SAFFRONCITY_PIDGEOT or {}
local cry = findRow(rows, "play_cry")
local text = findRow(rows, "show_text")
T.check(cry ~= nil, "saffron_city pidgeot has a play_cry row")
T.check(text ~= nil, "saffron_city pidgeot has a show_text row")
T.check(cry ~= nil and text ~= nil and cry < text,
  "saffron_city pidgeot play_cry precedes show_text")
T.eq(cry and rows[cry][2], "PIDGEOT", "saffron_city pidgeot plays PIDGEOT cry")
T.eq(cry and rows[cry][3], true, "saffron_city pidgeot cry holds for A/B")
T.eq(text and rows[text][2], "_SaffronCityPidgeotText",
  "saffron_city pidgeot shows _SaffronCityPidgeotText")

local src = assert(io.open("data/scripts/flavor_all.lua", "r"))
local index = src:read("*a")
src:close()
T.check(index:find('"data.scripts.flavor.saffron_city"', 1, true) ~= nil,
  "flavor_all indexes saffron_city")

T.finish("saffron_city_pidgeot_cry_bug2262")
