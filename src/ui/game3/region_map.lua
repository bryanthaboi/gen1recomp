local Stack = require("src.ui.game3.stack")
local FrlgFont = require("src.ui.game3.frlg_font")
local PokedexChrome = require("src.ui.game3.pokedex_chrome")
local RegionExtract = require("src.import.gba.region_map_extract")
local MapSectionsExtract = require("src.import.gba.map_sections_extract")
local RomText = require("src.core.game3.rom_text")
local Strings = require("src.core.Strings")
local Gpu = require("src.ui.game3.region_map_gpu")
local Position = require("src.ui.game3.region_map_position")

local RegionMap = {}

RegionMap.open = false
RegionMap.cursorX = 0
RegionMap.cursorY = 0
RegionMap.playerX = 0
RegionMap.playerY = 0
RegionMap.previewDungeon = nil
RegionMap._images = Gpu.images
RegionMap._session = nil
RegionMap._onClose = nil
RegionMap._onPick = nil
RegionMap.mode = "normal"

-- src/region_map.c:20-27
local MAP_WIDTH, MAP_HEIGHT = 22, 15
local CANCEL_BUTTON_X, CANCEL_BUTTON_Y = 21, 13
local SWITCH_BUTTON_X, SWITCH_BUTTON_Y = 21, 11

-- src/region_map.c:29-35
local REGION_IMAGES = { [0] = "kanto_map", "sevii123_map", "sevii45_map", "sevii67_map" }

-- src/region_map.c:37-43
RegionMap.MAPSECTYPE = {
  NONE = 0,
  ROUTE = 1,
  VISITED = 2,
  NOT_VISITED = 3,
  UNKNOWN = 4,
}
local SECTYPE = RegionMap.MAPSECTYPE

-- src/region_map.c:61-69
local INPUT = { NONE = 0, MOVE_START = 1, MOVE_CONT = 2, MOVE_END = 3, A_BUTTON = 4, SWITCH = 5, CANCEL = 6 }

-- src/region_map.c:595-617
local PERMISSIONS = {
  normal = { switchButton = true, mapPreview = true, openAnim = true, flyDestinations = false },
  wall = { switchButton = false, mapPreview = false, openAnim = false, flyDestinations = false },
  fly = { switchButton = false, mapPreview = false, openAnim = false, flyDestinations = true },
}

-- src/region_map.c:619-623
local NAME_BOX = {
  map = { 24, 16, 144, 32 },
  dungeon = { 24, 32, 144, 48 },
  clear = { 0, 0, 0, 0 },
}

-- src/region_map.c:734
local MAP_WINDOW = { 24, 16, 216, 160 }

-- src/region_map.c:2952
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

-- src/region_map.c:3005
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

-- include/constants/songs.h:5,46,105,106,204,230,245,249,250,251
local SE_USE_ITEM = 1
local SE_ROTATING_GATE = 42
local SE_DEX_SCROLL = 101
local SE_DEX_PAGE = 102
local SE_M_SWIFT = 199
local SE_M_SPIT_UP = 225
local SE_M_HYPER_BEAM2 = 240
local SE_CARD_FLIPPING = 243
local SE_CARD_OPEN = 244
local SE_BAG_CURSOR = 245

-- src/main.c:286-287
local KEY_REPEAT_START, KEY_REPEAT_CONTINUE = 40, 5

-- include/constants/map_types.h:8,12
local MAP_TYPE_UNDERGROUND, MAP_TYPE_INDOOR = 4, 8

local S = nil

local function se(id)
  require("src.core.game3.audio").playSe(id)
end

local function sec(id)
  return assert(MapSectionsExtract.ID_TO_SECTION[id], id)
end

local function symOf(mapsec)
  local info = MapSectionsExtract.SECTIONS[mapsec]
  return info and info.id or nil
end

local function numOf(mapsec)
  if mapsec == nil then return RegionExtract.MAPSEC_NONE end
  if type(mapsec) == "number" then return mapsec end
  return sec(mapsec)
end

local function mapDef(mapId)
  local Runtime = require("src.core.game3.runtime")
  local game = Runtime._game
  local maps = game and game.data and game.data.maps
  return assert(maps and maps[mapId], "no map header for " .. tostring(mapId))
end

-- pokefirered/src/palette.c:151 BeginNormalPaletteFade
local function beginFade(startY, targetY)
  local f = S.fade
  if f.active then return false end
  f.deltaY, f.delay, f.delayCounter = 2, 0, 0
  f.y, f.target = startY, targetY
  f.yDec = startY >= targetY
  f.active = true
  f.finishing, f.finishCounter = false, 0
  RegionMap._updateFade()
  f.pending = false
  f.shownBg, f.shownObj = f.bgY, f.objY
  return true
end

local function stepFade(f)
  if not f.active then return end
  if f.finishing then
    if f.finishCounter == 4 then
      f.active, f.finishing, f.finishCounter = false, false, 0
    else
      f.finishCounter = f.finishCounter + 1
    end
    return
  end
  if f.toggle == 0 then
    if f.delayCounter < f.delay then
      f.delayCounter = f.delayCounter + 1
      return
    end
    f.delayCounter = 0
    f.bgY = f.y
  else
    f.objY = f.y
  end
  f.toggle = 1 - f.toggle
  if f.toggle == 0 then
    if f.y == f.target then
      f.finishing = true
    elseif f.yDec then
      f.y = math.max(f.y - f.deltaY, f.target)
    else
      f.y = math.min(f.y + f.deltaY, f.target)
    end
  end
end

-- pokefirered/src/palette.c:113 UpdatePaletteFade, :393 UpdateNormalPaletteFade
function RegionMap._updateFade()
  local f = S.fade
  if f.pending then return end
  stepFade(f)
  f.pending = f.active and not f.finishing
end

-- pokefirered/src/palette.c:100 TransferPlttBuffer
local function vblank()
  if not S.vblank then return end
  local f = S.fade
  f.shownBg, f.shownObj = f.bgY, f.objY
  f.pending = false
end

-- pokefirered/src/palette.c:779 BlendPalettes
local function blendPalettes(y)
  S.fade.bgY, S.fade.objY = y, y
end

function RegionMap.isFlagSet(flagName)
  local Flags = require("src.core.game3.scripting.flags")
  local id = tonumber(flagName) or Flags.IDS[flagName]
  if not id then return false end
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = Space and Space.store
  if store and Flags.getFlag(store, nil, id) == true then return true end
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

-- src/region_map.c:1024-1029
local function perm(name)
  if S then return S.perms[name] == true end
  local p = PERMISSIONS[RegionMap.mode]
  if name == "switchButton" and not RegionMap.isFlagSet("FLAG_SYS_SEVII_MAP_123") then return false end
  return p[name] == true
end

function RegionMap.permission(name)
  return perm(name)
end

function RegionMap.hasFlyDestinations()
  return perm("flyDestinations")
end

function RegionMap.hasSwitchButton()
  return perm("switchButton")
end

function RegionMap.hasMapPreview()
  return perm("mapPreview")
end

function RegionMap.isFlyMode()
  return RegionMap.mode == "fly"
end

local function selectedRegion()
  return S and S.selectedRegion or 0
end

-- src/region_map.c:3354 GetSelectedMapSection
local function mapsecAt(region, layer, y, x)
  RegionExtract.ensureGenerated()
  local grid = RegionExtract.LAYOUTS[region]
  if not grid or y < 0 or y >= MAP_HEIGHT or x < 0 or x >= MAP_WIDTH then return RegionExtract.MAPSEC_NONE end
  return grid[layer][y][x]
end

-- src/region_map.c:2952 GetMapsecType
local function mapsecType(mapsec)
  if mapsec == RegionExtract.MAPSEC_NONE then return SECTYPE.NONE end
  local id = symOf(mapsec)
  if id == "MAPSEC_ROUTE_4_POKECENTER" and not perm("flyDestinations") then return SECTYPE.NONE end
  local flag = MAP_LAYER_FLAGS[id]
  if flag then return RegionMap.isFlagSet(flag) and SECTYPE.VISITED or SECTYPE.NOT_VISITED end
  return SECTYPE.ROUTE
end

