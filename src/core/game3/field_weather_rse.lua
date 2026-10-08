-- pokeemerald/src/field_weather.c
-- pokeemerald/src/field_weather_effect.c

local function lazyReq(name)
  local m = package.loaded[name]
  if type(m) == "table" then return m end
  return require(name)
end

local Trig = require("src.core.game3.trig")
local Rng = require("src.core.game3.rng")

local R = {}

local SCREEN_W, SCREEN_H = 240, 160

-- pokeemerald/include/constants/weather.h:4
local WEATHER_NONE = 0
local WEATHER_SUNNY_CLOUDS = 1
local WEATHER_SUNNY = 2
local WEATHER_RAIN = 3
local WEATHER_SNOW = 4
local WEATHER_RAIN_THUNDERSTORM = 5
local WEATHER_FOG_HORIZONTAL = 6
local WEATHER_VOLCANIC_ASH = 7
local WEATHER_SANDSTORM = 8
local WEATHER_FOG_DIAGONAL = 9
local WEATHER_UNDERWATER = 10
local WEATHER_SHADE = 11
local WEATHER_DROUGHT = 12
local WEATHER_DOWNPOUR = 13
local WEATHER_UNDERWATER_BUBBLES = 14

-- pokeemerald/include/constants/field_weather.h:4
local MAX_RAIN_SPRITES = 24
local NUM_CLOUD_SPRITES = 3
local NUM_SNOWFLAKE_SPRITES = 16
local NUM_SWIRL_SANDSTORM_SPRITES = 5
local PAL_CHANGING, PAL_FADING_IN, PAL_FADING_OUT, PAL_IDLE = 0, 1, 2, 3

-- pokeemerald/include/field_weather.h:22
local NUM_WEATHER_COLOR_MAPS = 19
-- pokeemerald/src/field_weather.c:24
local COLOR_MAP_NONE, COLOR_MAP_DARK_CONTRAST, COLOR_MAP_CONTRAST = 0, 1, 2

R.PAL = { CHANGING = PAL_CHANGING, FADING_IN = PAL_FADING_IN, FADING_OUT = PAL_FADING_OUT, IDLE = PAL_IDLE }

local S = {}
R.state = S

local function sine(i)
  return Trig.SINE[(math.floor(i) % 320) + 1]
end

local function random()
  return Rng.Random()
end

local function u16(v) return math.floor(v) % 65536 end
local function s16(v)
  v = math.floor(v) % 65536
  if v >= 32768 then v = v - 65536 end
  return v
end

local function playSe(name)
  local okA, Audio = pcall(lazyReq, "src.core.game3.audio")
  if not (okA and Audio and Audio.playSe) then return end
  local SE = lazyReq("src.core.game3.se_ids")
  local id = SE[name]
  if id then pcall(Audio.playSe, id) end
end

local function weatherPolicy()
  local ok, Profile = pcall(lazyReq, "src.core.game3.profile")
  if not ok then return nil end
  local okRow, row = pcall(Profile.forSession, nil)
  return okRow and type(row) == "table" and type(row.weather) == "table" and row.weather or nil
end

local function sePlaying()
  local Audio = package.loaded["src.core.game3.audio"]
  if Audio and Audio.isSePlaying then
    local ok, v = pcall(Audio.isSePlaying)
    return ok and v == true
  end
  return false
end

-- pokeemerald/src/field_weather.c:271 BuildColorMaps
local function buildColorMaps()
  local maps = { dark = {}, contrast = {} }
  for pass = 0, 1 do
    local out = pass == 0 and maps.dark or maps.contrast
    for i = 0, NUM_WEATHER_COLOR_MAPS - 1 do out[i] = {} end
    for colorVal = 0, 31 do
      local cur = colorVal * 256
      local delta = pass == 0 and math.floor(colorVal * 256 / 16) or 0
      local idx = 0
      while idx < 3 do
        cur = u16(cur - delta)
        out[idx][colorVal] = math.floor(cur / 256)
        idx = idx + 1
      end
      local base = cur
      delta = math.floor(u16(0x1f00 - cur) / (NUM_WEATHER_COLOR_MAPS - 3))
      if colorVal < 12 then
        while idx < NUM_WEATHER_COLOR_MAPS do
          cur = u16(cur + delta)
          local diff = s16(cur - base)
          if diff > 0 then cur = u16(cur - math.floor(diff / 2)) end
          local v = math.floor(cur / 256) % 256
          out[idx][colorVal] = v > 31 and 31 or v
          idx = idx + 1
        end
      else
        while idx < NUM_WEATHER_COLOR_MAPS do
          cur = u16(cur + delta)
          local v = math.floor(cur / 256) % 256
          out[idx][colorVal] = v > 31 and 31 or v
          idx = idx + 1
        end
      end
    end
  end
  return maps
end

R.colorMaps = buildColorMaps()

-- pokeemerald/src/field_weather.c:459 ApplyColorMap
function R.mapColor(r, g, b, index, kind)
  index = tonumber(index) or 0
  if index > 0 then
    local m = (kind == COLOR_MAP_CONTRAST and R.colorMaps.contrast or R.colorMaps.dark)[index - 1]
    return m[r], m[g], m[b]
  elseif index < 0 then
    local t = R.droughtTable(-index - 1)
    if not t then return r, g, b end
    -- pokeemerald/src/field_weather.c:20
    local c = t[math.floor(r / 2) + math.floor(g / 2) * 16 + math.floor(b / 2) * 256]
    return c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32
  end
  return r, g, b
end

local assets = nil
local assetsKey = nil

local function cacheRead(rel)
  local Dataset = lazyReq("src.core.game3.dataset")
  local cache = Dataset.cache and Dataset.cache()
  return cache and cache.read and cache:read(rel) or nil
end

local function loadManifest()
  local body = cacheRead("data/generated/gba/weather/manifest.lua")
  local chunk = body and load(body, "=weather_manifest", "t", {})
  if not chunk then return nil end
  local ok, m = pcall(chunk)
  if ok and type(m) == "table" and m.family == "rse" then return m end
  return nil
end

function R.manifest()
  if not R._manifest then R._manifest = loadManifest() end
  return R._manifest
end

local droughtTables = nil

function R.droughtTable(i)
  if not droughtTables then
    local m = R.manifest()
    local raw = m and m.drought and cacheRead("data/generated/gba/weather/" .. m.drought.file)
    if not raw then return nil end
    droughtTables = {}
    local entries = m.drought.entries or 0x1000
    for t = 0, (m.drought.tables or 6) - 1 do
      local tbl = {}
      local base = t * entries * 2
      for e = 0, entries - 1 do
        local lo, hi = raw:byte(base + e * 2 + 1, base + e * 2 + 2)
        tbl[e] = (lo or 0) + (hi or 0) * 256
      end
      droughtTables[t] = tbl
    end
  end
  return droughtTables[i]
end

local function gfxAvailable()
  return love and love.graphics and love.graphics.newImage and love.image and love.image.newImageData
end

local function imageFromRgba(raw, w, h)
  if not raw or #raw < w * h * 4 then return nil end
  local data = love.image.newImageData(w, h, "rgba8", raw:sub(1, w * h * 4))
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  return img
end

local SPRITE_SHADER = [[
extern Image lut;
extern Image dlut;
extern Image amask;
extern float mode;
extern float row;
extern float dtable;
extern float useMask;
extern vec2 maskSize;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
  vec4 c = Texel(tex, tc);
  if (mode < 0.5 || c.a <= 0.0) return c * color;
  vec3 v = floor(c.rgb * 31.0 + 0.5);
  vec3 o;
  if (mode < 1.5) {
    float r = row;
    if (useMask > 0.5 && r < 18.5 && Texel(amask, sc / maskSize).r > 0.5) r = r + 19.0;
    float y = (r + 0.5) / 38.0;
    o.r = Texel(lut, vec2((v.r + 0.5) / 32.0, y)).r;
    o.g = Texel(lut, vec2((v.g + 0.5) / 32.0, y)).r;
    o.b = Texel(lut, vec2((v.b + 0.5) / 32.0, y)).r;
  } else {
    vec3 h = floor(v / 2.0);
    float x = h.r + mod(h.g, 4.0) * 16.0;
    float yy = floor(h.g / 4.0) + h.b * 4.0 + dtable * 64.0;
    o = Texel(dlut, vec2((x + 0.5) / 64.0, (yy + 0.5) / 384.0)).rgb;
  }
  return vec4(o, c.a) * color;
}
]]

local MASK_SHADER = [[
extern float k;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
  vec4 c = Texel(tex, tc);
  if (c.a <= 0.0) return vec4(1.0, 1.0, 1.0, 1.0);
  return vec4(k, k, k, 1.0);
}
]]

local MASK_WRITE_SHADER = [[
extern float code;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc)
{
  if (Texel(tex, tc).a * color.a <= 0.0) discard;
  return vec4(code, 0.0, 0.0, 1.0);
}
]]

local function rgb8(c5) return math.floor(c5 * 255 / 31 + 0.5) end

local function buildLuts()
  local lut = love.image.newImageData(32, NUM_WEATHER_COLOR_MAPS * 2)
  for i = 0, NUM_WEATHER_COLOR_MAPS - 1 do
    for v = 0, 31 do
      local d = rgb8(R.colorMaps.dark[i][v]) / 255
      local c = rgb8(R.colorMaps.contrast[i][v]) / 255
      lut:setPixel(v, i, d, d, d, 1)
      lut:setPixel(v, NUM_WEATHER_COLOR_MAPS + i, c, c, c, 1)
    end
  end
  local lutImg = love.graphics.newImage(lut)
  lutImg:setFilter("nearest", "nearest")
  local dl = love.image.newImageData(64, 384)
  for t = 0, 5 do
    local tbl = R.droughtTable(t)
    if tbl then
      for e = 0, 4095 do
        local c = tbl[e]
        dl:setPixel(e % 64, t * 64 + math.floor(e / 64), rgb8(c % 32) / 255,
          rgb8(math.floor(c / 32) % 32) / 255, rgb8(math.floor(c / 1024) % 32) / 255, 1)
      end
    end
  end
  local dlImg = love.graphics.newImage(dl)
  dlImg:setFilter("nearest", "nearest")
  return lutImg, dlImg
end

