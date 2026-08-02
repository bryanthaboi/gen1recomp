-- Launcher touch-controls editor (#327): drag each on-screen button to a
-- new spot, resize them, toggle the overlay off entirely, Reset to
-- defaults, Done to persist into options.lua.  Opened from the game
-- panel's "Touch Controls" button; main.lua suspends the launcher the same
-- way it does for the save editor.
--
-- Everything edited here belongs to the orientation currently on screen
-- (#633): portrait and landscape keep separate positions and sizes, so a
-- player lays out each rotation once.  Rotate the device (or resize the
-- desktop window past square) and the editor switches buckets live.
--
-- Draws in full window LOVE units -- the same space TouchControls uses
-- after Renderer:endFrame -- so what you drag here is what you get in play.

local SaveData = require("src.core.SaveData")
local TouchControls = require("src.core.TouchControls")

local Editor = {}

local PAL = {
  bgTop = { 8, 14, 36 },
  bgBot = { 4, 8, 22 },
  white = { 245, 248, 255 },
  label = { 160, 175, 210 },
  green = { 80, 220, 140 },
  red = { 240, 90, 110 },
  card = { 18, 28, 58 },
  stroke = { 120, 150, 220 },
}

local function col(c, a)
  love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1)
end

local function inside(r, x, y)
  return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function roundRect(mode, x, y, w, h, r)
  love.graphics.rectangle(mode, x, y, w, h, r, r)
end

function Editor.load(opts)
  opts = opts or {}
  Editor.onClose = opts.onClose
  Editor.drag = nil
  Editor.rects = {}
  Editor.fonts = {
    title = love.graphics.newFont(28),
    body = love.graphics.newFont(16),
    btn = love.graphics.newFont(18),
  }
  local optsTbl = SaveData.loadOptions()
  TouchControls:init()
  TouchControls:ensureImages()
  TouchControls:applyOptions(optsTbl)
  TouchControls:setPreview(true)
  Editor.enabled = TouchControls.enabled ~= false
end

function Editor.unload()
  TouchControls:setPreview(false)
  TouchControls:reset()
  Editor.drag = nil
  Editor.onClose = nil
end

local function persist()
  local opts = SaveData.loadOptions()
  local cfg = TouchControls:config()
  -- replaces the whole table, so a pre-#633 top-level positions key is
  -- dropped once the player saves under the new shape
  opts.touchControls = {
    enabled = cfg.enabled,
    layouts = cfg.layouts,
  }
  SaveData.saveOptions(opts)
end

local function close()
  persist()
  local cb = Editor.onClose
  Editor.unload()
  if cb then cb() end
end

local function resetLayout()
  TouchControls:clearPositions()
end

local function toggleEnabled()
  Editor.enabled = not Editor.enabled
  TouchControls.enabled = Editor.enabled
  if not Editor.enabled then TouchControls:reset() end
end

function Editor.update(_dt)
  -- drag follows the live pointer when love.touch / mouse is available;
  -- touchmoved / mousemoved also update, so this is a belt-and-suspenders
  -- path for Android where move events can be thin
  if not Editor.drag then return end
  local x, y
  if love.touch and love.touch.getPosition and Editor.drag.touchId then
    local ok, tx, ty = pcall(love.touch.getPosition, Editor.drag.touchId)
    if ok and tx then x, y = tx, ty end
  end
  if not x and love.mouse then
    x, y = love.mouse.getPosition()
  end
  if x then
    TouchControls:setControlCenter(
      Editor.drag.name,
      x - Editor.drag.offX,
      y - Editor.drag.offY)
  end
end

function Editor.draw()
  local SafeArea = require("src.core.SafeArea")
  local fullW, fullH = love.graphics.getDimensions()
  local ox, oy, ww, wh = SafeArea.rect()
  local s = math.max(0.75, math.min(1.4, wh / 768))
  -- resolve the orientation bucket before any chrome reads scale (#633)
  local bucket = TouchControls:currentBucket()
  Editor.rects = {}

  -- radial-ish navy field (two stacked fills; matches launcher atmosphere)
  col(PAL.bgBot)
  love.graphics.rectangle("fill", 0, 0, fullW, fullH)
  col(PAL.bgTop, 0.85)
  love.graphics.circle("fill", ox + ww * 0.5, oy + wh * 0.15, math.max(ww, wh) * 0.55)

  local pad = 18 * s
  local barH = 56 * s
  local btnH = 40 * s
  local btnW = 100 * s

  -- top bar (inside the safe area so it clears the notch / status bar)
  col(PAL.card, 0.92)
  love.graphics.rectangle("fill", 0, 0, fullW, oy + barH + pad)
  col(PAL.stroke, 0.35)
  love.graphics.setLineWidth(1)
  love.graphics.line(0, oy + barH + pad, fullW, oy + barH + pad)

  love.graphics.setFont(Editor.fonts.title)
  col(PAL.white)
  love.graphics.print("Touch Controls", ox + pad, oy + pad + 4 * s)

  -- Done / Reset
  local done = { x = ox + ww - pad - btnW, y = oy + pad + (barH - btnH) / 2,
                 w = btnW, h = btnH }
  local reset = { x = done.x - 10 * s - btnW, y = done.y, w = btnW, h = btnH }
  Editor.rects.done, Editor.rects.reset = done, reset

  local function chromeBtn(r, label, fill)
    col(fill, 0.9)
    roundRect("fill", r.x, r.y, r.w, r.h, 8 * s)
    col(PAL.white, 0.2)
    roundRect("line", r.x, r.y, r.w, r.h, 8 * s)
    love.graphics.setFont(Editor.fonts.btn)
    col(PAL.white)
    local tw = Editor.fonts.btn:getWidth(label)
    love.graphics.print(label, r.x + (r.w - tw) / 2,
                        r.y + (r.h - Editor.fonts.btn:getHeight()) / 2)
  end
  chromeBtn(reset, "Reset", { 60, 70, 110 })
  chromeBtn(done, "Done", PAL.green)

  -- enable toggle card
  local cardY = oy + barH + pad + 14 * s
  local cardH = 64 * s
  local cardX, cardW = ox + pad, ww - 2 * pad
  col(PAL.card, 0.88)
  roundRect("fill", cardX, cardY, cardW, cardH, 12 * s)
  col(PAL.stroke, 0.4)
  roundRect("line", cardX, cardY, cardW, cardH, 12 * s)

  love.graphics.setFont(Editor.fonts.body)
  col(PAL.label)
  love.graphics.print("On-screen controls", cardX + 16 * s,
                      cardY + 12 * s)
  love.graphics.setFont(Editor.fonts.btn)
  local on = Editor.enabled
  col(on and PAL.green or PAL.red)
  love.graphics.print(on and "ON" or "OFF", cardX + 16 * s,
                      cardY + 34 * s)

  local toggleW = 110 * s
  local toggle = {
    x = cardX + cardW - 16 * s - toggleW,
    y = cardY + (cardH - btnH) / 2,
    w = toggleW, h = btnH,
  }
  Editor.rects.toggle = toggle
  chromeBtn(toggle, on and "Disable" or "Enable",
            on and PAL.red or PAL.green)

  -- size card (#633): -/+ resize every control in the orientation on
  -- screen; the heading names it so it is plain the other one is untouched
  local sizeY = cardY + cardH + 10 * s
  col(PAL.card, 0.88)
  roundRect("fill", cardX, sizeY, cardW, cardH, 12 * s)
  col(PAL.stroke, 0.4)
  roundRect("line", cardX, sizeY, cardW, cardH, 12 * s)

  love.graphics.setFont(Editor.fonts.body)
  col(PAL.label)
  local orient = TouchControls.orientation == "landscape"
    and "Landscape" or "Portrait"
  love.graphics.print("Button size (" .. orient .. ")",
                      cardX + 16 * s, sizeY + 12 * s)
  love.graphics.setFont(Editor.fonts.btn)
  col(PAL.white)
  love.graphics.print(
    string.format("%d%%", math.floor((bucket.scale or 1) * 100 + 0.5)),
    cardX + 16 * s, sizeY + 34 * s)

  local stepW = 52 * s
  local plus = { x = cardX + cardW - 16 * s - stepW,
                 y = sizeY + (cardH - btnH) / 2, w = stepW, h = btnH }
  local minus = { x = plus.x - 10 * s - stepW, y = plus.y, w = stepW, h = btnH }
  Editor.rects.sizeUp, Editor.rects.sizeDown = plus, minus
  chromeBtn(minus, "-", { 60, 70, 110 })
  chromeBtn(plus, "+", { 60, 70, 110 })

  -- hint
  love.graphics.setFont(Editor.fonts.body)
  col(PAL.label, 0.9)
  local hint = on
    and "Drag each button to reposition, -/+ to resize. Portrait and landscape are saved separately when you tap Done."
    or "Controls are hidden in-game. Enable them to show and edit the layout."
  love.graphics.printf(hint, ox + pad, sizeY + cardH + 12 * s, ww - 2 * pad, "left")

  -- the overlay itself (preview mode; dimmed when disabled)
  TouchControls:draw()

  -- highlight the control under drag
  if Editor.drag then
    local L = TouchControls:layout()
    local zone = L[Editor.drag.name]
    if zone then
      love.graphics.setLineWidth(3 * s)
      col(PAL.green, 0.85)
      love.graphics.circle("line", zone.cx, zone.cy, zone.w * 0.62)
    end
  end
end

local function beginDrag(id, x, y)
  -- chrome takes priority over controls
  if inside(Editor.rects.done, x, y) then close(); return end
  if inside(Editor.rects.reset, x, y) then resetLayout(); return end
  if inside(Editor.rects.toggle, x, y) then toggleEnabled(); return end
  if inside(Editor.rects.sizeDown, x, y) then
    TouchControls:nudgeScale(-TouchControls.SCALE_STEP); return
  end
  if inside(Editor.rects.sizeUp, x, y) then
    TouchControls:nudgeScale(TouchControls.SCALE_STEP); return
  end

  local name = TouchControls:hitTest(x, y)
  if not name then return end
  local zone = TouchControls:layout()[name]
  Editor.drag = {
    name = name,
    touchId = id,
    offX = x - zone.cx,
    offY = y - zone.cy,
  }
end

local function moveDrag(id, x, y)
  local d = Editor.drag
  if not d then return end
  if d.touchId ~= nil and id ~= nil and d.touchId ~= id then return end
  TouchControls:setControlCenter(d.name, x - d.offX, y - d.offY)
end

local function endDrag(id)
  local d = Editor.drag
  if not d then return end
  if d.touchId ~= nil and id ~= nil and d.touchId ~= id then return end
  Editor.drag = nil
end

function Editor.mousepressed(x, y, button)
  if button ~= 1 then return end
  beginDrag("mouse", x, y)
end

function Editor.mousemoved(x, y)
  if love.mouse.isDown(1) then moveDrag("mouse", x, y) end
end

function Editor.mousereleased(x, y, button)
  if button ~= 1 then return end
  endDrag("mouse")
end

function Editor.touchpressed(id, x, y)
  beginDrag(id, x, y)
end

function Editor.touchmoved(id, x, y)
  moveDrag(id, x, y)
end

function Editor.touchreleased(id, x, y)
  endDrag(id)
end

function Editor.keypressed(key)
  if key == "escape" or key == "return" or key == "space" then
    close()
  elseif key == "r" then
    resetLayout()
  -- desktop shortcuts for the size -/+ (POKEPORT_TOUCH=1 testing, #633)
  elseif key == "-" or key == "kp-" then
    TouchControls:nudgeScale(-TouchControls.SCALE_STEP)
  elseif key == "=" or key == "+" or key == "kp+" then
    TouchControls:nudgeScale(TouchControls.SCALE_STEP)
  end
end

return Editor
