local bitlib = rawget(_G, "bit") or rawget(_G, "bit32")
if not bitlib then error("StreamMD5 requires bit or bit32") end

local band, bor, bxor, bnot = bitlib.band, bitlib.bor, bitlib.bxor, bitlib.bnot
local lshift, rshift = bitlib.lshift, bitlib.rshift
local rol = bitlib.rol or bitlib.lrotate

local K = {
  0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
  0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
  0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
  0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
  0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
  0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
  0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
  0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391,
}
local S = {
  7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
  5,9,14,20, 5,9,14,20, 5,9,14,20, 5,9,14,20,
  4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
  6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21,
}

local function add32(a,b,c,d)
  local n = (a or 0) + (b or 0) + (c or 0) + (d or 0)
  return band(n, 0xffffffff)
end

local function le32_from(s, i)
  local b1,b2,b3,b4 = s:byte(i, i+3)
  return bor(b1, lshift(b2,8), lshift(b3,16), lshift(b4,24))
end

local function le32_bytes(x)
  return string.char(
    band(x,0xff), band(rshift(x,8),0xff),
    band(rshift(x,16),0xff), band(rshift(x,24),0xff))
end

local M = {}
local StreamMD5 = {}
StreamMD5.__index = StreamMD5

function StreamMD5.new()
  return setmetatable({
    a=0x67452301, b=0xefcdab89, c=0x98badcfe, d=0x10325476,
    bytes=0, buffer="", done=false,
  }, StreamMD5)
end

function StreamMD5:_block(block)
  for j=1,16 do M[j] = le32_from(block, (j-1)*4+1) end
  local a,b,c,d = self.a,self.b,self.c,self.d
  for i=0,63 do
    local f,g
    if i < 16 then
      f = bor(band(b,c), band(bnot(b),d)); g=i
    elseif i < 32 then
      f = bor(band(d,b), band(bnot(d),c)); g=(5*i+1)%16
    elseif i < 48 then
      f = bxor(b,c,d); g=(3*i+5)%16
    else
      f = bxor(c, bor(b,bnot(d))); g=(7*i)%16
    end
    local tmp=d
    d=c
    c=b
    b=add32(b, rol(add32(a,f,K[i+1],M[g+1]), S[i+1]))
    a=tmp
  end
  self.a=add32(self.a,a); self.b=add32(self.b,b)
  self.c=add32(self.c,c); self.d=add32(self.d,d)
end

function StreamMD5:update(data)
  assert(not self.done, "StreamMD5 context already finalized")
  assert(type(data)=="string", "StreamMD5:update expects a string")
  self.bytes = self.bytes + #data
  local s = self.buffer .. data
  local full = #s - (#s % 64)
  for i=1,full,64 do self:_block(s:sub(i,i+63)) end
  self.buffer = s:sub(full+1)
  return self
end

function StreamMD5:final()
  assert(not self.done, "StreamMD5 context already finalized")
  local originalBytes = self.bytes
  local padLen = (56 - ((originalBytes + 1) % 64)) % 64
  local bits = originalBytes * 8
  local lo = bits % 4294967296
  local hi = math.floor(bits / 4294967296) % 4294967296
  self:update("\128" .. string.rep("\0", padLen) .. le32_bytes(lo) .. le32_bytes(hi))
  assert(#self.buffer == 0, "MD5 finalization left a partial block")
  self.done=true
  local raw = le32_bytes(self.a)..le32_bytes(self.b)..le32_bytes(self.c)..le32_bytes(self.d)
  return (raw:gsub(".", function(ch) return string.format("%02x", ch:byte()) end))
end

return StreamMD5
