-- src/scrcmd.c:1274-1280, src/scrcmd.c:1285-1289, src/new_menu_helpers.c:701-705, src/new_menu_helpers.c:707-710

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Ops = require("src.core.game3.scripting.ops_a")
local Opcodes = require("src.core.game3.scripting.opcodes")
local TextIR = require("src.core.game3.scripting.text_ir")
local HelpWindow = require("src.ui.game3.help_window")

local store = Flags.newStore()
local function vm(texts)
  local c = Ctx.new({})
  c.mode, c.status = "bytecode", "running"
  return {
    ctx = c,
    store = store,
    adapters = { log = function() end },
    setPc = function() end,
    texts = texts or {},
    getText = function(self, key)
      local s = self.texts[key]
      return s and TextIR.fromAscii(s)
    end,
  }
end

HelpWindow.close()
local v = vm({ [Opcodes.key(0xABC)] = "Some HELP text." })
eq(Ops.dispatch(v, { op = "loadhelp", [1] = 0xABC }), false, "loadhelp does not yield")
eq(HelpWindow.isOpen(), true, "the help message window is open")
eq(HelpWindow.getText(), "Some HELP text.", "the resolved text reached the window")

eq(Ops.dispatch(v, { op = "unloadhelp" }), false, "unloadhelp does not yield")
eq(HelpWindow.isOpen(), false, "the window closed")
eq(Ops.dispatch(v, { op = "unloadhelp" }), false, "unloadhelp with no window is a no-op")
eq(HelpWindow.isOpen(), false, "still closed")

v.ctx.data = v.ctx.data or {}
v.ctx.data[0] = "T_FALLBACK"
local v2 = vm()
v2.ctx.data = { [0] = "T_FALLBACK" }
v2.texts = { T_FALLBACK = "Fallback text." }
local ok = pcall(Ops.dispatch, v2, { op = "loadhelp", [1] = 0 })
check(ok, "pointer 0 falls back through resolve_text without raising")
HelpWindow.close()

T.finish("game3_help_window_opcode_test")
