-- Shared Gen 2 menu chrome: boxes, tile-grid text, and the scrolling cursor
-- list that nearly every Gold screen is built out of.
--
-- Gold draws its menus through one routine (engine/menus/menu.asm SetUpMenu +
-- GetScrollingMenuJoypad), so the behaviour every screen inherits -- wrap at
-- the ends, a ▶ cursor in a one-tile gutter, B to back out, START as an
-- accept on some menus -- lives here once instead of in each screen.
--
-- Everything is in 8px tile coordinates on the 20x18 GB grid, because that is
-- how the ASM addresses the screen (hlcoord x, y) and it makes a layout
-- transcribed from pokegold land on the same pixels.

local Font = require("src.render.Font")
local GbcPalette = require("src.render.GbcPalette")

local Chrome = {}

-- charmap.asm: ▶ is the menu cursor, ▷ its hollow "held" form, ▼ the
-- text-advance arrow.
Chrome.CURSOR = 0xED
Chrome.CURSOR_HOLLOW = 0xEC
Chrome.DOWN_ARROW = 0xEE

Chrome.SCREEN_W = 20
Chrome.SCREEN_H = 18

-- charmap.asm "¥", the money field's own prefix tile.
local YEN = "\xc2\xa5"

function Chrome.paletteFill(px, py, pw, ph, palette)
  palette = palette or Chrome.DEFAULT_BOX_PALETTE
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  if GbcPalette.available() then
    GbcPalette.with(palette, function() G.rectangle("fill", px, py, pw, ph) end)
  else
    G.rectangle("fill", px, py, pw, ph)
  end
  G.setColor(0, 0, 0, 1)
end

-- Every drawWidescreen paints the window around its 160x144 panel through
-- here, so UI LETTERBOX has exactly one place to override.  r/g/b is what the
-- screen was authored with and is what AUTO keeps.
local function letterboxPaper()
  local c = GbcPalette.resolve(Chrome.DEFAULT_BOX_PALETTE)
  c = c and c[1]
  if not c then return nil end
  return c[1] / 255, c[2] / 255, c[3] / 255
end

Chrome.worldSurround = false

function Chrome.letterbox(winW, winH, r, g, b)
  if Chrome.worldSurround then return end
  local Letterbox = require("src.render.Letterbox")
  local G = love.graphics
  G.setColor(Letterbox.fill(r or 1, g or 1, b or 1, letterboxPaper))
  G.rectangle("fill", 0, 0, winW, winH)
end

