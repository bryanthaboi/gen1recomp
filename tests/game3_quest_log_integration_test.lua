package.path='./?.lua;./?/init.lua;'..package.path
require('src.core.GameVersion').set('firered')
local Q=require('src.core.game3.quest_log')
local UI=require('src.ui.game3.quest_log')
local Game=require('src.core.Game3')
local Runtime=require('src.core.game3.runtime')
local Save=require('src.core.SaveData')
local Schema=require('src.core.game3.save_schema_firered')
local Rng=require('src.core.game3.rng')
local Audio=require('src.core.game3.audio')
local Recorder=require('src.core.game3.quest_log_recorder')
local session=Schema.newGame({rngSeed=42})
local frame={x=16,y=32,actors={{id=255,x=16,y=32,graphicsId=0}}}
Q.record(session,'ArrivedInLocation',{'PALLET TOWN'},frame)
session.questLog.final={map=session.map,frames={frame},events={{key='SavedGameAtLocation',args={'PALLET TOWN'}}}}
local saved=Schema.toSaveTable(session)
assert(#Schema.fromSaveTable(saved).questLog.scenes==1)
UI.pack={text={PreviouslyOnYourQuest='History',ArrivedInLocation='Arrived in {S1}.',SavedGameAtLocation='{PLAYER} saved at {S1}.'}}
assert(UI.text('ArrivedInLocation',{['1']='PALLET TOWN'},session)=='Arrived in PALLET TOWN.')
Save.load=function()return saved end
local writes=0;Save.save=function()writes=writes+1 end
Audio.stopAll=function()end;Audio.pumpBgm=function()end
local ticks=0;Runtime.update=function()ticks=ticks+1 end
local rngTicks=0;Rng.step=function()rngTicks=rngTicks+1 end
local game=Game.new()
local key;local resets=0
game.input={step=function()end,wasPressed=function(_,k)return k==key end,reset=function()resets=resets+1 end}
local entries=0
game._enterField=function(self,s,reason) entries=entries+1;assert(reason=='continue');assert(s.money==saved.money);self.phase='field' end
game:_handleBootAction({action='continue'})
assert(game.phase=='quest_log' and entries==0)
for _=1,10 do game:fixedUpdate(1/60) end
assert(ticks==0 and rngTicks==0,'recap advanced gameplay')
game:saveGame();game:quit();assert(writes==0,'recap overwrote save')
key='a';game:fixedUpdate(1/60);assert(game.questPlayback:isFinal() and entries==0)
key='b';game:fixedUpdate(1/60);assert(entries==1 and resets==1 and not game.questPlayback)
saved.questLog=nil;game:_handleBootAction({action='continue'});assert(entries==2,'legacy save did not continue normally')
-- Recording is scoped to the active session, and event arguments are captured by value.
Runtime.active=true;Runtime.session=session;Runtime._game={session=session}
Recorder.capture=function()return frame end;Recorder.tiles=function()return {} end
local a={'TEST'};Recorder.event(session,'ArrivedInLocation',a);a[1]='WRONG'
assert(session.questLog.scenes[#session.questLog.scenes].events[2].args[1]=='TEST')
local other={map='FR_OTHER'};Recorder.event(other,'ArrivedInLocation',a);assert(other.questLog==nil)
local Pokemon=require('src.core.game3.pokemon');Pokemon.displayMonName=function(m)return m.name end
-- The French cart calls a gym LEADER "CHAMPION": the class id decides, not its name.
local st={wild=false,result='win',trainerName='BROCK',trainerClass=84,trainerClassName='CHAMPION',
 player={mon={name='BULBASAUR',hp=20,maxHp=30}},enemy={mon={name='ONIX'}}}
Recorder.battle(session,st)
local e=session.questLog.scenes[#session.questLog.scenes].events[3]
assert(e.key=='TookOnGymLeadersMonWithMonAndWon' and e.args.D4.text=='Handily')
local function keyFor(class,className)
  local s={wild=false,result='win',trainerName='X',trainerClass=class,trainerClassName=className,
   player={mon={name='BULBASAUR',hp=20,maxHp=30}},enemy={mon={name='ONIX'}}}
  Recorder.battle(session,s)
  local evs=session.questLog.scenes[#session.questLog.scenes].events
  return evs[#evs].key
end
assert(keyFor(87,'CONSEIL 4')=='TookOnEliteFoursMonWithMonAndWon')
assert(keyFor(90,'MAÎTRE')=='PlayerBattledChampionRival')
assert(keyFor(82,'LEADER')=='TookOnTrainersMonWithMonAndWon')
print('PASS Quest Log Continue, legacy save, quit, RNG isolation, event scoping and battle summary')
