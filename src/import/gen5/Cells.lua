-- Adapted from AnimaEngine v1.0.0 ncer.c/nitro_util.c (MIT).
-- See PROVENANCE.md/ANIMAENGINE_LICENSE. No imported pixels here.
local Graphics=require("src.import.gen5.Graphics")
local Cells={}
local widths={{8,16,32,64},{16,32,32,64},{8,8,16,32}}
local heights={{8,16,32,64},{8,8,16,32},{16,32,32,64}}
local function bits(n,shift,mod) return math.floor(n/2^shift)%mod end

function Cells.parse(data)
  local r=Graphics.reader(data)
  r:bounds(0,0x20)
  assert(r:sub(0,4)=="RECN","invalid NCER signature")
  local section,size=r:section("KBEC")
  assert(size>=0x20,"invalid NCER section")
  local count=r:u16(section+8)
  assert(count>0 and count<=1024,"NCER cell count exceeds bounds")
  local offset=r:u32(section+12)
  local tableStart=section+8+offset
  local oamBase=tableStart+count*8
  assert(offset>=0x18 and oamBase<=section+size,"invalid NCER cell table")
  local cells={}
  for index=0,count-1 do
    local entry=tableStart+index*8
    local oamCount,attr,rawOffset=r:u16(entry),r:u16(entry+2),r:u32(entry+4)
    local start=oamBase+rawOffset
    assert(oamCount<=128 and start+oamCount*6<=section+size,"invalid NCER OAM range")
    local oams={}
    for i=0,oamCount-1 do
      local pos=start+i*6
      local a,b,c=r:u16(pos),r:u16(pos+2),r:u16(pos+4)
      local shape,objSize=bits(a,14,4),bits(b,14,4)
      assert(shape<3,"unsupported NCER OAM shape")
      local x,y=b%512,a%256
      if x>=256 then x=x-512 end
      if y>=128 then y=y-256 end
      local affine=bits(a,8,2)==1
      local doubled=affine and bits(a,9,2)==1
      local width,height=widths[shape+1][objSize+1],heights[shape+1][objSize+1]
      oams[i+1]={attr0=a,attr1=b,attr2=c,x=x,y=y,shape=shape,size=objSize,
        width=width,height=height,tile_index=c%1024,priority=bits(c,10,4),palette=bits(c,12,16),
        affine=affine,double_size=doubled,disabled=not affine and bits(a,9,2)==1,
        obj_mode=bits(a,10,4),affine_index=bits(b,9,32),
        flip_h=not affine and bits(b,12,2)==1,flip_v=not affine and bits(b,13,2)==1,
        draw_x=x+(doubled and width/2 or 0),draw_y=y+(doubled and height/2 or 0)}
    end
    cells[index+1]={oams=oams,oam_count=oamCount,cell_attr=attr,raw_oam_offset=rawOffset}
  end
  return {cells=cells,cell_count=count,cellCount=count}
end
Cells.ncer=Cells.parse
return Cells
