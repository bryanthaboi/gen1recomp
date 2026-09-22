-- An unresolved region-map section must not be presented as PALLET TOWN.
--
-- Regression: dataset.lua defaulted a map's regionMapSectionId to 88
-- ("... or 88") and took getInfo's echoed secId, and getInfo returns the
-- Pallet Town record with secId 88 for anything it cannot identify.  Because 88
-- IS a valid section, `resolved` came back true and the map name popup showed
-- "PALLET TOWN" for maps it had never identified -- and the preview/Fly gates
-- treated the fake section as real.
--
-- The popup must fall back to the cleaned map id when the section is
-- unresolved, and the dataset must stop fabricating section 88.
--   luajit tests/engine/game3_map_section_unresolved_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local MapSectionsExtract = require("src.import.gba.map_sections_extract")
local MapNamePopup = require("src.ui.game3.map_name_popup")

-- The mechanism: 88 is a real section, so echoing it reads as "resolved".
local pallet = MapSectionsExtract.getInfo(88, "FR_ANYTHING", 0)
check(pallet.resolved == true, "section 88 resolves, so faking it hides an unknown map")
eq(pallet.name, "PALLET TOWN", "section 88 is Pallet Town")

-- An id nobody extracted does not resolve (getInfo still echoes the placeholder).
local unknown = MapSectionsExtract.getInfo(nil, "FR_TESTMAP", 0)
check(unknown.resolved == false, "an unknown map id does not resolve")

-- The popup must show the cleaned map id, not the placeholder place name.
MapNamePopup.dismiss()
MapNamePopup.show({ id = "FR_TESTMAP", showMapName = 1 }, { force = true })
check(MapNamePopup._name ~= "PALLET TOWN",
  "an unresolved map is not labelled PALLET TOWN (got " .. tostring(MapNamePopup._name) .. ")")
eq(MapNamePopup._name, "TESTMAP", "it falls back to the cleaned map id")

-- A resolved map still shows its real place name.
MapNamePopup.dismiss()
MapNamePopup.show({ id = "FR_PALLET_TOWN", regionMapSectionId = 88, showMapName = 1 },
  { force = true })
eq(MapNamePopup._name, "PALLET TOWN", "a resolved map still shows its place name")

-- Static guard on the root cause: dataset must not default the section to 88.
do
  local f = io.open("src/core/game3/dataset.lua", "r")
  check(f ~= nil, "dataset.lua is readable")
  if f then
    local src = f:read("*a")
    f:close()
    check(not src:find("regionMapSectionId or 88", 1, true),
      "dataset.lua does not fabricate regionMapSectionId 88")
  end
end

T.finish("game3_map_section_unresolved_test")
