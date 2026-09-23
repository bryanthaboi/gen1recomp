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
local Trainers = require("src.core.game3.scripting.trainers")
local ItemsData = require("src.core.game3.items_data")

Trainers._pack = { trainers = {} } -- no ROM pack: use the built-in fallbacks

Strings.load({ strings = {
  ["Not enough HP!"] = "Pas assez de PV!",
  ["RIVAL: Yeah!\nAm I great or what?"] = "RIVAL: Ouais!\nJe suis trop fort!",
  ["KEY ITEMS"] = "OBJETS RARES",
} })

check(FieldMoves.TEXT.NOT_ENOUGH_HP == "Pas assez de PV!",
  "FieldMoves.TEXT translates when read")
check(FieldMoves.TEXT.NOT_A_KEY == nil, "FieldMoves.TEXT has no entry for an unknown key")

local rival = Trainers.get(326)
check(rival and rival.dialogs.victory == "RIVAL: Ouais!\nJe suis trop fort!",
  "fallback rival dialogs are translated when the trainer is built")
check(rival and rival.dialogs.defeat == "WHAT?\nUnbelievable!\n\nI picked the wrong POKéMON!",
  "an untranslated fallback dialog stays in English")

check(ItemsData.POCKET_LABEL.KEY_ITEMS == "KEY ITEMS", "POCKET_LABEL keeps the English source")
check(Strings(ItemsData.POCKET_LABEL.KEY_ITEMS) == "OBJETS RARES", "POCKET_LABEL translates at the caller")

-- Map section names live in src/import/gba/map_sections_extract.lua; the
-- popup translates the name and words the floor through Strings().
Strings.load({ strings = { ["LAVENDER TOWN"] = "LAVANVILLE", ["3F"] = "2E" } })
local MapNamePopup = require("src.ui.game3.map_name_popup")
MapNamePopup.dismiss()
MapNamePopup.show({ regionMapSectionId = 92, floorNum = 3, showMapName = 1 })
check(MapNamePopup._name == "LAVANVILLE 2E", "the map name popup translates the place and its floor")
MapNamePopup.dismiss()

-- easy_chat's footer buttons are the same shape: a module-level table read
-- once per frame by the draw loop.
Strings.load({ strings = { ["DEL. ALL"] = "TOUT EFF.", ["CANCEL"] = "RETOUR" } })
local EasyChat = require("src.ui.game3.easy_chat")
local footer = EasyChat.FOOTER_BTNS
check(footer ~= nil and footer[1].label == "DEL. ALL",
  "the easy chat footer keeps the English source")
check(footer ~= nil and Strings(footer[1].label) == "TOUT EFF.",
  "and translates at the caller")
check(footer ~= nil and Strings(footer[2].label) == "RETOUR",
  "for every button in the table")

Strings.load({})

print(("game3_strings_module_tables_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
if failed > 0 then os.exit(1) end
