-- Independent part tracks for long Black/White idle animations.
--
-- The flattened atlas export bakes the least common multiple of every part's
-- loop. Some sprites need hundreds of thousands of ticks for that, so this
-- module keeps each multicell record as its own track instead: per-record
-- tick->state runs (intro, then loop), each state's cell/transform rendered
-- once per OAM priority group, and the canvas clip each state contributes.
-- A consumer composes the current states with the same global order as
-- Composer.objects: priority descending, then insertion index descending.
-- Insertion index is (record, OAM) lexicographic, so painting priority groups
-- high to low, and records last to first inside each group, is exact.
--
-- Rendering reuses Composer.renderIndexed on a one-record, one-frame view, so
-- the transform, rounding, flip, tile and palette-index rules are the
-- compositor's own. No pixels are stored in this file or the repository.
local Animation=require("src.import.gen5.Animation")
local Composer=require("src.import.gen5.Composer")
local Parts={FORMAT="gen5-parts",VERSION=1,ATLAS_WIDTH=256,ROW=64,MAX_TRACKS=512,
  MAX_TRACK_TICKS=65536,MAX_TOTAL_TICKS=262144,MAX_PIECES=4096,MAX_TRACK_STATES=4096,MAX_STATES=8192}

local function range(animation,first,last,step)
  local total=0
  for i=first,last,step do total=total+animation.frames[i].duration end
  return total
end
-- Mirrors Animation.frame's wrap rules exactly. The result satisfies
-- frame(t) == frame(t < intro and t or intro + (t - intro) % period).
function Parts.cycle(animation)
  local n=#animation.frames
  local duration=range(animation,1,n,1)
  if duration<=0 then return 0,1 end
  local playback=animation.playback_type
  local loop=playback==2 or playback==4
  local ping=playback==3 or playback==4
  local loopStart=(animation.loop_start or 0)+1
  local reverseStart,reverseEnd=n-1,loop and loopStart or 1
  local reverse=ping and reverseStart>=reverseEnd and range(animation,reverseStart,reverseEnd,-1) or 0
  local sequence=duration+reverse
  if loop then
    local prefix=range(animation,1,loopStart-1,1)
    local period=range(animation,loopStart,n,1)+reverse
    if period>0 then return prefix,period end
    return 0,sequence
  end
  return sequence-1,1
end
function Parts.trackTick(intro,period,tick)
  if tick<intro then return tick end
  return intro+(tick-intro)%period
end
local function stateKey(frame)
  return table.concat({frame.cell_id,frame.rotation or 0,frame.scale_x or 4096,frame.scale_y or 4096,
    frame.translate_x or 0,frame.translate_y or 0},":")
end
local function enabled(oam) return not (oam.disabled==true or oam.disabled==1) end

-- One record frozen at one frame: a single-record map and single-frame bank.
local function view(record,frame)
  local still={}
  for key,value in pairs(frame) do still[key]=value end
  still.duration=1
  local placed={}
  for key,value in pairs(record) do placed[key]=value end
  placed.animation_index=0
  return {animations={{frames={still},loop_start=0,playback_type=2}}},
    {maps={{records={placed}}}}
end

