-- Test game3 TrainerCard and SaveMenu mechanics and state flows.

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print("[ok] " .. name)
  else
    print("[FAIL] " .. name .. ": " .. tostring(err))
    error(err)
  end
end

print("[test] 1. Trainer Card lifecycle and fields")
local TrainerCard = require("src.ui.game3.trainer_card")

local session = {
  name = "RED",
  id = 12345,
  money = 3500,
  dex = { caught = { [1] = true, [4] = true, [7] = true } },
  playTimeHours = 2,
  playTimeMinutes = 45,
  badges = { true, true, false, false, false, false, false, false },
  -- sessions carry the engine's map id; the save screen resolves the place name
  -- from it (see tests/engine/save_menu_location_bug2328.lua)
  map = "FR_PALLET_TOWN",
}

local closed = false
TrainerCard.show({
  session = session,
  onClose = function() closed = true end,
})

test("TrainerCard is open", function()
  assert(TrainerCard.isOpen() == true, "TrainerCard should be open")
end)

TrainerCard.close()

test("TrainerCard closed callback called", function()
  assert(TrainerCard.isOpen() == false, "TrainerCard should be closed")
  assert(closed == true, "onClose should have been called")
end)

test("TrainerCard front and back flip", function()
  TrainerCard.show({ session = session })
  assert(TrainerCard.isOpen() == true, "Should be open")
  assert(TrainerCard.side == "front", "Initial side should be front")

  -- Press A to flip to back
  local inpA = { wasPressed = function(_, k) return k == "a" end }
  TrainerCard.handleInput(inpA)
  assert(TrainerCard.side == "back", "Side should flip to back")

  -- Press A again to flip to front
  TrainerCard.handleInput(inpA)
  assert(TrainerCard.side == "front", "Side should flip back to front")

  -- Press B to close
  local inpB = { wasPressed = function(_, k) return k == "b" end }
  TrainerCard.handleInput(inpB)
  assert(TrainerCard.isOpen() == false, "Should be closed after B")
end)

print("[test] 2. SaveMenu lifecycle and state machine")
local SaveMenu = require("src.ui.game3.save_menu")

local saveClosed = false
SaveMenu.show({
  session = session,
  onClose = function() saveClosed = true end,
})

test("SaveMenu starts in confirm phase", function()
  assert(SaveMenu.isOpen() == true, "SaveMenu should be open")
  assert(SaveMenu._phase == "confirm", "Initial phase should be confirm")
  assert(SaveMenu.cursor == 1, "Cursor should start on YES (1)")
end)

test("SaveMenu cursor movement", function()
  SaveMenu.move(1)
  assert(SaveMenu.cursor == 2, "Cursor should flip to NO (2)")
  SaveMenu.move(1)
  assert(SaveMenu.cursor == 1, "Cursor should flip back to YES (1)")
end)

test("SaveMenu confirm transitions to overwrite then saved", function()
  SaveMenu.confirm()
  assert(SaveMenu._phase == "overwrite", "Selecting YES in confirm should transition to overwrite")
  SaveMenu.confirm()
  assert(SaveMenu._phase == "saved", "Selecting YES in overwrite should transition to saved")
  SaveMenu.confirm()
  assert(SaveMenu.isOpen() == false, "Confirm in saved phase should close menu")
  assert(saveClosed == true, "Save onClose callback should be called")
end)

print("[test] 3. SaveMenu cancellation")
test("SaveMenu cancellation", function()
  local noClosed = false
  SaveMenu.show({
    session = session,
    onClose = function() noClosed = true end,
  })
  SaveMenu.move(1) -- Move to NO
  SaveMenu.confirm() -- Press A on NO
  assert(SaveMenu.isOpen() == false, "Selecting NO should close SaveMenu")
  assert(noClosed == true, "onClose should be called on cancel")
end)

print("[test] 4. Trainer Card badge unlocking & multi-format resolution")
test("Badges from array format", function()
  local s = { badges = { true, true, true, false, false, false, false, false } }
  assert(TrainerCard.countBadges(s) == 3, "Should count 3 badges from array")
  assert(TrainerCard.isBadgeUnlocked(1) == false, "Default closed should be false")
  TrainerCard.show({ session = s })
  assert(TrainerCard.isBadgeUnlocked(1) == true, "Badge 1 unlocked")
  assert(TrainerCard.isBadgeUnlocked(2) == true, "Badge 2 unlocked")
  assert(TrainerCard.isBadgeUnlocked(3) == true, "Badge 3 unlocked")
  assert(TrainerCard.isBadgeUnlocked(4) == false, "Badge 4 locked")
  TrainerCard.close()
end)

