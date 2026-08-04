-- ORIENTATION lock (#592, #716): the option model.
--
-- The Android side (SDL hint parsing, GameActivity's *_SENSOR -> *_USER
-- remap) can only be exercised on a device; what this tier pins down is the
-- Lua contract every UI row leans on: the mode set, normalization of stale
-- or garbage saves, the cycle order in both directions, and that apply() is
-- a safe no-op anywhere that is not Android -- including here, where love
-- is a headless stub and no SDL library is loaded.
--   luajit tests/engine/orientation_option.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Orientation = require("src.core.Orientation")

local realOS = love.system and love.system.getOS
love.system = love.system or {}

-- ------------------------------------------------------------- normalize

T.eq(Orientation.DEFAULT, "auto", "AUTO is the default")
T.eq(Orientation.normalize(nil), "auto", "missing option reads as AUTO")
T.eq(Orientation.normalize("sideways"), "auto", "garbage reads as AUTO")
T.eq(Orientation.normalize("portrait"), "portrait", "valid modes pass through")
T.eq(Orientation.normalize("reverseLandscape"), "reverseLandscape",
  "reverse landscape is a real mode")

-- ------------------------------------------------------------------ cycle

T.eq(Orientation.cycle("auto", 1), "portrait", "cycle forward from AUTO")
T.eq(Orientation.cycle("reverseLandscape", 1), "auto", "cycle wraps forward")
T.eq(Orientation.cycle("auto", -1), "reverseLandscape", "cycle wraps back")
T.eq(Orientation.cycle(nil, 1), "portrait", "cycling a fresh save starts at AUTO")

-- one full lap forward touches every mode exactly once
local seen, mode = {}, "auto"
for _ = 1, #Orientation.MODES do
  seen[mode] = true
  mode = Orientation.cycle(mode, 1)
end
T.eq(mode, "auto", "a full lap returns to the start")
for _, m in ipairs(Orientation.MODES) do
  T.eq(seen[m], true, "lap visits " .. m)
end

-- ----------------------------------------------------------------- labels

for _, m in ipairs(Orientation.MODES) do
  T.eq(type(Orientation.modeLabel(m)), "string", m .. " has a label")
  T.eq(#Orientation.modeLabel(m) <= 17, true,
    m .. "'s label fits the OPTION box value line (17 cells at x=24)")
end

-- -------------------------------------------------- apply() stays harmless

love.system.getOS = function() return "OS X" end
T.eq(Orientation.apply("portrait"), false, "desktop apply is a refused no-op")
love.system.getOS = function() return "iOS" end
T.eq(Orientation.apply("portrait"), false, "iOS defers to the Info.plist")
-- Android posed but no SDL loaded in this process: the FFI path must fail
-- closed inside its pcall, never throw.
love.system.getOS = function() return "Android" end
local ok, err = pcall(Orientation.applyOptions, { orientation = "landscape" })
T.eq(ok, true, "posed-Android apply never raises (" .. tostring(err) .. ")")

love.system.getOS = realOS
