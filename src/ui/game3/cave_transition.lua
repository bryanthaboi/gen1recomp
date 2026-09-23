-- src/fldeff_flash.c:288
-- src/fldeff_flash.c:356

local CaveTransition = {}

local W, H = 240, 160
local SCREEN_REL = "data/generated/gba/cave_transition/screen.bin"
local PALETTES_REL = "data/generated/gba/cave_transition/palettes.lua"

CaveTransition._run = nil
CaveTransition._assets = nil

local function loadAssets()
  if CaveTransition._assets then return CaveTransition._assets end
  local Dataset = require("src.core.game3.dataset")
  local cache = Dataset.cache()
  local screen = cache:read(SCREEN_REL)
  local src = cache:read(PALETTES_REL)
  assert(type(screen) == "string" and #screen == W * H, "cave_transition screen.bin missing from the cache")
  assert(type(src) == "string", "cave_transition palettes.lua missing from the cache")
  local pals = assert(load(src, "@" .. PALETTES_REL, "t", {}))()
  CaveTransition._assets = { screen = screen, pals = pals }
  return CaveTransition._assets
end

local function bgr555(c)
  return { c % 32, math.floor(c / 32) % 32, math.floor(c / 1024) % 32 }
end

local function copyPal(src)
  local out = {}
  for i = 0, 15 do out[i] = bgr555(src[i]) end
  return out
end

local function loadPalette(dst, src, srcStart, count)
  for i = 0, count - 1 do dst[i] = bgr555(src[srcStart + i]) end
end

local function newRun(kind, done)
  local a = loadAssets()
  return {
    kind = kind,
    done = done,
    task = "0",
    pal14 = copyPal(a.pals.white),
    backdrop = bgr555(a.pals[kind == "exit" and "black" or "white"][0]),
    blend = false,
    eva = 16,
    evb = 0,
    showBg0 = false,
    d1 = 0,
    d2 = 0,
    frame = 0,
  }
end

-- src/fldeff_flash.c:475
function CaveTransition.start(kind, done, skipFirstTask)
  local run = newRun(kind, done)
  if skipFirstTask then run.task = "1" else run.defer = true end
  CaveTransition._run = run
  CaveTransition._dirty = true
  return true
end

function CaveTransition.isActive()
  return CaveTransition._run ~= nil
end

local function finish(run)
  CaveTransition._run = nil
  if run.done then run.done() end
end

local function stepEnter(run, a)
  local t = run.task
  if t == "0" then
    run.task = "1"
  elseif t == "1" then
    -- src/fldeff_flash.c:366
    run.showBg0 = true
    run.blend = false
    run.pal14 = copyPal(a.pals.white)
    run.backdrop = bgr555(a.pals.black[0])
    run.task = "2"
    run.d1, run.d2 = 0, 0
  elseif t == "2" then
    -- src/fldeff_flash.c:384
    local count = run.d2
    if count < 16 then
      run.d2 = run.d2 + 2
      for i = 0, count do run.pal14[i] = bgr555(a.pals.tiles[15 - count + i]) end
    else
      run.blend = true
      run.eva, run.evb = 16, 16
      run.task = "3"
    end
  elseif t == "3" then
    -- src/fldeff_flash.c:401
    local r4 = 16 - run.d1
    run.eva, run.evb = r4, 16
    if r4 ~= 0 then
      run.d1 = run.d1 + 1
    else
      run.backdrop = bgr555(a.pals.black[0])
      finish(run)
    end
  end
end

local function stepExit(run, a)
  local t = run.task
  if t == "0" then
    run.task = "1"
  elseif t == "1" then
    -- src/fldeff_flash.c:298
    run.showBg0 = true
    run.pal14 = copyPal(a.pals.white)
    loadPalette(run.pal14, a.pals.tiles, 8, 8)
    run.blend = true
    run.eva, run.evb = 0, 0
    run.task = "2"
    run.d1 = 0
  elseif t == "2" then
    -- src/fldeff_flash.c:315
    local r4 = run.d1
    run.eva, run.evb = math.min(r4, 16), 16
    if r4 <= 16 then
      run.d1 = run.d1 + 1
    else
      run.d2 = 0
      run.task = "3"
    end
  elseif t == "3" then
    -- src/fldeff_flash.c:330
    run.eva, run.evb = 16, 16
    local count = run.d2
    if count < 8 then
      run.d2 = run.d2 + 1
      loadPalette(run.pal14, a.pals.tiles, count + 8, 8 - count)
    else
      run.backdrop = bgr555(a.pals.white[0])
      run.task = "4"
      run.d2 = 8
    end
  elseif t == "4" then
    -- src/fldeff_flash.c:348
    if run.d2 ~= 0 then
      run.d2 = run.d2 - 1
    else
      finish(run)
    end
  end
end

function CaveTransition.update(dt)
  local run = CaveTransition._run
  if not run then return end
  local steps = math.floor(((dt or (1 / 60)) * 60) + 0.5)
  if steps < 1 then steps = 1 end
  local a = loadAssets()
  for _ = 1, steps do
    run = CaveTransition._run
    if not run then return end
    if run.defer then
      run.defer = false
    else
      run.frame = run.frame + 1
      if run.kind == "exit" then stepExit(run, a) else stepEnter(run, a) end
      CaveTransition._dirty = true
    end
  end
end

local function blendChannel(top, below, eva, evb)
  local v = math.floor((top * eva + below * evb) / 16)
  if v > 31 then v = 31 end
  return v
end

local function outColor(run, i)
  local c = run.pal14[i]
  local b = run.backdrop
  if not run.blend then return c end
  return {
    blendChannel(c[1], b[1], run.eva, run.evb),
    blendChannel(c[2], b[2], run.eva, run.evb),
    blendChannel(c[3], b[3], run.eva, run.evb),
  }
end

function CaveTransition.colorAt(x, y)
  local run = CaveTransition._run
  if not run then return nil end
  if not run.showBg0 then return run.backdrop end
  local a = loadAssets()
  local byte = a.screen:byte(y * W + x + 1)
  local idx = byte % 16
  if idx == 0 then return run.backdrop end
  return outColor(run, idx)
end

local function rebuild(run)
  local a = loadAssets()
  if not CaveTransition._imageData then
    CaveTransition._imageData = love.image.newImageData(W, H)
  end
  local lut = {}
  for i = 1, 15 do
    local c = run.showBg0 and outColor(run, i) or run.backdrop
    lut[i] = { c[1] / 31, c[2] / 31, c[3] / 31 }
  end
  local b = run.backdrop
  lut[0] = { b[1] / 31, b[2] / 31, b[3] / 31 }
  local screen = a.screen
  CaveTransition._imageData:mapPixel(function(x, y)
    local c = lut[screen:byte(y * W + x + 1) % 16]
    return c[1], c[2], c[3], 1
  end)
  if CaveTransition._image then
    CaveTransition._image:replacePixels(CaveTransition._imageData)
  else
    CaveTransition._image = love.graphics.newImage(CaveTransition._imageData)
    CaveTransition._image:setFilter("nearest", "nearest")
  end
  CaveTransition._dirty = false
end

function CaveTransition.surroundColor()
  local c = CaveTransition.colorAt(0, 0)
  if not c then return nil end
  return { c[1] / 31, c[2] / 31, c[3] / 31 }
end

function CaveTransition.draw()
  local run = CaveTransition._run
  if not run then return end
  if CaveTransition._dirty or not CaveTransition._image then rebuild(run) end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(CaveTransition._image, 0, 0)
  local s = CaveTransition.surroundColor()
  local Renderer = package.loaded["src.render.Renderer"]
  if Renderer and s then
    Renderer.voidVeil = { s[1], s[2], s[3], 1 }
  end
end

function CaveTransition.clear()
  CaveTransition._run = nil
end

return CaveTransition
