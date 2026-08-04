-- NX launcher pad-cursor lag guards (Switch-only).
-- Proves the virtual mouse no longer warps love.mouse via setPosition on NX,
-- that FlexLove still sees pad coords through the getPosition bridge, that
-- desktop keeps setPosition, and that LauncherView wires NX perf guards.
-- Also prints a small metric block (setPosition counts + update cost).
--
-- FlexLove itself is not loaded here: the engine tier runs under plain luajit
-- without luautf8, which FlexLove requires. RomImporter owns the pointer
-- bridge; LauncherView wiring is asserted via source seams.
--   luajit tests/engine/launcher_nx_pad_cursor_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- Instrument setPosition so we can count warps (love_stub has none).
local setPositionCalls = 0
local mouseX, mouseY = 0, 0
love.mouse.getPosition = function() return mouseX, mouseY end
love.mouse.setPosition = function(x, y)
  setPositionCalls = setPositionCalls + 1
  mouseX, mouseY = x, y
end

local RomImporter = require("src.import.RomImporter")

local function freshImporter(isNX)
  return setmetatable({
    isNX = isNX and true or false,
    _padCursor = { x = 100, y = 100 },
    _padCursorActive = false,
    _padAxis = { leftx = 0, lefty = 0, righty = 0 },
    _padDir = {},
    _rawHatDirs = {},
    _padInited = true,
    _flex = true,
    tab = "red",
  }, RomImporter)
end

local function stickRight(imp, frames, dt)
  dt = dt or (1 / 60)
  imp._padAxis.leftx = 1
  for _ = 1, frames do
    imp:_updatePadCursor(dt)
  end
end

local function read(path)
  local f = assert(io.open(path, "r"))
  local src = f:read("*a")
  f:close()
  return src
end

-- ------- NX: no setPosition warps; getPosition bridge tracks the pad

do
  setPositionCalls = 0
  mouseX, mouseY = 0, 0
  local imp = freshImporter(true)
  local x0 = imp._padCursor.x
  stickRight(imp, 30)
  check(imp._padCursorActive, "NX stick activates pad cursor")
  check(imp._padCursor.x > x0, "NX stick moves pad cursor right")
  eq(setPositionCalls, 0, "NX pad move never calls love.mouse.setPosition")
  check(imp._nxPointerBridge, "NX installs getPosition bridge")
  local gx, gy = love.mouse.getPosition()
  eq(gx, imp._padCursor.x, "NX getPosition X matches pad cursor")
  eq(gy, imp._padCursor.y, "NX getPosition Y matches pad cursor")
  -- Real (stored) mouse must stay where the stub left it — bridge only.
  eq(mouseX, 0, "NX does not warp the underlying mouse X")
  eq(mouseY, 0, "NX does not warp the underlying mouse Y")
  imp:_restoreNxPointerBridge()
  check(not imp._nxPointerBridge, "restore clears NX mouse bridge")
  local rx, ry = love.mouse.getPosition()
  eq(rx, 0, "after restore getPosition is the real stub again")
  eq(ry, 0, "after restore getPosition Y is the real stub again")
end

-- ------- NX: A after idle must not false-yield the pad cursor

do
  mouseX, mouseY = 10, 20
  local imp = freshImporter(true)
  imp._padCursor.x, imp._padCursor.y = 400, 300
  -- Idle frames (NX ignores mouse yield entirely).
  imp:_updatePadCursor(1 / 60)
  -- A / activate without stick motion (clickAt path).
  imp:_activatePadCursor()
  imp:_updatePadCursor(1 / 60)
  check(imp._padCursorActive,
    "NX A after idle keeps pad cursor")
  local gx, gy = love.mouse.getPosition()
  eq(gx, 400, "bridged getPosition still reports pad X after A")
  eq(gy, 300, "bridged getPosition still reports pad Y after A")
  -- System mouse drift must NOT yield on NX (SDL stick→mouse / touch noise).
  mouseX, mouseY = 80, 90
  imp:_updatePadCursor(1 / 60)
  check(imp._padCursorActive, "NX ignores real mouse drift for yield")
  imp:parkNxPointerForHost()
end

-- ------- NX: sparse stick + SDL mouse drift must not flicker the overlay

