-- Synthetic part-track tests: component tick/loop rules, global OAM tie order,
-- per-tick canvas clipping and the serialized descriptor. No cartridge data.
package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.modkit")
local Animation=require("src.import.gen5.Animation")
local Composer=require("src.import.gen5.Composer")
local Parts=require("src.import.gen5.Parts")
local LuaWriter=require("src.import.LuaWriter")

-- Component cycle: Parts.cycle must reproduce Animation.frame for every
-- playback type, loop start and zero-duration edge case, far past one loop.
local function frames(list)
  local out={}
  for i,d in ipairs(list) do out[i]={cell_id=i-1,duration=d} end
  return out
end
local cases={
  {name="forward loop, intro then suffix",playback=2,loop=1,d={2,3,4}},
  {name="forward loop, no intro",playback=2,loop=0,d={5,1,7}},
  {name="ping-pong loop with intro",playback=4,loop=1,d={2,3,1,4}},
  {name="ping-pong loop, no intro",playback=4,loop=0,d={1,1,1}},
  {name="one-shot holds last pose",playback=1,loop=0,d={5,6}},
  {name="one-shot ping-pong",playback=3,loop=0,d={2,3,4}},
  {name="loop with zero-length suffix",playback=2,loop=2,d={3,2,0}},
  {name="all zero durations",playback=2,loop=0,d={0,0}},
  {name="single long pose",playback=2,loop=0,d={500}},
  {name="zero-duration middle pose",playback=2,loop=1,d={4,0,5}},
}
for _,case in ipairs(cases) do
  local bank={animations={{frames=frames(case.d),loop_start=case.loop,playback_type=case.playback}}}
  local intro,period=Parts.cycle(bank.animations[1])
  local ok=period>=1 and intro>=0
  for tick=0,5*(intro+period)+40 do
    local expected=Animation.frame(bank,0,tick).cell_id
    local mapped=Animation.frame(bank,0,Parts.trackTick(intro,period,tick)).cell_id
    if expected~=mapped then ok=false;break end
  end
  T.check(ok,"component cycle matches source playback: "..case.name)
end
do
  local bank={animations={{frames=frames({2,3,4}),loop_start=1,playback_type=2}}}
  local intro,period=Parts.cycle(bank.animations[1])
  T.eq(intro,2,"intro is played once before the loop")
  T.eq(period,7,"loop period excludes the intro")
  T.eq(Parts.trackTick(intro,period,1),1,"intro ticks map to themselves")
  T.eq(Parts.trackTick(intro,period,9),2,"first loop wraps to the loop start, not tick 0")
  T.eq(Parts.trackTick(intro,period,2+7*1000000+3),5,"deep ticks keep the loop phase")
end

-- Synthetic tiles: deterministic pattern with transparent holes.
local graphics={bpp=4}
function graphics:getPixel(tile,x,y)
  if (x+y+tile)%5==0 then return 0 end
  return (tile*7+x*3+y*5)%15+1
end
local function palette(shift)
  local colors={{r=0,g=0,b=0,a=0}}
  for i=1,15 do colors[i+1]={r=(i*16+shift)%256,g=(i*5)%256,b=(255-i*9)%256,a=255} end
  return {colors=colors}
end
local function oam(x,y,w,h,tile,priority,extra)
  local o={x=x,y=y,width=w,height=h,tile_index=tile,palette=0,priority=priority}
  for k,v in pairs(extra or {}) do o[k]=v end
  return o
end
local function compare(sprite,model,tick)
  local ref,width,_,b=Composer.renderIndexed(sprite.graphics,sprite.normal,sprite.cells,sprite.nanr,sprite.nmcr,sprite.map,tick)
  local got=Parts.composeIndexed(model,tick)
  local n=0
  for offset,index in pairs(ref) do
    local x=(offset-1)%width+b.min_x-model.min_x
    local y=math.floor((offset-1)/width)+b.min_y-model.min_y
    if x<0 or y<0 or x>=model.width or y>=model.height then return false end
    if got[y*model.width+x+1]~=index then return false end
    n=n+1
  end
  local m=0;for _ in pairs(got) do m=m+1 end
  return m==n,n
