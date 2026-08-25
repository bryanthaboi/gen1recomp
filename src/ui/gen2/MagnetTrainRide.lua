-- The Magnet Train ride, drawn (pokegold engine/events/magnet_train.asm).
--
-- src/core/gen2/MagnetTrain.lua is the routine: the jumptable, the three SCX
-- bands and the player's frameset, all love-free.  This is the presentation,
-- and it is the cart's presentation rather than an approximation of it:
--
--   * MagnetTrain_LoadGFX_PlayMusic loads NO background tiles.  The train, the
--     bushes and the window are all drawn out of whatever the map's tileset
--     already had in VRAM, which for both stations is TILESET_TRAIN_STATION --
--     so the sheet this screen bakes from is the same one the overworld was
--     drawing a frame earlier.
--   * The two tilemaps behind DrawMagnetTrain (MagnetTrainBGTiles, a 2x18
--     vertical strip repeated across all 32 columns, and MagnetTrainTilemap,
--     the 20x4 train laid over rows 6-9) come from the extracted cache at
--     data.gen2Field.magnetTrain.  A cache built before the extractor
--     learned to follow them has neither, and then the ride runs with a
--     blank screen rather than with invented art.
--   * The background is baked into a 256x144 canvas once, because the only
--     thing that changes per frame is the per-band SCX.
--   * SetMagnetTrainPals gives the four bush rows and the four bottom rows
--     PAL_BG_GREEN, the ten train rows PAL_BG_GRAY and the six window tiles
--     PAL_BG_YELLOW, out of a TOWN palette set at the current time of day
--     (the routine pushes wEnvironment, forces TOWN, and pops it back).
--
-- Two hardware details from the cart are faithfully reproduced:
-- 1. Viewport wrapping: the 256x144 background scrolls in 3 LY override bands,
--    wrapped strictly within the 160x144 GB screen so pixels do not bleed into
--    the widescreen surround.
-- 2. OAM Priority (OAM_PRIO): the four player OBJs sit behind background
--    colours 1-3 and only show through the window's colour 0.  This is drawn
--    via a base background pass, the player sprite, and an overlay pass where
--    shade 0 is transparent and solid train tiles mask the sprite.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local FieldMoves = require("src.world.gen2.FieldMoves")
local GbcPalette = require("src.render.GbcPalette")
local MagnetTrain = require("src.core.gen2.MagnetTrain")
local Music = require("src.core.Music")
local Palettes = require("src.world.gen2.Palettes")
local Sound = require("src.core.Sound")

local MagnetTrainRide = {}
MagnetTrainRide.__index = MagnetTrainRide
MagnetTrainRide.isOpaque = true

local SCREEN_W, SCREEN_H = 160, 144
local BG_W = 256           -- TILEMAP_WIDTH * 8
local TILES_PER_ROW = 16   -- every 2bpp sheet the importer writes
local BLACK = { 0, 0, 0 }

-- Overlay shader for OAM_PRIO: shade 0 is transparent; shades 1-3 are solid
-- palette colors, masking any sprites beneath solid background tiles.
local OVERLAY_SHADER_SOURCE = [[
extern vec3 pal0;
extern vec3 pal1;
extern vec3 pal2;
extern vec3 pal3;

vec4 effect(vec4 tint, Image tex, vec2 uv, vec2 screen) {
  vec4 px = Texel(tex, uv);
  float shade = floor((1.0 - px.r) * 3.0 + 0.5);
  vec3 rgb = pal0;
  if (shade > 2.5) {
    rgb = pal3;
  } else if (shade > 1.5) {
    rgb = pal2;
  } else if (shade > 0.5) {
    rgb = pal1;
  }
  float alpha = shade < 0.5 ? 0.0 : px.a;
  return vec4(rgb, alpha) * tint;
}
]]

function MagnetTrainRide:wantsFillScale() return true end

-- opts: toGoldenrod (the wScriptVar the officer's script set), onDone()
function MagnetTrainRide.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, MagnetTrainRide)
  self.game = game
  self.data = game and game.data
  self.onDone = opts.onDone
  self.finished = false
  local save = opts.save or (game and game.save)
  self.gender = save and save.player and save.player.gender or nil

  local field = self.data and self.data.gen2Field
  local gfx = field and field.magnetTrain
  self.ride = MagnetTrain.new({
    toGoldenrod = opts.toGoldenrod,
    bgTiles = gfx and gfx.bgTiles,
    fgTilemap = gfx and gfx.tilemap,
  })

  self.tileset = self.data and self.data.gen2Tilesets
    and self.data.gen2Tilesets.TILESET_TRAIN_STATION
  self.palettes = self:bgPalettes()
  self.spriteSheet = self:playerSheet()

  -- PlayMusic2 MUSIC_MAGNET_TRAIN, the last thing the GFX load does.
  local songs = self.data and self.data.audio and self.data.audio.songs
  if songs and songs.Music_MagnetTrain then
    Music.stop()
    Music.play(self.data, "Music_MagnetTrain", true, { reason = "magnettrain" })
  end
  return self
