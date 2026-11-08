-- A render pipeline claiming the Gen 3 field: who may claim, what a claimed
-- frame skips, and that declining or throwing still leaves a drawn world.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

love = love or {}
love.graphics = love.graphics or {}
local lg = love.graphics
for _, name in ipairs({ "push", "pop", "setCanvas", "origin", "clear" }) do lg[name] = function() end end

local Tilt = { level = 3, active = function() return true end,
  setLevel = function(level) Tilt_set = level end }
package.loaded["src.render.Tilt"] = Tilt
package.loaded["src.mods.Runtime"] = { reportError = function() end, wantsHook = function() return false end }

local Schemas = require("src.mods.Schemas")
local Pipelines = require("src.render.Pipelines")

local calls
local FieldView = {}
function FieldView.draw(_, _, _, opts)
  if opts.skipActors then calls[#calls + 1] = "ground" end
  if opts.actorsOnly then calls[#calls + 1] = "actors" end
end
function FieldView.prepareFrame() calls[#calls + 1] = "prepare" end
package.loaded["src.core.game3.field_view"] = FieldView

local Renderer = { worldCanvas = {}, worldOverride = nil }
function Renderer:beginUprightPass() end
function Renderer:endUprightPass() end
function Renderer:worldContext() return {} end
function Renderer:setWorldOverride(canvas) self.worldOverride = canvas end

local canvas = { getWidth = function() return 1 end, getHeight = function() return 1 end }
local result, actors, avail = canvas, "engine", true
local records = {
  gen1only = { label = "A", drawWorld = function() return canvas end, priority = 5 },
  claim = { label = "B", gen3 = true, keepTilt = true, defaultLevel = 1, priority = 1,
    levels = { "OFF", "GROUND", "ACTORS" },
    available = function() return avail end,
    actors = function(level) return level >= 2 and "mod" or actors end,
    drawWorld = function()
      if result == "throw" then error("boom") end
      return result
    end },
}
local data = { render_pipelines = records }
Schemas.bindGen3(data, "firered")
Pipelines.install(data)

-- 1. who may claim
Tilt_set = nil
local opts = { pipelines = { gen1only = 1 } }
Pipelines.applyOptions(opts)
check(Pipelines.level("gen1only") == 0, "a Gen 1 pipeline stays inert on Gen 3")
check(Pipelines.level("claim") == 1, "defaultLevel applies with no stored level")
check(Tilt_set == nil, "keepTilt leaves Tilt alone when restored")
check(Pipelines.worldPipeline() == "claim", "the gen3 pipeline owns the world")
opts.tilt = 3
Pipelines.syncOptions(opts)
check(opts.tilt == 3, "keepTilt leaves the saved tilt alone")
Pipelines.setLevel("claim", 0)
check(Pipelines.worldPipeline() == nil, "level 0 owns nothing")
Pipelines.syncOptions(opts)
Pipelines.applyOptions(opts)
check(Pipelines.level("claim") == 0, "a stored OFF beats defaultLevel")
Pipelines.setLevel("claim", 1)
avail = false
check(Pipelines.worldPipeline() == nil, "available false owns nothing")
avail = true

-- 2. the frame itself
local Display = require("src.core.game3.display")
local function upvalue(fn, wanted)
  for i = 1, 200 do
    local name, value = debug.getupvalue(fn, i)
    if not name then return nil end
    if name == wanted then return value end
  end
end
local presentPlanes = upvalue(Display.present, "presentPlanes")
local drawFieldPlane = presentPlanes and upvalue(presentPlanes, "drawFieldPlane")
local drawClaimedField = drawFieldPlane and upvalue(drawFieldPlane, "drawClaimedField")
check(type(drawClaimedField) == "function", "found drawClaimedField")
if not drawClaimedField then os.exit(1) end

local function frame()
  calls, Renderer.worldOverride = {}, nil
  local shown = drawClaimedField({}, 10, 10, Renderer, "claim", nil)
  return shown, table.concat(calls, " ")
end

local shown, order = frame()
check(shown == true and Renderer.worldOverride == canvas, "a claimed frame publishes the override")
check(order == "prepare actors", "a claimed frame skips the ground pass, keeps actors: " .. order)

Pipelines.setLevel("claim", 2)
check(Pipelines.actorMode("claim") == "mod", "actors may depend on the level")
shown, order = frame()
check(order == "prepare", "actors = mod skips the upright pass too: " .. order)

result = nil
shown, order = frame()
check(shown == false and Renderer.worldOverride == nil, "a declined frame publishes nothing")
check(order == "prepare ground actors", "a declined frame draws ground and actors: " .. order)

Pipelines.setLevel("claim", 1)
shown, order = frame()
check(order == "prepare actors ground", "a declined frame draws the skipped ground: " .. order)

result = "throw"
shown, order = frame()
check(shown == false and order == "prepare actors ground", "a throw falls back the same way")
check(Pipelines.worldPipeline() == nil, "a throw retires the pipeline")

print((failures == 0 and "PASS " or "FAIL ") .. "game3_pipeline_claim_test")
os.exit(failures == 0 and 0 or 1)
