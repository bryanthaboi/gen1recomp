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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

require("src.core.GameVersion").set("firered")

local imageStub = {
  setFilter = function() end,
  getDimensions = function() return 8, 8 end,
}
local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newImage = function() return imageStub end
gfx.newQuad = function() return {} end
_G.love = {
  image = { newImageData = function(w, h) return { w = w, h = h } end },
  graphics = gfx,
}

local MANIFEST = [[return {
  format = 6,
  textboxW = 8, textboxH = 8,
  terrainW = 8, terrainH = 8,
  terrains = {
    grass = { file = "terrain_grass.rgba", w = 8, h = 8 },
    cave = { file = "terrain_cave.rgba", w = 8, h = 8 },
    building = { file = "terrain_building.rgba", w = 8, h = 8 },
    pond = { file = "terrain_pond_absent.rgba", w = 8, h = 8 },
  },
}]]

local SHEET = string.rep("\0", 8 * 8 * 4)
local reads = {}
local cache = {
  read = function(_, rel)
    reads[#reads + 1] = rel
    if rel:find("manifest.lua", 1, true) then return MANIFEST end
    if rel:find("absent", 1, true) then return nil end
    return SHEET
  end,
}

local function terrainReads()
  local out = {}
  for _, rel in ipairs(reads) do
    local name = rel:match("([^/]+)$")
    if name and name:find("^terrain_") then out[#out + 1] = name end
  end
  return out
end

local function countReads(pattern)
  local n = 0
  for _, rel in ipairs(reads) do
    if rel:find(pattern, 1, true) then n = n + 1 end
  end
  return n
end

local BattleChrome = require("src.ui.game3.battle_chrome")

print("[test] 1. install reads no terrain sheet (battle_bg.c:644)")
BattleChrome.install(cache)
local afterInstall = terrainReads()
eq(#afterInstall, 0, "no terrain file was read during install, got " .. table.concat(afterInstall, ","))
check(countReads("healthbox_player.rgba") == 1, "install still reads the player healthbox")
check(BattleChrome._terrainInfo and BattleChrome._terrainInfo.grass ~= nil,
  "the manifest terrain table is kept for later")
eq(next(BattleChrome._terrains), nil, "no terrain entry is cached yet")

print("[test] 2. the first use of a terrain loads exactly that terrain")
reads = {}
local grass = BattleChrome.terrain("grass")
check(grass ~= nil and grass.image ~= nil, "BattleChrome.terrain('grass') built an entry")
local loadedGrass = terrainReads()
table.sort(loadedGrass)
eq(table.concat(loadedGrass, ","),
  "terrain_bg_grass.rgba,terrain_enemy_grass.rgba,terrain_grass.rgba,terrain_player_grass.rgba",
  "the four grass sheets were read")
eq(countReads("cave"), 0, "no cave sheet was read")
eq(countReads("building"), 0, "no building sheet was read")
eq(rawget(BattleChrome._terrains, "cave"), nil, "cave is still uncached")

print("[test] 3. the second use reads nothing")
reads = {}
local again = BattleChrome.terrain("grass")
check(rawequal(again, grass), "the cached entry is handed back")
eq(#terrainReads(), 0, "no file was read again")

print("[test] 4. indexing _terrains loads through the same path")
reads = {}
local cave = BattleChrome._terrains.cave
check(cave ~= nil and cave.image ~= nil, "_terrains.cave loaded on demand")
check(rawget(BattleChrome._terrains, "cave") ~= nil, "and it is cached after the index")
eq(countReads("terrain_cave.rgba"), 1, "the cave sheet was read once")

print("[test] 5. a terrain with no file stays missing without re-reading")
reads = {}
eq(BattleChrome.terrain("pond"), nil, "a terrain whose sheet is absent returns nil")
eq(countReads("terrain_pond_absent.rgba"), 1, "the absent sheet was tried once")
reads = {}
eq(BattleChrome.terrain("pond"), nil, "it is still nil on the second call")
eq(countReads("terrain_pond_absent.rgba"), 0, "and it was not read again")
eq(BattleChrome.terrain("no_such_terrain"), nil, "a terrain outside the manifest is nil")
eq(#terrainReads(), 0, "and reads nothing")

print("[test] 6. drawTerrain pulls the sheet it is asked for")
reads = {}
local drew = BattleChrome.drawTerrain("building", 0, 0, 0)
check(drew == true, "drawTerrain('building') drew")
eq(countReads("terrain_building.rgba"), 1, "and loaded the building sheet on the way")

print("[test] 7. install clears the cache again")
reads = {}
BattleChrome.install(cache)
eq(next(BattleChrome._terrains), nil, "re-install drops every cached terrain")
eq(#terrainReads(), 0, "and reads no terrain sheet")

print("[test] 8. the battle background still picks the right sheet key")
local BattleBg = require("src.core.game3.battle.bg")
BattleBg.setAvailableSheets(nil)
eq(BattleBg.sheetKey(BattleBg.TERRAIN.CAVE), "cave", "a cave battle still resolves to the cave sheet")
eq(BattleBg.sheetKey(BattleBg.TERRAIN.BUILDING), "building",
  "an indoor battle still resolves to the building sheet")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
