#!/usr/bin/env luajit
-- Battle transition table parity, selection, asset contract, and runner tests.

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

print("[test] 1. Transition IDs & Constants Parity (battle_transition.h)")
local BattleTransition = require("src.core.game3.battle_transition")
local ID = BattleTransition.ID
check(ID.BLUR == 0, "BLUR = 0")
check(ID.SWIRL == 1, "SWIRL = 1")
check(ID.SHUFFLE == 2, "SHUFFLE = 2")
check(ID.BIG_POKEBALL == 3, "BIG_POKEBALL = 3")
check(ID.POKEBALLS_TRAIL == 4, "POKEBALLS_TRAIL = 4")
check(ID.CLOCKWISE_WIPE == 5, "CLOCKWISE_WIPE = 5")
check(ID.RIPPLE == 6, "RIPPLE = 6")
check(ID.WAVE == 7, "WAVE = 7")
check(ID.SLICE == 8, "SLICE = 8")
check(ID.WHITE_BARS_FADE == 9, "WHITE_BARS_FADE = 9")
check(ID.GRID_SQUARES == 10, "GRID_SQUARES = 10")
check(ID.ANGLED_WIPES == 11, "ANGLED_WIPES = 11")
check(ID.LORELEI == 12, "LORELEI = 12")
check(ID.BRUNO == 13, "BRUNO = 13")
check(ID.AGATHA == 14, "AGATHA = 14")
check(ID.LANCE == 15, "LANCE = 15")
check(ID.BLUE == 16, "BLUE = 16")
check(ID.SPIRAL == 17, "SPIRAL = 17")

print("[test] 2. Map Terrain Classification (battle_setup.c)")
local TERRAIN = BattleTransition.TERRAIN
local function terrainCases(label)
  local T = BattleTransition.getTerrainByMap
  check(T({ flashLevel = 4, mapType = 4, mapBehavior = 0 }) == TERRAIN.FLASH, label .. " dark cave -> FLASH")
  check(T({ flashLevel = 4, mapType = 3, mapBehavior = 0x15 }) == TERRAIN.FLASH, label .. " flash beats surfable")
  check(T({ flashLevel = 0, mapType = 3, mapBehavior = 0x15 }) == TERRAIN.WATER,
    label .. " surfable cell on a ROUTE map -> WATER")
  check(T({ flashLevel = 0, mapType = 4, mapBehavior = 0x13 }) == TERRAIN.WATER,
    label .. " surfable cell in an UNDERGROUND map -> WATER")
  check(T({ flashLevel = 0, mapType = 4, mapBehavior = 0 }) == TERRAIN.CAVE, label .. " MAP_TYPE_UNDERGROUND -> CAVE")
  check(T({ flashLevel = 0, mapType = 5, mapBehavior = 0 }) == TERRAIN.WATER, label .. " MAP_TYPE_UNDERWATER -> WATER")
  check(T({ flashLevel = 0, mapType = 3, mapBehavior = 0 }) == TERRAIN.NORMAL, label .. " MAP_TYPE_ROUTE -> NORMAL")
  check(T({ flashLevel = 0, mapType = 1, mapBehavior = 0 }) == TERRAIN.NORMAL, label .. " MAP_TYPE_TOWN -> NORMAL")
  check(T({ flashLevel = 0, mapType = 8, mapBehavior = 0 }) == TERRAIN.NORMAL, label .. " MAP_TYPE_INDOOR -> NORMAL")
end
terrainCases("FRLG")

local BattleBridge = require("src.core.game3.battle_bridge")
local levelSum = BattleBridge._playerPartyLevelSum
local fainted = { species = 25, level = 50, hp = 0 }
local egg = { species = 412, level = 5, hp = 10, isEgg = true }
local second = { species = 19, level = 5, hp = 12 }
local third = { species = 16, level = 7, hp = 9 }
check(levelSum({ fainted, second }, 1) == 5, "lead level skips a fainted first mon")
check(levelSum({ egg, second }, 1) == 5, "lead level skips an egg")
check(levelSum({ second, third }, 1) == 5, "lead level is the first healthy mon")
check(levelSum({ fainted, second, egg, third }, 2) == 12, "two-mon sum skips fainted and egg slots")

