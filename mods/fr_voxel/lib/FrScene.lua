-- The 3D scene: one canvas, three passes.
--
--   1. terrain   depth-tested extruded geometry (FrTerrain)
--   2. characters  ordinary 2D draws slid onto their projected anchors
--   3. hand back the canvas, which the engine composites over the frame
--      in place of the flat world blit
--
-- Returning nil at any point is the contract for "not this frame": the
-- engine keeps the vanilla 2D path rather than showing an empty image,
-- which is what a first frame (mesh still building), a driver without
-- depth-canvas support or a headless run all get.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Voxel = V.require("VoxelState")
local FrTerrain = V.require("FrTerrain")
local FrActors = V.require("FrActors")

local FrScene = {}

-- Debug chatter for the "not this frame" branches.  Off by default and
-- flipped by hand (or by a test through mod.exports.scene): the mod sandbox
-- hides the environment, so there is no env var to gate it on, and a
-- per-frame line would drown the engine log anyway.  The once-only warnings
-- in FrTerrain/Voxel3D are what a broken device actually reports.
local DEBUG = false
local function dbg(msg)
  if DEBUG then pcall(print, "[fr_voxel] " .. msg) end
end
FrScene.dbg = dbg

-- Light afternoon sky: at the shallow end of the angle ladder the horizon
-- comes into frame, and this is what shows past the edge of the map.
local SKY = { 0.55, 0.76, 0.94, 1 }

-- Which maps render in 3D at each rung of the ladder (ctx.level).  nil at
-- a rung means "every map".  The prototype is scoped by hand: Pallet Town
-- first, Route 1 as the second rung, everything only once both have been
-- walked.
local SCOPE = {
  [1] = { FR_PALLET_TOWN = true },
  [2] = { FR_PALLET_TOWN = true, FR_ROUTE_1 = true, FR_ROUTE1 = true },
  [3] = nil,
}

--- Whether this rung of the ladder renders this map at all.  false means
-- drawWorld returns nil for the frame, which the engine treats as "keep
-- the vanilla 2D path" -- so walking out of Pallet Town on rung 1 lands
-- on the ordinary flat field rather than a broken scene.
function FrScene.allowed(mapId, level)
  local rung = math.floor(tonumber(level) or 1)
  if rung < 1 then rung = 1 end
  local scope = SCOPE[rung]
  if scope == nil then return true end
  return scope[mapId] == true
end

-- The scene canvas is sized in FRAMEBUFFER PIXELS.  The engine composites
-- a pipeline's canvas with draw(canvas, x, y, 0, 1/dpiX, 1/dpiY), so a
-- canvas measured in LOVE units pays the DPI scale twice and lands at a
-- third of the screen in the corner -- the trap the Dramatic Shape voxel
-- mod documents, invisible on a desktop where units and pixels agree.
local function sceneSize(ctx)
  if ctx.pixelsWidth and ctx.pixelsHeight then
    return ctx.pixelsWidth, ctx.pixelsHeight
  end
  local w, h = tonumber(ctx.width) or 0, tonumber(ctx.height) or 0
  local dpiX, dpiY = tonumber(ctx.dpiX) or 1, tonumber(ctx.dpiY) or 1
  if w > 0 and h > 0 then
    return math.floor(w * dpiX + 0.5), math.floor(h * dpiY + 0.5)
  end
  if love and love.graphics and love.graphics.getPixelDimensions then
    local pw, ph = love.graphics.getPixelDimensions()
    if pw and ph and pw > 0 and ph > 0 then return pw, ph end
  end
  return 240, 160
end

--- Render the world.  nil = fall back to the 2D path this frame.
function FrScene.render(ctx)
  if not (ctx and ctx.state and ctx.cam) then
    dbg("decline: ctx incomplete (state/cam)")
    return nil
  end
  if not Voxel3D.available() then
    dbg("decline: Voxel3D not available")
    return nil
  end
  local okM, Map = pcall(require, "src.core.game3.map")
  if not (okM and type(Map) == "table") then
    dbg("decline: no game3 map module")
    return nil
  end
  if not FrScene.allowed(Map.current, ctx.level) then
    dbg(("decline: %s out of scope at rung %s")
      :format(tostring(Map.current), tostring(ctx.level)))
    return nil
  end
  local vw, vh = tonumber(ctx.vw) or 240, tonumber(ctx.vh) or 160
  if vw <= 0 or vh <= 0 then
    dbg("decline: view size " .. vw .. "x" .. vh)
    return nil
  end

  if not FrTerrain.ensure(ctx.state, vw, vh) then
    dbg("decline: terrain not built")
    Voxel.ready = false
    return nil
  end
  Voxel.ready = true

  local w, h = sceneSize(ctx)
  local cx = ctx.cam.x + vw / 2
  local cy = ctx.cam.y + vh / 2
  if not Voxel3D.beginScene(w, h, cx, cy, vw, vh, SKY) then
    dbg(("decline: beginScene %dx%d refused"):format(w, h))
    return nil
  end

  FrTerrain.draw()
  local canvas = Voxel3D.endScene()
  if not canvas then
    dbg("decline: endScene handed back nothing")
    return nil
  end

  if Voxel3D.beginOverlay() then
    FrActors.draw(ctx, ctx.actors)
    Voxel3D.endOverlay()
  end
  dbg(("frame ok: canvas %s"):format(tostring(canvas)))
  return canvas
end

function FrScene.invalidate()
  FrTerrain.invalidate()
end

return FrScene
