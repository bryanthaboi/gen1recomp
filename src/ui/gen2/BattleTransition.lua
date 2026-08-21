-- DoBattleTransition (engine/battle/battle_transition.asm): the wipe that
-- takes the overworld off screen before a battle starts.
--
-- The cart drives it from a jumptable of 33 slots, four consecutive runs
-- through the same five steps with a different outro at the end:
--
--   LoadPokeBallGraphics   a 16x16 Poke Ball stamped over the map -- TRAINER
--                          battles only, `and a / jr z` on wOtherTrainerClass
--   SetUpBGMap             bookkeeping
--   Flash x3               the 13-entry rBGP table, twice per entry, run
--                          three times over
--   NextScene
--   SetUpFor<outro>        + the outro itself
--
-- and the outro is picked by two bits (StartTrainerBattle_DetermineWhichAnimation):
--
--                    | player's lead + 3 >= enemy | enemy stronger
--   CAVE/DUNGEON/5   | SineWave (a growing wobble)| ZoomToBlack
--   anywhere else    | SpinToBlack               | SpeckleToBlack
--
-- Note the cart's own bug, kept here: the level test reads wEnemyMonLevel
-- BEFORE the enemy mon is loaded, so "stronger" is decided against whatever
-- the previous battle left there.  This port has no such stale byte, so it
-- compares honestly -- the one place the port is deliberately not bug-exact,
-- because the alternative is emulating an uninitialised variable.
--
-- Everything that decides WHICH tiles go black is a pure function below and is
-- covered by tests; the state at the bottom is the only part that draws.

local GbcPalette = require("src.render.GbcPalette")
local Playfield = require("src.render.Playfield")
local Palettes = require("src.world.gen2.Palettes")
local Runtime = require("src.mods.Runtime")
local SpriteAnims = require("src.ui.gen2.SpriteAnims")
local Tilt = require("src.render.Tilt")

local BattleTransition = {}
BattleTransition.__index = BattleTransition
BattleTransition.isOpaque = false

local COLS, ROWS = 20, 18 -- SCREEN_WIDTH x SCREEN_HEIGHT, in tiles

--------------------------------------------------------------------------
-- The flash
--------------------------------------------------------------------------

-- StartTrainerBattle_Flash's `.pals`: one packed rBGP per entry, colour 3
-- first, and the run stops at %00000001 (which is why the last row is a
-- terminator rather than a palette).  On a CGB DmgToCgbBGPals pushes each
-- of these through every BG palette, so what the player sees is the whole
-- picture darkening to black, coming back, washing out to white, and coming
-- back again.
--
-- The port draws the overworld into a baked map canvas, so by the time the
-- flash runs there is no four-entry palette left in the frame to permute.
-- GbcPalette's remap shader puts one back: it matches each pixel to the BG
-- palette entry that produced it and substitutes what the byte sends that entry
-- to, which is CopyPals exactly.  BattleTransition:drawFlash does that and
-- falls back to flashVeil below -- the entry's mean shade against the identity
-- %11100100 (3,2,1,0), normalised so 3,3,3,3 is solid black and 0,0,0,0 is
-- solid white -- only when the exact pass cannot run.
BattleTransition.FLASH_PALS = {
  { 3, 3, 2, 1 },
  { 3, 3, 3, 2 },
  { 3, 3, 3, 3 },
  { 3, 3, 3, 2 },
  { 3, 3, 2, 1 },
  { 3, 2, 1, 0 },
  { 2, 1, 0, 0 },
  { 1, 0, 0, 0 },
  { 0, 0, 0, 0 },
  { 1, 0, 0, 0 },
  { 2, 1, 0, 0 },
  { 3, 2, 1, 0 },
}
-- `ld a, [hl] / inc [hl] / srl a`: the counter advances every frame and the
-- index is half of it, so each palette is held for two.
BattleTransition.FLASH_HOLD = 2
-- Three StartTrainerBattle_Flash slots in a row, each running the table once.
BattleTransition.FLASH_CYCLES = 3

