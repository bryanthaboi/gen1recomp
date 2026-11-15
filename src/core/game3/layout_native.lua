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

function LayoutNative.fromDecoded(decoded, mapId, pair, sourceBlob)
  if pair == nil then
    error(("layout %s has no tileset pair"):format(tostring(mapId)), 2)
  end
  local self = setmetatable({
    mapId = mapId,
    pair = pair,
    width = decoded.width or 0,
    height = decoded.height or 0,
    trueWidth = decoded.trueWidth or decoded.width or 0,
    trueHeight = decoded.trueHeight or decoded.height or 0,
    borderWidth = decoded.borderWidth or 1,
    borderHeight = decoded.borderHeight or 1,
    borderMids = decoded.borderMids or {},
    cells = decoded.cells or {},
    overrides = {}, -- [cy*1024+cx] = { mid, coll, elev }
    _revision = 0,
    _workerSource = sourceBlob and { blob = sourceBlob, cells = decoded.cells,
      width = decoded.width, height = decoded.height, trueWidth = decoded.trueWidth or decoded.width,
      trueHeight = decoded.trueHeight or decoded.height },
  }, LayoutNative)
  return self
end

-- Imported base grids are immutable in the built-in runtime; edits live in
-- overrides. Custom/mod layouts use sampled snapshots instead of this path.
function LayoutNative:workerPacked()
  local s = self._workerSource
  if not s or self.cells ~= s.cells or self.width ~= s.width or self.height ~= s.height
      or self.trueWidth ~= s.trueWidth or self.trueHeight ~= s.trueHeight
      or self.cellAt ~= LayoutNative.cellAt or self.midAt ~= LayoutNative.midAt then return nil end
  local Assets = package.loaded["src.render.Assets"]
  if Assets and Assets.loader and #Assets.loader:overrideOrder() > 0 then return nil end
  local overrides, borders = {}, {}
  for k, row in pairs(self.overrides) do overrides[k] = { mid = row.mid } end
  for i = 1, self.borderWidth * self.borderHeight do borders[i] = self.borderMids[i] end
  return { blob = s.blob, off = 17 + (s.blob:byte(15) * s.blob:byte(16)) * 2,
    width = self.width, trueWidth = self.trueWidth, trueHeight = self.trueHeight,
    borderWidth = self.borderWidth, borderHeight = self.borderHeight, borderMids = borders, overrides = overrides }
end

local function missingCell(self, cx, cy)
  error(("layout %s has no cell at %d,%d"):format(tostring(self.mapId), cx, cy), 3)
end

local function borderMid(self, cx, cy)
  local bx, by = wrap_border(
    cx, cy, self.trueWidth or self.width, self.trueHeight or self.height, self.borderWidth, self.borderHeight)
  local mid = self.borderMids[by * self.borderWidth + bx + 1]
  if mid == nil then
    error(("layout %s has no border metatile at %d,%d"):format(tostring(self.mapId), bx, by), 3)
  end
  return mid
end

function LayoutNative:cellAt(cx, cy)
  local key = cy * 1024 + cx
  local ov = self.overrides[key]
  if ov then return ov end
  local tw = self.trueWidth or self.width
  local th = self.trueHeight or self.height
  if cx >= 0 and cy >= 0 and cx < tw and cy < th then
    return self.cells[cy * self.width + cx + 1] or missingCell(self, cx, cy)
  end
  return { mid = borderMid(self, cx, cy), coll = 0xff, elev = 0 }
end

local baseCellAt = LayoutNative.cellAt

local function field(self, cx, cy, name, border)
  if self.cellAt ~= baseCellAt then return self:cellAt(cx, cy)[name] end
  local ov = self.overrides[cy * 1024 + cx]
  if ov then return ov[name] end
  local tw = self.trueWidth or self.width
  local th = self.trueHeight or self.height
  if cx >= 0 and cy >= 0 and cx < tw and cy < th then
    return (self.cells[cy * self.width + cx + 1] or missingCell(self, cx, cy))[name]
  end
  if border ~= nil then return border end
  return borderMid(self, cx, cy)
end

function LayoutNative:midAt(cx, cy)
  return field(self, cx, cy, "mid", nil)
end

function LayoutNative:collAt(cx, cy)
  return field(self, cx, cy, "coll", 0xff)
end

