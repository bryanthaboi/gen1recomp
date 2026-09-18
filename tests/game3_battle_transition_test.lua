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
check(BattleTransition.getTerrainByMap({ flashLevel = 1 }) == TERRAIN.FLASH, "flash terrain")
check(BattleTransition.getTerrainByMap({ surfing = true }) == TERRAIN.WATER, "water terrain (surfing)")
check(BattleTransition.getTerrainByMap({ mapKind = "water" }) == TERRAIN.WATER, "water terrain (mapKind)")
check(BattleTransition.getTerrainByMap({ isCave = true }) == TERRAIN.CAVE, "cave terrain (isCave)")
check(BattleTransition.getTerrainByMap({ mapKind = "dungeon" }) == TERRAIN.CAVE, "cave terrain (dungeon)")
check(BattleTransition.getTerrainByMap({}) == TERRAIN.NORMAL, "normal terrain default")

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
check(BattleTransition.pickTrainer({ trainerClass = "ELITE_FOUR", trainerId = 412 }) == ID.LORELEI, "Lorelei -> LORELEI")
check(BattleTransition.pickTrainer({ trainerClass = "ELITE_FOUR", trainerId = 414 }) == ID.BRUNO, "Bruno -> BRUNO")
check(BattleTransition.pickTrainer({ trainerClass = "ELITE_FOUR", trainerId = 416 }) == ID.AGATHA, "Agatha -> AGATHA")
check(BattleTransition.pickTrainer({ trainerClass = "ELITE_FOUR", trainerId = 418 }) == ID.LANCE, "Lance -> LANCE")
check(BattleTransition.pickTrainer({ trainerClass = "ELITE_FOUR", trainerId = 420 }) == ID.BLUE, "E4 Champion -> BLUE")
check(BattleTransition.pickTrainer({ trainerClass = "CHAMPION" }) == ID.BLUE, "Champion -> BLUE")
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

if failed > 0 then
  print(string.format("[FAIL] %d test(s) failed", failed))
  os.exit(1)
else
  print("[test] all passed")
end
