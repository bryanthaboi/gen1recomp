-- The Magnet Train ride (pokegold engine/events/magnet_train.asm).
--
-- `special MagnetTrain` is a self-contained cutscene: it takes the whole frame
-- loop away from the overworld, redraws the background out of the train
-- station tileset, and runs a seven-entry jumptable until it sets
-- JUMPTABLE_EXIT.  Everything below is that routine with no love calls in it,
-- so the timing, the scroll and the frameset can be asserted headless; the
-- screen that draws it is src/ui/gen2/MagnetTrainRide.lua.
--
-- The illusion is one 32x18 background and three horizontal SCX bands:
--
--   scanlines   0-46    wMagnetTrainOffset * 2   bushes, always moving
--   scanlines  47-94    wMagnetTrainPosition     the train body
--   scanlines  95-143   wMagnetTrainOffset * 2   bushes again
--
-- MagnetTrain_UpdateLYOverrides writes those three runs into
-- wLYOverridesBackup every frame and then advances the offset, so the scenery
-- never stops even while the jumptable is parked on a .WaitScene.  The train
-- band is what the jumptable actually moves, and the player sprite rides it
-- through wGlobalAnimXOffset, which is why the two stay locked together.
--
-- Everything here is 8-bit and wraps, exactly as the ASM's `add` does: the
-- forward trip runs wMagnetTrainPosition from 96 down past 0 to -96, and it is
-- the byte wrap that keeps SCX legal on the way.

local MagnetTrain = {}
MagnetTrain.__index = MagnetTrain

-- constants/gfx_constants.asm
local TILE_WIDTH = 8
local SCREEN_WIDTH, SCREEN_HEIGHT = 20, 18
local TILEMAP_WIDTH = 32
local SCREEN_HEIGHT_PX = 144

-- PAL_BG_* (constants/gfx_constants.asm) as 1-based palette slots, the way
-- src/world/gen2/Palettes.lua indexes a bgSet.
MagnetTrain.PAL_BG_GRAY = 1
MagnetTrain.PAL_BG_GREEN = 3
MagnetTrain.PAL_BG_YELLOW = 5

-- SetMagnetTrainPals paints the attribute map in four ByteFills: four rows of
-- green, ten of gray, four more of green, and then six tiles of yellow at
-- (7, 8) for the window the player is framed in.
local BUSH_ROWS_TOP = 4      -- hlbgcoord 0, 0  / bc = 4 * TILEMAP_WIDTH
local TRAIN_ROWS = 10        -- hlbgcoord 0, 4  / bc = 10 * TILEMAP_WIDTH
local WINDOW_ROW = 8         -- hlbgcoord 7, 8  / bc = 6
local WINDOW_COL, WINDOW_WIDTH = 7, 6

-- DrawMagnetTrain lays MagnetTrainTilemap over BG rows 6-9.
local FG_ROW = 6
local FG_ROWS = 4

-- Every value in this file is a hardware byte.
local function b(value) return value % 256 end
MagnetTrain.byte = b

--------------------------------------------------------------------------
-- The player in the window
--------------------------------------------------------------------------

-- data/sprite_anims/framesets.asm .Frameset_MagnetTrainRed: two OAM sets on an
-- eight frame beat, the fourth of them mirrored, then `oamrestart`.  The
-- object's own sequence is SPRITE_ANIM_FUNC_NULL (data/sprite_anims/
-- objects.asm), so nothing ever moves the struct: the only motion the player
-- has is wGlobalAnimXOffset, which the two MoveTrain states advance.
local FRAMESET = {
  { oamset = 1, duration = 8, xflip = false },
  { oamset = 2, duration = 8, xflip = false },
  { oamset = 1, duration = 8, xflip = false },
  { oamset = 2, duration = 8, xflip = true },
  "restart",
}

