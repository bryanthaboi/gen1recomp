#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_battle_win_text_test")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")

local function party()
  return { { species = 6, level = 60, hp = 200, maxHp = 200, moves = { 53 }, pp = { 15 }, maxPp = { 15 } } }
end

local function run(opts)
  if Battle.isActive() then Battle.abort("win") end
  local ok = Battle.start(opts)
  local res = Battle.runToEnd()
  local log = {}
  for i, t in ipairs(Ui.log() or {}) do log[i] = t end
  return ok, res, log
end

local function find(log, needle)
  for i, t in ipairs(log) do
    if t:find(needle, 1, true) then return i end
  end
  return nil
end

print("[test] 1. wild win prints nothing after EXP")
local ok, res, log = run({ wild = true, headless = true, playerParty = party(), foe = { species = 16, level = 2 } })
check(ok and res == "win", "wild battle won")
check(find(log, "won the battle") == nil, "no 'You won the battle!' line")
check(log[#log] ~= nil and log[#log]:find("EXP. Points", 1, true) ~= nil, "last wild line is the EXP line")

print("[test] 2. trainer win: defeated before lose text")
if not require("tests.game3_cache").mount() then
  print("[skip] trainer 326 comes from the ROM trainer pack: " .. tostring(require("tests.game3_cache").reason))
  if failed > 0 then os.exit(1) end
  print("[PASS] game3 battle win text")
  os.exit(0)
end
ok, res, log = run({ wild = false, headless = true, trainerId = 326, playerParty = party(), foe = { species = 7, level = 5, trainerId = 326 } })
check(ok and res == "win", "trainer battle won")
local iDef = find(log, "defeated\n")
local iLose = find(log, "I picked the wrong")
check(iDef ~= nil, "defeated line present")
check(iLose ~= nil, "lose text present")
check(iDef and iLose and iDef < iLose, "defeated line precedes lose text")
check(find(log, "won the battle") == nil, "no 'You won the battle!' in trainer log")

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[PASS] game3 battle win text")
