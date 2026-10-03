-- Adapted from AnimaEngine v1.0.0 ncgr.c/nclr.c/nitro_util.c (MIT).
-- See PROVENANCE.md/ANIMAENGINE_LICENSE. Source bytes remain private.
local Graphics = {}
local MAX_BYTES = 8 * 1024 * 1024

-- Zero-based bounded reader, kept local to these format parsers.
function Graphics.reader(data)
  assert(type(data) == "string" and #data <= MAX_BYTES, "Gen 5 entry must be a bounded byte string")
  local r = {size = #data}
  function r:bounds(offset, length)
    assert(type(offset)=="number" and offset%1==0 and offset>=0
      and type(length)=="number" and length%1==0 and length>=0
      and offset+length<=#data, "truncated Gen 5 graphics entry")
  end
  function r:sub(offset, length) self:bounds(offset,length); return data:sub(offset+1,offset+length) end
  function r:u8(offset) self:bounds(offset,1); return data:byte(offset+1) end
  function r:u16(offset) local a,b=self:u8(offset),self:u8(offset+1); return a+b*256 end
  function r:u32(offset) return self:u16(offset)+self:u16(offset+2)*65536 end
  function r:section(magic)
    local offset=0x10
    while offset+8<=#data do
      local size=self:u32(offset+4)
      assert(size>=8,"invalid Nitro section length"); self:bounds(offset,size)
      if self:sub(offset,4)==magic then return offset,size end
      offset=offset+size
    end
    error("missing Nitro section "..magic,0)
  end
  return r
end

local function integer(n,lo,hi)
  return type(n)=="number" and n%1==0 and n>=lo and n<=hi
end

function Graphics.parseGraphics(data)
  local r=Graphics.reader(data)
  r:bounds(0,0x30)
  assert(r:sub(0,4)=="RGCN","invalid NCGR signature")
  local section,size=r:section("RAHC")
  assert(size>=0x20,"invalid NCGR section")
  local width,height=r:u16(section+8),r:u16(section+10)
  local depth,kind,length=r:u32(section+12),r:u32(section+20),r:u32(section+24)
  local bpp=depth==3 and 4 or depth==4 and 8 or nil
  assert(bpp,"unsupported NCGR bit depth")
  local bytesPerTile=bpp==4 and 32 or 64
  if length==0 then length=size-0x20 end
  assert(length>0 and length<=size-0x20 and length%bytesPerTile==0,"invalid NCGR tile data length")
  local pixels=r:sub(section+0x20,length)
  local count=length/bytesPerTile
  -- Gen V linear 4bpp files use a 32-tile stride regardless of header width.
  local linear=kind==1 and bpp==4
  local object={bpp=bpp,tile_count=count,tileCount=count,width_tiles=linear and 32 or width,
    height_tiles=height,character_type=kind,tile_data_size=length}
  object.width=object.width_tiles*8
  object.height=math.ceil(count/math.max(1,object.width_tiles))*8
  function object:getPixel(tile,x,y)
    if not integer(tile,0,count-1) or not integer(x,0,7) or not integer(y,0,7) then return 0 end
    local pixel
    if linear then pixel=(tile%32*8+x)+(math.floor(tile/32)*8+y)*256
    else pixel=tile*64+y*8+x end
    if bpp==8 then return pixels:byte(pixel+1) or 0 end
    local byte=pixels:byte(math.floor(pixel/2)+1)
    if not byte then return 0 end
    return pixel%2==0 and byte%16 or math.floor(byte/16)
  end
  return object
end

function Graphics.parsePalette(data)
  local r=Graphics.reader(data)
  r:bounds(0,0x28)
  assert(r:sub(0,4)=="RLCN","invalid NCLR signature")
  local section,size=r:section("TTLP")
  assert(size>=0x18,"invalid NCLR section")
  local length=r:u32(section+0x10)
  if length==0 then length=size-0x18 end
  assert(length>0 and length<=size-0x18 and length%2==0,"invalid NCLR palette length")
  local count=math.min(length/2,256)
  local colors,raw={},{}
  local function expand(v) return v*8+math.floor(v/4) end
  for index=0,count-1 do
    local value=r:u16(section+0x18+index*2)
    raw[index+1]=value
    colors[index+1]={r=expand(value%32),g=expand(math.floor(value/32)%32),
      b=expand(math.floor(value/1024)%32),a=index==0 and 0 or 255}
  end
  return {colors=colors,raw_colors=raw,color_count=count,colorCount=count}
end

Graphics.ncgr=Graphics.parseGraphics
Graphics.nclr=Graphics.parsePalette
return Graphics
