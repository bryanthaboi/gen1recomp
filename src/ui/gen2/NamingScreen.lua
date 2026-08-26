-- Gen 2 naming screen: the on-screen keyboard Gold uses for the player, the
-- rival, mom, a box, and mon nicknames.  Ported from
-- engine/menus/naming_screen.asm.
--
-- Layout (tile coords, transcribed from the ASM's hlcoord calls):
--   whole screen filled with NAMINGSCREEN_BORDER
--   (1,1) 6x18 cleared  -- header: icon, prompt at (5,2), entry field at (5,6)
--   (1,8) 7x18 cleared  -- keyboard: 5 rows at y = 8,10,12,14,16
--   letters at x = 2,4,...,18 (nine per row)
--   NAME_BOX gets a sixth row and a shorter header (4x18 / 9x18 at y=6)
--
-- Cursor grid is 9 wide by 5 rows (6 for a box).  The bottom row is not nine
-- letters but three fat targets -- case switch, DEL, END -- which is why the
-- ASM keeps a separate x-offset table for it (.CaseDelEnd: $00,$00,$00,
-- $30,$30,$30,$60,$60,$60) instead of the even $10 steps letters use.
--
-- SELECT toggles case anywhere; START jumps the cursor onto END; B deletes.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local GbcPalette = require("src.render.GbcPalette")
local Runtime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")

local NamingScreen = {}
NamingScreen.__index = NamingScreen
NamingScreen.isOpaque = true

-- data/text/name_input_chars.asm.  Each row is a 17-character string with the
-- letters on the even columns, so cell N is the character at index N*2 - 1.
-- Rows whose cells are not single characters (the box screen's dakuten pairs
-- and multi-byte glyphs) are written out as arrays instead.
local function rowCells(row)
  local out = {}
  for i = 1, 9 do
    local ch = row:sub(i * 2 - 1, i * 2 - 1)
    out[i] = ch
  end
  return out
end

local NAME_INPUT_UPPER = {
  rowCells("A B C D E F G H I"),
  rowCells("J K L M N O P Q R"),
  rowCells("S T U V W X Y Z  "),
  rowCells("- ? ! / . ,      "),
}
local NAME_INPUT_LOWER = {
  rowCells("a b c d e f g h i"),
  rowCells("j k l m n o p q r"),
  rowCells("s t u v w x y z  "),
  { "\xc3\x97", "(", ")", ":", ";", "[", "]", "<PK>", "<MN>" },
}
-- BOX_NAME gets one extra symbol row in each case (BoxNameInput*).
local BOX_INPUT_UPPER = {
  NAME_INPUT_UPPER[1], NAME_INPUT_UPPER[2], NAME_INPUT_UPPER[3],
  { "\xc3\x97", "(", ")", ":", ";", "[", "]", "<PK>", "<MN>" },
  { "-", "?", "!", "\xe2\x99\x82", "\xe2\x99\x80", "/", ".", ",", "&" },
}
local BOX_INPUT_LOWER = {
  NAME_INPUT_LOWER[1], NAME_INPUT_LOWER[2], NAME_INPUT_LOWER[3],
  { "\xc3\xa9", "'d", "'l", "'m", "'r", "'s", "'t", "'v", "0" },
  { "1", "2", "3", "4", "5", "6", "7", "8", "9" },
}

-- The bottom row's three targets and the columns their labels start at.  The
-- case target names the board it SWITCHES TO, not the one it is on: the last
-- row of NameInputUpper is "lower  DEL   END" and the last row of
-- NameInputLower is "UPPER  DEL   END" (data/text/name_input_chars.asm).
-- Wrapped in Strings.source, not Strings: both tables are built once at
-- require time, before any mod's Strings.load has a catalog to answer from
-- (src/core/Strings.lua's own note on this); drawPanel resolves them live.
local BOTTOM_UPPER_LABELS = {
  Strings.source("lower"), Strings.source("DEL"), Strings.source("END"),
}
local BOTTOM_LOWER_LABELS = {
  Strings.source("UPPER"), Strings.source("DEL"), Strings.source("END"),
}
-- Cursor tile for each target: NamingScreen_AnimateCursor's .CaseDelEnd adds
-- pixel $00 / $30 / $60 to the cursor's own XCOORD of 24 (`depixel 10, 3`),
-- which is OAM x 24 / 72 / 120 and so screen tile 2 / 8 / 14.  The bracket is
-- five tiles wide there, so it wraps the whole label rather than sitting left
-- of it.
local BOTTOM_CURSOR_TX = { 2, 8, 14 }
local BOTTOM_LABEL_TX = { 2, 9, 15 }
local BOTTOM_CURSOR_TILES = 5

-- NAME_* types (constants/menu_constants.asm order) as prompts + field sizes.
-- Lengths are the ASM's *_NAME_LENGTH - 1, i.e. usable characters.
NamingScreen.TYPES = {
  player = { prompt = Strings.source("YOUR NAME?"), maxLength = 7,
    sprite = "SPRITE_CHRIS", spriteFemale = "SPRITE_KRIS" },
  rival = { prompt = Strings.source("RIVAL'S NAME?"), maxLength = 7, sprite = "SPRITE_RIVAL" },
  mom = { prompt = Strings.source("MOTHER'S NAME?"), maxLength = 7, sprite = "SPRITE_MOM" },
  box = { prompt = Strings.source("BOX NAME?"), maxLength = 8, isBox = true },
  nickname = { prompt = nil, maxLength = 10 },
}

-- GetPlayerIcon's two sheets (../pokecrystal/engine/gfx/player_gfx.asm:85-93),
-- which is also the pair the header icon here is cut from.
function NamingScreen.playerSprite(gender)
  local kind = NamingScreen.TYPES.player
  if gender == "female" and kind.spriteFemale then return kind.spriteFemale end
  return kind.sprite
end

function NamingScreen:wantsFillScale() return true end
function NamingScreen:drawsWidescreen() return true end

-- opts: type ("player"/"rival"/"mom"/"box"/"nickname"), prompt, maxLength,
-- initial, monName (nickname header), icon/sprite image path, gender,
-- onDone(name), onCancel().
function NamingScreen.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, NamingScreen)
  self.game = game
  local kind = NamingScreen.TYPES[opts.type or "player"]
    or NamingScreen.TYPES.player
  self.kind = kind
  self.gender = opts.gender
    or (game and game.save and game.save.player and game.save.player.gender)
  self.isBox = opts.isBox or kind.isBox or false
  self.maxLength = opts.maxLength or kind.maxLength or 7
  self.prompt = opts.prompt or kind.prompt or Strings.source("NICKNAME?")
  self.monName = opts.monName
  self.onDone = opts.onDone
  self.onCancel = opts.onCancel
  self.lower = false -- wNamingScreenLetterCase; upper first
  self.text = opts.initial or ""
  self.col = 0
  self.row = 0
  self.iconImage = nil
  if opts.iconPath then
    local ok, img = pcall(Assets.image, opts.iconPath)
    if ok then self.iconImage = img end
  end
  -- The header icon is an OBJ on the cart, so it wears a real palette; without
  -- one it would draw in raw DMG shades next to a colored world.
  self.iconColors = opts.iconColors
  local data = game and game.data or {}
  self.gfx = opts.menuGfx or data.gen2MenuGfx
  if self.gfx and self.gfx.naming then self.gfx = self.gfx.naming end
  -- engine/menus/naming_screen.asm:47
  -- engine/gfx/cgb_layouts.asm:488
  local diploma = data.gen2Diploma
  self.palette = diploma and diploma.palettes and diploma.palettes[1]
  self.tiles = {}
  if self.gfx then
    for _, key in ipairs({ "border", "middleLine", "underLine", "cursor" }) do
      if self.gfx[key] then
        local ok, img = pcall(Assets.image, self.gfx[key])
        if ok then self.tiles[key] = img end
      end
    end
  end
  return self
end

-- ui.naming.grid identity: unhooked, the board is the one the cart ships.
local function sameGrid(grid) return grid end

-- The letter rows of the page that is showing, through the ui.naming.grid hook
-- -- the same name and the same (grid, ctx) payload the Gen 1 screen uses
-- (src/ui/NamingScreen.lua), so a mod that splices digits onto a row does it
-- once for both generations.  Guarded with wantsHook because update and draw
-- both read the board every frame; unhooked this is the module's own table.
--
-- Only the LETTER rows travel through the hook.  Gold keeps the case / DEL /
-- END targets off the board entirely, in a fat bottom row of their own
-- (NamingScreen_AnimateCursor's .CaseDelEnd), so unlike Gen 1 there is no meta
-- cell a hooked grid could drop -- but bottomRow() counts the rows it answers
-- with, so a page carrying an extra row still keeps those targets under it.
function NamingScreen:rows()
  local base
  if self.isBox then
    base = self.lower and BOX_INPUT_LOWER or BOX_INPUT_UPPER
  else
    base = self.lower and NAME_INPUT_LOWER or NAME_INPUT_UPPER
  end
  if not Runtime.wantsHook("ui.naming.grid") then return base end
  local hooked = Runtime.call("ui.naming.grid", sameGrid, base, {
    lower = self.lower and true or false,
    -- `title` is the Gen 1 key for the line above the entry field; here that
    -- is the prompt ("YOUR NAME?").  `box` is Gen 2's own: a BOX NAME page has
    -- a row the name pages do not.
    title = self.prompt,
    maxLen = self.maxLength,
    box = self.isBox,
    game = self.game,
  })
  if type(hooked) ~= "table" or #hooked == 0 then return base end
  return hooked
end

-- The keyboard's first row, and the row index the bottom (case/DEL/END) row
-- sits at.  A box screen shifts everything up two rows to fit its sixth row.
function NamingScreen:keyboardTop()
  return self.isBox and 6 or 8
end

-- One past the last letter row: four on a name page, five on a box one, and
-- whatever a hooked grid answers with (see rows()).
function NamingScreen:bottomRow()
  return #self:rows()
end

function NamingScreen:onBottomRow()
  return self.row == self:bottomRow()
end

-- Which of the three fat targets the cursor is on (1 case, 2 delete, 3 end),
-- mirroring NamingScreen_GetCursorPosition's `cp $3 / cp $6` split.
function NamingScreen:bottomTarget()
  if self.col < 3 then return 1 end
  if self.col < 6 then return 2 end
  return 3
end

-- A blank cell is a real SPACE, not a dead key.  ApplyTextInputMode writes the
-- NameInput* rows straight into the tilemap and NamingScreen_GetLastCharacter
-- reads the tile UNDER the cursor back out of it (hlcoord 0,0 + row*SCREEN_WIDTH
-- + col), so the trailing blanks in "S T U V W X Y Z  " and "- ? ! / . ,      "
-- (data/text/name_input_chars.asm) type a space like any other character.  Only
-- a cell that is not on the board at all answers nil.  Trimming is not this
-- screen's job either: it stores what was typed and InitName decides whether
-- the result counts as blank (home/string.asm:6-30).
function NamingScreen:characterAt(col, row)
  local grid = self:rows()
  local line = grid[row + 1]
  local ch = line and line[col + 1]
  if not ch or ch == "" then return nil end
  return ch
end

function NamingScreen:addCharacter(ch)
  if not ch then return end
  if #self.text >= self.maxLength then return end
  self.text = self.text .. ch
end

function NamingScreen:deleteCharacter()
  if #self.text == 0 then return end
  self.text = self.text:sub(1, #self.text - 1)
end

function NamingScreen:toggleCase()
  self.lower = not self.lower
end

function NamingScreen:accept()
  local name = self.text
  if self.onDone then self.onDone(name) end
end

-- Cursor movement.  On the letter rows the columns step one at a time and wrap
-- (.right / .wrap_left); on the bottom row left/right hop between the three
-- targets, which the ASM does by rounding the column to a multiple of three.
function NamingScreen:moveHorizontal(delta)
  if self:onBottomRow() then
    local target = self:bottomTarget() + delta
    if target < 1 then target = 3 end
    if target > 3 then target = 1 end
    self.col = (target - 1) * 3
    return
  end
  self.col = self.col + delta
  if self.col < 0 then self.col = 8 end
  if self.col > 8 then self.col = 0 end
end

function NamingScreen:moveVertical(delta)
  local last = self:bottomRow()
  self.row = self.row + delta
  if self.row < 0 then self.row = last end
  if self.row > last then self.row = 0 end
  -- Coming onto the bottom row from a letter column lands on a target rather
  -- than between two.
  if self:onBottomRow() then
    self.col = (self:bottomTarget() - 1) * 3
  end
end

function NamingScreen:update(_dt)
  local input = self.game and self.game.input
  if not input then return end

  if input:wasPressed("left") then
    self:moveHorizontal(-1)
    return
  elseif input:wasPressed("right") then
    self:moveHorizontal(1)
    return
  elseif input:wasPressed("up") then
    self:moveVertical(-1)
    return
  elseif input:wasPressed("down") then
    self:moveVertical(1)
    return
  elseif input:wasPressed("select") then
    self:toggleCase()
    return
  elseif input:wasPressed("start") then
    -- .start parks the cursor on END (var1 = $8, var2 = last row).
    self.row = self:bottomRow()
    self.col = 6
    return
  elseif input:wasPressed("b") then
    -- B is delete, not cancel: the only way out is END (or an empty name,
    -- which callers treat as "keep the default").
    self:deleteCharacter()
    return
  elseif input:wasPressed("a") then
    if self:onBottomRow() then
      local target = self:bottomTarget()
      if target == 1 then
        self:toggleCase()
      elseif target == 2 then
        self:deleteCharacter()
      else
        self:accept()
      end
      return
    end
    self:addCharacter(self:characterAt(self.col, self.row))
    -- Filling the last slot does NOT end entry.  `.a` is
    -- `call NamingScreen_TryAddCharacter / ret nc`, and
    -- NamingScreen_AdvanceCursor_CheckEndOfString returns CARRY when the buffer
    -- just filled, so the handler falls through into `.start` and parks the
    -- cursor on END (VAR1 $8, VAR2 the bottom row) with the screen still
    -- running (engine/menus/naming_screen.asm:401-410).  Only `.end`, i.e. A
    -- pressed on END, stores the entry and sets JUMPTABLE_EXIT_F.  Pressing A
    -- on a letter again is already a no-op here, matching
    -- MailComposition_TryAddCharacter's `cp c / ret nc`.
    if #self.text >= self.maxLength then
      self.row = self:bottomRow()
      self.col = 6
    end
    return
  end
end

function NamingScreen:paperColor()
  return GbcPalette.color(self.palette, 1)
end

-- The backdrop: one patterned tile repeated over the whole screen.  Without
-- menu_gfx.lua (older cache) fall back to a flat mid gray, which keeps the
-- cleared panels readable.
function NamingScreen:drawBackdrop()
  local G = love.graphics
  local tile = self.tiles.border
  if not tile then
    local paper = self:paperColor()
    G.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
    G.rectangle("fill", 0, 0, 160, 144)
    G.setColor(1, 1, 1, 1)
    return
  end
  local function blit()
    G.setColor(1, 1, 1, 1)
    for ty = 0, Chrome.SCREEN_H - 1 do
      for tx = 0, Chrome.SCREEN_W - 1 do
        G.draw(tile, tx * 8, ty * 8)
      end
    end
  end
  if self.palette and GbcPalette.available() then
    GbcPalette.with(self.palette, blit)
  else
    blit()
  end
end

-- The cursor (data/sprite_anims/oam.asm .OAMData_TextEntryCursor and
-- .OAMData_TextEntryCursorBig).  It is not an arrow beside the character: it is
-- a box drawn AROUND the cell, stamped out of gfx/naming_screen/cursor.2bpp
-- tile $00 -- one corner carrying a top edge and a left edge -- four times with
-- X/Y flips.  The wide bottom-row bracket repeats tile $01 (top edge alone)
-- between the two corner pairs.
--
-- The frame offsets sit the top and left edges one pixel outside the cell
-- (`dbsprite -1, -1, 7, 7` is dy/dx = -1), while the flipped copies put the
-- bottom and right edges on the cell's last pixel row and column.  Sprite
-- coordinates are OAM's, so XCOORD 24 / YCOORD 80 is screen (16, 64): the
-- first letter's own tile, not the gutter left of it.
local CURSOR_TILE_H = 8

-- Where the bracket sits, in tiles, plus how many tiles wide it is:
-- .LetterEntries steps XOFFSET by $10 a column and AnimateCursor swaps the row
-- into YOFFSET (row * $10), so the letter rows land on the character's own
-- tile.  Split out from the draw so a test can read it without a canvas.
function NamingScreen:cursorTile()
  if self:onBottomRow() then
    return BOTTOM_CURSOR_TX[self:bottomTarget()],
      self:keyboardTop() + self:bottomRow() * 2, BOTTOM_CURSOR_TILES
  end
  return 2 + self.col * 2, self:keyboardTop() + self.row * 2, 1
end

function NamingScreen:drawCursorTile(quad, x, y, flipX, flipY)
  love.graphics.draw(self.tiles.cursor, quad, x, y, 0,
    flipX and -1 or 1, flipY and -1 or 1,
    flipX and 8 or 0, flipY and CURSOR_TILE_H or 0)
end

function NamingScreen:drawCursorBox(tx, ty, tilesWide)
  local G = love.graphics
  local sheet = self.tiles.cursor
  if not sheet then
    -- No extracted cursor art: the shared ▶ in the gutter left of the cell.
    Chrome.cursor(tx - 1, ty)
    return
  end
  G.setColor(1, 1, 1, 1)
  -- Both quads are cut once and kept: this runs every frame the keyboard is
  -- up, and a fresh Quad per draw churns the GC.
  if not self.cursorQuads then
    local sw, sh = sheet:getDimensions()
    local corner = love.graphics.newQuad(0, 0, 8, CURSOR_TILE_H, sw, sh)
    self.cursorQuads = {
      corner = corner,
      edge = sh >= 2 * CURSOR_TILE_H
        and love.graphics.newQuad(0, CURSOR_TILE_H, 8, CURSOR_TILE_H, sw, sh)
        or corner,
    }
  end
  local corner, edge = self.cursorQuads.corner, self.cursorQuads.edge
  local x0, y0 = tx * 8, ty * 8
  if (tilesWide or 1) <= 1 then
    self:drawCursorTile(corner, x0 - 1, y0 - 1, false, false)
    self:drawCursorTile(corner, x0, y0 - 1, true, false)
    self:drawCursorTile(corner, x0 - 1, y0, false, true)
    self:drawCursorTile(corner, x0, y0, true, true)
    return
  end
  local right = x0 + (tilesWide - 1) * 8
  self:drawCursorTile(corner, x0, y0 - 1, false, false)
  self:drawCursorTile(corner, right, y0 - 1, true, false)
  self:drawCursorTile(corner, x0, y0, false, true)
  self:drawCursorTile(corner, right, y0, true, true)
  for i = 1, tilesWide - 2 do
    self:drawCursorTile(edge, x0 + i * 8, y0 - 1, false, false)
    self:drawCursorTile(edge, x0 + i * 8, y0, false, true)
  end
end

function NamingScreen:clearPanel(tx, ty, tw, th)
  local G = love.graphics
  local paper = self:paperColor()
  G.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
  G.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
  G.setColor(0, 0, 0, 1)
end

-- The entry field: typed characters, then an underline in the next slot, then
-- middle lines for the rest (NamingScreen_InitNameEntry).
function NamingScreen:drawEntry(tx, ty)
  local G = love.graphics
  local pen = tx * 8
  local length = #self.text
  for i = 1, self.maxLength do
    if i <= length then
      G.setColor(0, 0, 0, 1)
      Font.draw(self.text:sub(i, i), pen, ty * 8)
    else
      local isNext = i == length + 1
      local glyph = isNext and self.tiles.underLine or self.tiles.middleLine
      if glyph then
        G.setColor(0, 0, 0, 1)
        G.draw(glyph, pen, ty * 8)
      else
        -- No extracted line tiles: draw them.  Underline sits on the cell's
        -- baseline, the middle line halfway up, same as the 1bpp art.
        G.setColor(0, 0, 0, 1)
        G.rectangle("fill", pen + 1, ty * 8 + (isNext and 7 or 4), 6, 1)
      end
    end
    pen = pen + 8
  end
  G.setColor(1, 1, 1, 1)
end

function NamingScreen:drawPanel()
  local G = love.graphics
  self:drawBackdrop()

  local headerH = self.isBox and 4 or 6
  self:clearPanel(1, 1, 18, headerH)
  local keyboardTop = self:keyboardTop()
  local keyboardH = self.isBox and 9 or 7
  self:clearPanel(1, keyboardTop, 18, keyboardH)
  -- NamingScreen_ApplyTextInputMode clears the bottom row separately
  -- (hlcoord 1, 16 / lb bc, 1, 18), leaving one patterned row between the
  -- letters and the case/DEL/END strip.
  self:clearPanel(1, 16, 18, 1)

  -- Header: the standing-down frame of a 16x96 OW sheet (or the first 16x16 of
  -- a mon icon) on the left, and the prompt at (5,2).  Quad it: blitting the
  -- whole sheet paints every walk frame down the screen.
  if self.iconImage then
    G.setColor(1, 1, 1, 1)
    local w, h = self.iconImage:getDimensions()
    local quad = love.graphics.newQuad(0, 0, math.min(16, w), math.min(16, h),
      w, h)
    if self.iconColors and GbcPalette.available() then
      GbcPalette.with(self.iconColors,
        function() G.draw(self.iconImage, quad, 16, 16) end)
    else
      G.draw(self.iconImage, quad, 16, 16)
    end
  end
  local pal = self.palette
  if self.monName then
    -- Nickname header is two lines: "<MON>'S" then "NICKNAME?".  Kept as two
    -- Strings() calls, one per line (Chrome.printThrough draws a single row),
    -- with the mon name folded into the first line's own format string so a
    -- language whose possessive is not a bare suffix can restructure that
    -- line rather than being stuck splicing one on.
    Chrome.printThrough(Strings("%s'S", self.monName), 5, 2, pal)
    Chrome.printThrough(Strings("NICKNAME?"), 5, 4, pal)
  else
    Chrome.printThrough(Strings(self.prompt), 5, 2, pal)
  end
  self:drawEntry(5, self.isBox and 4 or 6)

  -- Keyboard rows.
  local grid = self:rows()
  local bottom = self:bottomRow()
  for row = 0, bottom - 1 do
    local line = grid[row + 1] or {}
    for col = 0, 8 do
      local ch = line[col + 1]
      if ch and ch ~= " " and ch ~= "" then
        -- Same seam the Gen 1 board's cells go through (src/ui/NamingScreen
        -- .lua's own Strings(cell)): a script whose alphabet does not fit
        -- A-Z can swap a cell's glyph without needing the heavier
        -- ui.naming.grid hook this screen also offers.
        Chrome.printThrough(Strings(ch), 2 + col * 2, keyboardTop + row * 2, pal)
      end
    end
  end
  local labels = self.lower and BOTTOM_LOWER_LABELS or BOTTOM_UPPER_LABELS
  local bottomY = keyboardTop + bottom * 2
  for i, label in ipairs(labels) do
    Chrome.printThrough(Strings(label), BOTTOM_LABEL_TX[i], bottomY, pal)
  end

  local function cursor() self:drawCursorBox(self:cursorTile()) end
  if pal and GbcPalette.available() then
    GbcPalette.with(pal, cursor)
  else
    cursor()
  end
  G.setColor(1, 1, 1, 1)
end

function NamingScreen:draw()
  self:drawPanel()
end

function NamingScreen:drawWidescreen(winW, winH)
  local G = love.graphics
  -- The naming screen's own patterned backdrop is the surround: extend it to
  -- the window edges so a widescreen boot has no black pillarbox.
  local scale = Chrome.fitScale(winW, winH)
  local ox, oy = Chrome.fitOrigin(winW, winH, scale)
  local paper = self:paperColor()
  G.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  G.setColor(1, 1, 1, 1)
  if self.tiles.border then
    local tilesX = math.ceil(winW / (8 * scale))
    local tilesY = math.ceil(winH / (8 * scale))
    local tile = self.tiles.border
    local function blit()
      G.setColor(1, 1, 1, 1)
      G.push()
      G.scale(scale, scale)
      for ty = 0, tilesY do
        for tx = 0, tilesX do
          G.draw(tile, tx * 8, ty * 8)
        end
      end
      G.pop()
    end
    if self.palette and GbcPalette.available() then
      GbcPalette.with(self.palette, blit)
    else
      blit()
    end
  end
  G.push()
  G.translate(ox, oy)
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

-- Exported for tests: the character the cursor is over right now.
function NamingScreen:cursorCharacter()
  if self:onBottomRow() then
    local target = self:bottomTarget()
    return ({ "CASE", "DEL", "END" })[target]
  end
  return self:characterAt(self.col, self.row)
end

NamingScreen.NAME_INPUT_UPPER = NAME_INPUT_UPPER
NamingScreen.NAME_INPUT_LOWER = NAME_INPUT_LOWER
NamingScreen.BOX_INPUT_UPPER = BOX_INPUT_UPPER
NamingScreen.BOX_INPUT_LOWER = BOX_INPUT_LOWER

return NamingScreen
