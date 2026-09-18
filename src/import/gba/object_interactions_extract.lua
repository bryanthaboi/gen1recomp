-- Global interactions are code-referenced roots, absent from MapEvents BFS.
-- Read the original script bytecode/text and metatile attributes from the ROM.
local E={PATH='data/generated/gba/objects/pack.lua'}
local I=require('src.core.game3.scripting.interaction_scripts')
local Opcodes=require('src.core.game3.scripting.opcodes')
local function flavorBase(rom)
  for off=0x1A7000,0x1A8000 do
    local match=true
    for n=0,27 do
      local p=off+n*9
      if rom:get(p)~=0x0F or rom:get(p+1)~=0 or rom:get(p+6)~=9
          or rom:get(p+7)~=3 or rom:get(p+8)~=2 then match=false;break end
    end
    if match then
      local text=rom:ptrOffset(rom:u32(off+2))
      -- "It's" at the start of Text_Bookshelf (Latin BPRE).
      if text and rom:get(text)==0xC3 and rom:get(text+1)==0xE8
          and rom:get(text+2)==0xB4 and rom:get(text+3)==0xE7 then return off end
    end
  end
  error('Original object interaction scripts not found in this FireRed ROM')
end
function E.readScripts(rom)
  local base=flavorBase(rom);local seeds,aliases={},{}
  for n,row in ipairs(I.FLAVOR) do
    local ptr=0x08000000+base+(n-1)*9
    seeds[#seeds+1]=ptr;aliases['EventScript_'..row[2]]=Opcodes.key(ptr)
  end
  -- GetInteractedMetatileScript's preceding literal is WallTownMap.
  local wall
  for off=0x6D000,0x6D900,4 do
    if rom:u32(off)==base+0x08000000 and rom:u32(off+24)==base+9+0x08000000 then
      wall=rom:u32(off-24);break
    end
  end
  assert(wall and rom:ptrOffset(wall),'Wall Town Map script reference not found')
  seeds[#seeds+1]=wall;aliases.EventScript_WallTownMap=Opcodes.key(wall)
  local pack=require('src.import.gba.extract_scripts').bfsFromSeeds(rom,seeds)
  for alias,key in pairs(aliases) do pack.scripts[alias]=assert(pack.scripts[key]) end
  return {version=1,scripts=pack.scripts,text=pack.text,movements=pack.movements}
end
function E.read(rom,version)
  local pack=E.readScripts(rom)
  local V=require('src.import.gba.versions')
  local Catalog=require('src.import.gba.map_catalog')
  local census=assert(require('src.import.gba.map_tree').walk(rom,version))
  local order,entries=Catalog.allOrder(census)
  Catalog.registerOrder(rom,version,order,entries)
  pack.behaviors={}
  local attrs={}
  local function attributes(name)
    if attrs[name] then return attrs[name] end
    local spec=assert((version.tilesets or V.TILESETS)[name])
    local out={}
    for i=0,math.floor(spec.attr_bytes/4)-1 do out[i]=rom:u32(spec.attributes+i*4)%512 end
    attrs[name]=out;return out
  end
  for name,pair in pairs(version.tileset_pairs or V.TILESET_PAIRS) do
    local out={};pack.behaviors[name]=out
    for mid,beh in pairs(attributes(pair.primary)) do out[mid]=beh end
    for mid,beh in pairs(attributes(pair.secondary)) do out[mid+640]=beh end
  end
  return pack
end
local function serialize(value)
  if type(value)=='string' then return string.format('%q',value) end
  if type(value)~='table' then return tostring(value) end
  local keys={};for k in pairs(value) do keys[#keys+1]=k end
  table.sort(keys,function(a,b)return tostring(a)<tostring(b) end)
  local out={'{'}
  for _,k in ipairs(keys) do out[#out+1]='['..serialize(k)..']='..serialize(value[k])..',' end
  out[#out+1]='}';return table.concat(out)
end
function E.writeExtract(rom,cache,root,version)
  local pack=E.read(rom,version)
  local path=(root or 'data/generated/gba')..'/objects/pack.lua'
  assert(cache:write(path,'return '..serialize(pack)..'\n'))
  return pack
end
return E
