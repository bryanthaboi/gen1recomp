local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Display = require("src.core.game3.display")
local FrlgFont = require("src.ui.game3.frlg_font")
local PokedexChrome = require("src.ui.game3.pokedex_chrome")
local RegionExtract = require("src.import.gba.region_map_extract")
local MapSectionsExtract = require("src.import.gba.map_sections_extract")
local Strings = require("src.core.Strings")

local RegionMap = {}

RegionMap.open = false
RegionMap.cursorX = 4
RegionMap.cursorY = 11
RegionMap.playerX = 4
RegionMap.playerY = 11
RegionMap.playerGender = 0 -- 0: Red (male), 1: Leaf (female)
RegionMap.previewDungeon = nil
RegionMap.previewFrame = 0
RegionMap._snapIndex = 0
RegionMap._images = {}
RegionMap._session = nil
RegionMap._onClose = nil
RegionMap.mode = "normal"
RegionMap._onPick = nil
RegionMap._animFrame = 0

local MAP_OFFSET_X = 28
local MAP_OFFSET_Y = 28
local CELL_SIZE = 8

local CANCEL_BUTTON_X = 21
local CANCEL_BUTTON_Y = 13
local SWITCH_BUTTON_X = 21
local SWITCH_BUTTON_Y = 11

-- pokefirered/src/region_map.c:595-617
local PERMISSIONS = {
  normal = { switchButton = true, mapPreview = true, openAnim = true, flyDestinations = false },
  wall = { switchButton = false, mapPreview = false, openAnim = false, flyDestinations = false },
  fly = { switchButton = false, mapPreview = false, openAnim = false, flyDestinations = true },
}

-- pokefirered/src/region_map.c:37-43
RegionMap.MAPSECTYPE = {
  NONE = 0,
  ROUTE = 1,
  VISITED = 2,
  NOT_VISITED = 3,
  UNKNOWN = 4,
}
local SECTYPE = RegionMap.MAPSECTYPE

-- pokefirered/src/region_map.c:2952
local MAP_LAYER_FLAGS = {
  MAPSEC_PALLET_TOWN = "FLAG_WORLD_MAP_PALLET_TOWN",
  MAPSEC_VIRIDIAN_CITY = "FLAG_WORLD_MAP_VIRIDIAN_CITY",
  MAPSEC_PEWTER_CITY = "FLAG_WORLD_MAP_PEWTER_CITY",
  MAPSEC_CERULEAN_CITY = "FLAG_WORLD_MAP_CERULEAN_CITY",
  MAPSEC_LAVENDER_TOWN = "FLAG_WORLD_MAP_LAVENDER_TOWN",
  MAPSEC_VERMILION_CITY = "FLAG_WORLD_MAP_VERMILION_CITY",
  MAPSEC_CELADON_CITY = "FLAG_WORLD_MAP_CELADON_CITY",
  MAPSEC_FUCHSIA_CITY = "FLAG_WORLD_MAP_FUCHSIA_CITY",
  MAPSEC_CINNABAR_ISLAND = "FLAG_WORLD_MAP_CINNABAR_ISLAND",
  MAPSEC_INDIGO_PLATEAU = "FLAG_WORLD_MAP_INDIGO_PLATEAU_EXTERIOR",
  MAPSEC_SAFFRON_CITY = "FLAG_WORLD_MAP_SAFFRON_CITY",
  MAPSEC_ONE_ISLAND = "FLAG_WORLD_MAP_ONE_ISLAND",
  MAPSEC_TWO_ISLAND = "FLAG_WORLD_MAP_TWO_ISLAND",
  MAPSEC_THREE_ISLAND = "FLAG_WORLD_MAP_THREE_ISLAND",
  MAPSEC_FOUR_ISLAND = "FLAG_WORLD_MAP_FOUR_ISLAND",
  MAPSEC_FIVE_ISLAND = "FLAG_WORLD_MAP_FIVE_ISLAND",
  MAPSEC_SEVEN_ISLAND = "FLAG_WORLD_MAP_SEVEN_ISLAND",
  MAPSEC_SIX_ISLAND = "FLAG_WORLD_MAP_SIX_ISLAND",
  MAPSEC_ROUTE_4_POKECENTER = "FLAG_WORLD_MAP_ROUTE4_POKEMON_CENTER_1F",
  MAPSEC_ROUTE_10_POKECENTER = "FLAG_WORLD_MAP_ROUTE10_POKEMON_CENTER_1F",
}

