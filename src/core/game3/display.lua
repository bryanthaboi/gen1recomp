-- Game3 display owner (FRLG-native 240×160).
-- Owns the presented frame when Runtime is active: own canvas, own letterbox,
-- own UI. Field map is composited under the UI; Gen2 Chrome/StartMenu are not used.

local GameViewport = require("src.render.GameViewport")

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
local ModRuntime = require("src.mods.Runtime")

local function sameZones(_, zones) return zones end

local function frameZones(game)
  if ModRuntime.wantsHook("render.zones") then
    return ModRuntime.call("render.zones", sameZones, game, nil)
  end
end

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

  local okPF, Playfield = pcall(require, "src.render.Playfield")
  if okPF and Playfield and Playfield.cutout then
    local vx, vy, vw, vh = Playfield.cutout(winW, winH)
    if vx and vw and vh and vw > 0 and vh > 0 then
      local k = math.max(1, math.floor(math.min(vw * dpiX / Display.W, vh * dpiY / Display.H) + 1e-9))
      local scaleX, scaleY = k / dpiX, k / dpiY
      local pw = Display.W * scaleX
      local ph = Display.H * scaleY
      local ox = vx + (vw - pw) * 0.5
      local oy = vy + (vh - ph) * 0.5
      ox = math.floor(ox * dpiX + 1e-9) / dpiX
      oy = math.floor(oy * dpiY + 1e-9) / dpiY
      return scaleX, ox, oy, pw, ph, scaleY
    end
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
    Renderer:endFrame(frameZones(game), nil, { generation = 3 })
  end)
  if ok then return true end
  love.graphics.setCanvas()
  Display.planesBroken = true
  log("plane present failed, falling back: " .. tostring(err))
  return false
end

local Pipelines = require("src.render.Pipelines")
local drawWorldPipeline  -- below drawFieldPlane

-- `fieldOpts` reaches FieldView.draw (skipActors / actorsOnly), and
-- `animate == false` skips this frame's sprite animation tick -- a render
-- pipeline may draw the field more than once per frame and must not make
-- every sprite animate twice as fast.
local function drawFieldPlane(game, vw, vh, Renderer, fieldOpts, animate)
  local Bg = require("src.core.game3.bg")
  local Oam = require("src.core.game3.oam")
  local FieldView = require("src.core.game3.field_view")
  local Tilt = require("src.render.Tilt")
  local Transition = package.loaded["src.core.game3.battle_transition"]
  local transitioning = Transition and Transition.isActive and Transition.isActive()
  Oam.resetFrame()
  local prev = Oam.setLayer("world")
  local function exchange(current, replacement)
    return Renderer and Renderer:exchangeWorldCanvas(current, replacement)
  end
  if Tilt.active() and not transitioning and Renderer and Renderer.beginUprightPass then
    FieldView.draw(game, vw, vh, { skipActors = true, exchangeCanvas = exchange })
    Renderer:beginUprightPass()
    FieldView.draw(game, vw, vh, {
      actorsOnly = true, billboard = true,
      endUnderActors = function(drawOverhead) Renderer:occludeUprightActors(drawOverhead) end,
    })
    Renderer:endUprightPass()
  else
    local opts = { exchangeCanvas = exchange }
    for k, v in pairs(fieldOpts or {}) do opts[k] = v end
    FieldView.draw(game, vw, vh, opts)
  end
  Oam.setLayer(prev)
  if animate ~= false then Oam.animateSprites("world") end
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

