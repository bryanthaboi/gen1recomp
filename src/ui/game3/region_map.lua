-- FRLG Kanto & Sevii Region Map UI (pret region_map.c).
-- Interactive Town Map screen showing Kanto map, player location marker,
-- landmark selection cursor, and authentic top/bottom header bars.

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Display = require("src.core.game3.display")
local FrlgFont = require("src.ui.game3.frlg_font")
local RegionExtract = require("src.import.gba.region_map_extract")

local RegionMap = {}

RegionMap.open = false
RegionMap.cursorX = 4
RegionMap.cursorY = 11
RegionMap.playerX = 4
RegionMap.playerY = 11
RegionMap.playerGender = 0 -- 0: Red (male), 1: Leaf (female)
RegionMap._images = {}
RegionMap._session = nil
RegionMap._onClose = nil

local MAP_OFFSET_X = 36
local MAP_OFFSET_Y = 24
local CELL_SIZE = 8

local function try_load_image(path)
  if not (love and love.graphics and love.graphics.newImage) then return nil end
  local ok, img = pcall(love.graphics.newImage, path)
  if ok and img then
    if img.setFilter then img:setFilter("nearest", "nearest") end
    return img
  end
  return nil
end

local function get_map_image()
  if RegionMap._images["kanto_map"] ~= nil then
    return RegionMap._images["kanto_map"] or nil
  end
  local candidates = {
    "data/generated/gba/region_map/kanto_map.png",
    "pokefirered/graphics/region_map/region_map.png",
    "assets/generated/region_map/kanto_map.png",
  }
  for _, p in ipairs(candidates) do
    local img = try_load_image(p)
    if img then
      RegionMap._images["kanto_map"] = img
      return img
    end
  end
  RegionMap._images["kanto_map"] = false
  return nil
end

local function get_cursor_image()
  if RegionMap._images["cursor"] ~= nil then
    return RegionMap._images["cursor"] or nil
  end
  local img = try_load_image("pokefirered/graphics/region_map/cursor.png")
    or try_load_image("data/generated/gba/region_map/cursor.png")
  RegionMap._images["cursor"] = img or false
  return img
end

local function get_player_image(female)
  local key = female and "player_leaf" or "player_red"
  if RegionMap._images[key] ~= nil then
    return RegionMap._images[key] or nil
  end
  local path = female and "pokefirered/graphics/region_map/player_icon_leaf.png"
    or "pokefirered/graphics/region_map/player_icon_red.png"
  local img = try_load_image(path) or try_load_image("data/generated/gba/region_map/" .. key .. ".png")
  RegionMap._images[key] = img or false
  return img
end

function RegionMap.show(opts)
  opts = opts or {}
  RegionMap.open = true
  RegionMap._session = opts.session
  RegionMap._onClose = opts.onClose

  local session = opts.session
  local mapId = session and session.map
  local mapSec = session and session.mapSec
  local loc = RegionExtract.resolveLocation(mapId, mapSec)

  RegionMap.playerX = loc.x
  RegionMap.playerY = loc.y
  RegionMap.cursorX = loc.x
  RegionMap.cursorY = loc.y

  local gender = session and (session.gender or session.playerGender)
  RegionMap.playerGender = (gender == 1 or gender == "female") and 1 or 0

  Stack.push("region_map", RegionMap, { hideBelow = true })
end

function RegionMap.close()
  RegionMap.open = false
  Stack.pop("region_map")
  local cb = RegionMap._onClose
  RegionMap._onClose = nil
  if cb then cb() end
end

function RegionMap.isOpen()
  return RegionMap.open
end

function RegionMap.currentLocationName()
  local row = RegionExtract.KANTO_GRID[RegionMap.cursorY]
  local sec = row and row[RegionMap.cursorX]
  if sec and RegionExtract.SECTION_NAMES[sec] then
    return RegionExtract.SECTION_NAMES[sec]
  end
  return "KANTO REGION"
end

function RegionMap.handleInput(input)
  local function se(id)
    pcall(function() require("src.core.game3.audio").playSe(id) end)
  end

  if input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("select") then
    se(9)
    RegionMap.close()
    return
  end

  local moved = false
  if input:wasPressed("left") then
    if RegionMap.cursorX > 0 then
      RegionMap.cursorX = RegionMap.cursorX - 1
      moved = true
    end
  elseif input:wasPressed("right") then
    if RegionMap.cursorX < RegionExtract.MAP_WIDTH - 1 then
      RegionMap.cursorX = RegionMap.cursorX + 1
      moved = true
    end
  elseif input:wasPressed("up") then
    if RegionMap.cursorY > 0 then
      RegionMap.cursorY = RegionMap.cursorY - 1
      moved = true
    end
  elseif input:wasPressed("down") then
    if RegionMap.cursorY < RegionExtract.MAP_HEIGHT - 1 then
      RegionMap.cursorY = RegionMap.cursorY + 1
      moved = true
    end
  end

  if moved then
    se(5)
  end
end

