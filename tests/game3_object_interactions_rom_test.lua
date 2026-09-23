package.path='./?.lua;./?/init.lua;'..package.path
if not arg[1] then print('SKIP object ROM test: supply FireRed ROM');return end
local F=require('src.import.gba.file_io')
local imports=F.makeImports(arg[1],'test')
local rom=assert(require('src.import.gba.rom').open(imports,'firered'))
local E=require('src.import.gba.object_interactions_extract')
local p=E.readScripts(rom)
local I=require('src.core.game3.scripting.interaction_scripts')
local Vm=require('src.core.game3.scripting.vm')
local V=require('src.import.gba.versions')
local Opcodes=require('src.core.game3.scripting.opcodes')
local seeds,alias={},{}
for i=0,V.STD_SCRIPTS_COUNT-1 do
 local ptr=rom:u32(V.STD_SCRIPTS+i*4)
 seeds[#seeds+1]=ptr
 alias['std:'..i]=Opcodes.key(ptr)
end
local stdBfs=require('src.import.gba.extract_scripts').bfsFromSeeds(rom,seeds)
local stdScripts={}
for k,v in pairs(stdBfs.scripts) do stdScripts[k]=v end
for name,key in pairs(alias) do stdScripts[name]=assert(stdBfs.scripts[key]) end
local textCount=0
for _,row in ipairs(I.FLAVOR) do
 local messages={}
 local vm=Vm.new({scripts=p.scripts,text=p.text,stdscripts=stdScripts,
  onMessage=function(text) messages[#messages+1]=text end})
 assert(vm:start('EventScript_'..row[2]))
 for _=1,100 do vm:tick() end
 assert(#messages==1 and #messages[1]>0,row[2]..' did not show its text')
 assert(not vm:isRunning(),row[2]..' did not return control')
 -- Read original IR directly too: every shared script must resolve its text.
 local script=p.scripts['EventScript_'..row[2]]
 local key=script[1].value or script[1][2]
 assert(type(key)=='string' and p.text[key],row[2]..' text missing')
 textCount=textCount+1
end
assert(p.scripts.EventScript_WallTownMap)
assert(textCount==28)
imports:_close();print('PASS all 28 original object/sign scripts and Wall Town Map extracted')
