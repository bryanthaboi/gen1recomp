package.path='./?.lua;./?/init.lua;'..package.path
local Q=require('src.core.game3.quest_log')
local Json=require('src.link.Json')
local s={name='RED',map='FR_A',x=1,y=2,party={},flags={},money=3000}
local function frame(x) return {x=x,y=32,actors={{id=255,x=x,y=32,graphicsId=0,facing='right'}}} end
Q.record(s,'ArrivedInLocation',{[1]='PALLET TOWN'},frame(16))
for n=1,10 do Q.sample(s,frame(16+n),6) end
local saved=Q.export(s)
assert(#saved.scenes==1 and #saved.scenes[1].frames>1)
s.x=80
assert(saved.scenes[1].frames[1].x==16)
local restored=Q.restore(Json.decode(Json.encode(saved)))
local before=Json.encode(s)
local p=assert(Q.playback(restored))
assert(p:current().map=='FR_A' and p:number()==1)
p:update({a=true}); assert(p:isFinal())
p:update({b=true}); assert(p.done)
assert(Json.encode(s)==before,'playback changed live session')
for n=1,8 do s.map='FR_'..n; Q.record(s,'ArrivedInLocation',{[1]=tostring(n)},frame(n)) end
assert(#Q.export(s).scenes==4,'history must be bounded to four scenes')
assert(Q.restore(nil).version==1 and not Q.playback(Q.restore(nil)))
assert(#Q.restore({version=99,scenes={{}}}).scenes==0)
local copy=Q.export(s);copy.scenes[1].events[1].args[1]='CHANGED'
assert(Q.export(s).scenes[1].events[1].args[1]~='CHANGED','save aliases recorder')
for n=1,3000 do Q.sample(s,frame(n),6) end
local out=Q.export(s)
for _,scene in ipairs(out.scenes) do assert(#scene.frames<=Q.MAX_FRAMES and #scene.events<=Q.MAX_EVENTS) end
local a=assert(Q.playback(out)); for n=1,10000 do a:update({}) end;assert(a.done,'auto playback must finish')
print('PASS Quest Log history, persistence, limits, playback, skips and isolation')
