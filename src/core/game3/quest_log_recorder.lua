-- Engine-facing capture. Recorded actors/tiles are rendered without a field VM.
local Q=require('src.core.game3.quest_log')
local R={}
function R.location(game,session)
  local def=game and game.data and game.data.maps and game.data.maps[session.map]
  local ok,info=pcall(require("src.import.gba.map_sections_extract").getInfo,def and def.regionMapSectionId,session.map,0)
  if not ok then info=nil end
  if info and info.name and info.name~="???" then return info.name end
  return tostring(session.map or ''):gsub('^FR_',''):gsub('_',' ')
end
function R.capture(game,session)
  local P=require('src.core.game3.player')
  local O=require('src.core.game3.objects')
  local Ow=require('src.core.game3.ow_sprites')
  local Space=package.loaded['src.core.game3.scripting.space']
  local f={x=P.px or (session.x or 0)*16,y=P.py or (session.y or 0)*16,actors={}}
  if not P.isVisible or P.isVisible() then
    f.actors[#f.actors+1]={id=255,x=f.x+(P.spriteXOffset or 0),
      y=f.y+(P.spriteYOffset or (P.jumpSpriteY and P.jumpSpriteY()) or 0),
      graphicsId=Ow.playerGraphicsId(game),facing=P.facing or 'down',
      walkPhase=P.walkPhase(),stepFlip=P.drawFlip(),fieldMove=(P.fieldMoveAnim or 0)>0}
    local bx,by=require('src.core.game3.field_effects').surfBlobWorldPos()
    if bx then f.actors[#f.actors].surf={x=bx,y=by} end
  end
  for _,o in ipairs(O.forDraw()) do
    local gid=Space and Space.resolveObjectGraphicsId and o.def and Space.resolveObjectGraphicsId(o.def)
    f.actors[#f.actors+1]={id=o.localId or 1000+(tonumber(o.virtualId) or 0),x=o.px or o.cellX*16,y=o.py or o.cellY*16,
      graphicsId=gid or o.graphicsId or (o.def and (o.def.graphicsId or o.def.graphics)),
      facing=o.facing,walkPhase=O.walkPhase(o),stepFlip=o.stepFlip,frame=o.customFrame,bow=(o.bowFrames or 0)>8 and (o.bowFrames or 0)<=40}
  end
  return Q.trimActors(f)
end
function R.fillTiles(game,session,frame,out)
  local Map=require('src.core.game3.map')
  local def=game and game.data and game.data.maps and game.data.maps[session.map]
  if not def or not def.midLayout then return out end
  local cx=math.floor(frame.x/16);local cy=math.floor(frame.y/16)
  for y=cy-6,cy+6 do for x=cx-8,cx+8 do
    local mid,pair=Map.worldMidAt(x,y,def)
    local key=x..','..y
    local t=out[key]
    if type(t)~='table' or t[1]~=mid or t[2]~=pair then
      out[key]={mid,pair}
    end
  end end
  return out
end
function R.tiles(game,session,frame)
  return R.fillTiles(game,session,frame,{})
end
local FIELD_MOVE_OR_CENTER={UsedCut=true,UsedFly=true,UsedSurf=true,UsedStrength=true,UsedFlash=true,
  UsedRockSmash=true,UsedWaterfall=true,UsedDive=true,UsedDigInLocation=true,UsedSweetScent=true,
  UsedTeleportToLocation=true,UsedSoftboiled=true,UsedMilkDrink=true,MonsWereFullyRestoredAtCenter=true}
local BEFORE_GAME_CLEAR={SwitchMon1WithMon2=true,DefeatedWildMon=true,CaughtWildMon=true}
local BEFORE_RS_LINK={UsedItemOnMonAtThisLocation=true,UsedTheItem=true,UsedTheKeyItem=true,
  MonLearnedMoveFromTM=true,MonReplacedMoveWithTM=true,MonLearnedMoveFromHM=true,MonReplacedMoveWithHM=true,
  GaveMonHeldItem=true,GaveMonHeldItem2=true,GaveMonHeldItemFromPC=true,TookHeldItemFromMon=true,
  SwappedHeldItemsOnMon=true,SwappedHeldItemFromPC=true,SwitchedPartyMonForPCMon=true,
  WithdrewMonFromPC=true,DepositedMonInPC=true}
-- pokefirered/src/quest_log_events.c:640
local STORY_TRAINER_CLASSES={[81]=true,[83]=true,[89]=true,[90]=true}
-- pokefirered/src/quest_log_events.c:603
function R.isPartyAction(session,key,trainerClass)
  if FIELD_MOVE_OR_CENTER[key] then return true end
  local Flags=require('src.core.game3.scripting.flags')
  local Space=package.loaded['src.core.game3.scripting.space']
  local store=(Space and Space.store) or session.store or session
  if not Flags.getFlag(store,nil,Flags.IDS.FLAG_SYS_GAME_CLEAR) then
    if BEFORE_GAME_CLEAR[key] then return true end
    if key=='TookOnTrainersMonWithMonAndWon' and not STORY_TRAINER_CLASSES[tonumber(trainerClass)] then return true end
  end
  return BEFORE_RS_LINK[key]==true and not Flags.getFlag(store,nil,Flags.IDS.FLAG_SYS_CAN_LINK_WITH_RS)
end
function R.event(session,key,args,trainerClass)
  if not require('src.core.game3.field_modules').enabled('questLog',session) then return end
  local Runtime=package.loaded['src.core.game3.runtime']
  -- Ignore simulations/tests and sessions that aren't the active game.
  if not session or not Runtime or type(Runtime.isActive) ~= "function" or not Runtime.isActive() or (Runtime.getSession and Runtime.getSession() ~= session) then return end
  local game=Runtime._game
  local map=tostring(session.map):upper():gsub('_','')
  if map:find('TRAINERTOWER',1,true) or map:find('ELEVATOR',1,true)
      or map:find('POKEMONTRAINERFANCLUB',1,true) or map:find('SEVENISLANDHOUSEROOM',1,true) then return end
  Q.track(session)
  -- pokefirered/src/quest_log_events.c:504
  if not Q.recording(session) and R.isPartyAction(session,key,trainerClass) then return end
  local f=R.capture(game,session)
  Q.record(session,key,args,f);Q.addTiles(session,R.tiles(game,session,f))
  local scene=session.questLog.scenes[#session.questLog.scenes]
  if scene then scene.song=require('src.core.game3.audio')._mapSong end
end
-- pokefirered/src/quest_log.c:1294
function R.cut(session)
  if session then session._questNewScene=true end
end
function R.save(game)
  local session=game.session
  -- pokefirered/src/quest_log.c:1335
  R.cut(session)
  if not session or not session.questLog then return end
  local frame=R.capture(game,session)
  session.questLog.final={map=session.map,frames={frame},tiles=R.tiles(game,session,frame),
    song=require("src.core.game3.audio")._mapSong,
    events={{key='SavedGameAtLocation',args={R.location(game,session)},frame=1}}}
end
-- pokefirered/src/quest_log_events.c:2176
function R.recordEnteredMap(session,flag,wasSet)
  if not session or not require('src.core.game3.field_modules').enabled('questLog',session) then return end
  local UI=require('src.ui.game3.quest_log')
  if not UI.pack then UI.install(require('src.core.game3.dataset').cache()) end
  local list=UI.pack and UI.pack.worldMapFlags
  if type(list)~='table' then error('Quest Log cache pack has no worldMapFlags; reimport the ROM') end
  flag=tonumber(flag)
  for _,f in ipairs(list) do
    if f==flag then session._questNewlyEntered=not wasSet or nil;return end
  end
end
function R.update(game)
  local session=game.session;if not session then return end
  Q.track(session)
  local Battle=require('src.core.game3.battle')
  if Battle.isActive() then return end
  if require('src.core.game3.field_effects').flyActive() then return end
  local Warp=package.loaded['src.core.game3.warp']
  -- pokefirered/src/quest_log_events.c:2202
  if session._questNewlyEntered and not (Warp and Warp._busy) then
    session._questNewlyEntered=nil
    R.event(session,'ArrivedInLocation',{R.location(game,session)})
  end
  local Runtime=package.loaded['src.core.game3.runtime']
  if Runtime and Runtime.uiBusy() then return end
  session._questTick=(session._questTick or 0)+1
  if session._questTick%6~=0 then return end
  local f=R.capture(game,session)
  Q.sample(session,f,6)
  local scene=Q.tileScene(session)
  if scene then R.fillTiles(game,session,f,scene.tiles) end
end
function R.battle(session,st)
  if not st or (st.result~='win' and st.result~='catch') then return end
  local Runtime=package.loaded['src.core.game3.runtime']
  local loc=R.location(Runtime and Runtime._game,session)
  local Pokemon=require('src.core.game3.pokemon')
  local function name(b) return Pokemon.displayMonName(b and (b.mon or b)) end
  local enemy=name(st.enemy);local player=name(st.player)
  if st.wild then
    local args={D0=loc,D1=enemy,D3=enemy,D5=session.name}
    R.event(session,st.result=='catch' and 'CaughtWildMon' or 'DefeatedWildMon',args)
  else
    local mon=st.player and st.player.mon or {}
    local hp,max=mon.hp or 0,mon.maxHp or (mon.stats and mon.stats.hp) or 1
    local outcome=hp>=math.floor(max/3)*2 and 'Handily' or (hp>=math.floor(max/3) and 'Tenaciously' or 'Somehow')
    local args={D0=loc,D1=st.trainerName or 'TRAINER',D2=enemy,D3=player,D4={text=outcome}}
    local key='TookOnTrainersMonWithMonAndWon'
    -- pokefirered/src/quest_log_battle.c:25 switches on the class id, which a
    -- mod renaming the class leaves alone (include/constants/trainers.h:267-273)
    local class=tonumber(st.trainerClass)
    if class==84 then key='TookOnGymLeadersMonWithMonAndWon'
    elseif class==87 then
      key='TookOnEliteFoursMonWithMonAndWon'
      args={D0=st.trainerName,D1=enemy,D2=player,D3={text=outcome}}
    elseif class==90 then
      key='PlayerBattledChampionRival';args={D0=session.name,D1=st.trainerName}
    end
    R.event(session,key,args,class)
  end
end
return R
