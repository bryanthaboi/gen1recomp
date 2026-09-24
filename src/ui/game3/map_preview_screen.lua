-- FireRed location preview screen (pokefirered/src/map_preview_screen.c).

local FrlgFont = require("src.ui.game3.frlg_font")
local CaveTransition = require("src.ui.game3.cave_transition")
local Extract = require("src.import.gba.extract_island1")
local MapPreviewExtract = require("src.import.gba.map_preview_extract")
local Strings = require("src.core.Strings")

local MapPreviewScreen = {}

local STATE_IDLE = 0
local STATE_HOLD = 1
local STATE_FADE_OUT = 2

MapPreviewScreen.STATE = { IDLE = STATE_IDLE, HOLD = STATE_HOLD, FADE_OUT = STATE_FADE_OUT }

-- map_preview_screen.c:static const struct WindowTemplate sMapNameWindow
-- { .bg = 0, .tilemapLeft = 0, .tilemapTop = 0, .width = 13, .height = 2,
--   .paletteNum = 14, .baseBlock = 0x1C2 }
-- No LoadStdWindowTiles / DrawTextBorderOuter call, so unlike the map name
-- popup the window is a plain solid rect with no 9-slice border.
local NAME_WINDOW_X = 0
local NAME_WINDOW_Y = 0
local NAME_WINDOW_TILES = 13
local NAME_WINDOW_W = NAME_WINDOW_TILES * 8 -- 104, matches the xctr base
local NAME_WINDOW_H = 2 * 8
local NAME_WINDOW_TEXT_Y = 2 -- AddTextPrinterParameterized4(..., xctr / 2, 2, ...)

-- src/map_preview_screen.c:513
local FADE_OUT_FRAMES = 47
local DURATION_FIRST_VISIT = 120
local DURATION_REVISIT = 40

MapPreviewScreen.FADE_OUT_FRAMES = FADE_OUT_FRAMES
MapPreviewScreen.DURATION_FIRST_VISIT = DURATION_FIRST_VISIT
MapPreviewScreen.DURATION_REVISIT = DURATION_REVISIT

-- mps.c sHasVisitedMapBefore: a transient EWRAM global that MapPreview_SetFlag
-- refreshes on every ScrCmd_setworldmapflag and that never resets.
MapPreviewScreen.hasVisitedBefore = false

MapPreviewScreen._active = false
MapPreviewScreen._state = STATE_IDLE
MapPreviewScreen._mapsec = nil
MapPreviewScreen._entry = nil
MapPreviewScreen._name = nil
MapPreviewScreen._timer = 0
MapPreviewScreen._duration = 0
MapPreviewScreen._fadeFrames = 0
MapPreviewScreen._eva = 16
MapPreviewScreen._evb = 0
MapPreviewScreen._phase = 0
MapPreviewScreen._onDone = nil
MapPreviewScreen._cave = nil

MapPreviewScreen._cache = nil
MapPreviewScreen._manifest = nil
MapPreviewScreen._manifestTried = false
MapPreviewScreen._images = {}
MapPreviewScreen._canvas = nil
MapPreviewScreen._logged = false

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function log(msg)
  if MapPreviewScreen._logged then return end
  MapPreviewScreen._logged = true
  print("[game3/map_preview_screen] " .. tostring(msg))
end

