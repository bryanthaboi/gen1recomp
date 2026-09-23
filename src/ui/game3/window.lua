-- Pret-style WindowTemplate helpers for game3 (tile coords on 240×160).
-- Mirrors struct WindowTemplate { tilemapLeft, tilemapTop, width, height }.

local Display = require("src.core.game3.display")
local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")

local Window = {}

local T = Display.TILE

-- FrlgFont glyphs are ~14px tall (LINE_PITCH 15). One tile is 8px, so menu
-- list rows MUST advance by 2 tiles or lines overlap.
Window.ROW_STRIDE = 2
Window.TEXT_OY = 0 -- pixel nudge inside a row (pret printers often +0/+1)
-- pret Menu_InitCursor / PrintStartMenuItems: cursor at x=0, labels at x=8,
-- optionHeight=15. Cursor is gText_SelectorArrow2 (charmap ▶ = 0xEF).
Window.CURSOR_WIDTH = 8
Window.OPTION_HEIGHT = 15 -- start menu / Menu_InitCursor pitch in pixels

--- Build a template table (pret field names + short aliases).
function Window.template(left, top, width, height, opts)
  opts = opts or {}
  return {
    tilemapLeft = left,
    tilemapTop = top,
    width = width,
    height = height,
    paletteNum = opts.paletteNum or 15,
    left = left,
    top = top,
    w = width,
    h = height,
  }
end

function Window.fill(tpl, r, g, b, a)
  local L, Top, W, H = tpl.left or tpl.tilemapLeft, tpl.top or tpl.tilemapTop,
    tpl.w or tpl.width, tpl.h or tpl.height
  love.graphics.setColor(r or 1, g or 1, b or 1, a or 1)
  love.graphics.rectangle("fill", L * T, Top * T, W * T, H * T)
  love.graphics.setColor(1, 1, 1, 1)
end

--- Std 9-slice frame around content rect (content = left,top,width,height tiles).
function Window.stdFrame(tpl)
  local L = tpl.left or tpl.tilemapLeft
  local Top = tpl.top or tpl.tilemapTop
  local W = tpl.w or tpl.width
  local H = tpl.h or tpl.height
  Chrome.stdFrame(L, Top, W, H)
end

-- pokefirered/src/text_window.c:80
function Window.fixedStdFrame(tpl)
  Chrome.fixedStdFrame(tpl.left or tpl.tilemapLeft, tpl.top or tpl.tilemapTop,
    tpl.w or tpl.width, tpl.h or tpl.height)
end

function Window.userFrame(tpl, frameType)
  Chrome.userFrame(frameType, tpl.left or tpl.tilemapLeft, tpl.top or tpl.tilemapTop,
    tpl.w or tpl.width, tpl.h or tpl.height)
end

function Window.dialogueFrame()
  Chrome.dialogueFrame()
end

function Window.signFrame()
  Chrome.signFrame()
end

--- Print with FrlgFont at tile (tx, ty) + optional pixel offsets.
function Window.print(text, tx, ty, opts)
  opts = opts or {}
  local px = tx * T + (opts.ox or 0)
  local py = ty * T + (opts.oy ~= nil and opts.oy or Window.TEXT_OY)
  local maxW = opts.maxWidth
  if not maxW and opts.clipTiles then
    maxW = opts.clipTiles * T
  end
  FrlgFont.draw(tostring(text or ""), px, py, {
    maxWidth = maxW or (Display.COLS * T),
    colors = opts.colors or FrlgFont.COLOR.NORMAL,
    limitChars = opts.limitChars,
  })
end

-- pokefirered/src/new_menu_helpers.c:61
function Window.printPx(text, px, py, opts)
  opts = opts or {}
  FrlgFont.draw(tostring(text or ""), px, py, {
    maxWidth = opts.maxWidth or (Display.COLS * T),
    colors = opts.colors or FrlgFont.COLOR.NORMAL,
    limitChars = opts.limitChars,
    small = opts.small,
  })
end

--- FRLG menu cursor: pret gText_SelectorArrow2 (charmap ▶ = 0xEF).
-- Drawn from ROM-extracted glyph sheet (latin_normal @ sFontNormalLatinGlyphs),
-- same dark-gray + shadow as menu text. Labels start CURSOR_WIDTH (8) px after.
function Window.cursor(tx, ty, opts)
  opts = opts or {}
  local px = tx * T + (opts.ox or 0)
  local py = ty * T + (opts.oy ~= nil and opts.oy or Window.TEXT_OY)
  FrlgFont.drawGlyph(FrlgFont.CHAR_SELECTOR_ARROW, px, py, {
    colors = opts.colors or FrlgFont.COLOR.NORMAL,
  })
end

--- Pixel-space cursor (for 15px start-menu rows).
function Window.cursorPx(px, py, opts)
  opts = opts or {}
  FrlgFont.drawGlyph(FrlgFont.CHAR_SELECTOR_ARROW, px, py, {
    colors = opts.colors or FrlgFont.COLOR.NORMAL,
  })
end

--- Label X after cursor column (pret text at +8px).
function Window.labelTx(cursorTx)
  return cursorTx + 1
end

--- Double-spaced menu row Y in tiles (approx; prefer menuRowPx for start menu).
function Window.menuRowY(baseTop, index1)
  return baseTop + (index1 - 1) * Window.ROW_STRIDE
end

--- Pret Menu_InitCursor option row Y in pixels (15px pitch).
function Window.menuRowPx(baseTopPx, index1)
  return baseTopPx + (index1 - 1) * Window.OPTION_HEIGHT
end

--- How many double-spaced rows fit in a content height (tiles), given headerTiles.
function Window.fitRows(contentH, headerTiles)
  headerTiles = headerTiles or 0
  local avail = contentH - headerTiles
  if avail < Window.ROW_STRIDE then return 1 end
  return math.floor(avail / Window.ROW_STRIDE)
end

return Window