-- pokefirered/src/region_map.c:3005
local DUNGEON_LAYER_FLAGS = {
  MAPSEC_VIRIDIAN_FOREST = "FLAG_WORLD_MAP_VIRIDIAN_FOREST",
  MAPSEC_MT_MOON = "FLAG_WORLD_MAP_MT_MOON_1F",
  MAPSEC_S_S_ANNE = "FLAG_WORLD_MAP_SSANNE_EXTERIOR",
  MAPSEC_UNDERGROUND_PATH = "FLAG_WORLD_MAP_UNDERGROUND_PATH_NORTH_SOUTH_TUNNEL",
  MAPSEC_UNDERGROUND_PATH_2 = "FLAG_WORLD_MAP_UNDERGROUND_PATH_EAST_WEST_TUNNEL",
  MAPSEC_DIGLETTS_CAVE = "FLAG_WORLD_MAP_DIGLETTS_CAVE_B1F",
  MAPSEC_KANTO_VICTORY_ROAD = "FLAG_WORLD_MAP_VICTORY_ROAD_1F",
  MAPSEC_ROCKET_HIDEOUT = "FLAG_WORLD_MAP_ROCKET_HIDEOUT_B1F",
  MAPSEC_SILPH_CO = "FLAG_WORLD_MAP_SILPH_CO_1F",
  MAPSEC_POKEMON_MANSION = "FLAG_WORLD_MAP_POKEMON_MANSION_1F",
  MAPSEC_KANTO_SAFARI_ZONE = "FLAG_WORLD_MAP_SAFARI_ZONE_CENTER",
  MAPSEC_POKEMON_LEAGUE = "FLAG_WORLD_MAP_POKEMON_LEAGUE_LORELEIS_ROOM",
  MAPSEC_ROCK_TUNNEL = "FLAG_WORLD_MAP_ROCK_TUNNEL_1F",
  MAPSEC_SEAFOAM_ISLANDS = "FLAG_WORLD_MAP_SEAFOAM_ISLANDS_1F",
  MAPSEC_POKEMON_TOWER = "FLAG_WORLD_MAP_POKEMON_TOWER_1F",
  MAPSEC_CERULEAN_CAVE = "FLAG_WORLD_MAP_CERULEAN_CAVE_1F",
  MAPSEC_POWER_PLANT = "FLAG_WORLD_MAP_POWER_PLANT",
  MAPSEC_NAVEL_ROCK = "FLAG_WORLD_MAP_NAVEL_ROCK_EXTERIOR",
  MAPSEC_MT_EMBER = "FLAG_WORLD_MAP_MT_EMBER_EXTERIOR",
  MAPSEC_BERRY_FOREST = "FLAG_WORLD_MAP_THREE_ISLAND_BERRY_FOREST",
  MAPSEC_ICEFALL_CAVE = "FLAG_WORLD_MAP_FOUR_ISLAND_ICEFALL_CAVE_ENTRANCE",
  MAPSEC_ROCKET_WAREHOUSE = "FLAG_WORLD_MAP_FIVE_ISLAND_ROCKET_WAREHOUSE",
  MAPSEC_TRAINER_TOWER_2 = "FLAG_WORLD_MAP_TRAINER_TOWER_LOBBY",
  MAPSEC_DOTTED_HOLE = "FLAG_WORLD_MAP_SIX_ISLAND_DOTTED_HOLE_1F",
  MAPSEC_LOST_CAVE = "FLAG_WORLD_MAP_FIVE_ISLAND_LOST_CAVE_ENTRANCE",
  MAPSEC_PATTERN_BUSH = "FLAG_WORLD_MAP_SIX_ISLAND_PATTERN_BUSH",
  MAPSEC_ALTERING_CAVE = "FLAG_WORLD_MAP_SIX_ISLAND_ALTERING_CAVE",
  MAPSEC_TANOBY_CHAMBERS = "FLAG_WORLD_MAP_SEVEN_ISLAND_TANOBY_RUINS_MONEAN_CHAMBER",
  MAPSEC_THREE_ISLE_PATH = "FLAG_WORLD_MAP_THREE_ISLAND_DUNSPARCE_TUNNEL",
  MAPSEC_TANOBY_KEY = "FLAG_WORLD_MAP_SEVEN_ISLAND_SEVAULT_CANYON_TANOBY_KEY",
  MAPSEC_BIRTH_ISLAND = "FLAG_WORLD_MAP_BIRTH_ISLAND_EXTERIOR",
}

-- pokefirered/include/constants/songs.h:5,106,245
local SE_USE_ITEM = 1
local SE_DEX_PAGE = 102
local SE_M_HYPER_BEAM2 = 240

-- pokefirered/src/region_map.c:784-787
local FLY_ICON_FRAME0_TICKS = 30
local FLY_ICON_CYCLE_TICKS = 90

-- Dungeon Map Preview (GUIDE) geometry.  pret src/region_map.c:1941-2200.
-- The baked artwork lives on BG2 and is revealed through hardware window 1, which
-- grows from the cursor's map cell to (16, 32)-(224, 136) over 8 steps.  BG0 (the
-- region map itself) is hidden for the duration, and the name/flavour text sits on
-- BG3 in WIN_MAP_PREVIEW, a 25x11 tile window at (24, 48).
local PREVIEW_STEPS = 8
local PREVIEW_LEFT, PREVIEW_TOP = 16, 32
local PREVIEW_RIGHT, PREVIEW_BOTTOM = 224, 136
local PREVIEW_TEXT_X, PREVIEW_TEXT_Y = 24, 48
local PREVIEW_TEXT_W, PREVIEW_TEXT_H = 200, 88
local PREVIEW_NAME_DX, PREVIEW_NAME_DY = 4, 0
local PREVIEW_DESC_DX, PREVIEW_DESC_DY = 2, 14
local PREVIEW_LINE_PITCH = 16
-- TintPalette_CustomTone ramp: start at 0x0133/0x0100/0x00F0 and step down
-- -6/-5/-5 once per frame for 5 frames, then the text appears.
local PREVIEW_TONE_R, PREVIEW_TONE_G, PREVIEW_TONE_B = 0x0133, 0x0100, 0x00F0
local PREVIEW_FILL_DELAY = 42
local PREVIEW_TINT_FIRST = 63
local PREVIEW_TINT_STEPS = 5
local PREVIEW_TEXT_DELAY = 69

