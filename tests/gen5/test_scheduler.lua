package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local RomImporter=require('src.import.RomImporter')
local savedTimer=love.timer
local now=0
love.timer={getTime=function()return now end}
local function importer(id,cost)
 local resumes=0
 local co=coroutine.create(function()
  for i=1,100 do
   resumes=resumes+1;now=now+cost
   coroutine.yield({done=i,total=100,status='procedural work'})
  end
  return {packs={battle_sprites=100}}
 end)
 return setmetatable({_importerJob={id=id,co=co}},RomImporter),function()return resumes end
end
local ri,count=importer('gen5_bw',0.002)
ri:_stepImporter()
T.eq(count(),3,'timed scheduler uses about six milliseconds of work')
T.eq(ri._importerJob.progress,0.03,'last yield progress preserved')
ri:_stepImporter()
T.eq(count(),6,'next UI update resumes remaining work')
now=0
ri,count=importer('gen5_bw',0.0001)
ri:_stepImporter()
T.eq(count(),24,'cheap work batches up to bounded resume cap')
now=0
ri,count=importer('gen5_bw',0.012)
ri:_stepImporter()
T.eq(count(),1,'expensive slice stops before another resume')
ri,count=importer('pmd_red',0)
ri:_stepImporter()
T.eq(count(),1,'existing PMD pacing unchanged')
ri,count=importer('lttp',0)
ri:_stepImporter()
T.eq(count(),24,'existing Zelda pacing unchanged')
ri=setmetatable({_importerJob={id='gen5_bw',co=coroutine.create(function()return {packs={battle_sprites=8}} end)}},RomImporter)
ri:_stepImporter()
T.eq(ri._importerJob,nil,'completion releases job')
T.check(ri._importerNotice.ok,'completion remains successful')
ri=setmetatable({_importerJob={id='gen5_bw',co=coroutine.create(function()error('procedural failure')end)}},RomImporter)
ri:_stepImporter()
T.eq(ri._importerJob,nil,'failure releases job')
T.check(ri._importerNotice.text:find('procedural failure',1,true)~=nil,'failure notice preserved')
love.timer=savedTimer
T.finish('Gen5 timed importer scheduler')
