-- ROM-free job regression: missing female graphics must alias male assets,
-- while actual female art still gets composed/encoded and published separately.
for _,name in ipairs({'Nds','Narc','Lz','Graphics','Cells','Animation','Composer','Parts'}) do
  package.loaded['src.import.gen5.'..name]={}
end
package.loaded['src.mods.StreamMD5']={}
local writes,published,encoded,read,composed,partsBuilt=0,nil,0,{},{},{}
package.loaded['src.import.Importers']={
  writeAsset=function(importer,pack,file,bytes) writes=writes+1;return #bytes end,
  writePack=function(importer,pack,manifest) published=manifest;return true end,
}
love={image={}}
local Bw=require('src.import.gen5.BwImport')
assert(Bw.EXPORT_VERSION=='1.1.0')
local archive={member=function(index)
  -- Dex25 has distinct front female art; dex252 has none on either side.
  return index==25*20+3 and 'female art' or ''
end}
Bw.identify=function() return {md5='fixture'},archive end
Bw.readPokemon=function(_,dex,side,female)
  local key=dex..'/'..side..'/'..tostring(female)
  read[#read+1]=key
  return {key=key,normal='normal',shiny='shiny',capped=dex==252}
end
Bw.poses=function(sprite,progress)
  composed[#composed+1]=sprite.key
  progress(1,1)
  return {frames={{}},cycleCapped=sprite.capped}
end
Bw.image=function(poses,palette)
  return {getDimensions=function()return 8,8 end,release=function()end,
    encode=function()
      encoded=encoded+1
      return {getString=function()return palette end,release=function()end}
    end}, {cycleCapped=poses.cycleCapped,frames=1,tickRate=60,durations={1}}
end
-- Capped graphics also publish one shared part-track entry for both palettes.
Bw.parts=function(sprite,progress)
  partsBuilt[#partsBuilt+1]=sprite.key
  progress(1,1)
  return {key=sprite.key}
end
Bw.partsAssets=function(model)
  return 'parts '..model.key,'return {}',{kind='parts',width=256,height=64,frames=1,columns=1,
    tickRate=60,durations={1},cycleTicks=1,cycleCapped=true}
end
local job=Bw.job('no ROM',{}, {species={25,252}})
local lastDone,result=0,nil
while coroutine.status(job)~='dead' do
  local ok,value=coroutine.resume(job);assert(ok,value)
  if coroutine.status(job)=='dead' then result=value
  else
    assert(value.total==16 and value.done>=lastDone and value.done<=16)
    lastDone=value.done
  end
end
assert(result.packs.battle_sprites==16 and result.cappedCycles==8 and result.partTracks==2 and #result.partTracksSkipped==0)
assert(#read==5 and #composed==5 and writes==14 and encoded==10)
assert(#partsBuilt==2 and partsBuilt[1]=='252/front/false' and partsBuilt[2]=='252/back/false')
assert(published.version=='1.1.0')
local count=0
for id,entry in pairs(published.entries) do
  count=count+1;assert(entry.file:find('/1.1.0/',1,true))
  if id:match('^parts/') then
    assert(entry.sprite.kind=='parts' and entry.sprite.cycleCapped==true)
    assert(entry.metadata and entry.metadata.file:match('%.lua$') and entry.metadata.size==#'return {}')
  elseif id:find('/252/',1,true) then
    local side=id:match('/(%a+)$')=='female' and id:match('/(%a+)/female$') or id:match('/(%a+)$')
    assert(entry.sprite.cycleCapped==true,'capped atlas flag kept for 1.0 consumers')
    assert(entry.sprite.partsEntry=='parts/252/'..side and entry.sprite.partsPalette==id:match('^(%a+)/'))
  else assert(entry.sprite.partsEntry==nil) end
  if id:match('/female$') then
    local male=published.entries[id:gsub('/female$','')]
    if id:find('/025/front',1,true) then assert(entry.file~=male.file)
    else
      assert(entry.file==male.file and entry.size==male.size and entry.width==male.width)
      assert(entry.sprite==male.sprite and entry.frames==male.frames)
    end
  end
end
assert(count==18 and published.entries['parts/252/front'] and published.entries['parts/252/back'])
print('PASS missing-female atlas reuse: logical entries, distinct female art, capped counts, part tracks, species selection and bounded progress')

writes,published,encoded,read,composed,partsBuilt=0,nil,0,{},{},{}
local full=Bw.job('no ROM',{})
repeat
  local ok,value=coroutine.resume(full);assert(ok,value)
  if coroutine.status(full)=='dead' then result=value end
until coroutine.status(full)=='dead'
assert(result.packs.battle_sprites==5192 and result.cappedCycles==8 and result.partTracks==2)
assert(#read==1299 and #composed==1299 and writes==2602 and encoded==2598 and #partsBuilt==2)
count=0;for _ in pairs(published.entries) do count=count+1 end
assert(count==5194 and published.entries['shiny/649/back/female'])
print('PASS complete 649-species logical entry coverage with fallback alias optimization')

-- A part-track bound failure skips only that variant's parts: the capped
-- atlas remains (native fallback) and the import still completes.
writes,published,encoded,read,composed,partsBuilt=0,nil,0,{},{},{}
Bw.parts=function(sprite) partsBuilt[#partsBuilt+1]=sprite.key;return nil,'part track exceeds tick bounds' end
local skipped=Bw.job('no ROM',{}, {species={25,252}})
repeat
  local ok,value=coroutine.resume(skipped);assert(ok,value)
  if coroutine.status(skipped)=='dead' then result=value end
until coroutine.status(skipped)=='dead'
assert(result.packs.battle_sprites==16 and result.cappedCycles==8 and result.partTracks==0)
assert(#result.partTracksSkipped==2 and result.partTracksSkipped[1]:find('tick bounds',1,true))
assert(writes==10 and not published.entries['parts/252/front'])
assert(published.entries['normal/252/front'].sprite.cycleCapped==true and published.entries['normal/252/front'].sprite.partsEntry==nil)
print('PASS part-track bound failure keeps the capped atlas and completes the import')
