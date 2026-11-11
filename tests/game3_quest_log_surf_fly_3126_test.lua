package.path='./?.lua;./?/init.lua;'..package.path
local Json=require('src.link.Json')
local FE=require('src.core.game3.field_effects')
local Q=require('src.core.game3.quest_log')

local P={px=160,py=96,cellX=10,cellY=6,facing='left',surfing=true,fieldMoveAnim=0}
function P.isVisible() return true end
function P.walkPhase() return 0 end
function P.drawFlip() return false end
package.loaded['src.core.game3.player']=P
package.loaded['src.core.game3.objects']={forDraw=function() return {} end,walkPhase=function() return 0 end}
local owDraws={}
package.loaded['src.core.game3.ow_sprites']={
  playerGraphicsId=function() return 7 end,
  draw=function(gid,x,y) owDraws[#owDraws+1]={gid=gid,x=x,y=y} return true end,
}
package.loaded['src.core.game3.battle']={isActive=function() return false end}
package.loaded['src.core.game3.field_modules']={enabled=function() return true end}
package.loaded['src.core.game3.audio']={_mapSong=1}
package.loaded['src.import.gba.map_sections_extract']={getInfo=function() return {name='ROUTE 21'} end}
package.loaded['src.core.game3.map']={worldMidAt=function() return 1,0 end}
local session={name='RED',map='FR_ROUTE21_NORTH',x=10,y=6}
local game={session=session,data={maps={}}}
package.loaded['src.core.game3.runtime']={
  _game=game,
  isActive=function() return true end,
  getSession=function() return session end,
  uiBusy=function() return false end,
}
local R=require('src.core.game3.quest_log_recorder')

local fails=0
local function check(ok,label)
  print((ok and 'PASS ' or 'FAIL ')..label)
  if not ok then fails=fails+1 end
end

FE._surfBob={y2=-2}
local f=R.capture(game,session)
local s=f.actors[1].surf
check(type(s)=='table' and s.x==152 and s.y==86,'surfing capture records the blob position')
P.surfing=false
check(R.capture(game,session).actors[1].surf==nil,'walking capture records no blob')
P.surfing=true

for _=1,30 do R.update(game) end
local scenes=session.questLog.scenes
check(#scenes==1 and scenes[1].events[1].key=='ArrivedInLocation','arrival recorded on first tick')
local frames=#scenes[1].frames
check(frames>1,'surfing frames sampled')
check(scenes[1].frames[frames].actors[1].surf~=nil,'sampled surfing frame carries the blob')

local restored=Q.restore(Json.decode(Json.encode(Q.export(session))))
check(restored.scenes[1].frames[2].actors[1].surf~=nil,'blob survives export and restore')
local legacy=Q.restore({version=1,scenes={{map='FR_A',frames={{x=0,y=0,actors={{id=255,x=0,y=0,surf={x='bad'}}}}},
  events={{key='ArrivedInLocation',args={'X'},frame=1}}}}})
check(legacy.scenes[1].frames[1].actors[1].surf==nil,'malformed blob dropped on restore')

local function fr(x,bx) return {x=x,y=96,actors={{id=255,x=x,y=96,graphicsId=7,facing='left',surf={x=bx,y=86}}}} end
local pb=Q.playback({version=1,scenes={{map='FR_A',frames={fr(160,152),fr(166,158)},
  events={{key='ArrivedInLocation',args={'X'},frame=1}}}}})
pb.ticks=3
local mid=pb:frame().actors[1].surf
check(mid and math.abs(mid.x-155)<1e-9,'playback interpolates the blob between samples')

FE._anims={{kind='fly_out'}}
local before=#scenes[1].frames
for _=1,60 do R.update(game) end
check(#scenes[1].frames==before,'no samples while fly-out runs')
session.map='FR_PALLET_TOWN'
FE._anims={{kind='fly_in'}}
for _=1,60 do R.update(game) end
check(#scenes==1,'arrival held while fly-in runs')
FE._anims={}
package.loaded['src.core.game3.field']={_flyLanding=true}
for _=1,12 do R.update(game) end
check(#scenes==1,'arrival held while fly landing is pending')
package.loaded['src.core.game3.field']._flyLanding=false
R.update(game)
check(#scenes==2 and scenes[2].map=='FR_PALLET_TOWN','arrival fires once the fly animation ends')
package.loaded['src.core.game3.field']=nil

local noop=function() end
love=love or {}
love.graphics=setmetatable({newShader=function() return {} end},{__index=function() return noop end})
package.loaded['src.core.game3.tileset_native']={get=function() return nil end}
package.loaded['src.ui.game3.frlg_font']={draw=noop,wrap=function(t) return t end,COLOR={}}
package.loaded['src.ui.game3.pokedex_chrome']={drawControlInfoLeft=noop}
package.loaded['src.ui.game3.quest_log']=nil
local UI=require('src.ui.game3.quest_log')
UI.pack={text={ArrivedInLocation='Arrived',PreviouslyOnYourQuest='Previously'}}
local blobs={}
local realDraw=FE.drawSurfBlob
FE.drawSurfBlob=function(sx,sy,facing,step) blobs[#blobs+1]={sx=sx,sy=sy,facing=facing,step=step,ow=#owDraws} return true end
pb=Q.playback({version=1,scenes={{map='FR_A',frames={fr(160,152)},events={{key='ArrivedInLocation',args={'X'},frame=1}}}}})
UI.draw(pb,session)
FE.drawSurfBlob=realDraw
local cx=math.floor(160+8-120);local cy=math.floor(96+8-80)
check(#blobs==1 and blobs[1].sx==152-cx and blobs[1].sy==86-cy and blobs[1].facing=='left','recap draws the blob at the recorded spot')
check(#blobs==1 and blobs[1].ow==0 and #owDraws==1,'recap draws the blob under the player')
blobs={}
FE.drawSurfBlob=function() blobs[#blobs+1]=true return true end
pb=Q.playback({version=1,scenes={{map='FR_A',frames={{x=0,y=0,actors={{id=255,x=0,y=0,graphicsId=7}}}},
  events={{key='ArrivedInLocation',args={'X'},frame=1}}}}})
UI.draw(pb,session)
FE.drawSurfBlob=realDraw
check(#blobs==0,'old recordings without a blob draw none')

if fails>0 then os.exit(1) end
print('PASS Quest Log surf blob and fly gate')
