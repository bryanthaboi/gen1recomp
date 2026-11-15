local ORDER = {
 "ENGINE_RADIO_CARD",
 "ENGINE_MAP_CARD",
 "ENGINE_PHONE_CARD",
 "ENGINE_EXPN_CARD",
 "ENGINE_POKEGEAR",
 "ENGINE_DAY_CARE_MAN_HAS_EGG",
 "ENGINE_DAY_CARE_MAN_HAS_MON",
 "ENGINE_DAY_CARE_LADY_HAS_MON",
 "ENGINE_MOM_SAVING_MONEY",
 "ENGINE_MOM_ACTIVE",
 "ENGINE_UNUSED_TWO_DAY_TIMER_ON",
 "ENGINE_POKEDEX",
 "ENGINE_UNOWN_DEX",
 "ENGINE_CAUGHT_POKERUS",
 "ENGINE_ROCKET_SIGNAL_ON_CH20",
 "ENGINE_CREDITS_SKIP",
 "ENGINE_MOBILE_SYSTEM",
 "ENGINE_BUG_CONTEST_TIMER",
 "ENGINE_SAFARI_ZONE",
 "ENGINE_ROCKETS_IN_RADIO_TOWER",
 "ENGINE_BIKE_SHOP_CALL_ENABLED",
 "ENGINE_UNUSED_STATUSFLAGS2_5",
 "ENGINE_REACHED_GOLDENROD",
 "ENGINE_ROCKETS_IN_MAHOGANY",
 "ENGINE_STRENGTH_ACTIVE",
 "ENGINE_ALWAYS_ON_BIKE",
 "ENGINE_DOWNHILL",
 "ENGINE_ZEPHYRBADGE",
 "ENGINE_HIVEBADGE",
 "ENGINE_PLAINBADGE",
 "ENGINE_FOGBADGE",
 "ENGINE_MINERALBADGE",
 "ENGINE_STORMBADGE",
 "ENGINE_GLACIERBADGE",
 "ENGINE_RISINGBADGE",
 "ENGINE_BOULDERBADGE",
 "ENGINE_CASCADEBADGE",
 "ENGINE_THUNDERBADGE",
 "ENGINE_RAINBOWBADGE",
 "ENGINE_SOULBADGE",
 "ENGINE_MARSHBADGE",
 "ENGINE_VOLCANOBADGE",
 "ENGINE_EARTHBADGE",
 "ENGINE_UNLOCKED_UNOWNS_A_TO_K",
 "ENGINE_UNLOCKED_UNOWNS_L_TO_R",
 "ENGINE_UNLOCKED_UNOWNS_S_TO_W",
 "ENGINE_UNLOCKED_UNOWNS_X_TO_Z",
 "ENGINE_UNLOCKED_UNOWNS_UNUSED_4",
 "ENGINE_UNLOCKED_UNOWNS_UNUSED_5",
 "ENGINE_UNLOCKED_UNOWNS_UNUSED_6",
 "ENGINE_UNLOCKED_UNOWNS_UNUSED_7",
 "ENGINE_FLYPOINT_PLAYERS_HOUSE",
 "ENGINE_FLYPOINT_DEBUG",
 "ENGINE_FLYPOINT_PALLET",
 "ENGINE_FLYPOINT_VIRIDIAN",
 "ENGINE_FLYPOINT_PEWTER",
 "ENGINE_FLYPOINT_CERULEAN",
 "ENGINE_FLYPOINT_ROCK_TUNNEL",
 "ENGINE_FLYPOINT_VERMILION",
 "ENGINE_FLYPOINT_LAVENDER",
 "ENGINE_FLYPOINT_SAFFRON",
 "ENGINE_FLYPOINT_CELADON",
 "ENGINE_FLYPOINT_FUCHSIA",
 "ENGINE_FLYPOINT_CINNABAR",
 "ENGINE_FLYPOINT_INDIGO_PLATEAU",
 "ENGINE_FLYPOINT_NEW_BARK",
 "ENGINE_FLYPOINT_CHERRYGROVE",
 "ENGINE_FLYPOINT_VIOLET",
 "ENGINE_FLYPOINT_AZALEA",
 "ENGINE_FLYPOINT_CIANWOOD",
 "ENGINE_FLYPOINT_GOLDENROD",
 "ENGINE_FLYPOINT_OLIVINE",
 "ENGINE_FLYPOINT_ECRUTEAK",
 "ENGINE_FLYPOINT_MAHOGANY",
 "ENGINE_FLYPOINT_LAKE_OF_RAGE",
 "ENGINE_FLYPOINT_BLACKTHORN",
 "ENGINE_FLYPOINT_SILVER_CAVE",
 "ENGINE_FLYPOINT_UNUSED",
 "ENGINE_LUCKY_NUMBER_SHOW",
 "ENGINE_UNUSED_STATUSFLAGS2_3",
 "ENGINE_KURT_MAKING_BALLS",
 "ENGINE_DAILY_BUG_CONTEST",
 "ENGINE_QWILFISH_SWARM",
 "ENGINE_TIME_CAPSULE",
 "ENGINE_ALL_FRUIT_TREES",
 "ENGINE_GOT_SHUCKIE_TODAY",
 "ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED",
 "ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY",
 "ENGINE_MT_MOON_SQUARE_CLEFAIRY",
 "ENGINE_UNION_CAVE_LAPRAS",
 "ENGINE_GOLDENROD_UNDERGROUND_GOT_HAIRCUT",
 "ENGINE_GOLDENROD_DEPT_STORE_TM27_RETURN",
 "ENGINE_DAISYS_GROOMING",
 "ENGINE_INDIGO_PLATEAU_RIVAL_FIGHT",
 "ENGINE_DAILY_MOVE_TUTOR",
 "ENGINE_BUENAS_PASSWORD",
 "ENGINE_BUENAS_PASSWORD_2",
 "ENGINE_GOLDENROD_DEPT_STORE_SALE_IS_ON",
 "ENGINE_GAME_TIMER_MOBILE",
 "ENGINE_PLAYER_IS_FEMALE",
 "ENGINE_FOREST_IS_RESTLESS",
 "ENGINE_JACK_READY_FOR_REMATCH",
 "ENGINE_HUEY_READY_FOR_REMATCH",
 "ENGINE_GAVEN_READY_FOR_REMATCH",
 "ENGINE_BETH_READY_FOR_REMATCH",
 "ENGINE_JOSE_READY_FOR_REMATCH",
 "ENGINE_REENA_READY_FOR_REMATCH",
 "ENGINE_JOEY_READY_FOR_REMATCH",
 "ENGINE_WADE_READY_FOR_REMATCH",
 "ENGINE_RALPH_READY_FOR_REMATCH",
 "ENGINE_LIZ_READY_FOR_REMATCH",
 "ENGINE_ANTHONY_READY_FOR_REMATCH",
 "ENGINE_TODD_READY_FOR_REMATCH",
 "ENGINE_GINA_READY_FOR_REMATCH",
 "ENGINE_ARNIE_READY_FOR_REMATCH",
 "ENGINE_ALAN_READY_FOR_REMATCH",
 "ENGINE_DANA_READY_FOR_REMATCH",
 "ENGINE_CHAD_READY_FOR_REMATCH",
 "ENGINE_TULLY_READY_FOR_REMATCH",
 "ENGINE_BRENT_READY_FOR_REMATCH",
 "ENGINE_TIFFANY_READY_FOR_REMATCH",
 "ENGINE_VANCE_READY_FOR_REMATCH",
 "ENGINE_WILTON_READY_FOR_REMATCH",
 "ENGINE_PARRY_READY_FOR_REMATCH",
 "ENGINE_ERIN_READY_FOR_REMATCH",
 "ENGINE_BEVERLY_HAS_NUGGET",
 "ENGINE_JOSE_HAS_STAR_PIECE",
 "ENGINE_WADE_HAS_ITEM",
 "ENGINE_GINA_HAS_LEAF_STONE",
 "ENGINE_ALAN_HAS_FIRE_STONE",
 "ENGINE_DANA_HAS_THUNDERSTONE",
 "ENGINE_DEREK_HAS_NUGGET",
 "ENGINE_TULLY_HAS_WATER_STONE",
 "ENGINE_TIFFANY_HAS_PINK_BOW",
 "ENGINE_WILTON_HAS_ITEM",
 "ENGINE_JACK_MONDAY_MORNING",
 "ENGINE_HUEY_WEDNESDAY_NIGHT",
 "ENGINE_GAVEN_THURSDAY_MORNING",
 "ENGINE_BETH_FRIDAY_AFTERNOON",
 "ENGINE_JOSE_SATURDAY_NIGHT",
 "ENGINE_REENA_SUNDAY_MORNING",
 "ENGINE_JOEY_MONDAY_AFTERNOON",
 "ENGINE_WADE_TUESDAY_NIGHT",
 "ENGINE_RALPH_WEDNESDAY_MORNING",
 "ENGINE_LIZ_THURSDAY_AFTERNOON",
 "ENGINE_ANTHONY_FRIDAY_NIGHT",
 "ENGINE_TODD_SATURDAY_MORNING",
 "ENGINE_GINA_SUNDAY_AFTERNOON",
 "ENGINE_ARNIE_TUESDAY_MORNING",
 "ENGINE_ALAN_WEDNESDAY_AFTERNOON",
 "ENGINE_DANA_THURSDAY_NIGHT",
 "ENGINE_CHAD_FRIDAY_MORNING",
 "ENGINE_TULLY_SUNDAY_NIGHT",
 "ENGINE_BRENT_MONDAY_MORNING",
 "ENGINE_TIFFANY_TUESDAY_AFTERNOON",
 "ENGINE_VANCE_WEDNESDAY_NIGHT",
 "ENGINE_WILTON_THURSDAY_MORNING",
 "ENGINE_PARRY_FRIDAY_AFTERNOON",
 "ENGINE_ERIN_SATURDAY_NIGHT",
 "ENGINE_KRIS_IN_CABLE_CLUB",
 "ENGINE_DUNSPARCE_SWARM",
 "ENGINE_YANMA_SWARM",
}
package.path="./?.lua;./?/init.lua;"..package.path
local EngineFlagsFixture=require("tests.fixture_data.gen2_engine_flags")
love=require("tests.love_stub")
local Apr=require("src.core.gen2.Apricorns")
local Swarm=require("src.core.gen2.Roamers").Swarm
local World=require("src.world.gen2.World")
local Specials=require("src.script.gen2.Specials")
local pass,fail=0,0
local function test(ok,label,detail)
 if ok then pass=pass+1;print("PASS "..label)
 else fail=fail+1;print("FAIL "..label..(detail and " | "..detail or "")) end
