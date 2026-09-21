#!/usr/bin/env luajit
-- pokefirered/include/global.fieldmap.h:191 struct MapHeader on the live map def.

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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

local Cache = require("tests.game3_cache")
local root = Cache.mount("meta.json")
if not root then
  print("[skip] " .. tostring(Cache.reason))
  os.exit(0)
end
print("[info] FireRed cache at " .. root)

local Json = require("src.link.Json")
local MapCatalog = require("src.import.gba.map_catalog")
local Dataset = require("src.core.game3.dataset")
local DEFS = Dataset.buildMaps()

local function header_of(mapId)
  local slot = MapCatalog.slotKeyFor and MapCatalog.slotKeyFor(mapId)
  if not slot then return nil end
  local f = io.open(root .. "/map_tree/maps/" .. slot .. "/header.json", "rb")
  if not f then return nil end
  local raw = f:read("*a")
  f:close()
  if type(raw) ~= "string" or raw == "" then return nil end
  local ok, h = pcall(Json.decode, raw)
  if ok and type(h) == "table" then return h end
  return nil
end

local function def_of(pretName)
  local id = MapCatalog.pretToEngine(pretName)
  return id and DEFS[id], id
end

local FIELDS = {
  "cave", "allowEscaping", "allowRunning", "bikingAllowed",
  "battleType", "music", "borderWidth", "borderHeight",
}

print("[test] 1. every header field reaches the def")
local sample = { "PalletTown", "MtMoon_1F", "RockTunnel_1F", "ViridianForest",
  "PalletTown_PlayersHouse_1F", "ViridianCity_Gym" }
for _, pretName in ipairs(sample) do
  local def, id = def_of(pretName)
  if not def then
    print("[skip] the cache has no live map def for " .. pretName)
    os.exit(0)
  end
  local h = header_of(id)
  if not h then
    print("[skip] the cache has no header.json for " .. pretName)
    os.exit(0)
  end
  for _, key in ipairs(FIELDS) do
    eq(def[key], tonumber(h[key]), pretName .. "." .. key)
  end
end

print("[test] 2. the values are the cart's")
local rock = def_of("RockTunnel_1F")
eq(rock.cave, 1, "Rock Tunnel 1F is a flash cave")
eq(rock.allowEscaping, 1, "Rock Tunnel 1F allows Escape Rope and Dig")
eq(rock.mapType, 4, "Rock Tunnel 1F is MAP_TYPE_UNDERGROUND")
local moon = def_of("MtMoon_1F")
eq(moon.cave, 0, "Mt Moon 1F is not a flash cave")
eq(moon.allowEscaping, 1, "Mt Moon 1F allows Escape Rope and Dig")
eq(moon.bikingAllowed, 1, "Mt Moon 1F allows cycling")
local gym = def_of("ViridianCity_Gym")
eq(gym.battleType, 1, "Viridian Gym asks for the gym battle background")
eq(gym.bikingAllowed, 0, "Viridian Gym forbids cycling")
eq(gym.allowRunning, 0, "Viridian Gym forbids running")
local house = def_of("PalletTown_PlayersHouse_1F")
eq(house.allowEscaping, 0, "the player's house refuses Escape Rope")
eq(house.battleType, 0, "the player's house uses MAP_BATTLE_SCENE_NORMAL")
local pallet = def_of("PalletTown")
eq(pallet.battleType, 0, "Pallet Town uses MAP_BATTLE_SCENE_NORMAL")
eq(pallet.allowRunning, 1, "Pallet Town allows running")
eq(def_of("ViridianForest").borderWidth, 3, "Viridian Forest has a 3 wide border")

print("[test] 3. the whole map table agrees with the cache, with no gaps")
local checked, mismatched, missing = 0, 0, 0
for mapId, def in pairs(DEFS) do
  local h = header_of(mapId)
  if h then
    checked = checked + 1
    for _, key in ipairs(FIELDS) do
      if def[key] == nil then
        missing = missing + 1
        if missing <= 5 then print("   nil " .. mapId .. "." .. key) end
      elseif def[key] ~= tonumber(h[key]) then
        mismatched = mismatched + 1
        if mismatched <= 5 then
          print(string.format("   %s.%s def %s header %s",
            mapId, key, tostring(def[key]), tostring(h[key])))
        end
      end
    end
  end
end
check(checked > 300, "headers compared: " .. checked)
eq(missing, 0, "no def is missing a header field")
eq(mismatched, 0, "no def disagrees with its header")

print("[test] 4. FieldView reads the stamped cave flag")
-- pokefirered/src/overworld.c:956
local FieldView = require("src.core.game3.field_view")
local game = { data = { maps = DEFS } }
local rockId = MapCatalog.pretToEngine("RockTunnel_1F")
local palletId = MapCatalog.pretToEngine("PalletTown")
eq(FieldView.defaultFlashLevel(game, rockId), FieldView.MAX_FLASH_LEVEL,
  "Rock Tunnel 1F starts dark")
eq(FieldView.defaultFlashLevel(game, palletId), 0, "Pallet Town starts lit")

if failed > 0 then
  print(string.format("\n%d CHECK(S) FAILED", failed))
  os.exit(1)
end
print("\nALL STITCHMAP HEADER TESTS PASSED")
