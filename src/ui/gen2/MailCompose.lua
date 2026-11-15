-- Writing a letter: _ComposeMailMessage (engine/menus/naming_screen.asm) and
-- its own charset, data/text/mail_input_chars.asm.
--
-- It is the naming screen's cousin, not the naming screen: the grid is TEN
-- columns wide instead of nine, the entry field is two MAIL_LINE_LENGTH rows
-- instead of one, and the charsets are different in both cases (mail gets the
-- digits, the four POKé glyphs, the quote marks and the apostrophe pairs; a
-- nickname gets the dakuten pairs mail has no room for).
--
-- Layout, transcribed from .InitCharset's own hlcoords:
--   rows 0-5   NAMINGSCREEN_BORDER, with (1,1) 4x18 cleared for the letter
--   .Update    ClearBox (1,1) 4x18, then PlaceString at (2,2) -- so the first
--              line of the message is row 2 and the '<NEXT>' stored at offset
--              MAIL_LINE_LENGTH puts the second on row 3
--   rows 6-17  blank, with .PlaceMailCharset writing each 19-character row
--              from x = 1 and stepping SCREEN_WIDTH + 1, i.e. TWO rows: the
--              charset sits at y = 7, 9, 11, 13, 15 and the case/DEL/END strip
--              at y = 17
--
-- Cursor: ComposeMail_AnimateCursor's .GetDPad is a 10x6 grid that wraps in
-- both axes, and row 5 (the strip) collapses to three targets at columns
-- 0-2 / 3-5 / 6-9 -- ComposeMail_GetCursorPosition's `cp $3 / cp $6` split,
-- which is why RIGHT from END wraps to the case switch rather than stepping.
--
-- SELECT toggles case anywhere, START parks the cursor on END, B deletes.
-- Filling both lines does NOT end entry the way a nickname's last slot does:
-- .a only bumps the length past the stored line break, so the player still has
-- to press END.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local Mail = require("src.core.gen2.Mail")
local RomText = require("src.core.RomText")

local MailCompose = {}
MailCompose.__index = MailCompose
MailCompose.isOpaque = true

local function glyphs(row)
  local out, i = {}, 1
  while i <= #row do
    local glyph = row:match("^<[^>]+>", i) or row:match("^'[dlmrstv]", i)
      or row:match("^[%z\1-\127\194-\244][\128-\191]*", i)
    out[#out + 1] = glyph
    i = i + #glyph
  end
  return out
end

-- data/text/mail_input_chars.asm:3
function MailCompose.keyboard(data, case)
  local rows = {}
  for r = 1, 5 do
    local cells = glyphs(RomText(data, ("MailEntry_%s#%d"):format(case, r)))
    local line = {}
    for c = 1, 10 do line[c] = cells[c * 2 - 1] or " " end
    rows[r] = line
  end
  rows.bottom = RomText(data, ("MailEntry_%s#6"):format(case))
  return rows
end

local BOTTOM_X = 1
local BOTTOM_CURSOR_TX = { 0, 7, 13 }

-- .PlaceMailCharset: first row at (1,7), stepping two rows.
local KEYBOARD_TOP = 7
local KEYBOARD_X = 1
local BOTTOM_ROW = 5
-- .Update's PlaceString target.
local ENTRY_X, ENTRY_Y = 2, 2

function MailCompose:wantsFillScale() return true end
function MailCompose:drawsWidescreen() return true end

-- opts: initial (a message being edited), menuGfx (gen2MenuGfx, for the
-- border and line tiles), onDone(message), onCancel().
--
-- There is no cancel on the cart: _ComposeMailMessage loops until END, and the
-- caller has already committed the item.  onCancel is here for a driver and
-- for a mod screen that wants one; nothing in the game presses it.
function MailCompose.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, MailCompose)
  self.game = game
  self.onDone = opts.onDone
  self.onCancel = opts.onCancel
  self.lower = false -- wNamingScreenLetterCase; upper first
  self.text = Mail.trim(opts.initial or "")
  self.col = 0
  self.row = 0
  local data = game and game.data
  self.upper = MailCompose.keyboard(data, "Uppercase")
  self.lowerKeys = MailCompose.keyboard(data, "Lowercase")
  self.gfx = opts.menuGfx or (data and data.gen2MenuGfx)
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

