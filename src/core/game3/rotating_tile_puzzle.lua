local RotatingTilePuzzle = {}

-- pokeemerald/include/fieldmap.h:12
local METATILE_ROW_WIDTH = 8

RotatingTilePuzzle._p = nil

local function session()
  local rt = package.loaded["src.core.game3.runtime"]
  return rt and rt.getSession and rt.getSession() or nil
end

local function Objects()
  return package.loaded["src.core.game3.objects"] or require("src.core.game3.objects")
end

local function C()
  local Constants = require("src.core.game3.constants")
  return Constants.of(Constants.versionOf(session()))
end

local function action(name)
  return require("src.import.gba.movement_emerald").canonOf("MOVEMENT_ACTION_" .. name)
end

local STEP_END = 0xFE

-- pokeemerald/src/rotating_tile_puzzle.c:28
local function shift(dir)
  return { action("LOCK_ANIM"), action("WALK_NORMAL_" .. dir), action("UNLOCK_ANIM"), STEP_END }
end

local function face(dir)
  return { action("FACE_" .. dir), STEP_END }
end

local function metatileAt(x, y)
  local Collision = package.loaded["src.core.game3.collision"]
  local def = Collision and Collision._mapDef
  local layout = def and def.midLayout
  return layout and layout.midAt and layout:midAt(x, y) or 0
end
RotatingTilePuzzle.metatileAt = metatileAt

-- pokeemerald/src/rotating_tile_puzzle.c:89
function RotatingTilePuzzle.init(isTrickHouse)
  local p = RotatingTilePuzzle._p
  if not p then
    p = { objects = {} }
    RotatingTilePuzzle._p = p
  end
  p.isTrickHouse = isTrickHouse and true or false
  return p
end

-- pokeemerald/src/rotating_tile_puzzle.c:97
function RotatingTilePuzzle.free()
  local p = RotatingTilePuzzle._p
  RotatingTilePuzzle._p = nil
  if not p then return end
  local O = Objects()
  -- pokeemerald/src/rotating_tile_puzzle.c:105
  for _, o in ipairs(p.objects) do O.unfreeze(o.lid) end
end

local function tileStart(p)
  if p.isTrickHouse then return C():require("metatile_labels", "METATILE_TrickHousePuzzle_Arrow_YellowOnWhite_Right") end
  return C():require("metatile_labels", "METATILE_MossdeepGym_YellowArrow_Right")
end

local function startMovement(vm, lid, bytes)
  local Movement = require("src.core.game3.scripting.movement")
  if vm and vm.ctx then
    Movement.start(vm.ctx, lid, bytes, vm.adapters)
  else
    Objects().startTrack(lid, Movement.actionsFromBytes(bytes))
  end
end

local ARROWS = {
  [0] = { "RIGHT", 1, 0 },
  [1] = { "DOWN", 0, 1 },
  [2] = { "LEFT", -1, 0 },
  [3] = { "UP", 0, -1 },
}

-- pokeemerald/src/rotating_tile_puzzle.c:108
function RotatingTilePuzzle.move(vm, puzzleNumber)
  local p = RotatingTilePuzzle._p or RotatingTilePuzzle.init(false)
  local O = Objects()
  local start = tileStart(p)
  local mossdeepStart = C():require("metatile_labels", "METATILE_MossdeepGym_YellowArrow_Right")
  local moved
  for _, lid in ipairs(O._order or {}) do
    local eo = O._byId[lid]
    local def = eo and eo.def
    if eo and def and not eo.hidden and eo.visible then
      local x, y = tonumber(def.x) or eo.cellX, tonumber(def.y) or eo.cellY
      local mt = metatileAt(x, y)
      local row = math.floor((mt - start) / METATILE_ROW_WIDTH) % 256
      if mt >= mossdeepStart and row < 5 and row == puzzleNumber then
        local tile = (mt - start) % METATILE_ROW_WIDTH
        local a = ARROWS[tile]
        if a then
          local nx, ny = x + a[2], y + a[3]
          O.rememberPerm(nil, lid, { x = nx, y = ny })
          p.objects[#p.objects + 1] = { lid = lid, prev = tile }
          moved = lid
          startMovement(vm, lid, shift(a[1]))
        end
      end
    end
  end
  RotatingTilePuzzle.lastMoved = moved
  return false
end

-- pokeemerald/src/rotating_tile_puzzle.c:190
local CCW = {
  right = { "UP", 0x07 }, down = { "RIGHT", 0x0A }, left = { "DOWN", 0x08 }, up = { "LEFT", 0x09 },
}
local CW = {
  right = { "DOWN", 0x08 }, down = { "LEFT", 0x09 }, left = { "UP", 0x07 }, up = { "RIGHT", 0x0A },
}

function RotatingTilePuzzle.rotation(prev, now)
  local diff = now - prev
  if diff < 0 or diff == 3 then
    if diff == -3 then return "cw" end
    return "ccw"
  end
  if diff > 0 then return "cw" end
  return nil
end

function RotatingTilePuzzle.turn(vm)
  local p = RotatingTilePuzzle._p
  if not p then return false end
  local O = Objects()
  local start = tileStart(p)
  for _, o in ipairs(p.objects) do
    local eo = O._byId[o.lid]
    if eo then
      local x, y = tonumber(eo.def and eo.def.x) or eo.cellX, tonumber(eo.def and eo.def.y) or eo.cellY
      local now = (metatileAt(x, y) - start) % METATILE_ROW_WIDTH
      local r = RotatingTilePuzzle.rotation(o.prev, now)
      local tbl = r == "ccw" and CCW or r == "cw" and CW or nil
      local t = tbl and tbl[eo.facing]
      if t then
        O.rememberPerm(nil, o.lid, { movementType = t[2] })
        startMovement(vm, o.lid, face(t[1]))
      end
    end
  end
  return false
end

RotatingTilePuzzle.HOOK = {
  initrotatingtilepuzzle = function(_, isTrickHouse)
    RotatingTilePuzzle.init((tonumber(isTrickHouse) or 0) ~= 0)
    return false
  end,
  moverotatingtileobjects = function(vm, n) return RotatingTilePuzzle.move(vm, tonumber(n) or 0) end,
  turnrotatingtileobjects = function(vm) return RotatingTilePuzzle.turn(vm) end,
  freerotatingtilepuzzle = function()
    RotatingTilePuzzle.free()
    return false
  end,
}

require("src.core.game3.rse.init").register("rotatingTilePuzzle", RotatingTilePuzzle.HOOK)

return RotatingTilePuzzle
