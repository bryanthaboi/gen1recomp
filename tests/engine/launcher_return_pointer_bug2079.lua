-- #2079: EXIT GAME / Close editor leave the confirming finger down over
-- Import Save.  After remount the launcher must not treat that leftover as
-- a new tap (the file picker opening a few seconds later is that lift).
--   luajit tests/engine/launcher_return_pointer_bug2079.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local clock = 1000
love.timer.getTime = function() return clock end

local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

local function launcher()
  return setmetatable({
    _flex = true,
    _actAt = {},
    _uiActions = {},
  }, RomImporter)
end

-- ------- ignoreReturningPointer swallows a leftover hold

do
  local down = true
  love.mouse.isDown = function() return down end
  love.mouse.getPosition = function() return 280, 640 end
  local imp = launcher()
  imp:ignoreReturningPointer()
  check(imp._prevMouseDown == true,
    "returning marks the pointer already down so the first poll is not a press")
  check(imp._suppressClickUntil > clock,
    "and raises a click debounce over the leftover gesture")
  check(imp._clickPt == nil, "any queued click is cleared")

  LauncherView.update(imp, 0.016)
  check(imp._mouseAt == nil, "the leftover hold does not arm a drag/tap")
  check(imp._clickPt == nil)

  clock = 1000.7
  LauncherView.update(imp, 0.016)
  check(imp._mouseAt == nil,
    "a still-down finger after the debounce window still does not arm (#2079)")
  check(imp._clickPt == nil)

  down = false
  LauncherView.update(imp, 0.016)
  check(imp._clickPt == nil, "lifting the leftover finger is not a launcher tap")
  check(imp._prevMouseDown == false, "the poll then sees the pointer idle")

  down = true
  LauncherView.update(imp, 0.016)
  check(imp._mouseAt ~= nil, "a new press after the leftover lifts arms normally")
  down = false
  LauncherView.update(imp, 0.016)
  check(imp._clickPt ~= nil, "and that new press+release is a tap")
  love.mouse.isDown = nil
  love.mouse.getPosition = nil
end

-- ------- unmatched / leftover touch release is not a tap

do
  clock = 2000
  local imp = launcher()
  LauncherView.touchreleased(imp, "finger", 280, 640)
  check(imp._clickPt == nil,
    "a touch up with no matching press does not click Import Save")
end

do
  clock = 3000
  love.touch = love.touch or {}
  love.touch.getTouches = function() return { "held" } end
  local imp = launcher()
  imp:ignoreReturningPointer()
  check(imp._ignoreTouch.held == true, "already-down touch ids are ignored")
  LauncherView.touchpressed(imp, "held", 280, 640)
  check(imp._touchAt == nil or imp._touchAt.held == nil,
    "the leftover finger does not start a launcher tap")
  LauncherView.touchreleased(imp, "held", 280, 640)
  check(imp._clickPt == nil, "and its lift does not click")

  local ran = false
  LauncherView.queueAction(imp, "import-save", function() ran = true end)
  eq(#imp._uiActions, 0, "debounce drops Import Save during the hold window")
  check(not ran)

  clock = 3000.6
  LauncherView.touchpressed(imp, "fresh", 40, 40)
  LauncherView.touchreleased(imp, "fresh", 40, 40)
  check(imp._clickPt ~= nil, "a new finger after the window still taps")
  love.touch.getTouches = nil
end

-- ------- Close editor / overlay resume always debounces, even with no stick

do
  clock = 4000
  local imp = launcher()
  imp.launcher = true
  love.joystick = love.joystick or {}
  love.joystick.getJoystickCount = function() return 0 end
  imp:resumeAfterOverlay()
  check(imp._prevMouseDown == true,
    "resumeAfterOverlay debounces even when it does not re-arm the pad")
  check(imp._suppressClickUntil > clock,
    "so Close editor cannot click Import Save")
end

-- ------- EXIT GAME rebuilds the launcher with the same guard

do
  local main = assert(io.open("main.lua")):read("*a")
  local body = main:match("local function returnToLauncher%(opts%)(.-)\nend\n")
  check(body ~= nil, "main.lua still has returnToLauncher")
  check(body:find("ignoreReturningPointer", 1, true) ~= nil,
    "EXIT GAME asks the new launcher to ignore the leftover pointer (#2079)")
end

T.finish("launcher_return_pointer_bug2079")