-- src/region_map.c:3005 GetDungeonMapsecType
local function dungeonMapsecType(mapsec)
  if mapsec == RegionExtract.MAPSEC_NONE then return SECTYPE.NONE end
  local flag = DUNGEON_LAYER_FLAGS[symOf(mapsec)]
  if flag then return RegionMap.isFlagSet(flag) and SECTYPE.VISITED or SECTYPE.NOT_VISITED end
  return SECTYPE.ROUTE
end

function RegionMap.mapsecType(mapsec)
  return mapsecType(numOf(mapsec))
end

function RegionMap.dungeonMapsecType(mapsec)
  return dungeonMapsecType(numOf(mapsec))
end

-- src/region_map.c:2922 GetMapsecUnderCursor
local function mapsecUnderCursor()
  local mapsec = mapsecAt(selectedRegion(), "map", RegionMap.cursorY, RegionMap.cursorX)
  if (mapsec == sec("MAPSEC_NAVEL_ROCK") or mapsec == sec("MAPSEC_BIRTH_ISLAND"))
     and not RegionMap.isFlagSet("FLAG_WORLD_MAP_NAVEL_ROCK_EXTERIOR") then
    return RegionExtract.MAPSEC_NONE
  end
  return mapsec
end

-- src/region_map.c:2937 GetDungeonMapsecUnderCursor
local function dungeonUnderCursor()
  local mapsec = mapsecAt(selectedRegion(), "dungeon", RegionMap.cursorY, RegionMap.cursorX)
  if mapsec == sec("MAPSEC_CERULEAN_CAVE") and not RegionMap.isFlagSet("FLAG_SYS_CAN_LINK_WITH_RS") then
    return RegionExtract.MAPSEC_NONE
  end
  return mapsec
end

-- src/region_map.c:3078 GetSelectedMapsecType
local function selectedType(layer)
  local mapsec = mapsecAt(selectedRegion(), layer, RegionMap.cursorY, RegionMap.cursorX)
  if layer == "map" then return mapsecType(mapsec) end
  return dungeonMapsecType(mapsec)
end

function RegionMap.currentMapSec()
  return symOf(mapsecAt(selectedRegion(), "map", RegionMap.cursorY, RegionMap.cursorX))
end

function RegionMap.selectedMapsecType()
  return selectedType("map")
end

function RegionMap.selectedDungeonMapsecType()
  return selectedType("dungeon")
end

function RegionMap.dungeonSecAt(x, y)
  local saveX, saveY = RegionMap.cursorX, RegionMap.cursorY
  RegionMap.cursorX, RegionMap.cursorY = x, y
  local mapsec = dungeonUnderCursor()
  RegionMap.cursorX, RegionMap.cursorY = saveX, saveY
  return symOf(mapsec)
end

function RegionMap.currentDungeonSec()
  return symOf(dungeonUnderCursor())
end

-- src/region_map.c:3956
function RegionMap.canFlyToCursor()
  if not perm("flyDestinations") then return false end
  local t = selectedType("map")
  return t == SECTYPE.VISITED or t == SECTYPE.UNKNOWN
end

-- src/region_map.c:1266
function RegionMap.canGuideCursor()
  return perm("mapPreview") and selectedType("dungeon") == SECTYPE.VISITED
end

local function mapName(mapsec)
  RegionExtract.ensureGenerated()
  return Strings(assert(RegionExtract.SECTION_NAMES[symOf(mapsec)], "no sMapNames entry for " .. tostring(mapsec)))
end

function RegionMap.currentLocationName()
  local mapsec = mapsecUnderCursor()
  if mapsec == RegionExtract.MAPSEC_NONE then return nil end
  return mapName(mapsec)
end

function RegionMap.currentDungeonName()
  local mapsec = dungeonUnderCursor()
  if mapsec == RegionExtract.MAPSEC_NONE then return nil end
  return mapName(mapsec)
end

-- src/region_map.c:1930 GetDungeonName, :1919 GetDungeonFlavorText
local function dungeonInfo(mapsec)
  RegionExtract.ensureGenerated()
  local id = symOf(mapsec)
  local desc = id and RegionExtract.DUNGEON_DESCRIPTIONS[id]
  if desc then return Strings(RegionExtract.SECTION_NAMES[id]), Strings(desc) end
  local noData = RomText.plain("gText_RegionMap_NoData")
  return noData, noData
end

function RegionMap.dungeonIconFrame(dSec)
  return RegionMap.dungeonMapsecType(dSec) == SECTYPE.VISITED and 1 or 0
end

-- src/region_map.c:3546-3550
function RegionMap.dungeonIconOffset(x, y, region)
  local mapsec = mapsecAt(region or selectedRegion(), "map", y, x)
  local t = mapsecType(mapsec)
  if (t == SECTYPE.VISITED or t == SECTYPE.NOT_VISITED) and mapsec ~= sec("MAPSEC_ROUTE_10_POKECENTER") then
    return 2
  end
  return 0
end

function RegionMap.dungeonIconVisitedImage()
  return Gpu.image("dungeon_icon_visited")
end

-- src/region_map.c:784-787 sAnim_FlyIcon
function RegionMap.flyIconFrame()
  if not (S and S.icons.flyAnimStart) then return 0 end
  return ((S.frame - S.icons.flyAnimStart) % 90) < 30 and 0 or 1
end

-- src/region_map.c:747-751 sAnim_MapCursor
local function cursorFrame()
  return math.floor((S.frame - S.cursor.animStart) / 20) % 2
end

-- src/region_map.c:630-634 sAnim_SwitchMapCursor
local function switchCursorFrame()
  return math.floor((S.frame - S.switch.cursorAnimStart) / 20) % 2
end

