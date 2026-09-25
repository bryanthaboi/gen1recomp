-- Terrain geometry for the FireRed diorama.
--
-- The 2D path blits the current map (and its connected neighbours) as
-- metatile layers; here the same cells become extruded columns.  For each
-- cell the mesh carries the metatile's own atlas quad, so the ground
-- looks exactly like the flat game and the sides are the same tile
-- stretched down the height of the step -- which is what makes a house
-- roof, a tree canopy or the border ring read as a solid block instead of
-- a sticker.
--
-- Heights are DERIVED, not authored: there is no FireRed voxel-height
-- table, so the collision byte is the only signal the game itself has for
-- "you cannot stand here".  A cell the player can walk on stays at the
-- ground plane, a cell they cannot is raised one tile, and water is sunk.
-- That is enough for Pallet Town: buildings, fences and the border
-- extrude, while roads, grass and doorways stay flat.
--
-- Nothing here mutates the map: the collision array and the native
-- tileset atlas are read exactly as the 2D path reads them.

local V = ...
local Voxel3D = V.require("Voxel3D")

local FrTerrain = {}

local CELL = 16
-- Cells of apron meshed around the root map: enough to reach past the
-- connected neighbours the view can see, and to hide the void behind a
-- ring of border tiles (which the collision byte already reports as
-- solid, so it extrudes as a wall).
local APRON = 18
local MAX_CELLS = 9000
local WATER_DROP = 4
local SKIRT = -32

local heights = {}     -- flat row-major height of the BUILT rectangle
local scratch = {}      -- heights of the build under construction
local rect = nil        -- { x0, y0, W } describing `heights`
local signature = ""
local meshes = nil     -- pair -> { mesh = ..., image = ... }
local dirty = true
local warned = false

local function say(msg)
  pcall(print, "[fr_voxel] " .. msg)
end

-- UV axis per face direction: which corner component drives the atlas U
-- and which drives V.  Top faces map V onto +Z so the tile's own top edge
-- faces north, exactly as the flat blit puts it.
local FACE_U = { [1] = 3, [2] = 3, [3] = 1, [4] = 1, [5] = 1, [6] = 1 }
local FACE_V = { [1] = 2, [2] = 2, [3] = 3, [4] = 3, [5] = 2, [6] = 2 }

local function engineRequire(name)
  local ok, m = pcall(require, name)
  if ok then return m end
  return nil
end

--- Which map owns a world cell: its definition, layout and the cell in
-- that layout's own space.  Falls back to the root layout, whose
-- midAt/collAt wrap onto the border ring -- the same fill the pret
-- connection code uses, so cells beyond every connected map still get a
-- tile and a collision byte rather than a hole.
local function ownerAt(rootDef, rootL, world, cx, cy)
  if cx >= 0 and cy >= 0 and cx < rootL.width and cy < rootL.height then
    return rootDef, rootL, cx, cy
  end
  for i = 1, #world do
    local e = world[i]
    local L = e.def and e.def.midLayout
    if L then
      local lx, ly = cx - e.ox, cy - e.oy
      if lx >= 0 and ly >= 0 and lx < L.width and ly < L.height then
        return e.def, L, lx, ly
      end
    end
  end
  return rootDef, rootL, cx, cy
end

local function passable(coll)
  local P = engineRequire("src.world.gen2.Permissions")
  if P and P.isWalkable then
    local ok, res = pcall(P.isWalkable, coll)
    if ok then return res and true or false end
  end
  return coll ~= 0x07 and coll ~= 0xff and coll ~= 0x29
end

local function isWater(def, lx, ly, coll)
  local okC, Collision = pcall(require, "src.core.game3.collision")
  if okC and Collision and Collision.isWaterOn then
    local ok, res = pcall(Collision.isWaterOn, def, lx, ly, coll)
    if ok then return res and true or false end
  end
  local P = engineRequire("src.world.gen2.Permissions")
  if P and P.isWater then
    local ok, res = pcall(P.isWater, coll)
    if ok then return res and true or false end
  end
  return coll == 0x29
end

-- NativeTileset.slotFor, but pcall'd: a mod must not be able to take the
-- frame down by asking a tileset it has no business asking.
local function NativeSlot(ts, mid)
  local ok, NativeTileset = pcall(require, "src.core.game3.tileset_native")
  if ok and NativeTileset and NativeTileset.slotFor then
    local okS, slot = pcall(NativeTileset.slotFor, ts, mid)
    if okS and type(slot) == "number" then return slot end
  end
  if type(ts.midToSlot) == "table" then return ts.midToSlot[mid] end
  return nil
