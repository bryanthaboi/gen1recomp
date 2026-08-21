-- Screen orientation lock, Android and iOS (#592, #716, #1638).
--
-- Persisted as options.orientation: "auto" | "portrait" | "landscape" |
-- "reverseLandscape".  The lock travels through SDL_HINT_ORIENTATIONS:
-- SDLActivity.setOrientationBis parses the hint's space-separated names
-- into a setRequestedOrientation call, and GameActivity's override then
-- remaps any *_SENSOR result onto the matching *_USER constant, so a device
-- with auto-rotate off stays put (#716).  AUTO leaves the hint empty, which
-- with a resizable window means "any orientation, deferring to the system
-- rotation lock"; LANDSCAPE allows both landscapes (SENSOR_LANDSCAPE ->
-- USER_LANDSCAPE); REVERSE LANDSCAPE is SDL's LandscapeRight alone.
--
-- Android only re-reads the hint at window creation or on a resizable-flag
-- change (SDL_androidwindow.c), and SDL_SetWindowResizable early-returns on
-- a fullscreen window (SDL_video.c:2237) -- which LOVE's Android window
-- always is -- so the hint never reached a running activity (#1638).
-- apply() sets the hint for a later window, then goes over JNI for the live
-- one.  iOS needs only the hint.  Desktop and headless stubs no-op.

local Orientation = {}

Orientation.MODES = { "auto", "portrait", "landscape", "reverseLandscape" }
Orientation.DEFAULT = "auto"

local LABELS = {
  auto = "AUTO",
  portrait = "PORTRAIT",
  landscape = "LANDSCAPE",
  reverseLandscape = "REVERSE LANDSCAPE",
}

-- SDL_HINT_ORIENTATIONS values, exactly the names SDLActivity parses
-- (SDLActivity.java setOrientationBis): "Portrait", "PortraitUpsideDown",
-- "LandscapeLeft", "LandscapeRight".  Both landscapes together promote to
-- SENSOR_LANDSCAPE; LandscapeRight alone maps to REVERSE_LANDSCAPE.
local HINTS = {
  auto = "",
  portrait = "Portrait",
  landscape = "LandscapeLeft LandscapeRight",
  reverseLandscape = "LandscapeRight",
}

function Orientation.normalize(mode)
  if HINTS[mode] then return mode end
  return Orientation.DEFAULT
end

function Orientation.modeLabel(mode)
  return LABELS[Orientation.normalize(mode)]
end

function Orientation.isAndroid()
  if not love or not love.system or not love.system.getOS then return false end
  return love.system.getOS() == "Android"
end

function Orientation.isIOS()
  if not love or not love.system or not love.system.getOS then return false end
  return love.system.getOS() == "iOS"
end

function Orientation.cycle(mode, dir)
  local cur, idx = Orientation.normalize(mode), 1
  for i, m in ipairs(Orientation.MODES) do
    if m == cur then idx = i break end
  end
  local n = #Orientation.MODES
  return Orientation.MODES[(idx - 1 + (dir or 1)) % n + 1]
end

-- ActivityInfo constants, what setOrientationBis lands on per hint after
-- GameActivity's *_SENSOR -> *_USER remap (#716).
local REQUESTED = {
  auto = 13,
  portrait = 1,
  landscape = 11,
  reverseLandscape = 8,
}

-- The SDL2 C API this module needs.  cdef errors on redefinition, so run it
-- once and remember whether it took; ffi itself may be absent (plain Lua
-- test interpreters), hence the pcall'd require.
local cdefOk = nil
local function sdlFfi()
  local okFfi, ffi = pcall(require, "ffi")
  if not okFfi then return nil end
  if cdefOk == nil then
    cdefOk = pcall(ffi.cdef, [[
      typedef struct SDL_Window SDL_Window;
      typedef union { int32_t i; int64_t pad; } love_jvalue;
      int SDL_SetHint(const char *name, const char *value);
      SDL_Window *SDL_GL_GetCurrentWindow(void);
      void SDL_SetWindowResizable(SDL_Window *window, int resizable);
      void *SDL_AndroidGetJNIEnv(void);
      void *SDL_AndroidGetActivity(void);
    ]])
  end
  if not cdefOk then return nil end
  return ffi
end

-- Slot numbers in JNINativeInterface (jni.h).
local JNI_EXCEPTION_CLEAR = 17
local JNI_DELETE_LOCAL_REF = 23
local JNI_GET_OBJECT_CLASS = 31
local JNI_GET_METHOD_ID = 33
local JNI_CALL_VOID_METHOD_A = 63

-- What Android_JNI_SetOrientation reaches, called directly: the hint path
-- cannot re-run on a live fullscreen window (SDL_video.c:2237).
local function setRequestedOrientation(ffi, requested)
  local env = ffi.C.SDL_AndroidGetJNIEnv()
  if env == nil then return false end
  local activity = ffi.C.SDL_AndroidGetActivity()
  if activity == nil then return false end
  local fns = ffi.cast("void***", env)[0]
  local getObjectClass = ffi.cast("void *(*)(void *, void *)", fns[JNI_GET_OBJECT_CLASS])
  local getMethodID = ffi.cast(
    "void *(*)(void *, void *, const char *, const char *)", fns[JNI_GET_METHOD_ID])
  local callVoidMethodA = ffi.cast(
    "void (*)(void *, void *, void *, love_jvalue *)", fns[JNI_CALL_VOID_METHOD_A])
  local deleteLocalRef = ffi.cast("void (*)(void *, void *)", fns[JNI_DELETE_LOCAL_REF])
  local exceptionClear = ffi.cast("void (*)(void *)", fns[JNI_EXCEPTION_CLEAR])

  local ok = false
  local cls = getObjectClass(env, activity)
  if cls ~= nil then
    local mid = getMethodID(env, cls, "setRequestedOrientation", "(I)V")
    if mid ~= nil then
      local args = ffi.new("love_jvalue[1]")
      args[0].pad = 0
      args[0].i = requested
      callVoidMethodA(env, activity, mid, args)
      ok = true
    end
    exceptionClear(env)
    deleteLocalRef(env, cls)
  end
  deleteLocalRef(env, activity)
  return ok
end

-- Returns true only when the request actually landed, never unconditionally
-- as it once did (#1638).
function Orientation.apply(mode)
  local android = Orientation.isAndroid()
  if not (android or Orientation.isIOS()) then return false end
  local ffi = sdlFfi()
  if not ffi then return false end
  mode = Orientation.normalize(mode)
  local ok, reached = pcall(function()
    -- SDL_HINT_ORIENTATIONS is "SDL_IOS_ORIENTATIONS" in the SDL2 Android
    -- ships and "SDL_ORIENTATIONS" in the SDL3 the iOS app links; each
    -- engine ignores the other's key.
    ffi.C.SDL_SetHint("SDL_IOS_ORIENTATIONS", HINTS[mode])
    ffi.C.SDL_SetHint("SDL_ORIENTATIONS", HINTS[mode])
    -- On iOS the hint is the lock: UIKit re-asks on every rotation
    -- (SDL_uikitviewcontroller.m supportedInterfaceOrientations).
    if not android then return true end
    return setRequestedOrientation(ffi, REQUESTED[mode])
  end)
  return ok and reached == true
end

function Orientation.applyOptions(opts)
  return Orientation.apply(opts and opts.orientation)
end

return Orientation
