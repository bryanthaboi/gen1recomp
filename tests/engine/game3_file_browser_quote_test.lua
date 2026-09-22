-- The launcher file browser must not interpolate a path into a shell unescaped.
--
-- L3 regression: scanDirectory built
--   'ls -1ap "' .. dir:gsub('"', '\\"') .. '" 2>/dev/null'
-- so only a double quote was escaped.  A directory name containing $(...) or a
-- backtick executed as the user the moment it was entered in the ROM/mod picker.
-- HostShell.quote already escapes for the POSIX shell.
--   luajit tests/engine/game3_file_browser_quote_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local FileBrowser = require("src.ui.kit.FileBrowser")
local HostShell = require("src.core.HostShell")

-- 1. Injection: a directory named with a command substitution must not run.
-- The marker must not pre-exist (os.tmpname creates its file, so name it here).
local marker = "/tmp/gen1recomp-inject-" .. tostring(os.time())
  .. "-" .. tostring(math.random(1000000))
check(io.open(marker, "r") == nil, "the injection marker does not exist before the call")
local hostile = "/tmp/gen1recomp-inject-$(touch " .. marker .. ")-x"
FileBrowser.setDirectory(hostile)
local created = io.open(marker, "r")
if created then created:close(); os.remove(marker) end
check(created == nil,
  "a command substitution in a directory name is not executed by the file browser")

-- 2. Shape: the listing command single-quotes the path (HostShell's POSIX form).
local captured
local realPopen = io.popen
io.popen = function(cmd)
  captured = cmd
  return { read = function() return "" end, close = function() end }
end
FileBrowser.setDirectory("/tmp/it's $(here)")
io.popen = realPopen

check(type(captured) == "string", "the browser still lists through the shell")
if type(captured) == "string" then
  local quoted = HostShell.quote("/tmp/it's $(here)")
  check(captured:find(quoted, 1, true) ~= nil,
    "the directory is passed through HostShell.quote (" .. tostring(captured) .. ")")
  check(captured:find("$(here)", 1, true) == nil or captured:find(quoted, 1, true) ~= nil,
    "the raw path is not left unquoted")
end

T.finish("game3_file_browser_quote_test")
