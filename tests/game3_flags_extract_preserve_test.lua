package.path='./?.lua;./?/init.lua;'..package.path
local Extract=require('src.import.gba.flags_extract')
local function source()
 local f=assert(io.open('src/core/game3/scripting/flags_table.lua','rb'))
 local s=f:read('*a');f:close();return s
end
local before=source()
local empty=Extract.extract({root='/nonexistent-pokefirered-source'})
local cache={write=function(self,_,s) self.source=s;return true end}
assert(Extract.write(cache,'test',empty))
assert(source()==before,'Import must never overwrite engine source')
local flags=assert(loadstring(cache.source))()
assert(flags.FLAGS.FLAG_SYS_POKEDEX_GET==0x829,'Missing headers must use bundled constants')
print('Flag extraction preserves source and uses bundled constants')
