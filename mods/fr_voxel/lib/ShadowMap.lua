-- Cast-shadow pass, stubbed out for the FireRed prototype.
--
-- The scene shader declares the shadow sampler unconditionally, so the
-- uniforms have to exist even when nothing is rendering into them -- an
-- unbound sampler is a driver-dependent crash rather than a graceful
-- fallback (see Voxel3D.beginScene).  Everything here answers "there is no
-- shadow map": the shader receives sunDark = 0 and the terrain keeps its
-- baked per-face shading, which already reads as a light from the
-- southeast.
--
-- Enabling it means the caster/lit passes the Dramatic Shape voxel mod
-- runs (Voxel3D.casterMatrix + ShadowMap.start/render around the scene),
-- which is a FASE 3 item: it wants the character cards standing upright
-- for the sun and a second render target per frame.
--
-- Origin: DramaticShapeVoxelMod (lib/ShadowMap.lua), reduced to the
-- surface Voxel3D reads.

local ShadowMap = {}

-- never active: no shadow pass ever runs in this build
function ShadowMap.active() return nil end
function ShadowMap.texture() return nil end
ShadowMap.invalidate = nil

-- sent unconditionally; only read when active() answers a map
ShadowMap.uvVP = nil
ShadowMap.bias = 0.0025
ShadowMap.res = 256

-- the sun's screen-space shear, kept for Voxel3D's documentation and for
-- any future caster work: south-east, throwing shadows up and to the left
ShadowMap.KX = -0.45
ShadowMap.KZ = -0.45

return ShadowMap
