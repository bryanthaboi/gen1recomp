package.path="./?.lua;./?/init.lua;"..package.path
love=love or require("tests.love_stub")
local T=require("tests.harness")
local Migration=require("src.box.Migration")
local Store=require("src.box.Store")
local Catalog=require("src.box.Catalog")
local Serializer=require("src.core.SaveSerializer")
local CacheFs=require("src.import.CacheFs")
local GameVersion=require("src.core.GameVersion")
local oldRead,tables=CacheFs.readAt,{}
local function put(v,p,value) tables[GameVersion.cachePrefix(v)..p]=Serializer.encode(value) end
for _,v in ipairs(GameVersion.ORDER) do
  local gen=GameVersion.generation(v)
  if gen==3 then
    local root="data/generated/gba/pokemon/"
    put(v,root.."names.lua",{[25]="PIKACHU"})
    put(v,root.."national.lua",{toNational={[25]=25},toSpecies={[25]=25}})
    put(v,root.."meta.lua",{[25]={genderRatio=127,growthRate=0}})
    put(v,root.."stats.lua",{[25]={hp=35,atk=55,def=40,spe=90,spa=50,spd=50}})
    put(v,root.."move_names.lua",{[84]="THUNDERSHOCK"})
    put(v,root.."battle_moves.lua",{moves={[84]={pp=30}}})
    put(v,root.."abilities.lua",{[25]={9}})
    put(v,"data/generated/gba/items/pack.lua",{items={[68]={name="RARE CANDY"}}})
  else
    put(v,"data/generated/pokemon.lua",{PIKACHU={id="PIKACHU",name="PIKACHU",dex=25,growthRate="MEDIUM_FAST",genderRatio=127,catchRate=190,
      baseStats={hp=35,attack=55,defense=30,speed=90,special=50,specialAttack=50,specialDefense=40}}})
    put(v,"data/generated/moves.lua",{THUNDERSHOCK={name="THUNDERSHOCK",pp=30}})
    put(v,"data/generated/items.lua",{RARE_CANDY={name="RARE CANDY"}})
  end
end
CacheFs.readAt=function(path) return tables[path] end;Catalog.reset()

local function hop(state,version)
  local refs={{box=1,slot=1}}
  local preview,why=Migration.preview(state,refs,version)
  T.check(preview~=nil and preview.allowed,"preview to "..version..": "..tostring(why or preview and preview.rows[1].lines[1]))
  local nextState=assert(Migration.apply(state,refs,version,preview))
  return nextState,nextState.boxes[1].mons[1]
end
local function stateWith(version,mon)
  local state=Store.new();state.nextId=2
  state.boxes[1].mons[1]={id=1,version=version,generation=GameVersion.generation(version),mon=mon,display=Catalog.describe(version,mon)}
  return state
end

do
  local dvs={attack=15,defense=8,speed=11,special=3}
  local statExp={hp=3025,attack=2704,defense=2900,speed=3100,special=2500}
  local mon={species="PIKACHU",nickname="PIKA",ot="ALICE",otName="ALICE",otId=42,level=20,experience=8000,happiness=120,
    dvs=Store.copy(dvs),statExp=Store.copy(statExp),caughtTime=2,caughtLevel=10,caughtLocation=0x23,caughtByGender="girl",
    moves={{id="THUNDERSHOCK",pp=30,ppUps=0,maxPp=30}}}
  local state=stateWith("crystal",mon)
  local emeraldState,em=hop(state,"emerald")
  T.eq(em.mon.otGender,1,"Gen 2 caught-by-girl becomes Gen 3 OT gender")
  local _,back=hop(emeraldState,"crystal")
  for key,value in pairs(dvs) do T.eq(back.mon.dvs[key],value,"Crystal → Emerald → Crystal keeps the "..key.." DV") end
  for key,value in pairs(statExp) do T.eq(back.mon.statExp[key],value,"Crystal → Emerald → Crystal keeps "..key.." Stat Exp") end
  T.eq(back.mon.caughtTime,2,"round trip keeps caught time")
  T.eq(back.mon.caughtLevel,10,"round trip keeps caught level")
  T.eq(back.mon.caughtLocation,0x23,"round trip keeps caught location")
  T.eq(back.mon.caughtByGender,"girl","round trip keeps caught-by gender")

  local trained=Store.copy(emeraldState)
  trained.boxes[1].mons[1].mon.evs.atk=200
  local _,raised=hop(trained,"crystal")
  T.eq(raised.mon.statExp.attack,200*200,"Gen 3 training raises archived Stat Exp")
  T.eq(raised.mon.statExp.speed,3100,"untrained stats keep archived Stat Exp")
end

do
  local mon={species=25,nickname="PIKA",ot="ALICE",otName="ALICE",otId=42,otSecretId=777,level=20,exp=8000,friendship=120,
    personality=0x1234567,ivs={hp=30,atk=29,def=7,spe=18,spa=24,spd=3},evs={hp=40,atk=100,def=8,spe=60,spa=0,spd=12},
    metLocation=16,metLevel=5,metGame=3,pokeball=2,otGender=1,language=2,ribbons=0,contest={cool=10,beauty=0,cute=0,smart=0,tough=0,sheen=3},
    abilityNum=0,moves={84},pp={30},ppBonusesPacked=0,heldItem=0}
  local state=stateWith("emerald",mon)
  local crystalState,cr=hop(state,"crystal")
  T.eq(cr.mon.caughtLevel,5,"Gen 3 met level becomes Gen 2 caught level")
  T.eq(cr.mon.caughtByGender,"girl","Gen 3 OT gender becomes Gen 2 caught-by gender")
  local _,back=hop(crystalState,"emerald")
  T.eq(back.mon.personality,mon.personality,"Emerald → Crystal → Emerald keeps personality")
  T.eq(back.mon.otSecretId,777,"round trip keeps Secret ID")
  for key,value in pairs(mon.ivs) do T.eq(back.mon.ivs[key],value,"round trip keeps the "..key.." IV") end
  for key,value in pairs(mon.evs) do T.eq(back.mon.evs[key],value,"round trip keeps the "..key.." EV") end
  for _,key in ipairs({"metLocation","metLevel","metGame","pokeball","otGender"}) do
    T.eq(back.mon[key],mon[key],"round trip keeps "..key)
  end
  T.eq(back.mon.contest.cool,10,"round trip keeps contest stats")
end

CacheFs.readAt=oldRead;Catalog.reset()
T.finish("Box migration round trip")
