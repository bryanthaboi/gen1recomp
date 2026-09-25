-- Native Quest Log: bounded, data-only scenes. Playback never runs game logic.
-- pret quest_log.c: four scenes, descending scene numbers, A next / B finish.
local Q = { MAX_SCENES=4, MAX_FRAMES=300, MAX_EVENTS=8 }
local function copy(v)
  if type(v)~='table' then return v end
  local t={}; for k,x in pairs(v) do t[k]=copy(x) end; return t
end
-- Equal flat tables (no nested tables): a recorded tile already holds it.
local function sameFlat(a,b)
  if type(a)~='table' or type(b)~='table' then return false end
  for k,v in pairs(b) do if type(v)=='table' or a[k]~=v then return false end end
  for k in pairs(a) do if b[k]==nil then return false end end
  return true
end
local function empty() return {version=1,scenes={}} end
function Q.restore(value)
  local log=empty()
  if type(value)~='table' or value.version~=1 or type(value.scenes)~='table' then return log end
  for i=math.max(1,#value.scenes-Q.MAX_SCENES+1),#value.scenes do
    local scene=value.scenes[i]
    if type(scene)=='table' and type(scene.map)=='string' and type(scene.frames)=='table'
        and #scene.frames>0 and type(scene.events)=='table' and #scene.events>0 then
      local row={map=scene.map,frames={},events={},tiles=copy(scene.tiles or {}),song=scene.song}
      for j=1,math.min(#scene.frames,Q.MAX_FRAMES) do
        local f=scene.frames[j]
        if type(f)=='table' and type(f.x)=='number' and type(f.y)=='number'
            and type(f.actors)=='table' then row.frames[#row.frames+1]=copy(f) end
      end
      for j=1,math.min(#scene.events,Q.MAX_EVENTS) do
        local e=scene.events[j]
        if type(e)=='table' and type(e.key)=='string' and type(e.args)=='table' then
          row.events[#row.events+1]=copy(e)
        end
      end
      if #row.frames>0 and #row.events>0 then log.scenes[#log.scenes+1]=row end
    end
  end
  if type(value.final)=="table" and type(value.final.frames)=="table" and #value.final.frames>0 then
    log.final=Q.restore({version=1,scenes={value.final}}).scenes[1]
  end
  return log
end
function Q.export(session) return Q.restore(session and session.questLog) end
function Q.record(session,key,args,frame)
  if not session or not frame or not session.map then return end
  session.questLog=session.questLog or empty()
  local scenes=session.questLog.scenes
  local scene=scenes[#scenes]
  if session._questNewScene or not scene or scene.map~=session.map or #scene.frames>=Q.MAX_FRAMES or #scene.events>=Q.MAX_EVENTS then
    session._questNewScene=nil
    scene={map=session.map,frames={copy(frame)},events={}}
    scenes[#scenes+1]=scene
    if #scenes>Q.MAX_SCENES then table.remove(scenes,1) end
  end
  local event={key=key,args=copy(args or {}),frame=#scene.frames}
  local previous=scene.events[#scene.events]
  -- Repeated healing/arrival at the same spot should not evict useful history.
  if previous and previous.key==key and previous.frame==event.frame and key=="MonsWereFullyRestoredAtCenter" then return end
  scene.events[#scene.events+1]=event
end
function Q.sample(session,frame,elapsed)
  local scenes=session and session.questLog and session.questLog.scenes
  local scene=scenes and scenes[#scenes]
  if session._questNewScene or not scene or scene.map~=session.map or #scene.frames>=Q.MAX_FRAMES then return end
  session._questSampleTicks=(session._questSampleTicks or 0)+(elapsed or 1)
  if session._questSampleTicks<6 then return end
  session._questSampleTicks=0
  scene.frames[#scene.frames+1]=copy(frame)
end
-- Tiles are deduplicated per scene, outside the 10 Hz actor samples.
function Q.addTiles(session,tiles)
  local scenes=session and session.questLog and session.questLog.scenes
  local scene=scenes and scenes[#scenes]
  if session._questNewScene or not scene or scene.map~=session.map or #scene.frames>=Q.MAX_FRAMES then return end
  scene.tiles=scene.tiles or {}
  -- Sampled every 6 ticks over the same ~220 cells: keep a recorded tile
  -- whose {mid,pair} is unchanged instead of re-copying it (steady garbage).
  for key,tile in pairs(tiles or {}) do
    if not sameFlat(scene.tiles[key],tile) then scene.tiles[key]=copy(tile) end
  end
end
local Playback={}; Playback.__index=Playback
function Q.playback(log,finalScene)
  log=Q.restore(log)
  if #log.scenes==0 then return nil end
  return setmetatable({scenes=log.scenes,index=1,ticks=0,final=copy(finalScene or log.final)},Playback)
end
function Playback:current() return self.scenes[self.index] or self.final end
function Playback:number() return math.max(0,#self.scenes-self.index+1) end
function Playback:isFinal() return self.index>#self.scenes end
function Playback:next()
  if self:isFinal() then self.done=true else
    self.index=self.index+1; self.ticks=0
    if self:isFinal() and not self.final then self.done=true end
  end
end
function Playback:update(input)
  if self.done then return end
  input=input or {}; self.ticks=self.ticks+1
  if input.b then self.done=true; return end
  if input.a then self:next(); return end
  local scene=self:current()
  local duration=self:isFinal() and 127 or math.max(180,#scene.frames*6,#scene.events*180)
  if self.ticks>=duration then self:next() end
end
function Playback:frame()
  local scene=self:current()
  if not scene then return end
  local frames=scene.frames
  local i=math.min(#frames,math.floor(self.ticks/6)+1)
  local f=copy(frames[i]); local n=frames[i+1]
  -- Smooth the recorded 10 Hz movement to the native 60 Hz presentation.
  if n then
    local t=(self.ticks%6)/6
    if math.abs(n.x-f.x)<=32 and math.abs(n.y-f.y)<=32 then
      f.x=f.x+(n.x-f.x)*t;f.y=f.y+(n.y-f.y)*t
    end
    local byId={};for _,a in ipairs(n.actors) do byId[a.id]=a end
    for _,a in ipairs(f.actors) do
      local b=byId[a.id]
      if b and math.abs(a.x-b.x)<=32 and math.abs(a.y-b.y)<=32 then
        a.x=a.x+(b.x-a.x)*t;a.y=a.y+(b.y-a.y)*t
      end
    end
  end
  return f
end
function Playback:event()
  local scene=self:current();if not scene then return end
  local duration=math.max(180,#scene.frames*6,#scene.events*180)
  return scene.events[math.min(#scene.events,math.floor(self.ticks/(duration/#scene.events))+1)]
end
return Q
