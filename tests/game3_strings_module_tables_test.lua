#!/usr/bin/env luajit
-- Game3 text kept in module-level tables is built before any translation
-- catalog exists, so it must be translated when it is read, not when the
-- module loads.  Load the modules first, then the catalog, as a real boot does.

package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Strings = require("src.core.Strings")
local FieldMoves = require("src.core.game3.field_moves")
local ItemsData = require("src.core.game3.items_data")

Strings.load({ strings = {
  ["Not enough HP…"] = "Pas assez de PV…",
  ["KEY ITEMS"] = "OBJETS RARES",
} })

check(FieldMoves.TEXT.NOT_A_KEY == nil, "FieldMoves.TEXT has no entry for an unknown key")

if require("tests.game3_cache").mount() then
  check(FieldMoves.TEXT.NOT_ENOUGH_HP == "Pas assez de PV…",
    "FieldMoves.TEXT reads gText_NotEnoughHp through the catalog when read")
  check(ItemsData.POCKET_LABEL.KEY_ITEMS == "OBJETS RARES", "POCKET_LABEL reads sPocketNames[1] through the catalog when read")
else
  print("[skip] POCKET_LABEL reads ROM pocket names: " .. tostring(require("tests.game3_cache").reason))
end

-- Map section names live in src/import/gba/map_sections_extract.lua; the
-- popup translates the name and words the floor through Strings().
if require("tests.game3_cache").mount() then
  Strings.load({ strings = { ["LAVENDER TOWN"] = "LAVANVILLE", ["3F"] = "2E" } })
  local MapNamePopup = require("src.ui.game3.map_name_popup")
  MapNamePopup.dismiss()
  MapNamePopup.show({ regionMapSectionId = 92, floorNum = 3, showMapName = 1 })
  check(MapNamePopup._name == "LAVANVILLE 2E", "the map name popup translates the place and its floor")
  MapNamePopup.dismiss()
else
  print("[skip] map name popup reads ROM map section names: " .. tostring(require("tests.game3_cache").reason))
end

if require("tests.game3_cache").mount() then
  Strings.load({ strings = { ["DEL. ALL"] = "TOUT EFF.", ["CANCEL"] = "RETOUR" } })
  local EasyChat = require("src.ui.game3.easy_chat")
  local footer, xs = EasyChat.footerLabels()
  check(footer[1] == "TOUT EFF." and footer[2] == "RETOUR" and footer[3] == "OK",
    "the easy chat footer translates each gText_DelAllCancelOk piece when read")
  check(xs[2] == 0x57 and xs[3] == 0xA4, "and keeps the ROM's CLEAR_TO columns")
else
  print("[skip] easy chat footer reads gText_DelAllCancelOk: " .. tostring(require("tests.game3_cache").reason))
end

Strings.load({})

print(("game3_strings_module_tables_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
if failed > 0 then os.exit(1) end