-- src/region_map.c:3558 CreateFlyIcons
local function createFlyIcons()
  local list = {}
  if perm("flyDestinations") then
    for region = 0, 3 do
      for y = 0, MAP_HEIGHT - 1 do
        for x = 0, MAP_WIDTH - 1 do
          local mapsec = mapsecAt(region, "map", y, x)
          if mapsecType(mapsec) == SECTYPE.VISITED then
            list[#list + 1] = { region = region, x = x, y = y, mapsec = mapsec, visible = false }
          end
        end
      end
    end
  end
  S.icons.fly = list
  S.icons.flyAnimStart = S.frame
end

-- src/region_map.c:3581 CreateDungeonIcons
local function createDungeonIcons()
  local list = {}
  for region = 0, 3 do
    for y = 0, MAP_HEIGHT - 1 do
      for x = 0, MAP_WIDTH - 1 do
        local mapsec = mapsecAt(region, "dungeon", y, x)
        if mapsec ~= RegionExtract.MAPSEC_NONE
           and not (mapsec == sec("MAPSEC_CERULEAN_CAVE") and not RegionMap.isFlagSet("FLAG_SYS_CAN_LINK_WITH_RS")) then
          local offset = RegionMap.dungeonIconOffset(x, y, region)
          list[#list + 1] = {
            region = region, x = x, y = y, mapsec = mapsec, visible = false,
            px = 8 * x + 32 + offset, py = 8 * y + 32 + offset,
            frame = dungeonMapsecType(mapsec) == SECTYPE.VISITED and 1 or 0,
          }
        end
      end
    end
  end
  S.icons.dungeon = list
end

-- src/region_map.c:3608 SetFlyIconInvisibility, :3627 SetDungeonIconInvisibility
local function setIconsInvisible(kind, region, invisible)
  for _, icon in ipairs(S.icons[kind]) do
    if region == 0xFF or icon.region == region then icon.visible = not invisible end
  end
end

function RegionMap.flyTargets()
  local out = {}
  if not S then return out end
  for _, icon in ipairs(S.icons.fly) do
    if icon.region == S.selectedRegion then
      out[#out + 1] = { x = icon.x, y = icon.y, sec = symOf(icon.mapsec) }
    end
  end
  return out
end

function RegionMap.dungeonIcons()
  local out = {}
  if not S then return out end
  for _, icon in ipairs(S.icons.dungeon) do
    if icon.region == S.selectedRegion then out[#out + 1] = icon end
  end
  return out
end

-- src/region_map.c:3958-3963
function RegionMap.flyBlockedByMapType()
  local t = tonumber(mapDef(RegionMap._session.map).mapType)
  return t == MAP_TYPE_UNDERGROUND or t == MAP_TYPE_INDOOR
end

-- src/region_map.c:3839 PrintTopBarTextLeft
local function topBarLeft(key)
  S.topBar.left = key
end

-- src/region_map.c:3849 PrintTopBarTextRight
local function topBarRight(key)
  S.topBar.right = key
end

function RegionMap.topBarText()
  if not S then return nil, nil end
  return S.topBar.left, S.topBar.right
end

-- src/region_map.c:1422 UpdateMapsecNameBox
local function updateMapsecNameBox()
  local g = S.gpu
  Gpu.reset(g)
  Gpu.setBldCnt(g, 0, Gpu.BG0 + Gpu.OBJ, Gpu.DARKEN)
  Gpu.setBldY(g, 6)
  local inside = Gpu.BG0 + Gpu.BG3 + Gpu.OBJ + Gpu.CLR
  Gpu.setWinIn(g, inside, inside)
  Gpu.setWinOut(g, Gpu.BG0 + Gpu.BG1 + Gpu.BG3 + Gpu.OBJ)
  Gpu.setWindowDims(g, 0, unpack(NAME_BOX.map))
  Gpu.setWindowDims(g, 1, unpack(NAME_BOX.dungeon))
  Gpu.setDispCnt(g, 0, false)
  if dungeonUnderCursor() ~= RegionExtract.MAPSEC_NONE then Gpu.setDispCnt(g, 1, false) end
end

-- src/region_map.c:1438 DisplayCurrentMapName
local function displayCurrentMapName()
  S.text.map = nil
  local mapsec = mapsecUnderCursor()
  if mapsec == RegionExtract.MAPSEC_NONE then
    Gpu.setWindowDims(S.gpu, 0, unpack(NAME_BOX.clear))
  else
    S.text.map = mapName(mapsec)
    Gpu.setWindowDims(S.gpu, 0, unpack(NAME_BOX.map))
  end
end

-- src/region_map.c:1456 DrawDungeonNameBox
local function drawDungeonNameBox()
  Gpu.setWindowDims(S.gpu, 1, unpack(NAME_BOX.dungeon))
end

-- src/region_map.c:1461 DisplayCurrentDungeonName
local function displayCurrentDungeonName()
  Gpu.setDispCnt(S.gpu, 1, true)
  S.text.dungeon = nil
  local mapsec = dungeonUnderCursor()
  if mapsec ~= RegionExtract.MAPSEC_NONE then
    Gpu.setDispCnt(S.gpu, 1, false)
    S.text.dungeon = mapName(mapsec)
    S.text.dungeonType = selectedType("dungeon")
  end
end

-- src/region_map.c:1487 ClearMapsecNameText
local function clearMapsecNameText()
  S.text.map, S.text.dungeon = nil, nil
end

-- src/region_map.c:1495 BufferRegionMapBg
local function bufferRegionMapBg(region)
  local whichMap = S.switch and S.switch.currentSelection or S.selectedRegion
  S.bg0 = {
    region = region,
    switchButton = S.perms.switchButton,
    navelPatch = whichMap == 2 and not RegionMap.isFlagSet("FLAG_WORLD_MAP_NAVEL_ROCK_EXTERIOR"),
    birthPatch = whichMap == 3 and not RegionMap.isFlagSet("FLAG_WORLD_MAP_BIRTH_ISLAND_EXTERIOR"),
  }
end

local function saveGpuRegs()
  if S.savedRegs then return false end
  S.savedRegs = Gpu.save(S.gpu)
  return true
end

local function restoreGpuRegs()
  if not S.savedRegs then return false end
  Gpu.restore(S.gpu, S.savedRegs)
  S.savedRegs = nil
  return true
end

local function setTask(name)
  S.task = name
end

-- src/region_map.c:2674 SpriteCB_MapCursor
local function spriteCbMapCursor()
  local c = S.cursor
  if c.moveCounter ~= 0 then
    c.spriteX = c.spriteX + c.horizontalMove
    c.spriteY = c.spriteY + c.verticalMove
    c.moveCounter = c.moveCounter - 1
  else
    c.spriteX = 8 * RegionMap.cursorX + 36
    c.spriteY = 8 * RegionMap.cursorY + 36
  end
end

-- src/region_map.c:2689 CreateMapCursor
local function createMapCursor()
  local session = RegionMap._session
  local x, y = Position.playerCell({
    map = session.map, x = session.x, y = session.y,
    escapeWarp = session.escapeWarp, dynamicWarp = session.dynamicWarp, def = mapDef,
  }, RegionExtract.GEOMETRY)
  RegionMap.cursorX, RegionMap.cursorY = x, y
  local c = S.cursor
  c.exists = true
  c.spriteX, c.spriteY = 8 * x + 36, 8 * y + 36
  c.handler = "input"
  c.animStart = S.frame
  c.visible = false
end

-- src/region_map.c:3371 CreatePlayerIcon
local function createPlayerIcon()
  RegionMap.playerX, RegionMap.playerY = RegionMap.cursorX, RegionMap.cursorY
  S.player.exists = true
  S.player.visible = false
end

local function joyNew(k) return S.input and S.input:wasPressed(k) or false end
local function joyHeld(k) return S.input and S.input.isDown and S.input:isDown(k) or false end

-- src/region_map.c:2862 SnapToIconOrButton
local function snapToIconOrButton()
  local c = S.cursor
  if perm("switchButton") then
    c.snapId = (c.snapId + 1) % 3
    if c.snapId == 0 and S.selectedRegion ~= S.playersRegion then c.snapId = c.snapId + 1 end
    if c.snapId == 1 then
      RegionMap.cursorX, RegionMap.cursorY = SWITCH_BUTTON_X, SWITCH_BUTTON_Y
    elseif c.snapId == 2 then
      RegionMap.cursorX, RegionMap.cursorY = CANCEL_BUTTON_X, CANCEL_BUTTON_Y
    else
      RegionMap.cursorX, RegionMap.cursorY = RegionMap.playerX, RegionMap.playerY
    end
  else
    c.snapId = (c.snapId + 1) % 2
    if c.snapId == 1 then
      RegionMap.cursorX, RegionMap.cursorY = CANCEL_BUTTON_X, CANCEL_BUTTON_Y
    else
      RegionMap.cursorX, RegionMap.cursorY = RegionMap.playerX, RegionMap.playerY
    end
  end
  c.spriteX, c.spriteY = 8 * RegionMap.cursorX + 36, 8 * RegionMap.cursorY + 36
end

-- src/region_map.c:2754 HandleRegionMapInput
local function handleRegionMapInput()
  local c = S.cursor
  local input = INPUT.NONE
  c.horizontalMove, c.verticalMove = 0, 0
  if joyHeld("up") and RegionMap.cursorY > 0 then
    c.verticalMove = -2
    input = INPUT.MOVE_START
  end
  if joyHeld("down") and RegionMap.cursorY < MAP_HEIGHT - 1 then
    c.verticalMove = 2
    input = INPUT.MOVE_START
  end
  if joyHeld("right") and RegionMap.cursorX < MAP_WIDTH - 1 then
    c.horizontalMove = 2
    input = INPUT.MOVE_START
  end
  if joyHeld("left") and RegionMap.cursorX > 0 then
    c.horizontalMove = -2
    input = INPUT.MOVE_START
  end
  if joyNew("a") then
    input = INPUT.A_BUTTON
    if RegionMap.cursorX == CANCEL_BUTTON_X and RegionMap.cursorY == CANCEL_BUTTON_Y then
      se(SE_M_HYPER_BEAM2)
      input = INPUT.CANCEL
    end
    if RegionMap.cursorX == SWITCH_BUTTON_X and RegionMap.cursorY == SWITCH_BUTTON_Y and perm("switchButton") then
      se(SE_M_HYPER_BEAM2)
      input = INPUT.SWITCH
    end
  elseif not joyNew("b") then
    if S.startRepeat then
      snapToIconOrButton()
      return INPUT.MOVE_END
    elseif joyNew("select") and S.fromField then
      input = INPUT.CANCEL
    end
  else
    input = INPUT.CANCEL
  end
  if input == INPUT.MOVE_START then
    c.moveCounter = 4
    c.handler = "move"
  end
  return input
end

-- src/region_map.c:2836 MoveMapCursor
local function moveMapCursor()
  local c = S.cursor
  if c.moveCounter ~= 0 then return INPUT.MOVE_CONT end
  if c.horizontalMove > 0 then RegionMap.cursorX = RegionMap.cursorX + 1 end
  if c.horizontalMove < 0 then RegionMap.cursorX = RegionMap.cursorX - 1 end
  if c.verticalMove > 0 then RegionMap.cursorY = RegionMap.cursorY + 1 end
  if c.verticalMove < 0 then RegionMap.cursorY = RegionMap.cursorY - 1 end
  c.handler = "input"
  return INPUT.MOVE_END
end

-- src/region_map.c:2855 GetRegionMapInput
local function getRegionMapInput()
  if S.cursor.handler == "move" then return moveMapCursor() end
  return handleRegionMapInput()
end

-- src/region_map.c:1168 PlaySEForSelectedMapsec
local function playSEForSelectedMapsec()
  if mapsecAt(S.selectedRegion, "map", RegionMap.cursorY, RegionMap.cursorX) == sec("MAPSEC_ROUTE_4_POKECENTER") then
    return
  end
  local t, d = selectedType("map"), selectedType("dungeon")
  if (t ~= SECTYPE.ROUTE and t ~= SECTYPE.NONE) or (d ~= SECTYPE.ROUTE and d ~= SECTYPE.NONE) then
    se(SE_DEX_SCROLL)
  end
  if RegionMap.cursorX == SWITCH_BUTTON_X and RegionMap.cursorY == SWITCH_BUTTON_Y and perm("switchButton") then
    se(SE_M_SPIT_UP)
  elseif RegionMap.cursorX == CANCEL_BUTTON_X and RegionMap.cursorY == CANCEL_BUTTON_Y then
    se(SE_M_SPIT_UP)
  end
end

local Tasks = {}

-- src/region_map.c:3443 InitMapIcons
local function initMapIcons(exitTask)
  S.icons.state = 0
  S.icons.exitTask = exitTask
  setTask("loadMapIcons")
end

-- src/region_map.c:3453 LoadMapIcons
function Tasks.loadMapIcons()
  local st = S.icons.state
  if st == 0 then
    S.vblank = false
    S.icons.state = 1
  elseif st == 1 then
    createDungeonIcons()
    S.icons.state = 2
  elseif st == 2 then
    createFlyIcons()
    S.icons.state = 3
  elseif st == 3 then
    blendPalettes(16)
    beginFade(16, 0)
    S.icons.state = 4
  elseif st == 4 then
    S.vblank = true
    S.icons.state = 5
  else
    S.objOn = true
    setTask(S.icons.exitTask)
  end
end

-- src/region_map.c:2296 InitScreenForMapOpenAnim
local function initScreenForMapOpenAnim()
  local g = S.gpu
  Gpu.setBldCnt(g, 0, Gpu.BG1, Gpu.NONE)
  Gpu.setWinIn(g, Gpu.BG1 + Gpu.OBJ, 0)
  Gpu.setWinOut(g, Gpu.OBJ)
  Gpu.setWindowDims(g, 0, S.edges[1].x + 8, 16, S.edges[4].x - 8, 160)
  Gpu.setDispCnt(g, 0, false)
end

-- src/region_map.c:2518 SetGpuWindowDimsToMapEdges
local function setGpuWindowDimsToMapEdges()
  Gpu.setWindowDims(S.gpu, 0, S.edges[1].x, 16, S.edges[4].x, 160)
end

-- src/region_map.c:2310 SetGpuRegsToFadeMapToWhite
local function setGpuRegsToFadeMapToWhite()
  local g = S.gpu
  Gpu.reset(g)
  Gpu.setBldCnt(g, Gpu.BG1, Gpu.BG0 + Gpu.BG3 + Gpu.BD, Gpu.LIGHTEN)
  Gpu.setBldY(g, S.anim.blendY)
  Gpu.setWinIn(g, Gpu.ALL - Gpu.BG3, 0)
  Gpu.setWinOut(g, Gpu.BG1 + Gpu.OBJ)
  Gpu.setWindowDims(g, 0, unpack(MAP_WINDOW))
  Gpu.setDispCnt(g, 0, false)
end

local EDGE_NAMES = { "edge_top_left", "edge_mid_left", "edge_bottom_left", "edge_top_right", "edge_mid_right", "edge_bottom_right" }

-- src/region_map.c:2217 InitMapOpenAnim
local function initMapOpenAnim(exitTask)
  S.edges = {}
  for i = 0, 5 do
    S.edges[i + 1] = { name = EDGE_NAMES[i + 1], x = 32 * math.floor(i / 3) + 104, y = 64 * (i % 3) + 40, visible = false }
  end
  S.anim = { openState = 0, loadGfxState = 0, moveState = 0, closeState = 0, blendY = 0, exitTask = exitTask }
  saveGpuRegs()
  Gpu.reset(S.gpu)
  initScreenForMapOpenAnim()
  S.bgShown[0], S.bgShown[3] = false, false
  setTask("mapOpenAnim")
end

local function setEdgesVisible(visible)
  for _, e in ipairs(S.edges) do e.visible = visible end
end

-- src/region_map.c:2462 MoveMapEdgesOutward, :2618 MoveMapEdgesInward
local function moveMapEdges(outward)
  setGpuWindowDimsToMapEdges()
  local goal = outward and 0 or 104
  if S.edges[1].x == goal then return true end
  local ms = S.anim.moveState
  local step
  if ms > 17 then step = 1 elseif ms > 14 then step = 2 elseif ms > 10 then step = 3 elseif ms > 6 then step = 5 else step = 8 end
  if not outward then step = -step end
  for i = 1, 3 do S.edges[i].x = S.edges[i].x - step end
  for i = 4, 6 do S.edges[i].x = S.edges[i].x + step end
  S.anim.moveState = ms + 1
  return false
end

-- src/region_map.c:2354 Task_MapOpenAnim
function Tasks.mapOpenAnim()
  local a = S.anim
  local st = a.openState
  if st == 0 then
    S.vblank = false
    a.openState = 1
  elseif st == 1 then
    if a.loadGfxState >= 9 then
      a.openState = 2
    else
      a.loadGfxState = a.loadGfxState + 1
    end
  elseif st == 2 then
    S.bg1 = "frame_normal"
    a.openState = 3
  elseif st == 3 then
    blendPalettes(16)
    beginFade(16, 0)
    S.vblank = true
    a.openState = 4
  elseif st == 4 then
    S.bgShown[0], S.bgShown[3], S.bgShown[1] = true, true, true
    setEdgesVisible(true)
    setGpuWindowDimsToMapEdges()
    a.openState = 5
  elseif st == 5 then
    if not S.fade.active then
      a.openState = 6
      se(SE_CARD_OPEN)
    end
  elseif st == 6 then
    if moveMapEdges(true) then a.openState = 7 end
  elseif st == 7 then
    S.player.visible = true
    S.cursor.visible = true
    a.openState = 8
  elseif st == 8 then
    a.blendY = 15
    setGpuRegsToFadeMapToWhite()
    S.bgShown[0], S.bgShown[3] = true, true
    setIconsInvisible("fly", S.selectedRegion, false)
    setIconsInvisible("dungeon", S.selectedRegion, false)
    a.openState = 9
  elseif st == 9 then
    topBarLeft("gText_RegionMap_DPadMove")
    if selectedType("dungeon") ~= SECTYPE.VISITED then
      topBarRight("gText_RegionMap_Space")
    else
      topBarRight("gText_RegionMap_AButtonGuide")
    end
    S.topBar.shown = true
    a.openState = 10
  elseif st == 10 then
    S.backdropBlue = true
    a.openState = 11
  elseif st == 11 then
    require("src.core.game3.audio").stopSe(SE_CARD_OPEN)
    se(SE_ROTATING_GATE)
    a.openState = 12
  elseif st == 12 then
    if a.blendY == 2 then
      setEdgesVisible(false)
      a.openState = 13
      Gpu.setBldY(S.gpu, 0)
    else
      a.blendY = a.blendY - 1
      Gpu.setBldY(S.gpu, a.blendY)
    end
  elseif st == 13 then
    restoreGpuRegs()
    displayCurrentDungeonName()
    a.openState = 14
  else
    setTask(a.exitTask)
  end
end

-- src/region_map.c:2528 InitScreenForMapCloseAnim
local function initScreenForMapCloseAnim()
  local g = S.gpu
  Gpu.setBldCnt(g, 0, Gpu.BG1, Gpu.NONE)
  Gpu.setWinIn(g, Gpu.BG1 + Gpu.OBJ, 0)
  Gpu.setWinOut(g, Gpu.OBJ)
  Gpu.setWindowDims(g, 0, S.edges[1].x + 16, 16, S.edges[4].x - 16, 160)
  Gpu.setDispCnt(g, 0, false)
end

-- src/region_map.c:2557 Task_MapCloseAnim
function Tasks.mapCloseAnim()
  local a = S.anim
  local st = a.closeState
  if st == 0 then
    S.topBar.shown = false
    a.closeState = 1
  elseif st == 1 then
    a.closeState = 2
  elseif st == 2 then
    S.backdropBlue = false
    -- src/region_map.c:2572
    S.palTinted = false
    a.closeState = 3
  elseif st == 3 then
    setEdgesVisible(true)
    S.player.visible = false
    S.cursor.visible = false
    setIconsInvisible("dungeon", 0xFF, true)
    setIconsInvisible("fly", 0xFF, true)
    a.moveState = 0
    a.blendY = 0
    a.closeState = 4
  elseif st == 4 then
    setGpuRegsToFadeMapToWhite()
    a.closeState = 5
  elseif st == 5 then
    if a.blendY == 15 then
      Gpu.setBldY(S.gpu, a.blendY)
      a.closeState = 6
    else
      a.blendY = a.blendY + 1
      Gpu.setBldY(S.gpu, a.blendY)
    end
  elseif st == 6 then
    initScreenForMapCloseAnim()
    setGpuWindowDimsToMapEdges()
    se(SE_CARD_FLIPPING)
    a.closeState = 7
  elseif st == 7 then
    if moveMapEdges(false) then a.closeState = 8 end
  else
    setTask(a.exitTask)
  end
end

-- src/region_map.c:1553 InitSwitchMapMenu
local function initSwitchMapMenu(whichMap, exitTask)
  local sw = { alpha = 0, blendY = 0, mainState = 0, cursorLoadState = 0, exitTask = exitTask }
  if RegionMap.isFlagSet("FLAG_SYS_SEVII_MAP_4567") then
    sw.maxSelection = 3
  elseif RegionMap.isFlagSet("FLAG_SYS_SEVII_MAP_123") then
    sw.maxSelection = 1
  else
    sw.maxSelection = 0
  end
  if sw.maxSelection == 1 then
    sw.image, sw.yOffset = "switch_menu_123", 6
  else
    sw.image, sw.yOffset = "switch_menu_all", 3
  end
  sw.currentSelection = whichMap
  sw.chosenRegion = S.playersRegion
  sw.highlight = { 0, 0, 0, 0 }
  S.switch = sw
  saveGpuRegs()
  topBarRight("gText_RegionMap_AButtonOK")
  setTask("switchMapMenu")
end

-- src/region_map.c:1591 ResetGpuRegsForSwitchMapMenu
local function resetGpuRegsForSwitchMapMenu()
  local g = S.gpu
  Gpu.reset(g)
  Gpu.setBldCnt(g, Gpu.BG0 + Gpu.BG1 + Gpu.BG3 + Gpu.OBJ, Gpu.BG2, Gpu.BLEND)
  Gpu.setBldAlpha(g, 16 - S.switch.alpha, S.switch.alpha)
end

local function highlightRect()
  local sw = S.switch
  local top = 8 * (sw.yOffset + 4 * sw.currentSelection)
  sw.highlight = { 72, top, 168, top + 32 }
  return sw.highlight
end

-- src/region_map.c:1757 SetGpuRegsToDimScreen
local function setGpuRegsToDimScreen()
  local g = S.gpu
  local h = highlightRect()
  Gpu.reset(g)
  Gpu.setBldCnt(g, 0, Gpu.BG0 + Gpu.BG2 + Gpu.OBJ, Gpu.DARKEN)
  Gpu.setWinIn(g, Gpu.BG_ALL + Gpu.OBJ, Gpu.BG0 + Gpu.BG2 + Gpu.OBJ)
  Gpu.setWinOut(g, Gpu.ALL)
  Gpu.setDispCnt(g, 1, false)
  Gpu.setWindowDims(g, 1, unpack(h))
end

local function redrawForSelection()
  bufferRegionMapBg(S.switch.currentSelection)
  setIconsInvisible("fly", 0xFF, true)
  setIconsInvisible("dungeon", 0xFF, true)
end

-- src/region_map.c:1786 HandleSwitchMapInput
local function handleSwitchMapInput()
  local sw = S.switch
  local changed = false
  local h = highlightRect()
  if joyNew("up") and sw.currentSelection ~= 0 then
    se(SE_BAG_CURSOR)
    sw.currentSelection = sw.currentSelection - 1
    changed = true
  end
  if joyNew("down") and sw.currentSelection < sw.maxSelection then
    se(SE_BAG_CURSOR)
    sw.currentSelection = sw.currentSelection + 1
    changed = true
  end
  if joyNew("a") and sw.blendY == 6 then
    se(SE_M_SWIFT)
    sw.chosenRegion = sw.currentSelection
    return true
  end
  if joyNew("b") then
    sw.currentSelection = sw.chosenRegion
    redrawForSelection()
    return true
  end
  if changed then
    redrawForSelection()
    topBarRight("gText_RegionMap_AButtonOK")
    setIconsInvisible("fly", sw.currentSelection, false)
    setIconsInvisible("dungeon", sw.currentSelection, false)
  end
  S.player.visible = sw.currentSelection == S.playersRegion
  Gpu.setWindowDims(S.gpu, 1, unpack(h))
  return false
end

-- src/region_map.c:1626 Task_SwitchMapMenu
function Tasks.switchMapMenu()
  local sw = S.switch
  local st = sw.mainState
  if st == 0 then
    S.vblank = false
    topBarLeft("gText_RegionMap_UpDownPick")
    sw.mainState = 1
  elseif st == 1 then
    sw.mainState = 2
  elseif st == 2 then
    S.bg2 = { image = sw.image }
    sw.mainState = 3
  elseif st == 3 then
    clearMapsecNameText()
    sw.mainState = 4
  elseif st == 4 then
    resetGpuRegsForSwitchMapMenu()
    S.bgShown[2] = true
    sw.mainState = 5
  elseif st == 5 then
    S.vblank = true
    sw.mainState = 6
  elseif st == 6 then
    if sw.alpha < 16 then
      Gpu.setBldAlpha(S.gpu, 16 - sw.alpha, sw.alpha)
      sw.alpha = sw.alpha + 2
    else
      setGpuRegsToDimScreen()
      sw.mainState = 7
    end
  elseif st == 7 then
    if sw.blendY < 6 then
      sw.blendY = sw.blendY + 1
      Gpu.setBldY(S.gpu, sw.blendY)
    else
      sw.mainState = 8
    end
  elseif st == 8 then
    if sw.cursorLoadState >= 3 then
      sw.mainState = 9
    else
      if sw.cursorLoadState == 2 then
        sw.cursors = true
        sw.cursorAnimStart = S.frame
      end
      sw.cursorLoadState = sw.cursorLoadState + 1
    end
  elseif st == 9 then
    if handleSwitchMapInput() then
      S.selectedRegion = sw.currentSelection
      if S.playersRegion == sw.currentSelection then
        S.player.visible = true
        setIconsInvisible("fly", sw.currentSelection, false)
        setIconsInvisible("dungeon", sw.currentSelection, false)
      end
      sw.mainState = 10
    end
  elseif st == 10 then
    if sw.blendY ~= 0 then
      sw.blendY = sw.blendY - 1
      Gpu.setBldY(S.gpu, sw.blendY)
    else
      Gpu.setBldY(S.gpu, 0)
      sw.cursors = false
      resetGpuRegsForSwitchMapMenu()
      sw.mainState = 11
    end
  elseif st == 11 then
    if sw.alpha >= 2 then
      sw.alpha = sw.alpha - 2
      Gpu.setBldAlpha(S.gpu, 16 - sw.alpha, sw.alpha)
    else
      sw.mainState = 12
    end
  elseif st == 12 then
    S.cursor.visible = true
    sw.mainState = 13
  else
    setTask(sw.exitTask)
    S.bgShown[2] = false
    S.bg2 = nil
    topBarLeft("gText_RegionMap_DPadMove")
    topBarRight("gText_RegionMap_AButtonSwitch")
    S.switch = nil
    updateMapsecNameBox()
    drawDungeonNameBox()
    Gpu.setWindowDims(S.gpu, 0, unpack(NAME_BOX.clear))
  end
end

-- src/region_map.c:1941 InitDungeonMapPreview
local function initDungeonMapPreview(exitTask)
  local mapsec = dungeonUnderCursor()
  if mapsec == sec("MAPSEC_TANOBY_CHAMBERS") then mapsec = sec("MAPSEC_MONEAN_CHAMBER") end
  local MapPreviewScreen = require("src.ui.game3.map_preview_screen")
  if not MapPreviewScreen.entryFor(mapsec) then mapsec = sec("MAPSEC_ROCK_TUNNEL") end
  S.preview = {
    artSec = mapsec, mainState = 0, drawState = 0, loadState = 0, updateCounter = 0, timer = 0,
    blendY = 0, exitTask = exitTask, dungeon = dungeonUnderCursor(),
  }
  RegionMap.previewDungeon = symOf(S.preview.dungeon) or "MAPSEC_NONE"
  saveGpuRegs()
  Gpu.reset(S.gpu)
  clearMapsecNameText()
  setTask("dungeonMapPreview")
end

-- src/region_map.c:2113 InitScreenForDungeonMapPreview
local function initScreenForDungeonMapPreview()
  local g, p = S.gpu, S.preview
  Gpu.reset(g)
  Gpu.setBldCnt(g, 0, Gpu.BG0 + Gpu.OBJ, Gpu.DARKEN)
  Gpu.setBldY(g, p.blendY)
  Gpu.setWinIn(g, 0, Gpu.BG0 + Gpu.BG2 + Gpu.BG3)
  Gpu.setWinOut(g, Gpu.BG0 + Gpu.BG1 + Gpu.BG3 + Gpu.OBJ + Gpu.CLR)
  Gpu.setDispCnt(g, 1, false)
  p.left = 8 * RegionMap.cursorX + 32
  p.top = 8 * RegionMap.cursorY + 24
  p.right = p.left + 8
  p.bottom = p.top + 8
  local function inc(v) return v >= 0 and math.floor(v / 8) or -math.floor(-v / 8) end
  p.leftIncrement = inc(16 - p.left)
  p.topIncrement = inc(32 - p.top)
  p.rightIncrement = inc(224 - p.right)
  p.bottomIncrement = inc(136 - p.bottom)
end

-- src/region_map.c:2135 UpdateDungeonMapPreview
local function updateDungeonMapPreview(closing)
  local p = S.preview
  if not closing then
    if p.updateCounter < 8 then
      p.left = p.left + p.leftIncrement
      p.top = p.top + p.topIncrement
      p.right = p.right + p.rightIncrement
      p.bottom = p.bottom + p.bottomIncrement
      p.updateCounter = p.updateCounter + 1
      if p.blendY < 6 then p.blendY = p.blendY + 1 end
    else
      return true
    end
  else
    if p.updateCounter == 0 then return true end
    p.left = p.left - p.leftIncrement
    p.top = p.top - p.topIncrement
    p.right = p.right - p.rightIncrement
    p.bottom = p.bottom - p.bottomIncrement
    p.updateCounter = p.updateCounter - 1
    if p.blendY > 0 then p.blendY = p.blendY - 1 end
  end
  Gpu.setWindowDims(S.gpu, 1, p.left, p.top, p.right, p.bottom)
  Gpu.setBldY(S.gpu, p.blendY)
  return false
end

-- src/region_map.c:2095 FreeDungeonMapPreview
local function freeDungeonMapPreview()
  setTask(S.preview.exitTask)
  S.bgShown[2] = false
  S.bg2 = nil
  restoreGpuRegs()
  displayCurrentMapName()
  displayCurrentDungeonName()
  updateMapsecNameBox()
  drawDungeonNameBox()
  topBarRight("gText_RegionMap_AButtonGuide")
  S.preview = nil
  RegionMap.previewDungeon = nil
end

-- src/region_map.c:1984 Task_DungeonMapPreview
function Tasks.dungeonMapPreview()
  local p = S.preview
  local st = p.mainState
  if st == 0 then
    S.vblank = false
    p.mainState = 1
  elseif st == 1 then
    if p.loadState >= 4 then
      p.mainState = 2
    else
      p.loadState = p.loadState + 1
    end
  elseif st == 2 then
    initScreenForDungeonMapPreview()
    topBarRight("gText_RegionMap_AButtonCancel2")
    p.mainState = 3
  elseif st == 3 then
    S.bg2 = { preview = p.artSec }
    p.mainState = 4
  elseif st == 4 then
    S.bgShown[2] = true
    p.mainState = 5
  elseif st == 5 then
    S.vblank = true
    p.mainState = 6
  elseif st == 6 then
    if updateDungeonMapPreview(false) then p.mainState = 7 end
  elseif st == 7 then
    setTask("dungeonMapPreviewFlavorText")
  elseif st == 8 then
    if updateDungeonMapPreview(true) then p.mainState = 9 end
  elseif st == 9 then
    freeDungeonMapPreview()
  end
end

-- src/region_map.c:2035 Task_DrawDungeonMapPreviewFlavorText
function Tasks.dungeonMapPreviewFlavorText()
  local p = S.preview
  local st = p.drawState
  if st == 0 then
    p.red, p.green, p.blue = 0x0133, 0x0100, 0x00F0
    p.drawState = 1
  elseif st == 1 then
    local t = p.timer
    p.timer = t + 1
    if t > 40 then
      p.timer = 0
      p.drawState = 2
    end
  elseif st == 2 then
    p.text = nil
    p.drawState = 3
  elseif st == 3 then
    if p.timer > 25 then
      local name, desc = dungeonInfo(dungeonUnderCursor())
      p.text = { name = name, desc = desc }
      p.drawState = 4
    elseif p.timer > 20 then
      p.red, p.green, p.blue = p.red - 6, p.green - 5, p.blue - 5
      S.bg2.tone = { p.red, p.green, p.blue }
    end
    p.timer = p.timer + 1
  elseif st == 4 then
    if joyNew("b") or joyNew("a") then
      p.text = nil
      p.mainState = p.mainState + 1
      p.drawState = 5
    end
  else
    setTask("dungeonMapPreview")
  end
end

-- src/region_map.c:1182 Task_RegionMap
function Tasks.regionMap()
  local st = S.mainState
  if st == 0 then
    initMapIcons("regionMap")
    createMapCursor()
    createPlayerIcon()
    S.mainState = 1
  elseif st == 1 then
    if S.perms.openAnim then
      initMapOpenAnim("regionMap")
    else
      S.bgShown[0], S.bgShown[3], S.bgShown[1] = true, true, true
      topBarLeft("gText_RegionMap_DPadMove")
      topBarRight("gText_RegionMap_Space")
      S.topBar.shown = true
      S.player.visible = true
      S.cursor.visible = true
      setIconsInvisible("fly", S.selectedRegion, false)
      setIconsInvisible("dungeon", S.selectedRegion, false)
    end
    S.mainState = 2
  elseif st == 2 then
    if not S.fade.active then
      displayCurrentMapName()
      displayCurrentDungeonName()
      S.mainState = 3
    end
  elseif st == 3 then
    local input = getRegionMapInput()
    if input == INPUT.MOVE_START then
      S.cursor.snapId = 0
    elseif input == INPUT.MOVE_END then
      displayCurrentMapName()
      displayCurrentDungeonName()
      drawDungeonNameBox()
      playSEForSelectedMapsec()
      if dungeonUnderCursor() ~= RegionExtract.MAPSEC_NONE then
        if perm("mapPreview") then
          if selectedType("dungeon") == SECTYPE.VISITED then
            topBarRight("gText_RegionMap_AButtonGuide")
          else
            topBarRight("gText_RegionMap_Space")
          end
        end
      elseif RegionMap.cursorX == SWITCH_BUTTON_X and RegionMap.cursorY == SWITCH_BUTTON_Y and perm("switchButton") then
        topBarRight("gText_RegionMap_AButtonSwitch")
      elseif RegionMap.cursorX == CANCEL_BUTTON_X and RegionMap.cursorY == CANCEL_BUTTON_Y then
        topBarRight("gText_RegionMap_AButtonCancel")
      else
        topBarRight("gText_RegionMap_Space")
      end
    elseif input == INPUT.A_BUTTON then
      if selectedType("dungeon") == SECTYPE.VISITED and S.perms.mapPreview then
        initDungeonMapPreview("saveMainMapTask")
      end
    elseif input == INPUT.SWITCH then
      initSwitchMapMenu(S.selectedRegion, "saveMainMapTask")
    elseif input == INPUT.CANCEL then
      S.mainState = 4
    end
  elseif st == 4 then
    if perm("openAnim") then
      S.anim.closeState, S.anim.exitTask = 0, "regionMap"
      setTask("mapCloseAnim")
    end
    S.mainState = 5
  elseif st == 5 then
    beginFade(0, 16)
    S.mainState = 6
  else
    if not S.fade.active then S.finish = { picked = false } end
  end
end

-- src/region_map.c:1315 SaveMainMapTask
function Tasks.saveMainMapTask()
  setTask(S.mainTask)
end

-- src/region_map.c:3879 Task_FlyMap
function Tasks.flyMap()
  local st = S.mainState
  if st == 0 then
    beginFade(16, 0)
    initMapIcons("flyMap")
    createMapCursor()
    createPlayerIcon()
    S.cursor.visible = true
    S.player.visible = true
    S.mainState = 1
  elseif st == 1 then
    S.bgShown[0], S.bgShown[3], S.bgShown[1] = true, true, true
    topBarLeft("gText_RegionMap_DPadMove")
    setIconsInvisible("fly", S.selectedRegion, false)
    setIconsInvisible("dungeon", S.selectedRegion, false)
    S.mainState = 2
  elseif st == 2 then
    topBarRight("gText_RegionMap_AButtonOK")
    S.topBar.shown = true
    S.mainState = 3
  elseif st == 3 then
    if not S.fade.active then
      displayCurrentMapName()
      displayCurrentDungeonName()
      S.mainState = 4
    end
  elseif st == 4 then
    local input = getRegionMapInput()
    if input == INPUT.CANCEL then
      S.mainState = 6
    elseif input == INPUT.MOVE_END then
      if selectedType("map") == SECTYPE.VISITED then
        se(SE_DEX_PAGE)
      else
        playSEForSelectedMapsec()
      end
      S.cursor.snapId = 0
      displayCurrentMapName()
      displayCurrentDungeonName()
      drawDungeonNameBox()
      local t = selectedType("map")
      if RegionMap.cursorX == CANCEL_BUTTON_X and RegionMap.cursorY == CANCEL_BUTTON_Y then
        se(SE_M_SPIT_UP)
        topBarRight("gText_RegionMap_AButtonCancel")
      elseif t == SECTYPE.VISITED or t == SECTYPE.UNKNOWN then
        topBarRight("gText_RegionMap_AButtonOK")
      else
        topBarRight("gText_RegionMap_Space")
      end
    elseif input == INPUT.A_BUTTON then
      local t = selectedType("map")
      if (t == SECTYPE.VISITED or t == SECTYPE.UNKNOWN) and perm("flyDestinations") then
        if RegionMap.flyBlockedByMapType() then
          S.selectedDestination = false
        else
          se(SE_USE_ITEM)
          S.selectedDestination = true
        end
        S.mainState = 5
      end
    elseif input == INPUT.SWITCH then
      initSwitchMapMenu(S.selectedRegion, "saveMainMapTask")
    end
  elseif st == 5 then
    S.mainState = 6
  elseif st == 6 then
    beginFade(0, 16)
    S.mainState = 7
  else
    if not S.fade.active then
      S.finish = { picked = S.selectedDestination == true, mapsec = S.selectedDestination and mapsecUnderCursor() or nil }
    end
  end
end

-- src/region_map.c:1052 CB2_OpenRegionMap
local function cb2OpenRegionMap()
  local st = S.openState
  if st == 1 then
    updateMapsecNameBox()
  elseif st == 3 then
    if S.loadGfxState < 9 then
      S.loadGfxState = S.loadGfxState + 1
      return
    end
  elseif st == 4 then
    S.bg1 = nil
  elseif st == 5 then
    bufferRegionMapBg(S.selectedRegion)
    if S.type ~= "normal" then S.bg1 = "frame_fly" end
  elseif st == 6 then
    displayCurrentMapName()
  elseif st == 7 then
    displayCurrentDungeonName()
  elseif st == 8 then
    if S.perms.openAnim then S.bgShown[0], S.bgShown[3] = false, false end
  elseif st >= 9 then
    beginFade(16, 0)
    S.cb2 = "main"
    setTask(S.mainTask)
    S.vblank = true
  end
  S.openState = st + 1
end

local function newState(mode, session)
  local perms = {}
  for k, v in pairs(PERMISSIONS[mode]) do perms[k] = v end
  -- src/region_map.c:1028
  if not RegionMap.isFlagSet("FLAG_SYS_SEVII_MAP_123") then perms.switchButton = false end
  local region = Position.regionFor(mapDef(session.map).regionMapSectionId, RegionExtract.LAYOUTS)
  return {
    type = mode,
    perms = perms,
    selectedRegion = region,
    playersRegion = region,
    mainTask = mode == "fly" and "flyMap" or "regionMap",
    cb2 = "open",
    openState = 0,
    loadGfxState = 0,
    mainState = 0,
    frame = 0,
    gpu = Gpu.new(),
    fade = { active = false, y = 16, bgY = 16, objY = 16, shownBg = 16, shownObj = 16, toggle = 0, pending = false },
    vblank = false,
    bgShown = { [0] = false, [1] = false, [2] = false, [3] = false },
    objOn = false,
    backdropBlue = mode ~= "normal",
    -- src/region_map.c:1112
    palTinted = true,
    cursor = { exists = false, visible = false, spriteX = 0, spriteY = 0, horizontalMove = 0, verticalMove = 0,
      moveCounter = 0, snapId = 0, handler = "input", animStart = 0 },
    player = { exists = false, visible = false },
    icons = { fly = {}, dungeon = {} },
    text = {},
    topBar = { shown = false },
    repeatCounter = KEY_REPEAT_START,
  }
end

local function bagIsOpen()
  local BagMenu = package.loaded["src.ui.game3.bag_menu"]
  return BagMenu and BagMenu.isOpen and BagMenu.isOpen() or false
end

function RegionMap.show(opts)
  opts = opts or {}
  RegionExtract.ensureGenerated()
  if S then Stack.pop("region_map") end
  RegionMap._session = assert(opts.session, "RegionMap.show needs the session")
  RegionMap._onClose = opts.onClose
  RegionMap._onPick = opts.onPick
  -- src/item_use.c:666, :675, src/field_specials.c:185, src/region_map.c:3873
  RegionMap.mode = PERMISSIONS[opts.mode] and opts.mode or "normal"
  RegionMap.previewDungeon = nil
  RegionMap.cursorX, RegionMap.cursorY = 0, 0
  S = newState(RegionMap.mode, RegionMap._session)
  -- src/region_map.c:2819
  S.fromField = RegionMap.mode == "normal" and not bagIsOpen()
  RegionMap.open = true
  PokedexChrome.install()
  Stack.push("region_map", RegionMap, { hideBelow = true })
end

-- src/region_map.c:1320 FreeRegionMap, :4005 FreeFlyMap
function RegionMap.close(picked)
  local wasFly = RegionMap.mode == "fly"
  RegionMap.open = false
  RegionMap.previewDungeon = nil
  RegionMap.mode = "normal"
  S = nil
  Stack.pop("region_map")
  local cb = RegionMap._onClose
  RegionMap._onClose = nil
  RegionMap._onPick = nil
  if cb and not picked then cb(nil) end
  if wasFly and not picked then
    local PartyMenu = package.loaded["src.ui.game3.party_menu"]
    if PartyMenu and PartyMenu.returnFromFlyMap then PartyMenu.returnFromFlyMap() end
  end
end

function RegionMap.isOpen()
  return RegionMap.open
end

function RegionMap.inputReady()
  if not S or S.cb2 ~= "main" or S.task ~= S.mainTask then return false end
  local st = S.mainState
  return (S.mainTask == "regionMap" and st == 3) or (S.mainTask == "flyMap" and st == 4)
end

function RegionMap.state()
  return S
end

-- src/region_map.c:4023 SetFlyWarpDestination
local function finishFly(mapsec)
  local onPick, onClose = RegionMap._onPick, RegionMap._onClose
  RegionMap.close(true)
  if onPick then
    onPick(symOf(mapsec), mapsec)
  elseif onClose then
    onClose(nil)
  end
end

-- src/region_map.c:1342 CB2_RegionMap
function RegionMap.handleInput(input)
  if not S then return end
  S.input = input
  S.frame = S.frame + 1
  -- src/main.c:296 ReadKeys
  if input:wasPressed("start") then
    S.startRepeat = true
    S.repeatCounter = KEY_REPEAT_START
  elseif input.isDown and input:isDown("start") then
    S.repeatCounter = S.repeatCounter - 1
    S.startRepeat = S.repeatCounter == 0
    if S.startRepeat then S.repeatCounter = KEY_REPEAT_CONTINUE end
  else
    S.startRepeat = false
    S.repeatCounter = KEY_REPEAT_START
  end
  if S.cb2 == "open" then
    cb2OpenRegionMap()
    vblank()
    return
  end
  Tasks[S.task]()
  if not S then return end
  if S.finish then
    local f = S.finish
    if f.picked then finishFly(f.mapsec) else RegionMap.close() end
    return
  end
  if S.cursor.exists then spriteCbMapCursor() end
  RegionMap._updateFade()
  vblank()
end

local function drawSprite(name, frame, w, h, cx, cy)
  love.graphics.draw(Gpu.image(name), Gpu.frameQuad(name, frame, w, h), cx - w / 2, cy - h / 2)
end

local function drawObjPrio2()
  for _, icon in ipairs(S.icons.dungeon) do
    if icon.visible then
      love.graphics.draw(Gpu.image(icon.frame == 1 and "dungeon_icon_visited" or "dungeon_icon"), icon.px, icon.py)
    end
  end
  if S.player.exists and S.player.visible then
    local female = (RegionMap._session.gender == 1 or RegionMap._session.gender == "female"
      or RegionMap._session.playerGender == 1)
    love.graphics.draw(Gpu.image(female and "player_leaf" or "player_red"), 8 * RegionMap.playerX + 28, 8 * RegionMap.playerY + 28)
  end
  local flyFrame = RegionMap.flyIconFrame()
  for _, icon in ipairs(S.icons.fly) do
    if icon.visible then drawSprite("fly_icon", flyFrame, 16, 16, 8 * icon.x + 36, 8 * icon.y + 36) end
  end
  if S.cursor.exists and S.cursor.visible then
    drawSprite("cursor", cursorFrame(), 16, 16, S.cursor.spriteX, S.cursor.spriteY)
  end
end

local function drawObjPrio0()
  if S.edges then
    for _, e in ipairs(S.edges) do
      if e.visible then love.graphics.draw(Gpu.image(e.name), e.x - 16, e.y - 32) end
    end
  end
  if S.switch and S.switch.cursors then
    local top = S.switch.highlight[2]
    local frame = switchCursorFrame()
    drawSprite("switch_cursor_left", frame, 32, 32, 88, top + 16)
    drawSprite("switch_cursor_right", frame, 32, 32, 152, top + 16)
  end
end

local function bg1Image()
  if not S.palTinted and S.bg1 == "frame_normal" then return Gpu.image("frame_normal_untinted") end
  return Gpu.image(S.bg1)
end

local function drawBg0()
  local b = S.bg0
  if not b then return end
  love.graphics.draw(Gpu.image(REGION_IMAGES[b.region]), 0, 0)
  if b.switchButton then love.graphics.draw(Gpu.image("switch_button"), 192, 112) end
  if b.navelPatch then love.graphics.draw(Gpu.image("navel_rock_patch"), 104, 88) end
  if b.birthPatch then love.graphics.draw(Gpu.image("birth_island_patch"), 168, 128) end
end

local function drawBg2(alpha)
  local b = S.bg2
  if b.image then
    love.graphics.draw(Gpu.image(b.image), 0, 0)
  else
    love.graphics.draw(require("src.ui.game3.map_preview_screen").image(b.preview), 0, 0)
  end
end

local function textColors(fgIndex)
  return { fg = Gpu.topBarColor(fgIndex), shadow = Gpu.topBarColor(2), bg = { 0, 0, 0, 0 } }
end

local function drawBg3()
  local t = S.text
  -- src/region_map.c:1449
  if t.map then FrlgFont.draw(t.map, 26, 18, { colors = textColors(1) }) end
  -- src/region_map.c:1481, :518-525
  if t.dungeon then
    FrlgFont.draw(t.dungeon, 36, 34, { colors = textColors(t.dungeonType == SECTYPE.VISITED and 7 or 10) })
  end
  local p = S.preview
  if p and p.text then
    -- src/region_map.c:2063-2064
    FrlgFont.draw(p.text.name, 28, 48, { colors = textColors(7) })
    FrlgFont.draw(p.text.desc, 26, 62, { colors = textColors(1), linePitch = 14 })
  end
  if S.topBar.shown then
    if S.type ~= "normal" then
      local c = Gpu.topBarColor(15)
      love.graphics.setColor(c[1], c[2], c[3], 1)
      love.graphics.rectangle("fill", 144, 0, 40, 16)
      love.graphics.rectangle("fill", 192, 0, 40, 16)
      love.graphics.setColor(1, 1, 1, 1)
    end
    if S.topBar.left then PokedexChrome.drawControlInfoLeft(RomText.plain(S.topBar.left), 144, 0) end
    if S.topBar.right then PokedexChrome.drawControlInfoLeft(RomText.plain(S.topBar.right), 192, 0) end
  end
end

function RegionMap.draw()
  if not S then return end
  local Renderer = package.loaded["src.render.Renderer"]
  if Renderer then
    Renderer.worldFadeAlpha = 1
    Renderer.worldFadeColor = { 0, 0, 0 }
  end
  local manifest = Gpu.manifest()
  local backdrop = S.backdropBlue and Gpu.rgb(manifest.backdrop) or { 0, 0, 0, 1 }
  if S.palTinted and S.anim and S.anim.closeState > 0 then Gpu.image("frame_normal_untinted") end
  local layers = {}
  if S.bgShown[1] and S.bg1 then
    layers[#layers + 1] = { bit = Gpu.BG1, draw = function() love.graphics.draw(bg1Image(), 0, 0) end }
  end
  if S.bgShown[0] then layers[#layers + 1] = { bit = Gpu.BG0, draw = drawBg0 } end
  if S.objOn then layers[#layers + 1] = { bit = Gpu.OBJ, obj = true, draw = drawObjPrio2 } end
  if S.bgShown[2] and S.bg2 then layers[#layers + 1] = { bit = Gpu.BG2, tone = S.bg2.tone, draw = drawBg2 } end
  if S.bgShown[3] then layers[#layers + 1] = { bit = Gpu.BG3, draw = drawBg3 } end
  if S.objOn then layers[#layers + 1] = { bit = Gpu.OBJ, obj = true, draw = drawObjPrio0 } end
  love.graphics.push("all")
  Gpu.compose(S.gpu, { bgFade = S.fade.shownBg, objFade = S.fade.shownObj, backdrop = backdrop }, layers)
  love.graphics.pop()
end

return RegionMap
