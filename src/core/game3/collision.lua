-- Game3-owned field collision grid.
-- Built from mapDef.blocks + tileset.collision (Gen2 COLL_* quads baked from
-- FRLG metatile attrs at extract). Does not call World:step / Player:tryMove.

local Collision = {}

local DELTA = {
  up = { 0, -1 },
  down = { 0, 1 },
  left = { -1, 0 },
  right = { 1, 0 },
}

Collision._grid = nil -- 1-based flat COLL_* bytes, widthCells * heightCells
Collision._widthCells = 0
Collision._heightCells = 0
Collision._mapId = nil
Collision._mapDef = nil
Collision._warps = {} -- [cy*1024+cx] = warp def
Collision._logged = false

local function log(msg)
  print("[game3/collision] " .. tostring(msg))
end

local function permissions()
  local ok, P = pcall(require, "src.world.gen2.Permissions")
  return ok and P or nil
end

local function resolveTileset(game, mapDef)
  if not mapDef then return nil end
  local tsId = mapDef.tileset
  local data = game and game.data
  local sets = data and (data.tilesets or data.gen2Tilesets)
  return tsId and sets and sets[tsId], tsId
end

local function hostWorld(game)
  return game and (game.overworld or game.world)
end

--- Expand mapDef blocks × tileset.collision into a per-cell COLL_* grid.
-- Prefer native midLayout when present (already 16px COLL_* bytes).
function Collision.bindMap(game, mapId, mapDef)
  Collision._grid = nil
  Collision._mapId = mapId
  Collision._mapDef = mapDef
  Collision._warps = {}
  Collision._widthCells = 0
  Collision._heightCells = 0

  if mapDef and mapDef.midLayout then
    local layout = mapDef.midLayout
    Collision._grid = layout:collArray()
    Collision._widthCells = layout.width
    Collision._heightCells = layout.height
    Collision.installWarps(mapDef)
    if not Collision._logged then
      log(string.format("grid ready (native) map=%s cells=%dx%d warps=%d",
        tostring(mapId), layout.width, layout.height, #(mapDef.warps or {})))
      Collision._logged = true
    end
    return true
  end

  if not mapDef or type(mapDef.blocks) ~= "table" then
    log("bindMap failed — no blocks for " .. tostring(mapId))
    return false
  end

  local tileset = resolveTileset(game, mapDef)
  local collTbl = tileset and tileset.collision
  if not collTbl then
    log("bindMap failed — no tileset.collision for " .. tostring(mapDef.tileset))
    return false
  end

  local bw = mapDef.width or 0
  local bh = mapDef.height or 0
  local wc = bw * 2
  local hc = bh * 2
  local grid = {}
  local border = mapDef.borderBlock or 0

  for cy = 0, hc - 1 do
    for cx = 0, wc - 1 do
      local bx, by = math.floor(cx / 2), math.floor(cy / 2)
      local bid = border
      if bx >= 0 and by >= 0 and bx < bw and by < bh then
        bid = mapDef.blocks[by * bw + bx + 1] or border
      end
      local quad = collTbl[(bid or 0) + 1]
      local lx, ly = cx % 2, cy % 2
      local byte = 0xff
      if type(quad) == "table" then
        byte = quad[ly * 2 + lx + 1] or 0xff
      end
      grid[cy * wc + cx + 1] = byte
    end
  end

  Collision._grid = grid
  Collision._widthCells = wc
  Collision._heightCells = hc

  Collision.installWarps(mapDef)

  if not Collision._logged then
    log(string.format("grid ready map=%s cells=%dx%d warps=%d",
      tostring(mapId), wc, hc, #(mapDef.warps or {})))
    Collision._logged = true
  end
  return true
end

local function isWarpBehavior(coll)
  if not coll then return false end
  return (coll >= 0x60 and coll <= 0x7F)
end

-- Index warps and force door/warp cells walkable. Extract can leave outdoor
-- MB_WARP_DOOR tiles as solid when tileset attrs were read past EOF.
local COLL_DOOR = 0x71
function Collision.installWarps(mapDef)
  Collision._warps = Collision._warps or {}
  local layout = mapDef and mapDef.midLayout
  for _, w in ipairs((mapDef and mapDef.warps) or {}) do
    local x, y = tonumber(w.x), tonumber(w.y)
    if x and y then
      local cur = nil
      if Collision._grid and Collision._widthCells > 0 then
        local i = y * Collision._widthCells + x + 1
        cur = Collision._grid[i]
        if cur == nil or cur == 0x07 or cur == 0xff then
          Collision._grid[i] = COLL_DOOR
          cur = COLL_DOOR
          if layout and layout.applyOverride then
            local mid = layout.midAt and layout:midAt(x, y) or nil
            local elev = layout.elevAt and layout:elevAt(x, y) or nil
            layout:applyOverride(x, y, mid, COLL_DOOR, elev)
          end
        end
      end
      -- In pret, a warp in map header is only active if the metatile behavior is a warp behavior
      if isWarpBehavior(cur) then
        Collision._warps[y * 1024 + x] = w
      end
    end
  end
end

function Collision.clear()
  Collision._grid = nil
  Collision._mapId = nil
  Collision._mapDef = nil
  Collision._warps = {}
  Collision._widthCells = 0
  Collision._heightCells = 0
end

function Collision.inBounds(cx, cy)
  return cx >= 0 and cy >= 0
    and cx < Collision._widthCells and cy < Collision._heightCells
end

-- Preserve original MB semantics independently of the walkability COLL grid.
function Collision.behavior(cx,cy)
  local layout=Collision._mapDef and Collision._mapDef.midLayout
  if not layout or cx<0 or cy<0 or cx>=layout.width or cy>=layout.height then return nil end
  local pair=Collision._mapDef.pair or layout.pair
  local behaviors=require("src.core.game3.scripting.interaction_scripts").behaviors[pair]
  return behaviors and behaviors[layout:midAt(cx,cy)]
end

-- pokefirered/include/constants/metatile_behaviors.h:82
local MB_UP_ESCALATOR = 0x6A
local MB_DOWN_ESCALATOR = 0x6B
local MB_UP_RIGHT_STAIR_WARP = 0x6C
local MB_UP_LEFT_STAIR_WARP = 0x6D
local MB_DOWN_RIGHT_STAIR_WARP = 0x6E
local MB_DOWN_LEFT_STAIR_WARP = 0x6F

-- pokefirered/src/metatile_behavior.c:174
function Collision.isStairWarpBehavior(beh)
  return beh == MB_UP_RIGHT_STAIR_WARP or beh == MB_UP_LEFT_STAIR_WARP
    or beh == MB_DOWN_RIGHT_STAIR_WARP or beh == MB_DOWN_LEFT_STAIR_WARP
end

-- pokefirered/src/field_control_avatar.c:924
function Collision.stairWarpDir(beh)
  if beh == MB_UP_LEFT_STAIR_WARP or beh == MB_DOWN_LEFT_STAIR_WARP then
    return "left"
  end
  if beh == MB_UP_RIGHT_STAIR_WARP or beh == MB_DOWN_RIGHT_STAIR_WARP then
    return "right"
  end
  return nil
end

-- pokefirered/src/overworld.c:921
function Collision.stairArrivalFacing(beh)
  if beh == MB_UP_RIGHT_STAIR_WARP or beh == MB_DOWN_RIGHT_STAIR_WARP then
    return "left"
  end
  if beh == MB_UP_LEFT_STAIR_WARP or beh == MB_DOWN_LEFT_STAIR_WARP then
    return "right"
  end
  return nil
end

-- pokefirered/src/field_fadetransition.c:866
function Collision.stairSpeeds(beh)
  if beh == MB_UP_RIGHT_STAIR_WARP then return 16, -10 end
  if beh == MB_UP_LEFT_STAIR_WARP then return -17, -10 end
  if beh == MB_DOWN_RIGHT_STAIR_WARP then return 17, 3 end
  if beh == MB_DOWN_LEFT_STAIR_WARP then return -17, 3 end
  return 0, 0
end

function Collision.cell(cx, cy)
  if not Collision._grid or not Collision.inBounds(cx, cy) then
    return 0xff
  end
  return Collision._grid[cy * Collision._widthCells + cx + 1] or 0xff
end

-- Player dirs ↔ mapDef.connections keys (Dataset / pret use cardinal names).
local DIR_CONN = {
  up = "north",
  down = "south",
  left = "west",
  right = "east",
}

local function mapCellSize(def)
  if not def then return 0, 0 end
  local L = def.midLayout
  if L and L.width and L.height then
    return L.width, L.height
  end
  return tonumber(def.width) or 0, tonumber(def.height) or 0
end

--- Landing cell on dest after stepping off `dir` edge (FRLG metatile = one cell).
function Collision.connectionLanding(destDef, conn, dir, fromCx, fromCy)
  if not (destDef and conn) then return nil end
  local destW, destH = mapCellSize(destDef)
  if destW < 1 or destH < 1 then return nil end
  local offset = tonumber(conn.offset) or 0
  local x, y
  if dir == "up" then
    x, y = fromCx - offset, destH - 1
  elseif dir == "down" then
    x, y = fromCx - offset, 0
  elseif dir == "left" then
    x, y = destW - 1, fromCy - offset
  elseif dir == "right" then
    x, y = 0, fromCy - offset
  else
    return nil
  end
  x = math.max(0, math.min(destW - 1, x))
  y = math.max(0, math.min(destH - 1, y))
  return x, y
end

local function collWalkable(coll)
  local P = permissions()
  -- FRLG ledge metatiles carry map collision=1 (impassable). Extract encodes
  -- hop facing as Gen2 0xA0–0xA7, which Permissions treats as LAND — reject
  -- them here so you cannot climb from below; only ledgeLanding may clear them.
  if P and P.isLedge and P.isLedge(coll) then return false end
  if P and P.isWalkable then return P.isWalkable(coll) end
  return coll ~= 0x07 and coll ~= 0xff and coll ~= 0x29
end

--- Outdoor edge transition (Pallet↔Route 1). Seamless remap mid-step like
-- pret CameraMove → LoadMapFromCameraTransition / Gen2 World:tryConnection.
-- Returns true if the crossing was accepted.
function Collision.tryConnection(game, fromX, fromY, dir, run)
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then
    return false
  end
  local WarpMod = package.loaded["src.core.game3.warp"]
  if WarpMod and WarpMod.isBusy and WarpMod.isBusy() then
    return false
  end

  local mapDef = Collision._mapDef
  if not mapDef or type(mapDef.connections) ~= "table" then return false end
  local conn = mapDef.connections[dir]
    or mapDef.connections[DIR_CONN[dir] or ""]
  if not conn then return false end
  local destMap = conn.map or conn.mapId
  if type(destMap) ~= "string" then return false end

  local data = game and game.data and game.data.maps
  local destDef = data and data[destMap]
  if not destDef then return false end
  local Map = require("src.core.game3.map")
  if Map.ensureMidLayout then Map.ensureMidLayout(game, destMap, destDef) end

  local lx, ly = Collision.connectionLanding(destDef, conn, dir, fromX, fromY)
  if not lx then return false end

  local L = destDef.midLayout
  if L and L.collAt then
    if not collWalkable(L:collAt(lx, ly)) then return false end
  end

  local d = DELTA[dir]
  if not d then return false end

  local Runtime = package.loaded["src.core.game3.runtime"]
  local mod = Runtime and Runtime._mod
  local g = game or (Runtime and Runtime._game)
  local Player = require("src.core.game3.player")

  Map.load(mod, g, destMap, {
    x = lx,
    y = ly,
    facing = dir,
    seamless = true,
    depth1Connections = true,
  })

  -- Park one cell before landing and keep the step running so the seam does
  -- not hitch (same world pixels the neighbor strip already showed).
  local CELL = 16
  local WALK_FRAMES = 16
  local RUN_FRAMES = 8
  Player.cellX, Player.cellY = lx - d[1], ly - d[2]
  Player.px, Player.py = Player.cellX * CELL, Player.cellY * CELL
  Player.facing = dir
  Player.targetX, Player.targetY = lx, ly
  Player.moving = true
  Player.progress = 0
  Player.animClock = 0
  Player.running = run and true or false
  Player.jumping = false
  Player.spriteYOffset = 0
  Player.stepFrames = run and RUN_FRAMES or WALK_FRAMES
  Player.syncSavePosition(g)

  if Collision.isGrass and Collision.isGrass(lx, ly) then
    local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
    if okFx and FieldEffects and FieldEffects.tallGrassAt then
      FieldEffects.tallGrassAt(lx, ly, false)
    end
  end

  return true
end

function Collision.isWalkable(cx, cy)
  local P = permissions()
  local coll = Collision.cell(cx, cy)
  if P and P.isLedge and P.isLedge(coll) then
    return false
  end
  if P and P.isWalkable then
    return P.isWalkable(coll)
  end
  -- Fallback: treat 0x07 / 0xff as solid, water 0x29 as solid on foot.
  return coll ~= 0x07 and coll ~= 0xff and coll ~= 0x29
end

function Collision.isGrass(cx, cy)
  local P = permissions()
  local coll = Collision.cell(cx, cy)
  if P and P.isGrass then return P.isGrass(coll) end
  return coll == 0x18 or coll == 0x14
end

function Collision.isWater(cx, cy)
  local P = permissions()
  local coll = Collision.cell(cx, cy)
  if P and P.isWater then return P.isWater(coll) end
  return coll == 0x29
end

local function entityBlocks(game, tx, ty)
  local okO, Objects = pcall(require, "src.core.game3.objects")
  if okO and Objects and Objects.hasMap and Objects.hasMap() then
    if Objects.blocks(tx, ty) then return true end
    return false
  end
  local world = hostWorld(game)
  if not (world and world.npcs) then return false end
  for _, npc in ipairs(world.npcs) do
    if not npc.passable then
      local nx = npc.cellX or (npc.def and npc.def.x)
      local ny = npc.cellY or (npc.def and npc.def.y)
      if nx == tx and ny == ty then return true end
      if npc.moving and npc.targetX == tx and npc.targetY == ty then
        return true
      end
    end
  end
  return false
end

local function overrideBlocks(tx, ty)
  local Field = package.loaded["src.core.game3.field"]
  if not (Field and Field.metatileOverrides) then return false end
  for _, o in ipairs(Field.metatileOverrides) do
    if o.impassable and o.x == tx and o.y == ty then return true end
  end
  return false
end

--- Can the avatar enter cell (tx, ty) on foot?
-- Returns ok, reason ("bounds"|"tile"|"entity"|"water"|nil)
function Collision.canEnter(game, tx, ty, opts)
  opts = opts or {}
  local surfing = opts.surfing
  if surfing == nil then
    local P = package.loaded["src.core.game3.player"]
    surfing = P and P.surfing == true
  end

  -- Prefer owned grid; fall back to host map if unbound.
  if Collision._grid then
    if not Collision.inBounds(tx, ty) then return false, "bounds" end
    if overrideBlocks(tx, ty) then return false, "tile" end
    if entityBlocks(game, tx, ty) then return false, "entity" end
    local isW = Collision.isWater(tx, ty)
    if surfing then
      if isW then
        return true, nil
      else
        -- Dismount onto land: verify land tile is walkable
        if not Collision.isWalkable(tx, ty) then return false, "tile" end
        return true, nil
      end
    else
      if isW then return false, "water" end
      if not Collision.isWalkable(tx, ty) then return false, "tile" end
      return true, nil
    end
  end

  local world = hostWorld(game)
  local map = world and world.map
  if not map then return false, "bounds" end
  if map.inBounds and not map:inBounds(tx, ty) then return false, "bounds" end
  if overrideBlocks(tx, ty) then return false, "tile" end
  if entityBlocks(game, tx, ty) then return false, "entity" end
  if map.isWalkable and not map:isWalkable(tx, ty) then return false, "tile" end
  return true, nil
end

--- pret GetLedgeJumpDirection / ShouldJumpLedge: the DESTINATION cell (one
-- step along `dir`) is an impassable hop metatile whose facing matches `dir`.
-- Landing is two cells from `from` (Jump2). Wrong-facing approaches bump on
-- the ledge (isWalkable false); only the matching direction hops over it.
function Collision.ledgeLanding(game, fromX, fromY, dir)
  local P = permissions()
  if not (P and P.ledgeFacings) then return nil end
  local d = DELTA[dir]
  if not d then return nil end
  local destX, destY = fromX + d[1], fromY + d[2]
  local coll
  if Collision._grid then
    if not Collision.inBounds(destX, destY) then return nil end
    coll = Collision.cell(destX, destY)
  else
    local map = hostWorld(game) and hostWorld(game).map
    if not map then return nil end
    if map.inBounds and not map:inBounds(destX, destY) then return nil end
    if map.cellCollision then
      coll = map:cellCollision(destX, destY)
    end
  end
  local facings = P.ledgeFacings(coll)
  if not (facings and facings[dir]) then return nil end
  local tx, ty = fromX + d[1] * 2, fromY + d[2] * 2
  local ok = Collision.canEnter(game, tx, ty, {})
  if not ok then return nil end
  return tx, ty
end

local function resolveDest(game, warp)
  local destMap = warp.destMap or warp.map
  if type(destMap) ~= "string" or destMap == "" then
    local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
    if okC and MapCatalog and warp.mapGroup ~= nil then
      destMap = MapCatalog.mapIdFor(warp.mapGroup, warp.mapNum)
    end
    if type(destMap) ~= "string" then
      local Versions = require("src.import.gba.versions")
      destMap = Versions.mapIdFor and Versions.mapIdFor(warp.mapGroup, warp.mapNum)
    end
  else
    local okC, MapCatalog = pcall(require, "src.import.gba.map_catalog")
    if okC and MapCatalog and MapCatalog.resolve then
      destMap = MapCatalog.resolve(destMap) or destMap
    end
  end
  local destWarp = tonumber(warp.destWarp) or 1
  if type(destMap) ~= "string" then return nil end
  local data = game and game.data and game.data.maps
  local destDef = data and data[destMap]
  local warps = destDef and destDef.warps
  local landing = warps and warps[destWarp]
  if landing then
    return destMap, tonumber(landing.x) or 0, tonumber(landing.y) or 0
  end
  -- Fallback: use warp's own destX/destY if present.
  if warp.destX ~= nil then
    return destMap, tonumber(warp.destX) or 0, tonumber(warp.destY) or 0
  end
  return destMap, 0, 0
end

function Collision.warpAt(cx, cy)
  return Collision._warps[cy * 1024 + cx]
end

local function isBuilding(name)
  local n = string.upper(tostring(name or ""))
  return n:find("POKECENTER") or n:find("POKEMON_CENTER") or n:find("CENTER")
      or n:find("MART") or n:find("DEPT_STORE")
      or n:find("SILPH_CO") or n:find("HOUSE")
      or n:find("LAB") or n:find("GYM")
      or n:find("SAFARI_ZONE") or n:find("GAME_CORNER")
      or n:find("FAN_CLUB") or n:find("MUSEUM")
      or n:find("DAYCARE") or n:find("DAY_CARE")
      or n:find("CABLE_CLUB") or n:find("SCHOOL")
      or n:find("GATE") or n:find("BUILDING")
      or n:find("_1F") or n:find("_2F") or n:find("_3F")
      or n:find("_4F") or n:find("_5F")
end

--- Check if cell (cx, cy) is an entrance door warp
function Collision.isDoorWarp(game, cx, cy)
  local w = Collision.warpAt(cx, cy)
  if not w then
    local map = hostWorld(game) and hostWorld(game).map
    if map and map.warpAt then
      local hit = map:warpAt(cx, cy)
      w = hit and hit.def
    end
  end
  if not w then return nil end

  local destMap, destX, destY = resolveDest(game, w)
  if not destMap then return nil end

  local curMap = (game and game.currentMap) or (Collision._mapId)
  local okDoors, Doors = pcall(require, "src.core.game3.doors")
  if okDoors and Doors and Doors.getDoorEntryAt then
    local entry = Doors.getDoorEntryAt(curMap, cx, cy)
    if entry then
      return {
        warp = w,
        destMap = destMap,
        destX = destX,
        destY = destY,
        x = cx,
        y = cy,
        doorEntry = entry,
      }
    end
  end

  return nil
end

--- Check if cell (cx, cy) is an indoor exit mat warp leading to an outdoor animated door
function Collision.isExitWarp(game, cx, cy)
  local w = Collision.warpAt(cx, cy)
  if not w then
    local map = hostWorld(game) and hostWorld(game).map
    if map and map.warpAt then
      local hit = map:warpAt(cx, cy)
      w = hit and hit.def
    end
  end
  if not w then return nil end

  local destMap, destX, destY = resolveDest(game, w)
  if not destMap then return nil end

  local okDoors, Doors = pcall(require, "src.core.game3.doors")
  if okDoors and Doors and Doors.getDoorEntryAt then
    local entry = Doors.getDoorEntryAt(destMap, destX, destY)
    if entry then
      return {
        warp = w,
        destMap = destMap,
        destX = destX,
        destY = destY,
        x = cx,
        y = cy,
        doorEntry = entry,
      }
    end
  end

  return nil
end

--- Check if cell (cx, cy) is an escalator warp
function Collision.isEscalatorWarp(game, cx, cy, dir)
  local w = Collision.warpAt(cx, cy)
  if not w then
    local map = hostWorld(game) and hostWorld(game).map
    if map and map.warpAt then
      local hit = map:warpAt(cx, cy)
      w = hit and hit.def
    end
  end
  if not w then return nil end

  local destMap, destX, destY = resolveDest(game, w)
  if not destMap then return nil end

  local coll = Collision.cell(cx, cy)
  local curMap = (game and game.currentMap) or (Collision._mapId)
  local curUpper = string.upper(tostring(curMap or ""))
  local destUpper = string.upper(tostring(destMap or ""))

  -- pokefirered/src/metatile_behavior.c:126
  local beh = Collision.behavior(cx, cy)
  if beh ~= nil then
    if beh ~= MB_UP_ESCALATOR and beh ~= MB_DOWN_ESCALATOR then return nil end
    return {
      warp = w,
      destMap = destMap,
      destX = destX,
      destY = destY,
      escDir = (beh == MB_DOWN_ESCALATOR) and "down" or "up",
      x = cx,
      y = cy,
    }
  end

  local isEscalator = (curUpper:find("POKECENTER") or curUpper:find("POKEMON_CENTER") or curUpper:find("DEPT_STORE"))
      and (destUpper:find("POKECENTER") or destUpper:find("POKEMON_CENTER") or destUpper:find("DEPT_STORE"))

  if isEscalator then
    local escDir = "up"
    if curUpper:find("2F") and (destUpper:find("1F") or not destUpper:find("2F")) then
      escDir = "down"
    elseif curUpper:find("3F") and (destUpper:find("2F") or destUpper:find("1F")) then
      escDir = "down"
    elseif curUpper:find("4F") and (destUpper:find("3F") or destUpper:find("2F") or destUpper:find("1F")) then
      escDir = "down"
    elseif curUpper:find("5F") and (destUpper:find("4F") or destUpper:find("3F") or destUpper:find("2F") or destUpper:find("1F")) then
      escDir = "down"
    elseif coll == 0x6B then
      escDir = "down"
    end
    return {
      warp = w,
      destMap = destMap,
      destX = destX,
      destY = destY,
      escDir = escDir,
      x = cx,
      y = cy,
    }
  end
  return nil
end

-- pokefirered/src/field_control_avatar.c:839
function Collision.isStairWarp(game, cx, cy, dir)
  local beh = Collision.behavior(cx, cy)
  if not Collision.isStairWarpBehavior(beh) then return nil end
  if dir and Collision.stairWarpDir(beh) ~= dir then return nil end

  local w = Collision.warpAt(cx, cy)
  if not w then
    local map = hostWorld(game) and hostWorld(game).map
    if map and map.warpAt then
      local hit = map:warpAt(cx, cy)
      w = hit and hit.def
    end
  end
  if not w then return nil end

  local destMap, destX, destY = resolveDest(game, w)
  if not destMap then return nil end

  return {
    warp = w,
    destMap = destMap,
    destX = destX,
    destY = destY,
    behavior = beh,
    x = cx,
    y = cy,
  }
end

--- If standing on a warp cell, trigger game3 map load / host warp.
-- Door entrances (pressing UP in front of door), exit mats (pressing DOWN on mat),
-- and escalators (moving into escalator from adjacent cell) are triggered explicitly
-- via Player.tryMove, not on initial step landing.
function Collision.tryWarpAt(game, cx, cy, facing)
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then
    return false
  end

  local w = Collision.warpAt(cx, cy)
  if not w then
    local map = hostWorld(game) and hostWorld(game).map
    if map and map.warpAt then
      local hit = map:warpAt(cx, cy)
      w = hit and hit.def
    end
  end
  if not w then return false end

  local destMap, destX, destY = resolveDest(game, w)
  if not destMap then return false end

  local curMap = (game and game.currentMap) or (Collision._mapId)
  local curUpper = string.upper(tostring(curMap or ""))
  local destUpper = string.upper(tostring(destMap or ""))
  local coll = Collision.cell(cx, cy)

  -- Suppress auto-warp on landing for animated entrance doors, animated exit mats & escalators
  if Collision.isDoorWarp and Collision.isDoorWarp(game, cx, cy) then
    return false
  end
  if Collision.isExitWarp and Collision.isExitWarp(game, cx, cy) then
    return false
  end
  if Collision.isEscalatorWarp and Collision.isEscalatorWarp(game, cx, cy, facing) then
    return false
  end
  -- pokefirered/src/field_control_avatar.c:901
  if Collision.isStairWarpBehavior(Collision.behavior(cx, cy)) then
    return false
  end

  local Runtime = package.loaded["src.core.game3.runtime"]
  local mod = Runtime and Runtime._mod
  local g = game or (Runtime and Runtime._game)

  local MapIds = require("src.core.game3.map_ids")
  if MapIds.isGame3Map(destMap) then
    local Warp = require("src.core.game3.warp")

    local isTeleport = (curUpper:find("SILPH_CO") or curUpper:find("SAFFRON_GYM") or curUpper:find("ROCKET_HIDEOUT") or curUpper:find("POKEMON_MANSION"))
        and not (destUpper:find("ELEVATOR") or destUpper:find("1F") or destUpper:find("PLAYERS_HOUSE"))
        and (coll == 0x75 or coll == 0x72)

    local isFallHole = (coll == 0x76) or ((curUpper:find("SEAFOAM") or curUpper:find("MT_MOON") or curUpper:find("VICTORY_ROAD")) and coll == 0x76)

    if isTeleport then
      return Warp.startTeleport(mod, g, destMap, destX, destY)
    end

    if isFallHole then
      return Warp.startFall(mod, g, destMap, destX, destY)
    end

    Warp.request(mod, g, destMap, destX, destY, facing or "down", {
      fade = true,
      door = false,
      doorX = cx,
      doorY = cy,
    })
    return true
  end

  if not mod then return false end

  -- Leaving Sevii — hand back to host.
  if Runtime and Runtime.isActive and Runtime.isActive() then
    local Bridge = require("src.core.game3.bridge")
    if Bridge.persistSessionOnly then
      Bridge.persistSessionOnly(mod, g)
    end
    Runtime.stop(mod, g)
  end

  local world = hostWorld(g)
  if world and world.warpToMapId then
    world:warpToMapId(destMap, destX, destY, facing or "down")
    return true
  end
  return false
end

return Collision
