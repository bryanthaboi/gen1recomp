-- Game3 drawing primitives on the FRLG 240×160 canvas.
-- Tile grid: 30×20 cells of 8px. Dialog/menu chrome from pret text_window tiles.
-- All menu text uses FrlgFont (latin_normal) — never Gen2 Font.

local Chrome = require("src.ui.game3.chrome")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")

local Gfx = {}

local function setRgb(r, g, b, a)
  love.graphics.setColor(r, g, b, a or 1)
end

function Gfx.fill(px, py, pw, ph, r, g, b, a)
  setRgb(r, g, b, a)
  love.graphics.rectangle("fill", px, py, pw, ph)
end

function Gfx.rect(px, py, pw, ph, r, g, b, a)
  setRgb(r, g, b, a)
  love.graphics.rectangle("line", px, py, pw, ph)
end

function Gfx.window(tx, ty, tw, th)
  Chrome.stdFrame(tx, ty, tw, th)
end

function Gfx.dialogueWindow()
  Chrome.dialogueFrame()
end

function Gfx.signWindow()
  Chrome.signFrame()
end

function Gfx.print(text, tx, ty, r, g, b)
  local colors = FrlgFont.COLOR.NORMAL
  if r then
    colors = { fg = { r, g or r, b or r, 1 }, shadow = FrlgFont.COLOR.NORMAL.shadow }
  end
  Window.print(text, tx, ty, { colors = colors })
end

function Gfx.printPx(text, px, py, r, g, b)
  local colors = FrlgFont.COLOR.NORMAL
  if r then
    colors = { fg = { r, g or r, b or r, 1 }, shadow = FrlgFont.COLOR.NORMAL.shadow }
  end
  Window.printPx(text, px, py, { colors = colors })
end

function Gfx.cursor(tx, ty)
  Window.cursor(tx, ty)
end

function Gfx.clearUiBand()
end

function Gfx.drawUi()
  return require("src.ui.game3.ui_pass").drawUi()
end

-- Export Window geometry helpers used by menus / tests.
Gfx.Window = Window
Gfx.START_LEFT = 22 -- pret AddWindowParameterized tilemapLeft
Gfx.START_TOP = 1
Gfx.START_WIDTH = 7

return Gfx
