package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local SaveConvert = require("src.save_convert.SaveConvert")
local Gen3Save = require("src.save_convert.Gen3Save")
local F = require("tests.fixture_data.gen3_saves_emerald")

local function unrle(s)
  local out = {}
  for tok in s:gmatch("%S+") do
    local k, n = tok:match("^([ZF])(%x+)$")
    if k then
      out[#out + 1] = string.rep(k == "Z" and "\0" or "\255", tonumber(n, 16))
    else
      out[#out + 1] = (tok:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
    end
  end
  return table.concat(out)
end

-- pokeemerald/src/data/heal_locations.h:6
local SHARED = {
  { "LITTLEROOT_TOWN_BRENDANS_HOUSE_2F", 4, 2 }, { "LITTLEROOT_TOWN_MAYS_HOUSE_2F", 4, 2 },
  { "PETALBURG_CITY", 20, 17 }, { "SLATEPORT_CITY", 19, 20 }, { "MAUVILLE_CITY", 22, 6 },
  { "RUSTBORO_CITY", 16, 39 }, { "FORTREE_CITY", 5, 7 }, { "LILYCOVE_CITY", 24, 15 },
  { "MOSSDEEP_CITY", 28, 17 }, { "SOOTOPOLIS_CITY", 43, 32 }, { "EVER_GRANDE_CITY", 27, 49 },
  { "LITTLEROOT_TOWN", 5, 9 }, { "LITTLEROOT_TOWN", 14, 9 }, { "OLDALE_TOWN", 6, 17 },
  { "DEWFORD_TOWN", 2, 11 }, { "LAVARIDGE_TOWN", 9, 7 }, { "FALLARBOR_TOWN", 14, 8 },
  { "VERDANTURF_TOWN", 16, 4 }, { "PACIFIDLOG_TOWN", 8, 16 }, { "EVER_GRANDE_CITY", 18, 6 },
}
local TAIL = {
  emerald = { { "SOUTHERN_ISLAND_EXTERIOR", 15, 20 }, { "BATTLE_FRONTIER_OUTSIDE_EAST", 3, 52 } },
  -- pokeruby/src/data/heal_locations.h:127
  ruby = { { "BATTLE_TOWER_OUTSIDE", 14, 9 }, { "SOUTHERN_ISLAND_EXTERIOR", 15, 20 } },
}
TAIL.sapphire = TAIL.ruby
local PREFIX = { emerald = "EM_", ruby = "RU_", sapphire = "SA_" }

local function rowsFor(v)
  local rows = {}
  for i, r in ipairs(SHARED) do rows[i] = { map = PREFIX[v] .. r[1], x = r[2], y = r[3] } end
  for i, r in ipairs(TAIL[v]) do rows[#SHARED + i] = { map = PREFIX[v] .. r[1], x = r[2], y = r[3] } end
  return rows
end

local function serialize(rows, extra)
  local parts = { "local heal = {" }
  for i, r in ipairs(rows) do
    parts[#parts + 1] = ("[%d] = { map = %q, x = %d, y = %d },"):format(i, r.map, r.x, r.y)
  end
  parts[#parts + 1] = "} return { version = 1, " .. (extra or "") .. "whiteout = heal, heal_locations = heal }"
  return table.concat(parts, "\n")
end

local FAKE = "/nonexistent-heal-row-3080/"
local files = {}
local realOpen = io.open
io.open = function(path, mode)
  if type(path) == "string" and path:sub(1, #FAKE) == FAKE then
    local body = files[path:sub(#FAKE + 1)]
    if not body and path:match("map_tree/maps/%d+_%d+/header%.json$") then body = '{"layoutId": 1}' end
    if not body then return nil, "missing" end
    return { read = function() return body end, close = function() end, lines = function() return body:gmatch("[^\n]+") end }
  end
  return realOpen(path, mode)
end

local function captureOpts(v, save)
  local codec = Gen3Save.forVersion(v)
  local real, opts = codec.exportPort, nil
  codec.exportPort = function(_, o) opts = o return nil, "captured" end
  SaveConvert.exportSav(save, v, nil)
  codec.exportPort = real
  return opts
end

local function sameWarp(w, codec, row)
  if type(w) ~= "table" then return false end
  local key = codec.cartWarp({ map = row.map })
  return key and w.group == key.group and w.num == key.num and w.x == row.x and w.y == row.y and w.warpId == -1
end

for _, v in ipairs({ "emerald", "ruby", "sapphire" }) do
  local codec = Gen3Save.forVersion(v)
  local rows = rowsFor(v)
  SaveConvert.setGen3CacheDir(v, FAKE .. v)
  files[v .. "/data/generated/gba/region_map/heal_locations.lua"] = serialize(rows, 'model = "heal_row", ')
  local opts = captureOpts(v, { map = rows[3].map, x = 1, y = 1 })
  T.check(opts and type(opts.healWarp) == "function", v .. " export builds a heal warp from the heal_row table")
  if opts and opts.healWarp then
    for id, row in ipairs(rows) do
      T.check(sameWarp(opts.healWarp(row.map, row.x, row.y), codec, row),
        ("%s heal id %d (%s %d,%d) exports its own sHealLocations row"):format(v, id, row.map, row.x, row.y))
    end
    T.check(opts.healWarp(rows[11].map) == nil, v .. " a map-only lookup on Ever Grande is ambiguous")
    T.check(sameWarp(opts.healWarp(PREFIX[v] .. "INSIDE_OF_TRUCK", 2, 2), codec, rows[1]),
      v .. " a pre-setrespawn truck heal point exports row 1")
  end
end

do
  local v = "firered"
  SaveConvert.setGen3CacheDir(v, FAKE .. v)
  local base = v .. "/data/generated/gba/region_map/"
  files[base .. "heal_locations.lua"] = [[return { version = 1, whiteout = {
    [1] = { map = "FR_PLAYERS_HOUSE_1F", x = 8, y = 5 },
    [2] = { map = "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", x = 7, y = 4 } } }]]
  files[base .. "fly_destinations.lua"] = [[return { version = 1, fly_destinations = {
    MAPSEC_PALLET_TOWN = { map = "FR_PALLET_TOWN", x = 6, y = 8, healLocation = 1 },
    MAPSEC_VIRIDIAN_CITY = { map = "FR_VIRIDIAN_CITY", x = 26, y = 27, healLocation = 2 } } }]]
  local opts = captureOpts(v, { map = "FR_PALLET_TOWN", x = 1, y = 1 })
  local codec = Gen3Save.forVersion(v)
  T.check(opts and opts.healWarp ~= nil, "firered export still builds its heal warp from the fly table")
  if opts and opts.healWarp then
    T.check(sameWarp(opts.healWarp("FR_VIRIDIAN_CITY_POKEMON_CENTER_1F", 7, 4), codec,
      { map = "FR_VIRIDIAN_CITY", x = 26, y = 27 }), "firered whiteout center maps to its fly destination")
    T.check(sameWarp(opts.healWarp("FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"), codec,
      { map = "FR_VIRIDIAN_CITY", x = 26, y = 27 }), "firered map-only lookup unchanged")
  end
end

local Pokemon = require("src.core.game3.pokemon")
local HealLocations = require("src.core.game3.heal_locations")
local SaveMon = require("src.core.game3.save_mon")
Pokemon._names = Pokemon._names or { "BULBASAUR" }

do
  local v = "emerald"
  local codec = Gen3Save.forVersion(v)
  local rows = rowsFor(v)
  HealLocations.install({ model = "heal_row", whiteout = rows })
  local opts = captureOpts(v, { map = rows[3].map, x = 1, y = 1 })
  local base = assert(SaveConvert.importSav(unrle(F.images.em_fresh), v, v))
  for id, row in ipairs(rows) do
    local save = assert(SaveConvert.importSav(unrle(F.images.em_fresh), v, v))
    save.modData.cartImage, save.modData.cartImport = nil, nil
    save.healMap, save.healX, save.healY = row.map, row.x, row.y
    local o = {}
    for k, f in pairs(opts or {}) do o[k] = f end
    o.mapLayoutId = function() return 1 end
    o.toNational = o.toNational or function(sp) return sp end
    o.speciesFromNational = o.speciesFromNational or function(n) return n end
    local out, err = codec.exportPort(save, o)
    T.check(out ~= nil, ("emerald heal id %d exports with no cart template (%s)"):format(id, tostring(err)))
    local c = out and codec.decode(out)
    T.check(c and sameWarp(c.lastHealLocation, codec, row), ("emerald heal id %d decodes back to its row"):format(id))
    local back = out and SaveConvert.importSav(out, v, v)
    local ci = back and back.modData and back.modData.cartImport
    T.check(ci and ci.lastHealLocation and ci.lastHealLocation.map == row.map, ("emerald heal id %d re-imports"):format(id))
    if back then
      back.healMap, back.healX, back.healY = base.healMap, -1, -1
      SaveMon.finishCartImport(back)
      T.eq(back.healMap, row.map, ("emerald heal id %d re-import heal map"):format(id))
      T.eq(back.healX, row.x, ("emerald heal id %d re-import heal x"):format(id))
      T.eq(back.healY, row.y, ("emerald heal id %d re-import heal y"):format(id))
    end
  end
  local tpl = codec.decode(unrle(F.images.em_fresh)).lastHealLocation
  T.check(codec.mapFor(tpl.group, tpl.num) == rows[3].map and tpl.x == 0 and tpl.y == 0,
    "em_fresh template carries the zeroed Petalburg 0,0 heal warp")
  T.check(base.modData.cartImage ~= nil, "em_fresh import keeps its cart template")
  for id, row in ipairs(rows) do
    local save = assert(SaveConvert.importSav(unrle(F.images.em_fresh), v, v))
    save.modData.cartImport = nil
    save.healMap, save.healX, save.healY = row.map, row.x, row.y
    local o = {}
    for k, f in pairs(opts or {}) do o[k] = f end
    o.mapLayoutId = function() return 1 end
    o.toNational = o.toNational or function(sp) return sp end
    o.speciesFromNational = o.speciesFromNational or function(n) return n end
    local out, err = codec.exportPort(save, o)
    local c = out and codec.decode(out)
    T.check(c and sameWarp(c.lastHealLocation, codec, row),
      ("emerald heal id %d over the zeroed template writes its row (%s)"):format(id, tostring(err)))
  end
  HealLocations.invalidate()
end

do
  local v = "ruby"
  local rows = rowsFor(v)
  HealLocations.install({ model = "heal_row", whiteout = rows })
  for id, row in ipairs(rows) do
    local save = { modData = { cartImport = { lastHealLocation = { map = row.map, warpId = -1, x = row.x, y = row.y } } } }
    SaveMon.finishCartImport(save)
    T.check(save.healMap == row.map and save.healX == row.x and save.healY == row.y,
      ("ruby cart heal id %d imports as the session respawn"):format(id))
  end
  HealLocations.invalidate()
end

io.open = realOpen
T.finish("gen3_heal_row_export_3080")