-- data/sprite_anims/oam.asm: SPRITE_ANIM_OAMSET_MAGNET_TRAIN_RED_1 and _2 are
-- vtile $00 and $04 over the same .OAMData_MagnetTrainRed 2x2 block.  Those
-- two vtiles are the two four-tile requests MagnetTrain_LoadGFX_PlayMusic
-- makes: ChrisSpriteGFX at vTiles0 $00, and ChrisSpriteGFX + 12 tiles at
-- vTiles0 $04.  A walking overworld sprite is six 16x16 frames, so those are
-- sheet frame 0 (standing down) and sheet frame 3 (the down walk step).
local OAMSET_VTILE = { 0x00, 0x04 }
MagnetTrain.SHEET_FRAME = { [0x00] = 0, [0x04] = 3 }

-- .OAMData_MagnetTrainRed, `dbsprite x tile, y tile, x px, y px, vtile, attr`.
-- Every entry carries OAM_PRIO, so on the cart the four tiles sit BEHIND
-- background colours 1-3 and only show through the window's colour 0.
local OAM_DATA = {
  { x = b(-1 * TILE_WIDTH), y = b(-1 * TILE_WIDTH), tile = 0x00 },
  { x = b(0 * TILE_WIDTH), y = b(-1 * TILE_WIDTH), tile = 0x01 },
  { x = b(-1 * TILE_WIDTH), y = b(0 * TILE_WIDTH), tile = 0x02 },
  { x = b(0 * TILE_WIDTH), y = b(0 * TILE_WIDTH), tile = 0x03 },
}

-- AddOrSubtractX: a mirrored object flips around its own 8-pixel cell.
local function mirror(value, flip)
  if not flip then return value end
  return b(-(value + TILE_WIDTH))
end

--------------------------------------------------------------------------
-- The ride
--------------------------------------------------------------------------

-- `toGoldenrod` is the wScriptVar the script left behind: Goldenrod's officer
-- writes `setval FALSE` and Saffron's writes `setval TRUE`, and MagnetTrain
-- reads it as "and a / jr nz, .ToGoldenrod".
--
-- opts.bgTiles is MagnetTrainBGTiles (a 2x18 tilemap) and opts.fgTilemap is
-- MagnetTrainTilemap (20x4); both come from the extracted cache.
function MagnetTrain.new(opts)
  opts = opts or {}
  local self = setmetatable({}, MagnetTrain)
  self.toGoldenrod = opts.toGoldenrod and true or false
  if self.toGoldenrod then
    -- .ToGoldenrod: `ld a, -1` / `lb bc, -8 tiles, -12 tiles` /
    -- `lb de, (11 tiles) + (11 tiles + 4), 12 tiles`.
    self.direction = b(-1)
    self.holdPosition = b(-8 * TILE_WIDTH)                       -- b
    self.initPosition = b(-12 * TILE_WIDTH)                      -- c
    self.finalPosition = b(12 * TILE_WIDTH)                      -- e
    self.playerSpriteInitX =
      b((11 * TILE_WIDTH) + (11 * TILE_WIDTH + 4))               -- d
  else
    -- forwards: `ld a, 1` / `lb bc, 8 tiles, 12 tiles` /
    -- `lb de, (11 tiles) - (11 tiles + 4), -12 tiles`.
    self.direction = 1
    self.holdPosition = b(8 * TILE_WIDTH)
    self.initPosition = b(12 * TILE_WIDTH)
    self.finalPosition = b(-12 * TILE_WIDTH)
    self.playerSpriteInitX = b((11 * TILE_WIDTH) - (11 * TILE_WIDTH + 4))
  end

  -- MagnetTrain_LoadGFX_PlayMusic's tail writes wJumptableIndex and the three
  -- bytes after it, so the wait counter starts life holding the init position.
  -- State 0 overwrites it before any .WaitScene reads it.
  self.index = 0
  self.offset = self.initPosition
  self.position = self.initPosition
  self.waitCounter = self.initPosition
  self.exited = false
  self.globalX = 0

  -- The sprite struct does not exist until .InitPlayerSpriteAnim runs.
  self.spriteX, self.spriteY = nil, nil
  self.frame, self.frameDuration = -1, 0
  self.oamFrame = nil

  self.bgTiles = opts.bgTiles
  self.fgTilemap = opts.fgTilemap
  self:updateLYOverrides(true)
  return self
end

function MagnetTrain:done() return self.exited end

