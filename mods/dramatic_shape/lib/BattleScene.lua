-- Overworld battles: one frame of the arena, as geometry.
--
-- The same world the free-roam mode draws, from a placed camera instead of
-- the orbit, at the WINDOW's own pixel resolution -- not the GB's. The
-- backdrop reaches the screen through Renderer's worldOverride, the seam a
-- render pipeline's finished world image already composites through, which
-- is drawn one canvas pixel to one screen pixel; the 160x144 battle screen
-- then blits over it in the classic letterbox. So the world is as crisp as
-- the free-roam diorama and the pics, HUDs and text box stay exactly the
-- chunky GB art they are.
--
-- Rendering the whole window rather than just the letterbox means the
-- framing has to be split in two. The RIG frames the GB's 160x144 (see
-- BattleCam, which is solved against coordinates in that frame); this
-- module widens the lens by exactly the ratio the window bears to the
-- letterbox, so the letterbox sub-rectangle of what gets rendered is
-- bit-for-bit the framing the rig asked for, and everything outside it is
-- extra picture. That is what lets the two mons be PINNED: their cells
-- project to the same GB coordinates at any window size or zoom.
--
-- Characters are deliberately absent. The overworld cast is culled for the
-- length of the battle (see OverworldBattle), so this pass has terrain,
-- grass and flowers and nothing that walks -- the arena is empty, which is
-- what makes it an arena.
--
-- Everything expensive is shared with the free-roam mode rather than
-- duplicated: the same chunk meshes out of ChunkMesher, the same palette
-- atlas out of TerrainAtlas, the same sun out of ShadowMap. A battle on a
-- map already meshed for walking around costs the frame it draws and
-- nothing else.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel3D = V.require("Voxel3D")
local ShadowMap = V.require("ShadowMap")
local ChunkMesher = V.require("ChunkMesher")
local TerrainAtlas = V.require("TerrainAtlas")
local VoxelScene = V.require("VoxelScene")
local BattleCam = V.require("BattleCam")
local BattleBillboard = V.require("BattleBillboard")
local VoxelGrid = V.require("VoxelGrid")
local DayNight = V.require("DayNight")
local PaletteFX = require("src.render.PaletteFX")
local Map = require("src.world.Map")

local BattleScene = {}

-- The GB frame the battle screen is drawn in, and the frame BattleCam's rig
-- is solved against.
BattleScene.GB_W = 160
BattleScene.GB_H = 144

-- A map cell in world pixels: the overworld square a mon stands on, which is
-- both what the arena is measured in and what a mon is sized to.
BattleScene.CELL = 16

-- How far into black a shadow goes in the arena, against the free-roam
-- mode's own lighter setting.
--
-- Darker on purpose, and only here. Walking around, a shadow is scenery and
-- wants to stay out of the way of reading the map. In a battle it is doing
-- one specific job: the two mons are flat cards, and the ONLY thing telling
-- the eye they are standing on that floor rather than hanging in front of it
-- is the shadow they put on it. A faint one leaves them floating.
BattleScene.SHADOW_ALPHA = 0.68

-- Which rung of the sky ramp an indoor void is painted with. A room has no
-- sky, but it does have somewhere the geometry stops, and leaving that
-- transparent would show the letterbox clear through the gaps.
local INDOOR_SHADE = 4

-- ------- where the GB frame sits inside the window
--
-- Renderer blits worldOverride one canvas pixel to one screen pixel and then
-- blits the 160x144 UI canvas into a centred, integer-scaled letterbox. So
-- these have to agree with Renderer:endFrame exactly, or the pins land off
-- the mons by however much they disagree.
function BattleScene.letterbox()
  local Renderer = require("src.render.Renderer")
  local pw, ph = BattleScene.pixelSize()
  local s = Renderer:fitScale()
  return math.floor((pw - BattleScene.GB_W * s) / 2),
         math.floor((ph - BattleScene.GB_H * s) / 2),
         s, pw, ph
end

