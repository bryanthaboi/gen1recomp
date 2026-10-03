-- Adapted from AnimaEngine v1.0.0, Copyright (c) 2026 KillDaWill, MIT.
-- See ANIMAENGINE_LICENSE and PROVENANCE.md in this directory.
-- Serialized IDs/offsets are zero-based; Lua arrays are one-based.
local Animation = {}
local function reader(data)
  assert(type(data) == "string" and #data <= 8 * 1024 * 1024, "invalid Nitro member")
  local r = { data = data, size = #data }
  function r:check(p, n, limit)
    assert(type(p) == "number" and p >= 0 and n >= 0 and p + n <= (limit or #data), "truncated Nitro data")
  end
  function r:u16(p) self:check(p, 2); local a,b = data:byte(p+1,p+2); return a + b*256 end
  function r:u32(p) self:check(p, 4); return self:u16(p) + self:u16(p+2)*65536 end
  function r:s16(p) local n=self:u16(p); return n>=32768 and n-65536 or n end
  function r:s32(p) local n=self:u32(p); return n>=2147483648 and n-4294967296 or n end
  return r
end
local function sections(r, magic)
  r:check(0, 16)
  assert(r.data:sub(1,4)==magic, "incorrect Nitro animation magic")
  local out, p = {}, 16
  while p < r.size do
    r:check(p, 8)
    local size=r:u32(p+4)
    assert(size>=8, "invalid Nitro section size")
    r:check(p,size)
    local tag=r.data:sub(p+1,p+4)
    assert(not out[tag], "duplicate Nitro section")
    out[tag]={offset=p,size=size,limit=p+size}
    p=p+size
  end
  return out
end
local function identity(index)
  return {index=index,cell_id=index,map_index=index,rotation=0,
    scale_x=4096,scale_y=4096,translate_x=0,translate_y=0,transform_type=0}
end
local sizes = {[0]=2,[1]=16,[2]=8,[3]=4}
local function element(r,p,format,limit)
  assert(sizes[format], "unsupported animation element format")
  r:check(p,sizes[format],limit)
  local frame=identity(r:u16(p))
  frame.transform_type=format
  if format==1 then
    frame.rotation=r:s16(p+2); frame.scale_x=r:s32(p+4); frame.scale_y=r:s32(p+8)
    frame.translate_x=r:s16(p+12); frame.translate_y=r:s16(p+14)
    assert(math.abs(frame.scale_x)<=65536 and math.abs(frame.scale_y)<=65536, "animation scale exceeds bounds")
  elseif format==2 then
    frame.translate_x=r:s16(p+4); frame.translate_y=r:s16(p+6)
  end
  return frame
end
local function labels(r,section,animations)
  if not section then return end
  local start=section.offset+8
  local base=start+#animations*4
  r:check(start,#animations*4,section.limit)
  for i,animation in ipairs(animations) do
    local p=base+r:u32(start+(i-1)*4)
    r:check(p,1,section.limit)
    local chars={}
    for j=0,30 do
      if p+j>=section.limit then break end
      local byte=r.data:byte(p+j+1)
      if byte==0 then break end
      chars[#chars+1]=string.char(byte)
    end
    animation.label=table.concat(chars)
  end
end
local function parseBank(data,magic,isNmar)
  local r=reader(data)
  local sec=sections(r,magic)
  local section=assert(sec.KNBA,"missing KNBA animation section")
  local s,limit=section.offset,section.limit
  r:check(s,24,limit)
  local count=r:u16(s+8)
  assert(count>0 and count<=2048,"invalid animation count")
  local tableBase=s+8+r:u32(s+12)
  local frameBase=s+8+r:u32(s+16)
  local elementBase=s+8+r:u32(s+20)
  r:check(tableBase,count*16,limit); r:check(frameBase,0,limit); r:check(elementBase,0,limit)
  local offsetSet,total={},0
  for i=0,count-1 do
    local p=tableBase+i*16
    local n=r:u16(p)
    assert(n>0 and n<=4096,"invalid frame count")
    total=total+n
    assert(total<=65536,"animation bank frame limit exceeded")
    local base=frameBase+r:u32(p+12)
    r:check(base,n*8,limit)
    for j=0,n-1 do offsetSet[r:u32(base+j*8)]=true end
  end
  local offsets={}
  for offset in pairs(offsetSet) do offsets[#offsets+1]=offset end
  offsets[#offsets+1]=limit-elementBase
  table.sort(offsets)
  local spans={}
  for i=1,#offsets-1 do spans[offsets[i]]=offsets[i+1]-offsets[i] end
  local bank={animations={}}
  for i=0,count-1 do
    local p=tableBase+i*16
    local n,format=r:u16(p),r:u16(p+4)
    local animation={frames={},loop_start=r:u16(p+2),format=format,
      playback_type=r:u32(p+8),label="",duration=0}
    if animation.loop_start>=n then animation.loop_start=0 end
    local base=frameBase+r:u32(p+12)
    for j=0,n-1 do
      local f=base+j*8
      local offset=r:u32(f)
      local ep=elementBase+offset
      local available=math.min(spans[offset] or 0,limit-ep)
      r:check(ep,2,limit)
      local resolved=format
      if not isNmar then
        if available==4 and r:u16(ep+2)==52428 then resolved=3
        elseif not sizes[resolved] or available<sizes[resolved] then
          if available==2 or available==4 then resolved=0
          elseif available==8 then resolved=2
          elseif available>=16 then resolved=1
          else error("invalid NANR element span") end
        end
      end
      local frame=element(r,ep,resolved,ep+available)
      frame.duration=r:u16(f+4); frame.marker=r:u16(f+6)
      animation.duration=animation.duration+frame.duration
      animation.frames[#animation.frames+1]=frame
    end
    bank.animations[#bank.animations+1]=animation
  end
  labels(r,sec.LBAL,bank.animations)
  bank.animation_count=#bank.animations
  return bank
end
local function protected(fn,...)
  local ok,value=pcall(fn,...)
  if ok then return value end
  return nil,tostring(value)
end
function Animation.nanr(data) return protected(parseBank,data,"RNAN",false) end
function Animation.nmcr(data)
  return protected(function()
    local r=reader(data); local section=assert(sections(r,"RCMN").KBCM,"missing KBCM")
    local s,limit=section.offset,section.limit
    r:check(s,24,limit)
    local count=r:u16(s+8); assert(count>0 and count<=2048,"invalid map count")
    local tableBase=s+8+r:u32(s+12); r:check(tableBase,count*8,limit)
    local recordBase=tableBase+count*8
    local bank={maps={}}
    local total=0
    for i=0,count-1 do
      local p=tableBase+i*8; local n=r:u16(p)
      assert(n<=4096,"invalid map record count")
      total=total+n; assert(total<=65536,"multicell record limit exceeded")
      local base=recordBase+r:u32(p+4); r:check(base,n*8,limit)
      local map={records={}}
      for j=0,n-1 do
        local f=base+j*8
        map.records[#map.records+1]={animation_index=r:u16(f),x=r:s16(f+2),y=r:s16(f+4),flags=r:s16(f+6)}
      end
      bank.maps[#bank.maps+1]=map
    end
    bank.map_count=#bank.maps
    return bank
  end)
end
function Animation.nmar(data)
  local parsed,err=protected(parseBank,data,"RAMN",true)
  if parsed then return parsed end
  -- Legacy explicit NMAR map tables are accepted; unknown-section heuristics are not.
  return protected(function()
    local r=reader(data); local sec=sections(r,"RAMN")
    local section=assert(sec.KNMA or sec.KNAM,err)
    local base=section.offset+8; r:check(base,8,section.limit)
    local count=r:u16(base); assert(count>0 and count<=2048,"invalid NMAR count")
    local entries=base+r:u32(base+4); r:check(entries,count*4,section.limit)
    local bank={animations={}}
    for i=0,count-1 do
      local frame=identity(r:u16(entries+i*4)); frame.duration=1
      bank.animations[#bank.animations+1]={frames={frame},loop_start=0,
        playback_type=2,duration=1,label="",flags=r:u16(entries+i*4+2)}
    end
    labels(r,sec.LBAL,bank.animations)
    return bank
  end)
end
local function rangeDuration(animation,first,last,step)
  local total=0
  for i=first,last,step do total=total+animation.frames[i].duration end
  return total
end
local function selectRange(animation,first,last,step,tick)
  local chosen=first
  for i=first,last,step do
    chosen=i; local duration=animation.frames[i].duration
    if duration>0 then if tick<duration then return animation.frames[i] end; tick=tick-duration end
  end
  return animation.frames[chosen]
end
function Animation.frame(bank,index,tick)
  local animation=bank and bank.animations and bank.animations[index+1]
  if not animation or #animation.frames==0 then return nil,"missing animation" end
  tick=math.max(0,math.floor(tick or 0))
  local n,loopStart=#animation.frames,(animation.loop_start or 0)+1
  local duration=rangeDuration(animation,1,n,1)
  if duration<=0 then return animation.frames[1] end
  local playback=animation.playback_type
  local loop=playback==2 or playback==4
  local ping=playback==3 or playback==4
  local reverseStart=n-1
  local reverseEnd=loop and loopStart or 1
  local reverseDuration=ping and reverseStart>=reverseEnd and
    rangeDuration(animation,reverseStart,reverseEnd,-1) or 0
  local sequence=duration+reverseDuration
  if loop then
    local prefix=rangeDuration(animation,1,loopStart-1,1)
    local period=rangeDuration(animation,loopStart,n,1)+reverseDuration
    if tick>=sequence then tick=period>0 and prefix+(tick-prefix)%period or tick%sequence end
  else tick=math.min(tick,sequence-1) end
  if tick<duration or not ping or reverseDuration==0 then
    return selectRange(animation,1,n,1,tick)
  end
  return selectRange(animation,reverseStart,reverseEnd,-1,tick-duration)
end
function Animation.idle(nmar)
  for i,animation in ipairs(nmar and nmar.animations or {}) do
    if animation.label=="stay" then return animation.frames[1].map_index,i-1 end
  end
  local first=nmar and nmar.animations and nmar.animations[1]
  return first and first.frames[1].map_index or 0,first and 0 or nil
end
function Animation.duration(bank,index)
  local animation=bank and bank.animations[index+1]
  return animation and rangeDuration(animation,1,#animation.frames,1) or 0
end
function Animation.period(bank,index)
  local animation=bank and bank.animations[index+1]
  if not animation then return 1,0 end
  local n=#animation.frames
  local loopStart=(animation.loop_start or 0)+1
  local loop=animation.playback_type==2 or animation.playback_type==4
  local ping=animation.playback_type==3 or animation.playback_type==4
  local reverseStart=n-1
  local reverseEnd=loop and loopStart or 1
  local reverse=ping and reverseStart>=reverseEnd and
    rangeDuration(animation,reverseStart,reverseEnd,-1) or 0
  if loop then
    return math.max(1,rangeDuration(animation,loopStart,n,1)+reverse),
      rangeDuration(animation,1,loopStart-1,1)
  end
  return 1,math.max(0,rangeDuration(animation,1,n,1)+reverse-1)
end
function Animation.loopPrefix(bank,index)
  local _,prefix=Animation.period(bank,index)
  return prefix
end
function Animation.cycleTicks(nanr,map,maximum)
  maximum=maximum or 240
  local period,prefix=1,0
  local function gcd(a,b) while b~=0 do a,b=b,a%b end; return a end
  for _,record in ipairs(map.records) do
    local duration,intro=Animation.period(nanr,record.animation_index)
    prefix=math.max(prefix,intro)
    if duration>0 then
      local candidate=period/gcd(period,duration)*duration
      if candidate+prefix>maximum then return maximum,true,prefix end
      period=candidate
    end
  end
  return prefix+period,false,prefix
end
return Animation