-- Builds the track model and indexed pieces for the sprite's idle map.
-- progress(done,count) is called after each rendered state, and progress()
-- at other checkpoints, for job pacing. Exceeding a part-track bound returns
-- nil and a reason: the caller then keeps the capped atlas's native fallback
-- for this variant instead of failing the whole import.
function Parts.build(sprite,progress)
  local map=assert(sprite.nmcr.maps[sprite.map+1],"missing idle multicell map")
  if #map.records<1 or #map.records>Parts.MAX_TRACKS then return nil,"part track count exceeds bounds" end
  local tracks,pieces,data={}, {}, {}
  local totalTicks,totalStates=0,0
  local work={}
  for r,record in ipairs(map.records) do
    local animation=assert(sprite.nanr.animations[record.animation_index+1],"missing part animation")
    assert(#animation.frames>0,"part animation has no frames")
    local intro,period=Parts.cycle(animation)
    if period<1 or intro+period>Parts.MAX_TRACK_TICKS then return nil,"part track exceeds tick bounds" end
    totalTicks=totalTicks+intro+period
    if totalTicks>Parts.MAX_TOTAL_TICKS then return nil,"part tracks exceed total tick bounds" end
    local keys,states,runs,stateAt={}, {}, {}, {}
    local last,length=nil,0
    for tick=0,intro+period-1 do
      local frame=assert(Animation.frame(sprite.nanr,record.animation_index,tick))
      local key=stateKey(frame)
      local index=keys[key]
      if not index then
        index=#states+1;keys[key]=index
        states[index]={frame=frame}
        work[#work+1]={track=r,state=index}
      end
      stateAt[tick+1]=index
      if progress and tick%512==511 then progress() end
      if index==last then length=length+1 else
        if last then runs[#runs+1]=length;runs[#runs+1]=last end
        last,length=index,1
      end
    end
    runs[#runs+1]=length;runs[#runs+1]=last
    totalStates=totalStates+#states
    if #states>Parts.MAX_TRACK_STATES or totalStates>Parts.MAX_STATES then return nil,"part states exceed bounds" end
    if progress then progress() end
    tracks[r]={record=record,intro=intro,period=period,runs=runs,states=states,stateAt=stateAt}
  end
  local hull
  for done,job in ipairs(work) do
    local track=tracks[job.track]
    local state=track.states[job.state]
    local frame=state.frame
    local cell=assert(sprite.cells.cells[frame.cell_id+1],"animation refers to missing cell")
    local nanr,nmcr=view(track.record,frame)
    state.pieces={0,0,0,0}
    local byPriority,any={},false
    for _,oam in ipairs(cell.oams) do
      if enabled(oam) then
        any=true
        local list=byPriority[oam.priority] or {}
        list[#list+1]=oam;byPriority[oam.priority]=list
      end
    end
    if any then
      -- Composer's per-tick canvas is floor/ceil of every enabled item.
      -- Composer asserts (singular transform, oversized canvas) can reach a
      -- frame the 240-tick atlas never rendered; skip parts rather than fail
      -- the import. These calls never yield, so pcall is safe here.
      local okB,b=pcall(Composer.bounds,sprite.cells,nanr,nmcr,0,0)
      if not okB then return nil,"part state cannot be composed: "..tostring(b) end
      state.bounds={b.min_x,b.min_y,b.max_x,b.max_y}
      if not hull then hull={b.min_x,b.min_y,b.max_x,b.max_y} else
        hull[1]=math.min(hull[1],b.min_x);hull[2]=math.min(hull[2],b.min_y)
        hull[3]=math.max(hull[3],b.max_x);hull[4]=math.max(hull[4],b.max_y)
      end
      for priority=0,3 do
        local list=byPriority[priority]
        if list then
          local cells={cells={[frame.cell_id+1]={oams=list}}}
          local pb=Composer.bounds(cells,nanr,nmcr,0,0)
          -- Items paint one pixel past their floor/ceil box; keep that fringe
          -- here and let the consumer clip it to the per-tick canvas.
          local okR,pixels,width,_,origin=pcall(Composer.renderIndexed,sprite.graphics,sprite.normal,cells,nanr,nmcr,0,0,
            {bounds={min_x=pb.min_x-1,min_y=pb.min_y-1,max_x=pb.max_x+2,max_y=pb.max_y+2}})
          if not okR then return nil,"part piece cannot be composed: "..tostring(pixels) end
          local minx,miny,maxx,maxy=math.huge,math.huge,-math.huge,-math.huge
          for offset in pairs(pixels) do
            local x=(offset-1)%width+origin.min_x
            local y=math.floor((offset-1)/width)+origin.min_y
            minx,miny=math.min(minx,x),math.min(miny,y)
            maxx,maxy=math.max(maxx,x+1),math.max(maxy,y+1)
          end
          if minx<maxx then
            local w,h=maxx-minx,maxy-miny
            if w>Parts.ATLAS_WIDTH or h>Parts.ATLAS_WIDTH then return nil,"part piece exceeds bounds" end
            local values={}
            for i=1,w*h do values[i]=0 end
            for offset,index in pairs(pixels) do
              local x=(offset-1)%width+origin.min_x-minx
              local y=math.floor((offset-1)/width)+origin.min_y-miny
              values[y*w+x+1]=index
            end
            pieces[#pieces+1]={x=minx,y=miny,w=w,h=h}
            data[#pieces]=values
            if #pieces>Parts.MAX_PIECES then return nil,"part piece count exceeds bounds" end
            state.pieces[priority+1]=#pieces
          end
        end
      end
    end
    if progress then progress(done,#work) end
  end
  assert(hull,"idle animation has no enabled objects")
  -- Visible union: every piece pixel that any per-tick canvas could show.
  local minx,miny,maxx,maxy=math.huge,math.huge,-math.huge,-math.huge
  for i,piece in ipairs(pieces) do
    local values=data[i]
    for y=0,piece.h-1 do
      local wy=piece.y+y
      if wy>=hull[2] and wy<hull[4] then
        for x=0,piece.w-1 do
          local wx=piece.x+x
          if values[y*piece.w+x+1]~=0 and wx>=hull[1] and wx<hull[3] then
            minx,miny=math.min(minx,wx),math.min(miny,wy)
            maxx,maxy=math.max(maxx,wx+1),math.max(maxy,wy+1)
          end
        end
      end
    end
    if progress then progress() end
  end
  assert(minx<maxx and miny<maxy,"idle animation has no visible pixels")
  if maxx-minx>256 or maxy-miny>256 then return nil,"sprite frame exceeds pack bounds" end
  -- Crop pieces to the union. Outside it a pixel is transparent in every
  -- piece or lies outside every per-tick canvas, so cropping is lossless and
  -- keeps every piece inside the union.
  local remap,kept,keptData={}, {}, {}
  for i,piece in ipairs(pieces) do
    local values=data[i]
    local x0,y0=math.max(piece.x,minx),math.max(piece.y,miny)
    local x1,y1=math.min(piece.x+piece.w,maxx),math.min(piece.y+piece.h,maxy)
    local bx0,by0,bx1,by1=math.huge,math.huge,-math.huge,-math.huge
    for wy=y0,y1-1 do
      for wx=x0,x1-1 do
        if values[(wy-piece.y)*piece.w+(wx-piece.x)+1]~=0 then
          bx0,by0=math.min(bx0,wx),math.min(by0,wy)
          bx1,by1=math.max(bx1,wx+1),math.max(by1,wy+1)
        end
      end
    end
    remap[i]=0
    if bx0<bx1 then
      local w,h,out=bx1-bx0,by1-by0,{}
      for y=0,h-1 do
        for x=0,w-1 do out[y*w+x+1]=values[(by0+y-piece.y)*piece.w+(bx0+x-piece.x)+1] end
      end
      kept[#kept+1]={x=bx0,y=by0,w=w,h=h};keptData[#kept]=out;remap[i]=#kept
    end
    if progress then progress() end
  end
  for _,track in ipairs(tracks) do
    for _,state in ipairs(track.states) do
      for p=1,4 do
        local index=state.pieces[p]
        if index>0 then state.pieces[p]=remap[index] end
      end
    end
  end
  pieces,data=kept,keptData
  return {tracks=tracks,pieces=pieces,data=data,min_x=minx,min_y=miny,
    width=maxx-minx,height=maxy-miny,hull=hull}
end

-- Shelf-packs pieces into a 256-wide atlas whose height is a multiple of 64.
function Parts.layout(model)
  local order={}
  for i in ipairs(model.pieces) do order[i]=i end
  table.sort(order,function(a,b)
    local pa,pb=model.pieces[a],model.pieces[b]
    if pa.h~=pb.h then return pa.h>pb.h end
    return a<b
  end)
  local x,y,shelf=0,0,0
  for _,i in ipairs(order) do
    local piece=model.pieces[i]
    if x+piece.w>Parts.ATLAS_WIDTH then x,y,shelf=0,y+shelf,0 end
    piece.ax,piece.ay=x,y
    x=x+piece.w;shelf=math.max(shelf,piece.h)
  end
  local height=math.max(Parts.ROW,math.ceil((y+shelf)/Parts.ROW)*Parts.ROW)
  if height>16384 or height/Parts.ROW>512 then return nil,"part atlas exceeds bounds" end
  model.atlasWidth,model.atlasHeight=Parts.ATLAS_WIDTH,height
  return model
end

-- Pure reference compositor: sparse palette indices in union coordinates,
-- keyed y*width+x+1, exactly what Composer.renderIndexed shows at tick.
function Parts.composeIndexed(model,tick)
  local states={}
  local cx0,cy0,cx1,cy1=math.huge,math.huge,-math.huge,-math.huge
  for r,track in ipairs(model.tracks) do
    local state=track.states[track.stateAt[Parts.trackTick(track.intro,track.period,tick)+1]]
    states[r]=state
    local b=state.bounds
    if b then
      cx0,cy0=math.min(cx0,b[1]),math.min(cy0,b[2])
      cx1,cy1=math.max(cx1,b[3]),math.max(cy1,b[4])
    end
  end
  local out={}
  for priority=4,1,-1 do
    for r=#states,1,-1 do
      local index=states[r].pieces[priority]
      if index and index>0 then
        local piece,values=model.pieces[index],model.data[index]
        for y=0,piece.h-1 do
          local wy=piece.y+y
          if wy>=cy0 and wy<cy1 then
            for x=0,piece.w-1 do
              local wx=piece.x+x
              local v=values[y*piece.w+x+1]
              if v~=0 and wx>=cx0 and wx<cx1 then
                out[(wy-model.min_y)*model.width+(wx-model.min_x)+1]=v
              end
            end
          end
        end
      end
    end
  end
  return out
end

local function flatPalette(palette)
  local out={}
  for i,c in ipairs(palette.colors) do
    out[#out+1]=c.r;out[#out+1]=c.g;out[#out+1]=c.b;out[#out+1]=c.a or 255
    if i>=256 then break end
  end
  return out
end
-- Serializable descriptor. Coordinates are relative to the union canvas.
function Parts.metadata(model,sprite)
  local tracks={}
  for r,track in ipairs(model.tracks) do
    local states={}
    for _,state in ipairs(track.states) do
      local b=state.bounds
      if b then
        states[#states+1]=1
        states[#states+1]=b[1]-model.min_x;states[#states+1]=b[2]-model.min_y
        states[#states+1]=b[3]-model.min_x;states[#states+1]=b[4]-model.min_y
      else for _=1,5 do states[#states+1]=0 end end
      for p=1,4 do states[#states+1]=state.pieces[p] end
    end
    tracks[r]={intro=track.intro,period=track.period,runs=track.runs,states=states}
  end
  local pieces={}
  for _,piece in ipairs(model.pieces) do
    pieces[#pieces+1]=piece.x-model.min_x;pieces[#pieces+1]=piece.y-model.min_y
    pieces[#pieces+1]=piece.w;pieces[#pieces+1]=piece.h
    pieces[#pieces+1]=piece.ax;pieces[#pieces+1]=piece.ay
  end
  return {format=Parts.FORMAT,version=Parts.VERSION,tickRate=60,width=model.width,height=model.height,
    anchorX=-model.min_x,anchorY=-model.min_y,atlasWidth=model.atlasWidth,atlasHeight=model.atlasHeight,
    tracks=tracks,pieces=pieces,palettes={normal=flatPalette(sprite.normal),shiny=flatPalette(sprite.shiny)}}
end

-- Palette-index atlas: red holds the index, alpha 255 marks an opaque pixel.
-- One image serves both normal and shiny palettes.
function Parts.image(model,checkpoint)
  assert(love and love.image,"LÖVE image module required for sprite import")
  local image=love.image.newImageData(model.atlasWidth,model.atlasHeight)
  for i,piece in ipairs(model.pieces) do
    if checkpoint then checkpoint() end
    local values=model.data[i]
    for y=0,piece.h-1 do
      for x=0,piece.w-1 do
        local v=values[y*piece.w+x+1]
        if v~=0 then image:setPixel(piece.ax+x,piece.ay+y,v/255,0,0,1) end
      end
    end
  end
  return image
end
-- Inert atlas descriptor so 1.0.x consumers validate and then skip this entry.
function Parts.stub(model)
  local frames=model.atlasHeight/Parts.ROW
  local durations={}
  for i=1,frames do durations[i]=1 end
  return {kind="parts",format=Parts.FORMAT,version=Parts.VERSION,width=model.atlasWidth,height=Parts.ROW,
    columns=1,frames=frames,tickRate=60,durations=durations,loopStartFrame=0,cycleTicks=frames,cycleCapped=true}
end
return Parts
