#!/usr/bin/env luajit

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

local Versions = require("src.import.gba.versions")
local CacheContract = require("src.import.CacheContract")

print("[test] 1. the importer advertises a whole cache version")
local V = Versions.CACHE_VERSION
check(type(V) == "number" and V == math.floor(V) and V > 0,
  "Versions.CACHE_VERSION is a positive integer, got " .. tostring(V))

print("[test] 2. cacheVersionCurrent rejects the previous cache version")

local function metaFs(version)
  return {
    prefix = nil,
    read = function(path)
      if path == "data/generated/gba/meta.json" then
        return string.format('{"cache_version":%d,"native_version":%d}',
          version, Versions.NATIVE_VERSION)
      end
      return nil
    end,
    exists = function() return true end,
  }
end

check(CacheContract.cacheVersionCurrent("firered", metaFs(V)) == true,
  "a meta.json at the importer's own version is current")
check(CacheContract.cacheVersionCurrent("firered", metaFs(V - 1)) == false,
  "a meta.json one version behind is rejected as stale")
check(CacheContract.cacheVersionCurrent("firered", metaFs(V + 1)) == false,
  "a meta.json from a newer importer is rejected too")

local noMeta = { prefix = nil, read = function() return nil end, exists = function() return true end }
check(CacheContract.cacheVersionCurrent("firered", noMeta) == false,
  "a cache with no meta.json is rejected")

check(CacheContract.cacheVersionCurrent("firered", metaFs(V * 10)) == false,
  "a meta.json whose version merely starts with this one is rejected, got " .. tostring(V * 10))

print("[test] 3. the stitch round's new keys are in the firered required list")

local required = CacheContract.requiredFilesFor("firered")
local have = {}
for _, path in ipairs(required) do have[path] = true end

local NEW_KEYS = {
  -- src/region_map.c:425
  "data/generated/gba/region_map/fly_icon.rgba",
  "data/generated/gba/region_map/fly_icon.png",
  -- src/heal_location.c:62, src/region_map.c:4023
  "data/generated/gba/region_map/heal_locations.lua",
  "data/generated/gba/region_map/fly_destinations.lua",
  -- src/scrcmd.c:711
  "data/generated/gba/native/layouts/alt_264.mid",
  "data/generated/gba/native/layouts/alt_278.mid",
  "data/generated/gba/native/layouts/alt_279.mid",
  "data/generated/gba/native/layouts/alt_319.mid",
  -- src/data/field_effects/field_effect_objects.h:99,565,1203
  "data/generated/gba/field_effects/ripple.rgba",
  "data/generated/gba/field_effects/splash.rgba",
  "data/generated/gba/field_effects/hot_springs_water.rgba",
  "data/generated/gba/field_effects/fly_bird.rgba",
  "data/generated/gba/field_effects/rock_smash.rgba",
}
for _, path in ipairs(NEW_KEYS) do
  check(have[path] == true, "required: " .. path)
end

print("[test] 4. every key this round's importer writes is in the firered required list")