end

-- GetSGBLayout with wEnvironment forced to TOWN and wTimeOfDayPal taken from
-- the real clock, so the bushes are the colour the outside world is right now
-- even though both stations are INDOOR maps.
function MagnetTrainRide:bgPalettes()
  local data = self.data
  local palettes = data and data.gen2Palettes
  if not palettes then return nil end
  return Palettes.bgSet(palettes, { environment = "TOWN" },
    Palettes.clockDaytime())
end

function MagnetTrainRide:palette(slot)
  local set = self.palettes
  local colors = set and (set[slot] or set[1])
  return colors
end

--------------------------------------------------------------------------
-- Sheets & Shaders
--------------------------------------------------------------------------

local function sheetFor(path)
  if not path then return nil end
  -- `and` would truncate pcall's second return, so this cannot fold into one
  -- expression.
  local ok, image = pcall(Assets.image, path)
  if not (ok and image) then return nil end
  image:setFilter("nearest", "nearest")
  local width, height = image:getDimensions()
  local quads = {}
  for tile = 0, math.floor(width / 8) * math.floor(height / 8) - 1 do
    quads[tile] = love.graphics.newQuad(
      tile % TILES_PER_ROW * 8, math.floor(tile / TILES_PER_ROW) * 8,
      8, 8, width, height)
  end
  return { image = image, quads = quads, width = width, height = height }
end

function MagnetTrainRide:tileSheet()
  if self.sheet == nil then
    self.sheet = sheetFor(self.tileset and self.tileset.image) or false
  end
  return self.sheet or nil
end

-- The player's own overworld sheet: six 16x16 frames stacked vertically, of
-- which MagnetTrain.SHEET_FRAME names the two the cutscene requests.  Quads
-- are cut per 8x8 sub-tile rather than by the sheet's 16-pixel width, because
-- the OAM data addresses the four tiles of a frame individually.
function MagnetTrainRide:playerSheet()
  local def = self:playerSpriteDef()
  local path = def and def.image
  if not path then return nil end
  local ok, image = pcall(Assets.image, path)
  if not (ok and image) then return nil end
  image:setFilter("nearest", "nearest")
  return { image = image }
end

-- The quad for one vtile of the two loaded blocks.  A 2x2 frame is stored
-- top-left, top-right, bottom-left, bottom-right, which is the order
-- .OAMData_MagnetTrainRed's four `dbsprite` rows walk.
function MagnetTrainRide:playerQuad(vtile)
  local sheet = self.spriteSheet
  if not sheet then return nil end
  local frame = MagnetTrain.SHEET_FRAME[vtile - (vtile % 4)]
  if not frame then return nil end
  self.playerQuads = self.playerQuads or {}
  local quad = self.playerQuads[vtile]
  if not quad then
    local sub = vtile % 4
    local w, h = sheet.image:getDimensions()
    quad = love.graphics.newQuad(
      (sub % 2) * 8, frame * 16 + math.floor(sub / 2) * 8, 8, 8, w, h)
    self.playerQuads[vtile] = quad
  end
  return quad
end

function MagnetTrainRide:overlayShader()
  if self.ovShader ~= nil then return self.ovShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then
    self.ovShader = false
    return nil
  end
  local ok, result = pcall(love.graphics.newShader, OVERLAY_SHADER_SOURCE)
  self.ovShader = ok and result or false
  return self.ovShader or nil
end

