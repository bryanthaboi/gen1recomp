local bit = require("bit")
local Sha512 = require("src.core.crypto.sha512")

local band, bor, arshift = bit.band, bit.bor, bit.arshift
local floor = math.floor

local Ed25519 = {}

local function gf(init)
  local o = {}
  for i = 0, 15 do o[i] = init and init[i + 1] or 0 end
  return o
end

local gf0 = gf()
local gf1 = gf({ 1 })
local D = gf({ 0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070,
  0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203 })
local D2 = gf({ 0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0,
  0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406 })
local X = gf({ 0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c,
  0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169 })
local Y = gf({ 0x6658, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666,
  0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666, 0x6666 })
local I = gf({ 0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43,
  0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83 })

local L = { [0] = 0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2,
  0xde, 0xf9, 0xde, 0x14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10 }

local function set(o, a)
  for i = 0, 15 do o[i] = a[i] end
end

local function car(o)
  local c = 1
  for i = 0, 15 do
    local v = o[i] + c + 65535
    c = floor(v / 65536)
    o[i] = v - c * 65536
  end
  o[0] = o[0] + c - 1 + 37 * (c - 1)
end

local function A(o, a, b)
  for i = 0, 15 do o[i] = a[i] + b[i] end
end

local function Z(o, a, b)
  for i = 0, 15 do o[i] = a[i] - b[i] end
end

local T = {}
local function M(o, a, b)
  for i = 0, 30 do T[i] = 0 end
  for i = 0, 15 do
    local ai = a[i]
    for j = 0, 15 do
      T[i + j] = T[i + j] + ai * b[j]
    end
  end
  for i = 0, 14 do T[i] = T[i] + 38 * T[i + 16] end
  for i = 0, 15 do o[i] = T[i] end
  car(o)
  car(o)
end

local function S(o, a)
  M(o, a, a)
end

local function inv25519(o, i)
  local c = gf()
  set(c, i)
  for a = 253, 0, -1 do
    S(c, c)
    if a ~= 2 and a ~= 4 then M(c, c, i) end
  end
  set(o, c)
end

local function pow2523(o, i)
  local c = gf()
  set(c, i)
  for a = 250, 0, -1 do
    S(c, c)
    if a ~= 1 then M(c, c, i) end
  end
  set(o, c)
end

local function sel(p, q, b)
  if b ~= 0 then
    for i = 0, 15 do p[i], q[i] = q[i], p[i] end
  end
end

local function pack25519(o, n)
  local m, t = gf(), gf()
  set(t, n)
  car(t)
  car(t)
  car(t)
  for _ = 1, 2 do
    m[0] = t[0] - 0xffed
    for i = 1, 14 do
      m[i] = t[i] - 0xffff - band(arshift(m[i - 1], 16), 1)
      m[i - 1] = band(m[i - 1], 0xffff)
    end
    m[15] = t[15] - 0x7fff - band(arshift(m[14], 16), 1)
    local b = band(arshift(m[15], 16), 1)
    m[14] = band(m[14], 0xffff)
    sel(t, m, 1 - b)
  end
  for i = 0, 15 do
    o[2 * i] = band(t[i], 0xff)
    o[2 * i + 1] = band(arshift(t[i], 8), 0xff)
  end
end

local function neq25519(a, b)
  local c, d = {}, {}
  pack25519(c, a)
  pack25519(d, b)
  for i = 0, 31 do
    if c[i] ~= d[i] then return true end
  end
  return false
end

local function par25519(a)
  local d = {}
  pack25519(d, a)
  return band(d[0], 1)
end

local function unpack25519(o, n)
  for i = 0, 15 do o[i] = n[2 * i] + n[2 * i + 1] * 256 end
  o[15] = band(o[15], 0x7fff)
end

local function add(p, q)
  local a, b, c, d = gf(), gf(), gf(), gf()
  local e, f, g, h, t = gf(), gf(), gf(), gf(), gf()
  Z(a, p[1], p[0])
  Z(t, q[1], q[0])
  M(a, a, t)
  A(b, p[0], p[1])
  A(t, q[0], q[1])
  M(b, b, t)
  M(c, p[3], q[3])
  M(c, c, D2)
  M(d, p[2], q[2])
  A(d, d, d)
  Z(e, b, a)
  Z(f, d, c)
  A(g, d, c)
  A(h, b, a)
  M(p[0], e, f)
  M(p[1], h, g)
  M(p[2], g, f)
  M(p[3], e, h)
end

local function swap(p, q, b)
  if b ~= 0 then
    for i = 0, 3 do p[i], q[i] = q[i], p[i] end
  end
end

local function pack(r, p)
  local tx, ty, zi = gf(), gf(), gf()
  inv25519(zi, p[2])
  M(tx, p[0], zi)
  M(ty, p[1], zi)
  pack25519(r, ty)
  r[31] = bor(r[31], par25519(tx) * 128)
