package.path="./?.lua;./?/init.lua;"..package.path
local Binary=require("src.import.gen5.Binary")
local Nds=require("src.import.gen5.Nds")
local Narc=require("src.import.gen5.Narc")
local Lz=require("src.import.gen5.Lz")
local count=0
local function check(value) assert(value);count=count+1 end
local function rejects(fn) check(not pcall(fn)) end
local function u16(n) return string.char(n%256,math.floor(n/256)%256) end
local function u32(n) return u16(n%65536)..u16(math.floor(n/65536)) end
local r=Binary.reader(string.char(255,255,0,128))
check(r.u16(0)==65535);check(r.s16(0)==-1);check(r.s16(2)==-32768)
rejects(function()r.u8(-1)end);rejects(function()r.u32(1)end)
local chunks="BTAF"..u32(28)..u32(2)..u32(0)..u32(3)..u32(3)..u32(3)
  .."BTNF"..u32(8).."GMIF"..u32(11).."ABC"
local archive="NARC"..u16(0xfffe)..u16(0x100)..u32(16+#chunks)..u16(16)..u16(3)..chunks
local n=Narc.open(archive)
check(n.count==2);check(n.member(0)=="ABC");check(n.member(1)=="")
rejects(function()n.member(2)end)
rejects(function()Narc.open(archive:sub(1,-2))end)
local function fentry(pos,first,parent) return u32(pos)..u16(first)..u16(parent) end
local fnt=fentry(32,0,4)..fentry(37,0,0xf000)..fentry(42,0,0xf001)..fentry(47,0,0xf002)
  ..string.char(129).."a"..u16(0xf001).."\0"
  ..string.char(129).."0"..u16(0xf002).."\0"
  ..string.char(129).."0"..u16(0xf003).."\0"
  ..string.char(1).."4\0"
local header=string.rep("\0",512)
local function put(offset,value) header=header:sub(1,offset)..value..header:sub(offset+#value+1) end
put(12,"IRBO");put(0x40,u32(512)..u32(#fnt)..u32(512+#fnt)..u32(8))
local start=512+#fnt+8
local rom=header..fnt..u32(start)..u32(start+#archive)..archive
local nds=Nds.open(rom)
check(nds.file("/a/0/0/4")==archive)
rejects(function()nds.file("a/0/0/5")end)
rejects(function()nds.file("../a")end)
rejects(function()Nds.open(rom:sub(1,12).."IRDO"..rom:sub(17))end)
check(Lz.decode("RAW")=="RAW")
check(Lz.decode(string.char(0x10,6,0,0,32).."AB"..string.char(0x10,1))=="ABABAB")
check(Lz.decode(string.char(0x11,6,0,0,32).."AB"..string.char(0x30,1))=="ABABAB")
check(Lz.decode(string.char(0x11,19,0,0,64).."A"..string.char(0,0x10,0))==string.rep("A",19))
rejects(function()Lz.decode(string.char(0x10,4,0,0,128,0,0))end)
rejects(function()Lz.decode(string.char(0x10,255,255,255))end)
rejects(function()Lz.decode(string.char(0x10,4,0,0,0).."A")end)
print("gen5 containers PASS "..count.." checks")
