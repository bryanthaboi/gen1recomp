package.path="./?.lua;./?/init.lua;"..package.path
love=love or require("tests.love_stub")
local T=require("tests.harness")
local Migration=require("src.box.Migration")
local Items=require("src.box.Items")
local Store=require("src.box.Store")
local Catalog=require("src.box.Catalog")
local Serializer=require("src.core.SaveSerializer")
local CacheFs=require("src.import.CacheFs")
local GameVersion=require("src.core.GameVersion")
local oldRead,tables=CacheFs.readAt,{}
local function put(v,p,value) tables[GameVersion.cachePrefix(v)..p]=Serializer.encode(value) end
local base={hp=35,attack=55,defense=30,speed=90,special=50,specialAttack=50,specialDefense=40}
for _,v in ipairs(GameVersion.ORDER) do
  local gen=GameVersion.generation(v)
  if gen==3 then
    local root="data/generated/gba/pokemon/"
    put(v,root.."names.lua",{[25]="PIKACHU",[151]="MEW",[251]="CELEBI"})
    put(v,root.."national.lua",{toNational={[25]=25,[151]=151,[251]=251},toSpecies={[25]=25,[151]=151,[251]=251}})
    put(v,root.."meta.lua",{[25]={genderRatio=127,growthRate=0},[151]={genderRatio=255,growthRate=0},[251]={genderRatio=255,growthRate=0}})
    put(v,root.."stats.lua",{[25]={hp=35,atk=55,def=40,spe=90,spa=50,spd=50},[151]={hp=100,atk=100,def=100,spe=100,spa=100,spd=100},
      [251]={hp=100,atk=100,def=100,spe=100,spa=100,spd=100}})
    put(v,root.."move_names.lua",{[84]="THUNDERSHOCK"})
    put(v,root.."battle_moves.lua",{moves={[84]={pp=30}}})
    put(v,root.."abilities.lua",{[25]={9,31},[151]={28,0},[251]={30,0}})
    put(v,root.."ability_names.lua",{[9]="STATIC",[28]="SYNCHRONIZE",[30]="NATURAL CURE",[31]="LIGHTNINGROD"})
    put(v,"data/generated/gba/items/pack.lua",{items={[3]={name="GREAT BALL",pocket="POKE_BALLS",importance=0},
      [4]={name="POKé BALL",pocket="POKE_BALLS",importance=0},[200]={name="LEFTOVERS",pocket="ITEMS",importance=0},
      [259]={name="MACH BIKE",pocket="KEY_ITEMS",importance=1},[122]={name="ORANGE MAIL",pocket="ITEMS",importance=0}}})
  else
    local pokemon={PIKACHU={id="PIKACHU",name="PIKACHU",dex=25,growthRate="MEDIUM_FAST",genderRatio=127,catchRate=190,baseStats=base},
      MEW={id="MEW",name="MEW",dex=151,growthRate="MEDIUM_SLOW",genderRatio=255,catchRate=45,baseStats=base}}
    if gen==2 then pokemon.CELEBI={id="CELEBI",name="CELEBI",dex=251,growthRate="MEDIUM_SLOW",genderRatio=255,baseStats=base} end
    put(v,"data/generated/pokemon.lua",pokemon)
    put(v,"data/generated/moves.lua",{THUNDERSHOCK={name="THUNDERSHOCK",pp=30}})
    if gen==1 then
      put(v,"data/generated/items.lua",{POKE_BALL={id="POKE_BALL",name="POKé BALL",index=4},
        BICYCLE={id="BICYCLE",name="BICYCLE",index=6,keyItem=true},TM_01={id="TM_01",name="TM01",index=201}})
    else
      put(v,"data/generated/items.lua",{generation=2,pockets={"ITEM","KEY_ITEM","BALL","TM_HM"},
        POKE_BALL={id="POKE_BALL",name="POKé BALL",index=5,pocket="BALL"},
        LEFTOVERS={id="LEFTOVERS",name="LEFTOVERS",index=0x92,pocket="ITEM"},
        BITTER_BERRY={id="BITTER_BERRY",name="BITTER BERRY",index=0x53,pocket="ITEM"},
        BERRY={id="BERRY",name="BERRY",index=0xad,pocket="ITEM"},
        LIGHT_BALL={id="LIGHT_BALL",name="LIGHT BALL",index=0xa3,pocket="ITEM"},
        TM_DYNAMICPUNCH={id="TM_DYNAMICPUNCH",name="TM01",index=0xbf,pocket="TM_HM"},
        FLOWER_MAIL={id="FLOWER_MAIL",name="FLOWER MAIL",index=0x9e,pocket="ITEM"},
        timeCapsule={[0x19]="LEFTOVERS",[0x2d]="BITTER_BERRY",[0xbe]="BERRY",[0xff]="BERRY"}})
    end
  end
end
CacheFs.readAt=function(path) return tables[path] end;Catalog.reset()

