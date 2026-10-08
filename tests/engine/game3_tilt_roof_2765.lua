package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local noop = function() end
for _, name in ipairs({ "seagallop_ui", "shop_menu", "field_effects", "doors", "pokecenter_heal", "ss_anne", "field_weather", "ow_sprites" }) do
  package.loaded["src.core.game3." .. name] = {}
end
package.loaded["src.core.game3.map"] = { refreshWorld = noop }
package.loaded["src.core.game3.bg"] = { hasVisible = function() return false end }
package.loaded["src.core.game3.oam"] = {
  resetFrame = noop, setLayer = noop, animateSprites = noop, buildOamBuffer = noop, flush = noop,
}
local F = require("src.core.game3.field_view")
local D = require("src.core.game3.display")
local R = require("src.render.Renderer")
local Tilt = require("src.render.Tilt")
local function up(fn, wanted, replacement)
  for i = 1, 100 do
    local name, value = debug.getupvalue(fn, i)
    if name == wanted then
      if replacement then debug.setupvalue(fn, i, replacement) end
      return value
    end
  end
  error("missing " .. wanted)
end
local plane = up(up(D.present, "presentPlanes"), "drawFieldPlane")
local records = {}
local function record(label) records[#records + 1] = label end
local roof, neighbor = {}, {}
local mesh = { setTexture = function(self, texture) self.texture = texture end,
  setVertices = function(self, vertices) self.vertices = vertices end }
love.graphics.newMesh = function() return mesh end
love.graphics.newShader = function() return {} end
love.graphics.setStencilTest = noop
love.graphics.draw = function(what)
  if what == roof or what == neighbor then
    record(love.graphics.getCanvas() == R.worldCanvas and "ground-roof" or "mask-roof")
  elseif what == mesh then
    T.eq(love.graphics.getCanvas(), R.uprightCanvas, "mask projects onto upright actors")
    T.eq(love.graphics.getBlendMode(), "multiply", "mask removes actor coverage")
    local shader = love.graphics.getShader()
    T.check(shader ~= nil, "projected mask uses a shader")
    record("occlude-normal")
  end
end
up(F.draw, "drawNativeTiles", function()
  F._nativeOverPair, F._nativeOverBatches = "main", { main = roof, neighbor = neighbor }
  record("ground")
  return true
end)
up(F.draw, "collectGame3Actors", function()
  return F.applyDrawOrder({
    { kind = "mod", elevation = 3, x = 80, y = 192, draw = function() record("normal") end },
    { kind = "mod", elevation = 13, x = 80, y = 192, draw = function() record("elevated") end },
  })
end)
local game = { mapId = "sample", data = { maps = { sample = { width = 32, blocks = {} } } },
  world = { map = { id = "sample" }, player = { px = 80, py = 192 } } }
F._flashMapId = "sample"
local function index(label)
  for i, item in ipairs(records) do if item == label then return i end end
end
local function render(level, transitioning)
  records = {}
  Tilt.applyOptions({ tilt = level })
  package.loaded["src.core.game3.battle_transition"] = { isActive = function() return transitioning end }
  R:init()
  R:beginFrame(true)
  R:beginWorldPass()
  plane(game, 240, 160, R)
  T.eq(love.graphics.getCanvas(), R.worldCanvas, "field plane restores the current world canvas")
  if level > 0 and not transitioning then
    T.check(index("occlude-normal") ~= nil, "tilt2765 normal actors receive roof occlusion")
    local masked = index("occlude-normal")
    T.check(masked and index("normal") < masked and masked < index("elevated"),
      "tilt2765 elevated actors draw after roof occlusion")
    local maskRoofs = 0
    for _, item in ipairs(records) do if item == "mask-roof" then maskRoofs = maskRoofs + 1 end end
    T.eq(maskRoofs, 2, "tilt2765 includes the connected-pair overhead batch")
    local vw, vh = R.worldCanvas:getWidth(), R.worldCanvas:getHeight()
    local expected = Tilt.meshCorners(vw, vh)
    if mesh.vertices then
      for i, vertex in ipairs(expected) do
        for j, value in ipairs(vertex) do T.eq(mesh.vertices[i][j], value, "mask shares ground projection") end
      end
    end
    T.eq(love.graphics.getShader(), nil, "mask restores shader")
    T.eq(love.graphics.getBlendMode(), "alpha", "mask restores blend mode")
  else
    T.eq(index("occlude-normal"), nil, "tilt2765 OFF and transitions skip the mask")
    T.check(index("normal") < index("ground-roof") and index("ground-roof") < index("elevated"),
      "flat field keeps cart layer ordering")
    T.eq(R.uprightActive, false, "flat field does not enter upright pass")
  end
  R:endWorldPass()
end
for level = 0, 1 do
  Tilt.applyOptions({ tilt = level })
  R:init()
  R:beginFrame(true)
  R:beginWorldPass()
  if level > 0 then
    R:beginUprightPass()
    R:endUprightPass()
  end
  R:endWorldPass()
  local draw, getBlend = love.graphics.draw, love.graphics.getBlendMode
  local reads = 0
  love.graphics.draw = noop
  love.graphics.getBlendMode = function()
    reads = reads + 1
    return getBlend()
  end
  R:endFrame(nil, nil)
  love.graphics.draw, love.graphics.getBlendMode = draw, getBlend
  T.eq(reads, 0, "tilt2765 unmasked composite skips blend-state reads at level " .. level)
end
render(0, false)
for level = 1, 3 do render(level, false) end
render(1, true)
render(1, false)
local priorMask = R.tiltOverheadCanvas
T.check(priorMask ~= nil, "tilt2765 lifecycle starts with an allocated mask")
R:init()
T.check(priorMask and priorMask.released, "tilt2765 init releases the overhead mask")
T.eq(R.tiltOverheadCanvas, nil, "tilt2765 init drops the overhead mask")
T.eq(R.uprightOccluded, false, "tilt2765 init clears premultiplied upright compositing")
render(1, false)
local releasedMask = R.tiltOverheadCanvas
R:releaseCanvases()
T.check(releasedMask and releasedMask.released, "tilt2765 release frees the overhead mask")
T.eq(R.tiltOverheadCanvas, nil, "tilt2765 release drops the overhead mask")
T.eq(R.uprightOccluded, false, "tilt2765 release clears premultiplied upright compositing")
T.check(pcall(R.releaseCanvases, R), "tilt2765 repeated release is safe")
R._tiltOcclusionShader = nil
love.graphics.newShader = function() error("unsupported mask shader") end
local current = love.graphics.getCanvas()
local ok = pcall(R.occludeUprightActors, R, noop)
T.check(not ok, "tilt2765 shader compilation failure reaches the display error boundary")
T.eq(love.graphics.getCanvas(), current, "failed shader creation does not switch canvas")
R._tiltMesh = false
T.check(pcall(R.occludeUprightActors, R, noop), "tilt2765 unavailable perspective mesh uses the existing renderer route")
Tilt.reset()
T.finish("game3_tilt_roof_2765")
