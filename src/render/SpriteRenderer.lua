-- Overworld character sprites.  A 12-tile sheet (16x96 PNG) holds 6 16x16
-- frames: stand down/up/left, walk down/up/left (data/sprites/facings.asm).
-- Right-facing frames are horizontal flips of the left frames.
-- Sprites draw 4px above their cell, like the GB engine.

local Assets = require("src.render.Assets")
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

-- seed: any stable per-instance value (e.g. an NPC's `id`) used to resolve
-- RED++'s per-instance "random" OBP sentinel (PaletteFX.spriteObp)
function SpriteRenderer.new(spriteDef, seed)
  local self = setmetatable({}, SpriteRenderer)
  self.def = spriteDef
  self.seed = seed
  self.image = getImage(spriteDef.image)
  local iw, ih = self.image:getDimensions()
  self.frames = {}
  for f = 0, spriteDef.frames - 1 do
    self.frames[f] = love.graphics.newQuad(0, f * 16, 16, 16, iw, ih)
  end
  return self
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
function SpriteRenderer:resolveImage()
  if self.def.trueColor then return self.image end
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
local function blitFrame(image, quad, x, y, flip, redraw)
  if flip then
    love.graphics.draw(image, quad, x + 16, y, 0, -1, 1)
    if redraw then PaletteFX.markSpriteRedraw(image, quad, x + 16, y, -1) end
  else
    love.graphics.draw(image, quad, x, y)
    if redraw then PaletteFX.markSpriteRedraw(image, quad, x, y, 1) end
  end
end

-- topHalf blits only the upper 8 rows of the frame: FishingAnim overwrites the
-- bottom tile row of the standing frames with the fishing pose art, which the
-- caller then draws itself through :drawTile (Player:draw, #384)
function SpriteRenderer:draw(px, py, camX, camY, facing, walkPhase, stepFlip, topHalf)
  local x = math.floor(px - camX)
  local y = math.floor(py - camY) - 4
  local image = self.image
  local redraw = false
  -- full-color art claims its 16x16 cell out of the shade-remap pass
  if self.def.trueColor then
    PaletteFX.markTrueColor(x, y, 16, 16)
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
  -- single-frame sprites (item balls, fossils...) have one fixed pose;
  -- still 3-frame sprites turn to face (the nurse at her machine,
  -- facePlayer on STAY NPCs) but never show walk frames
  if self.def.frames <= 1 then
    blitFrame(image, self.frames[0], x, y, false, redraw)
    return
  end
  local frame = (self.def.walker and walkPhase == 1)
                and WALK[facing] or STAND[facing]
  local flip = false
  if facing == "right" then
    flip = true
  elseif (facing == "down" or facing == "up") and walkPhase == 1 and stepFlip then
    flip = true
  end
  local quad = self.frames[frame] or self.frames[0]
  if topHalf then
    self.halfFrames = self.halfFrames or {}
    if not self.halfFrames[frame] then
      local iw, ih = self.image:getDimensions()
      self.halfFrames[frame] = love.graphics.newQuad(0, frame * 16, 16, 8, iw, ih)
    end
    quad = self.halfFrames[frame]
  end
  blitFrame(image, quad, x, y, flip, redraw)
end

-- Blit a loose 16-wide fx tile at screen (x, y) wearing THIS sprite's OBJ
-- palette, mirroring the mode branches in :draw above.  The fishing pose row
-- overwrites the sheet's own tiles in VRAM in the original, so it has to be
-- recolored and OG-RED-redrawn exactly like the sheet rather than blitted as
-- raw DMG shades (#384).
function SpriteRenderer:drawTile(path, x, y, flip)
  local image, redraw = getImage(path), false
  if self.def.trueColor then
    PaletteFX.markTrueColor(x, y, 16, 8)
  elseif PaletteFX.usesGbcPack() then
    local colors, group = PaletteFX.spriteObp(self.def, self.seed)
    if colors then image = getObpImage(path, colors, group) end
  elseif PaletteFX.usesSpriteObp() and PaletteFX.spriteRedrawPassActive() then
    image, redraw = getObpImage(path, PaletteFX.ogObj()), true
  else
    image = getObpImage(path, PaletteFX.dmgObj())
  end
  local iw, ih = image:getDimensions()
  self.tileQuads = self.tileQuads or {}
  self.tileQuads[path] = self.tileQuads[path]
                         or love.graphics.newQuad(0, 0, iw, ih, iw, ih)
  blitFrame(image, self.tileQuads[path], x, y, flip, redraw)
end

return SpriteRenderer