-- MagnetTrain's .loop, one pass: the exit bit, PlaySpriteAnimations, the
-- jumptable, then the LY overrides.  Returns the sfx label the frame played,
-- which is only ever SFX_TRAIN_ARRIVED on the last one.
function MagnetTrain:update()
  if self.exited then return nil end
  self:stepSpriteFrame()
  local sfx = self:runJumptable()
  self:updateLYOverrides()
  return sfx
end

-- MagnetTrain_Jumptable.Next
function MagnetTrain:next()
  self.index = self.index + 1
end

-- .WaitScene: zero means "advance", anything else counts down.  A counter of
-- 128 therefore holds for 129 frames, the last of which is the one that reads
-- zero and moves on.
function MagnetTrain:waitScene()
  if self.waitCounter == 0 then
    self:next()
    return
  end
  self.waitCounter = self.waitCounter - 1
end

function MagnetTrain:runJumptable()
  local index = self.index
  if index == 0 then
    -- .InitPlayerSpriteAnim: InitSpriteAnimStruct at d = (8 + 2) * 8 + 5,
    -- e = wMagnetTrainPlayerSpriteInitX, then SPRITEANIMSTRUCT_TILE_ID = 0.
    self.spriteY = b((8 + 2) * TILE_WIDTH + 5)
    self.spriteX = self.playerSpriteInitX
    self.frame, self.frameDuration, self.oamFrame = -1, 0, nil
    self:next()
    self.waitCounter = 128
  elseif index == 1 or index == 3 or index == 5 then
    self:waitScene()
  elseif index == 2 then
    -- .MoveTrain1: one pixel a frame until the train reaches its hold
    -- position, then park for another 128 frames.
    if self.position == self.holdPosition then
      self:next()
      self.waitCounter = 128
      return nil
    end
    self.position = b(self.position - self.direction)
    self.globalX = b(self.globalX + self.direction)
  elseif index == 4 then
    -- .MoveTrain2: the same, at double speed, until it leaves the screen.
    if self.position == self.finalPosition then
      self:next()
      return nil
    end
    self.position = b(self.position - 2 * self.direction)
    self.globalX = b(self.globalX + 2 * self.direction)
  elseif index >= 6 then
    -- .TrainArrived: JUMPTABLE_EXIT and SFX_TRAIN_ARRIVED, and the loop reads
    -- the exit bit at the top of the next pass.
    self.exited = true
    return "Sfx_TrainArrived"
  end
  return nil
end

-- MagnetTrain_UpdateLYOverrides.  The three runs are 6*8-1, 6*8 and 6*8+1
-- entries, which is 144 scanlines exactly; hSCX takes the first band's value
-- because line 0 is drawn before the LCD interrupt has fired.  The offset
-- advances by two per frame (`add d` twice) AFTER the overrides are written.
--
-- `initial` builds the first frame's table without advancing, matching
-- MagnetTrain_InitLYOverrides, which ByteFills the whole array with the init
-- position before the loop starts.
function MagnetTrain:updateLYOverrides(initial)
  local ly = self.ly or {}
  if initial then
    for line = 1, SCREEN_HEIGHT_PX do ly[line] = self.initPosition end
    self.ly = ly
    self.scx = self.initPosition
    return ly
  end
  local scx = b(self.offset * 2)
  self.scx = scx
  local line = 1
  for _ = 1, 6 * TILE_WIDTH - 1 do ly[line] = scx; line = line + 1 end
  for _ = 1, 6 * TILE_WIDTH do ly[line] = self.position; line = line + 1 end
  for _ = 1, 6 * TILE_WIDTH + 1 do ly[line] = scx; line = line + 1 end
  self.ly = ly
  self.offset = b(self.offset + 2 * self.direction)
  return ly
end

