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

-- A square icon control: the header's gear and quit, and the game panel's
-- manage button.  Inverts to a solid white fill when hot, the same signal
-- every other control here uses, and rounds to the shared control radius.
-- `image` draws a texture; `drawFn(x, y, size, hot)` draws a hand-rolled
-- glyph (the quit X, which ships no asset).
local function iconButton(imp, key, x, y, size, image, action, drawFn)
  Kit._audit("control", x, y, size, size, key)
  local focused = Kit.focusable(key, x, y, size, size)
  local hot = focused or Kit.hover(x, y, size, size)
  Theme.fillRounded(x, y, size, size, hot and PAL.ink or PAL.surface, 1)
  Theme.strokeRounded(x, y, size, size, PAL.line,
    hot and Theme.A.focus or Theme.A.hairline, 1)
  if image then
    local iw, ih = image:getDimensions()
    local pad = math.floor(size * 0.24)
    local s = math.min((size - 2 * pad) / iw, (size - 2 * pad) / ih)
    if hot then love.graphics.setColor(0, 0, 0, 1)
    else love.graphics.setColor(1, 1, 1, 0.85) end
    love.graphics.draw(image, Theme.snap(x + (size - iw * s) / 2),
      Theme.snap(y + (size - ih * s) / 2), 0, s, s)
    love.graphics.setColor(1, 1, 1, 1)
  elseif drawFn then
    drawFn(x, y, size, hot)
  end
  if action and (Kit.press(x, y, size, size) or Kit._activateId == key) then
    queueAction(imp, key, action)
  end
end

-- The cartridge colour for a game, matching its tab in the header.  Play
-- wears it, so "which game is this button going to boot" is answered before
-- the label is read.  Unknown versions fall back to the commit green.
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
  local hoverTilt = hot and pointerX * 0.12 or math.sin(Kit.time * 0.75) * 0.035
  local pressX = active and pointerX * w * 0.025 or 0
  local pressY = active and pointerY * h * 0.018 or 0
  local yaw = -0.42 + state.spin + hoverTilt
  local pitch = 0.14 + (state.pitchDrag or 0)
    + (hot and pointerY * 0.08 or math.sin(Kit.time * 0.6) * 0.018)
  local pressedScale = active and 0.965 or 1

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

  if not state.active and (Kit._activateId == key) then
    queueAction(imp, key, action)
  end
end

local function modStatusColor(status)
  if status == "ok" then return Strings("Ready"), PAL.green end
  if status == "conflict" then return Strings("Conflict"), PAL.red end
  -- not a fault: the mod is intact, this is simply not a game it is for
  -- (src/mods/ModTargets.lua)
  if status == "other_game" then return Strings("Not for this game"), PAL.muted end
  return Strings("Incompatible"), PAL.yellow
end

