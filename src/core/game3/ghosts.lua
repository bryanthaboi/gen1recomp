local Ghosts = {}

Ghosts._pools = {}

local function Map()
  return package.loaded["src.core.game3.map"] or require("src.core.game3.map")
end

local function Objects()
  return package.loaded["src.core.game3.objects"] or require("src.core.game3.objects")
end

local function permissions()
  local ok, P = pcall(require, "src.world.gen2.Permissions")
  return ok and P or nil
end

local function defsFor(mapId, def)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local ev = Space and Space.bundle and Space.bundle.events
    and Space.bundle.events[mapId]
  local defs = ev and (ev.objects or ev.objectEvents)
  if type(defs) ~= "table" then defs = def and def.objects end
  return type(defs) == "table" and defs or nil
end

local function contextFor(entry, pool)
  local layout = entry.def and entry.def.midLayout
  local P = permissions()
  return {
    ox = entry.ox or 0,
    oy = entry.oy or 0,
    canEnter = function(tx, ty, fromX, fromY, dir)
      if not layout then return false end
      if tx < 0 or ty < 0 or tx >= (layout.width or 0) or ty >= (layout.height or 0) then
        return false
      end
      -- pokefirered/src/event_object_movement.c:4889
      if dir and entry.def then
        local C = require("src.core.game3.collision")
        if C.directionallyImpassableOn
            and C.directionallyImpassableOn(entry.def, fromX, fromY, tx, ty, dir) then
          return false
        end
      end
      local coll = layout:collAt(tx, ty)
      if P and P.isWalkable then return P.isWalkable(coll) end
      return coll ~= 0x07 and coll ~= 0xff and coll ~= 0x29
    end,
    blocks = function(tx, ty, exceptId)
      for _, lid in ipairs(pool.order or {}) do
        local eo = pool.byId[lid]
        if eo and lid ~= exceptId and eo.visible and not eo.hidden and not eo.passable then
          if eo.cellX == tx and eo.cellY == ty then return true end
          if eo.moving and eo.targetX == tx and eo.targetY == ty then return true end
        end
      end
      return Objects().playerBlocks(tx + (entry.ox or 0), ty + (entry.oy or 0))
    end,
  }
end

Ghosts._contextFor = contextFor

function Ghosts.sync()
  local M = Map()
  local placed = {}
  for _, entry in ipairs(M.world or {}) do
    placed[entry.id] = true
    if not Ghosts._pools[entry.id] then
      local defs = defsFor(entry.id, entry.def)
      if defs then
        Ghosts._pools[entry.id] = Objects().spawnFromDefs(defs, entry.def, entry.id)
      end
    end
  end
  for id in pairs(Ghosts._pools) do
    if not placed[id] and id ~= Ghosts._held then
      Ghosts._pools[id] = nil
    end
  end
  if Ghosts._held and not placed[Ghosts._held] then
    Ghosts._heldGrace = (Ghosts._heldGrace or 0) + 1
    if Ghosts._heldGrace > 2 then
      Ghosts._pools[Ghosts._held] = nil
      Ghosts._held = nil
      Ghosts._heldGrace = nil
    end
  else
    Ghosts._heldGrace = nil
  end
end

function Ghosts.update(game)
  local M = Map()
  local Obj = Objects()
  for _, entry in ipairs(M.world or {}) do
    local pool = Ghosts._pools[entry.id]
    if pool then
      Obj.tickPool(pool, game, contextFor(entry, pool))
    end
  end
end

function Ghosts.forDraw(mapId)
  local pool = Ghosts._pools[mapId]
  if not pool then return nil end
  return Objects().poolForDraw(pool)
end

-- pokefirered/src/event_object_movement.c:4899
function Ghosts.blocksOn(mapId, def, tx, ty)
  local pool = Ghosts._pools[mapId]
  if not pool then
    local defs = defsFor(mapId, def)
    if not defs then return false end
    pool = Objects().spawnFromDefs(defs, def, mapId)
    Ghosts._pools[mapId] = pool
  end
  for _, lid in ipairs(pool.order or {}) do
    local eo = pool.byId[lid]
    if eo and eo.visible and not eo.hidden and not eo.passable then
      if eo.cellX == tx and eo.cellY == ty then return true end
      if eo.moving and eo.targetX == tx and eo.targetY == ty then return true end
    end
  end
  return false
end

function Ghosts.capture(mapId)
  if not mapId then return end
  local snap = Objects().snapshotPool()
  if snap.mapId ~= mapId then return end
  local pool = { byId = {}, order = {}, bounds = snap.bounds }
  for _, lid in ipairs(snap.order or {}) do
    local eo = snap.byId[lid]
    if eo then
      pool.byId[lid] = eo
      pool.order[#pool.order + 1] = lid
      eo.scriptBusy = false
      eo.frozen = false
    end
  end
  Ghosts._pools[mapId] = pool
  Ghosts._held = mapId
  Ghosts._heldGrace = nil
end

function Ghosts.adopt(mapId)
  if not mapId then return end
  local pool = Ghosts._pools[mapId]
  if not pool then return end
  Objects().adoptPool(pool)
  Ghosts._pools[mapId] = nil
  if Ghosts._held == mapId then Ghosts._held = nil end
end

function Ghosts.clear()
  Ghosts._pools = {}
  Ghosts._held = nil
  Ghosts._heldGrace = nil
end

return Ghosts
