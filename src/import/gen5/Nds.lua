-- NDS FNT/FAT layout follows AnimaEngine v1.0.0 (MIT); see PROVENANCE.md/ANIMAENGINE_LICENSE.
local Binary=require("src.import.gen5.Binary")
local Nds={}
function Nds.open(data)
  local r=Binary.reader(data)
  assert(r.size>=512,"truncated NDS header")
  local code=r.sub(12,4)
  assert(code:sub(1,3)=="IRA" or code:sub(1,3)=="IRB","expected Pokemon Black/White dump")
  local fo,fl,ao,al=r.u32(0x40),r.u32(0x44),r.u32(0x48),r.u32(0x4c)
  r.bounds(fo,fl); r.bounds(ao,al)
  assert(fl>=8 and al>0 and al%8==0 and al/8<=65536,"invalid NDS filesystem")
  local f=Binary.reader(r.sub(fo,fl))
  local count=f.u16(6)
  assert(count>0 and count<=4096 and count*8<=fl,"invalid NDS directory table")
  local nds={code=code,size=r.size}
  function nds.file(path)
    assert(type(path)=="string" and #path<=256,"invalid NDS filename")
    local components={}
    for part in path:gmatch("[^/]+") do
      assert(part~="." and part~=".." and not part:find("\0",1,true),"invalid NDS path")
      components[#components+1]=part
    end
    assert(#components>0 and #components<=32,"invalid NDS path")
    local dir=0
    for partIndex,part in ipairs(components) do
      assert(dir>=0 and dir<count,"NDS directory outside table")
      local pos,id=f.u32(dir*8),f.u16(dir*8+4)
      assert(pos>=count*8 and pos<fl,"NDS subtable outside names")
      local matched=false
      while pos<fl do
        local control=f.u8(pos); pos=pos+1
        if control==0 then break end
        local length,isDir=control%128,control>=128
        assert(length>0,"empty NDS name")
        local name=f.sub(pos,length); pos=pos+length
        local child
        if isDir then child=f.u16(pos); pos=pos+2 end
        if name==part then
          if partIndex==#components then
            assert(not isDir and id<al/8,"NDS path is not a file")
            local first,last=r.u32(ao+id*8),r.u32(ao+id*8+4)
            assert(last>=first,"invalid NDS file range"); r.bounds(first,last-first)
            return r.sub(first,last-first),id
          end
          assert(isDir and child>=0xf000,"NDS path is not a directory")
          dir=child-0xf000; matched=true; break
        end
        if not isDir then id=id+1 end
      end
      assert(matched,"NDS file not found: "..path)
    end
  end
  return nds
end
return Nds
