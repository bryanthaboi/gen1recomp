#!/usr/bin/env luajit
-- pokefirered/src/field_screen_effect.c:18, :90, :118, :194
-- pokefirered/src/overworld.c:956, :966
-- pokefirered/src/field_effect.c:1258
-- pokefirered/src/event_data.c:49

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local FieldView = require("src.core.game3.field_view")
local FieldEffects = require("src.core.game3.field_effects")
local Runtime = require("src.core.game3.runtime")

-- pokefirered/include/constants/flags.h:1333
local FLAG_SYS_FLASH_ACTIVE = 0x806
-- pokefirered/include/constants/map_types.h:7
local MAP_TYPE_ROUTE = 3
local MAP_TYPE_UNDERGROUND = 4

print("[test] 1. the flash level API exists")
check(type(FieldView.setFlashLevel) == "function", "FieldView.setFlashLevel exists")
check(type(FieldView.getFlashLevel) == "function", "FieldView.getFlashLevel exists")
check(type(FieldView.flashSpans) == "function", "FieldView.flashSpans exists")
check(type(FieldView.flashSpansFor) == "function", "FieldView.flashSpansFor exists")
check(type(FieldView.setCameraPanning) == "function", "FieldView.setCameraPanning exists")
check(type(FieldEffects.animateFlashLevel) == "function", "FieldEffects.animateFlashLevel exists")
check(type(FieldEffects.startLandingShake) == "function", "FieldEffects.startLandingShake exists")
if type(FieldView.flashSpans) ~= "function" or type(FieldEffects.startLandingShake) ~= "function" then
  print("[test] no field darkness / camera pan system at all; the rest cannot run")
  finish()
end

print("[test] 2. sFlashLevelToRadius")
eq(FieldView.MAX_FLASH_LEVEL, 4, "gMaxFlashLevel is ARRAY_COUNT(sFlashLevelToRadius) - 1")
local RADII = { [0] = 200, 72, 56, 40, 24 }
for level = 0, 4 do
  eq(FieldView.radiusForLevel(level), RADII[level], "radius of level " .. level)
end

print("[test] 3. SetFlashLevel clamps out of range to 0")
FieldView.setFlashLevel(3)
eq(FieldView.getFlashLevel(), 3, "level 3 sticks")
FieldView.setFlashLevel(5)
eq(FieldView.getFlashLevel(), 0, "level 5 is out of range, so 0")
FieldView.setFlashLevel(-1)
eq(FieldView.getFlashLevel(), 0, "level -1 is out of range, so 0")
FieldView.setFlashLevel(0)
eq(FieldView.flashRadius(), nil, "level 0 draws no mask at all")
FieldView.setFlashLevel(4)
eq(FieldView.flashRadius(), 24, "level 4 masks down to a 24px radius")

print("[test] 4. SetDefaultFlashLevel from the map header")
local prevSession = Runtime.session
Runtime.session = { flags = {} }
local game = {
  data = {
    maps = {
      CAVE = { id = "CAVE", cave = 1, mapType = MAP_TYPE_UNDERGROUND },
      TUNNEL = { id = "TUNNEL", cave = 1, mapType = MAP_TYPE_UNDERGROUND },
      LIT = { id = "LIT", cave = 0, mapType = MAP_TYPE_UNDERGROUND },
      ROUTE = { id = "ROUTE", cave = 0, mapType = MAP_TYPE_ROUTE },
    },
  },
}
eq(FieldView.defaultFlashLevel(game, "CAVE"), 4, "a cave map with no Flash is fully dark")
eq(FieldView.defaultFlashLevel(game, "LIT"), 0, "an underground map that is not a cave is lit")
eq(FieldView.defaultFlashLevel(game, "ROUTE"), 0, "a route is lit")
Runtime.session.flags[FLAG_SYS_FLASH_ACTIVE] = true
eq(FieldView.defaultFlashLevel(game, "CAVE"), 0, "FLAG_SYS_FLASH_ACTIVE lights the cave")
eq(FieldView.defaultFlashLevel(game, "ROUTE"), 0, "the flag changes nothing outdoors")
Runtime.session.flags[FLAG_SYS_FLASH_ACTIVE] = nil
eq(FieldView.setDefaultFlashLevel(game, "CAVE"), 4, "entering the cave sets the level")
eq(FieldView.getFlashLevel(), 4, "the level is live after the map load")
eq(FieldView.setDefaultFlashLevel(game, "ROUTE"), 0, "leaving for a route clears it")
eq(FieldView.flashRadius(), nil, "and nothing is masked outdoors")