print("[test] 3. Wild Battle Transition Selection (battle_setup.c sBattleTransitionTable_Wild)")
-- Normal
check(BattleTransition.pickWild({ terrain = TERRAIN.NORMAL, playerLevel = 10, enemyLevel = 5 }) == ID.SLICE,
  "wild normal low-level foe -> SLICE")
check(BattleTransition.pickWild({ terrain = TERRAIN.NORMAL, playerLevel = 5, enemyLevel = 10 }) == ID.WHITE_BARS_FADE,
  "wild normal high-level foe -> WHITE_BARS_FADE")
-- Cave
check(BattleTransition.pickWild({ terrain = TERRAIN.CAVE, playerLevel = 10, enemyLevel = 5 }) == ID.CLOCKWISE_WIPE,
  "wild cave low-level foe -> CLOCKWISE_WIPE")
check(BattleTransition.pickWild({ terrain = TERRAIN.CAVE, playerLevel = 5, enemyLevel = 10 }) == ID.GRID_SQUARES,
  "wild cave high-level foe -> GRID_SQUARES")
-- Flash
check(BattleTransition.pickWild({ terrain = TERRAIN.FLASH, playerLevel = 10, enemyLevel = 5 }) == ID.BLUR,
  "wild flash low-level foe -> BLUR")
check(BattleTransition.pickWild({ terrain = TERRAIN.FLASH, playerLevel = 5, enemyLevel = 10 }) == ID.GRID_SQUARES,
  "wild flash high-level foe -> GRID_SQUARES")
-- Water
check(BattleTransition.pickWild({ terrain = TERRAIN.WATER, playerLevel = 10, enemyLevel = 5 }) == ID.WAVE,
  "wild water low-level foe -> WAVE")
check(BattleTransition.pickWild({ terrain = TERRAIN.WATER, playerLevel = 5, enemyLevel = 10 }) == ID.RIPPLE,
  "wild water high-level foe -> RIPPLE")

print("[test] 4. Trainer Battle Transition Selection (battle_setup.c sBattleTransitionTable_Trainer)")
-- Normal
check(BattleTransition.pickTrainer({ terrain = TERRAIN.NORMAL, playerLevel = 10, enemyLevel = 5 }) == ID.POKEBALLS_TRAIL,
  "trainer normal low-level foe -> POKEBALLS_TRAIL")
check(BattleTransition.pickTrainer({ terrain = TERRAIN.NORMAL, playerLevel = 5, enemyLevel = 10 }) == ID.ANGLED_WIPES,
  "trainer normal high-level foe -> ANGLED_WIPES")
-- Cave
check(BattleTransition.pickTrainer({ terrain = TERRAIN.CAVE, playerLevel = 10, enemyLevel = 5 }) == ID.SHUFFLE,
  "trainer cave low-level foe -> SHUFFLE")
check(BattleTransition.pickTrainer({ terrain = TERRAIN.CAVE, playerLevel = 5, enemyLevel = 10 }) == ID.BIG_POKEBALL,
  "trainer cave high-level foe -> BIG_POKEBALL")
-- Flash
check(BattleTransition.pickTrainer({ terrain = TERRAIN.FLASH, playerLevel = 10, enemyLevel = 5 }) == ID.BLUR,
  "trainer flash low-level foe -> BLUR")
check(BattleTransition.pickTrainer({ terrain = TERRAIN.FLASH, playerLevel = 5, enemyLevel = 10 }) == ID.GRID_SQUARES,
  "trainer flash high-level foe -> GRID_SQUARES")
-- Water
check(BattleTransition.pickTrainer({ terrain = TERRAIN.WATER, playerLevel = 10, enemyLevel = 5 }) == ID.SWIRL,
  "trainer water low-level foe -> SWIRL")
check(BattleTransition.pickTrainer({ terrain = TERRAIN.WATER, playerLevel = 5, enemyLevel = 10 }) == ID.RIPPLE,
  "trainer water high-level foe -> RIPPLE")

