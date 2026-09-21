#!/usr/bin/env luajit
-- pokefirered/src/wild_encounter.c:355, src/fieldmap.c:68

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Encounters = require("src.core.game3.encounters")

print("[test] 1. the encounter-type attribute has a runtime entry point")
check(type(Encounters.installEncounterTypes) == "function", "Encounters.installEncounterTypes exists")
check(type(Encounters.encounterTypeAt) == "function", "Encounters.encounterTypeAt exists")
check(type(Encounters.terrainAt) == "function", "Encounters.terrainAt exists")
if type(Encounters.encounterTypeAt) ~= "function" then
  print("[test] no encounter-type attribute path at all; the rest cannot run")
  finish()
end

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("objects/pack.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_encounters_cave_test: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local ExtractScripts = require("src.import.gba.extract_scripts")
local NativePack = require("src.import.gba.native_pack")
local LayoutNative = require("src.core.game3.layout_native")
local Collision = require("src.core.game3.collision")
local Rng = require("src.core.game3.rng")

local function read_file(rel)
  local f = io.open(rel, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function load_lua(rel)
  local src = read_file(rel)
  if not src then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  if not chunk then return nil end
  local ok, val = pcall(chunk)
  return ok and val or nil
end

print("[test] 2. the importer bakes the attribute into objects/pack.lua")
local pack = load_lua(cacheRoot .. "/objects/pack.lua")
check(type(pack) == "table", "objects/pack.lua loads")
check(type(pack and pack.encounterTypes) == "table", "pack.encounterTypes present")
local pairsWithLand = 0
local landMids, waterMids = 0, 0
for _, forPair in pairs((pack and pack.encounterTypes) or {}) do
  local has = false
  for _, e in pairs(forPair) do
    if e == 1 then landMids = landMids + 1; has = true
    elseif e == 2 then waterMids = waterMids + 1 end
  end
  if has then pairsWithLand = pairsWithLand + 1 end
end
print(("[info] land-tagged mids %d, water-tagged mids %d over %d pairs")
  :format(landMids, waterMids, pairsWithLand))
check(landMids > 500, "many metatiles carry TILE_ENCOUNTER_LAND (" .. landMids .. ")")
check(waterMids > 100, "metatiles carry TILE_ENCOUNTER_WATER (" .. waterMids .. ")")

print("[test] 3. loadBundle installs the table on the live Encounters module")
local bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })
check(bundle ~= nil, "script bundle loads")
check(type(Encounters._encounterTypes) == "table", "Encounters._encounterTypes installed by loadBundle")

local manifest = load_lua(cacheRoot .. "/native/manifest.lua") or {}
local layouts = manifest.layouts or {}

local function bind(mapId)
  local info = layouts[mapId]
  if not info then return nil end
  local blob = read_file(cacheRoot .. "/native/" .. (info.file or ("layouts/" .. mapId .. ".mid")))
  if not blob then return nil end
  local decoded = NativePack.decodeMidLayout(blob)
  if not decoded then return nil end
  local layout = LayoutNative.fromDecoded(decoded, mapId, info.pair)
  local def = { midLayout = layout, pair = info.pair, warps = {} }
  Collision.bindMap(nil, mapId, def)
  return layout
end

