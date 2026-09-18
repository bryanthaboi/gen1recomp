-- Optional real-ROM validation (ROM path supplied explicitly, never committed).
package.path='./?.lua;./?/init.lua;'..package.path
local path=arg and arg[1]
if not path then
  print('SKIP real-ROM Help test: pass a FireRed .gba path explicitly')
  return
end
local FileIO=require('src.import.gba.file_io')
local imports=FileIO.makeImports(path,'test')
local rom=assert(require('src.import.gba.rom').open(imports,'firered'))
local Extract=require('src.import.gba.help_extract')
local pack=Extract.read(rom)
assert(#pack.topics==6 and pack.topics[6]=='EXIT')
assert(pack.topics[1]=='What should I do in this situation?')
assert(pack.cancel=='CANCEL' and pack.greetings:find('Greetings!',1,true))
local count=0
for _,entries in ipairs(pack.entries) do
 for _,entry in ipairs(entries) do
  assert(#entry.question>0 and #entry.answer>0)
  count=count+1
 end
end
assert(count==177,'expected all 177 original help articles, got '..count)
assert(#pack.contexts[23][5]==35 and #pack.contexts[1][4]>0)
assert(#pack.palette==16 and #pack.tiles==288)
local cache={write=function(self,_,data) self.data=data;return true end}
Extract.writeExtract(rom,cache)
assert(loadstring(cache.data))()
imports:_close()
print('ROM Help: 177 articles, 36 contexts, graphics and serialized cache verified')
