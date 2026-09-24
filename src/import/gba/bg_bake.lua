-- Shared 4bpp BG baking for GBA extractors.
-- Turns ROM 4bpp tiles + a 32-wide tilemap + BGR555 palette banks into the
-- raw RGBA byte strings the UI loads via love.image.newImageData(w, h, "rgba8").

local BgBake = {}

--- BGR555 (15-bit) colour → 8-bit r, g, b.
function BgBake.bgr555ToRgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

--- Byte length of an LZ77 output array or binary string.
function BgBake.byteLen(buf)
  if type(buf) ~= "table" then return 0 end
  return buf._len or #buf
end

--- Write one 8x8 4bpp tile's palette indices into `out` (1-based, `stride` wide).
function BgBake.decodeTile4bpp(tileBytes, out, baseX, baseY, stride, hflip, vflip)
  for row = 0, 7 do
    local srcRow = vflip and (7 - row) or row
    for bx = 0, 3 do
      local byte = tileBytes[srcRow * 4 + bx + 1] or 0
      local p0 = byte % 16
      local p1 = math.floor(byte / 16) % 16
      local x0 = bx * 2
      local x1 = x0 + 1
      if hflip then
        x0, x1 = 7 - x0, 7 - x1
      end
      out[(baseY + row) * stride + (baseX + x0) + 1] = p0
      out[(baseY + row) * stride + (baseX + x1) + 1] = p1
    end
  end
end

--- Split a BGR555 palette block into 16-colour banks.
function BgBake.loadPalBanks(bytes, count)
  local banks = {}
  local n = count or math.floor(BgBake.byteLen(bytes) / 32)
  for b = 0, n - 1 do
    local colors = {}
    local off = b * 32
    for c = 0, 15 do
      local i = off + c * 2 + 1
      colors[c] = (bytes[i] or 0) + (bytes[i + 1] or 0) * 256
    end
    banks[b] = colors
  end
  return banks
end

--- Render a WxH RGBA image from 4bpp tiles + tilemap + palette banks.
-- Tilemap is 32 entries wide; entries carry tileId, hflip, vflip and palNum.
function BgBake.bakeBgRgba(gfx, palBanks, map, W, H)
  local tileCount = math.floor(BgBake.byteLen(gfx) / 32)
  local mapW = 32
  local indices, pals = {}, {}
  for i = 1, W * H do indices[i] = 0; pals[i] = 0 end

  local tilesH = math.min(32, math.floor(H / 8))
  local tilesW = math.min(32, math.floor(W / 8))
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local mi = (ty * mapW + tx) * 2 + 1
      local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
      local tileId = entry % 1024
      local hflip = math.floor(entry / 1024) % 2 == 1
      local vflip = math.floor(entry / 2048) % 2 == 1
      local palNum = math.floor(entry / 4096) % 16
      if tileId < tileCount then
        local tile = {}
        local base = tileId * 32
        for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
        local tmp = {}
        for i = 1, 64 do tmp[i] = 0 end
        BgBake.decodeTile4bpp(tile, tmp, 0, 0, 8, hflip, vflip)
        for row = 0, 7 do
          for col = 0, 7 do
            local px, py = tx * 8 + col, ty * 8 + row
            if px < W and py < H then
              local di = py * W + px + 1
              indices[di] = tmp[row * 8 + col + 1] or 0
              pals[di] = palNum
            end
          end
        end
      end
    end
  end

  local chunks = {}
  for i = 1, W * H do
    local bank = palBanks[pals[i]] or palBanks[0] or {}
    local col = bank[indices[i]] or 0
    local r, g, b = BgBake.bgr555ToRgb8(col)
    chunks[i] = string.char(r, g, b, 255)
  end
  return table.concat(chunks)
end

