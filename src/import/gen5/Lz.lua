-- Bounded LZ10/LZ11 port of AnimaEngine v1.0.0 lz.c (MIT).
-- Source and retained notices are documented in PROVENANCE.md/ANIMAENGINE_LICENSE.
local Binary=require("src.import.gen5.Binary")
local Lz={MAX_BYTES=8*1024*1024}
function Lz.decode(data,limit)
  assert(type(data)=="string","compressed data must be a string")
  local kind=data:byte(1)
  if kind~=0x10 and kind~=0x11 then return data end
  local r=Binary.reader(data)
  local size,pos=math.floor(r.u32(0)/256),4
  if size==0 and kind==0x11 then size=r.u32(4); pos=8 end
  assert(size>0 and size<=(limit or Lz.MAX_BYTES),"LZ output exceeds bound")
  local out,count={},0
  local function byte() local n=r.u8(pos); pos=pos+1; return n end
  while count<size do
    local flags=byte()
    for bit=7,0,-1 do
      if count>=size then break end
      if math.floor(flags/2^bit)%2==0 then
        count=count+1; out[count]=string.char(byte())
      else
        local a,b=byte(),byte()
        local high=math.floor(a/16)
        local length,disp
        if kind==0x10 then length,disp=high+3,(a%16)*256+b
        elseif high==0 then
          local c=byte(); length,disp=(a%16)*16+math.floor(b/16)+17,(b%16)*256+c
        elseif high==1 then
          local c,d=byte(),byte()
          length,disp=(a%16)*4096+b*16+math.floor(c/16)+273,(c%16)*256+d
        else length,disp=high+1,(a%16)*256+b end
        assert(disp+1<=count,"LZ reference before output")
        for _=1,math.min(length,size-count) do
          count=count+1; out[count]=out[count-disp-1]
        end
      end
    end
  end
  return table.concat(out)
end
return Lz