local function loadAssets()
  if not gfxAvailable() then return nil end
  local key = tostring(lazyReq("src.import.CacheFs").prefix)
  if assets and assetsKey == key then return assets end
  local m = R.manifest()
  if not m then return nil end
  local out = { sheets = {} }
  for name, b in pairs(m.blobs or {}) do
    local raw = cacheRead("data/generated/gba/weather/" .. b.file)
    local img = raw and imageFromRgba(raw, b.w, b.h)
    if img then
      out.sheets[name] = { image = img, w = b.w, h = b.h, cols = math.floor(b.w / 8), quads = {} }
    end
  end
  local okS, shader = pcall(love.graphics.newShader, SPRITE_SHADER)
  local okM, mask = pcall(love.graphics.newShader, MASK_SHADER)
  local okW, maskWrite = pcall(love.graphics.newShader, MASK_WRITE_SHADER)
  if okS and okM then
    out.shader, out.mask = shader, mask
    if okW then out.maskWrite = maskWrite end
    out.lut, out.dlut = buildLuts()
    shader:send("lut", out.lut)
    shader:send("dlut", out.dlut)
  end
  assets, assetsKey = out, key
  return assets
end

function R.invalidate()
  assets, assetsKey = nil, nil
  R._manifest = nil
  droughtTables = nil
  R._tmpCanvas = nil
end


local ANIMS = {
  -- pokeemerald/src/field_weather_effect.c:408
  rain = { { { 0, 16 }, "loop" }, { { 8, 3 }, { 32, 2 }, { 40, 2 }, "end" }, { { 8, 3 }, { 16, 3 }, { 24, 4 }, "end" } },
  -- pokeemerald/src/field_weather_effect.c:860
  snow = { { { 0, 16 }, "end" }, { { 1, 16 }, "end" } },
  -- pokeemerald/src/field_weather_effect.c:73
  cloud = { { { 0, 16 }, "end" } },
  -- pokeemerald/src/field_weather_effect.c:1629
  ash = { { { 0, 60 }, { 64, 60 }, "loop" } },
  -- pokeemerald/src/field_weather_effect.c:2087
  sandstorm = { { { 0, 3 }, "end" }, { { 64, 3 }, "end" } },
  -- pokeemerald/src/field_weather_effect.c:2348
  bubble = { { { 0, 16 }, { 1, 16 }, "end" } },
  still = { { { 0, 16 }, "end" } },
}

local function newSprite(kind, x, y, w, h, opts)
  local s = {
    kind = kind, x = x or 0, y = y or 0, x2 = 0, y2 = 0, w = w, h = h,
    cx = -math.floor(w / 2), cy = -math.floor(h / 2),
    invisible = false, coordOffsetEnabled = false, data = {},
    anims = ANIMS[(opts and opts.anims) or kind] or ANIMS.still,
    animNum = 1, animBegin = true, animEnded = false, frame = 0, delay = 0, animCmd = 1,
    priority = opts and opts.priority or 1, blend = opts and opts.blend or false,
    sheet = opts and opts.sheet or kind, inUse = true,
  }
  s.cb = opts and opts.cb or nil
  return s
end

local function startAnim(s, n)
  s.animNum = n + 1
  s.animBegin = true
  s.animEnded = false
end

-- pokeemerald/src/sprite.c:901 AnimateSprite
local function animate(s)
  local cmds = s.anims[s.animNum]
  if not cmds then return end
  if s.animBegin then
    s.animBegin = false
    s.animCmd = 1
    local c = cmds[1]
    s.frame, s.delay = c[1], c[2] - 1
    return
  end
  if s.animEnded then return end
  if s.delay > 0 then
    s.delay = s.delay - 1
    return
  end
  s.animCmd = s.animCmd + 1
  local c = cmds[s.animCmd]
  if c == "end" then
    s.animEnded = true
    s.animCmd = s.animCmd - 1
    return
  end
  if c == "loop" then
    s.animCmd = 1
    c = cmds[1]
  end
  s.frame, s.delay = c[1], c[2] - 1
end

local function runSprites(list)
  local i = 1
  while i <= #list do
    local s = list[i]
    if s.inUse and s.cb then s.cb(s) end
    if s.inUse then animate(s) end
    if not s.inUse then
      table.remove(list, i)
    else
      i = i + 1
    end
  end
end

local function destroySprite(s)
  s.inUse = false
end


local function blankState()
  for k in pairs(S) do S[k] = nil end
  S.started = false
  S.currWeather = WEATHER_NONE
  S.nextWeather = WEATHER_NONE
  S.readyForInit = false
  S.initialized = false
  S.weatherChangeComplete = true
  S.palProcessingState = PAL_IDLE
  S.colorMapIndex = 0
  S.targetColorMapIndex = 0
  S.colorMapStepDelay = 0
  S.colorMapStepCounter = 0
  S.initStep, S.finishStep = 0, 0
  S.weatherGfxLoaded = false
  S.currBlendEVA, S.currBlendEVB, S.targetBlendEVA, S.targetBlendEVB = 16, 0, 16, 0
  S.blendDelay, S.blendFrameCounter, S.blendUpdateCounter = 0, 0, 0
  S.rainSprites = {}
  S.rainSpriteCount, S.curRainSpriteIndex, S.targetRainSpriteCount = 0, 0, 0
  S.rainSpriteVisibleCounter, S.rainSpriteVisibleDelay = 0, 0
  S.isDownpour = 0
  S.rainStrength = 0
  S.snowSprites = {}
  S.snowflakeSpriteCount, S.targetSnowflakeSpriteCount, S.snowflakeVisibleCounter, S.snowflakeTimer = 0, 0, 0, 0
  S.cloudSprites = {}
  S.cloudSpritesCreated = false
  S.thunderTimer, S.thunderSETimer = 0, 0
  S.thunderAllowEnd, S.thunderLongBolt, S.thunderShortBolts, S.thunderEnqueued = false, 0, 0, false
  S.fogHSpritesCreated = false
  S.fogHScrollPosX, S.fogHScrollCounter, S.fogHScrollOffset = 0, 0, 0
  S.ashSpritesCreated = false
  S.ashBaseSpritesX, S.ashCounterY, S.ashOffsetY, S.ashAnim = 0, 0, 0, nil
  S.sandstormSpritesCreated, S.sandstormSwirlSpritesCreated = false, false
  S.sandstormXOffset, S.sandstormYOffset = 0, 0
  S.sandstormBaseSpritesX, S.sandstormPosY = 0, 0
  S.sandstormWaveIndex, S.sandstormWaveCounter = 0, 0
  S.swirlSprites = {}
  S.fogDSpritesCreated = false
  S.fogDBaseSpritesX, S.fogDPosY = 0, 0
  S.fogDScrollXCounter, S.fogDScrollYCounter, S.fogDXOffset, S.fogDYOffset = 0, 0, 0, 0
  S.bubbleSprites = {}
  S.bubblesSpritesCreated = false
  S.bubblesDelayCounter, S.bubblesDelayIndex, S.bubblesCoordsIndex, S.bubblesSpriteCount = 0, 0, 0, 0
  S.droughtBrightnessStage, S.droughtLastBrightnessStage, S.droughtTimer, S.droughtState = 0, 0, 0, 0
  S.totalCamX, S.totalCamY = 0, 0
  S.lastCamX, S.lastCamY = nil, nil
  S.offX, S.offY = 0, -40
  S.abnormal = nil
  S.currentAbnormal = WEATHER_DOWNPOUR
  S.frames = 0
end

blankState()

-- pokeemerald/src/field_weather.c:939
local function setBlendCoeffs(eva, evb)
  S.currBlendEVA, S.currBlendEVB = eva, evb
  S.targetBlendEVA, S.targetBlendEVB = eva, evb
end

-- pokeemerald/src/field_weather.c:948
local function setTargetBlendCoeffs(eva, evb, delay)
  S.targetBlendEVA, S.targetBlendEVB = eva, evb
  S.blendDelay = delay
  S.blendFrameCounter = 0
  S.blendUpdateCounter = 0
end

-- pokeemerald/src/field_weather.c:957
local function updateBlend()
  if S.currBlendEVA == S.targetBlendEVA and S.currBlendEVB == S.targetBlendEVB then return true end
  S.blendFrameCounter = S.blendFrameCounter + 1
  if S.blendFrameCounter > S.blendDelay then
    S.blendFrameCounter = 0
    S.blendUpdateCounter = (S.blendUpdateCounter + 1) % 256
    if S.blendUpdateCounter % 2 == 1 then
      if S.currBlendEVA < S.targetBlendEVA then S.currBlendEVA = S.currBlendEVA + 1
      elseif S.currBlendEVA > S.targetBlendEVA then S.currBlendEVA = S.currBlendEVA - 1 end
    else
      if S.currBlendEVB < S.targetBlendEVB then S.currBlendEVB = S.currBlendEVB + 1
      elseif S.currBlendEVB > S.targetBlendEVB then S.currBlendEVB = S.currBlendEVB - 1 end
    end
  end
  return S.currBlendEVA == S.targetBlendEVA and S.currBlendEVB == S.targetBlendEVB
end

-- pokeemerald/src/field_weather.c:715
function R.applyColorMapIfIdle(index)
  if S.palProcessingState == PAL_IDLE then
    S.colorMapIndex = index
  end
end

-- pokeemerald/src/field_weather.c:724
function R.applyColorMapIfIdleGradual(index, target, delay)
  if S.palProcessingState == PAL_IDLE then
    S.palProcessingState = PAL_CHANGING
    S.colorMapIndex = index
    S.targetColorMapIndex = target
    S.colorMapStepCounter = 0
    S.colorMapStepDelay = delay
  end
end

-- pokeemerald/src/field_weather.c:1037
local function setRainStrengthFromSoundEffect(name)
  if S.palProcessingState == PAL_FADING_OUT then return end
  if name == "SE_RAIN" then S.rainStrength = 0
  elseif name == "SE_DOWNPOUR" then S.rainStrength = 1
  elseif name == "SE_THUNDERSTORM" then S.rainStrength = 2
  else return end
  playSe(name)
end

-- pokeemerald/src/field_weather.c:1060
function R.playRainStoppingSoundEffect()
  local Audio = package.loaded["src.core.game3.audio"]
  -- pokeruby/src/field_weather.c:1214
  if not (Audio and Audio.isSpecialSePlaying and Audio.isSpecialSePlaying()) then return end
  if S.rainStrength == 0 then playSe("SE_RAIN_STOP")
  elseif S.rainStrength == 1 then playSe("SE_DOWNPOUR_STOP")
  else playSe("SE_THUNDERSTORM_STOP") end
end


-- pokeemerald/src/field_weather_effect.c:42
local CLOUD_MAP_COORDS = { { 0, 66 }, { 5, 73 }, { 10, 78 } }

-- pokeemerald/src/field_weather_effect.c:220
local function updateCloudSprite(s)
  s.data[0] = (s.data[0] + 1) % 2
  if s.data[0] == 1 then s.x = s.x - 1 end
end

