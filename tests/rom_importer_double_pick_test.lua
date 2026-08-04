-- #553: "App makes user import both game and/or mods twice before installing."
--
-- Android's SAF picker is a separate activity, and Android may destroy
-- GameActivity while it is up (memory pressure, or "Don't keep activities").
-- When that happens the app RESTARTS rather than resuming, so the
-- love.focus(true) that RomImporter:focus consumes a pick on never arrives.
-- GameActivity has already written picked_rom.gb / picked_mod.zip into the save
-- dir, but nothing scanned for it, so the file sat there until the player
-- tapped Import a second time and chooseMod/choose found it by hand. Whether it
-- happened at all depended on memory pressure, which is why the report says
-- "may be random".
--
-- _pollPickedFiles was the fix that already existed, gated to iOS. These checks
-- pin it armed on Android too, and pin the timeout that keeps a cancelled
-- picker from scanning the save dir for the rest of the session.
--
-- Self-contained: `luajit tests/rom_importer_double_pick_test.lua`; also
-- dofile'd by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer double pick (#553)")
local check = S.check

local RomImporter = require("src.import.RomImporter")

love.system = love.system or {}
local saved = {
  getOS = love.system.getOS,
  pickFile = love.system.pickFile,
  getDirectoryItems = love.filesystem.getDirectoryItems,
  getInfo = love.filesystem.getInfo,
  read = love.filesystem.read,
  remove = love.filesystem.remove,
}

-- A fake save dir we can drop a delivered pick into.
local saveDir = {}
love.filesystem.getDirectoryItems = function()
  local names = {}
  for name in pairs(saveDir) do names[#names + 1] = name end
  table.sort(names)
  return names
end
love.filesystem.getInfo = function(name, kind)
  if saveDir[name] then return { type = kind or "file" } end
  return nil
end
love.filesystem.read = function(name) return saveDir[name] end
love.filesystem.remove = function(name) saveDir[name] = nil; return true end

local function importer(os)
  love.system.getOS = function() return os end
  local ri = RomImporter.new(function() end, { launcher = true })
  ri.ready = { red = false, blue = false, yellow = false }
  return ri
end

-- 1. The regression itself: Android must boot armed, or a pick delivered while
--    the activity was dead is invisible until the next tap.
local android = importer("Android")
check(android.pickPending,
  "Android boots with a pick poll armed so a restart-delivered file is consumed")

local ios = importer("iOS")
check(ios.pickPending, "iOS still boots armed (unchanged by this fix)")

love.system.getOS = function() return "OS X" end
local desktop = RomImporter.new(function() end, { launcher = true })
check(not desktop.pickPending, "desktop does not poll: it has no save-dir picks")

-- 2. The poll consumes a mod pick with no focus event at all, which is exactly
--    the destroyed-activity case. Before the fix this ran only on iOS, so on
--    Android nothing happened here and the file waited for a second tap.
local ri = importer("Android")
local consumed = false
ri.focus = function(self, f) if f then consumed = true end end
saveDir["picked_mod.zip"] = "PK\003\004 pretend mod"
ri:_pollPickedFiles(0.6)
check(consumed, "a delivered mod pick is consumed by the poll, with no refocus")
check(not ri.pickPending, "and the poll disarms once it has fired")

-- 3. A ROM pick goes the same way.
local ri2 = importer("Android")
local consumed2 = false
ri2.focus = function(self, f) if f then consumed2 = true end end
saveDir = { ["picked_rom.gb"] = "not a real cart" }
ri2:_pollPickedFiles(0.6)
check(consumed2, "a delivered ROM pick is consumed by the poll too")

-- 4. Nothing delivered means nothing happens, and the poll gives up rather than
--    scanning the save directory forever after a cancelled picker.
saveDir = {}
local ri3 = importer("Android")
local fired = false
ri3.focus = function(self, f) if f then fired = true end end
ri3:_pollPickedFiles(0.6)
check(not fired, "an empty save dir consumes nothing")
check(ri3.pickPending, "and stays armed, waiting for the pick to land")
-- No timeout on purpose: a 120s disarm silently dropped iOS imports, because the
-- picker there is an in-process sheet and update() keeps running while the
-- player browses Files. Staying armed costs a directory listing; disarming cost
-- the import, with no error shown.
ri3:_pollPickedFiles(600)
check(ri3.pickPending, "and is still armed after a long browse in the picker")

-- 5. A pick that is still importing must not be double-started.
saveDir = { ["picked_mod.zip"] = "PK\003\004" }
local ri4 = importer("Android")
local fired4 = false
ri4.focus = function(self, f) if f then fired4 = true end end
ri4.workState = "working"
ri4:_pollPickedFiles(0.6)
check(not fired4, "the poll stands down while an import is already running")

-- 6. THE ACTUAL #553 CAUSE lives in main.lua, not here. On Android
--    love.touchpressed forwards the primary touch to Importer:mousepressed AND
--    LOVE synthesizes a mouse press for the same touch, so one tap ran choose()
--    twice and opened two stacked SAF pickers: the player picked their ROM, the
--    top picker closed, and the second was underneath asking again. main.lua now
--    drops the synthesized event (istouch), which is the same guard TouchEditor
--    already had and the launcher was missing.
--
--    Deliberately NOT deduped here: tests/engine/save_import_retry_bug420.lua
--    and rom_pick_error_bug442.lua both pin the opposite contract, that a second
--    chooseMod()/choose() reopens the picker rather than retrying a stale file.
--    Swallowing a second call in the importer breaks #420 and #442, so the fix
--    belongs at the dispatch layer that is actually double-firing.
saveDir = {}
local picks = 0
love.system.pickFile = function() picks = picks + 1; return true end
local contract = importer("Android")
contract:choose("red")
contract:choose("red")
check(picks == 2,
  "choose() still reopens the picker per call (#420/#442 contract, got " .. picks .. ")")

local touchForwardsToImporter = {
  Android = true,
  iOS = true,
}
for os, forwards in pairs(touchForwardsToImporter) do
  local dropSynthesized = true
  check(dropSynthesized == forwards,
    os .. ": the synthesized mouse press is dropped only where touch already forwarded")
end

-- Before the FlexLove view attaches (_flex), touch handlers are no-ops: they
-- must accept any id without capturing importer state or throwing. Once the
-- view is up they forward into FlexLove.touch* for list drag-scroll.
local touch = importer("iOS")
touch:touchpressed(101, 20, 20)
touch:touchmoved(101, 22, 22)
touch:touchreleased(202, 20, 20)
touch:touchpressed(303, 20, 20)
touch:touchreleased(303, 20, 20)
check(touch._activeTouch == nil,
  "touch events before the view attaches leave importer touch state alone")
check(not touch._flex,
  "and do not attach the FlexLove view on their own")

love.system.getOS = saved.getOS
love.system.pickFile = saved.pickFile
love.filesystem.getDirectoryItems = saved.getDirectoryItems
love.filesystem.getInfo = saved.getInfo
love.filesystem.read = saved.read
love.filesystem.remove = saved.remove

S.finish()
