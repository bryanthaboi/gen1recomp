-- Turns an opaque map crop into one sprite-like card. Ground is identified as
-- the light half of the crop's palette and flooded in from the border. Of the
-- remaining outlined islands, the component overlapping the collision seed is
-- the structure represented by the billboard.

local BillboardCutout = {}

local function luma(r, g, b)
  return r * 0.2126 + g * 0.7152 + b * 0.0722
end

local function componentMask(data, seed)
  if not (data and type(data.getDimensions) == "function"
      and type(data.getPixel) == "function"
      and type(data.setPixel) == "function") then
    return nil
  end

  local w, h = data:getDimensions()
  if not (w and h and w > 0 and h > 0) then return nil end

  local pixels, minL, maxL = {}, math.huge, -math.huge
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local r, g, b, a = data:getPixel(x, y)
      local i = y * w + x + 1
      local value = luma(r, g, b)
      pixels[i] = { r, g, b, a, value }
      if a > 0 then
        if value < minL then minL = value end
        if value > maxL then maxL = value end
      end
    end
  end
  if minL == math.huge then return nil end

  local light = minL + (maxL - minL) * 0.5
  local outside, queue, head = {}, {}, 1
  local function markOutside(x, y)
    if x < 0 or y < 0 or x >= w or y >= h then return end
    local i = y * w + x + 1
    local p = pixels[i]
    if outside[i] or p[4] <= 0 or p[5] < light then return end
    outside[i] = true
    queue[#queue + 1] = i
  end

  for x = 0, w - 1 do markOutside(x, 0); markOutside(x, h - 1) end
  for y = 0, h - 1 do markOutside(0, y); markOutside(w - 1, y) end
  while head <= #queue do
    local i = queue[head]
    head = head + 1
    local z = i - 1
    local x, y = z % w, math.floor(z / w)
    markOutside(x - 1, y); markOutside(x + 1, y)
    markOutside(x, y - 1); markOutside(x, y + 1)
  end

  local seedX = type(seed) == "table" and tonumber(seed.x) or nil
  local seedY = type(seed) == "table" and tonumber(seed.y) or nil
  local seedW = type(seed) == "table" and tonumber(seed.width) or nil
  local seedH = type(seed) == "table" and tonumber(seed.height) or nil
  local hasSeed = seedX and seedY and seedW and seedH
    and seedW > 0 and seedH > 0
  local function inSeed(x, y)
    return hasSeed and x >= seedX and y >= seedY
      and x < seedX + seedW and y < seedY + seedH
  end

  local seen, best, bestSize, bestOverlap = {}, nil, 0, -1
  local function candidate(i)
    return pixels[i][4] > 0 and not outside[i]
  end
  for start = 1, w * h do
    if candidate(start) and not seen[start] then
      local component, pending, nextIndex = {}, { start }, 1
      seen[start] = true
      local overlap = 0
      while nextIndex <= #pending do
        local i = pending[nextIndex]
        nextIndex = nextIndex + 1
        component[#component + 1] = i
        local z = i - 1
        local x, y = z % w, math.floor(z / w)
        if inSeed(x, y) then overlap = overlap + 1 end
        local function visit(nx, ny)
          if nx < 0 or ny < 0 or nx >= w or ny >= h then return end
          local ni = ny * w + nx + 1
          if candidate(ni) and not seen[ni] then
            seen[ni] = true
            pending[#pending + 1] = ni
          end
        end
        visit(x - 1, y); visit(x + 1, y)
        visit(x, y - 1); visit(x, y + 1)
      end
      if overlap > bestOverlap
          or (overlap == bestOverlap and #component > bestSize) then
        best, bestSize, bestOverlap = component, #component, overlap
      end
    end
  end

  local keep = {}
  for _, i in ipairs(best or {}) do keep[i] = true end
  return pixels, keep, bestSize, w, h
end

function BillboardCutout.mask(data, seed)
  local pixels, keep, bestSize, w, h = componentMask(data, seed)
  if not pixels then return false end
  for i, p in ipairs(pixels) do
    local z = i - 1
    local x, y = z % w, math.floor(z / w)
    data:setPixel(x, y, p[1], p[2], p[3], keep[i] and p[4] or 0)
  end
  return bestSize > 0
end

-- Preserve the captured map source while erasing only the selected structure.
-- Drawing this data with LOVE's replace blend mode clears those pixels from
-- the ground canvas while leaving nearby structures and terrain unchanged.
function BillboardCutout.erase(data, seed)
  local pixels, keep, bestSize, w, h = componentMask(data, seed)
  if not pixels then return false end
  for i, p in ipairs(pixels) do
    local z = i - 1
    local x, y = z % w, math.floor(z / w)
    data:setPixel(x, y, p[1], p[2], p[3], keep[i] and 0 or p[4])
  end
  return bestSize > 0
end

return BillboardCutout
