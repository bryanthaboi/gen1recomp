package.path='./?.lua;./?/init.lua;'..package.path
local I=require('src.core.game3.scripting.interaction_scripts')
assert(#I.FLAVOR==28)
for _,r in ipairs(I.FLAVOR) do
 assert(I.scriptFor(r[1],'up')=='EventScript_'..r[2])
 assert((I.scriptFor(r[1],'down')~=nil)==not r[3])
end
assert(I.scriptFor(0x83,'left')=='EventScript_PC')
assert(I.scriptFor(0x85,'up')=='EventScript_WallTownMap')
assert(not I.scriptFor(0,'up'))
for kind,dir in pairs({[1]=2,[2]=1,[3]=4,[4]=3}) do
 local ev={x=3,y=5,kind=kind,elevation=2}
 assert(I.backgroundMatches(ev,3,5,2,dir))
 assert(not I.backgroundMatches(ev,3,5,2,dir%4+1))
 assert(not I.backgroundMatches(ev,3,5,1,dir))
end
local Collision=require('src.core.game3.collision')
assert(Collision.behavior,'native metatile behavior accessor missing')
local Layout=require('src.core.game3.layout_native')
local l=Layout.fromDecoded({width=1,height=1,cells={{mid=7,coll=255,elev=1}}},'TEST','test')
Collision._mapDef={midLayout=l}
assert(Collision.behavior(0,0)==nil,'legacy cache fallback before bundle loads')
I.install({behaviors={test={[7]=0x81,[8]=0x90}}})
assert(Collision.behavior(0,0)==0x81)
l:applyOverride(0,0,8);assert(Collision.behavior(0,0)==0x90,'overrides use new tile behavior')
assert(Collision.behavior(1,0)==nil,'outside map should not interact')
print('PASS object behavior coverage, facing, elevation and metatile overrides')
