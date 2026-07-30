-- Manual check that the exit mat you warp in on answers the first press of
-- DOWN (#378).  The house door outside is a door tile, so it leaves
-- BIT_STANDING_ON_WARP set and ClearVariablesOnEnterMap never clears it
-- (home/overworld.asm:247, engine/overworld/player_state.asm:190).
--   POKEPORT_DRIVER=tests/drivers/exit_mat_bug378_test.lua POKEPORT_IDENTITY=bug378 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
-- Do not set POKEPORT_SPEED: fast-forward desynchronizes the audio clock.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Warp = require("src.world.Warp")

  local HOUSE = "REDS_HOUSE_1F"
  local TOWN = "PALLET_TOWN"

  local fails = 0
  local function expect(cond, ...)
    if not cond then fails = fails + 1 end
    U.log(cond and "PASS" or "FAIL", ...)
  end

  local ow
  local function settle(mapId)
    for _ = 1, 300 do
      ow = game.overworld
      if ow and ow.map.id == mapId and not ow.transitioning
         and #ow.scriptMoves == 0 and not ow.player.moving then
        break
      end
      U.wait(1)
    end
    U.wait(4)
    ow = game.overworld
  end

  -- data/generated/maps.lua warps, extracted from pokered
  -- data/maps/objects/PalletTown.asm and RedsHouse1F.asm: the town warp whose
  -- destination is the house is the door tile, and the house's LAST_MAP warps
  -- are the two mat cells on its bottom row.
  local function warpTo(mapId, destMap)
    for _, w in ipairs(game.data.maps[mapId].warps or {}) do
      if w.destMap == destMap then return w end
    end
    return nil
  end

  local door = warpTo(TOWN, HOUSE)
  local mat = warpTo(HOUSE, "LAST_MAP")
  expect(door ~= nil, "Pallet Town has a warp into " .. HOUSE)
  expect(mat ~= nil, HOUSE .. " has a LAST_MAP exit warp")
  if not (door and mat) then error("map data has no door/mat pair to test") end
  U.log(("door at (%d, %d), mat at (%d, %d)"):format(door.x, door.y,
                                                     mat.x, mat.y))

  -- Approach the door from the south, which is the only side the walk-in works
  -- from; if a map edit blocked that cell, take any walkable neighbour.
  U.teleport(game, TOWN, door.x, door.y + 1, "up")
  settle(TOWN)
  local stand = { x = door.x, y = door.y + 1, facing = "up" }
  if not ow.map:isWalkableCell(stand.x, stand.y) then
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = door.x + s[1], door.y + s[2]
      if ow.map:isWalkableCell(cx, cy) then
        U.log(("cell (%d, %d) is blocked, approaching from"):format(
              stand.x, stand.y), cx, cy, "facing", s[3])
        stand = { x = cx, y = cy, facing = s[3] }
        U.teleport(game, TOWN, cx, cy, s[3])
        settle(TOWN)
        break
      end
    end
  end

  -- Walk in for real: teleporting straight onto the mat would never set the
  -- flag the door sets, so the bug could not show up.  The direction is
  -- released the instant the warp lands, because a still-held d-pad walks the
  -- player off the mat and stepping back onto it is ExtraWarpCheck's own
  -- trigger, which would exit the house before the human sees anything.
  for _ = 1, 120 do
    if game.overworld and game.overworld.map.id == HOUSE then break end
    table.insert(game.input.pressQueue, stand.facing)
    game.input.state[stand.facing] = true
    coroutine.yield()
  end
  game.input.state[stand.facing] = false
  settle(HOUSE)
  expect(ow.map.id == HOUSE, "walked in through the door, map:", ow.map.id)
  local p = ow.player
  expect(p.cellX == mat.x and p.cellY == mat.y,
         ("landed on the mat (%d, %d), got:"):format(mat.x, mat.y),
         p.cellX, p.cellY)
  expect(ow.map:warpAtCell(p.cellX, p.cellY) ~= nil,
         "the cell under the player carries a warp entry")
  expect(not ow.map:isWarpTileCell(p.cellX, p.cellY),
         ("the mat tile ($%02X) is no warp-activating tile, so nothing cleared "
          .. "the flag"):format(ow.map:cellTile(p.cellX, p.cellY)))
  expect(ow:canCollisionWarp(),
         "BIT_STANDING_ON_WARP survived the warp, so DOWN can exit (#378)")
  expect(Warp.onEdge(ow.map, p.cellX, p.cellY, "down") ~= nil,
         "and DOWN off the south edge resolves to the exit warp")
  expect(ow.warpEntryCell ~= nil,
         "the completed-step arrival record is set, as #265 wants it")

  local vol = game.save.options and game.save.options.sfxVol
  if vol == 0 then
    U.log("sfxVol is 0: a wrong bonk would be SILENT, raise it in OPTION first")
  else
    U.log("sfxVol", tostring(vol), "-- there should be no collision thud at all")
  end

  U.log("You are on the mat inside the house, already facing down. Press DOWN.")
  U.log("Right: it fades out on the first press and you are back in Pallet")
  U.log("Town on the door, which auto-steps you one cell south. Wrong: a")
  U.log("collision thud and Red walks in place until you step off the mat.")
  U.log("The stairs at the top right must still bonk, not bounce floors (#230).")

  if fails > 0 then U.log(fails .. " check(s) failed before the handoff") end

  while true do
    coroutine.yield()
  end
end