test("Badges from FRLG flags format (0x820..0x827)", function()
  local s = {
    flags = {
      [0x820] = true, -- Boulder
      [0x821] = true, -- Cascade
      [0x823] = true, -- Rainbow
      [0x826] = true, -- Volcano
    }
  }
  assert(TrainerCard.countBadges(s) == 4, "Should count 4 badges from flags")
  TrainerCard.show({ session = s })
  assert(TrainerCard.isBadgeUnlocked(1) == true, "Boulder badge unlocked (0x820)")
  assert(TrainerCard.isBadgeUnlocked(2) == true, "Cascade badge unlocked (0x821)")
  assert(TrainerCard.isBadgeUnlocked(3) == false, "Thunder badge locked (0x822)")
  assert(TrainerCard.isBadgeUnlocked(4) == true, "Rainbow badge unlocked (0x823)")
  assert(TrainerCard.isBadgeUnlocked(7) == true, "Volcano badge unlocked (0x826)")
  assert(TrainerCard.isBadgeUnlocked(8) == false, "Earth badge locked (0x827)")
  TrainerCard.close()
end)

test("Badges from scripting store flags", function()
  local s = {
    store = {
      flags = {
        ["FLAG_BADGE01_GET"] = true,
        ["FLAG_BADGE03_GET"] = true,
        ["FLAG_BADGE05_GET"] = true,
      }
    }
  }
  assert(TrainerCard.countBadges(s) == 3, "Should count 3 badges from store.flags")
  TrainerCard.show({ session = s })
  assert(TrainerCard.isBadgeUnlocked(1) == true, "Badge 1 (Boulder)")
  assert(TrainerCard.isBadgeUnlocked(3) == true, "Badge 3 (Thunder)")
  assert(TrainerCard.isBadgeUnlocked(5) == true, "Badge 5 (Soul)")
  assert(TrainerCard.isBadgeUnlocked(2) == false, "Badge 2 (Cascade)")
  TrainerCard.close()
end)

test("Badges from bitmask format (0xFF = all 8 badges)", function()
  local s = { badges = 0xFF }
  assert(TrainerCard.countBadges(s) == 8, "Should count 8 badges from 0xFF bitmask")
  TrainerCard.show({ session = s })
  for i = 1, 8 do
    assert(TrainerCard.isBadgeUnlocked(i) == true, "Badge " .. i .. " unlocked")
  end
  TrainerCard.close()
end)

print("[test] 5. Currency glyph mapping and font measure")
test("Currency sign maps to Pokédollar 0xB7", function()
  local FrlgFont = require("src.ui.game3.frlg_font")
  assert(FrlgFont.glyphId("$") == 0xB7, "$ must map to Pokédollar glyph 0xB7")
  assert(FrlgFont.glyphId("¥") == 0xB7, "¥ must map to Pokédollar glyph 0xB7")
  assert(FrlgFont.glyphId("\xC2\xA5") == 0xB7, "UTF-8 yen must map to Pokédollar glyph 0xB7")
  local w1 = FrlgFont.measure("$3000")
  local w2 = FrlgFont.measure("¥3000")
  assert(w1 == w2, "Width of $3000 and ¥3000 must match")
  assert(w1 > 0, "Width must be positive")
end)

print("[test] 6. Runtime playtime accumulation and synchronization")
test("Runtime.pumpRtc increments and synchronizes playtime", function()
  local Runtime = require("src.core.game3.runtime")
  local sess = {
    playtime = { hours = 1, minutes = 59, seconds = 58, vblanks = 0 }
  }
  local game = { session = sess, save = {} }
  Runtime.session = sess
  Runtime._playTimeAcc = 0

  -- Tick 2 seconds (120 frames at 1/60s)
  for _ = 1, 120 do
    Runtime.pumpRtc(game, 1 / 60)
  end

  assert(sess.playTimeHours == 2, "Hours should roll over to 2 (was " .. tostring(sess.playTimeHours) .. ")")
  assert(sess.playTimeMinutes == 0, "Minutes should roll over to 0 (was " .. tostring(sess.playTimeMinutes) .. ")")
  assert(sess.playTimeSeconds == 0, "Seconds should roll over to 0 (was " .. tostring(sess.playTimeSeconds) .. ")")
  assert(game.save.playTimeHours == 2, "Save hours should synchronize to 2")
  assert(game.save.playTimeMinutes == 0, "Save minutes should synchronize to 0")
end)

print("[test] 7. SaveMenu location header resolution from ROM mapsec")
test("SaveMenu location resolution does not print engine internal map IDs", function()
  local MapSectionsExtract = require("src.import.gba.map_sections_extract")
  local tests = {
    { map = "FR_ROUTE_22", want = "ROUTE 22" },
    { map = "FR_PALLET_TOWN", want = "PALLET TOWN" },
    { map = "FR_VIRIDIAN_CITY", want = "VIRIDIAN CITY" },
    { map = "FR_CELADON_CITY_DEPARTMENT_STORE_2F", want = "CELADON DEPT." },
    { map = "FR_POKEMON_TOWER_3F", want = "POKéMON TOWER" },
    { map = "FR_ROUTE_1", want = "ROUTE 1" },
  }

  for _, item in ipairs(tests) do
    local place = MapSectionsExtract.getPlaceName(item.map)
    assert(place == item.want, string.format("Expected %s for map %s, got %s", item.want, item.map, tostring(place)))
  end
end)

print("[test] all passed")
