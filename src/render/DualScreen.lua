-- Stacks the world pass (top) and UI pass (bottom) as two Game Boy screens
-- instead of compositing UI over world in one letterbox. Persisted as
-- save.options.dualScreen; mutually exclusive with survey zoom, tilt and the
-- wide battle layout. regions() returns framebuffer pixels, layout() LOVE units.

local DualScreen = {}

DualScreen.enabled = false
DualScreen.GAP = 8

function DualScreen.active()
  return DualScreen.enabled
end

function DualScreen.setEnabled(on)
  DualScreen.enabled = on and true or false
  return DualScreen.enabled
end

function DualScreen.toggle()
  return DualScreen.setEnabled(not DualScreen.enabled)
end

function DualScreen.applyOptions(opts)
  DualScreen.enabled = (opts and opts.dualScreen) and true or false
end

function DualScreen.label()
  return DualScreen.enabled and "ON" or "OFF"
end

function DualScreen.surfaceSize(w, h)
  w = w or 160
  h = h or 144
  return w, h * 2 + DualScreen.GAP
end

function DualScreen.regions(pw, ph, w, h)
  w = w or 160
  h = h or 144
  local surfW, surfH = DualScreen.surfaceSize(w, h)
  local scale = math.max(1, math.floor(math.min(pw / surfW, ph / surfH)))
  local boxW = w * scale
  local boxH = h * scale
  local gap = DualScreen.GAP * scale
  local ox = math.floor((pw - boxW) / 2)
  local top = math.floor((ph - (boxH * 2 + gap)) / 2)
  local world = { ox = ox, oy = top, w = boxW, h = boxH }
  local ui = { ox = ox, oy = top + boxH + gap, w = boxW, h = boxH }
  return scale, world, ui
end

function DualScreen.layout(pw, ph, dpiX, dpiY, w, h)
  dpiX = dpiX or 1
  dpiY = dpiY or 1
  local scale, worldPx, uiPx = DualScreen.regions(pw, ph, w, h)
  local sx, sy = scale / dpiX, scale / dpiY
  local function toUnits(r)
    return {
      ox = r.ox / dpiX, oy = r.oy / dpiY,
      w = r.w / dpiX, h = r.h / dpiY,
      sx = sx, sy = sy,
    }
  end
  return scale, toUnits(worldPx), toUnits(uiPx)
end

function DualScreen.screenAt(px, py, pw, ph, w, h)
  local _, world, ui = DualScreen.regions(pw, ph, w, h)
  local function inside(r)
    return px >= r.ox and px < r.ox + r.w and py >= r.oy and py < r.oy + r.h
  end
  if inside(world) then return "world" end
  if inside(ui) then return "ui" end
  return nil
end

return DualScreen