local function palChannel(colors, index)
  local c = colors and colors[index]
  if not c then return 0, 0, 0 end
  return (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255
end

function MagnetTrainRide:useOverlayShader(colors)
  local sh = self:overlayShader()
  if not sh then return false end
  local resolved = GbcPalette.resolve(colors)
  for i = 0, 3 do
    local u = "pal" .. i
    if sh:hasUniform(u) then
      local r, g, b = palChannel(resolved, i + 1)
      sh:send(u, { r, g, b })
    end
  end
  love.graphics.setShader(sh)
  return true
end


--------------------------------------------------------------------------
-- The baked backgrounds (Base + OAM_PRIO Overlay)
--------------------------------------------------------------------------

-- DrawMagnetTrain plus SetMagnetTrainPals, rendered once into 256x144 canvases.
-- Base canvas contains the full opaque background; Overlay canvas contains
-- solid shades 1-3 with shade 0 transparent for OAM_PRIO window masking.
function MagnetTrainRide:backgrounds()
  if self.bgCanvas ~= nil then
    return self.bgCanvas or nil, self.bgOverlayCanvas or nil
  end
  self.bgCanvas = false
  self.bgOverlayCanvas = false
  local rows = self.ride:tilemap()
  local sheet = self:tileSheet()
  if not (rows and sheet) then return nil, nil end

  local ok1, baseCanvas = pcall(love.graphics.newCanvas, BG_W, SCREEN_H)
  if not ok1 then return nil, nil end
  baseCanvas:setFilter("nearest", "nearest")

  local ok2, overlayCanvas = pcall(love.graphics.newCanvas, BG_W, SCREEN_H)
  if ok2 and overlayCanvas then
    overlayCanvas:setFilter("nearest", "nearest")
  else
    overlayCanvas = nil
  end

  local groups = {}
  for row = 1, #rows do
    for col = 1, #rows[row] do
      local slot = MagnetTrain.paletteSlot(col - 1, row - 1)
      groups[slot] = groups[slot] or {}
      local list = groups[slot]
      list[#list + 1] = { rows[row][col], (col - 1) * 8, (row - 1) * 8 }
    end
  end

  local G = love.graphics
  local previous = G.getCanvas()
  G.push("all")
  G.origin()
  G.setScissor()

  -- 1. Base background canvas (shades 0-3)
  G.setCanvas(baseCanvas)
  G.clear(0, 0, 0, 1)
  G.setColor(1, 1, 1, 1)
  local shader = GbcPalette.available()
  for slot, list in pairs(groups) do
    local colors = self:palette(slot)
    if shader and colors then GbcPalette.use(colors) end
    for _, cell in ipairs(list) do
      local quad = sheet.quads[cell[1]]
      if quad then G.draw(sheet.image, quad, cell[2], cell[3]) end
    end
  end
  if shader then GbcPalette.clear() end

  -- 2. Overlay canvas for OAM_PRIO (shades 1-3 solid, shade 0 transparent)
  if overlayCanvas then
    G.setCanvas(overlayCanvas)
    G.clear(0, 0, 0, 0)
    G.setColor(1, 1, 1, 1)
    local ovShader = self:overlayShader()
    for slot, list in pairs(groups) do
      local colors = self:palette(slot)
      if ovShader and colors then self:useOverlayShader(colors) end
      for _, cell in ipairs(list) do
        local quad = sheet.quads[cell[1]]
        if quad then G.draw(sheet.image, quad, cell[2], cell[3]) end
      end
    end
    if ovShader then G.setShader() end
  end

  G.setCanvas(previous)
  G.pop()

  self.bgCanvas = baseCanvas
  self.bgOverlayCanvas = overlayCanvas
  return baseCanvas, overlayCanvas
end

function MagnetTrainRide:background()
  local base = self:backgrounds()
  return base
end

--------------------------------------------------------------------------
-- Frame
--------------------------------------------------------------------------

function MagnetTrainRide:playSfx(name)
  local audio = self.data and self.data.audio
  local sfx = audio and audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

function MagnetTrainRide:finish()
  if self.finished then return end
  self.finished = true
  if self.onDone then self.onDone() end
end

function MagnetTrainRide:update(_dt)
  if self.finished then return end
  local sfx = self.ride:update()
  if sfx then self:playSfx(sfx) end
  if self.ride:done() then
    -- MagnetTrain's .done tears the screen back down and returns to the
    -- script, which then runs `warpcheck` and `newloadmap MAPSETUP_TRAIN`.
    self:finish()
  end
end

-- Draws the 3 LY override bands strictly wrapped inside the 160px GB screen.
function MagnetTrainRide:drawBands(canvas)
  if not canvas then return end
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  self.bandQuad = self.bandQuad
    or love.graphics.newQuad(0, 0, SCREEN_W, 1, BG_W, SCREEN_H)
  for _, band in ipairs(self.ride:bands()) do
    local top, bottom, scx = band[1], band[2], band[3] % BG_W
    local height = bottom - top + 1
    local w1 = math.min(SCREEN_W, BG_W - scx)
    self.bandQuad:setViewport(scx, top, w1, height, BG_W, SCREEN_H)
    G.draw(canvas, self.bandQuad, 0, top)
    if w1 < SCREEN_W then
      local w2 = SCREEN_W - w1
      self.bandQuad:setViewport(0, top, w2, height, BG_W, SCREEN_H)
      G.draw(canvas, self.bandQuad, w1, top)
    end
  end
end

-- GetPlayerIcon's sheet, which .InitPlayerSpriteAnim pairs with
-- SPRITE_ANIM_OBJ_MAGNET_TRAIN_RED or _BLUE
-- (../pokecrystal/engine/events/magnet_train.asm:131-141, :291-305).
function MagnetTrainRide:playerSpriteDef()
  local sprites = self.data and self.data.gen2Sprites
  if not sprites then return nil end
  return sprites[FieldMoves.playerSprite(self.gender)]
    or sprites.SPRITE_CHRIS or sprites.SPRITE_KRIS
end

-- MapObjectPals' PAL_OW_RED, the palette every .OAMData_MagnetTrainRed entry
-- names, or PAL_OW_BLUE for the _BLUE object Kris rides under.
function MagnetTrainRide:playerPalette()
  local palettes = self.data and self.data.gen2Palettes
  if not palettes then return nil end
  return Palettes.spritePalette(palettes, Palettes.clockDaytime(),
    self:playerSpriteDef())
end

function MagnetTrainRide:drawPlayer()
  local sheet = self.spriteSheet
  if not sheet then return end
  local oam = self.ride:playerOam()
  if #oam == 0 then return end
  local G = love.graphics
  local shader = GbcPalette.available()
  local colors = shader and self:playerPalette()
  if colors then GbcPalette.use(colors) end
  G.setColor(1, 1, 1, 1)
  for _, entry in ipairs(oam) do
    if entry.x >= -8 and entry.x < SCREEN_W and entry.y >= -16 and entry.y < SCREEN_H then
      local quad = self:playerQuad(entry.tile)
      if quad then
        G.draw(sheet.image, quad,
          entry.x + (entry.xflip and 8 or 0), entry.y, 0,
          entry.xflip and -1 or 1, 1)
      end
    end
  end
  if colors then GbcPalette.clear() end
end


-- The backdrop is BG colour 0 of the gray palette the train body uses; on the
-- cart it is what shows wherever nothing was drawn.
function MagnetTrainRide:backdrop()
  return GbcPalette.color(self:palette(MagnetTrain.PAL_BG_GRAY), 1) or BLACK
end

function MagnetTrainRide:drawPanel()
  local G = love.graphics
  local backdrop = self:backdrop()
  G.setColor(backdrop[1] / 255, backdrop[2] / 255, backdrop[3] / 255, 1)
  G.rectangle("fill", 0, 0, SCREEN_W, SCREEN_H)
  G.setColor(1, 1, 1, 1)

  local base, overlay = self:backgrounds()
  -- 1. Base background (bushes, train body, window aperture)
  self:drawBands(base)
  -- 2. Player sprite (OAM_PRIO: sits behind train body, visible through window)
  self:drawPlayer()
  -- 3. Train body / frame overlay (colors 1-3 mask sprite; color 0 is transparent)
  self:drawBands(overlay)

  G.setColor(1, 1, 1, 1)
end

function MagnetTrainRide:draw()
  local G = love.graphics
  G.push("all")
  G.setScissor(0, 0, SCREEN_W, SCREEN_H)
  self:drawPanel()
  G.pop()
end

-- MagnetTrain_LoadGFX_PlayMusic opens on ClearBGPalettes / ClearSprites
-- (engine/events/magnet_train.asm:101-103), so nothing of the station is left
-- behind the ride.  The surround has to be the same gray backdrop the panel
-- computes: a white letterbox would frame the train in a colour the cart never
-- puts on this screen.
function MagnetTrainRide:drawsWidescreen() return true end

function MagnetTrainRide:drawWidescreen(winW, winH)
  local G = love.graphics
  local backdrop = self:backdrop()
  G.setColor(backdrop[1] / 255, backdrop[2] / 255, backdrop[3] / 255, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  G.setColor(1, 1, 1, 1)
  local scale = Chrome.fitScale(winW, winH)
  local ox, oy = Chrome.fitOrigin(winW, winH, scale)
  G.push("all")
  G.setScissor(ox, oy, SCREEN_W * scale, SCREEN_H * scale)
  G.translate(ox, oy)
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return MagnetTrainRide



