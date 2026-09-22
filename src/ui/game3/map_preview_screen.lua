-- FireRed location preview screen (pokefirered/src/map_preview_screen.c).
--
-- Forest-type map sections show a full-screen baked artwork plus a location
-- name window during the overworld warp transition, replacing the map name
-- popup. Cave-type sections have artwork too, but pret only uses that artwork
-- in the Town Map GUIDE panel, so show() refuses them unless opts.anyType.

local FrlgFont = require("src.ui.game3.frlg_font")
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

-- Task_RunMapPreviewScreenForest case 4 walks a 3-frame counter, adding 16 to
-- BLDALPHA's backdrop weight and dropping BG0's by 16. Both need 16 steps, so
-- the fade-out takes 32 changes over a 3-frame cycle = 48 frames.
local FADE_OUT_FRAMES = 48
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

--- Baked artwork Image for a mapsec, or nil. Misses are cached as false.
function MapPreviewScreen.image(mapsec)
  local artwork = MapPreviewScreen.artworkFor(mapsec)
  if not artwork then return nil end
  local cached = MapPreviewScreen._images[artwork]
  if cached ~= nil then return cached or nil end

  local rel = string.format("%s/%s/%d.rgba", cache_root(), MapPreviewExtract.CACHE_SUB, artwork)
  local bytes = read_bytes(rel)
  local image = bytes and rgba_to_image(bytes, MapPreviewExtract.WIDTH, MapPreviewExtract.HEIGHT) or nil
  if not image then
    log("missing baked artwork " .. rel)
    MapPreviewScreen._images[artwork] = false
    return nil
  end
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

function MapPreviewScreen.show(mapsec, opts)
  opts = opts or {}
  local entry = MapPreviewScreen.entryFor(mapsec)
  if not entry then return false end
  if not opts.anyType and entry.type ~= MapPreviewExtract.TYPE_FOREST then return false end
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
  return true
end

function MapPreviewScreen.dismiss()
  MapPreviewScreen._active = false
  MapPreviewScreen._state = STATE_IDLE
  MapPreviewScreen._entry = nil
  MapPreviewScreen._image = nil
  MapPreviewScreen._timer = 0
  MapPreviewScreen._fadeFrames = 0
end

function MapPreviewScreen.isActive()
  return MapPreviewScreen._active == true
end

function MapPreviewScreen.mapsec()
  return MapPreviewScreen._mapsec
end

--- 0..1 artwork opacity. pret blends BG0 against the field so the artwork
--- dissolves into the freshly loaded map rather than into black.
function MapPreviewScreen.alpha()
  if MapPreviewScreen._state ~= STATE_FADE_OUT then return 1 end
  local a = 1 - (MapPreviewScreen._fadeFrames / FADE_OUT_FRAMES)
  if a < 0 then a = 0 end
  return a
end

--- Task_RunMapPreviewScreenForest: hold for `duration` frames once the
--- FadeInFromBlack settles, then dissolve BG0 out over FADE_OUT_FRAMES.
function MapPreviewScreen.update(dt)
  if not MapPreviewScreen._active then return end
  local step = math.floor(((dt or (1 / 60)) * 60) + 0.5)
  if step < 1 then step = 1 end
  for _ = 1, step do
    if MapPreviewScreen._state == STATE_HOLD then
      local Fade = package.loaded["src.ui.game3.fade"]
      local fadingIn = Fade and Fade.isActive and Fade.isActive()
      if not fadingIn then
        MapPreviewScreen._timer = MapPreviewScreen._timer + 1
        if MapPreviewScreen._timer > MapPreviewScreen._duration then
          MapPreviewScreen._state = STATE_FADE_OUT
          MapPreviewScreen._fadeFrames = 0
        end
      end
    elseif MapPreviewScreen._state == STATE_FADE_OUT then
      MapPreviewScreen._fadeFrames = MapPreviewScreen._fadeFrames + 1
      if MapPreviewScreen._fadeFrames >= FADE_OUT_FRAMES then
        MapPreviewScreen.dismiss()
      end
    end
  end
end

local function nameWindowColors(manifest)
  local nw = manifest and manifest.name_window
  local function rgb(t, fallback)
    if type(t) == "table" and t[1] and t[2] and t[3] then
      return { t[1] / 255, t[2] / 255, t[3] / 255, 1 }
    end
    return fallback
  end
  return {
    fill = rgb(nw and nw.fill, { 247 / 255, 247 / 255, 255 / 255, 1 }),
    fg = rgb(nw and nw.fg, FrlgFont.STDPAL[1]),
    shadow = rgb(nw and nw.shadow, { 0, 0, 0, 1 }),
    bg = rgb(nw and nw.bg, FrlgFont.STDPAL[0]),
  }
end

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

--- BG0 holds both the artwork and the name window, so pret's BLDALPHA ramp
--- dissolves them together. Compose them into an offscreen buffer to fade the
--- pair as one layer.
function MapPreviewScreen.draw()
  if not MapPreviewScreen._active then return end
  local image = MapPreviewScreen._image or MapPreviewScreen.image(MapPreviewScreen._mapsec)
  if not image then return end
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
