-- src/scrcmd.c:92-97, src/script.c:70

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Ops = require("src.core.game3.scripting.ops_a")
local Natives = require("src.core.game3.scripting.natives")

local store = Flags.newStore()
local logs = {}
local function vm()
  return {
    ctx = (function() local c = Ctx.new({}); c.mode, c.status = "bytecode", "running"; return c end)(),
    store = store,
    adapters = { log = function(m) logs[#logs + 1] = m end },
    setPc = function() end,
  }
end

local v1 = vm()
eq(Ops.dispatch(v1, { op = "gotonative", [1] = 0x1234 }), false, "unmapped gotonative skips")
eq(#logs, 1, "the miss is logged once")
Ops.dispatch(v1, { op = "gotonative", [1] = 0x1234 })
eq(#logs, 1, "a repeated miss does not spam the log")

local calls = 0
Natives.NATIVE_SYMBOLS[0x100] = "test_native"
local saved = Natives.ALLOW["native:test_native"]
Natives.ALLOW["native:test_native"] = function(ctx)
  calls = calls + 1
  return true
end
local v2 = vm()
eq(Ops.dispatch(v2, { op = "gotonative", [1] = 0x100 }), true,
  "a registered symbol yields like a native that parks the script")
eq(calls, 1, "the registered handler ran exactly once")
Natives.ALLOW["native:test_native"] = saved
Natives.NATIVE_SYMBOLS[0x100] = nil

local calls2 = 0
Natives.ALLOW["native:0x77"] = nil
local saved2 = Natives.ALLOW["native:55"]
Natives.ALLOW["native:55"] = function() calls2 = calls2 + 1 return false end
local v3 = vm()
eq(Ops.dispatch(v3, { op = "gotonative", [1] = 55 }), false, "direct id registration resolves (no yield)")
eq(calls2, 1, "the direct handler ran")
Natives.ALLOW["native:55"] = saved2

T.finish("game3_gotonative_test")
