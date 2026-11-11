package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Loader = require("src.mods.Loader")
local Version = require("src.core.GameVersion")
local Versions = require("src.import.gba.versions")
local Profile = require("src.core.game3.profile")
local LayoutNative = require("src.core.game3.layout_native")
local NativePack = require("src.import.gba.native_pack")
local Dataset = require("src.core.game3.dataset")
local Interaction = require("src.core.game3.scripting.interaction_scripts")
local UnifiedContent = require("src.mods.UnifiedContent")

local PAIR = "p_test"
local savedBehaviors = Interaction.behaviors
local defined = {}
for mid = 0, 15 do defined[mid] = 0 end
for mid = 640, 650 do defined[mid] = 0 end
Interaction.behaviors = { [PAIR] = defined }

local function select(version)
  Version.set(version)
  Versions.select(version)
  Profile.reset()
end

local function blob(w, h, mid, elev)
  local cells = {}
  for i = 1, w * h do cells[i] = { mid = mid, coll = 0, elev = elev } end
  return NativePack.encodeMidLayout({ width = w, height = h, borderWidth = 1, borderHeight = 1,
    borderMids = { 1 }, cells = cells })
end

local function def(id, w, h, extra)
  local out = { id = id, name = id, width = w, height = h, pair = PAIR, kind = "town",
    warps = {}, connections = {}, weather = 0, mapType = 0 }
  for k, v in pairs(extra or {}) do out[k] = v end
  return out
end

local function dataset(prefix)
  prefix = prefix or "FR_"
  local data = T.sdk.gen3Data()
  data.maps = {
    [prefix .. "OAKS_LAB"] = def(prefix .. "OAKS_LAB", 13, 12),
    [prefix .. "PALLET_TOWN"] = def(prefix .. "PALLET_TOWN", 24, 20,
      { connections = { { dir = "north", map = prefix .. "ROUTE_1", offset = 0 } } }),
    [prefix .. "ROUTE_1"] = def(prefix .. "ROUTE_1", 24, 40,
      { connections = { { dir = "south", map = prefix .. "PALLET_TOWN", offset = 0 } } }),
    [prefix .. "CENTER_A"] = def(prefix .. "CENTER_A", 14, 10),
    [prefix .. "CENTER_B"] = def(prefix .. "CENTER_B", 14, 10),
  }
  local blobs = {
    [prefix .. "OAKS_LAB"] = blob(13, 12, 1, 3),
    [prefix .. "PALLET_TOWN"] = blob(24, 20, 2, 3),
    [prefix .. "ROUTE_1"] = blob(24, 40, 2, 3),
  }
  local shared = blob(14, 10, 4, 3)
  blobs[prefix .. "CENTER_A"], blobs[prefix .. "CENTER_B"] = shared, shared
  local cache = { read = function(_, rel)
    return blobs[rel:match("layouts/(.-)%.mid$") or ""]
  end }
  Dataset.attachMidLayouts(data.maps, cache)
  return data
end

local function manifest(id, api)
  return ('{"id":"%s","name":"%s","version":"1.0.0","api":%d,"games":["all"],"entry":"main.lua"}')
    :format(id, id, api or 2)
end

local function load(version, mods, data)
  select(version)
  T.sdk.captureRuntime()
  local files = {}
  for _, m in ipairs(mods) do
    files["mods/" .. m.id .. "/manifest.json"] = manifest(m.id, m.api)
    files["mods/" .. m.id .. "/main.lua"] = m.body
  end
  local loader = Loader.new({ fs = T.sdk.memfs(files), generation = 3, version = version, dev = true })
  local ok, err = pcall(loader.load, loader, data)
  T.sdk.restoreRuntime()
  T.check(ok, "loader runs: " .. tostring(err))
  return loader
end

local function errorsOf(loader)
  return table.concat(loader.errors or {}, "\n")
end

local function hasError(loader, text, label)
  T.check(errorsOf(loader):find(text, 1, true) ~= nil, label .. " (" .. text .. ")")
end