-- The Gen 3 half of the world-pipeline seam (docs/rfcs/0022): the same ctx
-- keys Gen 1 and Gen 2 hand a pipeline where they mean the same thing, plus
-- `drawField(opts)`, which draws the vanilla field plane -- tiles, sprites
-- and field effects, OAM included -- into whatever canvas is current, at
-- world-pixel scale.  `opts.skipActors` / `opts.actorsOnly` split it into
-- ground and actors.  Sprite animation ticks on the first call only.
drawWorldPipeline = function(game, id, vw, vh, Renderer)
  local FieldView = require("src.core.game3.field_view")
  local Map = require("src.core.game3.map")
  local _, _, pw, ph = Renderer:playfieldRect()
  local animated = false
  local ctx = {
    generation = 3,
    cam = FieldView.camera(game, vw, vh),
    vw = vw, vh = vh,
    width = pw, height = ph,
    scale = Renderer:fitScale(),
    level = Pipelines.level(id),
    map = Map.current,
    drawField = function(opts)
      love.graphics.push("all")
      love.graphics.origin()
      local ok, err = pcall(drawFieldPlane, game, vw, vh, nil, opts, not animated)
      animated = true
      love.graphics.pop()
      if not ok then error(err, 0) end
    end,
  }
  local override = Pipelines.drawWorld(id, ctx)
  if override then override = Pipelines.worldPresent(override, ctx) end
  return override
end

local uiRenderer
local uiPass
function Display.setUiRenderer(fn)
  uiRenderer = fn
end
local function drawUiPass()
  if uiRenderer then return uiRenderer() end
  if uiPass == nil then
    local ok, pass = pcall(require, "src.ui.game3.ui_pass")
    uiPass = (ok and type(pass) == "table") and pass or false
  end
  if uiPass and type(uiPass.drawUi) == "function" then uiPass.drawUi() end
end
Display.drawUiPass = drawUiPass

