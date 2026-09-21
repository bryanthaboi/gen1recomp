#!/usr/bin/env luajit
-- pokefirered/src/overworld.c:948 Overworld_IsBikingAllowed

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Space = require("src.core.game3.scripting.space")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_stitchmap_bike_test: " .. tostring(Cache.reason))
  done()
end
print("[info] FireRed cache at " .. cacheRoot)

local ExtractScripts = require("src.import.gba.extract_scripts")
Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })

local Dataset = require("src.core.game3.dataset")
local MapCatalog = require("src.import.gba.map_catalog")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Player = require("src.core.game3.player")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = "FR_PALLET_TOWN", x = 12, y = 20, facing = "down",
  flags = {}, vars = {}, party = {} }
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })

local MT_MOON_1F = MapCatalog.pretToEngine("MtMoon_1F")
local MT_MOON_B1F = MapCatalog.pretToEngine("MtMoon_B1F")
local HOUSE = MapCatalog.pretToEngine("PalletTown_PlayersHouse_1F")
local ROUTE_4 = MapCatalog.pretToEngine("Route4")

local function defOf(id) return id and game.data.maps[id] end
check(defOf(MT_MOON_1F) ~= nil, "MtMoon_1F is in the cache")
check(defOf(MT_MOON_B1F) ~= nil, "MtMoon_B1F is in the cache")
check(defOf(HOUSE) ~= nil, "PalletTown_PlayersHouse_1F is in the cache")
check(defOf(ROUTE_4) ~= nil, "Route4 is in the cache")
if not (MT_MOON_1F and MT_MOON_B1F and HOUSE and ROUTE_4) then done() end

local function goTo(mapId, x, y)
  Map.load(nil, game, mapId, { x = x, y = y, facing = "down" })
  session.map = mapId
end

print("[test] 1. the cave floors carry pret's allow_cycling bit")
check((tonumber(defOf(MT_MOON_1F).bikingAllowed) or 0) ~= 0, "MtMoon_1F allows cycling")
check((tonumber(defOf(MT_MOON_B1F).bikingAllowed) or 0) ~= 0, "MtMoon_B1F allows cycling")
check((tonumber(defOf(HOUSE).bikingAllowed) or 0) == 0, "the house does not")
check(type(defOf(MT_MOON_1F).pair) == "string"
  and defOf(MT_MOON_1F).pair:find("outdoor", 1, true) == nil,
  "and Mt Moon's tileset pair is not an outdoor one (" .. tostring(defOf(MT_MOON_1F).pair) .. ")")

print("[test] 2. riding from Route 4 into Mt Moon and down to B1F keeps the bike")
goTo(ROUTE_4, 5, 5)
Player.biking = true
goTo(MT_MOON_1F, 5, 5)
check(Player.biking == true, "MtMoon_1F did not dismount the player")
goTo(MT_MOON_B1F, 5, 5)
check(Player.biking == true, "MtMoon_B1F did not either")

print("[test] 3. a map with allow_cycling 0 still dismounts")
goTo(HOUSE, 4, 5)
check(Player.biking == false, "the house took the bike away")

print("[test] 4. with no header field the tileset pair still decides")
Player.biking = true
local def = defOf(MT_MOON_1F)
local saved = def.bikingAllowed
def.bikingAllowed = nil
goTo(MT_MOON_1F, 5, 5)
def.bikingAllowed = saved
check(Player.biking == false, "the pair fallback dismounts inside a cave")

done()
