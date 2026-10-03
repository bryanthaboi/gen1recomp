-- Synthetic binary fixtures and pixel patterns only; no cartridge assets.
local Animation=require("src.import.gen5.Animation")
local Composer=require("src.import.gen5.Composer")
local function eq(a,b) assert(a==b,tostring(a).." ~= "..tostring(b)) end
local function u16(n) return string.char(n%256,math.floor(n/256)%256) end
local function u32(n) return u16(n%65536)..u16(math.floor(n/65536)) end
local function file(magic,tag,payload)
  return magic..string.rep("\0",12)..tag..u32(#payload+8)..payload
end
local tableEntry=u16(2)..u16(0)..u16(0)..u16(0)..u32(2)..u32(0)
local frameEntries=u32(0)..u16(2)..u16(0)..u32(2)..u16(1)..u16(0)
local fixture=file("RNAN","KNBA",u16(1)..u16(2)..u32(16)..u32(32)..u32(48)..
  tableEntry..frameEntries..u16(0)..u16(1))
local bank,err=Animation.nanr(fixture)
assert(bank,err)
eq(Animation.frame(bank,0,0).cell_id,0)
eq(Animation.frame(bank,0,1).cell_id,0)
eq(Animation.frame(bank,0,2).cell_id,1)
eq(Animation.frame(bank,0,3).cell_id,0)
eq(Animation.duration(bank,0),3)
assert(not Animation.nanr(fixture:sub(1,-2)),"truncation must fail")
assert(not Animation.nanr(fixture:sub(1,28)..u32(4294967295)..fixture:sub(33)),"offset must fail")
local mapFixture=file("RCMN","KBCM",u16(1)..u16(0)..u32(16)..string.rep("\0",8)..
  u16(1)..u16(0)..u32(0)..u16(0)..u16(65534)..u16(3)..u16(0))
local maps=assert(Animation.nmcr(mapFixture))
eq(maps.maps[1].records[1].x,-2)
eq(maps.maps[1].records[1].y,3)
local nmar=assert(Animation.nmar("RAMN"..fixture:sub(5)))
eq(Animation.frame(nmar,0,2).map_index,1)
local timeline={animations={{loop_start=1,playback_type=4,frames={
  {cell_id=0,duration=2},{cell_id=1,duration=3},{cell_id=2,duration=1}}}}}
eq(Animation.frame(timeline,0,0).cell_id,0)
eq(Animation.frame(timeline,0,5).cell_id,2)
eq(Animation.frame(timeline,0,6).cell_id,1)
eq(Animation.frame(timeline,0,9).cell_id,1)
eq(Animation.frame(timeline,0,12).cell_id,2)
local cycle={animations={{loop_start=0,playback_type=4,frames={
  {cell_id=0,duration=1},{cell_id=1,duration=1},{cell_id=2,duration=1}}}}}
eq(Animation.cycleTicks(cycle,{records={{animation_index=0}}}),5)
eq(Animation.loopPrefix(timeline,0),2)
cycle.animations[1].playback_type=3
eq(Animation.loopPrefix(cycle,0),4)
eq(Animation.cycleTicks(cycle,{records={{animation_index=0}}}),5)
eq(Composer.round(-0.1),0);eq(Composer.round(-0.6),-1)
eq(Composer.round(-1.4),-1);eq(Composer.round(-1.6),-2)
local graphics={bpp=4}
function graphics:getPixel(tile,x,y) return tile==0 and x==0 and y==0 and 1 or 0 end
local palette={colors={{r=0,g=0,b=0,a=0},{r=255,g=0,b=0,a=255}}}
local cell={oams={{x=0,y=0,width=8,height=8,tile_index=0,palette=0,priority=0}}}
local cells={cells={cell,cell}}
local pixels,width,height,bounds=Composer.renderIndexed(graphics,palette,cells,bank,maps,0,0)
eq(width,8);eq(height,8);eq(bounds.min_x,-2);eq(bounds.min_y,3);eq(pixels[1],1)
local count=0;for _ in pairs(pixels) do count=count+1 end;eq(count,1)
cell.oams[1].flip_h=true
pixels=Composer.renderIndexed(graphics,palette,cells,bank,maps,0,0)
eq(pixels[8],1);assert(not pixels[1])
cell.oams[1].flip_h=false
bank.animations[1].frames[1].translate_x=4
bounds=Composer.bounds(cells,bank,maps,0,0)
eq(bounds.min_x,2)
local union=Composer.unionBounds(cells,bank,maps,0,{0,2})
eq(union.min_x,-2);eq(union.max_x,10)
-- Same-priority serialized-first OAM wins, matching DS/reference ordering.
cell.oams[2]={x=0,y=0,width=8,height=8,tile_index=1,palette=0,priority=0}
function graphics:getPixel(tile,x,y) return x==0 and y==0 and tile+1 or 0 end
palette.colors[3]={r=0,g=255,b=0,a=255}
pixels=Composer.renderIndexed(graphics,palette,cells,bank,maps,0,0)
eq(pixels[1],1)
-- Parent scaling/translation expands the bounds predictably.
bounds=Composer.bounds(cells,bank,maps,0,0,{scale_x=8192,scale_y=4096,translate_x=10})
eq(bounds.min_x,14);eq(bounds.max_x,30)
print("Gen5 animation/compositor synthetic tests passed")