function BgBake.regionIndices(gfx, map, W, H, opts)
  opts = opts or {}
  local mapW = opts.mapW or 32
  local x0 = opts.x0 or 0
  local y0 = opts.y0 or 0
  local bankOffset = opts.bankOffset or 0
  local tileCount = math.floor(BgBake.byteLen(gfx) / 32)
  local mapLen = BgBake.byteLen(map)

  local indices, pals = {}, {}
  for i = 1, W * H do indices[i] = 0; pals[i] = -1 end

  local tileX = math.floor(x0 / 8)
  local tileY = math.floor(y0 / 8)
  local subX = x0 - tileX * 8
  local subY = y0 - tileY * 8
  local tilesW = math.ceil((W + subX) / 8)
  local tilesH = math.ceil((H + subY) / 8)
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local mi = ((tileY + ty) * mapW + (tileX + tx)) * 2 + 1
      if tileY + ty >= 0 and mi + 1 <= mapLen then
        local entry = (map[mi] or 0) + (map[mi + 1] or 0) * 256
        local tileId = entry % 1024
        local hflip = math.floor(entry / 1024) % 2 == 1
        local vflip = math.floor(entry / 2048) % 2 == 1
        local palNum = math.floor(entry / 4096) % 16 - bankOffset
        if tileId < tileCount then
          local tile = {}
          local base = tileId * 32
          for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
          local tmp = {}
          for i = 1, 64 do tmp[i] = 0 end
          BgBake.decodeTile4bpp(tile, tmp, 0, 0, 8, hflip, vflip)
          for row = 0, 7 do
            for col = 0, 7 do
              local px, py = tx * 8 + col - subX, ty * 8 + row - subY
              if px >= 0 and py >= 0 and px < W and py < H then
                local di = py * W + px + 1
                indices[di] = tmp[row * 8 + col + 1] or 0
                pals[di] = palNum
              end
            end
          end
        end
      end
    end
  end
  return indices, pals
end

function BgBake.bakeRegionIndices(gfx, map, W, H, opts)
  local indices, pals = BgBake.regionIndices(gfx, map, W, H, opts)
  local chunks = {}
  for i = 1, W * H do
    chunks[i] = string.char(pals[i] < 0 and 0 or indices[i])
  end
  return table.concat(chunks)
end

function BgBake.bakeRegionRgba(gfx, palBanks, map, W, H, opts)
  opts = opts or {}
  local alpha0 = opts.alpha0 and true or false
  local indices, pals = BgBake.regionIndices(gfx, map, W, H, opts)
  local chunks = {}
  for i = 1, W * H do
    local idx = indices[i]
    if pals[i] < 0 or (alpha0 and idx == 0) then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local bank = palBanks[pals[i]] or palBanks[0] or {}
      local r, g, b = BgBake.bgr555ToRgb8(bank[idx] or 0)
      chunks[i] = string.char(r, g, b, 255)
    end
  end
  return table.concat(chunks)
end

function BgBake.bakeSpriteRgba(gfx, bank, tileIndex, fw, fh, hflip, vflip)
  local tw, th = math.floor(fw / 8), math.floor(fh / 8)
  local pixels = {}
  for i = 1, fw * fh do pixels[i] = 0 end
  for ty = 0, th - 1 do
    for tx = 0, tw - 1 do
      local tile = {}
      local base = (tileIndex + ty * tw + tx) * 32
      for i = 1, 32 do tile[i] = gfx[base + i] or 0 end
      BgBake.decodeTile4bpp(tile, pixels, tx * 8, ty * 8, fw, false, false)
    end
  end
  local chunks = {}
  for y = 0, fh - 1 do
    for x = 0, fw - 1 do
      local sx = hflip and (fw - 1 - x) or x
      local sy = vflip and (fh - 1 - y) or y
      local idx = pixels[sy * fw + sx + 1] or 0
      if idx == 0 then
        chunks[#chunks + 1] = string.char(0, 0, 0, 0)
      else
        local r, g, b = BgBake.bgr555ToRgb8((bank or {})[idx] or 0)
        chunks[#chunks + 1] = string.char(r, g, b, 255)
      end
    end
  end
  return table.concat(chunks)
end

return BgBake
