-- The field FX a render pipeline composites, where endFrame mirrors the
-- override.  The pipeline's pass goes in pre-flipped and comes back level;
-- ctx.drawFx puts these in as ordinary 2D, so without the matching mirror the
-- trainer "!" lands upside down and below its feet.
--
-- The checks ask where a pixel is SEEN: they run the arithmetic `at` does and
-- then apply the composite by hand, so a mirror about the wrong axis, the
-- wrong height or in the wrong order fails here.
--   luajit tests/engine/world_pipeline_fx_mirror.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Renderer = require("src.render.Renderer")
local Overworld = require("src.world.OverworldController")

-- ------------------------------------------------- a transform we can read

local g = love.graphics
local real = { push = g.push, pop = g.pop, translate = g.translate,
               scale = g.scale, getCanvas = g.getCanvas }
local stack

local function reset() stack = { { oy = 0, sy = 1 } } end
local function top() return stack[#stack] end

g.push = function() local t = top(); stack[#stack + 1] = { oy = t.oy, sy = t.sy } end
g.pop = function() if #stack > 1 then stack[#stack] = nil end end
g.translate = function(_, dy) local t = top(); t.oy = t.oy + t.sy * dy end
g.scale = function(_, ky) local t = top(); t.sy = t.sy * (ky or 1) end

local CANVAS_H = 400
g.getCanvas = function() return { getHeight = function() return CANVAS_H end } end

local osName, major = "iOS", 12
love.system = love.system or {}
local realOS, realVersion = love.system.getOS, love.getVersion
love.system.getOS = function() return osName end
love.getVersion = function() return major, 0, 0, "" end

reset()

-- ------------------------------------------------- which hosts mirror

T.check(Renderer.mirrorsWorldOverride(), "LOVE 12 on iOS mirrors the override")
major = 11
T.check(not Renderer.mirrorsWorldOverride(), "LOVE 11 stores a canvas the old way")
major, osName = 12, "Android"
T.check(not Renderer.mirrorsWorldOverride(), "and no other host reaches that branch")
osName = "iOS"

-- ------------------------------------------------- the geometry

local CAM_X, CAM_Y = 100, 200
local NPC_X, NPC_Y = 148, 264          -- the foot `at` anchors to
local ROW, SCALE = 120, 2              -- where the pipeline projects that foot
local function project() return 260, ROW end

-- src/world/OverworldController.lua's `at`, for the row a drawn point reaches
local function at(dy)
  local sx, sy = project()
  local fy = NPC_Y - CAM_Y
  g.push()
  g.scale(SCALE, SCALE)
  g.translate(sx / SCALE, sy / SCALE - fy)
  local t = top()
  local row = t.oy + t.sy * (fy + dy)
  g.pop()
  return row
end

-- endFrame draws the override from the bottom edge with a negative Y scale
local function seen(row) return CANVAS_H - row end

-- fxEmote draws the bubble 36 world pixels above the foot it anchors to
reset()
T.eq(seen(at(0)), CANVAS_H - ROW, "unmirrored, the anchor is seen at the mirrored row")
T.check(seen(at(-36)) > seen(at(0)), "and the bubble that belongs above is seen below")

reset()
Overworld.withOverrideMirror(function()
  T.eq(seen(at(0)), ROW, "mirrored, the anchor is seen where the pipeline put it")
  T.eq(seen(at(-36)), ROW - 36 * SCALE, "and the bubble sits above it, upright")
end)
T.eq(#stack, 1, "the transform stack is left balanced")

-- ------------------------------------------------- what it leaves alone

-- no mirror in the composite either, so the drawn row IS the row seen
osName = "Android"
reset()
Overworld.withOverrideMirror(function()
  T.eq(at(0), ROW, "a host that composites straight draws them untouched")
end)
osName = "iOS"

-- a pipeline at a reduced render scale mirrors about ITS canvas, not the playfield
CANVAS_H = 240
reset()
Overworld.withOverrideMirror(function()
  T.eq(seen(at(0)), ROW, "a reduced render scale mirrors about its own canvas")
end)
CANVAS_H = 400

reset()
g.getCanvas = function() return nil end
Overworld.withOverrideMirror(function()
  T.eq(seen(at(0)), CANVAS_H - ROW, "with nothing bound the effects still draw")
end)
T.eq(#stack, 1, "and no transform is pushed for them")

for name, fn in pairs(real) do g[name] = fn end
love.system.getOS, love.getVersion = realOS, realVersion

T.finish("world pipeline fx mirror")
