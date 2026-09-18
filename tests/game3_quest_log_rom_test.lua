package.path='./?.lua;./?/init.lua;'..package.path
if not arg[1] then print('SKIP Quest Log ROM test: supply ROM path');return end
local imports=require('src.import.gba.file_io').makeImports(arg[1],'test')
local rom=assert(require('src.import.gba.rom').open(imports,'firered'))
local E=require('src.import.gba.quest_log_extract')
local p=E.read(rom)
assert(p.text.PreviouslyOnYourQuest:find('Previously on your quest',1,true))
assert(p.text.CeruleanCave=='CERULEAN CAVE',p.text.CeruleanCave)
assert(p.text.ArrivedInLocation=='Arrived in {S1}.',p.text.ArrivedInLocation)
assert(p.text.TookOnTrainersMonWithMonAndWon:find('{D4}',1,true))
local cache={write=function(self,_,v)self.value=v;return true end}
E.writeExtract(rom,cache);assert(loadstring(cache.value))()
imports:_close();print('PASS Quest Log ROM strings, placeholders, offsets and cache')