-- region_map.c:1945-1950: TANOBY CHAMBERS shows MONEAN CHAMBER's artwork, and any
-- mapsec with no preview entry falls back to ROCK TUNNEL's artwork.
local TANOBY_CHAMBERS_SEC = MapSectionsExtract.ID_TO_SECTION["MAPSEC_TANOBY_CHAMBERS"]
local MONEAN_CHAMBER_SEC = MapSectionsExtract.ID_TO_SECTION["MAPSEC_MONEAN_CHAMBER"]
local ROCK_TUNNEL_SEC = MapSectionsExtract.ID_TO_SECTION["MAPSEC_ROCK_TUNNEL"]

local function previewModule()
  local ok, mod = pcall(require, "src.ui.game3.map_preview_screen")
  if ok and mod then return mod end
  return nil
end

--- Frames elapsed since the preview window finished expanding; the flavour-text
--- task (and its tint ramp) only starts once UpdateDungeonMapPreview returns TRUE.
local function previewTextFrame()
  return (RegionMap.previewFrame or 0) - PREVIEW_STEPS
end

--- The hardware-window rect for the current animation step.
local function previewWindowRect()
  local step = math.min(RegionMap.previewFrame or 0, PREVIEW_STEPS) / PREVIEW_STEPS
  local left = MAP_OFFSET_X + RegionMap.cursorX * CELL_SIZE
  local top = MAP_OFFSET_Y + RegionMap.cursorY * CELL_SIZE
  local right, bottom = left + CELL_SIZE, top + CELL_SIZE
  return left + (PREVIEW_LEFT - left) * step,
         top + (PREVIEW_TOP - top) * step,
         right + (PREVIEW_RIGHT - right) * step,
         bottom + (PREVIEW_BOTTOM - bottom) * step
end

--- Per-channel multipliers for TintPalette_CustomTone at the current frame.
local function previewTone()
  local n = math.max(0, math.min(previewTextFrame() - PREVIEW_TINT_FIRST, PREVIEW_TINT_STEPS))
  return (PREVIEW_TONE_R - 6 * n) / 256,
         (PREVIEW_TONE_G - 5 * n) / 256,
         (PREVIEW_TONE_B - 5 * n) / 256
end

--- Numeric mapsec whose baked artwork the GUIDE should show, or nil when the
--- extractor output is unavailable (the panel then renders text only).
local function guideArtworkSec(dSec)
  if not dSec then return nil end
  local mod = previewModule()
  if not mod or not mod.ready() then return nil end
  local secId = MapSectionsExtract.ID_TO_SECTION[dSec]
  if secId then
    if secId == TANOBY_CHAMBERS_SEC then secId = MONEAN_CHAMBER_SEC end
    if mod.entryFor(secId) then return secId end
  end
  return ROCK_TUNNEL_SEC
end

local function read_cache_file(rel)
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if okD and Dataset and Dataset.cache then
    local d = Dataset.cache():read(rel)
    if type(d) == "string" and #d > 0 then return d end
  end
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if ok and CacheFs then
    if CacheFs.readActive then
      local d = CacheFs.readActive(rel)
      if type(d) == "string" and #d > 0 then return d end
    end
    if CacheFs.read then
      local d = CacheFs.read(rel)
      if type(d) == "string" and #d > 0 then return d end
    end
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

local function rgba_to_image(rgba, w, h)
  if not (love and love.image and love.graphics) then return nil end
  if not rgba or #rgba < w * h * 4 then return nil end

  local ok, imgData = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if ok and imgData then
    local okImg, img = pcall(love.graphics.newImage, imgData)
    if okImg and img then
      if img.setFilter then img:setFilter("nearest", "nearest") end
      return img
    end
  end

  local ok2, id = pcall(love.image.newImageData, w, h)
  if ok2 and id then
    local i = 1
    for y = 0, h - 1 do
      for x = 0, w - 1 do
        local r = (rgba:byte(i) or 0) / 255
        local g = (rgba:byte(i + 1) or 0) / 255
        local b = (rgba:byte(i + 2) or 0) / 255
        local a = (rgba:byte(i + 3) or 0) / 255
        id:setPixel(x, y, r, g, b, a)
        i = i + 4
      end
    end
    local okImg, img = pcall(love.graphics.newImage, id)
    if okImg and img then
      if img.setFilter then img:setFilter("nearest", "nearest") end
      return img
    end
  end
  return nil
end

