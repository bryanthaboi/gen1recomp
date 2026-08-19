-- Overworld character sprites.  The vanilla 12-tile sheet (16x96 PNG) holds
-- 6 16x16 frames: stand down/up/left, walk down/up/left
-- (data/sprites/facings.asm).  Mod records may opt into another frame size
-- and anchor; the defaults below preserve the original grounded placement.
-- Right-facing frames are horizontal flips of the left frames.

local Assets = require("src.render.Assets")
local GbcPalette = require("src.render.GbcPalette")
local PaletteFX = require("src.render.PaletteFX")

local SpriteRenderer = {}
SpriteRenderer.__index = SpriteRenderer

local imageCache = {}

local function getImage(path)
  if not imageCache[path] then
    imageCache[path] = Assets.image(path)
  end
  return imageCache[path]
end

-- Overworld sprite OBJ-palette recolor, baked into an ImageData like
-- BattleState's mon-pic palette bake (src/battle/BattleState.lua getImage):
-- CPU-remap the 4 DMG shades to the resolved OBP colors, cached per
-- (image path, group).  Every colour mode goes through it now (#301): RED++
-- resolves real per-sprite colours (color/sprites.asm ColorOverworldSprite),
-- OG RED the one boot-ROM object palette, and everything else the plain
-- rOBP0 = $D0 shade lift (PaletteFX.dmgObj) that leaves the sprite in DMG
-- shades for the zone shader to colour.
--
-- Sprite sheets carry no real alpha (every pixel, including the
-- background, is opaque -- confirmed by sampling the extracted PNGs): the
-- "transparent" look in every other draw path is a coincidence of the
-- whole-canvas shade-remap shader, where shade 0 (white) happens to map to
-- a similarly light color in whatever terrain zone the sprite stands over.
-- That coincidence breaks once terrain is colored per-tile instead of one
-- flat color per map (different tiles can have very different color-0s),
-- so shade 0 is keyed to alpha 0 here explicitly -- matching real GBC OBJ
-- hardware, where sprite palette index 0 is unconditionally transparent
-- (same rule TileRenderer's getColor0KeyShader documents for tall grass).
local obpCache = {}

local function getObpImage(path, colors, group)
  local key = path .. "#obp" .. group
  if not obpCache[key] then
    local img
    if love.image and love.image.newImageData then
      local id = Assets.imageData(path)
      id:mapPixel(function(_, _, r, g, b, a)
        if a == 0 then return r, g, b, a end
        if r > 0.83 then return r, g, b, 0 end -- OBJ color 0: always transparent
        local col = r > 0.5 and colors[2] or r > 0.17 and colors[3] or colors[4]
        return col[1] / 255, col[2] / 255, col[3] / 255, a
      end)
      img = love.graphics.newImage(id)
    else
      img = getImage(path) -- headless stub: no pixel access
    end
    obpCache[key] = img
  end
  return obpCache[key]
end

SpriteRenderer.obpImage = getObpImage

-- hot reload drops the sheets; live instances hold their own image, so
-- the world rebuilds them (MapLoader.invalidateAll) rather than this
function SpriteRenderer.invalidate()
  imageCache = {}
  obpCache = {}
end

Assets.register(SpriteRenderer.invalidate)

-- exported: a render pipeline's own sprite geometry picks frames by the
-- same tables, so a 3D pose can never drift from the 2D one
local STAND = { down = 0, up = 1, left = 2, right = 2 }
local WALK = { down = 3, up = 4, left = 5, right = 5 }
SpriteRenderer.STAND = STAND
SpriteRenderer.WALK = WALK

-- Sprite records are anchored at the point where the actor stands in the
-- world.  In the vanilla renderer that point is the bottom-center of a
-- 16x16 frame: the frame starts at (px, py - 4), so the ground point is
-- (px + 8, py + 12).  Custom anchors are measured from the frame's top-left
-- in sheet pixels and may be fractional for a sub-pixel art style.
local DEFAULT_FRAME_WIDTH = 16
local DEFAULT_FRAME_HEIGHT = 16
local DEFAULT_ANCHOR_X = 8
local DEFAULT_ANCHOR_Y = 16
local WORLD_ANCHOR_X = 8
local WORLD_ANCHOR_Y = 12
SpriteRenderer.DEFAULT_FRAME_WIDTH = DEFAULT_FRAME_WIDTH
SpriteRenderer.DEFAULT_FRAME_HEIGHT = DEFAULT_FRAME_HEIGHT
SpriteRenderer.DEFAULT_ANCHOR_X = DEFAULT_ANCHOR_X
SpriteRenderer.DEFAULT_ANCHOR_Y = DEFAULT_ANCHOR_Y

local function finiteNumber(value)
  if type(value) ~= "number" or value ~= value
     or value == math.huge or value == -math.huge then
    return nil
  end
  return value
end

local function positiveInteger(value, fallback)
  value = finiteNumber(value)
  if value and value >= 1 then return math.floor(value) end
  return fallback
end

local function numberOr(value, fallback)
  return finiteNumber(value) or fallback
end

local function pose(self, facing, walkPhase, stepFlip)
  if self.frameCount <= 1 then return 0, false end
  local frame = (self.def.walker and walkPhase == 1)
                and WALK[facing] or STAND[facing]
  frame = frame or 0
  -- Preserve the old fallback for a short custom sheet whose pose table
  -- names a frame it does not provide.
  if not self.frames[frame] then frame = 0 end
  local flip = false
  if facing == "right" then
    flip = true
  elseif (facing == "down" or facing == "up")
         and walkPhase == 1 and stepFlip then
    flip = true
  end
  return frame, flip
end

-- seed: any stable per-instance value (e.g. an NPC's `id`) used to resolve
-- RED++'s per-instance "random" OBP sentinel (PaletteFX.spriteObp)
function SpriteRenderer.new(spriteDef, seed)
  local self = setmetatable({}, SpriteRenderer)
  self.def = spriteDef
  self.seed = seed
  self.image = getImage(spriteDef.image)
  self.frameCount = positiveInteger(spriteDef.frames, 1)
  self.frameWidth = positiveInteger(spriteDef.frameWidth, DEFAULT_FRAME_WIDTH)
  self.frameHeight = positiveInteger(spriteDef.frameHeight, DEFAULT_FRAME_HEIGHT)
  self.anchorX = numberOr(spriteDef.anchorX, self.frameWidth / 2)
  self.anchorY = numberOr(spriteDef.anchorY, self.frameHeight)
  local iw, ih = self.image:getDimensions()
  self.frames = {}
  for f = 0, self.frameCount - 1 do
    self.frames[f] = love.graphics.newQuad(0, f * self.frameHeight,
                                           self.frameWidth, self.frameHeight,
                                           iw, ih)
  end
  return self
end

-- Return the sheet rectangle and top-left-relative anchor for a frame.  The
-- result is a fresh table so a custom render pipeline may annotate it without
-- changing the renderer's shared definition.
function SpriteRenderer:getFrameGeometry(frame)
  frame = math.floor(finiteNumber(frame) or 0)
  if frame < 0 then frame = 0 end
  if frame >= self.frameCount then frame = self.frameCount - 1 end
  return {
    frame = frame,
    x = 0,
    y = frame * self.frameHeight,
    width = self.frameWidth,
    height = self.frameHeight,
    anchorX = self.anchorX,
    anchorY = self.anchorY,
    quad = self.frames[frame],
  }
end

-- Return the frame geometry selected by the ordinary 2D pose rules, plus the
-- horizontal mirror state that :draw applies.  This is the supported hook for
-- custom render pipelines that need to draw actors with the same pose/flip.
function SpriteRenderer:getPoseGeometry(facing, walkPhase, stepFlip)
  local frame, flip = pose(self, facing, walkPhase, stepFlip)
  local geometry = self:getFrameGeometry(frame)
  geometry.facing = facing
  geometry.walkPhase = walkPhase
  geometry.stepFlip = stepFlip
  geometry.mirror = flip
  return geometry
end

-- Screen-space top-left for the actor's current world anchor.  World-facing
-- effects such as fishing can use this instead of assuming a 16x16 frame.
function SpriteRenderer:getScreenOrigin(px, py, camX, camY)
  local baseX = math.floor(px - camX) + WORLD_ANCHOR_X
  local baseY = math.floor(py - camY) + WORLD_ANCHOR_Y
  return math.floor(baseX - self.anchorX),
         math.floor(baseY - self.anchorY)
end

-- The image this sprite would draw from right now: the plain sheet, or the
-- OBP-recolored bake of it.  Exposed so a render pipeline can texture its
-- own geometry from the very same image -- the geometry carries sheet pixel
-- coordinates rather than baked colors, so sharing this one resolver is
-- what makes palette modes and sprite-replacing mods apply to 2D and 3D
-- alike.
--
-- Deliberately free of draw's bookkeeping: markTrueColor and
-- markSpriteRedraw exist to patch up the screen-space zone shader, and a
-- pipeline that renders into its own canvas never runs through it.  For the
-- same reason the OG-RED bake is returned unconditionally here rather than
-- only during a redraw pass -- there is no later pass to restore it.
-- Gen 2 hands its OBJ palette over explicitly.  Gold is a CGB-native game:
-- every OW sprite already has a real 4-color OBJ palette (PAL_OW_* crossed
-- with the time of day, engine/gfx/color.asm MapObjectPals), so there is
-- nothing for the PaletteFX mode ladder below to infer -- src/world/gen2 just
-- says what the colors are.  It rides the same getObpImage bake as RED++,
-- which is also what keys OBJ color 0 to alpha; the sheets carry no real
-- alpha of their own, so a raw blit would put a white box behind every
-- character.
--
-- `group` must be distinct per palette or the bake cache collides -- callers
-- pass something like "gen2:NITE:1".
function SpriteRenderer:setObjPalette(colors, group)
  self.objColors = colors
  self.objGroup = group or "gen2"
end

-- The Gen 2 OBJ palette with the COLOR option applied.  Resolved on the way
-- to the bake rather than where the world hands the colours over: the option
-- can change between two frames of a standing map, and applyPalettes only
-- runs on map entry and once a second.  The mode joins the cache group
-- because the bake is per-palette -- without it, DMG would keep serving the
-- colour bake it made first.
function SpriteRenderer:gen2Obp()
  return GbcPalette.resolve(self.objColors),
    self.objGroup .. "|" .. tostring(GbcPalette.mode)
end

local function liveTrueColor(def)
  return def and def.trueColor and PaletteFX.honorsTrueColor()
end

function SpriteRenderer:resolveImage()
  if liveTrueColor(self.def) then return self.image end
  if self.objColors then
    return getObpImage(self.def.image, self:gen2Obp())
  end
  if PaletteFX.usesGbcPack() then
    local colors, group = PaletteFX.spriteObp(self.def, self.seed)
    if colors then return getObpImage(self.def.image, colors, group) end
  elseif PaletteFX.usesSpriteObp() then
    -- OG boot-ROM OBJ palette: green on Red, pink on Blue (PaletteFX.ogObj
    -- returns colors + a version-distinct cache group so the two never
    -- collide in obpCache) -- see issue #155
    return getObpImage(self.def.image, PaletteFX.ogObj())
  end
  -- Every other mode (SGB and the mono/inverted novelties) leaves the sprite
  -- in DMG shades so the zone shader colors it out of the map's own palette,
  -- but still bakes rOBP0 = $D0 in and keys OBJ color 0 to alpha -- the two
  -- things a raw sheet blit cannot express (#301, #150).  The sheets carry no
  -- real alpha (see getObpImage), so returning self.image here would put an
  -- opaque white box behind every character a pipeline textures.
  return getObpImage(self.def.image, PaletteFX.dmgObj())
end

-- facing: down/up/left/right; walkPhase: 0 stand, 1 walk; flip: alternate
-- steps mirror the walk frame for up/down (GB uses OAM flip for this).
local function blitFrame(image, quad, x, y, flip, redraw, frameWidth)
  frameWidth = frameWidth or DEFAULT_FRAME_WIDTH
  if flip then
    love.graphics.draw(image, quad, x + frameWidth, y, 0, -1, 1)
    if redraw then
      PaletteFX.markSpriteRedraw(image, quad, x + frameWidth, y, -1)
    end
  else
    love.graphics.draw(image, quad, x, y)
    if redraw then PaletteFX.markSpriteRedraw(image, quad, x, y, 1) end
  end
end

-- topHalf blits everything above the bottom 8-pixel tile row: FishingAnim
-- overwrites that row of the standing frames with fishing pose art, which the
-- caller then draws itself through :drawTile (Player:draw, #384).  Vanilla
-- frames therefore still draw 8 rows, while taller frames keep their larger
-- body and reserve only the overlay row.
-- `forceFlip` is the caller asking for the X-flipped copy of the frame it
-- already picked, for the facings whose OAM rows are the mirror of another
-- row's: FacingWeirdTree3 is FacingWeirdTree1's four tiles with the columns
-- swapped and OAM_XFLIP on each (data/sprites/facings.asm:192-197).  Optional
-- and trailing, so every existing call site is unchanged.
function SpriteRenderer:draw(px, py, camX, camY, facing, walkPhase, stepFlip,
    topHalf, forceFlip, frameOverride)
  local x, y = self:getScreenOrigin(px, py, camX, camY)
  local image = self.image
  local redraw = false
  -- True-color sheets bypass every palette bake; the screen-space exemption
  -- is recorded below once the final frame/height is known.
  if liveTrueColor(self.def) then
    image = self.image
  elseif self.objColors then
    -- Gen 2: the palette came from the caller (setObjPalette).  Like RED++
    -- this bakes to a true-color, real-alpha image and there is no BG zone
    -- shader over the Gen 2 world to exempt it from.
    image = getObpImage(self.def.image, self:gen2Obp())
  elseif PaletteFX.usesGbcPack() then
    -- RED++: the world canvas is already true-color (TileRenderer bakes
    -- terrain, this bakes the sprite) and the world pass runs unshaded
    -- (OverworldState.sgbWorldZones), so this draws like any normal sprite
    -- -- opaque character pixels over a real-alpha-transparent background,
    -- no trueColor rect needed (there is no shader left to exempt it from).
    local colors, group = PaletteFX.spriteObp(self.def, self.seed)
    if colors then
      image = getObpImage(self.def.image, colors, group)
    end
  elseif PaletteFX.usesSpriteObp() and PaletteFX.spriteRedrawPassActive() then
    -- OG RED (GBC boot-ROM look): every OBJ wears the one global object
    -- palette -- green over Red's red background, pink over Blue's blue
    -- background (PaletteFX.ogObj, #155).  The BG zone shader still runs over
    -- the world canvas, so the baked sprite is queued for a post-zone redraw
    -- (PaletteFX.markSpriteRedraw) that restores its object-colored pixels on
    -- top.
    image = getObpImage(self.def.image, PaletteFX.ogObj())
    redraw = true
  else
    -- SGB and the mono/inverted modes (and OG RED's tilt upright pass, which
    -- has no post-zone replay to restore a bake): the sprite stays in DMG
    -- shades -- rOBP0 = $D0 baked in, OBJ color 0 keyed to alpha -- and the
    -- whole-canvas zone shader colors it with the map's palette.  That is the
    -- only thing the Super Game Boy can do to an OBJ, since pokered never
    -- sends the OBJ_TRN packet that would give sprites palettes of their own
    -- (data/sgb/sgb_packets.asm defines ATTR_BLK / PAL_SET / PAL_TRN /
    -- MLT_REQ / CHR_TRN / PCT_TRN and nothing else).  No redraw is queued:
    -- being colorized by the zone IS the point (#301).
    image = getObpImage(self.def.image, PaletteFX.dmgObj())
  end
  -- Single-frame sprites (item balls, fossils...) have one fixed pose;
  -- still 3-frame sprites turn to face (the nurse at her machine,
  -- facePlayer on STAY NPCs) but never show walk frames.
  local frame, flip = pose(self, facing, walkPhase, stepFlip)
  if frameOverride and self.frames[frameOverride] then
    frame, flip = frameOverride, false
  end
  if forceFlip then flip = true end
  local quad = self.frames[frame]
  local drawHeight = self.frameHeight
  if topHalf and self.frameCount > 1 then
    self.halfFrames = self.halfFrames or {}
    if not self.halfFrames[frame] then
      local iw, ih = self.image:getDimensions()
      local topHeight = math.max(1, self.frameHeight - math.min(8, self.frameHeight))
      self.halfFrames[frame] = love.graphics.newQuad(
        0, frame * self.frameHeight, self.frameWidth, topHeight, iw, ih)
    end
    quad = self.halfFrames[frame]
    drawHeight = math.max(1, self.frameHeight - math.min(8, self.frameHeight))
  end
  -- Full-color art claims exactly the portion of the frame that was drawn.
  if liveTrueColor(self.def) then
    PaletteFX.markTrueColor(x, y, self.frameWidth, drawHeight)
  end
  blitFrame(image, quad, x, y, flip, redraw, self.frameWidth)
end

-- Blit a loose 16-wide fx tile at screen (x, y) wearing THIS sprite's OBJ
-- palette, mirroring the mode branches in :draw above.  The fishing pose row
-- overwrites the sheet's own tiles in VRAM in the original, so it has to be
-- recolored and OG-RED-redrawn exactly like the sheet rather than blitted as
-- raw DMG shades (#384).
function SpriteRenderer:drawTile(path, x, y, flip, quad)
  local image, redraw = getImage(path), false
  if liveTrueColor(self.def) then
    PaletteFX.markTrueColor(x, y, 16, 8)
  elseif self.objColors then
    image = getObpImage(path, self:gen2Obp())
  elseif PaletteFX.usesGbcPack() then
    local colors, group = PaletteFX.spriteObp(self.def, self.seed)
    if colors then image = getObpImage(path, colors, group) end
  elseif PaletteFX.usesSpriteObp() and PaletteFX.spriteRedrawPassActive() then
    image, redraw = getObpImage(path, PaletteFX.ogObj()), true
  else
    image = getObpImage(path, PaletteFX.dmgObj())
  end
  local iw, ih = image:getDimensions()
  local q = quad
  if not q then
    self.tileQuads = self.tileQuads or {}
    self.tileQuads[path] = self.tileQuads[path]
                           or love.graphics.newQuad(0, 0, iw, ih, iw, ih)
    q = self.tileQuads[path]
  end
  local qw = iw
  if q then
    if q.getViewport then
      local _, _, w = q:getViewport()
      qw = w
    elseif q.w then
      qw = q.w
    end
  end
  blitFrame(image, q, x, y, flip, redraw, qw)
end

return SpriteRenderer
