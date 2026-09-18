package.path='./?.lua;./?/init.lua;'..package.path
if not arg[1] then print('SKIP object cache test: supply FireRed cache root');return end
local root=arg[1];local cache={read=function(_,path)
 if path=='data/generated/gba/objects/pack.lua' and arg[2] then
  local f=assert(io.open(arg[2]));local data=f:read('*a');f:close();return data end
 local f=io.open(root..'/'..path);if not f then return end;local s=f:read('*a');f:close();return s end}
local bundle=assert(require('src.import.gba.extract_scripts').loadBundle(cache))
local Field=require('src.core.game3.field');local P=require('src.core.game3.player')
local Space=require('src.core.game3.scripting.space');local C=require('src.core.game3.collision')
local O=require('src.core.game3.objects');O.at=function()return nil end
Space.active=true;Space.bundle=bundle
local tests={{'FR_VIRIDIAN_CITY_SCHOOL',4,4,'up','notebook'},
 {'FR_SSANNE_CAPTAINS_OFFICE',2,4,'up','seasickness'},
 {'FR_RIVALS_HOUSE',12,1,'up','books'}}
for _,case in ipairs(tests) do
 local map,x,y,dir=unpack(case)
 local events=assert(bundle.events[map],map..' absent')
 local ev
 for _,e in ipairs(events.bgEvents or {}) do if e.x==x and e.y==y then ev=e end end
 if not ev then print('EVENTS',map);for _,e in ipairs(events.bgEvents or {})do print(e.x,e.y,e.scriptKey)end end
 assert(ev,'event missing '..map)
 assert(bundle.scripts[ev.scriptKey],'script missing '..ev.scriptKey)
 local messages={}
 Space.vm=require('src.core.game3.scripting.vm').new({scripts=bundle.scripts,text=bundle.text,movements=bundle.movements,
  onMessage=function(t)messages[#messages+1]=t end,askYesNo=function(cb)cb(false)end})
 Space.store=Space.vm.store
 Field._session={map=map};Field.running=true;Field.locked=false
 P.cellX=x;P.cellY=y+1;P.facing=dir;P.moving=false
 C._grid=nil;C._mapDef=nil
 local game={data={maps={[map]={bgEvents=events.bgEvents}}}}
 assert(Field.interact(game),'A-button not handled '..map)
 for _=1,300 do Space.vm:tick()end
 assert(#messages>0,'no text '..map)
 assert(table.concat(messages,' '):lower():find(case[5],1,true),'wrong map-specific text')
 assert(not Space.vm:isRunning())
end

print('PASS actual A-button dispatch: school notebook, captain book, rival bookshelf')

-- Audit every imported map and exercise each furniture behavior found there.
local native='data/generated/gba/native/'
local manifest=assert(loadstring(assert(cache:read(native..'manifest.lua'))))()
local I=require('src.core.game3.scripting.interaction_scripts')
local covered,maps,cells={},0,0
for map,info in pairs(manifest.layouts) do
 local decoded=assert(require('src.import.gba.native_pack').decodeMidLayout(assert(cache:read(native..info.file))))
 local layout=require('src.core.game3.layout_native').fromDecoded(decoded,map,info.pair)
 local attrs=assert(I.behaviors[info.pair], 'missing pair '..info.pair)
 local def={pair=info.pair,midLayout=layout,warps={}}
 C.bindMap(nil,map,def)
 maps=maps+1
 for y=0,layout.height-1 do for x=0,layout.width-1 do
  local behavior=assert(attrs[layout:midAt(x,y)],'missing metatile behavior')
  assert(C.behavior(x,y)==behavior)
  local key=I.scriptFor(behavior,'up')
  if key and behavior~=0x83 and behavior~=0x85 then
   cells=cells+1
   if not covered[behavior] and y+1<layout.height then
    local messages={}
    Space.vm=require('src.core.game3.scripting.vm').new({scripts=bundle.scripts,text=bundle.text,
     onMessage=function(t)messages[#messages+1]=t end})
    Space.store=Space.vm.store
    Field._session={map=map};Field.running=true;Field.locked=false
    P.cellX=x;P.cellY=y+1;P.facing='up';P.moving=false
    local game={data={maps={[map]=def}}}
    Field.locked=true;assert(not Field.interact(game));Field.locked=false
    assert(Field.interact(game),'furniture A-button not handled '..key)
    for _=1,100 do Space.vm:tick()end
    assert(#messages==1 and #messages[1]>0,'furniture text missing '..key)
    assert(not Space.vm:isRunning(),'furniture did not release control '..key)
    covered[behavior]=true
   end
  end
 end end
end
local count=0;for _ in pairs(covered)do count=count+1 end
assert(count>=20,'unexpectedly few furniture behaviors exercised')
print(('PASS %d maps audited, %d furniture cells, %d furniture types dispatched'):format(maps,cells,count))
