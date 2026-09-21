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

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Field = require("src.core.game3.field")
local FieldEffects = require("src.core.game3.field_effects")
local FieldMoves = require("src.core.game3.field_moves")
local Message = require("src.ui.game3.message")
local Extract = require("src.import.gba.extract_island1")

print("[test] 1. FLASH prints its line before the animation, not after")
-- pokefirered/src/fldeff_flash.c:177 FieldCallback_Flash
Message.close()
Field.locked = false
FieldEffects._anims = {}
local text = FieldMoves.TEXT.USED_FLASH:gsub("{STR_VAR_1}", "PIKACHU")
Field.executeFieldMove({ action = "flash", text = text })
check(Message.isOpen() == true, "the message box is open on the frame the move starts")
check(Field.locked == true, "and the field is locked for the animation")
local anims = #FieldEffects._anims
check(anims >= 1, "the flash animation is running, " .. anims .. " effects")

print("[test] 2. the animation clears the lock and adds no second message")
local closedOnce = false
local realClose = Message.close
Message.close = function(...)
  closedOnce = true
  return realClose(...)
end
for _ = 1, 40 do FieldEffects.step() end
Message.close = realClose
check(Field.locked == false, "the field unlocked when the animation finished")
check(closedOnce == false, "the message was not closed and reopened behind the animation")
check(Message.isOpen() == true, "it is still the same open message, waiting on the player")
Message.close()

print("[test] 3. a FLASH with no text still unlocks")
Field.locked = false
FieldEffects._anims = {}
Field.executeFieldMove({ action = "flash" })
check(Message.isOpen() == false, "no message box for a textless FLASH")
for _ = 1, 40 do FieldEffects.step() end
check(Field.locked == false, "and the field unlocked")

print("[test] 4. rock smash asks the encounter table directly")
-- pokefirered/src/wild_encounter.c:446
local Encounters = require("src.core.game3.encounters")
check(type(Encounters.rollRocks) == "function",
  "Encounters.rollRocks exists, so the old nil guard was dead code")

print("[test] 5. fly destinations fall back to the in-source table with no baked pack")
-- pokefirered/src/region_map.c:828 sMapFlyDestinations
local root = Extract.CACHE_ROOT or "data/generated/gba"
local emptyCache = { read = function() return nil end }
check(Field.loadFlyDestinations(emptyCache, root) == 0, "an empty cache bakes 0 rows")
local pallet = Field.flyDestination("MAPSEC_PALLET_TOWN")
check(pallet ~= nil and pallet.map == "FR_PALLET_TOWN" and pallet.x == 6 and pallet.y == 8,
  "MAPSEC_PALLET_TOWN still resolves from FLY_DESTINATIONS")

print("[test] 6. a baked region_map/fly_destinations.lua wins over the literal")
local baked = [[
return {
  fly_destinations = {
    MAPSEC_PALLET_TOWN = { map = "FR_PALLET_TOWN", x = 7, y = 9 },
    [90] = { map = "FR_PEWTER_CITY", x = 18, y = 27 },
  },
}
]]
local asked = {}
local cache = {
  read = function(_, rel)
    asked[#asked + 1] = rel
    if rel == root .. "/region_map/fly_destinations.lua" then return baked end
    return nil
  end,
}
check(Field.loadFlyDestinations(cache, root) == 2, "the pack installs 2 rows")
check(asked[1] == root .. "/region_map/fly_destinations.lua",
  "it read " .. tostring(asked[1]))
local baked1 = Field.flyDestination("MAPSEC_PALLET_TOWN")
check(baked1 ~= nil and baked1.x == 7 and baked1.y == 9,
  "the baked Pallet Town row wins, got "
  .. tostring(baked1 and baked1.x) .. "," .. tostring(baked1 and baked1.y))
local byNum = Field.flyDestination(90)
check(byNum ~= nil and byNum.map == "FR_PEWTER_CITY" and byNum.x == 18,
  "a numeric mapsec key resolves straight out of the pack")
local missing = Field.flyDestination("MAPSEC_CELADON_CITY")
check(missing ~= nil and missing.map == "FR_CELADON_CITY" and missing.x == 48,
  "a mapsec the pack leaves out still falls back to the literal")
check(Field.flyDestination("MAPSEC_NOT_A_PLACE") == nil, "an unknown mapsec is nil")
check(Field.flyDestination(nil) == nil, "and so is nil")

print("[test] 7. the numeric mapsec of a baked row goes through map_sections")
local okS, MapSections = pcall(require, "src.import.gba.map_sections_extract")
local palletNum
if okS and MapSections and MapSections.SECTIONS then
  for num, info in pairs(MapSections.SECTIONS) do
    if info and info.id == "MAPSEC_PALLET_TOWN" then palletNum = num end
  end
end
if palletNum then
  local byId = Field.flyDestination(palletNum)
  check(byId ~= nil and byId.x == 7 and byId.y == 9,
    "mapsec " .. palletNum .. " resolves to the baked Pallet Town row")
else
  check(false, "map_sections_extract knows MAPSEC_PALLET_TOWN")
end

Field.invalidateFlyDestinations()
done()