function Chrome.clear()
  Chrome.paletteFill(0, 0, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
end

-- The blit scale every `drawWidescreen` paints its 160x144 panel at.
--
-- One GB pixel has to cover a WHOLE number of window pixels or the 8x8 grid
-- everything here is laid out on stops landing on tile boundaries: at a
-- fractional scale some rows of a tile get one device pixel and their
-- neighbours get two, which is what breaks a box border into steps and eats
-- pixel rows out of glyphs.  This is the same rule src/render/Renderer.lua
-- fitScale applies to the Gen 1 UI canvas; the surround a widescreen screen
-- paints still fills the window, the PANEL is what stays on the grid.
local function playfieldRect(winW, winH)
  local ok, Playfield = pcall(require, "src.render.Playfield")
  if ok and Playfield.rect then
    local okv, x, y, w, h = pcall(Playfield.rect, winW, winH)
    if okv and w and w >= 1 and h and h >= 1 then
      return x, y, w, h
    end
  end
  return 0, 0, winW or 0, winH or 0
end

function Chrome.fitScaleFor(winW, winH, tilesW, tilesH)
  local _, _, w, h = playfieldRect(winW, winH)
  return math.max(1, math.floor(math.min(w / (tilesW * 8), h / (tilesH * 8))))
end

function Chrome.fitOriginFor(winW, winH, scale, tilesW, tilesH)
  scale = scale or Chrome.fitScaleFor(winW, winH, tilesW, tilesH)
  local x, y, w, h = playfieldRect(winW, winH)
  return x + math.floor((w - tilesW * 8 * scale) / 2),
    y + math.floor((h - tilesH * 8 * scale) / 2)
      - Chrome.positionLift(winW, winH, scale)
end

function Chrome.fitScale(winW, winH)
  return Chrome.fitScaleFor(winW, winH, Chrome.SCREEN_W, Chrome.SCREEN_H)
end

-- The centred origin that goes with it, so a caller does not re-derive it.
function Chrome.fitOrigin(winW, winH, scale)
  scale = scale or Chrome.fitScale(winW, winH)
  return Chrome.fitOriginFor(winW, winH, scale, Chrome.SCREEN_W,
    Chrome.SCREEN_H)
end

function Chrome.positionLift(winW, winH, scale)
  local ok, ScreenPosition = pcall(require, "src.core.ScreenPosition")
  if not ok or ScreenPosition.skinActive(winW, winH) then return 0 end
  local _, _, _, h = playfieldRect(winW, winH)
  return ScreenPosition.lift(h, Chrome.SCREEN_H * 8 * (scale
    or Chrome.fitScale(winW, winH)), ScreenPosition.safeTop())
end

-- pokegold engine/battle/core.asm:8646, engine/events/halloffame.asm:270
local function clipTo(x, y, w, h)
  local G = love.graphics
  if G.intersectScissor then G.intersectScissor(x, y, w, h)
  else G.setScissor(x, y, w, h) end
end

Chrome.clipTo = clipTo

function Chrome.withPanel(winW, winH, r, g, b, drawFn, scale)
  local G = love.graphics
  Chrome.letterbox(winW, winH, r, g, b)
  scale = scale or Chrome.fitScale(winW, winH)
  local ox, oy = Chrome.fitOrigin(winW, winH, scale)
  G.push("all")
  clipTo(ox, oy, Chrome.SCREEN_W * 8 * scale, Chrome.SCREEN_H * 8 * scale)
  G.translate(ox, oy)
  G.scale(scale, scale)
  drawFn()
  G.pop()
end

function Chrome.withClip(drawFn)
  local G = love.graphics
  G.push("all")
  clipTo(0, 0, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
  drawFn()
  G.pop()
end

Chrome.DEFAULT_BOX_PALETTE = {
  { 255, 255, 255 }, { 255, 255, 255 }, { 255, 255, 255 }, { 0, 0, 0 },
}

function Chrome.paletteBox(tx, ty, tw, th, palette)
  palette = palette or Chrome.DEFAULT_BOX_PALETTE
  if GbcPalette.available() then
    love.graphics.setColor(1, 1, 1, 1)
    GbcPalette.with(palette, function() Font.drawBox(tx, ty, tw, th) end)
  else
    Font.drawBox(tx, ty, tw, th, palette[1])
  end
  love.graphics.setColor(0, 0, 0, 1)
end

-- A bordered box, tile coords.  Leaves the draw color black for text.
function Chrome.box(tx, ty, tw, th)
  Chrome.paletteBox(tx, ty, tw, th)
end

-- Gold's Textbox helper takes an interior width/height and draws the border
-- around it; b/c in the ASM are interior rows/columns, so a `lb bc, 4, 13`
-- box is 6 rows by 15 columns on screen.
function Chrome.textbox(tx, ty, interiorW, interiorH)
  Chrome.box(tx, ty, interiorW + 2, interiorH + 2)
end

local function flatPrint(text, tx, ty)
  love.graphics.setColor(0, 0, 0, 1)
  return Font.draw(text, tx * 8, ty * 8)
end

function Chrome.print(text, tx, ty)
  if not GbcPalette.available() then return flatPrint(text, tx, ty) end
  return Chrome.printThrough(text, tx, ty, Chrome.DEFAULT_BOX_PALETTE)
end

-- Prints a string the way a tilemap screen does: the glyph tiles replace the
-- cells they land on, and both their ink and their blank pixels go through
-- that screen's own BG palette.
--
-- The font sheets here are black ink (shade 3) on transparent, and setColor
-- multiplies -- black times anything is still black -- so the ink colour
-- cannot come from a tint.  Drawing through GbcPalette maps shade 3 to the
-- palette's colour 3, and painting colour 0 behind the string first supplies
-- the cell background the sheet does not carry.  Without a shader this
-- degrades to the ordinary black print rather than drawing nothing.
--
-- The palette printThrough actually draws with: COLOR mode resolved,
-- inverted if asked, and the active rBGP byte folded in last -- the same
-- order GbcPalette.use follows.  Split out so the fold can be checked
-- without a real shader (GbcPalette.available() is false in a driverless
-- test harness, which used to hide this from every suite).
--
-- The substitution has to happen before the reversal or an inverted string
-- would come back through an un-reversed grey ramp and print black on white,
-- and the rBGP fold has to come after both: it REORDERS the four entries
-- this palette already settled on (colour 0 in the low bits, so
-- `dc 3,2,1,0` packs to $e4), it does not tint them, so folding it before
-- the invert reversal would permute the wrong four colours.
function Chrome.throughPalette(palette, invert)
  local pal = GbcPalette.resolve(palette)
  if invert then pal = { pal[4], pal[3], pal[2], pal[1] } end
  return GbcPalette.remap(pal, GbcPalette.bgp)
end

function Chrome.rawPalette(palette, invert)
  if invert then return { palette[4], palette[3], palette[2], palette[1] } end
  return palette
end

-- The per-glyph shader/tint switch printThrough needs, factored out so a
-- caller that positions its own glyphs (TextBox's typewriter/scroll
-- animation) gets the same shaded ink without re-deriving the TTF-vs-tile
-- split.
--
-- Returns (pal, drawGlyph, finish):
--   pal        the resolved ramp, or nil if there's no shader to draw
--              through; a caller that also draws a paper rect should skip
--              it and take the plain Chrome.print degrade instead.
--   drawGlyph  (code, x, y): draws one glyph, shaded through `pal` for a
--              tile glyph or tinted with pal[4] for a TTF one (see the
--              inline comment below, gen1recomp#1642).
--   finish     call once after the last glyph to restore the previous
--              shader and draw colour.
function Chrome.paletteGlyphs(palette, invert, raw)
  if not (palette and GbcPalette.available()) then
    return nil, Font.drawCode, function() end
  end
  -- `pal` is used below and never touches the caller's palette again --
  -- including useRaw for the draw, since useRaw skips the fold GbcPalette.use
  -- would otherwise apply and folding it a second time would undo this.
  local pal = raw and Chrome.rawPalette(palette, invert)
    or Chrome.throughPalette(palette, invert)
  local ink = pal[4] or { 0, 0, 0 }
  local previous = love.graphics.getShader()
  local shaded = false
  local function drawGlyph(code, x, y)
    if code >= Font.TTF_BASE then
      -- flat-shaded 2bpp tile sheet -- exactly what a TTF glyph is not.
      -- LÖVE's font rasterizer stores glyph coverage as alpha over a plain
      -- white texture, which this shader reads back as shade 0 no matter how
      -- solid the glyph looks, painting the character the SAME colour as the
      -- paper rect just drawn above it: invisible (reported against a real
      -- Gold build with a TTF translation mod active, gen1recomp#1642). A TTF
      -- glyph has no discrete shade to recover in the first place, so skip
      -- the shader for it and tint it with the palette's own ink colour
      -- (shade 3, the same entry `rgb = pal3` would have mapped a black tile
      -- pixel to) directly.
      if shaded then love.graphics.setShader(previous); shaded = false end
      love.graphics.setColor(ink[1] / 255, ink[2] / 255, ink[3] / 255, 1)
    elseif not shaded then
      love.graphics.setColor(1, 1, 1, 1)
      GbcPalette.useRaw(pal)
      shaded = true
    end
    Font.drawCode(code, x, y)
  end
  local function finish()
    if shaded then love.graphics.setShader(previous) end
    love.graphics.setColor(0, 0, 0, 1)
  end
  return pal, drawGlyph, finish
end

function Chrome.printThrough(text, tx, ty, palette, invert, raw)
  local pal, drawGlyph, finish = Chrome.paletteGlyphs(palette, invert, raw)
  if not pal then return Chrome.print(text, tx, ty) end
  local width = Font.width(text)
  local paper = pal[1] or { 255, 255, 255 }
  love.graphics.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
  love.graphics.rectangle("fill", tx * 8, ty * 8, width, 8)
  local pen = tx * 8
  for _, code in ipairs(Font.encode(text)) do
    drawGlyph(code, pen, ty * 8)
    pen = pen + Font.advanceOf(code)
  end
  finish()
  return width
end

-- The same, through an *inverted* font page.  Pokedex_LoadInvertedFont xors
-- both bitplanes of the standard font, so a glyph pixel of shade s becomes
-- shade 3 - s before the palette sees it -- which is exactly the palette read
-- backwards, and is what makes the dex white on black.
function Chrome.printInverted(text, tx, ty, palette)
  if not palette then return Chrome.print(text, tx, ty) end
  return Chrome.printThrough(text, tx, ty, palette, true)
end

-- Right-aligned within a field that ends at tile `txEnd` (exclusive), which is
-- how Gold prints numbers (PrintNum fills from the right).
local function flatPrintRight(text, txEnd, ty)
  local width = Font.width(text)
  love.graphics.setColor(0, 0, 0, 1)
  return Font.draw(text, txEnd * 8 - width, ty * 8)
end

function Chrome.printRight(text, txEnd, ty)
  if not GbcPalette.available() then return flatPrintRight(text, txEnd, ty) end
  return Chrome.printRightThrough(text, txEnd, ty, Chrome.DEFAULT_BOX_PALETTE)
end

function Chrome.printRightThrough(text, txEnd, ty, palette, invert, raw)
  local pal, drawGlyph, finish = Chrome.paletteGlyphs(palette, invert, raw)
  if not pal then return Chrome.printRight(text, txEnd, ty) end
  local width = Font.width(text)
  local tx = txEnd * 8 - width
  local paper = pal[1] or { 255, 255, 255 }
  love.graphics.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
  love.graphics.rectangle("fill", tx, ty * 8, width, 8)
  local pen = tx
  for _, code in ipairs(Font.encode(text)) do
    drawGlyph(code, pen, ty * 8)
    pen = pen + Font.advanceOf(code)
  end
  finish()
  return width
end

-- Wrap text to `width` tiles, measuring with the real font so a proportional
-- page wraps where it actually overflows.  Nothing on a 160px screen may print
-- past tile 20: text that does is drawn outside the GB frame entirely.
-- A "\n" in the text is the cart's OWN line break (data/text's `line` / `next`
-- control byte, e.g. "<USER>\nused <MOVE>!"), so it is a HARD break: each
-- segment wraps on its own and the break survives, rather than being eaten by
-- the %S+ tokenizer and re-wrapped by width.
function Chrome.wrap(text, width)
  local budget = (width or Chrome.SCREEN_W) * 8
  local lines = {}
  for segment in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    local line = nil
    for word in segment:gmatch("%S+") do
      local candidate = line and (line .. " " .. word) or word
      if line and Font.width(candidate) > budget then
        lines[#lines + 1] = line
        line = word
      else
        line = candidate
      end
    end
    if line then lines[#lines + 1] = line end
  end
  return lines
end

-- Print wrapped text from (tx, ty) downward, at most `rows` lines.
-- ../pokecrystal/home/text.asm:473
function Chrome.printWrapped(text, tx, ty, width, rows, step, palette)
  step = step or 1
  local lines = Chrome.wrap(text, width)
  for i = 1, math.min(#lines, rows or #lines) do
    if palette then
      Chrome.printThrough(lines[i], tx, ty + (i - 1) * step, palette)
    else
      Chrome.print(lines[i], tx, ty + (i - 1) * step)
    end
  end
  return #lines
end

local function flatCursor(tx, ty, hollow)
  love.graphics.setColor(0, 0, 0, 1)
  Font.drawCode(hollow and Chrome.CURSOR_HOLLOW or Chrome.CURSOR, tx * 8, ty * 8)
end

function Chrome.cursor(tx, ty, hollow)
  if not GbcPalette.available() then return flatCursor(tx, ty, hollow) end
  return Chrome.cursorThrough(tx, ty, Chrome.DEFAULT_BOX_PALETTE, nil, hollow)
end

-- The cursor glyph through a palette, the way Chrome.printThrough draws text.
-- A screen whose font page is inverted (the #DEX: Pokedex_LoadInvertedFont
-- xors both bitplanes, so it runs white on black) needs its cursor inverted
-- with everything else -- Chrome.cursor's flat black is invisible against that
-- ground, which is what made the dex's action arrow look absent.
function Chrome.cursorThrough(tx, ty, palette, invert, hollow, raw)
  if not (palette and GbcPalette.available()) then
    return Chrome.cursor(tx, ty, hollow)
  end
  local pal = raw and Chrome.rawPalette(palette, invert)
    or Chrome.throughPalette(palette, invert)
  local paper = pal[1] or { 255, 255, 255 }
  love.graphics.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
  love.graphics.rectangle("fill", tx * 8, ty * 8, 8, 8)
  love.graphics.setColor(1, 1, 1, 1)
  local previous = love.graphics.getShader()
  GbcPalette.useRaw(pal)
  Font.drawCode(hollow and Chrome.CURSOR_HOLLOW or Chrome.CURSOR, tx * 8, ty * 8)
  love.graphics.setShader(previous)
  love.graphics.setColor(0, 0, 0, 1)
end

-- Gold pads a numeric field with spaces, not zeroes, unless
-- PRINTNUM_LEADINGZEROS is set.
function Chrome.number(value, width, leadingZeros)
  local text = tostring(math.floor(value or 0))
  local pad = math.max(0, (width or 0) - #text)
  return (leadingZeros and ("0"):rep(pad) or (" "):rep(pad)) .. text
end

-- PrintNum with PRINTNUM_MONEY and without PRINTNUM_LEADINGZEROS
-- (home/print_num.asm .PrintYen): the ¥ is emitted just before the FIRST
-- significant digit rather than at a fixed column, and the field is six digits
-- wide, so the string is always seven tiles and the yen sign floats.
function Chrome.money(amount)
  local digits = ("%06d"):format(math.max(0, math.floor(amount or 0)))
  local first = digits:find("[1-9]") or #digits
  return (" "):rep(first - 1) .. YEN .. digits:sub(first)
end

-- ------------------------------------------------------- balance boxes
--
-- engine/menus/menu_2.asm.  These three are the boxes a SCRIPT puts up with a
-- `special` and then leaves standing: every one of them is immediately
-- followed by `loadmenu`, so the box is on screen for the whole of the static
-- menu that answers.  They live here rather than in one menu module because
-- three different screens print them (the Game Corner prize counters and the
-- coin vendor through src/ui/gen2/ScriptMenu.lua, the prize counter screen
-- itself) and all three are laid out by the same two routines.
--
-- DisplayCoinCaseBalance: Textbox at (11,0) with a 7x1 interior, "COIN" at
-- (12,0) -- yes, in the border row -- and the four-digit count at (13,1) with
-- PRINTNUM_LEADINGZEROS.
function Chrome.coinBalanceBox(coins)
  Chrome.textbox(11, 0, 7, 1)
  Chrome.printThrough("COIN", 12, 0, Chrome.DEFAULT_BOX_PALETTE)
  Chrome.printThrough(Chrome.number(coins, 4, true), 13, 1, Chrome.DEFAULT_BOX_PALETTE)
end

-- DisplayMoneyAndCoinBalance: one Textbox at (5,0) with a 13x3 interior
-- holding both fields, "MONEY" at (6,1) with the yen field at (12,1) and
-- "COIN" at (6,3) with the four-digit count at (15,3).
function Chrome.moneyAndCoinBalanceBox(money, coins)
  Chrome.textbox(5, 0, 13, 3)
  Chrome.printThrough("MONEY", 6, 1, Chrome.DEFAULT_BOX_PALETTE)
  Chrome.printThrough(Chrome.money(money), 12, 1, Chrome.DEFAULT_BOX_PALETTE)
  Chrome.printThrough("COIN", 6, 3, Chrome.DEFAULT_BOX_PALETTE)
  Chrome.printThrough(Chrome.number(coins, 4, true), 15, 3, Chrome.DEFAULT_BOX_PALETTE)
end

-- PlaceMoneyTopRight: MoneyTopRightMenuHeader is `menu_coords 11, 0,
-- SCREEN_WIDTH - 1, 2`, a MenuBox rather than a Textbox, and PlaceMoneyTextbox
-- prints the number at MenuBoxCoord2Tile + SCREEN_WIDTH + 1, i.e. (12,1).
function Chrome.moneyBalanceBox(money)
  Chrome.box(11, 0, 9, 3)
  Chrome.printThrough(Chrome.money(money), 12, 1, Chrome.DEFAULT_BOX_PALETTE)
end

-- A vertical cursor list.
--
-- opts:
--   items      array of strings, or of { label = , value = , disabled = }
--   x, y       tile coords of the first row's *label* (cursor sits at x - 1)
--   spacing    tile rows between entries (Gold uses 2 for most menus)
--   rows       visible rows; a longer list scrolls (default: all)
--   wrap       wrap past the ends (STATICMENU_WRAP)
--   startAccepts  treat START like A (STATICMENU_ENABLE_START)
--   onChoose(value, index)
--   onCancel()
--   onMove(value, index)  -- for the start menu's description box
local List = {}
List.__index = List
Chrome.List = List

function List.new(opts)
  local self = setmetatable({}, List)
  self.items = {}
  for i, entry in ipairs(opts.items or {}) do
    if type(entry) == "table" then
      self.items[i] = entry
    else
      self.items[i] = { label = tostring(entry), value = entry }
    end
  end
  self.x = opts.x or 1
  self.y = opts.y or 1
  self.spacing = opts.spacing or 2
  self.rows = math.min(opts.rows or #self.items, #self.items)
  self.wrap = opts.wrap ~= false
  self.startAccepts = opts.startAccepts or false
  self.onChoose = opts.onChoose
  self.onCancel = opts.onCancel
  self.onMove = opts.onMove
  self.palette = opts.palette == nil and Chrome.DEFAULT_BOX_PALETTE or opts.palette
  self.index = math.max(1, math.min(opts.index or 1, math.max(1, #self.items)))
  self.scroll = 0
  self:ensureVisible()
  return self
end

function List:current()
  return self.items[self.index]
end

function List:ensureVisible()
  if self.rows <= 0 then return end
  if self.index <= self.scroll then
    self.scroll = self.index - 1
  elseif self.index > self.scroll + self.rows then
    self.scroll = self.index - self.rows
  end
  self.scroll = math.max(0, math.min(self.scroll, #self.items - self.rows))
end

function List:move(delta)
  if #self.items == 0 then return end
  local next_ = self.index + delta
  if next_ < 1 then
    if not self.wrap then return end
    next_ = #self.items
  elseif next_ > #self.items then
    if not self.wrap then return end
    next_ = 1
  end
  self.index = next_
  self:ensureVisible()
  if self.onMove then self.onMove(self:current() and self:current().value, self.index) end
end

-- Returns true when the press was consumed, so a screen can layer its own
-- handling (left/right on the options rows) behind this.
function List:update(input)
  if not input then return false end
  if input:wasPressed("up") then
    self:move(-1)
    return true
  elseif input:wasPressed("down") then
    self:move(1)
    return true
  elseif input:wasPressed("a")
      or (self.startAccepts and input:wasPressed("start")) then
    local item = self:current()
    if item and not item.disabled and self.onChoose then
      self.onChoose(item.value, self.index)
    end
    return true
  elseif input:wasPressed("b") then
    if self.onCancel then self.onCancel() end
    return true
  end
  return false
end

function List:draw()
  for row = 1, self.rows do
    local i = row + self.scroll
    local item = self.items[i]
    if item then
      local ty = self.y + (row - 1) * self.spacing
      if i == self.index then
        if self.palette then
          Chrome.cursorThrough(self.x - 1, ty, self.palette)
        else
          flatCursor(self.x - 1, ty)
        end
      end
      if self.palette then
        Chrome.printThrough(item.label, self.x, ty, self.palette)
      else
        flatPrint(item.label, self.x, ty)
      end
    end
  end
  -- Scrolling lists get the ▼ hint Gold shows when there is more below.
  if self.rows < #self.items and self.scroll + self.rows < #self.items then
    if self.palette then
      local _, drawGlyph, finish = Chrome.paletteGlyphs(self.palette)
      drawGlyph(Chrome.DOWN_ARROW, (self.x - 1) * 8,
        (self.y + self.rows * self.spacing - 1) * 8)
      finish()
    else
      love.graphics.setColor(0, 0, 0, 1)
      Font.drawCode(Chrome.DOWN_ARROW, (self.x - 1) * 8,
        (self.y + self.rows * self.spacing - 1) * 8)
    end
  end
end

return Chrome
