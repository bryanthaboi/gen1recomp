local Store = require("src.box.Store")
local Catalog = require("src.box.Catalog")
local GameVersion = require("src.core.GameVersion")
local Serializer = require("src.core.SaveSerializer")
local Mon = require("src.battle.gen2.Mon")
local Pokemon = require("src.core.game3.pokemon")
local Unown = require("src.core.gen2.Unown")
local bit = require("bit")
local Migration = {}
local KEYS = { {"hp","hp"},{"atk","attack"},{"def","defense"},{"spe","speed"},{"spa","special"},{"spd","special"} }
local MET_GAME = { sapphire=1,ruby=2,emerald=3,firered=4,leafgreen=5 }
local function clamp(n,lo,hi) return math.max(lo,math.min(hi,math.floor(tonumber(n) or lo))) end
local function normalized(name) return tostring(name):upper():gsub("[%s_%p]","") end
local function label(value,key) return type(value)=="table" and (value.name or key) or value or key end
local function mapped(records,name)
  local want,found=normalized(name),nil
  for key,value in pairs(records) do
    if normalized(label(value,key))==want then
      if found~=nil and found~=key then return nil end
      found=key
    end
  end
  return found
end
local function nameFits(text,generation,limit)
  if type(text)~="string" or text:find("%c") then return false end
  if generation==3 then
    local codec=require("src.save_convert.Gen3Save").forVersion("emerald")
    return codec.decodeString(codec.encodeString(text,limit,0xFF),0,limit)==text
  end
  local chars=generation==1 and require("src.save_convert.data.charmap").byToken
    or require("src.save_convert.Gen2Layout").charmap
  local tokens={}
  for key,value in pairs(chars) do
    local glyph=generation==1 and key or value
    local code=generation==1 and value or key
    if type(glyph)=="string" and not glyph:find("[<>@{}]") and code~=0x50 then tokens[#tokens+1]=glyph end
  end
  table.sort(tokens,function(a,b) return #a>#b end)
  local at,count=1,0
  while at<=#text do
    local found
    for _,token in ipairs(tokens) do
      if #token>0 and text:sub(at,at+#token-1)==token then found=token;break end
    end
    if not found then return false end
    at,count=at+#found,count+1
    if count>limit then return false end
  end
  return true
end
local function gender3(ratio,pid)
  return ratio==255 and "Genderless" or ratio==0 and "Male" or ratio==254 and "Female"
    or pid%256<ratio and "Female" or "Male"
end
local function gender2(def,dvs)
  local gender=Mon.vanillaGender(def,dvs)
  return gender=="unknown" and "Genderless" or gender=="male" and "Male" or "Female"
end
local pidCache={}
local function pidFor(mon,def,national,dvs,shiny,nature)
  local tid=clamp(mon.otId,0,65535)
  local wantedGender=gender2({genderRatio=def.genderRatio},dvs)
  local letter=national==201 and Unown.letterFromDVs(dvs)-1
  local key=table.concat({tid,tostring(def.genderRatio),wantedGender,tostring(letter),tostring(shiny),nature},"|")
  local hit=pidCache[key]
  if hit~=nil then return hit or nil end
  local found=false
  for highVariant=0,31 do
    local first,step=0,1
    if not shiny then first,step=(nature-(0x4000+highVariant)*65536)%25,25 end
    for low=first,65535,step do
      local high=shiny and bit.bxor(low,tid,highVariant%8) or (0x4000+highVariant)
      local pid=high*65536+low
      if pid%25==nature and gender3(def.genderRatio,pid)==wantedGender
          and (bit.bxor(tid,high,low)<8)==shiny
          and (not letter or Pokemon.unownLetter(pid)==letter) then found=pid;break end
    end
    if found or shiny and highVariant==7 then break end
  end
  pidCache[key]=found
  return found or nil
end
local function ivsFromDvs(dvs)
  dvs=dvs or {}
  local function iv(dv) return clamp(dv,0,15)*2+1 end
  local special=iv(dvs.special)
  return {hp=iv(dvs.hp or Mon.hpDV(dvs)),atk=iv(dvs.attack),def=iv(dvs.defense),spe=iv(dvs.speed),spa=special,spd=special}
end
local function dvsFor(mon,def,national,generation)
  local iv=mon.ivs or {}
  local target={attack=math.floor((iv.atk or 0)/2),defense=math.floor((iv.def or 0)/2),
    speed=math.floor((iv.spe or 0)/2),special=math.floor(((iv.spa or 0)+(iv.spd or 0))/4)}
  local shiny=Pokemon.isShiny({personality=mon.personality,otId=mon.otId,otSecretId=mon.otSecretId})
  local source=Catalog.get(mon._boxVersion)
  local ratio=source.meta[mon.species] and source.meta[mon.species].genderRatio
  if ratio==nil then return nil,"The source gender data is missing." end
  local gender=gender3(ratio,mon.personality)
  local letter=national==201 and Pokemon.unownLetter(mon.personality)+1
  if letter and letter>26 then return nil,"Gen 2 cannot represent Unown ! or ?." end
  local best,score
  for n=0,65535 do
    local d={attack=math.floor(n/4096),defense=math.floor(n/256)%16,speed=math.floor(n/16)%16,special=n%16}
    if Mon.vanillaShiny(d)==shiny and (generation==1 or gender2(def,d)==gender)
        and (not letter or Unown.letterFromDVs(d)==letter) then
      local distance=0
      for key,value in pairs(target) do distance=distance+math.abs(d[key]-value) end
      if score==nil or distance<score then best,score=d,distance;if distance==0 then break end end
    end
  end
  if not best then return nil,"Gen 2 cannot preserve this combination of gender, shininess and form." end
  best.hp=Mon.hpDV(best)
  return best
end
local IV_KEYS={"hp","atk","def","spe","spa","spd"}
local CAUGHT={"caughtTime","caughtLevel","caughtLocation","caughtByGender","caughtData"}
local ORIGIN3={"metLocation","metLevel","metGame","pokeball","otGender","language","ribbons","championRibbon","contest"}
local function lastOrigin(entry,generation)
  local archives=type(entry.archives)=="table" and entry.archives or {}
  for i=#archives,1,-1 do
    local archive=archives[i]
    if type(archive)=="table" and archive.generation==generation and type(archive.mon)=="table" then return archive end
  end
end
local function sameDvs(a,b)
  if type(a)~="table" or type(b)~="table" then return false end
  for _,key in ipairs({"attack","defense","speed","special"}) do if a[key]~=b[key] then return false end end
  return true
end
local function sameIvs(a,b)
  if type(a)~="table" or type(b)~="table" then return false end
  for _,key in ipairs(IV_KEYS) do if a[key]~=b[key] then return false end end
  return true
end
local function statExpFromEffort(evs)
  local out={}
  for _,pair in ipairs(KEYS) do
    local effort=math.floor(clamp((evs or {})[pair[1]],0,255)/4)*4
    out[pair[2]]=math.max(out[pair[2]] or 0,effort^2)
  end
  return out
end
local function statExpOf(statExp,key)
  statExp=type(statExp)=="table" and statExp or {}
  local value=statExp[key]
  if value==nil and key=="special" then value=statExp.specialAttack end
  return clamp(value,0,65535)
end
local function effortFromStatExp(statExp,key)
  return math.min(255,math.ceil(math.sqrt(statExpOf(statExp,key))))
end
local function expAt(data,species,level)
  if data.generation==3 then
    return require("src.core.game3.summary_data").expForLevel(data.meta[species].growthRate,level)
  end
  return require("src.pokemon.Growth").expForLevel(data.pokemon[species].growthRate,level)
end
function Migration.convert(entry,version,opts)
  local from,to=Catalog.get(entry.version),Catalog.get(version)
  local g1,g2=entry.generation,GameVersion.generation(version)
  if not g2 or g1==g2 then return nil,"Choose a different generation; same-generation Pokémon can be withdrawn directly." end
  if not from.ready or not to.ready then return nil,"Import both games' ROMs before converting." end
  local mon=entry.mon
  if mon.isBadEgg then return nil,"A Bad Egg cannot be migrated." end
  if mon.isEgg and g2==1 then return nil,"Gen 1 cannot represent eggs." end
  if mon.mail~=nil and mon.mail~=255 then return nil,"Remove held mail before converting." end
  local d=Catalog.describe(entry.version,mon)
  if type(mon.otId)~="number" or mon.otId%1~=0 or mon.otId<0 or mon.otId>65535 then return nil,"The original trainer ID is missing or invalid." end
  if d.level<1 or d.level>100 or d.level%1~=0 then return nil,"The source level is invalid." end
  if g1==3 and (not from.meta[mon.species] or from.meta[mon.species].growthRate==nil) then return nil,"Import complete source species data first." end
  local national=d.national
  local species=g2==3 and (to.national.toSpecies or {})[national] or to.byNational[national]
  if not species then return nil,"The destination cannot represent this species." end
  local def=g2==3 and to.meta[species] or to.pokemon[species]
  if not def or def.growthRate==nil or g2==3 and (not to.stats[species] or def.genderRatio==nil)
      or g2<3 and not def.baseStats then return nil,"Import complete destination species data first." end
  local nickname=mon.nickname or d.species
  if g2<3 and normalized(nickname)==normalized(d.species) then nickname=nil end
  local ot=mon.otName or mon.ot or ""
  if nickname~=nil and not nameFits(nickname,g2,10) or not nameFits(ot,g2,7) then
    return nil,"The destination cannot represent this nickname or trainer name without changing it."
  end
  local item=mon.heldItem or mon.item
  local targetItem
  if item and item~=0 then
    if g2==1 and g1==3 then return nil,"Gen 1 cannot represent held items. Remove this item in its game first." end
    if not from.items[item] then return nil,"The held item is unknown in the source game." end
    if g2~=1 then
      targetItem=mapped(to.items,label(from.items[item],item))
      if not targetItem then return nil,"The destination cannot represent this held item." end
    end
  end
  local moves,pps,ups,missing={},{},{},{}
  local override=opts and opts.moves
  if override~=nil then
    if type(override)~="table" or #override==0 then return nil,"The replacement moveset is empty." end
    local seen={}
    for _,id in ipairs(override) do
      local row=g2==3 and to.battleMoves[id] or g2<3 and to.moves[id]
      if seen[id] or not row or not row.pp then return nil,"The replacement moveset does not fit the destination." end
      seen[id]=true
      moves[#moves+1]=g2==3 and id or {id=id,pp=row.pp,ppUps=0,maxPp=row.pp}
      pps[#pps+1],ups[#ups+1]=row.pp,0
    end
  else
    for _,move in ipairs(mon.moves or {}) do
      local key=type(move)=="table" and (move.moveId or move.id or move.move or move.name) or move
      if key and key~=0 then
        if not from.moves[key] then return nil,"A move is unknown in the source game." end
        local id=mapped(to.moves,label(from.moves[key],key))
        local row=id and (g2==3 and to.battleMoves[id] or to.moves[id])
        if not row or not row.pp then
          missing[#missing+1]=tostring(label(from.moves[key],key))
        else
          local detail=d.moveDetails[#pps+#missing+1]
          local bonus=detail and detail.ppUps or 0
          local max=row.pp+bonus*(g2==3 and math.floor(row.pp/5) or math.min(7,math.floor(row.pp/5)))
          local pp=clamp(detail and detail.pp or max,0,max)
          moves[#moves+1]=g2==3 and id or {id=id,pp=pp,ppUps=bonus,maxPp=max}
          pps[#pps+1],ups[#ups+1]=pp,bonus
        end
      end
    end
  end
  if #moves+#missing>4 then return nil,"The destination can represent at most four moves." end
  local out={species=species,nickname=nickname,ot=ot,otName=ot,otId=clamp(mon.otId,0,65535),
    level=clamp(d.level,1,100),moves=moves,isEgg=mon.isEgg or nil,item=targetItem,traded=mon.traded,
    pokerus=g2>=2 and clamp(mon.pokerus,0,255) or nil}
  local lines={"Original native record will be archived. Restore replaces this converted record; it does not create a duplicate."}
  local function note(value) lines[#lines+1]=value end
  lines.facts={}
  local function fact(name,value,tone) lines.facts[#lines.facts+1]={label=name,value=tostring(value),tone=tone} end
  if g1<3 then
    if type(mon.dvs)~="table" then return nil,"The source DVs are missing." end
    for _,key in ipairs({"attack","defense","speed","special"}) do
      if type(mon.dvs[key])~="number" or mon.dvs[key]%1~=0 or mon.dvs[key]<0 or mon.dvs[key]>15 then return nil,"The source DVs are invalid." end
    end
  elseif type(mon.personality)~="number" or type(mon.ivs)~="table" then return nil,"The native personality or IVs are missing." end
  if g2==3 then
    local home=lastOrigin(entry,3)
    local hm=home and home.mon
    local shiny=Mon.vanillaShiny(mon.dvs)
    local pid,nature,sourceExp
    if hm and type(hm.personality)=="number" and hm.otId==out.otId then
      local p,wanted=hm.personality,gender2({genderRatio=def.genderRatio},mon.dvs)
      if gender3(def.genderRatio,p)==wanted
          and Pokemon.isShiny({personality=p,otId=out.otId,otSecretId=hm.otSecretId or 0})==shiny
          and (national~=201 or Pokemon.unownLetter(p)+1==Unown.letterFromDVs(mon.dvs)) then
        pid,nature=p,p%25
      end
    end
    if pid then
      out.personality,out.otSecretId,out.nature=pid,hm.otSecretId or 0,nature
    else
      sourceExp=math.floor(tonumber(mon.exp or mon.experience) or expAt(from,mon.species,d.level))
      nature=sourceExp%25
      pid=pidFor(mon,def,national,mon.dvs,shiny,nature)
      if not pid then return nil,"No personality can preserve this Pokémon's gender, shininess and form." end
      out.personality,out.otSecretId,out.nature=pid,0,nature
    end
    local restoredIvs
    if hm and type(hm.ivs)=="table" then
      local input=Store.copy(hm);input._boxVersion=home.version
      if sameDvs(dvsFor(input,from.pokemon[mon.species],national,g1),mon.dvs) then restoredIvs=Store.copy(hm.ivs) end
    end
    out.ivs=restoredIvs or ivsFromDvs(mon.dvs)
    out.evs={}
    local forward=hm and statExpFromEffort(hm.evs)
    for _,pair in ipairs(KEYS) do
      local key,old=pair[1],hm and type(hm.evs)=="table" and clamp(hm.evs[pair[1]],0,255) or nil
      if old==nil then out.evs[key]=0
      elseif statExpOf(mon.statExp,pair[2])==forward[pair[2]] then out.evs[key]=old
      else out.evs[key]=math.max(old,effortFromStatExp(mon.statExp,pair[2])) end
    end
    local total=0;for _,key in ipairs(IV_KEYS) do total=total+out.evs[key] end
    if total>510 then for _,key in ipairs(IV_KEYS) do out.evs[key]=math.floor(out.evs[key]*510/total) end end
    out.friendship=mon.isEgg and clamp(mon.happiness or mon.eggCycles,0,255) or clamp(mon.happiness or 70,0,255)
    out.eggCycles=mon.isEgg and out.friendship or nil
    out.heldItem,out.pp=targetItem or 0,pps
    out.ppBonusesPacked=0;for i,value in ipairs(ups) do out.ppBonusesPacked=out.ppBonusesPacked+value*4^(i-1) end
    out.markings=entry.markings or 0
    local pair=to.abilities and to.abilities[species] or {}
    out.abilityNum=(pair[2] or 0)~=0 and 1 or 0
    if hm and (hm.abilityNum==0 or hm.abilityNum==1 and (pair[2] or 0)~=0) then out.abilityNum=hm.abilityNum end
    out.language,out.otGender=2,Mon.caughtGenderOf(mon.caughtByGender)=="girl" and 1 or 0
    -- include/constants/region_map_sections.h:229
    out.metLocation,out.metLevel,out.metGame,out.pokeball=255,out.level,MET_GAME[version],4
    out.modernFatefulEncounter=false
    if hm then
      for _,key in ipairs(ORIGIN3) do if hm[key]~=nil then out[key]=Store.copy(hm[key]) end end
      out.modernFatefulEncounter=hm.modernFatefulEncounter==true
    end
    -- src/battle_util.c:3898
    out.modernFatefulEncounter=out.modernFatefulEncounter or national==151
    local ability=pair[out.abilityNum+1] or pair[1]
    local NATURES=require("src.box.Metadata").NATURES
    local up,down=math.floor(nature/5)+1,nature%5+1
    local short={"Atk","Def","Spe","SpA","SpD"}
    local abilityName=ability and to.abilityNames and label(to.abilityNames[ability],ability)
    lines.ivs=Store.copy(out.ivs)
    if sourceExp then
      note("Nature from EXP: "..sourceExp.." % 25 = "..nature..", "..NATURES[nature+1]..".")
      lines.natureExp=sourceExp
    else
      note("Personality, nature and Secret ID restored from the original Gen 3 record.")
    end
    fact("Nature",NATURES[nature+1]..(up~=down and " +"..short[up].." -"..short[down] or ""),sourceExp and "new" or "kept")
    fact("Ability",abilityName or "First slot",hm and "kept" or "new")
    fact("EVs",hm and "Restored" or "Reset to 0",hm and "kept" or "lost")
    fact("Ball",hm and "Original" or "Poké Ball",hm and "kept" or "new")
    fact("Shiny",shiny and "Yes" or "No","kept")
    if out.modernFatefulEncounter and national==151 then fact("Mew","Obeys in battle",hm and "kept" or "new") end
    if restoredIvs then note("IVs restored from the original Gen 3 record.")
    else note("IVs: each DV doubled plus 1; Special fills both Sp. Atk and Sp. Def.") end
    note(hm and "EVs restored from the original Gen 3 record; Stat Exp gained since raises them." or "EVs reset to 0.")
    note("Ability: "..tostring(abilityName or "first slot")..(out.abilityNum==1 and " (second slot)." or "."))
    note("DV shininess, gender and Unown letter are preserved."..(hm and "" or " Secret ID 0."))
    if hm then note("Origin: met data, ball, ribbons and contest stats restored from the original Gen 3 record.")
    else
      note("Origin: Poké Ball, met level "..out.level..", fateful encounter location."
        ..(out.modernFatefulEncounter and " Fateful encounter flag set, so Mew obeys." or ""))
    end
  elseif g1==3 then
    local home=lastOrigin(entry,g2)
    local hm=home and home.mon
    local dvs,why
    if hm and type(hm.dvs)=="table" then
      local was=Catalog.describe(home.version,hm)
      if was and was.national and sameIvs(ivsFromDvs(hm.dvs),mon.ivs) then
        dvs={attack=hm.dvs.attack,defense=hm.dvs.defense,speed=hm.dvs.speed,special=hm.dvs.special}
        dvs.hp=Mon.hpDV(dvs)
      end
    end
    local restored=dvs~=nil
    if not dvs then
      local input=Store.copy(mon);input._boxVersion=entry.version
      dvs,why=dvsFor(input,def,national,g2)
      if not dvs then return nil,why end
    end
    out.dvs,out.statExp=dvs,statExpFromEffort(mon.evs)
    if hm then
      for _,pair in ipairs(KEYS) do
        out.statExp[pair[2]]=math.max(out.statExp[pair[2]],statExpOf(hm.statExp,pair[2]))
      end
    end
    out.happiness=g2==2 and clamp(mon.friendship or mon.happiness or 70,0,255) or nil
    if g2==2 then
      local met=tonumber(mon.metLevel) or 0
      out.caughtTime,out.caughtLocation=0,0
      out.caughtLevel=math.min(63,met>=1 and math.floor(met) or out.level)
      out.caughtByGender=mon.otGender==1 and "girl" or "boy"
      if hm then for _,key in ipairs(CAUGHT) do if hm[key]~=nil then out[key]=Store.copy(hm[key]) end end end
    end
    if restored then
      note("DVs restored from the original Gen "..g2.." record.")
    else
      note("IVs → nearest DVs preserving shininess"..(g2==2 and ", gender and Unown letter." or " as a latent DV pattern."))
    end
    note(("DVs: Attack %d · Defense %d · Speed %d · Special %d · HP %d"):format(dvs.attack,dvs.defense,dvs.speed,dvs.special,dvs.hp))
    note("EVs → Stat Exp; Special uses the greater Special Attack/Defense effort. HP DV is derived."
      ..(hm and " The original Stat Exp is kept where it is higher." or ""))
    if g2==2 then note(hm and "Caught data restored from the original Gen 2 record." or "Caught level and trainer gender come from the Gen 3 met data.") end
    note("Nature, ability, Secret ID, ball, ribbons, contests and Gen 3 origin data remain only in the archive.")
    lines.dvs={hp=dvs.hp,atk=dvs.attack,def=dvs.defense,spe=dvs.speed,spc=dvs.special}
    fact("DVs",restored and "Restored" or "From IVs",restored and "kept" or "new")
    fact("Stat Exp",hm and "Restored" or "From EVs",hm and "kept" or "new")
    fact("Archived","Nature, ability, ball, ribbons","lost")
  else
    local prepared=Store.copy(mon);prepared.species=mon.species
    local Convert=require("src.online.Convert")
    local native,why=(g2==2 and Convert.toGen2 or Convert.toGen1)(prepared,from,to)
    if not native then return nil,"Time Capsule conversion refused: "..tostring(why) end
    out.dvs,out.statExp=Store.copy(native.dvs),Store.copy(native.statExp)
    out.happiness=g2==2 and 70 or nil
    out.caughtLevel=g2==2 and out.level or nil
    note("DVs and Stat Exp are preserved; stats are recalculated using the destination's base stats.")
    fact("DVs","Kept","kept")
    if g2==2 then
      out.item=native.item
      note("Friendship starts at 70; caught level is the current level.")
      local rate=mon.catchRate or (from.pokemon[mon.species] or {}).catchRate or 0
      note(native.item and ("Holds "..label(to.items[native.item],native.item).." from catch rate "..rate..".")
        or "Catch rate "..rate.." gives no held item.")
      fact("Held item",native.item and label(to.items[native.item],native.item) or "None",native.item and "new" or nil)
      fact("Friendship","70","new")
    else
      out.catchRate=native.catchRate
      if item and item~=0 then
        note("Held "..label(from.items[item],item).." kept as catch rate "..native.catchRate..". It returns as the held item in Gen 2.")
        fact("Held item",label(from.items[item],item).." (kept for Gen 2)","kept")
      end
      fact("Archived","Friendship, Pokérus, met data","lost")
    end
  end
  local oldExp=tonumber(mon.exp or mon.experience)
  local oldBase=expAt(from,mon.species,out.level)
  local newBase=expAt(to,species,out.level)
  local experience=newBase
  if oldExp and out.level<100 then
    local oldNext,newNext=expAt(from,mon.species,out.level+1),expAt(to,species,out.level+1)
    local fraction=math.max(0,math.min(1,(oldExp-oldBase)/math.max(1,oldNext-oldBase)))
    experience=newBase+math.floor(fraction*(newNext-newBase))
  end
  if g2==2 then out.experience=experience else out.exp=experience end
  note("Level "..out.level.." retained; experience "..tostring(oldExp or "unrecorded").." → "..experience.." (same progress within the level).")
  local statuses={SLP="sleep",PSN="poison",BRN="burn",PAR="paralyze",FRZ="freeze"}
  local reverse={sleep="SLP",poison="PSN",toxic="PSN",burn="BRN",paralyze="PAR",freeze="FRZ"}
  out.status=g2==2 and (statuses[mon.status] or mon.status) or (reverse[mon.status] or mon.status)
  out.sleep=mon.sleep or mon.sleepTurns
  if g2==2 then
    out.gender=Mon.vanillaGender(def,out.dvs);out.shiny=Mon.vanillaShiny(out.dvs)
    if national==201 then out.unownLetter=Unown.letterFromDVs(out.dvs) end
  elseif g2==1 and out.catchRate==nil then out.catchRate=def.catchRate end
  local display=Catalog.describe(version,out)
  out.stats=g2<3 and Store.copy(display.stats) or nil
  out.maxHp,out.hp=display.hp,display.hp
  if g2==3 then for _,key in ipairs({"attack","defense","speed","spAtk","spDef"}) do out[key]=display[key] end end
  note("Stats recalculated; boxed HP restored to full. Status: "..tostring(mon.status or "healthy").." → "..tostring(out.status or "healthy")..".")
  fact("Level",out.level,"kept")
  fact("EXP",oldExp and math.floor(oldExp)~=experience and (math.floor(oldExp).." → "..experience) or experience,oldExp and math.floor(oldExp)~=experience and "new" or "kept")
  if targetItem and g2>1 and g1==3 or targetItem and g1==2 and g2==3 then fact("Held item",label(to.items[targetItem],targetItem),"kept") end
  fact("HP","Restored to full","new")
  if #missing>0 then
    return nil,"The destination cannot represent move "..missing[1]..".",{moveBlock=true,missing=missing,
      species=tostring(g2==3 and to.names and to.names[species] or def.name or species)}
  end
  if override then
    local names={}
    for _,id in ipairs(override) do names[#names+1]=tostring(label(to.moves[id],id)) end
    fact("Moves",table.concat(names,", "),"new")
    note("Moves replaced with the recommended set at full PP, no PP Ups. Held item mapped by exact name.")
  else
    note("Moves and held item mapped by exact name; current PP is capped to destination maximum, PP Ups retained.")
  end
  if g2==1 then note("Friendship, Pokérus, gender and met data remain only in the archive.") end
  return out,lines
end
function Migration.natureSteps(exp)
  local NATURES=require("src.box.Metadata").NATURES
  local rows={}
  for n=0,24 do rows[#rows+1]={nature=NATURES[n+1],add=(n-math.floor(exp))%25} end
  table.sort(rows,function(a,b) return a.add<b.add end)
  return rows
end
function Migration.preview(state,refs,version,opts)
  local preview={revision=state.revision,destination=version,rows={},allowed=true}
  local seen,overrides={},opts and opts.moves or {}
  if type(refs)~="table" or #refs==0 then return nil,"Select warehouse Pokémon to preview." end
  for _,ref in ipairs(refs) do
    local entry=Store.at(state,ref.box,ref.slot)
    if not entry or seen[entry.id] then return nil,"A selected Pokémon is missing or repeated." end
    seen[entry.id]=true
    local override=overrides[entry.id]
    local converted,lines,info=Migration.convert(entry,version,{moves=override})
    local row={id=entry.id,name=entry.display.name,original=Serializer.encode(entry),
      converted=converted,lines=converted and lines or {lines}}
    if converted and override then
      preview.moves=preview.moves or {};preview.moves[entry.id]=Store.copy(override);row.recommended=true
    end
    if not converted and type(info)=="table" and info.moveBlock then
      row.moveBlock,row.missing,row.species=true,info.missing,info.species
    end
    preview.rows[#preview.rows+1]=row
    if not converted then preview.allowed=false end
  end
  return preview
end
function Migration.moveBlocked(preview)
  local rows={}
  for _,row in ipairs(type(preview)=="table" and preview.rows or {}) do if row.moveBlock then rows[#rows+1]=row end end
  return rows
end
function Migration.recommendedMoves(preview,job,version)
  local Recommend=require("src.recommend.Recommend")
  local moves,failed={},{}
  for _,row in ipairs(Migration.moveBlocked(preview)) do
    local hit=Recommend.get(job,row.species)
    local keys=hit and Recommend.resolveMoves(hit,version) or {}
    if #keys>0 then
      moves[row.id]={}
      for i=1,math.min(4,#keys) do moves[row.id][i]=keys[i] end
    else failed[#failed+1]=row.name end
  end
  return moves,failed
end
function Migration.apply(state,refs,version,preview,opts)
  if type(preview)~="table" or preview.revision~=state.revision or preview.destination~=version then
    return nil,"Storage changed. Preview the migration again."
  end
  local fresh,why=Migration.preview(state,refs,version,{moves=opts and opts.moves or preview.moves})
  if not fresh then return nil,why end
  if not fresh.allowed then return nil,"The destination cannot represent every selected Pokémon." end
  if Serializer.encode(preview)~=Serializer.encode(fresh) then return nil,"The preview changed. Review it again." end
  local nextState=Store.copy(state)
  for i,ref in ipairs(refs) do
    local entry=Store.at(nextState,ref.box,ref.slot)
    local snapshot=Store.copy(entry);snapshot.archives=nil
    entry.archives=entry.archives or {};entry.archives[#entry.archives+1]=snapshot
    entry.version,entry.generation,entry.mon=version,GameVersion.generation(version),fresh.rows[i].converted
    entry.display=Catalog.describe(version,entry.mon)
    entry.gciRaw,entry.gciOriginal=nil,nil
  end
  nextState.revision=state.revision+1
  return nextState
end
function Migration.restore(state,ref,index)
  local entry=Store.at(state,ref.box,ref.slot)
  local original=entry and entry.archives and entry.archives[index]
  if not original then return nil,"Choose an archived original that is still in Box." end
  local nextState=Store.copy(state)
  local archives=Store.copy(entry.archives);table.remove(archives,index)
  local current=Store.copy(entry);current.archives=nil;archives[#archives+1]=current
  local restored=Store.copy(original);restored.archives=archives
  restored.display=Catalog.describe(restored.version,restored.mon)
  nextState.boxes[ref.box].mons[ref.slot]=restored
  nextState.revision=state.revision+1
  return nextState
end
return Migration
