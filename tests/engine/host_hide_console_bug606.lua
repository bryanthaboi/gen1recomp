-- #606: on Windows every shelled-out host tool (curl, the PowerShell ROM
-- picker, the update downloader) flashed its own cmd.exe console window,
-- because a GUI-subsystem process has no console for the child to inherit.
-- HostShell.hideHostConsole claims one hidden console at boot so the children
-- inherit it silently.  The Windows half needs Windows; what this tier can pin
-- is that the helper is a harmless memoized no-op everywhere else, and that
-- main.lua actually calls it (an unwired helper fixes nothing).
--   luajit tests/engine/host_hide_console_bug606.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local HostShell = require("src.core.HostShell")

check(type(HostShell.hideHostConsole) == "function",
      "HostShell exposes hideHostConsole (#606)")

local ok, hidden = pcall(HostShell.hideHostConsole)
check(ok, "hideHostConsole never throws")
eq(hidden, false, "non-Windows hosts allocate no console")
eq(select(2, pcall(HostShell.hideHostConsole)), false,
   "the answer is memoized, so repeat calls stay a no-op")

local f = assert(io.open("main.lua", "r"))
local src = f:read("*a")
f:close()
check(src:find("hideHostConsole", 1, true) ~= nil,
      "love.load wires the console suppression up at boot (#606)")

T.finish("host_hide_console_bug606")
