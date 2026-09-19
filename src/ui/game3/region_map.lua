local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Display = require("src.core.game3.display")
local FrlgFont = require("src.ui.game3.frlg_font")
local PokedexChrome = require("src.ui.game3.pokedex_chrome")
local RegionExtract = require("src.import.gba.region_map_extract")

local RegionMap = {}

RegionMap.open = false
RegionMap.cursorX = 4
RegionMap.cursorY = 11
RegionMap.playerX = 4
RegionMap.playerY = 11
RegionMap.playerGender = 0 -- 0: Red (male), 1: Leaf (female)
RegionMap.previewDungeon = nil
RegionMap._snapIndex = 0
RegionMap._images = {}
RegionMap._session = nil
RegionMap._onClose = nil

local MAP_OFFSET_X = 28
local MAP_OFFSET_Y = 28
local CELL_SIZE = 8

local CANCEL_BUTTON_X = 21
local CANCEL_BUTTON_Y = 13
local SWITCH_BUTTON_X = 21
local SWITCH_BUTTON_Y = 11

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
  local img = try_load_image("data/generated/gba/region_map/cursor.png")
    or try_load_image("pokefirered/graphics/region_map/cursor.png")
  RegionMap._images["cursor"] = img or false
  return img
end

local function get_dungeon_icon_image()
  if RegionMap._images["dungeon_icon"] ~= nil then
    return RegionMap._images["dungeon_icon"] or nil
  end
  local img = try_load_image("data/generated/gba/region_map/dungeon_icon.png")
  RegionMap._images["dungeon_icon"] = img or false
  return img
end

local function get_player_image(female)
  local key = female and "player_leaf" or "player_red"
  if RegionMap._images[key] ~= nil then
    return RegionMap._images[key] or nil
  end
  local path = "data/generated/gba/region_map/" .. key .. ".png"
  local img = try_load_image(path)
    or (female and try_load_image("pokefirered/graphics/region_map/player_icon_leaf.png")
               or try_load_image("pokefirered/graphics/region_map/player_icon_red.png"))
  RegionMap._images[key] = img or false
  return img
end

function RegionMap.show(opts)
  opts = opts or {}
  RegionMap.open = true
  RegionMap.previewDungeon = nil
  RegionMap._snapIndex = 0
  RegionMap._session = opts.session
  RegionMap._onClose = opts.onClose

  PokedexChrome.install()

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
  RegionMap.previewDungeon = nil
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
  return nil
end

function RegionMap.currentDungeonSec()
  local dRow = RegionExtract.DUNGEON_GRID[RegionMap.cursorY]
  return dRow and dRow[RegionMap.cursorX] or nil
end

function RegionMap.currentDungeonName()
  local dSec = RegionMap.currentDungeonSec()
  if dSec and RegionExtract.SECTION_NAMES[dSec] then
    return RegionExtract.SECTION_NAMES[dSec]
  end
  return nil
end

function RegionMap.handleInput(input)
  local function se(id)
    pcall(function() require("src.core.game3.audio").playSe(id) end)
  end

  -- If Dungeon Map Preview guide is open, A/B/Start/Select closes it
  if RegionMap.previewDungeon then
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("select") then
      se(5)
      RegionMap.previewDungeon = nil
    end
    return
  end

  -- Close on B or SELECT
  if input:wasPressed("b") or input:wasPressed("select") then
    se(9)
    RegionMap.close()
    return
  end

  -- START cycles snapping to Player Icon -> Cancel Button -> Switch Button
  if input:wasPressed("start") then
    RegionMap._snapIndex = (RegionMap._snapIndex + 1) % 2
    if RegionMap._snapIndex == 0 then
      RegionMap.cursorX = RegionMap.playerX
      RegionMap.cursorY = RegionMap.playerY
    else
      RegionMap.cursorX = CANCEL_BUTTON_X
      RegionMap.cursorY = CANCEL_BUTTON_Y
    end
    se(5)
    return
  end

  -- A button action
  if input:wasPressed("a") then
    if RegionMap.cursorX == CANCEL_BUTTON_X and RegionMap.cursorY == CANCEL_BUTTON_Y then
      se(9)
      RegionMap.close()
      return
    elseif RegionMap.cursorX == SWITCH_BUTTON_X and RegionMap.cursorY == SWITCH_BUTTON_Y then
      se(5)
      return
    else
      local dSec = RegionMap.currentDungeonSec()
      if dSec then
        se(5)
        RegionMap.previewDungeon = dSec
        return
      end
    end
  end

  local prevX, prevY = RegionMap.cursorX, RegionMap.cursorY
  if input:wasPressed("left") then
    if RegionMap.cursorX > 0 then
      RegionMap.cursorX = RegionMap.cursorX - 1
    end
  elseif input:wasPressed("right") then
    if RegionMap.cursorX < RegionExtract.MAP_WIDTH - 1 then
      RegionMap.cursorX = RegionMap.cursorX + 1
    end
  elseif input:wasPressed("up") then
    if RegionMap.cursorY > 0 then
      RegionMap.cursorY = RegionMap.cursorY - 1
    end
  elseif input:wasPressed("down") then
    if RegionMap.cursorY < RegionExtract.MAP_HEIGHT - 1 then
      RegionMap.cursorY = RegionMap.cursorY + 1
    end
  end

  if RegionMap.cursorX ~= prevX or RegionMap.cursorY ~= prevY then
    if (RegionMap.cursorX == CANCEL_BUTTON_X and RegionMap.cursorY == CANCEL_BUTTON_Y)
       or (RegionMap.cursorX == SWITCH_BUTTON_X and RegionMap.cursorY == SWITCH_BUTTON_Y) then
      se(11) -- SE_M_SPIT_UP
    elseif RegionMap.currentLocationName() or RegionMap.currentDungeonName() then
      se(5) -- SE_DEX_SCROLL
    end
  end
