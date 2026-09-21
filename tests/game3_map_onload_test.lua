#!/usr/bin/env luajit

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

local Space = require("src.core.game3.scripting.space")

print("[test] 1. Space exposes an ON_LOAD entry point")
check(type(Space.runOnLoad) == "function", "Space.runOnLoad exists")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_map_onload_test: " .. tostring(Cache.reason))
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local ExtractScripts = require("src.import.gba.extract_scripts")
local Objects = require("src.core.game3.objects")
local Field = require("src.core.game3.field")

Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })
check(Space.bundle ~= nil, "script bundle loads")

print("[test] 2. MAP_SCRIPT_ON_LOAD is carried through import")
local withLoad, withTransition, withResume, withReturn, withWarpInto = {}, 0, 0, 0, 0
for mapId, ev in pairs(Space.bundle.events or {}) do
  local ms = ev.mapScripts or {}
  if type(ms.onLoad) == "string" then withLoad[#withLoad + 1] = mapId end
  if type(ms.onTransition) == "string" then withTransition = withTransition + 1 end
  if type(ms.onResume) == "string" then withResume = withResume + 1 end
  if type(ms.onReturnToField) == "string" then withReturn = withReturn + 1 end
  if type(ms.onWarpIntoMap) == "table" and #ms.onWarpIntoMap > 0 then
    withWarpInto = withWarpInto + 1
  end
end
table.sort(withLoad)
print("[info] maps with ON_LOAD: " .. #withLoad)
check(#withLoad >= 20, "the cache carries ON_LOAD for many maps (" .. #withLoad .. ")")
check(withTransition > 0, "ON_TRANSITION still extracted (" .. withTransition .. ")")
check(withResume > 0, "ON_RESUME extracted as a script key (" .. withResume .. ")")
check(withReturn > 0, "ON_RETURN_TO_FIELD extracted (" .. withReturn .. ")")
check(withWarpInto > 0, "ON_WARP_INTO_MAP_TABLE extracted (" .. withWarpInto .. ")")

print("[test] 3. the puzzle maps this unblocks all have their ON_LOAD")
local SPOT_CHECK = {
  "FR_VERMILION_CITY_GYM",
  "FR_SILPH_CO_2F",
  "FR_POKEMON_MANSION_1F",
  "FR_SEAFOAM_ISLANDS_B4F",
  "FR_ROCKET_HIDEOUT_B1F",
  "FR_VICTORY_ROAD_1F",
}
for _, mapId in ipairs(SPOT_CHECK) do
  local ev = Space.bundle.events[mapId]
  local key = ev and ev.mapScripts and ev.mapScripts.onLoad
  check(type(key) == "string", mapId .. " carries an ON_LOAD script key")
  if type(key) == "string" then
    check(Space.bundle.scripts[key] ~= nil, mapId .. " ON_LOAD body decoded (" .. key .. ")")
  end
end

print("[test] 4. runEnterScripts runs ON_LOAD after ON_TRANSITION")
local GYM = "FR_VERMILION_CITY_GYM"
local gym = Space.bundle.events[GYM]
local FLAG_FOUND_BOTH = 0x264
local Flags = require("src.core.game3.scripting.flags")

if gym then
  local Dataset = require("src.core.game3.dataset")
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Collision = require("src.core.game3.collision")
  local CITY = "FR_VERMILION_CITY"
  local game = { data = {} }
  Dataset.hydrate(game)
  local session = { map = CITY, x = 12, y = 20, facing = "up", flags = {}, vars = {} }
  game.session = session
  Runtime.start(nil, game, session, { reason = "new_game" })
  local function warpTo(mapId, x, y)
    Map.load(nil, game, mapId, { x = x, y = y, facing = "up" })
    for _ = 1, 256 do
      if not Space.vm:isRunning() then break end
      Space.vm:tick()
    end
  end
  local function beamCells()
    local n = 0
    for y = 6, 7 do
      for x = 3, 7 do
        if Field.metatileOverrideAt and Field.metatileOverrideAt(GYM, x, y) then n = n + 1 end
      end
    end
    return n
  end

  Flags.setFlag(Space.store, Space.vm.ctx, FLAG_FOUND_BOTH, true)
  warpTo(GYM, 5, 18)
  check(beamCells() == 10,
    "ON_LOAD wrote the 10 beams-off metatiles on map enter, got " .. beamCells())
  check(Collision.canEnter(game, 5, 6) == true and Collision.canEnter(game, 5, 7) == true,
    "the solved gym is walkable through (5,6)/(5,7) on entry")

  print("[test] 5. Space.runOnLoad is idempotent and re-runnable")
  check(type(Space.runOnLoad) == "function" and Space.runOnLoad(GYM) == true,
    "Space.runOnLoad(GYM) reports it ran")
  check(beamCells() == 10, "a second ON_LOAD rewrites the same 10 cells in place, got " .. beamCells())
  check(Collision.canEnter(game, 5, 6) == true, "the rewrite keeps (5,6) open")

  print("[test] 6. a map load rebuilds the layout before ON_LOAD")
  local layout = game.data.maps[GYM].midLayout
  local openMid = layout:midAt(5, 6)
  warpTo(CITY, 12, 20)
  Flags.setFlag(Space.store, Space.vm.ctx, FLAG_FOUND_BOTH, false)
  warpTo(GYM, 5, 18)
  check(beamCells() == 0, "the unsolved gym has no script-written cells, got " .. beamCells())
  check(layout:midAt(5, 6) ~= openMid, "(5,6) is the layout's own beam metatile again")
  check(Collision.canEnter(game, 5, 6) ~= true, "the unsolved gym's beam is solid at (5,6)")

  print("[test] 7. a script-opened door keeps its warp (Six Island Ruin Valley)")
  local RUIN = "FR_SIX_ISLAND_RUIN_VALLEY"
  local FLAG_USED_CUT_ON_RUIN_VALLEY_BRAILLE = 0x2E3
  warpTo(RUIN, 24, 26)
  local ruinLayout = game.data.maps[RUIN].midLayout
  local closedMid = ruinLayout:midAt(24, 24)
  check(Collision.warpAt(24, 24) == nil, "the closed Dotted Hole door has no live warp")
  check(Collision.canEnter(game, 24, 24) ~= true, "the closed Dotted Hole door is solid")
  warpTo(CITY, 12, 20)
  Flags.setFlag(Space.store, Space.vm.ctx, FLAG_USED_CUT_ON_RUIN_VALLEY_BRAILLE, true)
  warpTo(RUIN, 24, 26)
  check(ruinLayout:midAt(24, 24) ~= closedMid, "ON_LOAD wrote the open door metatile at (24,24)")
  check(Collision.canEnter(game, 24, 24) == true, "the open door cell can be entered")
  check(Collision.warpAt(24, 24) ~= nil, "the Dotted Hole warp at (24,24) is live once the door is open")

  print("[test] 8. every metatile a script can place is in the native pack")
  local NativePack = require("src.import.gba.native_pack")
  local manifest = dofile(cacheRoot .. "/native/manifest.lua")
  local function pairOf(mapId)
    local info = manifest.layouts and manifest.layouts[mapId]
    return info and info.pair
  end
  local wanted = NativePack.scriptMidsByPair and NativePack.scriptMidsByPair(
    Space.bundle.scripts, Space.bundle.events, pairOf) or nil
  check(type(wanted) == "table" and next(wanted) ~= nil, "setmetatile rows resolve to tileset pairs")
  local missing, pairsSeen = 0, 0
  for pairName, mids in pairs(wanted or {}) do
    pairsSeen = pairsSeen + 1
    local f = io.open(cacheRoot .. "/native/" .. pairName .. "/mids.idx", "rb")
    local packed = {}
    if f then
      local idx = NativePack.decodeIdx(f:read("*a"))
      f:close()
      for _, mid in ipairs(idx and idx.midIds or {}) do packed[mid] = true end
    end
    for mid in pairs(mids) do
      if not packed[mid] then missing = missing + 1 end
    end
  end
  check(pairsSeen > 0 and missing == 0,
    "no script-placed metatile is missing from its pair's atlas, missing=" .. missing)
  local gymPair = pairOf(GYM)
  check(wanted and wanted[gymPair] and wanted[gymPair][layout:midAt(5, 6)] == true,
    "the gym's own beam metatile is among the script-placed ids")

  print("[test] 9. every General-primary pair packs the void-fill border metatiles")
  local VoidFill = require("src.core.game3.void_fill")
  local borderMids = {}
  for _, mapId in pairs(VoidFill.SOURCES) do
    local src = game.data.maps[mapId] and game.data.maps[mapId].midLayout
    for _, mid in ipairs(src and src.borderMids or {}) do borderMids[mid] = true end
  end
  check(next(borderMids) ~= nil, "the void-fill source maps carry border metatiles")
  local generalPairs, voidMissing = 0, 0
  for pairName in pairs(manifest.pairs or {}) do
    if VoidFill.primaryFor(pairName) == VoidFill.PRIMARY then
      generalPairs = generalPairs + 1
      local f = io.open(cacheRoot .. "/native/" .. pairName .. "/mids.idx", "rb")
      local packed = {}
      if f then
        local idx = NativePack.decodeIdx(f:read("*a"))
        f:close()
        for _, mid in ipairs(idx and idx.midIds or {}) do packed[mid] = true end
      end
      for mid in pairs(borderMids) do
        if not packed[mid] then voidMissing = voidMissing + 1 end
      end
    end
  end
  check(generalPairs > 0 and voidMissing == 0,
    ("all %d General-primary pairs pack the void-fill mids, missing=%d"):format(generalPairs, voidMissing))
else
  check(false, "the Vermilion gym is in the bundle")
end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
