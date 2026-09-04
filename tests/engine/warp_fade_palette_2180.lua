-- (pokeyellow home/fade.asm:74-81, engine/gfx/palettes.asm:799)
--   luajit tests/engine/warp_fade_palette_2180.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("warp fade palette #2180")
local check, eq = S.check, S.eq

local Timing = require("src.core.Timing")
local Transition = require("src.render.Transition")
local PaletteFX = require("src.render.PaletteFX")

local noData = { data = { transitions = {} } }

-- home/fade.asm:49
do
  local fade = Transition.new(noData, nil, nil, true)
  fade.phase = "out"
  local want = { { 0, 0xE4 }, { 7, 0xE4 }, { 8, 0xF9 }, { 15, 0xF9 },
                 { 16, 0xFE }, { 23, 0xFE }, { 24, 0xFF }, { 31, 0xFF } }
  for _, w in ipairs(want) do
    fade.t = w[1]
    eq(fade:bgp(), w[2],
       ("black fade out frame %d writes its FadePal byte"):format(w[1]))
  end
end

-- home/fade.asm:24
do
  local fade = Transition.new(noData, nil, nil, false, { framesIn = 32 })
  fade.phase = "in"
  local want = { { 0, 0xFF }, { 8, 0xFE }, { 16, 0xF9 }, { 24, 0xE4 } }
  for _, w in ipairs(want) do
    fade.t = w[1]
    eq(fade:bgp(), w[2],
       ("black fade in frame %d writes its FadePal byte"):format(w[1]))
  end
end

-- pokeyellow home/fade.asm:29
do
  local out = Transition.new(noData, nil, nil, false, {
    color = { 1, 1, 1 },
    frames = Timing.FADE_OUT_TO_WHITE,
    framesIn = Timing.FADE_IN_FROM_WHITE,
  })
  out.phase = "out"
  local wantOut = { { 0, 0x90 }, { 8, 0x40 }, { 16, 0x00 }, { 23, 0x00 } }
  for _, w in ipairs(wantOut) do
    out.t = w[1]
    eq(out:bgp(), w[2],
       ("white fade out frame %d writes FadePal6..8"):format(w[1]))
  end
  out.phase = "in"
  local wantIn = { { 0, 0x40 }, { 8, 0x90 }, { 16, 0xE4 } }
  for _, w in ipairs(wantIn) do
    out.t = w[1]
    eq(out:bgp(), w[2],
       ("white fade in frame %d writes FadePal7..5"):format(w[1]))
  end
end

do
  eq(Transition.shadeMapFor(0xE4), nil, "FadePal4 is the identity, so no map")
  local m = Transition.shadeMapFor(0xF9)
  eq(m[0], 1, "FadePal3 shows colour 0 as colour 1")
  eq(m[1], 2, "FadePal3 shows colour 1 as colour 2")
  eq(m[2], 3, "FadePal3 shows colour 2 as colour 3")
  eq(m[3], 3, "FadePal3 shows colour 3 as colour 3")
  local m2 = Transition.shadeMapFor(0xFE)
  eq(m2[0], 2, "FadePal2 shows colour 0 as colour 2")
  eq(m2[3], 3, "FadePal2 shows colour 3 as colour 3")
end

do
  local PAL_ROUTE = { { 255, 255, 255 }, { 132, 255, 33 },
                      { 90, 189, 255 }, { 24, 24, 24 } }
  local stepped = PaletteFX.permute(PAL_ROUTE, Transition.shadeMapFor(0xF9))
  eq(stepped[1][1], 132, "FadePal3 turns the white sky lime green, not grey")
  eq(stepped[1][2], 255, "FadePal3's sky keeps the palette's own green")
  eq(stepped[2][3], 255, "FadePal3 turns the grass sky blue")
  local stepped2 = PaletteFX.permute(PAL_ROUTE, Transition.shadeMapFor(0xFE))
  eq(stepped2[1][3], 255, "FadePal2 turns the sky the palette's blue")
  eq(stepped2[4][1], 24, "FadePal1's floor is the palette's near-black")
end

do
  local painted = 0
  local savedRect = love.graphics.rectangle
  love.graphics.rectangle = function() painted = painted + 1 end
  local fade = Transition.new({ data = { transitions = {} } }, nil, nil, true)
  fade.phase = "out"
  fade.t = 16
  fade.paletteStepped = true
  fade:draw()
  eq(painted, 0, "a palette-stepped frame paints no veil")
  eq(fade.paletteStepped, false, "the flag clears so the veil can come back")
  fade:draw()
  eq(painted, 1, "an unconsumed frame falls back to the veil")
  love.graphics.rectangle = savedRect
end

S.finish()