end

-- Multi-track sprite: four records with intro, ping-pong, one-shot hold and an
-- affine scaled track. Its global loop is long; tracks stay independent.
local cells={cells={
  {oams={oam(-8,-8,16,16,0,1),oam(4,-4,8,8,9,2)}},
  {oams={oam(-8,-8,16,8,4,1,{flip_h=true})}},
  {oams={oam(-4,-12,8,16,12,0),oam(-6,-6,8,8,20,1,{disabled=true})}},
  {oams={oam(-16,-4,32,8,30,2)}},
  {oams={oam(-4,-4,8,8,40,0),oam(-2,-2,8,8,41,3)}},
  {oams={oam(0,0,8,8,50,1,{flip_v=true})}},
  {oams={oam(-8,-8,16,16,60,2)}},
}}
local nanr={animations={
  {loop_start=1,playback_type=2,frames={
    {cell_id=0,duration=2},{cell_id=1,duration=3,translate_x=3},{cell_id=0,duration=4,translate_y=-2}}},
  {loop_start=0,playback_type=4,frames={
    {cell_id=2,duration=5},{cell_id=3,duration=6,rotation=8192},{cell_id=2,duration=4,rotation=-4096,translate_x=-5}}},
  {loop_start=0,playback_type=1,frames={{cell_id=4,duration=7},{cell_id=5,duration=13,translate_x=6}}},
  {loop_start=0,playback_type=2,frames={
    {cell_id=6,duration=11,scale_x=8192,scale_y=6144},{cell_id=5,duration=6},{cell_id=6,duration=6,scale_x=3072,rotation=16384}}},
}}
local nmcr={maps={{records={
  {animation_index=0,x=0,y=0},{animation_index=1,x=10,y=4},
  {animation_index=2,x=-12,y=6},{animation_index=3,x=4,y=-10}}}}}
