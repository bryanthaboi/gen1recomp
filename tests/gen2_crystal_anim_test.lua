-- Crystal's animated front pics: the bitmask decode and the frame sequencer.
--   luajit tests/gen2_crystal_anim_test.lua
--
-- ROM-free.  The fixtures are the shapes the extractor writes into
-- data/generated/pokemon.lua, with the numbers taken from BULBASAUR's own
-- bitmask/frames data so a failure names the bytes it disagrees with.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 crystal anim")
local check, eq = S.check, S.eq

local MonAnim = require("src.render.MonAnim")

-- ---- bitmask decode -------------------------------------------------------

-- ../pokecrystal/gfx/pokemon/bulbasaur/bitmask.asm bitmask 0 and frame 1:
-- %01100000 %10101101 %00000001 %00000000, then $19..$20.  The tool emits the
-- byte low bit first, so the eight set bits are tile positions 5, 6, 8, 10,
-- 11, 13, 15 and 16 in the pic's own column-major order.
local BULBASAUR = {
  tiles = 5,
  bitmasks = {
    { 0x60, 0xad, 0x01, 0x00 },
    { 0x20, 0xad, 0x01, 0x00 },
  },
  frames = {
    { bitmask = 1, tiles = { 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20 } },
    { bitmask = 2, tiles = { 0x21, 0x1b, 0x22, 0x1d, 0x1e, 0x23, 0x24 } },
  },
  play = { { 1, 10 }, { 2, 10 }, { 0, 5 } },
  idle = { { 2, 5 }, { 0, 5 } },
}

local base = MonAnim.tileMap(BULBASAUR, 0)
eq(base and #base, 25, "the base picture is 5x5 tiles")
eq(base and base[1], 0, "position 0 is tile 0")
eq(base and base[25], 24, "position 24 is tile 24")

local first = MonAnim.tileMap(BULBASAUR, 1)
eq(first and #first, 25, "frame 1 is still 5x5 tiles")
local REPLACED = { [6] = 0x19, [7] = 0x1a, [9] = 0x1b, [11] = 0x1c,
  [12] = 0x1d, [14] = 0x1e, [16] = 0x1f, [17] = 0x20 }
local wrong = nil
for slot = 1, 25 do
  local want = REPLACED[slot] or (slot - 1)
  if first[slot] ~= want then wrong = wrong or slot end
end
eq(wrong, nil, "frame 1 replaces exactly the eight bitmask-0 positions")

-- Bitmask 1 drops bit 6 and keeps bit 5, so frame 2 leaves position 6 alone.
local second = MonAnim.tileMap(BULBASAUR, 2)
eq(second and second[6], 0x21, "frame 2 replaces position 5")
eq(second and second[7], 6, "and leaves position 6 at its base tile")
eq(second and #BULBASAUR.frames[2].tiles, 7,
  "seven set bits, seven replacement tiles")

eq(MonAnim.tileMap({ frames = {}, bitmasks = {} }, 0), nil,
  "no pic size means no tile map")
eq(MonAnim.tileMap(BULBASAUR, 9), nil, "and a frame that does not exist is nil")

-- ---- durations ------------------------------------------------------------

-- PokeAnim_GetDuration: a * (1 + [wPokeAnimSpeed] / 16).
eq(MonAnim.duration(10, 0), 10, "speed 0 leaves a duration alone")
eq(MonAnim.duration(10, 4), 12, "ANIM_MON_SLOW's speed 4 stretches 10 to 12")
eq(MonAnim.duration(5, 4), 6, "and 5 to 6")
eq(MonAnim.duration(200, 4), 250, "the arithmetic stays inside a byte")

-- ---- the sequencer --------------------------------------------------------

-- setrepeat 2 / frame 1, 3 / frame 2, 2 / dorepeat 1 -- the shape most of
-- Crystal's entrance animations have (../pokecrystal/gfx/pokemon/abra/anim.asm).
local LOOPED = {
  tiles = 5, bitmasks = BULBASAUR.bitmasks, frames = BULBASAUR.frames,
  play = { { MonAnim.SETREPEAT, 2 }, { 1, 3 }, { 2, 2 }, { MonAnim.DOREPEAT, 1 } },
  idle = { { 2, 2 } },
}

local function timeline(data, scene, ticks)
  local anim = MonAnim.new(data, scene)
  local out = {}
  for _ = 1, ticks do
    anim:update()
    out[#out + 1] = anim:currentFrame()
  end
  return out, anim
end

local frames, anim = timeline(LOOPED, "battle", 14)
eq(table.concat(frames, ","), "0,1,1,1,2,2,1,1,1,2,2,2,0,0",
  "the looped script plays twice and lands back on the base picture")
check(anim:finished(), "and the scene is over after PokeAnim_Finish")

-- Setup costs a frame of its own before the script starts, so the first
-- animation frame is on tick 2, not tick 1.
eq(frames[1], 0, "PokeAnim_Setup shows the base picture for its own frame")

-- ANIM_MON_SLOW's speed 4 stretches every duration: 8 becomes 10.
local ONESHOT = {
  tiles = 5, bitmasks = BULBASAUR.bitmasks, frames = BULBASAUR.frames,
  play = { { 1, 8 } }, idle = { { 2, 2 } },
}
eq(table.concat(timeline(ONESHOT, "battle", 11), ","),
  "0,1,1,1,1,1,1,1,1,0,0", "speed 0 holds frame 1 for eight frames")
eq(table.concat(timeline(ONESHOT, "battleSlow", 13), ","),
  "0,1,1,1,1,1,1,1,1,1,1,0,0", "speed 4 holds it for ten")

-- ANIM_MON_MENU: the entrance animation, an 18-frame pause, then the idle.
local menu = MonAnim.new(ONESHOT, "menu")
local seen = {}
for tick = 1, 31 do
  menu:update()
  seen[tick] = menu:currentFrame()
end
eq(seen[10], 0, "the entrance script ends on the base picture")
local resume
for tick = 11, 31 do
  if seen[tick] ~= 0 then resume = tick break end
end
eq(resume, 11 + MonAnim.SCENE_WAIT + 1,
  "eighteen wait frames, then PokeAnim_Idle's own frame, then the idle script")
eq(resume and seen[resume], 2, "and the idle script's first frame comes up")
check(not menu:finished(), "the menu scene is longer than the battle one")

local ran = 0
for tick = 1, 60 do
  menu:update()
  if menu:finished() then ran = tick break end
end
check(ran > 0, "but it does end")

-- ---- gating ---------------------------------------------------------------

eq(MonAnim.new(nil, "battle"), nil, "no data means no sequencer")
eq(MonAnim.new({ tiles = 5, play = {} }, "battle"), nil,
  "and an empty script means no sequencer, which is every Gold species")
eq(MonAnim.new(LOOPED, "nosuchscene"), nil, "an unknown scene is nil too")

S.finish()