do
  mouseX, mouseY = 100, 100
  local imp = freshImporter(true)
  imp._padCursor.x, imp._padCursor.y = 100, 100
  local flickers = 0
  for i = 1, 60 do
    mouseX = mouseX + 8 -- simulated SDL stick→mouse drift
    if i % 2 == 1 then
      imp._padAxis.leftx = 1
    else
      imp._padAxis.leftx = 0 -- axis events not every frame
    end
    local before = imp._padCursorActive
    imp:_updatePadCursor(1 / 60)
    if before and not imp._padCursorActive then
      flickers = flickers + 1
    end
  end
  eq(flickers, 0, "NX sparse stick + mouse drift causes zero pad flickers")
  check(imp._padCursorActive, "NX pad stays active after sparse stick run")
  -- dt clamp: a 0.2s hitch must not move more than a 1/30 step
  local xBefore = imp._padCursor.x
  imp._padAxis.leftx = 1
  imp:_updatePadCursor(0.2)
  local moved = imp._padCursor.x - xBefore
  local maxStep = 560 * (1 / 30) + 0.01
  check(moved <= maxStep, "NX pad cursor dt is clamped at 1/30")
  imp:parkNxPointerForHost()
end

-- ------- NX: parkNxPointerForHost restores mouse for embedded editor

do
  mouseX, mouseY = 5, 6
  local imp = freshImporter(true)
  stickRight(imp, 5)
  check(imp._nxPointerBridge, "bridge on before park")
  check(imp._padCursorActive, "pad active before park")
  imp:parkNxPointerForHost()
  check(not imp._nxPointerBridge, "park clears bridge")
  check(not imp._padCursorActive, "park clears pad active")
  local gx, gy = love.mouse.getPosition()
  eq(gx, 5, "after park getPosition is real mouse X")
  eq(gy, 6, "after park getPosition is real mouse Y")
  -- Desktop no-op.
  local desk = freshImporter(false)
  desk._padCursorActive = true
  desk:parkNxPointerForHost()
  check(desk._padCursorActive, "desktop parkNxPointerForHost is a no-op")
end

-- ------- Overlay handoff / resume (Edit Save + Touch Controls)

do
  mouseX, mouseY = 9, 10
  local imp = freshImporter(true)
  imp.launcher = true
  stickRight(imp, 3)
  check(imp._padCursorActive, "pad active before overlay handoff")
  check(imp._nxPointerBridge, "bridge on before overlay handoff")
  imp:prepareOverlayHandoff()
  check(not imp._padCursorActive, "prepareOverlayHandoff clears pad")
  check(not imp._nxPointerBridge, "prepareOverlayHandoff clears NX bridge")
  check(imp._flex == nil, "prepareOverlayHandoff clears flex without FlexLove")
  local gx, gy = love.mouse.getPosition()
  eq(gx, 9, "after overlay handoff getPosition is real mouse X")
  eq(gy, 10, "after overlay handoff getPosition is real mouse Y")

  local prevCount = love.joystick and love.joystick.getJoystickCount
  love.joystick = love.joystick or {}
  love.joystick.getJoystickCount = function() return 1 end
  imp:resumeAfterOverlay()
  check(imp._padCursorActive, "NX resumeAfterOverlay re-arms pad with a stick")
  love.joystick.getJoystickCount = function() return 0 end
  imp._padCursorActive = false
  imp:resumeAfterOverlay()
  check(not imp._padCursorActive, "resumeAfterOverlay stays latent with no stick")
  love.joystick.getJoystickCount = prevCount

  local desk = freshImporter(false)
  desk.launcher = true
  desk._padCursorActive = true
  desk:prepareOverlayHandoff()
  check(not desk._padCursorActive, "desktop prepareOverlayHandoff clears pad too")
end

-- ------- Desktop: setPosition still warps (unchanged path)

do
  setPositionCalls = 0
  mouseX, mouseY = 0, 0
  local imp = freshImporter(false)
  local x0 = imp._padCursor.x
  stickRight(imp, 30)
  check(imp._padCursorActive, "desktop stick activates pad cursor")
  check(imp._padCursor.x > x0, "desktop stick moves pad cursor right")
  eq(setPositionCalls, 30, "desktop pad move warps mouse every frame")
  eq(mouseX, imp._padCursor.x, "desktop setPosition tracks pad X")
  eq(mouseY, imp._padCursor.y, "desktop setPosition tracks pad Y")
  check(not imp._nxPointerBridge, "desktop never installs NX bridge")
  -- Desktop yield still drops the pad when the real mouse moves (stick released).
  imp._padAxis.leftx = 0
  mouseX, mouseY = mouseX + 20, mouseY + 20
  imp:_updatePadCursor(1 / 60)
  check(not imp._padCursorActive, "desktop real mouse motion still yields pad")