-- The window in FRAMEBUFFER pixels, which is what the override blit works
-- in. love.graphics.getDimensions is in LOVE units and differs from this by
-- the display density on mobile.
function BattleScene.pixelSize()
  if love.graphics.getPixelDimensions then
    local pw, ph = love.graphics.getPixelDimensions()
    if pw and ph and pw > 0 and ph > 0 then return pw, ph end
  end
  return love.graphics.getDimensions()
end

-- Widen the rig's vertical field of view from the GB frame to the whole
-- window, so the letterbox rows show exactly what the rig framed.
--
-- The horizontal falls out of it: at aspect pw/ph the window's half-width is
-- tan(fov/2) * pw/ph, and the letterbox is 160*s of those pw pixels, which
-- works back out to the GB frame's own 160/144. So one scale on the vertical
-- pins both axes.
function BattleScene.letterboxFov(fovGB, ph, s)
  local span = BattleScene.GB_H * s
  if span <= 0 then return fovGB end
  return 2 * math.atan(math.tan(fovGB / 2) * ph / span)
end

-- ------- palette
--
-- The world palette a map draws under, in the shape VoxelScene's colour
-- helpers take. Rebuilt per frame from the overworld state, which is where
-- the engine's own pipeline context gets it too (OverworldController's
-- ctx.paletteFor).
local function paletteFor(state, home)
  return function(map)
    return PaletteFX.pal(require("src.core.Game").data,
                         state:paletteNameFor(map or home))
  end
end

-- ------- the map the fight is staged on
--
-- Normally the one the player is standing on. An authored arena may name
-- another floor of the same cave or building (see BattleArena), and then the
-- scene is THAT map: its terrain, its palette, its sky. Nothing else in the
-- battle changes -- the fight, the party, the player's own position are all
-- exactly where they were.
--
-- A foreign floor is meshed alone, with no connected neighbours: connections
-- are the player's neighbourhood, and the map the camera has gone to visit is
-- not standing in it. Both maps are kept live so neither the arena's mesh nor
-- the one waiting to be walked back onto is evicted mid-battle.
local function prefetchArena(state, host)
  if host == state.map then return VoxelScene.prefetch(state) end
  local live = { [host.id] = true, [state.map.id] = true }
  for _, nb in ipairs(state.neighbors or {}) do live[nb.map.id] = true end
  ChunkMesher.setLive(live)
  TerrainAtlas.setLive(live)
  local terrain = ChunkMesher.request(host, false, nil, true)
                  or ChunkMesher.peek(host, true)
  return terrain, {}
end

-- ------- the sun
--
-- Only has to be drawn once per battle: the arena does not move, and neither
-- does the light. So the signature is the map, the arena and the meshes --
-- not the camera, which is the one thing that IS moving and the one thing
-- the sun does not care about.
-- ------- the two mons, hung on their cells
--
-- The billboard texture is the battle screen's own 160x144 pics layer with
-- one side rendered into it (see OverworldBattle.sideTexture), so the quad is
-- that whole frame stood up on the map -- which is what carries every pic
-- effect the engine applies without any of them being reimplemented here.
--
-- Its size follows from one number: a full 7x7-tile mon covers one overworld
-- square, so a canvas pixel is FULL_W / FULL_PIC world pixels and the card is
-- the canvas at that scale. Its placement follows from the anchor the
-- texture reports -- the column the pic was centred on and the row its feet
-- were put on -- which is translated onto the cell before the card is stood
-- up, so a mon of any size in any pose has its feet on the ground.
-- `mirror` flips the card about its own anchor column. Both mons wear their
-- FRONT pic, which is drawn facing out of the screen -- so dropped into the
-- world unaltered the pair stand back to back, both looking the same way past
-- each other. Mirroring the near one turns it to face the far one, which is
-- what a fight looks like; and because it is a flip about the pic's own
-- centre the feet do not move off the tile.
--
-- The player's TRAINER pic is the exception, and it is exempted below. That
-- one is a BACK view -- the player seen from behind, already turned to face
-- up the field -- so it arrives pointing the right way and mirroring it would
-- turn it around to face the camera it is standing in front of.
local function monMatrix(tex, x, groundY, z, mirror)
  local k = BattleBillboard.FULL_W / BattleBillboard.FULL_PIC
  local w = BattleScene.GB_W * k
  local h = BattleScene.GB_H * k
  local ox = -((tex.ax / BattleScene.GB_W) - 0.5) * w
  local oy = -((BattleScene.GB_H - tex.ay) / BattleScene.GB_H) * h
  local yaw = BattleBillboard.yawToward(x, z, Voxel3D.eye)
  local card = Mat4.mul(Mat4.translate(ox, oy, 0), Mat4.scale(w, h, 1))
  if mirror then card = Mat4.mul(Mat4.scale(-1, 1, 1), card) end
  return Mat4.mul(Mat4.mul(Mat4.translate(x, groundY, z), Mat4.rotateY(yaw)),
                  card)
