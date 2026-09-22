-- Parity: S.S. Anne 1F door→room contents match pokered; after layout
-- patch, L→R hallway doors also land in rooms-map reading order (#189).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity ss anne rooms")
local check, eq = S.check, S.eq

local envDir = os.getenv("POKEPORT_DATA_DIR")
local mapsPath = (envDir and envDir .. "/maps.lua") or "data/generated/maps.lua"
local okMaps, freshMaps = pcall(dofile, mapsPath)
if not okMaps then
  error("fresh maps module load failed: " .. tostring(freshMaps))
end
local maps = freshMaps
local SsAnneLayout = require("src.world.SsAnneLayout")
local Warp = require("src.world.Warp")

-- OG occupants behind each hallway door, left → right (pokered + guides)
local OG_BY_DOOR = {
  { "SSANNE1FROOMS_GENTLEMAN3" },
  { "SSANNE1FROOMS_YOUNGSTER", "SSANNE1FROOMS_COOLTRAINER_F",
    "SSANNE1FROOMS_GIRL2", "SSANNE1FROOMS_TM_BODY_SLAM" },
  { "SSANNE1FROOMS_MIDDLE_AGED_MAN", "SSANNE1FROOMS_LITTLE_GIRL",
    "SSANNE1FROOMS_WIGGLYTUFF" },
  { "SSANNE1FROOMS_GIRL1" },
  { "SSANNE1FROOMS_GENTLEMAN2" },
  { "SSANNE1FROOMS_GENTLEMAN1" },
}

local function copyMaps()
  local ok, ser = pcall(require, "serpent")
  if ok and ser and ser.dump and ser.load then
    return ser.load(ser.dump(maps))
  end
  -- deep-ish copy of the Anne maps only
  local function deep(t)
    if type(t) ~= "table" then return t end
    local o = {}
    for k, v in pairs(t) do o[k] = deep(v) end
    return o
  end
  return {
    SS_ANNE_1F = deep(maps.SS_ANNE_1F),
    SS_ANNE_1F_ROOMS = deep(maps.SS_ANNE_1F_ROOMS),
  }
end

local function roomDoors(hall)
  local doors = {}
  for i, w in ipairs(hall.warps) do
    if w.destMap == "SS_ANNE_1F_ROOMS" then
      doors[#doors + 1] = { index = i, w = w }
    end
  end
  table.sort(doors, function(a, b) return a.w.x < b.w.x end)
  return doors
end

local function objsAt(rooms, x, y)
  local names = {}
  local col, row = math.floor(x / 10), math.floor(y / 10)
  for _, o in ipairs(rooms.objects) do
    if math.floor(o.x / 10) == col and math.floor(o.y / 10) == row then
      names[#names + 1] = o.name
    end
  end
  table.sort(names)
  return names
end

local function hasAll(got, want)
  local set = {}
  for _, n in ipairs(got) do set[n] = true end
  for _, n in ipairs(want) do
    if not set[n] then return false, n end
  end
  return true
end

-- raw ROM extract order: leftmost door → rooms warp 6
do
  local doors = roomDoors(maps.SS_ANNE_1F)
  eq(doors[1].w.destWarp, 6, "raw extract: leftmost door → rooms #6")
  eq(doors[#doors].w.destWarp, 1, "raw extract: rightmost door → rooms #1")
end

local m = copyMaps()
check(SsAnneLayout.apply(m) == true, "layout patch applies once")
check(SsAnneLayout.apply(m) == false, "layout patch is idempotent")

local data = { maps = m }
local doors = roomDoors(m.SS_ANNE_1F)
eq(#doors, 6, "six cabin doors")

local prevCell
for i, d in ipairs(doors) do
  eq(d.w.destWarp, i, ("L→R door %d → rooms warp %d"):format(i, i))
  local mid, x, y = Warp.destination(data, d.w, nil)
  eq(mid, "SS_ANNE_1F_ROOMS", "door lands in 1F rooms")
  local cell = math.floor(y / 10) * 3 + math.floor(x / 10)
  if prevCell then
    check(cell > prevCell,
      ("door %d cell %d is after door %d cell %d"):format(i, cell, i - 1, prevCell))
  end
  prevCell = cell
  local got = objsAt(m.SS_ANNE_1F_ROOMS, x, y)
  local ok, missing = hasAll(got, OG_BY_DOOR[i])
  check(ok, ("door %d keeps OG occupant %s (got %s)")
    :format(i, tostring(missing), table.concat(got, ",")))
end

-- return warps: rooms #1 exits to leftmost hall cabin door (warp 8)
eq(m.SS_ANNE_1F_ROOMS.warps[1].destWarp, 8, "rooms #1 returns to hall #8")
eq(m.SS_ANNE_1F_ROOMS.warps[6].destWarp, 3, "rooms #6 returns to hall #3")

S.finish()
