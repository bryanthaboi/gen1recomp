-- An ownsField pipeline on Gen 3: every field frame is its own, battle
-- transitions included, and a frame it does not draw is black, never the
-- engine's own map.  Without ownsField a declined frame still gets that map.
package.path = "./?.lua;./?/init.lua;" .. package.path

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
end

local cleared
love = love or {}
love.graphics = love.graphics or {}
local lg = love.graphics
for _, name in ipairs({ "push", "pop", "origin", "setColor" }) do lg[name] = function() end end
local target
function lg.setCanvas(c) target = c end
function lg.clear(r, g, b, a) cleared[#cleared + 1] = { target, r, g, b, a } end

local noop = function() end
package.loaded["src.render.Tilt"] = { level = 0, active = function() return false end, setLevel = noop }
package.loaded["src.mods.Runtime"] = { reportError = noop, wantsHook = function() return false end }
package.loaded["src.core.game3.oam"] = {
  resetFrame = noop, setLayer = function() return "ui" end, animateSprites = noop,
  buildOamBuffer = noop, flush = noop, flushPriority = noop,
}
package.loaded["src.core.game3.bg"] = { hasVisible = function() return false end, flushPriority = noop }
local transitioning = false
package.loaded["src.core.game3.battle_transition"] = { isActive = function() return transitioning end }

local calls
local FieldView = {}
function FieldView.draw(_, _, _, opts)
  opts = opts or {}
  if opts.actorsOnly then calls[#calls + 1] = "actors"
  else calls[#calls + 1] = "map" end
end
function FieldView.prepareFrame() calls[#calls + 1] = "prepare" end
package.loaded["src.core.game3.field_view"] = FieldView

local Schemas = require("src.mods.Schemas")
local Pipelines = require("src.render.Pipelines")

local worldCanvas, uprightCanvas = { name = "world" }, { name = "upright" }
local Renderer = { worldCanvas = worldCanvas, uprightCanvas = uprightCanvas }
function Renderer:beginUprightPass() end
function Renderer:endUprightPass() end
function Renderer:occludeUprightActors() end
function Renderer:exchangeWorldCanvas() end
function Renderer:worldContext() return {} end
function Renderer:setWorldOverride(canvas) self.worldOverride = canvas end

local canvas = { getWidth = function() return 1 end, getHeight = function() return 1 end }
local result, avail = canvas, true
local function record(owns)
  return { label = "P", gen3 = true, required = true, ownsField = owns,
    available = function() return avail end,
    drawWorld = function()
      if result == "throw" then error("boom") end
      return result
    end }
end
local function install(owns)
  local data = { render_pipelines = { p = record(owns) } }
  Schemas.bindGen3(data, "firered")
  Pipelines.install(data)
end

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
check(type(drawFieldPlane) == "function", "found drawFieldPlane")
if not drawFieldPlane then os.exit(1) end

local function frame()
  calls, cleared, Renderer.worldOverride = {}, {}, nil
  local before = Display.blankFrames
  drawFieldPlane({}, 10, 10, Renderer)
  return table.concat(calls, " "), Display.blankFrames - before
end
local function blackWorld()
  local last = cleared[#cleared]
  return last and last[1] == worldCanvas and last[2] == 0 and last[3] == 0
    and last[4] == 0 and last[5] == 1
end

-- 1. ownsField
install(true)
check(Pipelines.fieldOwner() == "p", "a required ownsField pipeline owns the field from install")
Pipelines.applyOptions({})
local order, blanks = frame()
check(Renderer.worldOverride == canvas and blanks == 0, "a drawn frame shows the pipeline's image")
check(order == "prepare actors", "a drawn frame never draws the map: " .. order)

result = nil
order, blanks = frame()
check(order == "prepare actors" and blanks == 1, "a declined frame is black, not the map: " .. order)
check(blackWorld(), "the world canvas is cleared to black")

result = canvas
avail = false
order, blanks = frame()
check(order == "prepare" and blanks == 1, "a not-ready pipeline leaves a black frame: " .. order)
avail = true

transitioning = true
order, blanks = frame()
check(Renderer.worldOverride == canvas and order == "prepare actors",
  "a battle transition is still the pipeline's: " .. order)
transitioning = false

result = "throw"
order, blanks = frame()
check(blanks == 1 and not order:find("map"), "a throw leaves a black frame: " .. order)
result = canvas
order, blanks = frame()
check(blanks == 1 and order == "prepare", "a retired owner keeps the field black: " .. order)

-- Tilt on, or a battle transition, with the owner not ready: still black
install(true)
Pipelines.applyOptions({})
avail = false
package.loaded["src.render.Tilt"].active = function() return true end
order, blanks = frame()
check(order == "prepare" and blanks == 1, "Tilt on never reaches the map: " .. order)
package.loaded["src.render.Tilt"].active = function() return false end
transitioning = true
order, blanks = frame()
check(order == "prepare" and blanks == 1, "a transition with the owner not ready is black: " .. order)
transitioning = false
avail = true

-- the display's error fallback
package.loaded["src.ui.game3.help_system"] = { isOpen = function() return false end }
package.loaded["src.core.game3.battle"] = { isActive = function() return false end }
Display.ensureCanvas = function() return { name = "main" } end
Display.presentCanvas = function() return true end
Display.setUiRenderer(noop)
calls, cleared = {}, {}
local before = Display.blankFrames
Display.presentFlat({}, 10, 10)
check(not table.concat(calls, " "):find("map") and Display.blankFrames == before + 1,
  "the error fallback shows black, not the map")

-- a higher-priority world pipeline that declines while the owner is on
local data = { render_pipelines = { p = record(true), hi = {
  label = "H", gen3 = true, required = true, priority = 9, drawWorld = function() return nil end } } }
Schemas.bindGen3(data, "firered")
Pipelines.install(data)
Pipelines.applyOptions({})
check(Pipelines.worldPipeline() == "hi", "the higher-priority pipeline claims")
order, blanks = frame()
check(blanks == 1 and not order:find("map"), "its declined frame is still black: " .. order)

-- 2. without ownsField, a declined frame still gets the engine's map
install(false)
Pipelines.applyOptions({})
calls, cleared = {}, {}
Display.presentFlat({}, 10, 10)
check(table.concat(calls, " "):find("map") ~= nil, "without an owner the error fallback draws the map")
check(Pipelines.fieldOwner() == nil, "no ownsField, no owner")
result = nil
order, blanks = frame()
check(order:find("map") ~= nil and blanks == 0, "a declined frame draws the map: " .. order)
result = canvas
transitioning = true
order = frame()
check(Renderer.worldOverride == nil and order:find("map") ~= nil,
  "a battle transition draws the map: " .. order)
transitioning = false

print((failures == 0 and "PASS " or "FAIL ") .. "game3_pipeline_owns_field_test")
os.exit(failures == 0 and 0 or 1)
