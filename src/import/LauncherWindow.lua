-- Launcher window preferences are separate from each game's video options.
local Window = {}
local state, dirty, quiet = nil, false, 0
local path = "launcher-window.cfg"

local function filesystem()
  return require("src.core.SaveData").portableFs() or love.filesystem
end

local function supported()
  return not require("src.core.VideoMode").fixedDisplay()
    and love.window and love.window.getMode and love.window.setMode
end
Window.supported = supported

local function size(value)
  local n = tonumber(value)
  return n and n == n and n >= 100 and n <= 32768 and math.floor(n) or nil
end

local function load()
  if state then return state end
  local fs = filesystem()
  local bytes = fs and fs.read and fs.read(path)
  local mode, w, h
  if type(bytes) == "string" then mode, w, h = bytes:match("^(%a+)\n(%d+)\n(%d+)") end
  local currentW, currentH = 960, 720
  if supported() then currentW, currentH = love.window.getMode() end
  state = { mode = mode == "fullscreen" and mode or "windowed",
    w = size(w) or currentW, h = size(h) or currentH }
  return state
end

function Window.mode()
  return load().mode
end

function Window.flush()
  if not dirty or not state then return end
  local fs = filesystem()
  if fs and fs.write and fs.write(path, ("%s\n%d\n%d\n"):format(state.mode, state.w, state.h)) then
    dirty, quiet = false, 0
  end
end

function Window.observe(dt)
  if not supported() or not state then return end
  local w, h, flags = love.window.getMode()
  if state.mode == "windowed" and not (flags or {}).fullscreen and size(w) and size(h) then
    if state.w ~= w or state.h ~= h then
      state.w, state.h, dirty, quiet = w, h, true, 0
    end
  end
  quiet = quiet + (dt or 0)
  if quiet >= 0.4 then Window.flush() end
end

function Window.apply(mode)
  if not supported() then return false end
  local st = load()
  local _, _, flags = love.window.getMode()
  flags = flags or {}
  local w, h = st.w, st.h
  mode = mode == "fullscreen" and mode or "windowed"
  if mode == "windowed" and love.window.getDesktopDimensions then
    local dw, dh = love.window.getDesktopDimensions(flags.display or 1)
    -- Leave room for the title bar and desktop dock/taskbar.
    w = math.min(w, math.max(100, math.floor(dw * 0.94)))
    h = math.min(h, math.max(100, math.floor(dh * 0.88)))
  end
  flags.fullscreen, flags.fullscreentype = mode == "fullscreen", "desktop"
  flags.resizable = true
  flags.minwidth = math.min(flags.minwidth or 0, w)
  flags.minheight = math.min(flags.minheight or 0, h)
  local ok = love.window.setMode(w, h, flags)
  if ok == false then return false end
  st.mode = mode
  if mode == "windowed" then st.w, st.h = w, h end
  dirty = true
  Window.flush()
  return true
end

function Window.toggle()
  Window.observe(0)
  return Window.apply(Window.mode() == "fullscreen" and "windowed" or "fullscreen")
end

function Window.activate()
  if supported() then Window.apply(Window.mode()) end
end

return Window