end

-- Every mon that has something to show this frame, as (texture, matrix).
local function monCards(arena, groundY, textures)
  local out = {}
  if not textures then return out end
  for _, side in ipairs({ "enemy", "player" }) do
    local tex = textures[side]
    local cell = (side == "player") and arena.player or arena.enemy
    if tex and tex.canvas and cell then
      local mirror = (side == "player") and not tex.trainer
      out[#out + 1] = { tex = tex.canvas,
                        model = monMatrix(tex, cell[1], groundY, cell[2],
                                          mirror) }
    end
  end
  return out
end

BattleScene.monCards = monCards

-- The sun has to see the mons too, or they stand on the ground without
-- putting anything on it. They are the one thing in this scene that MOVES,
-- so `token` -- a counter the caller bumps whenever a pic could have changed
-- -- goes in the signature; the terrain half of the answer would otherwise
-- keep a stale pass alive and freeze the shadows in whatever pose they were
-- first drawn in.
local function shadowSignature(state, arena, terrain, nbMesh, token)
  local host = arena.map or state.map
  local parts = { "battle", host.id, arena.x, arena.y, arena.shape,
                  tostring(terrain), tostring(token or 0),
                  -- the cycle keeps running through a fight, and an arena lit
                  -- from somewhere new must be re-cast from there
                  math.floor(ShadowMap.KX * 128),
                  math.floor(ShadowMap.KZ * 128) }
  for i = 1, #nbMesh do parts[#parts + 1] = tostring(nbMesh[i]) end
  return table.concat(parts, ",")
end

local function castShadows(state, arena, terrain, nbMesh, cx, cy, vw, vh,
                           atlasFor, cards, token, host, neighbors)
  if not ShadowMap.available() then return end
  local sig = shadowSignature(state, arena, terrain, nbMesh, token)
  if not ShadowMap.stale(sig) then return end
  if not ShadowMap.begin(cx, cy, vw, vh) then return end

  ShadowMap.draw(terrain, atlasFor(host), nil)
  for i, nb in ipairs(neighbors) do
    ShadowMap.draw(nbMesh[i], atlasFor(nb.map), Mat4.translate(nb.ox, 0, nb.oy))
  end
  -- thin cards are snugged toward the sun (ShadowMap.snug) so their shadows
  -- keep contact with their bases instead of starting a bias-width away
  ShadowMap.draw(ChunkMesher.flowers(host), atlasFor(host),
                 ShadowMap.snug(nil))
  for _, nb in ipairs(neighbors) do
    ShadowMap.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                   ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)))
  end

  -- the mons themselves, as the same cards the camera will see. Their alpha
  -- is the silhouette, so what lands on the ground is the shape of the
  -- Pokemon rather than a blob standing in for one.
  for _, card in ipairs(cards or {}) do
    ShadowMap.draw(BattleBillboard.mesh(), card.tex,
                   ShadowMap.snug(card.model))
  end

  ShadowMap.finish(sig)
end