-- pokefirered/src/overworld.c:958
print("[test] 4b. the cave answer comes off the map def, never off the cache")
local Dataset = require("src.core.game3.dataset")
local realDatasetCache = Dataset.cache
Dataset.cache = function() error("defaultFlashLevel must not read header.json") end
eq(FieldView.defaultFlashLevel(game, "TUNNEL"), 4, "a cave def is dark with the cache reader gone")
eq(FieldView.defaultFlashLevel(game, "ROUTE"), 0, "a non-cave def is lit with the cache reader gone")
game.data.maps.FR_ROCK_TUNNEL_1F = { id = "FR_ROCK_TUNNEL_1F", mapType = MAP_TYPE_UNDERGROUND }
local okNoField, noFieldLevel = pcall(FieldView.defaultFlashLevel, game, "FR_ROCK_TUNNEL_1F")
check(okNoField, "a def carrying no cave field never falls through to the cache reader")
eq(okNoField and noFieldLevel, 0, "it answers lit instead")
eq(game.data.maps.FR_ROCK_TUNNEL_1F.cave, nil, "and nothing is stamped back onto the def")
eq(FieldView.defaultFlashLevel(game, "NO_DEF"), 0, "a map with no def at all is lit, not an error")
Dataset.cache = realDatasetCache

print("[test] 5. the scanline window is pret's circle")
local W, H = 240, 160
local function windowRows(radius)
  local rows = {}
  for _, s in ipairs(FieldView.flashSpans(radius, W, H)) do
    for y = s.y, s.y + s.height - 1 do
      rows[y] = { left = s.left, right = s.right }
    end
  end
  return rows
end
local rows24 = windowRows(24)
eq(rows24[80] ~= nil and rows24[80].left, 96, "the widest row starts 24px left of centre")
eq(rows24[80] ~= nil and rows24[80].right, 144, "and ends 24px right of centre")
check(rows24[0].left == 0 and rows24[0].right == 0,
  "the top scanline is entirely outside the window")
check(rows24[H - 1].left == 0 and rows24[H - 1].right == 0,
  "so is the bottom scanline")
local area, asym = 0, 0
for y = 0, H - 1 do
  local r = rows24[y]
  local vis = math.max(0, r.right - r.left)
  area = area + vis
  local mirror = rows24[160 - y]
  if mirror and math.max(0, mirror.right - mirror.left) ~= vis then asym = asym + 1 end
end
eq(asym, 0, "the circle is symmetric about its centre row")
check(math.abs(area - math.pi * 24 * 24) < 120,
  string.format("the lit area %d approximates pi*r^2 %d", area, math.floor(math.pi * 576)))
local rows72 = windowRows(72)
eq(rows72[80].right - rows72[80].left, 144, "level 1 opens a 72px radius")
local rows200 = windowRows(200)
local full = true
for y = 0, H - 1 do
  if rows200[y].left ~= 0 or rows200[y].right < W then full = false end
end
check(full, "the level 0 radius covers the whole 240x160 screen")

