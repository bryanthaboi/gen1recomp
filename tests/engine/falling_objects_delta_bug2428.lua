-- engine/battle/animations.asm:2335-2469
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local AnimPlayer = require("src.battle.AnimPlayer")

local deltas = {}
for i = 0, 63 do deltas[i] = i end

local data = {
  moveAnims = {
    PETALS_TEST = { seq = { { effect = "SE_PETALS_FALLING" } } },
    LEAVES_TEST = { seq = { { effect = "SE_LEAVES_FALLING" } } },
  },
  subanims = {}, frameBlocks = {}, baseCoords = {}, tilesheets = {},
  fallingDeltaXs = deltas,
}

local p = AnimPlayer.new(data)
local ok, err = pcall(p.start, p, "PETALS_TEST", true)
T.check(ok, "petals compile past delta index 8: " .. tostring(err))
T.eq(#p.steps, 53, "52 three-frame ticks plus the ClearSprites frame")
T.eq(#p.steps[1].sprites, 20, "twenty petals")
T.eq(#p.steps[53].sprites, 0, "ClearSprites empties OAM")
T.eq(p.steps[52].sprites[1].y, 104, "object 1 stops at y=104")

local function obj(tick, i) return p.steps[tick].sprites[i] end
T.eq(obj(1, 10).x, 74 - 10, "object 10 starts past the table and reads index 10")
T.eq(obj(2, 10).x, 74 - 10 - 11, "object 10 never wraps at 9: index 11 next")
T.eq(obj(3, 10).x, 74 - 10 - 11 - 12, "index 12 after that")
T.check(obj(3, 10).xf, "object 10 keeps moving left")
T.eq(obj(1, 11).x, 119 + 10, "object 11 moves right on index 10")
T.eq(obj(2, 11).x, 119 + 10 + 11, "object 11 then index 11")
T.check(not obj(2, 11).xf, "object 11 keeps moving right")
T.eq(obj(16, 10).y, 160, "object 10 parks off-screen once past y=112")

T.eq(obj(8, 1).x, 56 + 36, "object 1 sways right through indices 1..8")
T.check(obj(9, 1).xf and obj(9, 1).x == 92, "index 9 wraps to 0 and flips left")
T.eq(obj(10, 1).x, 91, "then walks the table leftward")

p:start("LEAVES_TEST", true)
T.eq(#p.steps, 53, "leaves run the same 52 ticks")
T.eq(#p.steps[1].sprites, 3, "three leaves")

T.finish("falling objects delta-X table")
