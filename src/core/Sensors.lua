-- Accelerometer and gyroscope reads for the tilt-driven shader presets, plus
-- screen-rotation compensation. love.sensor does not exist in LOVE 11.5 on any
-- platform, so the working path is raw FFI into the SDL2 LOVE already links,
-- the same technique src/core/Orientation.lua uses. What is and is not verified
-- on real hardware is written down in docs/shaderfx.md.

local Sensors = {}

-- Test seams: a no-device harness injects synthetic readings.
local overrides = {}
local orientationOverride = nil

function Sensors.setOverride(kind, x, y, z)
  overrides[kind] = { x, y, z }
end

function Sensors.clearOverride(kind)
  overrides[kind] = nil
end

function Sensors.clearAllOverrides()
  overrides = {}
  orientationOverride = nil
end

-- "landscape" | "landscapeFlipped" | "portrait" | "portraitFlipped" | nil
-- (nil = ask SDL for real). Test seam for rotateForScreen below.
function Sensors.setOrientationOverride(o)
  orientationOverride = o
end

-- ---- love.sensor path (kept for a future LOVE 12 upgrade; always nil today).
local function safeHasSensor(kind)
  if not love or not love.sensor then return false end
  local ok, has = pcall(love.sensor.hasSensor, kind)
  return ok and has == true
end

local function loveSensorRead(kind)
  if not safeHasSensor(kind) then return nil end
  local ok, x, y, z = pcall(love.sensor.getData, kind)
  if not ok then return nil end
  return x or 0, y or 0, z or 0
end

-- ---- raw SDL2 FFI path (the one that actually works on LÖVE 11.5).
local SDL_SENSOR_ACCEL, SDL_SENSOR_GYRO = 1, 2
local SDL_INIT_SENSOR = 0x00008000
local KIND_TO_SDL_TYPE = { accelerometer = SDL_SENSOR_ACCEL, gyroscope = SDL_SENSOR_GYRO }

local sdlCdefOk = nil
local sdlSensorHandles = {} -- kind -> SDL_Sensor* (nil once confirmed absent)
local sdlSensorTried = {}

