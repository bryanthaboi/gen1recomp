-- Existing v1 example, driven through the real SDK with procedural base data.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local function fixture()
 local data=require('tests.fixture_data').load()
 local base={}
 for key,value in pairs(data.pokemon.FIXMON_A) do base[key]=value end
 base.id,base.index,base.dex,base.name='MEW',151,151,'PROCEDURAL TEST'
 data.pokemon.MEW=base
 return data,base
end
local data,base=fixture()
local vanilla=T.sdk.loadMods({}, {data=data})
T.eq(#vanilla.errors,0,'no-mod loader remains clean')
T.eq(vanilla.data.pokemon.MEW.spriteFront,base.spriteFront,'no consumer preserves vanilla sprite')
vanilla.release()
local run=T.sdk.loadMod('mods/example_mew_starter',{data=fixture()})
T.eq(#run.errors,0,'unchanged v1 Mew starter loads with its required base record')
T.eq(run.data.pokemon.MEW.name,'PROCEDURAL TEST','v1 whole-record copy preserves untouched fields')
T.check(run.data.pokemon.MEW.spriteFront:find('mew_front_inverted.png',1,true)~=nil,'v1 content override applies')
local gift={species='CHARMANDER',level=5,ctx={overworld={map={id='OAKS_LAB'}},save={flags={},party={}}}}
run.loader.events:emit('pokemon.before_give',gift)
T.eq(gift.species,'MEW','legacy before_give event still fires')
T.eq(gift.level,20,'v1 event effect preserved')
local other={species='CHARMANDER',level=5,ctx={overworld={map={id='OTHER_MAP'}},save={flags={},party={}}}}
run.loader.events:emit('pokemon.before_give',other)
T.eq(other.species,'CHARMANDER','unrelated gift retains vanilla species')
T.eq(other.level,5,'unrelated gift retains vanilla level')
run.release()
T.finish('gen5 v1 and no-mod compatibility')