local sprite={graphics=graphics,cells=cells,nanr=nanr,nmcr=nmcr,map=0,normal=palette(0),shiny=palette(7)}
local model=Parts.layout(Parts.build(sprite))
T.eq(#model.tracks,4,"one independent track per multicell record")
T.eq(model.tracks[1].intro,2,"track intro preserved")
T.eq(model.tracks[1].period,7,"track loop preserved")
T.eq(model.tracks[3].period,1,"one-shot track holds its final pose")
local lcm=Animation.cycleTicks(nanr,nmcr.maps[1],1e9)
T.check(lcm>240,"synthetic global loop exceeds the old export cap")
local allTicks,pixels=true,0
local ticks={}
for t=0,700 do ticks[#ticks+1]=t end
for _,t in ipairs({lcm-1,lcm,lcm+1,lcm*7+3,999983,2^31+5}) do ticks[#ticks+1]=t end
for _,t in ipairs(ticks) do
  local ok,n=compare(sprite,model,t)
  if not ok then allTicks=false;print("mismatch at tick",t);break end
  pixels=pixels+n
end
T.check(allTicks and pixels>0,"part composition equals the source compositor at every checked tick, including deep ticks")

-- Overlapping priorities: one shared pixel covered by five objects.
-- Composer.objects sorts priority descending, then insertion index descending,
-- so lower priority values win and earlier records/OAMs win ties.
local flat={bpp=4}
function flat:getPixel(tile) return tile+1 end
local tie={cells={
  {oams={oam(0,0,8,8,0,2),oam(0,0,8,8,1,0)}},  -- record 1: A prio 2, B prio 0
  {oams={oam(0,0,8,8,2,1)}},                  -- record 2: C prio 1
  {oams={oam(0,0,8,8,3,0)}},                  -- record 3: D prio 0 (ties B)
  {oams={oam(0,0,8,8,4,1)}},                  -- record 4: E prio 1 (ties C)
}}
local still={animations={}}
for i=1,4 do still.animations[i]={loop_start=0,playback_type=2,frames={{cell_id=i-1,duration=1}}} end
local function tieSprite(order)
  local records={}
  for i,cell in ipairs(order) do records[i]={animation_index=cell,x=0,y=0} end
  return {graphics=flat,cells=tie,nanr=still,nmcr={maps={{records=records}}},map=0,normal=palette(0),shiny=palette(0)}
end
local s1=tieSprite({0,1,2,3})
local m1=Parts.layout(Parts.build(s1))
local px=Parts.composeIndexed(m1,0)[1]
T.eq(px,2,"priority 0 from the first record wins over a later priority-0 record")
T.check(compare(s1,m1,0),"tie order equals Composer at the overlap")
local s2=tieSprite({2,3,0,1})
local m2=Parts.layout(Parts.build(s2))
T.eq(Parts.composeIndexed(m2,0)[1],4,"reordering records moves the tie winner to the earlier record")
T.check(compare(s2,m2,0),"reordered tie order equals Composer")
local s3=tieSprite({1,3,0})
local m3=Parts.layout(Parts.build(s3))
T.eq(Parts.composeIndexed(m3,0)[1],2,"a later record's priority-0 OAM beats earlier priority-1 records")
T.check(compare(s3,m3,0),"mixed-priority records equal Composer")
-- Per-record flattening (paint each record as one layer, last to first)
-- would show record 1's B over record 3's D only by accident of order; with
-- record 1 = {A prio2, B prio0} last-painted it hides the priority-1 record.
local s4=tieSprite({1,0})
local m4=Parts.layout(Parts.build(s4))
T.eq(Parts.composeIndexed(m4,0)[1],2,"record 2's priority-0 OAM B wins over record 1's priority-1 C")
T.check(compare(s4,m4,0),"priority groups split a record exactly as Composer does")
T.eq(#m4.pieces,3,"a mixed-priority cell yields one piece per priority group")
-- Same-cell tie: serialized-first OAM wins.
local same={cells={{oams={oam(0,0,8,8,5,1),oam(0,0,8,8,6,1)}}}}
local s5={graphics=flat,cells=same,nanr={animations={{loop_start=0,playback_type=2,frames={{cell_id=0,duration=1}}}}},
  nmcr={maps={{records={{animation_index=0,x=0,y=0}}}}},map=0,normal=palette(0),shiny=palette(0)}
local m5=Parts.layout(Parts.build(s5))
T.eq(Parts.composeIndexed(m5,0)[1],6,"same-priority serialized-first OAM wins inside a cell")

-- Canvas fringe: a 4x scaled object paints one column left of its own box,
-- but only when another record widens that tick's canvas. Parity must hold
-- in both states, which needs the per-tick canvas clip.
local fringe={cells={{oams={oam(0,0,8,8,7,1)}},{oams={oam(0,0,2,2,8,1)}}}}
local fnanr={animations={
  {loop_start=0,playback_type=2,frames={{cell_id=0,duration=1,scale_x=16384,scale_y=16384}}},
  {loop_start=0,playback_type=2,frames={{cell_id=1,duration=3},{cell_id=1,duration=2,translate_x=-20}}}}}
local fs={graphics=flat,cells=fringe,nanr=fnanr,nmcr={maps={{records={
  {animation_index=0,x=0,y=0},{animation_index=1,x=4,y=4}}}}},map=0,normal=palette(0),shiny=palette(0)}
local fm=Parts.layout(Parts.build(fs))
local fringeOk=true
for t=0,30 do fringeOk=fringeOk and compare(fs,fm,t) end
T.check(fringeOk,"per-tick canvas clipping matches Composer in both canvas states")
local narrow=Composer.renderIndexed(flat,fs.normal,fringe,fnanr,fs.nmcr,0,0)
local _,_,_,wide=Composer.renderIndexed(flat,fs.normal,fringe,fnanr,fs.nmcr,0,3)
local _,nw=Composer.renderIndexed(flat,fs.normal,fringe,fnanr,fs.nmcr,0,0)
local wideRef,ww=Composer.renderIndexed(flat,fs.normal,fringe,fnanr,fs.nmcr,0,3)
T.check(narrow[1]~=nil and wideRef[(0-wide.min_y)*ww+(-1-wide.min_x)+1]~=nil and nw==32,
  "fixture really exposes the fringe column only on the wide canvas")

-- Descriptor: LuaWriter output loads in an empty environment, and the inert
-- atlas stub satisfies the 1.0 provider's validation rules.
local meta=Parts.metadata(model,sprite)
local chunk=assert(loadstring(LuaWriter.encode(meta)))
setfenv(chunk,{})
local loaded=chunk()
T.eq(loaded.format,"gen5-parts","descriptor format")
T.eq(#loaded.tracks,4,"descriptor keeps every track")
T.eq(#loaded.pieces,#model.pieces*6,"six integers per piece")
T.eq(#loaded.tracks[1].states,#model.tracks[1].states*9,"nine integers per state")
T.eq(#loaded.palettes.normal,16*4,"normal palette carried")
local runTicks=0
for i=1,#loaded.tracks[1].runs,2 do runTicks=runTicks+loaded.tracks[1].runs[i] end
T.eq(runTicks,loaded.tracks[1].intro+loaded.tracks[1].period,"runs cover intro plus loop exactly")
local stub=Parts.stub(model)
local total=0;for _,d in ipairs(stub.durations) do total=total+d end
T.check(stub.cycleCapped==true and stub.kind=="parts" and stub.width<=256 and stub.height<=256
  and stub.columns==1 and #stub.durations==stub.frames and stub.cycleTicks==total
  and model.atlasHeight==stub.height*stub.frames and stub.width*model.atlasHeight<=4*1024*1024,
  "inert atlas descriptor passes 1.0 consumer validation and is skipped as capped")
for _,piece in ipairs(model.pieces) do
  T.check(piece.ax+piece.w<=model.atlasWidth and piece.ay+piece.h<=model.atlasHeight,"piece fits atlas")
  break
end
-- Pieces are cropped to the union, so the descriptor's offsets stay inside it.
local inside=true
for _,piece in ipairs(model.pieces) do
  inside=inside and piece.x>=model.min_x and piece.y>=model.min_y
    and piece.x+piece.w<=model.min_x+model.width and piece.y+piece.h<=model.min_y+model.height
end
T.check(inside,"every piece lies inside the visible union")
-- Bounds are soft: an over-long track skips part tracks, it does not throw.
local long={graphics=flat,cells=same,nmcr=s5.nmcr,map=0,normal=palette(0),shiny=palette(0),
  nanr={animations={{loop_start=0,playback_type=1,frames={{cell_id=0,duration=70000},{cell_id=0,duration=1}}}}}}
local none,why=Parts.build(long)
T.check(none==nil and tostring(why):find("tick bounds",1,true)~=nil,"over-long track returns a reason instead of failing")
-- A frame past the old 240-tick window that the compositor cannot render
-- (canvas over 1024 pixels) skips part tracks instead of throwing.
local huge={cells={{oams={oam(0,0,8,8,5,1)}},{oams={oam(0,0,64,64,5,1)}}}}
local hs={graphics=flat,cells=huge,nmcr=s5.nmcr,map=0,normal=palette(0),shiny=palette(0),
  nanr={animations={{loop_start=0,playback_type=2,frames={{cell_id=0,duration=300},
    {cell_id=1,duration=1,scale_x=65536,scale_y=65536}}}}}}
local okCall,hm,hwhy=pcall(Parts.build,hs)
T.check(okCall and hm==nil and tostring(hwhy):find("cannot be composed",1,true)~=nil,
  "uncomposable late frame returns a reason instead of aborting the import")
-- Checkpoints: progress() without arguments is offered outside renders too.
local calls,bare=0,0
Parts.build(sprite,function(done) calls=calls+1;if done==nil then bare=bare+1 end end)
T.check(bare>0 and calls>bare,"build offers render and non-render pacing checkpoints")
T.finish("gen5 part tracks")
