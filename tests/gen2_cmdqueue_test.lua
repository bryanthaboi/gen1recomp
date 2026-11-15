-- wCmdQueue and the stone table (engine/overworld/cmd_queue.asm,
-- home/stone_queue.asm).  ROM-free: `luajit tests/gen2_cmdqueue_test.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 cmd queue")
local check, eq = S.check, S.eq

local CmdQueue = require("src.world.gen2.CmdQueue")

-- ---- the four slots -------------------------------------------------------
do
  local q = CmdQueue.new()
  eq(CmdQueue.count(q), 0, "a fresh queue is empty")
  for i = 1, CmdQueue.CAPACITY do
    eq(CmdQueue.write(q, { kind = CmdQueue.TYPE1 }), i,
      "WriteCmdQueue fills the first free slot (" .. i .. ")")
  end
  check(CmdQueue.write(q, { kind = CmdQueue.TYPE1 }) == nil,
    "a full queue sets carry and the write is DROPPED, not overwritten")
  eq(CmdQueue.count(q), CmdQueue.CAPACITY, "four is the capacity")
  CmdQueue.clear(q)
  eq(CmdQueue.count(q), 0, "ClearCmdQueue zeroes every type byte")
end

-- DelCmdQueue answers whether it found the entry, which is the OPPOSITE of what
-- `delcmdqueue` writes to wScriptVar: `ret c` returns on the delete with
-- wScriptVar still 0, and only a miss falls through to TRUE.
do
  local q = CmdQueue.new()
  CmdQueue.write(q, { kind = CmdQueue.STONETABLE })
  check(not CmdQueue.delete(q, CmdQueue.TYPE4), "a type not in the queue misses")
  check(CmdQueue.delete(q, CmdQueue.STONETABLE), "and the one that is, hits")
  eq(CmdQueue.count(q), 0, "leaving the slot free")
  check(not CmdQueue.delete(q, CmdQueue.STONETABLE), "and only once")
end

-- ---- .IsObjectOnWarp ------------------------------------------------------
do
  local warps = { { x = 1, y = 1 }, { x = 11, y = 2 }, { x = 4, y = 7 } }
  eq(CmdQueue.warpNumberAt(warps, 11, 2), 2,
    "the answer is the warp NUMBER, 1-based, not a boolean")
  eq(CmdQueue.warpNumberAt(warps, 4, 7), 3, "counted in warp_event order")
  check(CmdQueue.warpNumberAt(warps, 9, 9) == nil, "and nil off a warp")
end

-- ---- .IsObjectInStoneTable ------------------------------------------------
do
  local rows = {
    { warp = 3, object = 2, script = "a" },
    { warp = 4, object = 3, script = "b" },
  }
  eq(CmdQueue.stoneRow(rows, 4, 3).script, "b", "both bytes have to match")
  check(CmdQueue.stoneRow(rows, 3, 3) == nil,
    "the right boulder on the wrong hole does not fall")
  check(CmdQueue.stoneRow(rows, 4, 2) == nil, "nor the wrong boulder on it")
end

-- ---- CmdQueue_StoneTable's four gates -------------------------------------
local ICE_WARPS = {
  { x = 3, y = 15 }, { x = 17, y = 3 }, { x = 11, y = 2 },
  { x = 4, y = 7 }, { x = 5, y = 12 }, { x = 12, y = 13 },
}

local function iceCtx(objects, pits)
  return {
    objects = objects,
    warps = ICE_WARPS,
    collisionAt = function(x, y)
      for _, p in ipairs(pits or {}) do
        if p[1] == x and p[2] == y then return 0x60 end -- COLL_PIT
      end
      return 0x00
    end,
  }
end

local function stoneTable(rows)
  return { type = CmdQueue.STONETABLE, queue = "CMDQUEUE_STONETABLE", rows = rows }
end

local ICE = CmdQueue.fromExtracted(stoneTable({
  { warp = 3, object = 2, scriptKey = "46:6192" },
  { warp = 4, object = 3, scriptKey = "46:619a" },
  { warp = 5, object = 4, scriptKey = "46:61a2" },
  { warp = 6, object = 5, scriptKey = "46:61aa" },
}), "ICE_PATH_B1F")

local GYM = CmdQueue.fromExtracted(stoneTable({
  { warp = 5, object = 4, scriptKey = "53:49f3" },
  { warp = 3, object = 5, scriptKey = "53:49f8" },
  { warp = 4, object = 6, scriptKey = "53:49fd" },
}), "BLACKTHORN_GYM_2F")

do
  check(ICE ~= nil, "Ice Path B1F has a stone table")
  eq(ICE.kind, CmdQueue.STONETABLE, "written as CMDQUEUE_STONETABLE")
  eq(#ICE.rows, 4, "with a row per boulder")
  eq(ICE.rows[1].script, "46:6192", "each row names its scripts.lua key")
  check(CmdQueue.fromExtracted({ type = CmdQueue.TYPE1, rows = {
    { warp = 3, object = 2, scriptKey = "46:6192" } } }) == nil,
    "and a queue type nothing acts on writes no entry")
  check(CmdQueue.fromExtracted(stoneTable({})) == nil,
    "nor does a stone table with no rows")
end

-- The happy path: boulder 1 (object id 2) pushed onto warp 3 at (11,2).
do
  local boulder = { id = 2, movement = CmdQueue.BOULDER_MOVEDATA,
    cellX = 11, cellY = 2, moving = false }
  local row = CmdQueue.stoneFall(ICE, iceCtx({ boulder }, { { 11, 2 } }))
  check(row ~= nil, "a boulder standing on its own hole falls through")
  eq(row.warp, 3, "through warp 3")

  -- ...and each of the four gates alone stops it.
  check(CmdQueue.stoneFall(ICE, iceCtx({ boulder }, {})) == nil,
    "CheckPitTile: a warp tile that is not a PIT is not a hole")
  boulder.moving = true
  check(CmdQueue.stoneFall(ICE, iceCtx({ boulder }, { { 11, 2 } })) == nil,
    "OBJECT_WALKING: a boulder mid-push does not fall early")
  boulder.moving = false
  boulder.movement = 1
  check(CmdQueue.stoneFall(ICE, iceCtx({ boulder }, { { 11, 2 } })) == nil,
    "OBJECT_MOVEMENT_TYPE: only a STRENGTH_BOULDER is checked at all")
  boulder.movement = CmdQueue.BOULDER_MOVEDATA
  boulder.visible = false
  check(CmdQueue.stoneFall(ICE, iceCtx({ boulder }, { { 11, 2 } })) == nil,
    "OBJECT_SPRITE: one already disappeared has no struct left")
end

-- A boulder on the WRONG hole stays put -- both stonetable bytes must match.
do
  local wrong = { id = 2, movement = CmdQueue.BOULDER_MOVEDATA,
    cellX = 4, cellY = 7, moving = false }
  check(CmdQueue.stoneFall(ICE, iceCtx({ wrong }, { { 4, 7 } })) == nil,
    "boulder 1 does not fall through boulder 2's hole")
end

-- HandleStoneQueue returns on the FIRST match, so two never drop together.
do
  local a = { id = 2, movement = CmdQueue.BOULDER_MOVEDATA,
    cellX = 11, cellY = 2, moving = false }
  local b = { id = 3, movement = CmdQueue.BOULDER_MOVEDATA,
    cellX = 4, cellY = 7, moving = false }
  local q = CmdQueue.new()
  CmdQueue.write(q, ICE)
  local row, obj = CmdQueue.poll(q, iceCtx({ a, b }, { { 11, 2 }, { 4, 7 } }))
  eq(obj.id, 2, "the first boulder in object order is the one that drops")
  eq(row.warp, 3, "and its own row is what runs")
end

-- An empty queue polls to nothing, which is the state every other map is in.
do
  eq(CmdQueue.poll(CmdQueue.new(), iceCtx({}, {})), nil,
    "no entry, nothing to handle")
end

do
  for i, row in ipairs(ICE.rows) do
    eq(row.object, i + 1, "Ice Path boulder " .. i .. " is object id " .. (i + 1))
    eq(row.warp, i + 2, "and falls through warp " .. (i + 2))
  end

  eq(#GYM.rows, 3, "Blackthorn Gym 2F has three rows for its six boulders")
  eq(GYM.rows[1].warp, 5, "BOULDER1 -> warp 5")
  eq(GYM.rows[2].warp, 3, "BOULDER2 -> warp 3, not 4")
  eq(GYM.rows[3].warp, 4, "BOULDER3 -> warp 4: the cart's own order, kept")
end

S.finish()
