-- Nitro archive layout follows AnimaEngine v1.0.0 (MIT); see PROVENANCE.md/ANIMAENGINE_LICENSE.
local Binary=require("src.import.gen5.Binary")
local Narc={}
function Narc.open(data)
  local sections,r=Binary.sections(data,"NARC")
  local fat,body=assert(sections.BTAF,"missing NARC FAT"),assert(sections.GMIF,"missing NARC data")
  assert(sections.BTNF,"missing NARC name section")
  local count=r.u32(fat.offset+8)
  assert(count>0 and count<=20000 and 12+count*8<=fat.size,"invalid NARC member table")
  local archive={count=count}
  function archive.member(index)
    assert(type(index)=="number" and index%1==0 and index>=0 and index<count,"invalid NARC member")
    local pos=fat.offset+12+index*8
    local first,last=r.u32(pos),r.u32(pos+4)
    assert(first<=last and last<=body.size-8,"NARC member outside payload")
    return r.sub(body.dataOffset+first,last-first)
  end
  return archive
end
return Narc
