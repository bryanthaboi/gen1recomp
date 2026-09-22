-- 1:1 FireRed Map Name Popup Overlay (pokefirered/src/map_name_popup.c)
-- Slides down from top-left on area/map transitions when showMapName == 1.

local FrlgFont = require("src.ui.game3.frlg_font")
local Chrome = require("src.ui.game3.chrome")
local MapSectionsExtract = require("src.import.gba.map_sections_extract")
local Strings = require("src.core.Strings")

local MapNamePopup = {}

-- State Machine Constants
local STATE_IDLE = 0
local STATE_SLIDE_IN = 1
local STATE_HOLD = 2
local STATE_SLIDE_OUT = 3

MapNamePopup.STATE = {
  IDLE = STATE_IDLE,
  SLIDE_IN = STATE_SLIDE_IN,
  HOLD = STATE_HOLD,
  SLIDE_OUT = STATE_SLIDE_OUT,
}

MapNamePopup._state = STATE_IDLE
MapNamePopup._tPos = 0 -- 0..24 pixels (Love2D Y = _tPos - 24)
MapNamePopup._timer = 0 -- frame counter for hold state
MapNamePopup._reshow = false
MapNamePopup._pendingName = nil
MapNamePopup._pendingWidthTiles = 14
MapNamePopup._pendingWidth = 112

-- Active banner properties
MapNamePopup._name = ""
MapNamePopup._widthTiles = 14
MapNamePopup._contentWidth = 112 -- 14 tiles * 8px
MapNamePopup._floorNum = 0

--- Check if flag FLAG_DONT_SHOW_MAP_NAME_POPUP (0x8000) is set in session
local function isFlagSuppressed()
  local Space = package.loaded["src.core.game3.scripting.space"]
  local Flags = package.loaded["src.core.game3.scripting.flags"]
  local store = Space and Space.store
  if store and Flags and Flags.getFlag then
    if Flags.getFlag(store, nil, 0x8000) then return true end
  end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local session = Runtime and Runtime.getSession and Runtime.getSession()
  if session and session.flags and session.flags[0x8000] then
    return true
  end
  return false
end

--- Format clean fallback name from mapId if somehow unresolved
local function cleanMapName(mapId)
  if type(mapId) ~= "string" or mapId == "" then return "KANTO" end
  local s = mapId:gsub("^FR_", ""):gsub("^SEVII_", "")
  s = s:gsub("(%l)(%u)", "%1 %2")
  s = s:gsub("(%a)(%d)", "%1 %2")
  s = s:gsub("(%d)(%a)", "%1 %2")
  s = s:gsub("_", " "):gsub("%s+", " "):upper()
  return s
end

