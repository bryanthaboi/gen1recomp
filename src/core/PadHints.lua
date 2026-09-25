local PadHints = {}

PadHints.BACKGROUND_HINT = "SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"

function PadHints.apply(osName, ffiLike, getenv)
  if osName ~= "Windows" then return false end
  getenv = getenv or os.getenv
  local okEnv, flag = pcall(getenv, "POKEPORT_PAD_BACKGROUND")
  if okEnv and flag == "0" then return false end
  local ok, set = pcall(function()
    local ffi = ffiLike or require("ffi")
    pcall(ffi.cdef, "int SDL_SetHint(const char *name, const char *value);")
    local sdl = ffi.load("SDL2")
    return sdl.SDL_SetHint(PadHints.BACKGROUND_HINT, "1")
  end)
  return ok and set ~= nil and set ~= 0
end

function PadHints.windowMinimized()
  local win = love and love.window
  if not win then return false end
  if win.isMinimized then
    local ok, v = pcall(win.isMinimized)
    if ok then return v == true end
  end
  if win.isVisible then
    local ok, v = pcall(win.isVisible)
    if ok then return v == false end
  end
  return false
end

function PadHints.hasFocus()
  local win = love and love.window
  if not (win and win.hasFocus) then return nil end
  local ok, v = pcall(win.hasFocus)
  if ok then return v end
  return nil
end

local fgReady = nil

function PadHints.foreground(osName, ffiLike)
  if osName ~= "Windows" then return nil end
  if fgReady == false then return nil end
  local ok, owner = pcall(function()
    local ffi = ffiLike or require("ffi")
    if not fgReady then
      pcall(ffi.cdef, [[
        void *GetForegroundWindow(void);
        unsigned long GetWindowThreadProcessId(void *hwnd, unsigned long *pid);
        unsigned long GetCurrentProcessId(void);
      ]])
      fgReady = true
    end
    local hwnd = ffi.C.GetForegroundWindow()
    if hwnd == nil then return "none" end
    local pid = ffi.new("unsigned long[1]")
    ffi.C.GetWindowThreadProcessId(hwnd, pid)
    return pid[0] == ffi.C.GetCurrentProcessId() and "ours" or "other"
  end)
  if not ok then
    fgReady = false
    return nil
  end
  return owner
end

function PadHints._resetForTests()
  fgReady = nil
end

return PadHints
