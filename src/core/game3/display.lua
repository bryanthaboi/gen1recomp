-- Game3 display owner (FRLG-native 240×160).
-- Owns the presented frame when Runtime is active: own canvas, own letterbox,
-- own UI. Field map is composited under the UI; Gen2 Chrome/StartMenu are not used.

local Display = {}

Display.W = 240
Display.H = 160
Display.TILE = 8
Display.COLS = 30
Display.ROWS = 20

Display._canvas = nil
Display._uiOnly = nil -- secondary canvas for UI layer when field is drawn by host
Display._logged = false

local function log(msg)
  print("[game3/display] " .. tostring(msg))
end

function Display.ensureCanvas(which)
  which = which or "main"
  local key = which == "ui" and "_uiOnly" or "_canvas"
  local existing = Display[key]
  if existing then
    local ok, cw, ch = pcall(function()
      return existing:getWidth(), existing:getHeight()
    end)
    if ok and cw == Display.W and ch == Display.H then
      return existing
    end
  end
  local ok, canvas = pcall(love.graphics.newCanvas, Display.W, Display.H, { dpiscale = 1 })
  if not ok or not canvas then
    log("FAILED canvas create")
    return nil
  end
  canvas:setFilter("nearest", "nearest")
  Display[key] = canvas
  if not Display._logged then
    log("owned FRLG frame " .. Display.W .. "x" .. Display.H
      .. " (not Gen2 160x144)")
    Display._logged = true
  end
  return canvas
end

local SafeArea = require("src.core.SafeArea")

function Display.fit(winW, winH)
  local gw, gh = 0, 0
  if love and love.graphics and love.graphics.getDimensions then
    gw, gh = love.graphics.getDimensions()
  end
  winW = winW or (gw > 0 and gw or Display.W)
  winH = winH or (gh > 0 and gh or Display.H)

  local safeX, safeY, safeW, safeH = 0, 0, winW, winH
  if gw > 0 and gh > 0 and winW == gw and winH == gh then
    local sx, sy, sw, sh = SafeArea.windowRect()
    if sw and sw > 0 and sh and sh > 0 then
      safeX, safeY, safeW, safeH = sx, sy, sw, sh
    end
  end

  local dpiX, dpiY = 1, 1
  if gw > 0 and gh > 0 and love.graphics.getPixelDimensions then
    local fw, fh = love.graphics.getPixelDimensions()
    if fw and fw > 0 then dpiX = fw / gw end
    if fh and fh > 0 then dpiY = fh / gh end
  elseif love and love.graphics and love.graphics.getDPIScale then
    local d = tonumber(love.graphics.getDPIScale())
    if d and d > 1e-6 then dpiX, dpiY = d, d end
  end

  local isPortrait = safeH > safeW
  local k, ox, oy, pw, ph, scaleX, scaleY

  if isPortrait then
    -- On mobile portrait, scale to fit the available safe width cleanly.
    k = math.max(1, math.floor(safeW * dpiX / Display.W + 1e-9))
    scaleX, scaleY = k / dpiX, k / dpiY
    pw = Display.W * scaleX
    ph = Display.H * scaleY
    ox = safeX + (safeW - pw) * 0.5
    -- In portrait, center the screen in the upper deck area (above the touch controls deck).
    local topDeckH = safeH * 0.48
    oy = safeY + math.max(4, (topDeckH - ph) * 0.5)
  else
    -- Landscape / desktop: fit cleanly within safe area
    k = math.max(1, math.floor(math.min(safeW * dpiX / Display.W, safeH * dpiY / Display.H) + 1e-9))
    scaleX, scaleY = k / dpiX, k / dpiY
    pw = Display.W * scaleX
    ph = Display.H * scaleY
    ox = safeX + (safeW - pw) * 0.5
    oy = safeY + (safeH - ph) * 0.5
  end
  ox = math.floor(ox * dpiX + 1e-9) / dpiX
  oy = math.floor(oy * dpiY + 1e-9) / dpiY

  return scaleX, ox, oy, pw, ph, scaleY
end

local function beginOn(canvas)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.origin()
  love.graphics.setColor(1, 1, 1, 1)
end

local function endCanvas()
  love.graphics.setCanvas()
  love.graphics.pop()
end