print("[test] 5. Elite Four & Rival Mugshots Routing")
-- pokefirered/src/battle_setup.c:633, opponents.h:416-419 and :741-744
check(BattleTransition.pickTrainer({ trainerClass = 87, trainerId = 410 }) == ID.LORELEI, "Lorelei -> LORELEI")
check(BattleTransition.pickTrainer({ trainerClass = 87, trainerId = 411 }) == ID.BRUNO, "Bruno -> BRUNO")
check(BattleTransition.pickTrainer({ trainerClass = 87, trainerId = 412 }) == ID.AGATHA, "Agatha -> AGATHA")
check(BattleTransition.pickTrainer({ trainerClass = 87, trainerId = 413 }) == ID.LANCE, "Lance -> LANCE")
check(BattleTransition.pickTrainer({ trainerClass = 87, trainerId = 737 }) == ID.AGATHA, "Agatha's rematch -> AGATHA")
check(BattleTransition.pickTrainer({ trainerClass = 87, trainerId = 999 }) == ID.BLUE, "other Elite Four -> BLUE")
check(BattleTransition.pickTrainer({ trainerClass = 90, trainerId = 438 }) == ID.BLUE, "Champion -> BLUE")
check(BattleTransition.pickTrainer({ trainerClass = 81, trainerId = 326, terrain = TERRAIN.NORMAL,
  playerLevel = 5, enemyLevel = 5 }) ~= ID.BLUE, "an early rival battle keeps the terrain transition")
check(BattleTransition.pickTrainer({ trainerClass = "CHAMPION", playerLevel = 5, enemyLevel = 5 }) ~= ID.BLUE,
  "a class is recognised by its id, not by its (translatable) name")
-- pokefirered/src/trainer_tower_sets.c:8663 MIKAELA, FACILITY_CLASS_LASS (90)
check(BattleTransition.pickTrainer({ trainerTower = true, trainerClass = 90, trainerId = 0,
  playerLevel = 5, enemyLevel = 5 }) ~= ID.BLUE, "a Trainer Tower LASS is not taken for the champion")
check(BattleTransition.pickTrainer({ eReader = true, trainerClass = 87, trainerId = 0,
  playerLevel = 5, enemyLevel = 5 }) ~= ID.BLUE, "nor an e-Reader trainer for the Elite Four")
check(BattleTransition.pickTrainer({ isRival = true }) == ID.BLUE, "Rival -> BLUE")

print("[test] 6. Cache Contract & Extract Pipeline")
local CacheContract = require("src.import.CacheContract")
local req = CacheContract.requiredFilesFor("firered")
local reqSet = {}
for _, f in ipairs(req) do reqSet[f] = true end
check(reqSet["data/generated/gba/pokemon/battle_transition/manifest.lua"] == true, "contract has manifest.lua")
check(reqSet["data/generated/gba/pokemon/battle_transition/big_pokeball.rgba"] == true, "contract has big_pokeball.rgba")
check(reqSet["data/generated/gba/pokemon/battle_transition/sliding_pokeball.rgba"] == true, "contract has sliding_pokeball.rgba")

print("[test] 7. Transition Runner State Lifecycle")
local doneCalled = false
BattleTransition.start(ID.SLICE, { headless = true }, function()
  doneCalled = true
end)
check(doneCalled == true, "headless transition finishes immediately")

-- Non-headless simulated tick cycle
doneCalled = false
BattleTransition.start(ID.SLICE, { skipIntro = false }, function()
  doneCalled = true
end)
check(BattleTransition.isActive() == true, "transition active on start")
check(BattleTransition._phase == "intro", "starts in intro phase")

-- src/battle_transition.c:703
for f = 1, 33 do
  BattleTransition.tick(1 / 60)
end
check(BattleTransition._phase == "intro", "intro still running after 33 frames")
BattleTransition.tick(1 / 60)
check(BattleTransition._phase == "main", "advances to main phase after 34 intro frames")

local ticks = 0
while BattleTransition.isActive() and ticks < 300 do
  BattleTransition.tick(1 / 60)
  ticks = ticks + 1
end
check(doneCalled == true, "transition completes and invokes done callback")
check(BattleTransition.isActive() == false, "transition inactive after finish")

