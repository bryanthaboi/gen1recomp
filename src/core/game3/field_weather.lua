-- Field Weather System (Fog, Shade, Rain)
-- pokefirered/src/field_weather.c
-- pokefirered/src/field_weather_effects.c

local Dataset = require("src.core.game3.dataset")
local Weather = require("src.core.game3.weather")

local FieldWeather = {}

local W, H = 240, 160
local CACHE_ROOT = "data/generated/gba/weather"

FieldWeather._current = Weather.NONE
FieldWeather._assets = nil
FieldWeather._fogScrollOffset = 0
FieldWeather._fogScrollCounter = 0
FieldWeather._rainSprites = {}
FieldWeather._rainTimer = 0

local function loadAssets()
  if FieldWeather._assets then return FieldWeather._assets end
  local cache = Dataset.cache()
  if not (cache and cache.read) then return nil end
  local fogRaw = cache:read(CACHE_ROOT .. "/fog_horizontal.rgba")
  local rainRaw = cache:read(CACHE_ROOT .. "/rain.rgba")

  local function imgFromRgba(raw, w, h)
    if not raw or #raw < w * h * 4 then return nil end
    local imgData = love.image.newImageData(w, h)
    local ptr = 1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r = raw:byte(ptr) or 0
        local g = raw:byte(ptr + 1) or 0
        local b = raw:byte(ptr + 2) or 0
        local a = raw:byte(ptr + 3) or 0
        imgData:setPixel(x, y, r / 255, g / 255, b / 255, a / 255)
        ptr = ptr + 4
      end
    end
    local img = love.graphics.newImage(imgData)
    img:setFilter("nearest", "nearest")
    img:setWrap("repeat", "repeat")
    return img
  end

  local fogImg = fogRaw and imgFromRgba(fogRaw, 64, 64)
  local rainImg = rainRaw and imgFromRgba(rainRaw, 16, 192)

  FieldWeather._assets = {
    fog = fogImg,
    rain = rainImg,
  }
  return FieldWeather._assets
end

function FieldWeather.setWeather(weatherId)
  FieldWeather._current = tonumber(weatherId) or Weather.NONE
  if FieldWeather._current == Weather.FOG_HORIZONTAL then
    FieldWeather._fogScrollOffset = 0
    FieldWeather._fogScrollCounter = 0
  elseif FieldWeather._current == Weather.RAIN or FieldWeather._current == Weather.RAIN_THUNDERSTORM then
    FieldWeather._rainSprites = {}
    FieldWeather._rainTimer = 0
  end
end

function FieldWeather.getWeather()
  return FieldWeather._current
end

function FieldWeather.update(dt)
  if Weather.isSuspended() then return end
  local w = FieldWeather._current

  -- pokefirered/src/field_weather_effects.c:1332 FogHorizontal_Main
  if w == Weather.FOG_HORIZONTAL then
    FieldWeather._fogScrollCounter = FieldWeather._fogScrollCounter + 1
    if FieldWeather._fogScrollCounter > 3 then
      FieldWeather._fogScrollCounter = 0
      FieldWeather._fogScrollOffset = (FieldWeather._fogScrollOffset + 1) % 256
    end
  elseif w == Weather.RAIN or w == Weather.RAIN_THUNDERSTORM or w == Weather.DOWNPOUR then
    -- Rain particle generation & simulation
    FieldWeather._rainTimer = FieldWeather._rainTimer + (dt or (1 / 60))
    if #FieldWeather._rainSprites < 24 and math.random() < 0.35 then
      table.insert(FieldWeather._rainSprites, {
        x = math.random(-20, W + 20),
        y = math.random(-40, -10),
        speed = math.random(7, 10),
        groundY = math.random(20, H),
        splashTick = 0,
        state = "falling",
      })
    end

    local i = 1
    while i <= #FieldWeather._rainSprites do
      local r = FieldWeather._rainSprites[i]
      if r.state == "falling" then
        r.x = r.x - 2
        r.y = r.y + r.speed
        if r.y >= r.groundY then
          r.state = "splash"
          r.splashTick = 0
        end
      elseif r.state == "splash" then
        r.splashTick = r.splashTick + 1
        if r.splashTick >= 6 then
          table.remove(FieldWeather._rainSprites, i)
          i = i - 1
        end
      end
      i = i + 1
    end
  end