-- One .pals row as the rBGP byte the cart writes.  `dc` emits colour 3 first,
-- so the row packs high bits to low and `dc 3, 2, 1, 0` comes out $e4.
function BattleTransition.flashByte(pal)
  return pal[1] * 64 + pal[2] * 16 + pal[3] * 4 + pal[4]
end

-- Signed veil for one palette row: +1 is black, -1 is white, 0 is untouched.
--
-- The approximation, kept as the fallback for a boot with no shader (where the
-- world is drawn as raw grayscale and there is nothing to re-index anyway) and
-- for TILT, whose perspective pass resamples with linear filtering so the frame
-- stops holding palette colours.
function BattleTransition.flashVeil(pal)
  local sum = 0
  for _, shade in ipairs(pal) do sum = sum + shade end
  -- identity (3,2,1,0) sums to 6; the extremes are 12 and 0.
  return (sum - 6) / 6
end

BattleTransition.FLASH_FRAMES =
  #BattleTransition.FLASH_PALS * BattleTransition.FLASH_HOLD
    * BattleTransition.FLASH_CYCLES

--------------------------------------------------------------------------
-- The Poke Ball overlay (trainer battles only)
--------------------------------------------------------------------------

-- `.PokeBallTransition`, 16 bigdw rows of 16 bits, stamped from hlcoord 2, 1.
-- A set bit becomes BATTLETRANSITION_SQUARE; the drawing loop stops early on a
-- byte that has shifted itself empty, which is why the trailing zero columns of
-- a byte are never written (and why it cannot be read as a plain 16-wide
-- bitmap without care).
local POKEBALL_ROWS = {
  "......XXXX......",
  "....XXXXXXXX....",
  "..XXXX....XXXX..",
  "..XX........XX..",
  ".XX..........XX.",
  ".XX...XXXX...XX.",
  "XX...XX..XX...XX",
  "XXXXXX....XXXXXX",
  "XXXXXX....XXXXXX",
  "XX...XX..XX...XX",
  ".XX...XXXX...XX.",
  ".XX..........XX.",
  "..XX........XX..",
  "..XXXX....XXXX..",
  "....XXXXXXXX....",
  "......XXXX......",
}
BattleTransition.POKEBALL_X = 2
BattleTransition.POKEBALL_Y = 1

function BattleTransition.pokeballCells()
  local cells = {}
  for row, bits in ipairs(POKEBALL_ROWS) do
    for col = 1, #bits do
      if bits:sub(col, col) == "X" then
        cells[#cells + 1] = {
          BattleTransition.POKEBALL_X + col - 1,
          BattleTransition.POKEBALL_Y + row - 1,
        }
      end
    end
  end
  return cells
end

--------------------------------------------------------------------------
-- SpinToBlack
--------------------------------------------------------------------------

-- Each wedge is a run-length walk away from its own corner: fill `count`
-- tiles, drop (or climb) a row, then step `shift` tiles back toward the
-- corner.  A -1 in the shift slot ends the wedge, so the last pair's fill
-- happens and the walk stops.
local WEDGES = {
  wedge1 = { 2, 3, 5, 4, 9, -1 },
  wedge2 = { 1, 1, 2, 2, 4, 2, 4, 2, 3, -1 },
  wedge3 = { 2, 1, 3, 1, 4, 1, 4, 1, 4, 1, 3, 1, 2, 1, 1, 1, 1, -1 },
  wedge4 = { 4, 1, 4, 0, 3, 1, 3, 0, 2, 1, 2, 0, 1, -1 },
  wedge5 = { 4, 0, 3, 0, 3, 0, 2, 0, 2, 0, 1, 0, 1, 0, 1, -1 },
}