print("[test] 8. Coverage never stops short or reverses")
local function run(id)
  local covs, finished = {}, false
  BattleTransition.start(id, { skipIntro = true }, function() finished = true end)
  local guard = 0
  while not finished and guard < 600 do
    BattleTransition.tick(1 / 60)
    if BattleTransition._fx then covs[#covs + 1] = BattleTransition.screenCoverage() end
    guard = guard + 1
  end
  return covs, finished
end

local covs, finished = run(ID.SLICE)
local monotonic = true
for i = 2, #covs do
  if covs[i] < covs[i - 1] then monotonic = false end
end
check(finished, "SLICE finishes")
check(covs[1] < 0.02, "SLICE starts uncovered (no instant black)")
check(monotonic, "SLICE coverage never reverses")
check(covs[#covs] == 1, "SLICE ends fully covered")
local firstFull
for i, c in ipairs(covs) do
  if c == 1 and not firstFull then firstFull = i end
end
check(firstFull ~= nil and #covs - firstFull <= 2, "SLICE hands off right after full coverage")

for _, id in ipairs({ ID.WAVE, ID.ANGLED_WIPES, ID.CLOCKWISE_WIPE, ID.GRID_SQUARES, ID.WHITE_BARS_FADE,
  ID.BLUR, ID.SWIRL, ID.SHUFFLE, ID.RIPPLE, ID.BIG_POKEBALL, ID.POKEBALLS_TRAIL, ID.BLUE }) do
  local c, done = run(id)
  check(done and c[#c] == 1, "transition " .. id .. " ends on a black screen")
end

print("[test] 9. SLICE rows extend to the full window width")
BattleTransition.start(ID.SLICE, { skipIntro = true })
for _ = 1, 20 do BattleTransition.tick(1 / 60) end
local even = BattleTransition.blackSpans(0, -120, 360)
local odd = BattleTransition.blackSpans(1, -120, 360)
check(even[1] == -120 and even[2] > -120, "even rows grow from the left window edge")
check(odd[2] == 360 and odd[1] < 360, "odd rows grow from the right window edge")
BattleTransition.abort()

print("[test] 10. CLOCKWISE_WIPE sweeps the top-left quarter")
local H = BattleTransition.H
local hs = {}
local hn = H.winHSpans(H.WIN_RANGE(120, 40), hs)
check(hn == 2 and hs[1] == 0 and hs[2] == 40 and hs[3] == 120 and hs[4] == 240,
  "WIN0H with left > right wraps to [0, right) + [left, 240)")
check(H.winHSpans(H.WIN_RANGE(243, 244), hs) == 0, "WIN0H past the screen edge is empty")
hn = H.winHSpans(H.WIN_RANGE(80, 120), hs)
check(hn == 1 and hs[1] == 80 and hs[2] == 120, "WIN0H with left < right is one span")

local function clockwise(label)
  local cw = BattleTransition.ID.CLOCKWISE_WIPE
  local finished = false
  BattleTransition.start(cw, { skipIntro = true }, function() finished = true end)
  local halfRow = (240 / 2) / (240 * 160)
  local prev, shrank, lastBefore = -1, false, nil
  local topLeftFromEdge, stalled = false, false
  local guard = 0
  while not finished and guard < 600 do
    BattleTransition.tick(1 / 60)
    local fx = BattleTransition._fx
    if fx then
      local c = BattleTransition.screenCoverage()
      if c < prev - halfRow - 1e-9 then shrank = true end
      if fx.state == 5 and c <= prev then stalled = true end
      prev = c
      if fx.state < 6 then lastBefore = c end
      if fx.state == 5 then
        local s = BattleTransition.blackSpans(40)
        if s[1] == 0 and s[2] > 0 then topLeftFromEdge = true end
      end
    end
    guard = guard + 1
  end
  BattleTransition.abort()
  check(finished, label .. " CLOCKWISE_WIPE finishes")
  check(not shrank, label .. " CLOCKWISE_WIPE coverage never shrinks past the one-row seam")
  check(not stalled, label .. " CLOCKWISE_WIPE coverage grows every TopLeft frame")
  check(lastBefore and lastBefore > 0.95,
    string.format("%s CLOCKWISE_WIPE covers %.3f before the end fade", label, lastBefore or -1))
  check(topLeftFromEdge, label .. " CLOCKWISE_WIPE top-left rows fill from the left edge")
end

clockwise("FRLG")
local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")
clockwise("RSE")

print("[test] 11. SHRED_SPLIT decodes WIN0H like the hardware window")
local function shred(cameraX, frames)
  local seen = { right = 0, left = 0, row0 = 0, margin = 0, strip = 0 }
  local bad = { right = 0, left = 0, row0 = 0, margin = 0, strip = 0 }
  local function edgeBlack(s1, e)
    local v = s1[e]
    local win
    if e % 2 == 0 then
      local p4 = (cameraX - v) % 0x10000
      win = (p4 * 256 + 241) % 0x10000
    else
      local p4 = (v - cameraX) % 0x10000
      win = (240 - p4) % 0x10000
    end
    local ws = {}
    local k = H.winHSpans(win, ws)
    local out, x = {}, 0
    for i = 1, k do
      if ws[2 * i - 1] > x then out[#out + 1] = x; out[#out + 1] = ws[2 * i - 1] end
      x = ws[2 * i]
    end
    if x < 240 then out[#out + 1] = x; out[#out + 1] = 240 end
    return out
  end
  local function same(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do if a[i] ~= b[i] then return false end end
    return true
  end
  local row0Want = { 0, 240 }
  local hn0 = H.winHSpans(cameraX - 240, hs)
  if hn0 == 1 and hs[1] == 0 then row0Want = { hs[2], 240 } end
  local finished = false
  BattleTransition.start(BattleTransition.ids().ID.SHRED_SPLIT, { skipIntro = true, cameraX = cameraX },
    function() finished = true end)
  for _ = 1, frames do
    BattleTransition.tick(1 / 60)
    local fx = BattleTransition._fx
    if finished or not fx or fx.state > 2 then break end
    local s1 = fx.shred1
    for y = 0, 159 do
      local v = s1 and s1[160 + y]
      local s = BattleTransition.blackSpans(y, 0, 240)
      if y == 0 and v == (cameraX - 240) % 0x10000 then
        seen.row0 = seen.row0 + 1
        if not (#s == 2 and s[1] == row0Want[1] and s[2] == row0Want[2]) then bad.row0 = bad.row0 + 1 end
      elseif v == 0xFFFA then
        seen.right = seen.right + 1
        if #s ~= 0 then bad.right = bad.right + 1 end
      elseif v == 0xF6F1 then
        seen.left = seen.left + 1
        if #s ~= 0 then bad.left = bad.left + 1 end
      end
    end
    if s1 then
      local alias = s1[160] == (cameraX - 240) % 0x10000
      local top, bottom = edgeBlack(s1, 0), edgeBlack(s1, 159)
      for d = 1, 16 do
        local up = BattleTransition.blackSpans(-d, 0, 240)
        local down = BattleTransition.blackSpans(159 + d, 0, 240)
        seen.margin = seen.margin + 2
        if not same(up, top) then bad.margin = bad.margin + 1 end
        if not same(down, bottom) then bad.margin = bad.margin + 1 end
        if alias then
          seen.strip = seen.strip + 1
          if same(up, row0Want) then bad.strip = bad.strip + 1 end
        end
      end
    end
  end
  BattleTransition.abort()
  return seen, bad, row0Want
end
local seen, bad, want0 = shred(0, 400)
check(seen.right > 0 and bad.right == 0,
  string.format("SHRED_SPLIT right-row overshoot 0xFFFA shows the whole row (%d of %d black)", bad.right, seen.right))
check(seen.left > 0 and bad.left == 0,
  string.format("SHRED_SPLIT left-row overshoot 0xF6F1 shows the whole row (%d of %d black)", bad.left, seen.left))
check(want0[1] == 16 and seen.row0 > 0 and bad.row0 == 0,
  string.format("SHRED_SPLIT row 0 alias 0xFF10 shows x 0..15 (%d of %d wrong)", bad.row0, seen.row0))
local function marginChecks(label)
  check(seen.margin > 0 and bad.margin == 0,
    string.format("SHRED_SPLIT %s margin rows take the edge row's own window (%d of %d wrong)", label, bad.margin,
      seen.margin))
  check(seen.strip > 0 and bad.strip == 0,
    string.format("SHRED_SPLIT %s row 0 alias strip stays one row tall (%d of %d margin rows show it)", label,
      bad.strip, seen.strip))
end
marginChecks("cameraX 0")
seen, bad, want0 = shred(208, 400)
check(want0[1] == 224 and seen.row0 > 0 and bad.row0 == 0,
  string.format("SHRED_SPLIT panned camera row 0 alias 0xFFE0 shows x 0..223 (%d of %d wrong)", bad.row0, seen.row0))
marginChecks("cameraX 208")
Profile.reset()
GameVersion.set("firered")

if failed > 0 then
  print(string.format("[FAIL] %d test(s) failed", failed))
  os.exit(1)
else
  print("[test] all passed")
end
