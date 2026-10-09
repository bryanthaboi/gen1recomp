package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
local Extract = require("src.import.gba.battle_chrome_extract")
local Lz77 = require("src.import.gba.lz77")
local V = require("src.import.gba.games.emerald")
local cfg = V.BATTLE_UI
local originals = { decompress = Lz77.decompress, terrainTable = Extract.requireTerrainTable }
local data, written = {}, {}
local terrainRows = {}
local gfx = string.rep("\x11", 32) .. string.rep("\x22", 32)
local palette = "\0\0\x1f\0\xe0\3" .. string.rep("\0", 26)
local map = string.rep("\0\x20", 1024) .. string.rep("\1\x20", 1024)
local function terrain(tr)
  data[tr.tiles], data[tr.pal], data[tr.tilemap] = gfx, palette, map
end
for id = 0, cfg.terrain_count - 1 do
  local tr = { tiles = 100 + id * 3, pal = 101 + id * 3, tilemap = 102 + id * 3 }
  tr.entryTiles, tr.entryTilemap = tr.tiles, tr.tilemap
  terrain(tr)
  terrainRows[#terrainRows + 1] = { key = Extract.TERRAIN_KEYS[id], id = id, cfg = tr }
end
for _, scene in ipairs(cfg.scenes) do terrain(scene.cfg) end
data[cfg.entry_rayquaza.tiles], data[cfg.entry_rayquaza.tilemap] = gfx, map
Extract.requireTerrainTable = function() return terrainRows end
Lz77.decompress = function(_, offset) return data[offset] or string.rep("\0", 32) end
local rom = { get = function() return 0 end, u16 = function() return 0 end }
local cache = { write = function(_, path, bytes) written[path] = bytes; return true end }
local root = "fixture/pokemon/battle/"
local function bake()
  Extract.runRse(rom, cache, { cacheRoot = "fixture" }, cfg)
  return assert(loadstring(written[root .. "manifest.lua"]))()
end
local manifest = bake()
local green = string.char(0, 255, 0, 255)
local red = string.char(255, 0, 0, 255)
for key, info in pairs(manifest.terrains) do
  T.eq(info.postDexFile, "terrain_" .. key .. "_post_dex.rgba", key .. " manifest retains right screen")
  local pixels = written[root .. (info.postDexFile or "missing")]
  T.eq(pixels and #pixels, 256 * 256 * 4, key .. " right screen dimensions")
  T.eq(pixels and pixels:sub(1, 4), green, key .. " right screen uses second map block and palette bank2")
  T.eq(written[root .. info.file]:sub(1, 4), red, key .. " ordinary left screen unchanged")
end
local tr = terrainRows[1].cfg
local savedMap = data[tr.tilemap]
data[tr.tilemap] = savedMap:sub(1, 2048)
T.raises(bake, "post-dex terrain map", "truncated ROM map cannot invent right screen")
data[tr.tilemap] = savedMap
local Versions = require("src.import.gba.versions")
local frlgManifests = {}
Extract.requireTerrainTable = originals.terrainTable
local profiles = {
  { "fr10", "41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc" },
  { "fr11", "dd5945db9b930750cb39d00c84da8571feebf417" },
  { "lg10", "574fa542ffebb14be69902d1d36f1ec0a4afd71e" },
  { "lg11", "7862c67bdecbe21d1d69ce082ce34327e1c6ed5e" },
}
for _, edition in ipairs(profiles) do
  Versions.select(edition[2])
  local frCfg, bytes, rows = Versions.BATTLE_UI, {}, {}
  local tableBase = frCfg.terrain_table or Versions.address(Extract.TERRAIN_TABLE)
  local function pointer(off, value)
    for i = 0, 3 do bytes[off + i] = math.floor((value + 0x08000000) / 256 ^ i) % 256 end
  end
  for id = 0, 19 do
    local row = id == 0 and frCfg.terrain_grass
      or { tiles = 1000 + id * 3, pal = 1001 + id * 3, tilemap = 1002 + id * 3 }
    terrain(row)
    pointer(tableBase + id * 20, row.tiles)
    pointer(tableBase + id * 20 + 4, row.tilemap)
    pointer(tableBase + id * 20 + 8, row.tiles)
    pointer(tableBase + id * 20 + 12, row.tilemap)
    pointer(tableBase + id * 20 + 16, row.pal)
    rows[#rows + 1] = row
  end
  local frRom = { get = function(_, off) return bytes[off] or 0 end }
  local function bakeFr()
    Extract.run(frRom, cache, { cacheRoot = "fixture" })
    return assert(loadstring(written[root .. "manifest.lua"]))()
  end
  local decoded = Extract.requireTerrainTable(function(off) return frRom:get(off) end, frCfg)
  T.eq(#decoded, 20, edition[1] .. " actual ROM terrain table decodes20 rows")
  local frManifest, count = bakeFr(), 0
  frlgManifests[edition[1]] = frManifest
  for key, info in pairs(frManifest.terrains) do
    count = count + 1
    T.eq(info.postDexFile, "terrain_" .. key .. "_post_dex.rgba", edition[1] .. " " .. key .. " manifest retains right screen")
    local pixels = written[root .. (info.postDexFile or "missing")]
    T.eq(pixels and #pixels, 256 * 256 * 4, edition[1] .. " " .. key .. " right screen dimensions")
    T.eq(pixels and pixels:sub(1, 4), green, edition[1] .. " " .. key .. " right screen uses second map block and palette bank2")
    T.eq(written[root .. info.file]:sub(1, 4), red, edition[1] .. " " .. key .. " ordinary left screen unchanged")
  end
  T.eq(count, 20, edition[1] .. " all20 terrains preserved")
  data[rows[1].tilemap] = map:sub(1, 2048)
  T.raises(bakeFr, "post-dex terrain map", edition[1] .. " truncated ROM map cannot invent right screen")
  data[rows[1].tilemap] = map
end
Versions.select("firered")
Lz77.decompress, Extract.requireTerrainTable = originals.decompress, originals.terrainTable

local draws, imageReads = {}, {}
_G.love = require("tests.love_stub")
love.image.newImageData = function(w, h, _, bytes) return { w = w, h = h, bytes = bytes } end
love.graphics.newImage = function(id)
  return { data = id, setFilter = function() end, getDimensions = function() return id.w, id.h end }
end
love.graphics.newQuad = function(...) return { ... } end
love.graphics.draw = function(...) draws[#draws + 1] = { ... } end
local Chrome = require("src.ui.game3.battle_chrome")
local function install(m, bytes)
  draws = {}
  Chrome.install({ read = function(_, path)
    if path:match("/manifest.lua$") then return m end
    local file = path:match("/([^/]+)$")
    imageReads[file] = (imageReads[file] or 0) + 1
    return bytes[file]
  end })
end
local rgba = string.rep(green, 256 * 256)
local assets = { ["terrain_grass.rgba"] = string.rep(red, 256 * 256), ["terrain_grass_post_dex.rgba"] = rgba }
local metadata = 'return { layout="rse", terrains={ grass={ file="terrain_grass.rgba", postDexFile="terrain_grass_post_dex.rgba", w=256, h=256 } } }'
install(metadata, assets)
T.check(type(Chrome.drawPostDexBg) == "function", "renderer exposes post-dex ROM scene")
if Chrome.drawPostDexBg then
  T.eq(Chrome.drawPostDexBg("grass"), true, "draw succeeds with required ROM data")
  T.eq(#draws, 1, "post-dex draw has one background")
  T.check(draws[1][1].data.bytes == rgba, "draw selects right screen image")
  T.same(draws[1][2], { 0, 0, 240, 112, 256, 256 }, "post-dex crop protects lower textbox")
  T.eq(draws[1][3], 0, "draw starts at screen x0")
  T.eq(draws[1][4], 0, "draw starts at screen y0")
  T.raises(function() Chrome.drawPostDexBg("missing") end, "post-dex", "unknown RSE terrain cannot substitute grass")
  assets["terrain_grass_post_dex.rgba"] = nil
  install(metadata, assets)
  T.raises(function() Chrome.drawPostDexBg("grass") end, "post-dex", "missing asset cannot substitute ordinary background")
  install('return { layout="rse", terrains={ grass={file="terrain_grass.rgba",w=256,h=256} } }', assets)
  T.raises(function() Chrome.drawPostDexBg("grass") end, "post-dex", "old manifest cannot degrade post-dex scene")
  assets["terrain_grass_post_dex.rgba"] = rgba
  for _, family in ipairs({ "firered", "leafgreen" }) do
    install('return { terrains={grass={file="terrain_grass.rgba",postDexFile="terrain_grass_post_dex.rgba",w=256,h=256}} }', assets)
    T.eq(Chrome.drawPostDexBg("grass"), true, family .. " draws its required post-dex ROM image")
    T.eq(#draws, 1, family .. " post-dex API draws one background")
    local draw = draws[1]
    T.check(draw and draw[1].data.bytes == rgba, family .. " draw selects second screen")
    T.same(draw and draw[2], { 0, 0, 240, 112, 256, 256 }, family .. " crop protects textbox")
    T.raises(function() Chrome.drawPostDexBg("missing") end, "post-dex", family .. " cannot substitute grass for unknown terrain")
    assets["terrain_grass_post_dex.rgba"] = nil
    install('return { terrains={grass={file="terrain_grass.rgba",postDexFile="terrain_grass_post_dex.rgba",w=256,h=256}} }', assets)
    T.raises(function() Chrome.drawPostDexBg("grass") end, "post-dex", family .. " missing asset cannot substitute ordinary background")
    assets["terrain_grass_post_dex.rgba"] = rgba
    install('return { terrains={grass={file="terrain_grass.rgba",w=256,h=256}} }', assets)
    T.raises(function() Chrome.drawPostDexBg("grass") end, "post-dex", family .. " old manifest cannot degrade post-dex scene")
  end
end
local Contract = require("src.import.CacheContract")
local required = Contract.requiredFiles("emerald")
local complete, requiredSet = {}, {}
for _, path in ipairs(required) do complete["emerald/" .. path] = "fixture"; requiredSet[path] = true end
local fs = { prefix = "" }
fs.exists = function(path) return complete[fs.prefix .. path] ~= nil end
T.eq(Contract.allRequiredFilesExist("emerald", fs), true, "complete Emerald contract is valid")
for key, info in pairs(manifest.terrains) do
  local path = "data/generated/gba/pokemon/battle/" .. (info.postDexFile or "missing")
  T.check(requiredSet[path], key .. " post-dex output is required")
  local saved = complete["emerald/" .. path]
  complete["emerald/" .. path] = nil
  local ok, missing = Contract.allRequiredFilesExist("emerald", fs)
  T.eq(ok, false, key .. " missing post-dex data blocks readiness")
  T.eq(missing, path, key .. " contract identifies missing post-dex output")
  complete["emerald/" .. path] = saved
end
local GameVersion = require("src.core.GameVersion")
for _, profile in ipairs(profiles) do
  local version = GameVersion.forSha1(profile[2])
  Versions.select(profile[2])
  local shared = require("src.import.gba.versions_frlg").CACHE_VERSION
  T.eq(Versions.CACHE_VERSION, shared, profile[1] .. " active edition retains the shared FRLG cache stamp")
  local files, set = {}, {}
  for _, path in ipairs(Contract.requiredFiles(version)) do
    files[version .. "/" .. path] = "fixture"
    set[path] = true
  end
  local meta = version .. "/data/generated/gba/meta.json"
  files[version .. "/" .. Contract.MARKER_PATH] = Contract.markerFor(version, profile[2])
  local profileFs = { prefix = "" }
  profileFs.exists = function(path) return files[profileFs.prefix .. path] ~= nil end
  profileFs.read = function(path) return files[profileFs.prefix .. path] end
  files[meta] = '{"cache_version":129}'
  T.eq(Contract.isReady(version, profileFs), false, profile[1] .. " old129 stamp requires reimport")
  files[meta] = '{"cache_version":' .. shared .. '}'
  T.eq(Contract.isReady(version, profileFs), true, profile[1] .. " complete current cache is ready")
  local count = 0
  for key, info in pairs(frlgManifests[profile[1]].terrains) do
    count = count + 1
    local path = "data/generated/gba/pokemon/battle/" .. info.postDexFile
    T.check(set[path], profile[1] .. " " .. key .. " post-dex output is required")
    local saved = files[version .. "/" .. path]
    files[version .. "/" .. path] = nil
    T.eq(Contract.isReady(version, profileFs), false, profile[1] .. " " .. key .. " missing post-dex data blocks readiness")
    local ok, missing = Contract.allRequiredFilesExist(version, profileFs)
    T.eq(ok, false, profile[1] .. " " .. key .. " contract rejects missing post-dex output")
    T.eq(missing, path, profile[1] .. " " .. key .. " contract identifies missing file")
    files[version .. "/" .. path] = saved
  end
  T.eq(count, 20, profile[1] .. " all20 required outputs tested")
  for _, key in ipairs({ "frontier", "groudon", "kyogre", "rayquaza", "magma", "aqua", "sidney", "phoebe", "glacia", "drake" }) do
    T.eq(set["data/generated/gba/pokemon/battle/terrain_" .. key .. "_post_dex.rgba"], nil,
      profile[1] .. " does not require Emerald-only " .. key)
  end
end
Versions.select("firered")
T.check(V.CACHE_VERSION >= 15, "Emerald cache version at or past 15")
T.check(require("src.import.gba.versions_frlg").CACHE_VERSION >= 130, "FRLG cache version at or past 130")
T.finish("game3_post_dex_background_2637")
