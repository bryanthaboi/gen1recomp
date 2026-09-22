#!/usr/bin/env luajit
-- pokefirered/include/constants/items.h:272 ITEM_ITEMFINDER
-- pokefirered/include/constants/items.h:428 ITEM_LIFT_KEY
-- pokefirered/include/constants/items.h:433 ITEM_TOWN_MAP
-- pokefirered/include/constants/items.h:434 ITEM_VS_SEEKER
-- pokefirered/include/constants/items.h:437 ITEM_BERRY_POUCH
-- pokefirered/include/constants/items.h:446 ITEM_SAPPHIRE

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_stitchmap_item_ids_test")

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

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local ItemsData = require("src.core.game3.items_data")
ItemsData.install(nil)
local VsSeeker = require("src.core.game3.vs_seeker")

local ITEM_ITEMFINDER = 261
local ITEM_LIFT_KEY = 356
local ITEM_TOWN_MAP = 361
local ITEM_VS_SEEKER = 362
local ITEM_BERRY_POUCH = 365
local ITEM_SAPPHIRE = 374

print("[test] 1. the key-item constants are FRLG's, not Emerald's")
eq(ItemsData.ITEM_ITEMFINDER, ITEM_ITEMFINDER, "ItemsData.ITEM_ITEMFINDER")
eq(ItemsData.ITEM_VS_SEEKER, ITEM_VS_SEEKER, "ItemsData.ITEM_VS_SEEKER")
eq(VsSeeker.ITEM_VS_SEEKER, ITEM_VS_SEEKER, "VsSeeker.ITEM_VS_SEEKER")
eq(ItemsData.ITEM_TM_CASE, 364, "ItemsData.ITEM_TM_CASE")
eq(ItemsData.ITEM_BERRY_POUCH, ITEM_BERRY_POUCH, "ItemsData.ITEM_BERRY_POUCH")

print("[test] 2. each id routes to the field handler pret gives it")
eq(ItemsData.fieldUseKind(ITEM_ITEMFINDER), "itemfinder", "261 is the ITEMFINDER")
eq(ItemsData.fieldUseKind(ITEM_TOWN_MAP), "map", "361 is the TOWN MAP")
eq(ItemsData.fieldUseKind(ITEM_VS_SEEKER), "vs_seeker", "362 is the VS SEEKER")
check(ItemsData.fieldUseKind(ITEM_BERRY_POUCH) ~= "map",
  "365 is the BERRY POUCH, not a second TOWN MAP (got "
  .. tostring(ItemsData.fieldUseKind(ITEM_BERRY_POUCH)) .. ")")
check(ItemsData.fieldUseKind(ITEM_LIFT_KEY) ~= "itemfinder",
  "356 is the LIFT KEY, not the ITEMFINDER (got "
  .. tostring(ItemsData.fieldUseKind(ITEM_LIFT_KEY)) .. ")")
check(ItemsData.fieldUseKind(ITEM_SAPPHIRE) ~= "vs_seeker",
  "374 is the SAPPHIRE, not the VS SEEKER (got "
  .. tostring(ItemsData.fieldUseKind(ITEM_SAPPHIRE)) .. ")")

print("[test] 3. the names the pack files under those ids agree")
local finder = ItemsData.info(ITEM_ITEMFINDER)
local lift = ItemsData.info(ITEM_LIFT_KEY)
local seeker = ItemsData.info(ITEM_VS_SEEKER)
local sapphire = ItemsData.info(ITEM_SAPPHIRE)
if finder and lift and seeker and sapphire then
  eq(finder.name, "ITEMFINDER", "261 is named")
  eq(lift.name, "LIFT KEY", "356 is named")
  eq(seeker.name, "VS SEEKER", "362 is named")
  eq(sapphire.name, "SAPPHIRE", "374 is named")
else
  print("[info] no item pack mounted, skipping the name cross-check")
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