-- ffi.load("SDL2") first, needed on desktop where SDL2 is a separate library,
-- then bare ffi.C, needed on Android where love-android links SDL2 statically
-- into libmain.so and there is no standalone libSDL2.so to attach to by name
-- (Orientation.lua's own sdlFfi resolves the same way on real hardware, #592/#716).
local sdlLib = nil
local function sdlFfi()
  local okFfi, ffi = pcall(require, "ffi")
  if not okFfi then return nil end
  if sdlCdefOk == nil then
    sdlCdefOk = pcall(ffi.cdef, [[
      typedef struct SDL_Window SDL_Window;
      typedef struct SDL_Sensor SDL_Sensor;
      int SDL_InitSubSystem(unsigned int flags);
      int SDL_NumSensors(void);
      int SDL_SensorGetDeviceType(int device_index);
      SDL_Sensor *SDL_SensorOpen(int device_index);
      void SDL_SensorUpdate(void);
      int SDL_SensorGetData(SDL_Sensor *sensor, float *data, int num_values);
      SDL_Window *SDL_GL_GetCurrentWindow(void);
      int SDL_GetWindowDisplayIndex(SDL_Window *window);
      int SDL_GetDisplayOrientation(int displayIndex);
    ]])
    if sdlCdefOk then
      local okLoad, lib = pcall(ffi.load, "SDL2")
      lib = okLoad and lib or ffi.C
      local okSyms = pcall(function()
        return lib.SDL_InitSubSystem, lib.SDL_NumSensors, lib.SDL_SensorGetDeviceType,
          lib.SDL_SensorOpen, lib.SDL_SensorUpdate, lib.SDL_SensorGetData,
          lib.SDL_GL_GetCurrentWindow, lib.SDL_GetWindowDisplayIndex,
          lib.SDL_GetDisplayOrientation
      end)
      sdlLib = okSyms and lib or false
    end
  end
  if not sdlCdefOk or not sdlLib then return nil end
  return sdlLib
end

-- Opens and caches once, and returns nil permanently once a real attempt finds
-- none, so a no-hardware desktop run pays this cost once rather than per frame.
local function sdlSensorHandle(lib, kind)
  if sdlSensorTried[kind] then return sdlSensorHandles[kind] end
  sdlSensorTried[kind] = true
  local wantType = KIND_TO_SDL_TYPE[kind]
  if not wantType then return nil end
  local okInit = pcall(lib.SDL_InitSubSystem, SDL_INIT_SENSOR)
  if not okInit then return nil end
  local okCount, count = pcall(lib.SDL_NumSensors)
  if not okCount or count <= 0 then return nil end
  for i = 0, count - 1 do
    local okType, t = pcall(lib.SDL_SensorGetDeviceType, i)
    if okType and t == wantType then
      local okOpen, handle = pcall(lib.SDL_SensorOpen, i)
      if okOpen and handle ~= nil then
        sdlSensorHandles[kind] = handle
        return handle
      end
    end
  end
  return nil
end

local function sdlSensorRead(kind)
  local lib = sdlFfi()
  if not lib then return nil end
  local handle = sdlSensorHandle(lib, kind)
  if not handle then return nil end
  pcall(lib.SDL_SensorUpdate)
  local data = require("ffi").new("float[3]")
  local okGet, n = pcall(lib.SDL_SensorGetData, handle, data, 3)
  if not okGet or n ~= 0 then return nil end
  return data[0], data[1], data[2]
end

-- ---- screen-rotation compensation (x/y only; z is perpendicular to the screen
-- and unaffected by an in-plane rotation). Mobile-only: a desktop monitor is
-- legitimately, permanently "landscape" to SDL_GetDisplayOrientation.
local function isMobile()
  if not love or not love.system or not love.system.getOS then return false end
  local os = love.system.getOS()
  return os == "Android" or os == "iOS"
end

local function sdlOrientation()
  if not isMobile() then return nil end
  local lib = sdlFfi()
  if not lib then return nil end
  local okWin, win = pcall(lib.SDL_GL_GetCurrentWindow)
  if not okWin or win == nil then return nil end
  local okIdx, idx = pcall(lib.SDL_GetWindowDisplayIndex, win)
  if not okIdx or idx < 0 then return nil end
  local okOr, o = pcall(lib.SDL_GetDisplayOrientation, idx)
  if not okOr then return nil end
  -- SDL_DisplayOrientation: 0=UNKNOWN, 1=LANDSCAPE, 2=LANDSCAPE_FLIPPED,
  -- 3=PORTRAIT, 4=PORTRAIT_FLIPPED.
  if o == 1 then return "landscape"
  elseif o == 2 then return "landscapeFlipped"
  elseif o == 3 then return "portrait"
  elseif o == 4 then return "portraitFlipped"
  else return nil end
end

-- Remaps raw device-frame (x,y) into "as currently displayed" (x,y). portrait,
-- and unknown/undetectable (desktop always lands here), is a no-op.
local function rotateForScreen(x, y)
  local o = orientationOverride or sdlOrientation()
  if o == "landscape" then return -y, x
  elseif o == "landscapeFlipped" then return y, -x
  elseif o == "portraitFlipped" then return -x, -y
  else return x, y end
end

-- Returns x, y, z for "accelerometer" | "gyroscope". {0,0,0} when overridden
-- that way, no hardware/module is available, or an underlying call errors.
-- x/y are rotated to be screen-relative; z passes through unchanged.
function Sensors.read(kind)
  local override = overrides[kind]
  if override then
    local x, y = rotateForScreen(override[1], override[2])
    return x, y, override[3]
  end

  local x, y, z = loveSensorRead(kind)
  if not x then x, y, z = sdlSensorRead(kind) end
  if not x then return 0, 0, 0 end

  x, y = rotateForScreen(x, y)
  return x, y, z
end

return Sensors