end

-- ------- Metrics: setPosition counts + pad-update cost (NX vs desktop)

do
  local frames = 120
  local dt = 1 / 60

  setPositionCalls = 0
  local nx = freshImporter(true)
  local t0 = os.clock()
  stickRight(nx, frames, dt)
  local nxMs = (os.clock() - t0) * 1000
  local nxSet = setPositionCalls
  nx:_restoreNxPointerBridge()

  setPositionCalls = 0
  local desk = freshImporter(false)
  t0 = os.clock()
  stickRight(desk, frames, dt)
  local deskMs = (os.clock() - t0) * 1000
  local deskSet = setPositionCalls

  eq(nxSet, 0, "metric: NX setPosition count is 0 over 120 frames")
  eq(deskSet, frames, "metric: desktop setPosition count equals frame count")

  print(string.format(
    "METRICS nx_pad_cursor: frames=%d nx_setPosition=%d desk_setPosition=%d nx_update_ms=%.3f desk_update_ms=%.3f",
    frames, nxSet, deskSet, nxMs, deskMs))
end

-- ------- Source seams: LauncherView NX perf + detach restore

do
  local view = read("src/import/LauncherView.lua")
  check(view:find("function LauncherView.applyNxPerfGuards", 1, true) ~= nil,
    "LauncherView exports applyNxPerfGuards")
  check(view:find("LauncherView.applyNxPerfGuards(imp)", 1, true) ~= nil,
    "ensureFlex calls applyNxPerfGuards")
  check(view:find("FlexLove._Performance.enabled = false", 1, true) ~= nil,
    "NX guard disables Performance.enabled")
  check(view:find("mp.enabled = false", 1, true) ~= nil,
    "NX guard disables memory profiling")
  -- The guard used to be NX-only; the same perf-timer and GC hitches showed
  -- up in desktop scrolling, so it now applies on every platform.
  check(view:find("if not (imp and FlexLove.isReady()", 1, true) ~= nil,
    "perf guard applies on every platform (not gated on imp.isNX)")
  check(view:find("parkNxPointerForHost", 1, true) ~= nil,
    "detach parks NX pointer before tearing down")

  local impSrc = read("src/import/RomImporter.lua")
  check(impSrc:find("function RomImporter:_ensureNxPointerBridge", 1, true) ~= nil,
    "RomImporter owns NX getPosition bridge")
  check(impSrc:find("function RomImporter:parkNxPointerForHost", 1, true) ~= nil,
    "RomImporter exports parkNxPointerForHost")
  check(impSrc:find("function RomImporter:prepareOverlayHandoff", 1, true) ~= nil,
    "RomImporter exports prepareOverlayHandoff")
  check(impSrc:find("function RomImporter:resumeAfterOverlay", 1, true) ~= nil,
    "RomImporter exports resumeAfterOverlay")
  check(impSrc:find("if not self.isNX then", 1, true) ~= nil,
    "NX skips desktop mouse-yield path")
  check(impSrc:find("if not self.isNX and love.mouse.setPosition", 1, true) ~= nil,
    "RomImporter skips setPosition on NX")
  check(impSrc:find("dt > 1 / 30", 1, true) ~= nil,
    "NX clamps pad cursor dt")

  local mainSrc = read("main.lua")
  check(mainSrc:find("prepareOverlayHandoff", 1, true) ~= nil,
    "openEditor / Touch Controls use prepareOverlayHandoff")
  check(mainSrc:find("resumeAfterOverlay", 1, true) ~= nil,
    "close paths resume the launcher pad cursor")

  check(view:find("math.floor(x + 0.5)", 1, true) ~= nil,
    "NX pad cursor draw is pixel-snapped")
  check(view:find('strategy = "periodic"', 1, true) ~= nil,
    "NX softens FlexLove GC strategy")
end

T.finish("launcher_nx_pad_cursor")