-- `.spin_quadrants`: quadrant, wedge, and the tile the walk starts on.  Twenty
-- steps, five per quadrant, going clockwise from the left edge.
BattleTransition.SPIN_STEPS = {
  { "UPPER_LEFT",  "wedge1",  1,  6 },
  { "UPPER_LEFT",  "wedge2",  0,  3 },
  { "UPPER_LEFT",  "wedge3",  1,  0 },
  { "UPPER_LEFT",  "wedge4",  5,  0 },
  { "UPPER_LEFT",  "wedge5",  9,  0 },
  { "UPPER_RIGHT", "wedge5", 10,  0 },
  { "UPPER_RIGHT", "wedge4", 14,  0 },
  { "UPPER_RIGHT", "wedge3", 18,  0 },
  { "UPPER_RIGHT", "wedge2", 19,  3 },
  { "UPPER_RIGHT", "wedge1", 18,  6 },
  { "LOWER_RIGHT", "wedge1", 18, 11 },
  { "LOWER_RIGHT", "wedge2", 19, 14 },
  { "LOWER_RIGHT", "wedge3", 18, 17 },
  { "LOWER_RIGHT", "wedge4", 14, 17 },
  { "LOWER_RIGHT", "wedge5", 10, 17 },
  { "LOWER_LEFT",  "wedge5",  9, 17 },
  { "LOWER_LEFT",  "wedge4",  5, 17 },
  { "LOWER_LEFT",  "wedge3",  1, 17 },
  { "LOWER_LEFT",  "wedge2",  0, 14 },
  { "LOWER_LEFT",  "wedge1",  1, 11 },
}

-- Each spin step holds for two frames (`call DelayFrame` twice).
BattleTransition.SPIN_HOLD = 2

-- Walk one wedge, marking cells in `black` (a [y * COLS + x] set).  The
-- quadrant only decides two signs: RIGHT_QUADRANT_F flips the fill direction
-- (and the shift, which always runs back the other way), LOWER_QUADRANT_F
-- flips the row step.
function BattleTransition.spinStep(black, step)
  local quadrant, wedgeName, x, y = step[1], step[2], step[3], step[4]
  local wedge = WEDGES[wedgeName]
  local right = quadrant == "UPPER_RIGHT" or quadrant == "LOWER_RIGHT"
  local lower = quadrant == "LOWER_LEFT" or quadrant == "LOWER_RIGHT"
  local dx = right and 1 or -1
  local dy = lower and -1 or 1
  local i = 1
  while i <= #wedge do
    local count = wedge[i]
    i = i + 1
    local cx = x
    for _ = 1, count do
      -- The cart writes straight into the tilemap and lets a run walk off the
      -- end of a row into the next one; clipping instead keeps the wedge the
      -- shape the data draws and costs nothing the player can see.
      if cx >= 0 and cx < COLS and y >= 0 and y < ROWS then
        black[y * COLS + cx] = true
      end
      cx = cx + dx
    end
    y = y + dy
    local shift = wedge[i]
    i = i + 1
    if shift == nil or shift == -1 then return black end
    x = x - dx * shift
  end
  return black
end

--------------------------------------------------------------------------
-- ZoomToBlack
--------------------------------------------------------------------------

-- `.boxes`: width, height, and the top-left corner, growing out of the middle
-- until the last one is the whole screen.  One box per WaitBGMap, i.e. one a
-- frame.
BattleTransition.ZOOM_BOXES = {
  {  4,  2,  8, 8 },
  {  6,  4,  7, 7 },
  {  8,  6,  6, 6 },
  { 10,  8,  5, 5 },
  { 12, 10,  4, 4 },
  { 14, 12,  3, 3 },
  { 16, 14,  2, 2 },
  { 18, 16,  1, 1 },
  { 20, 18,  0, 0 },
}
-- `zoombox width, height, start y, start x` -- the macro's own argument order,
-- which is why the third number is the ROW.
function BattleTransition.zoomStep(black, box)
  local width, height, y0, x0 = box[1], box[2], box[3], box[4]
  for y = y0, math.min(ROWS, y0 + height) - 1 do
    for x = x0, math.min(COLS, x0 + width) - 1 do
      black[y * COLS + x] = true
    end
  end
  return black
end

--------------------------------------------------------------------------
-- SpeckleToBlack
--------------------------------------------------------------------------

-- Sixteen passes of twelve tiles each; a tile that is already black is
-- resampled, so the count is twelve NEW tiles a frame, not twelve rolls.
BattleTransition.SPECKLE_PASSES = 0x10
BattleTransition.SPECKLE_PER_PASS = 12