end

--- The atlas image a tileset pair draws from.  nil means this map cannot
-- be meshed (no native tileset loaded for it).
local function atlasFor(pair)
  local okT, NativeTileset = pcall(require, "src.core.game3.tileset_native")
  if not (okT and NativeTileset and type(pair) == "string") then return nil end
  local ts = NativeTileset.get(pair)
  if not (ts and ts.image and ts.cols) then return nil end
  return ts
end

--- The atlas rectangle one metatile draws from.
local function uvFor(ts, mid)
  if not ts then return nil end
  local slot = NativeSlot(ts, mid)
  if type(slot) ~= "number" or slot < 0 then return nil end
  local sx = (slot % ts.cols) * CELL
  local sy = math.floor(slot / ts.cols) * CELL
  local iw, ih = ts.image:getDimensions()
  if not (iw and ih and iw > 0 and ih > 0) then return nil end
  return { u0 = sx / iw, v0 = sy / ih,
           u1 = (sx + CELL) / iw, v1 = (sy + CELL) / ih }
end

-- One quad: four vertices, six indices, in the shared Voxel3D shape.  The
-- quad index is read back off the index list itself, so each chunk counts
-- its own quads.
local function emitFace(chunk, faceId, x, z, y0, y1, uv)
  local verts, indices = chunk.verts, chunk.indices
  local corners = Voxel3D.FACE_CORNERS[faceId]
  local au, av = FACE_U[faceId], FACE_V[faceId]
  local shade = Voxel3D.FACE_SHADE[faceId]
  local dy = y1 - y0
  local du, dv = uv.u1 - uv.u0, uv.v1 - uv.v0
  for i = 1, 4 do
    local c = corners[i]
    local n = #verts
    verts[n + 1] = x + c[1] * CELL
    verts[n + 2] = y0 + c[2] * dy
    verts[n + 3] = z + c[3] * CELL
    verts[n + 4] = uv.u0 + c[au] * du
    verts[n + 5] = uv.v0 + c[av] * dv
    verts[n + 6] = shade
  end
  Voxel3D.pushQuad(indices, #indices / 6)
end

local function worldSignature(reachW, reachH)
  local Map = engineRequire("src.core.game3.map")
  if not Map then return "" end
  local s = tostring(Map.current) .. "|" .. reachW .. "," .. reachH
  for i = 1, #Map.world do
    local e = Map.world[i]
    s = s .. ";" .. tostring(e.id) .. "@" .. tostring(e.ox) .. "," .. tostring(e.oy)
  end
  return s
end

--- Make sure the mesh matches the world the field is showing.
-- Rebuilds only when the map, the connected-neighbour window or a block
-- itself changed (FrTerrain.markDirty), so walking is free: the vertices
-- live in absolute world coordinates and the camera moves over them.
function FrTerrain.ensure(game, vw, vh)
  local Map = engineRequire("src.core.game3.map")
  if not Map then return false end
  -- the same reach FieldView.draw asks for, so the two never disagree and
  -- recompute the neighbour window every other frame
  local reachW = math.ceil((vw or 0) / CELL)
  local reachH = math.ceil((vh or 0) / CELL)
  Map.refreshWorld(game, reachW, reachH, Map.current)
  local sig = worldSignature(reachW, reachH)
  if not dirty and meshes and sig == signature then return true end

  local maps = game and game.data and game.data.maps
  local rootDef = maps and maps[Map.current]
  local rootL = rootDef and rootDef.midLayout
  if not rootL then return false end

  -- The apron shrinks on a map too big to mesh in one piece, so a large
  -- route still gets built (tighter, but built) instead of timing out.
  local apron = APRON
  while apron > 4
      and (rootL.width + 2 * apron) * (rootL.height + 2 * apron) > MAX_CELLS do
    apron = apron - 4
  end
  local x0, y0 = -apron, -apron
  local x1, y1 = rootL.width + apron - 1, rootL.height + apron - 1
  local W, H = x1 - x0 + 1, y1 - y0 + 1
  local world = Map.world

  -- pass one: resolve every cell's tile, height and atlas rectangle
  local cells, atlasOf = {}, {}
  local n, skipped = 0, 0
  for cy = y0, y1 do
    for cx = x0, x1 do
      local def, L, lx, ly = ownerAt(rootDef, rootL, world, cx, cy)
      local mid = L:midAt(lx, ly)
      local coll = L:collAt(lx, ly)
      local y = 0
      if isWater(def, lx, ly, coll) then
        y = -WATER_DROP
      elseif not passable(coll) then
        y = CELL
      end
      scratch[(cy - y0) * W + (cx - x0) + 1] = y

      local pair = def.pair or L.pair or rootDef.pair or "?"
      local chunk = atlasOf[pair]
      if chunk == nil then
        local ts = atlasFor(pair)
        chunk = ts and { pair = pair, image = ts.image, ts = ts,
                         verts = {}, indices = {} } or false
        atlasOf[pair] = chunk
      end
      if chunk then
        local uv = uvFor(chunk.ts, mid)
        if uv then
          n = n + 1
          cells[n] = { cx = cx, cy = cy, y = y, uv = uv, chunk = chunk }
        else
          skipped = skipped + 1
        end
      else
        skipped = skipped + 1
      end
    end
  end

  if n == 0 then
    if not warned and skipped > 0 then
      warned = true
      say("no native tileset atlas for this map -- staying on the 2D path")
    end
    dirty = false
    signature = sig
    return false
  end
  if skipped > 0 and not warned then
    warned = true
    say(skipped .. " cell(s) had no atlas tile and were left out")
  end

  local function heightAt(cx, cy)
    if cx < x0 or cx > x1 or cy < y0 or cy > y1 then return SKIRT end
    return scratch[(cy - y0) * W + (cx - x0) + 1] or SKIRT
  end

  -- pass two: top face, plus whichever side faces a lower neighbour leaves
  for i = 1, n do
    local cell = cells[i]
    local cx, cy, y, uv = cell.cx, cell.cy, cell.y, cell.uv
    local chunk = cell.chunk
    local wx, wz = cx * CELL, cy * CELL
    emitFace(chunk, 3, wx, wz, y, y, uv)
    local e = heightAt(cx + 1, cy)
    if e < y then emitFace(chunk, 1, wx, wz, e, y, uv) end
    e = heightAt(cx - 1, cy)
    if e < y then emitFace(chunk, 2, wx, wz, e, y, uv) end
    e = heightAt(cx, cy + 1)
    if e < y then emitFace(chunk, 5, wx, wz, e, y, uv) end
    e = heightAt(cx, cy - 1)
    if e < y then emitFace(chunk, 6, wx, wz, e, y, uv) end
  end

  local out, count = {}, 0
  for _, chunk in pairs(atlasOf) do
    if chunk then
      local mesh = Voxel3D.newMesh(chunk.verts, chunk.indices)
      if mesh then
        out[chunk.pair] = { mesh = mesh, image = chunk.image }
        count = count + 1
      end
    end
  end
  if count == 0 then return false end

  FrTerrain.release()
  meshes = out
  heights, scratch = scratch, heights
  rect = { x0 = x0, y0 = y0, W = W }
  signature = sig
  dirty = false
  return true
end

--- Ground height under a world pixel, for anchoring a character to the
-- terrain it is standing on.  Returns 0 outside the built rectangle.
function FrTerrain.heightAtWorld(wx, wy)
  if not rect then return 0 end
  local cx = math.floor((wx or 0) / CELL)
  local cy = math.floor((wy or 0) / CELL)
  local i = (cy - rect.y0) * rect.W + (cx - rect.x0) + 1
  local h = heights[i]
  if h == nil then return 0 end
  return h
end

--- A block was replaced on the map (Cut, Rock Smash, a script): the
-- collision byte under it changed, so the extrusion has to follow.
function FrTerrain.markDirty()
  dirty = true
end

function FrTerrain.release()
  if meshes then
    for _, e in pairs(meshes) do
      if e.mesh and e.mesh.release then pcall(e.mesh.release, e.mesh) end
    end
    meshes = nil
  end
  rect = nil
  dirty = true
end

FrTerrain.invalidate = FrTerrain.release

--- Draw every built chunk under the current 3D camera.
function FrTerrain.draw()
  if not meshes then return false end
  local drew = false
  for _, e in pairs(meshes) do
    if e.mesh then
      Voxel3D.draw(e.mesh, e.image, nil, 0)
      drew = true
    end
  end
  return drew
end

function FrTerrain.ready()
  return meshes ~= nil
end

return FrTerrain
