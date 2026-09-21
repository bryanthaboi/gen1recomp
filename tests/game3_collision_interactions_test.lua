#!/usr/bin/env luajit
-- pokefirered/src/field_control_avatar.c:515 GetInteractedMetatileScript

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local I = require("src.core.game3.scripting.interaction_scripts")

-- pokefirered/include/constants/metatile_behaviors.h:104
local MB_CABLE_CLUB_WIRELESS_MONITOR = 0x8D
local MB_BATTLE_RECORDS = 0x8E
local MB_QUESTIONNAIRE = 0x8F
local MB_TRAINER_TOWER_MONITOR = 0xA3

print("[test] 1. the four code-side interaction behaviors dispatch")

check(I.scriptFor(MB_TRAINER_TOWER_MONITOR, "down")
    == "TrainerTower_EventScript_ShowTime",
  "0xA3 opens TrainerTower_EventScript_ShowTime from any facing")
check(I.scriptFor(MB_QUESTIONNAIRE, "left") == "EventScript_Questionnaire",
  "0x8F opens EventScript_Questionnaire from any facing")
check(I.scriptFor(MB_CABLE_CLUB_WIRELESS_MONITOR, "up")
    == "CableClub_EventScript_ShowWirelessCommunicationScreen",
  "0x8D facing north opens the wireless communication screen")
check(I.scriptFor(MB_BATTLE_RECORDS, "up")
    == "CableClub_EventScript_ShowBattleRecords",
  "0x8E facing north opens the battle records")

-- src/metatile_behavior.c:854, :864
for _, facing in ipairs({ "down", "left", "right" }) do
  check(I.scriptFor(MB_CABLE_CLUB_WIRELESS_MONITOR, facing) == nil,
    "0x8D facing " .. facing .. " is not an interaction")
  check(I.scriptFor(MB_BATTLE_RECORDS, facing) == nil,
    "0x8E facing " .. facing .. " is not an interaction")
end
check(I.scriptFor(MB_BATTLE_RECORDS, 2) == "CableClub_EventScript_ShowBattleRecords",
  "0x8E accepts DIR_NORTH as the number 2")

print("[test] 2. the flavor table is still the ROM's 28-entry block")

check(#I.FLAVOR == 28,
  "I.FLAVOR has 28 rows, the length of pret/data/scripts/flavor_text.inc")
local FLAVOR_ORDER = {
  "Bookshelf", "PokeMartShelf", "Food", "VideoGame", "Computer",
  "ImpressiveMachine", "Blueprints", "Burglary", "PlayerFacingTVScreen",
  "Cabinet", "Kitchen", "Dresser", "Snacks", "Painting", "PowerPlantMachine",
  "Telephone", "AdvertisingPoster", "TastyFood", "TrashBin", "Cup",
  "PolishedWindow", "BeautifulSkyWindow", "BlinkingLights",
  "NeatlyLinedUpTools", "PokemartSign", "PokecenterSign",
  "Indigo_UltimateGoal", "Indigo_HighestAuthority",
}
local orderOk = true
for i, name in ipairs(FLAVOR_ORDER) do
  if not I.FLAVOR[i] or I.FLAVOR[i][2] ~= name then orderOk = false end
end
check(orderOk,
  "and they are in the order object_interactions_extract seeds them from the ROM")
for _, row in ipairs(I.CODE) do
  local clash = false
  for _, f in ipairs(I.FLAVOR) do
    if f[1] == row[1] then clash = true end
  end
  check(not clash, string.format("0x%02X is not also a flavor row", row[1]))
end

print("[test] 3. the behaviors that already worked still do")
check(I.scriptFor(0x83, "down") == "EventScript_PC", "0x83 is still the PC")
check(I.scriptFor(0x85, "up") == "EventScript_WallTownMap",
  "0x85 is still the wall town map")
check(I.scriptFor(0x81, "down") == "EventScript_Bookshelf",
  "0x81 is still the bookshelf")
check(I.scriptFor(0x86, "up") == "EventScript_PlayerFacingTVScreen",
  "0x86 facing north is still the TV screen")
check(I.scriptFor(0x86, "down") == nil, "0x86 facing south is still nothing")
check(I.scriptFor(0x00, "down") == nil, "a plain floor is still nothing")

print("[test] 4. the cells these behaviors sit on")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_collision_interactions_test map checks: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local game = { data = {} }
Dataset.hydrate(game)

local function census(beh)
  local cells, maps = 0, 0
  for mapId, def in pairs(game.data.maps) do
    if def.midLayout then
      Collision.bindMap(game, mapId, def)
      local here = 0
      for y = 0, Collision._heightCells - 1 do
        for x = 0, Collision._widthCells - 1 do
          if Collision.behavior(x, y) == beh then here = here + 1 end
        end
      end
      if here > 0 then
        cells = cells + here
        maps = maps + 1
      end
    end
  end
  return cells, maps
end

local CENSUS = {
  { MB_CABLE_CLUB_WIRELESS_MONITOR, 19, 19, "wireless communication monitor" },
  { MB_BATTLE_RECORDS, 19, 19, "battle records" },
  { MB_QUESTIONNAIRE, 12, 12, "questionnaire" },
  { MB_TRAINER_TOWER_MONITOR, 8, 8, "Trainer Tower monitor" },
}
for _, row in ipairs(CENSUS) do
  local cells, maps = census(row[1])
  check(cells == row[2] and maps == row[3],
    string.format("%s: %d cells over %d maps (got %d / %d)",
      row[4], row[2], row[3], cells, maps))
end

finish()