function LayoutNative:elevAt(cx, cy)
  return field(self, cx, cy, "elev", 0)
end

--- Flat 1-based COLL_* array for Collision.bindMap.
function LayoutNative:collArray()
  local w = self.width
  local h = self.height
  local tw = self.trueWidth or w
  local th = self.trueHeight or h
  local n = w * h
  if n <= 0 then return nil end
  local out = {}
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      local i = cy * w + cx + 1
      if cx < tw and cy < th then
        local ov = self.overrides[cy * 1024 + cx]
        local c = self.cells[i]
        out[i] = (ov and ov.coll) or (c and c.coll) or 0xff
      else
        out[i] = 0xff
      end
    end
  end
  return out
end

function LayoutNative:applyOverride(x, y, mid, coll, elev)
  if type(mid) ~= "number" then
    error(("layout %s: metatile %s at %s,%s is not a number"):format(tostring(self.mapId), tostring(mid),
      tostring(x), tostring(y)), 2)
  end
  self._revision = (self._revision or 0) + 1
  x, y = tonumber(x) or 0, tonumber(y) or 0
  self.overrides[y * 1024 + x] = {
    mid = mid,
    coll = coll ~= nil and coll or 0xff,
    elev = elev or 0,
  }
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then
    if FieldView.invalidateLayoutCell then
      FieldView.invalidateLayoutCell(self, x, y)
    else
      FieldView._nativeDirty = true
    end
  end
end

local function markDirty()
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then
    FieldView._nativeDirty = true
  end
end

-- Re-sample only the written cells when there are few of them (per-frame
-- metatile animations); bulk writes rebuild the whole view.
local MAX_CELL_INVALIDATIONS = 64

local function markCellsDirty(layout, cells, n)
  local FieldView = package.loaded["src.core.game3.field_view"]
  if not FieldView then return end
  if not FieldView.invalidateLayoutCell or n > MAX_CELL_INVALIDATIONS then
    FieldView._nativeDirty = true
    return
  end
  for i = 1, n * 2, 2 do
    FieldView.invalidateLayoutCell(layout, cells[i], cells[i + 1])
  end
end

-- pokeemerald/src/battle_pyramid.c:1523
function LayoutNative:stamp(src, ox, oy)
  if type(src) ~= "table" or type(src.cells) ~= "table" then return 0 end
  ox, oy = tonumber(ox) or 0, tonumber(oy) or 0
  local sw = src.trueWidth or src.width or 0
  local sh = src.trueHeight or src.height or 0
  local n = 0
  for y = 0, sh - 1 do
    for x = 0, sw - 1 do
      local c = src.cells[y * src.width + x + 1]
      if c then
        if type(c.mid) ~= "number" then
          error(("layout %s: stamped cell %d,%d has no metatile"):format(tostring(self.mapId), x, y), 2)
        end
        self.overrides[(oy + y) * 1024 + ox + x] = {
          mid = c.mid, coll = c.coll ~= nil and c.coll or 0xff, elev = c.elev or 0,
        }
        n = n + 1
      end
    end
  end
  markDirty()
  if n > 0 then self._revision = (self._revision or 0) + 1 end
  return n
end

-- pokeemerald/src/fieldmap.c:357
function LayoutNative:setMetatiles(rows)
  local n = 0
  local cells = {}
  for _, r in ipairs(rows or {}) do
    local x, y = tonumber(r.x) or 0, tonumber(r.y) or 0
    local cur = self:cellAt(x, y)
    if r.mid ~= nil and type(r.mid) ~= "number" then
      error(("layout %s: metatile %s at %d,%d is not a number"):format(tostring(self.mapId), tostring(r.mid), x, y), 2)
    end
    self.overrides[y * 1024 + x] = {
      mid = r.mid or cur.mid,
      coll = r.coll ~= nil and r.coll or cur.coll,
      elev = r.elev ~= nil and r.elev or cur.elev or 0,
    }
    n = n + 1
    cells[n * 2 - 1], cells[n * 2] = x, y
  end
  if n > 0 then self._revision = (self._revision or 0) + 1; markCellsDirty(self, cells, n) end
  return n
end

function LayoutNative:clearOverrides()
  if next(self.overrides) then
    self._revision = (self._revision or 0) + 1
    self.overrides = {}
  end
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then
    FieldView._nativeDirty = true
  end
end

return LayoutNative