--- Trigger map name popup display
-- The section names are the cart's English, with the floor label
-- map_name_popup.c appends.  Both go through Strings(): the floor as a whole
-- label ("3F", "B1F", "ROOFTOP", the cart's gText_3F... rows), since the
-- European carts count floors differently (3F is "2E" in French).
local function translated_name(info)
  local base = Strings(info.rawName or info.name)
  local floor = tonumber(info.floorNum) or 0
  local label
  if floor == 127 then label = "ROOFTOP"
  elseif floor < 0 then label = string.format("B%dF", -floor)
  elseif floor > 0 then label = string.format("%dF", floor) end
  if not label then return base end
  return base .. " " .. Strings(label)
end

function MapNamePopup.show(mapDef, opts)
  opts = opts or {}
  if isFlagSuppressed() then return false end

  -- Strict indoor suppression: showMapName must be 1/true unless forced by opts
  if not opts.force then
    local showFlag = mapDef and (mapDef.showMapName or mapDef.show_map_name)
    if showFlag == 0 or showFlag == false then
      MapNamePopup.dismiss()
      return false
    end
  end

  local secId = mapDef and (mapDef.regionMapSectionId or mapDef.region_map_section_id or mapDef.mapsec)
  local mapId = mapDef and (mapDef.id or mapDef.name or mapDef.map)
  local floorNum = mapDef and (mapDef.floorNum or mapDef.floor_num or mapDef.floor) or 0

  local info = MapSectionsExtract.getInfo(secId, mapId, floorNum)
  local name = info and info.name
  -- getInfo answers with the Pallet Town placeholder for a map it could not
  -- identify (resolved == false).  Treat that as "no name" so the popup shows
  -- the cleaned map id instead of a place the map is not.
  if not name or name == "???" or name == "" or (info and info.resolved == false) then
    name = cleanMapName(mapId)
  else
    name = translated_name(info)
  end

  -- Calculate width matching pokefirered MapNamePopupCreateWindow:
  -- Floor == 0: width = 14 (112px content)
  -- Floor != 0 and Floor != 127: width = 19 (152px content)
  -- Floor == 127 (Rooftop): width = 22 (176px content)
  local widthTiles = 14
  local contentW = 112
  local floor = tonumber(floorNum) or (info and info.floorNum) or 0
  if floor ~= 0 then
    if floor == 127 then
      widthTiles = 22
      contentW = 176
    else
      widthTiles = 19
      contentW = 152
    end
  end

  if MapNamePopup._state == STATE_IDLE then
    MapNamePopup._name = name
    MapNamePopup._widthTiles = widthTiles
    MapNamePopup._contentWidth = contentW
    MapNamePopup._floorNum = floor
    MapNamePopup._tPos = 0
    MapNamePopup._timer = 0
    MapNamePopup._reshow = false
    MapNamePopup._state = STATE_SLIDE_IN
  else
    -- If already active, trigger reshow: slide up and reload text
    MapNamePopup._pendingName = name
    MapNamePopup._pendingWidthTiles = widthTiles
    MapNamePopup._pendingWidth = contentW
    MapNamePopup._reshow = true
    if MapNamePopup._state ~= STATE_SLIDE_OUT then
      MapNamePopup._state = STATE_SLIDE_OUT
    end
  end

  return true
end

--- Dismiss active popup immediately (e.g. on dialogue open, battle, or indoor warp)
function MapNamePopup.dismiss()
  if MapNamePopup._state ~= STATE_IDLE then
    MapNamePopup._state = STATE_IDLE
    MapNamePopup._tPos = 0
    MapNamePopup._timer = 0
    MapNamePopup._reshow = false
    MapNamePopup._pendingName = nil
  end
end

--- Check if popup is currently visible/animating
function MapNamePopup.isActive()
  return MapNamePopup._state ~= STATE_IDLE
end

--- Frame tick (60 FPS / dt-based)
function MapNamePopup.update(dt)
  if MapNamePopup._state == STATE_IDLE then return end

  -- Fixed-step 60 FPS increments (or accumulated sub-frames)
  local step = math.max(1, math.floor(((dt or (1 / 60)) * 60) + 0.5))

  for _ = 1, step do
    if MapNamePopup._state == STATE_SLIDE_IN then
      -- pokefirered/src/map_name_popup.c:66: task->tPos -= 2 (slide down 2px per frame)
      MapNamePopup._tPos = MapNamePopup._tPos + 2
      if MapNamePopup._tPos >= 24 then
        MapNamePopup._tPos = 24
        MapNamePopup._state = STATE_HOLD
        MapNamePopup._timer = 0
      end
    elseif MapNamePopup._state == STATE_HOLD then
      -- pokefirered/src/map_name_popup.c:75: hold for 120 frames (2.0 seconds)
      MapNamePopup._timer = MapNamePopup._timer + 1
      if MapNamePopup._timer > 120 then
        MapNamePopup._timer = 0
        MapNamePopup._state = STATE_SLIDE_OUT
      end
    elseif MapNamePopup._state == STATE_SLIDE_OUT then
      -- pokefirered/src/map_name_popup.c:82: slide back up 2px per frame
      MapNamePopup._tPos = MapNamePopup._tPos - 2
      if MapNamePopup._tPos <= 0 then
        MapNamePopup._tPos = 0
        if MapNamePopup._reshow and MapNamePopup._pendingName then
          MapNamePopup._name = MapNamePopup._pendingName
          MapNamePopup._widthTiles = MapNamePopup._pendingWidthTiles or 14
          MapNamePopup._contentWidth = MapNamePopup._pendingWidth or 112
          MapNamePopup._pendingName = nil
          MapNamePopup._reshow = false
          MapNamePopup._state = STATE_SLIDE_IN
        else
          MapNamePopup._state = STATE_IDLE
          return
        end
      end
    end
  end
end

--- Draw 1:1 FireRed location banner
function MapNamePopup.draw()
  if MapNamePopup._state == STATE_IDLE or MapNamePopup._tPos <= 0 then
    return
  end

  local tPos = MapNamePopup._tPos
  -- Love2D coordinate translation: base Y sits at tPos - 24
  -- When tPos = 0: py = -24 (offscreen above viewport)
  -- When tPos = 24: py = 0 (flush against top bezel [0, 0])
  local px = 0
  local py = tPos - 24
  local widthTiles = MapNamePopup._widthTiles or 14
  local contentW = MapNamePopup._contentWidth or (widthTiles * 8)

  -- 1. Draw 9-slice standard text window border and white interior
  Chrome.mapPopupFrame(px, py, widthTiles)

  -- 2. Map Name Text (Centered vertically and horizontally in enclosed window)
  -- Uses FONT_NORMAL with dark gray (#626262) fg and light gray (#D5D5CD) shadow
  local name = MapNamePopup._name or ""
  local textW = (FrlgFont.measure and FrlgFont.measure(name)) or (6 * #name)
  local textX = px + 8 + math.floor((contentW - textW) / 2)
  local textY = py + 5

  FrlgFont.draw(name, textX, textY, {
    colors = FrlgFont.COLOR.NORMAL,
    maxWidth = contentW,
  })

  love.graphics.setColor(1, 1, 1, 1)
end

return MapNamePopup
