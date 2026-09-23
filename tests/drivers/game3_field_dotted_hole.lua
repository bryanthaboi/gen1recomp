local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_field_dotted_hole"

-- pokefirered/src/field_specials.c:2296 CutMoveRuinValleyCheck
local RUIN_VALLEY = "FR_SIX_ISLAND_RUIN_VALLEY"
local DOTTED_1F = "FR_SIX_ISLAND_DOTTED_HOLE_1F"
local SAPPHIRE_ROOM = "FR_SIX_ISLAND_DOTTED_HOLE_SAPPHIRE_ROOM"
-- pokefirered/include/constants/flags.h:766
local FLAG_USED_CUT_ON_RUIN_VALLEY_BRAILLE = 0x2E3
-- pokefirered/include/constants/metatile_labels.h:206
local DOOR_CLOSED, DOOR_OPEN = 0x357, 0x358

local DESCENT = {
  { map = DOTTED_1F, from = { 6, 9 }, hole = { 6, 5 } },
  { map = "FR_SIX_ISLAND_DOTTED_HOLE_B1F", hole = { 6, 1 } },
  { map = "FR_SIX_ISLAND_DOTTED_HOLE_B2F", hole = { 1, 5 } },
  { map = "FR_SIX_ISLAND_DOTTED_HOLE_B3F", hole = { 11, 5 } },
  { map = "FR_SIX_ISLAND_DOTTED_HOLE_B4F", hole = { 6, 9 } },
}

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS field_dotted_hole")
    love.event.quit(0)
  else
    print("FAIL field_dotted_hole failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Collision = require("src.core.game3.collision")
  local FieldMoves = require("src.core.game3.field_moves")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end

  local function place(x, y, facing)
    Player.moving = false
    Player.progress = 0
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  local function goTo(id, x, y, facing)
    Map.load(nil, game, id, { x = x, y = y, facing = facing or "down" })
    place(x, y, facing or "down")
    U.wait(60)
  end

  local function walk(dir)
    local sx, sy = Player.cellX, Player.cellY
    for _ = 1, 30 do
      U.hold(game, dir, 1)
      if Player.moving then break end
    end
    for _ = 1, 90 do
      if not Player.moving then break end
      U.wait(1)
    end
    U.wait(2)
    return Player.cellX ~= sx or Player.cellY ~= sy
  end

  local function walkTo(tx, ty, limit)
    local startMap = Space.mapId
    local detour = "left"
    for _ = 1, limit or 60 do
      if Space.mapId ~= startMap then return false end
      if Player.cellX == tx and Player.cellY == ty then return true end
      local primary, secondary
      if Player.cellY ~= ty then
        primary = (Player.cellY < ty) and "down" or "up"
        if Player.cellX ~= tx then secondary = (Player.cellX < tx) and "right" or "left" end
      else
        primary = (Player.cellX < tx) and "right" or "left"
      end
      local moved = walk(primary)
      if not moved and secondary then moved = walk(secondary) end
      if not moved then
        moved = walk(detour)
        detour = (detour == "left") and "right" or "left"
      end
      if not moved and Space.mapId == startMap then return false end
      if Space.vm and Space.vm:isRunning() then U.wait(30) end
    end
    return Player.cellX == tx and Player.cellY == ty
  end

  local function midAt(mapId, x, y)
    local def = game.data and game.data.maps and game.data.maps[mapId]
    local layout = def and def.midLayout
    return layout and layout:midAt(x, y) or nil
  end

  local party = session.party
  if type(party) == "table" and type(party[1]) == "table" then
    party[1].level = 50
    party[1].moves = { 15 }
  end
  Flags.setFlag(Space.store, ctx(), FieldMoves.BADGE_FLAGS.CUT, true)
  -- pokefirered/data/maps/FourIsland_IcefallCave_Back/scripts.inc:83
  Flags.setFlag(Space.store, ctx(), 0x8E, true)
  session.repelSteps = 250

  goTo(RUIN_VALLEY, 24, 26, "up")
  result(Space.mapId == RUIN_VALLEY, "stood in Ruin Valley, map=" .. tostring(Space.mapId))
  result(Flags.getFlag(Space.store, ctx(), FLAG_USED_CUT_ON_RUIN_VALLEY_BRAILLE) == false,
    "FLAG_USED_CUT_ON_RUIN_VALLEY_BRAILLE starts clear")
  result(midAt(RUIN_VALLEY, 24, 24) == DOOR_CLOSED, "the Dotted Hole door starts shut")
  result(Collision.isWalkable(24, 24) == false, "and blocks the way in")
  U.shot(game, DIR .. "/field_dotted_hole_01_door_shut.png")

  result(walk("up"), "walked onto the braille tile at (24,25)")
  result(Player.cellX == 24 and Player.cellY == 25,
    "standing at (" .. Player.cellX .. "," .. Player.cellY .. ") facing " .. Player.facing)
  if Space.vm and Space.vm:isRunning() then
    for _ = 1, 40 do
      U.tap(game, "a")
      U.wait(6)
      if not (Space.vm and Space.vm:isRunning()) then break end
    end
    place(24, 25, "up")
  end

  -- pokefirered/src/fldeff_cut.c:118 SetUpFieldMove_Cut
  local res = FieldMoves.fromMenu("CUT", {
    party = session.party,
    store = Space.store,
    session = session,
  })
  result(res ~= nil and res.action == "dotted_hole",
    "Cut here is the dotted-hole arm (" .. tostring(res and res.action) .. ")")
  Field.executeFieldMove(res)
  for _ = 1, 1200 do
    U.wait(1)
    if not Field.locked then break end
  end
  print("[driver] after cut locked=" .. tostring(Field.locked) .. " flag=" ..
    tostring(Flags.getFlag(Space.store, ctx(), FLAG_USED_CUT_ON_RUIN_VALLEY_BRAILLE)))
  for _ = 1, 30 do
    U.tap(game, "a")
    U.wait(4)
    local Message = package.loaded["src.ui.game3.message"]
    if not (Message and Message.isOpen and Message.isOpen()) then break end
  end

  result(Flags.getFlag(Space.store, ctx(), FLAG_USED_CUT_ON_RUIN_VALLEY_BRAILLE) == true,
    "the braille flag is set")
  result(midAt(RUIN_VALLEY, 24, 24) == DOOR_OPEN, "the door metatile is the open one")
  result(Collision.isWalkable(24, 24) == true, "the doorway is walkable")
  U.shot(game, DIR .. "/field_dotted_hole_02_door_open.png")

  result(walk("up"), "walked into the doorway")
  for _ = 1, 60 do
    U.wait(4)
    if Space.mapId == DOTTED_1F then break end
  end
  result(Space.mapId == DOTTED_1F, "the warp led into the Dotted Hole, map=" .. tostring(Space.mapId))
  U.wait(120)
  U.shot(game, DIR .. "/field_dotted_hole_03_inside.png")

  for i, floor in ipairs(DESCENT) do
    if Space.mapId ~= floor.map then
      result(false, "expected to be on " .. floor.map .. ", am on " .. tostring(Space.mapId))
      break
    end
    local reached = walkTo(floor.hole[1], floor.hole[2], 30)
    if not reached then
      U.log("could not reach the hole on " .. floor.map ..
        ", stopped at (" .. Player.cellX .. "," .. Player.cellY .. ")")
    end
    for _ = 1, 90 do
      U.wait(4)
      if Space.mapId ~= floor.map then break end
    end
    result(Space.mapId ~= floor.map,
      "fell out of " .. floor.map .. " into " .. tostring(Space.mapId))
    if i == #DESCENT then
      result(Space.mapId == SAPPHIRE_ROOM,
        "the last hole drops into the Sapphire room (" .. tostring(Space.mapId) .. ")")
    end
  end

  if Space.mapId == SAPPHIRE_ROOM then
    walkTo(7, 8, 20)
    U.wait(20)
    U.shot(game, DIR .. "/field_dotted_hole_04_sapphire.png")
  end

  finish()
end