local function drawUiPlane()
  local Oam = require("src.core.game3.oam")
  local Help = require("src.ui.game3.help_system")
  local prev = Oam.setLayer("ui")
  drawUiPass()
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

  local battleActive = Battle.isActive()
  local Stack = package.loaded["src.ui.game3.stack"]
  local MG = package.loaded["src.core.game3.minigames.common"]
  local mgRun = type(MG) == "table" and MG._run or nil
  local minigameActive = not battleActive and type(mgRun) == "table" and mgRun.stage ~= "enter"
    and Stack ~= nil and Stack.has ~= nil and Stack.has("minigame")
  local uiOnly = minigameActive or (not battleActive and Stack ~= nil
    and Stack.fullscreen ~= nil and Stack.fullscreen())
  local Shop = package.loaded["src.ui.game3.shop_menu"]
  local shopView = not battleActive and not uiOnly and Shop ~= nil
    and Shop.isShopCamera ~= nil and Shop.isShopCamera()
  local Renderer = prepareRenderer(game, battleActive and "battle" or "field")
  Renderer:beginFrame(not battleActive and not uiOnly and not shopView)

  if battleActive then
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.clear(0.06, 0.12, 0.20, 1)
    Oam.resetFrame()
    Battle.draw(game, Display.W, Display.H)
    drawUiPass()
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
    Renderer:endFrame(frameZones(game), nil, { generation = 3 })
    Display.mirrorFlatFrame(Renderer)
    return
  end

  if uiOnly or shopView then
    love.graphics.push("all")
    love.graphics.origin()
    -- pokeemerald/src/shop.c:781
    if shopView then drawFieldPlane(game, Display.W, Display.H, nil) end
    drawUiPlane()
    love.graphics.pop()
    Renderer:endFrame(frameZones(game), nil, { generation = 3 })
    Display.mirrorFlatFrame(Renderer)
    return
  end

  Renderer:beginWorldPass()
  love.graphics.push("all")
  love.graphics.origin()
  local vw, vh = Renderer:worldViewSize()
  local Transition = package.loaded["src.core.game3.battle_transition"]
  local Fade = package.loaded["src.ui.game3.fade"]
  local override = nil
  -- A render pipeline (src/render/Pipelines.lua) may own the field plane,
  -- exactly as on Gen 1 and Gen 2: it hands back one finished window-size
  -- image (composited by Renderer:endFrame like Gen 1's worldOverride) or
  -- nil to leave this frame to the vanilla draw.  The battle transition and
  -- the barn-door wipe paint onto the world canvas, so they keep the
  -- vanilla plane for the few frames they run.
  local transitioning = (Transition and Transition.isActive and Transition.isActive())
    or (Fade and Fade.barnDoorWipeActive and Fade.barnDoorWipeActive())
  local pipelineId = not transitioning and Pipelines.worldPipeline() or nil
  if pipelineId then
    override = drawWorldPipeline(game, pipelineId, vw, vh, Renderer)
    -- setWorldOverride rejects a non-canvas return; the vanilla plane then
    -- draws as if the pipeline had declined, never a blank world
    Renderer:setWorldOverride(override)
    override = Renderer.worldOverride
  end
  -- with no world pipeline on, this is the vanilla frame, call for call
  if not override then drawFieldPlane(game, vw, vh, Renderer) end
  love.graphics.pop()
  love.graphics.setCanvas(Renderer.worldCanvas)
  if Transition and Transition.isActive and Transition.isActive() then
    Transition.drawWorld(Renderer.worldCanvas, vw, vh)
  end
  if Fade and Fade.barnDoorWipeActive and Fade.barnDoorWipeActive() then
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setCanvas(Renderer.worldCanvas)
    Fade.drawWorldWipe(vw, vh)
    love.graphics.pop()
  end
  Renderer:endWorldPass()

  love.graphics.push("all")
  love.graphics.origin()
  drawUiPlane()
  love.graphics.pop()
  Renderer:endFrame(frameZones(game), nil, { generation = 3 })
  Display.mirrorFlatFrame(Renderer)
end

-- The plane path presents straight from Renderer's canvases; the flat 240x160
-- copy is only for test drivers that read Display._canvas back.
Display.mirrorForTests = false

function Display.mirrorFlatFrame(Renderer)
  if not Display.mirrorForTests then return end
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

local function presentFlatHooks(game, canvas, winW, winH, worldActive)
  local composing = ModRuntime.wantsHook("render.compose")
  local output = ModRuntime.wantsHook("render.output")
  local letterbox = ModRuntime.wantsHook("render.letterbox")
  local Pipelines = require("src.render.Pipelines")
  local presenting = Pipelines.wantsPresent()
  if not (composing or output or letterbox or ModRuntime.wantsHook("render.zones") or presenting) then
    return false
  end

  local zones = frameZones(game)
  local Renderer = require("src.render.Renderer")
  local renderer = setmetatable({
    canvas = canvas, worldCanvas = canvas, worldActive = worldActive, uiOpaque = true,
  }, { __index = Renderer })
  local scale, ox, oy, vpw, vph, scaleY = Display.fit(winW, winH)
  local dpiX, dpiY = 1, 1
  local gw, gh = love.graphics.getDimensions()
  if gw > 0 and gh > 0 and love.graphics.getPixelDimensions then
    local pw, ph = love.graphics.getPixelDimensions()
    if pw and pw > 0 then dpiX = pw / gw end
    if ph and ph > 0 then dpiY = ph / gh end
  elseif love.graphics.getDPIScale then
    local dpi = tonumber(love.graphics.getDPIScale())
    if dpi and dpi > 1e-6 then dpiX, dpiY = dpi, dpi end
  end
  local ctx = {
    renderer = renderer, worldCanvas = canvas, uiCanvas = canvas,
    worldActive = worldActive, zones = zones,
    ww = winW, wh = winH, pw = winW * dpiX, ph = winH * dpiY,
    ox = ox, oy = oy, vpw = vpw, vph = vph, uiw = Display.W, uih = Display.H,
    scale = scale * dpiX, Sx = scale, Sy = scaleY, dpiX = dpiX, dpiY = dpiY,
    viewX = 0, viewY = 0, viewWidth = winW, viewHeight = winH,
    generation = 3, sceneCanvas = canvas,
  }
  local G = love.graphics
  local previous = G.getCanvas()
  G.push("all")
  local ok, err = xpcall(function()
    G.origin()
    G.setShader()
    G.setScissor()
    G.setColor(1, 1, 1, 1)
    local function call(name, vanilla, ...)
      local target = G.getCanvas()
      G.push("all")
      local okCall, result = pcall(ModRuntime.call, name, vanilla, ...)
      G.setCanvas(target)
      G.pop()
      if not okCall then error(result) end
      return result
    end
    if composing then
      ctx.secondScreen = require("src.render.SecondScreen")
      if call("render.compose", function() return false end, renderer, ctx) == true then return end
    end
    local hasOutput = output
      and call("render.output_enabled", function() return false end) == true
    local present
    if hasOutput or presenting then
      present = Display._presentCanvas
      if not present or present:getWidth() ~= winW or present:getHeight() ~= winH then
        present = G.newCanvas(winW, winH, { dpiscale = dpiY })
        present:setFilter("linear", "linear")
        Display._presentCanvas = present
      end
      G.setCanvas(present)
    end
    G.setColor(0.02, 0.04, 0.08, 1)
    G.rectangle("fill", 0, 0, winW, winH)
    G.setColor(1, 1, 1, 1)
    if letterbox then
      call("render.letterbox", function() end, ctx)
    end
    if zones and zones[1] then
      renderer:blitCanvas(canvas, scale, scaleY, zones, scale, scaleY,
        ox, oy, math.max(0, ox), math.max(0, oy),
        math.max(0, math.min(winW, ox + vpw) - math.max(0, ox)),
        math.max(0, math.min(winH, oy + vph) - math.max(0, oy)), dpiX, dpiY)
    else
      G.draw(canvas, ox, oy, 0, scale, scaleY)
    end
    if present then
      G.setCanvas(previous)
      G.push("all")
      local okPresent, composed = pcall(Pipelines.present, present, {
        width = winW, height = winH, scale = scale * dpiX,
        dpi = dpiY, dpiX = dpiX, dpiY = dpiY, generation = 3,
      })
      G.setCanvas(previous)
      G.pop()
      if not okPresent then error(composed) end
      composed = composed or present
      local outputHandled = hasOutput and call("render.output", function() return false end, {
        canvas = composed, width = winW, height = winH,
        gameX = ox, gameY = oy, gameWidth = vpw, gameHeight = vph,
        scale = scale * dpiX, dpiX = dpiX, dpiY = dpiY, generation = 3,
      }) == true
      if not outputHandled then
        G.setColor(1, 1, 1, 1)
        G.draw(composed, 0, 0)
      end
    end
  end, debug.traceback)
  G.setCanvas(previous)
  G.pop()
  if not ok then error(err) end
  return true
end

function Display.presentCanvas(game, canvas, winW, winH, worldActive)
  if GameViewport.active() then GameViewport.setTarget() end
  if presentFlatHooks(game, canvas, winW, winH, worldActive) then return true end

  love.graphics.setColor(0.02, 0.04, 0.08, 1)
  love.graphics.rectangle("fill", 0, 0, winW, winH)
  local scale, ox, oy, _, _, scaleY = Display.fit(winW, winH)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, ox, oy, 0, scale, scaleY)
  return true
