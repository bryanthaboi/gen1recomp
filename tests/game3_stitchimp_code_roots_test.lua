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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

print("[test] 1. src/field_control_avatar.c:539,:573-577 behavior to script mapping")
local I = require("src.core.game3.scripting.interaction_scripts")
-- src/metatile_behavior.c:854,:864,:874,:1033
check(I.scriptFor(0xA3, "up") == "TrainerTower_EventScript_ShowTime", "MB_TRAINER_TOWER_MONITOR")
check(I.scriptFor(0xA3, "down") == "TrainerTower_EventScript_ShowTime", "MB_TRAINER_TOWER_MONITOR ignores facing")
check(I.scriptFor(0x8F, "left") == "EventScript_Questionnaire", "MB_QUESTIONNAIRE ignores facing")
check(I.scriptFor(0x8D, "up") == "CableClub_EventScript_ShowWirelessCommunicationScreen",
  "MB_CABLE_CLUB_WIRELESS_MONITOR facing north")
check(I.scriptFor(0x8D, "down") == nil, "MB_CABLE_CLUB_WIRELESS_MONITOR needs DIR_NORTH")
check(I.scriptFor(0x8E, "up") == "CableClub_EventScript_ShowBattleRecords", "MB_BATTLE_RECORDS facing north")
check(I.scriptFor(0x8E, "right") == nil, "MB_BATTLE_RECORDS needs DIR_NORTH")

print("[test] 2. the imported cache")
local Cache = require("tests.game3_cache")
local bundle = Cache.bundle("objects/pack.lua")
if not bundle then
  print("[skip] game3_stitchimp_code_roots_test cache checks: " .. tostring(Cache.reason))
  finish()
end

local Extract = require("src.import.gba.object_interactions_extract")
for _, row in ipairs(Extract.CODE_SLOTS) do
  if not bundle.scripts[row[2]] then
    print("[skip] game3_stitchimp_code_roots_test cache checks: this cache predates the "
      .. "object_interactions_extract code-root seeding (" .. row[2] .. " absent); reimport it")
    finish()
  end
end

local Vm = require("src.core.game3.scripting.vm")
local function run(name, answer)
  local messages = {}
  local vm = Vm.new({
    scripts = bundle.scripts, text = bundle.text, movements = bundle.movements,
    onMessage = function(text) messages[#messages + 1] = text end,
    askYesNo = function(cb) cb(answer == true) end,
  })
  if not vm:start(name) then return nil end
  for _ = 1, 200 do vm:tick() end
  return messages, vm:isRunning()
end

local CASES = {
  -- data/scripts/trainer_tower.inc:318
  { "TrainerTower_EventScript_ShowTime", 1, "sec." },
  -- data/scripts/cable_club.inc:1076,:511
  { "CableClub_EventScript_ShowWirelessCommunicationScreen", 1, "undergoing" },
  -- data/scripts/questionnaire.inc:1,:35
  { "EventScript_Questionnaire", 1, "questionnaire" },
  -- data/scripts/cable_club.inc:566
  { "CableClub_EventScript_ShowBattleRecords", 0 },
}
for _, case in ipairs(CASES) do
  local name, want, needle = case[1], case[2], case[3]
  check(bundle.scripts[name] ~= nil, name .. " seeded into the objects pack")
  local messages, running = run(name, false)
  if messages then
    check(#messages == want, string.format("%s shows %d message(s), got %d", name, want, #messages))
    check(running == false, name .. " releases control")
    if needle then
      check((table.concat(messages, " "):lower()):find(needle, 1, true) ~= nil,
        name .. " text contains " .. needle)
    end
  else
    check(false, name .. " did not start")
  end
end

finish()