local function try_load_image(paths, w, h)
  if not (love and love.graphics) then return nil end
  if type(paths) == "string" then paths = { paths } end
  for _, p in ipairs(paths) do
    if p:sub(-5) == ".rgba" and w and h then
      local raw = read_cache_file(p)
      if raw then
        local img = rgba_to_image(raw, w, h)
        if img then return img end
      end
    else
      local bytes = read_cache_file(p)
      if bytes and #bytes > 0 and love.filesystem and love.image then
        local ok, img = pcall(function()
          local fd = love.filesystem.newFileData(bytes, p:match("[^/]+$") or "img.png")
          local id = love.image.newImageData(fd)
          local image = love.graphics.newImage(id)
          if image and image.setFilter then image:setFilter("nearest", "nearest") end
          return image
        end)
        if ok and img then return img end
      end
      if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(p) then
        local ok, img = pcall(love.graphics.newImage, p)
        if ok and img then
          if img.setFilter then img:setFilter("nearest", "nearest") end
          return img
        end
      end
    end
  end
  return nil
end

local function get_map_image()
  if RegionMap._images["kanto_map"] ~= nil then
    return RegionMap._images["kanto_map"] or nil
  end
  local candidates = {
    "region_map/kanto_map.rgba",
    "data/generated/gba/region_map/kanto_map.rgba",
    "region_map/kanto_map.png",
    "data/generated/gba/region_map/kanto_map.png",
  }
  local img = try_load_image(candidates, 240, 160)
  RegionMap._images["kanto_map"] = img or false
  return img
end

local function get_cursor_image()
  if RegionMap._images["cursor"] ~= nil then
    return RegionMap._images["cursor"] or nil
  end
  local candidates = {
    "region_map/cursor.rgba",
    "data/generated/gba/region_map/cursor.rgba",
    "region_map/cursor.png",
    "data/generated/gba/region_map/cursor.png",
  }
  local img = try_load_image(candidates, 16, 16)
  RegionMap._images["cursor"] = img or false
  return img
end

local function get_dungeon_icon_image()
  if RegionMap._images["dungeon_icon"] ~= nil then
    return RegionMap._images["dungeon_icon"] or nil
  end
  local candidates = {
    "region_map/dungeon_icon.rgba",
    "data/generated/gba/region_map/dungeon_icon.rgba",
    "region_map/dungeon_icon.png",
    "data/generated/gba/region_map/dungeon_icon.png",
  }
  local img = try_load_image(candidates, 8, 8)
  RegionMap._images["dungeon_icon"] = img or false
  return img
end

-- pokefirered/src/region_map.c:3597-3601, :790-793
local function get_dungeon_icon_visited_image()
  if RegionMap._images["dungeon_icon_visited"] ~= nil then
    return RegionMap._images["dungeon_icon_visited"] or nil
  end
  local img = try_load_image("data/generated/gba/region_map/dungeon_icon_visited.png")
  RegionMap._images["dungeon_icon_visited"] = img or false
  return img
end

-- pokefirered/src/region_map.c:425
local function get_fly_icon_image()
  if RegionMap._images["fly_icon"] ~= nil then
    return RegionMap._images["fly_icon"] or nil
  end
  local img = try_load_image("data/generated/gba/region_map/fly_icon.png")
  RegionMap._images["fly_icon"] = img or false
  if img and love and love.graphics and love.graphics.newQuad then
    local quads = {}
    for frame = 0, 1 do
      local ok, q = pcall(love.graphics.newQuad, 0, frame * 16, 16, 16,
                          img:getWidth(), img:getHeight())
      if ok then quads[frame] = q end
    end
    RegionMap._flyQuads = quads
  end
  return img
end

-- pokefirered/src/region_map.c:2952
function RegionMap.isFlagSet(flagName)
  local Flags = package.loaded["src.core.game3.scripting.flags"]
  if not Flags then
    local ok, mod = pcall(require, "src.core.game3.scripting.flags")
    Flags = ok and mod or nil
  end
  local id = tonumber(flagName) or (Flags and Flags.IDS and Flags.IDS[flagName])
  if not id then return false end
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = Space and Space.store
  if store and Flags and Flags.getFlag then
    local ok, val = pcall(Flags.getFlag, store, nil, id)
    if ok and val == true then return true end
  end
  local session = RegionMap._session
  if not session then
    local Runtime = package.loaded["src.core.game3.runtime"]
    session = Runtime and Runtime.getSession and Runtime.getSession()
  end
  if session and session.flags then
    if session.flags[id] or session.flags[flagName] then return true end
  end
  return false
end

-- pokefirered/src/region_map.c:1024-1029
function RegionMap.permission(name)
  local perms = PERMISSIONS[RegionMap.mode] or PERMISSIONS.normal
  if name == "switchButton" and not RegionMap.isFlagSet("FLAG_SYS_SEVII_MAP_123") then
    return false
  end
  return perms[name] == true
end

-- pokefirered/src/region_map.c:595-617
function RegionMap.hasFlyDestinations()
  return RegionMap.permission("flyDestinations")
end

function RegionMap.hasSwitchButton()
  return RegionMap.permission("switchButton")
end