-- The height of the arena floor: the ground the two mons stand on. Both
-- cells are open, so they are normally the same; take the player's, which is
-- the one nearer the camera and therefore the one a mismatch would show up
-- against.
function BattleScene.groundY(map, arena)
  local ok, h = pcall(VoxelScene.groundAt, map,
                      arena.playerCell[1], arena.playerCell[2])
  return (ok and h) or 0
end

-- Where a world point lands in GB frame coordinates under `vp`, or nil when
-- it is behind the camera. This is the function the pins are built on: it
-- takes the window-resolution clip position and divides the letterbox back
-- out of it, so the answer is in the same 160x144 space the battle screen
-- draws its pics in.
function BattleScene.toGB(vp, wx, wy, wz, lx, ly, s, pw, ph)
  local cx = vp[1] * wx + vp[2] * wy + vp[3] * wz + vp[4]
  local cy = vp[5] * wx + vp[6] * wy + vp[7] * wz + vp[8]
  local cw = vp[13] * wx + vp[14] * wy + vp[15] * wz + vp[16]
  if cw <= 1e-6 then return nil end
  -- viewProjection already flipped clip Y into LOVE's Y-down convention
  local px = (cx / cw * 0.5 + 0.5) * pw
  local py = (cy / cw * 0.5 + 0.5) * ph
  return (px - lx) / s, (py - ly) / s
end

-- Render the arena and hand back { canvas, player = {x,y}, enemy = {x,y} },
-- the two marks in GB coordinates -- or nil when there is nothing to draw
-- yet (the terrain mesh is still building, the driver has no depth support).
-- nil is not a failure: the caller simply leaves the battle screen as the
-- engine drew it for that frame.
-- White, for the hit flash, and how far toward it the card goes.
--
-- The shader replaces the card's colour rather than multiplying it, so at
-- full strength this is the sprite turned into a solid white silhouette --
-- which is what the effect is on a flat GB screen and far too much on a
-- sprite standing in a lit world. Held well short of 1, the mon's own
-- shading still reads through the flash: it looks struck rather than
-- deleted.
BattleScene.FLASH_COLOR = { 1, 1, 1 }
BattleScene.FLASH_STRENGTH = 0.5

