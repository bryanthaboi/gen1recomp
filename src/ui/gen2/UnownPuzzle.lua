-- The Ruins of Alph sliding-panel puzzle (engine/games/unown_puzzle.asm
-- _UnownPuzzle), opened by `special UnownPuzzle` from each chamber's `bg_event
-- BGEVENT_UP` wall.
--
-- Sixteen panels of a picture start on the OUTER ring of a 6x6 board and the
-- interior 4x4 is empty; A picks a panel up, A puts it down on an empty cell,
-- and the puzzle is solved when the interior holds panels 1..16 in reading
-- order.  START quits at any time.  The `setval UNOWNPUZZLE_*` in front of the
-- special picks which of the four pictures is being assembled (Kabuto,
-- Omanyte, Aerodactyl, Ho-Oh), and `wSolvedUnownPuzzle` comes back out in
-- wScriptVar so the chamber's `iftrue` can drop the floor.
--
-- The board is a TILEMAP, so every coordinate below is the hlcoord the ASM
-- writes and not a number picked to look right:
--
--   hlcoord 0, 0 + SCREEN_AREA  filled with PUZZLE_BORDER ($ee)
--   hlcoord 4, 3, lb bc 12, 12  filled with PUZZLE_VOID ($ef) -- the interior
--   UnownPuzzleCoordData        cell i sits at (1 + 3*(i%6), 3*(i/6)), so the
--                               6x6 board of 3x3-tile cells spans (1,0)..(18,17)
--   PlaceStartCancelBoxBorder   the box at rows 15-17, columns 4-15
--   PlaceStartCancelBox         $f6..$ff, the ten caption tiles, at (5,16)
--
-- The 16 initial positions are exactly the ring cells (.PuzzlePieceInitialPositions
-- lists all six of row 0, both ends of rows 1-4, and both ends of row 5), which
-- is why a fresh board is full on the outside and empty in the middle.
--
-- The cursor is an OBJ, four tiles mirrored into a 3x3 bracket, and it BLINKS:
-- RedrawUnownPuzzlePieces only runs when `hVBlankCounter and $10` is set, which
-- is 16 frames on and 16 off -- except while a panel is held, when the panel
-- itself rides the cursor and is drawn every frame.
--
-- The art comes out of the cache as menu_gfx.unownPuzzle (the extractor already
-- does ConvertLoadedPuzzlePieces' 2x enlargement and the border pass, so a
-- picture is a plain 96x96 sheet of 4x4 panels).  Without it the board still
-- plays: panels draw as their numbers, which is enough to solve and enough for
-- a test, and is the same degrade src/ui/gen2/CardFlip.lua takes.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local TileSheet = require("src.ui.gen2.TileSheet")

local UnownPuzzle = {}
UnownPuzzle.__index = UnownPuzzle
UnownPuzzle.isOpaque = true

-- DEF PUZZLE_BORDER EQU $ee / DEF PUZZLE_VOID EQU $ef.
UnownPuzzle.BORDER_TILE = 0xee
UnownPuzzle.VOID_TILE = 0xef

-- PREDEFPAL_UNOWN_PUZZLE (gfx/sgb/predef.pal), transcribed at the extractor's
-- own 5-bit to 8-bit scale so a re-imported cache produces these same bytes:
-- RGB 31,31,31 / 24,20,11 / 18,13,11 / 00,00,00, i.e. white, tan, dark brown,
-- black.  Used when the cache predates the extractor emitting the palette; the
-- same inline transcription src/ui/gen2/GameFreakPresents.lua keeps.
UnownPuzzle.PALETTE = {
  { 255, 255, 255 }, { 197, 165, 90 }, { 148, 107, 90 }, { 0, 0, 0 },
}
-- _CGB_UnownPuzzle loads the same palette into wOBPals1 and then overwrites
-- OBJ colour 0 with `palred 31` (pure red); _UnownPuzzle's `ld a, $24 / call
-- DmgToCgbObjPal0` reorders that to entries 0, 1, 2, 0.  The cursor sheet uses
-- colours 0 and 3, so the bracket comes out red on both.
UnownPuzzle.CURSOR_PALETTE = {
  { 255, 0, 0 }, { 197, 165, 90 }, { 148, 107, 90 }, { 255, 0, 0 },
}

UnownPuzzle.COLUMNS = 6
UnownPuzzle.ROWS = 6
UnownPuzzle.CELLS = 36
UnownPuzzle.PIECES = 16
-- A cell is 3x3 tiles, and the sheet lays the sixteen panels 4 across.
UnownPuzzle.PIECE_TILES = 3
UnownPuzzle.PIECES_WIDE = 4

-- `DEF puzcoord EQUS "* 6 +"`: the cart addresses a cell as row * 6 + column,
-- 0-based, and every cursor rule below is a comparison against one of those.
local function puzcoord(row, col) return row * UnownPuzzle.COLUMNS + col end
UnownPuzzle.puzcoord = puzcoord

-- .PuzzlePieceInitialPositions: the sixteen cells a panel may start on.  All of
-- row 0, then both ends of rows 1 through 5.
UnownPuzzle.START_CELLS = (function()
  local out = {}
  for col = 0, 5 do out[#out + 1] = puzcoord(0, col) end
  for row = 1, 5 do
    out[#out + 1] = puzcoord(row, 0)
    out[#out + 1] = puzcoord(row, 5)
  end
  return out
end)()

-- .SolvedPuzzleConfiguration, written out the way the ASM writes it: the ring
-- empty, 1..16 filling the interior in reading order.
UnownPuzzle.SOLVED = {
  0, 0, 0, 0, 0, 0,
  0, 1, 2, 3, 4, 0,
  0, 5, 6, 7, 8, 0,
  0, 9, 10, 11, 12, 0,
  0, 13, 14, 15, 16, 0,
  0, 0, 0, 0, 0, 0,
}

-- SFX_*, in pokegold's own labels; Gold's sfx table is keyed by those.
local SFX_MOVE_CURSOR = "Sfx_Pound"
local SFX_MOVE_PIECE = "Sfx_MovePuzzlePiece"
local SFX_PICK_UP = "Sfx_MegaKick"
local SFX_PUT_DOWN = "Sfx_PlacePuzzlePieceDown"
local SFX_WRONG = "Sfx_Wrong"
local SFX_SOLVED = "Sfx_1stPlace"

-- JoyTextDelay with hInMenu set reads hJoyDown, so the d-pad REPEATS: a fresh
-- press reloads wTextDelayFrames with 15 and every repeat after that with 5.
local REPEAT_DELAY = 15
local REPEAT_RATE = 5

-- The ten caption tiles ($f6..$ff) spell START▶CANCEL; the same words are
-- printed with the font when the sheet is not in the cache.  Declared here and
-- looked up at the draw site, which is what Strings.source marks.
UnownPuzzle.CAPTION = Strings.source("START>CANCEL")

-- ---------------------------------------------------------------- the board
--
-- InitUnownPuzzlePiecePositions: sixteen panels are dealt, `call Random / and
-- $f` into the initial-position list, rerolling while the cell it picks is
-- already taken.  `random(n)` is 0..n-1, the src/battle/gen2 convention.
--
-- The cart's reroll is unbounded; it cannot hang because hRandomAdd is never
-- degenerate.  Here the retries are capped and the fallback drops the panel in
-- the first free start cell, so a fixed RNG in a test deals a legal board
-- instead of spinning.
local DEAL_RETRIES = 512

function UnownPuzzle.deal(random)
  local pieces = {}
  for cell = 1, UnownPuzzle.CELLS do pieces[cell] = 0 end
  for piece = 1, UnownPuzzle.PIECES do
    local cell, tries = nil, 0
    repeat
      cell = UnownPuzzle.START_CELLS[random(16) + 1]
      tries = tries + 1
    until pieces[cell + 1] == 0 or tries >= DEAL_RETRIES
    if pieces[cell + 1] ~= 0 then
      for _, candidate in ipairs(UnownPuzzle.START_CELLS) do
        if pieces[candidate + 1] == 0 then cell = candidate break end
      end
    end
    pieces[cell + 1] = piece
  end
  return pieces
end

-- CheckSolvedUnownPuzzle: a byte-for-byte compare against
-- .SolvedPuzzleConfiguration.  With exactly sixteen panels on the board this is
-- the same thing as "the interior is 1..16", but the compare is transcribed
-- rather than replaced so a board that ever held a different number of panels
-- would still answer correctly.
function UnownPuzzle.isSolved(pieces)
  for cell = 1, UnownPuzzle.CELLS do
    if (pieces[cell] or 0) ~= UnownPuzzle.SOLVED[cell] then return false end
  end
  return true
end

-- .d_up / .d_down / .d_left / .d_right, each transcribed as its own list of
-- refusals.  They are NOT a rectangle: row 5 has only its two end cells (the
-- START>CANCEL box occupies the middle of it), so left from cell 35 jumps
-- straight to 30 and right from 30 jumps straight to 35, and row 4's four
-- interior cells cannot go down at all.
--
-- Returns the new position, or nil when the move is refused (`ret` in the ASM,
-- which also skips the cursor SFX).
function UnownPuzzle.moveCursor(position, direction)
  local pos = position or 0
  if direction == "up" then
    if pos < puzcoord(1, 0) then return nil end
    return pos - UnownPuzzle.COLUMNS
  elseif direction == "down" then
    for col = 1, 4 do
      if pos == puzcoord(4, col) then return nil end
    end
    if pos >= puzcoord(5, 0) then return nil end
    return pos + UnownPuzzle.COLUMNS
  elseif direction == "left" then
    if pos == 0 then return nil end
    for row = 1, 5 do
      if pos == puzcoord(row, 0) then return nil end
    end
    if pos == puzcoord(5, 5) then return puzcoord(5, 0) end
    return pos - 1
  elseif direction == "right" then
    for row = 0, 5 do
      if pos == puzcoord(row, 5) then return nil end
    end
    if pos == puzcoord(5, 0) then return puzcoord(5, 5) end
    return pos + 1
  end
  return nil
end

-- UnownPuzzleCoordData's `dwcoord` column: cell i is a 3x3 tile block whose
-- top-left corner is (1 + 3 * column, 3 * row).
function UnownPuzzle.cellTile(cell)
  local row = math.floor(cell / UnownPuzzle.COLUMNS)
  local col = cell % UnownPuzzle.COLUMNS
  return 1 + col * UnownPuzzle.PIECE_TILES, row * UnownPuzzle.PIECE_TILES
end

-- The same table's "vacant tile" column: the interior 4x4 clears to
-- PUZZLE_VOID, everything on the ring clears back to PUZZLE_BORDER.
function UnownPuzzle.vacantTile(cell)
  local row = math.floor(cell / UnownPuzzle.COLUMNS)
  local col = cell % UnownPuzzle.COLUMNS
  if row >= 1 and row <= 4 and col >= 1 and col <= 4 then
    return UnownPuzzle.VOID_TILE
  end
  return UnownPuzzle.BORDER_TILE
end

-- ------------------------------------------------------------- the screen
--
-- opts: puzzle (the UNOWNPUZZLE_* id the script's `setval` carried), save,
-- random(n) -> 0..n-1, onClose(solved).
function UnownPuzzle.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, UnownPuzzle)
  self.game = game
  self.onClose = opts.onClose
  self.puzzle = opts.puzzle or 0
  self.random = opts.random or function(n)
    if love and love.math and love.math.random then
      return love.math.random(n) - 1
    end
    return math.random(n) - 1
  end
  -- `ld hl, STARTOF("Miscellaneous") ... call ByteFill` zeroes the whole block
  -- wPuzzlePieces lives in, so every run starts from a clean board and a
  -- cursor at cell 0.
  self.pieces = UnownPuzzle.deal(self.random)
  self.cursor = 0
  self.holding = false
  self.held = 0
  self.solved = false
  self.frame = 0
  self.repeatLeft = 0
  self.lastDirection = nil
  -- The solve fanfare parks on SimpleWaitPressAorB before the screen closes.
  self.waiting = false
  self:loadGfx()
  return self
end

function UnownPuzzle:gfx()
  local data = self.game and self.game.data
  local menu = data and data.gen2MenuGfx
  return menu and menu.unownPuzzle or nil
end

function UnownPuzzle:loadGfx()
  local gfx = self:gfx()
  -- The palettes stand on their own: the board is coloured even on the
  -- art-less degrade, because the cart's colour comes from _CGB_UnownPuzzle
  -- and not from any sheet.
  self.palette = (gfx and gfx.palette) or UnownPuzzle.PALETTE
  self.cursorPalette = (gfx and gfx.cursorPalette)
    or UnownPuzzle.CURSOR_PALETTE
  if not gfx then return end
  self.chrome = TileSheet.new({
    path = gfx.chrome,
    wide = gfx.chromeTiles or 19,
    firstTile = gfx.chromeFirstTile or 0xed,
    palette = self.palette,
  })
  -- `and` would truncate pcall's second return, so the two loads cannot fold
  -- into one-liners.
  local path = gfx.pictures and gfx.pictures[(self.puzzle % 4) + 1]
  if path then
    local ok, image = pcall(Assets.image, path)
    if ok and image then self.picture = image end
  end
  if gfx.cursor then
    local ok, image = pcall(Assets.image, gfx.cursor)
    if ok and image then self.cursorSheet = image end
  end
end

function UnownPuzzle:sfx(name)
  local data = self.game and self.game.data
  if data then Sound.play(data, name) end
end

-- UnownPuzzle_CheckCurrentTileOccupancy: `wPuzzlePieces + wUnownPuzzleCursorPosition`.
function UnownPuzzle:occupant(cell)
  return self.pieces[(cell or self.cursor) + 1] or 0
end

-- UnownPuzzle_A.  Two arms, and both of them refuse loudly rather than
-- silently: an empty cell with nothing held, or an occupied cell with a panel
-- held, is UnownPuzzle_InvalidAction (SFX_WRONG) and nothing moves.
function UnownPuzzle:pressA()
  if not self.holding then
    local piece = self:occupant()
    if piece == 0 then
      self:sfx(SFX_WRONG)
      return
    end
    self:sfx(SFX_PICK_UP)
    self.pieces[self.cursor + 1] = 0
    self.held = piece
    self.holding = true
    return
  end
  if self:occupant() ~= 0 then
    self:sfx(SFX_WRONG)
    return
  end
  self:sfx(SFX_PUT_DOWN)
  self.pieces[self.cursor + 1] = self.held
  self.held = 0
  self.holding = false
  if not UnownPuzzle.isSolved(self.pieces) then return end
  -- The solve: the caption is blanked (PlaceStartCancelBoxBorder is called
  -- again WITHOUT PlaceStartCancelBox), the cursor is cleared, and the screen
  -- holds on the fanfare until A or B.
  self.solved = true
  self.waiting = true
  self:sfx(SFX_SOLVED)
end

function UnownPuzzle:quit()
  if self.closed then return end
  self.closed = true
  if self.onClose then self.onClose(self.solved) end
end

-- .done_joypad: the SFX depends on whether a panel is riding the cursor, and
-- it only plays on a move that actually happened.
function UnownPuzzle:step(direction)
  local target = UnownPuzzle.moveCursor(self.cursor, direction)
  if not target then return false end
  self.cursor = target
  self:sfx(self.holding and SFX_MOVE_PIECE or SFX_MOVE_CURSOR)
  return true
end

local DIRECTIONS = { "up", "down", "left", "right" }

function UnownPuzzle:update(_dt)
  self.frame = self.frame + 1
  local input = self.game and self.game.input
  if not input then return end
  if self.waiting then
    -- SimpleWaitPressAorB, then UnownPuzzle_Quit falls through with
    -- wSolvedUnownPuzzle already TRUE.
    if input:wasPressed("a") or input:wasPressed("b") then self:quit() end
    return
  end
  if input:wasPressed("start") then
    self:quit()
    return
  end
  if input:wasPressed("a") then
    self:pressA()
    return
  end
  -- The d-pad repeat, on JoyTextDelay's own 15-then-5 frame counts.
  local held = nil
  for _, direction in ipairs(DIRECTIONS) do
    if input:wasPressed(direction) then
      held = direction
      self.lastDirection = direction
      self.repeatLeft = REPEAT_DELAY
      self:step(direction)
      return
    end
  end
  for _, direction in ipairs(DIRECTIONS) do
    if input.isDown and input:isDown(direction) then held = held or direction end
  end
  if held ~= self.lastDirection then
    self.lastDirection = held
    self.repeatLeft = REPEAT_DELAY
    return
  end
  if not held then return end
  self.repeatLeft = self.repeatLeft - 1
  if self.repeatLeft > 0 then return end
  self.repeatLeft = REPEAT_RATE
  self:step(held)
end

-- ---------------------------------------------------------------- drawing
--
-- Everything here is 8px tile coordinates, and everything without art falls
-- back to a labelled cell rather than to nothing.
local BOX_X, BOX_Y = 4, 15
local BOX_RIGHT = 15
local CAPTION_X, CAPTION_Y = 5, 16
local CAPTION_TILES = 10
local CAPTION_FIRST = 0xf6
-- PlaceStartCancelBoxBorder's six corner and edge tiles.
local BOX_TOP_LEFT, BOX_TOP, BOX_TOP_RIGHT = 0xf0, 0xf1, 0xf2
local BOX_SIDE, BOX_BOTTOM_LEFT, BOX_BOTTOM_RIGHT = 0xf3, 0xf4, 0xf5

-- The board is BROWN, not grey.  _CGB_UnownPuzzle (engine/gfx/cgb_layouts.asm)
-- runs CopyFourPalettes over PalPacket_UnownPuzzle, which is
-- PREDEFPAL_UNOWN_PUZZLE four times, and then WipeAttrmap puts every tile on BG
-- palette 0 -- so the whole screen wears white / tan / dark brown / black.  The
-- later `ld a, $e4 / call DmgToCgbBGPals` is the IDENTITY reorder of that
-- palette (home/palettes.asm CopyPals), not a grey ramp of its own.
local function paletteColor(colors, index)
  local c = GbcPalette.color(colors, index)
  return (c[1] or 0) / 255, (c[2] or 0) / 255, (c[3] or 0) / 255
end

function UnownPuzzle:drawTile(tile, tx, ty)
  if self.chrome and self.chrome:draw(tile, tx, ty) then return true end
  local G = love.graphics
  if tile == UnownPuzzle.VOID_TILE then
    G.setColor(paletteColor(self.palette, 1))
  else
    G.setColor(paletteColor(self.palette, 3))
  end
  G.rectangle("fill", tx * 8, ty * 8, 8, 8)
  G.setColor(0, 0, 0, 1)
  return false
end

function UnownPuzzle:fillCell(cell, tile)
  local tx, ty = UnownPuzzle.cellTile(cell)
  for row = 0, UnownPuzzle.PIECE_TILES - 1 do
    for col = 0, UnownPuzzle.PIECE_TILES - 1 do
      self:drawTile(tile, tx + col, ty + row)
    end
  end
end

-- .Corners is `piece -> corner tile` on a 12-tile-wide sheet; as a quad that is
-- just the panel's row and column in the 4x4 picture.
function UnownPuzzle:drawPiece(piece, tx, ty)
  local size = UnownPuzzle.PIECE_TILES * 8
  if self.picture then
    local index = piece - 1
    local sx = (index % UnownPuzzle.PIECES_WIDE) * size
    local sy = math.floor(index / UnownPuzzle.PIECES_WIDE) * size
    local w, h = self.picture:getDimensions()
    local quad = love.graphics.newQuad(sx, sy, size, size, w, h)
    love.graphics.setColor(1, 1, 1, 1)
    -- The four pictures are drawn out of colours 1 and 2 alone, so binding BG
    -- palette 0 here is what turns the panels tan and dark brown.
    local function body()
      love.graphics.draw(self.picture, quad, tx * 8, ty * 8)
    end
    if self.palette and GbcPalette.available() then
      GbcPalette.with(self.palette, body)
    else
      body()
    end
    love.graphics.setColor(0, 0, 0, 1)
    return
  end
  local G = love.graphics
  G.setColor(paletteColor(self.palette, 2))
  G.rectangle("fill", tx * 8, ty * 8, size, size)
  G.setColor(0, 0, 0, 1)
  G.rectangle("line", tx * 8 + 0.5, ty * 8 + 0.5, size - 1, size - 1)
  Chrome.print(tostring(piece), tx + 1, ty + 1)
end

-- The cursor's four OBJ tiles, mirrored into a 3x3 bracket by
-- .OAM_NotHoldingPiece: tile 0 is the corner, 1 the top and bottom edge, 2 the
-- left and right edge, 3 the centre.
local CURSOR_CELLS = {
  { 0, 0, 0, false, false }, { 1, 1, 0, false, false },
  { 2, 0, 0, true, false },
  { 0, 0, 1, false, false }, { 1, 3, 1, false, false },
  { 2, 0, 1, true, false },
  { 0, 0, 2, false, true }, { 1, 1, 2, false, true },
  { 2, 0, 2, true, true },
}

function UnownPuzzle:drawCursor(tx, ty)
  local G = love.graphics
  if not self.cursorSheet then
    G.setColor(paletteColor(self.cursorPalette, 4))
    G.rectangle("line", tx * 8 + 0.5, ty * 8 + 0.5, 23, 23)
    G.setColor(0, 0, 0, 1)
    return
  end
  local w, h = self.cursorSheet:getDimensions()
  G.setColor(1, 1, 1, 1)
  local function body()
    for _, spec in ipairs(CURSOR_CELLS) do
      local col, tile, row, flipX, flipY = spec[1], spec[2], spec[3], spec[4],
        spec[5]
      local quad = love.graphics.newQuad(tile * 8, 0, 8, 8, w, h)
      local sx, sy = flipX and -1 or 1, flipY and -1 or 1
      local ox = (tx + col) * 8 + (flipX and 8 or 0)
      local oy = (ty + row) * 8 + (flipY and 8 or 0)
      G.draw(self.cursorSheet, quad, ox, oy, 0, sx, sy)
    end
  end
  -- OBJ palette 0, whose colours 0 and 3 are both the red _CGB_UnownPuzzle
  -- forces in: the bracket's sheet uses only those two, so it draws red.
  if self.cursorPalette and GbcPalette.available() then
    GbcPalette.with(self.cursorPalette, body)
  else
    body()
  end
  G.setColor(0, 0, 0, 1)
end

function UnownPuzzle:drawStartCancel()
  self:drawTile(BOX_TOP_LEFT, BOX_X, BOX_Y)
  for tx = BOX_X + 1, BOX_RIGHT - 1 do self:drawTile(BOX_TOP, tx, BOX_Y) end
  self:drawTile(BOX_TOP_RIGHT, BOX_RIGHT, BOX_Y)
  self:drawTile(BOX_SIDE, BOX_X, BOX_Y + 1)
  for tx = BOX_X + 1, BOX_RIGHT - 1 do
    self:drawTile(UnownPuzzle.VOID_TILE, tx, BOX_Y + 1)
  end
  self:drawTile(BOX_SIDE, BOX_RIGHT, BOX_Y + 1)
  self:drawTile(BOX_BOTTOM_LEFT, BOX_X, BOX_Y + 2)
  for tx = BOX_X + 1, BOX_RIGHT - 1 do self:drawTile(BOX_TOP, tx, BOX_Y + 2) end
  self:drawTile(BOX_BOTTOM_RIGHT, BOX_RIGHT, BOX_Y + 2)
  -- On the solve the border is redrawn without the caption, so the box empties.
  if self.solved then return end
  local drew = false
  if self.chrome then
    drew = self.chrome:available()
    for i = 0, CAPTION_TILES - 1 do
      self.chrome:draw(CAPTION_FIRST + i, CAPTION_X + i, CAPTION_Y)
    end
  end
  if not drew then
    Chrome.print(Strings(UnownPuzzle.CAPTION), CAPTION_X, CAPTION_Y)
  end
end

function UnownPuzzle:drawPanel()
  Chrome.clear()
  for ty = 0, Chrome.SCREEN_H - 1 do
    for tx = 0, Chrome.SCREEN_W - 1 do
      self:drawTile(UnownPuzzle.BORDER_TILE, tx, ty)
    end
  end
  for cell = 0, UnownPuzzle.CELLS - 1 do
    local tx, ty = UnownPuzzle.cellTile(cell)
    local piece = self:occupant(cell)
    if piece ~= 0 then
      self:drawPiece(piece, tx, ty)
    else
      self:fillCell(cell, UnownPuzzle.vacantTile(cell))
    end
  end
  self:drawStartCancel()
  if self.solved then return end
  local tx, ty = UnownPuzzle.cellTile(self.cursor)
  if self.holding then
    -- .OAM_HoldingPiece: the panel rides the cursor and is drawn every frame.
    if self.held ~= 0 then self:drawPiece(self.held, tx, ty) end
  elseif math.floor(self.frame / 16) % 2 == 0 then
    -- `ldh a, [hVBlankCounter] / and $10`: sixteen frames on, sixteen off.
    self:drawCursor(tx, ty)
  end
end

function UnownPuzzle:draw()
  self:drawPanel()
end

-- The puzzle owns the whole screen: engine/games/unown_puzzle.asm:11 is
-- ClearBGPalettes / ClearTilemap, so nothing of the map survives behind it and
-- the PUZZLE_BORDER black below is the real surround, not a letterbox filler.
function UnownPuzzle:drawsWidescreen() return true end

function UnownPuzzle:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(0, 0, 0, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return UnownPuzzle
