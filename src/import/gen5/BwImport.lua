-- Engine-owned Black/White battle-sprite pack importer. No external executable.
local Nds=require("src.import.gen5.Nds")
local Narc=require("src.import.gen5.Narc")
local Lz=require("src.import.gen5.Lz")
local Graphics=require("src.import.gen5.Graphics")
local Cells=require("src.import.gen5.Cells")
local Animation=require("src.import.gen5.Animation")
local Composer=require("src.import.gen5.Composer")
local Parts=require("src.import.gen5.Parts")
local LuaWriter=require("src.import.LuaWriter")
local Importers=require("src.import.Importers")
local StreamMD5=require("src.mods.StreamMD5")
local Bw={IMPORTER="gen5_bw",EXPORT_VERSION="1.1.0",COUNT=649,MAX_TICKS=240}

function Bw.open(rom)
  local nds=Nds.open(rom)
  local archive=Narc.open(nds.file("/a/0/0/4"))
  assert(archive.count>=650*20,"incomplete Black/White sprite archive")
  return archive,nds
end
function Bw.identify(rom)
  local ok,archive,nds=pcall(Bw.open,rom)
  if not ok then return nil,"Expected a Black/White NDS dump with its original sprite archive: "..tostring(archive) end
  if #rom~=268435456 then return nil,"Expected an untrimmed 256 MiB Black/White NDS dump." end
  local digest
  if love and love.data and love.data.hash then
    digest=love.data.encode("string","hex",love.data.hash("md5",rom))
  else digest=StreamMD5.new():update(rom):final() end
  return {name="Pokemon "..(nds.code:sub(1,3)=="IRB" and "Black" or "White").." ("..nds.code..")",
    md5=digest,size=#rom,gameCode=nds.code},archive
end
function Bw.readPokemon(archive,dex,side,female)
  assert(type(dex)=="number" and dex%1==0 and dex>=1 and dex<=Bw.COUNT,"invalid national dex")
  assert(side=="front" or side=="back","invalid sprite side")
  local base=dex*20
  local graphicsOffset=side=="front" and 2 or 11
  local genderFallback=false
  if female then
    local candidate=archive.member(base+graphicsOffset+1)
    genderFallback=#candidate==0
    if not genderFallback then graphicsOffset=graphicsOffset+1 end
  end
  local function member(offset) return Lz.decode(archive.member(base+offset)) end
  local first=side=="front" and 4 or 13
  local sprite={genderFallback=genderFallback,graphics=Graphics.parseGraphics(member(graphicsOffset)),
    cells=Cells.parse(member(first)),nanr=assert(Animation.nanr(member(first+1))),
    nmcr=assert(Animation.nmcr(member(first+2))),nmar=assert(Animation.nmar(member(first+3))),
    normal=Graphics.parsePalette(member(18)),shiny=Graphics.parsePalette(member(19))}
  sprite.map,sprite.animation=Animation.idle(sprite.nmar)
  assert(sprite.animation~=nil,"missing idle animation")
  return sprite
end
local function gcd(a,b) while b~=0 do a,b=b,a%b end;return a end
local function timeline(sprite)
  -- NMAR chooses the idle map. The export is the looping idle pose, without
  -- mixing its separate wait/break maps into the same battle animation.
  local period,intro=1,0
  do
    local map=assert(sprite.nmcr.maps[sprite.map+1],"missing idle multicell map")
    for _,record in ipairs(map.records) do
      local p,i=Animation.period(sprite.nanr,record.animation_index)
      -- A single fixed pose contributes no changing state to the loop LCM.
      if #sprite.nanr.animations[record.animation_index+1].frames==1 then p,i=1,0 end
      intro=math.max(intro,i)
      period=math.min(Bw.MAX_TICKS+1,period/gcd(period,p)*p)
    end
  end
  local total=intro+period
  assert(intro<Bw.MAX_TICKS,"animation introduction exceeds export bound")
  return math.min(total,Bw.MAX_TICKS),intro,total>Bw.MAX_TICKS
end

-- Keep sparse palette-index frames until the opaque union is known. Adjacent
-- equal timeline poses share a frame and retain exact 60 Hz duration metadata.
function Bw.poses(sprite,progress)
  local ticks,intro,capped=timeline(sprite)
  local frames,durations,last,loopStart={}, {}, nil,0
  local minx,miny,maxx,maxy=math.huge,math.huge,-math.huge,-math.huge
  for tick=0,ticks-1 do
    local map=assert(sprite.nmcr.maps[sprite.map+1],"missing idle multicell map")
    local signature={tostring(sprite.map)}
    for _,record in ipairs(map.records) do
      signature[#signature+1]=tostring(assert(Animation.frame(sprite.nanr,record.animation_index,tick)))
    end
    signature=table.concat(signature,"/")
    if tick==intro then loopStart=#frames end
    if signature~=last or tick==intro then
      local pixels,width,height,bounds=Composer.renderIndexed(sprite.graphics,sprite.normal,
        sprite.cells,sprite.nanr,sprite.nmcr,sprite.map,tick)
      local visible={}
      for offset,color in pairs(pixels) do
        local x=(offset-1)%width+bounds.min_x
        local y=math.floor((offset-1)/width)+bounds.min_y
        visible[#visible+1]={x=x,y=y,color=color}
        minx,miny,maxx,maxy=math.min(minx,x),math.min(miny,y),math.max(maxx,x+1),math.max(maxy,y+1)
      end
      frames[#frames+1]=visible;durations[#frames]=1;last=signature
    else durations[#frames]=durations[#frames]+1 end
    if progress then progress(tick+1,ticks) end
  end
  assert(minx<maxx and miny<maxy,"idle animation has no visible pixels")
  local width,height=maxx-minx,maxy-miny
  assert(width<=256 and height<=256 and #frames<=512,"sprite frame exceeds pack bounds")
  return {frames=frames,durations=durations,width=width,height=height,
    min_x=minx,min_y=miny,loopStartFrame=loopStart,ticks=ticks,cycleCapped=capped}
end
function Bw.image(poses,palette)
  assert(love and love.image,"LÖVE image module required for sprite import")
  local columns=math.min(16,#poses.frames)
  local rows=math.ceil(#poses.frames/columns)
  assert(poses.width*columns*poses.height*rows<=4*1024*1024,"atlas exceeds decoded memory bound")
  local image=love.image.newImageData(poses.width*columns,poses.height*rows)
  for index,frame in ipairs(poses.frames) do
    local ox=(index-1)%columns*poses.width-poses.min_x
    local oy=math.floor((index-1)/columns)*poses.height-poses.min_y
    for _,pixel in ipairs(frame) do
      local c=assert(palette.colors[pixel.color+1],"missing sprite palette color")
      image:setPixel(ox+pixel.x,oy+pixel.y,c.r/255,c.g/255,c.b/255,(c.a or 255)/255)
    end
  end
  return image,{width=poses.width,height=poses.height,columns=columns,frames=#poses.frames,
    tickRate=60,durations=poses.durations,loopStartFrame=poses.loopStartFrame,
    cycleTicks=poses.ticks,cycleCapped=poses.cycleCapped,anchorX=-poses.min_x,anchorY=-poses.min_y}
end
-- Complete long animations without a global loop: see Parts.lua.
-- Both return nil and a reason when a part-track bound is exceeded; the
-- variant then keeps its capped atlas and native fallback.
function Bw.parts(sprite,progress)
  local model,why=Parts.build(sprite,progress)
  if not model then return nil,why end
  return Parts.layout(model)
end
function Bw.partsAssets(model,sprite,checkpoint)
  local image=Parts.image(model,checkpoint)
  local ok,encoded=pcall(image.encode,image,"png");image:release();assert(ok,encoded)
  local bytes=encoded:getString();if encoded.release then encoded:release() end
  local meta=LuaWriter.encode(Parts.metadata(model,sprite))
  if #bytes>Importers.MAX_ENTRY_BYTES or #meta>Importers.MAX_ENTRY_BYTES then
    return nil,"part tracks exceed the pack entry limit"
  end
  return bytes,meta,Parts.stub(model)
end
function Bw.job(rom,fs,options)
  options=options or {}
  return coroutine.create(function()
    local source,archive=Bw.identify(rom);assert(source,archive)
    local species=options.species or {}
    if not options.species then for dex=1,Bw.COUNT do species[#species+1]=dex end end
    local entries,capped,parts,partsSkipped={},0,0,{}
    local total=#species*8
    local completed=0
    for _,dex in ipairs(species) do
      for _,side in ipairs({"front","back"}) do
        for _,female in ipairs({false,true}) do
          -- An empty female graphics member uses exactly the male graphics,
          -- cells, animation and palettes. Preserve its logical IDs while
          -- reusing the already published male atlas instead of rebuilding it.
          local genderFallback=female and #archive.member(dex*20+(side=="front" and 3 or 12))==0
          local sprite=not genderFallback and Bw.readPokemon(archive,dex,side,female) or nil
          local clock=love and love.timer and love.timer.getTime
          local sliceStart=clock and clock() or 0
          local poses=not genderFallback and Bw.poses(sprite,function(done,count)
            -- Avoid one launcher frame per source tick. Keep each slice at
            -- most eight ticks, with a 4 ms soft limit between compositions.
            if done%8==0 or done==count or (clock and clock()-sliceStart>=0.004) then
              coroutine.yield({done=completed+done/count*0.5,total=total,
                status=("Assembling %03d %s"):format(dex,side)})
              if clock then sliceStart=clock() end
            end
          end)
          -- The capped atlas stays as before for 1.0.x consumers. Its complete
          -- animation is published separately as independent part tracks.
          local partsId
          if poses and poses.cycleCapped then
            local id=("parts/%03d/%s%s"):format(dex,side,female and "/female" or "")
            sliceStart=clock and clock() or 0
            -- Renders yield every eight states; other checkpoints (done=nil)
            -- yield on the 4 ms soft limit only.
            local function pace(done,count)
              if (done and (done%8==0 or done==count)) or (clock and clock()-sliceStart>=0.004) then
                coroutine.yield({done=completed+0.5,total=total,
                  status=("Assembling %03d %s parts"):format(dex,side)})
                if clock then sliceStart=clock() end
              end
            end
            local model,why=Bw.parts(sprite,pace)
            local png,meta,stub
            if model then png,meta,stub=Bw.partsAssets(model,sprite,pace);why=png==nil and meta or why end
            if png then
              local base=source.md5.."/"..Bw.EXPORT_VERSION.."/"..id
              local size,err=Importers.writeAsset(Bw.IMPORTER,"battle_sprites",base..".png",png,fs);assert(size,err)
              local metaSize,metaErr=Importers.writeAsset(Bw.IMPORTER,"battle_sprites",base..".lua",meta,fs)
              assert(metaSize,metaErr)
              entries[id]={file=base..".png",size=size,width=stub.width,height=stub.height*stub.frames,
                frames=stub.frames,sprite=stub,metadata={file=base..".lua",size=metaSize}}
              partsId,parts=id,parts+1
            else partsSkipped[#partsSkipped+1]=id..": "..tostring(why) end
            -- Keep part publication and the atlas encodes in separate slices.
            coroutine.yield({done=completed+0.5,total=total,status=("Published %03d %s parts"):format(dex,side)})
          end
          for _,palette in ipairs({"normal","shiny"}) do
            local id=("%s/%03d/%s%s"):format(palette,dex,side,female and "/female" or "")
            if genderFallback then
              local male=assert(entries[("%s/%03d/%s"):format(palette,dex,side)],"missing male atlas")
              local alias={}
              for key,value in pairs(male) do alias[key]=value end
              entries[id]=alias
              if alias.sprite.cycleCapped then capped=capped+1 end
            else
              local image,metadata=Bw.image(poses,sprite[palette])
              if partsId then metadata.partsEntry,metadata.partsPalette=partsId,palette end
              local width,height=image:getDimensions()
              local ok,encoded=pcall(image.encode,image,"png");image:release();assert(ok,encoded)
              local bytes=encoded:getString();if encoded.release then encoded:release() end
              -- Content paths include source+export version. An interrupted new
              -- import cannot overwrite another source/version's published pack.
              local file=source.md5.."/"..Bw.EXPORT_VERSION.."/"..id..".png"
              local size,err=Importers.writeAsset(Bw.IMPORTER,"battle_sprites",file,bytes,fs);assert(size,err)
              entries[id]={file=file,size=size,width=width,height=height,frames=#poses.frames,sprite=metadata}
              if poses.cycleCapped then capped=capped+1 end
            end
            completed=completed+1
            coroutine.yield({done=completed,total=total,status="Imported "..id})
          end
        end
      end
    end
    local ok,err=Importers.writePack(Bw.IMPORTER,"battle_sprites",{
      format=1,importer=Bw.IMPORTER,pack="battle_sprites",kind="sprite",version=Bw.EXPORT_VERSION,
      source=source,entries=entries},fs);assert(ok,err)
    return {source=source,packs={battle_sprites=completed},skipped={},cappedCycles=capped,partTracks=parts,
      partTracksSkipped=partsSkipped}
  end)
end
return Bw
