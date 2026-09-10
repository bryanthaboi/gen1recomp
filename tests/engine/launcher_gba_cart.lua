-- luajit tests/engine/launcher_gba_cart.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness")
local check, eq = T.check, T.eq
local noop = function() end
love.graphics.setLineJoin = noop
love.graphics.polygon = noop
love.graphics.newShader = function() return {} end
love.graphics.newMesh = function(vertices)
  return { vertices = vertices,
    setVertices = function(self, v) self.vertices = v end,
    setTexture = function(self, t) self.texture = t end }
end

local Kit = require("src.ui.kit.Kit")
local View = require("src.import.LauncherView")
local Importer = require("src.import.RomImporter")
local LaunchOptions = require("src.core.LaunchOptions")
local GameVersion = require("src.core.GameVersion")
local Shape = require("src.import.CartShape")
local Art = require("src.import.CartLabelArt")
local getenv = os.getenv
local shape = "gba"
os.getenv = function(key)
  if key == "POKEPORT_CART_SHAPE" then return shape end
  if key == "POKEPORT_CART_LABEL" then return nil end
  return getenv(key)
end

eq(LaunchOptions.resolveRequest({ "--game", "red" }).launcher, false,
  "cart shape does not override game shortcuts")
local imp = Importer.new(noop, { launcher = true })
imp.tab, imp.ready.red = "red", false
local launches = 0
imp.play = function() launches = launches + 1 end
local function draw(w, h)
  love.graphics.getDimensions = function() return w, h end
  love.graphics.getPixelDimensions = function() return w, h end
  Kit.audit = {}
  View.draw(imp)
  local cart, manage
  for _, r in ipairs(Kit.audit) do
    if r.label == "play-red" then cart = r end
  end
  for _, r in ipairs(Kit._nav) do
    if r.id == "manage-red" then manage = r end
  end
  Kit.audit = nil
  return cart, manage
end

eq(draw(1024, 768), nil, "unimported games have no play cart")
imp.ready.red = true

for _, size in ipairs({ { 1024, 768 }, { 390, 844 }, { 640, 480 } }) do
  local cart, manage = draw(size[1], size[2])
  check(cart ~= nil, "imported games show the selected cart shape")
  check(math.abs(cart.w / cart.h - Shape.GBA_ASPECT) < 0.001,
    "window resizing preserves the wide shell proportions")
  check(cart.x + cart.w < manage.x, "cart leaves room for the gear")
  eq(imp.ready.red, true, "shape preserves import state")
end

local cart = draw(1024, 768)
local mx, my = cart.x + cart.w / 2, cart.y + cart.h / 2
local down = true
love.mouse.getPosition = function() return mx, my end
love.mouse.isDown = function() return down end
imp._clickPt = { x = mx, y = my }
draw(1024, 768)
mx = mx + 60
draw(1024, 768)
local state = imp._cartridge["gba:red"]
check(state.dragged and state.spin > 0.5, "dragging rotates the GBA shell")
down = false
draw(1024, 768)
eq(#imp._uiActions, 0, "a spin does not dispatch a click")
imp._clickPt = { x = mx, y = my }
draw(1024, 768)
check(#imp._uiActions > 0, "taps use the normal action queue")
for _, action in ipairs(imp._uiActions) do action.fn() end
eq(launches, 1, "cart taps launch the selected game")

local label = imp._gbaLabels["gba:red"]
local mesh = imp._cartridgeLabelMeshes["gba:red"]
eq(label.width, 512, "label uses landscape stock")
check(#mesh.vertices > 4, "label corners follow the rounded recess")
for _, v in ipairs(mesh.vertices) do
  check(v[3] >= 0 and v[3] <= 1 and v[4] >= 0 and v[4] <= 1,
    "rounded label vertices keep UVs inside the image")
end
for _, angle in ipairs({ math.pi / 2, math.pi, math.pi * 1.5, math.pi * 2 }) do
  state.spin = angle
  local ok, err = pcall(draw, 1024, 768)
  check(ok, "side and back views render: " .. tostring(err))
end
eq(imp._gbaLabels["gba:red"], label, "rotation reuses the label canvas")

local originalDraw, fitted = love.graphics.draw, nil
local source = { image = {}, width = 300, height = 500 }
love.graphics.draw = function(image, x, y, rotation, sx, sy)
  if image == source.image then fitted = { x, y, sx, sy } end
end
Art.label({}, { cacheKey = "custom", cartId = "custom", color = { 10, 20, 30 } },
  source)
love.graphics.draw = originalDraw
eq(fitted[3], fitted[4], "portrait custom art is never stretched")
check(fitted[1] > 0 and fitted[2] == 0, "portrait art is centered with side gutters")

shape = nil
local normal = Importer.new(noop, { launcher = true })
eq(normal.cartShape, nil, "ordinary launches keep the original cart")
eq(GameVersion.cartShape("red"), "gb", "existing games default to GB")
eq(GameVersion.cartShape("unknown"), "gb", "unknown games default to GB")

imp.cartShape = nil
GameVersion.VERSIONS.red.cartShape = "gba"
eq(GameVersion.cartShape("red"), "gba", "game metadata selects GBA")
cart = draw(1024, 768)
check(math.abs(cart.w / cart.h - Shape.GBA_ASPECT) < 0.001,
  "game metadata selects the wide shell without an override")

GameVersion.VERSIONS.red.cartLabel = "assets/labels/blue.png"
imp._cartridgeLabels, imp._gbaLabels = nil, nil
local seenSource
love.graphics.draw = function(image)
  if image.path == "assets/labels/blue.png" then seenSource = image end
end
draw(1024, 768)
love.graphics.draw = originalDraw
check(seenSource ~= nil, "the GBA label uses per-game artwork")

GameVersion.VERSIONS.red.cartShape = nil
GameVersion.VERSIONS.red.cartLabel = nil
cart = draw(1024, 768)
check(cart.w / cart.h < 1, "unmarked games keep the GB shape")
os.getenv = getenv
T.finish("launcher_gba_cart")
