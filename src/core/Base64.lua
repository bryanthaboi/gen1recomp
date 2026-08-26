local Base64 = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local PAD = 61

local ENC, DEC = {}, {}
for i = 0, 63 do
  local c = ALPHABET:sub(i + 1, i + 1)
  ENC[i] = c
  DEC[c:byte()] = i
end

local floor = math.floor
local char = string.char
local concat = table.concat

function Base64.encode(bytes)
  if type(bytes) ~= "string" then return nil, "base64 input must be a string" end
  local out, n, i = {}, #bytes, 1
  while i + 2 <= n do
    local a, b, c = bytes:byte(i, i + 2)
    local word = a * 65536 + b * 256 + c
    out[#out + 1] = ENC[floor(word / 262144)] .. ENC[floor(word / 4096) % 64]
      .. ENC[floor(word / 64) % 64] .. ENC[word % 64]
    i = i + 3
  end
  local rest = n - i + 1
  if rest == 1 then
    local a = bytes:byte(i)
    out[#out + 1] = ENC[floor(a / 4)] .. ENC[(a % 4) * 16] .. "=="
  elseif rest == 2 then
    local a, b = bytes:byte(i, i + 1)
    local word = a * 256 + b
    out[#out + 1] = ENC[floor(word / 1024)] .. ENC[floor(word / 16) % 64]
      .. ENC[(word % 16) * 4] .. "="
  end
  return concat(out)
end

function Base64.decode(text)
  if type(text) ~= "string" then return nil, "base64 input must be a string" end
  local n = #text
  if n % 4 ~= 0 then return nil, "base64 length must be a multiple of four" end
  if n == 0 then return "" end
  local out = {}
  local last = n - 3
  for i = 1, n, 4 do
    local b1, b2, b3, b4 = text:byte(i, i + 3)
    local v1, v2 = DEC[b1], DEC[b2]
    if not v1 or not v2 then
      return nil, "base64 holds a character outside the alphabet"
    end
    if i == last and b3 == PAD then
      if b4 ~= PAD then return nil, "base64 padding is malformed" end
      if v2 % 16 ~= 0 then return nil, "base64 padding carries data bits" end
      out[#out + 1] = char(v1 * 4 + floor(v2 / 16))
    elseif i == last and b4 == PAD then
      local v3 = DEC[b3]
      if not v3 then return nil, "base64 holds a character outside the alphabet" end
      if v3 % 4 ~= 0 then return nil, "base64 padding carries data bits" end
      local word = v1 * 1024 + v2 * 16 + floor(v3 / 4)
      out[#out + 1] = char(floor(word / 256), word % 256)
    else
      local v3, v4 = DEC[b3], DEC[b4]
      if not v3 or not v4 then
        return nil, "base64 holds a character outside the alphabet"
      end
      local word = v1 * 262144 + v2 * 4096 + v3 * 64 + v4
      out[#out + 1] = char(floor(word / 65536), floor(word / 256) % 256, word % 256)
    end
  end
  return concat(out)
end

return Base64
