-- Shared secondary-display facade. Android uses its native Presentation
-- bridge; process-capable desktop hosts fall back to a companion window.
-- Everything is guarded, so unsupported hosts keep the in-window layout.

local SecondScreen = {}
local C = nil
local ffi = nil
local desktop = nil
local nativePresent = false
local nativeTarget = false
local nativeScaling = false

local function log(msg)
  pcall(function() require("src.core.Logger").info("SecondScreen: %s", msg) end)
end

do
  local ok
  ok, ffi = pcall(require, "ffi")
  if not (ok and ffi) then
    log("ffi unavailable (not LuaJIT); second display disabled")
  else
    pcall(ffi.cdef, [[
      int love_android_secondary_ready();
      void love_android_push_secondary(const void *rgba, int w, int h);
      void love_android_secondary_enable(int on);
      int love_android_secondary_detected();
      int love_android_present_secondary(const void *rgba, int w, int h,
        unsigned int background, int cover);
      int love_android_present_secondary_scaled(const void *rgba, int w, int h,
        unsigned int background, int scaling);
      void love_android_secondary_target(int target);
      const char *love_android_poll_secondary_touch();
    ]])
    local okLib, lib = pcall(ffi.load, "love")
    if okLib and lib and pcall(function() return lib.love_android_secondary_ready end) then
      C = lib
      log("bridge linked via ffi.load('love')")
    elseif pcall(function() return ffi.C.love_android_secondary_ready end) then
      C = ffi.C
      log("bridge linked via default namespace")
    else
      log(("bridge symbols not found (ffi.load ok=%s); second display disabled")
        :format(tostring(okLib)))
    end
    if C then
      local okDetected, detected = pcall(function()
        return C.love_android_secondary_detected
      end)
      local okPresent, present = pcall(function()
        return C.love_android_present_secondary
      end)
      local okTarget, target = pcall(function()
        return C.love_android_secondary_target
      end)
      nativePresent = okDetected and detected ~= nil
        and okPresent and present ~= nil
      nativeTarget = okTarget and target ~= nil
      local okScaling, scaling = pcall(function()
        return C.love_android_present_secondary_scaled
      end)
      nativeScaling = nativePresent and okScaling and scaling ~= nil
    end
  end
end

if not C then
  local ok, backend = pcall(require, "src.render.DesktopScreen")
  if ok and backend and backend.usable and backend.usable() then
    desktop = backend
    log("desktop companion backend ready")
  end
end

function SecondScreen.usable()
  return C ~= nil or desktop ~= nil
end

function SecondScreen.available()
  if desktop then return desktop.available() end
  if not C then return false end
  local ok, r = pcall(C.love_android_secondary_ready)
  return ok and r ~= 0
end

-- A connected display is not necessarily the current Presentation yet. This
-- distinction lets a companion retry its first frame after hotplug/re-target.
function SecondScreen.detected()
  if desktop then return desktop.detected() end
  if nativePresent then
    local ok, r = pcall(C.love_android_secondary_detected)
    return ok and r ~= 0
  end
  return SecondScreen.available()
end

-- Explicit :fit and :integer preferences need the matching native APK.
function SecondScreen.scalingAvailable()
  return desktop ~= nil or nativeScaling
end

function SecondScreen.push(imageData, w, h, background, preference)
  if desktop then
    return desktop.push(imageData, w, h, background, preference)
  end
  if not C or not imageData then return false end
  if nativePresent and (background ~= nil or preference ~= nil) then
    if nativeTarget then
      local target = 0
      local destination = type(preference) == "string" and preference:match("^([^:]+)")
      if destination == "handheld" then
        target = 1
      elseif destination == "secondary" then
        target = 2
      end
      pcall(C.love_android_secondary_target, target)
    end
    local cover = type(preference) == "string"
      and preference:sub(-6) == ":cover"
    local policy = type(preference) == "string" and preference:match(":(fit)$") and 1
      or type(preference) == "string" and preference:match(":(integer)$") and 2
    if nativeScaling and policy then
      local ok, shown = pcall(C.love_android_present_secondary_scaled,
        imageData:getFFIPointer(), w, h, background or 0, policy)
      return ok and shown ~= 0
    end
    local ok, shown = pcall(C.love_android_present_secondary,
      imageData:getFFIPointer(), w, h, background or 0, cover and 1 or 0)
    return ok and shown ~= 0
  end
  return pcall(function()
    C.love_android_push_secondary(imageData:getFFIPointer(), w, h)
  end)
end

-- Returns the oldest queued secondary-display event as "action,x,y", where
-- coordinates are in the submitted frame's pixel space.
function SecondScreen.pollTouch()
  if desktop then return desktop.pollTouch() end
  if not C then return nil end
  local ok, event = pcall(function()
    return C.love_android_poll_secondary_touch()
  end)
  if not ok or event == nil or event == ffi.NULL then return nil end
  return ffi.string(event)
end

function SecondScreen.setEnabled(on)
  if desktop then return desktop.setEnabled(on) end
  if not C then return end
  pcall(function() C.love_android_secondary_enable(on and 1 or 0) end)
end

return SecondScreen
