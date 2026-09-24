local bit = require("bit")

local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local rshift, lshift, tobit = bit.rshift, bit.lshift, bit.tobit
local floor = math.floor
local byte, char, format = string.byte, string.char, string.format

local U32 = 4294967296

local Sha512 = {}

local K = {
  0x428a2f98, 0xd728ae22, 0x71374491, 0x23ef65cd,
  0xb5c0fbcf, 0xec4d3b2f, 0xe9b5dba5, 0x8189dbbc,
  0x3956c25b, 0xf348b538, 0x59f111f1, 0xb605d019,
  0x923f82a4, 0xaf194f9b, 0xab1c5ed5, 0xda6d8118,
  0xd807aa98, 0xa3030242, 0x12835b01, 0x45706fbe,
  0x243185be, 0x4ee4b28c, 0x550c7dc3, 0xd5ffb4e2,
  0x72be5d74, 0xf27b896f, 0x80deb1fe, 0x3b1696b1,
  0x9bdc06a7, 0x25c71235, 0xc19bf174, 0xcf692694,
  0xe49b69c1, 0x9ef14ad2, 0xefbe4786, 0x384f25e3,
  0x0fc19dc6, 0x8b8cd5b5, 0x240ca1cc, 0x77ac9c65,
  0x2de92c6f, 0x592b0275, 0x4a7484aa, 0x6ea6e483,
  0x5cb0a9dc, 0xbd41fbd4, 0x76f988da, 0x831153b5,
  0x983e5152, 0xee66dfab, 0xa831c66d, 0x2db43210,
  0xb00327c8, 0x98fb213f, 0xbf597fc7, 0xbeef0ee4,
  0xc6e00bf3, 0x3da88fc2, 0xd5a79147, 0x930aa725,
  0x06ca6351, 0xe003826f, 0x14292967, 0x0a0e6e70,
  0x27b70a85, 0x46d22ffc, 0x2e1b2138, 0x5c26c926,
  0x4d2c6dfc, 0x5ac42aed, 0x53380d13, 0x9d95b3df,
  0x650a7354, 0x8baf63de, 0x766a0abb, 0x3c77b2a8,
  0x81c2c92e, 0x47edaee6, 0x92722c85, 0x1482353b,
  0xa2bfe8a1, 0x4cf10364, 0xa81a664b, 0xbc423001,
  0xc24b8b70, 0xd0f89791, 0xc76c51a3, 0x0654be30,
  0xd192e819, 0xd6ef5218, 0xd6990624, 0x5565a910,
  0xf40e3585, 0x5771202a, 0x106aa070, 0x32bbd1b8,
  0x19a4c116, 0xb8d2d0c8, 0x1e376c08, 0x5141ab53,
  0x2748774c, 0xdf8eeb99, 0x34b0bcb5, 0xe19b48a8,
  0x391c0cb3, 0xc5c95a63, 0x4ed8aa4a, 0xe3418acb,
  0x5b9cca4f, 0x7763e373, 0x682e6ff3, 0xd6b2b8a3,
  0x748f82ee, 0x5defb2fc, 0x78a5636f, 0x43172f60,
  0x84c87814, 0xa1f0ab72, 0x8cc70208, 0x1a6439ec,
  0x90befffa, 0x23631e28, 0xa4506ceb, 0xde82bde9,
  0xbef9a3f7, 0xb2c67915, 0xc67178f2, 0xe372532b,
  0xca273ece, 0xea26619c, 0xd186b8c7, 0x21c0c207,
  0xeada7dd6, 0xcde0eb1e, 0xf57d4f7f, 0xee6ed178,
  0x06f067aa, 0x72176fba, 0x0a637dc5, 0xa2c898a6,
  0x113f9804, 0xbef90dae, 0x1b710b35, 0x131c471b,
  0x28db77f5, 0x23047d84, 0x32caab7b, 0x40c72493,
  0x3c9ebe0a, 0x15c9bebc, 0x431d67c4, 0x9c100d4c,
  0x4cc5d4be, 0xcb3e42b6, 0x597f299c, 0xfc657e2a,
  0x5fcb6fab, 0x3ad6faec, 0x6c44198c, 0x4a475817,
}

local IV = {
  0x6a09e667, 0xf3bcc908, 0xbb67ae85, 0x84caa73b,
  0x3c6ef372, 0xfe94f82b, 0xa54ff53a, 0x5f1d36f1,
  0x510e527f, 0xade682d1, 0x9b05688c, 0x2b3e6c1f,
  0x1f83d9ab, 0xfb41bd6b, 0x5be0cd19, 0x137e2179,
}

for i = 1, #K do K[i] = tobit(K[i]) end

local W = {}

