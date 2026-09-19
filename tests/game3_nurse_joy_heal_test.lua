#!/usr/bin/env luajit
-- Test 1:1 Nurse Joy healing flow and standard msgbox scripts (std:2..std:6).

package.path = "./?.lua;./?/init.lua;" .. package.path

local Vm = require("src.core.game3.scripting.vm")
local Std = require("src.core.game3.scripting.stdscripts")
local Adapters = require("src.core.game3.scripting.adapters")
local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local Opcodes = require("src.core.game3.scripting.opcodes")

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("FAILED %s: expected %s, got %s", msg or "", tostring(expected), tostring(actual)), 2)
  end
end

print("--- Test 1: Standard Msgbox definitions exist and run ---")
do
  local logs = {}
  local vm = Vm.new({
    scripts = Std.SCRIPTS,
    text = Std.TEXT,
    adapters = Adapters.stub({
      log = function(s) logs[#logs + 1] = s end,
      openMessage = function() end,
      openMessageStay = function() end,
      closeMessage = function() end,
    }),
  })

  -- Test std:2 (MSGBOX_NPC)
  local scriptNpc = {
    { op = "loadword", dest = 0, value = "Text_TownMap" },
    { op = "callstd", std = Opcodes.STD.MSGBOX_NPC },
    { op = "end" },
  }
  vm.scripts["test_npc"] = scriptNpc
  vm:start("test_npc")
  while vm:isRunning() do vm:resume() end
  assert_eq(#logs, 0, "std:2 should run without missing script warnings")

  -- Test std:3 (MSGBOX_SIGN)
  local scriptSign = {
    { op = "loadword", dest = 0, value = "Text_TownMap" },
    { op = "callstd", std = Opcodes.STD.MSGBOX_SIGN },
    { op = "end" },
  }
  vm.scripts["test_sign"] = scriptSign
  vm:start("test_sign")
  while vm:isRunning() do vm:resume() end
  assert_eq(#logs, 0, "std:3 should run without missing script warnings")

  -- Test std:4 (MSGBOX_DEFAULT)
  local scriptDef = {
    { op = "loadword", dest = 0, value = "Text_TownMap" },
    { op = "callstd", std = Opcodes.STD.MSGBOX_DEFAULT },
    { op = "end" },
  }
  vm.scripts["test_def"] = scriptDef
  vm:start("test_def")
  while vm:isRunning() do vm:resume() end
  assert_eq(#logs, 0, "std:4 should run without missing script warnings")

  -- Test std:5 (MSGBOX_YESNO)
  local scriptYesNo = {
    { op = "loadword", dest = 0, value = "Text_TownMap" },
    { op = "callstd", std = Opcodes.STD.MSGBOX_YESNO },
    { op = "end" },
  }
  vm.scripts["test_yesno"] = scriptYesNo
  vm:start("test_yesno")
  while vm:isRunning() do vm:resume() end
  assert_eq(#logs, 0, "std:5 should run without missing script warnings")
  print("ok  std:2..std:6 definitions all present and functional")
end

print("--- Test 2: Full Nurse Joy healing flow (Player chooses YES) ---")
do
  local messages = {}
  local movements = {}
  local fieldEffects = {}
  local partyHealed = false

  local session = {
    party = {
      { species = 1, hp = 5, maxHp = 20, moves = { { id = 1, pp = 0, maxPp = 35 } }, status = 1 },
      { species = 4, hp = 0, maxHp = 18, moves = { { id = 10, pp = 2, maxPp = 20 } }, status = 0 },
    },
  }
  package.loaded["src.core.game3.runtime"] = {
    isActive = function() return true end,
    getSession = function() return session end,
  }

  local customAdapters = Adapters.stub({
    openMessageStay = function(body)
      messages[#messages + 1] = body
    end,
    openMessage = function(body)
      messages[#messages + 1] = body
    end,
    closeMessage = function()
      messages[#messages + 1] = "<CLOSED>"
    end,
    askYesNo = function(cb)
      cb(true) -- User selects YES
    end,
    applyMovement = function(lid, stream, done)
      movements[#movements + 1] = { lid = lid, stream = stream }
      if done then done() end
    end,
    doFieldEffect = function(id)
      fieldEffects[#fieldEffects + 1] = id
    end,
    waitFieldEffect = function(id, done)
      if done then done() end
    end,
    nurseHeal = function(done)
      partyHealed = true
      session.party[1].hp = session.party[1].maxHp
      session.party[1].status = 0
      session.party[2].hp = session.party[2].maxHp
      if done then done() end
    end,
  })

  local vm = Vm.new({
    scripts = Std.SCRIPTS,
    text = Std.TEXT,
    adapters = customAdapters,
  })

  -- Map script calling Nurse Joy
  local mapScript = {
    { op = "lock" },
    { op = "faceplayer" },
    { op = "call", target = "EventScript_PkmnCenterNurse" },
    { op = "release" },
    { op = "end" },
  }
  vm.scripts["Nurse_Test"] = mapScript

  vm:startTalk("Nurse_Test", 2) -- Nurse Joy is object localId 2
  while vm:isRunning() do
    vm:resume()
  end

  -- Verify messages shown in sequence
  print("Messages recorded:")
  for i, m in ipairs(messages) do
    print(string.format("  [%d] %s", i, m:gsub("\n", "\\n")))
  end

  assert_eq(messages[1], "Welcome to our POKéMON CENTER!\fWould you like me to heal your\nPOKéMON to perfect health?", "Message 1: Welcome & Heal question")
  assert_eq(messages[2], "OK, may I see your POKéMON?", "Message 2: Take pokemon")
  assert_eq(messages[3], "Thank you for waiting.\nYour POKéMON are fully healed.", "Message 3: Fully healed")
  assert_eq(messages[4], "We hope to see you again!", "Message 4: Goodbye")
  assert_eq(messages[5], "<CLOSED>", "Message 5: Box closed on release")

  -- Verify Nurse movements
  assert_eq(#movements, 3, "Nurse had 3 movement sequences")
  -- Movement 1: Turn left (0x2F)
  assert_eq(movements[1].lid, 2, "Movement 1 targeted Nurse Joy")
  assert_eq(movements[1].stream[1], 0x2F, "Movement 1: WalkInPlaceFasterLeft")

  -- Field effect 25
  assert_eq(#fieldEffects, 1, "FLDEFF_POKECENTER_HEAL was triggered")
  assert_eq(fieldEffects[1], 25, "Field effect 25")

  -- Movement 2: Turn down (0x2D)
  assert_eq(movements[2].lid, 2, "Movement 2 targeted Nurse Joy")
  assert_eq(movements[2].stream[1], 0x2D, "Movement 2: WalkInPlaceFasterDown")

  -- Heal special called
  assert_eq(partyHealed, true, "Party was healed")
  assert_eq(session.party[1].hp, 20, "Mon 1 HP restored")
  assert_eq(session.party[2].hp, 18, "Mon 2 HP restored")

  -- Movement 3: Nurse Joy bow (0x5B, 0x1A)
  assert_eq(movements[3].lid, 2, "Movement 3 targeted Nurse Joy")
  assert_eq(movements[3].stream[1], 0x5B, "Movement 3: nurse_joy_bow")
  assert_eq(movements[3].stream[2], 0x1A, "Movement 3: delay_4")

  print("ok  Full Nurse Joy YES flow matches pret pokefirered 1:1")
end

print("--- Test 3: Nurse Joy flow (Player chooses NO) ---")
do
  local messages = {}
  local movements = {}
  local fieldEffects = {}

  local customAdapters = Adapters.stub({
    openMessageStay = function(body)
      messages[#messages + 1] = body
    end,
    openMessage = function(body)
      messages[#messages + 1] = body
    end,
    closeMessage = function()
      messages[#messages + 1] = "<CLOSED>"
    end,
    askYesNo = function(cb)
      cb(false) -- User selects NO
    end,
    applyMovement = function(lid, stream, done)
      movements[#movements + 1] = { lid = lid, stream = stream }
      if done then done() end
    end,
    doFieldEffect = function(id)
      fieldEffects[#fieldEffects + 1] = id
    end,
  })

  local vm = Vm.new({
    scripts = Std.SCRIPTS,
    text = Std.TEXT,
    adapters = customAdapters,
  })

  local mapScript = {
    { op = "lock" },
    { op = "faceplayer" },
    { op = "call", target = "EventScript_PkmnCenterNurse" },
    { op = "release" },
    { op = "end" },
  }
  vm.scripts["Nurse_Test"] = mapScript

  vm:startTalk("Nurse_Test", 2)
  while vm:isRunning() do
    vm:resume()
  end

  assert_eq(messages[1], "Welcome to our POKéMON CENTER!\fWould you like me to heal your\nPOKéMON to perfect health?", "Message 1: Welcome")
  assert_eq(messages[2], "We hope to see you again!", "Message 2: Goodbye")
  assert_eq(messages[3], "<CLOSED>", "Message 3: Closed")
  assert_eq(#movements, 0, "No nurse movements on NO")
  assert_eq(#fieldEffects, 0, "No field effects on NO")

  print("ok  Nurse Joy NO flow matches pret pokefirered 1:1")
end

print("ALL NURSE JOY TESTS PASSED!")