-- The SCX each of the three bands is scrolled by this frame, as
-- { first scanline, last scanline (inclusive), scx }.  A band is a run of
-- equal LY overrides, so this is the same information the table holds and the
-- shape a renderer wants.
function MagnetTrain:bands()
  local ly = self.ly
  if not ly then return {} end
  local out = {}
  local start, value = 0, ly[1]
  for line = 1, SCREEN_HEIGHT_PX do
    if ly[line] ~= value then
      out[#out + 1] = { start, line - 2, value }
      start, value = line - 1, ly[line]
    end
  end
  out[#out + 1] = { start, SCREEN_HEIGHT_PX - 1, value }
  return out
end

--------------------------------------------------------------------------
-- The background
--------------------------------------------------------------------------

-- DrawMagnetTrain.  Rows 0-17 are MagnetTrainBGTiles' two-tile pair for that
-- row repeated across all 32 columns (`.FillAlt`, TILEMAP_WIDTH / 2 times),
-- and then MagnetTrainTilemap's four 20-tile lines are laid over rows 6-9.
function MagnetTrain:tilemap()
  local bg = self.bgTiles
  if not (bg and #bg >= SCREEN_HEIGHT * 2) then
    error("magnetTrain has no MagnetTrainBGTiles", 2)
  end
  local rows = {}
  for row = 0, SCREEN_HEIGHT - 1 do
    local even, odd = bg[row * 2 + 1], bg[row * 2 + 2]
    local line = {}
    for col = 0, TILEMAP_WIDTH - 1 do
      line[col + 1] = (col % 2 == 0) and even or odd
    end
    rows[row + 1] = line
  end
  local fg = self.fgTilemap
  if not (fg and #fg >= SCREEN_WIDTH * FG_ROWS) then
    error("magnetTrain has no MagnetTrainTilemap", 2)
  end
  for line = 0, FG_ROWS - 1 do
    local row = rows[FG_ROW + line + 1]
    for col = 0, SCREEN_WIDTH - 1 do
      row[col + 1] = fg[line * SCREEN_WIDTH + col + 1]
    end
  end
  return rows
end

-- SetMagnetTrainPals, read back as "which palette does this cell use".
-- `col` and `row` are 0-based BG map coordinates.
function MagnetTrain.paletteSlot(col, row)
  if row == WINDOW_ROW and col >= WINDOW_COL
      and col < WINDOW_COL + WINDOW_WIDTH then
    return MagnetTrain.PAL_BG_YELLOW
  end
  if row < BUSH_ROWS_TOP then return MagnetTrain.PAL_BG_GREEN end
  if row < BUSH_ROWS_TOP + TRAIN_ROWS then return MagnetTrain.PAL_BG_GRAY end
  return MagnetTrain.PAL_BG_GREEN
end

--------------------------------------------------------------------------
-- The sprite
--------------------------------------------------------------------------

-- GetSpriteAnimFrame, cut down to one frameset that never waits, ends or
-- changes sequence.  A frame with duration 8 is therefore shown nine times:
-- the pass that sets the duration, then eight that decrement it.
function MagnetTrain:stepSpriteFrame()
  if not self.spriteX then return end
  if self.frameDuration ~= 0 then
    self.frameDuration = self.frameDuration - 1
    return
  end
  self.frame = self.frame + 1
  local entry = FRAMESET[self.frame + 1]
  if entry == "restart" then
    self.frame = 0
    entry = FRAMESET[1]
  end
  self.frameDuration = entry.duration
  self.oamFrame = entry
end

-- The four OAM entries the player is drawn as this frame, each
-- { x, y, tile, xflip } in SCREEN pixels (the hardware's byte minus the 8 and
-- 16 pixel OAM origins).  `tile` is the vtile the OAM set resolves to, which
-- MagnetTrain.SHEET_FRAME turns into a 16x16 frame of the walking sheet.
--
-- Empty before .InitPlayerSpriteAnim has run.
function MagnetTrain:playerOam()
  local entry = self.oamFrame
  if not (entry and self.spriteX) then return {} end
  local vtile = OAMSET_VTILE[entry.oamset]
  local out = {}
  for _, sprite in ipairs(OAM_DATA) do
    local x = b(self.spriteX + self.globalX + mirror(sprite.x, entry.xflip))
    local y = b(self.spriteY + sprite.y)
    out[#out + 1] = {
      x = x - 8,
      y = y - 16,
      tile = vtile + sprite.tile,
      xflip = entry.xflip,
    }
  end
  return out
end

return MagnetTrain
