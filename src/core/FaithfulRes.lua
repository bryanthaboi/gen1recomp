-- Faithful resolution: lock the window to an exact integer multiple of the
-- Game Boy's 160x144 screen, 1X through 4X.
--
-- At any other window size the renderer picks the largest integer scale that
-- fits and letterboxes the remainder (Renderer:fitScale), so the game is
-- already crisp -- what it is not is *exact*: there are bars, and at a wide
-- window a lot of them.  Locking the window to 160*N x 144*N removes the
-- letterbox entirely, so the surface is the Game Boy screen and nothing else.
--
-- Persisted as save.options.faithfulRes (0 = OFF).  Applied from OptionsMenu
-- and on boot via Game:applyOptions.  No-ops on mobile and in headless stubs
-- that lack love.window.

local FaithfulRes = {}

FaithfulRes.WIDTH, FaithfulRes.HEIGHT = 160, 144
FaithfulRes.LEVELS = { 0, 1, 2, 3, 4 }
FaithfulRes.DEFAULT = 0

-- conf.lua's floor for the resizable desktop window, restored when the lock
-- is released.  1X and 2X are BELOW it, so the lock has to lower the minimum
-- as well as set the size or LOVE clamps the window back up.
FaithfulRes.MIN_W, FaithfulRes.MIN_H = 480, 360

-- whether this module currently owns the window size
FaithfulRes.locked = false

function FaithfulRes.normalize(v)
  v = math.floor(tonumber(v) or FaithfulRes.DEFAULT)
  if v < 0 then return 0 end
  if v > 4 then return 4 end
  return v
end

function FaithfulRes.label(v)
  v = FaithfulRes.normalize(v)
  if v == 0 then return "OFF" end
  return tostring(v) .. "X"
end

function FaithfulRes.cycle(v, dir)
  local levels = FaithfulRes.LEVELS
  local cur = 1
  for i, level in ipairs(levels) do
    if level == FaithfulRes.normalize(v) then cur = i break end
  end
  return levels[(cur - 1 + (dir or 1)) % #levels + 1]
end

function FaithfulRes.isMobile()
  if not love or not love.system or not love.system.getOS then return false end
  local osName = love.system.getOS()
  return osName == "Android" or osName == "iOS"
end

-- Physical pixels per LOVE unit for the CURRENT window.
--
-- Deliberately NOT love.window.getDPIScale: that reports the display's
-- scaling factor even when the window is not high-DPI aware, and conf.lua
-- only sets t.window.highdpi on mobile.  On a plain desktop window a unit IS
-- a pixel, so dividing by the display scale just shrinks the window -- at
-- 125% scaling a 2X request became 256x230 pixels, which Renderer:fitScale
-- floors to 1, and 4X became 512x461, which floors to 3.  That is exactly
-- the "2X renders at 1X, 4X renders at 3X" this shipped with.
--
-- Measuring the ratio the window actually reports is correct in both worlds:
-- 1 on a plain desktop window, the real scale on a high-DPI one.
local function pixelsPerUnit()
  local g = love and love.graphics
  if not (g and g.getDimensions and g.getPixelDimensions) then return 1 end
  local uw = tonumber((g.getDimensions()))
  local pw = tonumber((g.getPixelDimensions()))
  if not uw or not pw or uw <= 0 or pw <= 0 then return 1 end
  return pw / uw
end

-- The window size in LOVE UNITS that puts 160*v x 144*v PHYSICAL pixels on
-- screen.
function FaithfulRes.size(v)
  v = FaithfulRes.normalize(v)
  if v == 0 then return nil end
  local ratio = pixelsPerUnit()
  return math.floor(FaithfulRes.WIDTH * v / ratio + 0.5),
         math.floor(FaithfulRes.HEIGHT * v / ratio + 0.5)
end

-- Push the lock into the live window.  Returns true when the window is
-- locked afterwards.
function FaithfulRes.apply(v)
  if FaithfulRes.isMobile() then return false end
  if not love or not love.window or not love.window.setMode
     or not love.window.getMode then
    return false
  end
  v = FaithfulRes.normalize(v)
  local curW, curH, flags = love.window.getMode()
  flags = flags or {}

  if v == 0 then
    -- only touch the window if we were the one holding it: an OFF setting on
    -- boot must not resize a window the player sized themselves
    if not FaithfulRes.locked then return false end
    flags.resizable = true
    flags.minwidth, flags.minheight = FaithfulRes.MIN_W, FaithfulRes.MIN_H
    love.window.setMode(curW, curH, flags)
    FaithfulRes.locked = false
    return false
  end

  local w, h = FaithfulRes.size(v)
  -- An exact size and a desktop-fullscreen mode cannot both hold.  The lock
  -- is the more specific request, so it wins and drops fullscreen; VIDEO MODE
  -- reads BORDERLESS until the player changes it, which then releases this.
  flags.fullscreen = false
  -- resizing by hand would silently break the lock, and nothing re-applies it
  -- (there is no love.resize handler -- the renderer re-reads the size every
  -- frame), so the window is fixed while locked rather than left draggable.
  flags.resizable = false
  flags.minwidth, flags.minheight = w, h
  love.window.setMode(w, h, flags)
  FaithfulRes.locked = true
  return true
end

function FaithfulRes.applyOptions(opts)
  return FaithfulRes.apply(opts and opts.faithfulRes)
end

return FaithfulRes
