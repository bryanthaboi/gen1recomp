-- pokefirered/src/save_menu_util.c:44
-- pokefirered/src/start_menu.c:966
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.ui.game3.stack"] = {
  push = function() end, pop = function() end,
  busy = function() return false end, drawOrder = function() return {} end,
}
package.loaded["src.ui.game3.window"] = {
  template = function(l, t, w, h)
    return { left = l, top = t, width = w, height = h }
  end,
  stdFrame = function() end,
  fixedStdFrame = function() end,
  cursorPx = function() end,
}
package.loaded["src.ui.game3.chrome"] = { dialogueFrame = function() end }

local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local SaveMenu = require("src.ui.game3.save_menu")
local FrlgFont = require("src.ui.game3.frlg_font")

local ROW_BADGES = 1 * 8 + 32
local ROW_DEX = 1 * 8 + 46
local ROW_TIME_LOW = 1 * 8 + 60
local LABEL_X = 1 * 8 + 4

local function drawn(session)
  local seen = {}
  local realDraw = FrlgFont.draw
  FrlgFont.draw = function(text, x, y)
    seen[#seen + 1] = { text = text, x = x, y = y }
    return 0
  end
  SaveMenu.open = true
  SaveMenu._phase = "confirm"
  SaveMenu._session = session
  local ok, err = pcall(SaveMenu.draw)
  SaveMenu.open = false
  FrlgFont.draw = realDraw
  check(ok, "save stats window draws: " .. tostring(err))
  return seen
end

local function valueAt(seen, y)
  for _, s in ipairs(seen) do
    if s.y == y and s.x ~= LABEL_X and s.x > LABEL_X then return s.text end
  end
end

local function labelRow(seen, label)
  for _, s in ipairs(seen) do
    if s.text == label and s.x == LABEL_X then return s.y end
  end
end

local function storeWith(ids)
  local store = Flags.newStore()
  for _, id in ipairs(ids) do Flags.setFlag(store, nil, id, true) end
  return store
end

Space.store = storeWith({ 0x820, 0x821 })
local session = { name = "RED", map = "FR_PALLET_TOWN", flags = Flags.serialize(Space.store).flags }
local seen = drawn(session)
eq(valueAt(seen, ROW_BADGES), "2", "two badge flags in the live store print BADGES 2")

Space.store = nil
seen = drawn({ name = "RED", map = "FR_PALLET_TOWN",
  flags = Flags.serialize(storeWith({ 0x820, 0x821, 0x822 })).flags })
eq(valueAt(seen, ROW_BADGES), "3", "session.flags string keys are counted")

seen = drawn({ name = "RED", map = "FR_PALLET_TOWN" })
eq(valueAt(seen, ROW_BADGES), "0", "no badge flags prints BADGES 0")

Space.store = storeWith({ 0x820, 0x821 })
seen = drawn({ name = "RED", map = "FR_PALLET_TOWN", flags = { ["2080"] = true } })
eq(valueAt(seen, ROW_BADGES), "2", "the live flag store wins over stale session.flags")
eq(SaveMenu.countBadges({}), 2, "SaveMenu.countBadges reads the live store")

Space.store = storeWith({ 0x820, 0x821, 0x822, 0x823, 0x824, 0x825, 0x826, 0x827 })
seen = drawn({ name = "RED", map = "FR_PALLET_TOWN" })
eq(valueAt(seen, ROW_BADGES), "8", "all eight badge flags print BADGES 8")

Space.store = storeWith({ 0x820 })
seen = drawn({ name = "RED", map = "FR_PALLET_TOWN", playTimeHours = 1, playTimeMinutes = 5 })
eq(labelRow(seen, "POKéDEX"), nil, "no POKéDEX row before FLAG_SYS_POKEDEX_GET")
eq(labelRow(seen, "TIME"), ROW_DEX, "TIME moves up to the POKéDEX row (y=42)")
eq(valueAt(seen, ROW_DEX), "1:05", "TIME value moves up with its label")

local dex = { seen = {}, caught = { [1] = true, [4] = true, [7] = true, [152] = true, [250] = true } }
Space.store = storeWith({ 0x820, 0x829 })
seen = drawn({ name = "RED", map = "FR_PALLET_TOWN", dex = dex })
eq(labelRow(seen, "POKéDEX"), ROW_DEX, "POKéDEX row drawn with FLAG_SYS_POKEDEX_GET")
eq(labelRow(seen, "TIME"), ROW_TIME_LOW, "TIME stays at y=56 under the POKéDEX row")
eq(valueAt(seen, ROW_DEX), "3", "Kanto dex count (<=151) before the National Dex")

Space.store = storeWith({ 0x820, 0x829, 0x840 })
Flags.setVar(Space.store, nil, 0x404E, 0x6258)
seen = drawn({ name = "RED", map = "FR_PALLET_TOWN", dex = dex })
eq(valueAt(seen, ROW_DEX), "5", "National dex count once the National Dex is enabled")

Space.store = nil
T.finish("save_menu_badges_bug2405")