local function read_bytes(rel)
  local cache = MapPreviewScreen._cache
  if cache and cache.read then
    local d = cache:read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local d = Dataset.cache():read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok and CacheFs and CacheFs.readActive then
    local d = CacheFs.readActive(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  if love and love.filesystem and love.filesystem.read then
    local d = love.filesystem.read(rel)
    if type(d) == "string" and #d > 0 then return d end
    local alt = "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", ""))
    d = love.filesystem.read(alt)
    if type(d) == "string" and #d > 0 then return d end
  end
  local candidates = {
    rel,
    "data/generated/gba/" .. (rel:gsub("^data/generated/gba/", "")),
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

local function load_lua(rel)
  local src = read_bytes(rel)
  if not src then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, t = pcall(chunk)
  if ok then return t end
  return nil
end

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end
  local ok, imageData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not ok or not imageData then
    imageData = love.image.newImageData(w, h)
    local i = 1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        imageData:setPixel(x, y,
          (rgba:byte(i) or 0) / 255,
          (rgba:byte(i + 1) or 0) / 255,
          (rgba:byte(i + 2) or 0) / 255,
          (rgba:byte(i + 3) or 0) / 255)
        i = i + 4
      end
    end
  end
  local image = love.graphics.newImage(imageData)
  if image.setFilter then image:setFilter("nearest", "nearest") end
  return image
end

function MapPreviewScreen.install(cache)
  if not cache or not cache.read then
    local okD, Dataset = pcall(require, "src.core.game3.dataset")
    if okD and Dataset and Dataset.cache then cache = Dataset.cache() end
  end
  MapPreviewScreen._cache = cache
end

function MapPreviewScreen.manifest()
  if MapPreviewScreen._manifest then
    return MapPreviewScreen._manifest
  end
  local rel = cache_root() .. "/" .. MapPreviewExtract.CACHE_SUB .. "/manifest.lua"
  local t = load_lua(rel)
  if type(t) ~= "table" or type(t.entries) ~= "table" then
    log("no preview manifest at " .. rel)
    return nil
  end
  MapPreviewScreen._manifest = t
  return t
end

function MapPreviewScreen.ready()
  return MapPreviewScreen.manifest() ~= nil
end

--- The map_preview_screen.c entry for a mapsec, or nil when there is none.
function MapPreviewScreen.entryFor(mapsec)
  local manifest = MapPreviewScreen.manifest()
  if not manifest then return nil end
  local id = tonumber(mapsec)
  if not id then return nil end
  for _, e in ipairs(manifest.entries) do
    if e.mapsec == id then return e end
  end
  return nil
end

--- The mapsec whose baked artwork an entry reuses (PATTERN_BUSH and the six
--- Tanoby chambers share another section's artwork), or nil.
function MapPreviewScreen.artworkFor(mapsec)
  local entry = MapPreviewScreen.entryFor(mapsec)
  if entry then return entry.artwork end
  return nil
end

--- Baked artwork Image for a mapsec; nil when it has no preview or LOVE has no graphics.
function MapPreviewScreen.image(mapsec)
  local artwork = MapPreviewScreen.artworkFor(mapsec)
  if not artwork then return nil end
  local cached = MapPreviewScreen._images[artwork]
  if cached then return cached end

  local rel = string.format("%s/%s/%d.rgba", cache_root(), MapPreviewExtract.CACHE_SUB, artwork)
  local bytes = read_bytes(rel)
  assert(bytes and #bytes >= MapPreviewExtract.WIDTH * MapPreviewExtract.HEIGHT * 4,
    "missing baked artwork " .. rel)
  local image = rgba_to_image(bytes, MapPreviewExtract.WIDTH, MapPreviewExtract.HEIGHT)
  MapPreviewScreen._images[artwork] = image
  return image
end

--- MapPreview_GetDuration: a mapsec with no entry lasts 0 frames. Caves key off
--- their own world-map flag; forests key off the transient global that
--- ScrCmd_setworldmapflag refreshed when the section was last entered.
function MapPreviewScreen.durationFor(mapsec)
  local entry = MapPreviewScreen.entryFor(mapsec)
  if not entry then return 0 end
  if entry.type == MapPreviewExtract.TYPE_CAVE then
    return MapPreviewScreen.isFlagSet(entry.flagId) and DURATION_REVISIT or DURATION_FIRST_VISIT
  end
  return MapPreviewScreen.hasVisitedBefore and DURATION_FIRST_VISIT or DURATION_REVISIT
end

--- FlagGet, reading the scripting store first and the runtime session second
--- (the same two sources map_name_popup.lua consults).
function MapPreviewScreen.isFlagSet(flagId)
  local id = tonumber(flagId)
  if not id then return false end
  local Space = package.loaded["src.core.game3.scripting.space"]
  local Flags = package.loaded["src.core.game3.scripting.flags"]
  if not Flags then
    local ok, mod = pcall(require, "src.core.game3.scripting.flags")
    Flags = ok and mod or nil
  end
  local store = Space and Space.store
  if store and Flags and Flags.getFlag then
    local ok, val = pcall(Flags.getFlag, store, nil, id)
    if ok and val == true then return true end
  end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  if session and session.flags and session.flags[id] then return true end
  return false
end

--- True when mapsec has an overworld preview of the given type. Mirrors
--- MapHasPreviewScreen; the overworld only ever asks for MPS_TYPE_FOREST.
function MapPreviewScreen.has(mapsec, type_)
  local entry = MapPreviewScreen.entryFor(mapsec)
  if not entry then return false end
  if type_ == nil then return true end
  return entry.type == type_
end

--- MapPreview_SetFlag: capture the pre-visit state, then set the flag.
function MapPreviewScreen.setVisitedFlag(flagId, wasSet)
  MapPreviewScreen.hasVisitedBefore = wasSet ~= true
end

local function scriptRunning()
  local Space = package.loaded["src.core.game3.scripting.space"]
  return Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning()
end

function MapPreviewScreen.show(mapsec)
  local entry = MapPreviewScreen.entryFor(mapsec)
  if not entry then return false end
  if entry.type ~= MapPreviewExtract.TYPE_FOREST then return false end
  local duration = MapPreviewScreen.durationFor(mapsec)
  if duration <= 0 then return false end
  local image = MapPreviewScreen.image(mapsec)
  if not image then return false end

  MapPreviewScreen._active = true
  MapPreviewScreen._state = STATE_HOLD
  MapPreviewScreen._mapsec = entry.mapsec
  MapPreviewScreen._entry = entry
  MapPreviewScreen._name = entry.name
  MapPreviewScreen._image = image
  MapPreviewScreen._timer = 0
  MapPreviewScreen._duration = duration
  MapPreviewScreen._fadeFrames = 0
  MapPreviewScreen._eva = 16
  MapPreviewScreen._evb = 0
  MapPreviewScreen._phase = 0
  -- src/map_preview_screen.c:439
  local Field = package.loaded["src.core.game3.field"]
  if Field and Field.lock then
    Field.lock()
    MapPreviewScreen._onDone = function()
      -- src/field_fadetransition.c:454
      local Warp = package.loaded["src.core.game3.warp"]
      if Field.unlock and not scriptRunning() and not (Warp and Warp.isBusy and Warp.isBusy()) then
        Field.unlock()
      end
    end
  end
  return true
end

function MapPreviewScreen.dismiss()
  local wasActive = MapPreviewScreen._active
  MapPreviewScreen._active = false
  MapPreviewScreen._state = STATE_IDLE
  MapPreviewScreen._entry = nil
  MapPreviewScreen._image = nil
  MapPreviewScreen._timer = 0
  MapPreviewScreen._fadeFrames = 0
  MapPreviewScreen._eva = 16
  MapPreviewScreen._evb = 0
  MapPreviewScreen._phase = 0
  local onDone = MapPreviewScreen._onDone
  MapPreviewScreen._onDone = nil
  if wasActive and onDone then onDone() end
end

-- pokefirered/src/main.c:480
function MapPreviewScreen.reset()
  MapPreviewScreen._onDone = nil
  MapPreviewScreen.dismiss()
  MapPreviewScreen._cave = nil
  CaveTransition.clear()
end

function MapPreviewScreen.isForestActive()
  return MapPreviewScreen._active == true
end

function MapPreviewScreen.isActive()
  return MapPreviewScreen._active == true or MapPreviewScreen._cave ~= nil
    or CaveTransition.isActive()
end

function MapPreviewScreen.mapsec()
  return MapPreviewScreen._mapsec
end

function MapPreviewScreen.alpha()
  if MapPreviewScreen._state ~= STATE_FADE_OUT then return 1 end
  return MapPreviewScreen._eva / 16
end

-- src/fldeff_flash.c:422
function MapPreviewScreen.runCave(mapsec, done)
  local entry = MapPreviewScreen.entryFor(mapsec)
  if not entry or entry.type ~= MapPreviewExtract.TYPE_CAVE then return false end
  local image = MapPreviewScreen.image(mapsec)
  if not image then return false end
  MapPreviewScreen._cave = {
    step = 0,
    entry = entry,
    image = image,
    name = entry.name,
    mapsec = entry.mapsec,
    data1 = 0,
    duration = 0,
    fade = nil,
    level = 16,
    color = 0,
    done = done,
    frame = 0,
    defer = true,
  }
  return true
end

-- src/palette.c:113
local function paletteFadeUpdate(f)
  if not f.active then return false end
  if f.pending then return true end
  if f.finishing then
    -- src/palette.c:757
    if f.counter == 4 then
      f.active = false
      f.finishing = false
      f.counter = 0
      return false
    end
    f.counter = f.counter + 1
    return true
  end
  if f.toggle == 0 then f.bgY = f.y end
  f.toggle = 1 - f.toggle
  if f.toggle == 0 then
    if f.y == f.targetY then
      f.finishing = true
    elseif f.dec then
      f.y = math.max(f.targetY, f.y - f.deltaY)
    else
      f.y = math.min(f.targetY, f.y + f.deltaY)
    end
  end
  -- src/palette.c:126
  f.pending = not f.finishing
  return true
end

-- src/palette.c:151
local function paletteFadeBegin(delay, startY, targetY)
  local f = {
    deltaY = 2, y = startY, targetY = targetY, dec = startY >= targetY,
    toggle = 0, finishing = false, counter = 0, active = true, bgY = startY,
    pending = false,
  }
  if delay < 0 then f.deltaY = f.deltaY - delay end
  paletteFadeUpdate(f)
  -- src/palette.c:184
  f.pending = false
  return f
end

local function holdingB()
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local input = game and game.input
  return input and input.isDown and input:isDown("b") and true or false
end

local function caveStep(c)
  if c.defer then
    c.defer = false
    return
  end
  c.frame = c.frame + 1
  if c.step == 0 then
    c.level, c.color = 16, 0
    c.step = 1
  elseif c.step == 1 then
    c.step = 2
  elseif c.step == 2 then
    c.fade = paletteFadeBegin(-1, 16, 0)
    c.step = 3
  elseif c.step == 3 then
    if not paletteFadeUpdate(c.fade) then
      c.duration = MapPreviewScreen.durationFor(c.mapsec)
      c.step = 4
    end
  elseif c.step == 4 then
    -- src/fldeff_flash.c:458
    c.data1 = c.data1 + 1
    if c.data1 > c.duration or holdingB() then
      c.fade = paletteFadeBegin(-2, 0, 16)
      c.color = 1
      c.step = 5
    end
  elseif c.step == 5 then
    if not paletteFadeUpdate(c.fade) then
      -- src/fldeff_flash.c:474
      MapPreviewScreen._cave = nil
      CaveTransition.start("enter", c.done, true)
      return
    end
  end
  if c.fade then
    -- src/fldeff_flash.c:199 CB2_ChangeMapMain
    paletteFadeUpdate(c.fade)
    c.fade.pending = false
    c.level = c.fade.bgY
  end
end

function MapPreviewScreen.update(dt)
  local step = math.floor(((dt or (1 / 60)) * 60) + 0.5)
  if step < 1 then step = 1 end
  if MapPreviewScreen._cave or CaveTransition.isActive() then
    for _ = 1, step do
      if MapPreviewScreen._cave then
        caveStep(MapPreviewScreen._cave)
      elseif CaveTransition.isActive() then
        CaveTransition.update(1 / 60)
      end
    end
    return
  end
  if not MapPreviewScreen._active then return end
  for _ = 1, step do
    if MapPreviewScreen._state == STATE_HOLD then
      local Fade = package.loaded["src.ui.game3.fade"]
      local fadingIn = Fade and Fade.isActive and Fade.isActive()
      if not fadingIn then
        -- src/map_preview_screen.c:505
        MapPreviewScreen._timer = MapPreviewScreen._timer + 1
        if MapPreviewScreen._timer > MapPreviewScreen._duration then
          MapPreviewScreen._state = STATE_FADE_OUT
          MapPreviewScreen._fadeFrames = 0
          MapPreviewScreen._phase = 0
        end
      end
    elseif MapPreviewScreen._state == STATE_FADE_OUT then
      -- src/map_preview_screen.c:513
      local phase = MapPreviewScreen._phase
      if phase == 0 then
        MapPreviewScreen._evb = math.min(MapPreviewScreen._evb + 1, 16)
      elseif phase == 1 then
        MapPreviewScreen._eva = math.max(MapPreviewScreen._eva - 1, 0)
      end
      MapPreviewScreen._phase = (phase + 1) % 3
      MapPreviewScreen._fadeFrames = MapPreviewScreen._fadeFrames + 1
      if MapPreviewScreen._eva == 0 and MapPreviewScreen._evb == 16 then
        MapPreviewScreen.dismiss()
        return
      end
    end
  end
end

local function nameWindowColors(manifest)
  local nw = assert(manifest and manifest.name_window, "map preview manifest has no name_window")
  local function rgb(key)
    local t = nw[key]
    assert(type(t) == "table" and tonumber(t[1]) and tonumber(t[2]) and tonumber(t[3]),
      "map preview name_window." .. key .. " is malformed")
    return { t[1] / 255, t[2] / 255, t[3] / 255, 1 }
  end
  return { fill = rgb("fill"), fg = rgb("fg"), shadow = rgb("shadow"), bg = rgb("bg") }
end
MapPreviewScreen._nameWindowColors = nameWindowColors

local nwManifestCache, nwColorsCache, nwFontColors = false, nil, nil
local function nameWindowColorsCached()
  local m = MapPreviewScreen.manifest()
  if m ~= nwManifestCache or nwColorsCache == nil then
    nwManifestCache = m
    nwColorsCache = nameWindowColors(m)
    nwFontColors = { fg = nwColorsCache.fg, shadow = nwColorsCache.shadow, bg = nwColorsCache.bg }
  end
  return nwColorsCache, nwFontColors
end

local function drawNameWindow(name)
  local colors, fontColors = nameWindowColorsCached()
  local f = colors.fill

  love.graphics.setColor(f[1], f[2], f[3], 1)
  love.graphics.rectangle("fill", NAME_WINDOW_X, NAME_WINDOW_Y, NAME_WINDOW_W, NAME_WINDOW_H)

  if not name or name == "" then
    love.graphics.setColor(1, 1, 1, 1)
    return
  end

  -- The ROM's English section name, translated like the map popup's.
  name = Strings(name)
  -- MapPreview_CreateMapNameWindow: xctr = 104 - GetStringWidth(FONT_NORMAL, ...)
  local textW = FrlgFont.measure(name)
  local xctr = NAME_WINDOW_W - textW
  if xctr < 0 then xctr = 0 end
  FrlgFont.draw(name, NAME_WINDOW_X + math.floor(xctr / 2), NAME_WINDOW_Y + NAME_WINDOW_TEXT_Y, {
    colors = fontColors,
  })
  love.graphics.setColor(1, 1, 1, 1)
end

local function drawOpaque(image, name)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, 0, 0)
  drawNameWindow(name)
end

local function ensureCanvas()
  if not (love and love.graphics and love.graphics.newCanvas) then return nil end
  if MapPreviewScreen._canvas then return MapPreviewScreen._canvas end
  local ok, canvas = pcall(love.graphics.newCanvas, MapPreviewExtract.WIDTH, MapPreviewExtract.HEIGHT)
  if not ok or not canvas then return nil end
  if canvas.setFilter then canvas:setFilter("nearest", "nearest") end
  MapPreviewScreen._canvas = canvas
  return canvas
end

local function setVoidVeil(r, g, b, a)
  local Renderer = package.loaded["src.render.Renderer"]
  if Renderer then Renderer.voidVeil = { r, g, b, a } end
end

local function drawCave(c)
  drawOpaque(c.image, c.name)
  local k = (c.level or 0) / 16
  local v = c.color == 1 and 1 or 0
  if k > 0 then
    love.graphics.setColor(v, v, v, k)
    love.graphics.rectangle("fill", 0, 0, MapPreviewExtract.WIDTH, MapPreviewExtract.HEIGHT)
    love.graphics.setColor(1, 1, 1, 1)
  end
  setVoidVeil(v * k, v * k, v * k, 1)
end

function MapPreviewScreen.draw()
  if MapPreviewScreen._cave then
    drawCave(MapPreviewScreen._cave)
    return
  end
  if CaveTransition.isActive() then
    CaveTransition.draw()
    return
  end
  if not MapPreviewScreen._active then return end
  local image = MapPreviewScreen._image or MapPreviewScreen.image(MapPreviewScreen._mapsec)
  if not image then return end
  -- src/map_preview_screen.c:532
  setVoidVeil(0, 0, 0, 1 - MapPreviewScreen._evb / 16)
  local alpha = MapPreviewScreen.alpha()
  if alpha >= 1 then
    drawOpaque(image, MapPreviewScreen._name)
    return
  end

  local canvas = ensureCanvas()
  if not canvas then
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(image, 0, 0)
    love.graphics.setColor(1, 1, 1, 1)
    drawNameWindow(MapPreviewScreen._name)
    return
  end

  local previous = love.graphics.getCanvas and love.graphics.getCanvas() or nil
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  drawOpaque(image, MapPreviewScreen._name)
  love.graphics.setCanvas(previous)
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.draw(canvas, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
end

return MapPreviewScreen
