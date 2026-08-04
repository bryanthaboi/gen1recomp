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
-- and on boot via Game:applyOptions.  No-ops in headless stubs that lack
-- love.window.
--
-- MOBILE takes the other route to the same place.  There is no window to
-- resize -- the window IS the screen, and it rotates -- so the lock caps the
-- RENDER scale instead: the renderer draws the Game Boy screen at exactly N
-- physical pixels per GB pixel and centres it, and the rest of the display
-- stays black.  Same promise as the desktop lock (a GB pixel is exactly N
-- screen pixels, no more) reached by moving the picture rather than the
-- window.  This used to return false on the first line, so the row sat in
-- OPTIONS on Android and iOS doing nothing at all.
--
-- Scale, not size, is also what makes rotation free: Renderer:fitScale runs
-- every frame off the live drawable size, so portrait and landscape both get
-- the same locked scale with the bars falling wherever the screen is longer.

local FaithfulRes = {}

FaithfulRes.WIDTH, FaithfulRes.HEIGHT = 160, 144
FaithfulRes.LEVELS = { 0, 1, 2, 3, 4 }
FaithfulRes.DEFAULT = 0

-- mobile only: the locked scale in physical pixels per GB pixel, 0 for OFF.
-- Renderer:fitScale reads it through FaithfulRes.scaleCap.
FaithfulRes.mobileScale = 0

-- conf.lua's floor for the resizable desktop window, restored when the lock
-- is released.  1X and 2X are BELOW it, so the lock has to lower the minimum
-- as well as set the size or LOVE clamps the window back up.
FaithfulRes.MIN_W, FaithfulRes.MIN_H = 480, 360

-- whether this module currently owns the window size
FaithfulRes.locked = false

-- The highest level this display can actually show.
--
-- On desktop it is 4: the levels are window sizes, and 4X is the ceiling the
-- feature shipped with.  On mobile there is no window to size, so a fixed
-- 1..4 ladder is meaningless -- 4X is a quarter of a 1080p phone, and the
-- levels the panel could really use are not on the list at all.  Derive it
-- from the screen instead, so a 1080x2400 phone offers up to 6X and the top
-- of the ladder is the biggest exact-pixel picture it can draw.
--
-- OFF (0) is untouched by any of this and keeps doing exactly what it always
-- did: the renderer fits and letterboxes as usual.
function FaithfulRes.maxLevel()
  -- Mobile is ON or OFF.  A ladder of absolute multiples is a desktop idea --
  -- there it names a window size you can see.  On a phone the same number
  -- means a different fraction of every device, and every level below the top
  -- is just a smaller picture for no reason.  ON means one thing instead:
  -- lock the viewport to the Game Boy's 10:9 and size it to this screen.
  if FaithfulRes.isMobile() then return 1 end
  return 4
end

-- the selectable ladder for this display: OFF, then 1X..maxLevel
function FaithfulRes.levels()
  local out = { 0 }
  for i = 1, FaithfulRes.maxLevel() do out[#out + 1] = i end
  return out
end

function FaithfulRes.normalize(v)
  v = math.floor(tonumber(v) or FaithfulRes.DEFAULT)
  if v < 0 then return 0 end
  local max = FaithfulRes.maxLevel()
  if v > max then return max end
  return v
end

function FaithfulRes.label(v)
  v = FaithfulRes.normalize(v)
  if v == 0 then return "OFF" end
  -- mobile has one ON: the level is chosen from the display, not the player
  if FaithfulRes.isMobile() then return "ON" end
  return tostring(v) .. "X"
end

function FaithfulRes.cycle(v, dir)
  local levels = FaithfulRes.levels()
  local cur = 1
  for i, level in ipairs(levels) do
    if level == FaithfulRes.normalize(v) then cur = i break end
  end
  return levels[(cur - 1 + (dir or 1)) % #levels + 1]
end

function FaithfulRes.isMobile()
  -- POKEPORT_FORCE_MOBILE=1: take the mobile branch on a desktop build, so the
  -- scale lock can be seen and driven without a device.  The window is still
  -- resizable, which is the point -- drag it to a phone aspect, rotate it by
  -- dragging the other way, and the lock has to hold through both.  Only this
  -- module reads isMobile, so the override cannot leak into anything else.
  if os.getenv("POKEPORT_FORCE_MOBILE") == "1" then return true end
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
-- The largest WHOLE multiple of the Game Boy screen this display can hold.
-- Integer, never fractional: a GB pixel has to be the same number of screen
-- pixels in both axes or it is not pixel perfect, it is resampled.
--
-- The leftover is black bars, and on a tall phone there is a lot of it
-- vertically -- that is simply what a 10:9 screen looks like on a 9:20
-- display, and it is what an emulator shows too.
function FaithfulRes.deviceScale()
  local g = love and love.graphics
  if not (g and g.getPixelDimensions) then return 1 end
  local pw, ph = g.getPixelDimensions()
  if not pw or not ph or pw <= 0 or ph <= 0 then return 1 end
  return math.max(1, math.floor(math.min(pw / FaithfulRes.WIDTH,
                                         ph / FaithfulRes.HEIGHT)))
end

-- The scale the renderer must lock to, or nil for "fit the window as usual".
-- Only ever set on mobile: on desktop the window itself is the lock, so
-- fitScale already lands on N and this would be a second, redundant one.
--
-- Always the device maximum.  Anything less is a smaller picture for no gain,
-- which is how the first cut ended up showing a postage stamp on a 1080p
-- phone.
function FaithfulRes.scaleCap()
  if not FaithfulRes.locked then return nil end
  if not FaithfulRes.isMobile() then return nil end
  return FaithfulRes.deviceScale()
end

function FaithfulRes.apply(v)
  v = FaithfulRes.normalize(v)
  -- Mobile: lock the render scale instead of the window.  The scale itself
  -- comes from the display (deviceScale), not from v -- v only says whether
  -- the lock is on.  Nothing to restore on release: the renderer simply goes
  -- back to filling the display.
  if FaithfulRes.isMobile() then
    FaithfulRes.locked = v > 0
    FaithfulRes.mobileScale = FaithfulRes.locked and FaithfulRes.deviceScale() or 0
    return FaithfulRes.locked
  end
  if not love or not love.window or not love.window.setMode
     or not love.window.getMode then
    return false
  end
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
