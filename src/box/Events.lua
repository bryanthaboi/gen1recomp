local Store = require("src.box.Store")
local Context = require("src.box.GameContext")
local Events = {}
local WESTERN = { [2]=true,[3]=true,[4]=true,[5]=true,[7]=true }
local ALL = { [1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[7]=true }
Events.ROWS = {
  { id="eon",name="Eon Ticket",item="ITEM_EON_TICKET",versions={ruby=ALL,sapphire=ALL,emerald=ALL},
    card="rse_eon_ticket",route="Southern Island",method="Record mixing" },
  { id="aurora",name="AuroraTicket",item="ITEM_AURORA_TICKET",versions={firered=ALL,leafgreen=ALL,emerald=WESTERN},
    card="aurora_ticket",rseCard="rse_aurora_ticket",route="Birth Island",method="Wonder Card" },
  { id="mystic",name="MysticTicket",item="ITEM_MYSTIC_TICKET",
    versions={firered={[1]=true,[2]=true},leafgreen={[1]=true,[2]=true},emerald={[1]=true,[2]=true}},
    card="mystic_ticket",rseCard="rse_mystic_ticket",route="Navel Rock",method="Wonder Card" },
  { id="oldSeaMap",name="Old Sea Map",item="ITEM_OLD_SEA_MAP",versions={emerald={[1]=true}},
    card="rse_old_sea_map",route="Faraway Island",method="Wonder Card" },
}
Events.FAMILY={firered="frlg",leafgreen="frlg",emerald="rse",ruby="rs",sapphire="rs"}
Events._feeds,Events._jobs={},{}
function Events.setFeed(version,list) Events._feeds[version]=list end
function Events.poll(version,opts)
  local family=Events.FAMILY[version]
  if not family then return "error","no_family" end
  if Events._feeds[version] then return "ok",Events._feeds[version] end
  local Gift=require("src.core.game3.mystery_gift")
  local job=Events._jobs[version]
  if not job then
    opts=opts or {}
    job=Gift.fetchOnline({family=family,version=version,transport=opts.transport,client=opts.client})
    Events._jobs[version]=job
  end
  local status,result=Gift.pollOnline(job)
  if status=="pending" then return status end
  Events._jobs[version]=nil
  if status=="ok" then Events._feeds[version]=result end
  return status,result
end
local function relayOffer(save,row)
  local status,list=Events.poll(save.version)
  if status=="pending" then return nil,"Checking the relay for tickets. Try again in a moment." end
  if status~="ok" then return nil,"The relay could not be reached, so no tickets can be received." end
  local Gift=require("src.core.game3.mystery_gift")
  local item=require("src.core.game3.constants").of(save.version):require("items",row.item)
  if Events.FAMILY[save.version]=="rs" then
    for _,ev in ipairs(list.events or {}) do
      if Gift.eventRecordMixingItem(ev.bytes)==item then return ev end
    end
  else
    for _,entry in ipairs(list.cards or {}) do
      if entry.card.gift and entry.card.gift.kind=="item" and entry.card.gift.item==item then return entry end
    end
  end
  return nil,"The relay is not offering this ticket right now."
end
Events.relayOffer=relayOffer
function Events.allowed(id,version,language)
  for _,row in ipairs(Events.ROWS) do
    if row.id==id then return row.versions[version] and row.versions[version][language] and row or nil end
  end
end
function Events.list(version,language)
  local out={}
  for _,row in ipairs(Events.ROWS) do if Events.allowed(row.id,version,language) then out[#out+1]=row end end
  if #out>0 and Events.autoFetch~=false then pcall(Events.poll,version) end
  return out
end
local function session(save)
  local store={version=save.version,flags={},vars={}}
  for id,on in pairs(save.flags or {}) do store.flags[tonumber(id) or id]=on end
  for id,value in pairs(save.vars or {}) do store.vars[tonumber(id) or id]=value end
  return {version=save.version,store=store,bag=save.bag,storage=save.storage,modData=save.modData or {}}
end
local function apply(s,save)
  local snap=require("src.core.game3.scripting.flags").serialize(s.store)
  save.flags,save.vars,save.bag,save.storage,save.modData=snap.flags,snap.vars,s.bag,s.storage,s.modData
end
function Events.status(save,row)
  return Context.withItems(save.version,function()
    local Gift=require("src.core.game3.mystery_gift")
    local s=session(Store.copy(save))
    local item=require("src.core.game3.constants").of(save.version):require("items",row.item)
    if require("src.core.game3.bag").has(s.bag or {pockets={}},item,1) then return "Collected" end
    local received=row.id=="eon" and (save.version=="ruby" or save.version=="sapphire") and "FLAG_SYS_HAS_EON_TICKET"
      or row.id=="eon" and "FLAG_ENABLE_SHIP_SOUTHERN_ISLAND"
      or row.id=="aurora" and "FLAG_RECEIVED_AURORA_TICKET"
      or row.id=="mystic" and "FLAG_RECEIVED_MYSTIC_TICKET" or "FLAG_RECEIVED_OLD_SEA_MAP"
    if Gift.getFlag(s,require("src.core.game3.constants").of(save.version):require("flags",received)) then return "Collected" end
    if row.id=="eon" then return "Available" end
    local family=save.version=="emerald" and "rse" or "frlg"
    local key=family=="rse" and (row.rseCard or row.card) or row.card
    for _,flag in ipairs(assert(Gift.cardHaveFlags(family)[key],key)) do
      if Gift.getFlag(s,flag) then return "Event already completed" end
    end
    local card=Gift.getSavedCard(s)
    if card and card.gift and card.gift.item==item then return "Ticket pending" end
    return "Available"
  end)
end
function Events.receive(save,id,language)
  local row=Events.allowed(id,save.version,language)
  if not row then return nil,"This event was not historically distributed for this game and language." end
  local status,why=Events.status(save,row)
  if not status then return nil,why end
  if status~="Available" then return nil,"This event has already been received." end
  return Context.withItems(save.version,function()
    local offer,offerWhy=relayOffer(save,row)
    if not offer then return nil,offerWhy end
    local out=Store.copy(save)
    local s=session(out)
    local C=require("src.core.game3.constants").of(save.version)
    local item=C:require("items",row.item)
    if id=="eon" then
      local leader={name="Box Events",giftItem=item}
      local result
      if save.version=="ruby" or save.version=="sapphire" then
        result=require("src.core.game3.link.rs_record_mix").receiveGift(s,leader,2)
      else result=require("src.core.game3.rse.record_mixing_gift").mixImport({leader,{}},s,2) end
      if not result or result.item~=item then return nil,"Make room in the Key Items pocket before receiving the Eon Ticket." end
    else
      local Gift=require("src.core.game3.mystery_gift")
      local existing=Gift.getSavedCard(s)
      if existing then
        local flag=Gift.receivedGiftFlag(existing.flagId,s)
        if flag and not Gift.getFlag(s,flag) then return nil,"Collect your existing Wonder Card gift before receiving another card." end
      end
      if not Gift.receiveCard(s,offer.card) then return nil,"The game's ticket delivery card could not be prepared." end
    end
    apply(s,out);return out
  end)
end
function Events.collect(save,id,language)
  local row=Events.allowed(id,save.version,language)
  if not row or id=="eon" then return nil,"Choose a pending ticket card." end
  return Context.withItems(save.version,function()
    local Gift=require("src.core.game3.mystery_gift")
    local out=Store.copy(save);local s=session(out)
    local card=Gift.getSavedCard(s)
    local item=require("src.core.game3.constants").of(save.version):require("items",row.item)
    if not card or not card.gift or card.gift.item~=item then return nil,"Receive this ticket's card first." end
    local result=Gift.deliverGift(s,card)
    if result~=Gift.DELIVER_GIVEN then
      return nil,result==Gift.DELIVER_NO_ROOM and "The Key Items pocket is full." or "This ticket has already been collected."
    end
    Gift.claimCard(s,card);apply(s,out);return out
  end)
end
return Events
