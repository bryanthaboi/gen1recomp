package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
require("src.core.game3.profile").reset()
GameVersion.set("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local src = cache and cache:read("data/generated/gba/battle_transition_rse/manifest.lua")
if type(src) ~= "string" then
  print("emerald_battle_transitions_test: skipped (no Emerald cache with battle_transition_rse; set POKEPORT_IDENTITY)")
  os.exit(0)
end
local manifest = assert(load(src, "@manifest", "t", {}))()

for _, key in ipairs({ "filled", "empty", "shrink1", "shrink2" }) do
  local tile = manifest.squaresBlankTile[key]
  eq(#tile, 64, key .. " blank tile is 8x8")
  local solid = true
  for i = 1, 64 do if tile[i] ~= 15 then solid = false end end
  check(solid, key .. " tile 1 is solid colour 15")
end
eq(manifest.logoCircles.w, 64, "logo circle oam width")
eq(manifest.logoCircles.h, 64, "logo circle oam height")
eq(table.concat(manifest.logoCircles.frames, ","), "0,1,2", "logo circle anim frames top/left/right")

local BT = require("src.core.game3.battle_transition")
local Ids = BT.ids("rse")
local defs = BT.defs("rse")
local missing = {}
for name, id in pairs(Ids.ID) do
  if not defs[id] then missing[#missing + 1] = name end
end
table.sort(missing)
eq(table.concat(missing, ","), "", "every Emerald transition id has a port")

local function run(name, opts)
  local rp = print
  local logs = {}
  print = function(...) logs[#logs + 1] = table.concat({ ... }, " ") end
  local done = false
  local n = 0
  local ok, err = pcall(function()
    BT.start(Ids.ID[name], opts or { skipIntro = true }, function() done = true end)
    while BT.isActive() and n < 1200 do
      n = n + 1
      BT.tick()
    end
  end)
  print = rp
  BT.abort()
  check(ok, name .. " runs without error " .. tostring(err or ""))
  for _, l in ipairs(logs) do
    if l:find("has no port", 1, true) then check(false, name .. " fell back to SLICE") end
  end
  return n, done
end

local TICKS = {
  BLACKHOLE = 79, BLACKHOLE_PULSATE = 160, RECTANGULAR_SPIRAL = 79,
  FRONTIER_SQUARES = 93, FRONTIER_SQUARES_SPIRAL = 109,
  FRONTIER_CIRCLES_MEET = 118, FRONTIER_CIRCLES_CROSS = 108,
  FRONTIER_CIRCLES_ASYMMETRIC_SPIRAL = 102, FRONTIER_CIRCLES_SYMMETRIC_SPIRAL = 102,
  FRONTIER_CIRCLES_MEET_IN_SEQ = 126, FRONTIER_CIRCLES_CROSS_IN_SEQ = 121,
  FRONTIER_CIRCLES_ASYMMETRIC_SPIRAL_IN_SEQ = 134, FRONTIER_CIRCLES_SYMMETRIC_SPIRAL_IN_SEQ = 134,
}
for name, want in pairs(TICKS) do
  local n, done = run(name)
  check(done, name .. " ends")
  eq(n, want, name .. " main phase frames")
end

local n, done = run("FRONTIER_SQUARES_SCROLL", { skipIntro = true, random = function() return 2 end })
check(done, "FRONTIER_SQUARES_SCROLL ends")
eq(n, 132, "FRONTIER_SQUARES_SCROLL main phase frames")

n, done = run("SHRED_SPLIT", { skipIntro = true, cameraX = 208 })
check(not done and n == 1200, "SHRED_SPLIT with a panned camera sticks in ShredSplit_BrokenCheck (pygba: hangs)")
n, done = run("SHRED_SPLIT", { skipIntro = true, cameraX = 0 })
check(done, "SHRED_SPLIT with camera x 0 passes the check")

T.finish("emerald_battle_transitions_test")
