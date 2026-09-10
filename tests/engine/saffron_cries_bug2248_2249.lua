-- pokered/scripts/SaffronPidgeyHouse.asm:14-19
-- pokered/scripts/CopycatsHouse1F.asm:18-23
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

local function findRow(rows, cmd)
  for i, row in ipairs(rows) do
    if row[1] == cmd then return i end
  end
  return nil
end

local pidgey = assert(loadfile("data/scripts/flavor/saffron_pidgey_house.lua"))()
local pidgeyRows = pidgey.SAFFRON_PIDGEY_HOUSE.talk.TEXT_SAFFRONPIDGEYHOUSE_PIDGEY
local pidgeyCry = findRow(pidgeyRows, "play_cry")
local pidgeyText = findRow(pidgeyRows, "show_text")
T.check(pidgeyCry ~= nil, "saffron_pidgey_house has a play_cry row")
T.check(pidgeyText ~= nil, "saffron_pidgey_house has a show_text row")
T.check(pidgeyCry ~= nil and pidgeyText ~= nil and pidgeyCry < pidgeyText,
  "saffron_pidgey_house play_cry precedes show_text")
T.eq(pidgeyRows[pidgeyCry][2], "PIDGEY", "saffron_pidgey_house plays PIDGEY cry")

local chansey = assert(loadfile("data/scripts/flavor/copycats_house_1f.lua"))()
local chanseyRows = chansey.COPYCATS_HOUSE_1F.talk.TEXT_COPYCATSHOUSE1F_CHANSEY
local chanseyCry = findRow(chanseyRows, "play_cry")
local chanseyText = findRow(chanseyRows, "show_text")
T.check(chanseyCry ~= nil, "copycats_house_1f has a play_cry row")
T.check(chanseyText ~= nil, "copycats_house_1f has a show_text row")
T.check(chanseyCry ~= nil and chanseyText ~= nil and chanseyCry < chanseyText,
  "copycats_house_1f play_cry precedes show_text")
T.eq(chanseyRows[chanseyCry][2], "CHANSEY", "copycats_house_1f plays CHANSEY cry")

T.finish("saffron_cries_bug2248_2249")