function BattleTransition.speckleStep(black, random)
  local roll = random or function(n) return math.random(n) - 1 end
  for _ = 1, BattleTransition.SPECKLE_PER_PASS do
    -- The cart rejects an out-of-range Random and rolls again; the modulo a
    -- port would reach for first is NOT the same distribution, so the reject
    -- loop stays.
    local x, y
    repeat y = roll(256) until y < ROWS
    repeat x = roll(256) until x < COLS
    local key = y * COLS + x
    if black[key] then
      -- `jr z, .y_loop`: a repeat lands on the same pass, so a late pass
      -- really does place fewer than twelve tiles.
      local tries = 0
      repeat
        repeat y = roll(256) until y < ROWS
        repeat x = roll(256) until x < COLS
        key = y * COLS + x
        tries = tries + 1
      until not black[key] or tries > COLS * ROWS
    end
    black[key] = true
  end
  return black
end

--------------------------------------------------------------------------
-- SineWave (the cave outro)
--------------------------------------------------------------------------

-- The amplitude is wBattleTransitionCounter, which grows by the frame index
-- every frame (`counter += offset`, `offset++`), so it runs 0, 0, 1, 3, 6, 10
-- ... and the outro ends the frame it reaches $60.  The phase does not
-- advance: `e` restarts at 0 each frame and steps 2 a scanline, i.e. one full
-- period every 32 rows.
BattleTransition.SINE_LIMIT = 0x60

function BattleTransition.sineFrames()
  local frames = {}
  local counter, offset = 0, 0
  while counter < BattleTransition.SINE_LIMIT do
    local amplitude = counter
    counter = counter + offset
    offset = offset + 1
    local row = {}
    for y = 0, 143 do
      -- The stored byte is signed; DrawSineWave returns it two's complement.
      local value = SpriteAnims.sine(y * 2, amplitude)
      row[y] = value >= 128 and value - 256 or value
    end
    frames[#frames + 1] = row
  end
  return frames
end

--------------------------------------------------------------------------
-- Choosing the animation
--------------------------------------------------------------------------

-- StartTrainerBattle_DetermineWhichAnimation: CAVE, ENVIRONMENT_5 and DUNGEON
-- take the cave pair, everything else the other one.
BattleTransition.CAVE_ENVIRONMENTS = {
  CAVE = true, ENVIRONMENT_5 = true, DUNGEON = true,
}

function BattleTransition.pick(opts)
  opts = opts or {}
  local cave = BattleTransition.CAVE_ENVIRONMENTS[opts.environment] == true
  local stronger = (opts.playerLevel or 1) + 3 < (opts.enemyLevel or 1)
  if cave then return stronger and "zoom" or "sine" end
  return stronger and "speckle" or "spin"
end

-- The four outros the jumptable can reach.  A transition.style hook that names
-- anything else falls back to the two-bit select, the way the Gen 1 site falls
-- back on an unregistered style (src/render/BattleTransition.lua).
BattleTransition.STYLES = {
  spin = true, speckle = true, zoom = true, sine = true,
}

-- The default of the transition.style hook: the caller's explicit pin if there
-- is one, otherwise StartTrainerBattle_DetermineWhichAnimation's own answer.
local function vanillaStyle(ctx)
  return ctx.style or BattleTransition.pick(ctx)
end

--------------------------------------------------------------------------
-- The state
--------------------------------------------------------------------------

function BattleTransition:drawsWidescreen() return true end
function BattleTransition:wantsFillScale() return true end

-- opts: world, trainer (bool), environment, playerLevel, enemyLevel,
--       random(n), onDone
function BattleTransition.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, BattleTransition)
  self.game = game
  self.world = opts.world or (game and game.world)
  self.onDone = opts.onDone
  self.random = opts.random
  -- transition.style, the same hook name the Gen 1 wipe uses
  -- (src/render/BattleTransition.lua), and the same context keys: `trainer`,
  -- `stronger` and `dungeon` are the selection bits a Gen 1 mod already reads,
  -- `dungeon` being the cave/dungeon environments this generation names
  -- CAVE / ENVIRONMENT_5 / DUNGEON.  `environment`, `playerLevel`,
  -- `enemyLevel` and `style` are Gen 2's own: the raw inputs the two bits are
  -- derived from, added rather than swapped in.
  local ctx = {
    game = game,
    trainer = opts.trainer and true or false,
    stronger = (opts.playerLevel or 1) + 3 < (opts.enemyLevel or 1),
    dungeon = BattleTransition.CAVE_ENVIRONMENTS[opts.environment] == true,
    environment = opts.environment,
    playerLevel = opts.playerLevel,
    enemyLevel = opts.enemyLevel,
    style = opts.style,
  }
  local style = Runtime.call("transition.style", vanillaStyle, ctx)
  -- A hook naming an outro that does not exist would freeze on a black screen
  -- (no phase ever finishes), so it falls back to the vanilla pick.
  if not BattleTransition.STYLES[style] then style = vanillaStyle(ctx) end
  self.style = style
  self.trainer = opts.trainer and true or false
  self.black = {}
  self.frame = 0
  self.step = 0
  self.phase = self.trainer and "pokeball" or "flash"
  self.sine = nil
  return self