local function entry(v,id,species,exp)
  local gen=GameVersion.generation(v)
  local mon={species=species or "PIKACHU",nickname="PIKA",ot="ALICE",otName="ALICE",otId=42,level=50,
    exp=exp or 125500,experience=exp or 125500,happiness=150,catchRate=190,
    dvs={attack=7,defense=3,speed=9,special=4},statExp={hp=65535,attack=65535,defense=65535,speed=65535,special=65535},
    moves={{id="THUNDERSHOCK",pp=15,ppUps=0,maxPp=30}}}
  return {id=id or 1,version=v,generation=gen,mon=mon,display=Catalog.describe(v,mon)}
end

for _,from in ipairs({"red","yellow","gold","crystal"}) do
  for k=0,24 do
    local out=assert(Migration.convert(entry(from,k+1,nil,125500+k),"emerald"))
    T.eq(out.nature,k,from.." EXP "..(125500+k).." gives nature "..k)
    T.eq(out.personality%25,k,from.." personality carries the EXP nature")
  end
end

do
  local e=entry("gold",7)
  local a,lines=assert(Migration.convert(e,"firered"))
  local b=assert(Migration.convert(e,"firered"))
  T.eq(Serializer.encode(a.ivs),Serializer.encode(b.ivs),"IVs are deterministic for one record")
  local want={hp=29,atk=15,def=7,spe=19,spa=9,spd=9}
  for key,iv in pairs(want) do T.eq(a.ivs[key],iv,"IV "..key.." is DV*2+1") end
  for key,ev in pairs(a.evs) do T.eq(ev,0,"EV "..key.." reset") end
  T.eq(a.abilityNum,1,"species with a second ability takes the second slot")
  T.eq(a.pokeball,4,"Poké Ball")
  T.eq(a.modernFatefulEncounter,false,"ordinary species has no fateful flag")
  T.eq(lines.natureExp,125500,"preview exposes source EXP for the nature helper")
  local other=assert(Migration.convert(entry("gold",8),"firered"))
  T.eq(Serializer.encode(other.ivs),Serializer.encode(a.ivs),"same DVs give the same IVs on any record")
  local shiny=entry("gold",9);shiny.mon.dvs={attack=15,defense=10,speed=10,special=10}
  local s=assert(Migration.convert(shiny,"emerald"))
  T.check(require("src.core.game3.pokemon").isShiny(s),"DV shininess survives with an EXP nature")
end

for _,case in ipairs({{"red","MEW",151},{"gold","MEW",151},{"gold","CELEBI",251}}) do
  local out=assert(Migration.convert(entry(case[1],3,case[2]),"emerald"))
  T.eq(out.ivs.spa,out.ivs.spd,case[2].." from "..case[1].." copies Special into both Sp. stats")
  T.eq(out.abilityNum,0,case[2].." keeps its only ability")
  T.eq(out.modernFatefulEncounter,case[3]==151,case[2].." fateful flag matches the Mew obedience check")
end

local steps=Migration.natureSteps(125503)
T.eq(steps[1].nature,"Adamant","nature helper lists the current nature first")
T.eq(steps[1].add,0,"current nature needs no EXP")
T.eq(steps[2].nature,"Naughty","next nature is one EXP away")
T.eq(steps[2].add,1,"next nature needs one EXP")

do
  local red=entry("red",11);red.mon.catchRate=0x19
  local gold=assert(Migration.convert(red,"gold"))
  T.eq(gold.item,"LEFTOVERS","catch rate 25 becomes LEFTOVERS through the Teru-sama table")
  red.mon.catchRate=0xa3
  T.eq(assert(Migration.convert(red,"crystal")).item,"LIGHT_BALL","Yellow Pikachu catch rate becomes LIGHT BALL")
  red.mon.catchRate=0
  T.eq(assert(Migration.convert(red,"gold")).item,nil,"catch rate 0 holds nothing")
  local held=entry("gold",12);held.mon.item="LEFTOVERS"
  local back=assert(Migration.convert(held,"red"))
  T.eq(back.catchRate,0x92,"Gen 2 held item becomes the Gen 1 catch rate byte")
  local again=entry("red",13);again.mon=back;again.display=Catalog.describe("red",back)
  T.eq(assert(Migration.convert(again,"gold")).item,"LEFTOVERS","held item survives a 2 to 1 to 2 round trip")
  held.mon.item="FLOWER_MAIL";held.mon.mail={message="HI"}
  T.check(not Migration.convert(held,"red"),"mail still refuses Gen 1")
end

