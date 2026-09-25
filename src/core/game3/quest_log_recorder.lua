-- Engine-facing capture. Recorded actors/tiles are rendered without a field VM.
local Q=require('src.core.game3.quest_log')
local R={}
function R.location(game,session)
  local def=game and game.data and game.data.maps and game.data.maps[session.map]
  local info=require("src.import.gba.map_sections_extract").getInfo(def and def.regionMapSectionId,session.map,0)
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
  end
  for _,o in ipairs(O.forDraw()) do
    local gid=Space and Space.resolveObjectGraphicsId and o.def and Space.resolveObjectGraphicsId(o.def)
    f.actors[#f.actors+1]={id=o.localId or 1000+(tonumber(o.virtualId) or 0),x=o.px or o.cellX*16,y=o.py or o.cellY*16,
      graphicsId=gid or o.graphicsId or (o.def and (o.def.graphicsId or o.def.graphics)),
      facing=o.facing,walkPhase=O.walkPhase(o),stepFlip=o.stepFlip,frame=o.customFrame,bow=(o.bowFrames or 0)>0}
  end
  return f
end
function R.tiles(game,session,frame)
  local Map=require('src.core.game3.map')
  local def=game and game.data and game.data.maps and game.data.maps[session.map]
  if not def or not def.midLayout then return {} end
  local out={};local cx=math.floor(frame.x/16);local cy=math.floor(frame.y/16)
  for y=cy-6,cy+6 do for x=cx-8,cx+8 do
    local mid,pair=Map.worldMidAt(x,y,def)
    out[x..','..y]={mid,pair}
  end end
  return out
end
function R.event(session,key,args)
  local Runtime=package.loaded['src.core.game3.runtime']
  -- Ignore simulations/tests and sessions that aren't the active game.
  if not session or not Runtime or type(Runtime.isActive) ~= "function" or not Runtime.isActive() or (Runtime.getSession and Runtime.getSession() ~= session) then return end
  local game=Runtime._game
  local map=tostring(session.map):upper():gsub('_','')
  if map:find('TRAINERTOWER',1,true) or map:find('ELEVATOR',1,true)
      or map:find('POKEMONTRAINERFANCLUB',1,true) or map:find('SEVENISLANDHOUSEROOM',1,true) then return end
  local f=R.capture(game,session)
  Q.record(session,key,args,f);Q.addTiles(session,R.tiles(game,session,f))
  local scene=session.questLog.scenes[#session.questLog.scenes]
  if scene then scene.song=require('src.core.game3.audio')._mapSong end
end
function R.save(game)
  local session=game.session
  if not session or not session.questLog then return end
  local frame=R.capture(game,session)
  session.questLog.final={map=session.map,frames={frame},tiles=R.tiles(game,session,frame),
    song=require("src.core.game3.audio")._mapSong,
    events={{key='SavedGameAtLocation',args={R.location(game,session)},frame=1}}}
end
function R.update(game)
  local session=game.session;if not session then return end
  local Battle=require('src.core.game3.battle')
  if Battle.isActive() then return end
  local map=session.map
  if session._questMap~=map then
    session._questMap=map
    R.event(session,'ArrivedInLocation',{R.location(game,session)})
  end
  local Runtime=package.loaded['src.core.game3.runtime']
  if Runtime and Runtime.uiBusy() then return end
  session._questTick=(session._questTick or 0)+1
  if session._questTick%6~=0 then return end
  local f=R.capture(game,session)
  Q.sample(session,f,6);Q.addTiles(session,R.tiles(game,session,f))
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
    R.event(session,key,args)
  end
end
return R
