-- ../pokecrystal/engine/events/map_name_sign.asm:41-44
-- ../pokecrystal/engine/events/map_name_sign.asm:99-107

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

package.loaded["src.core.GameVersion"] = {
  engine = function() return "crystal" end,
}
package.loaded["src.render.Assets"] = {
  register = function() end,
  resolve = function(path) return path end,
  exists = function() return false end,
  image = function() error("no sheet in the fixture cache") end,
}
package.loaded["src.render.GbcPalette"] = {
  available = function() return false end,
  with = function(_, body) body() end,
}
package.loaded["src.render.Font"] = {
  ttfActive = function() return false end,
  encode = function(text)
    local out = {}
    for i = 1, #tostring(text) do out[i] = string.byte(text, i) end
    return out
  end,
  width = function(text) return #tostring(text) * 8 end,
  draw = function() end,
}
package.loaded["src.world.gen2.MapNameSign"] = nil
local Sign = require("src.world.gen2.MapNameSign")

local World = {}
World.__index = World

function World.new(game)
  return setmetatable({
    game = game,
    map = { id = "ROUTE_29",
      def = { landmark = "LANDMARK_ROUTE_29", environment = "ROUTE" } },
    mapSignState = { prev = "LANDMARK_NEW_BARK_TOWN" },
  }, World)
end

function World:currentLandmarkId() return "LANDMARK_ROUTE_29" end
function World:landmarkName() return "ROUTE 29" end

local function raise(game)
  local w = World.new(game)
  Sign.init(w)
  return w
end

local function gameAt(speed)
  return { logicSpeed = function() return speed end }
end

local FixedStep = require("src.core.FixedStep")
local STEP = FixedStep.STEP

local function renderedFramesToClear(w, speed, limit)
  local steps, maxPerFrame = 0, 0
  FixedStep:init(function() steps = steps + 1 Sign.tick(w) end)
  FixedStep.maxAccum = FixedStep.catchupLimit(speed)
  for frame = 1, limit do
    local before = steps
    Sign.frame(w)
    FixedStep:update(STEP, speed)
    maxPerFrame = math.max(maxPerFrame, steps - before)
    if w.mapSign == nil then return frame, steps, maxPerFrame end
  end
  return nil, steps, maxPerFrame
end

local one = raise(gameAt(1))
if check(one.mapSign ~= nil, "the sign comes up at 1X") then
  eq(one.mapSign.timer, 60, "wLandmarkSignTimer starts at 60")
  eq(one.mapSign.shown, false, "and the window is still off screen")
  for _ = 1, 20 do Sign.frame(one) end
  eq(one.mapSign.timer, 50, "twenty real frames are ten HandleMap calls")
  eq(one.mapSign.shown, true, "shown from the second call")
end

-- ../pokecrystal/engine/overworld/events.asm:177-191
FixedStep.clock = function() return 0 end
for _, speed in ipairs({ 1, 4, 10, 20, 200 }) do
  local w = raise(gameAt(speed))
  local frame, steps, maxPerFrame = renderedFramesToClear(w, speed, 2000)
  eq(frame, 122, ("%dX: the sign clears on rendered frame 122"):format(speed))
  eq(steps, 122 * speed,
    ("%dX: the logic ran %d steps"):format(speed, speed * 122))
  eq(maxPerFrame, speed, ("%dX: %d steps a rendered frame"):format(speed, speed))
end
FixedStep.clock = nil

local hidden = raise(gameAt(1))
for _ = 1, 3 do Sign.frame(hidden) end
eq(hidden.mapSign.shown, false, "frames 1-3: the first call returns before drawing")
Sign.frame(hidden)
eq(hidden.mapSign.shown, true, "frame 4: the second call sets hWY = $70")
for _ = 5, 120 do Sign.frame(hidden) end
check(hidden.mapSign ~= nil and hidden.mapSign.shown, "frame 120: last visible")
Sign.frame(hidden)
check(hidden.mapSign ~= nil, "frame 121: the 61st call has not landed yet")
Sign.frame(hidden)
eq(hidden.mapSign, nil, "frame 122: a = 0, .disappear")

local bare = raise(nil)
local bareFrame = renderedFramesToClear(bare, 1, 400)
eq(bareFrame, 122, "no game object: the same 122 real frames")

-- ../pokecrystal/home/window.asm:42
for _, speed in ipairs({ 1, 4, 10, 200 }) do
  local talked = raise(gameAt(speed))
  talked.textbox = true
  Sign.tick(talked)
  eq(talked.mapSign, nil,
    "a text box takes the sign down on the first tick at " .. speed .. "X")
end

-- ../pokecrystal/data/maps/setup_scripts.asm:32-56
local fading = raise(gameAt(1))
fading.mapSetup = { phase = "in" }
for _ = 1, 200 do Sign.frame(fading) end
eq(fading.mapSign.timer, 60, "a map setup fade freezes the countdown")
fading.mapSetup = nil
for _ = 1, 4 do Sign.frame(fading) end
eq(fading.mapSign.timer, 58, "and it runs on once the fade is gone")

-- ../pokecrystal/engine/overworld/events.asm:284-285
local pushed = raise(gameAt(10))
for _ = 1, 30 do Sign.frame(pushed) end
check(pushed.mapSign ~= nil, "the sign survives 30 real frames at 10X")
Sign.cancel(pushed)
eq(pushed.mapSign, nil, "and a player event still clears it outright")

local stateful = raise(gameAt(4))
Sign.frame(stateful)
eq(Sign.state(stateful).frames, nil,
  "the frame counter does not reach the saved crystal state")
eq(Sign.state(stateful).shown, nil, "nor does the shown flag")
check(stateful.mapSign and stateful.mapSign.frames ~= nil,
  "they live on world.mapSign")

T.finish("crystal map name sign speed bug 1994")
