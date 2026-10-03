-- Atomic native picker publication through the actual launcher polling path.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local RomImporter=require('src.import.RomImporter')
local file='picked_importer_gen5_bw.bin'
local partial=file..'.part'
local oldSave=love.filesystem.getSaveDirectory
love.filesystem.getSaveDirectory=function() return '/procedural-picker-fixture' end
local ready={}
for _,id in ipairs(require('src.core.GameVersion').ORDER) do ready[id]=true end
local function pending()
 return setmetatable({android=true,ready=ready,pickPending=true,pickerPendingKind='importer',
  pickerPendingImporterId='gen5_bw',_runImporterData=function(self,id,bytes)
   self.received={id=id,bytes=bytes}
  end},RomImporter)
end
for _,name in ipairs({file,partial,'pick_error.flag','pick_complete.flag'}) do love.filesystem.remove(name) end
love.filesystem.write(partial,'unfinished procedural data')
local ri=pending()
local unrelated={'old_cart.gb','old_cart.gbc','old_cart.gba','picked_mod.zip',
 'picked_importer_pmd_red.bin','pick_complete.flag'}
for _,name in ipairs(unrelated) do love.filesystem.write(name,'unrelated procedural data') end
ri:_pollPickedFiles(10)
T.check(ri.pickPending,'partial copy keeps picker pending even after long delay')
T.eq(ri.received,nil,'partial file never starts import')
T.eq(ri.pickerPendingImporterId,'gen5_bw','pending importer identity retained')
ri:focus(true)
T.check(ri.pickPending,'refocus with unrelated files keeps importer pending')
T.eq(ri.pickerPendingImporterId,'gen5_bw','refocus preserves pending importer identity')
local picked=0
local oldPick=love.system.pickFile
love.system.pickFile=function() picked=picked+1;return true end
ri:_beginImporterImport('gen5_bw')
ri:_beginImporterImport('pmd_red')
ri:choose('red')
ri:chooseMod()
ri:chooseRequiredImport('unused','unused')
ri:chooseSaveImport('red')
ri:chooseSkin()
ri:importCartFile('red')
T.eq(picked,0,'pending importer blocks competing picker actions')
T.eq(ri.pickerPendingImporterId,'gen5_bw','blocked actions retain original importer')
love.system.pickFile=oldPick
for _,message in ipairs({'cancelled:picked_mod.zip','picked_importer_pmd_red.bin'}) do
 love.filesystem.write('pick_error.flag',message)
 ri:_pollPickedFiles(0.5)
 T.check(ri.pickPending,'unrelated copy error retains pending importer')
 T.eq(ri._importerNotice,nil,'unrelated copy error does not report current failure')
end
love.filesystem.write(file,'complete procedural data')
ri:_pollPickedFiles(0.5)
T.eq(ri.received.id,'gen5_bw','final filename reaches correct importer')
T.eq(ri.received.bytes,'complete procedural data','final published bytes handed to importer')
T.eq(ri.pickPending,nil,'success clears pending state')
T.eq(love.filesystem.getInfo(file),nil,'consumed final inbox file removed')
T.check(love.filesystem.getInfo('pick_complete.flag')~=nil,
 'current importer completion does not consume unrelated dependency marker')
for _,name in ipairs(unrelated) do love.filesystem.remove(name) end
ri=pending()
love.filesystem.write('pick_error.flag',file)
ri:_pollPickedFiles(0.5)
T.check(ri._importerNotice and ri._importerNotice.ok==false,'native copy failure reaches importer notice')
T.eq(ri.modNotice,nil,'copy failure does not become a required-mod import')
T.eq(ri.pickPending,nil,'failure clears pending state')
T.eq(ri.pickerPendingImporterId,nil,'failure retires importer identity')
ri=pending()
love.filesystem.write('pick_error.flag','cancelled:'..file)
ri:_pollPickedFiles(0.5)
T.eq(ri.pickPending,nil,'current picker cancellation clears pending state')
T.eq(ri.pickerPendingImporterId,nil,'current cancellation retires identity')
T.check(ri._importerNotice and ri._importerNotice.ok==false,'current cancellation reports notice')
local retried=0
love.system.pickFile=function() retried=retried+1;return true end
ri:_beginImporterImport('gen5_bw')
T.eq(retried,1,'cancelled request can be retried')
T.check(ri.pickPending,'retry arms polling again')
love.system.pickFile=oldPick
local otherPlatform=pending()
otherPlatform.android=false
T.check(not otherPlatform:_importerPickPending(),
 'Android copy lock does not block other platform picker cancellation flows')
love.filesystem.remove(partial)
love.filesystem.getSaveDirectory=oldSave
T.finish('gen5 Android atomic picker poll')
