package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")

local function seq(t)
  local out = {}
  for _, run in ipairs(t) do
    for _ = 1, run[2] do out[#out + 1] = run[1] end
  end
  return out
end

local function same(got, want, label)
  local ok = #got >= #want
  for i = 1, #want do
    if got[i] ~= want[i] then ok = false break end
  end
  check(ok, label .. " (got " .. table.concat(got, ",", 1, math.min(#got, #want)) .. ")")
end

do
  local Show = { calls = {} }
  local tasks = {}
  package.loaded["src.core.game3.field"] = {
    lock = function() end, unlock = function() end, holdInput = function() end,
  }
  package.loaded["src.core.game3.task"] = { spawn = function(fn) tasks[#tasks + 1] = fn end }
  package.loaded["src.core.game3.field_move_show_mon"] = {
    start = function(mon, opts, cb) Show.calls[#Show.calls + 1] = { mon = mon, opts = opts, cb = cb } end,
  }
  local Dive = require("src.core.game3.dive")
  Dive.useDive(0, { species = 320 })
  check(#tasks == 1, "FldEff_UseDive spawns its task")
  tasks[1]({ frames = 0 })
  eq(#Show.calls, 1, "Dive starts the show-mon cut-in")
  local opts = Show.calls[1] and Show.calls[1].opts or {}
  check(opts.pose ~= true, "Dive skips the player field-move pose (field_effect.c:1924)")
  Dive.reset()
  package.loaded["src.core.game3.field"] = nil
  package.loaded["src.core.game3.task"] = nil
  package.loaded["src.core.game3.field_move_show_mon"] = nil
  package.loaded["src.core.game3.dive"] = nil
end

local FE = require("src.core.game3.field_effects")
local P = require("src.core.game3.player")
local function blobY2() return FE.surfBlobY2 and FE.surfBlobY2() end

local function resetPlayer()
  P.surfing, P.underwater, P.surfHopping, P.dismounting = false, false, false, false
  P.moving, P.jumping, P.action, P.walkInPlace = false, false, nil, false
  P.cellX, P.cellY, P.px, P.py, P.facing = 5, 5, 80, 80, "down"
  P.spriteYOffset = 0
  FE._surfBob, FE._underwaterBob = nil, nil
end

local function run(n, each)
  local ys = {}
  for i = 1, n do
    if each then each(i) end
    ;(FE.stepSurfBob or FE.step)()
    P.tick(nil)
    ys[i] = P.spriteYOffset
  end
  return ys
end

local RSE_SURF = seq({ { 0, 3 }, { -1, 4 }, { -2, 4 }, { -3, 4 }, { -4, 4 }, { -3, 4 }, { -2, 4 }, { -1, 4 }, { 0, 4 }, { -1, 4 } })

FE._manifest = { family = "rse" }
resetPlayer()
P.surfing = true
same(run(#RSE_SURF), RSE_SURF, "RSE surf: player bobs 0..-4 on 4-frame steps (field_effect_helpers.c:1107)")
eq(blobY2(), P.spriteYOffset, "RSE surf: blob and player share y2")

resetPlayer()
P.surfing = true
P.moving, P.targetX, P.targetY, P.progress, P.stepFrames = true, 5, 6, 0, 1000
local moving = run(16)
eq(moving[16], -4, "RSE surf: bob keeps running while the player swims")
P.moving = false

resetPlayer()
P.surfHopping = true
P.moving, P.jumping, P.targetX, P.targetY, P.progress, P.stepFrames = true, true, 5, 6, 0, 1000
run(20)
eq(blobY2(), 0, "RSE surf hop: blob holds still until the hop ends (field_effect.c:3068)")

local Collision = require("src.core.game3.collision")
local realElev = Collision.elevationAt
Collision.elevationAt = function(x, y) return (x == 5 and y == 4) and 3 or 1 end
resetPlayer()
P.surfing = true
local nearLand = seq({ { 0, 7 }, { -1, 8 }, { -2, 8 }, { -1, 8 }, { 0, 8 } })
same(run(#nearLand), nearLand, "RSE surf next to land bobs every 8th frame (field_effect_helpers.c:1097)")
Collision.elevationAt = realElev

resetPlayer()
P.underwater = true
local UNDER = seq({ { 1, 4 }, { 2, 4 }, { 3, 4 }, { 4, 4 }, { 3, 4 }, { 2, 4 }, { 1, 4 }, { 0, 4 }, { 1, 4 } })
same(run(#UNDER), UNDER, "underwater: player sprite bobs 0..+4 (field_effect_helpers.c:1164)")

FE._manifest = false
resetPlayer()
P.surfing = true
local frlg = run(150)
check(frlg[1] == 0 and frlg[48] == 0, "FRLG surf: player rests on blob frame 0")
check(frlg[49] == 1 and frlg[96] == 1, "FRLG surf: player drops 1px on blob frame 1 (pokefirered field_effect_helpers.c:1069)")
eq(frlg[97], 0, "FRLG surf: 96-frame blob cycle")
eq(frlg[150], 1, "FRLG surf: second cycle on frame 1")
eq(blobY2(), 0, "FRLG surf: blob never moves")
P.facing = "left"
eq(run(1)[1], 0, "FRLG surf: turning restarts the blob anim (pokefirered field_effect_helpers.c:1020)")

resetPlayer()
FE._manifest = nil
T.finish()
