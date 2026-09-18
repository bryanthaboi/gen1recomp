package.path='./?.lua;./?/init.lua;'..package.path
if not arg[1] then print('SKIP object ROM test: supply FireRed ROM');return end
local F=require('src.import.gba.file_io')
local imports=F.makeImports(arg[1],'test')
local rom=assert(require('src.import.gba.rom').open(imports,'firered'))
local E=require('src.import.gba.object_interactions_extract')
local p=E.readScripts(rom)
local I=require('src.core.game3.scripting.interaction_scripts')
local Vm=require('src.core.game3.scripting.vm')
local Content=require('src.import.gba.island1_content')
local textCount=0
for _,row in ipairs(I.FLAVOR) do
 local messages={}
 local vm=Vm.new({scripts=p.scripts,text=p.text,stdscripts=Content.STDSCRIPTS,
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