end

-- One logic frame.  The phases run in the jumptable's order and the state pops
-- itself when the last one is done, so the battle screen comes up on the black
-- screen the wipe left behind.
function BattleTransition:update(_dt)
  self.frame = self.frame + 1
  if self.phase == "pokeball" then
    -- Two DelayFrames on the DMG path, one CGBOnly_CopyTilemapAtOnce on the
    -- other; either way the ball is on screen for a moment before the flash.
    if self.frame >= 2 then
      self.phase = "flash"
      self.frame = 0
    end
    return
  end
  if self.phase == "flash" then
    if self.frame >= BattleTransition.FLASH_FRAMES then
      self.phase = "outro"
      self.frame = 0
      self.step = 0
      if self.style == "sine" then
        self.sine = BattleTransition.sineFrames()
      end
    end
    return
  end
  if self.phase == "outro" then
    self:outroFrame()
    return
  end
  if self.phase == "black" then
    if self.frame >= BattleTransition.BLACK_HOLD then self:finish() end
    return
  end
  self:finish()
end

function BattleTransition:outroFrame()
  local style = self.style
  if style == "spin" then
    if self.frame % BattleTransition.SPIN_HOLD ~= 1 then return end
    self.step = self.step + 1
    local step = BattleTransition.SPIN_STEPS[self.step]
    if not step then
      self:blackOut()
      return
    end
    BattleTransition.spinStep(self.black, step)
  elseif style == "zoom" then
    self.step = self.step + 1
    local box = BattleTransition.ZOOM_BOXES[self.step]
    if not box then
      self:blackOut()
      return
    end
    BattleTransition.zoomStep(self.black, box)
  elseif style == "speckle" then
    self.step = self.step + 1
    if self.step > BattleTransition.SPECKLE_PASSES then
      self:blackOut()
      return
    end
    BattleTransition.speckleStep(self.black, self.random)
  else -- sine
    self.step = self.step + 1
    if not (self.sine and self.sine[self.step]) then
      self:blackOut()
      return
    end
  end
end

-- DoBattleTransition's own `.done`: every BG palette is filled with zero and
-- wBGP set to %11111111, i.e. the screen is solid black, and it stays that way
-- while the battle screen loads its tiles and decompresses its pics.  Two of
-- the four outros never black the whole screen out themselves -- the speckle
-- only ever reaches about half the tiles, and the sine wave none of them -- so
-- without this the map would still be showing under the last frame.
--
-- The hold is a frame budget for a load this port does not have, the same
-- judgement call src/render/BattleTransition.lua documents for Gen 1.
BattleTransition.BLACK_HOLD = 16

function BattleTransition:blackOut()
  self.phase = "black"
  self.frame = 0
end

function BattleTransition:finish()
  if self.finished then return end
  self.finished = true
  local stack = self.game and self.game.stack
  if stack then stack:pop() end
  if self.onDone then self.onDone() end
end

-- The LY overrides this frame, or nil outside the sine outro.
function BattleTransition:lyOverrides()
  if self.phase ~= "outro" or self.style ~= "sine" then return nil end
  return self.sine and self.sine[self.step] or nil
end

