-- Screen orientation lock, Android only (#592, #716).
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
-- SDL only re-reads the hint when the window is created or its resizable
-- flag changes (SDL_androidwindow.c: Android_CreateWindow /
-- Android_SetWindowResizable both call Android_JNI_SetOrientation).  LOVE
-- 11.5 exposes neither hints nor a resizable setter, so apply() goes through
-- the FFI to SDL's C API: set the hint, then pulse the window's resizable
-- flag off and back on -- each edge makes the Android backend recompute the
-- requested orientation, so a change from the launcher or the OPTION menu
-- takes hold immediately, and the flag ends where it started (conf.lua sets
-- resizable on mobile).  Everything is pcall-guarded: desktop, iOS (the
-- Info.plist governs there) and headless stubs make this a no-op.

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

function Orientation.cycle(mode, dir)
  local cur, idx = Orientation.normalize(mode), 1
  for i, m in ipairs(Orientation.MODES) do
    if m == cur then idx = i break end
  end
  local n = #Orientation.MODES
  return Orientation.MODES[(idx - 1 + (dir or 1)) % n + 1]
end

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
      int SDL_SetHint(const char *name, const char *value);
      SDL_Window *SDL_GL_GetCurrentWindow(void);
      void SDL_SetWindowResizable(SDL_Window *window, int resizable);
    ]])
  end
  if not cdefOk then return nil end
  return ffi
end

-- Push the mode into the live activity.  Returns true when the hint reached
-- SDL (the symbols resolved), false on any non-Android / stubbed platform.
function Orientation.apply(mode)
  if not Orientation.isAndroid() then return false end
  local ffi = sdlFfi()
  if not ffi then return false end
  mode = Orientation.normalize(mode)
  local ok = pcall(function()
    -- "SDL_IOS_ORIENTATIONS" is SDL_HINT_ORIENTATIONS's name (SDL_hints.h);
    -- despite the IOS in the string, the Android backend reads it too.
    ffi.C.SDL_SetHint("SDL_IOS_ORIENTATIONS", HINTS[mode])
    local win = ffi.C.SDL_GL_GetCurrentWindow()
    if win ~= nil then
      ffi.C.SDL_SetWindowResizable(win, 0)
      ffi.C.SDL_SetWindowResizable(win, 1)
    end
  end)
  return ok
end

function Orientation.applyOptions(opts)
  return Orientation.apply(opts and opts.orientation)
end

return Orientation
