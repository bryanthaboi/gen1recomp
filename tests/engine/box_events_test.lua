package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local Events = require("src.box.Events")
local Store = require("src.box.Store")
local Catalog = require("src.box.Catalog")
local CacheFs = require("src.import.CacheFs")
local Serializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local oldRead, tables = CacheFs.readAt, {}
for _, version in ipairs({ "ruby", "sapphire", "emerald", "firered", "leafgreen" }) do
  local C = require("src.core.game3.constants").of(version)
  local items = {}
  for _, row in ipairs(Events.ROWS) do
    local id = C:id("items",row.item)
    if id then items[id] = { name=row.name,pocket="KEY_ITEMS" } end
  end
  for id=500,529 do items[id]={name="Key "..id,pocket="KEY_ITEMS"} end
  local prefix=GameVersion.cachePrefix(version)
  tables[prefix.."data/generated/gba/pokemon/names.lua"] = Serializer.encode({[25]="PIKACHU"})
  tables[prefix.."data/generated/gba/items/pack.lua"] = Serializer.encode({items=items})
end
CacheFs.readAt=function(path) return tables[path] end;Catalog.reset()
Events.autoFetch=false
local Gift=require("src.core.game3.mystery_gift")
local EON_EVENT=require("src.core.Base64").decode("AQAAAAICAAIAAAAEAIABAAAQfhYAAB4AAAKaAgACBggBAWEAAAL7AQACCwEFEwEF+wEAAgLB4wDn2dkA7ePp5gDa1ejc2eYA1egA6NzZAMHTxwDd4v7Kv867xrzPzMGt/7hhAAACRxMBAQAhDYABALsBvwAAAkoTAQEAIQ2AAQC7Ab8AAAIrzgC7Ab8AAAJqWr3JAAACZm1GEwEBACENgAAAuwHAAAACGgCAEwEaAYABAAkAKVMIvQYBAAJmbWwNvYYBAAJmbWwCvru+8AD9AasAwePj2ADo4wDn2dkA7ePpq/7O3Nnm2bTnANUA4Nno6NnmANzZ5tkA2uPmAO3j6bgA/QGt/767vvAAw+gA1eTk2dXm5wDo4wDW2QDVANrZ5ubtAM7DvcW/zrj+1unoAMO06tkA4tnq2eYA59nZ4gDj4tkA4N3f2QDd6ADW2drj5tmt+9Pj6QDn3OPp4NgA6t3n3egAxsPG073J0L8A1eLYANXn3/7V1uPp6ADd6ADo3Nnm2a3/vru+8AD9AbgA6NzZAMW/0wDDzr/HzQDKyb3Fv84A3eL+7ePp5gC8u8EA3ecA2ung4K37x+Pq2QDn4+HZAN/Z7QDd6Nnh5wDa4+YA59Xa2d/Z2eTd4tv+3eIA7ePp5gDKvbgA6NzZ4gDX4+HZAOfZ2QDh2a3/uPsBAAJHEwEBACENgAEAuwFBAgACShMBAQAhDYABALsBQQIAAivOALsBQQIAAkYTAQEAIQ2AAAC7AUkCAAK+NQAAAg4CAr5RAgACDgMCvnUCAAIOAwLO3N3nAL/Qv8jOAOHV7QDW2QDk4NXt2dgA4+Lg7QDj4tfZrf/T4+nmALy7wbTnAMW/0wDDzr/HzQDKyb3Fv84A3ecA2ung4K3/")
T.eq(Gift.eventRecordMixingItem(EON_EVENT),275,"the relay eon event hands out ITEM_EON_TICKET by record mixing")
for _,version in ipairs({"firered","leafgreen","emerald","ruby","sapphire"}) do
  T.check(not Events.receive({version=version,flags={},vars={},modData={},bag=require("src.core.game3.bag").new()},
    version=="emerald" and "aurora" or (Events.FAMILY[version]=="rs" and "eon" or "aurora"),2),
    version.." hands out no ticket before the relay feed arrives")
