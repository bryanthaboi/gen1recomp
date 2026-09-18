local Lz2 = {}

Lz2.CMD_DIRECT = 0x00
Lz2.CMD_BYTE_FILL = 0x20
Lz2.CMD_WORD_FILL = 0x40
Lz2.CMD_INCREASING = 0x60
Lz2.CMD_COPY = 0x80

Lz2.MAX_OUTPUT = 0x10000

local byte = string.byte
local char = string.char
local concat = table.concat

function Lz2.decompress(rom, offset, limit)
  limit = limit or Lz2.MAX_OUTPUT
  local out, n = {}, 0
  local p = offset + 1
  local size = #rom
  while true do
    if p > size then return nil, "ran past the end of the rom" end
    local b = byte(rom, p)
    p = p + 1
    if b == 0xFF then break end
    local cmd, len
    if b >= 0xE0 then
      cmd = (b * 8) % 256
      cmd = cmd - (cmd % 32)
      if p > size then return nil, "truncated long length" end
      len = (b % 4) * 256 + byte(rom, p) + 1
      p = p + 1
    else
      cmd = b - (b % 32)
      len = (b % 32) + 1
    end
    if n + len > limit then return nil, "output exceeded " .. limit .. " bytes" end
    if cmd == Lz2.CMD_DIRECT then
      if p + len - 1 > size then return nil, "truncated direct copy" end
      for i = 0, len - 1 do out[n + 1 + i] = byte(rom, p + i) end
      n = n + len
      p = p + len
    elseif cmd == Lz2.CMD_BYTE_FILL then
      if p > size then return nil, "truncated byte fill" end
      local v = byte(rom, p)
      p = p + 1
      for i = 1, len do out[n + i] = v end
      n = n + len
    elseif cmd == Lz2.CMD_WORD_FILL then
      if p + 1 > size then return nil, "truncated word fill" end
      local a, c = byte(rom, p), byte(rom, p + 1)
      p = p + 2
      for i = 1, len do out[n + i] = (i % 2 == 1) and a or c end
      n = n + len
    elseif cmd == Lz2.CMD_INCREASING then
      if p > size then return nil, "truncated increasing fill" end
      local v = byte(rom, p)
      p = p + 1
      for i = 1, len do
        out[n + i] = v % 256
        v = v + 1
      end
      n = n + len
    else
      if p + 1 > size then return nil, "truncated back reference" end
      local src = byte(rom, p + 1) * 256 + byte(rom, p)
      p = p + 2
      for i = 1, len do
        local from = out[src + i]
        if from == nil then return nil, "back reference points past the output" end
        out[n + i] = from
      end
      n = n + len
    end
  end
  local chunk, pieces = {}, {}
  for i = 1, n do
    chunk[#chunk + 1] = char(out[i])
    if #chunk == 4096 then
      pieces[#pieces + 1] = concat(chunk)
      chunk = {}
    end
  end
  pieces[#pieces + 1] = concat(chunk)
  return concat(pieces), p - 1 - offset
end

return Lz2
