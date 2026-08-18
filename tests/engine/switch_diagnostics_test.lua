-- Opt-in Switch input diagnostics (SWNX-13/28): marker file, ring buffer, flush cap.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local SwitchDiagnostics = require("src.debug.SwitchDiagnostics")

local function reset()
  SwitchDiagnostics._resetForTests()
  love.filesystem.remove("switch-debug.txt")
  love.filesystem.remove("switch.log")
end

reset()
check(not SwitchDiagnostics.isEnabled(), "disabled without marker file")

love.filesystem.write("switch-debug.txt", "")
reset()
love.filesystem.write("switch-debug.txt", "")
check(SwitchDiagnostics.isEnabled(), "enabled when marker exists")

SwitchDiagnostics.onEvent("probe", { kind = "gamepadpressed", button = "a" })
SwitchDiagnostics.maybeFlush(true, 0)
local log = love.filesystem.read("switch.log") or ""
check(log:find("gamepadpressed", 1, true) ~= nil, "flush writes buffered events")
check(log:find("gitCommit=", 1, true) ~= nil, "identity includes gitCommit field")
check(log:find("loveNxTag=", 1, true) ~= nil, "identity includes loveNxTag field")

-- ROM-like byte sequences must never appear in diagnostics output.
local romSnippet = string.char(0xEA, 0x9B, 0xCA, 0xE6)
SwitchDiagnostics.onEvent("probe", { sample = romSnippet, note = "redacted" })
SwitchDiagnostics.maybeFlush(true, 1)
log = love.filesystem.read("switch.log") or ""
check(not log:find(romSnippet, 1, true),
  "ROM bytes are stripped from diagnostic payloads")

-- Flush rate capped at 1 Hz unless forced.
reset()
love.filesystem.write("switch-debug.txt", "")
SwitchDiagnostics.onEvent("tick", { n = 1 })
SwitchDiagnostics.maybeFlush(true, 0.0)
SwitchDiagnostics.onEvent("tick", { n = 2 })
SwitchDiagnostics.maybeFlush(false, 0.5)
local logMid = love.filesystem.read("switch.log") or ""
SwitchDiagnostics.maybeFlush(false, 1.0)
local logLate = love.filesystem.read("switch.log") or ""
check(not logMid:find("n=2", 1, true), "flush waits until 1s elapsed")
check(logLate:find("n=2", 1, true) ~= nil, "flush includes events after 1s")

-- Lua error log: redacted, no ROM bytes.
local romErr = string.char(0xEA, 0x9B, 0xCA, 0xE6)
local hint = SwitchDiagnostics.logLuaError("probe failure")
check(type(hint) == "string" and hint:find("lua-error.log", 1, true) ~= nil,
  "error handler hint mentions lua-error.log")
SwitchDiagnostics.logLuaError(romErr)
local errLog = love.filesystem.read("lua-error.log") or ""
check(errLog:find("probe failure", 1, true) ~= nil, "lua-error.log records message")
check(errLog:find("<redacted>", 1, true) ~= nil, "lua-error.log strips ROM bytes")
check(not errLog:find(romErr, 1, true), "lua-error.log omits raw ROM bytes")

-- Stack-trace style messages (newlines) must remain readable — not wholesale
-- "<redacted>" (fused Play triage regression).
SwitchDiagnostics.logLuaError("missing module 'data/generated/maps.lua'.\nImport again.\n(detail)")
errLog = love.filesystem.read("lua-error.log") or ""
check(errLog:find("missing module", 1, true) ~= nil,
  "lua-error.log keeps printable multiline error text")
check(errLog:find("Import again", 1, true) ~= nil,
  "lua-error.log preserves lines after newline")

-- NX asset probe: always writes nx-asset-probe.log on Play (Switch only).
local Platform = require("src.core.Platform")
local GameVersion = require("src.core.GameVersion")
local savedSystem = love.system
love.system = { getOS = function() return "NX" end }
Platform._resetForTests()
GameVersion.set("yellow")
love.filesystem.write("yellow/assets/generated/fonts/font.png", "font-bytes")
love.filesystem.write("yellow/assets/generated/tilesets/reds_house.png", "house-bytes")
love.filesystem.write("yellow/assets/generated/sprites/red.png", "red-bytes")
SwitchDiagnostics.probeAssets("yellow")
local probe = love.filesystem.read("nx-asset-probe.log") or ""
check(probe:find("probe=nx-asset", 1, true) ~= nil, "probe log writes header")
check(probe:find("cachePrefix=yellow/", 1, true) ~= nil, "probe records yellow prefix")
check(probe:find("resolve=yellow/assets/generated/fonts/font.png", 1, true) ~= nil
  or probe:find("versioned=type=file", 1, true) ~= nil,
  "probe records versioned font path visibility")
check(not probe:find(string.char(0xEA, 0x9B), 1, true),
  "probe log contains no ROM-like binary")
check(probe:find("data/generated/maps.lua", 1, true) ~= nil,
  "probe records Gold/Gen2 maps.lua visibility")
check(probe:find("loadActive=", 1, true) ~= nil,
  "probe uses loadActive for generated Lua instead of newImage")

-- Gold maps.lua / gold/ folders: fused NX intro/naming/overworld crash.
GameVersion.set("gold")
love.filesystem.write("gold/data/generated/maps.lua", "return { NEW_BARK_TOWN = true }")
love.filesystem.write("gold/data/generated/oak_speech.lua", "return {}")
SwitchDiagnostics.probeAssets("gold")
probe = love.filesystem.read("nx-asset-probe.log") or ""
check(probe:find("cachePrefix=gold/", 1, true) ~= nil, "probe records gold prefix")
check(probe:find("data/generated/maps.lua", 1, true) ~= nil,
  "probe lists maps.lua (the Gold cache incomplete path)")
check(probe:find("list gold", 1, true) ~= nil, "probe lists gold/ folder")
check(probe:find("list gold/data/generated", 1, true) ~= nil,
  "probe lists gold/data/generated/")

love.system = { getOS = function() return "OS X" end }
Platform._resetForTests()
love.filesystem.remove("nx-asset-probe.log")
SwitchDiagnostics.probeAssets("yellow")
check(love.filesystem.read("nx-asset-probe.log") == nil,
  "probe is a no-op off NX")

love.system = savedSystem
Platform._resetForTests()
GameVersion.set("red")
love.filesystem.remove("nx-asset-probe.log")
love.filesystem.remove("yellow/assets/generated/fonts/font.png")
love.filesystem.remove("yellow/assets/generated/tilesets/reds_house.png")
love.filesystem.remove("yellow/assets/generated/sprites/red.png")
love.filesystem.remove("gold/data/generated/maps.lua")
love.filesystem.remove("gold/data/generated/oak_speech.lua")

T.finish()
