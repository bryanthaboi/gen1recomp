local bit = require("bit")

local Affine = {}

local FLT_MAX = 3.4028234663852886e38

local function f32(x)
  if x ~= x or x == 0 or x == math.huge or x == -math.huge then return x end
  local m, e = math.frexp(x)
  local bits = e < -125 and 24 - (-125 - e) or 24
  if bits < 0 then return 0 * x end
  local s = math.ldexp(m, bits)
  local r = math.floor(s)
  local d = s - r
  if d > 0.5 or (d == 0.5 and r % 2 == 1) then r = r + 1 end
  local v = math.ldexp(r, e - bits)
  if v > FLT_MAX then return math.huge end
  if v < -FLT_MAX then return -math.huge end
  return v
end

Affine.f32 = f32

local function trunc(x)
  if x >= 0 then return math.floor(x) end
  return -math.floor(-x)
end

local function s16(v)
  v = bit.band(trunc(v), 0xFFFF)
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end

local function s32(v)
  return bit.tobit(trunc(v))
end

Affine.s16 = s16
Affine.s32 = s32

local function angle(alpha)
  return f32(f32(bit.rshift(bit.band(alpha, 0xFFFF), 8) / 128) * f32(math.pi))
end

-- pokeemerald/include/gba/syscall.h:56 BgAffineSet
function Affine.bgAffineSet(src)
  local ox = f32(s32(src.texX) / 256)
  local oy = f32(s32(src.texY) / 256)
  local cx = s16(src.scrX)
  local cy = s16(src.scrY)
  local sx = f32(s16(src.sx) / 256)
  local sy = f32(s16(src.sy) / 256)
  local theta = angle(src.alpha or 0)
  local cs, sn = f32(math.cos(theta)), f32(math.sin(theta))
  local a = f32(cs * sx)
  local b = f32(sn * f32(-sx))
  local c = f32(sn * sy)
  local d = f32(cs * sy)
  local rx = f32(ox - f32(f32(a * cx) + f32(b * cy)))
  local ry = f32(oy - f32(f32(c * cx) + f32(d * cy)))
  return {
    pa = s16(f32(a * 256)), pb = s16(f32(b * 256)),
    pc = s16(f32(c * 256)), pd = s16(f32(d * 256)),
    dx = s32(f32(rx * 256)), dy = s32(f32(ry * 256)),
  }
end

-- pokeemerald/include/gba/syscall.h:58 ObjAffineSet
function Affine.objAffineSet(xScale, yScale, rotation)
  local sx = f32(s16(xScale) / 256)
  local sy = f32(s16(yScale) / 256)
  local theta = angle(rotation or 0)
  local cs, sn = f32(math.cos(theta)), f32(math.sin(theta))
  return {
    a = s16(f32(f32(cs * sx) * 256)),
    b = s16(f32(f32(sn * f32(-sx)) * 256)),
    c = s16(f32(f32(sn * sy) * 256)),
    d = s16(f32(f32(cs * sy) * 256)),
  }
end

-- pokeemerald/src/intro.c:2810
function Affine.panFadeAndZoom(screenX, screenY, zoom, alpha)
  return Affine.bgAffineSet({
    texX = 0x8000, texY = 0x8000,
    scrX = screenX, scrY = screenY,
    sx = zoom, sy = zoom,
    alpha = alpha,
  })
end

-- pokeemerald/src/sprite.c:1316
function Affine.convertScaleParam(scale)
  scale = s16(scale)
  if scale == 0 then return 0 end
  return s16(trunc(0x10000 / scale))
end

function Affine.sample(reg, x, y, w, h, wrap)
  local tx = math.floor((reg.dx + reg.pa * x + reg.pb * y) / 256)
  local ty = math.floor((reg.dy + reg.pc * x + reg.pd * y) / 256)
  if wrap then
    return tx % w, ty % h
  end
  if tx < 0 or ty < 0 or tx >= w or ty >= h then return nil end
  return tx, ty
end

return Affine