local function compress(H, msg, off)
  for i = 0, 15 do
    local p = off + i * 8
    local b1, b2, b3, b4, b5, b6, b7, b8 = byte(msg, p + 1, p + 8)
    W[2 * i + 1] = tobit(((b1 * 256 + b2) * 256 + b3) * 256 + b4)
    W[2 * i + 2] = tobit(((b5 * 256 + b6) * 256 + b7) * 256 + b8)
  end
  for i = 16, 79 do
    local h, l = W[2 * (i - 15) + 1], W[2 * (i - 15) + 2]
    local s0h = bxor(bor(rshift(h, 1), lshift(l, 31)), bor(rshift(h, 8), lshift(l, 24)), rshift(h, 7))
    local s0l = bxor(bor(rshift(l, 1), lshift(h, 31)), bor(rshift(l, 8), lshift(h, 24)),
      bor(rshift(l, 7), lshift(h, 25)))
    h, l = W[2 * (i - 2) + 1], W[2 * (i - 2) + 2]
    local s1h = bxor(bor(rshift(h, 19), lshift(l, 13)), bor(rshift(l, 29), lshift(h, 3)), rshift(h, 6))
    local s1l = bxor(bor(rshift(l, 19), lshift(h, 13)), bor(rshift(h, 29), lshift(l, 3)),
      bor(rshift(l, 6), lshift(h, 26)))
    local lo = s1l % U32 + W[2 * (i - 7) + 2] % U32 + s0l % U32 + W[2 * (i - 16) + 2] % U32
    local hi = s1h + W[2 * (i - 7) + 1] + s0h + W[2 * (i - 16) + 1] + floor(lo / U32)
    W[2 * i + 1], W[2 * i + 2] = tobit(hi), tobit(lo)
  end

  local ah, al, bh, bl, ch, cl, dh, dl = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
  local eh, el, fh, fl, gh, gl, hh, hl = H[9], H[10], H[11], H[12], H[13], H[14], H[15], H[16]

  for i = 0, 79 do
    local S1h = bxor(bor(rshift(eh, 14), lshift(el, 18)), bor(rshift(eh, 18), lshift(el, 14)),
      bor(rshift(el, 9), lshift(eh, 23)))
    local S1l = bxor(bor(rshift(el, 14), lshift(eh, 18)), bor(rshift(el, 18), lshift(eh, 14)),
      bor(rshift(eh, 9), lshift(el, 23)))
    local chh = bxor(band(eh, fh), band(bnot(eh), gh))
    local chl = bxor(band(el, fl), band(bnot(el), gl))
    local t1l = hl % U32 + S1l % U32 + chl % U32 + K[2 * i + 2] % U32 + W[2 * i + 2] % U32
    local t1h = hh + S1h + chh + K[2 * i + 1] + W[2 * i + 1] + floor(t1l / U32)

    local S0h = bxor(bor(rshift(ah, 28), lshift(al, 4)), bor(rshift(al, 2), lshift(ah, 30)),
      bor(rshift(al, 7), lshift(ah, 25)))
    local S0l = bxor(bor(rshift(al, 28), lshift(ah, 4)), bor(rshift(ah, 2), lshift(al, 30)),
      bor(rshift(ah, 7), lshift(al, 25)))
    local mjh = bxor(band(ah, bh), band(ah, ch), band(bh, ch))
    local mjl = bxor(band(al, bl), band(al, cl), band(bl, cl))
    local t2l = S0l % U32 + mjl % U32
    local t2h = S0h + mjh + floor(t2l / U32)

    hh, hl = gh, gl
    gh, gl = fh, fl
    fh, fl = eh, el
    local el2 = dl % U32 + t1l % U32
    eh, el = tobit(dh + t1h + floor(el2 / U32)), tobit(el2)
    dh, dl = ch, cl
    ch, cl = bh, bl
    bh, bl = ah, al
    local al2 = t1l % U32 + t2l % U32
    ah, al = tobit(t1h + t2h + floor(al2 / U32)), tobit(al2)
  end

  local v = { ah, al, bh, bl, ch, cl, dh, dl, eh, el, fh, fl, gh, gl, hh, hl }
  for k = 1, 16, 2 do
    local lo = H[k + 1] % U32 + v[k + 1] % U32
    H[k] = tobit(H[k] + v[k] + floor(lo / U32))
    H[k + 1] = tobit(lo)
  end
end

local function word(n)
  return char(band(rshift(n, 24), 255), band(rshift(n, 16), 255), band(rshift(n, 8), 255), band(n, 255))
end

function Sha512.digest(msg)
  msg = tostring(msg or "")
  local len = #msg
  local bits = len * 8
  local pad = (111 - len) % 128
  local tail = char(0x80) .. string.rep("\0", pad) .. string.rep("\0", 8)
    .. word(floor(bits / U32)) .. word(bits % U32)
  local data = msg .. tail
  local H = {}
  for i = 1, 16 do H[i] = tobit(IV[i]) end
  for off = 0, #data - 1, 128 do
    compress(H, data, off)
  end
  local out = {}
  for i = 1, 16 do out[i] = word(H[i]) end
  return table.concat(out)
end

function Sha512.toHex(bytes)
  return (tostring(bytes):gsub(".", function(c) return format("%02x", byte(c)) end))
end

function Sha512.hex(msg)
  return Sha512.toHex(Sha512.digest(msg))
end

return Sha512