end

function RegionMap.draw()
  if not RegionMap.open then return end
  if not (love and love.graphics) then return end

  -- 1. Base Sea Backdrop (#5888A8 / authentic blue)
  love.graphics.setColor(0.35, 0.53, 0.66, 1.0)
  love.graphics.rectangle("fill", 0, 0, Display.W, Display.H)
  love.graphics.setColor(1, 1, 1, 1)

  -- 2. Kanto Map Backdrop (full 240x160 scroll)
  local mapImg = get_map_image()
  if mapImg then
    love.graphics.draw(mapImg, 0, 0)
  else
    -- Procedural Kanto Geography & Route network fallback
    love.graphics.setColor(0.55, 0.78, 0.45, 1.0) -- Land green
    love.graphics.rectangle("fill", MAP_OFFSET_X, MAP_OFFSET_Y, RegionExtract.MAP_WIDTH * CELL_SIZE, RegionExtract.MAP_HEIGHT * CELL_SIZE)

    for y = 0, RegionExtract.MAP_HEIGHT - 1 do
      local row = RegionExtract.KANTO_GRID[y]
      if row then
        for x = 0, RegionExtract.MAP_WIDTH - 1 do
          local sec = row[x]
          if sec then
            local px = MAP_OFFSET_X + x * CELL_SIZE
            local py = MAP_OFFSET_Y + y * CELL_SIZE
            if sec:find("CITY", 1, true) or sec:find("TOWN", 1, true) or sec:find("PLATEAU", 1, true) then
              love.graphics.setColor(0.85, 0.20, 0.20, 1.0)
              love.graphics.rectangle("fill", px + 1, py + 1, 6, 6)
              love.graphics.setColor(0.2, 0.2, 0.2, 1.0)
              love.graphics.rectangle("line", px + 1, py + 1, 6, 6)
            elseif sec:find("ROUTE", 1, true) then
              love.graphics.setColor(0.70, 0.65, 0.50, 1.0)
              love.graphics.rectangle("fill", px + 2, py + 2, 4, 4)
            else
              love.graphics.setColor(0.40, 0.35, 0.30, 1.0)
              love.graphics.rectangle("fill", px + 2, py + 2, 4, 4)
            end
          end
        end
      end
    end
  end

  -- 2.5. Dungeon Markers (8x8 icons for Viridian Forest, Mt Moon, Diglett's Cave, etc.)
  local dungeonIcon = get_dungeon_icon_image()
  for y, dRow in pairs(RegionExtract.DUNGEON_GRID) do
    for x, dSec in pairs(dRow) do
      local offset = 0
      local row = RegionExtract.KANTO_GRID[y]
      local oSec = row and row[x]
      if oSec and (oSec:find("CITY", 1, true) or oSec:find("TOWN", 1, true)) then
        offset = 2
      end
      local dx = 32 + x * CELL_SIZE + offset
      local dy = 32 + y * CELL_SIZE + offset
      if dungeonIcon then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(dungeonIcon, dx, dy)
      else
        love.graphics.setColor(0.35, 0.70, 0.90, 1.0)
        love.graphics.rectangle("fill", dx + 1, dy + 1, 6, 6)
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
    love.graphics.draw(playerImg, pPx, pPy)
  else
    -- Fallback Head icon
    love.graphics.setColor(female and 0.9 or 0.2, 0.2, female and 0.4 or 0.9, 1)
    love.graphics.circle("fill", pPx + 8, pPy + 8, 5)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.circle("line", pPx + 8, pPy + 8, 5)
  end

  -- 4. Target Selection Cursor
  local cursorImg = get_cursor_image()
  local cPx = MAP_OFFSET_X + RegionMap.cursorX * CELL_SIZE
  local cPy = MAP_OFFSET_Y + RegionMap.cursorY * CELL_SIZE
  if cursorImg then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(cursorImg, cPx, cPy)
  else
    -- Fallback cursor box
    love.graphics.setColor(1, 0.1, 0.1, 1)
    love.graphics.rectangle("line", cPx + 3, cPy + 3, 10, 10)
    love.graphics.setColor(1, 1, 1, 1)
  end

  -- 5. Location Name (WIN_MAP_NAME: 1:1 FRLG position x=26, y=18, white text + dark gray shadow)
  local locName = RegionMap.currentLocationName()
  if locName then
    FrlgFont.draw(locName, 26, 18, { colors = FrlgFont.COLOR.WHITE })
  end

  -- 6. Dungeon Name (WIN_DUNGEON_NAME: 1:1 FRLG position x=36, y=34, light green text + dark gray shadow)
  local dName = RegionMap.currentDungeonName()
  if dName then
    FrlgFont.draw(dName, 36, 34, {
      colors = {
        fg = FrlgFont.STDPAL[7],     -- LIGHT_GREEN
        shadow = FrlgFont.STDPAL[2], -- DARK_GRAY
        bg = FrlgFont.STDPAL[0],     -- TRANSPARENT
      }
    })
  end

  -- 7. Top Bar Button Prompts with authentic keypad icons (WIN_TOPBAR_LEFT at x=144, WIN_TOPBAR_RIGHT at x=192, y=2)
  PokedexChrome.drawControlInfoLeft("{DPAD_ANY}MOVE", 144, 2)
  if RegionMap.previewDungeon then
    PokedexChrome.drawControlInfoLeft("{A_BUTTON}CANCEL", 192, 2)
  elseif RegionMap.cursorX == CANCEL_BUTTON_X and RegionMap.cursorY == CANCEL_BUTTON_Y then
    PokedexChrome.drawControlInfoLeft("{A_BUTTON}CANCEL", 192, 2)
  elseif RegionMap.cursorX == SWITCH_BUTTON_X and RegionMap.cursorY == SWITCH_BUTTON_Y then
    PokedexChrome.drawControlInfoLeft("{A_BUTTON}SWITCH", 192, 2)
  elseif RegionMap.currentDungeonName() then
    PokedexChrome.drawControlInfoLeft("{A_BUTTON}GUIDE", 192, 2)
  end

  -- 8. Dungeon Map Preview / Guide Modal (WIN_MAP_PREVIEW)
  if RegionMap.previewDungeon then
    local dSec = RegionMap.previewDungeon
    local dTitle = RegionExtract.SECTION_NAMES[dSec] or "DUNGEON"
    local dDesc = RegionExtract.DUNGEON_DESCRIPTIONS[dSec] or "No data available."

    -- Translucent darkened card overlay
    love.graphics.setColor(0.06, 0.10, 0.14, 0.90)
    love.graphics.rectangle("fill", 20, 24, 200, 116, 4, 4)
    love.graphics.setColor(0.55, 0.70, 0.60, 1.0)
    love.graphics.rectangle("line", 20, 24, 200, 116, 4, 4)
    love.graphics.setColor(1, 1, 1, 1)

    -- Dungeon Title (Light Green)
    FrlgFont.draw(dTitle, 26, 28, {
      colors = {
        fg = FrlgFont.STDPAL[7],     -- LIGHT_GREEN
        shadow = FrlgFont.STDPAL[2], -- DARK_GRAY
        bg = FrlgFont.STDPAL[0],     -- TRANSPARENT
      }
    })

    -- Dungeon Description (White, word-wrapped)
    local wrappedDesc = FrlgFont.wrap(dDesc, 188)
    FrlgFont.draw(wrappedDesc, 26, 46, {
      maxWidth = 188,
      linePitch = 14,
      colors = FrlgFont.COLOR.WHITE,
    })
  end
end

return RegionMap
