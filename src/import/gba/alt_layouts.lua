-- pokefirered/src/overworld.c:490

local Versions = require("src.import.gba.versions")

local AltLayouts = {}

-- pokefirered/include/constants/layouts.h:253,267,268,308
AltLayouts.ROWS = {
  { id = 264, map = "SevenIsland_House_Room1", width = 11, height = 9 },
  { id = 278, map = "SeafoamIslands_B3F", width = 38, height = 24 },
  { id = 279, map = "SeafoamIslands_B4F", width = 38, height = 24 },
  { id = 319, map = "ThreeIsland_DunsparceTunnel", width = 30, height = 7 },
}

AltLayouts.KEY_PREFIX = "alt_"

function AltLayouts.key(id)
  return AltLayouts.KEY_PREFIX .. tostring(id)
end

function AltLayouts.layoutOffset(rom, version, id)
  local base = (version and version.g_map_layouts) or Versions.G_MAP_LAYOUTS
  if not base or not id or id < 1 then return nil end
  return rom:ptrOffset(rom:u32(base + (id - 1) * 4))
end

local function read_border(rom, layout)
  local bw = layout.borderWidth or 0
  local bh = layout.borderHeight or 0
  local off = rom:ptrOffset(layout.borderPtr)
  if not off or bw < 1 or bh < 1 or bw > 16 or bh > 16 then
    return { width = 1, height = 1, mids = { 0 } }
  end
  local mids = {}
  for i = 0, bw * bh - 1 do
    mids[i + 1] = rom:u16(off + i * 2) % 1024
  end
  return { width = bw, height = bh, mids = mids }
end

-- pokefirered/src/scrcmd.c:711
function AltLayouts.build(rom, version, grids, borders, padEven)
  local MapTree = require("src.import.gba.map_tree")
  local MapCatalog = require("src.import.gba.map_catalog")
  local Maps = require("src.import.gba.maps")
  local added = {}
  for _, row in ipairs(AltLayouts.ROWS) do
    local ownerId = MapCatalog.resolve(row.map)
    local owner = ownerId and grids and grids[ownerId]
    local layoutOff = AltLayouts.layoutOffset(rom, version, row.id)
    local layout = layoutOff and MapTree.parseLayout(rom, layoutOff)
    local mapOff = layout and rom:ptrOffset(layout.mapPtr)
    if owner and layout and mapOff
      and layout.width == row.width and layout.height == row.height then
      local grid = Maps.loadGrid(rom, {
        offset = mapOff, width = layout.width, height = layout.height,
      })
      grid.map_id = ownerId
      grid.kind = owner.kind
      grid.pair = owner.pair
      grid.environment = owner.environment
      if padEven then grid = padEven(grid) end
      grid.altLayoutId = row.id
      grid.altOwner = ownerId
      local key = AltLayouts.key(row.id)
      grids[key] = grid
      if borders then borders[key] = read_border(rom, layout) end
      added[#added + 1] = key
    end
  end
  return added
end

return AltLayouts