-- `black` covers the 20x18 tilemap; the window is bigger than that, so a cell
-- outside the map takes its nearest in-range neighbour's state.  That is the
-- same idea Renderer:drawBattleWipe uses for Gen 1: continue the pattern with
-- more tiles rather than scale the tiles up, so at 1x this is the cart's grid
-- exactly.
function BattleTransition:blackAt(col, row)
  local x = math.max(0, math.min(COLS - 1, col))
  local y = math.max(0, math.min(ROWS - 1, row))
  return self.black[y * COLS + x] == true
end

function BattleTransition:draw()
  local w, h = Playfield.dimensions()
  self:drawWidescreen(w, h)
end

-- The .pals row this frame is holding, or nil outside the flash phase.
function BattleTransition:flashPal()
  if self.phase ~= "flash" then return nil end
  local index = math.floor(self.frame / BattleTransition.FLASH_HOLD)
    % #BattleTransition.FLASH_PALS + 1
  return BattleTransition.FLASH_PALS[index]
end

-- The palette lists the flash's remap needs: the map's eight BG palettes, which
-- DmgToCgbBGPals permutes, and the time of day's eight OBJ palettes, which it
-- does not (that is DmgToCgbObjPals, and the flash never calls it -- the player
-- and the NPCs really do keep their colours while the map flashes, and
-- ClearSprites only runs at StartTrainerBattle_Finish).
function BattleTransition:remapPalettes()
  local world = self.world
  local def = world and world.map and world.map.def
  if not (def and world.palettes) then return nil end
  local bg = Palettes.bgSet(world.palettes, def, world.daytime)
  if not bg then return nil end
  return bg, Palettes.objectSet(world.palettes, world.daytime)
end

-- Draw the map through this frame's rBGP byte, exactly.  Returns false when the
-- exact pass cannot run, which is the caller's cue to draw the world plainly
-- and lay the brightness veil over it instead.
function BattleTransition:drawFlash(w, h, pal)
  local byte = BattleTransition.flashByte(pal)
  if byte == GbcPalette.BGP_IDENTITY then
    -- `dc 3, 2, 1, 0` twice in the table: the picture is simply itself.
    self.world:draw()
    return true
  end
  -- TILT projects the finished frame through a linear-filtered canvas, so its
  -- pixels are blends of palette colours rather than palette colours; matching
  -- them back would posterise the warp instead of flashing it.
  if Tilt.active and Tilt.active() then return false end
  local bg, obj = self:remapPalettes()
  if not bg then return false end
  local canvas = self:capture(w, h)
  if not canvas then return false end
  local applied = GbcPalette.useRemap(bg, byte, obj)
  if not applied then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, 0, 0)
  GbcPalette.clear()
  return true
end

function BattleTransition:drawWidescreen(w, h)
  local G = love.graphics
  local world = self.world
  local ly = self:lyOverrides()

  if self.phase == "black" then
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, w, h)
    G.setColor(1, 1, 1, 1)
    return
  end

  -- Cleared once the flash has been drawn exactly, so the veil below is only
  -- ever the fallback and the two can never both land on one frame.
  local pal = self:flashPal()

  if world and world.map then
    if ly then
      self:drawWavy(w, h, ly)
    elseif pal and self:drawFlash(w, h, pal) then
      pal = nil
    else
      world:draw()
    end
  else
    G.setColor(0, 0, 0, 1)
    G.rectangle("fill", 0, 0, w, h)
  end

  if self.phase == "pokeball" then
    self:drawCells(w, h, BattleTransition.pokeballCells())
  end

  if pal then
    local veil = BattleTransition.flashVeil(pal)
    if veil ~= 0 then
      local shade = veil > 0 and 0 or 1
      G.setColor(shade, shade, shade, math.abs(veil))
      G.rectangle("fill", 0, 0, w, h)
    end
  end

  self:drawBlack(w, h)
  G.setColor(1, 1, 1, 1)
end