function RegionMap.draw()
  if not RegionMap.open then return end
  if not (love and love.graphics) then return end

  -- 1. Base Sea Backdrop (#5888A8 / authentic blue)
  love.graphics.setColor(0.35, 0.53, 0.66, 1.0)
  love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  love.graphics.setColor(1, 1, 1, 1)

  -- 2. Kanto Map Backdrop
  local mapImg = get_map_image()
  if mapImg then
    love.graphics.draw(mapImg, 0, 0)
  else
    -- Procedural Kanto Geography & Route network
    -- Landmass Fill
    love.graphics.setColor(0.55, 0.78, 0.45, 1.0) -- Land green
    love.graphics.rectangle("fill", MAP_OFFSET_X, MAP_OFFSET_Y, RegionExtract.MAP_WIDTH * CELL_SIZE, RegionExtract.MAP_HEIGHT * CELL_SIZE)

    -- Draw Routes and Cities from Grid
    for y = 0, RegionExtract.MAP_HEIGHT - 1 do
      local row = RegionExtract.KANTO_GRID[y]
      if row then
        for x = 0, RegionExtract.MAP_WIDTH - 1 do
          local sec = row[x]
          if sec then
            local px = MAP_OFFSET_X + x * CELL_SIZE
            local py = MAP_OFFSET_Y + y * CELL_SIZE
            if sec:find("CITY", 1, true) or sec:find("TOWN", 1, true) or sec:find("PLATEAU", 1, true) then
              -- City Node
              love.graphics.setColor(0.85, 0.20, 0.20, 1.0) -- Red city square
              love.graphics.rectangle("fill", px + 1, py + 1, 6, 6)
              love.graphics.setColor(0.2, 0.2, 0.2, 1.0)
              love.graphics.rectangle("line", px + 1, py + 1, 6, 6)
            elseif sec:find("ROUTE", 1, true) then
              -- Route Path
              love.graphics.setColor(0.70, 0.65, 0.50, 1.0) -- Path beige
              love.graphics.rectangle("fill", px + 2, py + 2, 4, 4)
            else
              -- Cave / Dungeon Node
              love.graphics.setColor(0.40, 0.35, 0.30, 1.0) -- Brown cave
              love.graphics.rectangle("fill", px + 2, py + 2, 4, 4)
            end
          end
        end
      end
    end
  end

  -- 3. Player Head Marker
  local female = (RegionMap.playerGender == 1)
  local playerImg = get_player_image(female)
  local pPx = MAP_OFFSET_X + RegionMap.playerX * CELL_SIZE
  local pPy = MAP_OFFSET_Y + RegionMap.playerY * CELL_SIZE
  if playerImg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(playerImg, pPx - 4, pPy - 4)
  else
    -- Fallback Head icon
    love.graphics.setColor(female and 0.9 or 0.2, 0.2, female and 0.4 or 0.9, 1)
    love.graphics.circle("fill", pPx + 4, pPy + 4, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("line", pPx + 4, pPy + 4, 5)
  end

  -- 4. Target Selection Cursor
  local cursorImg = get_cursor_image()
  local cPx = MAP_OFFSET_X + RegionMap.cursorX * CELL_SIZE
  local cPy = MAP_OFFSET_Y + RegionMap.cursorY * CELL_SIZE
  if cursorImg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(cursorImg, cPx - 4, cPy - 4)
  else
    -- Authentic animated / blinking cursor box
    love.graphics.setColor(1, 0.1, 0.1, 1)
    love.graphics.rectangle("line", cPx - 1, cPy - 1, 10, 10)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- 5. Top Landmark Name Banner (y=0..20, dark header frame with white font)
  love.graphics.setColor(0.12, 0.22, 0.18, 0.92)
  love.graphics.rectangle("fill", 0, 0, Display.W, 20)
  love.graphics.setColor(0.40, 0.60, 0.50, 1.0)
  love.graphics.rectangle("fill", 0, 20, Display.W, 2)
  love.graphics.setColor(1, 1, 1, 1)

  local locName = RegionMap.currentLocationName()
  local tw = FrlgFont.measure(locName)
  local tx = math.floor((Display.W - tw) / 2)
  FrlgFont.draw(locName, tx, 3, { colors = FrlgFont.COLOR.WHITE })

  -- 6. Bottom Control Hint Bar (y=144..160)
  love.graphics.setColor(0.12, 0.22, 0.18, 0.92)
  love.graphics.rectangle("fill", 0, 144, Display.W, 16)
  love.graphics.setColor(0.40, 0.60, 0.50, 1.0)
  love.graphics.rectangle("fill", 0, 143, Display.W, 1)
  love.graphics.setColor(1, 1, 1, 1)

  FrlgFont.draw("D-PAD: MOVE", 8, 146, { colors = FrlgFont.COLOR.WHITE, small = true })
  FrlgFont.draw("B BUTTON: CANCEL", 140, 146, { colors = FrlgFont.COLOR.WHITE, small = true })
end

return RegionMap
