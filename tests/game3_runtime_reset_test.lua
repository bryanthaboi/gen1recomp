#!/usr/bin/env luajit
-- pokefirered/src/main.c:480

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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")
love = love or require("tests.love_stub")

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local Strings = require("src.core.Strings")
local Game3 = require("src.core.Game3")
local Choice = require("src.ui.game3.choice")
local Message = require("src.ui.game3.message")
local MoneyBox = require("src.ui.game3.money_box")
local CoinsBox = require("src.ui.game3.coins_box")
local ElevatorWindow = require("src.ui.game3.elevator_window")

local function openFieldScreens()
  Choice.multi({ "B1F", "B2F", "B4F", "EXIT" }, 1, function() end)
  Message.show(Strings("Which floor do you want?"))
  MoneyBox.show(19, 1, 3000)
  CoinsBox.show(0, 5, 1000)
  ElevatorWindow.show("B1F")
end

local function allClosed(label)
  check(not Choice.isOpen(), label .. ": the multichoice is gone")
  check(not Message.isOpen(), label .. ": the message window is gone")
  check(not MoneyBox.isVisible(), label .. ": the money box is gone")
  check(not CoinsBox.isVisible(), label .. ": the coins box is gone")
  check(not ElevatorWindow.isVisible(), label .. ": the elevator window is gone")
end

print("[test] 1. the field screens really are up before the reset")
openFieldScreens()
check(Choice.isOpen(), "a multichoice is on screen")
check(Message.isOpen(), "and so is its question")
check(MoneyBox.isVisible(), "the money box is showing")
check(CoinsBox.isVisible(), "the coins box is showing")
check(ElevatorWindow.isVisible(), "the elevator floor window is showing")

print("[test] 2. Game3:reset frees every one of them (main.c:480)")
local g = setmetatable({ phase = "field" }, { __index = Game3 })
local ok, err = pcall(Game3.reset, g)
check(ok, "Game3:reset ran: " .. tostring(err))
allClosed("after Game3:reset")

print("[test] 3. so does Game3:returnToTitle")
openFieldScreens()
check(Choice.isOpen() and MoneyBox.isVisible(), "the screens are up again")
local g2 = setmetatable({ phase = "field", options = {} }, { __index = Game3 })
local ok2, err2 = pcall(Game3.returnToTitle, g2)
check(ok2, "Game3:returnToTitle ran: " .. tostring(err2))
allClosed("after Game3:returnToTitle")

print("[test] 4. a reset does not fire the torn-down message's callback")
local fired = false
Message.show(Strings("Which floor do you want?"), function() fired = true end)
check(Message.isOpen(), "the message is up with a continuation")
local g3 = setmetatable({ phase = "field" }, { __index = Game3 })
pcall(Game3.reset, g3)
check(not Message.isOpen(), "the reset tore it down")
eq(fired, false, "and the continuation never ran")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
os.exit(0)