-- MODS panel scope row: which game the list is answering for.  Drawn from
-- GameVersion.ORDER so a new game needs nothing here.
local function buildModScopeRow(imp, x, y, w, m)
  local GameVersion = require("src.core.GameVersion")
  local h = math.max(Kit.tapMin(), math.floor(26 * m.s))
  local gap = math.floor(6 * m.s)
  local label = Strings("Show for:")
  Kit.text("small", label, x, y + (h - Kit.textHeight("small")) / 2, PAL.muted)
  local cx = x + Kit.textWidth("small", label) + math.floor(10 * m.s)
  local options = { { id = nil, label = Strings("All games") } }
  for _, version in ipairs(GameVersion.ORDER) do
    if imp.ready and imp.ready[version] then
      options[#options + 1] =
        { id = version, label = GameVersion.info(version).label }
    end
  end
  if #options < 2 then return 0 end
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

-- A hand-drawn X, for the same reason drawCheck exists below: the UI font has
-- no guaranteed glyph, and the launcher ships no icon asset for it.
local function drawCross(x, y, size, color)
  love.graphics.push("all")
  love.graphics.setColor(color)
  love.graphics.setLineWidth(math.max(2, size * 0.16))
  love.graphics.setLineJoin("bevel")
  love.graphics.line(x, y, x + size, y + size)
  love.graphics.line(x + size, y, x, y + size)
  love.graphics.pop()
end

-- ------------------------------------------------------------- header
-- Rail, logo row (settings and quit on the right), tab bar.
-- Returns the y at which content may start.  Its vertical arithmetic is
-- mirrored by headerHeight() at the bottom of this file (the short-window
-- scroll decision needs the height before anything draws) -- keep in sync.
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
    Theme.fill(lx, by, chipW, gear, PAL.bg, 1)
    Theme.stroke(lx, by, chipW, gear, PAL.yellow, Theme.A.hover, 1)
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
  iconButton(imp, "gear", rx, by, gear, imp._gearIcon,
    function() imp:_openSettings() end)

  -- Quit, top-right corner.
  iconButton(imp, "quit", quitX, by, gear, nil,
    function() imp:_quitApp() end,
    function(x, y, size, hot)
      local pad = math.floor(size * 0.32)
      drawCross(x + pad, y + pad, size - 2 * pad,
        hot and { 0, 0, 0, 1 } or { 1, 1, 1, 0.85 })
    end)

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
  local tabs = {
    { id = "red",    letter = "R", label = Strings("RED"),    color = PAL.railRed },
    { id = "blue",   letter = "B", label = Strings("BLUE"),   color = PAL.railBlue },
    { id = "yellow", letter = "Y", label = Strings("YELLOW"), color = PAL.railGold },
    { id = "gold",   letter = "G", label = Strings("GOLD"),   color = PAL.railAmber },
    { id = "mods",   icon = imp._modsIcon, label = Strings("MODS") },
    { id = "find",   icon = imp._findIcon, label = Strings("FIND MODS") },
  }
  local tabH = m.chip
  local tx = m.x + m.pad
  local ty = y + math.floor(6 * m.s)
  -- Wrap the strip instead of running off the edge.
  --
  -- Six tabs used to escape a phone width when an active icon tab spelled its
  -- name out (FIND MODS at 412x915).  Game tabs (R/B/Y/G) stay glyph-only even
  -- when active; only MODS / FIND MODS expand.  Still wrap when the next tab
  -- would not fit so the divider below moves with the row count.
  local tabLeft = tx
  local tabRight = m.x + m.w - m.pad
  local tabGap = math.floor(6 * m.s)
  local tabRowGap = math.floor(4 * m.s)
  for _, t in ipairs(tabs) do
    local active = imp.tab == t.id
    local key = "tab-" .. t.id
    -- Cartridge tabs stay square (letter only).  Icon tabs still expand to
    -- show MODS / FIND MODS when selected.
    local expand = active and t.icon ~= nil
    local labelW = expand and Kit.textWidth("tab", t.label) or 0
    local w = expand and (tabH + math.floor(8 * m.s) + labelW + math.floor(12 * m.s))
      or tabH
    -- Never wrap the first tab of a row: if one tab alone is wider than the
    -- panel there is nowhere better to put it, and wrapping would loop.
    if tx > tabLeft and tx + w > tabRight then
      tx = tabLeft
      ty = ty + tabH + tabRowGap
    end
    Kit._audit("control", tx, ty, w, tabH, key)
    local focused = Kit.focusable(key, tx, ty, w, tabH)
    local hot = focused or Kit.hover(tx, ty, w, tabH)
    local invert = active or hot
    local tint = t.color or PAL.ink
    Theme.fillRounded(tx, ty, w, tabH, invert and tint or PAL.surface, 1)
    if not invert then
      Theme.strokeRounded(tx, ty, w, tabH, tint,
        t.color and Theme.A.hover or Theme.A.hairline, 1)
    end
    -- Ink on a filled tab must contrast with THAT fill: black on the light
    -- red/blue/gold cartridge colours, which are all high-luminance.
    local ink = invert and PAL.inverse or (t.color or PAL.text)
    if t.icon then
      local iw, ih = t.icon:getDimensions()
      local pad = math.floor(tabH * 0.24)
      local s = math.min((tabH - 2 * pad) / iw, (tabH - 2 * pad) / ih)
      if invert then love.graphics.setColor(0, 0, 0, 1)
      else love.graphics.setColor(1, 1, 1, 0.9) end
      love.graphics.draw(t.icon, Theme.snap(tx + (tabH - iw * s) / 2),
        Theme.snap(ty + (tabH - ih * s) / 2), 0, s, s)
      love.graphics.setColor(1, 1, 1, 1)
    else
      Kit.textCenter("tab", t.letter, tx,
        ty + (tabH - Kit.textHeight("tab")) / 2, tabH, ink)
    end
    if expand then
      Kit.text("tab", t.label, tx + tabH + math.floor(4 * m.s),
        ty + (tabH - Kit.textHeight("tab")) / 2, ink)
    end
    if Kit.press(tx, ty, w, tabH) or Kit._activateId == key then
      queueAction(imp, key, function() imp:_switchTab(t.id) end)
    end
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
    function() pcall(imp.Check.start) end, false
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

  -- title + status tag
  local titleH = Kit.textHeight("title")
  Kit.text("title", Kit.ellipsize("title", gameName, w * 0.6), x, y, PAL.heading)
  local tagText, tagCol
  if ready then tagText, tagCol = Strings("GOOD TO GO"), PAL.green
  elseif imp.baseRoms and imp.baseRoms[version] then
    tagText, tagCol = Strings("ROM FOUND"), PAL.green
  elseif locked then tagText, tagCol = Strings("COMING SOON"), PAL.steel
  else tagText, tagCol = Strings("ROM REQUIRED"), PAL.yellow end
  local tagW = Kit.textWidth("micro", tagText) + math.floor(18 * m.s)
  local tagH = Kit.textHeight("micro") + math.floor(10 * m.s)
  local tagX = x + Kit.textWidth("title", Kit.ellipsize("title", gameName, w * 0.6))
    + math.floor(12 * m.s)
  Kit.tag(tagX, y + (titleH - tagH) / 2, tagW, tagH, tagText, tagCol)
  if ready then
    local hint = Strings("(PRESS THE CART TO PLAY)")
    local hintX = tagX + tagW + math.floor(10 * m.s)
    local hintW = math.max(0, x + w - hintX)
    Kit.text("micro", Kit.ellipsize("micro", hint, hintW), hintX,
      y + (titleH - Kit.textHeight("micro")) / 2, PAL.heading)
  end
  local cy = y + titleH + math.floor(12 * m.s)
  local remaining = availH - (titleH + math.floor(12 * m.s))

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
    iconButton(imp, "manage-" .. version, lx + lw - mgW, ly, mgW,
      imp._gearIcon, function() imp._gameManage = version end)
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
local function sortDefs()
  return {
    { key = "name", label = Strings("Name") },
    { key = "popularity", label = Strings("Popularity") },
    { key = "release", label = Strings("Release date") },
    { key = "updated", label = Strings("Last updated") },
  }
end

local function currentSort(imp)
  local sortKey = imp.modSort
  if sortKey == nil then
    local ok, opts = pcall(require("src.core.SaveData").loadOptions)
    if ok and type(opts) == "table" and type(opts.modSort) == "string" then
      sortKey = opts.modSort
    end
    sortKey = sortKey or "popularity"
    imp.modSort = sortKey
  end
  return sortKey
end

-- A hand-drawn check mark: the UI font has no guaranteed glyph for one, and
-- a tofu box on the "you already have this" signal would be worse than none.
local function drawCheck(x, y, size, color)
  love.graphics.push("all")
  love.graphics.setColor(color)
  love.graphics.setLineWidth(math.max(2, size * 0.16))
  love.graphics.setLineJoin("bevel")
  love.graphics.line(
    x, y + size * 0.55,
    x + size * 0.35, y + size * 0.85,
    x + size * 0.95, y + size * 0.15)
  love.graphics.pop()
end

-- One compact coloured checkbox for each game.  The cartridge colour carries
-- the game identity even when the row is narrow; the letter keeps an unchecked
-- box legible without relying on colour alone.
local function modGameCheckbox(x, y, size, checked, game, id)
  local color = cartColor(game)
  local focused = Kit.focusable(id, x, y, size, size)
  local hot = focused or Kit.hover(x, y, size, size)
  if love.graphics then
    if checked then
      Theme.fillRounded(x, y, size, size, color, 1)
      drawCheck(x, y, size, PAL.inverse)
    else
      Theme.fillRounded(x, y, size, size, PAL.bg, 1)
      Kit.textCenterBold("micro", game:sub(1, 1):upper(), x,
        y + (size - Kit.textHeight("micro")) / 2, size, color)
    end
    Theme.strokeRounded(x, y, size, size, color,
      hot and Theme.A.focus or Theme.A.hover, 1)
  end
  return Kit.press(x, y, size, size) or Kit._activateId == id
end

local function buildModsPanel(imp, x, y, w, availH, m)
  imp:_ensureMods()
  local ModUpdate = require("src.mods.ModUpdate")
  local mods = imp.mods or {}
  local gap = m.gap
  local cy = y

  -- header: just the action cluster, right-aligned.  No "Mods" headline (the
  -- active tab already says it) and no enabled count (the toggles show it).
  local place = Layout.rightCluster(x, w, math.floor(6 * m.s))
  local bh = m.btnH
  local importLabel = imp:_modsImportButtonLabel()
  local iw2 = Kit.textWidth("small", importLabel) + math.floor(24 * m.s)
  btn(imp, place(iw2), cy, iw2, bh, "mods-import", importLabel, {
    kind = "accent", font = "small",
    action = function() imp:chooseMod() end })
  if #mods > 0 then
    local dw = Kit.textWidth("small", Strings("Disable all")) + math.floor(20 * m.s)
    btn(imp, place(dw), cy, dw, bh, "mods-disable-all", Strings("Disable all"), {
      kind = "warn", font = "small",
      action = function() imp:_setAllMods(false) end })
    local ew = Kit.textWidth("small", Strings("Enable all")) + math.floor(20 * m.s)
    btn(imp, place(ew), cy, ew, bh, "mods-enable-all", Strings("Enable all"), {
      kind = "good", font = "small",
      action = function() imp:_setAllMods(true) end })
    local sw = Kit.textWidth("small", Strings("Sort")) + math.floor(24 * m.s)
    btn(imp, place(sw), cy, sw, bh, "mods-sort", Strings("Sort"), {
      font = "small",
      action = function() imp._sortPopup = true end })
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

  local sortKey = currentSort(imp)

  -- Immediate mode paints this panel every frame; re-sorting the whole list
  -- per frame (with lowercased-string allocations in the comparator) fed the
  -- GC for nothing.  Cache the sorted array, keyed on the list identity, the
  -- sort mode, and the update-info revision the fetch pump bumps.
  local cache = imp._modSortCache
  if cache and cache.src == mods and cache.n == #mods
      and cache.key == sortKey and cache.rev == (imp._modUpdateRev or 0) then
    mods = cache.list
  else
    local sorted = {}
    for i, v in ipairs(mods) do sorted[i] = v end
    table.sort(sorted, function(a, b)
      local function value(mod)
        if sortKey == "name" then return (mod.name or ""):lower() end
        local info = mod.github and mod.github ~= "" and imp:_modUpdateInfo(mod.id)
        if sortKey == "popularity" then
          return info and info.downloads and info.downloads.total or -1
        end
        local date = info and info.dates
        if sortKey == "release" then return date and date.first or "0000-00-00" end
        return date and date.latest or "0000-00-00"
      end
      local va, vb = value(a), value(b)
      if va ~= vb then
        if sortKey == "name" then return va < vb end
        return va > vb  -- data sorts newest / most popular first
      end
      return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    imp._modSortCache = { src = imp.mods, n = #mods, key = sortKey,
      rev = imp._modUpdateRev or 0, list = sorted }
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
  imp._modListRect = { x = x, y = listTop, w = w, h = listH }
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
    local rowKey = "mod-row-" .. mod.id
    -- The whole row is the control: it opens the per-mod actions popup
    -- (update / versions / delete moved there).  Only the enable toggle
    -- stays inline, because flipping a mod on and off is the everyday act.
    local focused = Kit.focusable(rowKey, x, ry, w, rowH)
    local hot = focused or Kit.hover(x, ry, w, rowH)
    Kit.card(x, ry, w, rowH, hot)
    local pad = math.floor(12 * m.s)
    local px, inner = x + pad, w - 2 * pad
    local ly = ry + math.floor(10 * m.s)

    local togGap = math.floor(4 * m.s)
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
    Kit.text("button", nameShown, px, ly, PAL.heading)
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
    action = function() imp._sortPopup = true end })
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

  local sortKey = currentSort(imp)

  -- Same caching rule as the MODS tab: the comparator allocates, so only
  -- re-sort when the inputs actually change.
  local fcache = imp._findSortCache
  if fcache and fcache.src == rows and fcache.key == sortKey
      and fcache.rev == (imp._findStatsRev or 0) then
    rows = fcache.list
  else
    local sorted = {}
    for i, v in ipairs(rows) do sorted[i] = v end
    table.sort(sorted, function(a, b)
      local function value(entry)
        if sortKey == "name" then return (entry.title or entry.id or ""):lower() end
        local stats = imp:_findStats(entry)
        if sortKey == "popularity" then return stats and stats.total or -1 end
        if sortKey == "release" then return stats and stats.first or "0000-00-00" end
        return stats and stats.latest or "0000-00-00"
      end
      local va, vb = value(a), value(b)
      if va ~= vb then
        if sortKey == "name" then return va < vb end
        return va > vb
      end
      return (a.title or a.id or ""):lower() < (b.title or b.id or ""):lower()
    end)
    imp._findSortCache = { src = rows, key = sortKey,
      rev = imp._findStatsRev or 0, list = sorted }
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
    local rowKey = "find-row-" .. entry.id
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
      Kit.textCenter("micro", "MOD", px,
        ly + (thumb - Kit.textHeight("micro")) / 2, thumb, PAL.faint)
    end

    local bx = px + thumb + math.floor(10 * m.s)
    local bw = inner - thumb - math.floor(10 * m.s) - chipsW
    Kit.text("button", Kit.ellipsize("button", entry.title or entry.id, bw),
      bx, ly, PAL.heading)
    local by2 = ly + Kit.textHeight("button") + math.floor(4 * m.s)
    -- meta and stats on one line, the download count first (and green)
    -- because it is what the default Popularity sort is ordering by: a
    -- narrow window ellipsizes the tail, and the count must survive that.
    local stats = imp:_findStats(entry)
    local baseCol = note and PAL.green or PAL.detail
    local lead = "v" .. tostring(ModIndex.displayVersion(entry))
    if note then lead = lead .. "  -  " .. note end
    local dl = stats and ModUpdate.downloadsLine(stats.total) or nil
    local dates = stats and ModUpdate.datesLine(stats.first, stats.latest)
      or nil
    local rest = {}
    if entry.author then rest[#rest + 1] = entry.author end
    if entry.categories and entry.categories[1] then
      rest[#rest + 1] = entry.categories[1]
    end
    if dates then
      rest[#rest + 1] = dates
    elseif not dl and (entry.summary or "") ~= "" then
      rest[#rest + 1] = entry.summary
    end
    local segs = { { lead, baseCol } }
    if dl then segs[#segs + 1] = { "  -  " .. dl, PAL.green } end
    if #rest > 0 then
      segs[#segs + 1] = { "  -  " .. table.concat(rest, "  -  "), baseCol }
    end
    segLine("small", segs, bx, by2, bw)
  end

  local pagerY = listTop + (last - first + 1) * (rowH + gap)
  setPage(imp, "find", Kit.pager(x, pagerY, w, cur, #rows, perPage, "find"))
end

-- ------------------------------------------------------------------ footer

local TRUST_WARNING = "if you did not get this from bryanthaboi's github "
  .. "or a link from the discord that bryanthaboi himself posted, just know "
  .. "it might have been tampered with. go to the discord to verify "
  .. COMMUNITY_URL .. " (or click the logo above)"

-- Pinned to the bottom of the window; returns the y it starts at, so the
-- panels above know how much room they have.
-- Deliberately compact: at a large UI scale the footer is pure overhead
-- competing with the panel for a short window's height, so the mark and the
-- link share one line and the trust warning is capped at a single line.
local function footerHeight(imp, m)
  -- Top pad + mark/update row + gap + the FULL wrapped trust message +
  -- bottom pad.  The message wraps to as many lines as it needs: truncating
  -- a trust warning defeats its purpose, and the bottom pad is not optional
  -- either (without it the last line sits flush on the window edge and its
  -- lower half clips off).  The row is tapMin tall because the small update
  -- button rides beside the mark.
  local rowH = math.max(math.floor(22 * m.s), Kit.tapMin())
  return math.floor(8 * m.s) + rowH + math.floor(6 * m.s)
    + Kit.wrapHeight("micro", TRUST_WARNING, m.contentW)
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
  local rowH = math.max(math.floor(22 * m.s), Kit.tapMin())
  -- The mark and the small self-update control share the row, centred as a
  -- group.  The updater moved down here from the header, where it overlapped
  -- the wordmark on a phone; small on purpose, its glow still carries the
  -- "act on me" signal.
  local upStatus, upLabel, upAction, upGlow = LauncherView._updateControl(imp)
  -- Kit.button insets its label 16*scale per side, so the width must budget
  -- more than that or the label ellipsizes ("Check for updat...").
  local uw = upStatus
    and (Kit.textWidth("micro", upLabel) + math.floor(36 * m.s)) or 0
  local groupW = dw + (upStatus and (math.floor(10 * m.s) + uw) or 0)
  local bx = m.x + math.floor((m.w - groupW) / 2)
  local my = cy + math.floor((rowH - dh) / 2)
  local hot = Kit.hover(bx, my, dw, dh)
  love.graphics.setShader(imp.invertShader)
  love.graphics.setColor(1, 1, 1, hot and 1 or 0.85)
  love.graphics.draw(imp.bcg, Theme.snap(bx), Theme.snap(my), 0, scale, scale)
  love.graphics.setShader()
  love.graphics.setColor(1, 1, 1, 1)
  if Kit.press(bx, my, dw, dh) then
    queueAction(imp, "bcg", function() love.system.openURL(COMMUNITY_URL) end)
  end
  if upStatus then
    btn(imp, bx + dw + math.floor(10 * m.s), cy, uw, rowH, "updater",
      upLabel, {
        kind = upGlow and "warn" or "ghost", font = "micro",
        glow = upGlow, action = upAction,
      })
  end
  cy = cy + rowH + math.floor(6 * m.s)
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

-- Sort chooser, shared by the MODS and FIND MODS tabs (they share the
-- persisted key, so one popup serves both).
local function buildSortModal(imp, m)
  local defs = sortDefs()
  local pad = math.floor(18 * m.s)
  local w = math.floor(360 * m.s)
  local gap = math.floor(8 * m.s)
  local h = pad + Kit.textHeight("button") + math.floor(12 * m.s)
    + #defs * (m.btnH + gap) + m.btnH + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Strings("Sort by"), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(12 * m.s)
  local cur = currentSort(imp)
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
  local info = hasGit and imp:_modUpdateInfo(mod.id)
  local pad = math.floor(18 * m.s)
  local w = math.floor(440 * m.s)
  local gap = math.floor(8 * m.s)
  local nBtns = (hasGit and 2 or 0) + 2
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
  local h = pad + Kit.textHeight("button") + math.floor(4 * m.s)
    + Kit.textHeight("small") + noteH + math.floor(12 * m.s)
    + nBtns * (m.btnH + gap) - gap + pad
  local px, py, pw = modalPanel(m, w, h)
  local cy = py + pad
  Kit.text("button", Kit.ellipsize("button", entry.title or entry.id,
    pw - 2 * pad), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + math.floor(4 * m.s)
  local stats = imp:_findStats(entry)
  local lead = "v" .. tostring(ModIndex.displayVersion(entry))
  if entry.author then lead = lead .. "  -  " .. entry.author end
  if entry.categories and entry.categories[1] then
    lead = lead .. "  -  " .. entry.categories[1]
  end
  local dl = stats and ModUpdate.downloadsLine(stats.total) or nil
  local segs = { { lead, PAL.detail } }
  if dl then segs[#segs + 1] = { "  -  " .. dl, PAL.green } end
  segLine("small", segs, px + pad, cy, pw - 2 * pad)
  cy = cy + Kit.textHeight("small")
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
  if model.refresh and model.refresh() then
    -- Rebuild the flattened cache after a parent setting changes so Android
    -- removes dependent controls and recalculates pagination immediately.
    imp._settingsFlat = nil
  end
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
      Theme.strokeRounded(px + pad, ry, pw - 2 * pad, rowH, PAL.line,
        Theme.A.hairline, 1)
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

-- Whether ANY modal will draw this frame.  draw() consults this BEFORE the
-- panels build: immediate mode hit-tests each control as it draws, so the
-- panels underneath a modal must run with Kit.blockClicks already raised or
-- a click on the scrim lands on whatever button happens to be behind it.
-- Keep this list in sync with buildModals below.
local function modalUp(imp)
  return (imp._settingsText or imp._settings or imp._rename
    or imp._indexPrompt or imp._modConfirm or imp._modReleaseNotes
    or imp._findDetails or imp._modVersions or imp._sortPopup
    or imp._filterPopup or imp._indexManage or imp._modActions
    or imp._findEntry or imp._gameManage) ~= nil
end

local function buildModals(imp, m)
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
  -- The lighter popups come after the deep ones on purpose: opening
  -- Versions or Details from inside an actions popup draws the deeper modal
  -- while the popup's own state stays set, so closing the deep one drops
  -- you back where you were.
  if imp._sortPopup then buildSortModal(imp, m) return true end
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

  local ms = m
  if scroll > 0 then
    ms = setmetatable({ top = m.top - scroll }, { __index = m })
  end
  local contentY = buildHeader(imp, ms)
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
