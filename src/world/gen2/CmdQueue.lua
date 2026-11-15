-- wCmdQueue: engine/overworld/cmd_queue.asm and home/stone_queue.asm.
--
-- Four five-byte slots, polled once a frame by HandleCmdQueue, written by the
-- `writecmdqueue` script command and cleared by `delcmdqueue`.  The port had
-- neither: both commands were explicit no-ops, and `delcmdqueue` answering TRUE
-- was correct only because the queue it reported on was permanently empty.
--
-- Only one of the five queue types does anything a player can see, and it is
-- the one that matters most: CMDQUEUE_STONETABLE is what makes a boulder pushed
-- onto a hole fall through it.  Two maps use it -- Ice Path B1F and Blackthorn
-- Gym 2F -- and Ice Path gates Blackthorn, so without this the eighth badge is
-- unreachable.
--
--   CmdQueue_Null       ret
--   CmdQueue_Type1      SetXYCompareFlags
--   CmdQueue_StoneTable the boulder check below
--   CmdQueue_Type3      ret
--   CmdQueue_Type4      an hSCY shake, unreferenced by any map
--
-- love-free: the caller supplies the objects, the warps and a collision lookup.

local CmdQueue = {}

CmdQueue.CAPACITY = 4

-- HandleQueuedCommand.Jumptable order (constants/script_constants.asm).
CmdQueue.NULL = 0
CmdQueue.TYPE1 = 1
CmdQueue.STONETABLE = 2
CmdQueue.TYPE3 = 3
CmdQueue.TYPE4 = 4
CmdQueue.NUM_TYPES = 5

-- CheckPitTile (home/map_objects.asm): COLL_PIT and COLL_PIT_68.
local PIT = { [0x60] = true, [0x68] = true }

-- SPRITEMOVEDATA_STRENGTH_BOULDER.  The check is on the MOVEMENT type, not on
-- SPRITE_BOULDER: Blackthorn Gym 2F has six boulders and only three of them are
-- in its stone table, but all six carry this movedata.
CmdQueue.BOULDER_MOVEDATA = 0x19

function CmdQueue.new()
  return {}
end

-- ClearCmdQueue: every slot's TYPE byte zeroed.  Called on a map load, which is
-- why a queue never survives a warp and every map that needs one writes it back
-- from a MAPCALLBACK_CMDQUEUE callback.
function CmdQueue.clear(queue)
  for i = 1, CmdQueue.CAPACITY do queue[i] = nil end
  return queue
end

-- WriteCmdQueue -> .GetNextEmptyEntry.  A full queue sets carry and the write is
-- simply DROPPED; there is no error path and no overwrite.
function CmdQueue.write(queue, entry)
  if type(entry) ~= "table" or not entry.kind then return nil end
  for i = 1, CmdQueue.CAPACITY do
    if queue[i] == nil then
      queue[i] = entry
      return i
    end
  end
  return nil
end

-- DelCmdQueue.  Answers whether it FOUND and deleted an entry of that type --
-- which is the opposite of what `delcmdqueue` writes to wScriptVar, because
-- Script_delcmdqueue's `ret c` returns on the delete with wScriptVar still 0
-- and only falls through to TRUE when the loop ran off the end.
function CmdQueue.delete(queue, kind)
  for i = 1, CmdQueue.CAPACITY do
    local entry = queue[i]
    if entry and entry.kind == kind then
      queue[i] = nil
      return true
    end
  end
  return false
end

function CmdQueue.count(queue)
  local n = 0
  for i = 1, CmdQueue.CAPACITY do
    if queue[i] then n = n + 1 end
  end
  return n
end

-- .IsObjectOnWarp's `.check_on_warp`: a linear walk of the map's warp_events
-- for one at the object's cell, answering the warp NUMBER rather than a
-- boolean.  The number is 1-based (`ld a, [wCurMapWarpEventCount] / sub d /
-- inc a`), which is the same numbering `stonetable`'s first byte uses.
--
-- The cart subtracts 4 from the object's stored coordinates because
-- OBJECT_MAP_X / _Y carry the map border's offset; the port stores plain map
-- cells, so there is nothing to subtract.
function CmdQueue.warpNumberAt(warps, x, y)
  for index, warp in ipairs(warps or {}) do
    if warp.x == x and warp.y == y then return index end
  end
  return nil
end

-- .IsObjectInStoneTable: walk `db warp, object / dw script` rows until $ff.
-- BOTH bytes have to match, which is what keeps a boulder pushed onto the wrong
-- hole from falling through it.
function CmdQueue.stoneRow(rows, warpNumber, objectId)
  for _, row in ipairs(rows or {}) do
    if row.warp == warpNumber and row.object == objectId then return row end
  end
  return nil
end

-- CmdQueue_StoneTable.  Four gates on the object before HandleStoneQueue is
-- even called, and they are all load bearing:
--
--   OBJECT_SPRITE non-zero   -- a disappeared boulder has no struct left
--   OBJECT_MOVEMENT_TYPE     -- SPRITEMOVEDATA_STRENGTH_BOULDER
--   CheckPitTile             -- the tile UNDER the boulder is a hole
--   OBJECT_WALKING STANDING  -- not mid-push, or it would fall a step early
--
-- The loop returns on the FIRST boulder that falls (`jr c, .fall_down_hole`
-- pops and rets), so two boulders never drop on the same frame.
function CmdQueue.stoneFall(entry, ctx)
  local rows = entry and entry.rows
  if not rows then return nil end
  for _, obj in ipairs((ctx and ctx.objects) or {}) do
    if obj.visible ~= false
        and obj.movement == CmdQueue.BOULDER_MOVEDATA
        and not obj.moving
        and PIT[ctx.collisionAt(obj.cellX, obj.cellY)] then
      local warp = CmdQueue.warpNumberAt(ctx.warps, obj.cellX, obj.cellY)
      local row = warp and CmdQueue.stoneRow(rows, warp, obj.id)
      if row then return row, obj end
    end
  end
  return nil
end

-- HandleCmdQueue: every slot, in order, once a frame.  Only STONETABLE produces
-- anything for the caller to act on; the other four are the cart's own `ret`s
-- and its unreferenced hSCY shake, written out so the jumptable is complete
-- rather than implied.
function CmdQueue.poll(queue, ctx)
  for i = 1, CmdQueue.CAPACITY do
    local entry = queue[i]
    if entry and entry.kind == CmdQueue.STONETABLE then
      local row, obj = CmdQueue.stoneFall(entry, ctx)
      if row then return row, obj, i end
    end
  end
  return nil
end

-- engine/overworld/scripting.asm:1999
function CmdQueue.fromExtracted(entry, mapId)
  if type(entry) ~= "table" then return nil end
  if entry.type ~= CmdQueue.STONETABLE then return nil end
  local rows = {}
  for _, row in ipairs(entry.rows or {}) do
    if row.warp and row.object and row.scriptKey then
      rows[#rows + 1] =
        { warp = row.warp, object = row.object, script = row.scriptKey }
    end
  end
  if #rows == 0 then return nil end
  return { kind = CmdQueue.STONETABLE, rows = rows, mapId = mapId,
           extracted = true }
end

return CmdQueue