function RegionMap.playerOnSelectedMap()
  return RegionMap.playerX ~= nil and RegionMap.playerY ~= nil
end

function RegionMap.hasMapPreview()
  return RegionMap.permission("mapPreview")
end

function RegionMap.isFlyMode()
  return RegionMap.mode == "fly"
end

-- pokefirered/src/region_map.c:2952
function RegionMap.mapsecType(sec)
  if sec == nil then return SECTYPE.NONE end
  if sec == "MAPSEC_ROUTE_4_POKECENTER" and not RegionMap.hasFlyDestinations() then
    return SECTYPE.NONE
  end
  local flag = MAP_LAYER_FLAGS[sec]
  if flag then
    return RegionMap.isFlagSet(flag) and SECTYPE.VISITED or SECTYPE.NOT_VISITED
  end
  return SECTYPE.ROUTE
end

-- pokefirered/src/region_map.c:3005
function RegionMap.dungeonMapsecType(sec)
  if sec == nil then return SECTYPE.NONE end
  local flag = DUNGEON_LAYER_FLAGS[sec]
  if flag then
    return RegionMap.isFlagSet(flag) and SECTYPE.VISITED or SECTYPE.NOT_VISITED
  end
  return SECTYPE.ROUTE
end

function RegionMap.currentMapSec()
  local row = RegionExtract.KANTO_GRID[RegionMap.cursorY]
  return row and row[RegionMap.cursorX] or nil
end

function RegionMap.selectedMapsecType()
  return RegionMap.mapsecType(RegionMap.currentMapSec())
end

-- pokefirered/src/region_map.c:3956
function RegionMap.canFlyToCursor()
  if not RegionMap.hasFlyDestinations() then return false end
  local t = RegionMap.selectedMapsecType()
  return t == SECTYPE.VISITED or t == SECTYPE.UNKNOWN
end

local function get_player_image(female)
  local key = female and "player_leaf" or "player_red"
  if RegionMap._images[key] ~= nil then
    return RegionMap._images[key] or nil
  end
  local candidates = {
    "region_map/" .. key .. ".rgba",
    "data/generated/gba/region_map/" .. key .. ".rgba",
    "region_map/" .. key .. ".png",
    "data/generated/gba/region_map/" .. key .. ".png",
  }
  local img = try_load_image(candidates, 16, 16)
  RegionMap._images[key] = img or false
  return img
end

function RegionMap.show(opts)
  opts = opts or {}
  RegionMap.open = true
  RegionMap.previewDungeon = nil
  RegionMap.previewFrame = 0
  RegionMap._snapIndex = 0
  if RegionMap._images["kanto_map"] == false then RegionMap._images["kanto_map"] = nil end
  RegionMap._session = opts.session
  RegionMap._onClose = opts.onClose
  -- pokefirered/src/item_use.c:666, src/field_specials.c:185
  RegionMap.mode = PERMISSIONS[opts.mode] and opts.mode or "normal"
  RegionMap._onPick = opts.onPick
  RegionMap._animFrame = 0
  RegionMap._mapType = opts.mapType

  -- pokefirered/src/region_map.c:3558, :3583
  RegionMap._flyTargets = nil
  RegionMap._dungeonIcons = nil
  RegionMap._flyTargets = RegionMap.flyTargets()
  RegionMap._dungeonIcons = RegionMap.dungeonIcons()

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

-- pokefirered/src/region_map.c:4016-4019
function RegionMap.close(picked)
  local wasFly = RegionMap.mode == "fly"
  RegionMap.open = false
  RegionMap.previewDungeon = nil
  RegionMap.previewFrame = 0
  RegionMap.mode = "normal"
  RegionMap._flyTargets = nil
  RegionMap._dungeonIcons = nil
  Stack.pop("region_map")
  local cb = RegionMap._onClose
  RegionMap._onClose = nil
  RegionMap._onPick = nil
  if cb and not picked then cb(nil) end
  if wasFly and not picked then
    local PartyMenu = package.loaded["src.ui.game3.party_menu"]
    if PartyMenu and PartyMenu.returnFromFlyMap then
      pcall(PartyMenu.returnFromFlyMap)
    end
  end
end

function RegionMap.isOpen()
  return RegionMap.open
end

function RegionMap.currentLocationName()
  RegionExtract.ensureGenerated()
  local row = RegionExtract.KANTO_GRID[RegionMap.cursorY]
  local sec = row and row[RegionMap.cursorX]
  if sec and RegionExtract.SECTION_NAMES[sec] then
    return Strings(RegionExtract.SECTION_NAMES[sec])
  end
  return nil
end

-- pokefirered/src/region_map.c:2946
function RegionMap.dungeonSecAt(x, y)
  local dRow = RegionExtract.DUNGEON_GRID[y]
  local sec = dRow and dRow[x] or nil
  if sec == "MAPSEC_CERULEAN_CAVE" and not RegionMap.isFlagSet("FLAG_SYS_CAN_LINK_WITH_RS") then
    return nil
  end
  return sec
end

function RegionMap.currentDungeonSec()
  return RegionMap.dungeonSecAt(RegionMap.cursorX, RegionMap.cursorY)