-- The tile grid, anchored on the letterbox and extended outward: `world` is
-- being drawn at the ZOOM scale but the wipe is screen furniture, so it takes
-- the plain integer fit the rest of the UI does.
function BattleTransition:grid(w, h)
  local scale = 1
  if self.world and self.world.fitScale then
    scale = self.world:fitScale()
  else
    scale = math.max(1, math.floor(math.min(w / 160, h / 144)))
  end
  local size = 8 * scale
  local Chrome = require("src.ui.gen2.Chrome")
  local ox, oy = Chrome.fitOrigin(w, h, scale)
  return size, ox, oy
end

function BattleTransition:drawBlack(w, h)
  local G = love.graphics
  local size, ox, oy = self:grid(w, h)
  local first = -math.ceil(ox / size)
  local last = math.ceil((w - ox) / size)
  local top = -math.ceil(oy / size)
  local bottom = math.ceil((h - oy) / size)
  G.setColor(0, 0, 0, 1)
  for row = top, bottom - 1 do
    for col = first, last - 1 do
      if self:blackAt(col, row) then
        G.rectangle("fill", ox + col * size, oy + row * size, size, size)
      end
    end
  end
end

-- BATTLETRANSITION_SQUARE, the Poke Ball's own tile: a filled block in the
-- text palette rather than the black the wipe uses, so the ball reads against
-- the map behind it.
function BattleTransition:drawCells(w, h, cells)
  local G = love.graphics
  local size, ox, oy = self:grid(w, h)
  -- Shade 3 of the text palette, through the COLOR mode like every other
  -- direct colour read.
  local color = GbcPalette.color(nil, 4)
  if color then
    G.setColor(color[1] / 255, color[2] / 255, color[3] / 255, 1)
  else
    G.setColor(0, 0, 0, 1)
  end
  for _, cell in ipairs(cells) do
    G.rectangle("fill", ox + cell[1] * size, oy + cell[2] * size, size, size)
  end
end

-- The sine outro shifts whole scanlines, which needs the frame as a texture:
-- the world is captured once and re-blitted a row at a time from then on.
function BattleTransition:drawWavy(w, h, ly)
  local G = love.graphics
  local canvas = self:capture(w, h)
  if not canvas then
    self.world:draw()
    return
  end
  local scale = 1
  if self.world.fitScale then scale = self.world:fitScale() end
  G.setColor(0, 0, 0, 1)
  G.rectangle("fill", 0, 0, w, h)
  G.setColor(1, 1, 1, 1)
  local rows = math.ceil(h / scale)
  if not self.quad then
    self.quad = love.graphics.newQuad(0, 0, w, scale, w, h)
  end
  for y = 0, rows - 1 do
    -- 144 overrides for however many screen rows the window has; a row past
    -- the end of the array holds the last value, the way the LCD keeps the
    -- final rSCX write.
    local shift = (ly[math.min(143, y)] or 0) * scale
    self.quad:setViewport(0, y * scale, w, scale, w, h)
    -- SCX scrolls the BACKGROUND, so a positive override moves the picture
    -- LEFT -- the same sign the battle BG effects take.  The hardware BG map
    -- WRAPS, so a shifted scanline never shows a hole; the row is drawn again
    -- a screen over to stand in for that (the cart wraps at the 256-pixel BG
    -- map, this at the window, but either way there is no black gap).
    G.draw(canvas, self.quad, -shift, y * scale)
    if shift > 0 then
      G.draw(canvas, self.quad, -shift + w, y * scale)
    elseif shift < 0 then
      G.draw(canvas, self.quad, -shift - w, y * scale)
    end
  end
end

function BattleTransition:capture(w, h)
  if self.canvas then
    local cw, ch = self.canvas:getDimensions()
    if cw ~= w or ch ~= h then self.canvas = nil end
  end
  if not self.canvas then
    local ok, made = pcall(love.graphics.newCanvas, w, h)
    if not ok or not made then return nil end
    made:setFilter("nearest", "nearest")
    self.canvas = made
    self.captured = false
  end
  if not self.captured then
    local G = love.graphics
    local previous = G.getCanvas()
    -- A canvas does not reset the transform.
    G.push()
    G.origin()
    G.setCanvas(self.canvas)
    G.clear(0, 0, 0, 1)
    self.world:draw()
    G.setCanvas(previous)
    G.pop()
    self.captured = true
  end
  return self.canvas
end

return BattleTransition
