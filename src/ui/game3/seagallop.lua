-- Seagallop high-speed ferry cutscene (FRLG 1:1)
-- pokefirered/src/seagallop.c

local Fade = require("src.ui.game3.fade")

local Seagallop = {}

local W, H = 240, 160
local SE_SHIP = 19 -- pokefirered/include/constants/songs.h:23
local SE_EXIT = 9  -- pokefirered/include/constants/songs.h:13
local CROSSING_FRAMES = 140

local DIRN_WESTBOUND = 0
local DIRN_EASTBOUND = 1

-- pokefirered/src/seagallop.c:88
local TRAVEL_DIRECTIONS = {
  [0] = 0x6fe, -- VERMILION_CITY
  [1] = 0x6fc, -- ONE_ISLAND
  [2] = 0x6f8, -- TWO_ISLAND
  [3] = 0x6f0, -- THREE_ISLAND
  [4] = 0x6e0, -- FOUR_ISLAND
  [5] = 0x4c0, -- FIVE_ISLAND
  [6] = 0x400, -- SIX_ISLAND
  [7] = 0x440, -- SEVEN_ISLAND
  [8] = 0x7ff, -- CINNABAR_ISLAND
  [9] = 0x6e0, -- NAVEL_ROCK
  [10] = 0x000, -- BIRTH_ISLAND
}

local CACHE_ROOT = "data/generated/gba/seagallop"

Seagallop._assets = nil
Seagallop._active = false
Seagallop._run = nil

function Seagallop.directionOfTravel(originId, destId)
  originId = tonumber(originId) or 0
  destId = tonumber(destId) or 0
  local mask = TRAVEL_DIRECTIONS[originId]
  if not mask then return DIRN_EASTBOUND end
  return (math.floor(mask / (2 ^ destId)) % 2 == 1) and DIRN_EASTBOUND or DIRN_WESTBOUND
end

local function read_bytes(rel)
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local d = Dataset.cache():read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local d = love.filesystem.read(rel)
    if type(d) == "string" and #d > 0 then return d end
    local alt = "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", ""))
    d = love.filesystem.read(alt)
    if type(d) == "string" and #d > 0 then return d end
  end
  local home = os.getenv("HOME") or ""
  local candidates = {
    rel,
    "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", "")),
    home .. "/.local/share/love/pokemon-love2d/firered/" .. rel,
    home .. "/.local/share/love/pokemon-love2d/leafgreen/" .. rel,
    home .. "/.local/share/love/pokemon-love2d/" .. rel,
  }
  for _, p in ipairs(candidates) do
    local f = io.open(p, "rb")
    if f then
      local d = f:read("*a")
      f:close()
      if d and #d > 0 then return d end
    end
  end
  return nil
end

