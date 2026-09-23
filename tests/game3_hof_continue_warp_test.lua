#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").stubSpeciesNames()

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Field = require("src.core.game3.field")
local root = require("src.import.gba.extract_island1").CACHE_ROOT
Field.installFlyDestinations({ fly_destinations = {
  MAPSEC_PALLET_TOWN = { mapsec = 88, map = "FR_PALLET_TOWN", x = 6, y = 8, healLocation = 1 },
} }, root)

local Schema = require("src.core.game3.save_schema_firered")
local Natives = require("src.core.game3.scripting.natives")
local Std = require("src.core.game3.scripting.stdscripts")

local session = Schema.newGame({ gender = 0 })
session.map, session.x, session.y = "FR_POKEMON_LEAGUE_HALL_OF_FAME", 5, 4
session.playtime = { hours = 12, minutes = 34, seconds = 56 }
session.party = {
  { species = 6, level = 60, hp = 3, maxHp = 180, status = 1 },
  { species = 412, isEgg = true, level = 5, hp = 20, maxHp = 20 },
}
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }

local setFlags = {}
local hofOpened = false
local adapters = {
  setFlag = function(id, v) setFlags[id] = v end,
  hallOfFame = function(done) hofOpened = true done() end,
}
local handler = Natives.ALLOW["special:" .. Std.SPECIAL.EnterHallOfFame]
check(type(handler) == "function", "EnterHallOfFame native registered")
handler({}, adapters)

check(hofOpened, "HoF screen opened")
check(session.party[1].hp == 180 and session.party[1].status == nil, "party healed")
check(session.party[1].championRibbon == true, "champion ribbon given")
check(not session.party[2].championRibbon, "egg gets no champion ribbon")
check(setFlags[0x83B] == true, "FLAG_SYS_RIBBON_GET set")
check(tonumber(session.gameStats[42]) == 1, "GAME_STAT_RECEIVED_RIBBONS incremented")
check(tonumber(session.gameStats[1]) == 12 * 65536 + 34 * 256 + 56, "GAME_STAT_FIRST_HOF_PLAY_TIME stamped")
check(setFlags[0x82C] == true and session.game_cleared == true, "FLAG_SYS_GAME_CLEAR set")

local saved = Schema.toSaveTable(session)
check(saved.map == "FR_POKEMON_LEAGUE_HALL_OF_FAME", "save keeps the HoF room position")
check(saved.specialSaveWarpFlags == 1, "CONTINUE_GAME_WARP saved")

local cont = Schema.fromSaveTable(saved)
check(cont.map == "FR_PALLET_TOWN" and cont.x == 6 and cont.y == 8,
  "continue lands at Pallet Town 6,8 (got " .. tostring(cont.map) .. " " .. tostring(cont.x) .. "," .. tostring(cont.y) .. ")")
check(cont.specialSaveWarpFlags == 0, "CONTINUE_GAME_WARP cleared on continue")

cont.map, cont.x, cont.y = "FR_VIRIDIAN_CITY", 20, 20
local cont2 = Schema.fromSaveTable(Schema.toSaveTable(cont))
check(cont2.map == "FR_VIRIDIAN_CITY" and cont2.x == 20 and cont2.y == 20, "normal save after continue keeps its position")

handler({}, adapters)
check(tonumber(session.gameStats[42]) == 1, "second induction gives no new ribbons")
check(tonumber(session.gameStats[1]) == 12 * 65536 + 34 * 256 + 56, "first HoF time not overwritten")

local stuck = Schema.toSaveTable(Schema.newGame({ gender = 0 }))
stuck.map, stuck.x, stuck.y = "FR_POKEMON_LEAGUE_HALL_OF_FAME", 5, 4
stuck.specialSaveWarpFlags = nil
stuck.continueGameWarp = nil
local freed = Schema.fromSaveTable(stuck)
check(freed.map == "FR_PALLET_TOWN" and freed.x == 6 and freed.y == 8, "save stuck in the HoF room continues in Pallet Town")

local Dataset = require("src.core.game3.dataset")
local realCache = Dataset.cache
Dataset.cache = function() return { read = function() return nil end } end
Field.invalidateFlyDestinations()
stuck.map, stuck.x, stuck.y = "FR_POKEMON_LEAGUE_HALL_OF_FAME", 5, 4
local okLoad, deferred = pcall(Schema.fromSaveTable, stuck)
check(okLoad, "a stuck save loads with no readable cache (" .. tostring(not okLoad and deferred or "ok") .. ")")
check(okLoad and deferred.map == "FR_POKEMON_LEAGUE_HALL_OF_FAME" and deferred._continueWarpDeferred == true,
  "the repair waits for the cache")
check(okLoad and Schema.toSaveTable(deferred)._continueWarpDeferred == nil, "the deferral is not written to the save")
Dataset.cache = realCache
Field.installFlyDestinations({ fly_destinations = {
  MAPSEC_PALLET_TOWN = { mapsec = 88, map = "FR_PALLET_TOWN", x = 6, y = 8, healLocation = 1 },
} }, root)
if okLoad then
  Field.start(nil, nil, deferred)
  check(deferred.map == "FR_PALLET_TOWN" and deferred.x == 6 and deferred.y == 8
    and not deferred._continueWarpDeferred, "the deferred repair lands in Pallet Town once the field starts")
  Field.stop()
end

print(string.format("%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
