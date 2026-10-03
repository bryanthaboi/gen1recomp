-- Provider 2.0 part-track playback through the real ModSDK loader. Lives with
-- the engine tests because it builds procedural fixtures with engine modules.
package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.modkit")
local path="mods/examples/gen5_battle_sprites"
local function read(file) local f=assert(io.open(file,"rb"));local bytes=f:read("*a");f:close();return bytes end
local source,manifest=read(path.."/main.lua"),read(path.."/manifest.json")
local function baseFiles() return {
  ["mods/GEN5_PRIVATE_SPRITES/main.lua"]=source,
  ["mods/GEN5_PRIVATE_SPRITES/manifest.json"]=manifest} end
local function run(files) return T.sdk.loadMod("mods/GEN5_PRIVATE_SPRITES",{fs=T.sdk.memfs(files)}) end
local function u32(n) return string.char(math.floor(n/16777216)%256,math.floor(n/65536)%256,math.floor(n/256)%256,n%256) end
local png=string.char(137).."PNG"..string.char(13,10,26,10)..u32(13).."IHDR"..u32(6)..u32(2)
local function entry(capped)
  return {file="synthetic.png",size=#png,width=6,height=2,
    sprite={width=2,height=2,columns=3,frames=3,tickRate=60,durations={6,12,18},
      loopStartFrame=1,cycleTicks=36,cycleCapped=capped or false}}
