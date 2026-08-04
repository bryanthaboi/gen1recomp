-- Switch-only display size: handheld 1280x720, docked (TV) 1920x1080.
-- love-nx's SDL backend can auto-resize on dock/undock when the window is
-- resizable; this module also syncs on boot and when the operation mode
-- changes so a docked launch is not stuck at the conf.lua 720p hint.
--
-- Important: only call love.window.setMode when width/height must change.
-- Re-applying every frame (e.g. to "fix" fullscreen/resizable flags that
-- love-nx reports differently) recreates the EGL surface and flickers the launcher.

local Platform = require("src.core.Platform")

local NxDisplay = {}

NxDisplay.HANDHELD_W, NxDisplay.HANDHELD_H = 1280, 720
NxDisplay.DOCKED_W, NxDisplay.DOCKED_H = 1920, 1080

-- AppletOperationMode from libnx: Handheld = 0, Console (docked) = 1.
local MODE_HANDHELD = 0
local MODE_CONSOLE = 1

-- Test hooks (nil = use live Platform / FFI / love.window).
NxDisplay._forceNXForTests = nil
NxDisplay._operationModeForTests = nil

local ffiOk, ffiC

local function ensureFfi()
  if ffiOk ~= nil then return ffiOk end
  ffiOk = false
  local ok, ffi = pcall(require, "ffi")
  if not ok or not ffi then return false end
  -- Redefinition is fine across hot reload / tests; we only need the symbol.
  pcall(ffi.cdef, [[
    unsigned char appletGetOperationMode(void);
  ]])
  local probeOk = pcall(function()
    return ffi.C.appletGetOperationMode
  end)
  if not probeOk then return false end
  ffiC = ffi.C
  ffiOk = true
  return true
end

local function isNX()
  if NxDisplay._forceNXForTests ~= nil then
    return not not NxDisplay._forceNXForTests
  end
  return Platform.isNX()
end

-- Returns AppletOperationMode or nil when unavailable.
function NxDisplay.operationMode()
  if NxDisplay._operationModeForTests ~= nil then
    return NxDisplay._operationModeForTests
  end
  if not ensureFfi() or not ffiC then return nil end
  local ok, mode = pcall(function()
    return tonumber(ffiC.appletGetOperationMode())
  end)
  if not ok then return nil end
  return mode
end

-- Map operation mode → framebuffer size.
-- Unknown / nil → nil,nil (do not fight SDL or force a wrong size).
function NxDisplay.desiredSize(mode)
  if mode == nil then mode = NxDisplay.operationMode() end
  if mode == MODE_CONSOLE then
    return NxDisplay.DOCKED_W, NxDisplay.DOCKED_H
  end
  if mode == MODE_HANDHELD then
    return NxDisplay.HANDHELD_W, NxDisplay.HANDHELD_H
  end
  return nil
end

-- Apply handheld/dock size when on NX and the window size differs.
-- Never setMode just to tweak flags — that flickers on love-nx.
-- Returns true when setMode ran.
function NxDisplay.sync()
  if not isNX() then return false end
  if not (love and love.window and love.window.getMode and love.window.setMode) then
    return false
  end
  local wantW, wantH = NxDisplay.desiredSize()
  if not wantW or not wantH then return false end
  local curW, curH, flags = love.window.getMode()
  if curW == wantW and curH == wantH then
    return false
  end
  flags = flags or {}
  flags.fullscreen = false
  flags.resizable = true
  love.window.setMode(wantW, wantH, flags)
  return true
end

function NxDisplay._resetForTests()
  NxDisplay._forceNXForTests = nil
  NxDisplay._operationModeForTests = nil
  ffiOk, ffiC = nil, nil
end

return NxDisplay