do
  local data = dataset()
  local lab = data.maps.FR_OAKS_LAB
  local loader = load("firered", { { id = "paint", body = [[
local mod = ...
mod.content.maps:patch("FR_OAKS_LAB", { cells = {
  { x = 2, y = 3, metatile = 5 },
  { x = 4, y = 3, metatile = 645, collision = 1 },
  { x = 6, y = 3, metatile = 6, elevation = 7 },
} })
]] } }, data)
  T.eq(errorsOf(loader), "", "a cells patch merges clean")
  T.check(data.maps.FR_OAKS_LAB == lab, "the vanilla def table keeps its identity")
  local layout = lab.midLayout
  T.check(getmetatable(layout) == LayoutNative, "the patched layout is a LayoutNative")
  T.eq(layout:midAt(2, 3), 5, "a patched cell reads the new metatile")
  T.eq(layout:midAt(3, 3), 1, "an untouched cell keeps the vanilla metatile")
  T.eq(layout:elevAt(2, 3), 3, "an omitted elevation keeps the cell's own")
  T.eq(layout:elevAt(6, 3), 7, "an explicit elevation is written")
  T.eq(layout:collAt(2, 3), 0, "an omitted collision is passable")
  T.eq(layout:collAt(4, 3), 7, "collision 1 is the impassable class")
  T.eq(layout:midAt(4, 3), 645, "a secondary metatile is written")
  T.check(layout:workerPacked() == nil, "a mod layout takes the sampled snapshot path")
  T.eq(layout:collArray()[3 * 13 + 4 + 1], 7, "the collision grid sees the patched cell")
  layout:applyOverride(2, 3, 9, 0, 0)
  T.eq(layout:midAt(2, 3), 9, "a runtime setmetatile layers over the patch")
  layout:clearOverrides()
  T.eq(layout:midAt(2, 3), 5, "clearing runtime overrides restores the patched base")
  local record = loader.content.maps:get("FR_OAKS_LAB")
  T.check(record ~= nil and record.midLayout == nil, "the registry record carries no live layout")
  T.eq(record and record.pair, PAIR, "maps:get exposes the tileset pair")
end

do
  local data = dataset()
  local loader = load("firered", {
    { id = "a_first", body = [[
local mod = ...
mod.content.maps:patch("FR_OAKS_LAB", { cells = { { x = 1, y = 1, metatile = 5 }, { x = 2, y = 2, metatile = 6 } } })
]] },
    { id = "b_second", body = [[
local mod = ...
mod.content.maps:patch("FR_OAKS_LAB", { cells = { { x = 2, y = 2, metatile = 7 }, { x = 3, y = 3, metatile = 8 } } })
]] },
    { id = "c_broken", body = [[
local mod = ...
mod.content.maps:patch("FR_OAKS_LAB", { cells = { { x = 5, y = 5, metatile = 9 } } })
error("boom")
]] },
  }, data)
  local layout = data.maps.FR_OAKS_LAB.midLayout
  T.eq(layout:midAt(1, 1), 5, "the first mod's cell lands")
  T.eq(layout:midAt(3, 3), 8, "the second mod's cell lands")
  T.eq(layout:midAt(2, 2), 7, "the later mod wins a shared cell")
  T.eq(layout:midAt(5, 5), 1, "a failed mod's cells roll back")
  T.check(loader.mods.c_broken.state ~= "loaded", "the broken mod is not loaded")
end