end

-- pokefirered/src/region_map.c:2700, :3087
function RegionMap.selectedDungeonMapsecType()
  RegionExtract.ensureGenerated()
  local dRow = RegionExtract.DUNGEON_GRID[RegionMap.cursorY]
  return RegionMap.dungeonMapsecType(dRow and dRow[RegionMap.cursorX] or nil)
end

-- pokefirered/src/region_map.c:1266
function RegionMap.canGuideCursor()
  if not RegionMap.hasMapPreview() then return false end
  return RegionMap.selectedDungeonMapsecType() == SECTYPE.VISITED
end

-- pokefirered/src/region_map.c:3597-3601, :790-797, :804-807
function RegionMap.dungeonIconFrame(dSec)
  return RegionMap.dungeonMapsecType(dSec) == SECTYPE.VISITED and 1 or 0
end

-- pokefirered/src/region_map.c:3549
function RegionMap.dungeonIconOffset(x, y)
  local row = RegionExtract.KANTO_GRID[y]
  local oSec = row and row[x]
  local oType = RegionMap.mapsecType(oSec)
  if (oType == SECTYPE.VISITED or oType == SECTYPE.NOT_VISITED)
     and oSec ~= "MAPSEC_ROUTE_10_POKECENTER" then
    return 2
  end
  return 0
end

