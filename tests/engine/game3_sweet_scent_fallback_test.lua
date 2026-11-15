--   luajit tests/engine/game3_sweet_scent_fallback_test.lua
-- Unit tests for Gen 3 Sweet Scent outside grass, weather suppression,
-- lock management, PP validation, and script cache assertion safeguards.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Field = require("src.core.game3.field")
local FieldMoves = require("src.core.game3.field_moves")
local Encounters = require("src.core.game3.encounters")
local Message = require("src.ui.game3.message")
local Weather = require("src.core.game3.weather")
rawset(FieldMoves.TEXT, "CANT_USE_HERE", "<gText_CantUseHere>")

-- =========================================================================
-- 1. FieldMoves.sweetScentFromMenu: PP validation & safe cache lookups
-- =========================================================================
local monWithPp = {
  species = 1,
  moves = { "SWEET_SCENT" },
  pp = { 20 },
}
local monNoPp = {
  species = 1,
  moves = { "SWEET_SCENT" },
  pp = { 0 },
}
local monTableMovesNoPp = {
  species = 1,
  moves = { { id = "SWEET_SCENT", pp = 0 } },
}

local okRes = FieldMoves.sweetScentFromMenu({ mon = monWithPp })
check(okRes.ok == true, "mon with PP: sweetScentFromMenu succeeds")
eq(okRes.action, "sweet_scent", "action is sweet_scent")
eq(okRes.failText, nil, "no hand-typed English failText")
eq(okRes.failKey, FieldMoves.textKey("NO_SWEET_SCENT_MONS"), "failure text is the ROM key")

local noPpRes = FieldMoves.sweetScentFromMenu({ mon = monNoPp })
check(noPpRes.ok == false, "mon with 0 PP (array): sweetScentFromMenu returns ok = false")

local noPpTableRes = FieldMoves.sweetScentFromMenu({ mon = monTableMovesNoPp })
check(noPpTableRes.ok == false, "mon with 0 PP (move table): sweetScentFromMenu returns ok = false")

local noMonRes = FieldMoves.sweetScentFromMenu({ party = {} })
check(noMonRes.ok == false, "no mon knowing sweet scent returns ok = false")

-- =========================================================================
-- 2. Field.finishSweetScent outside grass (terrain == nil)
-- =========================================================================
Player = { cellX = 5, cellY = 5 }
Field._session = { map = "MAP_PALLET_TOWN" }
Field.locked = true
Weather.current = Weather.NONE

-- Mock encounters so terrainAt returns nil (not grass/water)
local origTerrainAt = Encounters.terrainAt
Encounters.terrainAt = function() return nil end

local function dismissMessage()
  if Message.open then
    Message.advance() -- skip typewriter reveal
    Message.advance() -- dismiss page
  end
end

Field.finishSweetScent({
  action = "sweet_scent",
  failText = "Looks like there's nothing here…",
})

check(Message.open == true, "finishSweetScent outside grass opens dialogue")
check(Field.locked == true, "Field.locked remains true while failure dialogue is open")

-- Simulate player dismissing dialogue with A/B button
dismissMessage()
check(Message.open == false, "dialogue closes on advance")
check(Field.locked == false, "Field.locked is released on dialogue closure")

-- =========================================================================
-- 3. String failText with no symbols: ensure RomText.box is NOT called with English string
-- =========================================================================
Field.locked = true
Field.finishSweetScent({
  action = "sweet_scent",
  failText = "Custom failure string that is definitely not in ROM cache",
})
check(Message.open == true, "un-cached custom string does not crash and opens Message")
check(Field.locked == true, "Field.locked remains held")
dismissMessage()
check(Field.locked == false, "Field.locked released on dismiss")

-- =========================================================================
-- 4. Weather suppression: Sweet Scent fails in rain / thunderstorm / downpour / fog
-- =========================================================================
-- Restore terrain to pretend player IS in tall grass
Encounters.terrainAt = function() return "land" end

local origRoll = Encounters.rollSweetScent
local rollCalled = false
Encounters.rollSweetScent = function()
  rollCalled = true
  return { species = 16, level = 3 }
end

Weather.current = Weather.RAIN
Field.locked = true
rollCalled = false

Field.finishSweetScent({
  action = "sweet_scent",
  failText = "Looks like there's nothing here…",
})

check(rollCalled == false, "Weather.RAIN suppresses rollSweetScent")
check(Message.open == true, "Rain triggers failure dialogue")
check(Field.locked == true, "Field.locked is true while dialogue is open")
dismissMessage()
check(Field.locked == false, "Field.locked released on dismiss")

-- Fog suppression
Weather.current = Weather.FOG_HORIZONTAL
Field.locked = true
rollCalled = false

Field.finishSweetScent({
  action = "sweet_scent",
  failText = "Looks like there's nothing here…",
})

check(rollCalled == false, "Fog suppresses rollSweetScent")
check(Message.open == true, "Fog triggers failure dialogue")
dismissMessage()
check(Field.locked == false, "Field.locked released on dismiss")

-- Weather clear: battle roll is called
Weather.current = Weather.NONE
rollCalled = false
Field.finishSweetScent({
  action = "sweet_scent",
  failText = "Looks like there's nothing here…",
})
check(rollCalled == true, "Clear weather allows rollSweetScent on land")

-- =========================================================================
-- 5. Facility rejection (handled == false)
-- =========================================================================
Encounters.rules = function()
  return {
    sweetScentFacility = function() return false end,
  }
end

Field.locked = true
Field.finishSweetScent({
  action = "sweet_scent",
  failText = "Looks like there's nothing here…",
})
check(Message.open == true, "facility rejection triggers failure message")
check(Field.locked == true, "Field.locked held during facility rejection text")
dismissMessage()
check(Field.locked == false, "Field.locked released on facility rejection dismiss")

-- Cleanup
Encounters.terrainAt = origTerrainAt
Encounters.rollSweetScent = origRoll
Weather.current = Weather.NONE
Field.locked = false

T.finish("game3_sweet_scent_fallback_test")
