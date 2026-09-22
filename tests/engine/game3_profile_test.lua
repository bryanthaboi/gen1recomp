package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
local MapIds = require("src.core.game3.map_ids")

local prevVersion = GameVersion.get()

Profile.reset()
GameVersion.set("firered")
local active = Profile.active()
eq(active.id, "firered", "active() resolves the active Gen 3 game")
check(Profile.of("firered") == active, "for(id) and active() share one cached row")
check(Profile.isGame3Version("firered") == true, "isGame3Version(firered) is true")
check(Profile.isGame3Version("red") == false, "isGame3Version(red) is false")
check(Profile.isGame3Version("not-a-game") == false, "isGame3Version(unknown) is false")

check(Profile.of("firered") == active, "resolution is cached")

local unknown = Profile.of("not-a-game")
eq(unknown.id, "firered", "an unknown game id falls back to FireRed")

Profile.reset()
GameVersion.set("red")
eq(Profile.active().id, "firered", "non-Gen3 process fails closed to FireRed")

local caps = Profile.capabilitiesFor({ version = "firered" })
check(caps.fameChecker == true, "capabilitiesFor(session) reads the session game")
check(Profile.has({ version = "firered" }, "vsSeeker") == true, "has() reads a flag")
check(Profile.has({ version = "firered" }, "contests") == false, "has() is false for absent flags")

Profile.reset()
GameVersion.set("firered")
local row = Profile.active()

for _, prefix in ipairs(row.map.prefixes) do
  check(MapIds.isGame3Map(prefix .. "ANYTHING") == true,
    "profile prefix " .. prefix .. " is a Game3 map for MapIds")
end
check(MapIds.isGame3Map("NOT_A_MAP") == false, "a foreign id is not a Game3 map")
eq(row.map.enginePrefix, "FR_", "map id synthesis prefix is FR_")
eq(row.map.legacyPrefixes[1], "SEVII_", "Sevii is the one legacy namespace")
eq(row.map.newGameStart.map, MapIds.NEW_GAME_START.map, "new-game start map matches MapIds")
eq(row.map.newGameStart.x, MapIds.NEW_GAME_START.x, "new-game start x matches MapIds")
eq(row.map.newGameStart.y, MapIds.NEW_GAME_START.y, "new-game start y matches MapIds")
eq(row.map.newGameStart.healMap, MapIds.NEW_GAME_START.healMap, "heal map matches MapIds")
eq(row.map.newGameStart.healX, MapIds.NEW_GAME_START.healX, "heal x matches MapIds")
eq(row.map.newGameStart.healY, MapIds.NEW_GAME_START.healY, "heal y matches MapIds")

eq(row.optionsBlock, "firered", "options block is the FireRed key")
eq(row.species.num, 412, "species count is FRLG's 412")
eq(row.species.egg, 412, "egg species is FRLG's 412")

eq(row.dexArea.defaultKey, "kanto", "dex area default is kanto")
eq(row.dexArea.dexMax, 151, "dex area max is 151")
local okGroups, groups = pcall(require, row.dexArea.mapGroups)
check(okGroups and type(groups) == "table" and next(groups) ~= nil,
  "dexArea.mapGroups names a loadable map-group module")

eq(row.badges.count, 8, "eight badges")
eq(row.badges.flagBase, 0x820, "badge flag base is 0x820")
local badgeNames = {
  "BOULDER", "CASCADE", "THUNDER", "RAINBOW",
  "SOUL", "MARSH", "VOLCANO", "EARTH",
}
for i, name in ipairs(badgeNames) do
  eq(row.badges.names[i], name, "badge " .. i .. " name is " .. name)
end

eq(row.trainers.rivalIds.squirtle, 326, "rival squirtle id")
eq(row.trainers.rivalIds.bulbasaur, 327, "rival bulbasaur id")
eq(row.trainers.rivalIds.charmander, 328, "rival charmander id")
eq(row.trainers.fallback.class, 81, "rival fallback class")
eq(row.trainers.fallback.pic, 106, "rival fallback pic")
eq(row.trainers.fallback.name, "TERRY", "rival fallback name")
eq(row.trainers.music.encounter.girl, 284, "encounter music girl")
eq(row.trainers.music.encounter.rocket, 283, "encounter music rocket")
eq(row.trainers.music.encounter.boy, 285, "encounter music boy")
eq(row.trainers.music.battle.gym, 296, "gym battle music")
eq(row.trainers.music.victory.gym, 312, "gym victory music")
eq(row.trainers.music.victory.trainer, 310, "trainer victory music")

eq(row.regionMap.switchFlag, "FLAG_SYS_SEVII_MAP_123", "region-map switch flag")

for _, flag in ipairs({ "fameChecker", "teachyTV", "vsSeeker", "trainerTower", "seagallop" }) do
  check(row.capabilities[flag] == true, "FireRed capability " .. flag .. " is on")
end

local expectedNatives = {
  "natives_corner", "natives_cutscene", "natives_daycare", "natives_elevator",
  "natives_events", "natives_fame", "natives_fan_club", "natives_gift",
  "natives_link", "natives_listmenu", "natives_moveteach", "natives_queries",
  "natives_seagallop", "natives_size_record", "natives_tower", "natives_trade",
  "natives_wireless",
}
eq(#row.nativeModules, #expectedNatives, "native module count matches the registry")
for i, name in ipairs(expectedNatives) do
  eq(row.nativeModules[i], name, "native module " .. i .. " is " .. name)
end

Profile.reset()
local okMissing = pcall(function()
  local warn = Profile.of("not-a-game")
  return warn
end)
check(okMissing == true, "unknown ids resolve without raising")

for _, rel in ipairs({
  row.font.module,
  row.dexArea.mapGroups,
  row.saveRules,
}) do
  check(type(rel) == "string" and rel:match("^[%w_%.]+$") ~= nil,
    "module path is well-formed: " .. tostring(rel))
end
check(type(row.font.widths) == "string" and #row.font.widths > 0, "font widths path is set")
check(type(row.font.smallWidths) == "string" and #row.font.smallWidths > 0, "small font path is set")
check(type(row.extractors) == "table" and #row.extractors > 0, "aux extractor list is set")

GameVersion.set(prevVersion)
T.finish("game3_profile_test")
