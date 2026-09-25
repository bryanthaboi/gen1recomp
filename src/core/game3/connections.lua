local Connections = {}

local CARDINAL = {
  north = "north", south = "south", west = "west", east = "east",
  up = "north", down = "south", left = "west", right = "east",
}

function Connections.cardinal(dir)
  return CARDINAL[dir]
end

local function entry(dir, c)
  local d = CARDINAL[dir]
  local map = type(c) == "table" and (c.map or c.mapId) or c
  if not d or type(map) ~= "string" then return nil end
  return { dir = d, map = map, offset = type(c) == "table" and tonumber(c.offset) or 0 }
end

function Connections.each(def)
  local out = {}
  local conns = def and def.connections
  if type(conns) ~= "table" then return out end
  local n = #conns
  for i = 1, n do
    local c = conns[i]
    local e = type(c) == "table" and entry(c.dir or c.direction, c)
    if e then out[#out + 1] = e end
  end
  local keyed = {}
  for k, c in pairs(conns) do
    if type(k) == "string" then
      local e = entry(k, c)
      if e then keyed[#keyed + 1] = { k = k, e = e } end
    end
  end
  table.sort(keyed, function(a, b) return a.k < b.k end)
  for _, kv in ipairs(keyed) do out[#out + 1] = kv.e end
  return out
end

function Connections.sizeOf(def)
  local L = def and def.midLayout
  if L and L.width and L.height then return L.width, L.height end
  return (tonumber(def and def.width) or 0) * 2, (tonumber(def and def.height) or 0) * 2
end

local function vertical(dir)
  return dir == "north" or dir == "south"
end

-- pokefirered/src/fieldmap.c:724
local function coordInIncoming(coord, srcMax, destMax, offset)
  local lo = math.max(offset, 0)
  if destMax + offset < srcMax then srcMax = destMax + offset end
  return lo <= coord and coord <= srcMax
end

-- pokefirered/src/fieldmap.c:686
function Connections.incoming(def, dir, x, y, destDefOf)
  dir = CARDINAL[dir]
  if not dir then return nil end
  local srcW, srcH = Connections.sizeOf(def)
  for _, c in ipairs(Connections.each(def)) do
    if c.dir == dir then
      local destDef = destDefOf(c.map)
      if destDef then
        local w, h = Connections.sizeOf(destDef)
        local hit
        if vertical(dir) then
          hit = coordInIncoming(x, srcW, w, c.offset)
        else
          hit = coordInIncoming(y, srcH, h, c.offset)
        end
        if hit then return c, destDef end
      end
    end
  end
  return nil
end

-- pokefirered/src/fieldmap.c:745
function Connections.localPos(n, x, y, srcW, srcH)
  local w, h = Connections.sizeOf(n.def)
  local off = tonumber(n.offset) or 0
  local lx, ly
  if n.dir == "north" then
    lx, ly = x - off, h + y
  elseif n.dir == "south" then
    lx, ly = x - off, y - srcH
  elseif n.dir == "west" then
    lx, ly = w + x, y - off
  elseif n.dir == "east" then
    lx, ly = x - srcW, y - off
  else
    return nil
  end
  local along = vertical(n.dir) and lx or ly
  local span = vertical(n.dir) and w or h
  if along < 0 or along >= span then return nil end
  return lx, ly
end

-- pokefirered/src/fieldmap.c:761
function Connections.atPos(list, x, y, srcW, srcH)
  for _, n in ipairs(list or {}) do
    local dir = n.dir
    local skip = (dir == "north" and y >= 0) or (dir == "south" and y < srcH)
      or (dir == "west" and x >= 0) or (dir == "east" and x < srcW)
    if not skip and n.def then
      local lx, ly = Connections.localPos(n, x, y, srcW, srcH)
      if lx then return n, lx, ly end
    end
  end
  return nil
end

return Connections
