-- The launcher's view, drawn with the shared immediate-mode kit
-- (src/ui/kit/).  RomImporter owns every piece of state and all
-- import/platform logic; this module paints that state once per frame, so the
-- UI can never drift from the importer and every window size lays out fresh.
--
-- WHAT CHANGED, AND WHY.  This used to build a retained FlexLove element tree
-- every frame.  That cost ~9ms of build+draw on a real profile before a
-- single row of content existed (measure it yourself: POKEPORT_LAUNCHER_PROF=
-- 200 love .), because the engine hashed props per element, snapshotted every
-- public scalar for its immediate-mode persistence, and re-ran an O(n^2)
-- auto-size pass.  Painting the same screen directly is a small fraction of
-- that, and it removes a whole class of layout bug along with it: percentage
-- widths resolving against the wrong box, auto-sized buttons measuring zero
-- height, and flex-shrink compressing text until it overlapped.
--
-- THE RULES THIS FILE FOLLOWS:
--   * Lists paginate (Kit.pager).  The installed-mod list also scrolls inside
--     its viewport, so each of its pages can hold at least ten entries without
--     requiring a tall window.  Pages still bound how many mod rows we visit.
--   * Every click handler only QUEUES work (imp._uiActions); update() drains
--     the queue, so an action that tears the view down (Play, Edit save)
--     never runs inside the frame that dispatched it.
--   * Clicks are deduped per control key: a touch tap can surface as both a
--     touch release and a synthesized mouse click, and one action must not
--     fire twice (the shape of #553's double import).
--   * Anything that waits raises a non-dismissable loader (Loader.overlay),
--     driven by imp._busy / imp.workState.
--   * Layout is explicit pixels off Layout.metrics.  No percentages.

local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Layout = require("src.ui.kit.Layout")
local Loader = require("src.ui.kit.Loader")
local GameVersion = require("src.core.GameVersion")
local Version = require("src.core.Version")
local Strings = require("src.core.Strings")

local PAL = Theme.PAL
local LauncherView = {}

local COMMUNITY_URL = "https://bois.icu"

-- One dedup window covers a touch release plus the mouse click SDL
-- synthesizes for the same tap.
local ACT_DEDUP = 0.35
-- Finger travel past this (px) is a drag, not a tap.
local TAP_SLOP2 = 16 * 16
-- Installed mods should not turn into a one- or two-item pager on a compact
-- display.  Keep a useful page size, then let the list viewport scroll.
local MIN_MODS_PER_PAGE = 10

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function inRect(rect, x, y)
  return rect ~= nil and x >= rect.x and x <= rect.x + rect.w
    and y >= rect.y and y <= rect.y + rect.h
end

-- ------------------------------------------------------------- lifecycle

local function ensureState(imp)
  if not imp._flex then
    imp._flex = true
    imp._hot = imp._hot or {}
    imp._actAt = imp._actAt or {}
    imp._uiActions = imp._uiActions or {}
    imp._pages = imp._pages or {}
    -- Held backspace/arrows must repeat in the text fields; restored on
    -- detach because the game's Input does its own per-step edge detection
    -- and never expects repeated keypressed events.
    if love.keyboard and love.keyboard.setKeyRepeat then
      pcall(love.keyboard.setKeyRepeat, true)
    end
  end
end

-- Kept as a no-op hook: the engine tier asserts this exists, and the guards
-- it used to apply were FlexLove's (performance monitoring, GC tuning).  The
-- kit has neither a profiler nor a GC strategy to tune -- it does not
-- allocate per frame -- so there is nothing left to guard.
function LauncherView.applyNxPerfGuards(imp)
  return imp ~= nil
end

-- Tear down before handing the screen to the game / editor.
function LauncherView.detach(imp)
  -- Restore the NX mouse shim even if _flex was never set (the bridge can
  -- install on the first update before the first draw).
  if imp and imp.parkNxPointerForHost then
    pcall(imp.parkNxPointerForHost, imp)
  elseif imp and imp._restoreNxPointerBridge then
    pcall(imp._restoreNxPointerBridge, imp)
  end
  if not imp or not imp._flex then return end
  imp._flex = nil
  if love.keyboard and love.keyboard.setKeyRepeat then
    pcall(love.keyboard.setKeyRepeat, false)
  end
  Kit.clearCaches()
end

-- ---------------------------------------------------------------- input
-- The kit is polled, not evented: update() samples the mouse and turns a
-- rising edge into a click point that the next draw consumes.  Host-forwarded
-- mousepressed stays unused, exactly as before, so Android's synthesized
-- mouse path cannot double-fire a tap (#553) -- the dedup window below is the
-- other half of that guarantee.
function LauncherView.update(imp, dt)
  if not imp._flex then return end
  if imp._launchFade then return end

  local down = false
  if love.mouse and love.mouse.isDown then
    down = love.mouse.isDown(1) and true or false
  end
  if down and not imp._prevMouseDown and not imp._padCursorActive then
    -- On touch platforms SDL synthesizes a mouse button from the finger, so
    -- this rising edge fires at finger-DOWN while touchreleased dispatches
    -- the same tap again at finger-UP: every control acted twice per tap
    -- (the pager visibly jumped two pages).  While a touch is alive, or
    -- inside the dedup window one just closed, the polled mouse IS that
    -- finger and must not mint a second click.  A real desktop mouse has no
    -- touches, so its press-down click is unchanged.
    -- _suppressMouseUntil, NOT _suppressClickUntil: the latter is consulted
    -- by queueAction and would swallow the tap's own action along with the
    -- synthesized echo.
    local now = love.timer.getTime()
    local touching = imp._touchAt ~= nil and next(imp._touchAt) ~= nil
    if not touching and now >= (imp._suppressMouseUntil or 0)
        and now >= (imp._suppressClickUntil or 0) then
      local mx, my = love.mouse.getPosition()
      imp._clickPt = { x = mx, y = my }
    end
  end
  imp._prevMouseDown = down

  -- Drain the action queue OUTSIDE the draw, so an action is free to destroy
  -- the view (Play/Edit) or block in a native picker.  The batch is resolved
  -- by RomImporter:runActions so the drop/disarm rules stay testable without
  -- a live view (#780).
  local queue = imp._uiActions
  if queue and #queue > 0 then
    imp._uiActions = {}
    imp:runActions(queue)
  end
end

function LauncherView.wheelmoved(imp, dx, dy)
  if not imp._flex then return end
  imp._wheelY = (imp._wheelY or 0) + (dy or 0)
end

function LauncherView.touchpressed(imp, id, x, y)
  if not imp._flex then return end
  imp._touchAt = imp._touchAt or {}
  imp._touchAt[tostring(id)] = {
    x = x, y = y,
    modsList = (imp._modScrollMax or 0) > 0 and inRect(imp._modListRect, x, y),
  }
end

function LauncherView.touchmoved(imp, id, x, y)
  if not imp._flex then return end
  local start = imp._touchAt and imp._touchAt[tostring(id)]
  if start then
    local ddx, ddy = x - start.x, y - start.y
    if ddx * ddx + ddy * ddy > TAP_SLOP2 then
      start.dragged = true
    end
    -- A drag that began in the installed-mod viewport scrolls that page's
    -- rows.  Its pager remains available for moving to the next ten-plus
    -- entries; a drag elsewhere keeps the normal short-window page scroll.
    if start.dragged and start.modsList then
      local last = start.lastY or start.y
      imp.modScroll = clamp((imp.modScroll or 0) - (y - last), 0,
        imp._modScrollMax or 0)
    elseif start.dragged and (imp._pageScrollMax or 0) > 0 then
      local last = start.lastY or start.y
      imp._pageScroll = (imp._pageScroll or 0) - (y - last)
    end
    start.lastY = y
  end
end

-- A tap dispatches on RELEASE (not press) so a drag can disqualify it.
function LauncherView.touchreleased(imp, id, x, y)
  if not imp._flex then return end
  local start = imp._touchAt and imp._touchAt[tostring(id)]
  if imp._touchAt then imp._touchAt[tostring(id)] = nil end
  if start and start.dragged then
    -- Suppress the mouse click SDL will synthesize for this same gesture.
    imp._suppressClickUntil = love.timer.getTime() + ACT_DEDUP
    return
  end
  -- The tap dispatches HERE, once: suppress update()'s rising-edge path for
  -- the mouse press SDL synthesizes from this same gesture.  Mouse-only
  -- suppression -- _suppressClickUntil would also make queueAction drop the
  -- tap's own action.
  imp._suppressMouseUntil = love.timer.getTime() + ACT_DEDUP
  imp._clickPt = { x = x, y = y }
end

-- Synthetic click for the gamepad virtual cursor.
function LauncherView.clickAt(imp, x, y)
  if not imp._flex then return end
  imp._clickPt = { x = x, y = y }
end

-- Keyboard focus ring.  Returns true when the key was consumed.  Arrows arm
-- the ring; Enter only activates a focused control once the user has actually
-- used the arrows this session, so the long-standing "Enter plays the visible
-- game" shortcut keeps working for anyone who never touches the ring.
function LauncherView.keypressed(imp, key)
  if not imp._flex then return false end
  if key == "up" or key == "down" or key == "left" or key == "right" then
    imp._ringArmed = true
    Kit.navigate(key)
    return true
  end
  if imp._ringArmed and (key == "return" or key == "kpenter" or key == "space") then
    Kit.activateFocused()
    return true
  end
  return false
end

-- ------------------------------------------------------------- actions

local function queueAction(imp, key, fn, keepArm)
  local now = love.timer.getTime()
  local last = imp._actAt[key]
  if last and now - last < ACT_DEDUP then return end
  local untilT = imp._suppressClickUntil
  if untilT and now < untilT then return end
  imp._actAt[key] = now
  -- Any press that is not a Delete's own second click disarms the pending
  -- delete confirm (#433's rule).  The disarm is applied by runActions when
  -- the batch drains, not here: one touch lands on a row AND on the chip
  -- inside it, and clearing the arm as the row queued left Delete stuck on
  -- its first press (#780).
  imp._uiActions[#imp._uiActions + 1] = { key = key, fn = fn, keepArm = keepArm }
end

-- Every interactive control in this file goes through one of these two, so
-- the queueing and dedup rules cannot be forgotten at a call site.
local function btn(imp, x, y, w, h, key, label, opts)
  opts = opts or {}
  opts.id = key
  if Kit.button(x, y, w, h, label, opts) and opts.action then
    queueAction(imp, key, opts.action, opts.keepArm)
  end
end

local function rowHit(imp, x, y, w, h, selected, key, action)
  local clicked, ink = Kit.row(x, y, w, h, selected, key)
  if clicked and action then queueAction(imp, key, action) end
  return ink
end

-- ------------------------------------------------------- shared widgets

-- Read-only text field.  The importer owns the string (its textinput /
-- keypressed routing writes it); this only renders it, keeps the TAIL
-- visible while typing, and blinks a caret on the importer's pulse clock.
local function textField(imp, x, y, w, h, key, rawText, placeholder, focused, action)
  Kit._audit("control", x, y, w, h, key)
  Kit.focusable(key, x, y, w, h)
  Theme.fill(x, y, w, h, PAL.bg, 1)
  Theme.stroke(x, y, w, h, PAL.line,
    focused and Theme.A.focus or
      (Kit.hover(x, y, w, h) and Theme.A.hover or Theme.A.hairline),
    focused and 2 or 1)
  local pad = math.floor(10 * Kit.scale)
  local ty = y + (h - Kit.textHeight("button")) / 2
  local text = rawText or ""
  if text == "" and not focused then
    Kit.text("button", Kit.ellipsize("button", placeholder or "", w - 2 * pad),
      x + pad, ty, PAL.faint)
  else
    local shown = Kit.ellipsizeLeft("button", text, w - 2 * pad)
    local tw = Kit.text("button", shown, x + pad, ty, PAL.heading)
    if focused and (imp.pulse * 2 % 1) < 0.5 then
      Theme.fill(x + pad + tw + 2, ty, math.max(1, Kit.scale),
        Kit.textHeight("button"), PAL.ink, 1)
    end
  end
  if action and (Kit.press(x, y, w, h) or Kit._activateId == key) then
    queueAction(imp, key, action)
  end
end

local CART_COLOR = {
  red = PAL.railRed, blue = PAL.railBlue, yellow = PAL.railGold,
  gold = PAL.railAmber,
}
local function cartColor(version)
  return CART_COLOR[version] or PAL.green
end

local CART_DRAG_SLOP = 8
local TAU = math.pi * 2

local function cartridgeState(imp, version)
  imp._cartridge = imp._cartridge or {}
  local state = imp._cartridge[version]
  if not state then
    state = { spin = 0, lastTime = Kit.time }
    imp._cartridge[version] = state
  end
  return state
end

local function cartridgeLabel(imp, version)
  imp._cartridgeLabels = imp._cartridgeLabels or {}
  local label = imp._cartridgeLabels[version]
  if label ~= nil then return label or nil end
  local ok, image = pcall(love.graphics.newImage,
    "assets/labels/" .. tostring(version) .. ".png")
  if not ok then
    imp._cartridgeLabels[version] = false
    return nil
  end
  local iw, ih = image:getDimensions()
  label = { image = image, width = iw, height = ih }
  imp._cartridgeLabels[version] = label
  return label
end

local function cartProject(cx, cy, yaw, pitch, x, y, z)
  local cyaw, syaw = math.cos(yaw), math.sin(yaw)
  local cpitch, spitch = math.cos(pitch), math.sin(pitch)
  local rx = x * cyaw + z * syaw
  local rz = -x * syaw + z * cyaw
  local ry = y * cpitch - rz * spitch
  rz = y * spitch + rz * cpitch
  local perspective = 620 / (620 - rz)
  return cx + rx * perspective, cy + ry * perspective
end

local function cartPolygon(points, color, alpha)
  if not love.graphics.polygon then return end
  local flat = {}
  for i = 1, #points do
    flat[#flat + 1], flat[#flat + 2] = points[i][1], points[i][2]
  end
  Theme.col(color, alpha or 1)
  love.graphics.polygon("fill", flat)
end

local function cartQuad(project, x, y, w, h, z)
  return {
    { project(x, y, z) }, { project(x + w, y, z) },
    { project(x + w, y + h, z) }, { project(x, y + h, z) },
  }
end

local function cartPill(project, x, y, w, h, z, color, alpha)
  local points, radius = {}, h / 2
  for i = 0, 10 do
    local a = math.pi + math.pi * i / 10
    points[#points + 1] = { project(x + radius + math.cos(a) * radius,
      y + radius + math.sin(a) * radius, z) }
  end
  for i = 0, 10 do
    local a = math.pi * i / 10
    points[#points + 1] = { project(x + w - radius + math.cos(a) * radius,
      y + radius + math.sin(a) * radius, z) }
  end
  cartPolygon(points, color, alpha)
end

local function cartLabelMesh(imp, version, label, points)
  if not love.graphics.newMesh then return nil end
  imp._cartridgeLabelMeshes = imp._cartridgeLabelMeshes or {}
  local mesh = imp._cartridgeLabelMeshes[version]
  if not mesh then
    mesh = love.graphics.newMesh({
      { 0, 0, 0, 0, 255, 255, 255, 255 },
      { 0, 0, 1, 0, 255, 255, 255, 255 },
      { 0, 0, 1, 1, 255, 255, 255, 255 },
      { 0, 0, 0, 1, 255, 255, 255, 255 },
    }, "fan", "dynamic")
    mesh:setTexture(label.image)
    imp._cartridgeLabelMeshes[version] = mesh
  end
  mesh:setVertices({
    { points[1][1], points[1][2], 0, 0, 255, 255, 255, 255 },
    { points[2][1], points[2][2], 1, 0, 255, 255, 255, 255 },
    { points[3][1], points[3][2], 1, 1, 255, 255, 255, 255 },
    { points[4][1], points[4][2], 0, 1, 255, 255, 255, 255 },
  })
  return mesh
end

local CART_HOVER_SHADER = [[
extern vec2 mouse_screen_pos;
extern float hovering;
extern float screen_scale;

#ifdef VERTEX
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  if (hovering <= 0.) {
    return transform_projection * vertex_position;
  }
  float mid_dist = length(vertex_position.xy - 0.5 * love_ScreenSize.xy)
    / length(love_ScreenSize.xy);
  vec2 mouse_offset = (vertex_position.xy - mouse_screen_pos.xy) / screen_scale;
  float scale = 0.2 * (-0.03 - 0.3 * max(0., 0.3 - mid_dist))
    * hovering * (length(mouse_offset) * length(mouse_offset)) / (2. - mid_dist);
  return transform_projection * vertex_position + vec4(0.0, 0.0, 0.0, scale);
}
#endif

#ifdef PIXEL
vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
  return Texel(tex, texture_coords) * color;
}
#endif
]]

local function cartHoverShader(imp)
  if imp._cartHoverShader ~= nil then
    return imp._cartHoverShader or nil
  end
  if not (love.graphics and love.graphics.newShader) then
    imp._cartHoverShader = false
    return nil
  end
  local ok, sh = pcall(love.graphics.newShader, CART_HOVER_SHADER)
  imp._cartHoverShader = ok and sh or false
  return imp._cartHoverShader or nil
end

local function cartSendHover(shader, mx, my, hovering, screenScale)
  if not shader or not shader.send then return false end
  local ok = pcall(function()
    shader:send("mouse_screen_pos", { mx, my })
    shader:send("hovering", hovering)
    shader:send("screen_scale", screenScale)
  end)
  return ok
end

local function cartridgeButton(imp, x, y, w, h, key, version, gameName, action)
  local state = cartridgeState(imp, version)
  local focused = Kit.focusable(key, x, y, w, h)
  local hot = Kit.hover(x, y, w, h)
  local active = state.active
  local cx, cy = x + w / 2, y + h / 2

  if Kit.mouseClicked and Kit.hit(x, y, w, h) and not Kit.blockClicks then
    if Kit.mouseDown then
      state.active = true
      state.startX, state.startY = Kit.mouseX, Kit.mouseY
      state.lastDragX, state.lastDragY = Kit.mouseX, Kit.mouseY
      state.dragged = false
      active = true
    else
      queueAction(imp, key, action)
    end
  end

  if state.active then
    active = true
    if Kit.mouseDown then
      local movedX, movedY = Kit.mouseX - state.startX, Kit.mouseY - state.startY
      if movedX * movedX + movedY * movedY > CART_DRAG_SLOP * CART_DRAG_SLOP then
        state.dragged = true
      end
      if state.dragged then
        local dragX = Kit.mouseX - (state.lastDragX or Kit.mouseX)
        local dragY = Kit.mouseY - (state.lastDragY or Kit.mouseY)
        state.spin = state.spin + dragX * 0.018
        state.pitchDrag = clamp((state.pitchDrag or 0) + dragY * 0.010,
          -1.20, 1.20)
      end
      state.lastDragX, state.lastDragY = Kit.mouseX, Kit.mouseY
    else
      if not state.dragged then queueAction(imp, key, action) end
      state.active, active = nil, false
      state.dragged = nil
    end
  end

  local dt = math.min(0.08, math.max(0, Kit.time - (state.lastTime or Kit.time)))
  state.lastTime = Kit.time
  if not state.active then
    local upright = math.floor(state.spin / TAU + 0.5) * TAU
    state.spin = state.spin + (upright - state.spin) * math.min(1, dt * 4)
    state.pitchDrag = (state.pitchDrag or 0)
      * (1 - math.min(1, dt * 4))
  end
  local pointerX = clamp((Kit.mouseX - cx) / math.max(1, w / 2), -1, 1)
  local pointerY = clamp((Kit.mouseY - cy) / math.max(1, h / 2), -1, 1)
  local hoverFx = hot or focused
  if hoverFx and not state.wasHot then
    state.juiceStart = Kit.time
    state.juiceScaleAmt = 0.02
    state.juiceRAmt = (math.random() > 0.5 and 1 or -1) * 0.012
    state.visScale = 1 - 0.6 * 0.02
  end
  state.wasHot = hoverFx
  local juiceScale, juiceR = 0, 0
  if state.juiceStart then
    local juiceT = Kit.time - state.juiceStart
    if juiceT >= 0.4 then
      state.juiceStart = nil
    else
      local remain = (0.4 - juiceT) / 0.4
      juiceScale = state.juiceScaleAmt * math.sin(50.8 * juiceT) * remain ^ 3
      juiceR = state.juiceRAmt * math.sin(40.8 * juiceT) * remain ^ 2
    end
  end
  state.visScale = state.visScale or 1
  local desScale = (hoverFx and 1.05 or 1) + juiceScale
  local ease = math.exp(-60 * dt)
  state.visScale = ease * state.visScale + (1 - ease) * desScale
  if not state.animId then
    local n, s = 0, tostring(version)
    for i = 1, #s do n = n + s:byte(i) * i end
    state.animId = n
  end
  local hoverMx, hoverMy
  if hot then
    hoverMx, hoverMy = Kit.mouseX, Kit.mouseY
  elseif focused then
    hoverMx, hoverMy = cx, cy
  else
    local tiltAngle = Kit.time * (1.56 + (state.animId / 1.14212) % 1)
      + state.animId / 1.35122
    hoverMx = x + (0.5 + 0.1 * math.cos(tiltAngle)) * w
    hoverMy = y + (0.5 + 0.1 * math.sin(tiltAngle)) * h
  end
  local pressX = active and pointerX * w * 0.025 or 0
  local pressY = active and pointerY * h * 0.018 or 0
  local yaw = -0.42 + state.spin
  local pitch = 0.14 + (state.pitchDrag or 0)
  local pressedScale = (active and 0.965 or 1) * state.visScale

  Kit._audit("control", x, y, w, h, key)
  if focused then
    Theme.strokeRounded(x - 3, y - 3, w + 6, h + 6, PAL.lineStrong,
      Theme.A.focus, 2, Theme.cardRadius() + 2)
  end

  local halfW, halfH = w / 2, h / 2
  local depth = math.max(8, w * 0.14)
  local project = function(px, py, pz)
    return cartProject(cx + pressX, cy + pressY, yaw, pitch,
      px * pressedScale, py * pressedScale, pz * pressedScale)
  end
  local shader = cartHoverShader(imp)
  local useHover = shader
    and cartSendHover(shader, hoverMx, hoverMy, 1,
      math.max(1, 0.4 * math.min(w, h)))
  if not useHover then
    yaw = yaw + (hoverMx - cx) / math.max(1, w / 2) * 0.08
    pitch = pitch + (hoverMy - cy) / math.max(1, h / 2) * 0.05
  end
  love.graphics.push("all")
  love.graphics.translate(cx, cy)
  love.graphics.rotate(juiceR * 2)
  love.graphics.translate(-cx, -cy)
  if useHover then love.graphics.setShader(shader) end

  local capH = h * 3 / 65
  local mainTop = -halfH + capH
  local capRight = halfW - w * 5 / 57
  local mainFront = cartQuad(project, -halfW, mainTop, w, h - capH, depth)
  local mainBack = cartQuad(project, -halfW, mainTop, w, h - capH, -depth)
  local capFront = cartQuad(project, -halfW, -halfH,
    capRight + halfW, capH, depth)
  local capBack = cartQuad(project, -halfW, -halfH,
    capRight + halfW, capH, -depth)
  local shell = cartColor(version)
  local side = { math.floor(shell[1] * 0.54), math.floor(shell[2] * 0.54),
    math.floor(shell[3] * 0.54) }

  cartPolygon(mainBack, side, 1)
  cartPolygon(capBack, side, 1)
  cartPolygon({ mainFront[2], mainFront[3], mainBack[3], mainBack[2] }, side, 1)
  cartPolygon({ mainFront[3], mainFront[4], mainBack[4], mainBack[3] }, side, 1)
  cartPolygon({ mainFront[1], mainFront[2], mainBack[2], mainBack[1] }, side, 1)
  cartPolygon({ capFront[2], capFront[3], capBack[3], capBack[2] }, side, 1)
  cartPolygon({ capFront[1], capFront[2], capBack[2], capBack[1] }, side, 1)
  cartPolygon({ capFront[4], capFront[1], capBack[1], capBack[4] }, side, 1)
  cartPolygon(mainFront, shell, 1)
  cartPolygon(capFront, shell, 1)

  local faceZ = depth + 0.8
  for i = 0, 4 do
    local ry = mainTop + 7 + i * h * 0.025
    cartPolygon(cartQuad(project, -halfW + 2, ry, w * 0.13, 2, faceZ), side, 0.7)
    cartPolygon(cartQuad(project, halfW - w * 0.13 - 2, ry, w * 0.13, 2, faceZ), side, 0.7)
  end
  local recessX, recessY = -w * 0.32, mainTop + h * 0.023
  local recessW, recessH = w * 0.64, h * 0.24
  cartPolygon(cartQuad(project, recessX, recessY, recessW, recessH, faceZ), shell, 0.88)
  cartPill(project, recessX + w * 0.025, recessY + h * 0.025,
    recessW - w * 0.05, h * 0.12, faceZ + 0.5, shell, 0.7)
  cartPill(project, recessX + w * 0.045, recessY + h * 0.043,
    recessW - w * 0.09, h * 0.083, faceZ + 0.8, side, 0.42)

  local labelX, labelY = -w * 0.33, -h * 0.20
  local labelW, labelH = w * 0.66, h * 0.55
  local plate = cartQuad(project, labelX - 2, labelY - 2, labelW + 4, labelH + 4, faceZ + 0.8)
  cartPolygon(plate, side, 0.95)
  local labelPoints = cartQuad(project, labelX, labelY, labelW, labelH, faceZ + 1.2)
  local label = cartridgeLabel(imp, version)
  local mesh = label and cartLabelMesh(imp, version, label, labelPoints)
  if mesh then
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(mesh)
  elseif label then
    local artScale = math.min(labelW / label.width, labelH / label.height)
    love.graphics.draw(label.image, labelPoints[1][1], labelPoints[1][2],
      0, artScale, artScale)
  end
  cartPolygon({
    { project(-w * 0.07, h * 0.37, faceZ + 1) },
    { project(w * 0.07, h * 0.37, faceZ + 1) },
    { project(0, h * 0.43, faceZ + 1) },
  }, side, 0.70)
  love.graphics.pop()

  if not state.active and (Kit._activateId == key) then
    queueAction(imp, key, action)
  end
end

local function modStatusColor(status)
  if status == "ok" then return Strings("Ready"), PAL.green end
  if status == "needs_import" then return Strings("Import required"), PAL.yellow end
  if status == "conflict" then return Strings("Conflict"), PAL.red end
  -- not a fault: the mod is intact, this is simply not a game it is for
  -- (src/mods/ModTargets.lua)
  if status == "other_game" then return Strings("Not for this game"), PAL.muted end
  return Strings("Incompatible"), PAL.yellow
end

-- MODS panel scope row: which game the list is answering for, plus dedicated Profile control (cycle + gear).
local function modScopeOptions(imp)
  local GameVersion = require("src.core.GameVersion")
  local options = { { id = nil, label = Strings("All games") } }
  for _, version in ipairs(GameVersion.ORDER) do
    if imp.ready and imp.ready[version] then
      options[#options + 1] =
        { id = version, label = GameVersion.info(version).label }
    end
  end
  return options
end

local function modScopeCurrentLabel(imp, options)
  for _, opt in ipairs(options) do
    if imp.modScope == opt.id then return opt.label end
  end
  return options[1] and options[1].label or Strings("All games")
end

local function modScopeChipsWidth(options, gap, m)
  local need = 0
  for i, opt in ipairs(options) do
    need = need + Kit.textWidth("micro", opt.label) + math.floor(18 * m.s)
    if i < #options then need = need + gap end
  end
  return need
end

local function buildModScopeRow(imp, x, y, w, m)
  local LauncherMods = require("src.mods.LauncherMods")
  local h = math.max(Kit.tapMin(), math.floor(26 * m.s))
  local gap = math.floor(6 * m.s)
  local label = Strings("Show for:")
  Kit.text("small", label, x, y + (h - Kit.textHeight("small")) / 2, PAL.muted)
  local cx = x + Kit.textWidth("small", label) + math.floor(10 * m.s)
  local options = modScopeOptions(imp)

  -- Dedicated Profile control section (cycle button + gear icon button) on right side of Scope Bar
  local _, activeProf = LauncherMods.getProfiles()
  local isCompact = (w < math.floor(500 * m.s))
  local nameText = tostring(activeProf or "Default")
  local profLabel = isCompact and nameText or Strings("Profile: %s", nameText)
  local profW = Kit.textWidth("micro", profLabel) + math.floor(20 * m.s)
  local gearW = h
  local gearX = x + w - gearW
  local profX = gearX - profW - math.floor(4 * m.s)

  btn(imp, profX, y, profW, h, "mod-scope-profile", profLabel, {
    face = "invert", font = "micro",
    action = function()
      local list, cur = LauncherMods.getProfiles()
      local nextIdx = 1
      for i, p in ipairs(list) do
        if p.name == cur then
          nextIdx = (i % #list) + 1
          break
        end
      end
      local nextProf = list[nextIdx] and list[nextIdx].name
      if nextProf then
        LauncherMods.applyProfile(nextProf)
        if imp._refreshMods then imp:_refreshMods() end
      end
    end,
  })

  imp._gearIcon = imp._gearIcon or (love and love.graphics and love.graphics.newImage and love.graphics.newImage("assets/launcher/gear.png"))
  btn(imp, gearX, y, gearW, gearW, "mod-profile-gear", "", {
    face = "invert", image = imp._gearIcon,
    action = function() imp._profilesPopup = true end,
  })

  if #options >= 2 then
    local avail = profX - gap - cx
    -- Chips stay when they all fit; otherwise they used to be skipped and
    -- vanish off the portrait edge.  Collapse to one menu in that case only.
    if modScopeChipsWidth(options, gap, m) <= avail then
      for _, opt in ipairs(options) do
        local cw = Kit.textWidth("micro", opt.label) + math.floor(18 * m.s)
        if Kit.chip(cx, y, cw, h, opt.label, imp.modScope == opt.id, PAL.lineStrong,
                    "mod-scope-" .. tostring(opt.id or "all")) then
          local want = opt.id
          queueAction(imp, "mod-scope-" .. tostring(want or "all"),
            function() imp:_setModScope(want) end)
        end
        cx = cx + cw + gap
      end
    elseif avail > 0 then
      local shown = Kit.ellipsize("micro", modScopeCurrentLabel(imp, options),
        math.max(0, avail - math.floor(18 * m.s)))
      local cw = math.min(avail,
        Kit.textWidth("micro", shown) + math.floor(18 * m.s))
      if Kit.chip(cx, y, cw, h, shown, true, PAL.lineStrong, "mod-scope-menu") then
        queueAction(imp, "mod-scope-menu",
          function() imp._modScopePopup = true end)
      end
    end
  end
  return h + math.floor(8 * m.s)
end

local function findActionFor(entry, installedVersion)
  local ModIndex = require("src.mods.ModIndex")
  if not ModIndex.canInstall(entry) then
    return nil, Strings("Not installable from this index")
  end
  if not installedVersion then return Strings("Install"), nil end
  local listed = ModIndex.displayVersion(entry)
  local ModUpdate = require("src.mods.ModUpdate")
  if type(installedVersion) == "string"
      and ModUpdate.isNewer(installedVersion, listed) then
    return Strings("Update"), "Installed v" .. installedVersion
  end
  return Strings("Reinstall"), "Installed v" .. tostring(installedVersion)
end

local function DELETE_LABEL(armed)
  return armed and Strings("Sure?") or Strings("Delete")
end

local function deleteArmed(imp, kind, id, version)
  local a = imp._confirmDelete
  return a ~= nil and a.kind == kind and a.id == id and a.version == version
end

-- Page state lives on the importer keyed by list, so switching tabs and
-- coming back keeps your place -- the one thing scrolling did better.
local function page(imp, key)
  return imp._pages[key] or 1
end

local function setPage(imp, key, v)
  imp._pages[key] = v
end

-- A hand-drawn X / check: the UI font has no guaranteed glyph for either,
-- and the launcher ships no icon asset for them.
-- Skins tab glyph: a bezel with a screen cutout and two face buttons, drawn
-- rather than shipped as art so the tab needs no new asset.
local function drawSkinGlyph(x, y, w, h, hot)
  local box = math.min(w, h)
  local bx = x + (w - box) / 2
  local by = y + (h - box) / 2
  local pad = math.floor(box * 0.22)
  local ow, oh = box - 2 * pad, box - 2 * pad
  local ink = hot and PAL.inverse or PAL.ink
  local a = 1
  Theme.strokeRounded(bx + pad, by + pad, ow, oh, ink, a,
    math.max(1, math.floor(Kit.scale)), math.floor(oh * 0.22))
  local sw, sh = ow * 0.58, oh * 0.40
  Theme.fillRounded(bx + pad + ow * 0.10, by + pad + oh * 0.14, sw, sh, ink, a,
    math.max(1, math.floor(sh * 0.2)))
  local r = math.max(1, oh * 0.09)
  Theme.fillRounded(bx + pad + ow * 0.60, by + pad + oh * 0.64, r * 2, r * 2, ink, a, r)
  Theme.fillRounded(bx + pad + ow * 0.80, by + pad + oh * 0.50, r * 2, r * 2, ink, a, r)
end

local function drawCross(x, y, size, color)
  love.graphics.push("all")
  love.graphics.setColor(color)
  love.graphics.setLineWidth(math.max(2, size * 0.16))
  love.graphics.setLineJoin("bevel")
  love.graphics.line(x, y, x + size, y + size)
  love.graphics.line(x + size, y, x, y + size)
  love.graphics.pop()
end

local function drawCheck(x, y, size, color)
  love.graphics.push("all")
  love.graphics.setColor(color)
  love.graphics.setLineWidth(math.max(2.2, size * 0.17))
  love.graphics.setLineJoin("bevel")
  love.graphics.line(
    x + size * 0.02, y + size * 0.52,
    x + size * 0.38, y + size * 0.80,
    x + size * 1.015, y + size * 0.18)
  love.graphics.pop()
end

-- ------------------------------------------------------------- header
-- Rail, logo row (settings and quit on the right), tab bar.
-- Returns the y at which content may start.  Its vertical arithmetic is
-- mirrored by headerHeight() at the bottom of this file (the short-window
-- scroll decision needs the height before anything draws) -- keep in sync.
-- Header chrome is fixed: the same six tabs, the same gear and Quit, every
-- frame.  Their tab rows, opts tables and action closures are built once
-- instead of 60 times a second -- only `active`, `image` and the queued
-- action are written per frame.
-- The four cartridges used to be four tabs of their own.  They are one
-- dropdown now: the tab row was seven controls wide and wrapped to two rows on
-- anything narrow, and only ever one game is being looked at.
local GAME_TABS = {
  { id = "red",    key = "tab-red",    letter = "R", color = PAL.railRed,
    label = "Red" },
  { id = "blue",   key = "tab-blue",   letter = "B", color = PAL.railBlue,
    label = "Blue" },
  { id = "yellow", key = "tab-yellow", letter = "Y", color = PAL.railGold,
    label = "Yellow" },
  { id = "gold",   key = "tab-gold",   letter = "G", color = PAL.railAmber,
    label = "Gold" },
}

local HEADER_TABS = {
  { id = "mods",   key = "tab-mods" },
  { id = "find",   key = "tab-find" },
  { id = "skins",  key = "tab-skins", glyph = true },
}
for _, t in ipairs(HEADER_TABS) do
  t.opts = { face = "tab", font = "tab", color = t.color, letter = t.letter }
  if t.glyph then t.opts.drawFn = drawSkinGlyph end
end

-- Which cartridge the dropdown is showing: the open game tab, else the last
-- one visited, else Red.  Kept as a function so the mods/find/skins panels
-- still answer "for which game" without a game tab being open.
local function currentGame(imp)
  for _, g in ipairs(GAME_TABS) do
    if imp.tab == g.id then return g end
  end
  for _, g in ipairs(GAME_TABS) do
    if imp.modScope == g.id then return g end
  end
  return GAME_TABS[1]
end

LauncherView.GAME_TABS = GAME_TABS
LauncherView.currentGame = currentGame

local QUIT_INK_HOT = { 0, 0, 0, 1 }
local QUIT_INK_REST = { 1, 1, 1, 0.85 }

-- Keyed off the launcher instance so the closures die with it.
local function headerChrome(imp)
  local c = imp._headerChrome
  if c then return c end
  c = {
    gear = { face = "invert",
      action = function() imp:_openSettings() end },
    quit = { face = "invert",
      action = function() imp:_quitApp() end,
      drawFn = function(x, y, w, h, hot)
        local pad = math.floor(w * 0.32)
        drawCross(x + pad, y + pad, w - 2 * pad,
          hot and QUIT_INK_HOT or QUIT_INK_REST)
      end },
    tab = {},
    game = { face = "tab", font = "tab",
      action = function()
        local g = currentGame(imp)
        if imp.tab == g.id then
          imp._gamePopup = true
        else
          imp:_switchTab(g.id)
        end
      end },
  }
  for _, t in ipairs(HEADER_TABS) do
    local id = t.id
    c.tab[id] = function() imp:_switchTab(id) end
  end
  for _, g in ipairs(GAME_TABS) do
    local id = g.id
    c.tab[id] = function()
      imp._gamePopup = nil
      imp:_switchTab(id)
    end
  end
  imp._headerChrome = c
  return c
end

local function buildHeader(imp, m)
  local y = m.top
  Theme.versionRail(m.x, y, m.w, m.railH)
  y = y + m.railH

  -- logo row
  local rowH = m.logoH + math.floor(12 * m.s)
  local gear = m.chip

  -- The wordmark is centred in the row MINUS the right cluster, mirrored on
  -- the left so it still reads as centred in the window.  Centring it in the
  -- FULL row (what this used to do) let a phone-width wordmark run straight
  -- under the gear and the quit X -- "the settings is covering the logo".
  -- Reserving the space on both sides costs a little width and cannot
  -- overlap at any window size.
  local clusterW = 2 * gear + math.floor(6 * m.s) + m.pad
  local boxX = m.x + clusterW
  local boxW = math.max(0, m.w - 2 * clusterW)
  if imp.logo and boxW > 0 then
    local lw, lh = imp.logo:getDimensions()
    local maxW = math.min(320 * m.s, boxW)
    local scale = math.min(maxW / lw, m.logoH / lh)
    local dw, dh = lw * scale, lh * scale
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(imp.logo, Theme.snap(boxX + (boxW - dw) / 2),
      Theme.snap(y + (rowH - dh) / 2), 0, scale, scale)
  end

  local rx = m.x + m.w - m.pad
  local by = y + (rowH - gear) / 2

  -- Switch-only: show the running app version opposite the settings gear so
  -- players can confirm which build is on the microSD (OTA / zip updates).
  if imp.isNX then
    local label = "v" .. tostring(Version.engine or "?")
    local tw = Kit.textWidth("small", label)
    local padX = math.floor(12 * m.s)
    local chipW = math.max(tw + 2 * padX, gear)
    local lx = m.x + m.pad
    Kit.card(lx, by, chipW, gear, "badge")
    local th = Kit.textHeight("small")
    Kit.text("small", label, lx + math.floor((chipW - tw) / 2),
      by + math.floor((gear - th) / 2), PAL.yellow)
  end

  -- The right cluster is laid out right to left -- Quit outermost, the gear
  -- inboard of it -- but the two are REGISTERED gear first, because the first
  -- focusable of the first frame adopts the keyboard ring and that must not be
  -- the button that exits the app.
  local quitX = rx - gear
  rx = quitX - math.floor(6 * m.s)

  -- Settings gear.  It now also owns the CONTROL settings (touch overlay
  -- editor, reset rebinds), which used to be buttons stacked in the game
  -- panel -- see LauncherSettings.coreRows.
  imp._gearIcon = imp._gearIcon
    or love.graphics.newImage("assets/launcher/gear.png")
  rx = rx - gear
  local chrome = headerChrome(imp)
  chrome.gear.image = imp._gearIcon
  btn(imp, rx, by, gear, gear, "gear", "", chrome.gear)

  btn(imp, quitX, by, gear, gear, "quit", "", chrome.quit)

  -- The self-update control lives in the FOOTER next to the BCG mark (small,
  -- out of the wordmark's way -- it used to overlap the logo on a phone).  It
  -- still GLOWS through Kit.button when there is something to act on.
  y = y + rowH

  -- tab bar
  imp._modsIcon = imp._modsIcon
    or love.graphics.newImage("assets/launcher/mods.png")
  imp._findIcon = imp._findIcon
    or love.graphics.newImage("assets/launcher/find.png")
  -- Game tabs keep their cartridge colours -- that is the one piece of brand
  -- identity in the launcher, and "the red one" is how people actually refer
  -- to these.  The colour rides the outline and the glyph at rest and becomes
  -- the fill when active, the same rule the buttons follow.  Yellow stays the
  -- bright cart gold; Gold (Gen 2) uses the deeper amber so the two do not
  -- collide.
  local tabs = HEADER_TABS
  for _, t in ipairs(tabs) do
    if t.id == "mods" then t.icon = imp._modsIcon end
    if t.id == "find" then t.icon = imp._findIcon end
  end
  local tabH = m.chip
  local tx = m.x + m.pad
  local ty = y + math.floor(6 * m.s)
  local tabLeft = tx
  local tabRight = m.x + m.w - m.pad
  local tabGap = math.floor(6 * m.s)
  local tabRowGap = math.floor(4 * m.s)

  -- the cartridge dropdown, sized to its longest label so switching games
  -- never reflows the row
  local chrome0 = headerChrome(imp)
  local game = currentGame(imp)
  local labelW = 0
  for _, g in ipairs(GAME_TABS) do
    labelW = math.max(labelW, Kit.textWidth("tab", Strings(g.label)))
  end
  local dropW = math.min(tabRight - tabLeft,
    tabH + labelW + math.floor(34 * m.s))
  chrome0.game.color = game.color
  chrome0.game.letter = game.letter
  chrome0.game.active = imp.tab == game.id
  local gameHot = Kit.hover(tx, ty, dropW, tabH)
  local gameDown = gameHot and Kit.mouseDown
  -- face "tab" inverts on hover as well as when active, so the caret has to
  -- flip with it or it vanishes into the cartridge colour
  local gameInvert = chrome0.game.active or gameHot
  chrome0.game.ring = gameHot and not chrome0.game.active or nil
  btn(imp, tx, ty, dropW, tabH, "tab-game", Strings(game.label), chrome0.game)
  do
    local cw = math.floor(7 * m.s)
    local ccx = tx + dropW - math.floor(14 * m.s)
    local ccy = ty + tabH / 2 + (gameDown and math.floor(1 * m.s) or 0)
    if love.graphics.polygon then
      Theme.col(gameInvert and PAL.inverse or PAL.ink, gameDown and 1 or 0.9)
      love.graphics.polygon("fill",
        ccx - cw, ccy - cw * 0.5, ccx + cw, ccy - cw * 0.5, ccx, ccy + cw * 0.8)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end
  tx = tx + dropW + tabGap

  for _, t in ipairs(tabs) do
    local w = tabH
    if tx > tabLeft and tx + w > tabRight then
      tx = tabLeft
      ty = ty + tabH + tabRowGap
    end
    local o = t.opts
    o.active = imp.tab == t.id
    o.image = t.icon
    o.action = chrome.tab[t.id]
    btn(imp, tx, ty, w, tabH, t.key, "", o)
    tx = tx + w + tabGap
  end

  -- `ty` has walked down with the wraps, so this stays correct at one row too.
  y = ty + tabH + math.floor(8 * m.s)
  Theme.fill(m.x, y, m.w, 1, PAL.line, Theme.A.hairline)
  return y + math.floor(10 * m.s)
end

-- The state of the self-updater, as a top-right control.
-- Returns status, label, action, glow.
function LauncherView._updateControl(imp)
  if not imp.Check then return nil end
  local ok, st = pcall(imp.Check.state)
  st = (ok and type(st) == "table") and st or nil
  local status = st and st.status or "idle"
  if status == "checking" then
    return status, Strings("Checking..."), nil, false
  elseif status == "downloading" then
    local pct = st.progress and math.floor(st.progress * 100) or 0
    return status, Strings("Updating %d%%", pct), nil, false
  elseif status == "available" then
    return status, st.latest and (Strings("Update v") .. st.latest)
      or Strings("Update"), function() pcall(imp.Check.download) end, true
  elseif status == "ready" then
    return status, Strings("Restart to update"),
      function() require("src.core.HostShell").restart() end, true
  elseif status == "needs_full" then
    return status, Strings("Open releases"),
      function() love.system.openURL(imp.Check.releaseUrl()) end, true
  end
  -- idle / uptodate / error: offer a manual check, with no glow.
  return status, Strings("Check for updates"),
    function() pcall(imp.Check.start, true) end, false
end

-- ------------------------------------------------------------ game panel

-- What this version's ROM situation is, as a plain table.  The panel and the
-- per-game manage modal both read it, so the two can never disagree about
-- whether a ROM is present or what the import button should say.
--   state    a headline, or nil when there is nothing to report (ready)
--   detail   the paragraph under it
--   label    the import button's caption
--   enabled  whether that button may be pressed
--   progress 0-1 while an import for THIS version is running
local function romModel(imp, version, info, ready, locked)
  local importLabel = imp.isNX and Strings("Scan again") or Strings("Import ROM")
  if locked then
    return { state = Strings("Not supported yet"),
      detail = Strings("Support for this game is on the way."),
      label = Strings("Import unavailable"), enabled = false }
  end
  local dropHint = imp.isNX and Strings("Copy the .gb/.gbc via MTP into imports/.")
    or (imp.baseRomDiscovery and Strings("Or copy the .gb/.gbc into baseroms/.")
      or (imp.android and Strings("Copy the .gb/.gbc via USB.")
        or Strings("Or drop the .gb/.gbc file here.")))
  local importing = imp.importing == version
  local erroring = imp.workState == "error" and imp.errorVersion == version
  local notice = imp.notice and imp.notice.version == version and imp.notice
  local baseRom = imp.baseRoms and imp.baseRoms[version]
  local scanning = imp.baseRomDiscovery and imp.baseRomScan
    and imp.baseRomScan.state ~= "done"
  if importing and (imp.workState == "working" or imp.workState == "complete") then
    return { state = imp.status or Strings("Importing"),
      detail = imp.detail or "", progress = imp.progress or 0 }
  elseif erroring then
    -- An import that FAILED is reported even on a ready game (a re-import
    -- that could not read the new file): the failure is the only reason the
    -- library still holds the old cache, and it must not be silent (the
    -- "Import failed with no explanation" report).
    return { state = Strings("Import failed"),
      detail = imp.detail or Strings("That ROM could not be imported."),
      label = importLabel, enabled = true }
  elseif ready then
    return { label = Strings("Re-import ROM"), enabled = true }
  elseif notice then
    return { state = Strings("No ROM imported"),
      detail = ((notice.status or "") .. " " .. (notice.detail or ""))
        :gsub("^%s+", ""):gsub("%s+$", ""),
      label = importLabel, enabled = true }
  elseif baseRom then
    return { state = Strings("Compatible ROM found"),
      detail = Strings("Found in baseroms/: %s", baseRom.name),
      label = Strings("Import detected ROM"), enabled = true }
  elseif scanning then
    return { state = Strings("Checking baseroms..."),
      detail = Strings("Looking for compatible Red, Blue, and Yellow ROMs."),
      label = Strings("Import ROM"), enabled = false }
  elseif imp.returning[version] then
    return { state = Strings("Update required"),
      detail = Strings("This build needs a few more things from your ")
        .. info.label .. Strings(" ROM. Re-import to continue."),
      label = Strings("Re-import ROM"), enabled = true }
  end
  return { state = Strings("No ROM imported"),
    detail = Strings("The ROM is verified before any files are created. ")
      .. dropHint,
    label = importLabel, enabled = true }
end

-- The import action behind whichever button carries it.
local function romAction(imp, version, mdl)
  if not mdl.enabled then return nil end
  return function()
    if imp.ready[version] then imp:reimport(version)
    else imp:choose(version) end
  end
end

-- The ROM card: the state headline, its paragraph, and the Import button.
-- It exists ONLY while there is something to report -- a game with a verified
-- ROM shows Play, not a card of file management (that moved behind the manage
-- button next to Play, and the save file controls moved into the slot card).
-- Returns the height it consumed, 0 when it drew nothing.
local function buildRomCard(imp, x, y, w, m, version, mdl, maxH)
  if not (mdl.state or mdl.progress) then return 0 end
  local pad = math.floor(14 * m.s)
  local iw = w - 2 * pad
  local lineH = Kit.textHeight("small")
  local hasButton = mdl.progress == nil and mdl.label ~= nil
  -- Pads and the button are fixed furniture that always fits; the detail
  -- paragraph is the elastic part and gets trimmed to whatever lines the
  -- budget leaves.  Without that trim the card overflowed and got clipped
  -- mid-button, which is the failure a no-scroll layout must design out.
  local fixedH = pad + Kit.textHeight("button") + math.floor(4 * m.s)
    + math.floor(10 * m.s)
    + ((hasButton or mdl.progress) and (m.btnH + math.floor(2 * m.s)) or 0)
    + pad
  local detailLines = 3
  if maxH then
    detailLines = math.max(0,
      math.min(detailLines, math.floor((maxH - fixedH) / lineH)))
  end
  local detailH = Kit.wrapHeight("small", mdl.detail or "", iw, detailLines)
  local h = fixedH + detailH

  Kit.card(x, y, w, h)
  local cy = y + pad
  Kit.text("button", Kit.ellipsize("button", mdl.state or "", iw), x + pad, cy,
    PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(4 * m.s)
  cy = cy + Kit.textWrapped("small", mdl.detail or "", x + pad, cy, iw,
    PAL.detail, detailLines)
  cy = cy + math.floor(10 * m.s)
  if mdl.progress ~= nil then
    Kit.progress(x + pad, cy + (m.btnH - math.floor(10 * m.s)) / 2, iw,
      math.floor(10 * m.s), mdl.progress)
  elseif hasButton then
    btn(imp, x + pad, cy, iw, m.btnH, "rom-" .. version, mdl.label, {
      kind = "accent", enabled = mdl.enabled,
      action = romAction(imp, version, mdl),
    })
  end
  return h
end

-- Save slots, PAGINATED.  This was a fixed-height scroller with momentum; it
-- is now a page of rows sized to whatever height the column has left, which
-- is why 40 slots cost exactly what 4 do.
-- Lay a row's action chips out right-aligned, wrapping onto further lines
-- when they cannot all fit across the row.  A narrow window (the 150%-scaled
-- desktop and the portrait phone in the reports) could not fit four chips on
-- one line, and a fixed right-to-left cluster simply walked them off the left
-- edge and under the row's own text.  Returns an array of lines, each an
-- array of chips, so the caller can size the row BEFORE drawing it.
local function chipLines(chips, inner, gap)
  local lines, line, used = {}, {}, 0
  for _, c in ipairs(chips) do
    if #line > 0 and used + gap + c.w > inner then
      lines[#lines + 1] = line
      line, used = {}, 0
    end
    used = used + ((#line > 0) and gap or 0) + c.w
    line[#line + 1] = c
  end
  if #line > 0 then lines[#lines + 1] = line end
  return lines
end

-- The width a chip needs for its caption, at the row-chip font.
local function chipWidth(label, m)
  return Kit.textWidth("small", label) + math.floor(20 * m.s)
end

local function buildSlotCard(imp, x, y, w, availH, m, version, ready)
  imp:_ensureSlots(version)
  local slots = imp.slots[version] or {}
  local active = imp.activeSlot[version]
  local n = #slots
  local pad = math.floor(14 * m.s)
  local iw = w - 2 * pad
  local gap = math.floor(8 * m.s)

  -- A slot row: name + LOADED tag, meta line, then the action chips.  The
  -- chip set is measured against the WIDEST possible row (every chip present)
  -- so every row on the page is the same height even though an empty slot
  -- offers fewer -- pagination derives its row count from a uniform height.
  local chipH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local rowInner = iw - math.floor(20 * m.s)
  local maxChips = {
    { w = chipWidth(Strings("Export"), m) },
    { w = chipWidth(Strings("Rename"), m) },
    { w = chipWidth(Strings("Edit"), m) },
    -- Delete's width is pinned to the WIDER of its two captions so arming to
    -- "Sure?" never reflows the row under the pointer (#433).
    { w = math.max(chipWidth(DELETE_LABEL(false), m),
        chipWidth(DELETE_LABEL(true), m)) },
  }
  local chipGap = math.floor(6 * m.s)
  local maxChipsW = 0
  for i, c in ipairs(maxChips) do
    maxChipsW = maxChipsW + c.w + ((i > 1) and chipGap or 0)
  end
  -- BESIDE the text when the row is wide enough to hold both and still leave
  -- the name and meta lines a readable share, UNDER it when it is not.  A
  -- desktop row costs one text block instead of a text block plus a button
  -- strip, which is what lets a two-column window show several slots per page
  -- instead of one; a phone row keeps the taller shape rather than squeezing
  -- four chips and a name into one line.
  local textH = Kit.textHeight("button") + math.floor(4 * m.s)
    + Kit.textHeight("small")
  -- The threshold is what the TEXT needs, not a fraction of the row: a slot
  -- name plus its badges/time/dex line wants about this much before it starts
  -- ellipsizing anything a player came to read.
  local textMinW = math.floor(150 * m.s)
  local sideBySide =
    (rowInner - maxChipsW - math.floor(12 * m.s)) >= textMinW
  local chipRowCount = #chipLines(maxChips, rowInner, chipGap)
  local chipBlockH = chipRowCount * chipH
    + math.max(0, chipRowCount - 1) * chipGap
  local rowH
  if sideBySide then
    rowH = math.floor(8 * m.s) + math.max(textH, chipH) + math.floor(8 * m.s)
  else
    rowH = math.floor(8 * m.s) + textH + math.floor(8 * m.s) + chipBlockH
      + math.floor(8 * m.s)
  end

  -- The header carries "Import save": a .sav import CREATES a slot, so it
  -- belongs to the slot list rather than to the ROM card it used to sit in.
  local headH = math.max(Kit.textHeight("caption"), m.btnH) + math.floor(8 * m.s)
  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local newBtnH = m.btnH
  local sfNotice = imp.saveNotice[version]
  local hintText, hintCol
  if sfNotice then
    hintText, hintCol = sfNotice.text, (sfNotice.ok and PAL.green or PAL.red)
  else
    hintText, hintCol = nil, PAL.muted
  end
  local hintH = hintText
    and (Kit.wrapHeight("small", hintText, iw, 2) + math.floor(8 * m.s)) or 0
  local folderRow = sfNotice and sfNotice.dir
  if folderRow then hintH = hintH + Kit.textHeight("small") + math.floor(4 * m.s) end

  -- Rows get whatever is left after the card's fixed furniture.
  local listH = availH
    - (pad * 2 + headH + hintH + pagerH + gap + newBtnH + gap)
  local perPage = Kit.rowsThatFit(listH, rowH, gap, 1, 12)
  local pageKey = "slots-" .. version
  local first, last, cur, pages = Kit.pageBounds(page(imp, pageKey), n, perPage)
  setPage(imp, pageKey, cur)

  local shown = math.max(0, last - first + 1)
  local usedListH = (n == 0) and math.floor(70 * m.s)
    or (shown * rowH + math.max(0, shown - 1) * gap)
  local h = pad + headH + usedListH + gap + hintH
    + (pages > 1 and (pagerH + gap) or 0) + newBtnH + pad

  Kit.card(x, y, w, h)
  local cy = y + pad
  local capY = cy + math.floor((m.btnH - Kit.textHeight("caption")) / 2)
  Kit.caption(x + pad, capY, Strings("SAVE SLOT"))
  local savImportLabel = imp.isNX and Strings("Scan again")
    or Strings("Import save")
  local impW = chipWidth(savImportLabel, m) + math.floor(8 * m.s)
  btn(imp, x + w - pad - impW, cy, impW, m.btnH, "sav-import-" .. version,
    savImportLabel, {
      kind = "accent", font = "small", enabled = ready and true or false,
      action = ready and function() imp:chooseSaveImport(version) end or nil,
    })
  local countW = (x + w - pad - impW - math.floor(8 * m.s))
    - (x + pad + Kit.captionWidth(Strings("SAVE SLOT")) + math.floor(8 * m.s))
  if countW > 0 then
    Kit.textRight("small",
      n == 1 and Strings("1 slot") or Strings("%d slots", n),
      x + w - pad - impW - math.floor(8 * m.s), capY, PAL.muted)
  end
  cy = cy + headH

  if n == 0 then
    Kit.emptyBox(x + pad, cy, iw, usedListH,
      Strings("No saves yet - start a new game or import one."))
    cy = cy + usedListH + gap
  else
    -- Wheel over the list turns pages; the page index is bounded, so there is
    -- no scroll offset to interpolate and nothing to clamp against content.
    setPage(imp, pageKey,
      Kit.wheelPage(x + pad, cy, iw, usedListH, cur, n, perPage))
    for i = first, last do
      local slot = slots[i]
      local selected = slot.id == active
      local rowKey = "slot-" .. version .. "-" .. slot.id
      local ry = cy + (i - first) * (rowH + gap)
      local ink = rowHit(imp, x + pad, ry, iw, rowH, selected, rowKey,
        function() imp:_selectSlot(version, slot.id) end)

      local px = x + pad + math.floor(10 * m.s)
      local inner = iw - math.floor(20 * m.s)
      -- Beside the chips, the text block only owns what they leave; under
      -- them it owns the row.  Either way the width is fixed before anything
      -- prints, so the name ellipsizes into its own space rather than into
      -- a button.
      local textW = sideBySide
        and (inner - maxChipsW - math.floor(12 * m.s)) or inner
      local ly = ry + math.floor(8 * m.s)
        + (sideBySide and math.floor((math.max(textH, chipH) - textH) / 2) or 0)
      local name = slot.label or slot.name or Strings("NEW GAME")
      local tagW = 0
      if selected then
        tagW = Kit.textWidth("micro", Strings("LOADED")) + math.floor(16 * m.s)
        Kit.tag(px + textW - tagW, ly, tagW, Kit.textHeight("button"),
          Strings("LOADED"), PAL.inverse)
        tagW = tagW + math.floor(8 * m.s)
      end
      Kit.text("button", Kit.ellipsize("button", name, textW - tagW), px, ly, ink)
      ly = ly + Kit.textHeight("button") + math.floor(4 * m.s)
      local metaTxt
      if slot.exists and slot.meta then
        metaTxt = Strings("%d badges - %s - %d caught", slot.meta.badges or 0,
          slot.meta.timeText or "0:00", slot.meta.dexCount or 0)
      else
        metaTxt = Strings("empty slot")
      end
      Kit.text("small", Kit.ellipsize("small", metaTxt, textW), px, ly,
        selected and PAL.inverse or PAL.muted)
      -- Where the chip block starts: centred on the row beside the text, or
      -- on its own line under it.
      ly = sideBySide and (ry + (rowH - chipBlockH) / 2)
        or (ly + Kit.textHeight("small") + math.floor(8 * m.s))

      -- Action chips, right-aligned and wrapped onto as many lines as the row
      -- width needs.  Export lives HERE rather than beside the ROM buttons:
      -- an export is a property of a slot, so the control belongs on the slot
      -- it exports (it selects the row first, since the exporter writes
      -- whichever slot is active).
      local armed = deleteArmed(imp, "slot", slot.id, version)
      local chips = {}
      if slot.exists then
        chips[#chips + 1] = { label = Strings("Export"), kind = "accent",
          key = rowKey .. "-export",
          action = function()
            imp:_selectSlot(version, slot.id)
            imp:exportSave(version)
          end }
      end
      if not imp.android then
        chips[#chips + 1] = { label = Strings("Rename"), kind = "accent",
          key = rowKey .. "-rename",
          action = function() imp:_beginRename(version, slot.id) end }
      end
      if imp.onEditSave and slot.exists then
        chips[#chips + 1] = { label = Strings("Edit"), kind = "accent",
          key = rowKey .. "-edit",
          action = function() imp.onEditSave(version, slot.id) end }
      end
      chips[#chips + 1] = { label = DELETE_LABEL(armed), kind = "danger",
        keepArm = true, key = rowKey .. "-del",
        -- Pinned width, so arming to "Sure?" cannot reflow the cluster.
        w = math.max(chipWidth(DELETE_LABEL(false), m),
          chipWidth(DELETE_LABEL(true), m)),
        action = function()
          imp:pressDelete("slot", slot.id, version, function()
            imp:_deleteSlot(version, slot.id)
          end)
        end }
      for _, c in ipairs(chips) do c.w = c.w or chipWidth(c.label, m) end
      for li, line in ipairs(chipLines(chips, inner, chipGap)) do
        local total = 0
        for i, c in ipairs(line) do
          total = total + c.w + ((i > 1) and chipGap or 0)
        end
        local cx = px + inner - total
        local cly = ly + (li - 1) * (chipH + chipGap)
        for _, c in ipairs(line) do
          btn(imp, cx, cly, c.w, chipH, c.key, c.label, {
            kind = c.kind, font = "small", keepArm = c.keepArm,
            action = c.action,
          })
          cx = cx + c.w + chipGap
        end
      end
    end
    cy = cy + usedListH + gap
  end

  -- The save-file notice (import/export result) lands in this card now that
  -- the buttons that produce it do.
  if hintText then
    cy = cy + Kit.textWrapped("small", hintText, x + pad, cy, iw, hintCol, 2)
    if folderRow then
      cy = cy + math.floor(4 * m.s)
      local key = "sav-folder-" .. version
      local label = Strings("Open folder")
      local lw = Kit.textWidth("small", label)
      local lh = Kit.textHeight("small")
      Kit.focusable(key, x + pad, cy, lw, lh)
      Kit.text("small", label, x + pad, cy, PAL.blue)
      Theme.fill(x + pad, cy + lh - 1, lw, 1, PAL.blue, 0.6)
      if Kit.press(x + pad, cy, lw, lh) or Kit._activateId == key then
        local dir = sfNotice.dir
        queueAction(imp, key, function()
          love.system.openURL(imp:fileUrl(dir))
        end)
      end
      cy = cy + lh
    end
    cy = cy + math.floor(8 * m.s)
  end

  if pages > 1 then
    local newPage = Kit.pager(x + pad, cy, iw, cur, n, perPage, pageKey)
    setPage(imp, pageKey, newPage)
    cy = cy + pagerH + gap
  end
  btn(imp, x + pad, cy, iw, newBtnH, "slot-new-" .. version,
    Strings("+ New save slot"), {
      kind = "good",
      action = function() imp:_newSlot(version) end,
    })
  return h
end

local function buildGamePanel(imp, x, y, w, availH, m, version)
  imp.panelVersion = version
  local info = GameVersion.info(version)
  local locked = info == nil
  local gameName = info and (info.launcherName or info.displayName)
    or tostring(version)
  local ready = (not locked) and imp.ready[version] or false

  -- title + status tag.  Ready is a check chip (the font has no tick glyph);
  -- missing ROM stays a yellow "ROM REQUIRED" tag so it still reads as an action.
  local titleH = Kit.textHeight("title")
  Kit.text("title", Kit.ellipsize("title", gameName, w * 0.6), x, y, PAL.heading)
  local tagH = Kit.textHeight("micro") + math.floor(10 * m.s)
  local tagX = x + Kit.textWidth("title", Kit.ellipsize("title", gameName, w * 0.6))
    + math.floor(12 * m.s)
  local tagY = y + (titleH - tagH) / 2
  local tagW, tagCol
  if ready then
    tagCol = PAL.green
    tagW = tagH
    if love.graphics then
      Theme.strokeRounded(tagX, tagY, tagW, tagH, tagCol, 0.7, 1)
      local ck = math.floor(tagH * 0.55)
      drawCheck(tagX + (tagW - ck) / 2, tagY + (tagH - ck) / 2, ck, tagCol)
    end
  else
    local tagText
    if imp.baseRoms and imp.baseRoms[version] then
      tagText, tagCol = Strings("ROM FOUND"), PAL.green
    elseif locked then tagText, tagCol = Strings("COMING SOON"), PAL.steel
    else tagText, tagCol = Strings("ROM REQUIRED"), PAL.yellow end
    tagW = Kit.textWidth("micro", tagText) + math.floor(18 * m.s)
    Kit.tag(tagX, tagY, tagW, tagH, tagText, tagCol)
  end
  if ready then
    local hint = Strings("(PRESS THE CART TO PLAY)")
    local hintX = tagX + tagW + math.floor(10 * m.s)
    local hintW = math.max(0, x + w - hintX)
    Kit.text("micro", Kit.ellipsize("micro", hint, hintW), hintX,
      y + (titleH - Kit.textHeight("micro")) / 2, PAL.heading)
  end
  -- Extra gap under the title when the cart is showing: 12px left the 3D
  -- shell sitting on the hairline.  Scaled, and still small on a phone.
  local afterTitle = math.floor((ready and 22 or 12) * m.s)
  local cy = y + titleH + afterTitle
  local remaining = availH - (titleH + afterTitle)

  local gap = m.gap
  local lx, lw, rx2, rw
  if m.twoCol then
    lx, lw = x, m.colW
    rx2, rw = x + m.colW + m.colGap, m.colW
  else
    lx, lw, rx2, rw = x, w, x, w
  end

  -- LEFT COLUMN, laid out DOWNWARD from the top.  It used to pin Play and a
  -- Touch-Controls/Reset-rebinds pair to the BOTTOM and fill the cards
  -- downward into whatever was left, which meant the column's height was
  -- whatever its text happened to need -- and on any window shorter than
  -- that pile the pinned block simply left the window (Play was measurably
  -- off-screen at 1280x720 and on every phone shape).  The controls pair has
  -- moved behind the gear (they are global settings, not per-game), the ROM
  -- and save file management moved into the manage modal and the slot card,
  -- and what is left is short enough to lay out top-down and always fit.
  local mdl = romModel(imp, version, info, ready, locked)
  local ly = cy

  if ready then
    -- The cartridge takes the Play button's former place.  Its portrait
    -- ratio comes from a real Game Boy cart rather than stretching the old
    -- horizontal control, and its body colour comes from the active game.
    local playH = math.floor(clamp(remaining * 0.52, 112 * m.s, 260 * m.s))
    local mgW = math.max(Kit.tapMin(), math.floor(34 * m.s))
    local bgap = math.floor(8 * m.s)
    local cartAreaW = lw - mgW - bgap
    local cartW = math.min(cartAreaW, math.floor(playH * 0.88))
    local cartX = lx + math.floor((cartAreaW - cartW) / 2)
    cartridgeButton(imp, cartX, ly, cartW, playH, "play-" .. version,
      version, gameName, function() imp:play(version, true) end)
    imp._gearIcon = imp._gearIcon
      or love.graphics.newImage("assets/launcher/gear.png")
    btn(imp, lx + lw - mgW, ly, mgW, mgW, "manage-" .. version, "", {
      face = "invert", image = imp._gearIcon,
      action = function() imp._gameManage = version end,
    })
    ly = ly + playH + gap
  end

  -- The ROM card, which now only exists while there is something to report:
  -- no ROM, a failed import, an import in flight, or an unsupported game.
  local romH = buildRomCard(imp, lx, ly, lw, m, version, mdl,
    m.twoCol and remaining or math.floor(remaining * 0.5))
  if romH > 0 then ly = ly + romH + gap end

  -- Save slots.  Two columns put them beside the left stack; ONE column
  -- stacks them underneath.  Either way the card is clipped to the room it
  -- actually has, and sizes its own list to that budget.
  if not locked then
    local slotY = m.twoCol and cy or ly
    local slotAvail = m.twoCol and remaining or (cy + remaining - ly)
    if slotAvail > 80 * m.s then
      Kit.pushClip(rx2, slotY, rw, math.max(0, slotAvail))
      buildSlotCard(imp, rx2, slotY, rw, slotAvail, m, version, ready)
      Kit.popClip()
    end
  end
end

-- --------------------------------------------------------------- mods panel

-- One line of { text, color } segments, ellipsized as a whole: each segment
-- gets whatever width the previous ones left, and the first segment that has
-- to ellipsize ends the line.  Lets the download count sit green inside an
-- otherwise muted stats line without two competing ellipsis passes.
-- A row's control key is a pure function of its id, but concatenating it per
-- visible row per frame is ~1200 strings a second.  Memoised on the launcher,
-- NOT on the entry: index entries are the same tables ModIndex.writeCache
-- persists into options.modIndexCache, and view state must not ride along.
local function rowKeyFor(imp, prefix, id)
  local keys = imp._rowKeys
  if not keys then keys = {}; imp._rowKeys = keys end
  local byPrefix = keys[prefix]
  if not byPrefix then byPrefix = {}; keys[prefix] = byPrefix end
  local key = byPrefix[id]
  if not key then key = prefix .. tostring(id); byPrefix[id] = key end
  return key
end

local function segLine(fontName, segs, x, y, maxW)
  local sx = x
  for _, seg in ipairs(segs) do
    local text = seg[1]
    local avail = maxW - (sx - x)
    if avail <= 0 then break end
    local shown = Kit.ellipsize(fontName, text, avail)
    Kit.text(fontName, shown, sx, y, seg[2])
    if shown ~= text then break end
    sx = sx + Kit.textWidth(fontName, text)
  end
end

-- The persisted sort choice both mod panels share.  The chooser itself is a
-- popup (buildSortModal); panels just read the current key and offer a
-- "Sort" button, which is what freed the chip row's two lines of space.
local function sortDefs(scope)
  local defs = {
    { key = "name", label = Strings("Name") },
    { key = "popularity", label = Strings("Most downloaded") },
  }
  if scope == "find" then
    defs[#defs + 1] = { key = "trending", label = Strings("Trending") }
  end
  defs[#defs + 1] = { key = "release", label = Strings("Release date") }
  defs[#defs + 1] = { key = "updated", label = Strings("Last updated") }
  return defs
end

-- Sorting is decorate-sort-undecorate: the key is computed once per entry
-- instead of the 2*n*log(n) times a comparator that derives it would, and the
-- comparator itself is a module-level function so no closure is allocated per
-- comparison.  Measured on a synthetic index: 500 entries went from 8,964 key
-- computations and 4,482 closures to 500 and none.
local sortAsc = true

local function decCompare(a, b)
  if a.k ~= b.k then
    if sortAsc then return a.k < b.k end
    return a.k > b.k   -- data sorts newest / most popular first
  end
  return a.tie < b.tie
end

-- Fill `scratch` with one { e, k, tie } slot per entry, reusing the slots.
local function decorate(scratch, src, keyOf, tieOf)
  local n = #src
  for i = 1, n do
    local e = src[i]
    local slot = scratch[i]
    if not slot then slot = {}; scratch[i] = slot end
    slot.e, slot.tie = e, tieOf(e)
    slot.k = keyOf(e, slot.tie)
  end
  for i = #scratch, n + 1, -1 do scratch[i] = nil end
  return n
end

local function undecorate(scratch, n)
  local out = {}
  for i = 1, n do out[i] = scratch[i].e end
  return out
end

-- While results are still streaming in, re-ordering on every arrival re-sorts
-- the whole list every frame and makes rows jump under the reader.  Hold the
-- current order this long and take the change in one pass.
local RESORT_DEBOUNCE = 0.25

-- True when the cached order is still good.  `rev` is only part of the key
-- for a stats-dependent sort: Name order does not depend on release data, so
-- a stats arrival used to invalidate a sort whose result could not change.
local function sortCacheOk(cache, src, key, rev, pending)
  if not (cache and cache.src == src and cache.key == key) then return false end
  if cache.rev == rev then return true end
  return pending and (Kit.time - (cache.at or 0)) < RESORT_DEBOUNCE
end

local function currentSort(imp, scope)
  local sortKey = imp.modSort
  if sortKey == nil then
    local ok, opts = pcall(require("src.core.SaveData").loadOptions)
    if ok and type(opts) == "table" and type(opts.modSort) == "string" then
      sortKey = opts.modSort
    end
    sortKey = sortKey or "popularity"
    imp.modSort = sortKey
  end
  if sortKey == "trending" and scope ~= "find" then return "popularity" end
  return sortKey
end

-- One compact coloured checkbox for each game.  The cartridge colour carries
-- the game identity even when the row is narrow.
local function modGameCheckbox(x, y, size, checked, game, id)
  local color = cartColor(game)
  local focused = Kit.focusable(id, x, y, size, size)
  local hot = focused or Kit.hover(x, y, size, size)
  if love.graphics then
    Theme.fillRounded(x, y, size, size, PAL.bg, 1)
    if checked then
      Theme.strokeRounded(x, y, size, size, color,
        hot and Theme.A.focus or 0.9, 1.5)
      drawCheck(x, y, size, color)
    else
      Theme.strokeRounded(x, y, size, size, color,
        hot and Theme.A.focus or Theme.A.hairline, 1)
    end
  end
  return Kit.press(x, y, size, size) or Kit._activateId == id
end

local function buildModsPanel(imp, x, y, w, availH, m)
  imp:_ensureMods()
  local ModUpdate = require("src.mods.ModUpdate")
  local mods = imp.mods or {}
  local gap = m.gap
  local cy = y

  -- header: progressive action cluster. Surfaces primary/frequent actions
  -- (Import, Updates, Sort) directly on the bar across screen sizes, placing
  -- bulk actions (Enable all / Disable all) into More... on compact viewports.
  local bh = m.btnH
  local importLabel = imp:_modsImportButtonLabel()
  local importW = Kit.textWidth("small", importLabel) + math.floor(24 * m.s)

  if #mods > 0 then
    local disableW = Kit.textWidth("small", Strings("Disable all")) + math.floor(20 * m.s)
    local enableW = Kit.textWidth("small", Strings("Enable all")) + math.floor(20 * m.s)
    local checkFullW = Kit.textWidth("small", Strings("Check for updates")) + math.floor(20 * m.s)
    local checkShortW = Kit.textWidth("small", Strings("Updates")) + math.floor(20 * m.s)
    local sortW = Kit.textWidth("small", Strings("Sort")) + math.floor(24 * m.s)
    local moreW = Kit.textWidth("small", Strings("More...")) + math.floor(20 * m.s)

    local fullReq = importW + disableW + enableW + checkFullW + sortW + math.floor(30 * m.s)
    local medReq = importW + checkShortW + sortW + moreW + math.floor(24 * m.s)

    local place = Layout.rightCluster(x, w, math.floor(6 * m.s))

    if fullReq <= w then
      -- Tier 1 (Desktop / Wide): Show all 5 full-text buttons
      btn(imp, place(importW), cy, importW, bh, "mods-import", importLabel, {
        kind = "accent", font = "small",
        action = function() imp:chooseMod() end })
      btn(imp, place(disableW), cy, disableW, bh, "mods-disable-all", Strings("Disable all"), {
        kind = "warn", font = "small",
        action = function() imp:_setAllMods(false) end })
      btn(imp, place(enableW), cy, enableW, bh, "mods-enable-all", Strings("Enable all"), {
        kind = "good", font = "small",
        action = function() imp:_setAllMods(true) end })
      btn(imp, place(checkFullW), cy, checkFullW, bh, "mods-check-updates", Strings("Check for updates"), {
        font = "small",
        action = function() imp:_syncModUpdateInfo(true) end })
      btn(imp, place(sortW), cy, sortW, bh, "mods-sort", Strings("Sort"), {
        font = "small",
        action = function() imp._sortPopup = "mods" end })
    elseif medReq <= w then
      -- Tier 2 (Medium / Compact): Surface Import, Updates, and Sort directly
      btn(imp, place(importW), cy, importW, bh, "mods-import", importLabel, {
        kind = "accent", font = "small",
        action = function() imp:chooseMod() end })
      btn(imp, place(checkShortW), cy, checkShortW, bh, "mods-check-updates", Strings("Updates"), {
        font = "small",
        action = function() imp:_syncModUpdateInfo(true) end })
      btn(imp, place(sortW), cy, sortW, bh, "mods-sort", Strings("Sort"), {
        font = "small",
        action = function() imp._sortPopup = "mods" end })
      btn(imp, place(moreW), cy, moreW, bh, "mods-more-actions", Strings("More..."), {
        font = "small",
        action = function() imp._modHeaderActionsPopup = true end })
    else
      -- Tier 3 (Ultra-Compact Mobile): Surface Import, Sort + More...
      local importShortLabel = Strings("Import")
      local importShortW = Kit.textWidth("small", importShortLabel) + math.floor(20 * m.s)
      local miniReq = importShortW + sortW + moreW + math.floor(18 * m.s)
      local useImportW = (miniReq <= w) and importShortW or importW

      btn(imp, place(useImportW), cy, useImportW, bh, "mods-import", (miniReq <= w) and importShortLabel or importLabel, {
        kind = "accent", font = "small",
        action = function() imp:chooseMod() end })
      btn(imp, place(sortW), cy, sortW, bh, "mods-sort", Strings("Sort"), {
        font = "small",
        action = function() imp._sortPopup = "mods" end })
      btn(imp, place(moreW), cy, moreW, bh, "mods-more-actions", Strings("More..."), {
        font = "small",
        action = function() imp._modHeaderActionsPopup = true end })
    end
  else
    local place = Layout.rightCluster(x, w, math.floor(6 * m.s))
    btn(imp, place(importW), cy, importW, bh, "mods-import", importLabel, {
      kind = "accent", font = "small",
      action = function() imp:chooseMod() end })
  end
  cy = cy + bh + math.floor(8 * m.s)

  -- notice line
  local noticeText, noticeCol
  if imp.modNotice then
    noticeText = imp.modNotice.text
    noticeCol = imp.modNotice.ok and PAL.green or PAL.red
  else
    noticeText, noticeCol = imp:_modsDefaultHint(), PAL.muted
  end
  cy = cy + Kit.textWrapped("small", noticeText, x, cy, w, noticeCol, 2)
    + math.floor(8 * m.s)

  cy = cy + buildModScopeRow(imp, x, cy, w, m)

  if #mods == 0 then
    imp.modScroll, imp._modScrollMax, imp._modListRect = 0, 0, nil
    Kit.emptyBox(x, cy, w, math.floor(110 * m.s), imp:_modsEmptyHint())
    return
  end

  local sortKey = currentSort(imp, "mods")

  -- Immediate mode paints this panel every frame; re-sorting the whole list
  -- per frame (with lowercased-string allocations in the comparator) fed the
  -- GC for nothing.  Cache the sorted array, keyed on the list identity, the
  -- sort mode, and the update-info revision the fetch pump bumps.
  local statsSort = sortKey ~= "name"
  local rev = statsSort and (imp._modUpdateRev or 0) or 0
  local cache = imp._modSortCache
  if cache and cache.n == #mods
      and sortCacheOk(cache, mods, sortKey, rev, imp._modInfoFetch ~= nil) then
    mods = cache.list
  else
    local scratch = imp._modSortScratch or {}
    imp._modSortScratch = scratch
    local n = decorate(scratch, mods,
      function(mod, tie)
        if sortKey == "name" then return tie end
        local info = mod.github and mod.github ~= "" and imp:_modUpdateInfo(mod.id)
        if sortKey == "popularity" then
          return info and info.downloads and info.downloads.total or -1
        end
        local date = info and info.dates
        if sortKey == "release" then return date and date.first or "0000-00-00" end
        return date and date.latest or "0000-00-00"
      end,
      function(mod) return (mod.name or ""):lower() end)
    sortAsc = sortKey == "name"
    table.sort(scratch, decCompare)
    local sorted = undecorate(scratch, n)
    imp._modSortCache = { src = mods, n = #mods, key = sortKey,
      rev = rev, at = Kit.time, list = sorted }
    mods = sorted
  end

  -- A mod row is a fixed height: its details first, then a dedicated second
  -- line of per-game checkboxes.  Fixed because a page of uniform rows is
  -- what lets perPage come from the viewport.
  local togH = math.floor(26 * m.s)
  local gamesLabel = Strings("Enable for:")
  local textH = Kit.textHeight("button") + math.floor(4 * m.s)
    + Kit.textHeight("small") + math.floor(2 * m.s) + Kit.textHeight("small")
  local rowH = math.floor(8 * m.s) + textH + math.floor(8 * m.s) + togH
    + math.floor(8 * m.s)
  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local listH = availH - (cy - y) - pagerH - gap
  local perPage = Kit.rowsThatFit(listH, rowH, gap, MIN_MODS_PER_PAGE, 20)
  local first, last, cur, pages = Kit.pageBounds(page(imp, "mods"), #mods, perPage)
  setPage(imp, "mods", cur)
  local listTop = cy
  local shown = math.max(0, last - first + 1)
  local contentH = shown * rowH + math.max(0, shown - 1) * gap
  local scrollMax = math.max(0, contentH - listH)
  local scroll = clamp(imp.modScroll or 0, 0, scrollMax)
  local lr = imp._modListRect
  if not lr then lr = {}; imp._modListRect = lr end
  lr.x, lr.y, lr.w, lr.h = x, listTop, w, listH
  imp._modScrollMax = scrollMax
  if scrollMax > 0 and (Kit.wheelY or 0) ~= 0 and Kit.hit(x, listTop, w, listH) then
    scroll = clamp(scroll - Kit.wheelY * math.floor(48 * m.s), 0, scrollMax)
    Kit.wheelY = 0
  elseif scrollMax == 0 then
    local wheelPage = Kit.wheelPage(x, listTop, w, listH, cur, #mods, perPage)
    if wheelPage ~= cur then imp.modScroll = 0 end
    setPage(imp, "mods", wheelPage)
  end
  imp.modScroll = scroll

  Kit.pushClip(x, listTop, w, listH)
  for i = first, last do
    local mod = mods[i]
    local ry = listTop + (i - first) * (rowH + gap) - scroll
    local rowKey = rowKeyFor(imp, "mod-row-", mod.id)
    local isFullyDisabled = true
    if mod.enabledByVersion then
      for _, on in pairs(mod.enabledByVersion) do
        if on then isFullyDisabled = false; break end
      end
    else
      isFullyDisabled = not mod.enabled
    end

    local focused = Kit.focusable(rowKey, x, ry, w, rowH)
    local hot = focused or Kit.hover(x, ry, w, rowH)
    if isFullyDisabled then
      Kit.card(x, ry, w, rowH, hot and "mutedHot" or "muted")
    else
      Kit.card(x, ry, w, rowH, hot)
    end
    local pad = math.floor(12 * m.s)
    local px, inner = x + pad, w - 2 * pad
    local ly = ry + math.floor(10 * m.s)

    local togGap = math.floor(5 * m.s) + 1
    local info = mod.github and mod.github ~= "" and imp:_modUpdateInfo(mod.id)

    -- These answer separate games, not a single shared install flag.  The
    -- importer receives the game id so an experimental confirmation also
    -- applies only to the checkbox the player pressed.
    local flipped = false
    local gamesY = ry + math.floor(8 * m.s) + textH + math.floor(8 * m.s)
    Kit.text("micro", gamesLabel, px,
      gamesY + (togH - Kit.textHeight("micro")) / 2, PAL.muted)
    local tx = px + Kit.textWidth("micro", gamesLabel) + math.floor(10 * m.s)
    for _, game in ipairs(GameVersion.ORDER) do
      local togKey = "mod-toggle-" .. mod.id .. "-" .. game
      if modGameCheckbox(tx, gamesY, togH,
          mod.enabledByVersion and mod.enabledByVersion[game] == true,
          game, togKey) then
        local version = game
        queueAction(imp, togKey, function() imp:_toggleMod(mod.id, nil, version) end)
        flipped = true
      end
      tx = tx + togH + togGap
    end
    -- The checkboxes sit inside the row's rect, so their press also passes the
    -- row hit test; `flipped` gates the row action to everywhere else.
    if not flipped
        and (Kit.press(x, ry, w, rowH) or Kit._activateId == rowKey) then
      local id = mod.id
      queueAction(imp, rowKey, function() imp._modActions = id end)
    end
    local textW = inner

    local badgeW = Kit.textWidth("micro", mod.badge) + math.floor(12 * m.s)
    -- the games the mod is for, beside its category: the same chip the
    -- in-game manager shows (src/mods/ModTargets.lua)
    local gamesW = mod.targets
      and Kit.textWidth("micro", mod.targets) + math.floor(12 * m.s) or 0
    local nameShown = Kit.ellipsize("button", mod.name,
      textW - badgeW - gamesW - math.floor(12 * m.s))
    local headingCol = isFullyDisabled and PAL.muted or PAL.heading
    Kit.text("button", nameShown, px, ly, headingCol)
    local tagX = px + Kit.textWidth("button", nameShown) + math.floor(8 * m.s)
    Kit.tag(tagX, ly, badgeW, Kit.textHeight("button"), mod.badge,
      mod.experimental and PAL.yellow or PAL.muted)
    if mod.targets then
      Kit.tag(tagX + badgeW + math.floor(4 * m.s), ly, gamesW,
        Kit.textHeight("button"), mod.targets,
        mod.targetsHere == false and PAL.steel or PAL.blue)
    end
    ly = ly + Kit.textHeight("button") + math.floor(4 * m.s)

    -- version + status + update state
    local statusText, statusCol = modStatusColor(mod.status)
    local line = "v" .. tostring(mod.version or "?") .. "   " .. statusText
    Kit.text("small", line, px, ly, statusCol)
    local lx = px + Kit.textWidth("small", line) + math.floor(12 * m.s)
    if imp:_modInfoPending(mod.id) then
      -- An inline spinner, because this row's release check is genuinely in
      -- flight -- the list stays usable while it resolves.
      Loader.dot(lx, ly, Kit.textHeight("small"))
      Kit.text("small", Strings("Checking..."),
        lx + Kit.textHeight("small") + math.floor(6 * m.s), ly, PAL.muted)
    elseif info and info.status == "available" then
      Kit.text("small", Strings("v%s available", tostring(info.latest)),
        lx, ly, PAL.yellow)
    elseif info and info.status == "current" then
      Kit.text("small", Strings("up to date"), lx, ly, PAL.muted)
    elseif info and info.status == "error" then
      Kit.text("small", Strings("check failed"), lx, ly, PAL.red)
    end
    ly = ly + Kit.textHeight("small") + math.floor(2 * m.s)

    -- one line of description, or the download stats when we have them
    -- (download count in green so popularity reads at a glance)
    if info and info.downloads then
      local d = info.dates
      local dl = ModUpdate.downloadsLine(info.downloads.total)
      local dates = ModUpdate.datesLine(d and d.first, d and d.latest)
      local segs = {}
      if dl then segs[#segs + 1] = { dl, PAL.green } end
      if dates then
        segs[#segs + 1] = { (dl and "  -  " or "") .. dates, PAL.detail }
      end
      segLine("small", segs, px, ly, textW)
    elseif (mod.description or "") ~= "" then
      Kit.text("small", Kit.ellipsize("small", mod.description, textW),
        px, ly, PAL.detail)
    end
  end
  Kit.popClip()

  local pagerY = listTop + listH + gap
  local newPage = Kit.pager(x, pagerY, w, cur, #mods, perPage, "mods")
  if newPage ~= cur then imp.modScroll = 0 end
  setPage(imp, "mods", newPage)
end

-- ---------------------------------------------------------- find mods panel

-- SKINS tab: pick the on-screen skin, import one, or open the desktop studio.
local function buildSkinsPanel(imp, x, y, w, availH, m)
  local skins = imp:_ensureSkins()
  local active = imp:_activeSkin()
  local gap = m.gap
  local cy = y

  local title = Strings("Skins/Borders")
  local bh = m.btnH
  local importLabel = imp:_skinsImportButtonLabel()
  local importW = Kit.textWidth("small", importLabel) + math.floor(24 * m.s)
  if Kit.textWidth("button", title) + importW + math.floor(24 * m.s) > w then
    importLabel = Strings("Import")
    importW = Kit.textWidth("small", importLabel) + math.floor(20 * m.s)
  end
  local place = Layout.rightCluster(x, w, math.floor(6 * m.s))
  btn(imp, place(importW), cy, importW, bh, "skins-import", importLabel, {
    kind = "accent", font = "small",
    action = function() imp:chooseSkin() end })
  Kit.text("button", Kit.ellipsize("button", title,
    math.max(0, w - importW - math.floor(12 * m.s))), x,
    cy + math.floor((bh - Kit.textHeight("button")) / 2), PAL.heading)
  cy = cy + bh + math.floor(8 * m.s)

  if imp._skinNotice then
    cy = cy + Kit.textWrapped("small", imp._skinNotice.text, x, cy, w,
      imp._skinNotice.ok and PAL.green or PAL.red, 2) + math.floor(8 * m.s)
  end

  -- Studio button.  Desktop only: the host supplies the hook nowhere else.
  if imp.onOpenSkinStudio then
    local label = Strings("Open Skin Studio")
    local bw = math.min(w, Kit.textWidth("small", label) + math.floor(40 * m.s))
    btn(imp, x, cy, bw, m.btnH, "skins-studio", label, {
      kind = "accent", font = "small",
      action = function()
        -- the studio boots the game on Play, so hand it a real cartridge
        imp.onOpenSkinStudio(imp.modScope or "red")
      end })
    local hint = Strings("Design bezels and button layouts, then test them.")
    Kit.text("small", Kit.ellipsize("small", hint,
      w - bw - math.floor(12 * m.s)), x + bw + math.floor(12 * m.s),
      cy + math.floor((m.btnH - Kit.textHeight("small")) / 2), PAL.muted)
    cy = cy + m.btnH + gap
  end

  Kit.caption(x, cy, Strings("INSTALLED"))
  cy = cy + Kit.textHeight("small") + math.floor(6 * m.s)

  local rowH = math.max(Kit.tapMin(), math.floor(44 * m.s))
  imp._skinGear = imp._skinGear
    or love.graphics.newImage("assets/launcher/gear.png")

  -- The row itself is "use this skin"; the gear beside it configures that
  -- entry -- the built-in pad opens the drag-a-button layout editor, a skin
  -- opens the studio, so neither lands on a screen that cannot edit it.
  local function skinRow(key, id, title, detail, selected, configure)
    local gearW = configure and rowH or 0
    local rowW = w - (gearW > 0 and (gearW + math.floor(6 * m.s)) or 0)
    local ink = rowHit(imp, x, cy, rowW, rowH, selected, key,
      function() imp:_useSkin(id) end)
    local tagW = selected
      and (Kit.textWidth("small", Strings("IN USE")) + math.floor(20 * m.s))
      or math.floor(12 * m.s)
    local textW = rowW - math.floor(24 * m.s) - tagW
    local tx = x + math.floor(12 * m.s)
    local ty = cy + math.floor(7 * m.s)
    Kit.text("mono", Kit.ellipsize("mono", title, textW), tx, ty,
      ink or PAL.heading)
    Kit.text("small", Kit.ellipsize("small", detail, textW),
      tx, ty + Kit.textHeight("mono"), ink or PAL.muted)
    if selected then
      Kit.textRight("small", Strings("IN USE"), x + rowW - math.floor(12 * m.s),
        cy + math.floor((rowH - Kit.textHeight("small")) / 2), ink or PAL.green)
    end
    if configure then
      btn(imp, x + w - gearW, cy, gearW, gearW, key .. "-cfg", "", {
        face = "invert", image = imp._skinGear, action = configure })
    end
    cy = cy + rowH + math.floor(4 * m.s)
  end

  local entries = { false }
  for _, entry in ipairs(skins) do entries[#entries + 1] = entry end

  local TouchSkin = require("src.core.TouchSkin")
  local hint = Strings(
    "You can also drop a skin .zip on this window, or put a folder in %s/ of your save directory. RetroArch overlay .cfg files work as-is.",
    TouchSkin.USER_ROOT)
  local hintH = Kit.wrapHeight("small", hint, w, 3)
  local importH = math.floor(10 * m.s) + hintH

  local rowGap = math.floor(4 * m.s)
  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local listTop = cy
  local listH = availH - (cy - y) - importH
  local perPage = Kit.rowsThatFit(listH, rowH, rowGap, 1, 20)
  if #entries > perPage then
    perPage = Kit.rowsThatFit(listH - pagerH - gap, rowH, rowGap, 1, 20)
  end
  local first, last, cur, pages = Kit.pageBounds(page(imp, "skins"),
    #entries, perPage)
  setPage(imp, "skins", cur)
  setPage(imp, "skins",
    Kit.wheelPage(x, listTop, w, listH, cur, #entries, perPage))

  for i = first, last do
    local entry = entries[i]
    if not entry then
      skinRow("skin-none", nil, Strings("Built-in pad"),
        Strings("The default on-screen buttons."), active == nil,
        imp.onEditTouchControls and function()
          imp.onEditTouchControls(imp.modScope or "red")
        end or nil)
    else
      local bits = {}
      bits[#bits + 1] = entry.source == "user" and Strings("installed")
        or Strings("bundled")
      if entry.controls > 0 then
        bits[#bits + 1] = entry.controls .. " " .. Strings("buttons")
      else
        bits[#bits + 1] = Strings("bezel only")
      end
      if entry.pages > 1 then
        bits[#bits + 1] = entry.pages .. " " .. Strings("pages")
      end
      if entry.screen then bits[#bits + 1] = Strings("screen cutout") end
      local configure = imp.onOpenSkinStudio and function()
        imp.onOpenSkinStudio(imp.modScope or "red", entry.id)
      end or nil
      skinRow("skin-" .. entry.id, entry.id, entry.id,
        table.concat(bits, "  \194\183  "), active == entry.id, configure)
    end
  end

  if #skins == 0 then
    Kit.emptyBox(x, cy, w, math.floor(72 * m.s),
      Strings("No skins installed yet."))
    cy = cy + math.floor(72 * m.s) + gap
  end

  if pages > 1 then
    setPage(imp, "skins",
      Kit.pager(x, cy, w, cur, #entries, perPage, "skins"))
    cy = cy + pagerH + gap
  end

  cy = cy + math.floor(10 * m.s)
  Kit.textWrapped("small", hint, x, cy, w, PAL.muted, 3)
end

local function buildFindPanel(imp, x, y, w, availH, m)
  imp:_ensureFind()
  imp:_ensureMods()
  local ModIndex = require("src.mods.ModIndex")
  local ModUpdate = require("src.mods.ModUpdate")
  local sources = imp.findSources or {}
  local rows = imp:_findRows()
  local total = #((imp.findIndex and imp.findIndex.mods) or {})
  local gap = m.gap
  local cy = y

  -- No headline, no disclaimer paragraph: the active tab already names this
  -- panel, and the index list, the category filter and the sort choice all
  -- moved into popups (Indexes / Filter / Sort) so the space goes to rows.
  -- Only a live action-feedback notice (Installed X / errors) earns a line.
  if imp.findNotice then
    cy = cy + Kit.textWrapped("small", imp.findNotice.text, x, cy, w,
      imp.findNotice.ok and PAL.green or PAL.red, 2) + math.floor(8 * m.s)
  end

  if #sources == 0 then
    local h = math.floor(140 * m.s)
    Kit.card(x, cy, w, h)
    Kit.textCenter("button", Strings("No mod index added"), x,
      cy + math.floor(24 * m.s), w, PAL.heading)
    Kit.textWrapped("small", Strings(
      "Add an index to browse mods. An index is a published list; paste its URL or its owner/repo."),
      x + math.floor(24 * m.s), cy + math.floor(54 * m.s),
      w - math.floor(48 * m.s), PAL.muted, 2)
    local aw = Kit.textWidth("small", Strings("Add an index"))
      + math.floor(28 * m.s)
    btn(imp, x + math.floor((w - aw) / 2), cy + h - m.btnH - math.floor(14 * m.s),
      aw, m.btnH, "find-add", Strings("Add an index"), {
        kind = "accent", font = "small",
        action = function() imp._indexManage = true end })
    return
  end

  -- One row: the search field, then Filter / Sort / Indexes popup buttons.
  local fieldH = math.max(Kit.tapMin(), math.floor(36 * m.s))
  local bgap = math.floor(6 * m.s)
  local place = Layout.rightCluster(x, w, bgap)
  local xw = Kit.textWidth("small", Strings("Indexes")) + math.floor(20 * m.s)
  btn(imp, place(xw), cy, xw, fieldH, "find-indexes", Strings("Indexes"), {
    font = "small",
    action = function() imp._indexManage = true end })
  local sw = Kit.textWidth("small", Strings("Sort")) + math.floor(20 * m.s)
  btn(imp, place(sw), cy, sw, fieldH, "find-sort", Strings("Sort"), {
    font = "small",
    action = function() imp._sortPopup = "find" end })
  -- The Filter button carries its state: blue while a category is active,
  -- so a filtered-down list never reads as "the index shrank".
  local fw = Kit.textWidth("small", Strings("Filter")) + math.floor(20 * m.s)
  btn(imp, place(fw), cy, fw, fieldH, "find-filter", Strings("Filter"), {
    kind = imp.findCategory and "accent" or "ghost", font = "small",
    action = function() imp._filterPopup = true end })
  local searchW = place(0) - x - bgap
  textField(imp, x, cy, searchW, fieldH, "find-search", imp.findQuery or "",
    Strings("Search mods"), imp._findSearchFocus == true,
    function() imp:_toggleFindSearchFocus() end)
  cy = cy + fieldH + math.floor(8 * m.s)

  if #rows == 0 then
    Kit.emptyBox(x, cy, w, math.floor(110 * m.s),
      (total == 0) and Strings("This index lists no mods yet.")
        or Strings("No mods match that search."))
    return
  end

  local sortKey = currentSort(imp, "find")

  -- Same caching rule as the MODS tab: the comparator allocates, so only
  -- re-sort when the inputs actually change.
  local statsSort = sortKey ~= "name"
  local rev = statsSort and (imp._findStatsRev or 0) or 0
  local fcache = imp._findSortCache
  if sortCacheOk(fcache, rows, sortKey, rev, imp._findStatsPending ~= nil) then
    rows = fcache.list
  else
    local scratch = imp._findSortScratch or {}
    imp._findSortScratch = scratch
    local n = decorate(scratch, rows,
      function(entry, tie)
        if sortKey == "name" then return tie end
        -- The CACHED read, never the requesting one: a sort must not queue a
        -- fetch for every entry in the index (see _findStatsCached).
        local stats = imp:_findStatsCached(entry)
        if sortKey == "popularity" then return stats and stats.total or -1 end
        if sortKey == "trending" then return stats and stats.recent or -1 end
        if sortKey == "release" then return stats and stats.first or "0000-00-00" end
        return stats and stats.latest or "0000-00-00"
      end,
      function(entry) return (entry.title or entry.id or ""):lower() end)
    sortAsc = sortKey == "name"
    table.sort(scratch, decCompare)
    local sorted = undecorate(scratch, n)
    imp._findSortCache = { src = rows, key = sortKey, rev = rev,
      at = Kit.time, list = sorted }
    rows = sorted
  end

  local installed = imp:_findInstalledMap()
  -- The thumbnail sits BESIDE the text and the action chips share the title
  -- line's row, so a card is only as tall as its text block.  The old layout
  -- stacked chips under a 64px thumbnail and got ~2 rows per screen; this
  -- fits roughly twice as many without shrinking a single tap target.
  local thumb = math.floor(44 * m.s)
  local chipH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  -- TWO text lines, not three: the version/author/category meta and the
  -- download stats share a line.  A third line cost every row ~20px, which
  -- at this UI scale was the difference between one and two rows per page.
  local textH = Kit.textHeight("button") + math.floor(4 * m.s)
    + Kit.textHeight("small")
  local rowH = math.floor(8 * m.s) + math.max(thumb, textH, chipH)
    + math.floor(8 * m.s)
  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local listH = availH - (cy - y) - pagerH - gap
  local perPage = Kit.rowsThatFit(listH, rowH, gap, 1, 20)
  local first, last, cur, pages = Kit.pageBounds(page(imp, "find"), #rows, perPage)
  setPage(imp, "find", cur)
  local listTop = cy
  setPage(imp, "find", Kit.wheelPage(x, listTop, w, listH, cur, #rows, perPage))

  for i = first, last do
    local entry = rows[i]
    local ry = listTop + (i - first) * (rowH + gap)
    local rowKey = rowKeyFor(imp, "find-row-", entry.id)
    -- The whole row is the control: it opens the per-mod popup where
    -- Install / Details / Source moved.  The only inline signal left is a
    -- green check when the mod is already installed.
    local focused = Kit.focusable(rowKey, x, ry, w, rowH)
    local hot = focused or Kit.hover(x, ry, w, rowH)
    Kit.card(x, ry, w, rowH, hot)
    local pad = math.floor(12 * m.s)
    local px, inner = x + pad, w - 2 * pad
    local ly = ry + math.floor(8 * m.s)

    if Kit.press(x, ry, w, rowH) or Kit._activateId == rowKey then
      local e = entry
      queueAction(imp, rowKey, function() imp._findEntry = e end)
    end

    local _, note = findActionFor(entry, installed[entry.id])
    local chipsW = 0
    if installed[entry.id] then
      local ck = math.floor(20 * m.s)
      drawCheck(px + inner - ck, ry + (rowH - ck) / 2, ck, PAL.green)
      chipsW = ck + math.floor(6 * m.s)
    end

    -- thumbnail (or its placeholder while the async fetch is in flight)
    local image = imp:_findThumb(entry)
    if image then
      local iw3, ih3 = image:getDimensions()
      local s = math.min(thumb / iw3, thumb / ih3)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(image, Theme.snap(px), Theme.snap(ly), 0, s, s)
    else
      Theme.stroke(px, ly, thumb, thumb, PAL.line, Theme.A.hairline, 1)
      -- A thumbnail still downloading and one that will never arrive drew the
      -- same dead box, so a slow index looked broken.  Spin while it is in
      -- flight; only fall back to the wordmark once it has resolved.
      if imp:_findThumbPending(entry.id) then
        Kit.spinner(px + thumb / 2, ly + thumb / 2, thumb * 0.28)
      else
        Kit.textCenter("micro", "MOD", px,
          ly + (thumb - Kit.textHeight("micro")) / 2, thumb, PAL.faint)
      end
    end

    local bx = px + thumb + math.floor(10 * m.s)
    local bw = inner - thumb - math.floor(10 * m.s) - chipsW
    Kit.text("button", Kit.ellipsize("button", entry.title or entry.id, bw),
      bx, ly, PAL.heading)
    local by2 = ly + Kit.textHeight("button") + math.floor(4 * m.s)
    -- meta and stats on one line, the download count first (and green)
    -- because it is what the default Most-downloaded sort is ordering by: a
    -- narrow window ellipsizes the tail, and the count must survive that.
    local stats = imp:_findStats(entry)
    local baseCol = note and PAL.green or PAL.detail
    local lead = "v" .. tostring(ModIndex.displayVersion(entry))
    if note then lead = lead .. "  -  " .. note end
    local dl = stats and ModUpdate.downloadsShort(stats.total) or nil
    local hasCount = stats ~= nil and stats.total ~= nil
    local dates = stats and ModUpdate.datesLine(stats.first, stats.latest)
      or nil
    local rest = {}
    if entry.author then rest[#rest + 1] = entry.author end
    if entry.categories and entry.categories[1] then
      rest[#rest + 1] = entry.categories[1]
    end
    if dates then
      rest[#rest + 1] = dates
    elseif not hasCount and (entry.summary or "") ~= "" then
      rest[#rest + 1] = entry.summary
    end
    local segs = { { lead, baseCol } }
    if dl then
      segs[#segs + 1] = { "  -  " .. dl, hasCount and PAL.green or PAL.faint }
    end
    if #rest > 0 then
      segs[#segs + 1] = { "  -  " .. table.concat(rest, "  -  "), baseCol }
    end
    segLine("small", segs, bx, by2, bw)
    -- The stats line used to simply be absent until the release check landed,
    -- so rows silently changed under the reader and a slow check was
    -- indistinguishable from a mod with no data.  Say which it is, the way
    -- the MODS tab already does on its own rows.
    if not stats and imp:_findStatsPendingFor(entry.id) then
      local sw = Kit.textWidth("small", segs[1][1]) + math.floor(12 * m.s)
      local dh = Kit.textHeight("small")
      Loader.dot(bx + sw, by2, dh)
      Kit.text("small", Strings("Checking..."),
        bx + sw + dh + math.floor(6 * m.s), by2, PAL.muted)
    end
  end

  local pagerY = listTop + (last - first + 1) * (rowH + gap)
  setPage(imp, "find", Kit.pager(x, pagerY, w, cur, #rows, perPage, "find"))

  -- Aggregate progress.  Enrichment happens a page at a time and each row says
  -- so for itself, but with nothing summarising it the panel looked idle while
  -- work was in flight.  Only drawn while something is actually pending.
  local waiting = imp:_findStatsPendingCount()
  if waiting > 0 then
    local py = pagerY + math.max(Kit.tapMin(), math.floor(30 * m.s))
      + math.floor(4 * m.s)
    local dh = Kit.textHeight("micro")
    Loader.dot(x, py, dh)
    Kit.text("micro", Strings("Checking %d of %d on this page...",
      waiting, last - first + 1),
      x + dh + math.floor(6 * m.s), py, PAL.muted)
  end
end

-- ------------------------------------------------------------------ footer

local TRUST_WARNING = "if you did not get this from bryanthaboi's github "
  .. "or a link from the discord that bryanthaboi himself posted, just know "
  .. "it might have been tampered with. go to the discord to verify "
  .. COMMUNITY_URL .. " (or click the logo above)"

-- Mark + optional updater + Patch notes.  Chips match the mark's 22px
-- height so they do not read as bigger than the logo; the row can still
-- be tapMin tall for spacing.  On a phone the notes chip drops onto a
-- second row rather than overflowing the mark.
local function footerLayout(imp, m, markW)
  local markH = math.floor(22 * m.s)
  local rowH = math.max(markH, Kit.tapMin())
  local notesLabel = Strings("Patch notes")
  -- Tight chip, still enough for Kit.button's labelInset so the words survive.
  local chipPad = math.floor(24 * m.s)
  local nw = Kit.textWidth("micro", notesLabel) + chipPad
  local upStatus, upLabel, upAction, upGlow = LauncherView._updateControl(imp)
  local uw = upStatus
    and (Kit.textWidth("micro", upLabel) + chipPad) or 0
  local gap = math.floor(10 * m.s)
  local inner = m.w - 2 * m.pad
  local topW = (markW or 0) + (upStatus and (gap + uw) or 0) + gap + nw
  return {
    rowH = rowH, chipH = markH, gap = gap,
    notesLabel = notesLabel, nw = nw,
    upStatus = upStatus, upLabel = upLabel, upAction = upAction, upGlow = upGlow,
    uw = uw, wrap = topW > inner,
  }
end

-- Pinned to the bottom of the window; returns the y it starts at, so the
-- panels above know how much room they have.
-- Deliberately compact: at a large UI scale the footer is pure overhead
-- competing with the panel for a short window's height, so the mark and the
-- link share one line and the trust warning is capped at a single line.
local function footerHeight(imp, m)
  -- Top pad + mark/update row + optional notes wrap row + gap + the FULL
  -- wrapped trust message + bottom pad.  The message wraps to as many lines
  -- as it needs: truncating a trust warning defeats its purpose, and the
  -- bottom pad is not optional either (without it the last line sits flush
  -- on the window edge and its lower half clips off).  The row is tapMin
  -- tall because the small update button rides beside the mark.
  local f = footerLayout(imp, m, math.floor(130 * m.s))
  local h = math.floor(8 * m.s) + f.rowH + math.floor(6 * m.s)
  if f.wrap then h = h + f.chipH + math.floor(6 * m.s) end
  return h + Kit.wrapHeight("micro", TRUST_WARNING, m.contentW)
    + math.floor(8 * m.s)
end

local function buildFooter(imp, m, y)
  Theme.fill(m.x, y, m.w, 1, PAL.line, Theme.A.hairline)
  local cy = y + math.floor(8 * m.s)
  -- The BCG mark is dark ink; invert it for the black field.
  imp.invertShader = imp.invertShader or love.graphics.newShader([[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc);
      return vec4((vec3(1.0) - p.rgb) * color.rgb, p.a * color.a);
    }
  ]])
  local bw, bh = imp.bcg:getDimensions()
  local scale = math.min((130 * m.s) / bw, (22 * m.s) / bh)
  local dw, dh = bw * scale, bh * scale
  local f = footerLayout(imp, m, dw)
  local rowH, gap, chipH = f.rowH, f.gap, f.chipH
  -- The mark, the small self-update control, and Patch notes share the row,
  -- centred as a group.  The updater moved down here from the header, where
  -- it overlapped the wordmark on a phone; small on purpose, its glow still
  -- carries the "act on me" signal.  Notes wrap under the mark on a phone.
  local topW = dw + (f.upStatus and (gap + f.uw) or 0)
  if not f.wrap then topW = topW + gap + f.nw end
  local bx = m.x + math.floor((m.w - topW) / 2)
  local my = cy + math.floor((rowH - dh) / 2)
  local chipY = cy + math.floor((rowH - chipH) / 2)
  local hot = Kit.hover(bx, my, dw, dh)
  love.graphics.setShader(imp.invertShader)
  love.graphics.setColor(1, 1, 1, hot and 1 or 0.85)
  love.graphics.draw(imp.bcg, Theme.snap(bx), Theme.snap(my), 0, scale, scale)
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
  if Kit.press(bx, my, dw, dh) then
    queueAction(imp, "bcg", function() love.system.openURL(COMMUNITY_URL) end)
  end
  local cx = bx + dw
  if f.upStatus then
    cx = cx + gap
    btn(imp, cx, chipY, f.uw, chipH, "updater",
      f.upLabel, {
        kind = f.upGlow and "warn" or "ghost", font = "micro",
        glow = f.upGlow, action = f.upAction,
      })
    cx = cx + f.uw
  end
  local function notesBtn(x, y)
    btn(imp, x, y, f.nw, chipH, "patch-notes", f.notesLabel, {
      kind = "ghost", font = "micro",
      action = function() imp._appPatchNotes = true end,
    })
  end
  if f.wrap then
    cy = cy + rowH + gap
    notesBtn(m.x + math.floor((m.w - f.nw) / 2), cy)
    cy = cy + chipH + math.floor(6 * m.s)
  else
    notesBtn(cx + gap, chipY)
    cy = cy + rowH + math.floor(6 * m.s)
  end
  -- The trust message wraps in full, each line centred under the mark, and
  -- the URL inside it IS the link -- no separate link floating elsewhere.
  -- font:getWrap never splits an unspaced word, so the URL stays whole on
  -- one line and a plain substring find locates it.
  local lines = Kit.wrapLines("micro", TRUST_WARNING, m.contentW)
  local lh = Kit.textHeight("micro")
  for i, line in ipairs(lines or {}) do
    local lw = Kit.textWidth("micro", line)
    local lx = m.contentX + math.floor((m.contentW - lw) / 2)
    local ly = cy + (i - 1) * lh
    local s0, e0 = line:find(COMMUNITY_URL, 1, true)
    if s0 then
      local pre = line:sub(1, s0 - 1)
      local url = line:sub(s0, e0)
      Kit.text("micro", pre, lx, ly, PAL.muted)
      local ux = lx + Kit.textWidth("micro", pre)
      local uw = Kit.textWidth("micro", url)
      Kit.text("micro", url, ux, ly, PAL.blue)
      Theme.fill(ux, ly + lh - 1, uw, 1, PAL.blue, 0.6)
      if Kit.press(ux, ly, uw, lh) then
        queueAction(imp, "bois", function()
          love.system.openURL(COMMUNITY_URL)
        end)
      end
      Kit.text("micro", line:sub(e0 + 1), ux + uw, ly, PAL.muted)
    else
      Kit.text("micro", line, lx, ly, PAL.muted)
    end
  end
end

-- ------------------------------------------------------------------ modals
-- A modal draws its own scrim, then raises Kit.blockClicks so everything
-- underneath is inert, then lowers it for its own panel.  There is no
-- z-ordered hit test, so this ordering IS the z-order.

local function modalPanel(m, w, h)
  -- A near-opaque scrim, not a tint.  At 0.82 the header and the wordmark
  -- still read through the settings panel and the screen looked like two
  -- layouts fighting rather than one panel on top ("the settings is covering
  -- the logo"); at this weight the page behind is present but plainly out of
  -- play, which is what a modal is supposed to say.
  Theme.fill(0, 0, m.W, m.H, PAL.bg, 0.93)
  Kit.blockClicks = true
  local pw = math.floor(math.min(w, m.W - 2 * m.pad))
  local ph = math.floor(math.min(h, m.H - 2 * m.pad))
  local px = math.floor((m.W - pw) / 2)
  local py = math.floor((m.H - ph) / 2)
  Kit.card(px, py, pw, ph, true)
  Kit.blockClicks = false
  return px, py, pw, ph
end

-- Shared prompt: title, read-only field over the importer's text, buttons.
local function buildPrompt(imp, m, spec)
  local pad = math.floor(18 * m.s)
  local fieldH = math.max(Kit.tapMin(), math.floor(36 * m.s))
  local w = math.floor(460 * m.s)
  local hintH = spec.hint and (Kit.wrapHeight("small", spec.hint,
    w - 2 * pad, 2) + math.floor(6 * m.s)) or 0
  local footH = spec.footnote and (Kit.textHeight("micro")
    + math.floor(8 * m.s)) or 0
  local h = pad + Kit.textHeight("button") + math.floor(10 * m.s) + hintH
    + fieldH + math.floor(12 * m.s) + m.btnH + footH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", spec.title, px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(10 * m.s)
  if spec.hint then
    cy = cy + Kit.textWrapped("small", spec.hint, px + pad, cy,
      pw - 2 * pad, PAL.detail, 2) + math.floor(6 * m.s)
  end
  textField(imp, px + pad, cy, pw - 2 * pad, fieldH, spec.key .. "-field",
    spec.text or "", nil, true)
  cy = cy + fieldH + math.floor(12 * m.s)

  local place = Layout.rightCluster(px + pad, pw - 2 * pad, math.floor(8 * m.s))
  local okW = Kit.textWidth("small", spec.okLabel or Strings("Save"))
    + math.floor(28 * m.s)
  btn(imp, place(okW), cy, okW, m.btnH, spec.key .. "-ok",
    spec.okLabel or Strings("Save"),
    { kind = "primary", font = "small", action = spec.commit })
  local cw = Kit.textWidth("small", Strings("Cancel")) + math.floor(28 * m.s)
  btn(imp, place(cw), cy, cw, m.btnH, spec.key .. "-cancel", Strings("Cancel"),
    { font = "small", action = spec.cancel })
  if spec.paste then
    local pwid = Kit.textWidth("small", Strings("Paste")) + math.floor(28 * m.s)
    btn(imp, px + pad, cy, pwid, m.btnH, spec.key .. "-paste", Strings("Paste"),
      { kind = "accent", font = "small", action = spec.paste })
  end
  cy = cy + m.btnH + math.floor(8 * m.s)
  if spec.footnote then
    Kit.text("micro", spec.footnote, px + pad, cy, PAL.muted)
  end
end

local function buildConfirmModal(imp, m)
  local c = imp._modConfirm
  local pad = math.floor(22 * m.s)
  local w = math.floor(520 * m.s)
  local lineH = Kit.textHeight("small") + math.floor(4 * m.s)
  local h = pad + Kit.textHeight("stat") + math.floor(12 * m.s)
    + #(c.lines or {}) * lineH + math.floor(12 * m.s) + m.btnH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("stat", c.title or Strings("Confirm"), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("stat") + math.floor(12 * m.s)
  for _, line in ipairs(c.lines or {}) do
    Kit.text("small", Kit.ellipsize("small", line, pw - 2 * pad),
      px + pad, cy, PAL.detail)
    cy = cy + lineH
  end
  cy = cy + math.floor(12 * m.s)
  local gap = math.floor(10 * m.s)
  local halfW = math.floor((pw - 2 * pad - gap) / 2)
  btn(imp, px + pad, cy, halfW, m.btnH, "confirm-yes",
    c.yesLabel or Strings("OK"), {
      kind = "primary", font = "small",
      action = function()
        imp._modConfirm = nil
        if c.indexEntry then
          imp:_findInstall(c.indexEntry)
        elseif c.kind == "update" then
          imp:_confirmModUpdate(c.id, c.release)
        elseif c.kind == "enableAll" then
          imp:_setAllMods(true, true)
        elseif c.kind == "importOversize" then
          imp:_importSave(c.version, c.source, true)
        else
          imp:_toggleMod(c.id, true, c.version)
        end
      end,
    })
  btn(imp, px + pad + halfW + gap, cy, halfW, m.btnH, "confirm-no",
    Strings("Cancel"), { font = "small",
      action = function() imp._modConfirm = nil end })
end

-- A body of text, paginated rather than scrolled (release notes, mod
-- descriptions).  Long-form text is the one place a scrollbar was genuinely
-- convenient, so the pager here moves a LINE window instead of a row window.
local function buildTextModal(imp, m, key, title, body, closeFn)
  local pad = math.floor(18 * m.s)
  local w = math.floor(520 * m.s)
  local h = math.floor(math.min(m.H - 2 * m.pad, 460 * m.s))
  local px, py, pw, ph = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Kit.ellipsize("button", title, pw - 2 * pad),
    px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(10 * m.s)

  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local bodyH = (py + ph - pad) - cy - m.btnH - math.floor(10 * m.s)
    - pagerH - math.floor(8 * m.s)
  local lineH = Kit.textHeight("small")
  local perPage = math.max(1, math.floor(bodyH / lineH))
  local lines = Kit.wrapLines("small", body, pw - 2 * pad) or { "" }
  local first, last, cur = Kit.pageBounds(page(imp, key), #lines, perPage)
  setPage(imp, key, cur)
  setPage(imp, key, Kit.wheelPage(px, cy, pw, bodyH, cur, #lines, perPage))
  for i = first, last do
    Kit.text("small", lines[i], px + pad, cy + (i - first) * lineH, PAL.detail)
  end
  cy = cy + bodyH + math.floor(8 * m.s)
  setPage(imp, key, Kit.pager(px + pad, cy, pw - 2 * pad, cur, #lines,
    perPage, key))
  cy = cy + pagerH + math.floor(10 * m.s)
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, key .. "-close",
    Strings("Close"), { font = "small", action = closeFn })
end

local function buildVersionsModal(imp, m)
  local ModUpdate = require("src.mods.ModUpdate")
  local v = imp._modVersions
  local pad = math.floor(18 * m.s)
  local w = math.floor(520 * m.s)
  local h = math.floor(math.min(m.H - 2 * m.pad, 480 * m.s))
  local px, py, pw, ph = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Kit.ellipsize("button",
    Strings("Other versions: ") .. tostring(v.name), pw - 2 * pad),
    px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(6 * m.s)

  local info = imp:_modUpdateInfo(v.id)
  local statusTxt = Strings("Installed: v") .. tostring(v.current)
  local statusCol = PAL.detail
  if info and info.status == "available" then
    statusTxt = statusTxt .. "  -  " .. Strings("Update v") .. tostring(info.latest)
    statusCol = PAL.yellow
  elseif info and info.status == "current" then
    statusTxt = statusTxt .. "  -  " .. Strings("Up to date")
    statusCol = PAL.green
  end
  Kit.text("small", statusTxt, px + pad, cy, statusCol)
  cy = cy + Kit.textHeight("small") + math.floor(10 * m.s)

  local chipH = math.max(Kit.tapMin(), math.floor(28 * m.s))
  local rowH = math.floor(8 * m.s) + Kit.textHeight("small")
    + math.floor(4 * m.s) + chipH + math.floor(8 * m.s)
  local gap = math.floor(6 * m.s)
  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local listH = (py + ph - pad) - cy - m.btnH - math.floor(10 * m.s)
    - pagerH - math.floor(8 * m.s)
  local perPage = Kit.rowsThatFit(listH, rowH, gap, 1, 12)
  local n = #v.releases
  local first, last, cur = Kit.pageBounds(page(imp, "versions"), n, perPage)
  setPage(imp, "versions", cur)
  setPage(imp, "versions",
    Kit.wheelPage(px, cy, pw, listH, cur, n, perPage))

  for i = first, last do
    local rel = v.releases[i]
    local ry = cy + (i - first) * (rowH + gap)
    Theme.stroke(px + pad, ry, pw - 2 * pad, rowH, PAL.line, Theme.A.hairline, 1)
    local ix = px + pad + math.floor(10 * m.s)
    local inner = pw - 2 * pad - math.floor(20 * m.s)
    local text = "v" .. rel.version
    if rel.version == v.current then text = text .. Strings(" (installed)") end
    if rel.prerelease then text = text .. " pre" end
    Kit.text("small", text, ix, ry + math.floor(8 * m.s),
      rel.version == v.current and PAL.yellow or PAL.heading)
    local preview = ModUpdate.previewLine(rel.body or "", 90)
    if preview ~= "" then
      Kit.text("micro", Kit.ellipsize("micro", preview,
        inner - math.floor(180 * m.s)),
        ix + Kit.textWidth("small", text) + math.floor(10 * m.s),
        ry + math.floor(8 * m.s), PAL.muted)
    end
    local ly = ry + math.floor(8 * m.s) + Kit.textHeight("small")
      + math.floor(4 * m.s)
    local place = Layout.rightCluster(ix, inner, math.floor(6 * m.s))
    if rel.version ~= v.current then
      local iw5 = Kit.textWidth("small", Strings("Install")) + math.floor(20 * m.s)
      btn(imp, place(iw5), ly, iw5, chipH, "ver-inst-" .. i, Strings("Install"), {
        kind = "accent", font = "small",
        action = function() imp:_installModVersion(v.id, rel) end })
    end
    if type(rel.body) == "string" and rel.body:match("%S") then
      local rw = Kit.textWidth("small", Strings("Read more")) + math.floor(20 * m.s)
      btn(imp, place(rw), ly, rw, chipH, "ver-notes-" .. i, Strings("Read more"), {
        kind = "accent", font = "small",
        action = function()
          imp._modReleaseNotes = { version = rel.version, body = rel.body or "" }
        end })
    end
  end
  cy = cy + listH + math.floor(8 * m.s)
  setPage(imp, "versions",
    Kit.pager(px + pad, cy, pw - 2 * pad, cur, n, perPage, "versions"))
  cy = cy + pagerH + math.floor(10 * m.s)
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "versions-close",
    Strings("Close"), { font = "small",
      action = function() imp._modVersions = nil end })
end

-- Modal for per-profile actions (Duplicate, Rename, Delete) for compact / mobile / RG device compatibility
local function buildSingleProfileActionsModal(imp, m)
  local pName = imp._singleProfileActions and imp._singleProfileActions.name
  if not pName then imp._singleProfileActions = nil return end

  local LauncherMods = require("src.mods.LauncherMods")
  local SaveData = require("src.core.SaveData")
  local options = SaveData.loadOptions()
  local profiles, active = LauncherMods.getProfiles(options)

  local pad = math.floor(18 * m.s)
  local w = math.min(math.floor(380 * m.s), m.w - 2 * m.pad)
  local gap = math.floor(8 * m.s)
  local canDelete = (#profiles > 1)
  local armed = deleteArmed(imp, "profile", pName, nil)

  local btns = {
    {
      label = Strings("Duplicate profile"),
      kind = "accent",
      action = function()
        LauncherMods.duplicateProfile(pName, options)
        imp._singleProfileActions = nil
      end
    },
    {
      label = Strings("Rename profile"),
      font = "small",
      action = function()
        imp._singleProfileActions = nil
        imp._profileRenamePrompt = { oldName = pName, text = pName }
        imp:_armTextInput(pName)
      end
    },
  }
  if canDelete then
    btns[#btns + 1] = {
      label = DELETE_LABEL(armed),
      kind = armed and "warn" or "danger",
      keepArm = true,
      action = function()
        imp:pressDelete("profile", pName, nil, function()
          LauncherMods.deleteProfile(pName, options)
          imp._singleProfileActions = nil
        end)
      end
    }
  end

  local h = pad + Kit.textHeight("button") + math.floor(12 * m.s)
    + #btns * (m.btnH + gap) + m.btnH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad

  Kit.text("button", Kit.ellipsize("button", pName, pw - 2 * pad), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(12 * m.s)

  for i, b in ipairs(btns) do
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "profact-" .. i, b.label, {
      kind = b.kind,
      font = "small",
      keepArm = b.keepArm,
      action = function()
        b.action()
        if imp._refreshMods then imp:_refreshMods() end
      end
    })
    cy = cy + m.btnH + gap
  end

  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "profact-close",
    Strings("Close"), {
      font = "small",
      action = function() imp._singleProfileActions = nil end })
end

-- Modal for Mod Profiles (#593) - interactive profile manager (switch, edit, duplicate, delete)
local function buildProfilesModal(imp, m)
  local LauncherMods = require("src.mods.LauncherMods")
  local SaveData = require("src.core.SaveData")
  local options = SaveData.loadOptions()
  local profiles, active = LauncherMods.getProfiles(options)

  local pad = math.floor(18 * m.s)
  local w = math.min(math.floor(460 * m.s), m.w - 2 * m.pad)
  local gap = math.floor(8 * m.s)
  local rowH = math.max(Kit.tapMin(), math.floor(40 * m.s))

  local n = #profiles
  local maxVisible = 4
  local listH = math.min(maxVisible, math.max(1, n)) * (rowH + gap) - gap
  local h = pad + Kit.textHeight("button") + math.floor(12 * m.s)
    + m.btnH + gap + listH + math.floor(12 * m.s) + m.btnH + pad

  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad

  Kit.text("button", Strings("Mod Profiles"), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(12 * m.s)

  -- New Profile button
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "prof-new-top",
    Strings("+ Create New Profile"), {
      kind = "accent", font = "small",
      action = function()
        imp._profileSavePrompt = { text = "PROFILE " .. tostring(#profiles + 1) }
        imp:_armTextInput(imp._profileSavePrompt.text)
      end,
    })
  cy = cy + m.btnH + gap

  -- Scrollable Profile Rows
  local scrollMax = math.max(0, n * (rowH + gap) - gap - listH)
  local scroll = clamp(imp._profScrollOffset or 0, 0, scrollMax)
  if scrollMax > 0 and (Kit.wheelY or 0) ~= 0 and Kit.hit(px + pad, cy, pw - 2 * pad, listH) then
    scroll = clamp(scroll - Kit.wheelY * math.floor(36 * m.s), 0, scrollMax)
    Kit.wheelY = 0
  end
  imp._profScrollOffset = scroll

  Kit.pushClip(px + pad, cy, pw - 2 * pad, listH)
  for i, p in ipairs(profiles) do
    local ry = cy + (i - 1) * (rowH + gap) - scroll
    if ry + rowH >= cy and ry <= cy + listH then
      local isCur = (p.name == active)
      local rowKey = "prof-row-" .. i
      Kit.card(px + pad, ry, pw - 2 * pad, rowH, isCur)

      local rx = px + pad + math.floor(12 * m.s)
      local editBtnW = math.floor(64 * m.s)
      local swBtnW = isCur and 0 or math.floor(64 * m.s)
      local rightClusterW = editBtnW + swBtnW + (isCur and 0 or math.floor(4 * m.s))
      local nameW = math.max(math.floor(80 * m.s), pw - 2 * pad - 2 * math.floor(12 * m.s) - rightClusterW - math.floor(50 * m.s))
      local nameText = Kit.ellipsize("small", p.name, nameW)
      Kit.text("small", nameText, rx, ry + (rowH - Kit.textHeight("small")) / 2, isCur and PAL.heading or PAL.muted)

      if isCur then
        Kit.tag(rx + Kit.textWidth("small", nameText) + math.floor(6 * m.s),
          ry + (rowH - Kit.textHeight("micro")) / 2,
          Kit.textWidth("micro", Strings("Active")) + math.floor(8 * m.s),
          Kit.textHeight("micro"), Strings("Active"), PAL.green)
      end

      -- Right side controls: [Switch] (if not active) + [Edit]
      local place = Layout.rightCluster(px + pad, pw - 2 * pad, math.floor(4 * m.s))

      -- Edit button (opens per-profile action sheet)
      btn(imp, place(editBtnW), ry + math.floor(4 * m.s), editBtnW, rowH - math.floor(8 * m.s), "prof-ed-" .. i,
        Strings("Edit"), {
          font = "micro",
          action = function()
            imp._singleProfileActions = { name = p.name }
          end,
        })

      -- Switch button (if not active)
      if not isCur then
        btn(imp, place(swBtnW), ry + math.floor(4 * m.s), swBtnW, rowH - math.floor(8 * m.s), "prof-sw-" .. i,
          Strings("Switch"), {
            kind = "good", font = "micro",
            action = function()
              LauncherMods.applyProfile(p.name, options)
              if imp._refreshMods then imp:_refreshMods() end
            end,
          })
      end
    end
  end
  Kit.popClip()

  cy = cy + listH + math.floor(12 * m.s)

  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "prof-close",
    Strings("Close"), {
      font = "small",
      action = function() imp._profilesPopup = nil end })
end

-- Modal for MODS tab header actions on mobile / compact displays
local function buildModHeaderActionsModal(imp, m)
  local pad = math.floor(18 * m.s)
  local w = math.floor(380 * m.s)
  local gap = math.floor(8 * m.s)
  local btns = {
    { label = Strings("Mod profiles..."), action = function() imp._profilesPopup = true end },
    { label = Strings("Check for updates"), action = function() imp:_syncModUpdateInfo(true) end },
    { label = Strings("Enable all mods"), kind = "good", action = function() imp:_setAllMods(true) end },
    { label = Strings("Disable all mods"), kind = "warn", action = function() imp:_setAllMods(false) end },
    { label = Strings("Sort mods..."), action = function() imp._sortPopup = "mods" end },
  }
  local h = pad + Kit.textHeight("button") + math.floor(12 * m.s)
    + #btns * (m.btnH + gap) + m.btnH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Strings("More Mod Actions"), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(12 * m.s)

  for i, b in ipairs(btns) do
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "modheadact-" .. i, b.label, {
      kind = b.kind or "ghost", font = "small",
      action = function()
        imp._modHeaderActionsPopup = nil
        b.action()
      end
    })
    cy = cy + m.btnH + gap
  end

  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "modheadact-close",
    Strings("Close"), { font = "small",
      action = function() imp._modHeaderActionsPopup = nil end })
end

-- Sort chooser, shared by the MODS and FIND MODS tabs (they share the
-- persisted key, so one popup serves both).
local function buildSortModal(imp, m)
  local scope = imp._sortPopup
  local defs = sortDefs(scope)
  local pad = math.floor(18 * m.s)
  local w = math.floor(360 * m.s)
  local gap = math.floor(8 * m.s)
  local h = pad + Kit.textHeight("button") + math.floor(12 * m.s)
    + #defs * (m.btnH + gap) + m.btnH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Strings("Sort by"), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(12 * m.s)
  local cur = currentSort(imp, scope)
  for _, s in ipairs(defs) do
    local key = s.key
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "sortpop-" .. key, s.label, {
      kind = (cur == key) and "primary" or "ghost", font = "small",
      action = function()
        imp.modSort = key
        imp._sortPopup = nil
        pcall(function()
          local SaveData = require("src.core.SaveData")
          local opts = SaveData.loadOptions()
          opts.modSort = key
          SaveData.saveOptions(opts)
        end)
      end })
    cy = cy + m.btnH + gap
  end
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "sortpop-close",
    Strings("Close"), { font = "small",
      action = function() imp._sortPopup = nil end })
end

-- Game-scope chooser used when the Show-for chips cannot all fit on the
-- mods toolbar (portrait phones).  Same options as the chip row.
local function buildModScopeModal(imp, m)
  local options = modScopeOptions(imp)
  local pad = math.floor(18 * m.s)
  local w = math.floor(360 * m.s)
  local gap = math.floor(8 * m.s)
  local h = pad + Kit.textHeight("button") + math.floor(12 * m.s)
    + #options * (m.btnH + gap) + m.btnH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Strings("Show for"), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(12 * m.s)
  for _, opt in ipairs(options) do
    local key = tostring(opt.id or "all")
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "scopepop-" .. key, opt.label, {
      kind = (imp.modScope == opt.id) and "primary" or "ghost", font = "small",
      action = function()
        imp:_setModScope(opt.id)
        imp._modScopePopup = nil
      end })
    cy = cy + m.btnH + gap
  end
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "scopepop-close",
    Strings("Close"), { font = "small",
      action = function() imp._modScopePopup = nil end })
end

-- The cartridge dropdown's list.  Replaces the four R/B/Y/G tabs, so it is
-- also what a controller reaches after the tab row.
local function buildGameModal(imp, m)
  local pad = math.floor(18 * m.s)
  local gap = math.floor(8 * m.s)
  local w = math.floor(360 * m.s)
  local h = pad + Kit.textHeight("button") + math.floor(12 * m.s)
    + #GAME_TABS * (m.btnH + gap) + m.btnH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Strings("Choose game"), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(12 * m.s)
  local chrome = headerChrome(imp)
  for _, g in ipairs(GAME_TABS) do
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "gamepop-" .. g.id,
      Strings(g.label), {
        face = "tab", font = "small", letter = g.letter, color = g.color,
        active = imp.tab == g.id,
        action = chrome.tab[g.id] })
    cy = cy + m.btnH + gap
  end
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "gamepop-close",
    Strings("Close"), { font = "small",
      action = function() imp._gamePopup = nil end })
end

-- Category filter for FIND MODS.  Two columns, because an index can list
-- enough categories to overflow a single stacked column on a short window.
local function buildFilterModal(imp, m)
  local cats = (imp.findIndex and imp.findIndex.categories) or {}
  local items = { { key = nil, label = Strings("All") } }
  for _, c in ipairs(cats) do items[#items + 1] = { key = c, label = c } end
  local pad = math.floor(18 * m.s)
  local w = math.floor(440 * m.s)
  local gap = math.floor(8 * m.s)
  local nrows = math.ceil(#items / 2)
  local h = pad + Kit.textHeight("button") + math.floor(12 * m.s)
    + nrows * (m.btnH + gap) + m.btnH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Strings("Filter by category"), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(12 * m.s)
  local colW = math.floor((pw - 2 * pad - gap) / 2)
  for i, it in ipairs(items) do
    local bx = px + pad + ((i - 1) % 2) * (colW + gap)
    local by = cy + math.floor((i - 1) / 2) * (m.btnH + gap)
    local key = it.key
    btn(imp, bx, by, colW, m.btnH, "filterpop-" .. (key or "all"), it.label, {
      kind = (imp.findCategory == key) and "primary" or "ghost",
      font = "small",
      action = function()
        imp.findCategory = key
        setPage(imp, "find", 1)
        imp._filterPopup = nil
      end })
  end
  cy = cy + nrows * (m.btnH + gap)
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "filterpop-close",
    Strings("Close"), { font = "small",
      action = function() imp._filterPopup = nil end })
end

-- Index manager: every source with its Remove, plus Add and Refresh all.
-- This replaces both the old always-visible source rows above the search
-- field and the lone "Add index" header button.
local function buildIndexesModal(imp, m)
  local sources = imp.findSources or {}
  local pad = math.floor(18 * m.s)
  local w = math.floor(520 * m.s)
  local gap = math.floor(6 * m.s)
  local rowH = math.max(Kit.tapMin(), math.floor(34 * m.s))
  local listH = (#sources > 0) and #sources * (rowH + gap)
    or (Kit.textHeight("small") + gap)
  local h = pad + Kit.textHeight("button") + math.floor(12 * m.s) + listH
    + math.floor(6 * m.s) + 3 * (m.btnH + math.floor(8 * m.s))
    - math.floor(8 * m.s) + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Strings("Mod indexes"), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(12 * m.s)
  if #sources == 0 then
    Kit.text("small", Strings("No index added yet."), px + pad, cy, PAL.muted)
    cy = cy + Kit.textHeight("small") + gap
  else
    for _, source in ipairs(sources) do
      local feed = source.feed
      local rmW = Kit.textWidth("small", Strings("Remove"))
        + math.floor(20 * m.s)
      Kit.text("small", Kit.ellipsize("small", source.label or feed,
        pw - 2 * pad - rmW - math.floor(12 * m.s)), px + pad,
        cy + (rowH - Kit.textHeight("small")) / 2, PAL.detail)
      btn(imp, px + pw - pad - rmW, cy, rmW, rowH,
        "idx-rm-" .. tostring(feed), Strings("Remove"), {
          kind = "danger", font = "small",
          action = function() imp:_removeIndex(feed) end })
      cy = cy + rowH + gap
    end
  end
  cy = cy + math.floor(6 * m.s)
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "idx-add",
    Strings("Add index"), { kind = "accent", font = "small",
      action = function() imp:_promptAddIndex() end })
  cy = cy + m.btnH + math.floor(8 * m.s)
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "idx-refresh",
    Strings("Refresh all"), {
      kind = "accent", font = "small", enabled = #sources > 0,
      action = function()
        imp._findSearchFocus = false
        imp:_disarmTextInput()
        imp:_refreshFind(true)
      end })
  cy = cy + m.btnH + math.floor(8 * m.s)
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "idx-close",
    Strings("Close"), { font = "small",
      action = function() imp._indexManage = nil end })
end

-- Per-mod actions for the MODS tab: the row itself only carries the enable
-- toggle, everything episodic (update check, versions, delete) lives here.
local function buildModActionsModal(imp, m)
  local mod
  for _, mm in ipairs(imp.mods or {}) do
    if mm.id == imp._modActions then mod = mm break end
  end
  if not mod then imp._modActions = nil return end
  local hasGit = mod.github and mod.github ~= ""
  local depSpecs = mod.dependencySpecs or (mod.manifest and mod.manifest.dependencySpecs)
  local hasDeps = depSpecs and #depSpecs > 0
  local imports = mod.imports or mod.requiredImports
  local hasImports = imports and #imports > 0
  local info = hasGit and imp:_modUpdateInfo(mod.id)
  local pad = math.floor(18 * m.s)
  local w = math.floor(440 * m.s)
  local gap = math.floor(8 * m.s)
  local nBtns = (hasGit and 2 or 0) + (hasDeps and 1 or 0)
    + (hasImports and 1 or 0) + 2
  local h = pad + Kit.textHeight("button") + math.floor(4 * m.s)
    + Kit.textHeight("small") + math.floor(12 * m.s)
    + nBtns * (m.btnH + gap) - gap + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Kit.ellipsize("button", mod.name, pw - 2 * pad),
    px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(4 * m.s)
  local statusText, statusCol = modStatusColor(mod.status)
  local line = "v" .. tostring(mod.version or "?") .. "   " .. statusText
  if info and info.status == "available" then
    line = line .. "   " .. Strings("v%s available", tostring(info.latest))
  elseif info and info.status == "current" then
    line = line .. "   " .. Strings("up to date")
  end
  Kit.text("small", Kit.ellipsize("small", line, pw - 2 * pad),
    px + pad, cy, statusCol)
  cy = cy + Kit.textHeight("small") + math.floor(12 * m.s)
  local id = mod.id
  if hasGit then
    local updLabel, updKind = Strings("Check for updates"), "ghost"
    if info and info.status == "available" then
      updLabel, updKind = Strings("Update"), "warn"
    elseif info and info.status == "current" then
      updLabel = Strings("Check again")
    end
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "modact-upd", updLabel, {
      kind = updKind, font = "small",
      action = function() imp:_modGithubAction(id, "update") end })
    cy = cy + m.btnH + gap
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "modact-ver",
      Strings("Versions"), { kind = "accent", font = "small",
        action = function() imp:_modGithubAction(id, "versions") end })
    cy = cy + m.btnH + gap
  end
  if hasDeps then
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "modact-deps",
      Strings("Check dependencies"), {
        kind = "accent", font = "small",
        action = function()
          local LauncherMods = require("src.mods.LauncherMods")
          local depCheck = LauncherMods.checkDependencies(mod.manifest or mod)
          if depCheck then
            imp._modDepResolver = depCheck
          end
          imp._modActions = nil
        end })
    cy = cy + m.btnH + gap
  end
  if hasImports then
    local missing = tonumber(mod.missingRequiredImports) or 0
    local label = missing > 0
      and Strings("Imported files (%d required)", missing)
      or Strings("Imported files")
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "modact-imports",
      label, { kind = missing > 0 and "warn" or "accent", font = "small",
        action = function()
          imp._modImports = id
          imp._modActions = nil
        end })
    cy = cy + m.btnH + gap
  end
  local armed = deleteArmed(imp, "mod", id, nil)
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "modact-del",
    DELETE_LABEL(armed), {
      kind = "danger", font = "small", keepArm = true,
      action = function()
        imp:pressDelete("mod", id, nil, function()
          imp:_deleteMod(id)
          imp._modActions = nil
        end)
      end })
  cy = cy + m.btnH + gap
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "modact-close",
    Strings("Close"), { font = "small",
      action = function() imp._modActions = nil end })
end

-- Imported files declared by one installed mod.  The engine picks, validates,
-- canonicalizes and copies; this surface never exposes a host path to mod code.
local function buildRequiredImportsModal(imp, m)
  local mod
  for _, candidate in ipairs(imp.mods or {}) do
    if candidate.id == imp._modImports then mod = candidate break end
  end
  if not mod then imp._modImports = nil return end
  local imports = mod.imports or mod.requiredImports or {}
  local pad, gap = math.floor(18 * m.s), math.floor(8 * m.s)
  local w = math.floor(540 * m.s)
  local notice = imp.requiredImportNotice
  if not notice or notice.modId ~= mod.id then notice = nil end
  local noticeText
  if notice then
    local importName = notice.importId
    for _, row in ipairs(imports) do
      if row.id == notice.importId then importName = row.name break end
    end
    noticeText = Strings("%s rejected: %s", importName, notice.text)
  end
  local noticeW = w - 2 * pad
  local noticeH = noticeText and Kit.wrapHeight("small", noticeText, noticeW, 2) or 0
  local rowH = math.max(math.floor(70 * m.s), m.btnH)
  local perPage = math.min(4, math.max(1, #imports))
  local pagerH = #imports > perPage and math.max(Kit.tapMin(), math.floor(30 * m.s)) or 0
  local h = pad + Kit.textHeight("button") + math.floor(4 * m.s)
    + Kit.textHeight("small") + math.floor(12 * m.s)
    + noticeH + (noticeH > 0 and gap or 0)
    + perPage * rowH + math.max(0, perPage - 1) * gap
    + (pagerH > 0 and (gap + pagerH) or 0) + gap + m.btnH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Kit.ellipsize("button", mod.name, pw - 2 * pad),
    px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(4 * m.s)
  Kit.text("small", Strings("User-supplied files are validated by MD5 and copied into this mod only."),
    px + pad, cy, PAL.muted)
  cy = cy + Kit.textHeight("small") + math.floor(12 * m.s)
  if noticeText then
    cy = cy + Kit.textWrapped("small", noticeText, px + pad, cy,
      pw - 2 * pad, PAL.red, 2) + gap
  end

  local pageKey = "required-imports-" .. mod.id
  local cur = page(imp, pageKey)
  local first, last, bounded = Kit.pageBounds(cur, #imports, perPage)
  setPage(imp, pageKey, bounded)
  for i = first, last do
    local row = imports[i]
    local importId = row.id
    Kit.card(px + pad, cy, pw - 2 * pad, rowH, row.present and "muted" or false)
    local innerX = px + pad + math.floor(12 * m.s)
    local actionW = math.floor(108 * m.s)
    local removeW = row.present and math.floor(86 * m.s) or 0
    local actionX = px + pw - pad - math.floor(10 * m.s) - actionW
    if removeW > 0 then actionX = actionX - removeW - math.floor(6 * m.s) end
    local textW = actionX - innerX - math.floor(8 * m.s)
    Kit.text("small", Kit.ellipsize("small", row.name, textW), innerX,
      cy + math.floor(8 * m.s), PAL.heading)
    local stateY = cy + math.floor(8 * m.s) + Kit.textHeight("small")
      + math.floor(3 * m.s)
    if row.description and row.description ~= "" then
      Kit.text("micro", Kit.ellipsize("micro", row.description, textW),
        innerX, stateY, PAL.muted)
      stateY = stateY + Kit.textHeight("micro") + math.floor(2 * m.s)
    end
    local state = row.present and Strings("Ready - %s", row.file)
      or (row.error and Strings("Invalid file - choose again")
        or (row.required and Strings("Required - %s", row.file)
          or Strings("Optional - %s", row.file)))
    Kit.text("micro", Kit.ellipsize("micro", state, textW), innerX, stateY,
      row.present and PAL.green or (row.required and PAL.yellow or PAL.muted))
    btn(imp, actionX, cy + (rowH - m.btnH) / 2, actionW, m.btnH,
      "req-pick-" .. mod.id .. "-" .. importId,
      row.present and Strings("Replace") or Strings("Choose file"), {
        kind = row.present and "ghost" or "accent", font = "small",
        action = function() imp:chooseRequiredImport(mod.id, importId) end })
    if row.present then
      local deleteId = mod.id .. ":" .. importId
      local armed = deleteArmed(imp, "required-import", deleteId, nil)
      btn(imp, actionX + actionW + math.floor(6 * m.s),
        cy + (rowH - m.btnH) / 2, removeW, m.btnH,
        "req-remove-" .. mod.id .. "-" .. row.id, DELETE_LABEL(armed), {
          kind = "danger", font = "small", keepArm = true,
          action = function()
            imp:pressDelete("required-import", deleteId, nil, function()
              imp:_removeRequiredImport(mod.id, importId)
            end)
          end })
    end
    cy = cy + rowH + gap
  end
  if pagerH > 0 then
    local newPage = Kit.pager(px + pad, cy, pw - 2 * pad, bounded,
      #imports, perPage, pageKey)
    setPage(imp, pageKey, newPage)
    cy = cy + pagerH + gap
  end
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "req-close", Strings("Close"), {
    font = "small", action = function() imp._modImports = nil end })
end

-- Per-mod popup for FIND MODS: the row is a plain click, and Install /
-- Details / Source live here instead of crowding every row.
local function buildFindEntryModal(imp, m)
  local ModIndex = require("src.mods.ModIndex")
  local ModUpdate = require("src.mods.ModUpdate")
  local entry = imp._findEntry
  local installed = imp:_findInstalledMap()
  local action, note = findActionFor(entry, installed[entry.id])
  local pad = math.floor(18 * m.s)
  local w = math.floor(460 * m.s)
  local gap = math.floor(8 * m.s)
  local nBtns = 3  -- install row, details/source row, close row
  local noteH = note and (Kit.textHeight("small") + math.floor(4 * m.s)) or 0
  local stats = imp:_findStats(entry)
  local trend = {}
  local trendLine = stats and ModUpdate.trendingLine(stats.recent, stats.windowDays)
  if trendLine then trend[#trend + 1] = trendLine end
  if stats and stats.asOf then
    trend[#trend + 1] = Strings("counts approximate, as of %s",
      tostring(stats.asOf):match("^%d%d%d%d%-%d%d%-%d%d") or stats.asOf)
  end
  trend = (#trend > 0) and table.concat(trend, "  -  ") or nil
  local trendH = trend and (Kit.textHeight("small") + math.floor(2 * m.s)) or 0
  local h = pad + Kit.textHeight("button") + math.floor(4 * m.s)
    + Kit.textHeight("small") + trendH + noteH + math.floor(12 * m.s)
    + nBtns * (m.btnH + gap) - gap + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Kit.ellipsize("button", entry.title or entry.id,
    pw - 2 * pad), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(4 * m.s)
  local lead = "v" .. tostring(ModIndex.displayVersion(entry))
  if entry.author then lead = lead .. "  -  " .. entry.author end
  if entry.categories and entry.categories[1] then
    lead = lead .. "  -  " .. entry.categories[1]
  end
  local dl = stats and ModUpdate.downloadsShort(stats.total) or nil
  local hasCount = stats ~= nil and stats.total ~= nil
  local segs = { { lead, PAL.detail } }
  if dl then
    segs[#segs + 1] = { "  -  " .. dl, hasCount and PAL.green or PAL.faint }
  end
  segLine("small", segs, px + pad, cy, pw - 2 * pad)
  cy = cy + Kit.textHeight("small")
  if trend then
    cy = cy + math.floor(2 * m.s)
    Kit.text("small", Kit.ellipsize("small", trend, pw - 2 * pad),
      px + pad, cy, PAL.muted)
    cy = cy + Kit.textHeight("small")
  end
  if note then
    cy = cy + math.floor(4 * m.s)
    Kit.text("small", note, px + pad, cy, PAL.green)
    cy = cy + Kit.textHeight("small")
  end
  cy = cy + math.floor(12 * m.s)
  if action then
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "findpop-inst", action, {
      kind = "primary", font = "small",
      action = function()
        imp._findEntry = nil
        imp:_findConfirmInstall(entry)
      end })
  else
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "findpop-inst",
      Strings("Not installable from this index"),
      { font = "small", enabled = false })
  end
  cy = cy + m.btnH + gap
  local half = entry.repo and math.floor((pw - 2 * pad - gap) / 2)
    or (pw - 2 * pad)
  btn(imp, px + pad, cy, half, m.btnH, "findpop-det", Strings("Details"), {
    kind = "accent", font = "small",
    action = function() imp:_findShowDetails(entry) end })
  if entry.repo then
    local repo = entry.repo
    btn(imp, px + pad + half + gap, cy, half, m.btnH, "findpop-src",
      Strings("Source"), { kind = "accent", font = "small",
        action = function() love.system.openURL(repo) end })
  end
  cy = cy + m.btnH + gap
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "findpop-close",
    Strings("Close"), { font = "small",
      action = function() imp._findEntry = nil end })
end

-- Per-game file management, behind the manage button beside Play.  A ready
-- game's panel is Play and its saves; everything episodic about the FILES --
-- swapping the ROM out, finding them on disk -- lives here instead of taking
-- two permanent buttons out of a column that has to fit on a phone.
local function buildGameManageModal(imp, m)
  local version = imp._gameManage
  local info = GameVersion.info(version)
  local ready = imp.ready[version] or false
  local mdl = romModel(imp, version, info, ready, info == nil)
  local gameName = info and (info.launcherName or info.displayName)
    or tostring(version)
  local saveDir = love.filesystem.getSaveDirectory
    and love.filesystem.getSaveDirectory() or nil
  -- The folder link is desktop-only: Android and NX have no browsable path to
  -- open, and both already print their own transfer hint on the slot card.
  local canOpenFolder = saveDir and not imp.android and not imp.isNX

  local pad = math.floor(18 * m.s)
  local w = math.floor(460 * m.s)
  local gap = math.floor(8 * m.s)
  local bodyW = w - 2 * pad
  local detailH = Kit.wrapHeight("small",
    mdl.detail or Strings("The ROM for this game is imported and verified."),
    bodyW, 3)
  local pathH = saveDir
    and (Kit.textHeight("micro") + math.floor(8 * m.s)) or 0
  local nBtns = 1 + (canOpenFolder and 1 or 0) + 1
  local h = pad + Kit.textHeight("button") + math.floor(8 * m.s) + detailH
    + math.floor(12 * m.s) + pathH + nBtns * (m.btnH + gap) - gap + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad

  Kit.text("button", Kit.ellipsize("button",
    Strings("Manage ") .. gameName, pw - 2 * pad), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(8 * m.s)
  cy = cy + Kit.textWrapped("small",
    mdl.detail or Strings("The ROM for this game is imported and verified."),
    px + pad, cy, pw - 2 * pad, mdl.state and PAL.detail or PAL.green, 3)
  cy = cy + math.floor(12 * m.s)
  if saveDir then
    -- Truncated from the LEFT: the tail of a save path is the part that
    -- identifies it.
    Kit.text("micro", Kit.ellipsizeLeft("micro", saveDir, pw - 2 * pad),
      px + pad, cy, PAL.faint)
    cy = cy + Kit.textHeight("micro") + math.floor(8 * m.s)
  end

  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "manage-rom",
    mdl.label or Strings("Re-import ROM"), {
      kind = "accent", font = "small", enabled = mdl.enabled ~= false,
      action = (mdl.enabled ~= false) and function()
        imp._gameManage = nil
        local fn = romAction(imp, version, mdl)
        if fn then fn() end
      end or nil })
  cy = cy + m.btnH + gap
  if canOpenFolder then
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "manage-folder",
      Strings("Open folder"), { kind = "accent", font = "small",
        action = function() love.system.openURL(imp:fileUrl(saveDir)) end })
    cy = cy + m.btnH + gap
  end
  btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "manage-close",
    Strings("Close"), { font = "small",
      action = function() imp._gameManage = nil end })
end

local function buildSettingsModal(imp, m)
  local model = imp._settings
  local pad = math.floor(18 * m.s)
  local w = math.floor(640 * m.s)
  local h = math.floor(math.min(m.H - 2 * m.pad, m.H * 0.9))
  local px, py, pw, ph = modalPanel(m, w, h)
  local cy = py + pad

  Kit.text("stat", Strings("Settings"), px + pad, cy, PAL.heading)
  local cw = Kit.textWidth("small", Strings("Close")) + math.floor(24 * m.s)
  btn(imp, px + pw - pad - cw, cy, cw, m.btnH, "settings-close",
    Strings("Close"), { font = "small",
      action = function() imp:_closeSettings() end })
  cy = cy + math.max(Kit.textHeight("stat"), m.btnH) + math.floor(6 * m.s)
  -- WRAPPED, not printed flat: on a portrait panel this line ran straight off
  -- the right edge and the sentence ended mid-word at the card border.
  cy = cy + Kit.textWrapped("micro", Strings(
    "Saved to your options file; the game applies these on its next start."),
    px + pad, cy, pw - 2 * pad, PAL.muted, 2)
    + math.floor(10 * m.s)

  -- Settings rows are PAGINATED, flattened across sections so a page is a
  -- uniform run of rows.  Section titles ride along as their own entry.
  local flat = imp._settingsFlat
  if not flat or flat.model ~= model then
    flat = { model = model }
    for _, section in ipairs(model.sections) do
      flat[#flat + 1] = { header = section.title }
      for _, row in ipairs(section.rows) do
        flat[#flat + 1] = { row = row }
      end
    end
    imp._settingsFlat = flat
  end
  -- The widest label in the whole model decides the row shape (below), so it
  -- is measured once per model rather than per row per frame.  Measuring the
  -- WIDEST rather than each row keeps every row the same height, which is
  -- what lets the list paginate off a uniform row.
  if not flat.labelW or flat.labelFont ~= Kit.fonts.scale then
    local widest = 0
    for _, item in ipairs(flat) do
      if item.row then
        widest = math.max(widest, Kit.textWidth("small", item.row.label))
      end
    end
    flat.labelW, flat.labelFont = widest, Kit.fonts.scale
  end

  local stepW = math.floor(34 * m.s)
  local valW = math.floor(140 * m.s)
  local inner = pw - 2 * pad - math.floor(24 * m.s)
  -- STACKED ROWS.  Side by side, a row spends most of its width on the value
  -- ladder and leaves the label whatever remains -- on a portrait phone that
  -- was three characters and an ellipsis ("TEX...", "BAT...", "BAT..."), so
  -- the panel listed a dozen settings none of which could be identified.
  -- When the widest label does not fit beside its control, every row puts the
  -- label on its own line ABOVE the control instead.  All-or-nothing, because
  -- a list that switches shape row by row is harder to scan than either form.
  local stacked = flat.labelW
    > (inner - 2 * stepW - valW - math.floor(24 * m.s))
  local rowH
  if stacked then
    rowH = Kit.textHeight("small") + math.floor(4 * m.s) + m.btnH
      + math.floor(10 * m.s)
  else
    rowH = math.max(Kit.tapMin(), math.floor(36 * m.s))
  end
  local gap = math.floor(4 * m.s)
  local pagerH = math.max(Kit.tapMin(), math.floor(30 * m.s))
  local listH = (py + ph - pad) - cy - pagerH - math.floor(8 * m.s)
  local perPage = Kit.rowsThatFit(listH, rowH, gap, 1, 24)
  local n = #flat
  -- POKEPORT_LAUNCHER_SETTINGS_PAGE jumps straight to a page, so a shot can
  -- capture a row that is not on page one.
  local wanted = tonumber(os.getenv("POKEPORT_LAUNCHER_SETTINGS_PAGE") or "")
  if wanted and not imp._settingsPaged then
    imp._settingsPaged = true
    setPage(imp, "settings", wanted)
  end
  local first, last, cur = Kit.pageBounds(page(imp, "settings"), n, perPage)
  setPage(imp, "settings", cur)
  setPage(imp, "settings", Kit.wheelPage(px, cy, pw, listH, cur, n, perPage))

  for i = first, last do
    local item = flat[i]
    local ry = cy + (i - first) * (rowH + gap)
    if item.header then
      Kit.caption(px + pad, ry + (rowH - Kit.textHeight("caption")) / 2,
        item.header)
    else
      local row = item.row
      local key = "set-" .. i
      Kit.card(px + pad, ry, pw - 2 * pad, rowH, "hairline")
      local ix = px + pad + math.floor(12 * m.s)
      -- Where the label prints, and where the control band starts.  Stacked:
      -- label on its own full-width line, controls on the line below it.
      -- Inline: both centred on one line, label left, controls right.
      local labelY, ctlY, labelW
      if stacked then
        labelY = ry + math.floor(6 * m.s)
        ctlY = labelY + Kit.textHeight("small") + math.floor(4 * m.s)
        labelW = inner
      else
        labelY = ry + (rowH - Kit.textHeight("small")) / 2
        ctlY = ry + (rowH - m.btnH) / 2
        labelW = nil   -- per-shape below: what the controls leave over
      end
      local rx = ix + inner

      if row.editText then
        local ew = Kit.textWidth("small", Strings("Edit")) + math.floor(20 * m.s)
        local vw = math.floor(160 * m.s)
        Kit.text("small", Kit.ellipsize("small", row.label,
          labelW or (inner - ew - vw - math.floor(20 * m.s))),
          ix, labelY, PAL.text)
        Kit.textRight("small", Kit.ellipsize("small", tostring(row.value()), vw),
          rx - ew - math.floor(10 * m.s),
          ctlY + (m.btnH - Kit.textHeight("small")) / 2, PAL.detail)
        btn(imp, rx - ew, ctlY, ew, m.btnH,
          key .. "-edit", Strings("Edit"), { kind = "accent", font = "small",
            action = function()
              imp._settingsText = { row = row, text = tostring(row.value() or ""),
                maxLen = row.editText.maxLen }
              imp:_armTextInput()
            end })
      elseif row.action then
        -- A plain action row (Reset rebinds, Touch controls): the whole right
        -- side is one button rather than a value ladder.
        local aw = Kit.textWidth("small", row.actionLabel or Strings("Run"))
          + math.floor(24 * m.s)
        Kit.text("small", Kit.ellipsize("small", row.label,
          labelW or (inner - aw - math.floor(12 * m.s))), ix, labelY, PAL.text)
        btn(imp, rx - aw, ctlY, aw, m.btnH,
          key .. "-act", row.actionLabel or Strings("Run"), {
            kind = row.danger and "danger" or "ghost", font = "small",
            action = function()
              if row.action() ~= false then model.save() end
            end })
      else
        Kit.text("small", Kit.ellipsize("small", row.label,
          labelW or (inner - 2 * stepW - valW - math.floor(24 * m.s))),
          ix, labelY, PAL.text)
        -- Stacked rows give the value the whole span between the steppers,
        -- which is where the extra width goes now that the label is not
        -- competing for it.
        local vw = stacked and (inner - 2 * stepW - math.floor(16 * m.s))
          or valW
        btn(imp, rx - stepW, ctlY, stepW, m.btnH,
          key .. "-next", ">", { font = "small",
            action = function() if row.step and row.step(1) then model.save() end end })
        Kit.textCenter("small", Kit.ellipsize("small", tostring(row.value()), vw),
          rx - stepW - vw, ctlY + (m.btnH - Kit.textHeight("small")) / 2, vw,
          PAL.heading)
        btn(imp, rx - stepW - vw - stepW, ctlY, stepW,
          m.btnH, key .. "-prev", "<", { font = "small",
            action = function() if row.step and row.step(-1) then model.save() end end })
      end
    end
  end
  cy = cy + listH + math.floor(8 * m.s)
  setPage(imp, "settings",
    Kit.pager(px + pad, cy, pw - 2 * pad, cur, n, perPage, "settings"))
end

local function buildDepResolverModal(imp, m)
  local res = imp._modDepResolver
  if not res then return end

  local pad = math.floor(18 * m.s)
  local w = math.floor(540 * m.s)
  local chipH = math.max(Kit.tapMin(), math.floor(28 * m.s))
  local rowH = math.floor(74 * m.s)
  local gap = math.floor(8 * m.s)
  local warnH = math.floor(38 * m.s)

  local n = #(res.deps or {})
  local anyUnsatisfied = false
  for _, d in ipairs(res.deps or {}) do
    if d.status ~= "satisfied" and d.status ~= "disabled" then anyUnsatisfied = true; break end
  end

  local totalContentH = n > 0 and (n * rowH + (n - 1) * gap) or 0

  -- Calculate content height dynamically so modal auto-fits small lists snuggly
  local headerH = Kit.textHeight("button") + math.floor(4 * m.s)
    + Kit.textHeight("small") + math.floor(10 * m.s)
  local warnTotalH = warnH + math.floor(12 * m.s)
  local listMaxH = math.floor(240 * m.s)
  local itemsH = math.min(totalContentH > 0 and totalContentH or rowH, listMaxH)
  local footerH = math.floor(10 * m.s) + m.btnH
  local wantedH = pad + headerH + warnTotalH + itemsH + footerH + pad
  local h = math.floor(math.min(m.H - 2 * m.pad, math.max(260 * m.s, wantedH)))

  local px, py, pw, ph = modalPanel(m, w, h)
  local cy = py + pad

  -- Title
  local titleText = Strings("Dependency Resolver: ") .. tostring(res.targetMod.name or res.targetMod.id)
  Kit.text("button", Kit.ellipsize("button", titleText, pw - 2 * pad), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(4 * m.s)

  -- Subtitle / intro
  local subText = Strings("This mod requires additional dependencies or has conflicts:")
  Kit.text("small", subText, px + pad, cy, PAL.muted)
  cy = cy + Kit.textHeight("small") + math.floor(10 * m.s)

  -- Security Disclaimer Banner Callout Card
  Kit.card(px + pad, cy, pw - 2 * pad, warnH, "warn")
  local warnMsg = Strings("Caution: Only pull dependencies from sources you trust.\nVerify source repositories before fetching.")
  Kit.text("micro", warnMsg, px + pad + math.floor(12 * m.s), cy + math.floor(5 * m.s), PAL.yellow)
  cy = cy + warnH + math.floor(12 * m.s)

  -- List area bounds
  local listH = (py + ph - pad) - cy - m.btnH - math.floor(10 * m.s)
  local scrollMax = math.max(0, totalContentH - listH)

  -- Mouse wheel scroll handling matching upstream pattern
  if scrollMax > 0 and (Kit.wheelY or 0) ~= 0 and Kit.hit(px + pad, cy, pw - 2 * pad, listH) then
    imp._depScrollOffset = clamp((imp._depScrollOffset or 0) - Kit.wheelY * math.floor(48 * m.s), 0, scrollMax)
    Kit.wheelY = 0
  elseif scrollMax == 0 then
    imp._depScrollOffset = 0
  else
    imp._depScrollOffset = clamp(imp._depScrollOffset or 0, 0, scrollMax)
  end

  -- Pump active in-flight pulls
  if imp._pumpDepPulls then
    imp:_pumpDepPulls()
  end

  -- Clipped vertical scroll container
  Kit.pushClip(px + pad, cy, pw - 2 * pad, listH)
  local startY = cy - (imp._depScrollOffset or 0)

  for i = 1, n do
    local dep = res.deps[i]
    local ry = startY + (i - 1) * (rowH + gap)

    -- Cull rows completely outside the list viewport rectangle
    if ry + rowH >= cy and ry <= cy + listH then
      -- Item Card Fill & Stroke (matching launcher card interiors & radius)
      local hot = Kit.hover(px + pad, ry, pw - 2 * pad, rowH)
      Kit.card(px + pad, ry, pw - 2 * pad, rowH, hot and "rowHover" or "row")

      local ix = px + pad + math.floor(12 * m.s)
      local innerW = pw - 2 * pad - math.floor(24 * m.s)

      -- Dep title & range
      local depHeader = tostring(dep.name or dep.id)
      if dep.range and dep.range ~= "" then
        depHeader = depHeader .. " (" .. dep.range .. ")"
      end
      Kit.text("small", Kit.ellipsize("small", depHeader, innerW - math.floor(210 * m.s)),
        ix, ry + math.floor(8 * m.s), PAL.heading)

      -- Status Badge & Subtext
      local statusText, statusCol
      if dep.status == "satisfied" then
        statusText = Strings("Installed & Compatible (v%s)", tostring(dep.installedVersion or "?"))
        statusCol = PAL.green
      elseif dep.status == "incompatible" then
        statusText = Strings("Incompatible (installed v%s, needs %s)", tostring(dep.installedVersion or "?"), tostring(dep.range or ""))
        statusCol = PAL.yellow
      elseif dep.status == "conflict" then
        statusText = Strings("Incompatible mod enabled (v%s)", tostring(dep.installedVersion or "?"))
        statusCol = PAL.red
      elseif dep.status == "disabled" then
        statusText = Strings("Disabled (conflict resolved)")
        statusCol = PAL.green
      else
        statusText = Strings("Missing")
        statusCol = PAL.red
      end
      Kit.text("micro", statusText, ix, ry + math.floor(8 * m.s) + Kit.textHeight("small") + math.floor(2 * m.s), statusCol)

      -- Repo source line or Conflict reason
      local repoLine
      if dep.status == "conflict" or dep.kind == "conflict" then
        repoLine = Strings("Listed as incompatible with ") .. tostring(res.targetMod.name or res.targetMod.id)
      elseif dep.github then
        repoLine = Strings("Source: github.com/") .. dep.github
      else
        repoLine = Strings("Source: Unknown (no repo listed)")
      end
      Kit.text("micro", repoLine, ix, ry + math.floor(8 * m.s) + Kit.textHeight("small") + Kit.textHeight("micro") + math.floor(4 * m.s), PAL.muted)

      -- Action buttons right cluster (vertically centered inside card)
      local ly = ry + math.floor((rowH - chipH) / 2)
      local place = Layout.rightCluster(ix, innerW, math.floor(8 * m.s))

      local pState = imp._depPullState and imp._depPullState[dep.id]

      if pState and pState.stage ~= "done" and pState.stage ~= "error" then
        local label = Strings("Pulling...")
        if pState.stage == "fetching" then label = Strings("Fetching...")
        elseif pState.stage == "downloading" then
          if pState.progress and pState.progress > 0 then
            label = Strings("Downloading %d%%", math.floor(pState.progress * 100))
          else
            label = Strings("Downloading...")
          end
        elseif pState.stage == "installing" then label = Strings("Installing...")
        end
        Kit.chip(place(Kit.textWidth("small", label) + math.floor(16 * m.s)), ly,
          Kit.textWidth("small", label) + math.floor(16 * m.s), chipH, label, true, PAL.yellow, "dep-pulling-" .. i)
      elseif dep.status == "conflict" then
        local btnLabel = Strings("Disable mod")
        local bw = Kit.textWidth("small", btnLabel) + math.floor(20 * m.s)
        btn(imp, place(bw), ly, bw, chipH, "dep-dis-" .. i, btnLabel, {
          kind = "warn", font = "small",
          action = function()
            local LauncherMods = require("src.mods.LauncherMods")
            LauncherMods.setEnabled(dep.id, false, imp.modScope)
            dep.status = "disabled"
            if imp._refreshMods then imp:_refreshMods() end
          end,
        })
      elseif dep.status == "disabled" then
        local chipLabel = Strings("Disabled")
        local cw = Kit.textWidth("small", chipLabel) + math.floor(16 * m.s)
        Kit.chip(place(cw), ly, cw, chipH, chipLabel, true, PAL.green, "dep-dischip-" .. i)
      else
        -- Pull / Update button if github repo is known and not satisfied
        if dep.github and dep.status ~= "satisfied" then
          local btnLabel = dep.status == "incompatible" and Strings("Update") or Strings("Pull from GitHub")
          local bw = Kit.textWidth("small", btnLabel) + math.floor(20 * m.s)
          btn(imp, place(bw), ly, bw, chipH, "dep-pull-" .. i, btnLabel, {
            kind = "accent", font = "small",
            action = function()
              if imp._startDepPull then
                imp:_startDepPull(dep)
              end
            end,
          })
        end

        -- Open Source link button if safeUrl is present
        if dep.safeUrl then
          local bw = Kit.textWidth("small", Strings("View Source")) + math.floor(20 * m.s)
          btn(imp, place(bw), ly, bw, chipH, "dep-view-" .. i, Strings("View Source"), {
            font = "small",
            action = function()
              if love and love.system and love.system.openURL then
                love.system.openURL(dep.safeUrl)
              end
            end,
          })
        end
      end
    end
  end
  Kit.popClip()

  -- Scrollbar indicator if scrollMax > 0
  if scrollMax > 0 then
    local barW = math.floor(4 * m.s)
    local barX = px + pw - pad - barW
    local thumbH = math.max(math.floor(20 * m.s), math.floor(listH * (listH / totalContentH)))
    local thumbY = cy + (listH - thumbH) * ((imp._depScrollOffset or 0) / scrollMax)
    Theme.fill(barX, cy, barW, listH, PAL.bg, 0.4)
    Theme.fill(barX, thumbY, barW, thumbH, PAL.muted, 0.7)
  end

  cy = cy + listH + math.floor(10 * m.s)

  -- Bottom Action Buttons
  if anyUnsatisfied then
    local btnW = math.floor((pw - 2 * pad - math.floor(10 * m.s)) / 2)
    btn(imp, px + pad, cy, btnW, m.btnH, "depresolver-pullall", Strings("Pull All Available"), {
      kind = "accent", font = "small",
      action = function()
        for _, dep in ipairs(res.deps or {}) do
          if dep.github and dep.status ~= "satisfied" and dep.status ~= "disabled" and imp._startDepPull then
            imp:_startDepPull(dep)
          end
        end
      end,
    })
    btn(imp, px + pad + btnW + math.floor(10 * m.s), cy, btnW, m.btnH, "depresolver-close", Strings("Done"), {
      font = "small",
      action = function()
        imp._modDepResolver = nil
      end,
    })
  else
    btn(imp, px + pad, cy, pw - 2 * pad, m.btnH, "depresolver-close", Strings("Done"), {
      kind = "accent", font = "small",
      action = function()
        imp._modDepResolver = nil
      end,
    })
  end
end

-- Whether ANY modal will draw this frame.  draw() consults this BEFORE the
-- panels build: immediate mode hit-tests each control as it draws, so the
-- panels underneath a modal must run with Kit.blockClicks already raised or
-- a click on the scrim lands on whatever button happens to be behind it.
-- Keep this list in sync with buildModals below.
local function modalUp(imp)
  return (imp._settingsText or imp._settings or imp._rename
    or imp._indexPrompt or imp._modConfirm or imp._modReleaseNotes
    or imp._appPatchNotes
    or imp._findDetails or imp._modVersions or imp._modDepResolver or imp._sortPopup
    or imp._filterPopup or imp._modScopePopup or imp._indexManage
    or imp._gamePopup
    or imp._modActions or imp._modImports
    or imp._modHeaderActionsPopup or imp._profilesPopup or imp._singleProfileActions or imp._profileSavePrompt
    or imp._profileRenamePrompt or imp._findEntry or imp._gameManage) ~= nil
end

local function buildModals(imp, m)
  if imp._profileRenamePrompt then
    buildPrompt(imp, m, {
      key = "profren", title = Strings("Rename profile"),
      hint = Strings("Enter a new name for this profile:"),
      text = imp._profileRenamePrompt.text or "", okLabel = Strings("Save"),
      commit = function()
        local txt = imp._profileRenamePrompt and imp._profileRenamePrompt.text
        local old = imp._profileRenamePrompt and imp._profileRenamePrompt.oldName
        if txt and txt ~= "" and old then
          local LauncherMods = require("src.mods.LauncherMods")
          LauncherMods.renameProfile(old, txt)
          imp._profileRenamePrompt = nil
          imp:_disarmTextInput()
          if imp._refreshMods then imp:_refreshMods() end
        end
      end,
      cancel = function()
        imp._profileRenamePrompt = nil
        imp:_disarmTextInput()
      end,
      footnote = Strings("Enter to save - Esc to cancel"),
    })
    return true
  end
  if imp._profileSavePrompt then
    buildPrompt(imp, m, {
      key = "profsave", title = Strings("Save mod profile"),
      hint = Strings("Enter a name for this mod profile:"),
      text = imp._profileSavePrompt.text or "", okLabel = Strings("Save"),
      commit = function()
        local txt = imp._profileSavePrompt and imp._profileSavePrompt.text
        if txt and txt ~= "" then
          local LauncherMods = require("src.mods.LauncherMods")
          LauncherMods.saveProfile(txt)
          imp._profileSavePrompt = nil
          imp:_disarmTextInput()
          if imp._refreshMods then imp:_refreshMods() end
        end
      end,
      cancel = function()
        imp._profileSavePrompt = nil
        imp:_disarmTextInput()
      end,
      footnote = Strings("Enter to save - Esc to cancel"),
    })
    return true
  end
  if imp._settingsText then
    local st = imp._settingsText
    buildPrompt(imp, m, {
      key = "settext", title = st.row.label, text = st.text,
      okLabel = Strings("Save"),
      commit = function() imp:_commitSettingsText() end,
      cancel = function()
        imp._settingsText = nil
        imp:_disarmTextInput()
      end,
      footnote = Strings("Enter to save - Esc to cancel"),
    })
    return true
  end
  if imp._settings then buildSettingsModal(imp, m) return true end
  if imp._rename then
    buildPrompt(imp, m, {
      key = "rename", title = Strings("Name save slot"),
      text = imp._rename.text, okLabel = Strings("Save"),
      commit = function() imp:_commitRename() end,
      cancel = function()
        imp._rename = nil
        imp:_disarmTextInput()
      end,
      footnote = Strings("Enter to save - Esc to cancel - empty clears"),
    })
    return true
  end
  if imp._indexPrompt then
    buildPrompt(imp, m, {
      key = "index", title = Strings("Add a mod index"),
      hint = Strings("Paste the index URL, or its owner/repo."),
      text = imp._indexPrompt.text or "", okLabel = Strings("Add"),
      commit = function() imp:_commitAddIndex() end,
      cancel = function()
        imp._indexPrompt = nil
        imp:_disarmTextInput()
      end,
      paste = function() imp:_pasteIndexUrl() end,
      footnote = Strings("Enter to add - Esc to cancel"),
    })
    return true
  end
  if imp._modConfirm then buildConfirmModal(imp, m) return true end
  if imp._appPatchNotes then
    local PatchNotes = require("src.update.PatchNotes")
    local ModUpdate = require("src.mods.ModUpdate")
    local raw, ver = PatchNotes.body(imp.Check)
    local body = ModUpdate.cleanBody(raw or "", 0)
    if body == "" then body = Strings("(No patch notes.)") end
    local title = Strings("Patch notes")
    if ver and ver ~= "" then
      title = title .. "  v" .. tostring(ver)
    end
    buildTextModal(imp, m, "patch-notes-modal", title, body,
      function() imp._appPatchNotes = nil end)
    return true
  end
  if imp._modReleaseNotes then
    local ModUpdate = require("src.mods.ModUpdate")
    local n = imp._modReleaseNotes
    local body = ModUpdate.cleanBody(n.body or "", 0)
    if body == "" then body = Strings("(No release notes.)") end
    buildTextModal(imp, m, "release-notes",
      "v" .. tostring(n.version) .. Strings(" notes"), body,
      function() imp._modReleaseNotes = nil end)
    return true
  end
  if imp._findDetails then
    local ModUpdate = require("src.mods.ModUpdate")
    local d = imp._findDetails
    local body = ModUpdate.cleanBody(d.body or "", 0)
    if body == "" then body = Strings("(No description.)") end
    buildTextModal(imp, m, "find-details", d.title, body,
      function() imp._findDetails = nil end)
    return true
  end
  if imp._modVersions then buildVersionsModal(imp, m) return true end
  if imp._modDepResolver then buildDepResolverModal(imp, m) return true end
  if imp._modImports then buildRequiredImportsModal(imp, m) return true end
  -- The lighter popups come after the deep ones on purpose: opening
  -- Versions or Details from inside an actions popup draws the deeper modal
  -- while the popup's own state stays set, so closing the deep one drops
  -- you back where you were.
  if imp._singleProfileActions then buildSingleProfileActionsModal(imp, m) return true end
  if imp._profilesPopup then buildProfilesModal(imp, m) return true end
  if imp._modHeaderActionsPopup then buildModHeaderActionsModal(imp, m) return true end
  if imp._sortPopup then buildSortModal(imp, m) return true end
  if imp._gamePopup then buildGameModal(imp, m) return true end
  if imp._modScopePopup then buildModScopeModal(imp, m) return true end
  if imp._filterPopup then buildFilterModal(imp, m) return true end
  if imp._indexManage then buildIndexesModal(imp, m) return true end
  if imp._modActions then buildModActionsModal(imp, m) return true end
  if imp._findEntry then buildFindEntryModal(imp, m) return true end
  if imp._gameManage then buildGameManageModal(imp, m) return true end
  return false
end

-- --------------------------------------------------------------- overlays

-- The blocking loader.  imp.workState drives the ROM import (which reports
-- real progress); imp._busy drives every async network operation.
local function loaderSpec(imp)
  if imp.workState == "working" then
    return {
      title = imp.status or Strings("Working"),
      detail = imp.detail,
      progress = imp.progress,
    }
  end
  local b = imp._busy
  if b then
    return { title = b.title, detail = b.detail, progress = b.progress,
             onCancel = b.cancel }
  end
  -- The boot prewarm runs without an overlay (the user did not ask for it and
  -- must be able to use the launcher meanwhile), but if they reach the Find
  -- Mods tab before it lands, THEN they are waiting on it and it earns one.
  if imp.tab == "find" and imp._findFetch and not imp.findLoaded then
    return { title = Strings("Loading mod index") }
  end
  return nil
end

local function drawPadCursor(imp)
  if not imp._padCursorActive then return end
  -- Pixel-snap on NX: subpixel polygon edges shimmer on the 720p Switch
  -- framebuffer when the stick advances by fractional pixels each frame.
  local x, y = imp._padCursor.x, imp._padCursor.y
  if imp.isNX then
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
  end
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.polygon("fill",
    x + 2, y + 2, x + 2, y + 22, x + 8, y + 16, x + 14, y + 26,
    x + 18, y + 24, x + 11, y + 14, x + 20, y + 14)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.polygon("fill",
    x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
    x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.polygon("line",
    x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
    x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
  love.graphics.pop()
end

-- ------------------------------------------------------------ frame assembly

-- Mirror of buildHeader's vertical arithmetic, so the frame can decide
-- whether the window is tall enough BEFORE anything draws.  Keep in sync
-- with buildHeader (rail, logo row, tab row, hairline pad).
local function headerHeight(m)
  return m.railH + m.logoH + math.floor(12 * m.s) + math.floor(6 * m.s)
    + m.chip + math.floor(8 * m.s) + math.floor(10 * m.s)
end

-- The panel space a tab needs to lay out without crushing itself.  Below
-- this the page SCROLLS (wheel / touch drag) instead of compressing: the
-- pinned Play block used to walk up over the cards on a short window, which
-- is unusable, and the footer simply lives below the fold until scrolled to.
local function minPanelHeight(m)
  -- One column stacks the ROM card and the slot card in a single pile, so it
  -- needs more room than the side-by-side layout; two columns only have to
  -- fit the taller of the two.  Both numbers came DOWN sharply when the
  -- pinned Touch-Controls / Reset-rebinds pair moved behind the gear and the
  -- save-file buttons moved into the slot card: the pile they used to sit on
  -- top of was what forced 460/660 (#852), and a threshold larger than the
  -- content pushes the whole page below the fold on windows that could have
  -- shown it outright (a 1280x720 desktop was scrolling for 93px of nothing).
  -- Whatever a window still cannot show, the page scroll above reaches.
  return math.floor((m.twoCol and 340 or 470) * m.s)
end

function LauncherView.draw(imp)
  ensureState(imp)
  local m = Layout.metrics(1200)

  -- The pointer is the pad cursor while it is active, so the ring, hover and
  -- clicks all agree on where "the pointer" is.
  local mx, my = 0, 0
  if imp._padCursorActive then
    mx, my = imp._padCursor.x, imp._padCursor.y
  elseif love.mouse and love.mouse.getPosition then
    mx, my = love.mouse.getPosition()
  end
  local click = imp._clickPt
  if click then mx, my = click.x, click.y end

  -- SHORT-WINDOW SCROLL.  When the space between header and footer falls
  -- under the panel minimum, the whole page (header included) scrolls by a
  -- plain y offset: layout runs off a shifted m.top, so hit tests, focus
  -- rects and drawing all agree with the real pointer and no transform is
  -- involved.  Modals and the loader keep the REAL metrics and stay
  -- centred in the window.
  local footH = footerHeight(imp, m)
  local naturalAvail = m.h - headerHeight(m) - footH - m.gap
  local scrollMax = math.max(0, minPanelHeight(m) - naturalAvail)
  local scroll = math.max(0, math.min(imp._pageScroll or 0, scrollMax))
  if scrollMax > 0 and (imp._wheelY or 0) ~= 0 then
    scroll = math.max(0, math.min(
      scroll - imp._wheelY * math.floor(48 * m.s), scrollMax))
    imp._wheelY = 0  -- the page consumed the wheel; lists page by tap here
  end
  imp._pageScroll, imp._pageScrollMax = scroll, scrollMax

  Kit.beginFrame(mx, my, click ~= nil, imp._wheelY or 0)
  imp._clickPt = nil
  imp._wheelY = 0

  Theme.field()

  -- Everything from here to buildModals sits UNDER any open modal, so the
  -- whole stage draws shielded (no clicks, no hover, no focus ring) while
  -- one is up; buildModals lowers the shield for the modal's own controls.
  Kit.blockClicks = modalUp(imp)

  -- The header is the only block that moves with the page scroll, so shift
  -- m.top across the call and put it back rather than wrapping `m` in a
  -- proxy: the proxy cost two tables a frame and put a metatable lookup on
  -- every m.* read for the rest of the frame.
  local baseTop = m.top
  if scroll > 0 then m.top = baseTop - scroll end
  local contentY = buildHeader(imp, m)
  m.top = baseTop
  local footY, availH
  if scrollMax > 0 then
    availH = minPanelHeight(m)
    footY = contentY + availH + m.gap
  else
    footY = m.top + m.h - footH
    availH = footY - contentY - m.gap
  end

  local x, w = m.contentX, m.contentW
  if imp.tab == "mods" then
    buildModsPanel(imp, x, contentY, w, availH, m)
  elseif imp.tab == "find" then
    buildFindPanel(imp, x, contentY, w, availH, m)
  elseif imp.tab == "skins" then
    buildSkinsPanel(imp, x, contentY, w, availH, m)
  else
    buildGamePanel(imp, x, contentY, w, availH, m, imp.tab)
  end

  buildFooter(imp, m, footY)
  Kit.blockClicks = false
  buildModals(imp, m)

  -- The loader sits above everything, including modals: it is the one thing
  -- that must never be clicked around.
  local spec = loaderSpec(imp)
  if spec then
    if Loader.overlay(m, spec) and spec.onCancel then
      queueAction(imp, "loader-cancel", spec.onCancel)
    end
  end

  if imp._launchFade then
    Theme.fill(0, 0, m.W, m.H, PAL.bg,
      math.min(1, imp._launchFade.elapsed / imp._launchFade.duration))
  end

  Kit.endFrame()
  drawPadCursor(imp)
end

return LauncherView