print("[test] 6. AnimateFlash grows the radius by 2 every other frame")
FieldView.setFlashLevel(4)
FieldEffects._anims = {}
FieldEffects.animateFlashLevel(4, 0)
local samples = {}
local frames = 0
for _ = 1, 400 do
  FieldEffects.step()
  frames = frames + 1
  samples[#samples + 1] = FieldView.flashRadius()
  if #FieldEffects._anims == 0 then break end
end
eq(samples[1], 24, "frame 1 still holds the cave radius")
eq(samples[2], 24, "frame 2 as well: one step of the task is two frames")
eq(samples[3], 26, "frame 3 is 2px wider")
eq(samples[4], 26, "frame 4 holds it")
eq(samples[5], 28, "frame 5 is 4px wider")
eq(frames, 2 * ((200 - 24) / 2 + 1) + 1,
  "88 growth pairs, the overshoot pair, then the ScanlineEffect_Clear frame")
eq(FieldView.getFlashLevel(), 0, "setflashlevel 0 lands when the animation ends")
eq(FieldView.flashRadius(), nil, "and the mask is gone")
eq(#FieldEffects._anims, 0, "the task destroyed itself")

print("[test] 7. using Flash animates only where it is dark")
FieldEffects._anims = {}
FieldView.setFlashLevel(4)
FieldEffects.startFlash()
local hasLevelAnim = false
for _, a in ipairs(FieldEffects._anims) do
  if a.kind == "flash_level" then hasLevelAnim = true end
end
check(hasLevelAnim, "FldEff_UseFlash runs EventScript_FldEffFlash in a dark cave")
FieldEffects._anims = {}
FieldView.setFlashLevel(0)
FieldEffects.startFlash()
hasLevelAnim = false
for _, a in ipairs(FieldEffects._anims) do
  if a.kind == "flash_level" then hasLevelAnim = true end
end
check(not hasLevelAnim, "a lit map animates no flash level (and never shrinks forever)")
FieldEffects._anims = {}

-- pokefirered/src/field_screen_effect.c:202
print("[test] 7b. the Flash unlock waits for the whole AnimateFlash")
FieldEffects._anims = {}
FieldView.setFlashLevel(4)
local unlockedAt, radiusAtUnlock, endedAt = nil, nil, nil
FieldEffects.startFlash(function() unlockedAt = endedAt end)
for f = 1, 400 do
  endedAt = f
  FieldEffects.step()
  if unlockedAt and not radiusAtUnlock then radiusAtUnlock = FieldView.flashRadius() or false end
  if #FieldEffects._anims == 0 then break end
end
eq(unlockedAt, 179, "LockPlayerFieldControls is released on the frame the task dies")
eq(endedAt, 179, "and that is the last frame of the animation")
eq(radiusAtUnlock, false, "no partial mask survives the unlock")
eq(FieldView.getFlashLevel(), 0, "flash level 0 is in place by then")
FieldEffects._anims = {}
FieldView.setFlashLevel(0)
unlockedAt, endedAt = nil, nil
FieldEffects.startFlash(function() unlockedAt = endedAt end)
for f = 1, 120 do
  endedAt = f
  FieldEffects.step()
  if #FieldEffects._anims == 0 then break end
end
eq(unlockedAt, 30, "with no darkness to open, the 30-frame flourish still unlocks")
FieldEffects._anims = {}

print("[test] 7c. the mask span list is built once per radius, not once per frame")
FieldView._flashSpans = nil
local spans1 = FieldView.flashSpansFor(24, 240, 160, 120, 80)
local spans2 = FieldView.flashSpansFor(24, 240, 160, 120, 80)
check(rawequal(spans1, spans2), "the same geometry hands back the same table")
for _ = 1, 3000 do FieldView.flashSpansFor(24, 240, 160, 120, 80) end
collectgarbage("collect")
local before = collectgarbage("count")
for i = 1, 20000 do FieldView.flashSpansFor(24 + (i % 2), 240, 160, 120, 80) end
local rebuilt = collectgarbage("count") - before
collectgarbage("collect")
before = collectgarbage("count")
for _ = 1, 20000 do FieldView.flashSpansFor(24, 240, 160, 120, 80) end
local grew = collectgarbage("count") - before
check(rebuilt > 100, string.format("a moving radius allocates (%.0f KB), so the check is live", rebuilt))
check(grew * 50 < rebuilt,
  string.format("20000 draws at one radius allocate nothing (%.2f KB against %.0f KB)", grew, rebuilt))
local spans3 = FieldView.flashSpansFor(26, 240, 160, 120, 80)
check(not rawequal(spans1, spans3), "a changed radius rebuilds the spans")
FieldView._flashSpans = nil
FieldView._flashSpanR = nil

print("[test] 8. FallWarpEffect_6 halves the camera pan every four frames")
FieldView.setCameraPanning(0, 0)
FieldEffects.startLandingShake()
local pan = {}
for _ = 1, 20 do
  FieldEffects.step()
  pan[#pan + 1] = FieldView.cameraPanY
  if #FieldEffects._anims == 0 then break end
end
local EXPECT = { 4, -4, 4, -4, 2, -2, 2, -2, 1, -1, 1, -1, 0 }
eq(#pan, #EXPECT, "the shake runs 12 panned frames and one reset frame")
for i = 1, #EXPECT do
  eq(pan[i], EXPECT[i], "pan frame " .. i)
end
eq(FieldView.cameraPanY, 0, "InstallCameraPanAheadCallback puts the camera back")
eq(FieldView.cameraPanX, 0, "SetCameraPanning(0, y) never pans sideways")

print("[test] 9. the temp field flags are cleared where pret clears them")
local mapSrc = io.open("src/core/game3/map.lua", "r")
local mapText = mapSrc and mapSrc:read("*a") or ""
if mapSrc then mapSrc:close() end
check(not mapText:find("0x804", 1, true),
  "map.lua no longer clears FLAG_SYS_BLACK_FLUTE_ACTIVE believing it is Strength")
local Field = require("src.core.game3.field")
local FieldMoves = require("src.core.game3.field_moves")
eq(FieldMoves.SYS_FLAGS.BLACK_FLUTE_ACTIVE, 0x804, "0x804 is the black flute")
eq(FieldMoves.SYS_FLAGS.USE_STRENGTH, 0x805, "0x805 is Strength")
Field._session = { flags = { [0x803] = true, [0x804] = true, [0x805] = true, [0x806] = true } }
Field.clearTempFieldEventData(game, "CAVE")
eq(Field._session.flags[0x805], nil, "ClearTempFieldEventData clears Strength")
eq(Field._session.flags[0x804], nil, "and the black flute")
eq(Field._session.flags[0x803], nil, "and the white flute")
eq(Field._session.flags[0x806], true, "Flash survives a cave to cave warp")
Field._session.flags[0x805] = true
Field.clearTempFieldEventData(game, "ROUTE")
eq(Field._session.flags[0x806], nil, "and is dropped the moment the player is outdoors")
eq(Field._session.flags[0x805], nil, "Strength goes outdoors too")
Field._session = nil

Runtime.session = prevSession
finish()