end
local function feedFor(version)
  local fam=Events.FAMILY[version]
  if fam=="rs" then return {cards={},news={},events={{key="rs_eon_ticket",label="EON TICKET",bytes=EON_EVENT}}} end
  local cards={}
  for _,b in ipairs(require("tests.fixtures.game3_gift_cards").cards(fam)) do cards[#cards+1]={key=b.key,card=b.card} end
  return {cards=cards,news={}}
end
for _,version in ipairs({"firered","leafgreen","emerald","ruby","sapphire"}) do Events.setFeed(version,feedFor(version)) end
T.check(not Events.allowed("oldSeaMap","emerald",2),"English Emerald cannot receive Old Sea Map")
T.check(Events.allowed("oldSeaMap","emerald",1)~=nil,"Japanese Emerald has historical Old Sea Map distribution")
T.check(not Events.allowed("aurora","emerald",1),"Japanese Emerald has no historical AuroraTicket distribution")
T.check(Events.allowed("aurora","firered",1)~=nil,"Japanese FireRed did receive AuroraTicket")
T.check(not Events.allowed("mystic","emerald",3),"French MysticTicket is not offered without historical distribution")
T.check(not Events.allowed("eon","firered",2),"FRLG does not receive Eon Ticket")
T.eq(#Events.list("gold",2),0,"Gen2 has no Gen3 ticket events")
local Items=require("src.core.game3.items_data")
Items.applyProfile("firered")
local beforeModel,beforePack,beforeCap=Items._bagModel,Items._pack,Store.copy(Items.CAPACITY)
local oldSpace=package.loaded["src.core.game3.scripting.space"]
local liveStore={flags={[500]=true},vars={[17000]=42}}
package.loaded["src.core.game3.scripting.space"]={store=liveStore}
local liveBody=Serializer.encode(liveStore)
for _, version in ipairs({"ruby","sapphire","emerald","firered","leafgreen"}) do
  for _, row in ipairs(Events.list(version,2)) do
    local original={version=version,flags={},vars={},modData={},bag=require("src.core.game3.bag").new(),storage={boxes={},items={}}}
    local save,why=Events.receive(original,row.id,2)
    T.check(save~=nil,version.." receives "..row.id..": "..tostring(why))
    if save then
      T.same(original.flags,{},"event planning leaves original flags untouched")
      if row.id~="eon" then
        T.eq(Events.status(save,row),"Ticket pending","Wonder Card is staged before item delivery")
        local collected,err=Events.collect(save,row.id,2)
        T.check(collected~=nil,version.." actual delivery collects "..row.id..": "..tostring(err))
        if collected then
          T.eq(Events.status(collected,row),"Collected","native receipt marks event collected")
          T.check(not Events.receive(collected,row.id,2),"event cannot be received twice")
          T.check(not Events.collect(collected,row.id,2),"event cannot be collected twice")
          local C=require("src.core.game3.constants").of(version)
          local flag=C:require("flags",row.id=="aurora" and "FLAG_ENABLE_SHIP_BIRTH_ISLAND" or "FLAG_ENABLE_SHIP_NAVEL_ROCK")
          T.check(collected.flags[flag] or collected.flags[tostring(flag)],"delivery enables native island travel")
          local codec=require("src.save_convert.Gen3Save").forVersion(version)
          local image=assert(codec.encode({playerName="Owner",trainerId=42,secretId=97}))
          local port=codec.toPortSave(assert(codec.decode(image)),version)
          port.map=codec.mapFor(0,0)
          port.flags,port.vars,port.bag=collected.flags,collected.vars,collected.bag
          local exported=assert(codec.exportPort(port,{version=version,template=image,
            toNational=function(n)return n end,itemId=tonumber,mapLayoutId=function()return 1 end}))
          local reimported=codec.toPortSave(assert(codec.decode(exported)),version)
          T.eq(Events.status(reimported,row),"Collected",version.." native save retains ticket receipt")
          T.check(reimported.flags[flag] or reimported.flags[tostring(flag)],version.." native save retains travel flag")
        end
      else
        T.eq(Events.status(save,row),"Collected","record mixing delivers Eon Ticket through native gift receiver")
        T.check(not Events.receive(save,row.id,2),"record mixing Eon Ticket cannot duplicate")
        local codec=require("src.save_convert.Gen3Save").forVersion(version)
        local image=assert(codec.encode({playerName="Owner",trainerId=42,secretId=97}))
        local port=codec.toPortSave(assert(codec.decode(image)),version)
        port.map,port.flags,port.vars,port.bag=codec.mapFor(0,0),save.flags,save.vars,save.bag
        local exported=assert(codec.exportPort(port,{version=version,template=image,
          toNational=function(n)return n end,itemId=tonumber,mapLayoutId=function()return 1 end}))
        local reimported=codec.toPortSave(assert(codec.decode(exported)),version)
        T.eq(Events.status(reimported,row),"Collected",version.." native save retains record mixing Eon receipt")
        local C=require("src.core.game3.constants").of(version)
        local flag=C:require("flags",version=="emerald" and "FLAG_ENABLE_SHIP_SOUTHERN_ISLAND" or "FLAG_SYS_HAS_EON_TICKET")
        T.check(reimported.flags[flag] or reimported.flags[tostring(flag)],version.." native save retains Southern Island travel flag")
      end
    end
  end
end
T.eq(Items._bagModel,beforeModel,"offline event operations restore active item profile")
T.eq(Items._pack,beforePack,"offline events restore live item pack pointer")
T.same(Items.CAPACITY,beforeCap,"offline events restore live bag capacities")
T.eq(Serializer.encode(liveStore),liveBody,"offline event delivery cannot change active game flags or variables")
package.loaded["src.core.game3.scripting.space"]=oldSpace
T.check(not Events.receive({version="emerald"},"oldSeaMap",2),"activation also rejects historical-language mismatch")
do
  local original={version="firered",flags={},vars={},modData={},bag=require("src.core.game3.bag").new()}
  local save=assert(Events.receive(original,"aurora",2))
  for i=1,30 do save.bag.pockets.KEY_ITEMS[i]={id=499+i,qty=1} end
  local body=Serializer.encode(save)
  T.check(not Events.collect(save,"aurora",2),"full Key Items pocket refuses ticket delivery")
  T.eq(Serializer.encode(save),body,"full bag does not consume receipt or mutate card")
end
for _,version in ipairs({"emerald","firered","leafgreen"}) do
  local C=require("src.core.game3.constants").of(version)
  local flag=C:require("flags",version=="emerald" and "FLAG_CAUGHT_HO_OH" or "FLAG_FOUGHT_HO_OH")
  local save={version=version,flags={[flag]=true},vars={},modData={},bag=require("src.core.game3.bag").new()}
  local row=assert(Events.allowed("mystic",version,2))
  T.eq(Events.status(save,row),"Event already completed",version.." completed encounter is visible before receiving card")
  T.check(not Events.receive(save,"mystic",2),"completed encounter cannot create undeliverable pending card")
end
Events.setFeed("firered",{cards={},news={}})
do
  local save,why=Events.receive({version="firered",flags={},vars={},modData={},bag=require("src.core.game3.bag").new()},"aurora",2)
  T.check(save==nil and tostring(why):find("not offering"),"a ticket the relay does not publish cannot be received: "..tostring(why))
end
Events.setFeed("ruby",{cards={},news={},events={}})
T.check(not Events.receive({version="ruby",flags={},vars={},modData={},bag=require("src.core.game3.bag").new()},"eon",2),
  "Ruby gets no Eon Ticket without the relay e-Reader event")
CacheFs.readAt=oldRead;Catalog.reset()
T.finish("Box events")
