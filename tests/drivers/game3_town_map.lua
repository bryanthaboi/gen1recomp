local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_town_map"

-- pokefirered/data/maps/PalletTown_RivalsHouse/scripts.inc:144
local ITEM_TOWN_MAP = 361

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS town_map")
    love.event.quit(0)
  else
    print("FAIL town_map failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Bag = require("src.core.game3.bag")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = require("src.core.game3.scripting.space")
  local ItemUse = require("src.core.game3.item_use")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local RegionMap = require("src.ui.game3.region_map")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  for _, name in ipairs({
    "FLAG_WORLD_MAP_PALLET_TOWN", "FLAG_WORLD_MAP_VIRIDIAN_CITY", "FLAG_WORLD_MAP_MT_MOON_1F",
    "FLAG_SYS_SEVII_MAP_123", "FLAG_SYS_SEVII_MAP_4567",
    "FLAG_WORLD_MAP_ONE_ISLAND", "FLAG_WORLD_MAP_FOUR_ISLAND", "FLAG_WORLD_MAP_SEVEN_ISLAND",
  }) do
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, name, true)
  end

  session.bag = session.bag or Bag.new()
  Bag.add(session.bag, ITEM_TOWN_MAP, 1)

  local function state() return RegionMap.state() end
  local function waitFor(cond, max)
    for _ = 1, max or 300 do
      if cond() then return true end
      U.wait(1)
    end
    return cond()
  end
  local function settle() return waitFor(function() return RegionMap.inputReady() end, 400) end

  U.tap(game, "start")
  U.wait(30)
  if not result(StartMenu.isOpen(), "START opened the field menu") then return finish() end
  for _ = 1, 12 do
    local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
    if e and e.id == "bag" then break end
    U.tap(game, "down")
    U.wait(8)
  end
  U.tap(game, "a")
  U.wait(60)
  if not result(BagMenu.isOpen(), "BAG opened") then return finish() end
  for _ = 1, 4 do
    if BagMenu.currentPocket() == "KEY_ITEMS" then break end
    U.tap(game, "right")
    U.wait(15)
  end
  local function selectedName()
    local rows = BagMenu.list()
    local row = rows and rows[BagMenu.cursor]
    return row and tostring(row.name) or nil
  end
  for _ = 1, 20 do
    if selectedName() == "TOWN MAP" then break end
    U.tap(game, "down")
    U.wait(8)
  end
  if not result(selectedName() == "TOWN MAP", "the bag cursor is on TOWN MAP") then return finish() end
  U.tap(game, "a")
  U.wait(25)
  U.tap(game, "a")

  -- src/region_map.c:2462 MoveMapEdgesOutward
  local sliding = waitFor(function()
    local s = state()
    return s and s.anim and s.anim.openState == 6 and s.anim.moveState == 5
  end, 200)
  result(sliding, "the Town Map opens with the map-edge slide")
  U.still(game, DIR .. "/rm_open_anim_mid.png")

  -- src/region_map.c:2438
  local whiteFade = waitFor(function()
    local s = state()
    return s and s.anim and s.anim.openState >= 12
  end, 200)
  result(whiteFade, "the map fades in from white after the slide")
  -- src/region_map.c:2440 SetMapEdgeInvisibility
  local edgesFreed = waitFor(function()
    local s = state()
    if not (s and s.anim and s.anim.openState >= 13) then return false end
    for _, e in ipairs(s.edges or {}) do
      if e.visible then return false end
    end
    return true
  end, 200)
  result(edgesFreed, "the edge sprites are gone once the white fade ends")
  local fadePath = DIR .. "/rm_open_white_fade.png"
  U.still(game, fadePath)
  do
    local f = io.open(fadePath, "rb")
    local bytes = f and f:read("*a")
    if f then f:close() end
    local ok, img = pcall(function()
      return love.image.newImageData(love.filesystem.newFileData(bytes, "rm_open_white_fade.png"))
    end)
    if ok and img then
      local w, h = img:getDimensions()
      local scale = math.floor(math.min(w / 240, h / 160))
      local ox, oy = math.floor((w - 240 * scale) / 2), math.floor((h - 160 * scale) / 2)
      local gx, gy = 7, 134
      local r, g, b = img:getPixel(ox + gx * scale + 1, oy + gy * scale + 1)
      r, g, b = math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
      print(string.format("[driver] frame edge pixel at %d,%d = %d,%d,%d", gx, gy, r, g, b))
      -- src/region_map.c:963 RegionMap_DarkenPalette 95
      result(math.abs(r - 230) <= 6 and math.abs(g - 189) <= 6 and math.abs(b - 41) <= 6,
        string.format("the frame edge is the 95%% tinted yellow (%d,%d,%d ~ 230,189,41)", r, g, b))
    else
      result(false, "read back rm_open_white_fade.png")
    end
  end

  if not result(settle(), "the Town Map reached its input state") then return finish() end
  result(RegionMap.state().fromField == false, "opened from the BAG, so SELECT will not close it")
  result(RegionMap.currentLocationName() == "PALLET TOWN",
    "the Town Map opens on PALLET TOWN, got " .. tostring(RegionMap.currentLocationName()))
  local cursorImg = RegionMap._images["cursor"]
  result(cursorImg and cursorImg:getWidth() == 16 and cursorImg:getHeight() == 32,
    "the cursor sheet holds both 16x16 frames")
  U.still(game, DIR .. "/rm_kanto_town_map.png")

  local function moveTo(x, y)
    for _ = 1, 60 do
      if RegionMap.cursorX == x and RegionMap.cursorY == y then return true end
      if RegionMap.cursorX < x then U.tap(game, "right")
      elseif RegionMap.cursorX > x then U.tap(game, "left")
      elseif RegionMap.cursorY < y then U.tap(game, "down")
      else U.tap(game, "up") end
      U.wait(6)
    end
    return RegionMap.cursorX == x and RegionMap.cursorY == y
  end

  result(moveTo(9, 3), "the cursor walked to MT. MOON")
  U.wait(4)
  result(RegionMap.currentDungeonName() == "MT. MOON", "the dungeon name box reads MT. MOON")
  local _, right = RegionMap.topBarText()
  result(right == "gText_RegionMap_AButtonGuide", "a visited dungeon offers A GUIDE")
  U.still(game, DIR .. "/rm_name_box_mt_moon.png")

  U.tap(game, "a")
  local growing = waitFor(function()
    local s = state()
    return s and s.preview and s.preview.updateCounter == 4
  end, 60)
  result(growing, "A opened the GUIDE window")
  U.still(game, DIR .. "/rm_guide_growing.png")
  local texted = waitFor(function()
    local s = state()
    return s and s.preview and s.preview.text ~= nil
  end, 200)
  result(texted, "the GUIDE printed its text after the sepia tint")
  U.still(game, DIR .. "/rm_guide_text.png")
  U.tap(game, "b")
  local shrinking = waitFor(function()
    local s = state()
    return s and s.preview and s.preview.mainState == 8 and s.preview.updateCounter == 4
  end, 60)
  result(shrinking, "B shrinks the GUIDE window")
  U.still(game, DIR .. "/rm_guide_shrinking.png")
  settle()
  result(RegionMap.previewDungeon == nil, "the GUIDE closed")

  -- src/region_map.c:2862 SnapToIconOrButton
  U.tap(game, "start")
  U.wait(4)
  result(RegionMap.cursorX == 21 and RegionMap.cursorY == 11, "START snapped to the SWITCH button")
  U.tap(game, "a")
  local menu = waitFor(function()
    local s = state()
    return s and s.switch and s.switch.mainState == 9
  end, 120)
  result(menu, "A on SWITCH opened the switch menu")
  result(state().switch and state().switch.maxSelection == 3, "FLAG_SYS_SEVII_MAP_4567 offers all four maps")
  U.still(game, DIR .. "/rm_switch_menu.png")
  U.tap(game, "down")
  U.wait(4)
  U.still(game, DIR .. "/rm_switch_menu_sevii123.png")
  U.tap(game, "a")
  waitFor(function() return state() and state().switch == nil end, 120)
  settle()
  result(state().selectedRegion == 1, "the map switched to SEVII 1-2-3")
  U.still(game, DIR .. "/rm_sevii123_switched.png")

  result(state().palTinted == true, "the open Town Map draws bank 2 at 95%")
  U.tap(game, "b")
  -- src/region_map.c:2572
  local untinted = waitFor(function()
    local s = state()
    return s and s.anim and s.anim.closeState == 5 and s.anim.blendY == 1
  end, 120)
  result(untinted and state().palTinted == false, "close state 2 reloads sRegionMap_Pal untinted")
  U.still(game, DIR .. "/rm_close_untinted.png")
  local closing = waitFor(function()
    local s = state()
    return s and s.anim and s.anim.closeState == 7 and s.anim.moveState == 6
  end, 120)
  result(closing, "B runs the map-edge close slide")
  U.still(game, DIR .. "/rm_close_anim_mid.png")
  waitFor(function() return not RegionMap.isOpen() end, 200)
  result(not RegionMap.isOpen(), "B closed the Town Map")
  for _ = 1, 20 do
    if not BagMenu.isOpen() then break end
    U.tap(game, "b")
    U.wait(10)
  end
  U.wait(30)

  local function goTo(mapId, x, y)
    Map.load(nil, game, mapId, { x = x, y = y, facing = "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    U.wait(120)
  end

  local function openFromField(label)
    ItemUse.useField(session, session.bag, ITEM_TOWN_MAP, nil)
    return result(settle(), label)
  end

  -- src/region_map.c:1028-1049
  local sevii = {
    { map = "FR_FOUR_ISLAND", x = 12, y = 14, region = 2, name = "FOUR ISLAND", shot = "rm_four_island_sevii45.png" },
    { map = "SEVII_ONE_ISLAND", x = 12, y = 12, region = 1, name = "ONE ISLAND", shot = "rm_one_island_sevii123.png" },
    { map = "FR_SEVEN_ISLAND", x = 10, y = 10, region = 3, name = "SEVEN ISLAND", shot = "rm_seven_island_sevii67.png" },
  }
  for i, case in ipairs(sevii) do
    goTo(case.map, case.x, case.y)
    if openFromField("the Town Map opened on " .. case.map) then
      result(state().selectedRegion == case.region,
        case.map .. " opens the Sevii map " .. case.region .. ", got " .. tostring(state().selectedRegion))
      result(RegionMap.currentLocationName() == case.name,
        "the cursor starts on " .. case.name .. ", got " .. tostring(RegionMap.currentLocationName()))
      U.still(game, DIR .. "/" .. case.shot)
      if i == 1 then
        result(state().fromField == true, "opened from the field")
        U.tap(game, "select")
      else
        U.tap(game, "b")
      end
      waitFor(function() return not RegionMap.isOpen() end, 200)
      result(not RegionMap.isOpen(), (i == 1 and "SELECT" or "B") .. " closed the field Town Map")
      U.wait(20)
    end
  end

  finish()
end
