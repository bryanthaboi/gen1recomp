-- ROM-free bounded NCGR/NCLR/NCER parser tests, run from the engine root.
package.path="./?.lua;./?/init.lua;"..package.path
local G=require("src.import.gen5.Graphics")
local C=require("src.import.gen5.Cells")
local checks=0
local function eq(a,b,message) assert(a==b,(message or "mismatch")..": "..tostring(a).." ~= "..tostring(b));checks=checks+1 end
local function rejects(fn,message) local ok=pcall(fn);eq(ok,false,message) end
local function u16(n)return string.char(n%256,math.floor(n/256)%256)end
local function u32(n)return u16(n%65536)..u16(math.floor(n/65536))end
local function container(magic,section,body)
  return magic..u16(0xfffe)..u16(0x100)..u32(24+#body)..u16(16)..u16(1)..section..u32(8+#body)..body
end
local function ncgr(bpp,linear,payload,width)
  return container("RGCN","RAHC",u16(width or 1)..u16(1)..u32(bpp==4 and 3 or 4)
    ..u32(0)..u32(linear and 1 or 0)..u32(#payload)..u32(0)..payload)
end
local four=G.ncgr(ncgr(4,false,string.char(0x21)..string.rep(string.char(0x43),31)))
eq(four:getPixel(0,0,0),1,"low nibble first")
eq(four:getPixel(0,1,0),2,"high nibble second")
eq(four:getPixel(0,7,7),4,"4bpp tile end")
eq(four:getPixel(1,0,0),0,"out of range tile transparent")
eq(four:getPixel(0,-1,0),0,"out of range pixel transparent")
local bytes={}
for i=0,2047 do
  local pixel=i*2; local a=(math.floor(pixel/256)+pixel%256)%16
  local b=(math.floor((pixel+1)/256)+(pixel+1)%256)%16
  bytes[#bytes+1]=string.char(a+b*16)
end
local linear=G.ncgr(ncgr(4,true,table.concat(bytes),192))
eq(linear.width_tiles,32,"Gen V stride overrides misleading header")
eq(linear.tile_count,64,"linear tile count")
eq(linear:getPixel(1,0,0),8,"linear tile horizontal origin")
eq(linear:getPixel(0,0,1),1,"linear row origin")
eq(linear:getPixel(32,0,0),8,"linear next tile row")
bytes={};for i=0,127 do bytes[#bytes+1]=string.char(i)end
local eight=G.ncgr(ncgr(8,false,table.concat(bytes)))
eq(eight:getPixel(1,3,2),83,"8bpp direct tile addressing")
local palette=G.nclr(container("RLCN","TTLP",u32(3)..u32(0)..u32(6)..u32(0)..u16(0)..u16(31)..u16(0x7fff)))
eq(palette.color_count,3,"palette count")
eq(palette.colors[1].a,0,"palette zero transparent")
eq(palette.colors[2].r,255,"BGR555 red expansion")
eq(palette.colors[2].g,0,"BGR555 green channel")
eq(palette.colors[3].b,255,"BGR555 white expansion")
eq(palette.colors[3].a,255,"nonzero palette opaque")
local header=u16(1)..u16(0)..u32(0x18)..string.rep('\0',16)
local tableEntry=u16(2)..u16(7)..u32(0)
local first=u16(200+512)..u16(500+4096+8192+16384)..u16(3+2*1024+7*4096)
local second=u16(129+256+512+16384)..u16(255+9*512)..u16(8)
local cellData=container("RECN","KBEC",header..tableEntry..first..second)
local cells=C.ncer(cellData)
eq(cells.cell_count,1,"cell count")
local o=cells.cells[1].oams[1]
eq(o.x,-12,"signed 9bit X")
eq(o.y,-56,"signed 8bit Y")
eq(o.width,16,"square OAM size")
eq(o.priority,2,"OAM priority")
eq(o.palette,7,"palette bank")
eq(o.tile_index,3,"tile index")
eq(o.flip_h,true,"horizontal flip")
eq(o.flip_v,true,"vertical flip")
eq(o.disabled,true,"non affine disabled flag")
local a=cells.cells[1].oams[2]
eq(a.affine,true,"affine flag")
eq(a.double_size,true,"affine double size")
eq(a.width,16,"horizontal shape width")
eq(a.height,8,"horizontal shape height")
eq(a.draw_x,263,"affine doubled origin adds half width")
eq(a.draw_y,-123,"affine doubled origin adds half height")
eq(a.flip_h,false,"affine index does not imply flip")
eq(a.affine_index,9,"affine matrix index")
rejects(function()G.ncgr('RGCN')end,"truncated NCGR rejected")
rejects(function()G.ncgr(ncgr(4,false,'abc'))end,"partial tiles rejected")
rejects(function()G.nclr(container("RLCN","TTLP",u32(0)..u32(0)..u32(1000)..u32(0)..u16(0)))end,"palette out of section rejected")
rejects(function()C.ncer(cellData:sub(1,-2))end,"truncated OAM rejected")
rejects(function()C.ncer(container("RECN","KBEC",header..u16(129)..u16(0)..u32(0)..first))end,"OAM allocation limit")
rejects(function()C.ncer(container("RECN","KBEC",header..u16(1)..u16(0)..u32(0)..u16(0xc000)..u16(0)..u16(0)))end,"reserved OAM shape")
print(string.format("Gen 5 graphics: %d/%d checks passed",checks,checks))
