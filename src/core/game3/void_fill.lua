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

VoidFill._cache = {}

function VoidFill.invalidate()
  VoidFill._cache = {}
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then FieldView._nativeDirty = true end
end

local function permissions()
  local ok, P = pcall(require, "src.world.gen2.Permissions")
  return ok and P or nil
end

local function tally(layout, want, ring)
  local P = permissions()
  local w, h = layout.width or 0, layout.height or 0
  if w < 1 or h < 1 then return nil end
  local counts, best, bestN = {}, nil, 0
  for y = 0, h - 1 do
    local edgeRow = ring and (y < ring or y >= h - ring)
    for x = 0, w - 1 do
      local onEdge = edgeRow or (ring and (x < ring or x >= w - ring))
      if not ring or onEdge then
        local c = layout.cells[y * w + x + 1]
        local coll = c and c.coll
        if coll then
          local hit
          if want == "water" then
            hit = P and P.isWater and P.isWater(coll) or (not P and coll == 0x29)
          else
            hit = P and P.isWall and P.isWall(coll) or (not P and coll == 0x01)
          end
          if hit then
            local mid = c.mid or 0
            local k = (counts[mid] or 0) + 1
            counts[mid] = k
            if k > bestN then best, bestN = mid, k end
          end
        end
      end
    end
  end
  if bestN < 4 then return nil end
  return best
end

local function scan(layout, want)
  if not (layout and layout.cells) then return nil end
  local w, h = layout.width or 0, layout.height or 0
  if w * h > 65536 then return nil end
  return tally(layout, want, 3) or tally(layout, want, nil)
end

function VoidFill.midFor(mapDef, mode)
  mode = VoidFill.normalize(mode or VoidFill.mode)
  if mode == "map" then return nil end
  if mode == "black" then return false end
  local layout = mapDef and mapDef.midLayout
  if not layout then return nil end
  local key = tostring(layout.mapId or mapDef.id or mapDef.name or layout) .. ":" .. mode
  local hit = VoidFill._cache[key]
  if hit ~= nil then
    if hit == false then return nil end
    return hit
  end
  local mid = scan(layout, mode)
  VoidFill._cache[key] = mid or false
  return mid
end

return VoidFill