-- pokeemerald/src/field_weather_effect.c:173
local function createCloudSprites()
  if S.cloudSpritesCreated then return end
  for i = 1, NUM_CLOUD_SPRITES do
    local c = CLOUD_MAP_COORDS[i]
    local s = newSprite("cloud", 0, 0, 64, 64, { priority = 3, blend = true, cb = updateCloudSprite })
    s.data[0] = 0
    s.world = true
    s.worldX = c[1] * 16
    s.worldY = c[2] * 16
    S.cloudSprites[#S.cloudSprites + 1] = s
  end
  S.cloudSpritesCreated = true
end

local function destroyCloudSprites()
  if not S.cloudSpritesCreated then return end
  S.cloudSprites = {}
  S.cloudSpritesCreated = false
end

local function Clouds_InitVars()
  S.targetColorMapIndex = 0
  S.colorMapStepDelay = 20
  S.weatherGfxLoaded = false
  S.initStep = 0
  if not S.cloudSpritesCreated then setBlendCoeffs(0, 16) end
end

local function Clouds_Main()
  if S.initStep == 0 then
    createCloudSprites()
    S.initStep = S.initStep + 1
  elseif S.initStep == 1 then
    setTargetBlendCoeffs(12, 8, 1)
    S.initStep = S.initStep + 1
  elseif S.initStep == 2 then
    if updateBlend() then
      S.weatherGfxLoaded = true
      S.initStep = S.initStep + 1
    end
  end
end

local function Clouds_InitAll()
  Clouds_InitVars()
  while not S.weatherGfxLoaded do Clouds_Main() end
end

local function Clouds_Finish()
  if S.finishStep == 0 then
    setTargetBlendCoeffs(0, 16, 1)
    S.finishStep = S.finishStep + 1
    return true
  elseif S.finishStep == 1 then
    if updateBlend() then
      destroyCloudSprites()
      S.finishStep = S.finishStep + 1
    end
    return true
  end
  return false
end

local function Sunny_InitVars()
  S.targetColorMapIndex = 0
  S.colorMapStepDelay = 20
end


-- pokeemerald/src/field_weather.c:890
local function setDroughtColorMap(index)
  R.applyColorMapIfIdle(-index - 1)
end

local function droughtStateInit()
  S.droughtBrightnessStage = 0
  S.droughtTimer = 0
  S.droughtState = 0
  S.droughtLastBrightnessStage = 0
end

-- pokeemerald/src/field_weather.c:903
local function droughtStateRun()
  if S.droughtState == 0 then
    S.droughtTimer = S.droughtTimer + 1
    if S.droughtTimer > 5 then
      S.droughtTimer = 0
      setDroughtColorMap(S.droughtBrightnessStage)
      S.droughtBrightnessStage = S.droughtBrightnessStage + 1
      if S.droughtBrightnessStage > 5 then
        S.droughtLastBrightnessStage = S.droughtBrightnessStage
        S.droughtState = 1
        S.droughtTimer = 60
      end
    end
  elseif S.droughtState == 1 then
    S.droughtTimer = (S.droughtTimer + 3) % 128
    S.droughtBrightnessStage = math.floor((sine(S.droughtTimer) - 1) / 64) + 2
    if S.droughtBrightnessStage ~= S.droughtLastBrightnessStage then
      setDroughtColorMap(S.droughtBrightnessStage)
    end
    S.droughtLastBrightnessStage = S.droughtBrightnessStage
  elseif S.droughtState == 2 then
    S.droughtTimer = S.droughtTimer + 1
    if S.droughtTimer > 5 then
      S.droughtTimer = 0
      S.droughtBrightnessStage = S.droughtBrightnessStage - 1
      setDroughtColorMap(S.droughtBrightnessStage)
      if S.droughtBrightnessStage == 3 then S.droughtState = 0 end
    end
  end
end

local function Drought_InitVars()
  S.initStep = 0
  S.weatherGfxLoaded = false
  S.targetColorMapIndex = 0
  S.colorMapStepDelay = 0
end

-- pokeemerald/src/field_weather_effect.c:249
local function Drought_Main()
  if S.initStep == 0 then
    if S.palProcessingState ~= PAL_CHANGING then S.initStep = S.initStep + 1 end
  elseif S.initStep == 1 then
    S.droughtLoadFrames = 0
    S.initStep = S.initStep + 1
  elseif S.initStep == 2 then
    S.droughtLoadFrames = (S.droughtLoadFrames or 0) + 1
    local policy = weatherPolicy()
    -- pokeruby/src/field_weather.c:1033
    if S.droughtLoadFrames >= (policy and policy.droughtPaletteLoadFrames or 1) then S.initStep = S.initStep + 1 end
  elseif S.initStep == 3 then
    droughtStateInit()
    S.initStep = S.initStep + 1
  elseif S.initStep == 4 then
    droughtStateRun()
    if S.droughtBrightnessStage == 6 then
      S.weatherGfxLoaded = true
      S.initStep = S.initStep + 1
    end
  else
    droughtStateRun()
  end
end

local function Drought_InitAll()
  Drought_InitVars()
  local guard = 0
  while not S.weatherGfxLoaded and guard < 4096 do
    Drought_Main()
    guard = guard + 1
  end
end


-- pokeemerald/src/field_weather_effect.c:363
local RAIN_COORDS = {
  { 0, 0 }, { 0, 160 }, { 0, 64 }, { 144, 224 }, { 144, 128 }, { 32, 32 }, { 32, 192 }, { 32, 96 },
  { 72, 128 }, { 72, 32 }, { 72, 192 }, { 216, 96 }, { 216, 0 }, { 104, 160 }, { 104, 64 }, { 104, 224 },
  { 144, 0 }, { 144, 160 }, { 144, 64 }, { 32, 224 }, { 32, 128 }, { 72, 32 }, { 72, 192 }, { 48, 96 },
}
-- pokeemerald/src/field_weather_effect.c:449
local RAIN_MOVEMENT = { [0] = { -0x68, 0xD0 }, [1] = { -0xA0, 0x140 } }
-- pokeemerald/src/field_weather_effect.c:458
local RAIN_DURATIONS = { [0] = { 18, 7 }, [1] = { 12, 10 } }

local updateRainSprite

-- pokeemerald/src/field_weather_effect.c:551
local function startRainSpriteFall(s)
  local d = s.data
  if d.random == 0 then d.random = 361 end
  local rand = (Rng.mulU32(d.random, 1103515245) + 12345) % 4294967296
  d.random = (math.floor(rand / 65536) % 32768) % 600
  local frames = RAIN_DURATIONS[S.isDownpour][1]
  local tileX = d.random % 30
  local tileY = math.floor(d.random / 30)
  d.posX = s16(tileX * 128 - RAIN_MOVEMENT[S.isDownpour][1] * frames)
  d.posY = s16(tileY * 128 - RAIN_MOVEMENT[S.isDownpour][2] * frames)
  startAnim(s, 0)
  d.state = 0
  s.coordOffsetEnabled = false
  d.counter = frames
end

-- pokeemerald/src/field_weather_effect.c:588
updateRainSprite = function(s)
  local d = s.data
  if d.state == 0 then
    d.posX = s16(d.posX + RAIN_MOVEMENT[S.isDownpour][1])
    d.posY = s16(d.posY + RAIN_MOVEMENT[S.isDownpour][2])
    s.x = math.floor(d.posX / 16)
    s.y = math.floor(d.posY / 16)
    if d.active and s.x >= -8 and s.x <= SCREEN_W + 8 and s.y >= -16 and s.y <= SCREEN_H + 16 then
      s.invisible = false
    else
      s.invisible = true
    end
    d.counter = d.counter - 1
    if d.counter == 0 then
      startAnim(s, S.isDownpour + 1)
      d.state = 1
      s.x = s.x - S.offX
      s.y = s.y - S.offY
      s.coordOffsetEnabled = true
    end
  elseif s.animEnded then
    s.invisible = true
    startRainSpriteFall(s)
  end
end

-- pokeemerald/src/field_weather_effect.c:623
local function waitRainSprite(s)
  if s.data.counter == 0 then
    startRainSpriteFall(s)
    s.cb = updateRainSprite
  else
    s.data.counter = s.data.counter - 1
  end
end

-- pokeemerald/src/field_weather_effect.c:636
local function initRainSpriteMovement(s, val)
  local frames = RAIN_DURATIONS[S.isDownpour][1]
  local period = RAIN_DURATIONS[S.isDownpour][2] + frames
  local advance = math.floor(val / period)
  local frameVal = val % period
  for _ = 1, advance do startRainSpriteFall(s) end
  if frameVal < frames then
    for _ = 1, frameVal do updateRainSprite(s) end
    s.data.waiting = false
  else
    s.data.counter = frameVal - frames
    s.invisible = true
    s.data.waiting = true
  end
end

-- pokeemerald/src/field_weather_effect.c:665
local function createRainSprite()
  if S.rainSpriteCount == MAX_RAIN_SPRITES then return false end
  local index = S.rainSpriteCount
  local c = RAIN_COORDS[index + 1]
  local s = newSprite("rain", c[1], c[2], 16, 32, { priority = 1, cb = updateRainSprite })
  s.data.active = false
  s.data.random = index * 145
  while s.data.random >= 600 do s.data.random = s.data.random - 600 end
  startRainSpriteFall(s)
  initRainSpriteMovement(s, index * 9)
  s.invisible = true
  S.rainSprites[index + 1] = s
  S.rainSpriteCount = S.rainSpriteCount + 1
  if S.rainSpriteCount == MAX_RAIN_SPRITES then
    for i = 1, MAX_RAIN_SPRITES do
      local r = S.rainSprites[i]
      if r then r.cb = r.data.waiting and waitRainSprite or updateRainSprite end
    end
    return false
  end
  return true
end

-- pokeemerald/src/field_weather_effect.c:714
local function updateVisibleRainSprites()
  if S.curRainSpriteIndex == S.targetRainSpriteCount then return false end
  S.rainSpriteVisibleCounter = S.rainSpriteVisibleCounter + 1
  if S.rainSpriteVisibleCounter > S.rainSpriteVisibleDelay then
    S.rainSpriteVisibleCounter = 0
    if S.curRainSpriteIndex < S.targetRainSpriteCount then
      S.curRainSpriteIndex = S.curRainSpriteIndex + 1
      local r = S.rainSprites[S.curRainSpriteIndex]
      if r then r.data.active = true end
    else
      local r = S.rainSprites[S.curRainSpriteIndex]
      S.curRainSpriteIndex = S.curRainSpriteIndex - 1
      if r then
        r.data.active = false
        r.invisible = true
      end
    end
  end
  return true
end

local function destroyRainSprites()
  S.rainSprites = {}
  S.rainSpriteCount = 0
end

local function Rain_InitVars()
  S.initStep = 0
  S.weatherGfxLoaded = false
  S.rainSpriteVisibleCounter = 0
  S.rainSpriteVisibleDelay = 8
  S.isDownpour = 0
  S.targetRainSpriteCount = 10
  S.targetColorMapIndex = 3
  S.colorMapStepDelay = 20
  setRainStrengthFromSoundEffect("SE_RAIN")
end

local function Rain_Main()
  if S.initStep == 0 then
    S.initStep = S.initStep + 1
  elseif S.initStep == 1 then
    if not createRainSprite() then S.initStep = S.initStep + 1 end
  elseif S.initStep == 2 then
    if not updateVisibleRainSprites() then
      S.weatherGfxLoaded = true
      S.initStep = S.initStep + 1
    end
  end
end

local function Rain_InitAll()
  Rain_InitVars()
  while not S.weatherGfxLoaded do Rain_Main() end
end

local function isRainy(w)
  return w == WEATHER_RAIN or w == WEATHER_RAIN_THUNDERSTORM or w == WEATHER_DOWNPOUR
end

-- pokeemerald/src/field_weather_effect.c:513
local function Rain_Finish()
  if S.finishStep == 0 then
    if isRainy(S.nextWeather) then
      S.finishStep = 0xFF
      return false
    end
    S.targetRainSpriteCount = 0
    S.finishStep = 1
  end
  if S.finishStep == 1 then
    if not updateVisibleRainSprites() then
      destroyRainSprites()
      S.finishStep = S.finishStep + 1
      return false
    end
    return true
  end
  return false
end


local updateSnowflakeSprite

-- pokeemerald/src/field_weather_effect.c:922
local function initSnowflakeSpriteMovement(s)
  local d = s.data
  local x = ((d.id * 5) % 8) * 30 + (random() % 30)
  s.y = -3 - (S.offY + s.cy)
  s.x = x - (S.offX + s.cx)
  d.posY = s.y * 128
  s.x2 = 0
  local rand = random()
  d.deltaY = (rand % 4) * 5 + 64
  d.deltaY2 = d.deltaY
  startAnim(s, (rand % 2 == 1) and 0 or 1)
  d.waveIndex = 0
  d.waveDelta = (rand % 4 == 0) and 2 or 1
  d.fallDuration = (rand % 32) + 210
  d.fallCounter = 0
end

local function waitSnowflakeSprite(s)
  if S.snowflakeTimer > 18 then
    s.invisible = false
    s.cb = updateSnowflakeSprite
    s.y = 250 - (S.offY + s.cy)
    s.data.posY = s.y * 128
    S.snowflakeTimer = 0
  end
end

-- pokeemerald/src/field_weather_effect.c:954
updateSnowflakeSprite = function(s)
  local d = s.data
  d.posY = s16(d.posY + d.deltaY)
  s.y = math.floor(d.posY / 128)
  d.waveIndex = (d.waveIndex + d.waveDelta) % 256
  local sv = sine(d.waveIndex)
  s.x2 = sv >= 0 and math.floor(sv / 64) or -math.floor(-sv / 64)
  local x = (s.x + s.cx + S.offX) % 512
  if x >= 256 then x = x - 512 end
  if x < -3 then
    s.x = 242 - (S.offX + s.cx)
  elseif x > 242 then
    s.x = -3 - (S.offX + s.cx)
  end
  local y = (s.y + s.cy + S.offY) % 256
  if y > 163 and y < 171 then
    s.y = 250 - (S.offY + s.cy)
    d.posY = s.y * 128
    d.fallCounter = 0
    d.fallDuration = 220
  elseif y > 242 and y < 250 then
    s.y = 163
    d.posY = s.y * 128
    d.fallCounter = 0
    d.fallDuration = 220
    s.invisible = true
    s.cb = waitSnowflakeSprite
  end
  d.fallCounter = d.fallCounter + 1
  if d.fallCounter == d.fallDuration then
    initSnowflakeSpriteMovement(s)
    s.y = 250
    s.invisible = true
    s.cb = waitSnowflakeSprite
  end
end

-- pokeemerald/src/field_weather_effect.c:898
local function createSnowflakeSprite()
  local s = newSprite("snow", 0, 0, 8, 8, { priority = 1, cb = updateSnowflakeSprite })
  s.data.id = S.snowflakeSpriteCount
  initSnowflakeSpriteMovement(s)
  s.coordOffsetEnabled = true
  S.snowSprites[#S.snowSprites + 1] = s
  S.snowflakeSpriteCount = S.snowflakeSpriteCount + 1
  return true
end

local function destroySnowflakeSprite()
  if S.snowflakeSpriteCount > 0 then
    local s = table.remove(S.snowSprites)
    if s then destroySprite(s) end
    S.snowflakeSpriteCount = S.snowflakeSpriteCount - 1
    return true
  end
  return false
end

-- pokeemerald/src/field_weather_effect.c:820
local function updateVisibleSnowflakeSprites()
  if S.snowflakeSpriteCount == S.targetSnowflakeSpriteCount then return false end
  S.snowflakeVisibleCounter = S.snowflakeVisibleCounter + 1
  if S.snowflakeVisibleCounter > 36 then
    S.snowflakeVisibleCounter = 0
    if S.snowflakeSpriteCount < S.targetSnowflakeSpriteCount then
      createSnowflakeSprite()
    else
      destroySnowflakeSprite()
    end
  end
  return S.snowflakeSpriteCount ~= S.targetSnowflakeSpriteCount
end

local function Snow_InitVars()
  S.initStep = 0
  S.weatherGfxLoaded = false
  S.targetColorMapIndex = 3
  S.colorMapStepDelay = 20
  S.targetSnowflakeSpriteCount = NUM_SNOWFLAKE_SPRITES
  S.snowflakeVisibleCounter = 0
end

local function Snow_Main()
  if S.initStep == 0 and not updateVisibleSnowflakeSprites() then
    S.weatherGfxLoaded = true
    S.initStep = S.initStep + 1
  end
end

local function Snow_InitAll()
  Snow_InitVars()
  while not S.weatherGfxLoaded do
    Snow_Main()
    for _, s in ipairs(S.snowSprites) do updateSnowflakeSprite(s) end
  end
end

local function Snow_Finish()
  if S.finishStep == 0 then
    S.targetSnowflakeSpriteCount = 0
    S.snowflakeVisibleCounter = 0
    S.finishStep = 1
  end
  if S.finishStep == 1 then
    if not updateVisibleSnowflakeSprites() then
      S.finishStep = S.finishStep + 1
      return false
    end
    return true
  end
  return false
end


local THUNDER = {
  LOAD_RAIN = 0, CREATE_RAIN = 1, INIT_RAIN = 2, WAIT_CHANGE = 3,
  NEW_CYCLE = 4, NEW_CYCLE_WAIT = 5, INIT_CYCLE_1 = 6, INIT_CYCLE_2 = 7,
  SHORT_BOLT = 8, TRY_NEW_BOLT = 9, WAIT_BOLT_SHORT = 10, INIT_BOLT_LONG = 11,
  WAIT_BOLT_LONG = 12, FADE_BOLT_LONG = 13, END_BOLT_LONG = 14,
}

-- pokeemerald/src/field_weather_effect.c:1242
local function enqueueThunder(waitFrames)
  if not S.thunderEnqueued then
    S.thunderSETimer = random() % waitFrames
    S.thunderEnqueued = true
  end
end

-- pokeemerald/src/field_weather_effect.c:1251
local function updateThunderSound()
  if S.thunderEnqueued then
    if S.thunderSETimer == 0 then
      if sePlaying() then return end
      if random() % 2 == 1 then playSe("SE_THUNDER") else playSe("SE_THUNDER2") end
      S.thunderEnqueued = false
    else
      S.thunderSETimer = S.thunderSETimer - 1
    end
  end
end

local function Thunderstorm_InitVars()
  S.initStep = THUNDER.LOAD_RAIN
  S.weatherGfxLoaded = false
  S.rainSpriteVisibleCounter = 0
  S.rainSpriteVisibleDelay = 4
  S.isDownpour = 0
  S.targetRainSpriteCount = 16
  S.targetColorMapIndex = 3
  S.colorMapStepDelay = 20
  S.thunderEnqueued = false
  setRainStrengthFromSoundEffect("SE_THUNDERSTORM")
end

local function Downpour_InitVars()
  S.initStep = THUNDER.LOAD_RAIN
  S.weatherGfxLoaded = false
  S.rainSpriteVisibleCounter = 0
  S.rainSpriteVisibleDelay = 4
  S.isDownpour = 1
  S.targetRainSpriteCount = 24
  S.targetColorMapIndex = 3
  S.colorMapStepDelay = 20
  setRainStrengthFromSoundEffect("SE_DOWNPOUR")
end

local function dec16(v) return u16(v - 1) end

-- pokeemerald/src/field_weather_effect.c:1092
local function Thunderstorm_Main()
  updateThunderSound()
  local st = S.initStep
  if st == THUNDER.LOAD_RAIN then
    S.initStep = st + 1
  elseif st == THUNDER.CREATE_RAIN then
    if not createRainSprite() then S.initStep = st + 1 end
  elseif st == THUNDER.INIT_RAIN then
    if not updateVisibleRainSprites() then
      S.weatherGfxLoaded = true
      S.initStep = st + 1
    end
  elseif st == THUNDER.WAIT_CHANGE then
    if S.palProcessingState ~= PAL_CHANGING then S.initStep = THUNDER.INIT_CYCLE_1 end
  elseif st == THUNDER.NEW_CYCLE or st == THUNDER.NEW_CYCLE_WAIT then
    if st == THUNDER.NEW_CYCLE then
      S.thunderAllowEnd = true
      S.thunderTimer = (random() % 360) + 360
      S.initStep = THUNDER.NEW_CYCLE_WAIT
    end
    S.thunderTimer = dec16(S.thunderTimer)
    if S.thunderTimer == 0 then S.initStep = S.initStep + 1 end
  elseif st == THUNDER.INIT_CYCLE_1 then
    S.thunderAllowEnd = true
    S.thunderLongBolt = random() % 2
    S.initStep = st + 1
  elseif st == THUNDER.INIT_CYCLE_2 or st == THUNDER.SHORT_BOLT then
    if st == THUNDER.INIT_CYCLE_2 then
      S.thunderShortBolts = (random() % 2) + 1
    end
    R.applyColorMapIfIdle(19)
    if S.thunderLongBolt == 0 and S.thunderShortBolts == 1 then enqueueThunder(20) end
    S.thunderTimer = (random() % 3) + 6
    S.initStep = THUNDER.TRY_NEW_BOLT
  elseif st == THUNDER.TRY_NEW_BOLT then
    S.thunderTimer = dec16(S.thunderTimer)
    if S.thunderTimer == 0 then
      R.applyColorMapIfIdle(3)
      S.thunderAllowEnd = true
      S.thunderShortBolts = (S.thunderShortBolts - 1) % 256
      if S.thunderShortBolts ~= 0 then
        S.thunderTimer = (random() % 16) + 60
        S.initStep = THUNDER.WAIT_BOLT_SHORT
      elseif S.thunderLongBolt == 0 then
        S.initStep = THUNDER.NEW_CYCLE
      else
        S.initStep = THUNDER.INIT_BOLT_LONG
      end
    end
  elseif st == THUNDER.WAIT_BOLT_SHORT then
    S.thunderTimer = dec16(S.thunderTimer)
    if S.thunderTimer == 0 then S.initStep = THUNDER.SHORT_BOLT end
  elseif st == THUNDER.INIT_BOLT_LONG then
    S.thunderTimer = (random() % 16) + 60
    S.initStep = st + 1
  elseif st == THUNDER.WAIT_BOLT_LONG then
    S.thunderTimer = dec16(S.thunderTimer)
    if S.thunderTimer == 0 then
      enqueueThunder(100)
      R.applyColorMapIfIdle(19)
      S.thunderTimer = (random() % 16) + 30
      S.initStep = st + 1
    end
  elseif st == THUNDER.FADE_BOLT_LONG then
    S.thunderTimer = dec16(S.thunderTimer)
    if S.thunderTimer == 0 then
      R.applyColorMapIfIdleGradual(19, 3, 5)
      S.initStep = st + 1
    end
  elseif st == THUNDER.END_BOLT_LONG then
    if S.palProcessingState == PAL_IDLE then
      S.thunderAllowEnd = true
      S.initStep = THUNDER.NEW_CYCLE
    end
  end
end

local function Thunderstorm_InitAll()
  Thunderstorm_InitVars()
  while not S.weatherGfxLoaded do Thunderstorm_Main() end
end

local function Downpour_InitAll()
  Downpour_InitVars()
  while not S.weatherGfxLoaded do Thunderstorm_Main() end
end

-- pokeemerald/src/field_weather_effect.c:1205
local function Thunderstorm_Finish()
  if S.finishStep == 0 then
    S.thunderAllowEnd = false
    S.finishStep = 1
  end
  if S.finishStep == 1 then
    Thunderstorm_Main()
    if S.thunderAllowEnd then
      if isRainy(S.nextWeather) then return false end
      S.targetRainSpriteCount = 0
      S.finishStep = S.finishStep + 1
    end
  elseif S.finishStep == 2 then
    if not updateVisibleRainSprites() then
      destroyRainSprites()
      S.thunderEnqueued = false
      S.finishStep = S.finishStep + 1
      return false
    end
  else
    return false
  end
  return true
end


local function scrollFogH()
  S.fogHScrollPosX = (S.offX - S.fogHScrollOffset) % 256
  S.fogHScrollCounter = S.fogHScrollCounter + 1
  if S.fogHScrollCounter > 3 then
    S.fogHScrollCounter = 0
    S.fogHScrollOffset = u16(S.fogHScrollOffset + 1)
  end
end

local function FogHorizontal_InitVars()
  S.initStep = 0
  S.weatherGfxLoaded = false
  S.targetColorMapIndex = 0
  S.colorMapStepDelay = 20
  if not S.fogHSpritesCreated then
    S.fogHScrollCounter = 0
    S.fogHScrollOffset = 0
    S.fogHScrollPosX = 0
    setBlendCoeffs(0, 16)
  end
end

-- pokeemerald/src/field_weather_effect.c:1392
local function FogHorizontal_Main()
  scrollFogH()
  if S.initStep == 0 then
    S.fogHSpritesCreated = true
    if S.currWeather == WEATHER_FOG_HORIZONTAL then
      setTargetBlendCoeffs(12, 8, 3)
    else
      setTargetBlendCoeffs(4, 16, 0)
    end
    S.initStep = S.initStep + 1
  elseif S.initStep == 1 then
    if updateBlend() then
      S.weatherGfxLoaded = true
      S.initStep = S.initStep + 1
    end
  end
end

local function FogHorizontal_InitAll()
  FogHorizontal_InitVars()
  while not S.weatherGfxLoaded do FogHorizontal_Main() end
end

-- pokeemerald/src/field_weather_effect.c:1420
local function FogHorizontal_Finish()
  scrollFogH()
  if S.finishStep == 0 then
    setTargetBlendCoeffs(0, 16, 3)
    S.finishStep = S.finishStep + 1
  elseif S.finishStep == 1 then
    if updateBlend() then S.finishStep = S.finishStep + 1 end
  elseif S.finishStep == 2 then
    S.fogHSpritesCreated = false
    S.finishStep = S.finishStep + 1
  else
    return false
  end
  return true
end


local function Ash_InitVars()
  S.initStep = 0
  S.weatherGfxLoaded = false
  S.targetColorMapIndex = 0
  S.colorMapStepDelay = 20
  if not S.ashSpritesCreated then setBlendCoeffs(0, 16) end
end

-- pokeemerald/src/field_weather_effect.c:1657
local function createAshSprites()
  if S.ashSpritesCreated then return end
  S.ashCounterY = 0
  S.ashOffsetY = 0
  S.ashAnim = newSprite("ash", 0, 0, 64, 64, { priority = 1, blend = true })
  S.ashSpritesCreated = true
end

-- pokeemerald/src/field_weather_effect.c:1704
local function updateAsh()
  if not S.ashSpritesCreated then return end
  S.ashCounterY = S.ashCounterY + 1
  if S.ashCounterY > 5 then
    S.ashCounterY = 0
    S.ashOffsetY = s16(S.ashOffsetY + 1)
  end
  animate(S.ashAnim)
end

-- pokeemerald/src/field_weather_effect.c:1546
local function Ash_Main()
  S.ashBaseSpritesX = S.offX % 512
  while S.ashBaseSpritesX >= SCREEN_W do S.ashBaseSpritesX = S.ashBaseSpritesX - SCREEN_W end
  if S.initStep == 0 then
    S.initStep = S.initStep + 1
  elseif S.initStep == 1 then
    createAshSprites()
    setTargetBlendCoeffs(16, 0, 1)
    S.initStep = S.initStep + 1
  elseif S.initStep == 2 then
    if updateBlend() then
      S.weatherGfxLoaded = true
      S.initStep = S.initStep + 1
    end
  else
    updateBlend()
  end
end

local function Ash_InitAll()
  Ash_InitVars()
  while not S.weatherGfxLoaded do Ash_Main() end
end

local function Ash_Finish()
  if S.finishStep == 0 then
    setTargetBlendCoeffs(0, 16, 1)
    S.finishStep = S.finishStep + 1
  elseif S.finishStep == 1 then
    if updateBlend() then
      S.ashSpritesCreated = false
      S.ashAnim = nil
      S.finishStep = S.finishStep + 1
    end
  elseif S.finishStep == 2 then
    S.finishStep = S.finishStep + 1
    return false
  else
    return false
  end
  return true
end


-- pokeemerald/src/field_weather_effect.c:1808
local function updateFogDiagonalMovement()
  S.fogDScrollXCounter = S.fogDScrollXCounter + 1
  if S.fogDScrollXCounter > 2 then
    S.fogDXOffset = u16(S.fogDXOffset + 1)
    S.fogDScrollXCounter = 0
  end
  S.fogDScrollYCounter = S.fogDScrollYCounter + 1
  if S.fogDScrollYCounter > 4 then
    S.fogDYOffset = u16(S.fogDYOffset + 1)
    S.fogDScrollYCounter = 0
  end
  S.fogDBaseSpritesX = (S.offX - S.fogDXOffset) % 256
  S.fogDPosY = S.offY + S.fogDYOffset
end

local function FogDiagonal_InitVars()
  S.initStep = 0
  S.weatherGfxLoaded = false
  S.targetColorMapIndex = 0
  S.colorMapStepDelay = 20
  S.fogHScrollCounter = 0
  S.fogHScrollOffset = 1
  if not S.fogDSpritesCreated then
    S.fogDScrollXCounter, S.fogDScrollYCounter = 0, 0
    S.fogDXOffset, S.fogDYOffset = 0, 0
    S.fogDBaseSpritesX, S.fogDPosY = 0, 0
    setBlendCoeffs(0, 16)
  end
end

local function FogDiagonal_Main()
  updateFogDiagonalMovement()
  if S.initStep == 0 then
    S.fogDSpritesCreated = true
    S.initStep = S.initStep + 1
  elseif S.initStep == 1 then
    setTargetBlendCoeffs(12, 8, 8)
    S.initStep = S.initStep + 1
  elseif S.initStep == 2 then
    if updateBlend() then
      S.weatherGfxLoaded = true
      S.initStep = S.initStep + 1
    end
  end
end

local function FogDiagonal_InitAll()
  FogDiagonal_InitVars()
  while not S.weatherGfxLoaded do FogDiagonal_Main() end
end

local function FogDiagonal_Finish()
  updateFogDiagonalMovement()
  if S.finishStep == 0 then
    setTargetBlendCoeffs(0, 16, 1)
    S.finishStep = S.finishStep + 1
  elseif S.finishStep == 1 then
    if updateBlend() then S.finishStep = S.finishStep + 1 end
  elseif S.finishStep == 2 then
    S.fogDSpritesCreated = false
    S.finishStep = S.finishStep + 1
  else
    return false
  end
  return true
end


local MIN_SANDSTORM_WAVE_INDEX = 0x20
-- pokeemerald/src/field_weather_effect.c:2161
local SWIRL_ENTRANCE_DELAYS = { 0, 120, 80, 160, 40, 0 }

-- pokeemerald/src/field_weather_effect.c:2028
local function updateSandstormWaveIndex()
  local c = S.sandstormWaveCounter
  S.sandstormWaveCounter = c + 1
  if c > 4 then
    S.sandstormWaveIndex = u16(S.sandstormWaveIndex + 1)
    S.sandstormWaveCounter = 0
  end
end

-- pokeemerald/src/field_weather_effect.c:2037
local function updateSandstormMovement()
  S.sandstormXOffset = S.sandstormXOffset - sine(S.sandstormWaveIndex) * 4
  S.sandstormYOffset = S.sandstormYOffset - sine(S.sandstormWaveIndex)
  S.sandstormBaseSpritesX = (S.offX + math.floor(S.sandstormXOffset / 256)) % 256
  S.sandstormPosY = S.offY + math.floor(S.sandstormYOffset / 256)
end

-- pokeemerald/src/field_weather_effect.c:2213
local function updateSandstormSwirlSprite(s)
  s.y = s.y - 1
  if s.y < -48 then
    s.y = SCREEN_H + 48
    s.data.radius = 4
  end
  local x = s.data.radius * sine(s.data.waveIndex)
  local y = s.data.radius * sine(s.data.waveIndex + 0x40)
  s.x2 = math.floor((x % 4294967296) / 256)
  if s.x2 >= 8388608 then s.x2 = s.x2 - 16777216 end
  s.y2 = math.floor((y % 4294967296) / 256)
  if s.y2 >= 8388608 then s.y2 = s.y2 - 16777216 end
  s.data.waveIndex = (s.data.waveIndex + 10) % 256
  s.data.radiusCounter = s.data.radiusCounter + 1
  if s.data.radiusCounter > 8 then
    s.data.radiusCounter = 0
    s.data.radius = s.data.radius + 1
  end
end

local function waitSandSwirlSpriteEntrance(s)
  s.data.entranceDelay = s.data.entranceDelay - 1
  if s.data.entranceDelay == -1 then s.cb = updateSandstormSwirlSprite end
end

-- pokeemerald/src/field_weather_effect.c:2163
local function createSwirlSandstormSprites()
  if S.sandstormSwirlSpritesCreated then return end
  for i = 0, NUM_SWIRL_SANDSTORM_SPRITES - 1 do
    local s = newSprite("sandstorm", i * 48 + 24, 208, 32, 32, { priority = 1, blend = true,
      cb = waitSandSwirlSpriteEntrance })
    s.data.waveIndex = i * 51
    s.data.radius = 8
    s.data.radiusCounter = 0
    s.data.entranceDelay = SWIRL_ENTRANCE_DELAYS[i + 1]
    startAnim(s, 1)
    S.swirlSprites[#S.swirlSprites + 1] = s
  end
  S.sandstormSwirlSpritesCreated = true
end

local function Sandstorm_InitVars()
  S.initStep = 0
  S.weatherGfxLoaded = false
  S.targetColorMapIndex = 0
  S.colorMapStepDelay = 20
  if not S.sandstormSpritesCreated then
    S.sandstormXOffset, S.sandstormYOffset = 0, 0
    S.sandstormWaveIndex = 8
    S.sandstormWaveCounter = 0
    setBlendCoeffs(0, 16)
  end
end

-- pokeemerald/src/field_weather_effect.c:1975
local function Sandstorm_Main()
  updateSandstormMovement()
  updateSandstormWaveIndex()
  if S.sandstormWaveIndex >= 0x80 - MIN_SANDSTORM_WAVE_INDEX then
    S.sandstormWaveIndex = MIN_SANDSTORM_WAVE_INDEX
  end
  if S.initStep == 0 then
    S.sandstormSpritesCreated = true
    createSwirlSandstormSprites()
    S.initStep = S.initStep + 1
  elseif S.initStep == 1 then
    setTargetBlendCoeffs(16, 0, 0)
    S.initStep = S.initStep + 1
  elseif S.initStep == 2 then
    if updateBlend() then
      S.weatherGfxLoaded = true
      S.initStep = S.initStep + 1
    end
  end
end

local function Sandstorm_InitAll()
  Sandstorm_InitVars()
  while not S.weatherGfxLoaded do Sandstorm_Main() end
end

local function Sandstorm_Finish()
  updateSandstormMovement()
  updateSandstormWaveIndex()
  if S.finishStep == 0 then
    setTargetBlendCoeffs(0, 16, 0)
    S.finishStep = S.finishStep + 1
  elseif S.finishStep == 1 then
    if updateBlend() then S.finishStep = S.finishStep + 1 end
  elseif S.finishStep == 2 then
    S.sandstormSpritesCreated = false
    S.sandstormSwirlSpritesCreated = false
    S.swirlSprites = {}
    S.finishStep = S.finishStep + 1
  else
    return false
  end
  return true
end


local function Shade_InitVars()
  S.initStep = 0
  S.targetColorMapIndex = 3
  S.colorMapStepDelay = 20
end


-- pokeemerald/src/field_weather_effect.c:2276
local BUBBLE_START_DELAYS = { 40, 90, 60, 90, 2, 60, 40, 30 }
-- pokeemerald/src/field_weather_effect.c:2285
local BUBBLE_START_COORDS = {
  { 120, 160 }, { 376, 160 }, { 40, 140 }, { 296, 140 }, { 180, 130 }, { 436, 130 }, { 60, 160 },
  { 436, 160 }, { 220, 180 }, { 476, 180 }, { 10, 90 }, { 266, 90 }, { 256, 160 },
}

-- pokeemerald/src/field_weather_effect.c:2408
local function updateBubbleSprite(s)
  local d = s.data
  d.scrollXCounter = d.scrollXCounter + 2
  if d.scrollXCounter > 8 then
    d.scrollXCounter = 0
    if d.scrollXDir == 0 then
      s.x2 = s.x2 + 1
      if s.x2 > 4 then d.scrollXDir = 1 end
    else
      s.x2 = s.x2 - 1
      if s.x2 <= 0 then d.scrollXDir = 0 end
    end
  end
  s.y = s.y - 3
  d.counter = d.counter + 1
  if d.counter >= 120 then destroySprite(s) end
end

-- pokeemerald/src/field_weather_effect.c:2375
local function createBubbleSprite(index)
  local c = BUBBLE_START_COORDS[index + 1]
  local s = newSprite("bubble", c[1], c[2] - S.offY, 8, 8, { priority = 1, cb = updateBubbleSprite })
  s.coordOffsetEnabled = true
  s.data.scrollXCounter, s.data.scrollXDir, s.data.counter = 0, 0, 0
  S.bubbleSprites[#S.bubbleSprites + 1] = s
  S.bubblesSpriteCount = S.bubblesSpriteCount + 1
end

local function Bubbles_InitVars()
  FogHorizontal_InitVars()
  if not S.bubblesSpritesCreated then
    S.bubblesDelayIndex = 0
    S.bubblesDelayCounter = BUBBLE_START_DELAYS[1]
    S.bubblesCoordsIndex = 0
    S.bubblesSpriteCount = 0
  end
end

-- pokeemerald/src/field_weather_effect.c:2322
local function Bubbles_Main()
  FogHorizontal_Main()
  S.bubblesDelayCounter = S.bubblesDelayCounter + 1
  if S.bubblesDelayCounter > BUBBLE_START_DELAYS[S.bubblesDelayIndex + 1] then
    S.bubblesDelayCounter = 0
    S.bubblesDelayIndex = S.bubblesDelayIndex + 1
    if S.bubblesDelayIndex > #BUBBLE_START_DELAYS - 1 then S.bubblesDelayIndex = 0 end
    createBubbleSprite(S.bubblesCoordsIndex)
    S.bubblesCoordsIndex = S.bubblesCoordsIndex + 1
    if S.bubblesCoordsIndex > #BUBBLE_START_COORDS - 1 then S.bubblesCoordsIndex = 0 end
  end
end

local function Bubbles_InitAll()
  Bubbles_InitVars()
  while not S.weatherGfxLoaded do Bubbles_Main() end
end

local function Bubbles_Finish()
  if not FogHorizontal_Finish() then
    S.bubbleSprites = {}
    S.bubblesSpriteCount = 0
    return false
  end
  return true
end


local function None_Init()
  S.targetColorMapIndex = 0
  S.colorMapStepDelay = 0
end
local function noop() end
local function none_finish() return false end

-- pokeemerald/src/field_weather.c:85
local FUNCS = {
  [WEATHER_NONE] = { None_Init, noop, None_Init, none_finish },
  [WEATHER_SUNNY_CLOUDS] = { Clouds_InitVars, Clouds_Main, Clouds_InitAll, Clouds_Finish },
  [WEATHER_SUNNY] = { Sunny_InitVars, noop, Sunny_InitVars, none_finish },
  [WEATHER_RAIN] = { Rain_InitVars, Rain_Main, Rain_InitAll, Rain_Finish },
  [WEATHER_SNOW] = { Snow_InitVars, Snow_Main, Snow_InitAll, Snow_Finish },
  [WEATHER_RAIN_THUNDERSTORM] = { Thunderstorm_InitVars, Thunderstorm_Main, Thunderstorm_InitAll, Thunderstorm_Finish },
  [WEATHER_FOG_HORIZONTAL] = { FogHorizontal_InitVars, FogHorizontal_Main, FogHorizontal_InitAll, FogHorizontal_Finish },
  [WEATHER_VOLCANIC_ASH] = { Ash_InitVars, Ash_Main, Ash_InitAll, Ash_Finish },
  [WEATHER_SANDSTORM] = { Sandstorm_InitVars, Sandstorm_Main, Sandstorm_InitAll, Sandstorm_Finish },
  [WEATHER_FOG_DIAGONAL] = { FogDiagonal_InitVars, FogDiagonal_Main, FogDiagonal_InitAll, FogDiagonal_Finish },
  [WEATHER_UNDERWATER] = { FogHorizontal_InitVars, FogHorizontal_Main, FogHorizontal_InitAll, FogHorizontal_Finish },
  [WEATHER_SHADE] = { Shade_InitVars, noop, Shade_InitVars, none_finish },
  [WEATHER_DROUGHT] = { Drought_InitVars, Drought_Main, Drought_InitAll, none_finish },
  [WEATHER_DOWNPOUR] = { Downpour_InitVars, Thunderstorm_Main, Downpour_InitAll, Thunderstorm_Finish },
  [WEATHER_UNDERWATER_BUBBLES] = { Bubbles_InitVars, Bubbles_Main, Bubbles_InitAll, Bubbles_Finish },
}

local function funcs(w)
  return FUNCS[w] or FUNCS[WEATHER_NONE]
end

-- pokeemerald/src/field_weather.c:154 StartWeather
function R.start()
  if S.started then return end
  local cam = { S.lastCamX, S.lastCamY }
  blankState()
  S.lastCamX, S.lastCamY = cam[1], cam[2]
  S.started = true
  setBlendCoeffs(16, 0)
  S.palProcessingState = PAL_IDLE
  S.readyForInit = false
  S.weatherChangeComplete = true
end

function R.restart()
  local rainStrength = S.rainStrength
  S.started = false
  R.start()
  S.rainStrength = rainStrength
end

function R.stop()
  blankState()
end

function R.isStarted()
  return S.started == true
end

-- pokeemerald/src/field_weather.c:183
function R.setNextWeather(w)
  w = tonumber(w) or WEATHER_NONE
  if not S.started then R.start() end
  if not isRainy(w) then R.playRainStoppingSoundEffect() end
  if S.nextWeather ~= w and S.currWeather == w then funcs(w)[1]() end
  S.weatherChangeComplete = false
  S.nextWeather = w
  S.finishStep = 0
end

-- pokeemerald/src/field_weather.c:200
function R.setCurrentAndNextWeather(w)
  w = tonumber(w) or WEATHER_NONE
  if not S.started then R.start() end
  R.playRainStoppingSoundEffect()
  S.currWeather = w
  S.nextWeather = w
end

-- pokeemerald/src/field_weather.c:207
function R.setCurrentAndNextWeatherNoDelay(w)
  R.setCurrentAndNextWeather(w)
  S.readyForInit = true
end

-- pokeemerald/src/field_weather.c:801
function R.readyForInit()
  S.readyForInit = true
  S.initialized = false
end

-- pokeemerald/src/field_weather.c:368 FadeInScreenWithWeather
local FADE_IN_COLOR_MAP = {
  [WEATHER_RAIN] = 3, [WEATHER_RAIN_THUNDERSTORM] = 3, [WEATHER_DOWNPOUR] = 3, [WEATHER_SNOW] = 3,
  [WEATHER_SHADE] = 3, [WEATHER_DROUGHT] = -6, [WEATHER_FOG_HORIZONTAL] = 0,
}

-- pokeemerald/src/field_weather.c:216 Task_WeatherInit
local function weatherInit()
  S.palProcessingState = PAL_FADING_IN
  funcs(S.currWeather)[3]()
  S.initialized = true
  local idx = FADE_IN_COLOR_MAP[S.currWeather]
  if idx == nil then idx = S.targetColorMapIndex end
  S.colorMapIndex = idx
  S.palProcessingState = PAL_IDLE
end

-- pokeemerald/src/field_weather.c:344 UpdateWeatherColorMap
local function updateWeatherColorMap()
  if S.palProcessingState == PAL_FADING_OUT then return end
  if S.colorMapIndex == S.targetColorMapIndex then
    S.palProcessingState = PAL_IDLE
  else
    S.colorMapStepCounter = S.colorMapStepCounter + 1
    if S.colorMapStepCounter >= S.colorMapStepDelay then
      S.colorMapStepCounter = 0
      if S.colorMapIndex < S.targetColorMapIndex then
        S.colorMapIndex = S.colorMapIndex + 1
      else
        S.colorMapIndex = S.colorMapIndex - 1
      end
    end
  end
end

-- pokeemerald/src/field_weather_effect.c:2448
local function tickAbnormal()
  local a = S.abnormal
  if not a then return end
  if a.state == 0 then
    local d = a.delay
    a.delay = d - 1
    if d <= 0 then
      R.setNextWeather(a.weatherA)
      S.currentAbnormal = a.weatherA
      a.delay = 600
      a.state = 1
    end
  else
    local d = a.delay
    a.delay = d - 1
    if d <= 0 then
      R.setNextWeather(a.weatherB)
      S.currentAbnormal = a.weatherB
      a.delay = 600
      a.state = 0
    end
  end
end

-- pokeemerald/src/field_weather_effect.c:2475
function R.startAbnormal()
  if not S.abnormal then
    local a = { state = 0, delay = 600 }
    if S.currentAbnormal == WEATHER_DOWNPOUR then
      a.weatherA, a.weatherB = WEATHER_DROUGHT, WEATHER_DOWNPOUR
    elseif S.currentAbnormal == WEATHER_DROUGHT then
      a.weatherA, a.weatherB = WEATHER_DOWNPOUR, WEATHER_DROUGHT
    else
      S.currentAbnormal = WEATHER_DOWNPOUR
      a.weatherA, a.weatherB = WEATHER_DROUGHT, WEATHER_DOWNPOUR
    end
    S.abnormal = a
  end
  return S.currentAbnormal
end

function R.stopAbnormal()
  S.abnormal = nil
  S.currentAbnormal = WEATHER_DOWNPOUR
end

function R.getCurrentWeather()
  return S.currWeather
end

function R.isWeatherChangeComplete()
  return S.weatherChangeComplete == true
end

function R.colorMapIndex()
  return S.colorMapIndex
end

-- pokeemerald/src/field_weather.c:227 Task_WeatherMain
function R.update()
  if not S.started then return end
  S.frames = S.frames + 1
  local initFrame = false
  if not S.initialized then
    if not S.readyForInit then return end
    -- pokeruby/src/field_weather.c:322
    weatherInit()
    initFrame = true
  end
  tickAbnormal()
  if initFrame then
    S.initialized = true
  elseif S.currWeather ~= S.nextWeather then
    if not funcs(S.currWeather)[4]() and S.palProcessingState ~= PAL_FADING_OUT then
      funcs(S.nextWeather)[1]()
      S.colorMapStepCounter = 0
      S.palProcessingState = PAL_CHANGING
      S.currWeather = S.nextWeather
      S.weatherChangeComplete = true
    end
  else
    funcs(S.currWeather)[2]()
  end
  if S.palProcessingState == PAL_CHANGING then updateWeatherColorMap() end
  runSprites(S.rainSprites)
  runSprites(S.snowSprites)
  runSprites(S.cloudSprites)
  runSprites(S.swirlSprites)
  runSprites(S.bubbleSprites)
  updateAsh()
end


function R.setCamera(camX, camY)
  camX, camY = math.floor(camX or 0), math.floor(camY or 0)
  if S.lastCamX then
    local dx, dy = camX - S.lastCamX, camY - S.lastCamY
    if math.abs(dx) <= 32 then S.totalCamX = u16(S.totalCamX - dx) end
    if math.abs(dy) <= 32 then S.totalCamY = u16(S.totalCamY - dy) end
  end
  S.lastCamX, S.lastCamY = camX, camY
  S.offX = s16(S.totalCamX)
  -- pokeruby/src/field_camera.c:465
  S.offY = s16(S.totalCamY - 32 - 8)
end

function R.resetCamera()
  S.totalCamX, S.totalCamY = 0, 0
  S.offX, S.offY = 0, -40
end


local function sheetQuad(sheet, tile, wT, hT)
  local key = tile * 4096 + wT * 64 + hT
  local q = sheet.quads[key]
  if q then return q end
  if sheet.cols == wT then
    q = love.graphics.newQuad(0, math.floor(tile / sheet.cols) * 8, wT * 8, hT * 8, sheet.w, sheet.h)
  else
    q = {}
    for r = 0, hT - 1 do
      for c = 0, wT - 1 do
        local t = tile + r * wT + c
        q[#q + 1] = { love.graphics.newQuad((t % sheet.cols) * 8, math.floor(t / sheet.cols) * 8, 8, 8, sheet.w, sheet.h),
          c * 8, r * 8 }
      end
    end
  end
  sheet.quads[key] = q
  return q
end

local function drawSheetFrame(sheet, tile, wT, hT, x, y)
  local q = sheetQuad(sheet, tile, wT, hT)
  if type(q) == "table" then
    for _, part in ipairs(q) do love.graphics.draw(sheet.image, part[1], x + part[2], y + part[3]) end
  else
    love.graphics.draw(sheet.image, q, x, y)
  end
end

local function spriteSheetFor(A, s)
  if s.kind == "snow" then return A.sheets[s.frame == 1 and "snow_2" or "snow_1"], 0 end
  if s.kind == "sandstorm" then return A.sheets.sandstorm, s.frame end
  if s.kind == "cloud" then return A.sheets.cloud, s.frame end
  return A.sheets[s.kind], s.frame
end

local function colorMapUniforms(shader, kind)
  shader:send("useMask", 0)
  local idx = S.colorMapIndex
  if idx > 0 then
    shader:send("mode", 1)
    shader:send("row", (kind == COLOR_MAP_CONTRAST and NUM_WEATHER_COLOR_MAPS or 0) + idx - 1)
    return true
  elseif idx < 0 then
    shader:send("mode", 2)
    shader:send("dtable", -idx - 1)
    return true
  end
  shader:send("mode", 0)
  return false
end

local function withBlend(A, eva, evb, drawFn)
  if not (A.shader and A.mask) then
    love.graphics.setColor(1, 1, 1, eva / 16)
    drawFn()
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local k = math.min(evb, 16) / 16
  if k < 1 then
    love.graphics.setShader(A.mask)
    A.mask:send("k", k)
    love.graphics.setBlendMode("multiply", "premultiplied")
    drawFn()
  end
  if eva > 0 then
    love.graphics.setShader(A.shader)
    colorMapUniforms(A.shader, COLOR_MAP_CONTRAST)
    local e = math.min(eva, 16) / 16
    love.graphics.setBlendMode("add", "alphamultiply")
    love.graphics.setColor(e, e, e, 1)
    drawFn()
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setBlendMode("alpha", "alphamultiply")
  love.graphics.setShader()
end

local function oamPos(s)
  local x = s.x + s.x2 + s.cx
  local y = s.y + s.y2 + s.cy
  if s.coordOffsetEnabled then
    x = x + S.offX
    y = y + S.offY
  end
  x = x % 512
  if x >= 256 then x = x - 512 end
  y = y % 256
  if y + s.h > 256 then y = y - 256 end
  return x, y
end

local function drawScreenSprites(A, list, ox, oy, cw, ch, repeatScreen)
  local xs = repeatScreen and math.ceil((ox + 0.0) / SCREEN_W) or 0
  local ys = repeatScreen and math.ceil((oy + 0.0) / SCREEN_H) or 0
  for _, s in ipairs(list) do
    if s.inUse and not s.invisible then
      local sheet, frame = spriteSheetFor(A, s)
      if sheet then
        local x, y = oamPos(s)
        for ty = -ys, ys do
          for tx = -xs, xs do
            local px, py = ox + x + tx * SCREEN_W, oy + y + ty * SCREEN_H
            if px + s.w > 0 and py + s.h > 0 and px < cw and py < ch then
              drawSheetFrame(sheet, frame, s.w / 8, s.h / 8, px, py)
            end
          end
        end
      end
    end
  end
end

local function drawTiled(sheet, frame, baseX, baseY, ox, oy, cw, ch)
  local sx = ox + (baseX % 64) - 64
  local sy = oy + (baseY % 64) - 64
  while sx > -64 do sx = sx - 64 end
  while sy > -64 do sy = sy - 64 end
  if love.graphics.newSpriteBatch then
    local r, g, b, a = love.graphics.getColor()
    local bucket = r == 1 and g == 1 and b == 1 and a == 1 and "tiledBase" or "tiledTint"
    local store = sheet[bucket] or {}; sheet[bucket] = store
    local key = table.concat({ frame, sx, sy, cw, ch, r, g, b, a }, ":")
    if store.key ~= key then
      local q = sheetQuad(sheet, frame, 8, 8)
      local count = (math.floor((cw - sx) / 64) + 1) * (math.floor((ch - sy) / 64) + 1)
      count = count * (type(q) == "table" and #q or 1)
      if not store.batch or store.capacity < count then
        store.batch = love.graphics.newSpriteBatch(sheet.image, count, "dynamic")
        store.capacity = count
      end
      local batch = store.batch
      batch:clear()
      -- Image draws store their colour as bytes in the vertex buffer. Use
      -- the same byte conversion here, including fractional EVA/16, instead
      -- of applying a float constant colour to the finished SpriteBatch.
      batch:setColor(r, g, b, a)
      for y = sy, ch, 64 do
        for x = sx, cw, 64 do
          if type(q) == "table" then
            for _, part in ipairs(q) do batch:add(part[1], x + part[2], y + part[3]) end
          else batch:add(q, x, y) end
        end
      end
      store.key = key
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(store.batch)
    love.graphics.setColor(r, g, b, a)
    return
  end
  for y = sy, ch, 64 do
    for x = sx, cw, 64 do
      drawSheetFrame(sheet, frame, 8, 8, x, y)
    end
  end
end

local function drawCloudSprites(A, camX, camY, ox, oy)
  local sheet = A.sheets.cloud
  if not sheet then return end
  withBlend(A, S.currBlendEVA, S.currBlendEVB, function()
    for _, s in ipairs(S.cloudSprites) do
      if s.inUse and not s.invisible then
        local x = s.worldX - camX + s.x - 32
        local y = s.worldY - camY - 32
        drawSheetFrame(sheet, 0, 8, 8, x, y)
      end
    end
  end)
  local FxRse = package.loaded["src.core.game3.field_effects_rse"]
  if FxRse and FxRse.coverWorldRect then
    -- pokeruby/src/field_weather_effects.c:49
    for _, s in ipairs(S.cloudSprites) do
      if s.inUse and not s.invisible then
        FxRse.coverWorldRect(s.worldX + s.x - 32, s.worldY - 32, 64, 64, camX, camY)
      end
    end
  end
end

local function drawPriority2(A, camX, camY, ox, oy, cw, ch)
  if S.cloudSpritesCreated then drawCloudSprites(A, camX, camY, ox, oy) end
  if S.fogHSpritesCreated and A.sheets.fog_h then
    withBlend(A, S.currBlendEVA, S.currBlendEVB, function()
      drawTiled(A.sheets.fog_h, 0, S.fogHScrollPosX, S.offY % 256, ox, oy, cw, ch)
    end)
  end
  if S.fogDSpritesCreated and A.sheets.fog_d then
    withBlend(A, S.currBlendEVA, S.currBlendEVB, function()
      drawTiled(A.sheets.fog_d, 0, S.fogDBaseSpritesX, S.fogDPosY - 32, ox, oy, cw, ch)
    end)
  end
end

local function drawPriority1(A, ox, oy, cw, ch)
  local repeatScreen = cw > SCREEN_W or ch > SCREEN_H
  if S.ashSpritesCreated and S.ashAnim and A.sheets.ash then
    withBlend(A, S.currBlendEVA, S.currBlendEVB, function()
      drawTiled(A.sheets.ash, S.ashAnim.frame, S.ashBaseSpritesX, S.offY + S.ashOffsetY, ox, oy, cw, ch)
    end)
  end
  if S.sandstormSpritesCreated and A.sheets.sandstorm then
    withBlend(A, S.currBlendEVA, S.currBlendEVB, function()
      drawTiled(A.sheets.sandstorm, 0, S.sandstormBaseSpritesX, S.sandstormPosY - 32, ox, oy, cw, ch)
      drawScreenSprites(A, S.swirlSprites, ox, oy, cw, ch, repeatScreen)
    end)
  end
  local mapped = A.shader and colorMapUniforms(A.shader, COLOR_MAP_CONTRAST)
  if mapped then love.graphics.setShader(A.shader) end
  drawScreenSprites(A, S.rainSprites, ox, oy, cw, ch, repeatScreen)
  drawScreenSprites(A, S.snowSprites, ox, oy, cw, ch, repeatScreen)
  drawScreenSprites(A, S.bubbleSprites, ox, oy, cw, ch, repeatScreen)
  if mapped then love.graphics.setShader() end
end

R._maskOn = false

local function beginActorMask(A)
  R._maskOn = false
  if not (A.shader and A.maskWrite) or S.colorMapIndex <= 0 then return end
  local policy = weatherPolicy()
  if not (policy and policy.fixedObjectPaletteSlots) then return end
  local cur = love.graphics.getCanvas()
  if not cur then return end
  local w, h = cur:getWidth(), cur:getHeight()
  local m = R._maskCanvas
  if not m or m:getWidth() ~= w or m:getHeight() ~= h then
    if m and m.release then m:release() end
    m = love.graphics.newCanvas(w, h, { dpiscale = cur.getDPIScale and cur:getDPIScale() or 1 })
    m:setFilter("nearest", "nearest")
    R._maskCanvas = m
  end
  love.graphics.push("all")
  love.graphics.setCanvas(m)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.pop()
  R._maskOn = true
end

local function useActorMask(A, cw, ch)
  local m = R._maskCanvas
  if not (R._maskOn and m and m:getWidth() == cw and m:getHeight() == ch) then return end
  A.shader:send("amask", m)
  A.shader:send("maskSize", { cw, ch })
  A.shader:send("useMask", 1)
end

-- pokeruby/src/field_weather.c:580
function R.actorMaskCode(paletteSlot)
  local m = R.manifest()
  local types = m and m.color_map_types
  local t = types and paletteSlot and types[16 + paletteSlot + 1]
  return t == COLOR_MAP_CONTRAST and 1 or 0
end

function R.maskActive() return R._maskOn end

function R.writeActorMask(code, drawFn)
  if not R._maskOn then return end
  local A = loadAssets()
  if not (A and A.maskWrite and R._maskCanvas) then return end
  love.graphics.push("all")
  love.graphics.setCanvas(R._maskCanvas)
  love.graphics.setShader(A.maskWrite)
  A.maskWrite:send("code", code)
  love.graphics.setBlendMode("replace", "premultiplied")
  love.graphics.setColor(1, 1, 1, 1)
  drawFn()
  love.graphics.pop()
end

-- pokeemerald/src/field_weather.c:459 ApplyColorMap
local function colorMapPass(A, cw, ch, exchangeCanvas)
  if S.colorMapIndex == 0 or not A.shader then return end
  local cur = love.graphics.getCanvas()
  if not cur then return end
  cw, ch = cur:getWidth(), cur:getHeight()
  local tmp = R._tmpCanvas
  if not tmp or tmp:getWidth() ~= cw or tmp:getHeight() ~= ch then
    if tmp and tmp.release then tmp:release() end
    tmp = love.graphics.newCanvas(cw, ch, { dpiscale = cur.getDPIScale and cur:getDPIScale() or 1,
      format = cur.getFormat and cur:getFormat() or "normal" })
    tmp:setFilter("nearest", "nearest")
    R._tmpCanvas = tmp
  end
  if exchangeCanvas and not love.graphics.getScissor() and exchangeCanvas(cur, tmp) then
    local shader = love.graphics.getShader()
    local blend, alpha = love.graphics.getBlendMode()
    local r, g, b, a = love.graphics.getColor()
    -- A transform-only push leaves ownership of the new target with the
    -- caller. push("all") would restore the old canvas and switch twice more.
    love.graphics.push()
    love.graphics.origin()
    love.graphics.setCanvas(tmp)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    colorMapUniforms(A.shader, COLOR_MAP_DARK_CONTRAST)
    useActorMask(A, cw, ch)
    love.graphics.setShader(A.shader)
    love.graphics.draw(cur, 0, 0)
    love.graphics.pop()
    love.graphics.setShader(shader)
    love.graphics.setBlendMode(blend, alpha)
    love.graphics.setColor(r, g, b, a)
    R._tmpCanvas = cur
    return tmp
  end
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setShader()
  love.graphics.setCanvas(tmp)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setBlendMode("replace", "premultiplied")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(cur, 0, 0)
  love.graphics.setCanvas(cur)
  colorMapUniforms(A.shader, COLOR_MAP_DARK_CONTRAST)
  useActorMask(A, cw, ch)
  love.graphics.setShader(A.shader)
  love.graphics.draw(tmp, 0, 0)
  love.graphics.pop()
end

R._belowFrame = -1

function R.drawBelow(camX, camY, canvasW, canvasH)
  R._belowFrame = S.frames
  R._maskOn = false
  if not S.started or not S.initialized then return end
  local A = loadAssets()
  if not A then return end
  beginActorMask(A)
  local ox = math.floor((canvasW - SCREEN_W) / 2)
  local oy = math.floor((canvasH - SCREEN_H) / 2)
  love.graphics.push("all")
  drawPriority2(A, camX, camY, ox, oy, canvasW, canvasH)
  love.graphics.pop()
end

function R.draw(camX, camY, canvasW, canvasH, exchangeCanvas)
  R.setCamera(camX, camY)
  if R._belowFrame ~= S.frames then R._maskOn = false end
  if not S.started or not S.initialized then return end
  local A = loadAssets()
  if not A then return end
  canvasW = canvasW or SCREEN_W
  canvasH = canvasH or SCREEN_H
  local ox = math.floor((canvasW - SCREEN_W) / 2)
  local oy = math.floor((canvasH - SCREEN_H) / 2)
  love.graphics.push("all")
  if R._belowFrame ~= S.frames then
    drawPriority2(A, camX, camY, ox, oy, canvasW, canvasH)
  end
  love.graphics.pop()
  colorMapPass(A, canvasW, canvasH, exchangeCanvas)
  love.graphics.push("all")
  drawPriority1(A, ox, oy, canvasW, canvasH)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

R.WEATHER = {
  NONE = WEATHER_NONE, SUNNY_CLOUDS = WEATHER_SUNNY_CLOUDS, SUNNY = WEATHER_SUNNY, RAIN = WEATHER_RAIN,
  SNOW = WEATHER_SNOW, RAIN_THUNDERSTORM = WEATHER_RAIN_THUNDERSTORM, FOG_HORIZONTAL = WEATHER_FOG_HORIZONTAL,
  VOLCANIC_ASH = WEATHER_VOLCANIC_ASH, SANDSTORM = WEATHER_SANDSTORM, FOG_DIAGONAL = WEATHER_FOG_DIAGONAL,
  UNDERWATER = WEATHER_UNDERWATER, SHADE = WEATHER_SHADE, DROUGHT = WEATHER_DROUGHT, DOWNPOUR = WEATHER_DOWNPOUR,
  UNDERWATER_BUBBLES = WEATHER_UNDERWATER_BUBBLES,
}

function R.snapshot()
  return {
    curr = S.currWeather, next = S.nextWeather, colorMapIndex = S.colorMapIndex,
    target = S.targetColorMapIndex, rain = S.rainSpriteCount, rainVisible = S.curRainSpriteIndex,
    snow = S.snowflakeSpriteCount, bubbles = #S.bubbleSprites, fogH = S.fogHSpritesCreated,
    fogD = S.fogDSpritesCreated, ash = S.ashSpritesCreated, sandstorm = S.sandstormSpritesCreated,
    swirls = #S.swirlSprites, clouds = #S.cloudSprites, eva = S.currBlendEVA, evb = S.currBlendEVB,
    initialized = S.initialized, palState = S.palProcessingState, droughtStage = S.droughtBrightnessStage,
  }
end

return R
