package.path='./?.lua;./?/init.lua;'..package.path
local Flags=require('src.core.game3.scripting.flags')
local WORLD_MAP={'VIRIDIAN_CITY','PEWTER_CITY','CERULEAN_CITY','LAVENDER_TOWN','VERMILION_CITY','CELADON_CITY',
  'FUCHSIA_CITY','CINNABAR_ISLAND','INDIGO_PLATEAU_EXTERIOR','SAFFRON_CITY','ONE_ISLAND','TWO_ISLAND',
  'THREE_ISLAND','FOUR_ISLAND','FIVE_ISLAND','SEVEN_ISLAND','SIX_ISLAND'}
local function checkWorldMapFlags(list,label)
  assert(type(list)=='table' and #list==17,label..': expected 17 world map flags')
  for i,name in ipairs(WORLD_MAP) do
    local want=assert(Flags.IDS['FLAG_WORLD_MAP_'..name],name)
    assert(list[i]==want,('%s: entry %d is 0x%X, want FLAG_WORLD_MAP_%s 0x%X'):format(label,i,list[i] or -1,name,want))
  end
end
local Cache=require('tests.game3_cache')
local root=Cache.root('quest_log/pack.lua')
if root then
  local src=assert(Cache.cache():read(root..'/quest_log/pack.lua'))
  local f=assert(loadstring(src));setfenv(f,{})
  checkWorldMapFlags(f().worldMapFlags,'cache pack')
  print('PASS Quest Log cache pack carries the 17 sWorldMapFlags')
else
  print('[skip] Quest Log cache pack: '..tostring(Cache.reason))
end
if not arg[1] then print('SKIP Quest Log ROM test: supply ROM path');return end
local imports=require('src.import.gba.file_io').makeImports(arg[1],'firered')
local rom=assert(require('src.import.gba.rom').open(imports,'firered'))
local E=require('src.import.gba.quest_log_extract')
local p=E.read(rom)
assert(p.text.PreviouslyOnYourQuest:find('Previously on your quest',1,true))
assert(p.text.CeruleanCave=='CERULEAN CAVE',p.text.CeruleanCave)
assert(p.text.ArrivedInLocation=='Arrived in {S1}.',p.text.ArrivedInLocation)
assert(p.text.TookOnTrainersMonWithMonAndWon:find('{D4}',1,true))
checkWorldMapFlags(p.worldMapFlags,'ROM')
local cache={write=function(self,_,v)self.value=v;return true end}
E.writeExtract(rom,cache);checkWorldMapFlags(assert(loadstring(cache.value))().worldMapFlags,'written pack')
imports:_close();print('PASS Quest Log ROM strings, placeholders, offsets, world map flags and cache')