do
  local data = dataset()
  local loader = load("firered", { { id = "cave", body = [[
local mod = ...
local pair = mod.content.maps:get("FR_OAKS_LAB").pair
local blocks = {}
for i = 1, 12 do blocks[i] = 2 end
blocks[1] = 5 + 1024
blocks[2] = { metatile = 6, collision = 1, elevation = 4 }
blocks[3] = 7 + 3 * 4096
mod.content.maps:register("FR_MOD_CAVE", { width = 4, height = 3, pair = pair, blocks = blocks,
  border = { 8 }, mapType = 4, warps = { { x = 3, y = 2, destMap = "FR_OAKS_LAB", destWarp = 1 } } })
]] } }, data)
  T.eq(errorsOf(loader), "", "a new map registers clean")
  local cave = data.maps.FR_MOD_CAVE
  T.check(cave ~= nil, "the new map lands in data.maps")
  local layout = require("src.core.game3.map").ensureMidLayout({ data = data }, "FR_MOD_CAVE", cave)
  T.check(getmetatable(layout) == LayoutNative, "the new map has a layout")
  T.eq(cave.width, 4, "width comes from the record")
  T.eq(cave.height, 3, "height comes from the record")
  T.eq(cave.pair, PAIR, "pair comes from the record")
  T.eq(cave.kind, "indoor", "map type 4 builds an indoor map")
  T.eq(layout:midAt(0, 0), 5, "a raw word's metatile")
  T.eq(layout:collAt(0, 0), 7, "a raw word's collision bits")
  T.eq(layout:midAt(1, 0), 6, "a record block's metatile")
  T.eq(layout:collAt(1, 0), 7, "a record block's collision")
  T.eq(layout:elevAt(1, 0), 4, "a record block's elevation")
  T.eq(layout:elevAt(2, 0), 3, "a raw word's elevation bits")
  T.eq(layout:collAt(3, 1), 0, "a plain block is passable")
  T.eq(layout:midAt(-1, -1), 8, "the border comes from the record")
  T.eq(layout:collAt(-1, -1), 0xff, "the border is impassable")
  T.eq(#cave.warps, 1, "the warps come from the record")
end

do
  local data = dataset()
  local loader = load("firered", { { id = "bad", body = [[
local mod = ...
mod.content.maps:register("FR_BAD_PAIR", { width = 1, height = 1, pair = "nope", blocks = { 1 } })
mod.content.maps:register("BAD_PREFIX", { width = 1, height = 1, pair = "p_test", blocks = { 1 } })
mod.content.maps:patch("FR_OAKS_LAB", { cells = { { x = 13, y = 0, metatile = 1 }, { x = 0, y = 0, metatile = 300 } } })
mod.content.maps:register("FR_BAD_BLOCK", { width = 1, height = 1, pair = "p_test", blocks = { 300 } })
mod.content.maps:patch("FR_PALLET_TOWN", { blocks = { 1, 2, 3 } })
mod.content.maps:patch("FR_ROUTE_1", { border = { 1, 2, 3 } })
mod.content.maps:patch("FR_CENTER_A", { border = { 300 } })
mod.content.maps:register("FR_BAD_WARP", { width = 2, height = 2, pair = "p_test", blocks = { 1, 1, 1, 1 },
  warps = { { x = 5, y = 0, destMap = "FR_OAKS_LAB", destWarp = 1 } } })
]] } }, data)
  hasError(loader, 'bad: maps.FR_BAD_PAIR: unknown tileset pair "nope"', "an unknown pair is refused")
  hasError(loader, "bad: maps.BAD_PREFIX: new map ids on", "an unprefixed new id is refused")
  hasError(loader, "bad: maps.FR_OAKS_LAB.cells[1]: (13,0) is outside the 13x12 grid", "an off-grid cell is refused")
  hasError(loader, "bad: maps.FR_OAKS_LAB.cells[2]: metatile 300 is not defined by tileset pair p_test",
    "an undefined cell metatile is refused")
  hasError(loader, "bad: maps.FR_BAD_BLOCK.blocks[1]: metatile 300 is not defined", "an undefined block metatile is refused")
  hasError(loader, "bad: maps.FR_PALLET_TOWN: blocks has 3 entries, expected width*height = 480", "a short grid is refused")
  hasError(loader, "bad: maps.FR_ROUTE_1.border: 3 entries, expected borderWidth*borderHeight = 1", "a short border is refused")
  hasError(loader, "bad: maps.FR_CENTER_A.border[1]: metatile 300 is not defined", "an undefined border metatile is refused")
  hasError(loader, "bad: maps.FR_BAD_WARP.warps[1]: (5,0) is outside the 2x2 grid", "an off-grid warp is refused")
  T.check(data.maps.FR_BAD_PAIR == nil and data.maps.BAD_PREFIX == nil, "refused new maps are not written")
  T.eq(data.maps.FR_OAKS_LAB.midLayout:midAt(0, 0), 1, "a refused patch leaves the vanilla grid")
  T.eq(data.maps.FR_PALLET_TOWN.midLayout:midAt(0, 0), 2, "a refused grid leaves the vanilla layout")

  local strict = load("firered", { { id = "nopair", body = [[
local mod = ...
mod.content.maps:register("FR_NO_PAIR", { width = 1, height = 1, blocks = { 1 } })
]] } }, dataset())
  T.check(strict.mods.nopair.state ~= "loaded"
    and tostring(strict.mods.nopair.error or errorsOf(strict)):find("needs pair", 1, true) ~= nil,
    "a grid without a pair is refused at register")

  local rse = dataset("EM_")
  local emerald = load("emerald", { { id = "hoenn", body = [[
local mod = ...
mod.content.maps:patch("EM_OAKS_LAB", { border = { 1 }, borderWidth = 1, borderHeight = 1 })
mod.content.maps:register("EM_MOD_ROOM", { width = 1, height = 1, pair = "p_test", blocks = { 1 } })
]] } }, rse)
  hasError(emerald, "hoenn: maps.EM_OAKS_LAB.border: border is 2x2 on", "an R/S/E border must be 2x2")
  local room = rse.maps.EM_MOD_ROOM
  T.check(room ~= nil and room.midLayout ~= nil, "an Emerald map without a border still builds")
  T.eq(room and room.midLayout.borderWidth, 2, "an Emerald map's default border is 2 wide")
end

do
  local data = dataset()
  load("firered", { { id = "one", body = [[
local mod = ...
mod.content.maps:patch("FR_CENTER_A", { cells = { { x = 1, y = 1, metatile = 9 } } })
]] } }, data)
  T.eq(data.maps.FR_CENTER_A.midLayout:midAt(1, 1), 9, "the patched map shows the cell")
  T.eq(data.maps.FR_CENTER_B.midLayout:midAt(1, 1), 4, "the map sharing its layout is untouched")
end

for _, api in ipairs({ 2, 3 }) do
  local data = dataset()
  local lab, town = data.maps.FR_OAKS_LAB, data.maps.FR_PALLET_TOWN
  local decoded = lab.midLayout
  local loader = load("firered", { { id = "hdr" .. api, api = api, body = [[
local mod = ...
local ok, err = mod.content.maps:patch("FR_PALLET_TOWN", { weather = 2 })
assert(ok ~= nil, tostring(err))
ok, err = mod.content.maps:patch("FR_OAKS_LAB", { warps = { { x = 6, y = 11, destMap = "FR_PALLET_TOWN", destWarp = 1 } } })
assert(ok ~= nil, tostring(err))
]] } }, data)
  T.eq(errorsOf(loader), "", "api " .. api .. " header patches merge clean")
  T.check(loader.mods["hdr" .. api].state == "loaded", "api " .. api .. " the documented weather example loads")
  T.check(data.maps.FR_PALLET_TOWN == town, "api " .. api .. " a header patch keeps the def table")
  T.eq(town.weather, 2, "api " .. api .. " weather is written")
  T.check(data.maps.FR_OAKS_LAB == lab, "api " .. api .. " a warps patch keeps the def table")
  T.check(lab.midLayout == decoded and getmetatable(lab.midLayout) == LayoutNative,
    "api " .. api .. " an already decoded layout survives")
  T.eq(lab.warps[1].y, 11, "api " .. api .. " warps are written")
end

local function sup(query, gen, version)
  return (UnifiedContent.supports(query, gen, version)) == true
end
T.check(sup("maps.blocks", 1, "red"), "red supports maps.blocks")
T.check(sup("maps.blocks", 2, "gold"), "gold supports maps.blocks")
T.check(sup("maps.blocks", 3, "firered"), "firered supports maps.blocks")
T.check(sup("maps.cells", 3, "firered"), "firered supports maps.cells")
T.check(not sup("maps.cells", 1, "red"), "red has no maps.cells")
T.check(not sup("maps.bogus", 3, "firered"), "an unknown field is unsupported")
T.check(sup("maps", 3, "firered"), "the registry query keeps its meaning")

do
  select("firered")
  local data = dataset()
  load("firered", { { id = "strip", body = [[
local mod = ...
mod.content.maps:patch("FR_ROUTE_1", { cells = { { x = 5, y = 39, metatile = 11 } } })
]] } }, data)
  local Map = require("src.core.game3.map")
  Map._loadedLayouts, Map.world = {}, {}
  Map.loadNeighborsDepth1({ data = data }, data.maps.FR_PALLET_TOWN)
  T.eq(Map.worldMidAt(5, -1, data.maps.FR_PALLET_TOWN), 11, "the connection strip reads the patched neighbour")
  T.eq(Map.worldMidAt(6, -1, data.maps.FR_PALLET_TOWN), 2, "the rest of the strip is vanilla")
end

do
  local data = dataset()
  T.eq(data.maps.FR_OAKS_LAB.midLayout:midAt(-1, -1), 1, "the vanilla border metatile is 1")
  local loader = load("firered", { { id = "regrid", body = [[
local mod = ...
local b = {}
for i = 1, 13 * 12 do b[i] = 3 end
mod.content.maps:patch("FR_OAKS_LAB", { blocks = b })
local r = {}
for i = 1, 24 * 40 do r[i] = 3 end
mod.content.maps:patch("FR_ROUTE_1", { blocks = r, border = { 9 } })
]] } }, data)
  T.eq(errorsOf(loader), "", "blocks patches on vanilla maps merge clean")
  local lab = data.maps.FR_OAKS_LAB.midLayout
  T.eq(lab:midAt(0, 0), 3, "the patched grid is drawn")
  T.eq(lab:midAt(-1, -1), 1, "a blocks patch without a border keeps the map's own border")
  T.eq(lab.borderWidth, 1, "a blocks patch keeps the map's border width")
  T.eq(lab.borderHeight, 1, "a blocks patch keeps the map's border height")
  T.eq(data.maps.FR_ROUTE_1.midLayout:midAt(-1, -1), 9, "a blocks patch with a border uses the mod's border")

  local rseData = dataset("EM_")
  local rseRoute = rseData.maps.EM_ROUTE_1
  local wide = {}
  for i = 1, 24 * 40 do wide[i] = { mid = 2, coll = 0, elev = 3 } end
  rawset(rseRoute, "midLayout", LayoutNative.fromDecoded({ width = 24, height = 40, borderWidth = 2,
    borderHeight = 2, borderMids = { 10, 11, 12, 13 }, cells = wide }, "EM_ROUTE_1", PAIR))
  local em = load("emerald", { { id = "hoenngrid", body = [[
local mod = ...
local r = {}
for i = 1, 24 * 40 do r[i] = 3 end
mod.content.maps:patch("EM_ROUTE_1", { blocks = r })
]] } }, rseData)
  T.eq(errorsOf(em), "", "an Emerald blocks patch merges clean")
  local route = rseData.maps.EM_ROUTE_1.midLayout
  T.eq(route.borderWidth, 2, "an Emerald blocks patch keeps the 2x2 border")
  T.eq(table.concat(route.borderMids, ","), "10,11,12,13", "an Emerald blocks patch keeps the border metatiles")
end

do
  local data = dataset()
  local loader = load("firered", {
    { id = "a_good", body = [[
local mod = ...
mod.content.maps:patch("FR_OAKS_LAB", { weather = 2, cells = { { x = 1, y = 1, metatile = 5 } } })
]] },
    { id = "b_bad", body = [[
local mod = ...
mod.content.maps:patch("FR_OAKS_LAB", { cells = { { x = 2, y = 2, metatile = 6 }, { x = 13, y = 0, metatile = 7 } } })
]] },
    { id = "c_good", body = [[
local mod = ...
mod.content.maps:patch("FR_OAKS_LAB", { cells = { { x = 3, y = 3, metatile = 8 } } })
]] },
  }, data)
  local lab = data.maps.FR_OAKS_LAB
  hasError(loader, "b_bad: maps.FR_OAKS_LAB.cells[2]: (13,0) is outside the 13x12 grid", "the bad mod is named")
  T.check(not errorsOf(loader):find("a_good", 1, true) and not errorsOf(loader):find("c_good", 1, true),
    "the good mods are not blamed")
  T.eq(lab.weather, 2, "another mod's weather on the same map lands")
  T.eq(lab.midLayout:midAt(1, 1), 5, "an earlier mod's cell on the same map lands")
  T.eq(lab.midLayout:midAt(3, 3), 8, "a later mod's cell on the same map lands")
  T.eq(lab.midLayout:midAt(2, 2), 1, "the bad mod's valid cells on that map are dropped too")
end

do
  local data = dataset()
  local loader = load("firered", { { id = "ghost", body = [[
local mod = ...
mod.content.maps:patch("FR_NOPE", { cells = { { x = 1, y = 1, metatile = 5 } } })
]] } }, data)
  hasError(loader, "ghost: maps.FR_NOPE: no map FR_NOPE to patch", "patching an unknown map names the id and mod")
  T.check(not errorsOf(loader):find("tileset pair", 1, true), "an unknown map is not reported as a pair")
  T.check(data.maps.FR_NOPE == nil, "an unknown map id is not created by a patch")
end

do
  local data = dataset()
  local loader = load("firered", { { id = "record", body = [[
local mod = ...
mod.content.maps:patch("FR_OAKS_LAB", { cells = { x = 1, y = 1, metatile = 5 } })
]] } }, data)
  T.check(loader.mods.record.state ~= "loaded"
    and tostring(loader.mods.record.error or errorsOf(loader)):find("cells", 1, true) ~= nil,
    "a cells record that is not a list is a load error")
  T.eq(data.maps.FR_OAKS_LAB.midLayout:midAt(1, 1), 1, "the refused cells record writes nothing")
end

Interaction.behaviors = savedBehaviors
T.finish("gen3 map layouts")
