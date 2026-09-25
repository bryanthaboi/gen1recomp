-- home/overworld.asm:1809
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local MapContext = require("src.save_convert.MapContext")
local GenSave = require("src.save_convert.GenSave")

local O = MapContext.OFFSETS
local SAVE = GenSave.OFFSETS
local stampMapWindow = loadfile("tests/fixture_data/map_window.lua")()

GenSave.setCharmap(loadfile("src/save_convert/data/charmap.lua")())

local GRASS = {}
for i = 1, 10 do
  GRASS[i] = { level = 2 + i, species = (i % 2 == 1) and "FIXMON_A" or "FIXMON_C" }
end
local WATER = {}
for i = 1, 10 do WATER[i] = { level = 20 + i, species = "FIXMON_B" } end

local function fixtureData()
  local maps = {}
  for id, map in pairs(dofile("tests/fixture_data/maps.lua")) do
    local copy = {}
    for k, v in pairs(map) do copy[k] = v end
    maps[id] = copy
  end
  local data = {
    maps = maps,
    pokemon = dofile("tests/fixture_data/pokemon.lua"),
    moves = dofile("tests/fixture_data/moves.lua"),
    items = dofile("tests/fixture_data/items.lua"),
    encounters = {
      FIX_TOWN = { grass = { rate = 25, slots = GRASS }, water = { rate = 5, slots = WATER } },
    },
  }
  data = stampMapWindow(data, "FIX_TOWN")
  data.maps.FIX_TOWN.sram.objects = {
    0x0E, 0, 0,
    1, 0x01, 0x14, 0x15, 0xFF, 0xD0, 0x05,
  }
  return data
end

local data = fixtureData()

local function newSave(x, y)
  return {
    player = { name = "RED", rival = "BLUE", map = "FIX_TOWN", x = x, y = y },
    money = 3000, inventory = {}, pokedex = { seen = {}, owned = {} },
    flags = {}, party = {}, boxes = {},
  }
end

local function mainByte(bytes, off) return bytes:byte(SAVE.mainData + off + 1) end

do
  local ctx = assert(MapContext.build(data, "FIX_TOWN", 7, 4))
  T.eq(ctx.writes[O.grassRate][1], 25, "wGrassRate is the map's grass rate")
  T.eq(#ctx.writes[O.grassMons], 20, "wGrassMons is 10 level/species rows")
  T.eq(ctx.writes[O.grassMons][1], 3, "grass slot 1 level")
  T.eq(ctx.writes[O.grassMons][2], 1, "grass slot 1 species index")
  T.eq(ctx.writes[O.grassMons][4], 3, "grass slot 2 species index")
  T.eq(ctx.writes[O.waterRate][1], 5, "wWaterRate is the map's water rate")
  T.eq(ctx.writes[O.waterMons][1], 21, "water slot 1 level")
  T.eq(ctx.writes[O.waterMons][2], 2, "water slot 1 species index")
  T.eq(O.grassRate, 0xD886 - 0xD2F6, "wGrassRate offset matches the Yellow sym")
  T.eq(O.waterMons, 0xD8A4 - 0xD2F6, "wWaterMons offset matches the Yellow sym")
  T.eq(O.grassRate, 0xD887 - 0xD2F7, "wGrassRate offset matches the Red sym")
  T.eq(O.waterMons, 0xD8A5 - 0xD2F7, "wWaterMons offset matches the Red sym")
end

do
  local d = fixtureData()
  d.encounters = {}
  local ctx = assert(MapContext.build(d, "FIX_TOWN", 7, 4))
  T.eq(ctx.writes[O.grassRate][1], 0, "a map with no wild data writes grass rate 0")
  T.eq(ctx.writes[O.waterRate][1], 0, "a map with no wild data writes water rate 0")
  T.eq(ctx.writes[O.grassMons], nil, "no grass rows when the rate is 0")
  d.encounters = nil
  local none, why = MapContext.build(d, "FIX_TOWN", 7, 4)
  T.eq(none, nil, "a data set with no encounter table refuses the build")
  T.eq(type(why) == "string" and why:find("re%-import") ~= nil, true, "and says to re-import the ROM")
end

do
  local fresh = GenSave.encode(newSave(7, 4), data, nil)
  T.eq(mainByte(fresh, O.grassRate), 25, "a templateless export carries the grass rate")
  T.eq(mainByte(fresh, O.grassMons + 1), 1, "a templateless export carries the grass mons")
  T.eq(mainByte(fresh, O.waterRate), 5, "a templateless export carries the water rate")
  T.eq(GenSave.mainChecksumValid(fresh), true, "wild data sits inside a valid checksum")

  local tpl = {}
  for i = 1, #fresh do tpl[i] = fresh:sub(i, i) end
  tpl[SAVE.spriteData + 17] = string.char(0x77)
  tpl[SAVE.mainData + O.grassRate + 1] = string.char(0x44)
  local template = table.concat(tpl)

  local same = GenSave.encode(newSave(7, 4), data, template)
  T.eq(same:byte(SAVE.spriteData + 17), 0x77, "an unmoved template keeps its live sprite window")
  T.eq(mainByte(same, O.grassRate), 0x44, "an unmoved template keeps its own wild data")

  local moved = GenSave.encode(newSave(9, 6), data, template)
  local ctx = assert(MapContext.build(data, "FIX_TOWN", 9, 6))
  local view = ctx.writes[O.viewPointer]
  T.eq(mainByte(moved, O.yCoord), 6, "moved export writes the new y")
  T.eq(mainByte(moved, O.xCoord), 9, "moved export writes the new x")
  T.eq(mainByte(moved, O.viewPointer), view[1], "moved export rebuilds the view pointer (lo)")
  T.eq(mainByte(moved, O.viewPointer + 1), view[2], "moved export rebuilds the view pointer (hi)")
  T.eq(mainByte(moved, O.yBlockCoord), 0, "moved export rebuilds wYBlockCoord")
  T.eq(mainByte(moved, O.xBlockCoord), 1, "moved export rebuilds wXBlockCoord")
  for i = 1, 512 do
    if moved:byte(SAVE.spriteData + i) ~= ctx.spriteData[i] then
      T.eq(moved:byte(SAVE.spriteData + i), ctx.spriteData[i], ("moved export sprite byte %d"):format(i))
      break
    end
  end
  T.eq(moved:byte(SAVE.spriteData + 17), ctx.spriteData[17], "moved export drops the stale sprite window")
  T.eq(mainByte(moved, O.grassRate), 25, "moved export reloads the grass rate")
  T.eq(GenSave.mainChecksumValid(moved), true, "moved export checksum is valid")

  local frac = GenSave.encode(newSave(7.4, 4.9), data, template)
  T.eq(frac:byte(SAVE.spriteData + 17), 0x77, "fractional coords floor onto the template's own spot")
  T.eq(mainByte(frac, O.yCoord), 4, "fractional y floors")
  T.eq(mainByte(frac, O.xCoord), 7, "fractional x floors")
  local movedX = GenSave.encode(newSave(8, 4), data, template)
  T.eq(mainByte(movedX, O.xBlockCoord), 0, "an x-only move rebuilds the window too")
end

T.finish("save_export_same_map_moved_2468")