--- GBA-style compositor: for priority 3→0, draw BGs then OBJs at that priority.
-- Lower priority number composites in front. Same priority: OBJ above BG.
-- opts:
--   animate (bool, default true) — run Oam.animateSprites
--   build (bool, default true) — rebuild OAM buffer
--   clear (r,g,b,a table) — clear before compose
--   scissor {x,y,w,h} — WIN-style clip
--   underlay function() — drawn behind all BG/OBJ (rare)
--   overlay function() — drawn after all BG/OBJ (fades, blend approximates)
function Display.composeHardware(opts)
  opts = opts or {}
  local Bg = require("src.core.game3.bg")
  local Oam = require("src.core.game3.oam")

  if opts.clear then
    local c = opts.clear
    love.graphics.clear(c[1] or 0, c[2] or 0, c[3] or 0, c[4] or 1)
  end

  if opts.underlay then
    opts.underlay()
  end

  if opts.animate ~= false then
    Oam.animateSprites()
  end
  if opts.build ~= false then
    Oam.buildOamBuffer(opts.pretOrder)
  end

  if opts.scissor then
    local s = opts.scissor
    love.graphics.setScissor(s.x, s.y, s.w, s.h)
  end

  -- Back → front: pri 3,2,1,0. Within each: BG then OBJ.
  for pri = 3, 0, -1 do
    Bg.flushPriority(pri)
    Oam.flushPriority(pri)
  end

  if opts.scissor then
    love.graphics.setScissor()
  end

  if opts.overlay then
    opts.overlay()
  end
end

function Display.surround(game, kind)
  local paper = nil
  if kind == "boot" or kind == "quest" then
    paper = { 0, 0, 0 }
  elseif kind == "battle" then
    paper = { 0.92, 0.94, 0.96 }
  end
  if not paper then return false, nil end
  return { letterboxWhite = true }, function()
    return paper[1], paper[2], paper[3]
  end
end

Display.planesBroken = false

local function prepareRenderer(game, kind)
  local Renderer = require("src.render.Renderer")
  if not Renderer.canvas then Renderer:init() end
  local okP, PaletteFX = pcall(require, "src.render.PaletteFX")
  if okP and PaletteFX then
    if PaletteFX.mode ~= "gbc" and PaletteFX.setMode then
      PaletteFX.setMode("gbc")
    end
    if PaletteFX.setCustomRamp then pcall(PaletteFX.setCustomRamp, nil) end
  end
  Renderer:setUISize(Display.W, Display.H)
  local opts = (game and game.options) or {}
  Renderer.uiCentered = (opts.uiLayout ~= "dynamic")
  Renderer.uiFill = false
  Renderer.uiWorldHold = false
  Renderer.battleDim = nil
  Renderer.extendedWorldBand = false
  local state, paper = Display.surround(game, kind)
  Renderer.surroundState = state
  Renderer.paperShade = paper
  return Renderer
end

function Display.presentUi(game, winW, winH, kind, drawFn)
  if Display.planesBroken then return false end
  local Renderer = require("src.render.Renderer")
  local ok, err = pcall(function()
    prepareRenderer(game, kind)
    Renderer:beginFrame(false)
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setColor(1, 1, 1, 1)
    drawFn()
    love.graphics.pop()
    Renderer:endFrame(nil, nil)
  end)
  if ok then return true end
  love.graphics.setCanvas()
  Display.planesBroken = true
  log("plane present failed, falling back: " .. tostring(err))
  return false
end

local function drawFieldPlane(game, vw, vh, Renderer)
  local Bg = require("src.core.game3.bg")
  local Oam = require("src.core.game3.oam")
  local FieldView = require("src.core.game3.field_view")
  local Tilt = require("src.render.Tilt")
  local Transition = package.loaded["src.core.game3.battle_transition"]
  local transitioning = Transition and Transition.isActive and Transition.isActive()
  Oam.resetFrame()
  local prev = Oam.setLayer("world")
  if Tilt.active() and not transitioning and Renderer and Renderer.beginUprightPass then
    FieldView.draw(game, vw, vh, { skipActors = true })
    Renderer:beginUprightPass()
    FieldView.draw(game, vw, vh, { actorsOnly = true, billboard = true })
    Renderer:endUprightPass()
  else
    FieldView.draw(game, vw, vh)
  end
  Oam.setLayer(prev)
  Oam.animateSprites("world")
  Oam.buildOamBuffer()
  if Bg.hasVisible() then
    for pri = 3, 0, -1 do
      Bg.flushPriority(pri)
      Oam.flushPriority(pri, "world")
    end
  else
    Oam.flush("world")
  end
end

local function drawUiPlane()
  local Oam = require("src.core.game3.oam")
  local Gfx = require("src.core.game3.gfx")
  local Help = require("src.ui.game3.help_system")
  local prev = Oam.setLayer("ui")
  Gfx.drawUi()
  if Help.isOpen() then Help.draw() end
  Oam.setLayer(prev)
  Oam.animateSprites("ui")
  Oam.buildOamBuffer()
  Oam.flush("ui")
end

