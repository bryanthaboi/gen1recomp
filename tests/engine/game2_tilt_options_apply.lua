package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local Tilt = require("src.render.Tilt")
local Performance = require("src.core.Performance")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")

local tiltRow
for _, row in ipairs(OptionsMenu.ROWS) do
  if row.key == "tilt" then tiltRow = row break end
end
check(tiltRow ~= nil and tiltRow.cycle ~= nil and tiltRow.text ~= nil,
  "Gen 2 OPTIONS has a TILT row with cycle and text")

local function applyThenClamp(options)
  Tilt.applyOptions(options)
  local caps = Performance.applyOptions(options)
  if not caps.tilt then Tilt.setLevel(0) end
  for _ = 1, 20 do Tilt.update(0.05) end
end

local realGetOS = love.system.getOS
local function stubOS(osName)
  love.system.getOS = function() return osName end
end
local function restoreOS()
  love.system.getOS = realGetOS
end

do
  Tilt.reset()
  local options = { performance = "balanced", tilt = 3 }
  applyThenClamp(options)
  eq(options.tilt, 3, "apply-then-clamp leaves the saved tilt value")
  check(not Tilt.active(), "balanced apply-then-clamp leaves Tilt inactive")
  eq(tiltRow.text(options), "OFF",
    "TILT text is OFF while live tilt is clamped")
end

do
  Tilt.reset()
  local options = { performance = "balanced", tilt = 3 }
  applyThenClamp(options)
  eq(tiltRow.text(options), "OFF",
    "saved 50 + balanced still shows OFF before first right")
  tiltRow.cycle(options, 1)
  eq(options.tilt, 1, "first right from displayed OFF (saved 50) steps to 15")
  applyThenClamp(options)
  eq(Performance.resolve(options.performance), "high",
    "saved 50 first right promotes PERFORMANCE")
  check(Tilt.active(), "saved 50 first right leaves Tilt live after apply")
end

do
  Tilt.reset()
  local options = { performance = "high", tilt = 2 }
  tiltRow.cycle(options, 1)
  eq(options.tilt, 3, "TILT cycle steps 35 to 50")
  applyThenClamp(options)
  eq(Performance.resolve(options.performance), "high",
    "TILT cycle promotes PERFORMANCE so applyOptions keeps tilt")
  check(Tilt.active(), "after OPTIONS cycle + apply-then-clamp, Tilt is live")
  eq(tiltRow.text(options), "50", "TILT text matches live 50 once the tier allows it")
end

do
  Tilt.reset()
  stubOS("Android")
  local options = { performance = "auto", tilt = 2 }
  eq(Performance.resolve(options.performance), "balanced",
    "Android AUTO resolves to balanced before the cycle")
  tiltRow.cycle(options, 1)
  applyThenClamp(options)
  eq(Performance.resolve(options.performance), "high",
    "Android AUTO + TILT cycle promotes to high")
  check(Tilt.active(), "Android AUTO + TILT cycle leaves Tilt live after apply")
  restoreOS()
end

Tilt.reset()
restoreOS()
T.finish("game2 tilt options apply")