end
local function encode(value)
  if type(value)=="string" then return string.format("%q",value) end
  if type(value)~="table" then return tostring(value) end
  local fields={}
  for key,item in pairs(value) do fields[#fields+1]="["..encode(key).."]="..encode(item) end
  return "{"..table.concat(fields,",").."}"
end
local oldImage,oldNewImage,oldFileData=love.image.newImageData,love.graphics.newImage,love.filesystem.newFileData
love.filesystem.newFileData=function(bytes)return bytes end
local files
-- Exporter 1.1 part tracks: a procedural sprite wider than 64 pixels whose
-- tracks have different intros and loops. All original pixels must survive.
local Parts=require("src.import.gen5.Parts")
local LuaWriter=require("src.import.LuaWriter")
local graphics={bpp=4}
function graphics:getPixel(tile,x,y)
  if (x*3+y+tile)%7==0 then return 0 end
  return (tile*5+x+y*2)%15+1
end
local function palette(shift)
  local colors={{r=0,g=0,b=0,a=0}}
  for i=1,15 do colors[i+1]={r=(i*17+shift)%256,g=(i*29)%256,b=(i*41+shift)%256,a=255} end
  return {colors=colors}
end
local function oam(x,y,w,h,tile,priority) return {x=x,y=y,width=w,height=h,tile_index=tile,palette=0,priority=priority} end
local cells={cells={{oams={oam(-8,-8,16,16,0,1)}},{oams={oam(-8,-4,16,8,8,0),oam(-4,-8,8,16,16,2)}},
  {oams={oam(-16,-8,32,16,24,1)}},{oams={oam(-4,-4,8,8,40,0)}}}}
local nanr={animations={
  {loop_start=1,playback_type=2,frames={{cell_id=0,duration=3},{cell_id=1,duration=5},{cell_id=0,duration=7,translate_y=-3}}},
  {loop_start=0,playback_type=4,frames={{cell_id=2,duration=4},{cell_id=3,duration=6,rotation=4096},{cell_id=2,duration=5,translate_x=4}}},
  {loop_start=0,playback_type=2,frames={{cell_id=3,duration=11,scale_x=8192},{cell_id=1,duration=2}}},
  {loop_start=0,playback_type=1,frames={{cell_id=1,duration=9},{cell_id=2,duration=1,translate_y=2}}}}}
local nmcr={maps={{records={{animation_index=0,x=-40,y=0},{animation_index=1,x=0,y=4},
  {animation_index=2,x=40,y=-6},{animation_index=3,x=10,y=10}}}}}
local sprite={graphics=graphics,cells=cells,nanr=nanr,nmcr=nmcr,map=0,normal=palette(0),shiny=palette(90)}
local model=Parts.layout(Parts.build(sprite))
T.check(model.width>64,"procedural part sprite exercises full-width output beyond 64 pixels")
local meta=Parts.metadata(model,sprite)
local metaBytes=LuaWriter.encode(meta)
local stub=Parts.stub(model)
local rgba={}
for i=1,model.atlasWidth*model.atlasHeight do rgba[i]="\0\0\0\0" end
for i,piece in ipairs(model.pieces) do
  for y=0,piece.h-1 do for x=0,piece.w-1 do
    local v=model.data[i][y*piece.w+x+1]
    if v~=0 then rgba[(piece.ay+y)*model.atlasWidth+piece.ax+x+1]=string.char(v,0,0,255) end
  end end
end
rgba=table.concat(rgba)
local partsPng=string.char(137).."PNG"..string.char(13,10,26,10)..u32(13).."IHDR"..u32(model.atlasWidth)..u32(model.atlasHeight).."parts"
local partsPack={format=1,importer="gen5_bw",pack="battle_sprites",kind="sprite",version="1.1.0",
  source={name="Procedural test fixture",md5=string.rep("0",32),size=0},entries={}}
partsPack.entries["normal/025/front"]=entry()
-- A large atlas fixture must keep every source pixel in native mode.
local largePng=string.char(137).."PNG"..string.char(13,10,26,10)..u32(13).."IHDR"..u32(90)..u32(85)
partsPack.entries["normal/384/front"]={file="large.png",size=#largePng,width=90,height=85,
  sprite={width=90,height=85,columns=1,frames=1,tickRate=60,durations={12}}}
partsPack.entries["parts/030/front"]={file="parts.png",size=#partsPng,width=stub.width,height=stub.height*stub.frames,
  frames=stub.frames,sprite=stub,metadata={file="parts.lua",size=#metaBytes}}
for _,name in ipairs({"normal","shiny"}) do
  local capped=entry(true);capped.sprite.partsEntry="parts/030/front";capped.sprite.partsPalette=name
  partsPack.entries[name.."/030/front"]=capped
end
local broken=entry(true);broken.sprite.partsEntry="parts/031/front";broken.sprite.partsPalette="normal"
partsPack.entries["normal/031/front"]=broken
local badMeta="return {format='gen5-parts',version=99}"
partsPack.entries["parts/031/front"]={file="parts.png",size=#partsPng,width=stub.width,height=stub.height*stub.frames,
  frames=stub.frames,sprite=stub,metadata={file="bad.lua",size=#badMeta}}
-- Unscaled fixture: a 4x affine object paints one column past its own box,
-- shown only on ticks where another track widens the canvas.
local flat={bpp=4}
function flat:getPixel(tile) return tile+1 end
local fringeSprite={graphics=flat,map=0,normal=palette(0),shiny=palette(5),
  cells={cells={{oams={oam(0,0,8,8,7,1)}},{oams={oam(0,0,2,2,8,1)}}}},
  nanr={animations={{loop_start=0,playback_type=2,frames={{cell_id=0,duration=1,scale_x=16384,scale_y=16384}}},
    {loop_start=0,playback_type=2,frames={{cell_id=1,duration=3},{cell_id=1,duration=2,translate_x=-20}}}}},
  nmcr={maps={{records={{animation_index=0,x=0,y=0},{animation_index=1,x=4,y=4}}}}}}
local fringeModel=Parts.layout(Parts.build(fringeSprite))
local fringeMeta=Parts.metadata(fringeModel,fringeSprite)
local fringeMetaBytes=LuaWriter.encode(fringeMeta)
local fringeStub=Parts.stub(fringeModel)
local fringeRgba={}
for i=1,fringeModel.atlasWidth*fringeModel.atlasHeight do fringeRgba[i]="\0\0\0\0" end
for i,piece in ipairs(fringeModel.pieces) do
  for y=0,piece.h-1 do for x=0,piece.w-1 do
    local v=fringeModel.data[i][y*piece.w+x+1]
    if v~=0 then fringeRgba[(piece.ay+y)*fringeModel.atlasWidth+piece.ax+x+1]=string.char(v,0,0,255) end
  end end
end
fringeRgba=table.concat(fringeRgba)
local fringePng=string.char(137).."PNG"..string.char(13,10,26,10)..u32(13).."IHDR"..u32(fringeModel.atlasWidth)..u32(fringeModel.atlasHeight).."fringe"
partsPack.entries["parts/033/front"]={file="fringe.png",size=#fringePng,width=fringeStub.width,
  height=fringeStub.height*fringeStub.frames,frames=fringeStub.frames,sprite=fringeStub,
  metadata={file="fringe.lua",size=#fringeMetaBytes}}
local fringeEntry=entry(true);fringeEntry.sprite.partsEntry="parts/033/front";fringeEntry.sprite.partsPalette="normal"
partsPack.entries["normal/033/front"]=fringeEntry
for i=40,46 do
  local pid=("parts/%03d/front"):format(i)
  partsPack.entries[pid]={file="parts.png",size=#partsPng,width=stub.width,height=stub.height*stub.frames,
    frames=stub.frames,sprite=stub,metadata={file="parts.lua",size=#metaBytes}}
  local capped=entry(true);capped.sprite.partsEntry=pid;capped.sprite.partsPalette="normal"
  partsPack.entries[("normal/%03d/front"):format(i)]=capped
end
local orphan=entry(true);orphan.sprite.partsEntry="parts/099/front";orphan.sprite.partsPalette="normal"
partsPack.entries["normal/032/front"]=orphan
files=baseFiles()
files["asset_packs/gen5_bw/battle_sprites/pack.lua"]="return "..encode(partsPack)
files["asset_packs/gen5_bw/battle_sprites/synthetic.png"]=png
files["asset_packs/gen5_bw/battle_sprites/large.png"]=largePng
files["asset_packs/gen5_bw/battle_sprites/parts.png"]=partsPng
files["asset_packs/gen5_bw/battle_sprites/parts.lua"]=metaBytes
files["asset_packs/gen5_bw/battle_sprites/bad.lua"]=badMeta
files["asset_packs/gen5_bw/battle_sprites/fringe.png"]=fringePng
files["asset_packs/gen5_bw/battle_sprites/fringe.lua"]=fringeMetaBytes
local composes,partDecodes,lastPixels=0,0,nil
love.image.newImageData=function(a,b,c,d)
  if type(a)=="string" then
    if a==partsPng then partDecodes=partDecodes+1;return {getString=function()return rgba end,release=function()end} end
    if a==fringePng then return {getString=function()return fringeRgba end,release=function()end} end
    return {getPixel=function(_,x,y)return x,y,0,1 end,release=function()end}
  end
  if c=="rgba8" then
    composes=composes+1;lastPixels=d
    T.check(#d==a*b*4,"composite byte length matches native dimensions")
  end
  local data={width=a,height=b,pixels=d,samples={},release=function()end}
  function data:setPixel(x,y,r,g,blue,alpha) self.samples[y*self.width+x+1]={r,g,blue,alpha} end
  return data
end
love.graphics.newImage=function(data)return {setFilter=function()end,release=function()end,
  pixels=data.pixels,width=data.width,height=data.height,samples=data.samples} end
local partsRun=run(files)
T.eq(#partsRun.errors,0,"real loader reads a 1.1 pack with part-track metadata")
local pe=assert(partsRun.loader.exports.GEN5_PRIVATE_SPRITES)
T.check(pe.status().ready,"1.1 pack index accepted, inert parts descriptor validated")
local function pstep(dt) partsRun.loader.hooks:call("input.step",function()end,{},dt) end
local function expected(tick,name,m,md)
  local model,meta=m or model,md or meta
  local idx=Parts.composeIndexed(model,tick)
  local W,H=model.width,model.height
  local pal,out=meta.palettes[name],{}
  for i=1,W*H do out[i]="\0\0\0\0" end
  for y=0,H-1 do for x=0,W-1 do
    local v=idx[y*W+x+1]
    if v then out[y*W+x+1]=string.char(pal[v*4+1],pal[v*4+2],pal[v*4+3],pal[v*4+4]) end
  end end
  return table.concat(out)
end
local preq={dex=30,side="front",battleId=2,battlerId=1,mon={}}
local first=assert(pe.frame(preq),"capped entry with part tracks plays instead of falling back")
T.eq(first.entryId,"normal/030/front","part entry id")
T.eq(first.width,model.width,"part output width");T.eq(first.height,model.height,"part output height")
T.eq(partDecodes,1,"part atlas decoded once")
local exact,tick,before=true,0,composes
for t=0,400 do
  local frame=assert(pe.frame(preq))
  local again=assert(pe.frame(preq))
  if frame.image~=again.image or frame.frame~=t+1 then exact=false;print("stereo/tick mismatch",t);break end
  if frame.image.pixels~=expected(t,"normal") then exact=false;print("pixel mismatch at tick",t);break end
  pstep(1/60);tick=t+1
end
T.check(exact,"401 consecutive ticks: intro then independent loops match the reference compositor; eyes share one image")
T.check(composes-before<401,"unchanged state combinations reuse cached composites")
pstep(100000)
local deep=assert(pe.frame(preq))
T.eq(deep.image.pixels,expected(deep.frame-1,"normal"),"deep tick far beyond every loop stays exact")
T.check(deep.frame-1>6000000,"deep tick really advanced on the shared clock")
local shinyReq={dex=30,side="front",shiny=true,battleId=2,battlerId=2,mon={}}
local shiny=assert(pe.frame(shinyReq))
T.eq(shiny.image.pixels,expected(0,"shiny"),"shiny palette applied to the same part tracks")
T.eq(partDecodes,1,"normal and shiny share one decoded part model")
preq.mon={}
T.eq(pe.frame(preq).image.pixels,expected(0,"normal"),"battler change restarts every track")
local fringeReq={dex=33,side="front",battleId=3,battlerId=1,mon={}}
local fringeExact,shown=true,{}
for t=0,9 do
  local frame=assert(pe.frame(fringeReq))
  local want=expected(t,"normal",fringeModel,fringeMeta)
  if frame.image.pixels~=want then fringeExact=false;print("fringe mismatch",t) end
  shown[want]=true
  pstep(1/60)
end
local variants=0;for _ in pairs(shown) do variants=variants+1 end
T.check(fringeExact and variants==2,"per-tick canvas clip: fringe column appears only on widened-canvas ticks")
T.eq(pe.frame({dex=31,side="front"}),nil,"invalid part metadata keeps native artwork")
T.check(pe.frame(preq)~=nil,"a broken part entry does not disable other sprites")
T.eq(pe.frame({dex=32,side="front"}),nil,"capped entry naming a missing part entry keeps native artwork")
T.check(pe.frame({dex=25,side="front"})~=nil,"atlas entries still play next to part entries")
local st=pe.status()
T.check(st.cachedImages<=8 and st.cachedComposites<=16 and st.cachedPartPlans<=16 and st.cachedPartPixels<=6,
  "bounded image, composite, plan and pixel caches")
-- Seven distinct part entries in rotation: once composed, stereo repeats and
-- unchanged ticks must not decode or reload anything.
local rotation={}
for i=40,46 do
  local pid=("parts/%03d/front"):format(i)
  rotation[#rotation+1]={dex=i,side="front",battleId=4,battlerId=i,mon={}}
end
local decodesBefore=partDecodes
for _,req in ipairs(rotation) do T.check(pe.frame(req)~=nil,"rotation sprite plays") end
local afterFirst=partDecodes
for _,req in ipairs(rotation) do pe.frame(req) end
T.eq(partDecodes,afterFirst,"repeated calls at the same tick reuse composites without decoding")
T.check(afterFirst-decodesBefore<=7,"each rotation sprite decodes at most once to compose")
-- Native resolution is the only output contract; no 64x64 resampling path.
T.check(pe.capabilities.nativeResolution==true,"provider advertises native resolution")
local function nativeExpected(tick,name)
  local idx=Parts.composeIndexed(model,tick)
  local pal,out=meta.palettes[name],{}
  for i=1,model.width*model.height do
    local v=idx[i]
    out[i]=v and string.char(pal[v*4+1],pal[v*4+2],pal[v*4+3],pal[v*4+4]) or "\0\0\0\0"
  end
  return table.concat(out)
end
preq.mon={}
local nativeFirst=assert(pe.frame(preq))
T.eq(nativeFirst.width,model.width,"native parts preserve original width")
T.eq(nativeFirst.height,model.height,"native parts preserve original height")
T.eq(nativeFirst.groundOffset,model.height/2,"native bottom anchor uses image half-height")
local nativeExact=true
for t=0,400 do
  local nf=assert(pe.frame(preq))
  if nf.image.pixels~=nativeExpected(t,"normal") or nf.frame~=t+1 then nativeExact=false;break end
  if pe.frame(preq).image~=nf.image then nativeExact=false;break end
  pstep(1/60)
end
T.check(nativeExact,"401 native frames retain every pixel; stereo shares the image and clock")
pstep(100000)
local nativeDeep=assert(pe.frame(preq))
T.eq(nativeDeep.image.pixels,nativeExpected(nativeDeep.frame-1,"normal"),"native parts stay exact past six million ticks")
local nativeShiny={dex=30,side="front",shiny=true,battleId=8,battlerId=1,mon={}}
T.eq(pe.frame(nativeShiny).image.pixels,nativeExpected(0,"shiny"),"native shiny palette is exact")
local largeReq={dex=384,side="front",battleId=9,battlerId=1,mon={}}
local large=assert(pe.frame(largeReq))
T.eq(large.width,90,"native atlas keeps Rayquaza-sized width")
T.eq(large.height,85,"native atlas keeps Rayquaza-sized height")
T.eq(large.groundOffset,42.5,"odd native height preserves bottom anchor")
local allPixels=true
for y=0,84 do for x=0,89 do
  local pixel=large.image.samples[y*90+x+1]
  if not pixel or pixel[1]~=x or pixel[2]~=y then allPixels=false end
end end
T.check(allPixels,"native atlas copies all 7650 pixels without resampling")
T.eq(pe.apiVersion,2,"variable dimension output declares receiver API 2")
T.eq(pe.frame(largeReq).image,large.image,"native atlas cache reuses the same full-resolution image")
st=pe.status()
T.check(st.cachedImages<=8 and st.cachedComposites<=16 and st.cachedPartPlans<=16 and st.cachedPartPixels<=6,
  "native resolution caches remain bounded")
partsRun.loader.events:emit("core.session_ending",{})
st=pe.status()
T.check(st.cachedComposites==0 and st.cachedPartPlans==0 and st.cachedPartPixels==0,"session releases part caches")
T.eq(st.cachedImages,0,"session releases atlas images")
partsRun.release()
love.image.newImageData,love.graphics.newImage,love.filesystem.newFileData=oldImage,oldNewImage,oldFileData
T.finish("gen5 provider part tracks")
