-- engine/tilesets/timeofday_pals.asm:65-91
-- data/maps/setup_scripts.asm:124-139

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle return fade")
local check, eq = S.check, S.eq

local World = require("src.world.gen2.World")

local function rowEq(row, a, b, c, d, label)
  check(row ~= nil, label .. " (row exists)")
  if not row then return end
  check(row[1] == a and row[2] == b and row[3] == c and row[4] == d,
    label .. " (" .. row[1] .. row[2] .. row[3] .. row[4] .. ")")
end

rowEq(World.fadeRampRow("white", 0.25), 3, 2, 1, 0,
  "the first white step is the identity row")
rowEq(World.fadeRampRow("white", 0.5), 2, 1, 0, 0,
  "the second collapses one gradation")
rowEq(World.fadeRampRow("white", 0.75), 1, 0, 0, 0,
  "the third another")
rowEq(World.fadeRampRow("white", 1), 0, 0, 0, 0,
  "the fourth is solid white")
rowEq(World.fadeRampRow("black", 1), 3, 3, 3, 3,
  "the black ramp ends solid black")
rowEq(World.fadeRampRow("white", 0), 3, 2, 1, 0,
  "a floor of one keeps level 0 on the identity row")
rowEq(World.fadeRampRow("white", 2), 0, 0, 0, 0,
  "and a cap of four keeps an overshoot on white")
eq(World.fadeRampRow("outWhite", 1), nil, "an unknown kind quantizes to nothing")
eq(World.fadeRampRow(nil, 1), nil, "and so does no fade at all")

eq(World.fadeRampByte({ 3, 2, 1, 0 }), 0xe4, "identity packs to $e4")
eq(World.fadeRampByte({ 0, 0, 0, 0 }), 0x00, "white packs to $00")
eq(World.fadeRampByte({ 3, 3, 3, 3 }), 0xff, "black packs to $ff")

local w = {}
World.battleReturnFade(w)
check(w.mapSetup ~= nil, "the battle exit arms a map setup chain")
eq(w.mapSetup.phase, "in", "the chain is the fade-in half only")
eq(w.mapSetup.step, 4, "four steps up")
eq(w.fade, "white", "under a full white sheet")
eq(w.fadeLevel, 1, "at full strength")
check(World.busy(w), "and the world is busy for its whole run")

local armed = { mapSetup = { phase = "out", step = 2, wait = 1 } }
World.battleReturnFade(armed)
eq(armed.mapSetup.phase, "out",
  "a chain already running is left alone")
eq(armed.fade, nil, "and its sheet untouched")

local ticks, white = 0, 0
while w.mapSetup and ticks < 64 do
  if w.fadeLevel == 1 then white = white + 1 end
  World.updateMapSetup(w)
  ticks = ticks + 1
end
eq(World.MAP_LOAD_WHITE_FRAMES, 4, "the LCD-off map load is held as four white frames")
eq(white, World.MAP_LOAD_WHITE_FRAMES + World.FADE_STEP_FRAMES,
  "white holds for the load plus FadeInFromWhite's first row")
eq(ticks, 8 + World.MAP_LOAD_WHITE_FRAMES,
  "the fade in runs four steps of two frames after the hold")
eq(w.mapSetup, nil, "then the chain ends")
eq(w.fade, nil, "with nothing left over the world")
check(not World.busy(w), "and control back")

-- data/maps/setup_scripts.asm:102-125
local door = { mapSetup = { phase = "out", step = 0, wait = 2,
  load = function() return true end } }
local levels, whiteRun = {}, 0
ticks = 0
while door.mapSetup and ticks < 64 do
  World.updateMapSetup(door)
  ticks = ticks + 1
  levels[#levels + 1] = door.fadeLevel or 0
  if door.mapSetup and door.fadeLevel == 1 then whiteRun = whiteRun + 1 end
end
eq(whiteRun, World.FADE_STEP_FRAMES + World.MAP_LOAD_WHITE_FRAMES
  + World.FADE_STEP_FRAMES, "a door holds white: last out row, load, first in row")
eq(ticks, 8 + (2 * World.FADE_STEP_FRAMES + World.MAP_LOAD_WHITE_FRAMES)
  + 3 * World.FADE_STEP_FRAMES, "out ramp, hold, in ramp")
eq(levels[World.FADE_STEP_FRAMES], 0.25, "the out ramp opens on the identity row")
eq(levels[#levels], 0, "and the in ramp closes on nothing")

S.finish()
