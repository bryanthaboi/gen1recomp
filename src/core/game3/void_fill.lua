local VoidFill = {}

VoidFill.MODES = { "map", "trees", "water", "black" }
VoidFill.LABELS = { map = "MAP", trees = "TREES", water = "WATER", black = "BLACK" }

VoidFill.mode = "map"

function VoidFill.normalize(mode)
  for _, m in ipairs(VoidFill.MODES) do
    if m == mode then return m end
  end
  return "map"
end

function VoidFill.setMode(mode)
  mode = VoidFill.normalize(mode)
  if mode ~= VoidFill.mode then
    VoidFill.mode = mode
    VoidFill.invalidate()
  end
  return VoidFill.mode
end

function VoidFill.cycle(mode, dir)
  mode = VoidFill.normalize(mode)
  local n = #VoidFill.MODES
  local at = 1
  for i, m in ipairs(VoidFill.MODES) do
    if m == mode then at = i end
  end
  dir = (dir and dir < 0) and -1 or 1
  return VoidFill.MODES[((at - 1 + dir) % n) + 1]
end

function VoidFill.label(mode)
  return VoidFill.LABELS[VoidFill.normalize(mode)]
end

function VoidFill.invalidate()
  VoidFill._borders = {}
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then FieldView._nativeDirty = true end
end

VoidFill.PRIMARY = "general"
-- pokefirered/include/fieldmap.h:8
VoidFill.PRIMARY_MIDS = 640
VoidFill.SOURCES = { trees = "FR_PALLET_TOWN", water = "FR_CINNABAR_ISLAND" }
VoidFill._borders = {}

function VoidFill.primaryFor(pair)
  if type(pair) ~= "string" then return nil end
  local okV, Versions = pcall(require, "src.import.gba.versions")
  local spec = okV and Versions and Versions.TILESET_PAIRS and Versions.TILESET_PAIRS[pair]
  if spec and spec.primary then return spec.primary end
  return pair:match("^(.-)__")
end

function VoidFill.layoutFor(mapId)
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  if not game then return nil, true end
  local Map = package.loaded["src.core.game3.map"]
  if not (Map and Map.ensureMidLayout) then return nil, true end
  return Map.ensureMidLayout(game, mapId)
end

function VoidFill.borderFromLayout(layout)
  if type(layout) ~= "table" or type(layout.borderMids) ~= "table" then return nil end
  if VoidFill.primaryFor(layout.pair) ~= VoidFill.PRIMARY then return nil end
  local w, h = layout.borderWidth or 0, layout.borderHeight or 0
  if w < 1 or h < 1 then return nil end
  local mids = {}
  for i = 1, w * h do
    local mid = layout.borderMids[i]
    if type(mid) ~= "number" or mid < 0 or mid >= VoidFill.PRIMARY_MIDS then return nil end
    mids[i] = mid
  end
  return { w = w, h = h, mids = mids }
end

function VoidFill.borderFor(mode)
  mode = VoidFill.normalize(mode)
  local mapId = VoidFill.SOURCES[mode]
  if not mapId then return nil end
  local b = VoidFill._borders[mode]
  if b ~= nil then return b or nil end
  local layout, pending = VoidFill.layoutFor(mapId)
  if pending then return nil end
  b = VoidFill.borderFromLayout(layout)
  VoidFill._borders[mode] = b or false
  return b
end

-- pokefirered/src/fieldmap.c:39
function VoidFill.fillAt(mode, cx, cy, hasMid, primary)
  mode = VoidFill.normalize(mode or VoidFill.mode)
  if mode == "map" then return nil end
  if mode == "black" then return false end
  if primary ~= VoidFill.PRIMARY then return nil end
  local b = VoidFill.borderFor(mode)
  if not b then return nil end
  if hasMid then
    for _, mid in ipairs(b.mids) do
      if not hasMid(mid) then return nil end
    end
  end
  local bx = (cx or 0) % b.w
  local by = (cy or 0) % b.h
  return b.mids[by * b.w + bx + 1]
end

return VoidFill
