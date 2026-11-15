package.path="./?.lua;./?/init.lua;"..package.path
love=require("tests.love_stub")
local T=require("tests.harness")
local Version=require("src.core.GameVersion")
local sess
package.loaded["src.core.game3.runtime"]={getSession=function() return sess end,isActive=function() return true end}
local Space={store={flags={},vars={}}}
package.loaded["src.core.game3.scripting.space"]=Space
package.loaded["src.core.game3.map"]={current="RU_ROUTE101"}
local immunityResets=0
package.loaded["src.core.game3.encounters"]={resetRateModifiers=function() immunityResets=immunityResets+1 end}
package.loaded["src.core.game3.audio"]={playSong=function() end,restoreMapSong=function() end}
local pending,started
package.loaded["src.core.game3.battle_transition"]={pick=function() return 0 end,start=function(_,_,cb) pending=cb end}
package.loaded["src.core.game3.field"]={lock=function() end}
package.loaded["src.core.game3.battle"]={start=function(opts) started=opts;return true end,getState=function() return nil end}
local Bridge=require("src.core.game3.battle_bridge")
Bridge._interceptInstalled=true
require("tests.fixture_data.game3_battle_moves").install()
local Rse=require("src.core.game3.rse.init")
Rse.register("tv",{incrementDailyWildBattles=function() end})
for _,game in ipairs({"ruby","sapphire"}) do
  Version.set(game)
  local C=require("src.core.game3.constants").of(game)
  local poison=C:require("vars","VAR_POISON_STEP_COUNTER")
  local cases={
    {"normal wild",{wild=true},8}, {"scripted wild",{wild=true,wildScripted=true},8},
    {"roamer",{wild=true,roamer=true},8}, {"legendary",{wild=true,legendary=true},8},
    {"trainer",{},9}, {"secret base",{secretBase=true},9},
    {"first Birch",{wild=true,firstBattleKind="birch"},8,true},
    {"first boolean",{wild=true,firstBattle=true},8,true},
    {"Safari",{wild=true,safari=true},nil}, {"Wally",{wild=true,tutorialKind="wally"},nil},
    {"link",{link=true},nil,false,true}, {"recorded link",{recordedLink=true},nil,false,true},
    {"Battle Tower",{battleTower=true},nil,false,true}, {"eReader",{eReader=true},nil,false,true},
  }
  for _,row in ipairs(cases) do
    for _,initial in ipairs({11,0xFFFFFE,0xFFFFFF}) do
      sess={version=game,vars={[poison]=7},flags={},poisonSteps=7,money=500,
        party={{species=1,level=5,hp=20,maxHp=20,status=0,moves={1},pp={10}}},gameStats={[7]=initial,[8]=initial,[9]=initial}}
      Space.store={vars={[poison]=7},flags={}}
      started,pending=nil,nil;local oldResets=immunityResets
      local opts={song=1,mapBehavior=0,noWhiteout=true}
      for k,v in pairs(row[2]) do opts[k]=v end
      T.eq(Bridge.start(nil,nil,{species=1,level=2},opts),true,"accepted native battle "..row[1])
      T.eq(started,nil,"battle initialization waits for transition")
      local counted=row[3] and not row[4]
      local increment=math.min(0xFFFFFF,initial+1)
      T.eq(sess.gameStats[7],counted and increment or initial,"native pre-transition total count")
      T.eq(sess.gameStats[8],counted and row[3]==8 and increment or initial,"native pre-transition wild count")
      T.eq(sess.gameStats[9],counted and row[3]==9 and increment or initial,"native pre-transition trainer count")
      T.eq(Space.store.vars[poison],7,"poison retained before battle starts")
      pending();T.eq(type(started.onStarted),"function","owned callback survives local startOpts construction")
      started.onStarted()
      T.eq(sess.gameStats[7],row[3] and increment or initial,"native total count after successful start")
      T.eq(sess.gameStats[8],row[3]==8 and increment or initial,"native wild count after successful start")
      T.eq(sess.gameStats[9],row[3]==9 and increment or initial,"native trainer count after successful start")
      T.eq(Space.store.vars[poison],row[5] and 7 or 0,"native live poison counter hook")
      T.eq(sess.vars[poison],row[5] and 7 or 0,"session poison counter mirrors native live state")
      T.eq(immunityResets-oldResets,row[5] and 0 or 1,"native encounter immunity clears at successful start")
      for _,outcome in ipairs({"win","lose","draw","run","caught"}) do
        started.onDone(outcome)
        T.eq(sess.gameStats[7],row[3] and increment or initial,"outcome does not count battle twice")
      end
    end
  end
  sess={version=game,party={},gameStats={[7]=1,[8]=2,[9]=3}}
  T.eq(Bridge.start(nil,nil,{}, {wild=true,song=1,mapBehavior=0}),nil,"empty party cannot start battle")
  T.same(sess.gameStats,{[7]=1,[8]=2,[9]=3},"rejected start does not increment counters")
end
T.finish("game3_rs_battle_start")
