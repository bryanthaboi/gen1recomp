#!/usr/bin/env luajit
-- ../pokefirered/src/region_map.c:1239-1246, :1266

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function eq(a, b, msg)
  if a == b then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print(string.format("[FAIL] %s (%s ~= %s)", msg, tostring(a), tostring(b)))
  end
end

package.loaded["src.core.game3.audio"] = {
  playCry = function() end,
  playSe = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local RegionExtract = require("src.import.gba.region_map_extract")
local RegionMap = require("src.ui.game3.region_map")
local PokedexChrome = require("src.ui.game3.pokedex_chrome")
local Strings = require("src.core.Strings")

local GUIDE = Strings("{A_BUTTON}GUIDE")
local SECTYPE = RegionMap.MAPSECTYPE

local MT_MOON_X, MT_MOON_Y = 9, 3
local MT_MOON_FLAG = "FLAG_WORLD_MAP_MT_MOON_1F"

local function press(btn)
  RegionMap.handleInput({
    wasPressed = function(_, k) return k == btn end,
    isDown = function() return false end,
  })
end

local function openAt(session, x, y, mode)
  RegionMap.show({ session = session, mode = mode })
  RegionMap.cursorX, RegionMap.cursorY = x, y
  return session
end

print("[test] 1. A fresh save cannot open the GUIDE for any dungeon")
do
  local session = { map = "PALLET_TOWN", gender = 0, flags = {} }
  openAt(session, MT_MOON_X, MT_MOON_Y)
  eq(RegionMap.currentDungeonSec(), "MAPSEC_MT_MOON", "cursor is over MT. MOON")
  press("a")
  eq(RegionMap.previewDungeon, nil, "A opens no preview")
  eq(RegionMap.isOpen(), true, "the map stays open")
  eq(RegionMap.selectedDungeonMapsecType(), SECTYPE.NOT_VISITED, "MT. MOON is NOT_VISITED")
  eq(RegionMap.canGuideCursor(), false, "the GUIDE is refused")

  local refused, total = 0, 0
  RegionExtract.ensureGenerated()
  for y, row in pairs(RegionExtract.DUNGEON_GRID) do
    for x in pairs(row) do
      RegionMap.cursorX, RegionMap.cursorY = x, y
      total = total + 1
      press("a")
      if RegionMap.previewDungeon == nil then refused = refused + 1 else press("b") end
    end
  end
  eq(total > 0, true, "the dungeon layer has cells to walk")
  eq(refused, total, "every dungeon cell refuses the GUIDE on a fresh save")
  RegionMap.close()
end

print("[test] 2. The world map flag the map's ON_TRANSITION sets opens the GUIDE")
do
  -- ../pokefirered/data/maps/MtMoon_1F/scripts.inc:6
  local session = { map = "PALLET_TOWN", gender = 0, flags = { [MT_MOON_FLAG] = true } }
  openAt(session, MT_MOON_X, MT_MOON_Y)
  eq(RegionMap.selectedDungeonMapsecType(), SECTYPE.VISITED, "MT. MOON is VISITED")
  eq(RegionMap.canGuideCursor(), true, "the GUIDE is offered")
  press("a")
  eq(RegionMap.previewDungeon, "MAPSEC_MT_MOON", "A opens the MT. MOON preview")
  press("b")
  eq(RegionMap.previewDungeon, nil, "B closes the preview")
  RegionMap.close()
end

print("[test] 3. The fly map has no preview permission")
do
  -- ../pokefirered/src/region_map.c:611-616
  local session = { map = "PALLET_TOWN", gender = 0, flags = { [MT_MOON_FLAG] = true } }
  openAt(session, MT_MOON_X, MT_MOON_Y, "fly")
  eq(RegionMap.selectedDungeonMapsecType(), SECTYPE.VISITED, "MT. MOON is still VISITED")
  eq(RegionMap.canGuideCursor(), false, "the fly map refuses the GUIDE")
  press("a")
  eq(RegionMap.previewDungeon, nil, "A opens no preview on the fly map")
  if RegionMap.isOpen() then RegionMap.close() end
end

print("[test] 4. The top bar prints the GUIDE prompt only for a visited dungeon")
do
  local realLove = love
  love = {
    graphics = {
      setColor = function() end,
      rectangle = function() end,
      circle = function() end,
      draw = function() end,
      getScissor = function() return nil end,
      setScissor = function() end,
    },
  }
  local realPrompt = PokedexChrome.drawControlInfoLeft
  local prompts = {}
  PokedexChrome.drawControlInfoLeft = function(text) prompts[#prompts + 1] = tostring(text) end

  local function topBar(session)
    prompts = {}
    openAt(session, MT_MOON_X, MT_MOON_Y)
    RegionMap.draw()
    RegionMap.close()
    return table.concat(prompts, "|")
  end

  local off = topBar({ map = "PALLET_TOWN", gender = 0, flags = {} })
  local on = topBar({ map = "PALLET_TOWN", gender = 0, flags = { [MT_MOON_FLAG] = true } })

  PokedexChrome.drawControlInfoLeft = realPrompt
  love = realLove

  eq(off:find(GUIDE, 1, true), nil, "no GUIDE prompt over an unvisited MT. MOON")
  eq(on:find(GUIDE, 1, true) ~= nil, true, "the GUIDE prompt is drawn over a visited MT. MOON")
end

print("[test] 5. The wall Town Map has no preview and no switch button")
do
  -- ../pokefirered/src/field_specials.c:185, src/region_map.c:603-608
  local session = {
    map = "PALLET_TOWN", gender = 0,
    flags = { [MT_MOON_FLAG] = true, FLAG_SYS_SEVII_MAP_123 = true },
  }
  openAt(session, MT_MOON_X, MT_MOON_Y, "wall")
  eq(RegionMap.mode, "wall", "show({ mode = wall }) selects REGIONMAP_TYPE_WALL")
  eq(RegionMap.selectedDungeonMapsecType(), SECTYPE.VISITED, "MT. MOON is still VISITED")
  eq(RegionMap.permission("mapPreview"), false, "the wall map has no MAPPERM_HAS_MAP_PREVIEW")
  eq(RegionMap.permission("openAnim"), false, "the wall map has no MAPPERM_HAS_OPEN_ANIM")
  eq(RegionMap.hasSwitchButton(), false, "the wall map has no MAPPERM_HAS_SWITCH_BUTTON")
  eq(RegionMap.canGuideCursor(), false, "the wall map refuses the GUIDE")
  press("a")
  eq(RegionMap.previewDungeon, nil, "A opens no preview on the wall map")
  eq(RegionMap.isOpen(), true, "the wall map stays open")
  RegionMap.close()

  openAt(session, MT_MOON_X, MT_MOON_Y)
  eq(RegionMap.permission("mapPreview"), true, "the item Town Map keeps MAPPERM_HAS_MAP_PREVIEW")
  eq(RegionMap.canGuideCursor(), true, "and still offers the GUIDE")
  RegionMap.close()

  openAt(session, MT_MOON_X, MT_MOON_Y, "nonsense")
  eq(RegionMap.mode, "normal", "an unknown mode falls back to REGIONMAP_TYPE_NORMAL")
  RegionMap.close()
end

print("[test] 6. The switch button waits for the Sevii map")
do
  -- ../pokefirered/src/region_map.c:1028-1029
  local SWITCH_X, SWITCH_Y = 21, 11
  local SWITCH = Strings("{A_BUTTON}SWITCH")
  local realLove = love
  love = {
    graphics = {
      setColor = function() end,
      rectangle = function() end,
      circle = function() end,
      draw = function() end,
      getScissor = function() return nil end,
      setScissor = function() end,
    },
  }
  local realPrompt = PokedexChrome.drawControlInfoLeft
  local prompts = {}
  PokedexChrome.drawControlInfoLeft = function(text) prompts[#prompts + 1] = tostring(text) end

  local function switchPrompt(session)
    prompts = {}
    openAt(session, SWITCH_X, SWITCH_Y)
    local allowed = RegionMap.hasSwitchButton()
    RegionMap.draw()
    RegionMap.close()
    return allowed, table.concat(prompts, "|")
  end

  local offAllowed, off = switchPrompt({ map = "PALLET_TOWN", gender = 0, flags = {} })
  local onAllowed, on = switchPrompt({
    map = "PALLET_TOWN", gender = 0, flags = { FLAG_SYS_SEVII_MAP_123 = true },
  })

  PokedexChrome.drawControlInfoLeft = realPrompt
  love = realLove

  eq(offAllowed, false, "no switch button before FLAG_SYS_SEVII_MAP_123")
  eq(off:find(SWITCH, 1, true), nil, "and no SWITCH prompt on the top bar")
  eq(onAllowed, true, "the flag turns the switch button on")
  eq(on:find(SWITCH, 1, true) ~= nil, true, "and the SWITCH prompt is drawn")
end

if failed > 0 then
  print(string.format("\n[FAILED] %d check(s) failed", failed))
  os.exit(1)
end
print("\n[test] all passed")
