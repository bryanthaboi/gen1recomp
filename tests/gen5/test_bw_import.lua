package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Bw=require('src.import.gen5.BwImport')
local Composer=require('src.import.gen5.Composer')
local original=Composer.renderIndexed
Composer.renderIndexed=function(_,_,_,nanr,_,_,tick)
 local frame=require('src.import.gen5.Animation').frame(nanr,0,tick)
 return {[1]=frame.cell_id+1},1,1,{min_x=-2,min_y=-3}
end
local function sprite(frames,loopStart,playback)
 return {map=0,nmcr={maps={{records={{animation_index=0}}}}},
  nanr={animations={{frames=frames,loop_start=loopStart or 0,playback_type=playback or 2}}}}
end
local frames={{cell_id=0,duration=2},{cell_id=1,duration=3},{cell_id=2,duration=4}}
local p=Bw.poses(sprite(frames,1))
T.eq(p.ticks,9,'intro plus suffix period exported once')
T.eq(p.loopStartFrame,1,'zero-based suffix start excludes introduction')
T.eq(table.concat(p.durations,','),'2,3,4','original tick durations preserved')
T.eq(p.min_x,-2,'opaque anchor x preserved')
T.eq(p.min_y,-3,'opaque anchor y preserved')
T.eq(p.width,1,'visible union crops empty area')
T.check(not p.cycleCapped,'complete cycle is not flagged truncated')
p=Bw.poses(sprite({{cell_id=0,duration=500}}))
T.eq(p.ticks,1,'fixed pose contributes no spurious long cycle')
p=Bw.poses(sprite({{cell_id=0,duration=130},{cell_id=1,duration=130}}))
T.eq(p.ticks,240,'long changing cycle stays bounded')
T.check(p.cycleCapped,'truncation is explicit for consumer fallback')
p=Bw.poses(sprite(frames,0,1))
T.eq(p.loopStartFrame,3,'terminal hold splits the final pose at the loop boundary')
T.eq(table.concat(p.durations,','),'2,3,3,1','one-shot final duration includes stable terminal hold')
T.eq(p.ticks,9,'one-shot terminal frame follows its introduction')
Composer.renderIndexed=original
local registry=require('src.import.Importers')
T.eq(registry.get('gen5_bw').module,'src.import.gen5.BwImport','registered launcher module')
T.eq(registry.get('pmd_red').module,'src.import.pmd.PmdImport','existing PMD dispatch preserved')
T.eq(registry.get('lttp').module,'src.import.lttp.LttpImport','existing Zelda dispatch preserved')
T.eq(registry.state('gen5_bw',{read=function() return nil end}),'missing','no imported pack leaves normal missing state')
T.finish('gen5 native import timing')
