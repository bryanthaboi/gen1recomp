-- Extract FRLG field-effect graphics directly from ROM.
-- Tall grass, Cut grass leaves, Rock smash rubble, Surf blob, Fly bird, Ripples.

local Versions = require("src.import.gba.versions")

local FieldEffectExtract = {}

FieldEffectExtract.FORMAT_VERSION = 2

local function log(msg)
  print("[gba/field_effects] " .. tostring(msg))
end

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

--- Decode one frame (4bpp tiles in row-major layout).
local function decode_frame(rom, off, fw, fh)
  local tw = math.floor(fw / 8)
  local th = math.floor(fh / 8)
  local pixels = {}
  for i = 1, fw * fh do pixels[i] = 0 end
  for ty = 0, th - 1 do
    for tx = 0, tw - 1 do
      local tileIdx = ty * tw + tx
      local tileOff = off + tileIdx * 32
      local ox, oy = tx * 8, ty * 8
      for y = 0, 7 do
        for x = 0, 7 do
          local byteIndex = tileOff + y * 4 + math.floor(x / 2)
          local b = rom:get(byteIndex)
          local idx = (x % 2 == 1) and math.floor(b / 16) % 16 or (b % 16)
          pixels[(oy + y) * fw + (ox + x) + 1] = idx
        end
      end
    end
  end
  return pixels
end

local function load_palette(rom, palOff)
  local rgb = {}
  for i = 0, 15 do
    local c = rom:u16(palOff + i * 2)
    local r, g, b = bgr555_to_rgb8(c)
    rgb[i] = { r, g, b }
  end
  return rgb
end

local function bake_rgba(rom, picOff, palOff, fw, fh, frames)
  local frameBytes = math.floor(fw / 8) * math.floor(fh / 8) * 32
  local w = fw
  local h = fh * frames
  local rgb = load_palette(rom, palOff)
  local bytes = {}
  for f = 0, frames - 1 do
    local pix = decode_frame(rom, picOff + f * frameBytes, fw, fh)
    for i = 1, fw * fh do
      local idx = pix[i] or 0
      local a = (idx == 0) and 0 or 255
      local c = rgb[idx] or { 0, 0, 0 }
      bytes[#bytes + 1] = string.char(c[1], c[2], c[3], a)
    end
  end
  return table.concat(bytes), w, h
end

-- pokefirered/src/field_effect.c:949
local function bake_indexed(rom, picOff, fw, fh, frames)
  local frameBytes = math.floor(fw / 8) * math.floor(fh / 8) * 32
  local bytes = {}
  for f = 0, frames - 1 do
    local pix = decode_frame(rom, picOff + f * frameBytes, fw, fh)
    for i = 1, fw * fh do
      bytes[#bytes + 1] = string.char(pix[i] or 0)
    end
  end
  return table.concat(bytes)
end

local function bake_pal(rom, palOff)
  local rgb = load_palette(rom, palOff)
  local bytes = {}
  for i = 0, 15 do
    local c = rgb[i] or { 0, 0, 0 }
    bytes[#bytes + 1] = string.char(c[1], c[2], c[3])
  end
  return table.concat(bytes)
end

-- pokefirered/src/field_effect.c:2738
local function bake_streaks(rom, spec)
  local cols, rows = 32, 10
  local w, h = cols * 8, rows * 8
  local rgb = load_palette(rom, spec.pal)
  local tiles = {}
  for t = 0, (spec.tiles or 16) - 1 do
    tiles[t] = decode_frame(rom, spec.gfx + t * 32, 8, 8)
  end
  local out = {}
  for i = 1, w * h do out[i] = "\0\0\0\0" end
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      local e = rom:u16(spec.tilemap + (r * cols + c) * 2)
      local tile = tiles[e % 1024]
      local hflip = math.floor(e / 1024) % 2 == 1
      local vflip = math.floor(e / 2048) % 2 == 1
      if tile then
        for y = 0, 7 do
          for x = 0, 7 do
            local sx = hflip and (7 - x) or x
            local sy = vflip and (7 - y) or y
            local idx = tile[sy * 8 + sx + 1] or 0
            if idx ~= 0 then
              local col = rgb[idx]
              out[(r * 8 + y) * w + c * 8 + x + 1] = string.char(col[1], col[2], col[3], 255)
            end
          end
        end
      end
    end
  end
  return table.concat(out), w, h
end

function FieldEffectExtract.writeExtract(rom, cache, root, version)
  root = root or "data/generated/gba"
  version = version or {}
  if not rom or not cache then return nil, "rom and cache required" end

  local effects = Versions.FIELD_EFFECTS or {}
  local rel = root .. "/field_effects"
  local results = {}

  for name, spec in pairs(effects) do
    local picOff = spec.pic
    local palOff = spec.pal
    if picOff and palOff then
      local fw = spec.w or 16
      local fh = spec.h or 16
      local frames = spec.frames or 1
      local rgba, w, h = bake_rgba(rom, picOff, palOff, fw, fh, frames)
      cache:write(rel .. "/" .. name .. ".rgba", rgba)
      if spec.indexed then
        cache:write(rel .. "/" .. name .. ".idx", bake_indexed(rom, picOff, fw, fh, frames))
        cache:write(rel .. "/" .. name .. ".pal", bake_pal(rom, palOff))
      end
      cache:write(rel .. "/" .. name .. ".meta", string.format(
        "return { w = %d, h = %d, frames = %d, fw = %d, fh = %d, indexed = %s, format = %d }\n",
        w, h, frames, fw, fh, spec.indexed and "true" or "false",
        FieldEffectExtract.FORMAT_VERSION))
      log(string.format("%s %dx%d (%d frames, %dx%d) → %s", name, w, h, frames, fw, fh, rel))
      results[name] = { path = rel .. "/" .. name .. ".rgba", w = w, h = h, frames = frames }
    end
  end

  for kind, spec in pairs(Versions.FIELD_MOVE_STREAKS or {}) do
    local name = "field_move_streaks_" .. kind
    local rgba, w, h = bake_streaks(rom, spec)
    cache:write(rel .. "/" .. name .. ".rgba", rgba)
    cache:write(rel .. "/" .. name .. ".meta", string.format(
      "return { w = %d, h = %d, frames = 1, fw = %d, fh = %d, indexed = false, format = %d }\n",
      w, h, w, h, FieldEffectExtract.FORMAT_VERSION))
    log(string.format("%s %dx%d → %s", name, w, h, rel))
    results[name] = { path = rel .. "/" .. name .. ".rgba", w = w, h = h, frames = 1 }
  end

  return results
end

return FieldEffectExtract
