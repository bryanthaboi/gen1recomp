-- Characters in the FireRed diorama.
--
-- There is no voxel character model here: a FireRed sprite is 16x16 of
-- art that only exists as art, so it is drawn the way the flat field
-- draws it -- through the engine's own actor path, with the same fallback
-- chain (live sprite sheet, resolved graphics id, finally a block) -- and
-- the camera is slid so the projected anchor and the flat draw coincide.
-- The depth scale then grows the figure with its distance from the eye,
-- which is the one thing the flat path cannot do.
--
-- Actors are composited after the depth-tested terrain (Voxel3D's overlay
-- pass), so a character never disappears behind geometry: honest occlusion
-- needs the sprite slabs and ghost pass the Dramatic Shape voxel mod
-- builds, which is a FASE 3 item.  Draw order inside the overlay is the
-- field's own: normal-priority actors first, then the elevated ones.

local V = ...
local Voxel3D = V.require("Voxel3D")
local FrTerrain = V.require("FrTerrain")

local FrActors = {}

local function fieldView()
  local ok, F = pcall(require, "src.core.game3.field_view")
  if ok and type(F) == "table" and F.drawActor then return F end
  return nil
end

--- Draw every collected actor into the scene canvas.
-- `cast` is FieldView.pipelineActors' result; `ctx.state` is the game.
function FrActors.draw(ctx, cast)
  if not (ctx and cast) then return end
  local F = fieldView()
  if not F then return end
  local list = {}
  for _, a in ipairs(cast.under or {}) do list[#list + 1] = a end
  for _, a in ipairs(cast.over or {}) do list[#list + 1] = a end

  love.graphics.setColor(1, 1, 1, 1)
  for i = 1, #list do
    local a = list[i]
    local fx = (a.x or 0) + 8
    local fy = (a.y or 0) + 16
    local ground = FrTerrain.heightAtWorld(fx, fy)
    local sx, sy, k = Voxel3D.project(fx, ground, fy)
    if sx and sy then
      k = tonumber(k) or 1
      if k < 0.05 then k = 0.05 elseif k > 8 then k = 8 end
      love.graphics.push()
      love.graphics.scale(k, k)
      -- slide the flat camera so this actor's feet land on (sx/k, sy/k),
      -- which the scale below puts back on (sx, sy)
      F.drawActor(ctx.state, cast.mapDef, a, fx - sx / k, fy - sy / k)
      love.graphics.pop()
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return FrActors
