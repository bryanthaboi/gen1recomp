-- The Magnet Train ride (engine/events/magnet_train.asm).  ROM-free:
-- `luajit tests/gen2_magnet_train_test.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 magnet train")
local check, eq = S.check, S.eq

local MagnetTrain = require("src.core.gen2.MagnetTrain")
local Specials = require("src.script.gen2.Specials")

-- ---- the direction the officer's setval picks ------------------------------
--
--   ld a, [wScriptVar] / and a / jr nz, .ToGoldenrod
--
-- so Goldenrod's `setval FALSE` runs the forwards arm and Saffron's
-- `setval TRUE` runs .ToGoldenrod.
do
  local out = MagnetTrain.new({ toGoldenrod = false })
  eq(out.direction, 1, "forwards: wMagnetTrainDirection is 1")
  eq(out.initPosition, 96, "lb bc, 8 tiles, 12 tiles -> c is the init position")
  eq(out.holdPosition, 64, "...and b is the hold position")
  eq(out.finalPosition, 160,
    "lb de, (11 tiles) - (11 tiles + 4), -12 tiles -> e is the final position")
  eq(out.playerSpriteInitX, 252, "...and d is the player sprite's x, -4")

  local back = MagnetTrain.new({ toGoldenrod = true })
  eq(back.direction, 255, ".ToGoldenrod: -1, as a byte")
  eq(back.initPosition, 160, "and every position is its mirror")
  eq(back.holdPosition, 192, "hold")
  eq(back.finalPosition, 96, "final")
  eq(back.playerSpriteInitX, 180,
    "(11 tiles) + (11 tiles + 4) = 180, the far side of the screen")
end

-- ---- MagnetTrain_UpdateLYOverrides ----------------------------------------
--
-- Three runs of 6*8-1, 6*8 and 6*8+1 entries, which is 144 scanlines: bushes,
-- the train body, bushes.  The train band is the only one the jumptable moves.
do
  local ride = MagnetTrain.new({ toGoldenrod = false })
  ride:update()
  eq(#ride.ly, 144, "the three runs cover every scanline exactly once")
  local bands = ride:bands()
  eq(#bands, 3, "and they are three bands")
  eq(bands[1][1], 0, "band 1 opens at scanline 0")
  eq(bands[1][2], 46, "and closes at 46 (6 * TILE_WIDTH - 1 entries)")
  eq(bands[2][1], 47, "band 2 is the train")
  eq(bands[2][2], 94, "48 scanlines of it")
  eq(bands[3][1], 95, "and band 3 runs to the bottom")
  eq(bands[3][2], 143, "")
  eq(bands[1][3], bands[3][3], "the two bush bands share one SCX")
  eq(bands[2][3], ride.position, "the middle band IS wMagnetTrainPosition")
end

-- The scenery never stops: the offset advances two a frame whatever the
-- jumptable is doing, and the bands read offset * 2.
do
  local ride = MagnetTrain.new({ toGoldenrod = false })
  local first = ride.offset
  ride:update()
  eq(ride.offset, first + 2, "wMagnetTrainOffset gains `add d` twice a frame")
  local scx = ride:bands()[1][3]
  ride:update()
  eq(ride:bands()[1][3], (scx + 4) % 256, "so the bushes move four pixels")
  eq(ride.position, ride.initPosition,
    "while the train has not moved at all yet: state 0 is the sprite init")
end

-- ---- the jumptable ---------------------------------------------------------
--
-- .InitPlayerSpriteAnim, .WaitScene(128), .MoveTrain1 to the hold position,
-- .WaitScene(128), .MoveTrain2 at double speed to the final position,
-- .WaitScene(already 0), .TrainArrived.
do
  local ride = MagnetTrain.new({ toGoldenrod = false })
  eq(ride.index, 0, "the ride opens on .InitPlayerSpriteAnim")
  check(ride.spriteX == nil, "with no sprite struct yet")
  ride:update()
  eq(ride.index, 1, "which advances immediately")
  eq(ride.spriteX, ride.playerSpriteInitX, "having placed the player")
  eq(ride.spriteY, (8 + 2) * 8 + 5, "at d = (8 + 2) * TILE_WIDTH + 5")
  eq(ride.waitCounter, 128, "and armed the first 128 frame wait")

  -- .WaitScene holds for 129 frames: 128 decrements, then the pass that reads
  -- zero and advances.
  local frames = 0
  while ride.index == 1 do ride:update() frames = frames + 1 end
  eq(frames, 129, "a counter of 128 holds for 129 frames")
  eq(ride.index, 2, "then .MoveTrain1")

  frames = 0
  while ride.index == 2 do ride:update() frames = frames + 1 end
  -- 96 down to 64, a pixel a frame, plus the pass that notices it arrived.
  eq(frames, 33, ".MoveTrain1 walks 32 pixels and then prepares the hold")
  eq(ride.position, ride.holdPosition, "landing exactly on the hold position")
  eq(ride.globalX, 32,
    "wGlobalAnimXOffset tracks it pixel for pixel, which is what keeps the "
    .. "player locked to the window")
  eq(ride.waitCounter, 128, ".PrepareToHoldTrain re-arms the wait")

  while ride.index == 3 do ride:update() end
  eq(ride.index, 4, "the second wait ends on .MoveTrain2")
  frames = 0
  while ride.index == 4 do ride:update() frames = frames + 1 end
  -- 64 down to -96 in twos.
  eq(frames, 81, ".MoveTrain2 covers 160 pixels two at a time")
  eq(ride.position, ride.finalPosition, "and stops on the final position")
  eq(ride.globalX, 192, "the player has ridden the whole 160 with it")

  eq(ride.waitCounter, 0,
    "the third .WaitScene has a counter of 0 left over, so it passes straight "
    .. "through")
  local sfx = nil
  while not ride:done() do sfx = ride:update() or sfx end
  eq(sfx, "Sfx_TrainArrived", ".TrainArrived plays SFX_TRAIN_ARRIVED")
  check(ride:done(), "and sets JUMPTABLE_EXIT, which ends the loop")
  check(ride:update() == nil, "a finished ride does nothing more")
end

-- The trip back is the mirror image: the same frame count, the other way.
do
  local forward, back = 0, 0
  local a = MagnetTrain.new({ toGoldenrod = false })
  while not a:done() and forward < 2000 do a:update() forward = forward + 1 end
  local b = MagnetTrain.new({ toGoldenrod = true })
  while not b:done() and back < 2000 do b:update() back = back + 1 end
  eq(back, forward, "both directions run for the same number of frames")
  eq(a.globalX, 192, "forwards ends with the player 192 pixels along")
  eq(b.globalX, 64, "backwards ends 192 pixels the other way, as a byte")
end

-- ---- the player in the window ---------------------------------------------
--
-- .Frameset_MagnetTrainRed: OAM sets 1 and 2 on an eight frame beat, the
-- fourth mirrored, then oamrestart.  The object's sequence is
-- SPRITE_ANIM_FUNC_NULL, so nothing but wGlobalAnimXOffset ever moves it.
do
  local ride = MagnetTrain.new({ toGoldenrod = false })
  eq(#ride:playerOam(), 0, "nothing is drawn before .InitPlayerSpriteAnim")
  ride:update()
  eq(#ride:playerOam(), 0,
    "nor on the frame that creates the struct: PlaySpriteAnimations runs "
    .. "BEFORE MagnetTrain_Jumptable, so the first frame of the frameset is "
    .. "picked on the pass after the one that spawned it")
  ride:update()
  local oam = ride:playerOam()
  eq(#oam, 4, ".OAMData_MagnetTrainRed is a 2x2 block")
  eq(oam[1].tile, 0x00, "OAM set 1 is vtile $00")
  eq(MagnetTrain.SHEET_FRAME[0x00], 0,
    "which is ChrisSpriteGFX tile 0: the standing-down frame")
  eq(MagnetTrain.SHEET_FRAME[0x04], 3,
    "and vtile $04 is ChrisSpriteGFX + 12 tiles: the down walk frame")
  eq(oam[1].y, oam[2].y, "the top two tiles share a row")
  eq(oam[3].y - oam[1].y, 8, "and the bottom two sit eight pixels under them")

  -- The frameset holds each entry for nine passes (the one that sets the
  -- duration plus eight that decrement it).
  local seen, flipped = {}, {}
  for _ = 1, 9 * 4 do
    local entry = ride:playerOam()[1]
    seen[#seen + 1] = entry.tile
    flipped[#flipped + 1] = entry.xflip
    ride:update()
  end
  eq(seen[1], 0x00, "frame 1 is the standing tile")
  eq(seen[10], 0x04, "frame 2 the walk tile, nine passes later")
  eq(seen[19], 0x00, "frame 3 back to standing")
  eq(seen[28], 0x04, "frame 4 the walk tile again")
  check(flipped[28], "...and that fourth one is B_OAM_XFLIP")
  check(not flipped[1] and not flipped[10] and not flipped[19],
    "the other three are not")
  eq(seen[37 - 1], 0x04, "the 36th pass is still inside frame 4")
end

-- The player rides with the train: the sprite's x is its struct x plus
-- wGlobalAnimXOffset, which is the same counter the train band moves by.
do
  local ride = MagnetTrain.new({ toGoldenrod = false })
  while ride.index < 2 do ride:update() end
  local before = ride:playerOam()[1].x
  local band = ride:bands()[2][3]
  ride:update()
  eq(ride:playerOam()[1].x - before, 1, "the player moves a pixel")
  eq((band - ride:bands()[2][3]) % 256, 1, "and so does the train band")
end

-- ---- DrawMagnetTrain -------------------------------------------------------
--
-- Rows 0-17 are MagnetTrainBGTiles' pair for that row repeated across all 32
-- columns; MagnetTrainTilemap's four 20-tile lines land on rows 6-9.
do
  local bgTiles, tilemap = {}, {}
  for row = 0, 17 do
    bgTiles[row * 2 + 1] = row
    bgTiles[row * 2 + 2] = row + 100
  end
  for i = 1, 20 * 4 do tilemap[i] = 200 + i end

  local ride = MagnetTrain.new({ bgTiles = bgTiles, fgTilemap = tilemap })
  local rows = ride:tilemap()
  eq(#rows, 18, "eighteen screen rows")
  eq(#rows[1], 32, "each a full TILEMAP_WIDTH")
  eq(rows[1][1], 0, ".FillAlt writes e then d")
  eq(rows[1][2], 100, "")
  eq(rows[1][31], 0, "sixteen times over")
  eq(rows[6][1], 5, "row 5 is untouched by the train")
  eq(rows[7][1], 201, "row 6 is the first MagnetTrainTilemap line")
  eq(rows[10][20], 200 + 80, "and row 9 the last, twenty tiles wide")
  eq(rows[10][21], 9, "column 20 onward keeps the background strip")
  eq(rows[11][1], 10, "row 10 is background again")

  check(MagnetTrain.new({}):tilemap() == nil,
    "a cache with no tilemaps answers nil rather than inventing one")
end

-- ---- SetMagnetTrainPals ----------------------------------------------------
do
  eq(MagnetTrain.paletteSlot(0, 0), MagnetTrain.PAL_BG_GREEN,
    "four rows of bushes on top")
  eq(MagnetTrain.paletteSlot(31, 3), MagnetTrain.PAL_BG_GREEN, "")
  eq(MagnetTrain.paletteSlot(0, 4), MagnetTrain.PAL_BG_GRAY,
    "ten rows of train under them")
  eq(MagnetTrain.paletteSlot(0, 13), MagnetTrain.PAL_BG_GRAY, "")
  eq(MagnetTrain.paletteSlot(0, 14), MagnetTrain.PAL_BG_GREEN,
    "and four more rows of bushes at the bottom")
  eq(MagnetTrain.paletteSlot(7, 8), MagnetTrain.PAL_BG_YELLOW,
    "the window is six tiles at (7, 8)")
  eq(MagnetTrain.paletteSlot(12, 8), MagnetTrain.PAL_BG_YELLOW, "")
  eq(MagnetTrain.paletteSlot(13, 8), MagnetTrain.PAL_BG_GRAY,
    "and no wider than that")
  eq(MagnetTrain.paletteSlot(7, 9), MagnetTrain.PAL_BG_GRAY,
    "nor any taller")
end

-- ---- special MagnetTrain ---------------------------------------------------
--
-- The routine READS wScriptVar and never writes it, so the handler must leave
-- vm.scriptVar exactly as the officer's `setval` left it.
do
  check(Specials.HANDLERS.MagnetTrain, "MagnetTrain is a handler now")
  check(not Specials.STUBS.MagnetTrain, "and no longer a stub")

  local calls = {}
  local vm = {
    scriptVar = 0,
    specials = {
      magnetTrain = function(toGoldenrod, done)
        calls[#calls + 1] = toGoldenrod
        done()
      end,
    },
  }
  Specials.ALL.MagnetTrain(vm)
  eq(#calls, 1, "the hook is called once")
  eq(calls[1], false, "wScriptVar 0 is the forwards trip")
  eq(vm.scriptVar, 0, "and wScriptVar comes back untouched")

  vm.scriptVar = 1
  Specials.ALL.MagnetTrain(vm)
  eq(calls[2], true, "wScriptVar 1 is .ToGoldenrod")
  eq(vm.scriptVar, 1, "still untouched")

  local bare = { scriptVar = 7, specials = {} }
  Specials.ALL.MagnetTrain(bare)
  eq(bare.scriptVar, 7,
    "and with no hook at all the special is a no-op, not a clobber")
end

-- ---- MagnetTrainRide UI screen --------------------------------------------
do
  local MagnetTrainRide = require("src.ui.gen2.MagnetTrainRide")
  check(MagnetTrainRide.isOpaque, "MagnetTrainRide is opaque")
  local ride = MagnetTrainRide.new(nil, { toGoldenrod = false })
  check(ride:wantsFillScale(), "wantsFillScale returns true")
  check(ride:drawsWidescreen(), "drawsWidescreen returns true")
  check(type(ride.drawBands) == "function", "drawBands exists")
  check(type(ride.backgrounds) == "function", "backgrounds exists for OAM_PRIO")
end


-- ---- the arrival, from `warpcheck` to the officer's line -------------------
--
-- The ride is only half the feature: the two station scripts end
--
--     special MagnetTrain
--     warpcheck
--     newloadmap MAPSETUP_TRAIN
--
-- and everything the player actually SEES on the far side hangs off the coord
-- event the load leaves them one step away from.  These check that chain
-- against the real map data, because each link is a place the port could be
-- complete and still reach nobody.  They need the gold cache.
do
  local cache = os.getenv("GOLD_CACHE")
  if not cache then
    local home = os.getenv("HOME") or ""
    cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local probe = io.open(cache .. "/data/generated/maps.lua", "r")
  if not probe then
    check(true, "gold cache absent : ride checks only (SKIP the arrival)")
    S.finish()
    return
  end
  probe:close()

  local function loadLua(rel) return assert(loadfile(cache .. "/" .. rel))() end
  local maps = loadLua("data/generated/maps.lua")
  local tilesets = loadLua("data/generated/tilesets.lua")
  local scripts = loadLua("data/generated/scripts.lua")

  local World = require("src.world.gen2.World")
  local Map = require("src.world.gen2.Map")
  local Permissions = require("src.world.gen2.Permissions")

  local GOLDENROD = "GOLDENROD_MAGNET_TRAIN_STATION"
  local SAFFRON = "SAFFRON_MAGNET_TRAIN_STATION"

  -- maps/GoldenrodMagnetTrainStation.asm and maps/SaffronMagnetTrainStation.asm
  -- carry the same four warp_events, and the two train doors cross over: the
  -- door the player walks INTO at x 6 comes out of the far station's door at
  -- x 11.  That crossing is what decides the arrival cell, so it is checked
  -- before anything that depends on it.
  for _, pair in ipairs({ { GOLDENROD, SAFFRON }, { SAFFRON, GOLDENROD } }) do
    local here, there = maps[pair[1]], maps[pair[2]]
    eq(here.warps[3].x, 6, pair[1] .. " warp 3 is the boarding door")
    eq(here.warps[3].y, 5, "on the platform's top row")
    eq(here.warps[3].destMap, pair[2], "leading to the other station")
    eq(here.warps[3].destWarp, 4, "and out of ITS warp 4")
    eq(there.warps[4].x, 11, "which stands at x 11")
    eq(there.warps[4].y, 5, "on the same top row")
  end

  -- Script_ArriveFromGoldenrod / Script_ArriveFromSaffron: one coord_event per
  -- map, on scene 0 (`def_scene_scripts`' const_def is 0-based and the arrive
  -- scene is its first entry, which is also the scene a fresh save is on).
  for _, id in ipairs({ GOLDENROD, SAFFRON }) do
    local evs = maps[id].coordEvents or {}
    eq(#evs, 1, id .. " has exactly one coord_event")
    eq(evs[1].x, 11, "at x 11")
    eq(evs[1].y, 6, "and y 6, one cell SOUTH of the arrival door")
    eq(evs[1].sceneId or 0, 0, "on the arrive scene, which is scene 0")
    local body = scripts[evs[1].scriptKey]
    check(body, "and its script body is in the cache")
    eq(body[1].op, "applymovement", "officer steps up to the train door")
    eq(body[2].op, "applymovement", "the player walks off the train")
    eq(body[4].op, "opentext", "and only then does the officer talk")
  end

  -- A World over the real defs, driven the way the station script drives it.
  local function station(id)
    local game = { data = { audio = { sfxOrder = {} } }, save = { player = {} } }
    local world = World.new(game)
    world.maps, world.tilesets = maps, tilesets
    world.map = Map.new(maps[id], tilesets[maps[id].tileset])
    world.map.def = maps[id]
    world.player = { cellX = 6, cellY = 5, facing = "up", moving = false }
    return world
  end

  for _, pair in ipairs({ { GOLDENROD, SAFFRON }, { SAFFRON, GOLDENROD } }) do
    local world = station(pair[1])
    local loaded
    world.setMap = function(_, id, x, y, facing)
      loaded = { id = id, x = x, y = y, facing = facing }
      return true
    end

    -- `warpcheck`, run standing on the boarding door the applymovement walked
    -- the player onto.
    check(world:armWarpCheck(), pair[1] .. ": warpcheck finds the train door")
    eq(world.pendingWarp.destMap, pair[2], "armed for the other station")

    -- `newloadmap MAPSETUP_TRAIN`.  EnterMapWarp then GetWarpDestCoords, so the
    -- load goes to the DESTINATION warp's own cell rather than back onto the
    -- cell underfoot, and _Train carries no SpawnInFacingDown so the facing the
    -- player boarded with survives.
    world:newLoadMap(0xf9)
    check(loaded, "newloadmap MAPSETUP_TRAIN loads a map")
    eq(loaded.id, pair[2], "the far station")
    eq(loaded.x, 11, "at the destination warp's x")
    eq(loaded.y, 5, "and its y : the train doorway, NOT the coord_event")
    eq(loaded.facing, "up", "still facing the way they walked aboard")
    check(world.pendingWarp == nil, "and the armed warp is spent")
  end

  -- Why (11,5) is not an off-by-one.  Block $12 of TILESET_TRAIN_STATION is
  -- `tilecoll WALL, WALL, WALL, DOOR`, so the doorway's only open neighbour is
  -- the cell to the SOUTH -- which is the coord_event.  The arrival
  -- conversation is reached by that one forced step, exactly as the cart
  -- reaches it: EnterMap runs DisableEvents, and CheckPlayerState only turns
  -- player events back on once a step finishes.
  for _, id in ipairs({ GOLDENROD, SAFFRON }) do
    local map = Map.new(maps[id], tilesets[maps[id].tileset])
    check(Permissions.isWarpCollision(map:cellCollision(11, 5)),
      id .. ": the arrival cell is the train doorway")
    check(map:isWalkable(11, 6), "south of it is the platform")
    check(not map:isWalkable(10, 5), "west is wall")
    check(not map:isWalkable(12, 5), "east is wall")
    check(not map:isWalkable(11, 4), "and north is wall")
  end

  -- The step itself: World:tryCoordScript is what the overworld loop calls on
  -- the frame the player lands, and it is the only thing that starts the
  -- arrival script.
  for _, id in ipairs({ GOLDENROD, SAFFRON }) do
    local world = station(id)
    local started
    world.vm = { start = function(_, key) started = key return true end }
    world.busy = function() return false end

    world.player = { cellX = 11, cellY = 5, facing = "up", moving = false }
    check(not world:tryCoordScript(),
      id .. ": standing in the doorway starts nothing")

    world.player = { cellX = 11, cellY = 6, facing = "down", moving = false }
    check(world:tryCoordScript(), "the step south starts the arrival script")
    eq(started, maps[id].coordEvents[1].scriptKey,
      "which is the map's own coord_event script")
  end
end

S.finish()
