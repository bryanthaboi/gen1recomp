-- Parity: Yellow's Route 18 Gate 2F trader is a cook offering SPIKE
-- (TANGELA -> PARASECT), not Red's youngster (pokeyellow/scripts/
-- Route18Gate2F.asm Route18Gate2FCookText, TRADE_FOR_SPIKE).  The port
-- only wired TEXT_ROUTE18GATE2F_YOUNGSTER, so on Yellow the cook had no
-- talk script at all and never answered (#651).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("parity Yellow route 18 gate trade")
local check, eq = S.check, S.eq

local scripts = require("data.scripts.init")

local cook = scripts.talkScript("ROUTE_18_GATE_2F", "TEXT_ROUTE18GATE2F_COOK")
check(cook ~= nil, "the Yellow cook has a talk script")
if cook then
  eq(cook[2][1], "trade", "the cook runs a trade")
  eq(cook[2][2], 6, "the cook's trade is TRADE_FOR_SPIKE (index 6)")
  eq(cook[2][3], "EVENT_TRADED_SLOWBRO_FOR_LICKITUNG",
    "the cook shares slot 6's done flag, so a converted .sav stays done")
end

-- Red's youngster row stays put: trade 6 is MARC on Red's table and the
-- two rows share the index across versions.
local youngster = scripts.talkScript("ROUTE_18_GATE_2F", "TEXT_ROUTE18GATE2F_YOUNGSTER")
check(youngster ~= nil, "Red's youngster keeps his talk script")
if youngster then
  eq(youngster[2][1], "trade", "the youngster runs a trade")
  eq(youngster[2][2], 6, "the youngster's trade stays index 6")
end

-- Yellow's map only has the cook, so the new key is the one that fires.
local manifestFile = assert(io.open("tools/rom_manifest_yellow.json", "r"))
local manifest = manifestFile:read("*a")
manifestFile:close()
check(manifest:find('"name": "ROUTE18GATE2F_COOK"', 1, true) ~= nil,
  "Yellow's Route18Gate2F object is the cook")
check(manifest:find('"TEXT_ROUTE18GATE2F_COOK"', 1, true) ~= nil,
  "the cook carries TEXT_ROUTE18GATE2F_COOK")
check(manifest:find("ROUTE18GATE2F_YOUNGSTER", 1, true) == nil,
  "Yellow's Route18Gate2F has no youngster")

-- The Yellow table makes index 6 the SPIKE row (TANGELA -> PARASECT).
local Data = require("src.core.Data")
if not (Data.field and Data.field.trades) then Data:load() end
local GameVersion = require("src.core.GameVersion")
local oldVersion = GameVersion.get()
local oldTrades = Data.field.trades
GameVersion.set("yellow")
Data:applyVersionedFieldData()
local spike = Data.field.trades[6]
check(spike.give == "TANGELA" and spike.get == "PARASECT"
  and spike.nickname == "SPIKE",
  "on Yellow trade 6 is SPIKE (TANGELA -> PARASECT)")
Data.field.trades = oldTrades
GameVersion.set(oldVersion)

S.finish()
