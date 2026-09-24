package.path = "./?.lua;./?/init.lua;" .. package.path

local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Schema = require("src.core.game3.save_schema_firered")
local Hud = require("src.ui.game3.hud")
local Events = require("src.core.game3.scripting.natives_events")

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function signVm(session)
  package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
  local ctx = {
    session = session,
    flags = session.flags,
    vars = session.vars,
    stringVars = session.stringVars,
    specialVars = session.specialVars,
  }
  local vm = {
    ctx = ctx,
    halted = false,
    adapters = { closeMessage = function() end },
    isRunning = function() return true end,
    halt = function(self, aborted) self.halted = aborted == true end,
  }
  Natives.special(ctx, Std.SPECIAL.SetWalkingIntoSignVars)
  ctx.messageOpen = true
  ctx.specialVars[0x800C] = 2
  return vm
end

local function dirInput(key)
  return {
    wasPressed = function(_, k) return k == key end,
    isDown = function(_, k) return k == key end,
  }
end

print("=== walking away from a sign drops the waitbuttonpress wait ===")
do
  local vm = signVm(Schema.newGame({ name = "RED" }))
  local fired = 0
  Hud.armWaitButton(function() fired = fired + 1 end)
  check(Hud.busy() == true, "the armed waitbuttonpress keeps the HUD busy")
  for _ = 1, 7 do Events.pollWalkaway(vm, dirInput("down")) end
  check(vm.halted == true, "DOWN cancels the sign script")
  check(Hud._waitButton == nil, "the HUD wait is cleared with the script context")
  check(Hud.busy() == false, "field input is free right after the cancel")
  check(fired == 0, "the stale wait callback never runs")
end

print("=== START cancel drops the wait too ===")
do
  local vm = signVm(Schema.newGame({ name = "RED" }))
  package.loaded["src.core.game3.runtime"].defer = function() return true end
  Hud.armWaitButton(function() end)
  for _ = 1, 6 do Events.pollWalkaway(vm, dirInput("up")) end
  Events.pollWalkaway(vm, dirInput("start"))
  check(vm.halted == true, "START cancels the sign script")
  check(Hud._waitButton == nil, "START cancel clears the HUD wait")
end

print("=== a blocked walkaway leaves the wait armed ===")
do
  local vm = signVm(Schema.newGame({ name = "RED" }))
  Hud.armWaitButton(function() end)
  for _ = 1, 7 do Events.pollWalkaway(vm, dirInput("up")) end
  check(vm.halted == false, "pushing the facing direction does not cancel")
  check(Hud._waitButton ~= nil, "the wait stays armed for A/B")
  Hud.clearWaitButton()
end

print(string.format("\nTotal: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