function BattleScene.render(state, arena, textures, token)
  if not (state and state.map and arena) then return nil end
  if not Voxel3D.available() then return nil end

  -- the floor the fight is staged on: normally the player's own, sometimes
  -- another floor of the same cave or building (see BattleArena)
  local host = arena.map or state.map
  local neighbors = (host == state.map) and (state.neighbors or {}) or {}

  -- the hour's light reaches the arena exactly as it reaches free-roam: the
  -- shared rig follows the clock on an outdoor floor and stays at noon on an
  -- indoor one, and the same tint multiplies the staged shot -- with the
  -- same window glass on whatever buildings stand in the background
  local outdoor = host.def and Map.isOutdoor(host.def) or false
  DayNight.applyRig(outdoor)
  -- a canopy floor (Viridian Forest) fights under the hour's tint too,
  -- with the rig and the void exactly as they were
  Voxel3D.tint = DayNight.tint(outdoor or DayNight.isCanopy(host))
  local GlassMask = V.require("GlassMask")
  Voxel3D.glassMask = outdoor and GlassMask.texture(host.tileset) or nil
  Voxel3D.glassNight = outdoor and DayNight.windowLight() or 0
  -- no glint in the arena: the drift is the shot breathing, not the player
  -- moving, and a shimmer on background windows would fight the mons
  Voxel3D.glassGlint = 0

  -- shares the free-roam mode's request/evict bookkeeping, so a battle warms
  -- exactly the meshes walking around would have and nothing extra
  local terrain, nbMesh = prefetchArena(state, host)
  if not terrain then return nil end

  local lx, ly, s, pw, ph = BattleScene.letterbox()
  if not (pw > 0 and ph > 0 and s > 0) then return nil end

  local palette = paletteFor(state, host)
  local function atlasFor(map)
    return TerrainAtlas.forMap(map, VoxelScene._modeColors(palette, map))
  end

  local groundY = BattleScene.groundY(host, arena)
  local cam, pitch = BattleCam.rig(arena, groundY)
  cam.fov = BattleScene.letterboxFov(cam.fov, ph, s)

  local cx, cy = arena.mid[1], arena.mid[2]
  -- the world extents the sun frustum is fitted to; the camera itself is
  -- framed by cam.fov, so these only have to describe the ground in shot
  local vh = BattleCam.rigFor(arena).frameH * ph / (BattleScene.GB_H * s)
  local vw = vh * pw / ph

  -- the cards need the camera's eye to face it, so the rig has to be live
  -- before they are built; Voxel3D.eye is set by viewProjection, which
  -- beginScene calls -- so a provisional one is taken here for the sun pass
  -- and the real one is rebuilt inside the scene below.
  Voxel3D.camera = cam
  Voxel3D.viewProjection(cx, cy, vw, vh)
  local cards = monCards(arena, groundY, textures)
  Voxel3D.camera = nil
  castShadows(state, arena, terrain, nbMesh, cx, cy, vw, vh, atlasFor,
              cards, token, host, neighbors)

  -- An opaque void either way. Outdoors the camera is low enough that the
  -- horizon is genuinely in frame, so it is sky; indoors it is the dark end
  -- of the same ramp, which is a room's "past the wall". Transparent -- the
  -- free-roam default -- would let the letterbox clear through wherever the
  -- geometry stops.
  local sky = VoxelScene.skyColor(host, 1)
             or VoxelScene.skyShade(INDOOR_SHADE, 1)

  Voxel3D.camera = cam
  -- the sun is turned up for the arena and put back afterwards, so the
  -- free-roam world it shares this module with keeps its own weight -- and
  -- the hour still has the last word: a sunset fades the arena's shadows
  -- out and the moon presses more softly, exactly as it does outside
  local sunWas = Voxel3D.SHADOW_ALPHA
  Voxel3D.SHADOW_ALPHA = BattleScene.SHADOW_ALPHA
                         * DayNight.shadowScale(outdoor)
  -- and the wireframe is ON for a battle whatever the V-GRID row says. The
  -- arena is a staged shot rather than the world being walked through, and
  -- the seams are what make it read as built rather than photographed. Forced
  -- through the override so the player's own row is never written to.
  local gridWas = VoxelGrid.override
  VoxelGrid.override = true
  local out = nil
  local ok, err = pcall(function()
    -- its own canvas slot: this renders at the window's pixel size and the
    -- free-roam pass does too, but the two are alive at different moments
    -- and a shared slot would reallocate on every battle entry and exit
    if not Voxel3D.beginScene(pw, ph, cx, cy, vw, vh, sky, "battle") then
      return
    end
    Voxel3D.draw(terrain, atlasFor(host), nil)
    for i, nb in ipairs(neighbors) do
      Voxel3D.draw(nbMesh[i], atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy))
    end
    -- The mons, standing on their tiles. Depth-tested like everything else,
    -- so a ledge or a tree between the camera and a Pokemon really is in
    -- front of it, and the alpha discard cuts the sprite's own outline out of
    -- the card. A small camera-ward pull keeps a card rooted to the ground
    -- plane from z-fighting the tile it is standing on.
    -- The engine's hit flash is a full-screen white rectangle, which on a
    -- white battle field is a flash and over a world is a whiteout of the
    -- map, the HUD and the text box alike. It is dropped on the way past
    -- (see OverworldBattle) and put back HERE, on the two things it was ever
    -- about: the mons themselves go solid white for those frames.
    local flashing = textures and textures.flash
    if flashing then
      Voxel3D.flatten(BattleScene.FLASH_COLOR, BattleScene.FLASH_STRENGTH)
    end
    -- and no voxel wireframe on the pair. Everything else in this frame is
    -- built a unit per voxel and wears the seams that fall out of that; a
    -- mon's card is one quad wearing the battle screen (see
    -- BattleBillboard), so it is off the grid and has no seams to draw.
    Voxel3D.seams(false)
    -- and no glass either: the cards wear the battle screen, not the
    -- tileset atlas, so the mask's coordinates mean nothing on them
    Voxel3D.glass(false)
    for _, card in ipairs(monCards(arena, groundY, textures)) do
      -- the sun stored this card snugged (castShadows), so its own shadow
      -- lookup must read the same snugged transform -- see ShadowMap.snug
      Voxel3D.draw(BattleBillboard.mesh(), card.tex, card.model,
                   BattleBillboard.PULL, ShadowMap.snug(card.model))
    end
    Voxel3D.glass(true)
    Voxel3D.seams(true)
    if flashing then Voxel3D.flatten(nil) end
    -- grass and flowers ride the same camera-ward pull the free-roam pass
    -- gives them, measured against THIS camera's pitch rather than the
    -- orbit's -- there is no character here for them to overdraw, but the
    -- pull is also what keeps a tuft from z-fighting the floor it stands on
    local pull = VoxelScene.pull(math.max(pitch, 0.05))
    Voxel3D.draw(ChunkMesher.grass(host), atlasFor(host), nil, pull)
    for _, nb in ipairs(neighbors) do
      Voxel3D.draw(ChunkMesher.grass(nb.map), atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy), pull)
    end
    local fpull = math.max(0, pull - 8 * math.sin(math.max(pitch, 0.05)))
    Voxel3D.draw(ChunkMesher.flowers(host), atlasFor(host), nil, fpull,
                 ShadowMap.snug(nil))
    for _, nb in ipairs(neighbors) do
      Voxel3D.draw(ChunkMesher.flowers(nb.map), atlasFor(nb.map),
                   Mat4.translate(nb.ox, 0, nb.oy), fpull,
                   ShadowMap.snug(Mat4.translate(nb.ox, 0, nb.oy)))
    end
    local canvas = Voxel3D.endScene()
    if not canvas then return end

    local vp = Voxel3D.vp
    local pmx, pmy = BattleScene.toGB(vp, arena.player[1], groundY,
                                      arena.player[2], lx, ly, s, pw, ph)
    local emx, emy = BattleScene.toGB(vp, arena.enemy[1], groundY,
                                      arena.enemy[2], lx, ly, s, pw, ph)
    if not (pmx and emx) then return end
    -- How wide one overworld square is on screen where each mon stands, in
    -- GB pixels. This is what the pics are scaled to: a mon covers its own
    -- square and no more, at whatever the drift has done to the distance.
    local half = BattleScene.CELL / 2
    local pl = BattleScene.toGB(vp, arena.player[1] - half, groundY,
                                arena.player[2], lx, ly, s, pw, ph)
    local pr = BattleScene.toGB(vp, arena.player[1] + half, groundY,
                                arena.player[2], lx, ly, s, pw, ph)
    local el = BattleScene.toGB(vp, arena.enemy[1] - half, groundY,
                                arena.enemy[2], lx, ly, s, pw, ph)
    local er = BattleScene.toGB(vp, arena.enemy[1] + half, groundY,
                                arena.enemy[2], lx, ly, s, pw, ph)
    if not (pl and pr and el and er) then return end
    out = {
      canvas = canvas,
      player = { pmx, pmy },
      enemy = { emx, emy },
      playerSpan = math.abs(pr - pl),
      enemySpan = math.abs(er - el),
      -- the letterbox, so the depth-of-field pass can put its sharp band on
      -- the two marks rather than on a fraction of the window
      lx = lx, ly = ly, scale = s, pw = pw, ph = ph,
    }
  end)
  -- the placed camera is ours for exactly this pass; anything else that
  -- renders (the free-roam pipeline, next frame) must find the orbit back
  Voxel3D.camera = nil
  Voxel3D.SHADOW_ALPHA = sunWas
  VoxelGrid.override = gridWas
  if not ok then
    -- endScene never ran, so the canvas is still bound and the shader still
    -- set; put the frame back the way it was found before rethrowing
    pcall(love.graphics.setShader)
    pcall(love.graphics.setDepthMode)
    pcall(love.graphics.setCanvas)
    error(err, 0)
  end
  return out
end

return BattleScene
