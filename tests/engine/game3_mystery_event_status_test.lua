-- src/scrcmd.c:269-273, src/mystery_event_script.c:92-95, src/mystery_event_script.c:75-80

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Ops = require("src.core.game3.scripting.ops_a")
local Std = require("src.core.game3.scripting.stdscripts")
local MysteryGift = require("src.core.game3.mystery_gift")

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

eq(Std.SPECIAL.setmysteryeventstatus or 0xE, 0xE, "opcode 0x0e is setmysteryeventstatus")
eq(MysteryGift.getStatus(), 0, "the slot starts at 0")

local v = vm()
eq(Ops.dispatch(v, { op = "setmysteryeventstatus", [1] = 2 }), false, "the op does not yield")
eq(v.ctx.mysteryEventStatus, 2, "the ctx slot carries the written value")
eq(MysteryGift.getStatus(), 2, "mystery_gift mirrors the value (setStatus/getStatus)")

Ops.dispatch(v, { op = "setmysteryeventstatus", [1] = 3 })
eq(MysteryGift.getStatus(), 3, "value 3 (pret SetIncompatible's status) round-trips")
eq(v.ctx.mysteryEventStatus, 3, "and the ctx copy agrees")

Ops.dispatch(v, { op = "setmysteryeventstatus", [1] = "bogus" })
eq(MysteryGift.getStatus(), 0, "non-numeric value normalises to 0")
eq(#logs, 0, "no log spam on the happy path")

T.finish("game3_mystery_event_status_test")
