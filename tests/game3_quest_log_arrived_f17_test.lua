package.path='./?.lua;./?/init.lua;'..package.path
local P={px=160,py=96,cellX=10,cellY=6,facing='down',fieldMoveAnim=0}
function P.isVisible() return true end
function P.walkPhase() return 0 end
function P.drawFlip() return false end
package.loaded['src.core.game3.player']=P
package.loaded['src.core.game3.objects']={forDraw=function() return {} end,walkPhase=function() return 0 end}
package.loaded['src.core.game3.ow_sprites']={playerGraphicsId=function() return 7 end}
package.loaded['src.core.game3.battle']={isActive=function() return false end}
local questLogOn=true
package.loaded['src.core.game3.field_modules']={enabled=function(name) return name~='questLog' or questLogOn end}
package.loaded['src.core.game3.audio']={_mapSong=1}
package.loaded['src.import.gba.map_sections_extract']={getInfo=function() return {name='VIRIDIAN CITY'} end}
package.loaded['src.core.game3.map']={worldMidAt=function() return 1,0 end}
package.loaded['src.core.game3.field_effects']={flyActive=function() return false end,surfBlobWorldPos=function() return nil end}
local Warp={_busy=false}
package.loaded['src.core.game3.warp']=Warp
local UI={pack={text={},worldMapFlags={0x891,0x892,0x893}}}
package.loaded['src.ui.game3.quest_log']=UI
local session={name='RED',map='FR_ROUTE1',x=10,y=6,flags={}}
local game={session=session,data={maps={}}}
package.loaded['src.core.game3.runtime']={
  _game=game,
  isActive=function() return true end,
  getSession=function() return session end,
  uiBusy=function() return false end,
}
local R=require('src.core.game3.quest_log_recorder')
local Q=require('src.core.game3.quest_log')
local Flags=require('src.core.game3.scripting.flags')

local fails=0
local function check(ok,label)
  print((ok and 'PASS ' or 'FAIL ')..label)
  if not ok then fails=fails+1 end
end
local function arrivals()
  local n=0
  for _,scene in ipairs(session.questLog and session.questLog.scenes or {}) do
    for _,e in ipairs(scene.events) do if e.key=='ArrivedInLocation' then n=n+1 end end
  end
  return n
end
local function tick(n) for _=1,n or 1 do R.update(game) end end
local function enter(map) session.map=map;session._questNewScene=true end

enter('FR_ROUTE1');tick(30)
enter('FR_VIRIDIAN_CITY_POKEMON_CENTER_1F');tick(30)
check(arrivals()==0,'map changes without setworldmapflag record no Arrived')