local function presentPlanes(game)
  local Help = require("src.ui.game3.help_system")
  local Battle = require("src.core.game3.battle")
  local Oam = require("src.core.game3.oam")
  local Bg = require("src.core.game3.bg")
  local Gfx = require("src.core.game3.gfx")

  local battleActive = Battle.isActive()
  local Renderer = prepareRenderer(game, battleActive and "battle" or "field")
  Renderer:beginFrame(not battleActive)

  if battleActive then
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.clear(0.06, 0.12, 0.20, 1)
    Oam.resetFrame()
    Battle.draw(game, Display.W, Display.H)
    Gfx.drawUi()
    if Help.isOpen() then Help.draw() end
    Oam.animateSprites()
    Oam.buildOamBuffer()
    if Bg.hasVisible() then
      for pri = 3, 0, -1 do
        Bg.flushPriority(pri)
        Oam.flushPriority(pri)
      end
    else
      Oam.flush()
    end
    love.graphics.pop()
    Renderer:endFrame(nil, nil)
    Display.mirrorFlatFrame(Renderer)
    return
  end

  Renderer:beginWorldPass()
  love.graphics.push("all")
  love.graphics.origin()
  local vw, vh = Renderer:worldViewSize()
  drawFieldPlane(game, vw, vh, Renderer)
  love.graphics.pop()
  local Transition = package.loaded["src.core.game3.battle_transition"]
  if Transition and Transition.isActive and Transition.isActive() then
    Transition.drawWorld(Renderer.worldCanvas, vw, vh)
  end
  Renderer:endWorldPass()

  love.graphics.push("all")
  love.graphics.origin()
  drawUiPlane()
  love.graphics.pop()
  Renderer:endFrame(nil, nil)
  Display.mirrorFlatFrame(Renderer)
end

function Display.mirrorFlatFrame(Renderer)
  local canvas = Display.ensureCanvas("main")
  if not canvas then return end
  local world = Renderer.worldCanvas
  local ui = Renderer.canvas
  if not ui then return end
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.setBlendMode("alpha")
  love.graphics.clear(0, 0, 0, 1)
  love.graphics.setColor(1, 1, 1, 1)
  if world and Renderer.worldActive then
    local ok, vw, vh = pcall(function()
      return world:getWidth(), world:getHeight()
    end)
    if ok and vw and vh then
      love.graphics.draw(world,
        math.floor((Display.W - vw) / 2), math.floor((Display.H - vh) / 2))
    end
  end
  love.graphics.draw(ui, 0, 0)
  love.graphics.setCanvas()
  love.graphics.pop()
end

local function presentFlat(game, winW, winH)
  local canvas = Display.ensureCanvas("main")
  if not canvas then return false end

  beginOn(canvas)
  local ok, err = xpcall(function()
    local Help = require("src.ui.game3.help_system")
    if Help.isOpen() then Help.draw(); return end
    love.graphics.clear(0.06, 0.12, 0.20, 1)

    local Oam = require("src.core.game3.oam")
    local Bg = require("src.core.game3.bg")
    Oam.resetFrame()

    local Battle = require("src.core.game3.battle")
    if Battle.isActive() then
      Battle.draw(game, Display.W, Display.H)
    else
      local FieldView = require("src.core.game3.field_view")
      FieldView.draw(game, Display.W, Display.H)
    end

    local Gfx = require("src.core.game3.gfx")
    Gfx.drawUi()

    -- Animate after UI so party can attach bounce callbacks this frame.
    Oam.animateSprites()
    Oam.buildOamBuffer()
    if Bg.hasVisible() then
      for pri = 3, 0, -1 do
        Bg.flushPriority(pri)
        Oam.flushPriority(pri)
      end
    else
      Oam.flush()
    end
  end, debug.traceback)
  endCanvas()
  if not ok then
    error(err)
  end

  -- Void bars + blit our frame (game3 letterbox, not Gen2 Playfield).
  love.graphics.setColor(0.02, 0.04, 0.08, 1)
  love.graphics.rectangle("fill", 0, 0, winW, winH)
  local scale, ox, oy, _, _, scaleY = Display.fit(winW, winH)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, ox, oy, 0, scale, scaleY)
  return true
end

Display.presentFlat = presentFlat

function Display.present(game, winW, winH)
  if not Display.planesBroken then
    local ok, err = pcall(presentPlanes, game)
    if ok then return true end
    love.graphics.setCanvas()
    Display.planesBroken = true
    log("plane present failed, falling back: " .. tostring(err))
  end
  return presentFlat(game, winW, winH)
end

function Display.release()
  for _, key in ipairs({ "_canvas", "_uiOnly" }) do
    local canvas = Display[key]
    if canvas then
      pcall(function() canvas:release() end)
      Display[key] = nil
    end
  end
  Display._logged = false
end

return Display
