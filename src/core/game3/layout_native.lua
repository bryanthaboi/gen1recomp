-- Native FRLG mid-grid layout handle (16px cells).

local LayoutNative = {}
LayoutNative.__index = LayoutNative

local function wrap_border(cx, cy, w, h, bw, bh)
  -- FRLG: out-of-bounds samples border tiled from (0,0).
  local bx = cx % bw
  if bx < 0 then bx = bx + bw end
  local by = cy % bh
  if by < 0 then by = by + bh end
  return bx, by
end

function LayoutNative.fromDecoded(decoded, mapId, pair)
  local self = setmetatable({
    mapId = mapId,
    pair = pair or "sevii_outdoor",
    width = decoded.width or 0,
    height = decoded.height or 0,
    trueWidth = decoded.trueWidth or decoded.width or 0,
    trueHeight = decoded.trueHeight or decoded.height or 0,
    borderWidth = decoded.borderWidth or 1,
    borderHeight = decoded.borderHeight or 1,
    borderMids = decoded.borderMids or { 0 },
    cells = decoded.cells or {},
    overrides = {}, -- [cy*1024+cx] = { mid, coll, elev }
  }, LayoutNative)
  return self
end

function LayoutNative:cellAt(cx, cy)
  local key = cy * 1024 + cx
  local ov = self.overrides[key]
  if ov then return ov end
  if cx >= 0 and cy >= 0 and cx < self.width and cy < self.height then
    return self.cells[cy * self.width + cx + 1]
      or { mid = 0, coll = 0xff, elev = 0 }
  end
  local bx, by = wrap_border(
    cx, cy, self.width, self.height, self.borderWidth, self.borderHeight)
  local mid = self.borderMids[by * self.borderWidth + bx + 1] or 0
  return { mid = mid, coll = 0xff, elev = 0 }
end

function LayoutNative:midAt(cx, cy)
  return self:cellAt(cx, cy).mid
end

function LayoutNative:collAt(cx, cy)
  return self:cellAt(cx, cy).coll
end

function LayoutNative:elevAt(cx, cy)
  return self:cellAt(cx, cy).elev
end

--- Flat 1-based COLL_* array for Collision.bindMap.
function LayoutNative:collArray()
  local n = self.width * self.height
  local out = {}
  for i = 1, n do
    local cx = (i - 1) % self.width
    local cy = math.floor((i - 1) / self.width)
    local ov = self.overrides[cy * 1024 + cx]
    local c = self.cells[i]
    out[i] = (ov and ov.coll) or (c and c.coll) or 0xff
  end
  return out
end

function LayoutNative:applyOverride(x, y, mid, coll, elev)
  x, y = tonumber(x) or 0, tonumber(y) or 0
  self.overrides[y * 1024 + x] = {
    mid = tonumber(mid) or 0,
    coll = coll ~= nil and coll or 0xff,
    elev = elev or 0,
  }
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then
    FieldView._nativeDirty = true
  end
end

function LayoutNative:clearOverrides()
  self.overrides = {}
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then
    FieldView._nativeDirty = true
  end
end

return LayoutNative
