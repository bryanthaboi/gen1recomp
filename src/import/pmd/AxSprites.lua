local Ax = {}
local floor = math.floor
local SHAPES = {
  { {8,8}, {16,16}, {32,32}, {64,64} },
  { {16,8}, {32,8}, {32,16}, {64,32} },
  { {8,16}, {8,32}, {16,32}, {32,64} },
}

local function reader(rom)
  local function check(p, n)
    assert(p >= 0 and p % 1 == 0 and p + n <= #rom, "PMD sprite data is truncated")
  end
  local function u8(p) check(p, 1); return rom:byte(p + 1) end
  local function u16(p) return u8(p) + u8(p + 1) * 256 end
  local function s16(p) local v = u16(p); return v < 32768 and v or v - 65536 end
  local function u32(p) return u16(p) + u16(p + 2) * 65536 end
  local function ptr(p)
    local v = u32(p) - 0x08000000
    check(v, 1)
    return v
  end
  return u8, u16, s16, u32, ptr, check
end

function Ax.read(rom, archive, poseCount, paletteOffset, paletteId)
  local u8, u16, s16, u32, ptr, check = reader(rom)
  assert(rom:sub(archive + 1, archive + 4) == "SIRO", "expected a PMD SIRO sprite")
  assert(poseCount > 0 and poseCount <= 1024, "invalid PMD pose count")
  assert(paletteId >= 0 and paletteId < 14, "invalid PMD palette")
  local main = ptr(archive + 4)
  local poses, animations, sprites = ptr(main), ptr(main + 4), ptr(main + 12)
  local animCount = u32(main + 8)
  assert(animCount > 0 and animCount <= 128, "invalid PMD animation count")
  local out = { poses = {}, palettes = {}, animations = {}, sequences = {},
    minX = 0, minY = 0, maxX = 1, maxY = 1 }
  for row = 0, 13 do
    out.palettes[row] = {}
    for i = 0, 15 do
      local p = paletteOffset + row * 64 + i * 4
      out.palettes[row][i] = { u8(p), u8(p + 1), u8(p + 2) }
    end
  end
  out.palette = out.palettes[paletteId]
  local chunks = {}
  local function spriteBytes(id)
    if chunks[id] then return chunks[id] end
    assert(id >= 0 and id < 4096, "invalid PMD sprite index")
    local p, parts, total = ptr(sprites + id * 4), {}, 0
    for _ = 1, 1024 do
      local size = u32(p + 4)
      if size == 0 then
        chunks[id] = table.concat(parts)
        return chunks[id]
      end
      total = total + size
      assert(size % 32 == 0 and total <= 32768, "invalid PMD tile stream")
      if u32(p) == 0 then
        parts[#parts + 1] = string.rep("\0", size)
      else
        local src = ptr(p); check(src, size)
        parts[#parts + 1] = rom:sub(src + 1, src + size)
      end
      p = p + 8
    end
    error("unterminated PMD tile stream")
  end
  for index = 0, poseCount - 1 do
    local p, parts, streams = ptr(poses + index * 4), {}, {}
    local terminated = false
    for _ = 1, 128 do
      local sprite = s16(p)
      if sprite == -1 and u16(p + 2) == 65535 then terminated = true; break end
      assert(sprite >= -1, "invalid PMD pose sprite")
      if sprite >= 0 then streams[#streams + 1] = spriteBytes(sprite) end
      local f1, f2, f3 = u16(p + 4), u16(p + 6), u16(p + 8)
      local shape = SHAPES[floor(f1 / 16384) + 1]
      assert(shape and floor(f1 / 8192) % 2 == 0, "unsupported PMD OAM format")
      local size = shape[floor(f2 / 16384) + 1]
      local part = { x = f2 % 512 - 256, y = f1 % 1024 - 512,
        w = size[1], h = size[2], tile = f3 % 1024,
        palette = floor(f2 / 1024) % 2 == 1 and floor(f3 / 4096) or paletteId,
        depth = u8(p + 3) < 128 and u8(p + 3) or u8(p + 3) - 256,
        order = #parts + 1,
        flipX = floor(f2 / 4096) % 2 == 1, flipY = floor(f2 / 8192) % 2 == 1 }
      assert(out.palettes[part.palette], "invalid PMD piece palette")
      parts[#parts + 1] = part
      out.minX, out.minY = math.min(out.minX, part.x), math.min(out.minY, part.y)
      out.maxX, out.maxY = math.max(out.maxX, part.x + part.w), math.max(out.maxY, part.y + part.h)
      p = p + 10
    end
    assert(terminated, "unterminated PMD pose")
    local tiles = table.concat(streams)
    for _, part in ipairs(parts) do
      assert(part.tile * 32 + part.w * part.h / 2 <= #tiles, "PMD pose exceeds its tiles")
    end
    table.sort(parts, function(a, b)
      if a.depth ~= b.depth then return a.depth > b.depth end
      return a.order < b.order
    end)
    out.poses[index + 1] = { parts = parts, tiles = tiles }
  end
  local sequenceIds = {}
  for anim = 0, animCount - 1 do
    local directions, group = {}, ptr(animations + anim * 4)
    for direction = 0, 7 do
      local p = ptr(group + direction * 4)
      local id = sequenceIds[p]
      if not id then
        id = #out.sequences + 1
        sequenceIds[p] = id
        local sequence, terminated = {}, false
        for _ = 1, 1024 do
          local duration = u8(p)
          if duration == 0 then terminated = true; break end
          local pose = s16(p + 2)
          assert(pose >= 0 and pose < poseCount, "PMD animation references an invalid pose")
          sequence[#sequence + 1] = { pose + 1, duration, s16(p + 4), s16(p + 6),
            s16(p + 8), s16(p + 10), u8(p + 1) }
          p = p + 12
        end
        assert(terminated, "unterminated PMD animation")
        out.sequences[id] = sequence
      end
      directions[direction + 1] = id
    end
    out.animations[anim + 1] = directions
  end
  out.frameWidth, out.frameHeight = out.maxX - out.minX, out.maxY - out.minY
  assert(out.frameWidth <= 512 and out.frameHeight <= 512, "PMD pose bounds are too large")
  return out
end

function Ax.drawPose(pose, putPixel)
  for i = #pose.parts, 1, -1 do
    local part = pose.parts[i]
    for y = 0, part.h - 1 do
      for x = 0, part.w - 1 do
        local sx, sy = part.flipX and part.w - x - 1 or x, part.flipY and part.h - y - 1 or y
        local tile = part.tile + floor(sy / 8) * (part.w / 8) + floor(sx / 8)
        local byte = pose.tiles:byte(tile * 32 + sy % 8 * 4 + floor(sx % 8 / 2) + 1)
        local color = floor(byte / (sx % 2 == 0 and 1 or 16)) % 16
        if color ~= 0 then putPixel(part.x + x, part.y + y, color, part.palette) end
      end
    end
  end
end

Ax.reader = reader
return Ax