end

local function scalarmult(p, q, s)
  set(p[0], gf0)
  set(p[1], gf1)
  set(p[2], gf1)
  set(p[3], gf0)
  for i = 255, 0, -1 do
    local b = band(arshift(s[floor(i / 8)], i % 8), 1)
    swap(p, q, b)
    add(q, p)
    add(p, p)
    swap(p, q, b)
  end
end

local function scalarbase(p, s)
  local q = { [0] = gf(), gf(), gf(), gf() }
  set(q[0], X)
  set(q[1], Y)
  set(q[2], gf1)
  M(q[3], X, Y)
  scalarmult(p, q, s)
end

local function unpackneg(r, p)
  local t, chk, num, den = gf(), gf(), gf(), gf()
  local den2, den4, den6 = gf(), gf(), gf()
  set(r[2], gf1)
  unpack25519(r[1], p)
  S(num, r[1])
  M(den, num, D)
  Z(num, num, r[2])
  A(den, r[2], den)
  S(den2, den)
  S(den4, den2)
  M(den6, den4, den2)
  M(t, den6, num)
  M(t, t, den)
  pow2523(t, t)
  M(t, t, num)
  M(t, t, den)
  M(t, t, den)
  M(r[0], t, den)
  S(chk, r[0])
  M(chk, chk, den)
  if neq25519(chk, num) then M(r[0], r[0], I) end
  S(chk, r[0])
  M(chk, chk, den)
  if neq25519(chk, num) then return false end
  if par25519(r[0]) == arshift(p[31], 7) then Z(r[0], gf0, r[0]) end
  M(r[3], r[0], r[1])
  return true
end

local function modL(r, x)
  for i = 63, 32, -1 do
    local carry = 0
    local j = i - 32
    local k = i - 12
    while j < k do
      x[j] = x[j] + carry - 16 * x[i] * L[j - (i - 32)]
      carry = floor((x[j] + 128) / 256)
      x[j] = x[j] - carry * 256
      j = j + 1
    end
    x[j] = x[j] + carry
    x[i] = 0
  end
  local carry = 0
  for j = 0, 31 do
    x[j] = x[j] + carry - arshift(x[31], 4) * L[j]
    carry = arshift(x[j], 8)
    x[j] = band(x[j], 255)
  end
  for j = 0, 31 do x[j] = x[j] - carry * L[j] end
  for i = 0, 31 do
    x[i + 1] = x[i + 1] + arshift(x[i], 8)
    r[i] = band(x[i], 255)
  end
end

local function reduce(bytes64)
  local x = {}
  for i = 0, 63 do x[i] = bytes64:byte(i + 1) end
  x[64] = 0
  local r = {}
  modL(r, x)
  return r
end

local function fromHex(hex, n)
  if type(hex) ~= "string" or #hex ~= n * 2 or hex:find("[^0-9a-fA-F]") then return nil end
  local out = {}
  for i = 0, n - 1 do
    out[i] = tonumber(hex:sub(2 * i + 1, 2 * i + 2), 16)
  end
  return out
end

local function scalarIsCanonical(sig)
  for i = 63, 32, -1 do
    local s, l = sig[i], L[i - 32]
    if s < l then return true end
    if s > l then return false end
  end
  return false
end

local function pointIsCanonical(pk)
  if band(pk[31], 0x7f) ~= 0x7f then return true end
  for i = 30, 1, -1 do
    if pk[i] ~= 0xff then return true end
  end
  return pk[0] < 0xed
end

local function toString(bytes, from, to)
  local out = {}
  for i = from, to do out[#out + 1] = string.char(bytes[i]) end
  return table.concat(out)
end

local function verify(pubHex, msg, sigHex)
  if type(msg) ~= "string" then return false end
  local pk = fromHex(pubHex, 32)
  local sig = fromHex(sigHex, 64)
  if not pk or not sig then return false end
  if not scalarIsCanonical(sig) then return false end
  if not pointIsCanonical(pk) then return false end
  local q = { [0] = gf(), gf(), gf(), gf() }
  if not unpackneg(q, pk) then return false end
  local h = reduce(Sha512.digest(toString(sig, 0, 31) .. toString(pk, 0, 31) .. msg))
  local p = { [0] = gf(), gf(), gf(), gf() }
  scalarmult(p, q, h)
  local s = {}
  for i = 0, 31 do s[i] = sig[32 + i] end
  scalarbase(q, s)
  add(p, q)
  local t = {}
  pack(t, p)
  local diff = 0
  for i = 0, 31 do
    if t[i] ~= sig[i] then diff = diff + 1 end
  end
  return diff == 0
end

function Ed25519.verify(pubHex, msg, sigHex)
  local ok, result = pcall(verify, pubHex, msg, sigHex)
  return ok and result == true
end

return Ed25519
