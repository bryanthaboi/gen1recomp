-- Select+face display chord digit map (NXMOD-06..09).
-- Spec: Nintendo UX A/B → keys 2/3; Y/X/L → 5/6/7. Map-only (Select held is Game's job).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check = T.check
local eq = T.eq

local GamepadMap = require("src.core.GamepadMap")

-- Desktop / default: SDL face labels map identity for A/B chords.
GamepadMap._setForceNXForTests(false)
eq(GamepadMap.displayChordDigit("a"), "2", "desktop SDL a (GB A) -> key 2")
eq(GamepadMap.displayChordDigit("b"), "3", "desktop SDL b (GB B) -> key 3")
eq(GamepadMap.displayChordDigit("y"), "5", "Y -> key 5")
eq(GamepadMap.displayChordDigit("x"), "6", "X -> key 6")
eq(GamepadMap.displayChordDigit("leftshoulder"), "7", "leftshoulder (L) -> key 7")

-- Unmapped buttons yield nil (no accidental digit).
eq(GamepadMap.displayChordDigit("start"), nil, "start is not a display chord")
eq(GamepadMap.displayChordDigit("back"), nil, "back/Select alone is not a digit")
eq(GamepadMap.displayChordDigit("dpup"), nil, "d-pad is not a display chord")
eq(GamepadMap.displayChordDigit("rightshoulder"), nil, "R is not a display chord")
eq(GamepadMap.displayChordDigit(nil), nil, "nil button -> nil")

-- NX Nintendo UX: GamepadMap swaps SDL a/b so physical A/B match docs.
-- Physical Nintendo A arrives as SDL "b" → GB a → key "2".
-- Physical Nintendo B arrives as SDL "a" → GB b → key "3".
GamepadMap._setForceNXForTests(true)
eq(GamepadMap.mapGamepadButton("b"), "a", "precondition: NX SDL east -> GB A")
eq(GamepadMap.mapGamepadButton("a"), "b", "precondition: NX SDL south -> GB B")
eq(GamepadMap.displayChordDigit("b"), "2",
  "NX physical A (SDL b / GB a) -> key 2")
eq(GamepadMap.displayChordDigit("a"), "3",
  "NX physical B (SDL a / GB b) -> key 3")
-- Y/X/L unchanged under NX face swap.
eq(GamepadMap.displayChordDigit("y"), "5", "NX Y -> key 5")
eq(GamepadMap.displayChordDigit("x"), "6", "NX X -> key 6")
eq(GamepadMap.displayChordDigit("leftshoulder"), "7", "NX L -> key 7")
GamepadMap._setForceNXForTests(false)

-- Edge: map alone never invents a digit for non-chord faces (NXMOD-09 map half)
for _, btn in ipairs({ "guide", "leftstick", "rightstick", "lefttrigger" }) do
  eq(GamepadMap.displayChordDigit(btn), nil,
    "edge: unmapped " .. btn .. " is not a display digit")
end

T.finish()