end
local function world(save,offset)
 local order={};for i,name in ipairs(ORDER) do order[i+(offset or 0)]=name end
 require("src.world.gen2.FieldMoves").bindEngineFlags(order)
 return setmetatable({game={save=save},constants={engineFlagOrder=order}}, {__index=World})
end
local function seed(version,offset)
 local s={version=version,engineFlags={},dailyReset={day=57,remaining=1},crystal={kenjiBreak=2},dailyFlags={}}
 for _,id in ipairs({97,160,161}) do s.engineFlags[id+(offset or 0)]=true end
 for id=101,158 do s.engineFlags[id+(offset or 0)]=true end
 for _,id in ipairs({98,99,100,159}) do s.engineFlags[id+(offset or 0)]=true end
 local w=world(s,offset)
 return s,w,w:engineFlagResolver()
end
local function poll(s,resolve,day)
 return Apr.checkDailyResetTimer(s,{day=day,hour=0,minute=0,second=0},resolve)
end
for _,offset in ipairs({0,400}) do
 local s,w,res=seed("crystal",offset)
 test(not poll(s,res,57),"Crystal same-day does not expire offset "..offset)
 test(s.engineFlags[97+offset] and s.engineFlags[101+offset] and s.crystal.kenjiBreak==2,"same-day sale/phone/Kenji preserved")
 test(poll(s,res,58),"Crystal actual timer expires")
 test(s.dailyReset.day==58 and s.dailyReset.remaining==1,"timer restarts once")
 for _,id in ipairs({97,160,161}) do
  test(not s.engineFlags[id+offset],ORDER[id+1].." clears via actual resolver offset "..offset)
 end
 for _,group in ipairs({{101,124,"rematch"},{125,134,"phone item"},{135,158,"phone time-of-day"}}) do
  local stale={}
  for id=group[1],group[2] do if s.engineFlags[id+offset] then stale[#stale+1]=ORDER[id+1] end end
  test(#stale==0,"all modeled "..group[3].." flags clear offset "..offset,table.concat(stale,","))
 end
 for _,id in ipairs({98,99,100,159}) do test(s.engineFlags[id+offset]==true,"unrelated neighbor "..ORDER[id+1].." retained") end
 test(w:readVar(0x1a)==1,"Kenji 2→1 reaches actual VAR_KENJI_BREAK consumer")
 local after=s.crystal.kenjiBreak
 test(not poll(s,res,58) and s.crystal.kenjiBreak==after,"second same-day poll leaves Kenji unchanged")
end
for _,version in ipairs({"gold","silver"}) do
 local s=seed(version)
 EngineFlagsFixture.bind("gold")
 s.cartTimers={daily="0123456789abcdef"};s.cartDayCareWild="abcdef"
 s.engineFlags[79]=true;s.dailyFlags.swarm=true;s.swarmMap="DARK_CAVE";s.swarmMaps={DUNSPARCE="DARK_CAVE"};s.dailyFlags.fishingSwarm=1
 test(poll(s,nil,58),version.." expiry still runs")
 test(not s.engineFlags[79] and not Swarm.active(s),version.." ordinary daily flag clears")
 test(s.engineFlags[97] and s.engineFlags[101] and s.engineFlags[158] and s.crystal.kenjiBreak==2,version.." Crystal-only sentinel state unaffected")
 test(s.cartTimers.daily=="0123456789abcdef" and s.cartDayCareWild=="abcdef",version.." Crystal packed reset helpers leave carriers unchanged")
 test(Swarm.check(s)==1 and not s.swarmMap and not s.swarmMaps.DUNSPARCE and not s.dailyFlags.fishingSwarm,version.." inactive map/fishing cleanup retained")
end
for _,start in ipairs({0,1}) do
 local s,_,res=seed("crystal");s.crystal.kenjiBreak=start
 local calls=0;local oldMath,oldSpecial=math.random,Specials.random
 local function rng(n) calls=calls+1;return n and math.min(n,4) or 0.99 end
 math.random=rng;Specials.random=rng
 poll(s,res,58)
 math.random=oldMath;Specials.random=oldSpecial
 local k=s.crystal.kenjiBreak
 test(k and k>=3 and k<=6,"Kenji "..start.." samples 3–6 after expiry","actual="..tostring(k)..", observed rng calls="..calls)
end
local s,_,res=seed("crystal");poll(s,res,60)
test(s.crystal.kenjiBreak==1,"elapsed three days causes one Kenji decrement, matching one source reset event")
for _,kind in ipairs({"DUNSPARCE","YANMA"}) do
 local s={version="crystal",engineFlags={[160]=kind=="DUNSPARCE",[161]=kind=="YANMA"},swarmMaps={DUNSPARCE="DARK_CAVE",YANMA="ROUTE_35"},dailyReset={day=57,remaining=1},dailyFlags={}}
 local map=kind=="DUNSPARCE" and "DARK_CAVE" or "ROUTE_35"
 local other=kind=="DUNSPARCE" and "ROUTE_35" or "DARK_CAVE"
 test(Swarm.onMap(s,map)==kind,"Crystal imported active "..kind.." table visible without Gold bool")
 test(Swarm.onMap(s,other)==nil,"Crystal inactive sibling map does not activate")
 Swarm.check(s)
 test(s.swarmMaps.DUNSPARCE=="DARK_CAVE" and s.swarmMaps.YANMA=="ROUTE_35","Crystal same-day cleanup preserves stored source map pairs")
end
local s={version="crystal",engineFlags={[160]=false,[161]=false},dailyFlags={},swarmMaps={DUNSPARCE="DARK_CAVE",YANMA="ROUTE_35"}}
test(Swarm.onMap(s,"DARK_CAVE")==nil and Swarm.onMap(s,"ROUTE_35")==nil,"map bytes alone do not activate Crystal grass swarm")
local Vm=require("src.script.gen2.Vm")
local Events=require("src.world.gen2.Events")
local function vmFlag(save,id,op)
 local vm=Vm.new({generation=2,gate={{op=op,flag=id},{op="end"}}},{},Events.new(),{})
 vm.engineFlags=save.engineFlags
 assert(vm:start("gate"));vm:update()
 return vm.scriptVar
end
for _,id in ipairs({97,111,125,145,160,161}) do
 local s,_,res=seed("crystal");s.engineFlags={}
 vmFlag(s,id,"setflag")
 test(vmFlag(s,id,"checkflag")==1,"actual VM producer/consumer before expiry "..ORDER[id+1])
 poll(s,res,58)
 test(vmFlag(s,id,"checkflag")==0,"actual VM source gate after expiry "..ORDER[id+1])
end
local sampled,calls=nil,0
local old=Specials.random
Specials.random=function(n) calls=calls+1;assert(n==4);return 4 end
Specials.HANDLERS.SampleKenjiBreakCountdown({specials={setKenjiBreak=function(v)sampled=v end}})
Specials.random=old
test(sampled==6 and calls==1,"existing actual Kenji sampler supports one controlled 3–6 draw")

local cache = os.getenv("H11_CRYSTAL_CACHE") or (os.getenv("HOME") .. "/Library/Application Support/LOVE/bsa1003-buena-crystal-b/crystal/data/generated")
local function load(name) local f=loadfile(cache.."/"..name..".lua");return f and f() end
local scripts,constants=load("scripts"),load("constants")
if scripts and constants then
 local data={pokemon=load("pokemon"),moves=load("moves"),items=load("items"),maps=load("maps")}
 local encounters,text=load("encounters"),load("text")
 local BC=require("src.core.gen2.BugContest")
 local oldNow=BC.now
 local today=57
 BC.now=function()return {day=today,hour=12,minute=0,second=0} end
 local s={version="crystal",engineFlags={},dailyReset={day=57,remaining=1},crystal={kenjiBreak=2},dailyFlags={},party={},player={}}
 local w=world(s)
 w.constants=constants;w.maps=data.maps;w.encounters=encounters
 w.map={id="ROUTE_32",inBounds=function()return true end,cellCollision=function()return 0x29 end}
 w.player={cellX=5,cellY=5,facing="up"};w.game.data=data
 w.stepContext=function()return {phone={standingOnEntrance=true,random=function()return 1 end}} end
 local function run(key)
  local blocks={}
  local vm=Vm.new(scripts,text,Events.new(),{
   specialOrder=constants.specialOrder,
   specials={save=function()return s end,data=function()return data end},
   getEngineFlag=function(id)return s.engineFlags[id] end,
   setEngineFlag=function(id,value)s.engineFlags[id]=value or nil end,
   setSwarm=function(g,n,k)w:setSwarm(g,n,k) end,
   changeBlock=function(x,y,b)blocks[#blocks+1]={x,y,b} end,
   showText=function(_,done)done() end,waitButton=function(done)done() end,
  })
  test(vm:start(key),"cache script starts "..key)
  for _=1,200 do if not vm:running() then break end;vm:update() end
  test(not vm:running(),"cache script finishes "..key)
  return blocks,vm
 end
 run("2f:573c")
 test(s.engineFlags[97],"actual Todd producer sets sale")
 local blocks=run("15:671b")
 test(#blocks==2,"actual rooftop callback creates sale boxes and booth")
 run("2f:56a6");run("2f:5887")
 test(s.engineFlags[160] and s.engineFlags[161],"actual Anthony/Arnie producers set independent flags")
 test(Swarm.onMap(s,"DARK_CAVE_VIOLET_ENTRANCE")=="DUNSPARCE" and Swarm.onMap(s,"ROUTE_35")=="YANMA","actual source-produced map pairs reach swarm reader")
 local shifted={version="crystal",engineFlags={[560]=true,[561]=false,[482]=true},dailyFlags={fishingSwarm=1},swarmMaps={DUNSPARCE="DARK_CAVE_VIOLET_ENTRANCE",YANMA="ROUTE_35"}}
 local shiftedWorld=world(shifted,400)
 shiftedWorld.encounters=encounters;shiftedWorld.game.data=data;shiftedWorld.maps=data.maps
 shiftedWorld.map=w.map;shiftedWorld.player=w.player
 local resolve=shiftedWorld:engineFlagResolver()
 test(Swarm.onMap(shifted,"DARK_CAVE_VIOLET_ENTRANCE",resolve)=="DUNSPARCE" and Swarm.onMap(shifted,"ROUTE_35",resolve)==nil,"shifted metadata keeps grass active bits independent")
 shiftedWorld.map={id="DARK_CAVE_VIOLET_ENTRANCE"}
 test(shiftedWorld:wildTables().grass.DARK_CAVE_VIOLET_ENTRANCE==encounters.swarmGrass.DARK_CAVE_VIOLET_ENTRANCE,"actual World grass table reads shifted metadata flag")
 shiftedWorld.map=w.map
 run("2f:5699");run("2f:5172")
 test(s.engineFlags[111] and s.engineFlags[145] and s.engineFlags[125],"actual phone writers populate rematch/daypart/item")
 s.engineFlags[82]=true;s.dailyFlags={fishingSwarm=1}
 local oldRng=love.math.random;love.math.random=function()return 1 end
 local outcome,fish=w:rollFishing("SUPER_ROD")
 test(outcome=="battle" and fish.species=="QWILFISH","import-shaped82/type1 reaches actual ROM super-rod Qwilfish")
 local shiftedOutcome,shiftedFish=shiftedWorld:rollFishing("SUPER_ROD")
 test(shiftedOutcome=="battle" and shiftedFish.species=="QWILFISH","actual World rod reads shifted fishing metadata flag")
 s.engineFlags[82]=nil;run("2f:5544")
 test(s.engineFlags[82] and s.dailyFlags.fishingSwarm==1 and not s.dailyFlags.swarm,"actual Ralph producer sets source flag/type without Gold bool")
 outcome,fish=w:rollFishing("SUPER_ROD")
 test(outcome=="battle" and fish.species=="QWILFISH","actual Ralph producer reaches real rod consumer")
 s.engineFlags[82]=false;s.dailyFlags.swarm=true
 outcome,fish=w:rollFishing("SUPER_ROD")
 test(outcome=="battle" and fish.species=="TENTACOOL","explicitfalse82 overrides stale Gold-shaped bool")
 s.engineFlags[82]=true
 w.map.cellCollision=function()return 0x71 end
 w:checkTimeEvents()
 test(s.engineFlags[97] and s.swarmMaps.YANMA=="ROUTE_35","actual same-day World poll preserves sale/map")
 today=58;w:checkTimeEvents()
 test(not s.engineFlags[97] and not s.engineFlags[160] and not s.engineFlags[161],"actual World expiry ends sale and both grass swarms")
 test(not s.engineFlags[111] and not s.engineFlags[145] and not s.engineFlags[125],"actual World expiry clears real phone producer state")
 test(w:readVar(0x1a)==1,"actual World expiry advances Kenji to consumer value1")
 s.engineFlags[97]=true;s.dailyReset={day=57,remaining=1};s.bugContest={active=true}
 w:checkTimeEvents()
 test(s.engineFlags[97] and s.dailyReset.day==57 and s.crystal.kenjiBreak==1,"actual Bug Contest branch skips daily reset")
 s.bugContest.active=false;s.engineFlags[97]=nil;s.dailyReset={day=58,remaining=1}
 test(s.swarmMaps.YANMA=="ROUTE_35" and s.swarmMaps.DUNSPARCE=="DARK_CAVE_VIOLET_ENTRANCE" and s.dailyFlags.fishingSwarm==1,"Crystal expiry retains inactive grass/fish byte carriers")
 blocks=run("15:671b");test(#blocks==0,"actual rooftop callback stops sale block changes after expiry")
 w.map.cellCollision=function()return 0x29 end
 outcome,fish=w:rollFishing("SUPER_ROD")
 test(outcome=="battle" and fish.species=="TENTACOOL","real rod returns to ordinary group after World expiry")
 run("2f:56a6");run("2f:5887");test(s.engineFlags[160] and s.engineFlags[161],"actual phone producers can announce new swarms after expiry")
 love.math.random=oldRng;BC.now=oldNow
 local GS=require("src.save_convert.Gen2Save")
 local SY=require("src.save_convert.Gen2Syms").crystal
 local G2=require("tests.fixtures.save.gen2_build")
 local B=require("tests.fixtures.save.bytes")
 local L=G2.layout("crystal")
 local bytes=G2.build({version="crystal",patch=function(b)
  b[SY.wCurDay]=57;b[SY.wDailyResetTimer]=1;b[SY.wDailyResetTimer+1]=57
  b[SY.wSwarmFlags]=255;b[SY.wDailyFlags1]=4;b[SY.wFishingSwarmFlag]=1
  for _,name in ipairs({"wDailyRematchFlags","wDailyPhoneItemFlags","wDailyPhoneTimeOfDayFlags"}) do
   for i=0,3 do b[SY[name]+i]=255 end
  end
  b[SY.wUnusedDailyFlag]=255;b[SY.wUnusedTwoDayTimerOn]=165
  b[SY.wKenjiBreakTimer]=2
  b[SY.wDunsparceMapGroup]=data.maps.DARK_CAVE_VIOLET_ENTRANCE.group;b[SY.wDunsparceMapNumber]=data.maps.DARK_CAVE_VIOLET_ENTRANCE.map
  b[SY.wYanmaMapGroup]=data.maps.ROUTE_35.group;b[SY.wYanmaMapNumber]=data.maps.ROUTE_35.map
 end})
 local imported=assert(GS.decode(bytes,"crystal",data))
 test(imported.engineFlags[82] and imported.engineFlags[160] and imported.engineFlags[161] and not (imported.dailyFlags and imported.dailyFlags.swarm),"true SRAM imports Crystal active bits without Gold bool")
 local function resetBytes(raw,first,swarm,unused)
  local b=B.fromString(raw)
  for _,name in ipairs({"wDailyRematchFlags","wDailyPhoneItemFlags","wDailyPhoneTimeOfDayFlags"}) do
   test(b[SY[name]]==first and b[SY[name]+1]==unused and b[SY[name]+2]==unused and b[SY[name]+3]==unused,"full source four-byte reset "..name)
  end
  test(b[SY.wUnusedDailyFlag]==unused and b[SY.wSwarmFlags]==swarm,"unused daily and swarm bits match source reset")
  test(b[SY.wUnusedTwoDayTimerOn]==165 and b[SY.wFishingSwarmFlag]==1,"packed reset preserves unrelated daily and fishing carrier bytes")
 end
 poll(imported,world(imported):engineFlagResolver(),57)
 resetBytes(assert(GS.encode(imported,"crystal",bytes,data)),255,255,255)
 poll(imported,world(imported):engineFlagResolver(),58)
 local encoded=assert(GS.encode(imported,"crystal",bytes,data))
 resetBytes(encoded,0,0,0)
 resetBytes(assert(GS.encode(imported,"crystal",nil,data)),0,0,0)
 test(GS.checksumValid(encoded,L) and GS.backupValid(encoded,L),"expired SRAM primary and backup checksums valid")
 local decoded=assert(GS.decode(encoded,"crystal",data))
 test(not decoded.engineFlags[97] and not decoded.engineFlags[160] and not decoded.engineFlags[161] and not decoded.engineFlags[101] and not decoded.engineFlags[125] and not decoded.engineFlags[135],"expired modeled source flag groups roundtrip cleared")
 test(decoded.crystal.kenjiBreak==1 and decoded.dailyFlags.fishingSwarm==1 and decoded.swarmMaps.YANMA=="ROUTE_35","SRAM retains Kenji and inactive map/type carriers")
 local damaged=B.fromString(encoded);damaged[L.sChecksum]=(damaged[L.sChecksum]+1)%256
 local backup=assert(GS.decode(B.pack(damaged),"crystal",data))
 test(not backup.engineFlags[97] and backup.crystal.kenjiBreak==1 and backup.swarmMaps.YANMA=="ROUTE_35","backup recovery retains post-expiry state")
 resetBytes(assert(GS.encode(backup,"crystal",bytes,data)),0,0,0)
 for _,id in ipairs({101,125,135,160}) do decoded.engineFlags[id]=true end
 local announced=assert(GS.encode(decoded,"crystal",bytes,data))
 resetBytes(announced,1,4,0)
 test(GS.checksumValid(announced,L) and GS.backupValid(announced,L),"today's modeled flags restore after packed reset with valid checksums")
 local serializer=require("src.core.SaveSerializer")
 local native=assert(serializer.decode(serializer.encode(decoded)))
 test(native.crystal.kenjiBreak==1 and native.swarmMaps.YANMA=="ROUTE_35" and not native.engineFlags[97],"native serializer roundtrip retains cleared flags/inactive pairs")
 local NativeSave=require("src.core.gen2.Save")
 local SD=require("src.core.SaveData")
 local oldFs=SD.persistenceFs;SD.persistenceFs=function()return love.filesystem end
 test(NativeSave.save(decoded),"actual native save writes only in-memory LÖVE stub filesystem")
 local restored=assert(NativeSave.load("crystal"))
 SD.persistenceFs=oldFs
 test(restored.crystal.kenjiBreak==1 and restored.swarmMaps.YANMA=="ROUTE_35" and not restored.engineFlags[97],"actual native load retains source reset state")
 resetBytes(assert(GS.encode(restored,"crystal",bytes,data)),1,4,0)
else print("SKIP cache-backed H11 source scripts/SRAM; set H11_CRYSTAL_CACHE") end
print("SUMMARY crystal_daily_swarm_h11: "..pass.." pass, "..fail.." fail")
os.exit(fail==0 and 0 or 1)