-- pokefirered/src/region_map.c:3558
local function computeFlyTargets()
  local out = {}
  if not RegionMap.hasFlyDestinations() then return out end
  RegionExtract.ensureGenerated()
  for y = 0, RegionExtract.MAP_HEIGHT - 1 do
    local row = RegionExtract.KANTO_GRID[y]
    if row then
      for x = 0, RegionExtract.MAP_WIDTH - 1 do
        local sec = row[x]
        if RegionMap.mapsecType(sec) == SECTYPE.VISITED then
          out[#out + 1] = { x = x, y = y, sec = sec }
        end
      end
    end
  end
  return out
end

function RegionMap.flyTargets()
  return RegionMap._flyTargets or computeFlyTargets()
end

-- pokefirered/src/region_map.c:3583
local function computeDungeonIcons()
  local out = {}
  RegionExtract.ensureGenerated()
  for y, dRow in pairs(RegionExtract.DUNGEON_GRID) do
    for x in pairs(dRow) do
      local dSec = RegionMap.dungeonSecAt(x, y)
      if dSec then
        local offset = RegionMap.dungeonIconOffset(x, y)
        out[#out + 1] = {
          -- pokefirered/src/region_map.c:3551
          px = 32 + x * CELL_SIZE + offset,
          py = 32 + y * CELL_SIZE + offset,
          frame = RegionMap.dungeonIconFrame(dSec),
        }
      end
    end
  end
  return out
end

function RegionMap.dungeonIcons()
  return RegionMap._dungeonIcons or computeDungeonIcons()
end

-- pokefirered/src/region_map.c:784-787
function RegionMap.flyIconFrame()
  local tick = (RegionMap._animFrame or 0) % FLY_ICON_CYCLE_TICKS
  return tick < FLY_ICON_FRAME0_TICKS and 0 or 1
end

function RegionMap.dungeonIconVisitedImage()
  return get_dungeon_icon_visited_image()
end

function RegionMap.currentDungeonName()
  RegionExtract.ensureGenerated()
  local dSec = RegionMap.currentDungeonSec()
  if dSec and RegionExtract.SECTION_NAMES[dSec] then
    return Strings(RegionExtract.SECTION_NAMES[dSec])
  end
  return nil
end

-- pokefirered/src/region_map.c:3958-3963, include/constants/map_types.h:8,12
function RegionMap.flyBlockedByMapType()
  local mapType = RegionMap._mapType
  if mapType == nil then
    local okM, Map = pcall(require, "src.core.game3.map")
    local def = okM and Map and Map.currentDef and Map.currentDef()
    mapType = def and def.mapType
  end
  mapType = tonumber(mapType)
  return mapType == 4 or mapType == 8
end

function RegionMap.handleInput(input)
  local function se(id)
    pcall(function() require("src.core.game3.audio").playSe(id) end)
  end

  RegionMap._animFrame = (RegionMap._animFrame or 0) + 1

  -- If Dungeon Map Preview guide is open, A/B/Start/Select closes it
  if RegionMap.previewDungeon then
    RegionMap.previewFrame = (RegionMap.previewFrame or 0) + 1
    if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("select") then
      se(5)
      RegionMap.previewDungeon = nil
      RegionMap.previewFrame = 0
    end
    return
  end

  -- Close on B or SELECT
  -- pokefirered/src/region_map.c:2819, :968
  if input:wasPressed("b")
     or (input:wasPressed("select") and not RegionMap.hasFlyDestinations()) then
    -- pokefirered/src/region_map.c:2826
    RegionMap.close()
    return
  end

  -- pokefirered/src/region_map.c:2862
  if input:wasPressed("start") then
    local snap
    if RegionMap.hasSwitchButton() then
      RegionMap._snapIndex = (RegionMap._snapIndex + 1) % 3
      if RegionMap._snapIndex == 0 and not RegionMap.playerOnSelectedMap() then
        RegionMap._snapIndex = 1
      end
      snap = ({ "player", "switch", "cancel" })[RegionMap._snapIndex + 1]
    else
      RegionMap._snapIndex = (RegionMap._snapIndex + 1) % 2
      snap = RegionMap._snapIndex == 1 and "cancel" or "player"
    end
    if snap == "switch" then
      RegionMap.cursorX = SWITCH_BUTTON_X
      RegionMap.cursorY = SWITCH_BUTTON_Y
    elseif snap == "cancel" then
      RegionMap.cursorX = CANCEL_BUTTON_X
      RegionMap.cursorY = CANCEL_BUTTON_Y
    else
      RegionMap.cursorX = RegionMap.playerX
      RegionMap.cursorY = RegionMap.playerY
    end
    se(5)
    return
  end

  -- A button action
  if input:wasPressed("a") then
    if RegionMap.cursorX == CANCEL_BUTTON_X and RegionMap.cursorY == CANCEL_BUTTON_Y then
      se(240) -- pokefirered/src/region_map.c:2798
      RegionMap.close()
      return
    elseif RegionMap.cursorX == SWITCH_BUTTON_X and RegionMap.cursorY == SWITCH_BUTTON_Y
           and RegionMap.hasSwitchButton() then
      se(240) -- pokefirered/src/region_map.c:2805
      return
    elseif RegionMap.hasFlyDestinations() then
      -- pokefirered/src/region_map.c:3956
      if RegionMap.canFlyToCursor() then
        local sec = RegionMap.currentMapSec()
        if RegionMap.flyBlockedByMapType() then
          RegionMap.close()
        else
          se(SE_USE_ITEM)
          local onPick = RegionMap._onPick
          local onClose = RegionMap._onClose
          RegionMap.close(true)
          local handled = false
          if onPick then
            handled = pcall(onPick, sec, MapSectionsExtract.ID_TO_SECTION[sec])
          end
          if not handled and onClose then pcall(onClose, nil) end
        end
      end
      return
    else
      -- pokefirered/src/region_map.c:1266
      local dSec = RegionMap.canGuideCursor() and RegionMap.currentDungeonSec() or nil
      if dSec then
        se(5)
        RegionMap.previewDungeon = dSec
        RegionMap.previewFrame = 0
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
    -- pokefirered/src/region_map.c:3932-3936
    if RegionMap.hasFlyDestinations()
       and RegionMap.selectedMapsecType() == SECTYPE.VISITED then
      se(SE_DEX_PAGE)
    elseif (RegionMap.cursorX == CANCEL_BUTTON_X and RegionMap.cursorY == CANCEL_BUTTON_Y)
       or (RegionMap.cursorX == SWITCH_BUTTON_X and RegionMap.cursorY == SWITCH_BUTTON_Y
           and RegionMap.hasSwitchButton()) then
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

  -- 2. Kanto Map Backdrop (full 240x160 scroll).  BG0 is hidden for the duration of
  -- the GUIDE preview (pret region_map.c:2129 SetDispCnt(1, FALSE)).
  local previewOpen = RegionMap.previewDungeon ~= nil
  local mapImg
  if not previewOpen then mapImg = get_map_image() end
  if mapImg then
    love.graphics.draw(mapImg, 0, 0)
  elseif not previewOpen then
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

  -- 2.2. GUIDE preview artwork.  pret copies the baked tilemap to BG2 and reveals it
  -- through hardware window 1, so only the growing window shows the artwork while the
  -- rest of the screen keeps BG1 (region_map.c:1984-2022, 2113-2186).
  if previewOpen then
    local artSec = guideArtworkSec(RegionMap.previewDungeon)
    local artImg = artSec and previewModule().image(artSec)
    if artImg then
      local left, top, right, bottom = previewWindowRect()
      local tr, tg, tb = previewTone()
      local sx, sy, sw, sh = love.graphics.getScissor()
      love.graphics.setScissor(math.floor(left), math.floor(top),
                               math.ceil(right) - math.floor(left),
                               math.ceil(bottom) - math.floor(top))
      love.graphics.setColor(tr, tg, tb, 1)
      love.graphics.draw(artImg, 0, 0)
      love.graphics.setColor(1, 1, 1, 1)
      if sx then love.graphics.setScissor(sx, sy, sw, sh) else love.graphics.setScissor() end
    end
  end

  -- 2.5. Dungeon Markers (8x8 icons for Viridian Forest, Mt Moon, Diglett's Cave, etc.)
  local dungeonIcon = get_dungeon_icon_image()
  local dungeonIconVisited = get_dungeon_icon_visited_image()
  for _, icon in ipairs(RegionMap.dungeonIcons()) do
    local img = (icon.frame == 1 and dungeonIconVisited) or dungeonIcon
    if img then
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, icon.px, icon.py)
    else
      love.graphics.setColor(0.35, 0.70, 0.90, 1.0)
      love.graphics.rectangle("fill", icon.px + 1, icon.py + 1, 6, 6)
    end
  end

  -- pokefirered/src/region_map.c:3558
  if RegionMap.hasFlyDestinations() then
    local flyIcon = get_fly_icon_image()
    local frame = RegionMap.flyIconFrame()
    local quad = flyIcon and RegionMap._flyQuads and RegionMap._flyQuads[frame] or nil
    for _, t in ipairs(RegionMap.flyTargets()) do
      local fx = MAP_OFFSET_X + t.x * CELL_SIZE
      local fy = MAP_OFFSET_Y + t.y * CELL_SIZE
      love.graphics.setColor(1, 1, 1, 1)
      if quad then
        love.graphics.draw(flyIcon, quad, fx, fy)
      elseif flyIcon then
        love.graphics.draw(flyIcon, fx, fy)
      else
        love.graphics.setColor(1, 0.85, 0.25, frame == 0 and 1.0 or 0.55)
        love.graphics.rectangle("line", fx + 0.5, fy + 0.5, 15, 15)
      end
      love.graphics.setColor(1, 1, 1, 1)
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
  PokedexChrome.drawControlInfoLeft(Strings("{DPAD_ANY}MOVE"), 144, 2)
  if RegionMap.previewDungeon then
    PokedexChrome.drawControlInfoLeft(Strings("{A_BUTTON}CANCEL"), 192, 2)
  elseif RegionMap.cursorX == CANCEL_BUTTON_X and RegionMap.cursorY == CANCEL_BUTTON_Y then
    PokedexChrome.drawControlInfoLeft(Strings("{A_BUTTON}CANCEL"), 192, 2)
  elseif RegionMap.hasFlyDestinations() then
    -- pokefirered/src/region_map.c:3946-3953
    if RegionMap.canFlyToCursor() then
      PokedexChrome.drawControlInfoLeft(Strings("{A_BUTTON}OK"), 192, 2)
    end
  elseif RegionMap.cursorX == SWITCH_BUTTON_X and RegionMap.cursorY == SWITCH_BUTTON_Y
         and RegionMap.hasSwitchButton() then
    -- pokefirered/src/region_map.c:1251
    PokedexChrome.drawControlInfoLeft(Strings("{A_BUTTON}SWITCH"), 192, 2)
  elseif RegionMap.currentDungeonSec() and RegionMap.canGuideCursor() then
    -- pokefirered/src/region_map.c:1235-1246
    PokedexChrome.drawControlInfoLeft(Strings("{A_BUTTON}GUIDE"), 192, 2)
  end

  -- 8. Dungeon Map Preview / Guide Modal (WIN_MAP_PREVIEW, pret region_map.c:486-494)
  if RegionMap.previewDungeon then
    RegionExtract.ensureGenerated()
    local dSec = RegionMap.previewDungeon
    local dTitle = Strings(RegionExtract.SECTION_NAMES[dSec] or "DUNGEON")
    -- GetDungeonName/GetDungeonFlavorText fall back to gText_RegionMap_NoData
    -- ("No data") for both fields when the mapsec is absent from sDungeonInfo.
    local dDesc = Strings(RegionExtract.DUNGEON_DESCRIPTIONS[dSec] or "No data")
    local tf = previewTextFrame()

    -- drawState 2: FillWindowPixelBuffer(WIN_MAP_PREVIEW, PIXEL_FILL(0)) turns the
    -- text window opaque over the artwork once the window has finished expanding.
    if tf >= PREVIEW_FILL_DELAY then
      love.graphics.setColor(0.06, 0.10, 0.14, 1.0)
      love.graphics.rectangle("fill", PREVIEW_TEXT_X, PREVIEW_TEXT_Y, PREVIEW_TEXT_W, PREVIEW_TEXT_H)
      love.graphics.setColor(1, 1, 1, 1)
    end

    -- drawState 3: the name and flavour text appear only after the tint ramp.
    if tf >= PREVIEW_TEXT_DELAY then
      -- Dungeon Title (Light Green, sTextColor_Green)
      FrlgFont.draw(dTitle, PREVIEW_TEXT_X + PREVIEW_NAME_DX, PREVIEW_TEXT_Y + PREVIEW_NAME_DY, {
        colors = {
          fg = FrlgFont.STDPAL[7],     -- LIGHT_GREEN
          shadow = FrlgFont.STDPAL[2], -- DARK_GRAY
          bg = FrlgFont.STDPAL[0],     -- TRANSPARENT
        }
      })

      -- Dungeon Description (White, sTextColor_White).  ROM strings already carry
      -- their own line breaks; only the ROM-free fallback text needs wrapping.
      local desc = dDesc
      if not desc:find("\n", 1, true) then
        desc = FrlgFont.wrap(desc, PREVIEW_TEXT_W - PREVIEW_DESC_DX)
      end
      FrlgFont.draw(desc, PREVIEW_TEXT_X + PREVIEW_DESC_DX, PREVIEW_TEXT_Y + PREVIEW_DESC_DY, {
        linePitch = PREVIEW_LINE_PITCH,
        colors = FrlgFont.COLOR.WHITE,
      })
    end
  end
end

return RegionMap