function MailCompose:rows()
  return self.lower and self.lowerKeys or self.upper
end

function MailCompose:onBottomRow()
  return self.row == BOTTOM_ROW
end

-- ComposeMail_GetCursorPosition: columns 0-2 are the case switch, 3-5 DEL,
-- 6-9 END.
function MailCompose:bottomTarget()
  if self.col < 3 then return 1 end
  if self.col < 6 then return 2 end
  return 3
end

function MailCompose:characterAt(col, row)
  local line = self:rows()[row + 1]
  local ch = line and line[col + 1]
  if not ch or ch == " " or ch == "" then return nil end
  return ch
end

function MailCompose:length()
  return #Mail.characters(self.text)
end

function MailCompose:addCharacter(ch)
  if not ch then return end
  if self:length() >= Mail.MAIL_MSG_LENGTH then return end
  self.text = self.text .. ch
end

function MailCompose:deleteCharacter()
  local chars = Mail.characters(self.text)
  if #chars == 0 then return end
  self.text = table.concat(chars, "", 1, #chars - 1)
end

function MailCompose:toggleCase()
  self.lower = not self.lower
end

-- .finished: NamingScreen_StoreEntry writes '@' over the first line/underline
-- glyph, so the message is exactly what was typed and the rest of the buffer
-- is terminator.
function MailCompose:accept()
  if self.onDone then self.onDone(self.text) end
end

-- .right / .left.  A letter row steps one column and wraps at 9/0; the strip
-- steps one TARGET and wraps at 3/1, which the ASM does by multiplying the
-- target back out by three.
function MailCompose:moveHorizontal(delta)
  if self:onBottomRow() then
    local target = self:bottomTarget() + delta
    if target < 1 then target = 3 end
    if target > 3 then target = 1 end
    self.col = (target - 1) * 3
    return
  end
  self.col = self.col + delta
  if self.col < 0 then self.col = 9 end
  if self.col > 9 then self.col = 0 end
end

function MailCompose:moveVertical(delta)
  self.row = self.row + delta
  if self.row < 0 then self.row = BOTTOM_ROW end
  if self.row > BOTTOM_ROW then self.row = 0 end
  if self:onBottomRow() then
    self.col = (self:bottomTarget() - 1) * 3
  end
end

function MailCompose:update(_dt)
  local input = self.game and self.game.input
  if not input then return end

  if input:wasPressed("left") then
    self:moveHorizontal(-1)
  elseif input:wasPressed("right") then
    self:moveHorizontal(1)
  elseif input:wasPressed("up") then
    self:moveVertical(-1)
  elseif input:wasPressed("down") then
    self:moveVertical(1)
  elseif input:wasPressed("select") then
    self:toggleCase()
  elseif input:wasPressed("start") then
    -- .start puts VAR1 = $9 / VAR2 = $5, i.e. the cursor onto END.
    self.row = BOTTOM_ROW
    self.col = 9
  elseif input:wasPressed("b") then
    -- .b is NamingScreen_DeleteCharacter, not a way out.
    self:deleteCharacter()
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
  end
end

-- The patterned backdrop the border tile fills rows 0-5 with.  Without
-- menu_gfx.lua (an older cache) a flat mid grey keeps the cleared panel
-- readable, the same fallback src/ui/gen2/NamingScreen.lua takes.
function MailCompose:drawBackdrop()
  local G = love.graphics
  local tile = self.tiles.border
  if not tile then
    G.setColor(0.62, 0.62, 0.62, 1)
    G.rectangle("fill", 0, 0, 160, 6 * 8)
    G.setColor(1, 1, 1, 1)
    return
  end
  G.setColor(1, 1, 1, 1)
  for ty = 0, 5 do
    for tx = 0, Chrome.SCREEN_W - 1 do
      G.draw(tile, tx * 8, ty * 8)
    end
  end
end

function MailCompose:clearPanel(tx, ty, tw, th)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", tx * 8, ty * 8, tw * 8, th * 8)
  G.setColor(0, 0, 0, 1)
end

-- One of the two entry rows: the characters that landed on it, then the
-- underline in the next slot and middle lines for the rest -- exactly what
-- NamingScreen_InitNameEntry lays into the buffer before the first keypress.
function MailCompose:drawEntryRow(chars, first, ty, cursorAt)
  local G = love.graphics
  for i = 1, Mail.MAIL_LINE_LENGTH do
    local index = first + i - 1
    local pen = (ENTRY_X + i - 1) * 8
    local ch = chars[index]
    if ch then
      G.setColor(0, 0, 0, 1)
      Font.draw(ch, pen, ty * 8)
    else
      local isNext = index == cursorAt
      local glyph = isNext and self.tiles.underLine or self.tiles.middleLine
      G.setColor(0, 0, 0, 1)
      if glyph then
        G.draw(glyph, pen, ty * 8)
      else
        -- No extracted line tiles: draw them.  The underline sits on the
        -- cell's baseline, the middle line halfway up, same as the 1bpp art.
        G.rectangle("fill", pen + 1, ty * 8 + (isNext and 7 or 4), 6, 1)
      end
    end
  end
  G.setColor(1, 1, 1, 1)
end

function MailCompose:drawPanel()
  local G = love.graphics
  self:drawBackdrop()
  -- rows 6-17 are ByteFilled with ' ', which is the blank tile.
  self:clearPanel(0, 6, Chrome.SCREEN_W, 12)
  -- .InitCharset's ClearBox (1,1) 4x18, which .Update repeats every frame.
  self:clearPanel(1, 1, 18, 4)

  local chars = Mail.characters(self.text)
  local cursorAt = #chars + 1
  self:drawEntryRow(chars, 1, ENTRY_Y, cursorAt)
  self:drawEntryRow(chars, Mail.MAIL_LINE_LENGTH + 1, ENTRY_Y + 1, cursorAt)

  local grid = self:rows()
  for row = 0, BOTTOM_ROW - 1 do
    local line = grid[row + 1] or {}
    for col = 0, 9 do
      local ch = line[col + 1]
      if ch and ch ~= " " and ch ~= "" then
        Chrome.print(ch, KEYBOARD_X + col * 2, KEYBOARD_TOP + row * 2)
      end
    end
  end

  local bottomY = KEYBOARD_TOP + BOTTOM_ROW * 2
  Chrome.print(grid.bottom, BOTTOM_X, bottomY)

  local cursorTx, cursorTy
  if self:onBottomRow() then
    cursorTx, cursorTy = BOTTOM_CURSOR_TX[self:bottomTarget()], bottomY
  else
    cursorTx = KEYBOARD_X - 1 + self.col * 2
    cursorTy = KEYBOARD_TOP + self.row * 2
  end
  if self.tiles.cursor then
    G.setColor(1, 1, 1, 1)
    G.draw(self.tiles.cursor, cursorTx * 8, cursorTy * 8)
  else
    Chrome.cursor(cursorTx, cursorTy)
  end
  G.setColor(1, 1, 1, 1)
end

function MailCompose:draw()
  self:drawPanel()
end

function MailCompose:drawWidescreen(winW, winH)
  local G = love.graphics
  Chrome.letterbox(winW, winH, 0.62, 0.62, 0.62)
  G.setColor(1, 1, 1, 1)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

-- Exported for tests: what the cursor is over right now.
function MailCompose:cursorCharacter()
  if self:onBottomRow() then
    return ({ "CASE", "DEL", "END" })[self:bottomTarget()]
  end
  return self:characterAt(self.col, self.row)
end

return MailCompose
