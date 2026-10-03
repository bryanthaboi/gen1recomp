package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.modkit")
local path="mods/examples/gen5_battle_sprites"
local function read(file) local f=assert(io.open(file,"rb"));local bytes=f:read("*a");f:close();return bytes end
local source,manifest=read(path.."/main.lua"),read(path.."/manifest.json")
local function baseFiles() return {
  ["mods/GEN5_PRIVATE_SPRITES/main.lua"]=source,
  ["mods/GEN5_PRIVATE_SPRITES/manifest.json"]=manifest} end
local function run(files) return T.sdk.loadMod("mods/GEN5_PRIVATE_SPRITES",{fs=T.sdk.memfs(files)}) end
local missing=run(baseFiles())
T.eq(#missing.errors,0,"actual loader accepts absent optional pack")
T.eq(missing.loader.exports.GEN5_PRIVATE_SPRITES.frame({dex=25,side="front"}),nil,"absent pack preserves native sprite")
missing.release()

local function u32(n) return string.char(math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256) end
local png=string.char(137).."PNG"..string.char(13,10,26,10)..u32(13).."IHDR"..u32(6)..u32(2)
local pack={format=1,importer="gen5_bw",pack="battle_sprites",kind="sprite",version="1.0.0",
  source={name="Procedural test fixture",md5=string.rep("0",32),size=0},entries={}}
local function entry(capped)
  return {file="synthetic.png",size=#png,width=6,height=2,
    sprite={width=2,height=2,columns=3,frames=3,tickRate=60,durations={6,12,18},
      loopStartFrame=1,cycleTicks=36,cycleCapped=capped or false}}
end
pack.entries["normal/025/front"]=entry()
pack.entries["normal/025/front/female"]=entry()
pack.entries["normal/026/front"]=entry(true)
local function encode(value)
  if type(value)=="string" then return string.format("%q",value) end
  if type(value)~="table" then return tostring(value) end
  local fields={}
  for key,item in pairs(value) do fields[#fields+1]="["..encode(key).."]="..encode(item) end
  return "{"..table.concat(fields,",").."}"
end
local files=baseFiles()
files["asset_packs/gen5_bw/battle_sprites/pack.lua"]="return "..encode(pack)
files["asset_packs/gen5_bw/battle_sprites/synthetic.png"]=png
local oldImage,oldNewImage,oldFileData=love.image.newImageData,love.graphics.newImage,love.filesystem.newFileData
local decodes=0
love.filesystem.newFileData=function(bytes)return bytes end
love.image.newImageData=function(a)
  if type(a)=="string" then decodes=decodes+1;return {getPixel=function(_,x,y)return x,y,0,1 end,release=function()end} end
  return {setPixel=function()end,release=function()end}
end
love.graphics.newImage=function()return {setFilter=function()end,release=function()end} end
local installed=run(files)
T.eq(#installed.errors,0,"real loader reads native optional pack through scoped API")
local e=assert(installed.loader.exports.GEN5_PRIVATE_SPRITES)
T.eq(e.apiVersion,2,"native-resolution receiver contract")
T.check(e.status().ready,"native pack metadata accepted")
T.eq(e.capabilities.source,"gen5_bw","source capability")
local request={dex=25,side="front",battleId=1,battlerId=1,mon={}}
local function step(dt) installed.loader.hooks:call("input.step",function()end,{},dt) end
local a,b,c=installed.loader.hooks:call("input.step",function()return 7,nil,9 end,{},0)
T.eq(a,7,"clock hook preserves first native return")
T.eq(b,nil,"clock hook preserves nil native return")
T.eq(c,9,"clock hook preserves trailing native return")
T.eq(e.frame(request).frame,1,"intro starts first")
T.eq(e.frame(request).width,2,"small sprites retain original width")
T.eq(e.frame(request).height,2,"small sprites retain original height")
T.eq(e.frame(request).groundOffset,1,"small sprite anchor tracks its height")
step(0.1);T.eq(e.frame(request).frame,2,"six tick intro ends")
T.eq(e.frame(request).frame,2,"second eye leaves clock unchanged")
step(0.2);T.eq(e.frame(request).frame,3,"unequal twelve tick frame ends")
step(0.3);T.eq(e.frame(request).frame,2,"loop repeats suffix without replaying intro")
step(0.5);T.eq(e.frame(request).frame,2,"second suffix loop skips intro")
T.eq(decodes,1,"frame cache reuses decoded atlas")
request.mon={};T.eq(e.frame(request).frame,1,"switch restarts intro")
request.gender="female";T.eq(e.frame(request).entryId,"normal/025/front/female","female entry selected")
request.shiny=true;T.eq(e.frame(request),nil,"missing shiny retains native palette")
request.shiny=false;request.form=1;T.eq(e.frame(request),nil,"unsupported form falls back")
request.form=0;request.dex=26;T.eq(e.frame(request),nil,"capped cycle uses native fallback")
installed.loader.events:emit("core.session_ending",{})
T.eq(e.status().cachedImages,0,"session releases GPU images")
T.eq(e.status().cachedAtlases,0,"session releases decoded atlases")
installed.release()
love.image.newImageData,love.graphics.newImage,love.filesystem.newFileData=oldImage,oldNewImage,oldFileData
T.finish("native_gen5_provider")