local function rgba_to_image(raw, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not raw or #raw < w * h * 4 then return nil end
  local ok, imgData = pcall(love.image.newImageData, w, h, "rgba8", raw)
  if not ok or not imgData then return nil end
  local img = love.graphics.newImage(imgData)
  if img.setFilter then img:setFilter("nearest", "nearest") end
  if img.setWrap then img:setWrap("repeat", "repeat") end
  return img
end

local function loadAssets()
  if Seagallop._assets then return Seagallop._assets end

  local wbRaw = read_bytes(CACHE_ROOT .. "/wb.rgba")
  local ebRaw = read_bytes(CACHE_ROOT .. "/eb.rgba")
  local ferryRaw = read_bytes(CACHE_ROOT .. "/ferry.rgba")
  local wakeRaw = read_bytes(CACHE_ROOT .. "/wake.rgba")

  local wbImg = rgba_to_image(wbRaw, 256, 256)
  local ebImg = rgba_to_image(ebRaw, 256, 256)
  local ferryImg = rgba_to_image(ferryRaw, 64, 40)
  local wakeImg = rgba_to_image(wakeRaw, 32, 128)

  local wakeQuads = nil
  if wakeImg and love and love.graphics and love.graphics.newQuad then
    wakeQuads = {
      love.graphics.newQuad(0, 0, 32, 32, 32, 128),
      love.graphics.newQuad(0, 32, 32, 32, 32, 128),
      love.graphics.newQuad(0, 64, 32, 32, 32, 128),
    }
  end

  Seagallop._assets = {
    wb = wbImg,
    eb = ebImg,
    ferry = ferryImg,
    wake = wakeImg,
    wakeQuads = wakeQuads,
  }
  return Seagallop._assets
end

function Seagallop.start(originId, destId, onWarp, onDone)
  local dir = Seagallop.directionOfTravel(originId, destId)
  local run = {
    origin = originId,
    dest = destId,
    direction = dir,
    onWarp = onWarp,
    onDone = onDone,
    tick = 0,
    accum = 0,
    bgX = 0,
    ferryX = (dir == DIRN_EASTBOUND) and 0 or 240,
    ferryY = 92,
    wakes = {},
    state = "running",
  }

  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.playSe then
    pcall(Audio.playSe, SE_SHIP)
  end

  Seagallop._run = run
  Seagallop._active = true
  loadAssets()

  -- pokefirered/src/seagallop.c:229: Fade in from black as cutscene starts
  Fade.begin(Fade.MODE.FROM_BLACK, 0.3)

  return true
end

function Seagallop.isActive()
  return Seagallop._active and Seagallop._run ~= nil
end

function Seagallop.stop()
  Seagallop._active = false
  Seagallop._run = nil
end

local function stepTick(run)
  run.tick = run.tick + 1

  -- 6.0 pixels per tick for water background (0x600 8.8 fixed-point displacement)
  -- 3.0 pixels per tick for ferry (48 subpixels: 48 >> 4)
  if run.direction == DIRN_EASTBOUND then
    run.bgX = (run.bgX + 6.0) % 256
    run.ferryX = run.ferryX + 3.0
  else
    run.bgX = (run.bgX - 6.0) % 256
    run.ferryX = run.ferryX - 3.0
  end

  -- Spawn wake every 5 ticks
  if run.tick % 5 == 0 then
    table.insert(run.wakes, {
      x = run.ferryX,
      y = run.ferryY,
      frame = 1,
      tick = 0,
    })
  end

  -- Update wake animation (20 frames, 20 frames, 15 frames)
  local i = 1
  while i <= #run.wakes do
    local w = run.wakes[i]
    w.tick = w.tick + 1
    if w.tick < 20 then
      w.frame = 1
    elseif w.tick < 40 then
      w.frame = 2
    elseif w.tick < 55 then
      w.frame = 3
    else
      table.remove(run.wakes, i)
      i = i - 1
    end
    i = i + 1
  end

  -- pokefirered/src/seagallop.c:286
  if run.tick >= CROSSING_FRAMES and run.state == "running" then
    run.state = "fading"
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if okA and Audio and Audio.fadeOutBgm then
      pcall(Audio.fadeOutBgm, 4)
    end
    Fade.begin(Fade.MODE.TO_BLACK, 0.35, function()
      run.state = "warping"
      if Audio and Audio.playSe then
        pcall(Audio.playSe, SE_EXIT)
      end
      if run.onWarp then
        run.onWarp()
      end
      Fade.begin(Fade.MODE.FROM_BLACK, 0.35, function()
        run.state = "done"
        Seagallop.stop()
        if run.onDone then
          run.onDone()
        end
      end)
    end)
  end
end

function Seagallop.update(dt)
  local run = Seagallop._run
  if not run then return end

  run.accum = run.accum + (dt or (1 / 60))
  local maxTicks = 10
  while run.accum >= (1 / 60) and maxTicks > 0 do
    run.accum = run.accum - (1 / 60)
    maxTicks = maxTicks - 1
    stepTick(run)
  end
end

function Seagallop.draw()
  local run = Seagallop._run
  if not run then return end
  local assets = loadAssets()

  local cw = (love.graphics.getWidth and love.graphics.getWidth()) or W
  local ch = (love.graphics.getHeight and love.graphics.getHeight()) or H
  local maxW = math.max(cw, W, 800)
  local maxH = math.max(ch, H, 600)

  -- Solid black full-screen background
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", -maxW, -maxH, maxW * 3, maxH * 3)
  love.graphics.setColor(1, 1, 1, 1)

  -- GBA WIN0 letterbox scissor (Y: 24 to 136)
  love.graphics.setScissor(0, 24, W, 112)

  if assets and assets.wb and assets.eb then
    local bg = (run.direction == DIRN_EASTBOUND) and assets.eb or assets.wb
    local ox = math.floor(run.bgX)
    local startX = -ox
    while startX > 0 do startX = startX - 256 end
    for x = startX, W, 256 do
      love.graphics.draw(bg, x, 0)
    end

    -- Wakes
    if assets.wake and assets.wakeQuads then
      local scaleX = (run.direction == DIRN_EASTBOUND) and -1 or 1
      for _, w in ipairs(run.wakes) do
        local q = assets.wakeQuads[w.frame] or assets.wakeQuads[1]
        love.graphics.draw(assets.wake, q, math.floor(w.x), math.floor(w.y), 0, scaleX, 1, 16, 16)
      end
    end

    -- Ferry
    if assets.ferry then
      local scaleX = (run.direction == DIRN_EASTBOUND) and -1 or 1
      love.graphics.draw(assets.ferry, math.floor(run.ferryX), math.floor(run.ferryY), 0, scaleX, 1, 32, 20)
    end
  else
    love.graphics.setColor(0.18, 0.44, 0.75, 1)
    love.graphics.rectangle("fill", 0, 24, W, 112)
  end

  love.graphics.setScissor()

  -- Top and bottom black letterbox bars (and side borders)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("fill", -maxW, -maxH, maxW * 3, maxH + 24)
  love.graphics.rectangle("fill", -maxW, 136, maxW * 3, maxH * 2)
  love.graphics.rectangle("fill", -maxW, 0, maxW, H)
  love.graphics.rectangle("fill", W, 0, maxW, H)
  love.graphics.setColor(1, 1, 1, 1)
end

return Seagallop
