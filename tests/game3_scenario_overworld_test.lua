#!/usr/bin/env luajit
-- src/field_control_avatar.c:618-623, src/metatile_behavior.c:544-571, src/event_object_movement.c:4889

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local HALL = "FR_SCENARIO_HALL"
local ANNEX = "FR_SCENARIO_ANNEX"
local PAIR = "scenario_overworld"

local session = { map = HALL, x = 1, y = 5, facing = "right", party = {}, vars = {} }
local game = { data = { maps = {} }, currentMap = HALL, session = session }

local mapLoads = {}
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
  _mod = nil,
}
package.loaded["src.core.game3.map"] = {
  current = nil,
  load = function(_, _g, mapId, opts)
    mapLoads[#mapLoads + 1] = { map = mapId, x = opts and opts.x, y = opts and opts.y }
  end,
}

local Interactions = require("src.core.game3.scripting.interaction_scripts")
local behs = {}
Interactions.behaviors[PAIR] = behs

local W, H = 8, 8
local MID_WALL, MID_EDGE, MID_DOOR = 2, 3, 4
local function cellIdx(x, y) return y * W + x + 1 end

local function layoutFor(cells)
  local coll, mid = {}, {}
  for i = 1, W * H do
    coll[i] = 0x00
    mid[i] = 1
  end
  for k, v in pairs(cells or {}) do
    coll[k] = v.coll or coll[k]
    mid[k] = v.mid or mid[k]
  end
  return {
    width = W, height = H, pair = PAIR,
    collArray = function() return coll end,
    midAt = function(_, x, y) return mid[y * W + x + 1] end,
  }
end

local ScriptColl = require("src.core.game3.scripting.collision")
local WALL_BYTE = ScriptColl.fromCell(721, 1, 0x32, "indoor")
local EDGE_BYTE = ScriptColl.fromCell(721, 0, 0x32, "indoor")

behs[MID_EDGE] = 0x32
behs[MID_DOOR] = 0x60

local hallDef = {
  pair = PAIR,
  warps = { { x = 5, y = 3, destMap = ANNEX, destWarp = 1 } },
  midLayout = layoutFor({
    [cellIdx(3, 5)] = { coll = WALL_BYTE, mid = MID_WALL },
    [cellIdx(2, 2)] = { coll = EDGE_BYTE, mid = MID_EDGE },
    [cellIdx(5, 3)] = { coll = 0x71, mid = MID_DOOR },
  }),
}
local annexDef = { warps = { { x = 1, y = 1 } } }
game.data.maps[HALL] = hallDef
game.data.maps[ANNEX] = annexDef

local Collision = require("src.core.game3.collision")
local Player = require("src.core.game3.player")
local Warp = require("src.core.game3.warp")

local function settle(limit)
  local frames = 0
  while Player.moving and frames < (limit or 64) do
    Player.tick(game)
    frames = frames + 1
  end
  return frames
end

print("[test] 1. a walkable step carries the avatar and the session one cell east")
check(Collision.bindMap(game, HALL, hallDef) == true, "the stub hall binds a collision grid")
check(Collision.isWalkable(2, 5) == true, "the lane at (2,5) is walkable")
Player.reset(1, 5, "right")
local r1 = Player.tryMove("right", game, false)
check(r1 == "step", "the real Player.tryMove starts the step (got " .. tostring(r1) .. ")")
check(Player.moving == true and Player.targetX == 2, "mid-step the avatar targets the east cell")
local frames = settle()
check(frames == 16, "the walk lands after 16 frames (got " .. frames .. ")")
check(Player.cellX == 2 and Player.cellY == 5, "the avatar stands on (2,5)")
check(session.x == 2 and session.y == 5, "the session coords follow the step")
check(Player.moving == false, "the step is finished")

print("[test] 2. the solid metatile refuses the step and nothing moves")
check(WALL_BYTE == 0x07,
  string.format("the classifier shuts MB_NORTH with mapColl 1 to COLL 0x07 (got 0x%02X)", WALL_BYTE))
check(Collision.cell(3, 5) == 0x07, "the wall byte sits at (3,5)")
local r2, why2 = Player.tryMove("right", game, false)
check(r2 == "blocked", "the wall refuses the step (got " .. tostring(r2) .. ")")
check(why2 == "tile", "for the tile reason (got " .. tostring(why2) .. ")")
check(Player.cellX == 2 and Player.cellY == 5, "the avatar stays on (2,5)")
check(session.x == 2 and session.y == 5, "and the session never advanced")
check(Player.moving == false, "no step ever started")

print("[test] 3. the MB_IMPASSABLE_NORTH edge blocks the north edge only")
check(EDGE_BYTE ~= 0x07 and EDGE_BYTE ~= 0xff,
  string.format("the band tile stays walkable with mapColl 0 (0x%02X)", EDGE_BYTE))
check(Collision.behavior(2, 2) == 0x32, "(2,2) carries MB_IMPASSABLE_NORTH")
check(Collision.cell(2, 2) == EDGE_BYTE, "and its COLL byte is the walkable band")

local function D(fx, fy, tx, ty, dir)
  return Collision.directionallyImpassable(fx, fy, tx, ty, dir) == true
end
-- pokefirered/src/event_object_movement.c:4889
check(D(2, 2, 2, 1, "up"), "leaving northward off the band is blocked")
check(not D(2, 2, 2, 3, "down"), "leaving southward is allowed")
check(not D(2, 2, 3, 2, "right"), "leaving eastward is allowed")
check(D(2, 1, 2, 2, "down"), "entering the band from the north is blocked")
check(not D(2, 3, 2, 2, "up"), "entering from the south is allowed")

Player.reset(2, 2, "up")
local r3, why3 = Player.tryMove("up", game, false)
check(r3 == "blocked" and why3 == "tile",
  "the avatar cannot walk north off the band (got " .. tostring(r3) .. "/" .. tostring(why3) .. ")")
check(Player.cellX == 2 and Player.cellY == 2, "and stays put on (2,2)")

Player.reset(2, 2, "down")
local r4 = Player.tryMove("down", game, false)
check(r4 == "step", "the southward edge of the same tile opens (got " .. tostring(r4) .. ")")
settle()
check(Player.cellY == 3, "the step lands one cell south")
check(session.y == 3, "and the session follows")

print("[test] 4. stepping onto the warp tile resolves the destination map load")
check(Collision.warpAt(5, 3) ~= nil, "the warp event indexes under the door tile")
check(Collision.behavior(5, 3) == 0x60,
  "(5,3) carries MB_CAVE_DOOR (field_control_avatar.c:901 warp behavior)")
check(Collision.isWalkable(5, 3) == true, "the warp tile is walkable")
Player.reset(4, 3, "right")
local r5 = Player.tryMove("right", game, false)
check(r5 == "step", "the avatar steps onto the warp tile (got " .. tostring(r5) .. ")")
settle()
check(Player.cellX == 5, "the step lands on (5,3)")
check(#mapLoads == 0, "the destination has not loaded yet - the fade owns the hand-off")
check(Warp.isBusy() == true, "the real warp sequence is running")
local Fade = require("src.ui.game3.fade")
for _ = 1, 64 do Fade.tick(1 / 60) end
check(#mapLoads == 1, "the stubbed Map.load fired once (got " .. #mapLoads .. ")")
check(mapLoads[1] and mapLoads[1].map == ANNEX,
  "destination is " .. ANNEX .. " (got " .. tostring(mapLoads[1] and mapLoads[1].map) .. ")")
check(mapLoads[1] and mapLoads[1].x == 1 and mapLoads[1].y == 1,
  "landing on the annex warp-1 coords (1,1), got "
    .. tostring(mapLoads[1] and mapLoads[1].x) .. "," .. tostring(mapLoads[1] and mapLoads[1].y))
check(Warp.isBusy() == false, "the warp sequence releases")

finish()