local function cells_of_type(layout, want)
  local out = {}
  for cy = 0, layout.height - 1 do
    for cx = 0, layout.width - 1 do
      if Encounters.encounterTypeAt(cx, cy) == want and Collision.isWalkable(cx, cy) then
        out[#out + 1] = { cx, cy }
      end
    end
  end
  return out
end

local function walk(mapId, cells, steps)
  Encounters.resetRateModifiers()
  for i = 1, steps do
    local c = cells[((i - 1) % #cells) + 1]
    local enc = Encounters.onStep(mapId, nil, { x = c[1], y = c[2] })
    if enc then return enc, i end
  end
  return nil, steps
end

print("[test] 4. Mt Moon 1F cave floor is TILE_ENCOUNTER_LAND and rolls")
local MT_MOON = "FR_MT_MOON_1F"
local mtLayout = bind(MT_MOON)
check(mtLayout ~= nil, "FR_MT_MOON_1F native layout decodes")
if not mtLayout then finish() end

local caveCells = cells_of_type(mtLayout, 1)
print("[info] Mt Moon 1F land-encounter walkable cells: " .. #caveCells)
check(#caveCells > 200, "Mt Moon 1F has land-encounter floor (" .. #caveCells .. ")")

local mtTable = Encounters.tableFor(MT_MOON)
check(type(mtTable) == "table" and type(mtTable.land) == "table", "Mt Moon 1F has a land table")
local allowed = {}
local tblMinLevel, tblMaxLevel
for _, slot in ipairs((mtTable and mtTable.land and mtTable.land.slots) or {}) do
  allowed[slot.species] = true
  local lo = tonumber(slot.minLevel or slot.level) or 0
  local hi = tonumber(slot.maxLevel or slot.level) or lo
  if not tblMinLevel or lo < tblMinLevel then tblMinLevel = lo end
  if not tblMaxLevel or hi > tblMaxLevel then tblMaxLevel = hi end
end

if #caveCells >= 2 then
  Rng.SeedRng(0x1234)
  Rng.SeedWildEncounterRng(0x1234)
  local route = { caveCells[1], caveCells[2] }
  local enc, step = walk(MT_MOON, route, 2000)
  check(enc ~= nil, "walking Mt Moon 1F starts a wild encounter (step " .. tostring(step) .. ")")
  if enc then
    print(("[info] Mt Moon encounter: species=%s level=%s on step %d")
      :format(tostring(enc.species), tostring(enc.level), step))
    check(allowed[enc.species] == true,
      "species " .. tostring(enc.species) .. " is in the Mt Moon 1F land table")
    check(tblMinLevel ~= nil
      and (enc.level or 0) >= tblMinLevel and (enc.level or 0) <= tblMaxLevel,
      ("level inside the table range (%s..%s)")
        :format(tostring(tblMinLevel), tostring(tblMaxLevel)))
  end
end

print("[test] 5. a plain indoor floor with no encounter attribute never rolls")
local deadCells = cells_of_type(mtLayout, 0)
print("[info] Mt Moon 1F walkable cells with TILE_ENCOUNTER_NONE: " .. #deadCells)
if #deadCells >= 2 then
  Rng.SeedRng(0x1234)
  Rng.SeedWildEncounterRng(0x1234)
  local enc = walk(MT_MOON, { deadCells[1], deadCells[2] }, 3000)
  check(enc == nil, "3000 steps on TILE_ENCOUNTER_NONE floor produce no encounter")
end

print("[test] 6. Route 1 road still never rolls, its grass still does")
local ROUTE1 = "FR_ROUTE_1"
local r1Layout = bind(ROUTE1)
check(r1Layout ~= nil, "FR_ROUTE_1 native layout decodes")
if r1Layout then
  local road = cells_of_type(r1Layout, 0)
  local grass = cells_of_type(r1Layout, 1)
  print(("[info] Route 1: %d road cells, %d grass cells"):format(#road, #grass))
  check(#road > 50, "Route 1 has plain road cells")
  check(#grass > 20, "Route 1 has land-encounter cells")
  if #road >= 2 then
    Rng.SeedRng(0x2222)
    Rng.SeedWildEncounterRng(0x2222)
    local enc = walk(ROUTE1, { road[1], road[2] }, 3000)
    check(enc == nil, "3000 steps on the Route 1 road produce no encounter")
  end
  if #grass >= 2 then
    Rng.SeedRng(0x2222)
    Rng.SeedWildEncounterRng(0x2222)
    local enc, step = walk(ROUTE1, { grass[1], grass[2] }, 2000)
    check(enc ~= nil, "Route 1 grass still starts a wild encounter (step " .. tostring(step) .. ")")
  end
end

print("[test] 7. water tiles still roll from the water table")
local surfMap, surfLayout, surfCells
for _, mapId in ipairs({ "FR_ROUTE_21_NORTH", "FR_ROUTE_20", "FR_ROUTE_19", "FR_PALLET_TOWN", "FR_ROUTE_4" }) do
  local layout = bind(mapId)
  local t = Encounters.tableFor(mapId)
  if layout and t and t.water then
    local cells = {}
    for cy = 0, layout.height - 1 do
      for cx = 0, layout.width - 1 do
        if Encounters.encounterTypeAt(cx, cy) == 2 then cells[#cells + 1] = { cx, cy } end
      end
    end
    if #cells >= 2 then
      surfMap, surfLayout, surfCells = mapId, layout, cells
      break
    end
  end
end
check(surfCells ~= nil, "found a map with TILE_ENCOUNTER_WATER cells and a water table")
if surfCells then
  bind(surfMap)
  print(("[info] %s water-encounter cells: %d"):format(surfMap, #surfCells))
  local waterAllowed = {}
  for _, slot in ipairs(Encounters.tableFor(surfMap).water.slots or {}) do
    waterAllowed[slot.species] = true
  end
  Rng.SeedRng(0x4321)
  Rng.SeedWildEncounterRng(0x4321)
  local enc, step = walk(surfMap, { surfCells[1], surfCells[2] }, 2000)
  check(enc ~= nil, "surfing " .. surfMap .. " starts a wild encounter (step " .. tostring(step) .. ")")
  if enc then
    check(waterAllowed[enc.species] == true,
      "species " .. tostring(enc.species) .. " is in the " .. surfMap .. " water table")
  end
end

print("[test] 8. prevMetatileBehavior gates the global 60% dice roll")
bind(MT_MOON)
Encounters.resetRateModifiers()
Encounters._prevMetatileBehavior = -1
local c = caveCells[1]
Encounters.onStep(MT_MOON, nil, { x = c[1], y = c[2] })
check(Encounters._prevMetatileBehavior == (Collision.behavior(c[1], c[2]) or 0),
  "onStep stamps the cell behavior into prevMetatileBehavior")
if #deadCells >= 1 then
  local d = deadCells[1]
  Encounters.onStep(MT_MOON, nil, { x = d[1], y = d[2] })
  check(Encounters._prevMetatileBehavior == (Collision.behavior(d[1], d[2]) or 0),
    "a non-encounter cell still stamps prevMetatileBehavior")
end

print("[test] 9. Repel keeps wilds at or above the lead's level")
-- pokefirered/src/wild_encounter.c:601
local Runtime = require("src.core.game3.runtime")
local prevSession = Runtime.session
bind(MT_MOON)

local function repelWalk(leadLevel, steps)
  Runtime.session = {
    map = MT_MOON,
    repelSteps = 250,
    party = { { species = 41, level = leadLevel, hp = 20 } },
  }
  Rng.SeedRng(0x1234)
  Rng.SeedWildEncounterRng(0x1234)
  Encounters.resetRateModifiers()
  local got, minLevel = {}, nil
  for i = 1, steps do
    local cell = caveCells[((i - 1) % 2) + 1]
    local enc = Encounters.onStep(MT_MOON, nil, { x = cell[1], y = cell[2] })
    if enc then
      got[#got + 1] = enc.level
      if not minLevel or enc.level < minLevel then minLevel = enc.level end
    end
  end
  return got, minLevel
end

if #caveCells >= 2 and tblMaxLevel then
  local atMax, minAtMax = repelWalk(tblMaxLevel, 4000)
  print(("[info] lead L%d under Repel: %d encounters, lowest level %s")
    :format(tblMaxLevel, #atMax, tostring(minAtMax)))
  check(#atMax > 0,
    "a wild at exactly the lead's level still battles under Repel (wildLevel < ourLevel denies)")
  check(minAtMax == nil or minAtMax >= tblMaxLevel,
    "no wild below the lead's level got through (lowest " .. tostring(minAtMax) .. ")")

  local aboveMax = repelWalk(tblMaxLevel + 1, 4000)
  print(("[info] lead L%d under Repel: %d encounters"):format(tblMaxLevel + 1, #aboveMax))
  check(#aboveMax == 0,
    "a lead above the whole table repels every wild (" .. #aboveMax .. " got through)")
  local minSteps = Encounters.cooldownMinSteps("land", (mtTable.land or {}).rate or 21)
  print("[info] stepsSinceLastEncounter after the repelled walk: "
    .. tostring(Encounters._stepsSinceLastEncounter) .. " / minSteps " .. tostring(minSteps))
  check(minSteps ~= nil and Encounters._stepsSinceLastEncounter >= minSteps,
    "a repelled roll does not re-arm the immunity steps")
  check(Encounters._encounterRateBuff == 0, "an active Repel keeps the rate bank at zero")
end

Runtime.session = prevSession

finish()
