-- FireRed Help ROM tables. Offsets relative to sHelpSystemTopicPtrs, verified
-- against pret/pokefirered and BPRE Rev 1. No game text is distributed here.
local TextIR = require('src.core.game3.scripting.text_ir')
local Extract = {}
-- CHAR_EXTRA_SYMBOL glyphs use the second bank of the original Latin font.
local SYMBOLS = {[0]='↑',[1]='↓',[2]='←',[3]='→',[4]='+',
  [10]='①',[11]='②',[12]='③',[13]='④',[14]='⑤',[15]='⑥',[16]='⑦',
  [17]='⑧',[18]='⑨',[19]='(',[20]=')',[21]='◎',[22]='△',[23]='✕'}
Extract.PATH = 'data/generated/gba/help/pack.lua'
local BASE_REV1 = 0x45B0E0
local TABLES = {{0x30,0xE4,44},{0x198,0x25C,48},{0x320,0x3D0,43},
  {0x480,0x4A0,7},{0x4C0,0x550,35}}
local function pointer(rom, off)
  local p = rom:u32(off) - 0x08000000
  assert(p >= 0 and p < rom.size, 'Invalid Help ROM pointer')
  return p
end
local function readText(rom, off)
  local out, bytes = {}, {}
  local function flush()
    for _, seg in ipairs(TextIR.decode(bytes)) do
      if seg.t == 'nl' or seg.t == 'scroll' or seg.t == 'para' then
        out[#out+1] = '\n'
      elseif seg.t == 'player' then out[#out+1] = '{PLAYER}'
      elseif seg.t == 'rival' then out[#out+1] = '{RIVAL}'
      elseif seg.t == 'strvar' and seg.n == 1 then out[#out+1] = '{PC_OWNER}'
      elseif seg.t == 'text' then out[#out+1] = seg.s end
    end
    bytes = {}
  end
  for _ = 1, 4096 do
    local b = rom:get(off); off = off + 1
    if b == 0xFF then flush(); return table.concat(out) end
    if b == 0xF9 then
      flush()
      local glyph = rom:get(off); off = off + 1
      out[#out+1] = assert(SYMBOLS[glyph], 'Unsupported Help symbol '..glyph)
    else bytes[#bytes+1] = b end
  end
  error('Unterminated Help ROM text')
end
local function list(rom, off)
  local out = {}
  for i=0,63 do
    local v=rom:get(off+i)
    if v==255 then return out end
    out[#out+1]=v
  end
  error('Unterminated Help topic list')
end
local function locate(rom)
  -- Rev 0 and Rev 1 keep this rodata block's layout. Validate the signature
  -- instead of applying the Rev 1 displacement to unrelated ROM tables.
  local signature={0xD1,0xDC,0xD5,0xE8,0,0xE7,0xDC,0xE3,0xE9,0xE0,0xD8}
  for base=BASE_REV1-0x200,BASE_REV1+0x200,4 do
    local p=rom:u32(base)-0x08000000
    if p>=0 and p+#signature<rom.size then
      local match=true
      for i,b in ipairs(signature) do if rom:get(p+i-1)~=b then match=false; break end end
      if match then return base end
    end
  end
  error('Help tables not found in this ROM revision')
end
function Extract.read(rom)
  local base=locate(rom)
  local textBase=pointer(rom,base)
  local pack={version=1,topics={},descriptions={},entries={},contexts={},
    greetings=readText(rom,textBase+0x1D1),cancel=readText(rom,textBase+0x77),
    basic=list(rom,base+0x93E),tiles={},palette={}}
  for i=1,6 do
    pack.topics[i]=readText(rom,pointer(rom,base+(i-1)*4))
    pack.descriptions[i]=readText(rom,pointer(rom,base+24+(i-1)*4))
  end
  for topic, row in ipairs(TABLES) do
    local entries={}; pack.entries[topic]=entries
    for id=1,row[3] do
      entries[id]={question=readText(rom,pointer(rom,base+row[1]+id*4)),
        answer=readText(rom,pointer(rom,base+row[2]+id*4))}
    end
  end
  for context=0,35 do
    local topics={};pack.contexts[context]=topics
    for topic=1,5 do
      local off=base+0x960+(context*5+topic-1)*4
      if rom:u32(off)~=0 then topics[topic]=list(rom,pointer(rom,off)) end
    end
  end
  for i=0,287 do pack.tiles[i+1]=rom:get(base+0x8F88+i) end
  for i=0,15 do
    local c=rom:u16(base+0x90A8+i*2)
    pack.palette[i+1]={c%32/31,math.floor(c/32)%32/31,math.floor(c/1024)%32/31,1}
  end
  return pack
end
local function serialize(v)
  if type(v)=='string' then return string.format('%q',v) end
  if type(v)~='table' then return tostring(v) end
  local keys={};for k in pairs(v) do keys[#keys+1]=k end
  table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
  local out={'{'}
  for _,k in ipairs(keys) do out[#out+1]='['..serialize(k)..']='..serialize(v[k])..',' end
  out[#out+1]='}'; return table.concat(out)
end
function Extract.writeExtract(rom,cache)
  local pack=Extract.read(rom)
  assert(cache:write(Extract.PATH,'return '..serialize(pack)..'\n'))
  return pack
end
return Extract
