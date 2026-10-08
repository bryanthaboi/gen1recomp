local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("game3_tilt_roof_2765")

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

return function(game)
  if not F.boot(game) then return F.finish() end
  local View = require("src.core.game3.field_view")
  local Display = require("src.core.game3.display")
  local Renderer = require("src.render.Renderer")
  local Tilt = require("src.render.Tilt")
  local Player = require("src.core.game3.player")
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  local version = session.version
  local map = version == "emerald" and "EM_OLDALE_TOWN" or "FR_PALLET_TOWN"
  local x, y = 6, version == "emerald" and 13 or 3
  if not F.check(F.goTo(game, map, x, y, "down"), "tilt2765 cached_roof_map") then return F.finish() end
  require("src.core.game3.field").lock()
  local plane = up(up(Display.present, "presentPlanes"), "drawFieldPlane")
  local overhead = up(View.draw, "drawNativeOverTiles")
  local function capturePlane(g)
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.setColor(1, 1, 1, 1)
    Renderer:beginFrame(true)
    Renderer:beginWorldPass()
    local vw, vh = Renderer:worldViewSize()
    plane(g, vw, vh, Renderer)
    Renderer:endWorldPass()
    love.graphics.pop()
    return Renderer.worldCanvas:newImageData(),
      Renderer.uprightActive and Renderer.uprightCanvas:newImageData() or nil
  end
  local function projectedAlpha()
    local vw, vh = Renderer.worldCanvas:getDimensions()
    local source = love.graphics.newCanvas(vw, vh, { dpiscale = 1 })
    source:setFilter("linear", "linear")
    local m = Renderer.UPRIGHT_MARGIN
    local target = love.graphics.newCanvas(vw + 2 * m, vh + 2 * m, { dpiscale = 1 })
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setCanvas(source)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setShader()
    love.graphics.setStencilTest()
    love.graphics.setScissor()
    love.graphics.setBlendMode("alpha", "alphamultiply")
    overhead()
    love.graphics.setCanvas(target)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setShader(Renderer:tiltShader())
    local mesh = Renderer:tiltMesh()
    mesh:setTexture(source)
    mesh:setVertices(Tilt.meshCorners(vw, vh))
    love.graphics.translate(m, m)
    love.graphics.draw(mesh)
    love.graphics.pop()
    local data = target:newImageData()
    source:release()
    target:release()
    return data
  end
  local maskMethod = Renderer.occludeUprightActors
  Tilt.applyOptions({ tilt = 0 })
  local off = capturePlane(game)
  Renderer.occludeUprightActors = function() end
  local referenceOff = capturePlane(game)
  Renderer.occludeUprightActors = maskMethod
  F.check(off:getString() == referenceOff:getString(), "tilt2765 " .. version .. " OFF_byte_identical")
  F.check(F.shot(game, "2765_" .. version .. "_00_off.png", true), "tilt2765 OFF_capture")
  local priority = Player.oamPriority
  for level = 1, 3 do
    Tilt.applyOptions({ tilt = level })
    Player.oamPriority = 0
    local _, elevated = capturePlane(game)
    Player.oamPriority = 2
    local _, normal = capturePlane(game)
    local alpha = projectedAlpha()
    local hidden = 0
    if normal and elevated then
      local w, h = normal:getDimensions()
      for py = math.floor(h / 2) - 30, math.floor(h / 2) + 20 do
        for px = math.floor(w / 2) - 16, math.floor(w / 2) + 16 do
          local _, _, _, ea = elevated:getPixel(px, py)
          local _, _, _, na = normal:getPixel(px, py)
          local _, _, _, ma = alpha:getPixel(px, py)
          if ea > 0.99 and ma > 0.99 and na < 0.01 then hidden = hidden + 1 end
        end
      end
    end
    F.check(hidden > 0, "tilt2765 " .. version .. " " .. Tilt.levelLabel(level) .. " real_roof_normal_hidden_elevated_visible")
    F.check(F.shot(game, "2765_" .. version .. "_" .. Tilt.levelLabel(level) .. "_normal.png", true), "tilt2765 normal_capture")
    Player.oamPriority = 0
    F.check(F.shot(game, "2765_" .. version .. "_" .. Tilt.levelLabel(level) .. "_elevated.png", true), "tilt2765 elevated_capture")
  end
  Player.oamPriority = priority

  local weather = require("src.core.game3.field_weather_rse")
  if version == "emerald" then
    require("src.core.game3.weather").resume()
    local exchanges, writes = 0, 0
    local exchange, write = Renderer.exchangeWorldCanvas, weather.writeActorMask
    Renderer.exchangeWorldCanvas = function(self, current, replacement)
      local changed = exchange(self, current, replacement)
      if changed then exchanges = exchanges + 1 end
      return changed
    end
    weather.writeActorMask = function(code, draw)
      local canvas, shader = love.graphics.getCanvas(), love.graphics.getShader()
      write(code, draw)
      F.check(love.graphics.getCanvas() == canvas and love.graphics.getShader() == shader,
        "tilt2765 weather_actor_mask_canvas_shader_restored")
      writes = writes + 1
    end
    for _, id in ipairs({ weather.WEATHER.SHADE, weather.WEATHER.RAIN, weather.WEATHER.FOG_HORIZONTAL }) do
      weather.setCurrentAndNextWeatherNoDelay(id)
      weather.readyForInit()
      for _ = 1, 180 do weather.update() end
      capturePlane(game)
      F.check(Renderer.uprightActive and Renderer.uprightOccluded, "tilt2765 weather_keeps_tilt_mask")
    end
    F.check(exchanges > 0 and writes > 0,
      "tilt2765 real_weather_canvas_exchange_and_actor_mask exchanges=" .. exchanges .. " writes=" .. writes)
    Renderer.exchangeWorldCanvas, weather.writeActorMask = exchange, write
    weather.setCurrentAndNextWeatherNoDelay(weather.WEATHER.NONE)
  end

  local vw, vh = 96, 80
  local oldViewSize = Renderer.worldViewSize
  Renderer.worldViewSize = function() return vw, vh end
  local saved = {}
  local function replace(name, fn) saved[name] = up(View.draw, name, fn) end
  replace("currentMapId", function() return "fixture" end)
  replace("playerPixels", function() return 40, 32, "down", 0, false, nil, 0, 0 end)
  for _, name in ipairs({ "modSeagallop", "modShopMenu", "modFieldEffects", "modDoors", "modHeal", "modSSAnne", "modFieldWeather" }) do
    replace(name, function() return nil end)
  end
  local function batch(w, h, ox, oy, pixel)
    local data = love.image.newImageData(w, h)
    for py = 0, h - 1 do for px = 0, w - 1 do data:setPixel(px, py, pixel(px, py)) end end
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    local b = love.graphics.newSpriteBatch(image, 1)
    b:add(ox, oy)
    return b
  end
  local main = batch(32, 32, 24, 20, function(px, py)
    return 1, 0, 0, (px >= 12 and px < 20 and py >= 12 and py < 20) and 0 or 1
  end)
  local neighbor = batch(16, 32, 64, 20, function(_, py) return 1, 1, 0, py < 16 and 1 or 0.5 end)
  replace("drawNativeTiles", function()
    View._nativeOverPair, View._nativeOverBatches = "main", { main = main, neighbor = neighbor }
    View._nativeOverOx, View._nativeOverOy, View._voidFrom = 0, 0, nil
    love.graphics.setColor(0, 0, 1, 1)
    love.graphics.rectangle("fill", 0, 0, vw, vh)
    return true
  end)
  local elevatedOn = false
  replace("collectGame3Actors", function()
    local actors = { { kind = "mod", elevation = 3, x = 40, y = 24, draw = function()
      love.graphics.setColor(0, 1, 0, 1)
      love.graphics.rectangle("fill", 0, 0, vw, vh)
    end } }
    if elevatedOn then actors[#actors + 1] = { kind = "mod", elevation = 13, x = 40, y = 24, draw = function()
      love.graphics.setColor(0, 1, 1, 1)
      love.graphics.rectangle("fill", 64, 20, 16, 32)
    end } end
    return View.applyDrawOrder(actors)
  end)
  local fixture = { data = { maps = { fixture = { width = 32, blocks = {} } } } }
  View._flashMapId, View._flashRadius = "fixture", nil
  for level = 1, 3 do
    Tilt.applyOptions({ tilt = level })
    elevatedOn = false
    local _, normal = capturePlane(fixture)
    local alpha = projectedAlpha()
    local errors, opaque, holes, partial = 0, 0, 0, 0
    local m = Renderer.UPRIGHT_MARGIN
    for py = 1, vh - 2 do
      for px = 1, vw - 2 do
        local _, green, _, a = normal:getPixel(px + m, py + m)
        local _, _, _, mask = alpha:getPixel(px + m, py + m)
        if math.abs(a - (1 - mask)) > 0.01 or math.abs(green - (1 - mask)) > 0.01 then errors = errors + 1 end
        if mask > 0.99 then opaque = opaque + 1 elseif mask < 0.01 then holes = holes + 1 else partial = partial + 1 end
      end
    end
    F.check(errors == 0 and opaque > 0 and holes > 0 and partial > 0,
      "tilt2765 GPU_" .. Tilt.levelLabel(level) .. " opaque_holes_fractional_connected_pair errors=" .. errors)
    elevatedOn = true
    local _, elevated = capturePlane(fixture)
    local _, g, b, a = elevated:getPixel(70 + m, 30 + m)
    F.check(g > 0.99 and b > 0.99 and a > 0.99, "tilt2765 GPU_elevated_above_mask")
  end
  local current = love.graphics.newCanvas(160, 120, { dpiscale = 1 })
  local shader = love.graphics.newShader("vec4 effect(vec4 c, Image t, vec2 uv, vec2 p) { return Texel(t,uv)*c; }")
  love.graphics.push("all")
  love.graphics.setCanvas(current)
  love.graphics.setShader(shader)
  love.graphics.setBlendMode("add", "premultiplied")
  love.graphics.setColor(0.2, 0.3, 0.4, 0.5)
  love.graphics.setScissor(4, 5, 6, 7)
  love.graphics.translate(3, 9)
  local before = { love.graphics.transformPoint(0, 0) }
  before[3], before[4] = love.graphics.transformPoint(1, 0)
  before[5], before[6] = love.graphics.transformPoint(0, 1)
  Renderer:occludeUprightActors(overhead)
  local r, g, b, a = love.graphics.getColor()
  local blend, mode = love.graphics.getBlendMode()
  local sx, sy, sw, sh = love.graphics.getScissor()
  local after = { love.graphics.transformPoint(0, 0) }
  after[3], after[4] = love.graphics.transformPoint(1, 0)
  after[5], after[6] = love.graphics.transformPoint(0, 1)
  local sameTransform = true
  for i, value in ipairs(before) do sameTransform = sameTransform and value == after[i] end
  F.check(love.graphics.getCanvas() == current and love.graphics.getShader() == shader
    and blend == "add" and mode == "premultiplied" and math.abs(r - 0.2) < 0.001
    and math.abs(g - 0.3) < 0.001 and math.abs(b - 0.4) < 0.001 and a == 0.5
    and sx == 4 and sy == 5 and sw == 6 and sh == 7 and sameTransform,
    "tilt2765 GPU_canvas_shader_blend_color_scissor_transform_restored")
  love.graphics.pop()
  for name, fn in pairs(saved) do up(View.draw, name, fn) end
  Renderer.worldViewSize = oldViewSize
  View.invalidate()
  Tilt.applyOptions({ tilt = 0 })
  F.finish()
end
