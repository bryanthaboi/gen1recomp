-- Bounded zero-based readers for Nintendo DS / Nitro containers.
local Binary = {}
function Binary.reader(data)
  assert(type(data) == "string", "binary data must be a string")
  local r = {size = #data}
  function r.bounds(offset, length)
    assert(type(offset)=="number" and offset%1==0 and offset>=0
      and type(length)=="number" and length%1==0 and length>=0
      and offset<=#data-length, "binary range outside container")
  end
  function r.sub(offset,length) r.bounds(offset,length); return data:sub(offset+1,offset+length) end
  function r.u8(offset) r.bounds(offset,1); return data:byte(offset+1) end
  function r.u16(offset) r.bounds(offset,2); local a,b=data:byte(offset+1,offset+2); return a+b*256 end
  function r.u32(offset) r.bounds(offset,4); local a,b,c,d=data:byte(offset+1,offset+4); return a+b*256+c*65536+d*16777216 end
  function r.s16(offset) local n=r.u16(offset); return n>=32768 and n-65536 or n end
  function r.s32(offset) local n=r.u32(offset); return n>=2147483648 and n-4294967296 or n end
  return r
end
function Binary.sections(data,magic)
  local r=Binary.reader(data)
  assert(r.sub(0,4)==magic,"unexpected Nitro signature")
  local size,header,count=r.u32(8),r.u16(12),r.u16(14)
  assert(size<=r.size and size>=16 and header>=16 and header<=size
    and count>0 and count<=64,"invalid Nitro header")
  local result,pos={},header
  for _=1,count do
    assert(pos+8<=size,"truncated Nitro section")
    local tag,length=r.sub(pos,4),r.u32(pos+4)
    assert(length>=8 and length<=size-pos and not result[tag],"invalid Nitro section")
    result[tag]={offset=pos,size=length,dataOffset=pos+8}
    pos=pos+length
  end
  return result,r
end
return Binary
