-- #1479 / #1449: TILESET_KANTO takes no map-group roof (home/map.asm:1738-1749)
--   luajit tests/engine/gen2_kanto_no_roof_bug1479.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local MapPreview = require("src.world.gen2.MapPreview")

local baker = {
  tilesets = {
    TILESET_KANTO = { image = "assets/generated/tilesets/kanto.png" },
    TILESET_JOHTO = { image = "assets/generated/tilesets/johto.png" },
  },
  roofs = {
    mapGroupRoofs = { [19] = "ROOF_SILVER" },
    roofs = { ROOF_SILVER = {} },
  },
  atlasCache = {},
  mapImages = {},
}

-- data/maps/maps.asm:396: SilverCaveOutside and Route28 are both group 19
-- (MapGroup_Silver) and both TILESET_KANTO.
MapPreview.atlasFor(baker, { tileset = "TILESET_KANTO", group = 19 })
MapPreview.atlasFor(baker, { tileset = "TILESET_JOHTO", group = 19 })

local keys = {}
for key in pairs(baker.atlasCache) do keys[key] = true end

T.check(keys["TILESET_KANTO"],
  "the Kanto atlas is cached under the bare tileset, with no roof")
T.check(not keys["TILESET_KANTO|ROOF_SILVER"],
  "and never under a map-group roof")
T.check(keys["TILESET_JOHTO|ROOF_SILVER"],
  "while TILESET_JOHTO still takes its group's roof")

-- World:atlasFor is the copy the bug was filed against; it has its own
-- ROOF_TILESETS gate, so pin it separately from MapPreview's
local realAssets = package.loaded["src.render.Assets"]
package.loaded["src.render.Assets"] = setmetatable({
  image = function() return { setFilter = function() end } end,
  resolve = function(path) return path end,
}, { __index = realAssets or { register = function() end } })
package.loaded["src.world.gen2.World"] = nil
local World = require("src.world.gen2.World")
local world = setmetatable({
  tilesets = baker.tilesets,
  roofs = baker.roofs,
  atlasCache = {},
}, { __index = World })
world:atlasFor({ tileset = "TILESET_KANTO", group = 19 })
world:atlasFor({ tileset = "TILESET_JOHTO", group = 19 })
T.check(world.atlasCache["TILESET_KANTO"] ~= nil
        and world.atlasCache["TILESET_KANTO|ROOF_SILVER"] == nil,
  "World:atlasFor bakes Kanto with no map-group roof (home/map.asm:1738-1749)")
T.check(world.atlasCache["TILESET_JOHTO|ROOF_SILVER"] ~= nil,
  "and still roofs TILESET_JOHTO by group")
package.loaded["src.render.Assets"] = realAssets
package.loaded["src.world.gen2.World"] = nil

T.finish("gen2 Kanto roof gate (#1479)")