local ROUND2_KEYS = {
  -- src/slot_machine.c:399, :739
  "data/generated/gba/slot_machine/manifest.lua",
  "data/generated/gba/slot_machine/reel_icons.rgba",
  "data/generated/gba/slot_machine/clefairy.rgba",
  "data/generated/gba/slot_machine/digits.rgba",
  "data/generated/gba/slot_machine/bg.rgba",
  "data/generated/gba/slot_machine/payout_lights.rgba",
  "data/generated/gba/slot_machine/match_lines.rgba",
  "data/generated/gba/slot_machine/button_pressed.rgba",
  "data/generated/gba/slot_machine/combos_window.rgba",
  -- src/trade_scene.c:151
  "data/generated/gba/trade/manifest.lua",
  "data/generated/gba/trade/gba_screen.rgba",
  "data/generated/gba/trade/gba_screen_wireless.rgba",
  "data/generated/gba/trade/gba_screen_flash.rgba",
  "data/generated/gba/trade/cable_closeup.rgba",
  "data/generated/gba/trade/cable_end.rgba",
  "data/generated/gba/trade/link_mon_glow.rgba",
  "data/generated/gba/trade/link_mon_shadow.rgba",
  "data/generated/gba/trade/ball.rgba",
  "data/generated/gba/trade/ball_spin.rgba",
  -- src/link_rfu_3.c:34, src/union_room_chat_objects.c:30
  "data/generated/gba/union_room/manifest.lua",
  "data/generated/gba/union_room/wireless_icon.rgba",
  "data/generated/gba/union_room/chat_bg.rgba",
  "data/generated/gba/union_room/chat_panel.rgba",
  "data/generated/gba/union_room/chat_icons.rgba",
  "data/generated/gba/union_room/chat_selector_cursor.rgba",
  -- src/wireless_communication_status_screen.c:50
  "data/generated/gba/wireless_status/manifest.lua",
  "data/generated/gba/wireless_status/bg.rgba",
  "data/generated/gba/wireless_status/palettes.pal",
  -- src/fame_checker.c:119, src/graphics.c:1230
  "data/generated/gba/fame_checker/manifest.lua",
  "data/generated/gba/fame_checker/bg.rgba",
  "data/generated/gba/fame_checker/0.rgba",
  "data/generated/gba/fame_checker/1.rgba",
  "data/generated/gba/fame_checker/13.rgba",
  "data/generated/gba/fame_checker/14.rgba",
  "data/generated/gba/fame_checker/cursor.rgba",
  "data/generated/gba/fame_checker/question_mark.rgba",
  "data/generated/gba/fame_checker/silhouette.pal",
  "data/generated/gba/fame_checker/pack.lua",
  -- src/graphics.c:1117, src/teachy_tv.c:526, :637, :1218
  "data/generated/gba/teachy_tv/manifest.lua",
  "data/generated/gba/teachy_tv/screen.rgba",
  "data/generated/gba/teachy_tv/title.rgba",
  "data/generated/gba/teachy_tv/end.rgba",
  "data/generated/gba/teachy_tv/static.rgba",
  "data/generated/gba/teachy_tv/bg3.rgba",
  -- src/mystery_gift_show_card.c:150, src/mystery_gift_show_news.c:99
  "data/generated/gba/mystery_gift/manifest.lua",
  "data/generated/gba/mystery_gift/card_bg0.rgba",
  "data/generated/gba/mystery_gift/card_bg7.rgba",
  "data/generated/gba/mystery_gift/news_bg0.rgba",
  "data/generated/gba/mystery_gift/news_bg7.rgba",
  -- src/trainer_tower_sets.c:8956, src/battle_records.c:563
  "data/generated/gba/trainer_tower.lua",
  "data/generated/gba/trainer_tower/manifest.lua",
  "data/generated/gba/trainer_tower/records_bg.rgba",
  -- src/data/pokemon/tutor_learnsets.h:22
  "data/generated/gba/pokemon/tutor.lua",
  -- src/trainer_tower.c:554, include/constants/layouts.h:355, :363
  "data/generated/gba/native/layouts/alt_366.mid",
  "data/generated/gba/native/layouts/alt_373.mid",
  "data/generated/gba/native/layouts/alt_374.mid",
  "data/generated/gba/native/layouts/alt_381.mid",
  -- src/script_menu.c:1161
  "data/generated/gba/museum/manifest.lua",
  "data/generated/gba/museum/kabutops.rgba",
  "data/generated/gba/museum/aerodactyl.rgba",
  -- src/region_map.c:790
  "data/generated/gba/region_map/dungeon_icon_visited.rgba",
  "data/generated/gba/region_map/dungeon_icon_visited.png",
  -- src/learn_move.c:403
  "data/generated/gba/move_relearner/manifest.lua",
  "data/generated/gba/move_relearner/bg.rgba",
  -- src/daycare.c:137, :138, :139
  "data/generated/gba/pokemon/egg/manifest.lua",
  "data/generated/gba/pokemon/egg/hatch.rgba",
  "data/generated/gba/pokemon/egg/shard.rgba",
  "data/generated/gba/pokemon/front/412.rgba",
  -- src/trainer_card.c:265, :1454, :1560
  "data/generated/gba/trainer_card/front_0.rgba",
  "data/generated/gba/trainer_card/front_4_female.rgba",
  "data/generated/gba/trainer_card/back_0.rgba",
  "data/generated/gba/trainer_card/back_4_female.rgba",
  "data/generated/gba/trainer_card/screen_0.rgba",
  "data/generated/gba/trainer_card/screen_4_female.rgba",
  "data/generated/gba/trainer_card/star.rgba",
  "data/generated/gba/trainer_card/stickers.rgba",
}
for _, path in ipairs(ROUND2_KEYS) do
  check(have[path] == true, "required: " .. path)
end

print("[test] 5. an imported cache at this version walks with zero missing keys")

local Cache = require("tests.game3_cache")
local root = Cache.root("meta.json")
if not root then
  print("[skip] cache half: " .. tostring(Cache.reason))
else
  print("[info] FireRed cache at " .. root)
  local base = root:gsub("/data/generated/gba$", "")
  local diskFs = {
    prefix = nil,
    read = function(path)
      local f = io.open(base .. "/" .. path, "rb")
      if not f then return nil end
      local data = f:read("*a")
      f:close()
      return data
    end,
    exists = function(path)
      local f = io.open(base .. "/" .. path, "rb")
      if not f then return false end
      f:close()
      return true
    end,
  }
  check(CacheContract.cacheVersionCurrent("firered", diskFs) == true,
    "the imported cache passes the staleness gate")
  local complete, missing = CacheContract.allRequiredFilesExist("firered", diskFs)
  check(complete == true, "zero missing required keys, first missing: " .. tostring(missing))
end

if failed > 0 then
  print(string.format("[result] %d CHECK(S) FAILED", failed))
  os.exit(1)
end
print("[result] all checks passed")
os.exit(0)