do
  local state=Store.new()
  local red={version="red",inventory={POKE_BALL=5,BICYCLE=1,TM_01=1},bagOrder={"POKE_BALL","BICYCLE","TM_01"}}
  local rows=Items.bag(red,"red")
  T.eq(#rows,2,"key items are not offered for storage")
  T.check(not Items.deposit(state,red,"red","BICYCLE",1),"key items refuse storage")
  local s1,save1=assert(Items.deposit(state,red,"red","POKE_BALL",3))
  T.eq(save1.inventory.POKE_BALL,2,"deposit removes from the bag")
  T.eq(Items.locker(s1,"gen12")[1].count,3,"deposit adds to the shared Gen 1 and 2 stash")
  T.check(Store.validate(Serializer.decode(Serializer.encode(s1)))~=nil,"locker survives validation")
  T.check(not Items.deposit(state,red,"red","POKE_BALL",9),"cannot deposit more than the bag has")
  local key=Items.locker(s1,"gen12")[1].key
  local crystal={version="crystal",inventory={}}
  local s2,save2=assert(Items.withdraw(s1,crystal,"crystal",key,2))
  T.eq(save2.inventory.POKE_BALL,2,"Gen 1 balls withdraw into a Gen 2 bag")
  T.eq(Items.locker(s2,"gen12")[1].count,1,"withdraw removes from the stash")
  local s3=assert(Items.deposit(s1,red,"red","TM_01",1))
  local tm
  for _,row in ipairs(Items.locker(s3,"gen12")) do if row.name=="TM01" then tm=row.key end end
  T.check(not Items.withdraw(s3,crystal,"crystal",tm,1),"Gen 1 TM01 does not become Gen 2 TM01")
  local gold={version="gold",inventory={LEFTOVERS=2}}
  local s4=assert(Items.deposit(state,gold,"gold","LEFTOVERS",2))
  local left=Items.locker(s4,"gen12")[1].key
  T.check(not Items.withdraw(s4,{version="red",inventory={}},"red",left,1),"Gen 2-only items refuse a Gen 1 bag")

  s4.nextId=3
  s4.boxes[1].mons[1]=entry("gold",1)
  s4.boxes[1].mons[2]=entry("red",2)
  local s5=assert(Items.give(s4,{box=1,slot=1},left))
  T.eq(s5.boxes[1].mons[1].mon.item,"LEFTOVERS","give sets the held item")
  T.eq(Items.locker(s5,"gen12")[1].count,1,"give uses one from the stash")
  T.check(not Items.give(s4,{box=1,slot=2},left),"Gen 1 Pokémon cannot hold items")
  local s6=assert(Items.takeHeld(s5,{box=1,slot=1}))
  T.eq(s6.boxes[1].mons[1].mon.item,nil,"take clears the held item")
  T.eq(Items.locker(s6,"gen12")[1].count,2,"take returns the item to the stash")
  local mail=Store.copy(s4);mail.boxes[1].mons[1].mon.item="FLOWER_MAIL"
  T.check(not Items.takeHeld(mail,{box=1,slot=1}),"mail stays on its Pokémon")
end

do
  local state=Store.new()
  local em={version="emerald",bag={pockets={ITEMS={},KEY_ITEMS={{id=259,qty=1}},POKE_BALLS={{id=3,qty=4}},TM_CASE={},BERRY_POUCH={}}}}
  local rows=Items.bag(em,"emerald")
  T.eq(#rows,1,"Gen 3 key items are not offered for storage")
  local s1,save1=Items.deposit(state,em,"emerald",3,2)
  T.check(s1~=nil,"Gen 3 deposit works: "..tostring(save1))
  if s1 then
    T.eq(save1.bag.pockets.POKE_BALLS[1].qty,2,"Gen 3 deposit removes from the ball pocket")
    s1.nextId=2
    local out=assert(Migration.convert(entry("gold",1),"emerald"))
    s1.boxes[1].mons[1]={id=1,version="emerald",generation=3,mon=out,display=Catalog.describe("emerald",out)}
    local key=Items.balls(s1)[1].key
    local s2=assert(Items.swapBall(s1,{box=1,slot=1},key))
    T.eq(s2.boxes[1].mons[1].mon.pokeball,3,"ball swap writes the ball id")
    T.eq(Items.balls(s2)[1].count,1,"ball swap uses exactly one ball")
    T.eq(#Items.balls(s2),1,"the old Poké Ball is not refunded")
    T.check(not Items.swapBall(s2,{box=1,slot=1},key),"same ball is refused")
    local egg=Store.copy(s1);egg.boxes[1].mons[1].mon.isEgg=true
    T.check(not Items.swapBall(egg,{box=1,slot=1},key),"eggs cannot change ball")
    T.check(not Items.swapBall(s1,{box=1,slot=1},"NOPE"),"unknown ball refused")
  end
end

do
  local ctx={save={party={{species="PIKACHU",catchRate=190}}}}
  require("src.script.Commands").set_catch_rate(ctx,1,0xA3)
  T.eq(ctx.save.party[1].catchRate,0xA3,"Yellow starter Pikachu carries the LIGHT BALL catch rate byte")
  local body=assert(io.open("data/scripts/oaks_lab_yellow.lua")):read("*a")
  T.check(body:find('{ "give_pokemon", "PIKACHU", 5 }\n      rows[#rows + 1] = { "set_catch_rate", 1, 0xA3 }',1,true)~=nil,
    "Oak's Lab stamps the catch rate right after giving Pikachu")
end

CacheFs.readAt=oldRead;Catalog.reset()
T.finish("Box bank rules and items")
