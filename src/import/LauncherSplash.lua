local LauncherSplash = {}
LauncherSplash.__index = LauncherSplash

local DURATION = 127 / 30
local FADE_SECONDS = 0.75
local REVEAL_SECONDS = 0.65

local function smoothstep(value)
  local t = math.max(0, math.min(1, value))
  return t * t * (3 - 2 * t)
end

function LauncherSplash.new()
  local self = setmetatable({ elapsed = 0, age = 0, opacity = 1 }, LauncherSplash)
  local ok, err = pcall(function()
    self.video = love.graphics.newVideo("assets/launcher/splash.ogv", {
      audio = love.audio ~= nil,
    })
    self.video:setFilter("linear", "linear")
    local width, height = self.video:getDimensions()
    self.canvas = love.graphics.newCanvas(width, height)
    self.canvas:setFilter("linear", "linear")
    self.shader = love.graphics.newShader([[
      extern number opacity;
      vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
        vec4 pixel = Texel(texture, uv);
        float brightness = max(pixel.r, max(pixel.g, pixel.b));
        float coverage = smoothstep(0.015, 0.10, brightness);
        return vec4(pixel.rgb, pixel.a * coverage * opacity) * color;
      }
    ]])
    local options = require("src.core.SaveData").loadOptions()
    self.volume = math.max(0, math.min(7, tonumber(options.sfxVol) or 7)) / 7
    local source = self.video:getSource()
    if source then source:setVolume(self.volume) end
    self.video:play()
  end)
  if not ok then
    self:release()
    print("[launcher splash] unavailable: " .. tostring(err))
    return nil
  end
  return self
end

function LauncherSplash:update(dt)
  self.age = self.age + dt
  self.elapsed = self.video:tell()
  self.opacity = 1 - smoothstep((self.elapsed - (DURATION - FADE_SECONDS)) / FADE_SECONDS)
  local source = self.video:getSource()
  if source then source:setVolume(self.volume * self.opacity) end
  -- A decoder that stalls must not prevent access to the launcher.
  return self.elapsed >= DURATION - 0.035 or not self.video:isPlaying()
    or self.age > DURATION + 2
end

function LauncherSplash:draw()
  local g = love.graphics
  local width, height = g.getDimensions()
  local vw, vh = self.video:getDimensions()
  local scale = width / vw
  local backdrop = 1 - smoothstep((self.elapsed - DURATION / 2) / REVEAL_SECONDS)

  g.push("all")
  g.origin()
  g.setScissor()
  g.setShader()
  g.setBlendMode("alpha", "alphamultiply")
  g.setColor(0, 0, 0, backdrop)
  g.rectangle("fill", 0, 0, width, height)

  -- Video supplies YUV planes, so convert through a canvas before keying RGB.
  local target = g.getCanvas()
  g.setCanvas(self.canvas)
  g.clear(0, 0, 0, 0)
  g.setColor(1, 1, 1, 1)
  g.draw(self.video, 0, 0)
  g.setCanvas(target)
  self.shader:send("opacity", self.opacity)
  g.setShader(self.shader)
  g.draw(self.canvas, 0, (height - vh * scale) / 2, 0, scale, scale)
  g.pop()
end

function LauncherSplash:release()
  if self.video then
    self.video:pause()
    local source = self.video:getSource()
    if source then source:stop() end
  end
  for _, key in ipairs({ "video", "canvas", "shader" }) do
    local resource = self[key]
    if resource then resource:release(); self[key] = nil end
  end
end

return LauncherSplash
