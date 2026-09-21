-- Unit tests for game3 multichoice resolution, grid layout, and navigation
package.path = "./?.lua;./src/?.lua;" .. package.path

local Multi = require("src.core.game3.scripting.multichoice")
local Choice = require("src.ui.game3.choice")

local passed = 0
local failed = 0

local function assert_eq(actual, expected, msg)
  if actual == expected then
    passed = passed + 1
  else
    failed = failed + 1
    print(string.format("FAIL: %s (expected %s, got %s)", tostring(msg), tostring(expected), tostring(actual)))
  end
end

-- 1. Test Multichoice.resolve for list 15 (Trainer School Whiteboard)
local Cache = require("tests.game3_cache")
local labels15 = { "SLP", "PSN", "PAR", "BRN", "FRZ", "EXIT" }
local root = Cache.root("scripts/multichoice.lua")
if root then
  require("src.import.gba.extract_island1").CACHE_ROOT = root
  Multi.LISTS = {}
  Multi.tryLoadCache()
  labels15 = Multi.resolve(15, 6)
  assert_eq(#labels15, 6, "List 15 has 6 labels")
  assert_eq(labels15[1], "SLP", "List 15 item 1 is SLP")
  assert_eq(labels15[2], "PSN", "List 15 item 2 is PSN")
  assert_eq(labels15[3], "PAR", "List 15 item 3 is PAR")
  assert_eq(labels15[4], "BRN", "List 15 item 4 is BRN")
  assert_eq(labels15[5], "FRZ", "List 15 item 5 is FRZ")
  assert_eq(labels15[6], "EXIT", "List 15 item 6 is EXIT")

  -- 2. Test Multichoice.resolve for list 0 (YES/NO)
  local labels0 = Multi.resolve(0, 2)
  assert_eq(#labels0, 2, "List 0 has 2 labels")
  assert_eq(labels0[1], "YES", "List 0 item 1 is YES")
  assert_eq(labels0[2], "NO", "List 0 item 2 is NO")
else
  print("[skip] imported list labels: " .. tostring(Cache.reason))
end

-- 3. Test Choice module 2D Grid navigation (3 columns, 2 rows)
local result = nil
Choice.multi(labels15, 0, function(sel)
  result = sel
end, { cols = 3, left = 7, top = 1 })

assert_eq(Choice.active, true, "Choice is active")
assert_eq(Choice.cursor, 1, "Cursor starts at 1 (SLP)")

-- Move Right: 1 -> 2 (PSN)
Choice.move(0, 1)
assert_eq(Choice.cursor, 2, "Move Right -> PSN (2)")

-- Move Right: 2 -> 3 (PAR)
Choice.move(0, 1)
assert_eq(Choice.cursor, 3, "Move Right -> PAR (3)")

-- Move Right: 3 wraps to 1 (SLP) in column space
Choice.move(0, 1)
assert_eq(Choice.cursor, 1, "Move Right wraps -> SLP (1)")

-- Move Down: 1 -> 4 (BRN)
Choice.move(1, 0)
assert_eq(Choice.cursor, 4, "Move Down -> BRN (4)")

-- Move Right: 4 -> 5 (FRZ)
Choice.move(0, 1)
assert_eq(Choice.cursor, 5, "Move Right -> FRZ (5)")

-- Move Right: 5 -> 6 (EXIT)
Choice.move(0, 1)
assert_eq(Choice.cursor, 6, "Move Right -> EXIT (6)")

-- Move Down: 6 -> 3 (PAR) (row wraps)
Choice.move(1, 0)
assert_eq(Choice.cursor, 3, "Move Down wraps row -> PAR (3)")

-- Move Up: 3 -> 6 (EXIT) (row wraps back)
Choice.move(-1, 0)
assert_eq(Choice.cursor, 6, "Move Up wraps row back -> EXIT (6)")

-- Confirm selection of EXIT (index 6 -> result 5)
Choice.confirm()
assert_eq(Choice.active, false, "Choice is no longer active after confirm")
assert_eq(result, 5, "Result is 5 for EXIT")

-- 4. Test Choice cancel (B press returns 127)
local cancelResult = nil
Choice.multi(labels15, 0, function(sel)
  cancelResult = sel
end, { cols = 3 })
Choice.cancel()
assert_eq(cancelResult, 127, "Cancel returns 127")

-- 5. Test ignoreBPress
local ignoreResult = nil
Choice.multi(labels15, 0, function(sel)
  ignoreResult = sel
end, { cols = 3, ignoreBPress = true })
Choice.cancel()
assert_eq(Choice.active, true, "Choice remains active when ignoreBPress is true")
Choice.confirm()
assert_eq(ignoreResult, 0, "Confirm picked item 0")

print(string.format("Multichoice Grid Tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
