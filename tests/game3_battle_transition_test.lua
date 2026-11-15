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
local even = BattleTransition.blackSpans(1, -120, 360)
local odd = BattleTransition.blackSpans(2, -120, 360)
check(even[1] == -120 and even[2] > -120, "screen row 1 (buffer row 0, even) grows from the left window edge")
check(odd[2] == 360 and odd[1] < 360, "screen row 2 (buffer row 1, odd) grows from the right window edge")
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
check(H.winH == nil, "only the hardware WIN0H decoder is exported")
hn = H.winOutside(H.WIN_RANGE(120, 40), hs)
check(hn == 1 and hs[1] == 40 and hs[2] == 120, "outside of a wrapped WIN0H is the gap between its two spans")
hn = H.winOutside(H.WIN_RANGE(243, 244), hs)
check(hn == 1 and hs[1] == 0 and hs[2] == 240, "outside of an empty WIN0H is the whole row")
hn = H.winInside(H.WIN_RANGE(80, 120), hs, H.winInside(H.WIN_RANGE(120, 40), hs))
check(hn == 3 and hs[1] == 0 and hs[2] == 40 and hs[3] == 120 and hs[4] == 240 and hs[5] == 80 and hs[6] == 120,
  "inside spans of two windows append in order")

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

print("[test] 11. SHRED_SPLIT decodes WIN0H like the hardware window, one scanline late")
local FULL = { 0, 240 }
local function same(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end
local function spansOf(fn, v)
  local ws = {}
  local n = fn(v, ws)
  local out = {}
  for i = 1, 2 * n do out[i] = ws[i] end
  return out
end
local function shred(cameraX, frames)
  local keys = { "rows", "right", "left", "alias", "follow", "black", "strip" }
  local seen, bad = {}, {}
  for _, k in ipairs(keys) do seen[k], bad[k] = 0, 0 end
  local aliasWin = (cameraX - 240) % 0x10000
  local aliasWant = spansOf(H.winOutside, aliasWin)
  local finished = false
  local last159
  BattleTransition.start(BattleTransition.ids().ID.SHRED_SPLIT, { skipIntro = true, cameraX = cameraX },
    function() finished = true end)
  for _ = 1, frames do
    BattleTransition.tick(1 / 60)
    local fx = BattleTransition._fx
    if finished or not fx or fx.pal.slots[0].y >= 16 then break end
    local s1 = fx.shred1
    local rows, lit = {}, false
    for y = 0, 159 do
      local win
      if y == 0 then win = last159 else win = s1[160 + y - 1] end
      local s = BattleTransition.blackSpans(y, 0, 240)
      rows[y] = s
      if y ~= 1 and not same(s, FULL) then lit = true end
      if win then
        seen.rows = seen.rows + 1
        if not same(s, spansOf(H.winOutside, win)) then bad.rows = bad.rows + 1 end
      end
      if win == 0xFFFA then
        seen.right = seen.right + 1
        if #s ~= 0 then bad.right = bad.right + 1 end
      elseif win == 0xF6F1 then
        seen.left = seen.left + 1
        if #s ~= 0 then bad.left = bad.left + 1 end
      end
    end
    local alias = s1[160] == aliasWin
    if alias then
      seen.alias = seen.alias + 1
      if not same(rows[1], aliasWant) then bad.alias = bad.alias + 1 end
    end
    for d = 1, 16 do
      local up = BattleTransition.blackSpans(-d, 0, 240)
      local down = BattleTransition.blackSpans(159 + d, 0, 240)
      if lit then
        seen.follow = seen.follow + 2
        if not same(up, rows[0]) then bad.follow = bad.follow + 1 end
        if not same(down, rows[159]) then bad.follow = bad.follow + 1 end
      else
        seen.black = seen.black + 2
        if not same(up, FULL) then bad.black = bad.black + 1 end
        if not same(down, FULL) then bad.black = bad.black + 1 end
      end
      if alias then
        seen.strip = seen.strip + 1
        if same(up, aliasWant) then bad.strip = bad.strip + 1 end
      end
    end
    last159 = s1[160 + 159]
  end
  BattleTransition.abort()
  return seen, bad, aliasWant
end
local function shredChecks(label, seen, bad)
  check(seen.rows > 0 and bad.rows == 0,
    string.format("SHRED_SPLIT %s screen row y shows WIN0H buffer row y-1, row 0 the last frame's row 159 (%d of %d wrong)",
      label, bad.rows, seen.rows))
  check(seen.follow > 0 and bad.follow == 0,
    string.format("SHRED_SPLIT %s margin rows follow the edge rows while the field shows (%d of %d wrong)", label,
      bad.follow, seen.follow))
  check(seen.black > 0 and bad.black == 0,
    string.format("SHRED_SPLIT %s margin rows go black once the shred covers the screen (%d of %d wrong)", label,
      bad.black, seen.black))
  check(seen.strip > 0 and bad.strip == 0,
    string.format("SHRED_SPLIT %s alias strip stays one row tall (%d of %d margin rows show it)", label,
      bad.strip, seen.strip))
end
local seen, bad, aliasWant = shred(0, 400)
check(seen.right > 0 and bad.right == 0,
  string.format("SHRED_SPLIT right-row overshoot 0xFFFA shows the whole row (%d of %d black)", bad.right, seen.right))
check(seen.left > 0 and bad.left == 0,
  string.format("SHRED_SPLIT left-row overshoot 0xF6F1 shows the whole row (%d of %d black)", bad.left, seen.left))
check(aliasWant[1] == 16 and seen.alias > 0 and bad.alias == 0,
  string.format("SHRED_SPLIT row 0 alias 0xFF10 reaches screen row 1 and shows x 0..15 (%d of %d wrong)", bad.alias,
    seen.alias))
shredChecks("cameraX 0", seen, bad)
seen, bad, aliasWant = shred(208, 400)
check(aliasWant[1] == 224 and seen.alias > 0 and bad.alias == 0,
  string.format("SHRED_SPLIT panned camera alias 0xFFE0 reaches screen row 1 and shows x 0..223 (%d of %d wrong)",
    bad.alias, seen.alias))
shredChecks("cameraX 208", seen, bad)

print("[test] 12. Scanline buffers reach the screen one row late")
local bit = require("bit")
local function runFrames(name, frames, perFrame)
  local finished = false
  BattleTransition.start(BattleTransition.ids().ID[name], { skipIntro = true }, function() finished = true end)
  for f = 1, frames do
    BattleTransition.tick(1 / 60)
    local fx = BattleTransition._fx
    if finished or not fx or fx.pal.slots[0].y >= 16 then break end
    perFrame(fx, f)
  end
  BattleTransition.abort()
end

local function winCase(label, name, field, decode, row0)
  local seen, bad, prev = 0, 0, nil
  runFrames(name, 600, function(fx)
    local buf = fx[field]
    if buf then
      for y = 0, 159 do
        local want
        if y > 0 then
          want = spansOf(decode, buf[y - 1])
        elseif row0 == "first" then
          want = spansOf(decode, buf[0])
        elseif prev then
          want = spansOf(decode, prev[1])
        else
          want = {}
        end
        seen = seen + 1
        if not same(BattleTransition.blackSpans(y), want) then bad = bad + 1 end
      end
    end
    prev = buf and { buf[159] } or nil
  end)
  check(seen > 0 and bad == 0, string.format("%s %s row y shows buffer row y-1, row 0 %s (%d of %d wrong)", label, name,
    row0 == "first" and "buffer row 0" or "the last frame's row 159", bad, seen))
end

local function waveX(w, y)
  local x = w.x + H.Sin(bit.band(w.idx + 4 * y, 0xFF), 40)
  if x < 0 then x = 0 end
  if x > 240 then x = 240 end
  return x
end
local function waveCase(label)
  local seen, bad, prevW = 0, 0, nil
  runFrames("WAVE", 200, function(fx)
    local w = fx.wv1
    if w then
      for y = 0, 159 do
        local src = y > 0 and w or prevW
        local x = src and waveX(src, y > 0 and y - 1 or 159) or 0
        local want = x > 0 and { 0, x } or {}
        seen = seen + 1
        if not same(BattleTransition.blackSpans(y), want) then bad = bad + 1 end
      end
    end
    prevW = w
  end)
  check(seen > 0 and bad == 0, string.format("%s WAVE row y shows waveX(y-1), row 0 last frame's row 159 (%d of %d wrong)",
    label, bad, seen))
end

local function sliceCase(label)
  local seen, bad, prevE = 0, 0, 0
  runFrames("SLICE", 200, function(fx)
    local e = fx.sl1 or 0
    for y = 0, 159 do
      local ee, odd = e, y > 0 and (y - 1) % 2 == 1
      if y == 0 then ee, odd = prevE, true end
      local want = {}
      if ee > 0 then want = odd and { 240 - ee, 240 } or { 0, ee } end
      local dx = BattleTransition.rowShift(y)
      seen = seen + 1
      if not same(BattleTransition.blackSpans(y), want) or dx ~= (odd and ee or -ee) then bad = bad + 1 end
    end
    prevE = e
  end)
  check(seen > 0 and bad == 0,
    string.format("%s SLICE rows and HOFS follow buffer row y-1, row 0 last frame's row 159 (%d of %d wrong)", label,
      bad, seen))
end

local function shiftCase(label, name, field, formula)
  local seen, bad = 0, 0
  runFrames(name, 300, function(fx)
    local w = fx[field]
    if w then
      for y = 0, 159 do
        local wantX, wantY = formula(w, y > 0 and y - 1 or 0)
        local dx, dy = BattleTransition.rowShift(y)
        seen = seen + 1
        if dx ~= wantX or dy ~= wantY then bad = bad + 1 end
      end
    end
  end)
  check(seen > 0 and bad == 0, string.format("%s %s row y scrolls by buffer row y-1, row 0 by row 0 (%d of %d wrong)",
    label, name, bad, seen))
end
local function swirl(w, y) return H.Sin(w.idx + 2 * y, w.amp), 0 end
local function shuffle(s, y) return 0, H.Sin(bit.rshift(H.u16(s.sinVal + 4224 * y), 8), s.amp) end
local function ripple(s, y) return 0, H.Sin(bit.rshift(H.u16(s.sinVal + 384 * y), 8), s.amp) end

local function scanlineCases(label)
  waveCase(label)
  sliceCase(label)
  shiftCase(label, "SWIRL", "wave1", swirl)
  shiftCase(label, "SHUFFLE", "sh1", shuffle)
  shiftCase(label, "RIPPLE", "rp1", ripple)
  winCase(label, "CLOCKWISE_WIPE", "buf1", H.winHSpans, "first")
  winCase(label, "ANGLED_WIPES", "buf1", H.winOutside, "first")
end

scanlineCases("FRLG")
winCase("FRLG", "BIG_POKEBALL", "mask1", H.winOutside, "prev")
Profile.reset()
GameVersion.set("emerald")
scanlineCases("Emerald")
winCase("Emerald", "BIG_POKEBALL", "mask1", H.winOutside, "prev")
winCase("Emerald", "BLACKHOLE", "hole1", H.winHSpans, "prev")
winCase("Emerald", "BLACKHOLE_PULSATE", "hole1", H.winHSpans, "prev")

local function whiteBarsRow0(label)
  local def = BattleTransition.defs()[BattleTransition.ids().ID.WHITE_BARS_FADE]
  local rows, alpha = {}, 0
  local G = {
    setColor = function(_, _, _, a) alpha = a or 1 end,
    rectangle = function(_, x, y, w, h)
      if h == 1 then rows[y] = { x = x, w = w, v = math.floor(alpha * 16 + 0.5) } end
    end,
  }
  local R = { X0 = 0, X1 = 240, Y0 = 0, Y1 = 160, hmap = function(x) return x end, hmapR = function(x) return x end }
  local seen, bad, darkTop, prev319 = 0, 0, 0, nil
  runFrames("WHITE_BARS_FADE", 400, function(fx)
    if fx.darkenPhase or not fx.buf1 then return end
    rows = {}
    def.post(fx, R, G)
    local want = math.min(16, bit.band(fx.buf1[227] or 0, 0x1F))
    local got = rows[0] and rows[0].v or 0
    if prev319 and prev319 < 240 then
      seen = seen + 1
      if got ~= want then bad = bad + 1 end
    end
    if got == 0 and rows[1] and rows[1].v == 16 then darkTop = darkTop + 1 end
    prev319 = fx.buf1[319]
  end)
  check(seen > 0 and bad == 0, string.format("%s WHITE_BARS_FADE row 0 BLDY is buffer entry 227 (%d of %d wrong)",
    label, bad, seen))
  check(darkTop > 0, string.format("%s WHITE_BARS_FADE row 0 stays unlit while row 1 is white (%d frames)", label,
    darkTop))
end
whiteBarsRow0("Emerald")
Profile.reset()
GameVersion.set("firered")

if failed > 0 then
  print(string.format("[FAIL] %d test(s) failed", failed))
  os.exit(1)
else
  print("[test] all passed")
end
