-- Overworld battles: the two mons, as geometry standing on the map.
--
-- Not pics composited over a picture of the world -- quads INSIDE it, drawn
-- in the same 3D pass as the terrain, from the same camera, through the same
-- shader. Which means they get everything the world gets and nothing has to
-- be faked for them: the depth buffer decides what is in front of what, the
-- sun pass sees them and throws their real silhouettes across the ground,
-- and their size on screen is whatever standing on that tile at that
-- distance actually looks like.
--
-- One quad, standing upright with its feet on the cell and yawed to face the
-- camera. Upright rather than leaned back, unlike the free-roam mode's
-- character cards: those lean because that camera looks DOWN and a standing
-- card would foreshorten to nothing, and this one looks along the ground
-- from about a foot above it, where a card standing up is simply correct.
--
-- The shader's alpha discard cuts the mon's exact outline out of the quad,
-- so a Pokemon is its own silhouette against the world with no matte, no
-- billboard edge and no sorting to get wrong.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")

local BattleBillboard = {}

-- How wide a full-size (7x7 tile) mon stands, in world pixels. One overworld
-- square, so a Pokemon covers the tile it is on and no more; a species whose
-- pic is smaller than the full buffer comes out proportionally smaller,
-- which is how the artwork's own size differences survive the trip.
BattleBillboard.FULL_W = 16
BattleBillboard.FULL_PIC = 56     -- the pic size FULL_W refers to

-- A hair of camera-ward bias, so a card standing ON the ground plane wins
-- the depth test against it instead of z-fighting the tile it is rooted to.
BattleBillboard.PULL = 1.5

local quad = nil                  -- nil = untried, false = unavailable

-- The unit card: x in -0.5..0.5, y in 0..1, z = 0, UV over the whole
-- texture. Feet on the model origin, so the model matrix only has to say
-- where the mon is standing and how big it is.
--
-- Which puts this card OFF the voxel grid, alone among the meshes in this
-- mode: the rest are built one unit per voxel in their own model space --
-- terrain in world pixels, a character's card in the sprite's own pixels --
-- and the wireframe is the integer planes of that space (see VoxelGrid).
-- One unit here is the whole card, so the only integer plane inside it is
-- x = 0, which is the pic's centre column: a single stray line straight
-- down the middle of every Pokemon and no seams anywhere else.
--
-- The card stays a unit card, because a mon's size on screen is decided by
-- the artwork's own dimensions and the distance it is standing at, and a
-- unit card is what lets one matrix say both. Whoever draws it turns the
-- wireframe off instead (Voxel3D.seams) -- a mesh that is not on the voxel
-- grid does not get a voxel grid drawn on it.
local function unitQuad()
  if quad ~= nil then return quad or nil end
  local verts = {
    { -0.5, 0, 0, 0, 1, 1 },
    { 0.5, 0, 0, 1, 1, 1 },
    { 0.5, 1, 0, 1, 0, 1 },
    { -0.5, 1, 0, 0, 0, 1 },
  }
  local indices = {}
  Voxel3D.pushQuad(indices, 0)
  local mesh = Voxel3D.newMesh(verts, indices)
  quad = mesh or false
  return quad or nil
end

BattleBillboard.mesh = unitQuad

-- The yaw that turns the card's face toward the eye. The quad's normal is
-- +Z before rotation, so this is just the bearing from the mon to the
-- camera -- flattened to the horizontal, because a card that also tipped to
-- face a camera above it would lift its feet off the floor.
function BattleBillboard.yawToward(x, z, eye)
  if not eye then return 0 end
  return math.atan2(eye[1] - x, eye[3] - z)
end

-- Stand a `w` x `h` card with its feet centred on world (x, y, z).
function BattleBillboard.matrix(x, y, z, w, h, yaw)
  return Mat4.mul(Mat4.mul(Mat4.translate(x, y, z), Mat4.rotateY(yaw)),
                  Mat4.scale(w, h, 1))
end

-- The world size a pic of `pw` x `ph` texture pixels stands at.
function BattleBillboard.sizeFor(pw, ph)
  if not (pw and ph and pw > 0 and ph > 0) then return 0, 0 end
  local scale = BattleBillboard.FULL_W / BattleBillboard.FULL_PIC
  return pw * scale, ph * scale
end

-- Draw one mon. `tex` is the pic already rendered to a texture (see
-- OverworldBattle, which lets the engine's own battler draw produce it, so
-- every faint slide, blink and squish comes along), `grow` the send-out
-- animation's scale or nil.
function BattleBillboard.draw(tex, x, y, z, grow)
  local mesh = unitQuad()
  if not (mesh and tex) then return false end
  local pw, ph = tex:getDimensions()
  local w, h = BattleBillboard.sizeFor(pw, ph)
  if grow then w, h = w * grow, h * grow end
  if w <= 0 or h <= 0 then return false end
  local yaw = BattleBillboard.yawToward(x, z, Voxel3D.eye)
  -- off the voxel grid, so no wireframe on it (see unitQuad)
  Voxel3D.seams(false)
  Voxel3D.draw(mesh, tex, BattleBillboard.matrix(x, y, z, w, h, yaw),
               BattleBillboard.PULL)
  Voxel3D.seams(true)
  return true
end

-- The same card, as the SUN sees it: no camera-ward pull (that is a trick
-- for the view's own depth buffer and would drag the shadow off its owner)
-- and no draw call of its own, because the shadow pass has its own.
function BattleBillboard.caster(shadowMap, tex, x, y, z, grow)
  local mesh = unitQuad()
  if not (mesh and tex) then return false end
  local pw, ph = tex:getDimensions()
  local w, h = BattleBillboard.sizeFor(pw, ph)
  if grow then w, h = w * grow, h * grow end
  if w <= 0 or h <= 0 then return false end
  local yaw = BattleBillboard.yawToward(x, z, Voxel3D.eye)
  shadowMap.draw(mesh, tex, BattleBillboard.matrix(x, y, z, w, h, yaw))
  return true
end

function BattleBillboard.invalidate()
  quad = nil
end

return BattleBillboard
