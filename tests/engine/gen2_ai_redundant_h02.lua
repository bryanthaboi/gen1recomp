package.path='./?.lua;./?/init.lua;'..package.path
local Ai=require('src.battle.gen2.Ai')
local Mon=require('src.battle.gen2.Mon')
local Battle=require('src.battle.gen2.Battle')
local GameVersion=require('src.core.GameVersion')
local checks,failures=0,0
local function eq(got,want,name)
  checks=checks+1
  if got~=want then failures=failures+1;if failures<=25 then print('FAIL '..name..' got='..tostring(got)..' want='..tostring(want)) end end
end
eq(Ai.SMART.EFFECT_ATTRACT,Ai.SMART.EFFECT_SWAGGER,'source SMART shared label')
local function context(move,mine,theirs,love,confused)
  return {moves={{id=move,pp=15},{id='TACKLE',pp=35}},
    moveDef=function(id) return id=='TACKLE' and {effect='EFFECT_NORMAL_HIT',power=35,type='NORMAL'} or {effect='EFFECT_'..id,power=0,type='NORMAL'} end,
    attacker={gender=mine,level=20,stats={attack=30},types={'NORMAL'}},
    defender={gender=theirs,attract=love,confused=confused,hp=50,stats={defense=30},types={'NORMAL'}},flags=Ai.FLAGS.BASIC,random=function() return 0 end,
    typeChart={types={NORMAL={category='physical'}},matchups={}}}
end
local cases={
  {'same','ATTRACT','male','male',false,false,true},
  {'user unknown','ATTRACT','unknown','female',false,false,true},
  {'target unknown','ATTRACT','male','unknown',false,false,true},
  {'already love','ATTRACT','male','female',true,false,true},
  {'opposite','ATTRACT','male','female',false,false,false},
  {'Swagger confused','SWAGGER','male','female',false,true,true},
  {'Swagger love only','SWAGGER','male','female',true,false,false},
  {'Swagger unknown','SWAGGER','unknown','unknown',false,false,false},
}
for _,row in ipairs(cases) do
  local name,move,mine,theirs,love,confused,bad=unpack(row)
  local c=context(move,mine,theirs,love,confused)
  local rolls=0;c.random=function() rolls=rolls+1;return 0 end
  local chosen,scores=Ai.choose(c)
  eq(scores[1],bad and 30 or 20,name..' BASIC source score')
  eq(chosen,bad and 'TACKLE' or move,name..' BASIC choice')
  eq(rolls,1,name..' BASIC tie roll only')
  c.flags=0;rolls=0;chosen,scores=Ai.choose(c)
  eq(chosen,move,name..' no flags preserves random choice');eq(#scores,0,name..' no flags bypass scores');eq(rolls,1,name..' no flags one roll')
end
local missing=context('ATTRACT',nil,'female',false,false)
local _,scores=Ai.choose(missing);eq(scores[1],30,'missing gender conservatively redundant')
local overrideCalls=0
missing.data={gen2AiClasses={BASIC={kind='layer',flag='BASIC',score=function(view,def,score)
  overrideCalls=overrideCalls+1;eq(view.attacker.gender,nil,'mod receives original missing gender');return score-3
end}}}
_,scores=Ai.choose(missing);eq(scores[1],17,'registered BASIC owns score');eq(overrideCalls,2,'registered BASIC runs once per move')
local oldVersion=GameVersion.get()
for _,version in ipairs({'gold','silver','crystal'}) do
  local root=os.getenv('POKEPORT_GEN2_'..version:upper()..'_DATA')
  if not root then print('SKIP H02 actual '..version..' dispatch; set POKEPORT_GEN2_'..version:upper()..'_DATA')
  else
    GameVersion.set(version)
    local data={}
    for _,name in ipairs({'pokemon','moves','trainers','type_chart'}) do data[name]=assert(loadfile(root..'/'..name..'.lua'))() end
    local attrs=assert(data.trainers.classes.WHITNEY.attributes)
    eq(Ai.has(Ai.flagsOf(attrs),'BASIC'),true,version..' actual Whitney BASIC')
    eq(Ai.has(Ai.flagsOf(attrs),'SMART'),true,version..' actual Whitney SMART')
    for _,row in ipairs(cases) do
      local name,move,mine,theirs,love,confused,bad=unpack(row)
      local function new(gender)
        return assert(Mon.new(data,gender=='unknown' and 'DITTO' or gender=='female' and 'NIDORAN_F' or 'NIDORAN_M',20,{dvs={attack=15,defense=3,speed=15,special=5}}))
      end
      local enemy,player=new(mine),new(theirs)
      enemy.moves={{id=move,pp=15,maxPp=15},{id='TACKLE',pp=35,maxPp=35}}
      local battle=Battle.new({data=data,party={player},trainer={party={enemy},attributes=attrs},random=function() return 0 end})
      local v=battle:volatile(player);v.attract=love or nil;v.confuseCount=confused and 2 or nil
      local realChoose,captured=Ai.choose
      Ai.choose=function(c) captured=c;return realChoose(c) end
      local ok,chosen=pcall(battle.vanillaEnemyMove,battle)
      Ai.choose=realChoose
      assert(ok,chosen)
      eq(captured.attacker.gender,mine,version..' '..name..' attacker bridge')
      eq(captured.defender.gender,theirs,version..' '..name..' defender bridge')
      eq(captured.defender.attract,love or nil,version..' '..name..' love bridge')
      eq(captured.defender.confused,confused,version..' '..name..' confused bridge')
      captured.flags=Ai.FLAGS.BASIC
      local _s,scores=Ai.choose(captured);eq(scores[1],bad and 30 or 20,version..' '..name..' actual BASIC')
      captured.flags=Ai.FLAGS.SMART
      local _,smart=Ai.choose(captured)
      captured.flags=Ai.FLAGS.SMART+Ai.FLAGS.BASIC
      local _,both=Ai.choose(captured)
      eq(both[1]-smart[1],bad and 10 or 0,version..' '..name..' isolated BASIC+SMART delta')
      if bad then eq(chosen,'TACKLE',version..' '..name..' full actual trainer rejects redundant') end
    end
    local ditto=assert(Mon.new(data,'DITTO',20,{dvs={attack=15,defense=3,speed=15,special=5}}))
    local female=assert(Mon.new(data,'NIDORAN_F',20,{dvs={attack=15,defense=3,speed=15,special=5}}))
    female.moves={{id='ATTRACT',pp=15,maxPp=15},{id='TACKLE',pp=35,maxPp=35}}
    local b=Battle.new({data=data,party={female},trainer={party={ditto},attributes=attrs},random=function() return 0 end})
    b:useMove(ditto,female,'TRANSFORM')
    eq(ditto.species,'NIDORAN_F',version..' actual Transform copies species')
    eq(ditto.gender,'unknown',version..' actual Transform keeps original gender')
    eq(b:vanillaEnemyMove(),'TACKLE',version..' transformed original gender reaches BASIC')
    b:untransform(ditto);eq(ditto.species,'DITTO',version..' untransform restores species')
    b:volatile(female).attract=true;b:clearVolatile(female)
    eq(b:volatile(female).attract,nil,version..' actual volatile clear drops love')
  end
end
GameVersion.set(oldVersion)
print('H02 AI redundancy '..(checks-failures)..'/'..checks)
assert(failures==0,tostring(failures)..' H02 failures')