enter('FR_VIRIDIAN_CITY');R.recordEnteredMap(session,0x891,false);tick()
check(arrivals()==1,'listed world map flag not yet set records one Arrived on the next tick')
local scene=session.questLog.scenes[#session.questLog.scenes]
check(scene.map=='FR_VIRIDIAN_CITY' and scene.events[1].args[1]=='VIRIDIAN CITY','Arrived scene opens on the town with its mapsec name')
tick(30)
check(arrivals()==1,'Arrived fires once per first entry')

enter('FR_VIRIDIAN_CITY');R.recordEnteredMap(session,0x891,true);tick(30)
check(arrivals()==1,'listed world map flag already set records no Arrived')

enter('FR_PALLET_TOWN');R.recordEnteredMap(session,0x890,false);tick(30)
check(arrivals()==1,'unlisted world map flag records no Arrived')

enter('FR_PEWTER_CITY');R.recordEnteredMap(session,0x892,false)
R.recordEnteredMap(session,0x892,true);tick(30)
check(arrivals()==1,'a later setworldmapflag on an already set listed flag clears the pending Arrived')

Warp._busy=true
enter('FR_CERULEAN_CITY');R.recordEnteredMap(session,0x893,false);tick(30)
check(arrivals()==1,'Arrived held while a warp is running')
Warp._busy=false;tick()
check(arrivals()==2,'Arrived recorded once the warp finishes')

questLogOn=false
UI.pack=nil
local ok=pcall(R.recordEnteredMap,session,0x891,false)
check(ok and session._questNewlyEntered==nil,'setworldmapflag is a no-op without the questLog module')
questLogOn=true
ok=pcall(R.recordEnteredMap,session,0x891,false)
check(not ok,'missing worldMapFlags in the cache pack is an error')
UI.pack={text={},worldMapFlags={0x891,0x892,0x893}}

local Ops=require('src.core.game3.scripting.ops_a')
local store={flags={},vars={}}
local vm={ctx={stack={},specialVars={}},store=store,adapters={}}
session._questNewlyEntered=nil
Ops.dispatchUnhooked(vm,{op='setworldmapflag',flag=0x892})
check(session._questNewlyEntered==true and Flags.getFlag(store,nil,0x892)==true,'setworldmapflag op checks the flag before setting it and marks a first entry')
Ops.dispatchUnhooked(vm,{op='setworldmapflag',flag=0x892})
check(session._questNewlyEntered==nil,'setworldmapflag op on a revisit clears the first entry mark')

local function scenes() return #session.questLog.scenes end
local function lastScene() return session.questLog.scenes[scenes()] end
enter('FR_ROUTE2')
R.event(session,'UsedTeleportToLocation',{'ABRA','PALLET TOWN'})
R.event(session,'UsedDigInLocation',{'DIGLETT','MT. MOON'})
R.event(session,'UsedFly',{'PIDGEY','PALLET TOWN'})
R.event(session,'MonsWereFullyRestoredAtCenter',{})
check(lastScene().map~='FR_ROUTE2','field moves and the nurse never start a scene')
R.event(session,'SwitchMon1WithMon2',{'A','B'})
R.event(session,'DefeatedWildMon',{})
R.event(session,'TookOnTrainersMonWithMonAndWon',{},42)
check(lastScene().map~='FR_ROUTE2','party order, wild wins and ordinary trainers never start a scene before the game is cleared')
R.event(session,'UsedTheItem',{})
R.event(session,'DepositedMonInPC',{})
check(lastScene().map~='FR_ROUTE2','item and PC party actions never start a scene before the R/S link flag')
R.event(session,'TookOnTrainersMonWithMonAndWon',{},81)
local trainerScene=lastScene()
check(trainerScene.map=='FR_ROUTE2' and #trainerScene.events==1,'a story trainer win starts a scene')
R.event(session,'UsedDigInLocation',{'DIGLETT','ROUTE 2'})
local last=lastScene()
check(last==trainerScene and #last.events==2 and last.events[2].key=='UsedDigInLocation','a field move appends to the scene already recording')

enter('FR_ROUTE3')
session.flags[Flags.IDS.FLAG_SYS_GAME_CLEAR]=true
session.flags[Flags.IDS.FLAG_SYS_CAN_LINK_WITH_RS]=true
R.event(session,'UsedFly',{'PIDGEY','PALLET TOWN'})
check(lastScene().map~='FR_ROUTE3','field moves still never start a scene after the game is cleared')
R.event(session,'SwitchMon1WithMon2',{'A','B'})
check(lastScene().map=='FR_ROUTE3','party order starts a scene after the game is cleared')
enter('FR_ROUTE4')
R.event(session,'UsedTheItem',{})
last=lastScene()
check(last.map=='FR_ROUTE4' and last.events[1].key=='UsedTheItem','item use starts a scene after the R/S link flag')

session.flags[Flags.IDS.FLAG_SYS_GAME_CLEAR]=nil
session.flags[Flags.IDS.FLAG_SYS_CAN_LINK_WITH_RS]=nil
tick(12)
local route4=lastScene()
local framesAtLeave=#route4.frames
session.map='FR_ROUTE5';tick(12)
session.map='FR_ROUTE4';P.px=P.px+192;tick(30)
check(#route4.frames==framesAtLeave,'leaving a map and coming back does not resume sampling into its old scene')
R.event(session,'UsedCut',{'ABRA'})
check(#route4.events==1,'a field move after leaving and returning does not append to the old scene')
local cont=lastScene()
check(cont~=route4 and cont.map=='FR_ROUTE4' and cont.events[1].key=='UsedCut','a field move after leaving and returning is logged while the cart scene is still recording')
P.px=P.px-192

-- pokefirered/src/quest_log_events.c:502
session.map='FR_ROUTE6';tick(6)
R.event(session,'DefeatedWildMon',{})
local route6=lastScene()
check(route6.map=='FR_ROUTE6' and route6.events[1].key=='DefeatedWildMon','a wild win on the next map is logged while the cart scene is still recording')
check(route6.span~=nil and route6.span>=cont.span,'the scene on the next map keeps the recording budget of the one it continues')

-- pokefirered/src/quest_log.c:1457
tick(6*Q.MAX_FRAMES)
check(not Q.recording(session),'the scene stops recording once its frame budget is spent')
session.map='FR_ROUTE7'
R.event(session,'DefeatedWildMon',{})
check(lastScene()==route6,'a wild win after the budget is spent does not start a scene before the game is cleared')

if fails>0 then os.exit(1) end
print('PASS Quest Log Arrived trigger and party action scene gate')