end

--- Render weather atmospheric layer over the field (before UI/dialogues)
function FieldWeather.draw(camX, camY, canvasW, canvasH)
  if Weather.isSuspended() then return end
  local w = FieldWeather._current
  if w == Weather.NONE or w == Weather.SUNNY then return end

  canvasW = canvasW or W
  canvasH = canvasH or H
  camX = camX or 0
  camY = camY or 0

  local assets = loadAssets()

  -- 1. WEATHER_SHADE: Atmospheric gamma dimming without color washout
  -- pokefirered/src/field_weather_effects.c:2172 Shade_InitVars (gammaTargetIndex = 3)
  if w == Weather.SHADE then
    love.graphics.push("all")
    love.graphics.setBlendMode("multiply", "premultiplied")
    -- Dim factor ~70% (0.70, 0.70, 0.75) for authentic cool shadow tint
    love.graphics.setColor(0.68, 0.68, 0.74, 1)
    love.graphics.rectangle("fill", 0, 0, canvasW, canvasH)
    love.graphics.pop()
  end

  -- 2. WEATHER_FOG_HORIZONTAL: 64x64 fog sprites with GBA BLDALPHA (12/16 sprite, 8/16 backdrop)
  -- pokefirered/src/field_weather_effects.c:1343 Weather_SetTargetBlendCoeffs(12, 8, 3)
  if w == Weather.FOG_HORIZONTAL then
    love.graphics.push("all")
    love.graphics.setBlendMode("alpha")
    -- Alpha blend weight: 12/16 = 0.75
    love.graphics.setColor(1, 1, 1, 0.70)

    if assets and assets.fog then
      -- pokefirered/src/field_weather_effects.c:1332 FogHorizontal_Update
      -- In vanilla FireRed, fog sprites are fixed in screen space and drift horizontally
      -- (+1 px every 4 frames) with zero camera/map parallax.
      local scrollX = FieldWeather._fogScrollOffset % 64
      local startX = -scrollX

      for py = 0, canvasH, 64 do
        for px = startX, canvasW + 64, 64 do
          love.graphics.draw(assets.fog, px, py)
        end
      end
    else
      -- Procedural atmospheric horizontal fog bands fallback
      for py = 0, canvasH, 16 do
        local offset = (FieldWeather._fogScrollOffset * 2 + py * 4) % 64
        love.graphics.setColor(0.92, 0.95, 1.0, 0.28)
        love.graphics.rectangle("fill", -offset, py, canvasW + 64, 12)
      end
    end
    love.graphics.pop()
  end

  -- 3. WEATHER_RAIN: Falling raindrops and splash particles
  if w == Weather.RAIN or w == Weather.RAIN_THUNDERSTORM or w == Weather.DOWNPOUR then
    love.graphics.push("all")
    love.graphics.setBlendMode("alpha")

    for _, r in ipairs(FieldWeather._rainSprites) do
      if r.state == "falling" then
        love.graphics.setColor(0.75, 0.85, 1.0, 0.85)
        love.graphics.line(r.x, r.y, r.x - 2, r.y + 7)
      elseif r.state == "splash" then
        love.graphics.setColor(0.85, 0.92, 1.0, 0.65 - (r.splashTick * 0.1))
        love.graphics.circle("line", r.x, r.groundY, r.splashTick + 1)
      end
    end

    love.graphics.pop()
  end

  love.graphics.setColor(1, 1, 1, 1)
end

return FieldWeather