end

local function presentFlat(game, winW, winH)
  local canvas = Display.ensureCanvas("main")
  if not canvas then return false end

  local worldActive = false
  beginOn(canvas)
  local ok, err = xpcall(function()
    local Help = require("src.ui.game3.help_system")
    if Help.isOpen() then Help.draw(); return end
    love.graphics.clear(0.06, 0.12, 0.20, 1)

    local Oam = require("src.core.game3.oam")
    local Bg = require("src.core.game3.bg")
    Oam.resetFrame()

    local Battle = require("src.core.game3.battle")
    worldActive = not Battle.isActive()
    if not worldActive then
      Battle.draw(game, Display.W, Display.H)
    else
      local FieldView = require("src.core.game3.field_view")
      FieldView.draw(game, Display.W, Display.H)
    end

    drawUiPass()

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

  return Display.presentCanvas(game, canvas, winW, winH, worldActive)
end

Display.presentFlat = presentFlat

function Display.present(game, winW, winH)
  local Stream = package.loaded["src.core.game3.asset_stream"]
  if Stream then Stream.frameComplete() end
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
  for _, key in ipairs({ "_canvas", "_uiOnly", "_presentCanvas" }) do
    local canvas = Display[key]
    if canvas then
      pcall(function() canvas:release() end)
      Display[key] = nil
    end
  end
  Display._logged = false
end

return Display
